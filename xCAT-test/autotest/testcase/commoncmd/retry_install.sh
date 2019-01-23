#!/bin/bash

declare -i installsuccess=0
declare -i a=0
declare -i tryreinstall=1
node=$1
osimage=$2

if [ $# -eq 3 ];
then
    times=$3+1
    echo "Try to retry rinstall $3 times ......"
else
    times=6
    echo "Try to retry rinstall 5 times ......" 
fi


for (( tryreinstall = 1 ; tryreinstall < $times ; ++tryreinstall ))
do
    echo "Try to install $node on the $tryreinstall time..."

    echo "rinstall $node osimage=$osimage"
    rinstall $node osimage=$osimage
    if [ $? != 0 ];then
        echo "rinstall failed, double check xcat command rinstall to see if it is a bug..."
        exit 1
    fi

    #sleep while for installation.
    sleep 360
    while [ ! `lsdef -l $node|grep status|grep booted` ]
    do 
        sleep 10
        echo "The status is not booted..." 
        a=++a 
        if [ $a -gt 400 ];then
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
        echo "The provision succeed on the $tryreinstall time....."
        installsuccess=1
        break
    fi

done       

if [ $installsuccess -eq 1 ];then
    echo "The provision succeed......"
    exit 0 
else
    echo "The provision failed......"
    exit 1
fi
