#!/usr/bin/env bats
#
# A DHCPv6 reservation is keyed on the DUID, and a DUID names the machine, not the nic.
# 10-xcat-genesis.conf puts the DHCPv6 settings in [connection], which NetworkManager applies to
# every nic, so each nic of a node asks for the same reserved address and Kea gives it to the
# first REQUEST. Measured on xcat88-cn, which has three nics on the provisioning bridge: the
# firmware and Genesis sent four solicits under one DUID and only one of them held 2001:db8:188::20.

load 'helpers/shell_source'

setup()
{
    SCRIPT="$(require_repo_file 'xCAT-genesis-base/oe/meta-xcat-genesis/recipes-connectivity/xcat-genesis-network/files/genesis-bootnic')"
    CONFD="${BATS_TEST_TMPDIR}/conf.d"
    CMDLINE="${BATS_TEST_TMPDIR}/cmdline"
    CONF="${CONFD}/16-xcat-genesis-bootnic.conf"
    mkdir -p "$CONFD"
    BIN="${BATS_TEST_TMPDIR}/bin"; mkdir -p "$BIN"
    printf '#!/bin/sh\nexit 0\n' >"$BIN/logger"; chmod 0755 "$BIN/logger"
}

run_bootnic()
{
    printf '%s\n' "$1" >"$CMDLINE"
    run env PATH="$BIN:$PATH" XCAT_CMDLINE_FILE="$CMDLINE" XCAT_NM_CONF_DIR="$CONFD" \
        bash "$SCRIPT"
}

@test "the boot nic keeps DHCPv6 and every other nic does not ask for an address" {
    run_bootnic 'quiet xcatd=[2001:db8:188::1]:3001 BOOTIF=01-42-7c-b6-21-e1-81'
    [ "$status" -eq 0 ]
    [ -r "$CONF" ]
    grep -q '^match-device=mac:42:7c:b6:21:e1:81$' "$CONF"
    grep -q '^match-device=except:mac:42:7c:b6:21:e1:81$' "$CONF"
    grep -q '^ipv6.method=auto$' "$CONF"
    grep -q '^ipv6.method=link-local$' "$CONF"
}

@test "an upper case BOOTIF is written as NetworkManager matches it" {
    run_bootnic 'BOOTIF=01-AA-BB-CC-DD-EE-FF'
    [ "$status" -eq 0 ]
    grep -q '^match-device=mac:aa:bb:cc:dd:ee:ff$' "$CONF"
}

@test "the file sorts after the DUID file, or NetworkManager would not read it last" {
    run_bootnic 'BOOTIF=01-42-7c-b6-21-e1-81'
    [ "$(ls "$CONFD")" = '16-xcat-genesis-bootnic.conf' ]
    [[ '16-xcat-genesis-bootnic.conf' > '15-xcat-genesis-duid.conf' ]]
}

@test "no BOOTIF leaves every nic as it was" {
    run_bootnic 'quiet xcatd=[2001:db8:188::1]:3001'
    [ "$status" -eq 0 ]
    refute_grep -q . <(ls "$CONFD")
}

@test "a BOOTIF that is not a hardware address leaves every nic as it was" {
    run_bootnic 'BOOTIF=01-not-a-mac'
    [ "$status" -eq 0 ]
    refute_grep -q . <(ls "$CONFD")
}

@test "an unreadable command line leaves every nic as it was" {
    rm -f "$CMDLINE"
    run env PATH="$BIN:$PATH" XCAT_CMDLINE_FILE="$CMDLINE" XCAT_NM_CONF_DIR="$CONFD" bash "$SCRIPT"
    [ "$status" -eq 0 ]
    refute_grep -q . <(ls "$CONFD")
}
