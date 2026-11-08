#!/usr/bin/env bats
#
# A DHCPv6 reservation is keyed on the DUID, and a DUID names the machine, not the nic. Every
# nic of a node therefore asks for the same reserved address and the first REQUEST takes it, so
# Genesis must give the boot nic its address before a secondary nic asks for one.

load 'helpers/doxcat_sandbox'

setup()
{
    setup_doxcat
    add_doxcat_link boot0 BROADCAST,MULTICAST,UP ether aa:bb:cc:dd:ee:ff
    add_doxcat_link eno1 BROADCAST,MULTICAST,UP
    mkdir -p "$fixture/sys/devices/eno1/interface"
    ln -s "/sys/devices/eno1/interface" "$fixture/sys/class/net/eno1/device"
}

# Replace the recording dhclient with one that also grants the address, so the order the test
# reads is the order the nics were served and not the order the commands were written.
grant_v6_to()
{
    local nic=$1
    cat >"$fixture/bin/dhclient" <<SH
#!/bin/sh
printf '%s\n' "\$*" >>/run/fixture/dhcp
case "\$*" in
    '-6 '*' $nic '*)
        printf '2: $nic inet6 2001:db8:188::20/64 scope global\n' \
            >/run/fixture/addrs6/$nic ;;
esac
SH
    chmod +x "$fixture/bin/dhclient"
}

boot_genesis()
{
    : >"$fixture/dhcp"
    run_genesis 0 --setenv BOOTIF 01-aa-bb-cc-dd-ee-ff
    [ "$(cat "$fixture/bootnic")" = boot0 ]
    [ "$(cat "$fixture/selected")" = eno1 ]
}

dhcp6_nics()
{
    awk '/^-6 /{ print $(NF-2) }' "$fixture/dhcp"
}

@test "the boot nic is served DHCPv6 before a secondary nic" {
    grant_v6_to boot0
    boot_genesis
    [ "$(dhcp6_nics | head -1)" = boot0 ]
    [ "$(dhcp6_nics | sort | tr '\n' ' ')" = "boot0 eno1 " ]
}

@test "a secondary nic is not served DHCPv6 while the boot nic has no address" {
    boot_genesis
    [ "$(dhcp6_nics | tr '\n' ' ')" = "boot0 " ]
}

@test "IPv4 on a secondary nic does not wait for the boot nic" {
    boot_genesis
    run grep -c -- '-cf /etc/dhclient.conf' "$fixture/dhcp"
    [ "$status" -eq 0 ]
    [ "$output" = 2 ]
}
