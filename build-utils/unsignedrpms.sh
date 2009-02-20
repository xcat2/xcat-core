# Check if the given rpm is not signed, and display its file name if not signed.
# This would normally be run from find, e.g.: find . -type f -name '*.rpm' -exec ~/unsignedrpms.sh {} \;

count=`rpm -qip $1 2>/dev/null | grep -c 'DSA/SHA1'`
#echo "count=$count"
if [ $count -eq 0 ]; then
        echo $1
fi
