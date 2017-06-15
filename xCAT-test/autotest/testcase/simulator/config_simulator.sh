#!/bin/bash

flag=$1
mnhn=$2
cnhn=$3
nodes=$4

mnip=`ping $mnhn -c 1 | grep "64 bytes from" |awk -F'(' '{print $2}'|awk -F')' '{print $1}'`
if [ $nodes ]; then
    nic=`ip -4 -o a | grep $mnip | awk -F ' ' '{print $2}'`

    if [ $nodes = "1000" ]; then
        range=`echo $(echo 10.100.{1..10}.{1..100})`
    elif [ $nodes = "5000" ]; then
        range=`echo $(echo 10.100.{1..50}.{1..100})`
    else
        range=`echo $(echo 10.100.{1..10}.{1..10})`
    fi
fi

if [ $flag = "-s" ]; then
    if [ $nodes ]; then
        lsdef $cnhn -z > /tmp/$cnhn.stanza
        rmdef $cnhn

        /root/openbmc_simulator/simulator -n $nic -r $range 

        if [ $nodes = "1000" ]; then
            chdef -t group $cnhn mgt=openbmc bmc="|\D+(\d+)$|10.100.(1+((\$1)/100)).((\$1)%100+1)|" bmcusername=root bmcpassword=0penBmc
            chdef simulator_test_[0-999] groups=$cnhn
        elif [ $nodes = "5000" ]; then
            chdef -t group $cnhn mgt=openbmc bmc="|\D+(\d+)$|10.100.(1+((\$1)/100)).((\$1)%100+1)|" bmcusername=root bmcpassword=0penBmc
            chdef simulator_test_[0-4999] groups=$cnhn
        else 
            chdef -t group $cnhn mgt=openbmc bmc="|\D+(\d+)$|10.100.(1+((\$1)/10)).((\$1)%10+1)|" bmcusername=root bmcpassword=0penBmc
            chdef simulator_test_[0-99] groups=$cnhn
        fi
    else 
        cnip=`lsdef $cnhn -i bmc -c | awk -F '=' '{print $2}'`
        echo $cnip > "/tmp/simulator"
        mnip=`ping $mnhn -c 1 | grep "64 bytes from" |awk -F'(' '{print $2}'|awk -F')' '{print $1}'`
        chdef $cnhn bmc=$mnip
        /root/openbmc_simulator/simulator
    fi
elif [ $flag = "-c" ]; then
    if [ $nodes ]; then
        /root/openbmc_simulator/simulator -c -n $nic -r $range
        rmdef $cnhn
        cat /tmp/$cnhn.stanza | mkdef -z
    else 
        /root/openbmc_simulator/simulator -c
        cnip=`cat /tmp/simulator`
        chdef $cnhn bmc=$cnip
    fi

    rm -rf /root/openbmc_simulator
fi
exit $?
