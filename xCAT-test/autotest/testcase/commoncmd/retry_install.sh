#!/bin/bash

# How many times to ask ICMP, and how long to wait between asks. Overridable so a test can drive
# node_pingable without sleeping.
PING_TRIES=${PING_TRIES:-5}
PING_RETRY_SLEEP=${PING_RETRY_SLEEP:-2}

#--- node_pingable
# Descriptions: whether the node answers ICMP, asked more than once.
#
#   ICMP to a node is lossy for a few seconds after it finishes booting. One sample on an
#   openSUSE Leap 15.6 cluster lost 2 of 2 packets while xdsh to the same node succeeded a second
#   later; the caller ANDs both answers, so that one sample forced a second full rinstall and cost
#   401 seconds. A second run of the same cell lost 2 of 3 packets at a moment that was not the
#   decision point and passed. The difference between the two runs was which side of a
#   two-packet sample landed, not the state of the node.
#
#   So ask again before concluding. A node that never answers still reports non-pingable, because
#   that is a real defect and the caller must keep vetoing it.
# Arguments: $1 - the node
# Returns: 0 if the node answered, non-zero if it never did
#---
node_pingable() {
    local node=$1
    local i
    for (( i = 1; i <= PING_TRIES; ++i )); do
        if ping -c 2 "$node"; then
            return 0
        fi
        echo "[$i/$PING_TRIES] $node did not answer ICMP; asking again"
        if [ "$i" -lt "$PING_TRIES" ]; then
            sleep "$PING_RETRY_SLEEP"
        fi
    done
    return 1
}

# Sourcing stops here. BASH_SOURCE[0] differs from $0 only when this file is sourced, so a bats
# test can drive node_pingable without running a provisioning loop -- and without the lsdef below,
# which needs an xCAT database.
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    return 0
fi

declare -i installsuccess=0
declare -i a=0
declare -i tryreinstall=1
node=$1
osimage=$2
vmhost=`lsdef $node -i vmhost -c | cut -d '=' -f 2`
times=2
wait_for_provision=${WAIT_FOR_PROVISION:-20} #Min to wait for node to provision (overridable via WAIT_FOR_PROVISION; kept short so a boot-loop fails fast, raised only where the happy path is slow -- e.g. Ubuntu subiquity diskful)
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

    node_pingable $node
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
