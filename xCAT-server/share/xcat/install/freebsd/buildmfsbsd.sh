#!/bin/sh

set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
LC_ALL=C
export PATH LC_ALL

if [ "$#" -ne 5 ]; then
    printf 'Usage: %s mfsbsd-source dist-directory output.iso mfsbsd-commit manifest-sha256\n' "$0" >&2
    exit 2
fi
[ "$(uname -s)" = FreeBSD ] && [ "$(uname -m)" = amd64 ] || {
    printf 'Build this image on FreeBSD amd64.\n' >&2; exit 1;
}
case "$(freebsd-version -u)" in 15.1-RELEASE|15.1-RELEASE-p[0-9]*) ;; *)
    printf 'The build host must run FreeBSD 15.1-RELEASE.\n' >&2; exit 1 ;;
esac
[ "$(id -u)" -eq 0 ] || { printf 'The mfsBSD build requires root.\n' >&2; exit 1; }
script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$script_dir/xcat-install-lib.sh"
source_dir=$(realpath "$1")
dist_dir=$(realpath "$2")
output_dir=$(realpath "$(dirname "$3")")
output_file=$output_dir/$(basename "$3")
source_commit=$4
manifest_sha256=$5
for build_path in "$source_dir" "$dist_dir" "$output_file" "$script_dir"; do
    case "$build_path" in *[!A-Za-z0-9_./+-]*) xcat_error 'Build paths must not contain spaces or shell metacharacters' ;; esac
done
xcat_hex "$source_commit" 40 && xcat_hex "$manifest_sha256" 64 || xcat_error 'Invalid source or manifest checksum'
[ ! -e "$output_file" ] && [ ! -L "$output_file" ] || xcat_error 'Output file already exists'
[ "$(git -C "$source_dir" rev-parse "$source_commit^{commit}")" = "$source_commit" ] || xcat_error 'mfsBSD source commit does not match'
[ "$(sha256 -q "$dist_dir/MANIFEST")" = "$manifest_sha256" ] || xcat_error 'Distribution manifest checksum does not match'
for dist_set in base.txz kernel.txz; do
    expected=$(awk -v name="$dist_set" '$1==name {value=$2; count++} END {if (count==1) print value; else exit 1}' "$dist_dir/MANIFEST")
    xcat_hex "$expected" 64 && [ "$(sha256 -q "$dist_dir/$dist_set")" = "$expected" ] || xcat_error "Checksum mismatch: $dist_set"
done
build_work=$(mktemp -d /tmp/xcat-mfsbsd.XXXXXX)
output_stage=
build_cleanup()
{
    build_result=$?
    trap - EXIT HUP INT TERM
    if [ "$build_result" -ne 0 ]; then
        printf 'mfsBSD build stopped. Work directory: %s\n' "$build_work" >&2
    else
        chflags -R noschg "$build_work"
        rm -rf "$build_work"
    fi
    [ -z "$output_stage" ] || rm -f "$output_stage"
    exit "$build_result"
}
trap build_cleanup EXIT
trap 'exit 1' HUP INT TERM
mkdir -p "$build_work/source" "$build_work/conf" "$build_work/custom/usr/local/sbin" \
    "$build_work/custom/usr/local/libexec" "$build_work/custom/usr/local/share/xcat" \
    "$build_work/custom/usr/libexec/bsdinstall" \
    "$build_work/scripts" "$build_work/native" \
    "$build_work/bundle/usr/freebsd-dist" "$build_work/bundle/xcat"
git -C "$source_dir" archive -o "$build_work/source.tar" "$source_commit"
tar -xf "$build_work/source.tar" -C "$build_work/source"
cp -R "$build_work/source/conf/." "$build_work/conf/"
install -m 0555 "$script_dir/xcat-install" "$build_work/custom/usr/local/sbin/xcat-install"
install -m 0444 "$script_dir/xcat-install-lib.sh" "$build_work/custom/usr/local/libexec/xcat-install-lib.sh"
install -m 0444 "$script_dir/installerconfig.tmpl" "$build_work/custom/usr/local/share/xcat/installerconfig.tmpl"
tar -xf "$dist_dir/base.txz" -C "$build_work/native" usr/libexec/bsdinstall/umount
sh "$script_dir/patch-bsdinstall-umount.sh" "$build_work/native/usr/libexec/bsdinstall/umount" \
    > "$build_work/custom/usr/libexec/bsdinstall/umount"
chmod 0555 "$build_work/custom/usr/libexec/bsdinstall/umount"
cat > "$build_work/conf/rc.conf" <<'XCAT_RC'
hostname="xcat-installer"
sshd_enable="NO"
sendmail_enable="NONE"
cron_enable="NO"
local_enable="YES"
zfs_enable="NO"
XCAT_RC
cat > "$build_work/conf/rc.local" <<'XCAT_LOCAL'
#!/bin/sh
exec /usr/local/sbin/xcat-install
XCAT_LOCAL
cat > "$build_work/conf/loader.conf" <<'XCAT_LOADER'
mfs_load="YES"
mfs_type="mfs_root"
mfs_name="/mfsroot"
vfs.root.mountfrom="ufs:/dev/ufs/mfsroot"
mfsbsd.autodhcp="NO"
autoboot_delay="-1"
beastie_disable="YES"
kern.maxphys="65536"
XCAT_LOADER
cat > "$build_work/scripts/strip-hostkeys" <<'XCAT_KEYS'
#!/bin/sh
set -eu
[ -n "${DESTDIR:-}" ] && [ -d "$DESTDIR/etc/ssh" ]
find "$DESTDIR/etc/ssh" -type f -name 'ssh_host_*' -delete
XCAT_KEYS
env -i PATH="$PATH" LC_ALL=C make -j 1 -C "$build_work/source" mfsroot \
    BASE="$dist_dir" VERSION=15.1-RELEASE RELEASE=15.1-RELEASE \
    TARGET=amd64 TARGET_ARCH=amd64 WRKDIR="$build_work/build" \
    CFGDIR="$build_work/conf" CUSTOMFILESDIR="$build_work/custom" \
    CUSTOMSCRIPTSDIR="$build_work/scripts" NO_PACKAGES=1 \
    'ROOTPW_HASH=*' PERMIT_ROOT_LOGIN=no
cp -RL "$build_work/build/disk/boot" "$build_work/bundle/boot"
cp "$build_work/build/disk/mfsroot.gz" "$build_work/bundle/mfsroot.gz"
tar -xf "$dist_dir/base.txz" -C "$build_work/native" boot
cp -RL "$build_work/native/boot/." "$build_work/bundle/boot/"
cp "$build_work/conf/loader.conf" "$build_work/bundle/boot/loader.conf"
find "$build_work/bundle/boot" -type f -size 0 -delete
for dist_set in MANIFEST base.txz kernel.txz; do cp "$dist_dir/$dist_set" "$build_work/bundle/usr/freebsd-dist/$dist_set"; done
(
    cd "$build_work/bundle"
    find boot usr/freebsd-dist -type f -print
    printf '%s\n' mfsroot.gz
) | sort > "$build_work/payload-files"
awk '!/^[A-Za-z0-9_.+-]+(\/[A-Za-z0-9_.+-]+)*$/ || /(^|\/)\.\.?($|\/)/ {exit 1}' "$build_work/payload-files" || xcat_error 'Unsupported boot payload filename'
{
    printf '{"format":"xcat-mfsbsd-1","release":"15.1-RELEASE","arch":"amd64","mfsbsd_commit":"%s","files":{' "$source_commit"
    separator=
    while IFS= read -r payload_file; do
        printf '%s"%s":"%s"' "$separator" "$payload_file" "$(sha256 -q "$build_work/bundle/$payload_file")"
        separator=,
    done < "$build_work/payload-files"
    printf '}}\n'
} > "$build_work/bundle/xcat/mfsbsd.json"
for required in boot/pxeboot boot/loader.efi boot/lua/loader.lua boot/defaults/loader.conf boot/kernel/kernel.gz mfsroot.gz; do
    [ -s "$build_work/bundle/$required" ] || xcat_error "Missing required boot payload: $required"
done
output_stage=$(mktemp "$output_file.XXXXXX")
makefs -t cd9660 -o rockridge,label=xCATmfsBSD \
    -o "bootimage=i386;$build_work/build/cdboot/cdboot,no-emul-boot" \
    -o "bootimage=i386;$build_work/build/cdboot/efiboot.img,no-emul-boot,platformid=efi" \
    "$output_stage" "$build_work/bundle"
chmod 0644 "$output_stage"
ln "$output_stage" "$output_file"
printf 'Created %s\n' "$output_file"
