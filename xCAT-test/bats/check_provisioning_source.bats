#!/usr/bin/env bats
#
# Drive check_provisioning_source.sh, which is what tells a hierarchical provision from a flat
# one. The management node, the service node and the compute node share one subnet and both
# dhcpd instances answer for the compute node, so the management node can win the xNBA exchange
# and serve the boot payload itself. The httpd access logs are the only record of that.
#
# The check takes a baseline of both logs before provisioning and reads only what came after, so
# these tests write the old lines, take the baseline, then append the lines of the run.
#
# lsdef, xdsh and hostname are stubbed. XCAT_HTTPD_ACCESS_LOG is the management node's log.

load 'helpers/shell_source'

CN=cn01
SN=sn01
CN_IP=192.0.2.10

setup()
{
    SCRIPT="$(require_repo_file 'xCAT-test/autotest/testcase/commoncmd/check_provisioning_source.sh')"
    BIN="${BATS_TEST_TMPDIR}/bin"
    MN_LOG="${BATS_TEST_TMPDIR}/mn-access_log"
    SN_LOG="${BATS_TEST_TMPDIR}/sn-access_log"
    STATE="${BATS_TEST_TMPDIR}/baseline"
    mkdir -p "$BIN"
    : >"$MN_LOG"
    : >"$SN_LOG"

    printf '#!/bin/sh\nprintf "Object name: %s\\n    ip=%s\\n" "$3" "%s"\n' "%s" "%s" "$CN_IP" >"$BIN/lsdef"
    printf '#!/bin/sh\necho mn01\n' >"$BIN/hostname"
    # A test that reaches the network measures the lab, not this script.
    printf '#!/bin/sh\necho "unexpected getent $*" >&2\nexit 1\n' >"$BIN/getent"
    # xdsh -e copies the script to the service node and runs it there. Run it here instead, with
    # the service node log in place of the management node one, and prefix the node name as xdsh
    # does.
    printf '#!/bin/sh\nnode=$1\nshift\n[ "$1" = "-e" ] && shift\nscript=$1\nshift\nXCAT_HTTPD_ACCESS_LOG=%s "$script" "$@" | sed "s/^/$node: /"\n' \
        "$SN_LOG" >"$BIN/xdsh"
    chmod 0755 "$BIN"/*

    export PATH="$BIN:$PATH"
}

# One access-log line in the combined format: $1 client, $2 bytes, $3 path.
access_line()
{
    printf '%s - - [01/Jan/2026:00:00:00 +0000] "GET %s HTTP/1.1" 200 %s "-" "iPXE"\n' "$1" "$3" "$2"
}

take_baseline()
{
    env XCAT_HTTPD_ACCESS_LOG="$MN_LOG" XCAT_PROV_SOURCE_STATE="$STATE" \
        "$SCRIPT" --baseline "$CN" "$SN" >/dev/null
}

run_check()
{
    run env XCAT_HTTPD_ACCESS_LOG="$MN_LOG" XCAT_PROV_SOURCE_STATE="$STATE" "$SCRIPT" "$CN" "$SN"
}

# A log that has to hold something at baseline time, so the baseline is not trivially zero.
seed_logs()
{
    access_line 192.0.2.30 512 /install/rh/x86_64/ >"$SN_LOG"
    access_line 192.0.2.31 512 /install/rh/x86_64/ >"$MN_LOG"
}

@test "a service node that served the compute node and a silent management node pass" {
    seed_logs
    take_baseline
    access_line "$CN_IP" 12345678 /tftpboot/xcat/genesis.kernel >>"$SN_LOG"
    access_line 192.0.2.21 4096 /install/rh/x86_64/ >>"$MN_LOG"

    run_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"provisioning source ok"* ]]
}

@test "a management node request from BEFORE the baseline does not fail this run" {
    access_line "$CN_IP" 12345678 /tftpboot/xcat/genesis.kernel >"$MN_LOG"
    access_line 192.0.2.30 512 /install/rh/x86_64/ >"$SN_LOG"
    take_baseline
    access_line "$CN_IP" 12345678 /tftpboot/xcat/genesis.kernel >>"$SN_LOG"
    access_line 192.0.2.21 4096 /install/rh/x86_64/ >>"$MN_LOG"

    run_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"provisioning source ok"* ]]
}

@test "a service node request from BEFORE the baseline does not satisfy the check" {
    access_line "$CN_IP" 12345678 /tftpboot/xcat/genesis.kernel >"$SN_LOG"
    access_line 192.0.2.31 512 /install/rh/x86_64/ >"$MN_LOG"
    take_baseline
    access_line 192.0.2.21 4096 /install/rh/x86_64/ >>"$MN_LOG"

    run_check
    [ "$status" -ne 0 ]
    [[ "$output" == *"no boot payload"* ]]
}

@test "a request that carries no boot payload does not satisfy the check" {
    seed_logs
    take_baseline
    printf '%s - - [01/Jan/2026:00:00:00 +0000] "GET /favicon.ico HTTP/1.1" 404 209 "-" "iPXE"\n' \
        "$CN_IP" >>"$SN_LOG"
    access_line 192.0.2.21 4096 /install/rh/x86_64/ >>"$MN_LOG"

    run_check
    [ "$status" -ne 0 ]
    [[ "$output" == *"no boot payload"* ]]
}

@test "a management node request that carries no boot payload does not read as a flat provision" {
    seed_logs
    take_baseline
    access_line "$CN_IP" 12345678 /tftpboot/xcat/genesis.kernel >>"$SN_LOG"
    printf '%s - - [01/Jan/2026:00:00:00 +0000] "GET /favicon.ico HTTP/1.1" 404 209 "-" "iPXE"\n' \
        "$CN_IP" >>"$MN_LOG"

    run_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"provisioning source ok"* ]]
}

@test "the check refuses to answer with no baseline" {
    seed_logs
    access_line "$CN_IP" 12345678 /tftpboot/xcat/genesis.kernel >>"$SN_LOG"

    run_check
    [ "$status" -ne 0 ]
    [[ "$output" == *"no baseline"* ]]
    [[ "$output" != *"provisioning source ok"* ]]
}

@test "a log rotated below its baseline is read from its first line" {
    for i in 1 2 3 4 5; do access_line 192.0.2.30 512 /install/rh/x86_64/; done >"$SN_LOG"
    access_line 192.0.2.31 512 /install/rh/x86_64/ >"$MN_LOG"
    take_baseline
    access_line "$CN_IP" 12345678 /tftpboot/xcat/genesis.kernel >"$SN_LOG"
    access_line 192.0.2.21 4096 /install/rh/x86_64/ >>"$MN_LOG"

    run_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"provisioning source ok"* ]]
}

@test "the management node answering for the compute node fails the check" {
    seed_logs
    take_baseline
    access_line "$CN_IP" 12345678 /tftpboot/xcat/genesis.kernel >>"$SN_LOG"
    {
        access_line 192.0.2.21 4096 /install/rh/x86_64/
        access_line "$CN_IP" 12345678 /tftpboot/xcat/genesis.kernel
    } >>"$MN_LOG"

    run_check
    [ "$status" -ne 0 ]
    [[ "$output" == *"this provision was flat"* ]]
    [[ "$output" != *"provisioning source ok"* ]]
}

@test "a management node answering only a bodyless request still fails the check" {
    seed_logs
    take_baseline
    access_line "$CN_IP" 12345678 /tftpboot/xcat/genesis.kernel >>"$SN_LOG"
    {
        access_line 192.0.2.21 4096 /install/rh/x86_64/
        printf '%s - - [01/Jan/2026:00:00:00 +0000] "HEAD %s HTTP/1.1" 304 - "-" "iPXE"\n' \
            "$CN_IP" /tftpboot/xcat/genesis.kernel
    } >>"$MN_LOG"

    run_check
    [ "$status" -ne 0 ]
    [[ "$output" == *"this provision was flat"* ]]
}

@test "a service node that served the compute node nothing fails the check" {
    seed_logs
    take_baseline
    access_line 192.0.2.22 4096 /install/rh/x86_64/ >>"$SN_LOG"
    access_line 192.0.2.21 4096 /install/rh/x86_64/ >>"$MN_LOG"

    run_check
    [ "$status" -ne 0 ]
    [[ "$output" == *"no boot payload"* ]]
}

@test "an unreadable service node log fails the check instead of passing it" {
    seed_logs
    take_baseline
    access_line 192.0.2.21 4096 /install/rh/x86_64/ >>"$MN_LOG"
    printf '#!/bin/sh\nexit 1\n' >"$BIN/xdsh"
    chmod 0755 "$BIN/xdsh"

    run_check
    [ "$status" -ne 0 ]
    [[ "$output" == *"no httpd access log could be read on $SN"* ]]
}

# The service node is provisioned before the baseline, so on a correct hierarchical run the
# management node serves nothing after it and its log does not grow. Every other case here appends
# a management-node line after the baseline, so none of them reaches this state.
@test "a management node log that does not grow after the baseline still passes" {
    seed_logs
    take_baseline
    access_line "$CN_IP" 12345678 /tftpboot/xcat/genesis.kernel >>"$SN_LOG"

    run_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"provisioning source ok"* ]]
}

# The guard the case above relaxes still has a job. An empty log makes "the management node served
# nothing" a property of the file, not a measurement.
@test "an empty management node log fails the check instead of passing it" {
    : >"$MN_LOG"
    access_line 192.0.2.30 512 /install/rh/x86_64/ >"$SN_LOG"
    take_baseline
    access_line "$CN_IP" 12345678 /tftpboot/xcat/genesis.kernel >>"$SN_LOG"

    run_check
    [ "$status" -ne 0 ]
    [[ "$output" == *"no httpd access log with entries could be read on"* ]]
    [[ "$output" != *"provisioning source ok"* ]]
}

@test "the Debian per-vhost log format is read as the client address" {
    seed_logs
    take_baseline
    printf 'xcat:80 %s - - [01/Jan/2026:00:00:00 +0000] "GET %s HTTP/1.1" 200 12345678\n' \
        "$CN_IP" /tftpboot/xcat/genesis.kernel >>"$SN_LOG"
    printf 'xcat:80 %s - - [01/Jan/2026:00:00:00 +0000] "GET %s HTTP/1.1" 200 4096\n' \
        192.0.2.21 /install/ubuntu/x86_64/ >>"$MN_LOG"

    run_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"provisioning source ok"* ]]
}

@test "a compute node with no address fails the check" {
    seed_logs
    take_baseline
    printf '#!/bin/sh\nexit 1\n' >"$BIN/lsdef"
    printf '#!/bin/sh\nexit 2\n' >"$BIN/getent"
    chmod 0755 "$BIN/lsdef" "$BIN/getent"
    access_line "$CN_IP" 12345678 /tftpboot/xcat/genesis.kernel >>"$SN_LOG"
    access_line 192.0.2.21 4096 /install/rh/x86_64/ >>"$MN_LOG"

    run_check
    [ "$status" -ne 0 ]
    [[ "$output" == *"has no address"* ]]
}
