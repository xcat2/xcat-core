#!/bin/bash

os=`cat /etc/*release*`

if [[ "$os" =~ "Red Hat" ]] || [[ "$os" =~ "suse" ]]; then
    yum install git
    if [ $? != 0 ]; then
        echo "Install git Failed." >> $log_file
        exit 1
    fi
elif [[ "$os" =~ "ubuntu" ]]; then
    apt-get install git
    if [ $? != 0 ]; then
        echo "Install git Failed." >> $log_file
        exit 1
    fi
fi

cd 

git clone git@github.com:xuweibj/openbmc_simulator.git

exit $?

