#!/bin/sh

set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
LC_ALL=C
export PATH LC_ALL

fail()
{
    printf 'xCAT FreeBSD adapter: %s\n' "$*" >&2
    exit 1
}

[ "$#" -eq 3 ] || fail 'Usage: stage-pkgbase-adapter.sh ram-root pkg-archive native-resolver'
root=$(realpath "$1")
resolver=$(realpath "$3")
source=$(CDPATH= cd "$(dirname "$0")" && pwd)
[ "$root" = "$1" ] && [ "$root" != / ] || fail 'Use a canonical RAM-root path'
for name in "$root" "$resolver" "$source"; do
    case "$name" in *[!A-Za-z0-9_./+-]*) fail 'Unsupported staging path' ;; esac
done
[ -f "$resolver" ] && [ ! -L "$3" ] || fail 'Resolver must be a regular file'
[ "$(sha256 -q "$resolver")" = ad1be19a9491ac9b34c5a203c6c90d70907949c6ddb548a168034b64f8e87be9 ] || fail 'Unsupported qualified resolver'
[ ! -e "$root/xcat/runtime.tsv" ] && [ ! -L "$root/xcat/runtime.tsv" ] || fail 'Runtime already described'
# The release distribution supplies this empty directory before pkg activation.
if [ -d "$root/var/db/pkg" ] && [ ! -L "$root/var/db/pkg" ]; then
    rmdir "$root/var/db/pkg" || fail 'The build root contains package state'
fi
sh "$source/stage-pkgbase-runtime.sh" "$root" "$2"
install -d -m 0755 "$root/usr/local/libexec" "$root/xcat"
install -m 0555 "$resolver" "$root/usr/local/libexec/freebsd-pkg-resolve"
for file in xcat-pkgbase.lua xcat-package-plan.lua xcat-postscript-packages xcat-storage-efi.sh; do
    install -m 0444 "$source/$file" "$root/usr/local/libexec/$file"
done
for file in xcat-postscript xcat-postscript-time xcat-postboot xcat-storage; do
    install -m 0555 "$source/$file" "$root/usr/local/libexec/$file"
done
for file in script pkgbase zfsboot bootconfig; do
    sh "$source/patch-bsdinstall-$file.sh" "$root/usr/libexec/bsdinstall/$file" > "$root/usr/libexec/bsdinstall/$file.xcat"
    chmod 0555 "$root/usr/libexec/bsdinstall/$file.xcat"
    mv "$root/usr/libexec/bsdinstall/$file.xcat" "$root/usr/libexec/bsdinstall/$file"
done
# The v2 root is already a RAM filesystem; retain its registered package database.
[ "$(sha256 -q "$root/etc/rc.d/mdinit")" = 2b4bb4c2ea4a8796736ca61571b74f453890ad8f4130de56d4b89e3f1f233394 ] || fail 'Unsupported mfsBSD startup script'
awk '
    /# Check if we are using roothack/ { skip = 1; count++; next }
    skip && /^\tfi$/ { skip = 0; next }
    !skip { print }
    END { if (skip || count != 1) exit 1 }
' "$root/etc/rc.d/mdinit" > "$root/etc/rc.d/mdinit.xcat"
chmod 0555 "$root/etc/rc.d/mdinit.xcat"
mv "$root/etc/rc.d/mdinit.xcat" "$root/etc/rc.d/mdinit"

work=$(mktemp -d "$root/tmp/xcat-adapter.XXXXXX")
[ -L "$root/usr/bin/tar" ] && [ "$(readlink "$root/usr/bin/tar")" = bsdtar ] &&
    [ -f "$root/usr/bin/bsdtar" ] && [ ! -L "$root/usr/bin/bsdtar" ] || fail 'Unsupported native tar alias'
# Runtime records bind regular files, including command aliases.
install -m 0555 "$root/usr/bin/bsdtar" "$work/tar"
rm "$root/usr/bin/tar"
mv "$work/tar" "$root/usr/bin/tar"
# Preserve diagnostics on failure; the parent builder retains its complete work tree.
cat > "$work/paths" <<'PATHS'
/bin/cat
/bin/chmod
/bin/cp
/bin/date
/bin/dd
/bin/df
/bin/hostname
/bin/kenv
/bin/ln
/bin/mkdir
/bin/mv
/bin/ps
/bin/realpath
/bin/rm
/bin/rmdir
/bin/sh
/bin/sleep
/bin/test
/bin/timeout
/boot/gptzfsboot
/boot/loader.efi
/boot/pmbr
/etc/defaults/rc.conf
/etc/login.conf
/etc/rc.d/mdinit
/etc/rc.subr
/libexec/ld-elf.so.1
/sbin/dhclient
/sbin/geli
/sbin/geom
/sbin/glabel
/sbin/gpart
/sbin/ifconfig
/sbin/kldload
/sbin/mdconfig
/sbin/mount
/sbin/mount_msdosfs
/sbin/newfs_msdos
/sbin/route
/sbin/sha256
/sbin/shutdown
/sbin/sysctl
/sbin/umount
/sbin/zfs
/sbin/zpool
/usr/bin/awk
/usr/bin/base64
/usr/bin/basename
/usr/bin/cmp
/usr/bin/cut
/usr/bin/dirname
/usr/bin/env
/usr/bin/fetch
/usr/bin/find
/usr/bin/fsync
/usr/bin/grep
/usr/bin/head
/usr/bin/id
/usr/bin/limits
/usr/bin/lockf
/usr/bin/mkfifo
/usr/bin/mktemp
/usr/bin/nc
/usr/bin/od
/usr/bin/openssl
/usr/bin/sed
/usr/bin/sort
/usr/bin/ssh-keygen
/usr/bin/stat
/usr/bin/tar
/usr/bin/tr
/usr/bin/uname
/usr/bin/wc
/usr/lib/flua/ucl.so
/usr/libexec/bsdconfig/040.password/include/messages.subr
/usr/libexec/bsdconfig/include/messages.subr
/usr/libexec/bsdinstall/bootconfig
/usr/libexec/bsdinstall/config
/usr/libexec/bsdinstall/entropy
/usr/libexec/bsdinstall/mount
/usr/libexec/bsdinstall/mount_aux
/usr/libexec/bsdinstall/pkgbase
/usr/libexec/bsdinstall/script
/usr/libexec/bsdinstall/umount
/usr/libexec/bsdinstall/zfsboot
/usr/libexec/flua
/usr/local/libexec/freebsd-pkg-resolve
/usr/local/libexec/xcat-install-lib.sh
/usr/local/libexec/xcat-package-plan.lua
/usr/local/libexec/xcat-pkgbase.lua
/usr/local/libexec/xcat-postboot
/usr/local/libexec/xcat-postscript
/usr/local/libexec/xcat-postscript-packages
/usr/local/libexec/xcat-postscript-time
/usr/local/libexec/xcat-storage
/usr/local/libexec/xcat-storage-efi.sh
/usr/local/sbin/pkg-static
/usr/local/sbin/xcat-install
/usr/local/share/xcat/installerconfig.tmpl
/usr/share/bsdconfig/common.subr
/usr/share/bsdconfig/device.subr
/usr/share/bsdconfig/dialog.subr
/usr/share/bsdconfig/geom.subr
/usr/share/bsdconfig/password/password.subr
/usr/share/bsdconfig/strings.subr
/usr/share/bsdconfig/struct.subr
/usr/share/bsdconfig/variable.subr
/usr/sbin/bsdinstall
/usr/sbin/chroot
/usr/sbin/daemon
/usr/sbin/efibootmgr
/usr/sbin/efivar
/usr/sbin/fstyp
/usr/sbin/mtree
/usr/sbin/zdb
PATHS
# Installation runs as root; shutdown needs no setuid permission in this image.
[ -f "$root/sbin/shutdown" ] && [ ! -L "$root/sbin/shutdown" ] || fail 'Invalid shutdown executable'
chmod u-s "$root/sbin/shutdown"
: > "$work/loader.out"
while IFS= read -r path; do
    [ -f "$root$path" ] && [ ! -L "$root$path" ] || fail "Missing runtime file: $path"
    [ "$(stat -f %u "$root$path")" = 0 ] || fail "Runtime file is not root-owned: $path"
    mode=$(stat -f %Lp "$root$path")
    [ "$((0$mode & 07022))" -eq 0 ] || fail "Runtime file has unsafe permissions: $path"
    case "$path" in
        *.lua|*.sh|*.subr|*.tmpl|/boot/*|/etc/*|*/bsdinstall/*|*/bsdinstall|*/xcat-install|*/xcat-post*|*/xcat-storage|*/pkg-static) continue ;;
    esac
    ldd "$root$path" >> "$work/loader.out" 2>> "$work/loader.err" || fail "Cannot inspect loader dependencies: $path"
done < "$work/paths"
[ ! -s "$work/loader.err" ] || fail 'Loader inspection failed'
! grep -q 'not found' "$work/loader.out" || fail 'Unresolved loader dependency'
awk '$2 == "=>" && $3 ~ /^\// {print $3}' "$work/loader.out" >> "$work/paths"
sort -u "$work/paths" > "$work/sorted"
[ "$(wc -l < "$work/sorted" | tr -d ' ')" -le 256 ] || fail 'Runtime roster exceeds its bound'
{
    printf 'format\txcat-freebsd-runtime-2\ntarget\t15.1-RELEASE\tFreeBSD:15:amd64\t1501000\npkg-version\t2.6.2\nbsdinstall-contract\txcat-freebsd-pkgbase-1\n'
    while IFS= read -r path; do
        [ -f "$root$path" ] && [ ! -L "$root$path" ] || fail "Invalid runtime file: $path"
        [ "$(stat -f %u "$root$path")" = 0 ] || fail "Runtime file is not root-owned: $path"
        mode=$(stat -f %Lp "$root$path")
        [ "$((0$mode & 07022))" -eq 0 ] || fail "Runtime file has unsafe permissions: $path"
        printf 'file\t%s\t%s\n' "${path#/}" "$(sha256 -q "$root$path")"
    done < "$work/sorted"
} > "$work/runtime.tsv"
[ "$(wc -c < "$work/runtime.tsv" | tr -d ' ')" -le 65536 ] || fail 'Runtime descriptor exceeds its bound'
for path in /usr/local/libexec/xcat-pkgbase.lua /usr/local/libexec/xcat-package-plan.lua /usr/libexec/bsdinstall/pkgbase; do
    env -i PATH="$PATH" LC_ALL=C XCAT_SYNTAX_FILE="$root$path" /usr/libexec/flua -e 'assert(loadfile(os.getenv("XCAT_SYNTAX_FILE")))'
done
for path in /usr/local/libexec/xcat-install-lib.sh /usr/local/sbin/xcat-install /usr/libexec/bsdinstall/script /etc/rc.d/mdinit \
    /usr/local/libexec/xcat-postscript /usr/local/libexec/xcat-postscript-packages /usr/local/libexec/xcat-postboot \
    /usr/local/libexec/xcat-storage /usr/local/libexec/xcat-storage-efi.sh \
    /usr/libexec/bsdinstall/zfsboot /usr/libexec/bsdinstall/bootconfig; do
    sh -n "$root$path"
done
[ "$(env -i PATH="$PATH" LC_ALL=C chroot "$root" /usr/local/libexec/freebsd-pkg-resolve -C /dev/null -v)" = 2.6.2 ] || fail 'Staged resolver does not load'
[ "$(env -i PATH="$PATH" LC_ALL=C chroot "$root" /usr/local/libexec/xcat-postscript-time uptime)" -ge 0 ] || fail 'Staged postscript timer does not load'
install -m 0444 "$work/runtime.tsv" "$root/xcat/runtime.tsv"
rm -rf "$work"
printf 'Staged the qualified pkgbase adapter in %s\n' "$root"
