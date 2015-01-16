#!/bin/sh
NEWROOT=/sysroot
SERVER=${SERVER%%/*}
SERVER=${SERVER%:}
RWDIR=.statelite
if [ ! -z $STATEMNT ]; then #btw, uri style might have left future options other than nfs open, will u    se // to detect uri in the future I guess
    SNAPSHOTSERVER=${STATEMNT%:*}
    SNAPSHOTROOT=${STATEMNT#*/}
    #echo $SNAPSHOTROOT
    #echo $SNAPSHOTSERVER
    # may be that there is not server and just a directory.
    if [ -z $SNAPSHOTROOT ]; then
        SNAPSHOTROOT=$SNAPSHOTSERVER
        SNAPSHOTSERVER=
    fi
fi

echo Setting up Statelite
mkdir -p $NEWROOT

# now we need to mount the rest of the system.  This is the read/write portions
# echo Mounting snapshot directories

MAXTRIES=7
ITER=0
if [ ! -e "$NEWROOT/$RWDIR" ]; then
    echo ""
    echo "This NFS root directory doesn't have a /$RWDIR directory for me to mount a rw filesystem.      You'd better create it... "
    echo ""
    /bin/sh
fi

if [ ! -e "$NEWROOT/etc/init.d/statelite" ]; then
    echo ""
    echo "$NEWROOT/etc/init.d/statelite doesn't exist.  Perhaps you didn't create this image with th    e -m statelite mode"
    echo ""
    /bin/sh
fi

mount -t tmpfs rw $NEWROOT/$RWDIR
mkdir -p $NEWROOT/$RWDIR/tmpfs
ME=`hostname`
if [ ! -z $NODE ]; then
    ME=$NODE
fi

# mount the SNAPSHOT directory here for persistent use.
if [ ! -z $SNAPSHOTSERVER ]; then
    mkdir -p $NEWROOT/$RWDIR/persistent
    MAXTRIES=5
    ITER=0
    if [ -z $MNTOPTS ]; then
        MNT_OPTIONS="nolock,rsize=32768,tcp,nfsvers=3,timeo=14"
    else
        MNT_OPTIONS=$MNTOPTS
    fi
    while ! mount $SNAPSHOTSERVER:/$SNAPSHOTROOT  $NEWROOT/$RWDIR/persistent -o $MNT_OPTIONS; do
        ITER=$(( ITER + 1 ))
        if [ "$ITER" == "$MAXTRIES" ]; then
            echo "Your are dead, rpower $ME boot to play again."
            echo "Possible problems:
1.  $SNAPSHOTSERVER is not exporting $SNAPSHOTROOT ?
2.  Is DNS set up?  Maybe that's why I can't mount $SNAPSHOTSERVER."
            /bin/sh
            exit
        fi
        RS= $(( $RANDOM % 20 ))
        echo "Trying again in $RS seconds..."
        sleep $RS
    done

    # create directory which is named after my node name
    mkdir -p $NEWROOT/$RWDIR/persistent/$ME
    ITER=0
    # umount current persistent mount
    while ! umount -l $NEWROOT/$RWDIR/persistent; do
        ITER=$(( ITER + 1 ))
        if [ "$ITER" == "$MAXTRIES" ]; then
            echo "Your are dead, rpower $ME boot to play again."
            echo "Cannot umount $NEWROOT/$RWDIR/persistent."
            /bin/sh
            exit
        fi
        RS= $(( $RANDOM % 20 ))
        echo "Trying again in $RS seconds..."
        sleep $RS
    done

    # mount persistent to server:/rootpath/nodename
    ITER=0
    while ! mount $SNAPSHOTSERVER:/$SNAPSHOTROOT/$ME  $NEWROOT/$RWDIR/persistent -o $MNT_OPTIONS; do
        ITER=$(( ITER + 1 ))
        if [ "$ITER" == "$MAXTRIES" ]; then
            echo "Your are dead, rpower $ME boot to play again."
            echo "Possible problems: cannot mount to $SNAPSHOTSERVER:/$SNAPSHOTROOT/$ME."
            /bin/sh
            exit
        fi
        RS= $(( $RANDOM % 20 ))
        echo "Trying again in $RS seconds..."
        sleep $RS
    done
fi

# TODO: handle the dhclient/resolv.conf/ntp, etc
echo "Get to enable localdisk"
$NEWROOT/etc/init.d/localdisk
$NEWROOT/etc/init.d/statelite
READONLY=yes
export READONLY
fastboot=yes
export fastboot
keep_old_ip=yes
export keep_old_ip
mount -n --bind /dev $NEWROOT/dev
mount -n --bind /proc $NEWROOT/proc
mount -n --bind /sys $NEWROOT/sys

function getdevfrommac() {
    boothwaddr=$1
    ip link show | while read line
    do
        dev=`echo $line | egrep "^[0-9]+: [0-9A-Za-z]+" | cut -d ' ' -f 2 | cut -d ':' -f 1`
        if [ "X$dev" != "X" ]; then
            devname=$dev
        fi

        if [ "X$devname" != "X" ]; then
            hwaddr=`echo $line | egrep "^[ ]*link" | awk '{print $2}'`
            if [ "X$hwaddr" = "X$boothwaddr" ]; then
                echo $devname
            fi
        fi
    done
}


for lf in /tmp/dhclient.*.lease; do
    netif=${lf#*.}
    netif=${netif%.*}
    cp $lf  "$NEWROOT/var/lib/dhclient/dhclient-$netif.leases"
done

if [ ! -z "$ifname" ]; then
    MACX=${ifname#*:}
    ETHX=${ifname%:$MACX*}
elif [ ! -z "$netdev" ]; then
    ETHX=$netdev
    MACX=`ip link show $netdev | grep ether | awk '{print $2}'`
elif [ ! -z "$BOOTIF" ]; then
    MACX=$BOOTIF
    ETHX=$(getdevfrommac $BOOTIF)
fi

if [ ! -z "$MACX" ] && [ ! -z "$ETHX" ]; then
    if [ ! -e $NEWROOT/etc/sysconfig/network/ifcfg-$ETHX ]; then
        touch $NEWROOT/etc/sysconfig/network/ifcfg-$ETHX
    fi
    echo "DEVICE=$ETHX" > $NEWROOT/etc/sysconfig/network/ifcfg-$ETHX
    echo "BOOTPROTO=dhcp" >> $NEWROOT/etc/sysconfig/network/ifcfg-$ETHX
    echo "HWADDR=$MACX" >> $NEWROOT/etc/sysconfig/network/ifcfg-$ETHX
    echo "ONBOOT=yes" >> $NEWROOT/etc/sysconfig/network/ifcfg-$ETHX
fi

cp /etc/resolv.conf "$NEWROOT/etc/"

if [ -d "$NEWROOT/etc/sysconfig" -a ! -e "$NEWROOT/etc/sysconfig/selinux" ]; then
    echo "SELINUX=disabled" >> "$NEWROOT/etc/sysconfig/selinux"
fi

# inject new exit_if_exists
echo 'settle_exit_if_exists="--exit-if-exists=/dev/root"; rm "$job"' > $hookdir/initqueue/xcat.sh
# force udevsettle to break
> $hookdir/initqueue/work
