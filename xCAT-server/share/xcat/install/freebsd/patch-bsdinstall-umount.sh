#!/bin/sh

set -eu
if [ "$#" -ne 1 ]; then
    printf 'Usage: %s native-bsdinstall-umount\n' "$0" >&2
    exit 2
fi
if [ "$(sha256 -q "$1")" != 624ae8e292566b28bb6c5a37d14c6e98f06c1fe9b77712cf195982dfc0f9dec0 ]; then
    printf 'Unsupported FreeBSD 15.1 bsdinstall umount checksum.\n' >&2
    exit 1
fi
sed -f - "$1" <<'XCAT_UMOUNT'
s/^cat \$PATH_FSTAB | awk /awk /
s/^}' > \$TMP_FSTAB$/}' "$PATH_FSTAB" > "$TMP_FSTAB" || exit 1/
s/^if \[ -n "\$TMP_FSTAB" \]; then$/if [ -s "$TMP_FSTAB" ]; then/
s/^umount \$BSDINSTALL_CHROOT\/dev 2>\/dev\/null$/umount "$BSDINSTALL_CHROOT\/dev" 2>\/dev\/null || exit 1/
XCAT_UMOUNT
