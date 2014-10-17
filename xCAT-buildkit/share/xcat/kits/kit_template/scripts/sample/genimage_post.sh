#!/bin/sh

rpmdir="/opt/xcat/kits/<<<buildkit_WILL_INSERT_kit_basename_HERE>>>/<<<buildkit_WILL_INSERT_kitcomponent_name_HERE>>>"

if [[ ! -z "$installroot" ]]; then
    if [ -n "`ls $installroot$rpmdir/*.deb 2> /dev/null`" ] ; then
        dpkg -i --force-all --instdir=$installroot  $installroot$rpmdir/*.deb
   
    elif [ -n "`ls $installroot$rpmdir/*.rpm 2> /dev/null`" ] ; then
        rpm --force --root $installroot -Uvh $installroot$rpmdir/*.rpm
    fi
else
    if [ -n "`ls $rpmdir/*.deb 2> /dev/null`" ] ; then
        dpkg -i --force-all $rpmdir/*.deb
    
    elif [ -n "`ls $rpmdir/*.rpm 2> /dev/null`" ] ; then
        rpm --force -Uvh $rpmdir/*.rpm
    fi
fi

exit 0
