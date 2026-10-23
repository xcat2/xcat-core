#!/usr/bin/env bats
#
# updateflag.awk reports the install state back to xcatd over a gawk network
# special file, built from the address xCAT passes it. An IPv6 management
# address arrives bracketed, and gawk resolves nothing unless the brackets come
# off, so the node never reports its state.
#
# These tests do not cover the /inet/ to /inet6/ prefix the same routine
# chooses. Measured on gawk 5.3.0: /inet/ reaches an IPv6 literal and only
# /inet4/ refuses it, so removing that choice breaks nothing a test could see.
# The prefix stays because it is explicit, not because it is load-bearing.
#
# Each test runs the real program against a listener on the loopback address of
# the family under test. Nothing here reaches the lab.

load 'helpers/shell_source'

setup()
{
    SCRIPT="$(require_repo_file 'xCAT/postscripts/updateflag.awk')"
    command -v gawk >/dev/null || skip 'gawk is required'
    command -v socat >/dev/null || skip 'socat is required'
    command -v ss >/dev/null || skip 'ss is required'
    RECEIVED="${BATS_TEST_TMPDIR}/received"
    : >"$RECEIVED"
}

# serve <family> <listen-address> -- speak the updateflag protocol once and
# record the flag the client sent. Prints the port it listened on.
#
# The protocol is three lines: the server sends "ready", the client sends the
# flag, the server sends "done". A server that stops after "ready" makes the
# client retry for a hundred seconds instead of failing, so all three are here.
#
# The listener serves one connection and exits, so readiness is read from ss
# rather than by connecting: a probe connection would consume it.
serve()
{
    local family="$1" addr="$2" port handler i
    port=$(( 20000 + RANDOM % 20000 ))
    handler="${BATS_TEST_TMPDIR}/handler.sh"
    cat >"$handler" <<'HANDLER'
#!/bin/bash
printf 'ready\n'
IFS= read -r flag
printf '%s\n' "$flag" >"$RECEIVED"
printf 'done\n'
HANDLER
    chmod 0755 "$handler"
    # Detach the server's stdio: a child holding the test's pipes open makes a
    # failure hang instead of going red.
    RECEIVED="$RECEIVED" setsid socat "${family}-LISTEN:${port},bind=${addr},reuseaddr" \
        "EXEC:$handler" </dev/null >/dev/null 2>&1 &
    SERVER_PID=$!
    for i in $(seq 1 100); do
        ss -Hltn "sport = :${port}" 2>/dev/null | grep -q . && break
        sleep 0.1
    done
    printf '%s\n' "$port"
}

teardown()
{
    # The listener serves one connection and exits, so this only matters when a
    # test failed before connecting. Signal the session setsid created, then
    # confirm the port is gone rather than assuming the signal landed.
    [ -n "${SERVER_PID:-}" ] || return 0
    kill -- "-${SERVER_PID}" 2>/dev/null
    kill "$SERVER_PID" 2>/dev/null
    local i
    for i in $(seq 1 50); do
        kill -0 "$SERVER_PID" 2>/dev/null || return 0
        sleep 0.1
    done
    kill -9 -- "-${SERVER_PID}" 2>/dev/null
    return 0
}

@test "an IPv4 xcatd address still reaches the listener" {
    local port
    port="$(serve TCP4 127.0.0.1)"
    run timeout 30 gawk -f "$SCRIPT" 127.0.0.1 "$port" installing
    [ "$status" -eq 0 ]
    grep -qx 'installing' "$RECEIVED"
}

@test "an IPv6 xcatd address reaches the listener" {
    local port
    port="$(serve TCP6 ::1)"
    run timeout 30 gawk -f "$SCRIPT" ::1 "$port" installing
    [ "$status" -eq 0 ]
    grep -qx 'installing' "$RECEIVED"
}

@test "a bracketed IPv6 address has its brackets stripped before gawk resolves it" {
    local port
    port="$(serve TCP6 ::1)"
    run timeout 30 gawk -f "$SCRIPT" '[::1]' "$port" netbooting
    [ "$status" -eq 0 ]
    grep -qx 'netbooting' "$RECEIVED"
}

@test "the default flag is sent when none is given" {
    local port
    port="$(serve TCP6 ::1)"
    run timeout 30 gawk -f "$SCRIPT" ::1 "$port"
    [ "$status" -eq 0 ]
    grep -qx 'next' "$RECEIVED"
}
