#!/bin/bash
set -eu
root=$TEST_SANDBOX
mkdir -p "$root/etc/yum.repos.d" "$root/tmp" "$root/xcatpost" "$root/dev" \
    "$root$TEST_FIXTURES" "$root$TEST_POSTSCRIPTS"
for path in /usr /bin /sbin /lib /lib64; do
    [ -d "$path" ] || continue
    mkdir -p "$root$path"
    /bin/mount --bind "$path" "$root$path"
    /bin/mount -o remount,bind,ro "$root$path"
done
for file in passwd group nsswitch.conf ld.so.cache os-release; do
    [ ! -f "/etc/$file" ] || cp "/etc/$file" "$root/etc/$file"
done
for path in /etc/dnf /etc/rpm; do
    [ -d "$path" ] || continue
    mkdir -p "$root$path"
    /bin/mount --bind "$path" "$root$path"
    /bin/mount -o remount,bind,ro "$root$path"
done
for device in null zero random urandom; do
    touch "$root/dev/$device"
    /bin/mount --bind "/dev/$device" "$root/dev/$device"
done
/bin/mount --bind "$TEST_FIXTURES" "$root$TEST_FIXTURES"
/bin/mount --bind "$TEST_POSTSCRIPTS" "$root$TEST_POSTSCRIPTS"
/bin/mount -o remount,bind,ro "$root$TEST_POSTSCRIPTS"
/bin/mount --bind "$TEST_REPOS" "$root/etc/yum.repos.d"
if [ -n "${TEST_KEY:-}" ]; then
    mkdir -p "$root/etc/pki/rpm-gpg"
    cp "$TEST_KEY" "$root/etc/pki/rpm-gpg/RPM-GPG-KEY-openEuler"
fi
exec /usr/sbin/chroot "$root" "$@"
