#!/usr/bin/env bats
#
# genesis-duid runs in the OpenEmbedded Genesis image before NetworkManager. It turns the
# SMBIOS UUID into the DUID-UUID that the xCAT DHCPv6 reservation holds, and writes it into
# a NetworkManager conf.d drop-in that sorts after the packaged DUID-LL default.
#
# The expected DUIDs are the same literals as xCAT-test/bats/genesis_duid_uuid.bats, which
# holds the legacy image to the same byte order, and as the Kea reservation in
# xCAT-test/unit/dhcp_kea_plugin_intent.t. logger is a scratch script that logs its
# arguments.

load 'helpers/shell_source'

NETWORK='xCAT-genesis-base/oe/meta-xcat-genesis/recipes-connectivity/xcat-genesis-network'

setup()
{
    # repo_path, not require_repo_file: this repository ships the script, so an absent one
    # has to fail rather than skip.
    DUID_SCRIPT="$(repo_path "$NETWORK/files/genesis-duid")"
    PACKAGED_CONF="$(require_repo_file "$NETWORK/files/10-xcat-genesis.conf")"
    bin="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$bin"
    printf '#!/bin/sh\nprintf "logger %%s\\n" "$*" >>"$XCAT_TEST_LOG"\n' >"$bin/logger"
    chmod 0755 "$bin"/*

    export PATH="$bin:$PATH"
    export XCAT_PRODUCT_UUID_FILE="$BATS_TEST_TMPDIR/product_uuid"
    export XCAT_NM_CONF_DIR="$BATS_TEST_TMPDIR/conf.d"
    export XCAT_TEST_LOG="$BATS_TEST_TMPDIR/commands.log"
    mkdir -p "$XCAT_NM_CONF_DIR"
    cp "$PACKAGED_CONF" "$XCAT_NM_CONF_DIR/10-xcat-genesis.conf"
    : >"$XCAT_TEST_LOG"
    drop_in="$XCAT_NM_CONF_DIR/15-xcat-genesis-duid.conf"
}

# Run genesis-duid against a product_uuid. $status is its exit status.
run_duid()
{
    printf '%s\n' "$1" >"$XCAT_PRODUCT_UUID_FILE"
    run /bin/bash "$DUID_SCRIPT"
}

# The conf.d file names, in the order NetworkManager reads them.
conf_order()
{
    (cd "$XCAT_NM_CONF_DIR" && printf '%s\n' * | LC_ALL=C sort)
}

@test "the DUID carries the first three SMBIOS fields in firmware order" {
    run_duid 00112233-4455-6677-8899-aabbccddeeff
    [ "$status" -eq 0 ]
    [ "$(cat "$drop_in")" = '[connection]
ipv6.dhcp-duid=00:04:33:22:11:00:55:44:77:66:88:99:aa:bb:cc:dd:ee:ff' ]
}

@test "a second UUID gives its own DUID, swapped the same way" {
    run_duid aabbccdd-eeff-0011-2233-445566778899
    [ "$status" -eq 0 ]
    [ "$(cat "$drop_in")" = '[connection]
ipv6.dhcp-duid=00:04:dd:cc:bb:aa:ff:ee:11:00:22:33:44:55:66:77:88:99' ]
}

@test "an uppercase SMBIOS UUID gives the same DUID as its lowercase form" {
    run_duid 00112233-4455-6677-8899-AABBCCDDEEFF
    [ "$status" -eq 0 ]
    [ "$(cat "$drop_in")" = '[connection]
ipv6.dhcp-duid=00:04:33:22:11:00:55:44:77:66:88:99:aa:bb:cc:dd:ee:ff' ]
}

@test "the drop-in overrides the packaged DUID-LL, because it is read later" {
    run_duid 00112233-4455-6677-8899-aabbccddeeff
    [ "$status" -eq 0 ]
    [ "$(conf_order)" = '10-xcat-genesis.conf
15-xcat-genesis-duid.conf' ]
    grep -Fx 'ipv6.dhcp-duid=ll' "$XCAT_NM_CONF_DIR/10-xcat-genesis.conf"
}

@test "a machine with no SMBIOS UUID keeps the packaged DUID-LL" {
    rm -f "$XCAT_PRODUCT_UUID_FILE"
    run /bin/bash "$DUID_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$(conf_order)" = 10-xcat-genesis.conf ]
    grep -F 'keeping the DUID-LL default' "$XCAT_TEST_LOG"
}

@test "a machine whose SMBIOS UUID is not sixteen bytes keeps the packaged DUID-LL" {
    run_duid 'Not Settable'
    [ "$status" -eq 0 ]
    [ "$(conf_order)" = 10-xcat-genesis.conf ]
    grep -F 'no usable SMBIOS UUID' "$XCAT_TEST_LOG"
}

@test "a conf.d directory that cannot be created fails loudly" {
    # A regular file in the way, so mkdir -p fails for root as well.
    printf 'not a directory\n' >"$BATS_TEST_TMPDIR/blocked"
    XCAT_NM_CONF_DIR="$BATS_TEST_TMPDIR/blocked/conf.d" run_duid \
        00112233-4455-6677-8899-aabbccddeeff
    [ "$status" -eq 1 ]
    grep -F 'unable to create' "$XCAT_TEST_LOG"
}
