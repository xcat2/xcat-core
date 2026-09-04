#!/bin/bash
root=1
rootok=1
netroot=xcat

# The image ships the C.UTF-8 locale only. tmux refuses to start under the C locale.
export LC_ALL=C.UTF-8

# screen exits when the image carries no usable terminal. doxcat is the whole of Genesis, so
# it must run whether or not the multiplexer starts. Prints screen or direct.
xcat_console_mode() {
    if screen -ln -d -m -S xcatprobe true >/dev/null 2>&1; then
        screen -S xcatprobe -X quit >/dev/null 2>&1
        echo screen
    else
        echo direct
    fi
}
clear
echo PS1="'"'[xCAT Genesis running on \H \w]\$ '"'" > /.bashrc
echo PS1="'"'[xCAT Genesis running on \H \w]\$ '"'" > /.bash_profile
mkdir -p /etc/ssh
mkdir -p /var/tmp/
mkdir -p /var/empty/sshd
sed -i '/^root:x/d' /etc/passwd
cat >>/etc/passwd <<"__ENDL"
root:x:0:0::/:/bin/bash
sshd:x:30:30:SSH User:/var/empty/sshd:/sbin/nologin
rpc:x:32:32:Rpcbind Daemon:/var/cache/rpcbind:/sbin/nologin
rpcuser:x:29:29:RPC Service User:/var/lib/nfs:/sbin/nologin
qemu:x:107:107:qemu user:/:/sbin/nologin
chrony:x:995:991::/var/lib/chrony:/sbin/nologin
__ENDL
# Fedora 20 ppc64 uses /lib/dracut/hooks/initqueue/finished
# CentOS 7 probably uses /lib/dracut/hooks/initqueue/finished also
if [ -d "/initqueue-finished" ]; then
    echo '[ -e $NEWROOT/proc ]' > /initqueue-finished/xcatroot.sh
else
    #echo 'if [ -e /proc ]; then /bin/doxcat; fi' > /lib/dracut/hooks/initqueue/finished/xcatroot.sh
    echo '[ -e /proc ]' > /lib/dracut/hooks/initqueue/finished/xcatroot.sh
fi
mkdir /dev/cgroup
mount -t cgroup -o cpu,memory,devices cgroup /dev/cgroup
# Fedora 20 ppc64 does not udevd
# CentOS 7 probably does not have udevd either
if [ -f "/sbin/udevd" ]; then
    udevd --daemon
else
    /usr/lib/systemd/systemd-udevd --daemon
fi
udevadm trigger
mkdir -p /var/lib/dhclient/
mkdir -p /var/log
ip link set lo up
echo '127.0.0.1 localhost' >> /etc/hosts
XCAT_CONSOLE_MODE="$(xcat_console_mode)"
if [ "$XCAT_CONSOLE_MODE" = "screen" ]; then
    if grep -q console=ttyS /proc/cmdline; then
        while :; do sleep 1; screen -S console -ln screen -x doxcat </dev/tty1 &>/dev/tty1; clear &>/dev/tty1 ; done &
    fi
    while :; do screen -ln < /dev/tty2 &> /dev/tty2 ; done &
fi

# The section below is just for System P LE hardware discovery

ARCH="$(uname -m)"

if [[ ${ARCH} =~ ppc64 ]]; then
    # Need to wait for NIC initialization (System P LE discovery only)
    sleep 20
    # load all network driver modules listed in /lib/modules/<kernel>/modules.dep file
    KERVER=`uname -r`
    for line in `cat /lib/modules/$KERVER/modules.dep | awk -F: '{print \$1}' | sed -e "s/\(.*\)\.ko.*/\1/"`; do
        if [[ $line =~ "kernel/drivers/net" ]]; then
            modprobe `basename $line`
        fi
    done
    # Check if running on a VM, and load "virtio_pci" module
    cat /proc/cpuinfo | grep "machine" | grep "emulated"
    if [ $? -eq 0 ]; then
        modprobe virtio_pci
    fi
    waittime=2
    ALL_NICS=$(ip link show | grep -v "^ " | awk '{print $2}' | sed -e 's/:$//' | grep -v lo)
    for tmp in $ALL_NICS; do
        tmp_data="$(ip link show "$tmp" | grep -v "^ " | grep "UP")"
        if [ "$tmp_data" == "" ]; then
            ip link set "$tmp" up
        fi
        tmp_data="UP"
        waittime=$((waittime+1))
    done
    # wait 2+number_of_nics seconds for all the LINKed NICs to be UP
    sleep $waittime
elif [[ ${ARCH} =~ x86_64 ]]; then
    # load all network driver modules listed in /lib/modules/<kernel>/modules.dep file
    KERVER=`uname -r`
    # Xen guests require xen-netfront for the paravirtual NIC.
    modprobe xen-netfront 2>/dev/null || :
    for line in `cat /lib/modules/$KERVER/modules.dep |grep -vE 'tunnel|ieee|ifb|bond|dummy|fjes|hv_netvsc|ntb_netdev|hdlc_fr|dlci'| awk -F: '{print \$1}' | sed -e "s/\(.*\)\.ko.*/\1/"`; do
        if [[ $line =~ "kernel/drivers/net" ]]; then
            modprobe `basename $line`
        fi
    done
fi

if [ "$XCAT_CONSOLE_MODE" = "screen" ]; then
    while :; do screen -dr doxcat || screen -S doxcat -L -ln doxcat; done
else
    while :; do doxcat; sleep 5; done
fi
