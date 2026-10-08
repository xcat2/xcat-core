#!/bin/sh
# Label the stateless root with the policy of the image. dracut 98selinux loads that
# policy at pre-pivot 50, and systemd cannot start from an unlabelled tmpfs root.

xcat_selinux_relabel()
{
    getarg selinux=0 >/dev/null && return 0

    # A squashfs root carries its labels, and a relabel would copy every file to the overlay.
    [ -e "${xcat_sfs_image:-/rootimg.sfs}" ] && return 0

    local config="$NEWROOT/etc/selinux/config" mode type fc setfiles rc
    [ -r "$config" ] || return 0
    mode=$(sed -n 's/^[[:space:]]*SELINUX[[:space:]]*=[[:space:]]*//p' "$config" | tail -n 1)
    [ "$mode" = disabled ] && return 0
    type=$(sed -n 's/^[[:space:]]*SELINUXTYPE[[:space:]]*=[[:space:]]*//p' "$config" | tail -n 1)
    fc="/etc/selinux/${type:-targeted}/contexts/files/file_contexts"
    if [ ! -r "$NEWROOT$fc" ]; then
        warn "xCAT: $fc is not in the image, the root is not labelled"
        return 0
    fi

    setfiles=/usr/sbin/setfiles
    [ -x "$NEWROOT$setfiles" ] || setfiles=/sbin/setfiles

    mount -t proc proc "$NEWROOT/proc"
    mount --bind /sys "$NEWROOT/sys"
    chroot "$NEWROOT" "$setfiles" -F -e /proc -e /sys -e /dev "$fc" /
    rc=$?
    umount "$NEWROOT/sys"
    umount "$NEWROOT/proc"
    [ "$rc" -eq 0 ] || warn "xCAT: setfiles returned $rc"
}

xcat_selinux_relabel
