#!/bin/bash
# IBM(c) 2010 EPL license http://www.eclipse.org/legal/epl-v10.html
#(C)IBM Corp

#
#-----------------------------------------------------------------------------
#
#cleanup_nvm.sh
# It is found that in some case, there will be nvram entries wrote that block
#     the normal booting for Tuleta server running OPAL mode and OpenPOWER server.
# This script is used to clean up the nvram entries within host OS, can be run as
#     a postscript for xCAT.
#
#-----------------------------------------------------------------------------

tries=0
while true; do

    entries=`nvram --print-config | grep "^petitboot"`

    if [ $? -ne 0 ]; then
        if [ $tries -gt 0 ]; then
            echo "The nvram cleaning up is done"
        else
            echo "No nvram entry found that is releated to petitboot"
        fi
        exit 0
    fi

    if [ $tries -ge 5 ]; then
        echo "The nvram entries can not be cleaned up for $tries times"
        echo "$entries"
        exit 1
    fi
    while read -r entry
    do
        entry_name="${entry%%=*}="
        `nvram --update-config="$entry_name"`
    done < <(echo "$entries")
    tries=$(($tries+1))
done
