#!/bin/sh

# Exercise target startup selection with account and service recorders.
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
LC_ALL=C
export PATH LC_ALL
umask 077
[ "$#" -eq 2 ]
workspace=$1
source=$2
[ "$(id -u):$(freebsd-version -u)" = 0:15.1-RELEASE ]
[ ! -e "$workspace" ] && [ ! -L "$workspace" ]
mkdir -m 0700 "$workspace"
skeleton=$workspace/skeleton
mkdir -p "$skeleton/etc/ssh" "$skeleton/usr/sbin" "$skeleton/var/db/xcat/pkgbase-install" \
    "$skeleton/usr/local/etc/rc.d" "$skeleton/fixture" "$skeleton/tmp" "$workspace/installer-tmp"
for tool in sh cat chmod cp install mkdir mv rm awk base64 cmp fsync mktemp stat sha256; do
    path=$(command -v "$tool")
    printf '%s\n' "$path" >> "$workspace/paths"
    ldd "$path" >> "$workspace/ldd"
done
printf '%s\n' /libexec/ld-elf.so.1 >> "$workspace/paths"
awk '$2 == "=>" && $3 ~ /^\// {print $3}' "$workspace/ldd" >> "$workspace/paths"
! grep -q 'not found' "$workspace/ldd"
sort -u "$workspace/paths" > "$workspace/runtime"
while IFS= read -r path; do
    mkdir -p "$skeleton$(dirname "$path")"
    cp -p "$path" "$skeleton$path"
done < "$workspace/runtime"
install -m 0444 "$source/installerconfig.tmpl" "$skeleton/template"
install -m 0555 "$source/xcat-postboot" "$skeleton/usr/local/etc/rc.d/xcatpostboot"
cat > "$skeleton/usr/sbin/pw" <<'PW'
#!/bin/sh
[ "$*" = 'usermod root -h -' ] || exit 99
printf '%s\n' "$*" >> /fixture/accounts
PW
cat > "$skeleton/usr/sbin/sysrc" <<'SYSRC'
#!/bin/sh
set -eu
temporary=$(mktemp -t xcat-test-sysrc)
[ -f "$temporary" ]
rm "$temporary"
printf '%s\n' "$@" >> /fixture/services
SYSRC
chmod 0555 "$skeleton/usr/sbin/pw" "$skeleton/usr/sbin/sysrc"
printf '# fixture SSH configuration\n' > "$skeleton/etc/ssh/sshd_config"
printf 'fixture runtime\n' > "$skeleton/var/db/xcat/pkgbase-install/runtime"
runtime_sha=$(sha256 -q "$skeleton/var/db/xcat/pkgbase-install/runtime")
generation=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
attempt=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
key=$(printf 'ssh-ed25519 fixture' | base64 | tr -d '\n')
count=0
for label in legacy complete legacy-tmpdir complete-tmpdir marker-digest marker-link marker-mode missing-reporter \
    reporter-link reporter-mode existing-controller controller-link; do
    case_dir=$workspace/$label
    mkdir -m 0700 "$case_dir"
    cp -Rp "$skeleton" "$case_dir/root"
    root=$case_dir/root
    marker=$root/var/db/xcat/pkgbase-install/postscript-runtime
    reporter=$root/usr/local/etc/rc.d/xcatpostboot
    controller=$root/var/db/xcat/boot-controller
    selection=${label%-tmpdir}
    if [ "$selection" != legacy ]; then
        printf 'format\txcat-freebsd-postscripts-1\nruntime-sha256\t%s\n' "$runtime_sha" > "$marker"
        chmod 0400 "$marker"
    fi
    case "$label" in
    marker-digest) chmod 0600 "$marker"; printf 'incorrect\n' > "$marker"; chmod 0400 "$marker" ;;
    marker-link) mv "$marker" "$root/marker"; ln -s /marker "$marker" ;;
    marker-mode) chmod 0644 "$marker" ;;
    missing-reporter) rm "$reporter" ;;
    reporter-link) mv "$reporter" "$root/reporter"; ln -s /reporter "$reporter" ;;
    reporter-mode) chmod 0755 "$reporter" ;;
    existing-controller) printf 'preserve\n' > "$controller" ;;
    controller-link) printf 'preserve\n' > "$root/sentinel"; ln -s /sentinel "$controller" ;;
    esac
    temporary_directory=/tmp
    case "$label" in
    *-tmpdir) temporary_directory=$workspace/installer-tmp; [ ! -e "$root$temporary_directory" ] ;;
    esac
    status=0
    env TMPDIR="$temporary_directory" XCAT_MASTER=192.0.2.1 XCAT_PORT=3002 XCAT_GENERATION="$generation" XCAT_ATTEMPT="$attempt" \
        XCAT_HOSTNAME=node.example.test XCAT_PROVISIONING_IF=em0 XCAT_IPV4=192.0.2.20 \
        XCAT_NETMASK=255.255.255.0 XCAT_GATEWAY= XCAT_NAMESERVERS= XCAT_AUTHORIZED_KEY_BASE64="$key" \
        chroot "$root" /bin/sh /template > "$case_dir/stdout" 2> "$case_dir/stderr" || status=$?
    printf '%s\n' "$status" > "$case_dir/status"
    case "$selection" in
    legacy)
        [ "$status" = 0 ]
        [ -f "$root/var/db/xcat/firstboot" ] && [ ! -e "$controller" ]
        grep -qx xcatfirstboot_enable=YES "$root/fixture/services"
        ! grep -q xcatpostboot_enable "$root/fixture/services"
        ;;
    complete)
        [ "$status" = 0 ]
        [ ! -e "$root/var/db/xcat/firstboot" ]
        [ "$(stat -f '%u:%g:%l:%Lp' "$controller")" = 0:0:1:600 ]
        printf '192.0.2.1\n3002\n%s\n%s\n' "$generation" "$attempt" | cmp -s - "$controller"
        grep -qx xcatpostboot_enable=YES "$root/fixture/services"
        grep -qx xcatfirstboot_enable=NO "$root/fixture/services"
        cmp "$source/xcat-postboot" "$reporter"
        ;;
    *)
        [ "$status" -ne 0 ]
        ! grep -qx xcatpostboot_enable=YES "$root/fixture/services"
        if [ "$label" = existing-controller ]; then [ "$(cat "$controller")" = preserve ]; fi
        if [ "$label" = controller-link ]; then [ -L "$controller" ] && [ "$(cat "$root/sentinel")" = preserve ]; fi
        ;;
    esac
    count=$((count+1))
    printf 'PASS target startup %s\n' "$label"
done
[ "$count" -eq 12 ]
