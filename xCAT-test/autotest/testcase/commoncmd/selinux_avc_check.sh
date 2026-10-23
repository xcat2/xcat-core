#!/bin/sh
# Report the SELinux denials that xCAT is answerable for, out of the audit records since
# a start time.
#
# A cluster denies things xCAT has nothing to do with. On an idle enforcing management
# node httpd asks the kernel for net_admin on itself every ten seconds, and the base
# policy carries no dontaudit rule for that shape, so a two hour window holds hundreds of
# denials that no change to xCAT can remove. 1034 denials were counted on one node in one
# day, of which 817 were that one shape. "The window holds no denial" is therefore not a
# test xCAT can pass. This script keeps the denials whose subject program or object path
# belongs to xCAT, and counts those.
#
# ausearch reads the journal unless it is told otherwise, and on el10 the journal carries
# no audit records, so --input-logs is not optional: without it the search returns 0
# records and every answer is "clean".
#
# A time window cannot say whether an empty answer means a quiet node or a broken
# search, and -ts has one second of granularity, so a denial in the second a case starts
# lands in that case's window. A checkpoint file is an offset: nothing since the
# checkpoint has one meaning, there is no format to reject, and two cases cannot share a
# record. Prefer --init and --since. The -ts form stays for the keywords boot and today,
# where the window is not a case boundary.
#
# audit 4.0.3 rejects the output of date "+%x %T" and names the format on stderr, which
# the pipeline below discards, so a window that holds records reads as empty. Measured on
# an enforcing el10 node: "-ts 10/21/2026 20:59:08" returned 0 records, "-ts 20:59:08"
# returned 22 and "-ts today" returned 4006.
#
# Usage:
#   selinux_avc_check.sh --init <file>          start a window, print the records it read
#   selinux_avc_check.sh --since <file>         report the denials after that window
#   selinux_avc_check.sh <ausearch -ts value>   search a time window and report
#   selinux_avc_check.sh --classify             read raw records on stdin
#
# Prints: BASELINE=<records read> for --init. AVC=<all denials> XCAT_AVC=<ours> for a
#         report, then the records it kept. The -ts form adds SEARCHED=<records>.
# Exits:  0 when it kept none, 1 when it kept any, 2 on a usage error.

# Subjects: the programs xCAT runs. Objects: the directories xCAT owns.
XCAT_AVC_COMM='xcatd|genimage|packimage|nodeset|mknb|makedhcp|makedns|makehosts|makeknownhosts|copycds|liteimg|xdsh|xdcp|xcatprobe|xcatconfig'
XCAT_AVC_PATH='/opt/xcat|/xcatpost|/tftpboot|/install|/var/log/xcat|/etc/xcat|/var/lib/xcat'

selinux_avc_classify()
{
    grep -E "(comm|exe)=\"[^\"]*(${XCAT_AVC_COMM})[^\"]*\"|(path|name)=\"[^\"]*(${XCAT_AVC_PATH})"
}

# Report the denials ausearch answered with. An error message is not a clean window:
# ausearch prints the records, or '<no matches>', or nothing at all when it has read to
# the end of the log, and anything else is a failure of the search.
selinux_avc_count()
{
    denials=$1
    noise=$(printf '%s\n' "$denials" | grep -v -e '^type=' -e '^<no matches>$' -e '^$')
    if [ -n "$noise" ]; then
        echo "AVC=? XCAT_AVC=?"
        echo "ausearch answered neither a record nor '<no matches>': $noise" >&2
        return 2
    fi

    all=$(printf '%s\n' "$denials" | grep -c '^type=')
    kept=$(printf '%s\n' "$denials" | selinux_avc_classify)
    ours=$(printf '%s\n' "$kept" | grep -c '^type=')

    echo "AVC=$all XCAT_AVC=$ours"
    [ "$ours" -eq 0 ] && return 0
    printf '%s\n' "$kept"
    return 1
}

# Consume every record written so far, so the checkpoint names this moment. BASELINE
# counts them: on a running node a zero means the search reads nothing, not that the node
# is quiet, and the checkpoint file is then not written.
selinux_avc_init()
{
    checkpoint=$1
    [ -n "$checkpoint" ] || return 2

    rm -f "$checkpoint"
    records=$(ausearch --input-logs --checkpoint "$checkpoint" -ts today --raw 2>&1 \
        | grep -c '^type=')
    echo "BASELINE=$records"
    return 0
}

selinux_avc_since()
{
    checkpoint=$1
    [ -n "$checkpoint" ] || return 2

    selinux_avc_count "$(ausearch --input-logs -m AVC,USER_AVC \
        --checkpoint "$checkpoint" --raw 2>&1)"
}

# The -ts form keeps the two-query discriminator: an empty narrow window with records
# today is a quiet node, an empty window in both is a search that reads nothing.
selinux_avc_report()
{
    since=$1
    [ -n "$since" ] || return 2

    searched=$(ausearch --input-logs -ts "$since" --raw 2>/dev/null | grep -c '^type=')
    if [ "$searched" -eq 0 ]; then
        today=$(ausearch --input-logs -ts today --raw 2>/dev/null | grep -c '^type=')
        if [ "$today" -eq 0 ]; then
            echo "SEARCHED=0 AVC=0 XCAT_AVC=0"
            echo "no audit record since '$since' and none today. ausearch takes a bare HH:MM:SS." >&2
            return 2
        fi
    fi

    echo "SEARCHED=$searched"
    selinux_avc_count "$(ausearch --input-logs -m AVC,USER_AVC -ts "$since" --raw 2>&1)"
}

# Sourced by the bats test, which calls the functions directly.
if [ "$(basename "$0")" = selinux_avc_check.sh ]; then
    case $1 in
        --classify) selinux_avc_classify ;;
        --init)     selinux_avc_init "$2" ;;
        --since)    selinux_avc_since "$2" ;;
        '')         echo "usage: $0 --init|--since <file> | <ausearch -ts value>" >&2; exit 2 ;;
        *)          selinux_avc_report "$1" ;;
    esac
fi
