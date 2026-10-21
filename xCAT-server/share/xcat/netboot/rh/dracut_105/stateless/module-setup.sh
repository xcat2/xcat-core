#!/bin/bash
# Dracut module for xCAT Stateless Boot
# /opt/xcat/.../dracut_105/stateless/module-setup.sh

check() {
    # Always allow this module to load
    return 0
}

depends() {
    echo "network nfs"
    # EL10 may require network-manager explicitly if selected
    return 0
}

install() {
    # Install binaries
    # Note: Copied from dracut_047/install.netboot
    dracut_install curl tar cpio gzip modprobe touch echo cut wc xz sha256sum \
        grep ifconfig hostname awk egrep dirname expr \
        mount.nfs parted mke2fs bc mkswap swapon chmod mkfs mkfs.ext4 mkfs.xfs xfs_db \
        ethtool

    # xCAT helper scripts
    inst_script "$moddir/xcatroot" "/sbin/xcatroot"
    inst_simple "$moddir/xcat-updateflag" "/tmp/updateflag"

    # cmdline hook
    inst_hook cmdline 10 "$moddir/xcat-cmdline.sh"

    # genimage adds the UFTP helper only when the image has a UFTP 5 receiver.
    if [ -r "$moddir/xcat-rootimg-fetch.sh" ]; then
        inst_simple "$moddir/xcat-rootimg-fetch.sh" "/lib/xcat-rootimg-fetch.sh"
        for uftpd in /usr/sbin/uftpd /usr/bin/uftpd; do
            if [ -x "$uftpd" ]; then
                dracut_install "$uftpd"
                break
            fi
        done
    fi

    # udev rules with "xcat"
    for file in /etc/udev/rules.d/*; do
        if grep -qi xcat "$file"; then
            inst_simple "$file" "$file"
        fi
    done
}
