if [ ! -r /etc/redhat-release ] || ! grep "release 6" /etc/redhat-release >/dev/null; then
    exit 0; #only rhel6 supported
fi
if [ -r /sys/devices/virtual/dmi/id/product_uuid ]; then 
    duid='default-duid "\000\004';
    for i in `sed -e 's/\(..\)\(..\)\(..\)\(..\)-\(..\)\(..\)-\(..\)\(..\)/\4\3\2\1-\6\5-\8\7/;s/-//g;s/\(..\)/\1 /g' /sys/devices/virtual/dmi/id/product_uuid`; do
        num=`printf "%d" 0x$i`
        octnum=`printf "\\%03o" 0x$i`
#Instead of hoping to be inside printable case, just make them all octal codes
#        if [ $num -lt 127 -a $num -gt 34 ]; then
#            octnum=`printf $octnum`
#        fi
        duid=$duid$octnum
    done
    duid=$duid'";'
    #for interface in `ifconfig -a|grep HWaddr|awk '{print $1}'`; do
    for interface in `ip -4 -oneline link show|grep -i ether |awk -F ":" '{print $2}'| grep -o "[^ ]\+\( \+[^ ]\+\)*"`; do
        echo $duid > /var/lib/dhclient/dhclient6-$interface.leases
    done
    echo $duid  > /var/lib/dhclient/dhclient6.leases
fi
