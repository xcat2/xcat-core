#!/usr/bin/env bats
#
# The Genesis ramdisk carries its own copies of two awk helpers, because nothing
# of xCAT is installed in it. The copies under xCAT/postscripts choose the gawk
# network family from the management address; the copies under
# xCAT-genesis-scripts/usr/bin named /inet/ unconditionally, so on an IPv6-only
# cluster the credential listener accepted no connection and the state report
# reached no listener. A node discovered by Genesis then hung with no
# credentials and no state.
#
# Each test runs the real program and speaks to it over the loopback address of
# the family under test. Nothing here reaches the lab.

load 'helpers/shell_source'

setup()
{
    command -v gawk >/dev/null || skip 'gawk is required'
    command -v socat >/dev/null || skip 'socat is required'
    command -v ss >/dev/null || skip 'ss is required'
    SERVER_PID=
}

teardown()
{
    [ -n "${SERVER_PID:-}" ] || return 0
    kill -- "-${SERVER_PID}" 2>/dev/null
    kill "$SERVER_PID" 2>/dev/null
    return 0
}

# ---------------------------------------------------------------------------
# allowcred.awk -- the credential listener.

# listen_cred <script> <port> -- start the listener with the caller's exports,
# then wait for the port. Its stdio is detached, because a child holding the
# test's pipes open makes a failure hang instead of go red.
listen_cred()
{
    local script="$1" port="$2" i
    setsid gawk -f "$script" </dev/null >/dev/null 2>&1 &
    SERVER_PID=$!
    for i in $(seq 1 100); do
        ss -Hltn "sport = :${port}" 2>/dev/null | grep -q . && return 0
        sleep 0.1
    done
    return 1
}

ask()
{
    printf 'CREDOKBYYOU\n' | socat -T2 - "$1" 2>/dev/null
}

@test "the Genesis credential listener answers an IPv6 master over IPv6" {
    local script port
    script="$(require_repo_file 'xCAT-genesis-scripts/usr/bin/allowcred.awk')"
    port=$(( 20000 + RANDOM % 20000 ))
    export MASTER_IP='2001:db8::1'
    export XCAT_CREDENTIAL_CALLBACK_PORT="$port"
    listen_cred "$script" "$port"
    run ask "TCP6:[::1]:${port}"
    [ "$status" -eq 0 ]
    [ "$output" = 'CREDOKBYME' ]
}

@test "the Genesis credential listener answers an IPv4 master over IPv4" {
    local script port
    script="$(require_repo_file 'xCAT-genesis-scripts/usr/bin/allowcred.awk')"
    port=$(( 20000 + RANDOM % 20000 ))
    export MASTER_IP='192.0.2.1'
    export XCAT_CREDENTIAL_CALLBACK_PORT="$port"
    listen_cred "$script" "$port"
    run ask "TCP4:127.0.0.1:${port}"
    [ "$status" -eq 0 ]
    [ "$output" = 'CREDOKBYME' ]
}

@test "the Genesis credential listener reads the master from MASTER too" {
    local script port
    script="$(require_repo_file 'xCAT-genesis-scripts/usr/bin/allowcred.awk')"
    port=$(( 20000 + RANDOM % 20000 ))
    unset MASTER_IP
    export MASTER='2001:db8::1'
    export XCAT_CREDENTIAL_CALLBACK_PORT="$port"
    listen_cred "$script" "$port"
    run ask "TCP6:[::1]:${port}"
    [ "$status" -eq 0 ]
    [ "$output" = 'CREDOKBYME' ]
}

# listen_doxcat <script> <port> <master> -- start the listener with only the
# variables doxcat exports to getcert and bmcsetup. doxcat sets no MASTER_IP and
# no MASTER. XCAT_CREDENTIAL_CALLBACK_PORT moves the listener off port 300.
listen_doxcat()
{
    local script="$1" port="$2" master="$3" dest i
    dest="$master:3001"
    [[ $master == *:* ]] && dest="[$master]:3001"
    env -i PATH="$PATH" XCATMASTER="$master" XCATPORT=3001 XCATDEST="$dest" \
        XCAT_CREDENTIAL_CALLBACK_PORT="$port" \
        setsid gawk -f "$script" </dev/null >/dev/null 2>&1 &
    SERVER_PID=$!
    for i in $(seq 1 100); do
        ss -Hltn "sport = :${port}" 2>/dev/null | grep -q . && return 0
        sleep 0.1
    done
    return 1
}

@test "the Genesis credential listener answers over IPv6 with the doxcat environment" {
    local script port
    script="$(require_repo_file 'xCAT-genesis-scripts/usr/bin/allowcred.awk')"
    port=$(( 20000 + RANDOM % 20000 ))
    listen_doxcat "$script" "$port" '2001:db8::1'
    run ask "TCP6:[::1]:${port}"
    [ "$status" -eq 0 ]
    [ "$output" = 'CREDOKBYME' ]
}

@test "the Genesis credential listener answers over IPv4 with the doxcat environment" {
    local script port
    script="$(require_repo_file 'xCAT-genesis-scripts/usr/bin/allowcred.awk')"
    port=$(( 20000 + RANDOM % 20000 ))
    listen_doxcat "$script" "$port" '192.0.2.1'
    run ask "TCP4:127.0.0.1:${port}"
    [ "$status" -eq 0 ]
    [ "$output" = 'CREDOKBYME' ]
}

# ---------------------------------------------------------------------------
# updateflag.awk -- the state report.

# serve <family> <listen-address> -- speak the updateflag protocol once and
# record the flag the client sent. Prints the port it listened on.
#
# The protocol is three lines: the server sends "ready", the client sends the
# flag, the server sends "done". A server that stops after "ready" makes the
# client retry instead of failing, so all three are here.
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
    RECEIVED="$RECEIVED" setsid socat "${family}-LISTEN:${port},bind=${addr},reuseaddr" \
        "EXEC:$handler" </dev/null >/dev/null 2>&1 &
    SERVER_PID=$!
    for i in $(seq 1 100); do
        ss -Hltn "sport = :${port}" 2>/dev/null | grep -q . && break
        sleep 0.1
    done
    printf '%s\n' "$port"
}

# report <seconds> <script> <args...> -- run updateflag.awk with its stdio detached.
#
# The helper retries with "system(\"sleep 10\")", and such a child inherits gawk's stdout. A
# child holding bats's pipe open makes a failing case hang instead of go red, so gawk's output
# goes to a file and the kill after the timeout is unconditional.
report()
{
    local seconds="$1"; shift
    timeout -k 2 "$seconds" gawk -f "$@" </dev/null \
        >"${BATS_TEST_TMPDIR}/gawk.out" 2>&1
}

@test "the Genesis state report reaches an IPv6 xcatd" {
    local script port
    script="$(require_repo_file 'xCAT-genesis-scripts/usr/bin/updateflag.awk')"
    RECEIVED="${BATS_TEST_TMPDIR}/received"
    : >"$RECEIVED"
    port="$(serve TCP6 ::1)"
    run report 15 "$script" ::1 "$port" installing
    [ "$status" -eq 0 ]
    grep -qx 'installing' "$RECEIVED"
}

@test "the Genesis state report still reaches an IPv4 xcatd" {
    local script port
    script="$(require_repo_file 'xCAT-genesis-scripts/usr/bin/updateflag.awk')"
    RECEIVED="${BATS_TEST_TMPDIR}/received"
    : >"$RECEIVED"
    port="$(serve TCP4 127.0.0.1)"
    run report 15 "$script" 127.0.0.1 "$port" installing
    [ "$status" -eq 0 ]
    grep -qx 'installing' "$RECEIVED"
}

@test "the Genesis state report strips the brackets of an IPv6 literal" {
    local script port
    script="$(require_repo_file 'xCAT-genesis-scripts/usr/bin/updateflag.awk')"
    RECEIVED="${BATS_TEST_TMPDIR}/received"
    : >"$RECEIVED"
    port="$(serve TCP6 ::1)"
    run report 15 "$script" '[::1]' "$port" netbooting
    [ "$status" -eq 0 ]
    grep -qx 'netbooting' "$RECEIVED"
}

# ---------------------------------------------------------------------------
# udpcat.awk -- the discovery packet.

# recv_udp <family> <listen-address> -- take one datagram and record it. Prints the port.
#
# udpcat.awk sends from source port 301, so binding it needs root. CI runs as root.
#
# These two cases pass before and after any change: a /inet/ socket that CONNECTS resolves an
# IPv6 literal, unlike the /inet/ LISTENER that allowcred.awk needed changed. They are here
# because two of the three awk helpers did need the change, and nothing else holds the third
# one to it.
recv_udp()
{
    local family="$1" addr="$2" port i
    port=$(( 20000 + RANDOM % 20000 ))
    setsid socat -u "${family}-RECVFROM:${port},bind=${addr}" "CREATE:$RECEIVED" \
        </dev/null >/dev/null 2>&1 &
    SERVER_PID=$!
    for i in $(seq 1 100); do
        ss -Hlun "sport = :${port}" 2>/dev/null | grep -q . && break
        sleep 0.1
    done
    printf '%s\n' "$port"
}

send_disco()
{
    printf 'findme\n' | timeout -k 2 10 gawk -f "$@" >/dev/null 2>&1
}

@test "the Genesis discovery packet reaches an IPv6 xcatd" {
    [ "$(id -u)" -eq 0 ] || skip 'binding the source port of udpcat.awk requires root'
    local script port
    script="$(require_repo_file 'xCAT-genesis-scripts/usr/bin/udpcat.awk')"
    RECEIVED="${BATS_TEST_TMPDIR}/received"
    port="$(recv_udp UDP6 '[::1]')"
    send_disco "$script" ::1 "$port"
    for i in $(seq 1 50); do [ -s "$RECEIVED" ] && break; sleep 0.1; done
    grep -q findme "$RECEIVED"
}

@test "the Genesis discovery packet still reaches an IPv4 xcatd" {
    [ "$(id -u)" -eq 0 ] || skip 'binding the source port of udpcat.awk requires root'
    local script port
    script="$(require_repo_file 'xCAT-genesis-scripts/usr/bin/udpcat.awk')"
    RECEIVED="${BATS_TEST_TMPDIR}/received"
    port="$(recv_udp UDP4 127.0.0.1)"
    send_disco "$script" 127.0.0.1 "$port"
    for i in $(seq 1 50); do [ -s "$RECEIVED" ] && break; sleep 0.1; done
    grep -q findme "$RECEIVED"
}
