#!/usr/bin/env bats
#
# Drive the DHCP client selection out of doxcat.
#
# doxcat cannot be sourced: it restarts rsyslogd, reads /proc/cmdline and ends in a loop that
# waits for an address. Extract the two routines and run them with the clients shadowed by
# stubs that record their own argv.

load 'helpers/shell_source'

ISC4='dhclient -cf /etc/dhclient.conf -pf /var/run/dhclient.eth0.pid eth0'
ISC6='dhclient -6 -pf /var/run/dhclient6.eth0.pid eth0 -lf /var/lib/dhclient/dhclient6.leases'

setup()
{
    DOXCAT="$(repo_path 'xCAT-genesis-scripts/usr/bin/doxcat')"
    SPEC="$(repo_path 'xCAT-genesis-base/xCAT-genesis-base.spec')"
    MODULE="$(repo_path 'xCAT-genesis-base/dracut_105/el/module-setup.sh')"
    [ -r "$DOXCAT" ] || skip "$DOXCAT is required"
    [ -r "$SPEC" ] || skip "$SPEC is required"
    [ -r "$MODULE" ] || skip "$MODULE is required"
    export DOXCAT SPEC MODULE
}

# Run the extracted routines with only the named clients on PATH. Sets OUT to the standard
# output, RAN to the recorded argv of whatever ran, and STATUS to the exit status.
probe()
{
    local call="$1"
    shift
    local dir="${BATS_TEST_TMPDIR}/probe"
    local bin="$dir/bin" record="$dir/record" client selector runner

    selector="$(extract_shell_function "$DOXCAT" genesis_dhcp_command)" ||
        { echo 'doxcat carries no genesis_dhcp_command() to choose the client' >&2; return 99; }
    runner="$(extract_shell_function "$DOXCAT" genesis_start_dhcp)" ||
        { echo 'doxcat carries no genesis_start_dhcp() to run the chosen client' >&2; return 99; }

    rm -rf "$dir"
    mkdir -p "$bin"

    # PATH holds the stubs alone, so each one names itself rather than calling basename.
    for client in "$@"; do
        printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 0\n' "$client" "$record" >"$bin/$client"
        chmod 0755 "$bin/$client"
    done

    # logger writes to the console in the image and is not what these assertions measure.
    printf '#!/bin/sh\nexit 0\n' >"$bin/logger"
    chmod 0755 "$bin/logger"

    printf 'log_label=test\n%s\n%s\n%s\n' "$selector" "$runner" "$call" >"$dir/probe.sh"
    OUT="$(PATH="$bin" /bin/bash "$dir/probe.sh" 2>/dev/null)" && STATUS=0 || STATUS=$?
    RAN="$(read_file_or_empty "$record")"
    return 0
}

selected()
{
    local family="$1"
    shift
    probe "genesis_dhcp_command $family eth0" "$@"
    printf '%s\n' "$OUT"
}

started()
{
    local family="$1"
    shift
    probe "genesis_start_dhcp $family eth0" "$@"
    printf '%s\n' "$RAN"
}

@test "doxcat names no DHCP client directly" {
    # A release that packages no ISC client has no dhclient.
    refute_grep -qE '^[[:space:]]*dhclient[[:space:]]' "$DOXCAT"
    refute_grep -qE ';[[:space:]]*dhclient[[:space:]]' "$DOXCAT"
}

@test "the build root and the payload check name the client the release ships" {
    # EL8 and EL9 package the ISC client; AlmaLinux 10 baseos packages dhcpcd. The payload
    # check has to name the client too, or the build passes with no client in the image again.
    grep -A1 '^%if 0%{?rhel} >= 10$' "$SPEC" | grep -qx 'BuildRequires: dhcpcd'
    grep -A1 '^%if 0%{?rhel} >= 10$' "$SPEC" | grep -qx 'GENESIS_REQUIRED="usr/sbin/dhcpcd"'
}

@test "the dracut module installs the client the build root carries" {
    # dracut_install reports a missing binary and returns, so naming dhclient alone shipped an
    # image with no client at all.
    refute_grep -qE '^[[:space:]]*dracut_install dhclient lldpad$' "$MODULE"
    grep -qE '^[[:space:]]*dracut_install dhcpcd$' "$MODULE"
    grep -qE '^[[:space:]]*dracut_install /usr/libexec/dhcpcd-run-hooks$' "$MODULE"
}

@test "the ISC client keeps its command lines and is preferred when both are present" {
    [ "$(selected 4 dhclient)" = "$ISC4" ]
    [ "$(selected 6 dhclient)" = "$ISC6" ]
    [ "$(selected 4 dhclient dhcpcd)" = "$ISC4" ]
}

@test "dhcpcd stands in for dhclient, waiting for a lease and keeping the address" {
    # dhcpcd on a single interface exits when its timeout expires, and the default is 30
    # seconds; doxcat waits for the lease for as long as it takes. dhcpcd also de-configures
    # the interface when it exits unless it is persistent.
    [ "$(selected 4 dhcpcd)" = 'dhcpcd -4 -b -p -t 0 eth0' ]
    [ "$(selected 6 dhcpcd)" = 'dhcpcd -6 -b -p -t 0 eth0' ]
    [[ "$(selected 4 dhcpcd)" =~ (^|[[:space:]])-t\ 0([[:space:]]|$) ]]
    [[ "$(selected 4 dhcpcd)" =~ (^|[[:space:]])-p([[:space:]]|$) ]]
}

@test "an image with no client chooses nothing, runs nothing and reports a failure" {
    [ "$(selected 4)" = '' ]
    [ "$(started 4)" = '' ]

    probe 'genesis_start_dhcp 4 eth0'
    [ "$STATUS" -ne 0 ]
}

@test "genesis_start_dhcp runs the client it chose" {
    [ "$(started 4 dhcpcd)" = 'dhcpcd -4 -b -p -t 0 eth0' ]
    [ "$(started 4 dhclient)" = "$ISC4" ]
}
