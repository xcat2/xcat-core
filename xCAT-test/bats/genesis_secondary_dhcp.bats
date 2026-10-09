#!/usr/bin/env bats

load 'helpers/doxcat_sandbox'

setup()
{
    setup_doxcat
    add_doxcat_link boot0 BROADCAST,MULTICAST,UP ether aa:bb:cc:dd:ee:ff
}

physical_nic()
{
    local nic=$1 vendor=${2:-} product=${3:-}
    mkdir -p "$fixture/sys/devices/$nic/interface"
    ln -s "/sys/devices/$nic/interface" "$fixture/sys/class/net/$nic/device"
    [ -z "$vendor" ] || printf '%s\n' "$vendor" >"$fixture/sys/devices/$nic/idVendor"
    [ -z "$product" ] || printf '%s\n' "$product" >"$fixture/sys/devices/$nic/idProduct"
}

enslave_nic()
{
    mkdir -p "$fixture/sys/class/net/bond0"
    ln -s /sys/class/net/bond0 "$fixture/sys/class/net/$1/master"
}

check_secondary()
{
    : >"$fixture/dhcp"
    run_genesis 0 --setenv BOOTIF 01-aa-bb-cc-dd-ee-ff
    [ "$(cat "$fixture/bootnic")" = boot0 ]
    assert_doxcat_dhcp "$@"
}

@test "DOWN virtual interface keeps the legacy DHCP path" {
    add_doxcat_link veth0 BROADCAST,MULTICAST
    check_secondary veth0
}

@test "DOWN interface short-circuits every ownership guard" {
    add_doxcat_link eno1 BROADCAST,MULTICAST
    physical_nic eno1 046b ffb0
    enslave_nic eno1
    printf 'eno1\n' >"$fixture/tmp/tsmhostnic"
    printf '2: eno1 inet 192.0.2.21/24 scope global eno1\n' >"$fixture/addrs/eno1"
    check_secondary eno1
}

@test "operational state does not replace the IFF_UP flag" {
    add_doxcat_link eno2 BROADCAST,MULTICAST
    check_secondary eno2
}

@test "UP physical unaddressed interface gets both DHCP families" {
    add_doxcat_link eno3 BROADCAST,MULTICAST,UP,LOWER_UP
    physical_nic eno3
    check_secondary eno3
}

@test "UP without carrier is still administratively UP" {
    add_doxcat_link eno4 BROADCAST,MULTICAST,UP
    sed -i 's/state UP/state DOWN/' "$fixture/links/eno4" "$fixture/link-list"
    physical_nic eno4
    check_secondary eno4
}

@test "IFF_UP is recognized as the first flag" {
    add_doxcat_link eno5 UP,BROADCAST
    physical_nic eno5
    check_secondary eno5
}

@test "IFF_UP is recognized as the only flag" {
    add_doxcat_link eno6 UP
    physical_nic eno6
    check_secondary eno6
}

@test "IFF_UP is recognized as the last flag" {
    add_doxcat_link eno7 BROADCAST,UP
    physical_nic eno7
    check_secondary eno7
}

@test "physical IPoIB interface remains eligible" {
    add_doxcat_link ib0 BROADCAST,MULTICAST,UP,LOWER_UP infiniband "$ib_address"
    physical_nic ib0
    check_secondary ib0
}

@test "link-local IPv4 and IPv6 addresses do not claim the interface" {
    add_doxcat_link eno8 BROADCAST,MULTICAST,UP
    physical_nic eno8
    printf '%s\n' '2: eno8 inet 169.254.10.20/16 scope link eno8' \
        '2: eno8 inet6 fe80::20/64 scope link' '2: eno8 inet6 feb0::20/64 scope link' \
        >"$fixture/addrs/eno8"
    check_secondary eno8
}

@test "global IPv4 address preserves existing ownership" {
    add_doxcat_link eno9 BROADCAST,MULTICAST,UP
    physical_nic eno9
    printf '2: eno9 inet 198.51.100.9/24 scope global eno9\n' >"$fixture/addrs/eno9"
    check_secondary
}

@test "global IPv6 address preserves existing ownership" {
    add_doxcat_link eno10 BROADCAST,MULTICAST,UP
    physical_nic eno10
    printf '2: eno10 inet6 2001:db8::10/64 scope global\n' >"$fixture/addrs/eno10"
    check_secondary
}

@test "global address wins when link-local addresses also exist" {
    add_doxcat_link eno11 BROADCAST,MULTICAST,UP
    physical_nic eno11
    printf '%s\n' '2: eno11 inet6 fe80::11/64 scope link' \
        '2: eno11 inet 203.0.113.11/24 scope global eno11' >"$fixture/addrs/eno11"
    check_secondary
}

@test "TSM-owned interface is excluded by exact name" {
    add_doxcat_link eno12 BROADCAST,MULTICAST,UP
    physical_nic eno12
    printf 'eno12\n' >"$fixture/tmp/tsmhostnic"
    check_secondary
}

@test "known management USB devices are excluded before setup markers" {
    add_doxcat_link enp18s0f0u1 BROADCAST,MULTICAST,UP
    add_doxcat_link enp18s0f0u2 BROADCAST,MULTICAST,UP
    physical_nic enp18s0f0u1 046b ffb0
    physical_nic enp18s0f0u2 04b3 4010
    check_secondary
}

@test "other USB device identities remain eligible" {
    local nic vendor product
    while read -r nic vendor product; do
        add_doxcat_link "$nic" BROADCAST,MULTICAST,UP
        physical_nic "$nic" "$vendor" "$product"
    done <<'NICS'
enp18s0f0u3 046b ffb1
enp18s0f0u4 04b4 4010
enp18s0f0u5 046c ffb0
enp18s0f0u6 04b3 4011
NICS
    check_secondary enp18s0f0u3 enp18s0f0u4 enp18s0f0u5 enp18s0f0u6
}

@test "TSM ownership does not use substring matching" {
    add_doxcat_link eno13 BROADCAST,MULTICAST,UP
    physical_nic eno13
    printf 'eno130\n' >"$fixture/tmp/tsmhostnic"
    check_secondary eno13
}

@test "UP virtual interface is excluded" {
    add_doxcat_link vnet0 BROADCAST,MULTICAST,UP
    check_secondary
}

@test "UP physical slave is excluded" {
    add_doxcat_link eno14 BROADCAST,MULTICAST,UP
    physical_nic eno14
    enslave_nic eno14
    check_secondary
}

@test "link-state query failure is closed" {
    add_doxcat_link eno15 BROADCAST,MULTICAST,UP
    physical_nic eno15
    touch "$fixture/links/eno15.fail"
    check_secondary
}

@test "address query failure is closed" {
    add_doxcat_link eno16 BROADCAST,MULTICAST,UP
    physical_nic eno16
    touch "$fixture/addrs/eno16.fail"
    check_secondary
}

@test "caller excludes loopback, boot and USB interfaces on repeated startup" {
    local nic
    add_doxcat_link lo LOOPBACK,UP
    physical_nic lo
    physical_nic boot0
    for nic in usb0 eno17; do
        add_doxcat_link "$nic" BROADCAST,MULTICAST,UP
        physical_nic "$nic"
    done
    check_secondary eno17
    check_secondary eno17
}
