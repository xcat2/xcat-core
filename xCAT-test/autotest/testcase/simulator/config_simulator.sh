#!/bin/bash

flag=$1  # -s:setup simulator -c:clear simulator env
mnhn=$2  # MN hostname
cnhn=$3  # CN hostname
username=$4  # bmcusername
password=$5  # bmcpassword
nodes=$6  # number of IPs want to config
delay_type=$7 # delay type "constant" or "random"
delay_time=$8 # delay time

if [ $nodes -gt 10000 ]; then
    echo "Unsupported number of nodes: $nodes"
    exit 1
fi

mnip=`ping $mnhn -c 1 | grep "64 bytes from" |awk -F'(' '{print $2}'|awk -F')' '{print $1}'`
if [ $nodes ]; then
    nic=`ip -4 -o a | grep $mnip | awk -F ' ' '{print $2}'`

    ((a=$nodes/100))
    ((b=$nodes%100))
    if [ $b -eq 0 ]; then
        b=100
    fi
    range=`for((i=1;i<=$a;i++)); do for((m=1;m<=$b;m++)); do echo -n "10.100.$i.$m ";done; done`
fi

if [ $flag = "-s" ]; then
    os=`cat /etc/*release*`
    if [[ "$os" =~ "Red Hat" ]] || [[ "$os" =~ "suse" ]]; then
        yum install git -y
        if [ $? != 0 ]; then
            echo "Install git Failed"
            exit 1
        fi
    elif [[ "$os" =~ "ubuntu" ]]; then
        apt-get install git -y
        if [ $? != 0 ]; then
            echo "Install git Failed"
            exit 1
        fi
    fi

    cd /root/ && git clone git@github.com:xuweibj/openbmc_simulator.git

    if [ $nodes ] && [ $nodes -gt 0 ]; then
        lsdef $cnhn -z > /tmp/$cnhn.stanza
        rmdef $cnhn

        if [ $delay_type ] && [ $delay_time ]; then
            option_string="-d $delay_type -t $delay_time -n $nic -r $range"
        else
            option_string="-n $nic -r $range"
        fi
        /root/openbmc_simulator/simulator $option_string
        if [ $? != 0 ]; then
            echo "Start simulator Failed"
            exit 1
        fi

        node_end=$[nodes-1]
        chdef -t group $cnhn mgt=openbmc bmc="|\D+(\d+)$|10.100.(1+((\$1)/100)).((\$1)%100+1)|" bmcusername=$username bmcpassword=$password
        chdef simulator_test[0-$node_end] groups=$cnhn  # use CN hostname as group, so when run command against CN will rpower against all nodes added here
    else
        cnip=`lsdef $cnhn -i bmc -c | awk -F '=' '{print $2}'`
        echo $cnip > "/tmp/simulator"
        mnip=`ping $mnhn -c 1 | grep "64 bytes from" |awk -F'(' '{print $2}'|awk -F')' '{print $1}'`
        chdef $cnhn bmc=$mnip
        if [ $delay_type ] && [ $delay_time ]; then
            /root/openbmc_simulator/simulator -d $delay_type -t $delay_time
        else
            /root/openbmc_simulator/simulator
        fi
    fi
elif [ $flag = "-c" ]; then
    if [ $nodes ] && [ $nodes -gt 0 ]; then
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
