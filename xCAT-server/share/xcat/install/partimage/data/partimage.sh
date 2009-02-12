#!/bin/sh
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
set -x
# Need to get:
# NFS_SERVER
# NFS_DIR
# xCATd IP
# Image profile

#initrd=xcat/partimage/x86/nbfs.x86.gz quiet console=ttyS0,19200n8r xcatd=172.10.0.1:3001 mode=restore|capture pcfg=172.10.0.1:/install/autoinst/x3455001
# grab all the arguments from the kernel command line.
#  They are:
#  PCFG (partimage config) is a mount point or wget: 
#	e.g. 172.10.0.1:/install/autoinst/<nodename>
#  XCATDEST:
#  	e.g. xcatd:172.10.0.1:3001
#  MODE
#	e.g. restore (to restore a previously saved file)
#       e.g. capture (to capture an image)
for parm in `cat /proc/cmdline`; do 
	key=`echo $parm|awk -F= '{print $1}'`
	if [ "$key" == "pcfg" ]; then
		PCFG=`echo $parm | awk -F= '{print $2}'`
	elif [ "$key" == "xcatd" ]; then
		XCATDEST=`echo $parm | awk -F= '{print $2}'`
	elif [ "$key" == "mode" ]; then
		MODE=`echo $parm | awk -F= '{print $2}'`
	fi	
done

export XCATPORT=3001
if [ ! -z "$XCATDEST" ]; then
	export XCATMASTER=`echo $XCATDEST | awk -F: '{print $1}'`
	export XCATPORT=`echo $XCATDEST | awk -F: '{print $2}'`
fi


# Get the configuration file from xCAT:
wget $PCFG -O /tmp/pcfg

if [ -f "/tmp/pcfg" ]
then 
	source /tmp/pcfg
else
	echo "Error in getting $PCFG with wget!"
	sleep 30
	# drop into shell
	while :; do /bin/sh; done
fi

echo $NFS_SERVER
echo $NFS_DIR
echo $IMAGE
echo $DISK

mkdir -p /images
mount -o rw,nolock,wsize=8192,rsize=8192 $NFS_SERVER:$NFS_DIR /images/


if [ "$MODE" == "capture" ]; then
	for DISK in $DISKS
	do
		echo "Partitions for $DISK"
		/lib/ld-linux.so.2 /sbin/sfdisk -l /dev/$DISK
		echo "==="

		/bin/dd if=/dev/sda of=/images/$IMAGE-$DISK.mbr count=1 bs=512
		/lib/ld-linux.so.2 /sbin/sfdisk  /dev/$DISK -d >/images/$IMAGE-$DISK.sfdisk
		for i in `/lib/ld-linux.so.2 /sbin/sfdisk -l /dev/$DISK | grep "^/dev/$DISK" | grep -v Win95 | grep -v Extended | grep -v Empty | grep -v swap | awk '{print $1}'`; do

			PARTNAME=$(basename $i)
			OUTPUTFILE=/images/$IMAGE-$PARTNAME.gz
			echo running partimage -z1 -f3 -odb save /dev/$PARTNAME $OUTPUTFILE
			sleep 5
			/bin/partimage -z1 -f3 -odb save /dev/$PARTNAME $OUTPUTFILE
		done
		tput clear
		tput sgr0
		tput cnorm

		cd /images
		for i in *.000
		do
			mv $i ${i%%.000}
		done
	done
#
# This part of the code is for installing disks
#
elif [ "$MODE" == "restore" ]; then
	DONE=0
	OLD=""
	echo "restoring image!"
	for DISK in $DISKS	
	do
		cd /images
		for i in $IMAGE-$DISK[0-9]*.gz*
		do
			PARTNAME=${i%%.gz}
			PARTNAME=${PARTNAME##*-}	
			INPUTFILE=$i
			if [ "$DONE" == "0" ]
			then
				if [ -r $IMAGE-$DISK.sfdisk ]
				then
					# read in the disk formatting template
					/lib/ld-linux.so.2 /sbin/sfdisk /dev/$DISK <$IMAGE-$DISK.sfdisk
				fi
				if [ -r $IMAGE-$DISK.mbr ]
				then
					dd if=$IMAGE-$DISK.mbr of=/dev/$DISK
					/lib/ld-linux.so.2 /sbin/sfdisk /dev/$DISK <$IMAGE-$DISK.sfdisk
				else
					/bin/partimage -b f3 restmbr $INPUTFILE
				fi
				/lib/ld-linux.so.2 /sbin/sfdisk /dev/$DISK -R
				DONE=1
			fi
			/bin/partimage -b -f3 restore /dev/$PARTNAME $INPUTFILE
							
		done

		tput clear
		tput sgr0
		tput cnorm

		for i in `/lib/ld-linux.so.2 /sbin/sfdisk -l /dev/$DISK | grep "Linux swap" | awk '{print $1}'`; do 
			echo "Setting up swap on $i"
			mkswap $i
		done
		# go to next disk!
	done
fi
# finish with a shell

echo "Hopefully we're all done imaging now... Over to you shell!"
while :; do /bin/sh; done
