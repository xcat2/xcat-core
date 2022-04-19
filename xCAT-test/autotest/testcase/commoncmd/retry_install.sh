#!/bin/bash

declare -i installsuccess=0
declare -i a=0
declare -i tryreinstall=1
node=$1
osimage=$2
vmhost=`lsdef $node -i vmhost -c | cut -d '=' -f 2`
times=3
wait_for_provision=30 #Min to wait for node to provision
check_status=10 #Sec to keep checking status
iterations=$wait_for_provision*60/$check_status #Iterations to check for "booted" status

if [ $# -eq 3 ];
then
    times=$3
fi

echo "Try to rinstall for $times times (allowing $wait_for_provision min for each try) ......" 

for (( tryreinstall = 1 ; tryreinstall <= $times ; ++tryreinstall ))
do
    echo "[$tryreinstall] Trying to install $node with $osimage ..."

    if [[ ! -z $vmhost ]];then
        # Display memory and active VMs on VM host, when installing on VM
        echo "Memory on vmhost $vmhost"
        ssh $vmhost free -m
        echo "Active VMs on vmhost $vmhost"
        ssh $vmhost virsh list
    fi

    echo "rinstall $node osimage=$osimage"
    rinstall $node osimage=$osimage
    if [ $? != 0 ];then
        echo "First attempt to run rinstall command failed ..."
        # First rinstall failed, try again with verbose flag
        rinstall $node osimage=$osimage -V
        if [ $? != 0 ];then
            echo "Second attempt to run rinstall command failed ..."
            exit 1
        fi
    fi

    #sleep while for installation.
    sleep 360
    while [ ! `lsdef -l $node|grep status|grep booted` ]
    do 
        sleep $check_status
        stat=`lsdef $node -i status -c | cut -d '=' -f 2`
        echo "[$a] The status is not booted... ($stat)" 
        if [ $stat = "failed" ]; then
            # Installation failed, no reason to keep checking
            break
        fi
        a=++a 
        if [ $a -gt $(($iterations + 0)) ];then
            a=0 
            break
        fi
    done

    lsdef -l $node|grep status|grep booted
    tobooted=$?
    echo "The tobooted is $tobooted"

    ping -c 2 $node
    pingable=$?
    echo "The pingable is $pingable"

    xdsh $node date
    canruncmd=$?
    echo "The canruncmd is $canruncmd"

    if [[ $canruncmd -eq 0  &&  $tobooted -eq 0  &&  $pingable -eq 0 ]];then
        echo "The provision succeeded on the $tryreinstall time....."
        installsuccess=1
        break
    fi

done       

if [ $installsuccess -eq 1 ];then
    echo "The provision succeeded......"
    exit 0 
else
    echo "The provision failed......"
    exit 1
fi
