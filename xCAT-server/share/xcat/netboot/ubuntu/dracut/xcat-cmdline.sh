root=1
rootok=1
netroot=xcat
# dracut-initqueue ends at once while initqueue/finished is empty, before the settled hook that
# brings the root online runs.
echo '[ -e $NEWROOT/proc ]' > "$hookdir/initqueue/finished/xcatroot.sh"
