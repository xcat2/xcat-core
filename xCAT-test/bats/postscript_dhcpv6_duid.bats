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
    unset DHCP6DUID MACMAC ARCH VPDUUID
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

# ---- mac.duid decides the identifier, the same way makedhcp decides it -------------------
# The script always derived the firmware order. A node whose reservation holds a
# canonical-order or a literal DUID matched nothing, took a pool address and had no boot URL.
# mypostscript exports the attribute as DHCP6DUID.

CANONICAL=00:04:00:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff

@test "an unset attribute keeps the firmware order" {
    unset DHCP6DUID
    run_duid 00112233-4455-6677-8899-aabbccddeeff
    [ "$status" -eq 0 ]
    [ "$(nm_file)" = "[connection]
ipv6.dhcp-duid=$DUID" ]
}

@test "firmware asks for the order the firmware sends" {
    export DHCP6DUID=firmware
    run_duid 00112233-4455-6677-8899-aabbccddeeff
    [ "$status" -eq 0 ]
    [ "$(nm_file)" = "[connection]
ipv6.dhcp-duid=$DUID" ]
}

@test "canonical keeps the order product_uuid prints" {
    export DHCP6DUID=canonical
    run_duid 00112233-4455-6677-8899-aabbccddeeff
    [ "$status" -eq 0 ]
    [ "$(nm_file)" = "[connection]
ipv6.dhcp-duid=$CANONICAL" ]
}

@test "canonical gives systemd-networkd the same sixteen bytes" {
    export DHCP6DUID=canonical
    run_duid 00112233-4455-6677-8899-aabbccddeeff
    [ "$status" -eq 0 ]
    [ "$(nd_file)" = "[DHCPv6]
DUIDType=uuid
DUIDRawData=00:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff" ]
}

@test "a literal UUID DUID is written as it stands" {
    export DHCP6DUID=00:04:de:ad:be:ef:00:01:02:03:04:05:06:07:08:09
    run_duid 00112233-4455-6677-8899-aabbccddeeff
    [ "$status" -eq 0 ]
    [ "$(nm_file)" = "[connection]
ipv6.dhcp-duid=00:04:de:ad:be:ef:00:01:02:03:04:05:06:07:08:09" ]
    [ "$(nd_file)" = "[DHCPv6]
DUIDType=uuid
DUIDRawData=de:ad:be:ef:00:01:02:03:04:05:06:07:08:09" ]
}

@test "a literal DUID-LLT reaches systemd-networkd as its type and raw data" {
    export DHCP6DUID=00:01:00:01:aa:bb:cc:dd:ee:ff:00:11
    run_duid 00112233-4455-6677-8899-aabbccddeeff
    [ "$status" -eq 0 ]
    [ "$(nm_file)" = "[connection]
ipv6.dhcp-duid=00:01:00:01:aa:bb:cc:dd:ee:ff:00:11" ]
    [ "$(nd_file)" = "[DHCPv6]
DUIDType=link-layer-time
DUIDRawData=00:01:aa:bb:cc:dd:ee:ff:00:11" ]
}

@test "a literal DUID-LL reaches systemd-networkd as its type and raw data" {
    export DHCP6DUID=00:03:00:01:52:54:00:aa:bb:cc
    run_duid 00112233-4455-6677-8899-aabbccddeeff
    [ "$status" -eq 0 ]
    [ "$(nd_file)" = "[DHCPv6]
DUIDType=link-layer
DUIDRawData=00:01:52:54:00:aa:bb:cc" ]
}

@test "a literal DUID-EN reaches systemd-networkd as the vendor type" {
    export DHCP6DUID=00:02:00:00:ab:11:f9:2a:c2:77:29:f9:5c:00
    run_duid 00112233-4455-6677-8899-aabbccddeeff
    [ "$status" -eq 0 ]
    [ "$(nd_file)" = "[DHCPv6]
DUIDType=vendor
DUIDRawData=00:00:ab:11:f9:2a:c2:77:29:f9:5c:00" ]
}

# ---- a literal or a DUID-LL needs no SMBIOS UUID -----------------------------------------
# makedhcp reserves a literal or a DUID-LL without reading vpd.uuid, so a node with no usable
# SMBIOS UUID still has a reservation that this script must match.

@test "a literal DUID is written when the machine has no SMBIOS UUID" {
    export DHCP6DUID=00:01:00:01:aa:bb:cc:dd:ee:ff:00:11
    rm -f "$XCAT_PRODUCT_UUID_FILE"
    run /bin/bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$(nm_file)" = "[connection]
ipv6.dhcp-duid=00:01:00:01:aa:bb:cc:dd:ee:ff:00:11" ]
}

@test "a literal DUID is written when the SMBIOS UUID is the nil UUID" {
    export DHCP6DUID=00:01:00:01:aa:bb:cc:dd:ee:ff:00:11
    run_duid 00000000-0000-0000-0000-000000000000
    [ "$status" -eq 0 ]
    [ "$(nm_file)" = "[connection]
ipv6.dhcp-duid=00:01:00:01:aa:bb:cc:dd:ee:ff:00:11" ]
}

# ---- ll: the DUID-LL that makedhcp builds from the first address of mac.mac ---------------

LL=00:03:00:01:52:54:00:aa:bb:cc

@test "ll writes the DUID-LL of the first mac.mac address" {
    export DHCP6DUID=ll MACMAC='52:54:00:AA:BB:CC!cn1|52:54:00:11:22:33'
    run_duid 00112233-4455-6677-8899-aabbccddeeff
    [ "$status" -eq 0 ]
    [ "$(nm_file)" = "[connection]
ipv6.dhcp-duid=$LL" ]
    [ "$(nd_file)" = "[DHCPv6]
DUIDType=link-layer
DUIDRawData=00:01:52:54:00:aa:bb:cc" ]
}

@test "ll needs no SMBIOS UUID" {
    export DHCP6DUID=ll MACMAC=52-54-00-aa-bb-cc
    rm -f "$XCAT_PRODUCT_UUID_FILE"
    run /bin/bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$(nm_file | sed -n 's/^ipv6.dhcp-duid=//p')" = "$LL" ]
}

@test "a node moved from firmware to ll loses its UUID identifier" {
    run_duid 00112233-4455-6677-8899-aabbccddeeff
    [ "$(nm_file | sed -n 's/^ipv6.dhcp-duid=//p')" = "$DUID" ]
    export DHCP6DUID=ll MACMAC=52:54:00:aa:bb:cc
    run_duid 00112233-4455-6677-8899-aabbccddeeff
    [ "$status" -eq 0 ]
    [ "$(nm_file | sed -n 's/^ipv6.dhcp-duid=//p')" = "$LL" ]
    [ "$(nd_file | sed -n 's/^DUIDType=//p')" = "link-layer" ]
}

@test "ll with no usable mac.mac writes nothing" {
    export DHCP6DUID=ll MACMAC=
    run_duid 00112233-4455-6677-8899-aabbccddeeff
    [ "$status" -eq 0 ]
    [ ! -e "$XCAT_NM_CONF_DIR/15-xcat-dhcpv6-duid.conf" ]
    grep -q 'no usable address in mac.mac' "$XCAT_TEST_LOG"
}

@test "an unset attribute on ppc64le means ll, as makedhcp reserves it" {
    unset DHCP6DUID
    export ARCH=ppc64le MACMAC=52:54:00:aa:bb:cc
    rm -f "$XCAT_PRODUCT_UUID_FILE"
    run /bin/bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$(nm_file | sed -n 's/^ipv6.dhcp-duid=//p')" = "$LL" ]
}

# ---- mypostscript hands the attribute to the postscript -----------------------------------
# mypostscript runs each postscript as a child process, so DHCP6DUID reaches it only when the
# template exports it. The render below does what makescript does to the lines it needs: each
# #TABLE:<table>:$NODE:<column># becomes "<table>.<column>", the other tags become empty, and the
# tabdump lines, which makescript replaces with table contents, are dropped.

@test "mypostscript exports DHCP6DUID to the postscripts it runs" {
    tmpl="$(repo_path 'xCAT-server/share/xcat/mypostscript/mypostscript.tmpl')"
    rendered="$BATS_TEST_TMPDIR/mypostscript"
    sed -e '/^tabdump(/d' \
        -e 's/#TABLE:\([^:]*\):\$NODE:\([^#]*\)#/\1.\2/g' \
        -e 's/=#[A-Z_]*#/=/g' "$tmpl" >"$rendered"
    unset DHCP6DUID
    run /bin/bash -c '. "$1" && /bin/bash -c "printf %s \"\${DHCP6DUID-unset}\""' _ "$rendered"
    [ "$status" -eq 0 ]
    [ "$output" = "mac.duid" ]
}

@test "an attribute that is neither keyword nor DUID writes nothing" {
    export DHCP6DUID=garbage-value
    run_duid 00112233-4455-6677-8899-aabbccddeeff
    [ "$status" -eq 0 ]
    [ ! -e "$XCAT_NM_CONF_DIR/15-xcat-dhcpv6-duid.conf" ]
    [ ! -e "$XCAT_NETWORKD_CONF_DIR/15-xcat-dhcpv6-duid.conf" ]
    grep -q 'is not firmware, canonical, ll, or a DUID' "$XCAT_TEST_LOG"
}

# ---- the UUID policies read vpd.uuid, as makedhcp does ------------------------------------
# makedhcp applies firmware and canonical to vpd.uuid. A KVM domain that an earlier mkvm defined
# holds the byte swap of vpd.uuid, so product_uuid in the guest is that swap, and a policy applied
# to product_uuid gives the other order. mypostscript exports vpd.uuid as VPDUUID.

@test "canonical applies to vpd.uuid when product_uuid is its byte swap" {
    export DHCP6DUID=canonical VPDUUID=00112233-4455-6677-8899-aabbccddeeff
    run_duid 33221100-5544-7766-8899-aabbccddeeff
    [ "$status" -eq 0 ]
    [ "$(nm_file | sed -n 's/^ipv6.dhcp-duid=//p')" = "$CANONICAL" ]
}

@test "firmware applies to vpd.uuid when product_uuid is its byte swap" {
    export DHCP6DUID=firmware VPDUUID=00112233-4455-6677-8899-aabbccddeeff
    run_duid 33221100-5544-7766-8899-aabbccddeeff
    [ "$status" -eq 0 ]
    [ "$(nm_file | sed -n 's/^ipv6.dhcp-duid=//p')" = "$DUID" ]
}

@test "the unset attribute applies the firmware order to vpd.uuid too" {
    export VPDUUID=00112233-4455-6677-8899-aabbccddeeff
    run_duid 33221100-5544-7766-8899-aabbccddeeff
    [ "$status" -eq 0 ]
    [ "$(nm_file | sed -n 's/^ipv6.dhcp-duid=//p')" = "$DUID" ]
}

@test "vpd.uuid is read without a SMBIOS UUID on the node" {
    export DHCP6DUID=canonical VPDUUID=00112233-4455-6677-8899-AABBCCDDEEFF
    rm -f "$XCAT_PRODUCT_UUID_FILE"
    run /bin/bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$(nm_file | sed -n 's/^ipv6.dhcp-duid=//p')" = "$CANONICAL" ]
}

@test "mypostscript exports VPDUUID to the postscripts it runs" {
    tmpl="$(repo_path 'xCAT-server/share/xcat/mypostscript/mypostscript.tmpl')"
    rendered="$BATS_TEST_TMPDIR/mypostscript"
    sed -e '/^tabdump(/d' \
        -e 's/#TABLE:\([^:]*\):\$NODE:\([^#]*\)#/\1.\2/g' \
        -e 's/=#[A-Z_]*#/=/g' "$tmpl" >"$rendered"
    run /bin/bash -c '. "$1" && /bin/bash -c "printf %s \"\${VPDUUID-unset}\""' _ "$rendered"
    [ "$status" -eq 0 ]
    [ "$output" = "vpd.uuid" ]
}
