#!/usr/bin/env bats
#
# The booted stateless system of an IPv6-only Ubuntu node.
#
# xcatroot wrote "dhcp4: true" into the netplan of every node, so an IPv6-only node came up
# with no address: systemd-networkd-wait-online failed, xcatpostinit failed, and the node
# answered no ssh. Measured on Ubuntu 24.04.5, which reached its login prompt with
# "[FAILED] Failed to start systemd-networkd-w... Wait for Network to be Configured."
#
# The address is on the kernel command line already, in the static form dracut takes.

load 'helpers/shell_source'

setup()
{
    XCATROOT_SCRIPT="$(require_repo_file \
      'xCAT-server/share/xcat/netboot/ubuntu/dracut/xcatroot')"
    SNIPPET="${BATS_TEST_TMPDIR}/fields.sh"
    extract_shell_function "$XCATROOT_SCRIPT" xcat_static_ip6_fields >"$SNIPPET"
}

fields()
{
    (
        # shellcheck disable=SC1090
        . "$SNIPPET" >/dev/null 2>&1
        xcat_static_ip6_fields "$1"
    )
}

@test "the address, prefix and gateway are read from the static form" {
    run fields 'ip=[2001:db8:147::10]::[2001:db8:147::1]:64:::none'
    [ "$status" -eq 0 ]
    [ "$output" = '2001:db8:147::10 64 2001:db8:147::1' ]
}

@test "a node with no gateway still yields its address and prefix" {
    run fields 'ip=[2001:db8:147::10]:::64:::none'
    [ "$status" -eq 0 ]
    [ "$output" = '2001:db8:147::10 64 ' ]
}

@test "an interface name in the parameter does not disturb the fields" {
    run fields 'ip=[2001:db8:147::10]::[2001:db8:147::1]:64::eth0:none'
    [ "$output" = '2001:db8:147::10 64 2001:db8:147::1' ]
}

# The IPv4 forms must be refused, or an IPv4 node would be given an IPv6 netplan.
@test "the dracut dhcp form is refused" {
    run fields 'ip=dhcp'
    [ "$status" -ne 0 ]
}

@test "the interface dhcp form is refused" {
    run fields 'ip=eth0:dhcp'
    [ "$status" -ne 0 ]
}

@test "either6 is refused, because it carries no address" {
    run fields 'ip=either6'
    [ "$status" -ne 0 ]
}

# A prefix that is not a number would reach the netplan as an address suffix.
@test "a parameter with no prefix is refused" {
    run fields 'ip=[2001:db8:147::10]::[2001:db8:147::1]::::none'
    [ "$status" -ne 0 ]
}
