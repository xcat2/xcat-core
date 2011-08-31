root=1
rootok=1
netroot=xcat
clear
echo '[ -e $NEWROOT/proc ]' > /initqueue-finished/xcatroot.sh
mkdir /dev/cgroup
mount -t cgroup -o cpu,memory,devices cgroup /dev/cgroup
udevd --daemon
udevadm trigger
mkdir -p /var/lib/dhclient/
mkdir -p /var/log
ip link set lo up
echo '127.0.0.1 localhost' >> /etc/hosts
if [ ! -z "$BOOTIF" ]; then
	BOOTIF=`echo $BOOTIF|sed -e s/01-// -e s/-/:/g`
	echo -n "Waiting for device with address $BOOTIF to appear.."
	gripeiter=300
	while [ -z "$bootnic" ]; do 
		bootnic=`ip link show|grep -B1 $BOOTIF|grep mtu|awk '{print $2}'|sed -e 's/:$//'`
		sleep 0.1
		if [ $gripeiter = 0 ]; then
			echo "ERROR"
			echo "Unable to find boot device (maybe the nbroot is missing the driver for your nic?)"
			while :; do sleep 365d; done
		fi
		gripeiter=$((gripeiter-1))
	done
fi
echo "Done"
if [ -z "$bootnic" ]; then
	echo "ERROR: BOOTIF missing, can't detect boot nic"
fi

if [ -r /sys/devices/virtual/dmi/id/product_uuid ]; then
	duid='default-duid "\\000\\004';
	for i in `sed -e s/-//g -e 's/\(..\)/\1 /g' /sys/devices/virtual/dmi/id/product_uuid`; do
		octnum="\\"`printf "\\%03o" 0x$i`
		duid=$duid$octnum
	done
	duid=$duid'";'
	echo $duid > /var/lib/dhclient/dhclient6.leases
fi
#/bin/sh
mkdir -p /etc/ssh
mkdir -p /var/empty/sshd
echo root:x:0:0::/:/bin/sh >> /etc/passwd
echo sshd:x:30:30:SSH User:/var/empty/sshd:/sbin/nologin >> /etc/passwd
echo rpc:x:32:32:Rpcbind Daemon:/var/cache/rpcbind:/sbin/nologin >> /etc/passwd
echo rpcuser:x:29:29:RPC Service User:/var/lib/nfs:/sbin/nologin >> /etc/passwd
echo qemu:x:107:107:qemu user:/:/sbin/nologin >> /etc/passwd
rpcbind
rpc.statd
ssh-keygen -q -t rsa -f /etc/ssh/ssh_host_rsa_key -C '' -N ''
ssh-keygen -q -t dsa -f /etc/ssh/ssh_host_dsa_key -C '' -N ''
echo 'Protocol 2' >> /etc/ssh/sshd_config
/usr/sbin/sshd
mkdir -p /etc/xcat
mkdir -p /etc/pki/tls
echo "[ req ]
distinguished_name = nodedn

[ nodedn ]" > /etc/pki/tls/openssl.cnf
openssl genrsa -out /etc/xcat/privkey.pem 1024
PUBKEY=`openssl rsa -in /etc/xcat/privkey.pem -pubout|grep -v "PUBLIC KEY"`
PUBKEY=`echo $PUBKEY|sed -e 's/ //g'`
export PUBKEY
/sbin/rsyslogd -c4
mkdir -p /var/lib/lldpad
echo 'lldp :' >> /var/lib/lldpad/lldpad.conf
echo '{' >> /var/lib/lldpad/lldpad.conf
for iface in `ip link |grep -v '^ '|awk '{print $2}'|sed -e 's/:$//'|grep -v lo`; do
echo "$iface :" >> /var/lib/lldpad/lldpad.conf
echo "{" >> /var/lib/lldpad/lldpad.conf
	echo  "tlvid00000006 :" >> /var/lib/lldpad/lldpad.conf
	echo "{" >> /var/lib/lldpad/lldpad.conf
	echo info = '"'$PUBKEY'";' >> /var/lib/lldpad/lldpad.conf
	echo 'enableTx = true;' >> /var/lib/lldpad/lldpad.conf
	echo '};' >> /var/lib/lldpad/lldpad.conf
	echo 'adminStatus = 3;' >> /var/lib/lldpad/lldpad.conf
echo '};' >> /var/lib/lldpad/lldpad.conf
done
echo '};' >> /var/lib/lldpad/lldpad.conf
lldpad -d
dhclient -cf /etc/dhclient.conf -pf /var/run/dhclient.$bootnic.pid $bootnic &
dhclient -6 -pf /var/run/dhclient6.$bootnic.pid $bootnic -lf /var/lib/dhclient/dhclient6.leases &
openssl genrsa -out /etc/xcat/certkey.pem 4096 > /dev/null 2>&1 &

	
	

gripeiter=101
echo -n "Acquiring network addresses.."
while ! ip addr show dev $bootnic|grep -v 'scope link'|grep -v 'dynamic'|grep -v  inet6|grep inet > /dev/null; do
	sleep 0.1
	if [ $gripeiter = 1 ]; then
		echo
		echo "It seems to be taking a while to acquire an IPv4 address, you may want to check spanning tree..."
	fi
	gripeiter=$((gripeiter-1))
done
echo -n "Acquired IPv4 address "
ip addr show dev $bootnic|grep -v 'scope link'|grep -v 'dynamic'|grep -v  inet6|grep inet|awk '{print $2}'
ntpd -g -x
(while ! ntpq -c "rv 0 state"|grep 'state=4' > /dev/null; do sleep 1; done; hwclock --systohc) &
if dmidecode|grep IPMI > /dev/null; then
	modprobe ipmi_si
	modprobe ipmi_devintf
fi
XCATPORT=3001
export XCATPORT
for parm in `cat /proc/cmdline`; do
        key=`echo $parm|awk -F= '{print $1}'`
        if [ "$key" = "xcatd" ]; then
                XCATMASTER=`echo $parm|awk -F= '{print $2}'|awk -F: '{print $1}'`
                XCATPORT=`echo $parm|awk -F= '{print $2}'|awk -F: '{print $2}'`
        fi
done
if [ "$destiny" = "discover" ]; then #skip a query to xCAT when /proc/cmdline will do
	/bin/dodiscovery
fi
/bin/getcert $XCATMASTER:$XCATPORT
/bin/sh
