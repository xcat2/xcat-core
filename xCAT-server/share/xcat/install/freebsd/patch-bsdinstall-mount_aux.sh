#!/bin/sh

set -eu
[ "$#" -eq 1 ] || {
    printf 'Usage: %s native-bsdinstall-mount_aux\n' "$0" >&2
    exit 2
}
[ "$(sha256 -q "$1")" = 39ecb2ae16c45198b5fbda31dbc41278417f07f60521ba458e530ffa4a720ecb ] || {
    printf 'Unsupported FreeBSD 15.1 bsdinstall mount_aux checksum.\n' >&2
    exit 1
}
sed -f - "$1" <<'XCAT_MOUNT_AUX'
s/^mount -t devfs devfs \$BSDINSTALL_CHROOT\/dev$/mount -t devfs devfs "$BSDINSTALL_CHROOT\/dev" || exit 1/
XCAT_MOUNT_AUX
