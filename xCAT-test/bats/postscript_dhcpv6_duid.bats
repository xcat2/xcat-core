#!/usr/bin/env bats
#
# configdhcpv6duid writes the DHCPv6 client identifier of an installed node, for whichever
# renderer it has. The reservation makedhcp writes carries one identifier, so a client that
# derives its own from the machine-id or a lease matches nothing.
#
# The expected DUID is the same literal as xCAT-test/bats/genesis_duid_uuid.bats and
# genesis_openembedded_duid.bats, which hold the two Genesis images to this byte order, and as
# the Kea reservation in xCAT-test/unit/dhcp_kea_plugin_intent.t. NetworkManager takes the whole
# DUID; systemd-networkd names the type and takes the sixteen UUID bytes alone.

load 'helpers/shell_source'

DUID=00:04:33:22:11:00:55:44:77:66:88:99:aa:bb:cc:dd:ee:ff
RAW=33:22:11:00:55:44:77:66:88:99:aa:bb:cc:dd:ee:ff

setup()
{
    SCRIPT="$(repo_path 'xCAT/postscripts/configdhcpv6duid')"
    bin="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$bin"
    printf '#!/bin/sh\nprintf "logger %%s\\n" "$*" >>"$XCAT_TEST_LOG"\n' >"$bin/logger"
    chmod 0755 "$bin"/*
    export PATH="$bin:$PATH"
    export XCAT_PRODUCT_UUID_FILE="$BATS_TEST_TMPDIR/product_uuid"
    export XCAT_NM_CONF_DIR="$BATS_TEST_TMPDIR/nm"
    export XCAT_NETWORKD_CONF_DIR="$BATS_TEST_TMPDIR/nd"
    export XCAT_TEST_LOG="$BATS_TEST_TMPDIR/commands.log"
    : >"$XCAT_TEST_LOG"
    mkdir -p "$XCAT_NM_CONF_DIR" "$XCAT_NETWORKD_CONF_DIR"
}

run_duid()
{
    printf '%s\n' "$1" >"$XCAT_PRODUCT_UUID_FILE"
    run /bin/bash "$SCRIPT"
}

nm_file() { cat "$XCAT_NM_CONF_DIR/15-xcat-dhcpv6-duid.conf"; }
nd_file() { cat "$XCAT_NETWORKD_CONF_DIR/15-xcat-dhcpv6-duid.conf"; }

@test "NetworkManager gets the whole DUID in firmware byte order" {
    run_duid 00112233-4455-6677-8899-aabbccddeeff
    [ "$status" -eq 0 ]
    [ "$(nm_file)" = "[connection]
ipv6.dhcp-duid=$DUID" ]
}

@test "systemd-networkd gets the type by name and the sixteen bytes alone" {
    run_duid 00112233-4455-6677-8899-aabbccddeeff
    [ "$status" -eq 0 ]
    [ "$(nd_file)" = "[DHCPv6]
DUIDType=uuid
DUIDRawData=$RAW" ]
}

@test "the two renderers are told the same identifier" {
    run_duid 00112233-4455-6677-8899-aabbccddeeff
    nm=$(nm_file | sed -n 's/^ipv6.dhcp-duid=00:04://p')
    nd=$(nd_file | sed -n 's/^DUIDRawData=//p')
    [ "$nm" = "$nd" ]
}

@test "an uppercase SMBIOS UUID gives the same DUID as its lowercase form" {
    run_duid 00112233-4455-6677-8899-AABBCCDDEEFF
    [ "$(nm_file | sed -n 's/^ipv6.dhcp-duid=//p')" = "$DUID" ]
}

@test "a machine with no SMBIOS UUID writes nothing" {
    rm -f "$XCAT_PRODUCT_UUID_FILE"
    run /bin/bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -e "$XCAT_NM_CONF_DIR/15-xcat-dhcpv6-duid.conf" ]
    [ ! -e "$XCAT_NETWORKD_CONF_DIR/15-xcat-dhcpv6-duid.conf" ]
    grep -F 'leaving the DHCPv6 client identifier alone' "$XCAT_TEST_LOG"
}

@test "a SMBIOS UUID that is not sixteen bytes writes nothing" {
    run_duid 'Not Settable'
    [ "$status" -eq 0 ]
    [ ! -e "$XCAT_NM_CONF_DIR/15-xcat-dhcpv6-duid.conf" ]
    grep -F 'no usable SMBIOS UUID' "$XCAT_TEST_LOG"
}

@test "the nil UUID writes nothing, because makedhcp reserves the hardware address for it" {
    run_duid 00000000-0000-0000-0000-000000000000
    [ "$status" -eq 0 ]
    [ ! -e "$XCAT_NM_CONF_DIR/15-xcat-dhcpv6-duid.conf" ]
    grep -F 'nil UUID' "$XCAT_TEST_LOG"
}

@test "a node with only systemd-networkd still gets its identifier" {
    rmdir "$XCAT_NM_CONF_DIR"
    XCAT_NM_CONF_DIR="$BATS_TEST_TMPDIR/absent/conf.d" run_duid 00112233-4455-6677-8899-aabbccddeeff
    [ "$status" -eq 0 ]
    [ "$(nd_file | sed -n 's/^DUIDRawData=//p')" = "$RAW" ]
}

@test "a node with no renderer at all fails loudly rather than silently" {
    # The UUID has to be present, or the script exits 0 on the earlier check and this would
    # pass for the wrong reason.
    printf '%s\n' 00112233-4455-6677-8899-aabbccddeeff >"$XCAT_PRODUCT_UUID_FILE"
    run env XCAT_NM_CONF_DIR=/proc/x/conf.d XCAT_NETWORKD_CONF_DIR=/proc/x/networkd.conf.d \
        XCAT_PRODUCT_UUID_FILE="$XCAT_PRODUCT_UUID_FILE" XCAT_TEST_LOG="$XCAT_TEST_LOG" \
        PATH="$PATH" /bin/bash "$SCRIPT"
    [ "$status" -eq 1 ]
    grep -F 'the DHCPv6 client identifier is unset' "$XCAT_TEST_LOG"
}
