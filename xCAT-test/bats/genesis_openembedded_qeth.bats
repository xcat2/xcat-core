#!/usr/bin/env bats
#
# genesis-qeth runs in the s390x Genesis image before NetworkManager. It groups the qeth
# channels named by rd.znet=qeth on the kernel command line, or found by znetconf -u, and
# publishes the result. znetconf, genesis-status and logger are scratch scripts that log
# their arguments; znetconf answers -c and -u from files.

load 'helpers/shell_source'

QETH='xCAT-genesis-base/oe/meta-xcat-genesis/recipes-connectivity/xcat-genesis-qeth/files/genesis-qeth'

setup()
{
    QETH_SCRIPT="$(require_repo_file "$QETH")"
    bin="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$bin"
    cat >"$bin/znetconf" <<'SH'
#!/bin/sh
printf 'znetconf %s\n' "$*" >>"$XCAT_TEST_LOG"
case "$1" in
    -c)
        cat "$XCAT_TEST_CONFIGURED"
        exit "${XCAT_TEST_CONFIGURED_STATUS:-0}"
        ;;
    -u)
        cat "$XCAT_TEST_UNCONFIGURED"
        exit "${XCAT_TEST_UNCONFIGURED_STATUS:-0}"
        ;;
    -a)
        [ "${XCAT_TEST_FAIL_CHANNELS:-}" != "$2" ]
        ;;
esac
SH
    printf '#!/bin/sh\nprintf "status %%s\\n" "$*" >>"$XCAT_TEST_LOG"\n' >"$bin/genesis-status"
    printf '#!/bin/sh\nprintf "logger %%s\\n" "$*" >>"$XCAT_TEST_LOG"\n' >"$bin/logger"
    chmod 0755 "$bin"/*

    export PATH="$bin:$PATH"
    export XCAT_CIO_SETTLE_FILE="$BATS_TEST_TMPDIR/cio_settle"
    export XCAT_CMDLINE_FILE="$BATS_TEST_TMPDIR/cmdline"
    export XCAT_STATUS_COMMAND="$bin/genesis-status"
    export XCAT_ZNETCONF_COMMAND="$bin/znetconf"
    export XCAT_TEST_CONFIGURED="$BATS_TEST_TMPDIR/configured"
    export XCAT_TEST_UNCONFIGURED="$BATS_TEST_TMPDIR/unconfigured"
    export XCAT_TEST_LOG="$BATS_TEST_TMPDIR/commands.log"
    : >"$XCAT_CIO_SETTLE_FILE"
    : >"$XCAT_TEST_CONFIGURED"
    : >"$XCAT_TEST_UNCONFIGURED"
    : >"$XCAT_TEST_LOG"
}

# Run genesis-qeth with a kernel command line. $status is its exit status.
run_qeth()
{
    printf '%s\n' "$1" >"$XCAT_CMDLINE_FILE"
    run /bin/bash "$QETH_SCRIPT"
}

activations()
{
    grep '^znetconf -a ' "$XCAT_TEST_LOG" || true
}

@test "a system without ccwgroup devices needs no qeth setup, after CIO work settles" {
    XCAT_TEST_UNCONFIGURED_STATUS=31 run_qeth 'console=ttysclp0 xcatd=192.0.2.1'
    [ "$status" -eq 0 ]
    [ -z "$(activations)" ]
    [ "$(cat "$XCAT_CIO_SETTLE_FILE")" = 1 ]
}

@test "configured qeth devices need no activation" {
    printf '0.0.0500,0.0.0501,0.0.0502 1731/01 OSA 10 qeth enc500 online\n' >"$XCAT_TEST_CONFIGURED"
    run_qeth 'console=ttysclp0 xcatd=192.0.2.1'
    [ "$status" -eq 0 ]
    [ -z "$(activations)" ]
}

@test "an explicit qeth triplet is normalized, defaults to layer 2, and is published" {
    run_qeth 'rd.znet=qeth,0600,0.0.0601,0.0.0602,portno=1 xcatd=192.0.2.1'
    [ "$status" -eq 0 ]
    [ "$(activations)" = 'znetconf -a 0.0.0600,0.0.0601,0.0.0602 -d qeth -o portno=1 -o layer2=1' ]
    grep -qx 'status network CONFIGURING_NETWORK qeth devices are ready' "$XCAT_TEST_LOG"
}

@test "a duplicate qeth triplet is grouped once" {
    run_qeth 'rd.znet=qeth,0.0.0600,0.0.0601,0.0.0602 rd.znet=qeth,0.0.0600,0.0.0601,0.0.0602 xcatd=192.0.2.1'
    [ "$status" -eq 0 ]
    [ "$(activations | grep -c '^znetconf -a 0\.0\.0600,0\.0\.0601,0\.0\.0602 ')" -eq 1 ]
}

@test "explicit qeth options are accepted, and an explicit layer is not overridden" {
    run_qeth 'rd.znet=qeth,0.0.0610,0.0.0611,0.0.0612,layer2=0,portname=test xcatd=192.0.2.1'
    [ "$status" -eq 0 ]
    [ "$(activations)" = 'znetconf -a 0.0.0610,0.0.0611,0.0.0612 -d qeth -o layer2=0 -o portname=test' ]
}

@test "an already configured triplet is left unchanged" {
    printf '0.0.0620,0.0.0621,0.0.0622 1731/01 OSA 10 qeth enc600 online\n' >"$XCAT_TEST_CONFIGURED"
    run_qeth 'rd.znet=qeth,0.0.0620,0.0.0621,0.0.0622 xcatd=192.0.2.1'
    [ "$status" -eq 0 ]
    [ -z "$(activations)" ]
}

@test "unconfigured qeth devices are discovered and activated for DHCP, other types are not" {
    printf '%s\n' 'Scanning for network devices...' \
        'Device IDs                 Type    Card Type      CHPID Drv.' \
        '0.0.0710,0.0.0711          3088/60 LCS OSA         20 lcs' \
        '0.0.0700,0.0.0701,0.0.0702 1731/01 OSA (QDIO)       10 qeth' >"$XCAT_TEST_UNCONFIGURED"
    run_qeth 'xcatd=192.0.2.1'
    [ "$status" -eq 0 ]
    [ "$(activations)" = 'znetconf -a 0.0.0700,0.0.0701,0.0.0702 -d qeth -o layer2=1' ]
}

@test "a qeth discovery error is returned and published" {
    XCAT_TEST_UNCONFIGURED_STATUS=9 run_qeth 'xcatd=192.0.2.1'
    [ "$status" -eq 9 ]
    grep -q '^status network DEGRADED Unable to inspect qeth devices' "$XCAT_TEST_LOG"
}

@test "a non-qeth rd.znet entry disables qeth discovery and activates nothing" {
    printf '0.0.0700,0.0.0701,0.0.0702 1731/01 OSA 10 qeth\n' >"$XCAT_TEST_UNCONFIGURED"
    run_qeth 'rd.znet=ctc,0.0.0800,0.0.0801 xcatd=192.0.2.1'
    [ "$status" -eq 0 ]
    refute_grep -qx 'znetconf -u' "$XCAT_TEST_LOG"
    [ -z "$(activations)" ]
}

@test "an incomplete qeth triplet fails with a degraded status" {
    run_qeth 'rd.znet=qeth,0.0.0900,0.0.0901 xcatd=192.0.2.1'
    [ "$status" -eq 1 ]
    grep -q '^status network DEGRADED One or more qeth devices' "$XCAT_TEST_LOG"
}

@test "an invalid qeth option fails before activation" {
    run_qeth 'rd.znet=qeth,0.0.0910,0.0.0911,0.0.0912,bad?=1 xcatd=192.0.2.1'
    [ "$status" -eq 1 ]
    [ -z "$(activations)" ]
}

@test "failure of one qeth triplet is reported, and the others are still attempted" {
    XCAT_TEST_FAIL_CHANNELS=0.0.0a00,0.0.0a01,0.0.0a02 \
        run_qeth 'rd.znet=qeth,0.0.0a00,0.0.0a01,0.0.0a02 rd.znet=qeth,0.0.0b00,0.0.0b01,0.0.0b02 xcatd=192.0.2.1'
    [ "$status" -eq 1 ]
    activations | grep -q '^znetconf -a 0\.0\.0b00,0\.0\.0b01,0\.0\.0b02 '
}
