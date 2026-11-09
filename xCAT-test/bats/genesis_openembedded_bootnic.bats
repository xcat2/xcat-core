#!/usr/bin/env bats
#
# A DHCPv6 reservation is keyed on the DUID, and a DUID names the machine, not the nic.
# 10-xcat-genesis.conf puts the DHCPv6 settings in [connection], which NetworkManager applies to
# every nic, so each nic of a node asks for the same reserved address and Kea gives it to the
# first REQUEST. Measured on xcat88-cn, which has three nics on the provisioning bridge: the
# firmware and Genesis sent four solicits under one DUID and only one of them held 2001:db8:188::20.
#
# NetworkManager.conf(5) does not list ipv6.method among the properties a [connection] section
# can default, so the restriction has to be a connection profile.

load 'helpers/shell_source'

setup()
{
    SCRIPT="$(require_repo_file 'xCAT-genesis-base/oe/meta-xcat-genesis/recipes-connectivity/xcat-genesis-network/files/genesis-bootnic')"
    CONFD="${BATS_TEST_TMPDIR}/conf.d"
    CONND="${BATS_TEST_TMPDIR}/system-connections"
    CMDLINE="${BATS_TEST_TMPDIR}/cmdline"
    BOOT="${CONND}/xcat-genesis-bootnic.nmconnection"
    SECONDARY="${CONND}/xcat-genesis-secondary.nmconnection"
    mkdir -p "$CONFD"
    BIN="${BATS_TEST_TMPDIR}/bin"; mkdir -p "$BIN"
    printf '#!/bin/sh\nexit 0\n' >"$BIN/logger"; chmod 0755 "$BIN/logger"
}

run_bootnic()
{
    printf '%s\n' "$1" >"$CMDLINE"
    run env PATH="$BIN:$PATH" XCAT_CMDLINE_FILE="$CMDLINE" XCAT_NM_CONF_DIR="$CONFD" \
        XCAT_NM_CONNECTION_DIR="$CONND" bash "$SCRIPT"
}

# keyfile_value <file> <section> <key>: the value NetworkManager reads for section.key.
keyfile_value()
{
    awk -v section="[$2]" -v key="$3" '
        /^\[/ { in_section = ($0 == section); next }
        in_section && index($0, key "=") == 1 { print substr($0, length(key) + 2) }
    ' "$1"
}

@test "the boot nic profile is bound to the BOOTIF address and asks for DHCPv6" {
    run_bootnic 'quiet xcatd=[2001:db8:188::1]:3001 BOOTIF=01-42-7c-b6-21-e1-81'
    [ "$status" -eq 0 ]
    [ "$(keyfile_value "$BOOT" connection type)" = ethernet ]
    [ "$(keyfile_value "$BOOT" ethernet mac-address)" = '42:7c:b6:21:e1:81' ]
    [ "$(keyfile_value "$BOOT" ipv6 method)" = auto ]
    [ "$(keyfile_value "$BOOT" ipv4 method)" = auto ]
}

@test "every other nic keeps a link-local address and does not ask for one" {
    run_bootnic 'BOOTIF=01-42-7c-b6-21-e1-81'
    [ "$status" -eq 0 ]
    [ "$(keyfile_value "$SECONDARY" connection type)" = ethernet ]
    [ -z "$(keyfile_value "$SECONDARY" ethernet mac-address)" ]
    [ "$(keyfile_value "$SECONDARY" ipv6 method)" = link-local ]
    # 3 is multiple: one profile active on every secondary nic at once.
    [ "$(keyfile_value "$SECONDARY" connection multi-connect)" = 3 ]
}

@test "NetworkManager prefers the boot nic profile on the boot nic" {
    run_bootnic 'BOOTIF=01-42-7c-b6-21-e1-81'
    boot_priority=$(keyfile_value "$BOOT" connection autoconnect-priority)
    secondary_priority=$(keyfile_value "$SECONDARY" connection autoconnect-priority)
    [ "$boot_priority" -gt "$secondary_priority" ]
}

@test "the profiles are private to root, or NetworkManager does not load them" {
    run_bootnic 'BOOTIF=01-42-7c-b6-21-e1-81'
    [ "$(stat -c %a "$BOOT")" = 600 ]
    [ "$(stat -c %a "$SECONDARY")" = 600 ]
}

@test "no connection default carries ipv6.method, which NetworkManager ignores there" {
    run_bootnic 'BOOTIF=01-42-7c-b6-21-e1-81'
    refute_grep -rq '^ipv6.method=' "$CONFD"
}

@test "an upper case BOOTIF is written as NetworkManager matches it" {
    run_bootnic 'BOOTIF=01-AA-BB-CC-DD-EE-FF'
    [ "$status" -eq 0 ]
    [ "$(keyfile_value "$BOOT" ethernet mac-address)" = 'aa:bb:cc:dd:ee:ff' ]
}

@test "no BOOTIF leaves every nic as it was" {
    run_bootnic 'quiet xcatd=[2001:db8:188::1]:3001'
    [ "$status" -eq 0 ]
    [ ! -e "$CONND" ] || refute_grep -q . <(ls "$CONND")
    refute_grep -q . <(ls "$CONFD")
}

@test "a BOOTIF that is not a hardware address leaves every nic as it was" {
    run_bootnic 'BOOTIF=01-not-a-mac'
    [ "$status" -eq 0 ]
    [ ! -e "$CONND" ] || refute_grep -q . <(ls "$CONND")
    refute_grep -q . <(ls "$CONFD")
}

@test "an unreadable command line leaves every nic as it was" {
    rm -f "$CMDLINE"
    run env PATH="$BIN:$PATH" XCAT_CMDLINE_FILE="$CMDLINE" XCAT_NM_CONF_DIR="$CONFD" \
        XCAT_NM_CONNECTION_DIR="$CONND" bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -e "$CONND" ] || refute_grep -q . <(ls "$CONND")
}
