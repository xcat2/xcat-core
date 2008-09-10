#!/bin/sh
#-- script backs up xCAT database to csv files into (newly created) directory
#-- jurij.sikorsky@t-systems.cz

basedir=/scratch/xcat/backup
dirname=$basename/xcatdb-`hostname`-`date +%y%m%d-%H%M%S`
echo $dirname
mkdir $dirname
cd $dirname

for tab in `/opt/xcat/sbin/tabdump`; do 
  echo $tab
  tabdump $tab > $tab.csv
done


cd - > /dev/null

