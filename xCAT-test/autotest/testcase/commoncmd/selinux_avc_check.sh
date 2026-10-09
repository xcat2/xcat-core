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
# Usage:
#   selinux_avc_check.sh <ausearch -ts value>   search and report
#   selinux_avc_check.sh --classify             read raw records on stdin
#
# Prints: SEARCHED=<records in the window> AVC=<all denials> XCAT_AVC=<ours>
#         then the records it kept.
# Exits:  0 when it kept none, 1 when it kept any, 2 on a usage error.

# Subjects: the programs xCAT runs. Objects: the directories xCAT owns.
XCAT_AVC_COMM='xcatd|genimage|packimage|nodeset|mknb|makedhcp|makedns|makehosts|makeknownhosts|copycds|liteimg|xdsh|xdcp|xcatprobe|xcatconfig'
XCAT_AVC_PATH='/opt/xcat|/xcatpost|/tftpboot|/install|/var/log/xcat|/etc/xcat|/var/lib/xcat'

selinux_avc_classify()
{
    grep -E "(comm|exe)=\"[^\"]*(${XCAT_AVC_COMM})[^\"]*\"|(path|name)=\"[^\"]*(${XCAT_AVC_PATH})"
}

selinux_avc_report()
{
    since=$1
    [ -n "$since" ] || return 2

    searched=$(ausearch --input-logs -ts "$since" --raw 2>/dev/null | grep -c '^type=')
    denials=$(ausearch --input-logs -m AVC,USER_AVC -ts "$since" --raw 2>/dev/null)
    all=$(printf '%s\n' "$denials" | grep -c '^type=')
    kept=$(printf '%s\n' "$denials" | selinux_avc_classify)
    ours=$(printf '%s\n' "$kept" | grep -c '^type=')

    echo "SEARCHED=$searched AVC=$all XCAT_AVC=$ours"
    [ "$ours" -eq 0 ] && return 0
    printf '%s\n' "$kept"
    return 1
}

# Sourced by the bats test, which calls the functions directly.
if [ "$(basename "$0")" = selinux_avc_check.sh ]; then
    case $1 in
        --classify) selinux_avc_classify ;;
        '')         echo "usage: $0 <ausearch -ts value>" >&2; exit 2 ;;
        *)          selinux_avc_report "$1" ;;
    esac
fi
