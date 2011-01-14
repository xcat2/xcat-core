if [ ! -r /etc/redhat-release ] || ! grep "release 6" /etc/redhat-release >/dev/null; then
    exit 0; #only rhel6 supported
fi
if [ -r /sys/devices/virtual/dmi/id/product_uuid ]; then 
    duid='default-duid "\000\004';
    for i in `sed -e s/-//g -e 's/\(..\)/\1 /g' /sys/devices/virtual/dmi/id/product_uuid`; do
        num=`printf "%d" 0x$i`
        octnum=`printf "\\%03o" 0x$i`
        if [ $num -lt 127 -a $num -gt 31 ]; then
            octnum=`printf $octnum`
        fi
        duid=$duid$octnum
    done
    duid=$duid'";'
    for interface in `ifconfig -a|grep HWaddr|awk '{print $1}'`; do
        echo $duid > /var/lib/dhclient/dhclient6-$interface.leases
    done
    echo $duid  > /var/lib/dhclient/dhclient6.leases
fi
