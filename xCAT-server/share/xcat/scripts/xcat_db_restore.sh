#!/bin/sh
#-- script restores xCAT database from directory with csv files,
#-- created by xcat_db_backup.sh script
#-- jurij.sikorsky@t-systems.cz

dirname=$1

if [[ -z $dirname ]]; then echo "Usage: $0 {backup dir}"; exit 1; fi

for tab in $dirname/*.csv; do 
  echo $tab
  tabrestore $tab
done
