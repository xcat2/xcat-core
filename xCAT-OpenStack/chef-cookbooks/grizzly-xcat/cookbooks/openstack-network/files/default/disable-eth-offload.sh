#!/usr/bin/env bash
#
# Copyright (C) 2013 ATT Services, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at:
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
### BEGIN INIT INFO
# Provides:          disable-eth-offload
# Required-Start:    $network
# Required-Stop:     $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Disable NIC Offloads
### END INIT INFO

function check_setting() {
  setting_on="false"
  INTERFACE=$1
  SETTING=$2
  if [ -z $INTERFACE ] || [ -z $SETTING ]; then
    echo "You didn't call check_setting right, it needs interfaces as \$1 and setting as \$2"
    exit 1
  fi

  if [ $LOGGING == "true" ]; then
    ethtool -k $INTERFACE | grep $SETTING | grep ": on"
  fi

  ethtool -k $INTERFACE | grep $SETTING | grep ": on" > /dev/null
  if [ $? == 0 ]; then
    setting_on="true"
  fi
}

start () {

    INTERFACES=$( grep auto /etc/network/interfaces | grep -v lo | awk '{ print $NF }' )
    declare -A SETTINGS
    SETTINGS=( ["lro"]="large-receive-offload" ["tso"]="tcp-segmentation-offload" ["gso"]="generic-segmentation-offload" ["gro"]="generic-receive-offload" )
    ETHTOOL_BIN="/sbin/ethtool"
    LOGGING="false"
    setting_on="false"

    for interface in $INTERFACES; do
      for setting in "${!SETTINGS[@]}"; do
        check_setting $interface ${SETTINGS[$setting]}
        if [ $setting_on == "true" ]; then
          $ETHTOOL_BIN -K $interface $setting off
          if [ $LOGGING == "true" ]; then
            echo "RUNNING: $ETHTOOL_BIN -K $interface $setting off"
          fi
        fi
      done
    done
}

case $1 in
    start)
        start
        ;;
    *)
        echo "Usage: $0 {start}" >&2
        exit 1
        ;;
esac

exit 0

