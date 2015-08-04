#!/bin/sh
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

# Creates the syslog udev rules to be triggered when interface becomes online.
type getarg >/dev/null 2>&1 || . /lib/dracut-lib.sh

detect_syslog() {
    syslogtype=""
    if [ -e /sbin/rsyslogd ]; then
        syslogtype="rsyslogd"
    elif [ -e /sbin/syslogd ]; then
        syslogtype="syslogd"
    elif [ /sbin/syslog-ng ]; then
        syslogtype="syslog-ng"
    else
        warn "Could not find any syslog binary although the syslogmodule is selected to be installed. Please check."
    fi
    echo "$syslogtype"
    [ -n "$syslogtype" ]
}

#the initqueue.sh shipped does not support --online option and 
#there are some problem when processing --onetime option
#implement a patched initqueue function here, named initqueue_enhanced
initqueue_enhanced() {
    local onetime=
    local qname=
    local unique=
    local name=
    local env=
    while [ $# -gt 0 ]; do
        case "$1" in
            --onetime)
                onetime="yes";;
            --settled)
                qname="/settled";;
            --finished)
                qname="/finished";;
            --timeout)
                qname="/timeout";;
            --online)
                qname="/online";;
            --unique)
                unique="yes";;
            --name)
                name="$2";shift;;
            --env)
                env="$2"; shift;;
            *)
                break;;
        esac
        shift
    done
    
    local job=    
    if [ -z "$unique" ]; then
        job="${name}$$"
    else
        job="${name:-$1}"
        job=${job##*/}
    fi
    
    local exe= 
    exe=$1
    shift
    
    [ -x "$exe" ] || exe=$(command -v $exe)
    if [ -z "$exe" ] ; then
        echo "Invalid command"
        return 1
    fi
    
    {
        [ -n "$env" ] && echo "$env"
        echo "$exe $@"
        [ -n "$onetime" ] && echo "[ -e $hookdir/initqueue${qname}/${job}.sh ] && rm -f -- $hookdir/initqueue${qname}/${job}.sh"
    } > "/tmp/$$-${job}.sh"
    
    mv -f "/tmp/$$-${job}.sh" "$hookdir/initqueue${qname}/${job}.sh"
    [ -z "$qname" ] && >> $hookdir/initqueue/work
    
    return 0
}

[ -f /tmp/syslog.type  ] &&  read syslogtype < /tmp/syslog.type
if [ -z "$syslogtype" ]; then
    syslogtype=$(detect_syslog)
    echo $syslogtype > /tmp/syslog.type
fi
if [ -e "/sbin/${syslogtype}-start" ]; then
    #printf 'ACTION=="online", SUBSYSTEM=="net", RUN+="/sbin/initqueue --onetime /sbin/'${syslogtype}'-start $env{INTERFACE}"\n' > /etc/udev/rules.d/70-syslog.rules
    #printf 'ATTR{operstate}!="down", SUBSYSTEM=="net", RUN+="/sbin/initqueue --onetime /sbin/'${syslogtype}'-start $env{INTERFACE}"\n' > /etc/udev/rules.d/70-syslog.rules
    initqueue_enhanced --online --onetime /sbin/${syslogtype}-start     
else
    warn "syslog-genrules: Could not find binary to start syslog of type \"$syslogtype\". Syslog will not be started."
fi
