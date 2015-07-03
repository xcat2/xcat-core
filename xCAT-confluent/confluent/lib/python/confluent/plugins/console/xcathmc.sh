#!/bin/bash
# export XCATSSLVER for SLES 11.  Other OS can work without this setting.
if [ -r /etc/SuSE-release ]; then
  ver=`grep 'VERSION' /etc/SuSE-release | awk -F= '{print $2}' | sed 's/ //g'`
  if [ "$ver" = "11" ]; then
    export XCATSSLVER=TLSv1
  fi
fi
exec /opt/xcat/share/xcat/cons/hmc $CONFLUENT_NODE
