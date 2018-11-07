#!/bin/sh
#script to update nodelist.nodestatus during provision

XCAT="$(getarg XCAT=)"
STATEMNT="$(getarg STATEMNT=)"
MASTER=`echo $XCAT |awk -F: '{print $1}'`

getarg nonodestatus
NODESTATUS=$?

XCATIPORT="$(getarg XCATIPORT=)"
if [ $? -ne 0 ]; then
XCATIPORT="3002"
fi

log_label="xcat.deployment"
[ "$xcatdebugmode" = "1" -o "$xcatdebugmode" = "2" ] && SYSLOGHOST="" || SYSLOGHOST="-n $MASTER"
logger $SYSLOGHOST -t $log_label -p local4.info "=============deployment starting===================="
logger $SYSLOGHOST -t $log_label -p local4.info "Starting xcat-premount..."
[ "$xcatdebugmode" > "0" ] && logger $SYSLOGHOST -t $log_label -p local4.debug "MASTER=$MASTER XCATIPORT=$XCATIPORT NODESTATUS=$NODESTATUS"
if [ $NODESTATUS -ne 0 ];then
    logger $SYSLOGHOST -t $log_label -p local4.info "Sending request to $MASTER:$XCATIPORT for changing status to netbooting..."
/tmp/updateflag $MASTER $XCATIPORT "installstatus netbooting"
fi
