#!/bin/bash

file1=$1
file2=$2
tmp_diff_file=$3
rm -rf $tmp_diff_file
echo "copy /opt/xcat/share/xcat/tools/autotest/testcase/xcat_inventory/templates/diff/diff.result to $tmp_diff_file and modify compare file name in $tmp_diff_file"
cp /opt/xcat/share/xcat/tools/autotest/testcase/xcat_inventory/templates/diff/diff.result $tmp_diff_file
echo "copy command exit code $?"
sed -i "s|#FILE1#|$file1|g" $tmp_diff_file
echo "sed command exit code $?"
sed -i "s|#FILE2#|$file2|g" $tmp_diff_file
echo "sed command exit code $?"
