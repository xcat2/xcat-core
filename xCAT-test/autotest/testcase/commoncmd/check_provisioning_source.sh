#!/bin/sh
#
# check_provisioning_source.sh --baseline <compute node> <service node>
# check_provisioning_source.sh <compute node> <service node>
# check_provisioning_source.sh --count <ip> [<baseline spec>]
#
# Answer which server sent the compute node its boot payload during THIS run.
#
# The hierarchy cases set noderes.servicenode and read SERVICEGROUP back out of the compute
# node's xcatinfo. That records what xCAT wrote, not where the node fetched from. The management
# node, the service node and the compute node share one subnet, both dhcpd instances hold a
# reservation for the compute node, and xCAT does not arbitrate between them. The compute node
# takes whichever server answers first, so a flat provision satisfies every other assertion the
# cases make.
#
# The httpd access logs settle it. The xNBA exchange hands out an http:// filename, so the
# kernel, the initrd, the root image and the install tree are HTTP requests logged against the
# compute node's address on the server that answered them.
#
# Two things bound what counts, and without either one the answer is wrong in both directions.
# Run --baseline before provisioning: an earlier flat run leaves management-node requests for the
# same address, and counting the whole log fails a later hierarchical run for them. And only a
# request under /install or /tftpboot is a boot payload: a 404 for /favicon.ico is a request from
# the compute node that carries no payload, and it must not stand for one.
#
# Scope: the PXE ROM exchange hands out xcat/xnba.kpxe over TFTP and httpd never sees it.
# xnba.kpxe is the same binary on both servers, so it decides nothing about the fetch source.
#
# Run this on the management node. It reads the service node's log with "xdsh -e", which copies
# this script to the service node and runs it there with --count.

set -u

TOKEN=XCAT_HTTPD_REQUESTS
STATE="${XCAT_PROV_SOURCE_STATE:-/var/tmp/xcat-provisioning-source.base}"

# Every readable candidate log. The combined format puts the client address in field 1, and the
# Debian per-vhost format puts the vhost there and the client in field 2.
local_logs()
{
    for f in ${XCAT_HTTPD_ACCESS_LOG:-} \
             /var/log/httpd/access_log \
             /var/log/apache2/access.log \
             /var/log/apache2/access_log \
             /var/log/apache2/other_vhosts_access.log
    do
        [ -r "$f" ] || continue
        echo "$f"
    done
}

# Record how many lines each log holds now, as file:lines joined by commas.
baseline_local()
{
    spec=""
    for f in $(local_logs); do
        n=$(wc -l <"$f" 2>/dev/null | tr -d ' ')
        [ -n "$n" ] || n=0
        spec="$spec,$f:$n"
    done
    echo "$TOKEN base $(echo "$spec" | sed 's/^,//')"
}

# Count the boot-payload requests this address made AFTER the baseline. A log shorter than its
# baseline was rotated, so its baseline no longer locates anything and the whole file is new.
count_local_requests()
{
    ip="$1"
    spec="${2:-}"
    logs=$(local_logs | tr '\n' ' ')

    if [ -z "$logs" ]; then
        echo "$TOKEN nolog 0 0 0"
        return 0
    fi

    checked=""
    for f in $logs; do
        base=$(echo "$spec" | tr ',' '\n' | sed -n "s|^$f:||p" | head -1)
        [ -n "$base" ] || base=0
        now=$(wc -l <"$f" 2>/dev/null | tr -d ' ')
        [ -n "$now" ] || now=0
        [ "$now" -lt "$base" ] && base=0
        checked="$checked,$f:$base"
    done

    # shellcheck disable=SC2086
    awk -v ip="$ip" -v token="$TOKEN" -v bases="$(echo "$checked" | sed 's/^,//')" '
        BEGIN {
            n = split(bases, a, ",")
            for (i = 1; i <= n; i++) {
                if (a[i] == "") continue
                p = index(a[i], ":")
                if (p) base[substr(a[i], 1, p - 1)] = substr(a[i], p + 1) + 0
            }
        }
        {
            total++
            b = (FILENAME in base) ? base[FILENAME] : 0
            if (FNR <= b) next
            fresh++
            if ($1 != ip && $2 != ip) next
            path = ""
            for (i = 1; i <= NF; i++) if ($i ~ /^"(GET|HEAD|POST)$/) { path = $(i + 1); break }
            if (path ~ /^\/(install|tftpboot)\//) payload++
        }
        END { print token, "ok", payload + 0, fresh + 0, total + 0 }
    ' $logs
}

# xdsh prefixes each line with the node name, so read the fields after the token.
read_counts()
{
    awk -v token="$TOKEN" '
        { for (i = 1; i <= NF; i++) if ($i == token) { print $(i+1), $(i+2), $(i+3), $(i+4); exit } }
    '
}

read_baseline()
{
    awk -v token="$TOKEN" '
        { for (i = 1; i <= NF; i++) if ($i == token && $(i+1) == "base") { print $(i+2); exit } }
    '
}

node_address()
{
    node="$1"
    addr=$(lsdef -t node -o "$node" -i ip 2>/dev/null | sed -n 's/^[[:space:]]*ip=//p' | head -1)
    [ -n "$addr" ] || addr=$(getent ahostsv4 "$node" 2>/dev/null | awk '{ print $1; exit }')
    echo "$addr"
}

if [ "${1:-}" = "--count" ]; then
    count_local_requests "${2:-}" "${3:-}"
    exit 0
fi

if [ "${1:-}" = "--baseline-local" ]; then
    baseline_local
    exit 0
fi

MODE=check
if [ "${1:-}" = "--baseline" ]; then
    MODE=baseline
    shift
fi

CN="${1:-}"
SN="${2:-}"
if [ -z "$CN" ] || [ -z "$SN" ]; then
    echo "provisioning source error: usage: $0 [--baseline] <compute node> <service node>" >&2
    exit 2
fi

SELF=$(readlink -f "$0")
MN=$(hostname)

if [ "$MODE" = baseline ]; then
    MN_BASE=$(baseline_local | read_baseline)
    SN_BASE=$(xdsh "$SN" -e "$SELF" --baseline-local 2>&1 | read_baseline)
    if [ -z "$MN_BASE" ] || [ -z "$SN_BASE" ]; then
        echo "provisioning source error: no access log to baseline on ${MN_BASE:+$SN}${MN_BASE:-$MN}" >&2
        exit 1
    fi
    printf 'MN %s\nSN %s\n' "$MN_BASE" "$SN_BASE" >"$STATE" || exit 1
    echo "provisioning source baseline recorded in $STATE"
    exit 0
fi

# Without a baseline this cannot tell a request from this run from one an earlier run left
# behind, so it refuses rather than answering from the whole log.
if [ ! -r "$STATE" ]; then
    echo "provisioning source error: no baseline in $STATE. Run --baseline before provisioning" >&2
    exit 1
fi
MN_BASE=$(sed -n 's/^MN //p' "$STATE" | head -1)
SN_BASE=$(sed -n 's/^SN //p' "$STATE" | head -1)

CN_IP=$(node_address "$CN")
if [ -z "$CN_IP" ]; then
    echo "provisioning source error: $CN has no address, so no log can be read for it" >&2
    exit 1
fi

MN_COUNTS=$(count_local_requests "$CN_IP" "$MN_BASE" | read_counts)
SN_COUNTS=$(xdsh "$SN" -e "$SELF" --count "$CN_IP" "$SN_BASE" 2>&1 | read_counts)

set -- $MN_COUNTS
MN_STATE="${1:-none}" MN_REQ="${2:-0}" MN_NEW="${3:-0}" MN_LINES="${4:-0}"
set -- $SN_COUNTS
SN_STATE="${1:-none}" SN_REQ="${2:-0}" SN_NEW="${3:-0}" SN_LINES="${4:-0}"

echo "$SN served $CN $SN_REQ boot-payload request(s) since the baseline (log $SN_STATE, $SN_NEW new of $SN_LINES lines)"
echo "$MN served $CN $MN_REQ boot-payload request(s) since the baseline (log $MN_STATE, $MN_NEW new of $MN_LINES lines)"

RC=0

if [ "$SN_STATE" != ok ]; then
    echo "provisioning source error: no httpd access log could be read on $SN" >&2
    RC=1
fi

# An empty log makes "the management node served nothing" a property of the file, not a
# measurement. New lines are NOT required: the service node is provisioned before the baseline, so
# after it a correct hierarchical run leaves the management node's log unchanged.
if [ "$MN_STATE" != ok ] || [ "$MN_LINES" -eq 0 ]; then
    echo "provisioning source error: no httpd access log with entries could be read on $MN" >&2
    RC=1
fi

if [ "$RC" -eq 0 ] && [ "$SN_REQ" -eq 0 ]; then
    echo "provisioning source error: $SN served $CN no boot payload, so it did not provision it" >&2
    RC=1
fi

# Count requests, not bytes. A 304 or a HEAD carries no body, so the management node can answer
# for the compute node and still log 0 bytes.
if [ "$RC" -eq 0 ] && [ "$MN_REQ" -gt 0 ]; then
    echo "provisioning source error: $MN answered $MN_REQ boot-payload request(s) for $CN, so this provision was flat" >&2
    RC=1
fi

if [ "$RC" -eq 0 ]; then
    echo "provisioning source ok: $SN served $CN and $MN served it nothing"
fi

exit "$RC"
