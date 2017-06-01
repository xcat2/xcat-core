#!/bin/bash

flag=$1
mnhn=$2
cnhn=$3

if [ $flag = "-s" ]; then
    cnip=`lsdef $cnhn -i bmc -c | awk -F '=' '{print $2}'`
    echo $cnip > "/tmp/simulator"
    mnip=`ping $mnhn -c 1 | grep "64 bytes from" |awk -F'(' '{print $2}'|awk -F')' '{print $1}'`
    chdef $cnhn bmc=$mnip
elif [ $flag = "-c" ]; then
    cnip=`cat /tmp/simulator`
    chdef $cnhn bmc=$cnip
    process=`ps aux | grep "simulator" | grep "python" | awk -F ' ' '{print $2}'`
    kill $process
    rm -rf "openbmc_simulator"
fi
exit $?
