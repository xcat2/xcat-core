#!/bin/sh

set -eu
[ "$#" -eq 1 ] || {
    printf 'Usage: %s native-bsdinstall-script\n' "$0" >&2
    exit 2
}
[ "$(sha256 -q "$1")" = 1683193f5d36338d3a3db10322a0953222bcee357715819e0f8996e48c192788 ] || {
    printf 'Unsupported FreeBSD 15.1 bsdinstall script checksum.\n' >&2
    exit 1
}
XCAT_STORAGE_HOOKS=$(cat "$(dirname "$0")/xcat-storage-hooks.sh")
export XCAT_STORAGE_HOOKS
awk '
    /^BSDCFG_SHARE=/ {hooks++; print ENVIRON["XCAT_STORAGE_HOOKS"]}
    /^[\t ]+if \[ "\$file" \]; then$/ {
        dialog++
        $0="\tif [ \"$file\" ] && [ \"${nonInteractive:-}\" != YES ]; then"
    }
    /^[\t ]+\[ -f "\$PATH_FSTAB" \] \|\| exit$/ {
        cleanup++
        print "\t[ -z \"${XCAT_STORAGE_WORK:-}\" ] || exit 1"
    }
    /^bsdinstall mount$/ {mount++; $0="xcat_storage_step bsdinstall mount"}
    /^bsdinstall umount$/ {unmount++; $0="xcat_storage_step bsdinstall umount"}
    /^[\t ]+zpool export \$ZFSBOOT_POOL_NAME$/ {
        exports++
        if (exports == 2) sub(/zpool export /, "xcat_storage_step zpool export ")
    }
    /^trap - EXIT$/ {
        finish++
        print "if [ -n \"${XCAT_STORAGE_WORK:-}\" ]; then"
        print "    xcat_storage_call finish || exit 1"
        print "fi"
    }
    {print}
    END {
        if (hooks != 1 || dialog != 1 || cleanup != 1 || mount != 1 || unmount != 1 ||
            exports != 2 || finish != 1) exit 1
    }
' "$1"
