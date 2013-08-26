#!/bin/sh
#script to update nodelist.nodestatus during provision

MASTER=`echo $XCAT |awk -F: '{print $1}'`

getarg nonodestatus
NODESTATUS=$?

XCATIPORT="$(getarg XCATIPORT=)"
if [ $? -ne 0 ]; then
XCATIPORT="3002"
fi



if [ $NODESTATUS -ne 0 ];then
/tmp/updateflag $MASTER $XCATIPORT "installstatus netbooting"
fi
