#!/bin/bash
set -eu
mount --make-rslave /
etc="$BUILD_FIXTURE/etc"
mkdir -p "$etc/mock" "$etc/yum.repos.d"
for file in passwd group nsswitch.conf ld.so.cache; do
    [ ! -f "/etc/$file" ] || /bin/cp "/etc/$file" "$etc/$file"
done
/bin/cp "$BUILD_FIXTURE/os-release" "$etc/os-release"
mount --bind "$etc" /etc
mount --bind "$BUILD_FIXTURE/locks" /var/lock
if [ -d "$BUILD_FIXTURE/repos" ]; then
    mount --bind "$BUILD_FIXTURE/repos" /etc/yum.repos.d
fi
if [ -d "$BUILD_FIXTURE/mock" ]; then
    mount --bind "$BUILD_FIXTURE/mock" /etc/mock
fi
exec "$@"
