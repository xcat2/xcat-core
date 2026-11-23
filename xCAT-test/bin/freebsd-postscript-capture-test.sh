#!/bin/sh

set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
LC_ALL=C
export PATH LC_ALL
umask 077
[ "$#" -eq 2 ]
workspace=$1
helper=$2
case "$workspace:$helper" in /*:/*) ;; *) exit 2 ;; esac
[ "$(id -u):$(freebsd-version -u)" = 0:15.1-RELEASE ]
[ ! -e "$workspace" ]
[ ! -L "$workspace" ]
mkdir -m 0700 "$workspace"

field()
{
    awk -F '\t' -v key="$2" '$1 == key { if (NF != 2) exit 1; value=$2; n++ }
        END { if (n != 1) exit 1; print value }' "$1"
}

cleanup()
{
    status=$?
    trap - EXIT
    for file in "$workspace"/*/owned.pid; do
        [ -f "$file" ] || continue
        identity=${file%/*}/owned.identity
        [ -f "$identity" ] || continue
        pid=$(cat "$file")
        current=$("$helper" process "$pid" 2>/dev/null) || continue
        [ "$current" = "$(cat "$identity")" ] || continue
        kill -KILL "$pid"
    done
    printf '%s\n' "$status" > "$workspace/exit-code"
    exit "$status"
}
trap cleanup EXIT

capture()
{
    name=$1
    seconds=$2
    limit=$3
    shift 3
    case_dir=$workspace/$name
    mkdir -m 0700 "$case_dir"
    before=$("$helper" uptime)
    "$helper" "${capture_mode:-capture}" "$seconds" "$limit" "$case_dir/stdout" "$case_dir/stderr" "$@" \
        < /dev/null > "$case_dir/result" 2> "$case_dir/helper.stderr"
    elapsed=$(($("$helper" uptime)-before))
    printf '%s\n' "$elapsed" > "$case_dir/elapsed"
    awk -F '\t' 'BEGIN { split("format status stdout-bytes stderr-bytes stdout-truncated stderr-truncated stdout-open stderr-open", keys, " ") }
        NF != 2 || $1 != keys[NR] { bad=1 }
        END { if (bad || NR != 8) exit 1 }' "$case_dir/result"
    [ "$(field "$case_dir/result" format)" = xcat-freebsd-postscript-capture-1 ]
    for capture_stream in stdout stderr; do
        [ "$(stat -f '%u:%g:%Lp:%l' "$case_dir/$capture_stream")" = 0:0:600:1 ]
        [ "$(stat -f %z "$case_dir/$capture_stream")" = "$(field "$case_dir/result" "$capture_stream-bytes")" ]
        [ "$(stat -f %z "$case_dir/$capture_stream")" -le "$limit" ]
    done
}

passed()
{
    printf 'PASS %s\n' "$1" | tee -a "$workspace/results"
}

capture arguments 5 1024 /bin/sh -c 'printf "<%s>" "$@"; printf error >&2' sh 'a b' '' 'single"quote'
[ "$(cat "$case_dir/stdout")" = '<a b><><single"quote>' ]
[ "$(cat "$case_dir/stderr")" = error ]
[ "$(field "$case_dir/result" status)" = 0 ]
for key in stdout-truncated stderr-truncated stdout-open stderr-open; do
    [ "$(field "$case_dir/result" "$key")" = no ]
done
passed arguments

set --
argument=0
while [ "$argument" -lt 255 ]; do
    set -- "$@" "$argument"
    argument=$((argument+1))
done
capture many-arguments 5 1024 env ONE=1 TWO=2 THREE=3 FOUR=4 /bin/sh -c \
    '[ "$#" -eq 255 ] || exit 3; [ "$1" = 0 ] || exit 3; shift 254; [ "$1" = 254 ]' sh "$@"
[ "$(field "$case_dir/result" status)" = 0 ]
passed many-arguments

for code in 3 143; do
    capture exit-$code 5 1024 /bin/sh -c "exit $code"
    [ "$(field "$case_dir/result" status)" = "$code" ]
    passed exit-$code
done
capture signal 5 1024 /bin/sh -c 'kill -TERM $$'
[ "$(field "$case_dir/result" status)" = 143 ]
passed signal

for bytes in 1024 1025 1048576; do
    for stream in stdout stderr; do
        redirect=
        [ "$stream" = stdout ] || redirect='>&2'
        capture "$stream-$bytes" 5 1024 /bin/sh -c "head -c $bytes /dev/zero $redirect"
        [ "$(field "$case_dir/result" status)" = 0 ]
        [ "$(stat -f %z "$case_dir/$stream")" = 1024 ]
        expected=yes
        [ "$bytes" -ne 1024 ] || expected=no
        [ "$(field "$case_dir/result" "$stream-truncated")" = "$expected" ]
        passed "$stream-$bytes"
    done
done
capture zero-limit 5 0 /bin/sh -c 'printf output; printf error >&2'
[ "$(field "$case_dir/result" status)" = 0 ]
[ "$(field "$case_dir/result" stdout-truncated)" = yes ]
[ "$(field "$case_dir/result" stderr-truncated)" = yes ]
passed zero-limit

capture large-file 5 1024 /bin/sh -c 'dd if=/dev/zero of="$1" bs=1048576 count=2' sh "$workspace/payload"
[ "$(field "$case_dir/result" status)" = 0 ]
[ "$(stat -f %z "$workspace/payload")" = 2097152 ]
passed large-file

for mode in detached inherited nested; do
    directory=$workspace/daemon-$mode
    flag=-f
    [ "$mode" != inherited ] || flag=
    script="/usr/sbin/daemon $flag -p '$directory/daemon.pid' /bin/sleep 30
attempt=0
while [ ! -s '$directory/daemon.pid' ]; do
    attempt=\$((attempt+1)); [ \"\$attempt\" -lt 40 ] || exit 3; sleep 0.05
done
cp '$directory/daemon.pid' '$directory/owned.pid'
'$helper' process \"\$(cat '$directory/owned.pid')\" > '$directory/owned.identity'
printf entry-complete"
    if [ "$mode" = nested ]; then
        capture daemon-$mode 5 1024 "$helper" capture 4 1024 "$directory/inner.stdout" "$directory/inner.stderr" /bin/sh -c "$script"
        [ "$(field "$case_dir/stdout" status)" = 0 ]
    else
        capture daemon-$mode 5 1024 /bin/sh -c "$script"
        [ "$(cat "$case_dir/stdout")" = entry-complete ]
    fi
    [ "$(field "$case_dir/result" status)" = 0 ]
    [ "$elapsed" -lt 3 ]
    pid=$(cat "$case_dir/owned.pid")
    "$helper" process "$pid" > "$case_dir/after.identity"
    cmp "$case_dir/owned.identity" "$case_dir/after.identity"
    if [ "$mode" = inherited ]; then
        [ "$(field "$case_dir/result" stdout-open)" = yes ]
        [ "$(field "$case_dir/result" stderr-open)" = yes ]
    fi
    kill -TERM "$pid"
    passed daemon-$mode
done

for mode in timeout nested-timeout; do
    directory=$workspace/$mode
    script="trap '' TERM
printf '%s\\n' \$\$ > '$directory/owned.pid'
'$helper' process \$\$ > '$directory/owned.identity'
while :; do sleep 30; done"
    if [ "$mode" = nested-timeout ]; then
        capture "$mode" 1 1024 "$helper" capture 20 1024 "$directory/inner.stdout" "$directory/inner.stderr" /bin/sh -c "$script"
    else
        capture "$mode" 1 1024 /bin/sh -c "$script"
    fi
    [ "$(field "$case_dir/result" status)" = 124 ]
    [ "$elapsed" -ge 1 ]
    [ "$elapsed" -le 8 ]
    [ -s "$case_dir/owned.pid" ]
    [ -s "$case_dir/owned.identity" ]
    if "$helper" process "$(cat "$case_dir/owned.pid")" > "$case_dir/process.after" 2> "$case_dir/process.stderr"; then exit 1; fi
    grep -q 'No such process$' "$case_dir/process.stderr"
    passed "$mode"
done

directory=$workspace/interrupted
mkdir -m 0700 "$directory"
"$helper" capture 30 1024 "$directory/stdout" "$directory/stderr" /bin/sh -c \
    'printf "%s\n" $$ > "$1/owned.pid"; "$2" process $$ > "$1/owned.identity"; sleep 30' \
    sh "$directory" "$helper" < /dev/null > "$directory/result" 2> "$directory/helper.stderr" &
supervisor=$!
attempt=0
while [ ! -s "$directory/owned.identity" ]; do
    attempt=$((attempt+1)); [ "$attempt" -lt 40 ]; sleep 0.05
done
kill -TERM "$supervisor"
wait "$supervisor"
[ "$(field "$directory/result" status)" = 143 ]
[ -s "$directory/owned.pid" ]
if "$helper" process "$(cat "$directory/owned.pid")" > "$directory/process.after" 2> "$directory/process.stderr"; then exit 1; fi
grep -q 'No such process$' "$directory/process.stderr"
passed interrupted

capture drain-signal 30 1024 /bin/sh -c '
    supervisor=$PPID
    /bin/sh -c '\''trap "" TERM
        printf "%s\n" $$ > "$1/owned.pid"
        "$2" process $$ > "$1/owned.identity"
        exec /bin/sleep 30'\'' sh "$1" "$2" &
    attempt=0
    while [ ! -s "$1/owned.identity" ]; do
        attempt=$((attempt+1)); [ "$attempt" -lt 40 ] || exit 3; sleep 0.05
    done
    (sleep 0.05; kill -TERM "$supervisor") &
    exit 0
' sh "$workspace/drain-signal" "$helper"
[ "$(field "$case_dir/result" status)" = 143 ]
[ "$elapsed" -ge 5 ]
[ "$elapsed" -le 8 ]
[ -s "$case_dir/owned.pid" ]
[ -s "$case_dir/owned.identity" ]
if "$helper" process "$(cat "$case_dir/owned.pid")" > "$case_dir/process.after" 2> "$case_dir/process.stderr"; then exit 1; fi
grep -q 'No such process$' "$case_dir/process.stderr"
passed drain-signal

for mode in existing symlink; do
    directory=$workspace/$mode
    mkdir -m 0700 "$directory"
    printf original > "$directory/protected"
    if [ "$mode" = existing ]; then
        cp "$directory/protected" "$directory/stdout"
    else
        ln -s protected "$directory/stdout"
    fi
    status=0
    "$helper" capture 5 1024 "$directory/stdout" "$directory/stderr" touch "$directory/executed" \
        > "$directory/result" 2> "$directory/helper.stderr" || status=$?
    [ "$status" -eq 125 ]
    [ ! -e "$directory/executed" ]
    [ "$(cat "$directory/protected")" = original ]
    [ "$(cat "$directory/stdout")" = original ]
    passed "$mode"
done
directory=$workspace/guard-missing
mkdir -m 0700 "$directory"
status=0
"$helper" capture-guard 5 1024 "$directory/stdout" "$directory/stderr" touch "$directory/executed" \
    9>&- > "$directory/result" 2> "$directory/helper.stderr" || status=$?
[ "$status" -eq 125 ]
grep -q 'Cannot guard inherited worker lock:' "$directory/helper.stderr"
[ ! -e "$directory/stdout" ]
[ ! -e "$directory/stderr" ]
[ ! -e "$directory/executed" ]
passed guard-missing

directory=$workspace/guard-lifetime
mkdir -m 0700 "$directory"
: > "$directory/lock"
(
    exec 9<> "$directory/lock"
    lockf -s -k -t 0 /dev/fd/9
    exec "$helper" capture-guard 30 1024 "$directory/stdout" "$directory/stderr" /bin/sh -c '
        if ( : <&9 ) 2>/dev/null; then exit 3; fi
        printf "%s\n" $$ > "$1/owned.pid"
        "$2" process $$ > "$1/owned.identity"
        exec /bin/sleep 30
    ' sh "$directory" "$helper"
) > "$directory/result" 2> "$directory/helper.stderr" &
supervisor=$!
attempt=0
while [ ! -s "$directory/owned.identity" ]; do
    attempt=$((attempt+1)); [ "$attempt" -lt 100 ]; sleep 0.05
done
status=0
lockf -s -k -t 0 "$directory/lock" /bin/sh -c : || status=$?
[ "$status" -eq 75 ]
kill -TERM "$supervisor"
wait "$supervisor"
[ "$(field "$directory/result" status)" = 143 ]
"$helper" process-state "$(cat "$directory/owned.pid")" > "$directory/process.after"
[ "$(field "$directory/process.after" state)" = absent ]
lockf -s -k -t 0 "$directory/lock" /bin/sh -c :
passed guard-lifetime

directory=$workspace/guard-service
mkdir -m 0700 "$directory"
: > "$directory/lock"
(
    exec 9<> "$directory/lock"
    lockf -s -k -t 0 /dev/fd/9
    exec "$helper" capture-guard 5 1024 "$directory/stdout" "$directory/stderr" /bin/sh -c '
        /usr/sbin/daemon -f -p "$1/daemon.pid" /bin/sleep 30
        attempt=0
        while [ ! -s "$1/daemon.pid" ]; do
            attempt=$((attempt+1)); [ "$attempt" -lt 100 ] || exit 3; sleep 0.05
        done
        cp "$1/daemon.pid" "$1/owned.pid"
        "$2" process "$(cat "$1/owned.pid")" > "$1/owned.identity"
    ' sh "$directory" "$helper"
) > "$directory/result" 2> "$directory/helper.stderr"
[ "$(field "$directory/result" status)" = 0 ]
"$helper" process "$(cat "$directory/owned.pid")" > "$directory/service.after"
cmp "$directory/owned.identity" "$directory/service.after"
lockf -s -k -t 0 "$directory/lock" /bin/sh -c :
kill -TERM "$(cat "$directory/owned.pid")"
passed guard-service
capture_mode=capture-watch
capture watch-completed 0 1024 /bin/sh -c 'sleep 0.05; printf observed'
[ "$(field "$case_dir/result" status)" = 0 ]
[ "$(cat "$case_dir/stdout")" = observed ]
passed watch-completed
directory=$workspace/watch-deadline
capture watch-deadline 0 1024 "$helper" capture 1 1024 "$directory/inner.stdout" "$directory/inner.stderr" /bin/sleep 30
[ "$(field "$case_dir/result" status)" = 0 ]
[ "$(field "$case_dir/stdout" status)" = 124 ]
[ "$elapsed" -ge 1 ] && [ "$elapsed" -le 8 ]
passed watch-deadline
unset capture_mode
directory=$workspace/watch-interrupted
mkdir -m 0700 "$directory"
"$helper" capture-watch 0 1024 "$directory/stdout" "$directory/stderr" /bin/sh -c '
    printf "%s\n" $$ > "$1/owned.pid"
    "$2" process $$ > "$1/owned.identity"
    exec /bin/sleep 30
' sh "$directory" "$helper" > "$directory/result" 2> "$directory/helper.stderr" &
supervisor=$!
attempt=0
while [ ! -s "$directory/owned.identity" ]; do
    attempt=$((attempt+1)); [ "$attempt" -lt 100 ]; sleep 0.05
done
kill -TERM "$supervisor"
wait "$supervisor"
[ "$(field "$directory/result" status)" = 143 ]
"$helper" process-state "$(cat "$directory/owned.pid")" > "$directory/process.after"
[ "$(field "$directory/process.after" state)" = absent ]
passed watch-interrupted
directory=$workspace/watch-bound
mkdir -m 0700 "$directory"
status=0
"$helper" capture-watch 1 1024 "$directory/stdout" "$directory/stderr" touch "$directory/executed" \
    > "$directory/result" 2> "$directory/helper.stderr" || status=$?
[ "$status" -eq 125 ]
grep -q 'Capture bound is out of range$' "$directory/helper.stderr"
[ ! -e "$directory/stdout" ]
[ ! -e "$directory/stderr" ]
[ ! -e "$directory/executed" ]
passed watch-bound
printf 'PASS cases=%s\n' "$(wc -l < "$workspace/results" | tr -d ' ')"
