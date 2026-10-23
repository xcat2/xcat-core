#!/bin/sh
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

# Triggered by udev and starts rsyslogd with bootparameters

type getarg >/dev/null 2>&1 || . /lib/dracut-lib.sh

# A COLON DOES NOT MEAN IPv6. An IPv4 address or a hostname with a port has one
# colon; an IPv6 literal has at least two. This is a second copy of the rule in
# xCAT/postscripts/syslog, because this script runs inside the dracut initramfs
# and cannot source the postscript.
format_syslog_server() {
    case "$1" in
        \[*)   printf '%s\n' "$1" ;;
        *:*:*) printf '[%s]\n' "$1" ;;
        *)     printf '%s\n' "$1" ;;
    esac
}

rsyslog_config() {
    local server
    server=$(format_syslog_server "$1")
    shift
    local syslog_template=$1
    shift
    local filters=$*
    local filter=
    local confline=

    cat $syslog_template

#    for filter in $filters; do
#        echo "${filter} @${server}"
#    done

    # In dracut 33, default rsyslogd configuration does not use journald. Then when
    # rsyslog in debug mode, it causes `/dev/log` is not available after switch_root (#4929)
    echo "\$ModLoad imjournal"
    echo "\$OmitLocalLogging on"
    echo "\$IMJournalStateFile imjournal.state"

    if [ -n "$filters" ];then
        confline="${filters}";
    else
        confline="*.*"
    fi

    if [ -n "$server" ];then
       confline="$confline @${server}"
    else
       confline="$confline /var/log/messages"
    fi

    echo "$confline"
#       echo "*.* /tmp/syslog"
}

[ -f /tmp/syslog.server ] && read server < /tmp/syslog.server
[ -f /tmp/syslog.filters ] && read filters < /tmp/syslog.filters
[ -z "$filters" ] && filters="kern.*"
[ -f /tmp/syslog.conf ] && read conf < /tmp/syslog.conf
[ -z "$conf" ] && conf="/etc/rsyslog.conf" && echo "$conf" > /tmp/syslog.conf

template=/etc/templates/rsyslog.conf
if [ -n "$server" ]; then
    rsyslog_config "$server" "$template" "$filters" > $conf
    rsyslogd -i /var/run/syslogd.pid
fi
