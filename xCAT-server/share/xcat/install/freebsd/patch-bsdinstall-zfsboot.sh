#!/bin/sh

set -eu
[ "$#" -eq 1 ] || {
    printf 'Usage: %s native-bsdinstall-zfsboot\n' "$0" >&2
    exit 2
}
[ "$(sha256 -q "$1")" = 0ffa0dc4ed3346e5e732fa96e460291f74a47f8d0bd8b349738a8acfb2d57e98 ] || {
    printf 'Unsupported FreeBSD 15.1 bsdinstall zfsboot checksum.\n' >&2
    exit 1
}
XCAT_STORAGE_HOOKS=$(cat "$(dirname "$0")/xcat-storage-hooks.sh")
export XCAT_STORAGE_HOOKS
awk '
    /^############################################################ MAIN$/ {
        main++
        print ENVIRON["XCAT_STORAGE_HOOKS"]
        print "if [ -n \"${XCAT_STORAGE_WORK:-}\" ]; then"
        print "    XCAT_STORAGE_FORCE="
        print "    ZFSBOOT_POOL_CREATE_OPTIONS=\"$ZFSBOOT_POOL_CREATE_OPTIONS -o cachefile=none\""
        print "    XCAT_STORAGE_EFI_PREFIX=$(xcat_storage_call efi-prefix) || exit 1"
        print "    xcat_storage_call start \"$ZFSBOOT_DISKS\" \"$ZFSBOOT_VDEV_TYPE\" \"$ZFSBOOT_POOL_NAME\" \"$ZFSBOOT_SWAP_SIZE\" \"$ZFSBOOT_GELI_ENCRYPTION\" \"$ZFSBOOT_BOOT_POOL\" || exit 1"
        print "else"
        print "    XCAT_STORAGE_FORCE=-f"
        print "    XCAT_STORAGE_EFI_PREFIX=efiboot"
        print "fi"
    }
    /Exporting ZFS pools\.\.\./ {
        cleanup++
        print "\tif [ -z \"${XCAT_STORAGE_WORK:-}\" ]; then"
    }
    /ZFSBOOT_POOL_NAME=\$\(dialog_pool_name/ {
        collision++
        print "\t\t[ -z \"${XCAT_STORAGE_WORK:-}\" ] || exit 1"
    }
    /^exit \$SUCCESS$/ {
        finish++
        print "if [ -n \"${XCAT_STORAGE_WORK:-}\" ]; then"
        print "    xcat_storage_call configured || exit 1"
        print "fi"
    }
    {
        close_cleanup=0
        if (cleanup && /\$GPART_DESTROY_F/ && ++destroy == 2) close_cleanup=1
        labels+=gsub(/efiboot\$index/, "${XCAT_STORAGE_EFI_PREFIX}$index")
        force+=gsub(/-m none -f/, "-m none ${XCAT_STORAGE_FORCE}")
        gsub(/f_eval_catch/, "xcat_storage_eval")
        print
        if (close_cleanup) print "\tfi"
    }
    /zfs_create_diskpart \$disk \$n \|\| return \$FAILURE/ {
        partitioned++
        print "\t\tif [ -n \"${XCAT_STORAGE_WORK:-}\" ]; then"
        print "\t\t\txcat_storage_call partitioned \"$disk\" \"$targetpart\" || exit 1"
        print "\t\tfi"
    }
    /^while :; do$/ {
        retry++
        print "\tif [ -n \"${XCAT_STORAGE_WORK:-}\" ]; then"
        print "\t\txcat_storage_call attempt || exit 1"
        print "\tfi"
    }
    END {if (main != 1 || cleanup != 1 || destroy != 2 || labels != 2 || force != 2 || partitioned != 1 || retry != 1 || finish != 1 || collision != 1) exit 1}
' "$1"
