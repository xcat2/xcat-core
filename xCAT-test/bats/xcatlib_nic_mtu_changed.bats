#!/usr/bin/env bats
#
# xcat_nic_mtu_changed is the decision configeth makes when it has to choose between writing
# the configuration files and also restarting the NIC. Its address comparison cannot see an
# MTU change, so a run that changes nothing else left the NIC on its old MTU: the profile said
# 1496 and `ip link` still said 1500 (confignetwork_secondarynic_updatenode on EL8 and EL9).
#
# `ip` is stubbed, so nothing on the host is read.

load 'helpers/shell_source'

setup()
{
    LIB="$(require_repo_file 'xCAT/postscripts/xcatlib.sh')"
    BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "$BIN"
    export PATH="$BIN:$PATH"
}

# Write an `ip` that reports $1 as the line for `ip link show dev <nic>`.
stub_ip()
{
    printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$1" >"$BIN/ip"
    chmod 0755 "$BIN/ip"
}

stub_ip_absent_device()
{
    printf '#!/bin/sh\necho "Device does not exist" >&2\nexit 1\n' >"$BIN/ip"
    chmod 0755 "$BIN/ip"
}

@test "a wanted MTU different from the live one is a change" {
    stub_ip "3: ens4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000"
    . "$LIB"
    run xcat_nic_mtu_changed ens4 1496
    [ "$status" -eq 0 ]
}

@test "a wanted MTU equal to the live one is not a change" {
    stub_ip "3: ens4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1496 qdisc fq_codel state UP group default qlen 1000"
    . "$LIB"
    run xcat_nic_mtu_changed ens4 1496
    [ "$status" -ne 0 ]
}

@test "a network that declares no MTU is not a change" {
    stub_ip "3: ens4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000"
    . "$LIB"
    run xcat_nic_mtu_changed ens4 ""
    [ "$status" -ne 0 ]
    run xcat_nic_mtu_changed ens4 default
    [ "$status" -ne 0 ]
}

@test "a NIC whose MTU cannot be read is not a change" {
    stub_ip_absent_device
    . "$LIB"
    run xcat_nic_mtu_changed ens4 1496
    [ "$status" -ne 0 ]
}
