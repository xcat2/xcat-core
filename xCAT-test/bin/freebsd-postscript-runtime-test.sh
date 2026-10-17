#!/bin/sh

# The mount recorder stops preparation after its real runtime validation.
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
LC_ALL=C
export PATH LC_ALL
umask 077
[ "$#" -ge 2 ] && [ "$#" -le 4 ]
workspace=$1
source=$2
native_pkgbase=${3:-/usr/libexec/bsdinstall/pkgbase}
timer=${4:-/usr/local/libexec/xcat-postscript-time}
[ "$(id -u):$(freebsd-version -u)" = 0:15.1-RELEASE ]
[ ! -e "$workspace" ] && [ ! -L "$workspace" ]
mkdir -m 0700 "$workspace"
skeleton=$workspace/skeleton
mkdir -p "$skeleton/dev" "$skeleton/fixture" "$skeleton/xcat"
: > "$skeleton/dev/null"
for path in /usr/libexec/flua /bin/sh /bin/cat /bin/chmod /bin/df /bin/mkdir /bin/timeout \
    /sbin/sha256 /sbin/sysctl /sbin/mdconfig /sbin/glabel /usr/bin/env /usr/bin/fetch \
    /usr/bin/fsync /usr/bin/stat /usr/local/sbin/pkg-static /usr/local/libexec/freebsd-pkg-resolve; do
    printf '%s\n' "$path" >> "$workspace/paths"
    case "$path" in */pkg-static|*/freebsd-pkg-resolve) ;;
        *) ldd "$path" >> "$workspace/ldd" ;;
    esac
done
ldd "$timer" >> "$workspace/ldd" 2>&1 || :
printf '%s\n' /libexec/ld-elf.so.1 >> "$workspace/paths"
awk '$2 == "=>" && $3 ~ /^\// {print $3}' "$workspace/ldd" >> "$workspace/paths"
! grep -q 'not found' "$workspace/ldd"
sort -u "$workspace/paths" > "$workspace/native-files"
while IFS= read -r path; do
    mkdir -p "$skeleton$(dirname "$path")"
    cp -p "$path" "$skeleton$path"
done < "$workspace/native-files"
mkdir -p "$skeleton/usr/libexec/bsdinstall" "$skeleton/usr/local/libexec"
install -m 0555 "$timer" "$skeleton/usr/local/libexec/xcat-postscript-time"
sh "$source/patch-bsdinstall-pkgbase.sh" "$native_pkgbase" > "$skeleton/usr/libexec/bsdinstall/pkgbase"
for name in xcat-install-lib.sh xcat-package-plan.lua xcat-pkgbase.lua xcat-postscript xcat-postscript-packages xcat-postboot; do
    install -m 0444 "$source/$name" "$skeleton/usr/local/libexec/$name"
done
install -m 0555 "$source/xcat-install" "$skeleton/usr/local/sbin/xcat-install"
cat > "$skeleton/sbin/mount" <<'MOUNT'
#!/bin/sh
printf '%s\n' "$*" > /fixture/mount-reached
exit 33
MOUNT
chmod 0555 "$skeleton/sbin/mount"
cat > "$skeleton/fixture/driver.lua" <<'LUA'
local api = assert(loadfile('/usr/libexec/bsdinstall/pkgbase'))('xcat-freebsd-pkgbase-selection-api-1')
api.prepare('/fixture/config', '/fixture')
LUA

case_number=0
for selection in none all worker backend reporter worker-backend worker-reporter backend-reporter timer-unrostered timer-absent; do
    case_number=$((case_number+1))
    case_dir=$workspace/$selection
    mkdir -m 0700 "$case_dir"
    cp -Rp "$skeleton" "$case_dir/root"
    root=$case_dir/root
    if [ "$selection" = timer-absent ]; then rm "$root/usr/local/libexec/xcat-postscript-time"; fi
    {
        printf '%s\n' /usr/libexec/bsdinstall/pkgbase /usr/local/libexec/xcat-pkgbase.lua \
            /usr/local/libexec/xcat-package-plan.lua /usr/local/libexec/xcat-install-lib.sh \
            /usr/local/libexec/freebsd-pkg-resolve /usr/local/sbin/pkg-static /usr/local/sbin/xcat-install \
            /usr/libexec/flua /bin/sh /bin/mkdir /bin/chmod /sbin/sha256 /sbin/mount /sbin/mdconfig \
            /sbin/glabel /usr/bin/stat /bin/df /usr/bin/env /bin/timeout /usr/bin/fetch /sbin/sysctl /usr/bin/fsync
        case "$selection" in timer-unrostered|timer-absent) ;; *) printf '%s\n' /usr/local/libexec/xcat-postscript-time ;; esac
        case "$selection" in all|timer-*|worker|worker-backend|worker-reporter) printf '%s\n' /usr/local/libexec/xcat-postscript ;; esac
        case "$selection" in all|timer-*|backend|worker-backend|backend-reporter) printf '%s\n' /usr/local/libexec/xcat-postscript-packages ;; esac
        case "$selection" in all|timer-*|reporter|worker-reporter|backend-reporter) printf '%s\n' /usr/local/libexec/xcat-postboot ;; esac
    } | sort > "$case_dir/paths"
    {
        printf 'format\txcat-freebsd-runtime-2\ntarget\t15.1-RELEASE\tFreeBSD:15:amd64\t1501000\npkg-version\t2.6.2\nbsdinstall-contract\txcat-freebsd-pkgbase-1\n'
        while IFS= read -r path; do printf 'file\t%s\t%s\n' "${path#/}" "$(sha256 -q "$root$path")"; done < "$case_dir/paths"
    } > "$root/xcat/runtime.tsv"
    cat > "$root/fixture/config" <<'CONFIG'
format=xcat-freebsd-install-2
release=15.1-RELEASE
node=node01
generation=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
master=192.0.2.1
port=3002
mac=52:54:00:12:34:56
ipv4=192.0.2.20
netmask=255.255.255.0
gateway=
hostname=node01.example.test
target_disk=vtbd0
target_disk_ident=XCAT_TEST_DISK
filesystem=ufs
swap_size=0
authorized_key_base64=c3NoLWVkMjU1MTkgZml4dHVyZQ==
nameservers=
install_url=http://192.0.2.1/install
package_plan_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
boot_media_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
CONFIG
    printf 'runtime_sha256=%s\n' "$(sha256 -q "$root/xcat/runtime.tsv")" >> "$root/fixture/config"
    status=0
    env XCAT_ATTEMPT=cccccccccccccccccccccccccccccccc /bin/timeout -k 5 30 \
        chroot "$root" /usr/libexec/flua /fixture/driver.lua > "$case_dir/stdout" 2> "$case_dir/stderr" || status=$?
    printf '%s\n' "$status" > "$case_dir/status"
    [ "$status" -eq 1 ]
    case "$selection" in
    all)
        [ -f "$root/fixture/mount-reached" ]
        [ "$(cat "$root/fixture/mount-reached")" = -p ]
        grep -q 'Native command failed or exceeded its bound' "$case_dir/stderr"
        ;;
    timer-unrostered)
        [ ! -e "$root/fixture/mount-reached" ]
        grep -q 'Runtime roster lacks a required preparation file' "$case_dir/stderr"
        ;;
    timer-absent)
        [ ! -e "$root/fixture/mount-reached" ]
        grep -q 'Native command failed or exceeded its bound' "$case_dir/stderr"
        ;;
    *)
        [ ! -e "$root/fixture/mount-reached" ]
        grep -q 'Incomplete postscript runtime' "$case_dir/stderr"
        ;;
    esac
    [ ! -e "$root/fixture/pkgbase" ]
    printf 'PASS runtime roster %s\n' "$selection"
done
printf 'PASS cases=%s\n' "$case_number"
