root=1
rootok=1
IFACES=eth0 #THIS WILL SOURCE FROM /procm/cmdline if genimage -i argument omitted, TODO
netroot=xcat
echo '[ -e $NEWROOT/proc ]' > /initqueue-finished/xcatroot.sh
