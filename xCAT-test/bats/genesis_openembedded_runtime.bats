#!/usr/bin/env bats
#
# The runtime scripts of the OpenEmbedded Genesis image: getdestiny and nextdestiny ask xCAT
# for the node action, genesis-network-state writes the management network state,
# genesis-network-refresh renews the DHCP lease, genesis-register records the action,
# genesis-status publishes one status record, and genesis-maintenance-shell reports them.
# openssl, ip, nmcli and logger are scratch scripts. A local TCP listener stands in for xcatd.

load 'helpers/shell_source'

INIT_FILES='xCAT-genesis-base/oe/meta-xcat-genesis/recipes-core/xcat-genesis-init/files'

setup_file()
{
    # A listener that accepts and closes connections and logs one line for each.
    export LISTENER_LOG="$BATS_FILE_TMPDIR/listener.log"
    : >"$LISTENER_LOG"
    perl -MIO::Socket::INET -e '
        my $s = IO::Socket::INET->new(LocalAddr => "127.0.0.1", LocalPort => 0,
            Listen => 5, ReuseAddr => 1) or die "listen: $!";
        open(my $port, ">", $ARGV[0]) or die; print {$port} $s->sockport, "\n"; close $port;
        while (my $c = $s->accept) {
            open(my $log, ">>", $ARGV[1]) or die; print {$log} "accept\n"; close $log; close $c;
        }' "$BATS_FILE_TMPDIR/port" "$LISTENER_LOG" </dev/null >/dev/null 2>&1 3>&- &
    echo "$!" >"$BATS_FILE_TMPDIR/listener.pid"
    for _ in $(seq 50); do [ -s "$BATS_FILE_TMPDIR/port" ] && break; sleep 0.1; done
    [ -s "$BATS_FILE_TMPDIR/port" ]
}

teardown_file()
{
    kill "$(cat "$BATS_FILE_TMPDIR/listener.pid")" 2>/dev/null || true
}

setup()
{
    NETWORK_SCRIPT="$(require_repo_file "$INIT_FILES/genesis-network-state")"
    REFRESH_SCRIPT="$(require_repo_file "$INIT_FILES/genesis-network-refresh")"
    REGISTER_SCRIPT="$(require_repo_file "$INIT_FILES/genesis-register")"
    STATUS_SCRIPT="$(require_repo_file "$INIT_FILES/genesis-status")"
    SHELL_SCRIPT="$(require_repo_file "$INIT_FILES/genesis-maintenance-shell")"
    GETDESTINY="$(require_repo_file 'xCAT-genesis-scripts/usr/bin/getdestiny')"
    NEXTDESTINY="$(require_repo_file 'xCAT-genesis-scripts/usr/bin/nextdestiny')"
    port="$(cat "$BATS_FILE_TMPDIR/port")"

    root="$BATS_TEST_TMPDIR"
    bin="$root/bin"
    state_dir="$root/run"
    status_dir="$state_dir/status"
    metadata="$state_dir/xcat-response.env"
    mkdir -p "$bin" "$state_dir" "$root/sys/class/net/eth0" "$root/sys/class/net/eth1"
    printf '52:54:00:00:00:35\n' >"$root/sys/class/net/eth0/address"
    printf 'up\n' >"$root/sys/class/net/eth0/operstate"
    printf '123.45 456.78\n' >"$root/uptime"
    : >"$root/commands.log"

    printf '#!/bin/sh\nprintf "logger %%s\\n" "$*" >>"$XCAT_TEST_LOG"\n[ -z "${XCAT_TEST_LOGGER_FAIL-}" ]\n' >"$bin/logger"
    cat >"$bin/ip" <<'SH'
#!/bin/sh
case "$*" in
    '-4 -o route get '*) printf '%s\n' "$XCAT_TEST_ROUTE" ;;
    '-4 -o address show dev eth0 scope global')
        printf '%s\n' '2: eth0 inet 192.0.2.98/24 scope global eth0'
        ;;
esac
SH
    cat >"$bin/nmcli" <<'SH'
#!/bin/sh
printf 'nmcli %s\n' "$*" >>"$XCAT_TEST_LOG"
case "$*" in
    '-t -f DEVICE,TYPE device status')
        printf '%s\n' 'eth0:ethernet' 'eth1:ethernet' 'lo:loopback'
        ;;
    '-g GENERAL.CON-UUID device show eth0') printf '%s\n' 'connection-eth0' ;;
    '-g GENERAL.CON-UUID device show eth1') printf '%s\n' 'connection-eth1' ;;
    '-g GENERAL.STATE device show '*) printf '%s\n' '100 (connected)' ;;
    '--terse --escape no -g IP4.DNS,IP6.DNS device show eth0')
        printf '%s\n' "${XCAT_TEST_DNS-192.0.2.53 | 2001:db8::53}"
        ;;
    '--wait 30 device connect eth0')
        [ -z "${XCAT_TEST_CONNECT_FAIL-}" ] || exit 1
        ;;
esac
SH
    printf '#!/bin/sh\nprintf "%%s\\n" network-state-refresh >>"$XCAT_TEST_LOG"\n' >"$bin/network-state-refresh"
    cat >"$bin/getdestiny" <<'SH'
#!/bin/sh
printf 'getdestiny %s\n' "$*" >>"$XCAT_TEST_LOG"
metadata=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --metadata) metadata=$2; shift 2 ;;
        *) shift ;;
    esac
done
if [ -n "$metadata" ]; then
    printf '%s\n' XCAT_NODE_NAME=node042 XCAT_DESTINY=osimage=test-image \
        XCAT_IMAGE_SERVER=192.0.2.10 XCAT_KERNEL=/tftp/vmlinuz XCAT_INITRD=/tftp/initrd \
        'XCAT_KERNEL_COMMAND_LINE=console=ttyS0 quiet' >"$metadata"
fi
printf '%s\n' "${XCAT_TEST_DESTINY-standby}"
SH
    cat >"$bin/openssl" <<'SH'
#!/bin/sh
printf 'openssl %s\n' "$*" >>"$XCAT_TEST_LOG"
[ -z "${XCAT_TEST_OPENSSL_DELAY-}" ] || exec sleep "$XCAT_TEST_OPENSSL_DELAY"
[ -z "${XCAT_TEST_OPENSSL_STATUS-}" ] || exit "$XCAT_TEST_OPENSSL_STATUS"
cat "$XCAT_TEST_RESPONSE_FILE"
SH
    chmod 0755 "$bin"/*

    export PATH="$bin:$PATH"
    export XCAT_CMDLINE_FILE="$root/cmdline"
    export XCAT_STATE_DIR="$state_dir"
    export XCAT_STATUS_COMMAND="$STATUS_SCRIPT"
    export XCAT_STATUS_DIR="$status_dir"
    export XCAT_SYS_CLASS_NET="$root/sys/class/net"
    export XCAT_TEST_LOG="$root/commands.log"
    export XCAT_TEST_RESPONSE_FILE="$root/destiny-response.xml"
    export XCAT_TEST_ROUTE='127.0.0.1 via 192.0.2.1 dev eth0 src 192.0.2.98'
    export XCAT_UPTIME_FILE="$root/uptime"
    export XCAT_GENESIS_FUNCTIONS="$(require_repo_file "$INIT_FILES/genesis-functions")"
    export XCAT_REGISTRATION_ATTEMPTS=1
    export XCAT_REGISTRATION_RETRY_SECONDS=0
    export XCAT_REGISTRATION_REQUEST_TIMEOUT=1
}

EXPECTED_METADATA='XCAT_NODE_NAME=node042
XCAT_DESTINY=osimage=test-image
XCAT_IMAGE_SERVER=192.0.2.10
XCAT_KERNEL=/tftp/vmlinuz
XCAT_INITRD=/tftp/initrd
XCAT_KERNEL_COMMAND_LINE=console=ttyS0 quiet'

# An xCAT response naming node042, its image server, and an action.
response()
{
    printf '%s\n' '<xcatresponse>' '<node>' '<name>node042</name>' "<destiny>$1</destiny>" \
        '<kernel>/tftp/vmlinuz</kernel>' '<initrd>/tftp/initrd</initrd>' \
        '<kcmdline>console=ttyS0 quiet</kcmdline>' '<imgserver>192.0.2.10</imgserver>' \
        '</node>' '</xcatresponse>' >"$XCAT_TEST_RESPONSE_FILE"
}

# Start a command, send it SIGTERM after 0.2 s, and print its exit status. Prints "hung"
# when it is still running 3 s later.
terminate_after()
{
    local pid rc=0
    "$@" </dev/null >/dev/null 2>&1 &
    pid=$!
    sleep 0.2
    kill -TERM "$pid"
    for _ in $(seq 30); do
        kill -0 "$pid" 2>/dev/null || { wait "$pid" || rc=$?; echo "$rc"; return; }
        sleep 0.1
    done
    kill -KILL "$pid"
    echo hung
}

network_state()
{
    status=0
    /bin/bash "$NETWORK_SCRIPT" </dev/null >/dev/null 2>&1 || status=$?
}

@test "getdestiny accepts a complete response, keeps the complete action, and records the metadata" {
    response osimage=test-image
    run /bin/bash "$GETDESTINY" 192.0.2.10:3001 --once --metadata "$metadata"
    [ "$status" -eq 0 ]
    [ "$output" = osimage=test-image ]
    [ "$(cat "$metadata")" = "$EXPECTED_METADATA" ]
}

@test "getdestiny rejects an error response, and the failed request keeps the prior metadata" {
    response osimage=test-image
    /bin/bash "$GETDESTINY" 192.0.2.10:3001 --once --metadata "$metadata"
    printf '<xcatresponse><error>denied</error></xcatresponse>\n' >"$XCAT_TEST_RESPONSE_FILE"
    run /bin/bash "$GETDESTINY" 192.0.2.10:3001 --once --metadata "$metadata"
    [ "$status" -ne 0 ]
    [ "$(cat "$metadata")" = "$EXPECTED_METADATA" ]
}

@test "legacy getdestiny retries an error response and a connection failure until stopped" {
    printf '<xcatresponse><error>denied</error></xcatresponse>\n' >"$XCAT_TEST_RESPONSE_FILE"
    [ "$(terminate_after /bin/bash "$GETDESTINY" 192.0.2.10:3001)" = 143 ]
    [ "$(XCAT_TEST_OPENSSL_STATUS=1 terminate_after /bin/bash "$GETDESTINY" 192.0.2.10:3001)" = 143 ]
}

@test "without a destiny, legacy getdestiny returns an empty one and one-shot getdestiny fails" {
    printf '<xcatresponse/>\n' >"$XCAT_TEST_RESPONSE_FILE"
    run /bin/bash "$GETDESTINY" 192.0.2.10:3001
    [ "$status" -eq 0 ]
    [ "$output" = '' ]
    [ "$(/bin/bash "$GETDESTINY" 192.0.2.10:3001 | od -An -c | tr -d ' ')" = '\n' ]
    run /bin/bash "$GETDESTINY" 192.0.2.10:3001 --once
    [ "$status" -ne 0 ]
}

@test "nextdestiny accepts a complete response and keeps a legacy action with arguments" {
    response 'install rocky9.7-x86_64-compute'
    run /bin/bash "$NEXTDESTINY" 192.0.2.10:3001 --once --metadata "$metadata"
    [ "$status" -eq 0 ]
    [ "$output" = 'install rocky9.7-x86_64-compute' ]
    grep -qx 'XCAT_DESTINY=install rocky9.7-x86_64-compute' "$metadata"
}

@test "nextdestiny returns a server error as an action" {
    printf '<xcatresponse><error>chain unavailable</error></xcatresponse>\n' >"$XCAT_TEST_RESPONSE_FILE"
    run /bin/bash "$NEXTDESTINY" 192.0.2.10:3001 --once
    [ "$status" -eq 0 ]
    [ "$output" = 'error=chain unavailable' ]
}

@test "one-shot nextdestiny rejects an incomplete response, legacy nextdestiny returns it" {
    printf '<xcatresponse/>\n' >"$XCAT_TEST_RESPONSE_FILE"
    run /bin/bash "$NEXTDESTINY" 192.0.2.10:3001 --once
    [ "$status" -ne 0 ]
    run /bin/bash "$NEXTDESTINY" 192.0.2.10:3001
    [ "$status" -eq 0 ]
    [ "$output" = 'error=No destiny command received' ]
}

@test "SIGTERM stops getdestiny and nextdestiny during a request" {
    export XCAT_TEST_OPENSSL_DELAY=30
    [ "$(terminate_after /bin/bash "$GETDESTINY" 192.0.2.10:3001)" = 143 ]
    [ "$(terminate_after /bin/bash "$NEXTDESTINY" 192.0.2.10:3001)" = 143 ]
}

@test "the network state accepts DHCP boot state, probes the xCAT port, and publishes readiness" {
    printf 'xcatd=127.0.0.1:%s BOOTIF=01-52-54-00-00-00-35\n' "$port" >"$XCAT_CMDLINE_FILE"
    accepted_before="$(wc -l <"$LISTENER_LOG")"
    network_state
    [ "$status" -eq 0 ]
    [ "$(wc -l <"$LISTENER_LOG")" -gt "$accepted_before" ]
    [ "$(cat "$state_dir/genesis.env")" = "XCATDEST=127.0.0.1:$port
XCATMASTER=127.0.0.1
XCATPORT=$port
XCAT_INTERFACE=eth0
XCAT_SOURCE_ADDRESS=192.0.2.98
XCAT_SOURCE_PREFIXED_ADDRESS=192.0.2.98/24
XCAT_GATEWAY=192.0.2.1
XCAT_DNS_SERVERS=192.0.2.53,2001:db8::53
XCAT_NETWORK_METHOD=auto
XCAT_LINK_STATE=up
XCAT_MAC_ADDRESS=52:54:00:00:00:35
XCAT_VERIFIED_SECONDS=123" ]
    [ "$(cat "$status_dir/network.env")" = 'SCHEMA=1
STATE=READY
DETAIL=Management network ready on eth0
STARTED_SECONDS=123
UPDATED_SECONDS=123
VERIFIED_SECONDS=123' ]
}

@test "network readiness does not depend on logging" {
    printf 'xcatd=127.0.0.1:%s BOOTIF=01-52-54-00-00-00-35\n' "$port" >"$XCAT_CMDLINE_FILE"
    XCAT_TEST_LOGGER_FAIL=1 network_state
    [ "$status" -eq 0 ]
}

@test "unsafe network data is rejected, never evaluated, and does not replace the prior state" {
    printf 'xcatd=127.0.0.1:%s BOOTIF=01-52-54-00-00-00-35\n' "$port" >"$XCAT_CMDLINE_FILE"
    network_state
    safe="$(cat "$state_dir/genesis.env")"
    XCAT_TEST_DNS="192.0.2.53;touch$root/injected" network_state
    [ "$status" -ne 0 ]
    [ "$(cat "$state_dir/genesis.env")" = "$safe" ]
    [ ! -e "$root/injected" ]
    grep -qx CODE=UNSAFE_NETWORK_STATE "$status_dir/network.env"
}

# Refresh renews the lease of the interface named in the current network state.
with_network_state()
{
    printf 'xcatd=127.0.0.1:%s BOOTIF=01-52-54-00-00-00-35\n' "$port" >"$XCAT_CMDLINE_FILE"
    network_state
    [ "$status" -eq 0 ]
    : >"$XCAT_TEST_LOG"
}

@test "discovery refreshes its DHCP identity on the selected interface and rebuilds the state" {
    with_network_state
    XCAT_NETWORK_STATE_COMMAND="$bin/network-state-refresh" run /bin/bash "$REFRESH_SCRIPT" 'restart (eth0)'
    [ "$status" -eq 0 ]
    grep -qx 'nmcli --wait 10 device disconnect eth1' "$XCAT_TEST_LOG"
    grep -qx 'nmcli --wait 10 device disconnect eth0' "$XCAT_TEST_LOG"
    grep -qx 'nmcli --wait 30 device connect eth0' "$XCAT_TEST_LOG"
    grep -qx network-state-refresh "$XCAT_TEST_LOG"
}

@test "a failed DHCP renewal returns an error, restores the connections, and publishes nothing" {
    with_network_state
    XCAT_TEST_CONNECT_FAIL=1 XCAT_NETWORK_STATE_COMMAND="$bin/network-state-refresh" \
        run /bin/bash "$REFRESH_SCRIPT" 'restart (eth0)'
    [ "$status" -ne 0 ]
    grep -qx 'nmcli --wait 30 connection up uuid connection-eth0 ifname eth0' "$XCAT_TEST_LOG"
    grep -qx 'nmcli --wait 30 connection up uuid connection-eth1 ifname eth1' "$XCAT_TEST_LOG"
    refute_grep -qx network-state-refresh "$XCAT_TEST_LOG"
}

@test "static boot settings are accepted, and a dotted netmask becomes a CIDR prefix" {
    printf 'xcatd=127.0.0.1:%s BOOTIF=01-52-54-00-00-00-35 hostip=192.0.2.98 netmask=255.255.255.192 gateway=192.0.2.1\n' \
        "$port" >"$XCAT_CMDLINE_FILE"
    network_state
    [ "$status" -eq 0 ]
    grep -q 'ipv4\.addresses 192\.0\.2\.98/26' "$XCAT_TEST_LOG"
}

@test "static IPv6 settings disable IPv4 and configure the IPv6 route" {
    printf 'xcatd=127.0.0.1:%s BOOTIF=01-52-54-00-00-00-35 hostip=2001:db8::98/64 netmask=64 gateway=2001:db8::1\n' \
        "$port" >"$XCAT_CMDLINE_FILE"
    network_state
    [ "$status" -eq 0 ]
    grep -q 'ipv4\.method disabled ipv6\.method manual ipv6\.addresses 2001:db8::98/64 ipv6\.gateway 2001:db8::1' \
        "$XCAT_TEST_LOG"
}

@test "partial static settings fail closed and replace the status with the rejected configuration" {
    printf 'xcatd=127.0.0.1:%s BOOTIF=01-52-54-00-00-00-35\n' "$port" >"$XCAT_CMDLINE_FILE"
    network_state
    printf 'xcatd=127.0.0.1:%s BOOTIF=01-52-54-00-00-00-35 hostip=192.0.2.98 netmask=255.255.255.0\n' \
        "$port" >"$XCAT_CMDLINE_FILE"
    network_state
    [ "$status" -ne 0 ]
    grep -qx STATE=FAILED "$status_dir/network.env"
    grep -qx CODE=INVALID_STATIC_NETWORK "$status_dir/network.env"
}

@test "registration keeps a kernel destiny, still contacts xCAT, and publishes the identity" {
    export XCATDEST=192.0.2.213:3001
    printf 'xcatd=192.0.2.213:3001 destiny=shell\n' >"$XCAT_CMDLINE_FILE"
    run /bin/bash "$REGISTER_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$(cat "$state_dir/destiny")" = shell ]
    grep -q 'getdestiny 192\.0\.2\.213:3001' "$XCAT_TEST_LOG"
    grep -qx STATE=ACTION_RECEIVED "$status_dir/registration.env"
    grep -A2 -x ACTION=shell "$status_dir/registration.env" | paste -sd' ' | grep -qx 'ACTION=shell TARGET= NODE_NAME=node042'
    XCAT_TEST_LOGGER_FAIL=1 run /bin/bash "$REGISTER_SCRIPT"
    [ "$status" -eq 0 ]
}

@test "registration requests a missing destiny, and rejects an empty one without replacing state" {
    export XCATDEST=192.0.2.213:3001
    printf 'xcatd=192.0.2.213:3001\n' >"$XCAT_CMDLINE_FILE"
    run /bin/bash "$REGISTER_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$(cat "$state_dir/destiny")" = standby ]
    XCAT_TEST_DESTINY='' run /bin/bash "$REGISTER_SCRIPT"
    [ "$status" -ne 0 ]
    [ "$(cat "$state_dir/destiny")" = standby ]
    grep -qx STATE=FAILED "$status_dir/registration.env"
    grep -A1 -x CODE=XCAT_RESPONSE_UNAVAILABLE "$status_dir/registration.env" | tail -n1 | grep -q '^RECOVERY='
}

@test "registration separates a legacy action from its argument" {
    export XCATDEST=192.0.2.213:3001
    printf 'xcatd=192.0.2.213:3001\n' >"$XCAT_CMDLINE_FILE"
    XCAT_TEST_DESTINY='install rocky9.7-x86_64-compute' run /bin/bash "$REGISTER_SCRIPT"
    [ "$status" -eq 0 ]
    grep -A1 -x ACTION=install "$status_dir/registration.env" | tail -n1 | grep -qx 'TARGET=rocky9.7-x86_64-compute'
}

@test "the status helper reduces the detail to printable text and keeps the stage start time" {
    run /bin/sh "$STATUS_SCRIPT" console DEGRADED $'bad\n\tvalue\x01'
    [ "$status" -eq 0 ]
    grep -qx 'DETAIL=bad  value' "$status_dir/console.env"
    printf '130.00 500.00\n' >"$XCAT_UPTIME_FILE"
    run /bin/sh "$STATUS_SCRIPT" console DEGRADED 'waiting for operator' CODE=OPERATOR_WAIT \
        'RECOVERY=Review diagnostics'
    [ "$status" -eq 0 ]
    [ "$(cat "$status_dir/console.env")" = 'SCHEMA=1
STATE=DEGRADED
DETAIL=waiting for operator
STARTED_SECONDS=123
UPDATED_SECONDS=130
CODE=OPERATOR_WAIT
RECOVERY=Review diagnostics' ]
}

@test "the status helper rejects an unsafe component, an unknown state and a bad number" {
    run /bin/sh "$STATUS_SCRIPT" ../console READY
    [ "$status" -ne 0 ]
    [[ "$output" == *'invalid component'* ]]
    [ ! -e "$state_dir/console.env" ]
    run /bin/sh "$STATUS_SCRIPT" console UNKNOWN
    [ "$status" -ne 0 ]
    [[ "$output" == *'invalid state'* ]]
    run /bin/sh "$STATUS_SCRIPT" console READY '' ATTEMPT=invalid
    [ "$status" -ne 0 ]
    [[ "$output" == *'invalid numeric field'* ]]
    [ ! -e "$status_dir/console.env" ]
}

@test "the maintenance shell reports a failure as the overall state, then prefers the action state" {
    mkdir -p "$status_dir"
    printf 'STATE=READY\n' >"$status_dir/network.env"
    printf 'STATE=FAILED\n' >"$status_dir/extensions.env"
    printf 'STATE=READY\n' >"$status_dir/registration.env"
    printf 'STATE=IDLE\n' >"$status_dir/action.env"
    run /bin/bash -c 'printf "exit\n" | /bin/bash "$1" 2>&1' genesis-maintenance-shell "$SHELL_SCRIPT"
    [ "$status" -eq 0 ]
    grep -qx 'Overall state: FAILED' <<<"$output"
    printf 'STATE=READY\n' >"$status_dir/extensions.env"
    run /bin/bash -c 'printf "exit\n" | /bin/bash "$1" 2>&1' genesis-maintenance-shell "$SHELL_SCRIPT"
    grep -qx 'Overall state: IDLE' <<<"$output"
}

@test "the maintenance shell runs by its own interpreter, identifies Genesis, and explains the return" {
    mkdir -p "$status_dir"
    IFS= read -r shebang <"$SHELL_SCRIPT"
    [ "$shebang" = '#!/bin/bash' ]
    run bash -c 'printf "exit\n" | "$1" "$2" 2>&1' genesis-maintenance-shell "${shebang#\#!}" "$SHELL_SCRIPT"
    [ "$status" -eq 0 ]
    grep -qx 'xCAT Genesis maintenance shell' <<<"$output"
    grep -qx 'Exit returns to the status console.' <<<"$output"
}

@test "the maintenance shell starts an isolated Bash with the genesis prompt" {
    mkdir -p "$status_dir" "$root/home"
    printf 'echo profile-was-read\n' >"$root/home/.bash_profile"
    printf 'echo rc-was-read\n' >"$root/home/.bashrc"
    run env HOME="$root/home" /bin/bash -c 'printf "exit\n" | /bin/bash "$1" 2>&1' \
        genesis-maintenance-shell "$SHELL_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *'genesis# '* ]]
    [[ "$output" != *profile-was-read* ]]
    [[ "$output" != *rc-was-read* ]]
}

@test "a status record replaces the previous one through a temporary file in the same directory" {
    # mv logs its arguments, then moves.
    printf '#!/bin/sh\nprintf "mv %%s\\n" "$*" >>"$XCAT_TEST_LOG"\nexec /bin/mv "$@"\n' >"$bin/mv"
    chmod 0755 "$bin/mv"
    run /bin/sh "$STATUS_SCRIPT" console READY 'ready'
    [ "$status" -eq 0 ]
    grep -Eqx "mv -f -- $status_dir/\.console\.[A-Za-z0-9]{6} $status_dir/console\.env" "$XCAT_TEST_LOG"
    [ "$(ls -A "$status_dir")" = console.env ]
}
