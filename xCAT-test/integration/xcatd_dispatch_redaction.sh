#!/bin/sh

set -eu
umask 077

fail()
{
    echo "$*" >&2
    exit 1
}

[ "$(id -u)" -eq 0 ] || fail 'Run this test as root on a management node.'
log=/var/log/xcat/cluster.log
[ -r "$log" ] || fail "Cannot read $log"
work=$(mktemp -d /tmp/xcat-redaction.XXXXXXXX)
node=$(printf '%s' "xcat-redaction-${work##*.}" | tr '[:upper:]' '[:lower:]')
restore_debug=0
remove_node=0

cleanup()
{
    status=$?
    trap - 0 HUP INT TERM
    if [ "$restore_debug" -eq 1 ]; then
        chdef -t site "xcatdebugmode=$debug" || status=1
    fi
    if [ "$remove_node" -eq 1 ]; then
        rmdef "$node" || status=1
    fi
    rm -rf "$work" || status=1
    exit "$status"
}
trap cleanup 0
trap 'exit 1' HUP INT TERM

lsdef -t site -i xcatdebugmode > "$work/site"
debug=$(sed -n 's/^[[:space:]]*xcatdebugmode=//p' "$work/site")
mkdef "$node" groups=all mgt=ipmi
remove_node=1
restore_debug=1
chdef -t site xcatdebugmode=1
chdef "$node" "bmcpassword=SEKRET-$node"
lsdef "$node" -i bmcpassword > "$work/node"
grep -Fx "    bmcpassword=SEKRET-$node" "$work/node" > /dev/null ||
    fail 'Logging changed the password stored by chdef.'
logger -p local4.debug -t xcat "$node complete"

attempt=0
while :; do
    if grep -F "$node complete" "$log" > /dev/null; then
        break
    else
        status=$?
        [ "$status" -eq 1 ] || fail 'Cannot read the syslog completion marker.'
    fi
    attempt=$((attempt + 1))
    [ "$attempt" -lt 30 ] || fail 'Timed out waiting for syslog.'
    sleep 1
done

grep -F "$node" "$log" > "$work/log"
if grep -F "SEKRET-$node" "$work/log" > /dev/null; then
    fail 'The unmasked password reached syslog.'
else
    status=$?
    [ "$status" -eq 1 ] || fail 'Cannot check syslog for the password.'
fi
grep -F "xcatd: dispatch request 'chdef $node bmcpassword=xxxxxxxx' to plugin '" \
    "$work/log" > /dev/null || fail 'The masked chdef dispatch trace is missing.'
echo 'The dispatch trace masks the password and keeps the command and node.'
