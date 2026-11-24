#!/bin/sh

# genimage stages the fetch helper only for an eligible UFTP receiver.
xcat_install_uftp_receiver() {
    if [ -r "$moddir/xcat-rootimg-fetch.sh" ]; then
        "$1" "$moddir/xcat-rootimg-fetch.sh" "/lib/xcat-rootimg-fetch.sh"
        for uftpd in /usr/sbin/uftpd /usr/bin/uftpd; do
            if [ -x "$uftpd" ]; then
                dracut_install "$uftpd"
                break
            fi
        done
    fi
}
