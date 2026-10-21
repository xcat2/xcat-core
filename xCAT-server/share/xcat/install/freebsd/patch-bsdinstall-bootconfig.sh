#!/bin/sh

set -eu
[ "$#" -eq 1 ] || {
    printf 'Usage: %s native-bsdinstall-bootconfig\n' "$0" >&2
    exit 2
}
[ "$(sha256 -q "$1")" = 9211feb6f6b5b6acfb402b7fe506e370112653b280ee2811e6dea5d3ccfa6138 ] || {
    printf 'Unsupported FreeBSD 15.1 bsdinstall bootconfig checksum.\n' >&2
    exit 1
}
XCAT_STORAGE_HOOKS=$(cat "$(dirname "$0")/xcat-storage-hooks.sh")
export XCAT_STORAGE_HOOKS
awk '
    /^BSDCFG_SHARE=/ {hooks++; print ENVIRON["XCAT_STORAGE_HOOKS"]}
    /local loader_path=\$1/ {
        print
        print "\tif [ -n \"${XCAT_STORAGE_WORK:-}\" ] && [ \"$nentries\" -ne 0 ]; then exit 1; fi"
        entries++
        next
    }
    {
        if ($0 ~ /mkdir -p "\$\{freebsd_dir\}"/) {
            sub(/mkdir -p/, "xcat_storage_boot mkdir -p"); directories++
        }
        if ($0 ~ /cp "\$\{ldr\}"/) {sub(/cp /, "xcat_storage_boot cp "); copies++}
        if ($0 ~ /mount -t msdos "\$dev"/) {sub(/mount -t/, "xcat_storage_boot mount -t"); mounts++}
        if ($0 ~ /umount "\$tmpmnt"/) {sub(/umount /, "xcat_storage_boot umount "); unmounts++}
        if ($0 ~ /^[\t ]+update_uefi_bootentry "\$\{mntpt\}/) {
            print "\t\txcat_storage_esp=${XCAT_STORAGE_PRIMARY_ESP:-}"
            sub(/update_uefi_bootentry /, "xcat_storage_boot update_uefi_bootentry "); updates++
        }
        print
    }
    /mntpt="\$BSDINSTALL_CHROOT\/boot\/efi"/ {
        primary++
        print "\tif [ -n \"${XCAT_STORAGE_WORK:-}\" ]; then"
        print "\t\txcat_storage_esp=$(xcat_storage_call boot-primary \"$PATH_FSTAB\" \"$mntpt\") || exit 1"
        print "\t\tXCAT_STORAGE_PRIMARY_ESP=$xcat_storage_esp"
        print "\t\tEFI_LABEL_NAME=$(xcat_storage_call boot-label) || exit 1"
        print "\t\texport EFI_LABEL_NAME"
        print "\t\tBSDINSTALL_CONFIGCURRENT=YES"
        print "\tfi"
    }
    /for dev in \$\(cat \$esps\); do/ {
        extra++
        print "\t\txcat_storage_esp=$dev"
    }
    END {
        if (hooks != 1 || entries != 1 || directories != 1 || copies != 2 || mounts != 1 ||
            unmounts != 1 || updates != 1 || primary != 1 || extra != 1) exit 1
        print "if [ -n \"${XCAT_STORAGE_WORK:-}\" ]; then"
        print "    xcat_storage_call boot-finish || exit 1"
        print "fi"
    }
' "$1"
