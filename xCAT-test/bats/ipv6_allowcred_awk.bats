#!/usr/bin/env bats
#
# allowcred.awk runs on the management node and answers the credential request
# a node sends during discovery. It listens on a gawk network special file, and
# the family of that file comes from the master address xCAT exports. An IPv6
# master needs /inet6/, because a /inet/ listener on this gawk accepts no IPv6
# connection, so an IPv6-only node never gets its credentials.
#
# Each test runs the real program and connects to it over the family under
# test. Everything is on the loopback address; nothing reaches the lab.

load 'helpers/shell_source'

setup()
{
    SCRIPT="$(require_repo_file 'xCAT/postscripts/allowcred.awk')"
    command -v gawk >/dev/null || skip 'gawk is required'
    command -v socat >/dev/null || skip 'socat is required'
    command -v ss >/dev/null || skip 'ss is required'
    PORT=$(( 20000 + RANDOM % 20000 ))
    SERVER_PID=
}

teardown()
{
    [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
    return 0
}

# listen <port> -- start allowcred.awk with the environment already in the
# caller's export list, then wait for the port. Its stdio is detached, because
# a child holding the test's pipes open makes a failure hang instead of go red.
listen()
{
    local port="$1" i
    setsid gawk -f "$SCRIPT" </dev/null >/dev/null 2>&1 &
    SERVER_PID=$!
    for i in $(seq 1 100); do
        ss -Hltn "sport = :${port}" 2>/dev/null | grep -q . && return 0
        sleep 0.1
    done
    return 1
}

# ask <socat-address> -- send one credential request and print the answer.
ask()
{
    printf 'CREDOKBYYOU\n' | socat -T2 - "$1" 2>/dev/null
}

@test "an IPv6 master address makes the credential callback answer over IPv6" {
    export MASTER_IP='2001:db8::1'
    export XCAT_CREDENTIAL_CALLBACK_PORT="$PORT"
    listen "$PORT"
    run ask "TCP6:[::1]:${PORT}"
    [ "$status" -eq 0 ]
    [ "$output" = 'CREDOKBYME' ]
}

@test "an IPv4 master address makes the credential callback answer over IPv4" {
    export MASTER_IP='192.0.2.1'
    export XCAT_CREDENTIAL_CALLBACK_PORT="$PORT"
    listen "$PORT"
    run ask "TCP4:127.0.0.1:${PORT}"
    [ "$status" -eq 0 ]
    [ "$output" = 'CREDOKBYME' ]
}

@test "the master address is read from MASTER when MASTER_IP is unset" {
    export MASTER='2001:db8::1'
    export XCAT_CREDENTIAL_CALLBACK_PORT="$PORT"
    listen "$PORT"
    run ask "TCP6:[::1]:${PORT}"
    [ "$status" -eq 0 ]
    [ "$output" = 'CREDOKBYME' ]
}

@test "an IPv4 listener refuses the IPv6 loopback" {
    export MASTER_IP='192.0.2.1'
    export XCAT_CREDENTIAL_CALLBACK_PORT="$PORT"
    listen "$PORT"
    run ask "TCP6:[::1]:${PORT}"
    [ "$output" != 'CREDOKBYME' ]
}

@test "a port outside the valid range falls back to the default port 300" {
    [ "$(id -u)" -eq 0 ] || skip 'binding port 300 needs root'
    export MASTER_IP='2001:db8::1'
    export XCAT_CREDENTIAL_CALLBACK_PORT='99999'
    listen 300
    run ask 'TCP6:[::1]:300'
    [ "$status" -eq 0 ]
    [ "$output" = 'CREDOKBYME' ]
}
