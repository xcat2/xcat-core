#!/bin/sh
# Fetch the root when an interface comes up.
#
# dracut dispatches a netroot= handler from network-legacy's ifup. Ubuntu 25.10 and later ship no
# network-legacy, so network resolves through systemd-networkd and nothing calls /sbin/netroot.
# xcat-cmdline.sh sets netroot=xcat and install.netboot puts /sbin/xcatroot in the image, and
# neither is ever reached: the initramfs fetches nothing and gives up in emergency mode about
# three seconds in. This hook runs from initqueue/online, which every network module reaches.
type getarg >/dev/null 2>&1 || . /lib/dracut-lib.sh

# One interface is enough, and a second call would download the image again.
[ -e /tmp/xcat.rootimg.done ] && exit 0
[ -x /sbin/xcatroot ] || exit 0

netif=$1
[ -n "$netif" ] || exit 0

# dracut calls a netroot handler as <interface> <netroot> <NEWROOT>.
if /sbin/xcatroot "$netif" "${netroot:-xcat}" "${NEWROOT:-/sysroot}"; then
    : > /tmp/xcat.rootimg.done
fi
