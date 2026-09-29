#!/bin/sh
#
# check_provisioning_source.sh <compute node> <service node>
# check_provisioning_source.sh --count <ip>
#
# Answer which server sent the compute node its boot payload.
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
# compute node's address on the server that answered them. The service node must have served the
# compute node, and the management node must have served it nothing.
#
# Scope: the PXE ROM exchange hands out xcat/xnba.kpxe over TFTP and httpd never sees it.
# xnba.kpxe is the same binary on both servers, so it decides nothing about the fetch source.
#
# Run this on the management node. It reads the service node's log with "xdsh -e", which copies
# this script to the service node and runs it there with --count.

set -u

TOKEN=XCAT_HTTPD_REQUESTS

# The first argument to --count is the address to count. Every readable candidate log is read:
# the combined format puts the client address in field 1, and the Debian per-vhost format puts
# the vhost there and the client in field 2.
count_local_requests()
{
    ip="$1"
    logs=""
    for f in ${XCAT_HTTPD_ACCESS_LOG:-} \
             /var/log/httpd/access_log \
             /var/log/apache2/access.log \
             /var/log/apache2/access_log \
             /var/log/apache2/other_vhosts_access.log
    do
        [ -r "$f" ] || continue
        logs="$logs $f"
    done

    if [ -z "$logs" ]; then
        echo "$TOKEN nolog 0 0"
        return 0
    fi

    # shellcheck disable=SC2086
    awk -v ip="$ip" -v token="$TOKEN" \
        '$1 == ip || $2 == ip { n++ } END { print token, "ok", n+0, NR+0 }' $logs
}

# xdsh prefixes each line with the node name, so read the fields after the token.
read_counts()
{
    awk -v token="$TOKEN" '
        { for (i = 1; i <= NF; i++) if ($i == token) { print $(i+1), $(i+2), $(i+3); exit } }
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
    count_local_requests "${2:-}"
    exit 0
fi

CN="${1:-}"
SN="${2:-}"
if [ -z "$CN" ] || [ -z "$SN" ]; then
    echo "provisioning source error: usage: $0 <compute node> <service node>" >&2
    exit 2
fi

SELF=$(readlink -f "$0")
MN=$(hostname)

CN_IP=$(node_address "$CN")
if [ -z "$CN_IP" ]; then
    echo "provisioning source error: $CN has no address, so no log can be read for it" >&2
    exit 1
fi

MN_COUNTS=$(count_local_requests "$CN_IP" | read_counts)
SN_COUNTS=$(xdsh "$SN" -e "$SELF" --count "$CN_IP" 2>&1 | read_counts)

set -- $MN_COUNTS
MN_STATE="${1:-none}" MN_REQ="${2:-0}" MN_LINES="${3:-0}"
set -- $SN_COUNTS
SN_STATE="${1:-none}" SN_REQ="${2:-0}" SN_LINES="${3:-0}"

echo "$SN served $CN $SN_REQ request(s) (log $SN_STATE, $SN_LINES lines)"
echo "$MN served $CN $MN_REQ request(s) (log $MN_STATE, $MN_LINES lines)"

RC=0

if [ "$SN_STATE" != ok ]; then
    echo "provisioning source error: no httpd access log could be read on $SN" >&2
    RC=1
fi

# The management node provisioned the service node over http, so its log is never empty on a
# hierarchical run. An empty log cannot show that the management node served nothing.
if [ "$MN_STATE" != ok ] || [ "$MN_LINES" -eq 0 ]; then
    echo "provisioning source error: no httpd access log with entries could be read on $MN" >&2
    RC=1
fi

if [ "$RC" -eq 0 ] && [ "$SN_REQ" -eq 0 ]; then
    echo "provisioning source error: $SN served $CN nothing, so it did not provision it" >&2
    RC=1
fi

# Count requests, not bytes. A 304 or a HEAD carries no body, so the management node can answer
# for the compute node and still log 0 bytes.
if [ "$RC" -eq 0 ] && [ "$MN_REQ" -gt 0 ]; then
    echo "provisioning source error: $MN answered $MN_REQ request(s) for $CN, so this provision was flat" >&2
    RC=1
fi

if [ "$RC" -eq 0 ]; then
    echo "provisioning source ok: $SN served $CN and $MN served it nothing"
fi

exit "$RC"
