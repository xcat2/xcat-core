root=1
rootok=1
netroot=xcat
clear
echo PS1="'"'[xCAT Genesis running on \H \w]\$ '"'" > /.bashrc
echo PS1="'"'[xCAT Genesis running on \H \w]\$ '"'" > /.bash_profile
mkdir -p /etc/ssh
mkdir -p /var/tmp/
mkdir -p /var/empty/sshd
echo root:x:0:0::/:/bin/bash >> /etc/passwd
echo sshd:x:30:30:SSH User:/var/empty/sshd:/sbin/nologin >> /etc/passwd
echo rpc:x:32:32:Rpcbind Daemon:/var/cache/rpcbind:/sbin/nologin >> /etc/passwd
echo rpcuser:x:29:29:RPC Service User:/var/lib/nfs:/sbin/nologin >> /etc/passwd
echo qemu:x:107:107:qemu user:/:/sbin/nologin >> /etc/passwd
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
if grep console=ttyS /proc/cmdline > /dev/null; then
	while :; do sleep 1; screen -x console < /dev/tty1 > /dev/tty1 2>&1; clear; done &
fi
while :; do screen -ln < /dev/tty2 > /dev/tty2 2>&1; done &
while :; do screen -L -ln doxcat; done 
