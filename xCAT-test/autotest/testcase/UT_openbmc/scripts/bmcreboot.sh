#!/bin/sh

if [[ -z ${1} ]]; then
    echo "Provide the name of the node as the first argument of this script"
    exit 1
fi
NODE=${1}

if [[ -z ${2} ]]; then
    echo "Provide the name of the log file as the second argument of this script"
    exit 1
fi
LOGFILE=$2

if [[ -z ${3} ]]; then
    echo "Provide either PERL or PYTHON as the third argument of this script"
    exit 1
fi

if [[ ${3} == "PERL" ]]; then
   echo "Running the test in PERL"
   unset XCAT_OPENBMC_PYTHON
elif [[ ${3} == "PYTHON" ]]; then
   echo "Running the test in PYTHON"
   export XCAT_OPENBMC_PYTHON=YES
else
   echo "UNKNOWN SELECTED!"
   exit 1
fi

ITERATIONS=20
SLEEP_TIME=2

# Turn off debug mode....
#
chdef -t site clustersite xcatdebugmode=

# Create a new log file
date > $LOGFILE

rpower $NODE bmcstate

# Reboot the bmc
rpower $NODE bmcreboot | tee -a $LOGFILE 2>&1

counter=1
ready_cnt=0
while [[ $counter -le $ITERATIONS ]]; do
   sleep $SLEEP_TIME
   RC=`rpower $NODE bmcstate >> $LOGFILE 2>&1 ; echo $?`
   echo "Count: $counter, RC: $RC"
    ((counter++))
   if [[ $RC == 0 ]]; then
       ((ready_cnt++))
       if [[ $ready_cnd > 2 ]]; then
           echo "Leaving loop...."
           break
       fi
   fi
done

echo "All done!"
