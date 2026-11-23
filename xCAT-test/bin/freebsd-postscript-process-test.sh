#!/bin/sh

# Run on a disposable FreeBSD node with the native helper, zombie fixture and
# a helper linked with the fixture's sysctl wrappers. The production helper
# handles the real live, zombie and absent process observations.
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
LC_ALL=C
export PATH LC_ALL
umask 077
[ "$#" -eq 4 ]
workspace=$1
helper=$2
fixture=$3
fault_helper=$4
for path in "$workspace" "$helper" "$fixture" "$fault_helper"; do
    case "$path" in /*) ;; *) exit 2 ;; esac
done
[ "$(id -u):$(freebsd-version -u)" = 0:15.1-RELEASE ]
[ ! -e "$workspace" ] && [ ! -L "$workspace" ]
mkdir -m 0700 "$workspace"
fixture_pid=
finish()
{
    status=$?
    trap - EXIT HUP INT TERM
    if [ -n "$fixture_pid" ]; then
        current=$("$helper" process "$fixture_pid" 2>/dev/null) || current=
        if [ -n "$current" ] && [ -s "$workspace/fixture.identity" ] &&
            [ "$current" = "$(cat "$workspace/fixture.identity")" ]; then
            kill -USR2 "$fixture_pid" || status=99
            wait "$fixture_pid" || status=99
        fi
    fi
    printf '%s\n' "$status" > "$workspace/exit-code"
    exit "$status"
}
trap finish EXIT
trap 'exit 1' HUP INT TERM
field()
{
    awk -F '\t' -v key="$2" '$1==key {n++; if(NF!=2) exit 1; value=$2}
        END {if(n!=1) exit 1; print value}' "$1"
}
"$helper" process "$$" > "$workspace/live.identity"
"$helper" process-state "$$" > "$workspace/live.state"
printf 'format\txcat-freebsd-process-state-1\npid\t%s\nstate\trunning\nidentity\t%s\n' \
    "$$" "$(cat "$workspace/live.identity")" > "$workspace/live.expected"
cmp "$workspace/live.expected" "$workspace/live.state"
printf 'PASS live\n'
"$fixture" > "$workspace/zombie.pid" 2> "$workspace/fixture.stderr" &
fixture_pid=$!
"$helper" process "$fixture_pid" > "$workspace/fixture.identity"
attempt=0
while [ ! -s "$workspace/zombie.pid" ]; do
    attempt=$((attempt+1)); [ "$attempt" -lt 100 ]; sleep 0.05
done
pid=$(head -n 1 "$workspace/zombie.pid")
"$helper" process "$pid" > "$workspace/child.live.identity"
kill -USR1 "$fixture_pid"
attempt=0
while [ "$(tail -n 1 "$workspace/zombie.pid")" != zombie ]; do
    attempt=$((attempt+1)); [ "$attempt" -lt 100 ]; sleep 0.05
done
"$helper" process-state "$pid" > "$workspace/zombie.state"
[ "$(field "$workspace/zombie.state" state)" = zombie ]
[ "$(field "$workspace/zombie.state" pid)" = "$pid" ]
grep -Eq "^identity[[:space:]]$pid:[0-9]+[.][0-9]{6}$" "$workspace/zombie.state"
[ "$(field "$workspace/zombie.state" identity)" = "$(cat "$workspace/child.live.identity")" ]
if "$helper" process "$pid" > "$workspace/zombie.legacy" 2> "$workspace/zombie.legacy.stderr"; then exit 1; fi
[ ! -s "$workspace/zombie.legacy" ]
printf 'PASS zombie\n'
kill -USR2 "$fixture_pid"
wait "$fixture_pid"
fixture_pid=
"$helper" process-state "$pid" > "$workspace/absent.state"
printf 'format\txcat-freebsd-process-state-1\npid\t%s\nstate\tabsent\nidentity\t-\n' "$pid" > "$workspace/absent.expected"
cmp "$workspace/absent.expected" "$workspace/absent.state"
printf 'PASS absent\n'
for mode in permission io zero short wrong-pid wrong-size jailed jail-shape jail-error; do
    status=0
    env XCAT_TEST_PROCESS_QUERY="$mode" "$fault_helper" process-state "$$" \
        > "$workspace/$mode.stdout" 2> "$workspace/$mode.stderr" || status=$?
    [ "$status" -eq 1 ]
    [ ! -s "$workspace/$mode.stdout" ]
    case "$mode" in
    permission|io) grep -q 'Cannot read process identity:' "$workspace/$mode.stderr" ;;
    jailed|jail-shape) grep -q 'Process observation requires the host root context$' "$workspace/$mode.stderr" ;;
    jail-error) grep -q 'Cannot observe process visibility:' "$workspace/$mode.stderr" ;;
    *) grep -q 'Invalid process identity response$' "$workspace/$mode.stderr" ;;
    esac
    printf 'PASS %s\n' "$mode"
done
for value in 0 01 invalid 100000000; do
    status=0
    "$helper" process-state "$value" > "$workspace/invalid-$value.stdout" 2> "$workspace/invalid-$value.stderr" || status=$?
    [ "$status" -eq 1 ]
    [ ! -s "$workspace/invalid-$value.stdout" ]
    grep -q 'Invalid process identifier$' "$workspace/invalid-$value.stderr"
    printf 'PASS invalid-%s\n' "$value"
done
printf 'PASS cases=16\n'
