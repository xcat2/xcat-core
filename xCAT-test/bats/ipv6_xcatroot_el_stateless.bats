#!/usr/bin/env bats
#
# The EL stateless initrd decides whether the node it is building is IPv6-only, and if it is it
# has to leave a NetworkManager profile behind in the new root. Nothing in the booted system
# repeats the DHCPv6 exchange the initrd made, so a node with no profile comes up with no
# address and answers no ssh.
#
# ip=dhcp6 is not the only form that means IPv6: a node given a static address on the kernel
# command line carries no "dhcp6" anywhere, so the live interface is what settles it. An
# interface that also holds an IPv4 address is a dual-stack node, which keeps the IPv4 path.

load 'helpers/shell_source'

setup()
{
    XCATROOT_SCRIPT="$(require_repo_file \
      'xCAT-server/share/xcat/netboot/rh/dracut_105/stateless/xcatroot')"
    LIB="${BATS_TEST_TMPDIR}/xcatroot.sh"
    { extract_shell_function "$XCATROOT_SCRIPT" 'xcat_is_ipv6_boot'
      extract_shell_function "$XCATROOT_SCRIPT" 'persist_ipv6_nm_connection'
      extract_shell_function "$XCATROOT_SCRIPT" 'xcat_boot_netif'
      extract_shell_function "$XCATROOT_SCRIPT" 'xcat_persist_ipv6_boot'; } >"$LIB"

    SYSNET="${BATS_TEST_TMPDIR}/sys-class-net"
    mkdir -p "$SYSNET"

    BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "$BIN"
    : >"${BATS_TEST_TMPDIR}/addr6"
    : >"${BATS_TEST_TMPDIR}/addr4"
    : >"${BATS_TEST_TMPDIR}/route6"
    cat >"$BIN/ip" <<'IPSTUB'
#!/bin/sh
case "$*" in
*"-6 -o addr show"*) cat "${BATS_TEST_TMPDIR}/addr6" ;;
*"-4 -o addr show"*) cat "${BATS_TEST_TMPDIR}/addr4" ;;
*"-6 route show default"*) cat "${BATS_TEST_TMPDIR}/route6" ;;
*) exit 1 ;;
esac
IPSTUB
    chmod 0755 "$BIN/ip"
}

# is_ipv6_boot <ip= argument> <interface> -- run the real decision
is_ipv6_boot()
{
    PATH="$BIN:$PATH" BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" bash -c '
        . "$1"
        xcat_is_ipv6_boot "$2" "$3"
    ' bash "$LIB" "$1" "$2"
}

@test "the dracut dhcp6 forms are an IPv6 boot, whatever the interface holds" {
    for arg in 'dhcp6' 'eth0:dhcp6' 'eth0:dhcp6:something'; do
        run is_ipv6_boot "$arg" ''
        [ "$status" -eq 0 ]
    done
}

@test "a global IPv6 address and no IPv4 address is an IPv6 boot" {
    printf '3: eth0    inet6 2001:db8:149::20/64 scope global\n' >"${BATS_TEST_TMPDIR}/addr6"
    run is_ipv6_boot 'ip=[2001:db8:149::20]::::::none' eth0
    [ "$status" -eq 0 ]
}

@test "a dual-stack interface is not an IPv6 boot" {
    printf '3: eth0    inet6 2001:db8:149::20/64 scope global\n' >"${BATS_TEST_TMPDIR}/addr6"
    printf '3: eth0    inet 192.0.2.20/24 scope global\n' >"${BATS_TEST_TMPDIR}/addr4"
    run is_ipv6_boot 'ip=dhcp' eth0
    [ "$status" -ne 0 ]
}

@test "an interface with no global IPv6 address is not an IPv6 boot" {
    run is_ipv6_boot 'ip=dhcp' eth0
    [ "$status" -ne 0 ]
}

@test "an IPv4 form with no interface named is not an IPv6 boot" {
    printf '3: eth0    inet6 2001:db8:149::20/64 scope global\n' >"${BATS_TEST_TMPDIR}/addr6"
    run is_ipv6_boot 'ip=dhcp' ''
    [ "$status" -ne 0 ]
}

# persist <newroot> <interface> <mac> [sources...]
persist()
{
    PATH="$BIN:$PATH" BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" bash -c '
        lib="$1"; shift
        . "$lib"
        persist_ipv6_nm_connection "$@"
    ' bash "$LIB" "$@"
}

@test "a profile the initrd already holds is copied into the new root" {
    local root="${BATS_TEST_TMPDIR}/root" src="${BATS_TEST_TMPDIR}/run-nm"
    mkdir -p "$root" "$src"
    printf '[connection]\nid=live\n' >"$src/live.nmconnection"
    run persist "$root" eth0 'aa:bb:cc:dd:ee:ff' "$src"
    [ "$status" -eq 0 ]
    [ -f "$root/etc/NetworkManager/system-connections/live.nmconnection" ]
    grep -q '^id=live$' "$root/etc/NetworkManager/system-connections/live.nmconnection"
    [ "$(stat -c '%a' "$root/etc/NetworkManager/system-connections/live.nmconnection")" = '600' ]
}

@test "with no profile to copy one is written from the live address" {
    local root="${BATS_TEST_TMPDIR}/root" profile
    mkdir -p "$root"
    printf '3: eth0    inet6 2001:db8:149::20/64 scope global\n' >"${BATS_TEST_TMPDIR}/addr6"
    printf 'default via 2001:db8:149::1 dev eth0 metric 100\n' >"${BATS_TEST_TMPDIR}/route6"
    run persist "$root" eth0 'aa:bb:cc:dd:ee:ff' "${BATS_TEST_TMPDIR}/absent"
    [ "$status" -eq 0 ]
    profile="$root/etc/NetworkManager/system-connections/xcat-eth0.nmconnection"
    [ -f "$profile" ]
    grep -q '^address1=2001:db8:149::20/64$' "$profile"
    grep -q '^gateway=2001:db8:149::1$' "$profile"
    grep -q '^mac-address=aa:bb:cc:dd:ee:ff$' "$profile"
    [ "$(stat -c '%a' "$profile")" = '600' ]
}

# A profile that leaves IPv4 on makes NetworkManager wait for a DHCPv4 lease that never comes,
# and systemd-networkd-wait-online fails the boot it was meant to complete.
@test "the written profile disables IPv4 and sets IPv6 manually" {
    local root="${BATS_TEST_TMPDIR}/root" profile
    mkdir -p "$root"
    printf '3: eth0    inet6 2001:db8:149::20/64 scope global\n' >"${BATS_TEST_TMPDIR}/addr6"
    run persist "$root" eth0 'aa:bb:cc:dd:ee:ff' "${BATS_TEST_TMPDIR}/absent"
    [ "$status" -eq 0 ]
    profile="$root/etc/NetworkManager/system-connections/xcat-eth0.nmconnection"
    grep -q '^method=disabled$' "$profile"
    grep -q '^method=manual$' "$profile"
    refute_grep -q '^method=auto$' "$profile"
}

# Writing a profile with an empty address1 is worse than writing none: NetworkManager refuses the
# file and the interface is left unmanaged, with no record of why.
@test "no live address and nothing to copy is a failure, not an empty profile" {
    local root="${BATS_TEST_TMPDIR}/root"
    mkdir -p "$root"
    run persist "$root" eth0 'aa:bb:cc:dd:ee:ff' "${BATS_TEST_TMPDIR}/absent"
    [ "$status" -ne 0 ]
    refute_grep -q . <(ls "$root/etc/NetworkManager/system-connections")
}

# add_netdev <interface> <mac> -- an interface in the scratch sysfs tree
add_netdev()
{
    mkdir -p "$SYSNET/$1"
    printf '%s\n' "$2" >"$SYSNET/$1/address"
}

# boot_netif <ifname= value> <netdev= value> <BOOTIF= value> -- run the real derivation
boot_netif()
{
    bash -c '
        . "$1"
        xcat_boot_netif "$2" "$3" "$4" "$5"
    ' bash "$LIB" "$1" "$2" "$3" "$SYSNET"
}

@test "ifname= names the interface, and its MAC is not part of the name" {
    run boot_netif 'ens7:aa:bb:cc:dd:ee:ff' '' ''
    [ "$status" -eq 0 ]
    [ "$output" = 'ens7' ]
}

@test "netdev= names the interface when ifname= is absent" {
    run boot_netif '' ens7 ''
    [ "$status" -eq 0 ]
    [ "$output" = 'ens7' ]
}

# BOOTIF carries the MAC in the PXE form, upper case and hyphen separated, and no name at all.
@test "BOOTIF is matched to an interface by the MAC sysfs reports" {
    add_netdev lo '00:00:00:00:00:00'
    add_netdev ens7 'aa:bb:cc:dd:ee:ff'
    run boot_netif '' '' '01-AA-BB-CC-DD-EE-FF'
    [ "$status" -eq 0 ]
    [ "$output" = 'ens7' ]
}

@test "a BOOTIF that matches no interface names no interface" {
    add_netdev ens7 'aa:bb:cc:dd:ee:ff'
    run boot_netif '' '' '01-00-11-22-33-44-55'
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

# nm_value <file> <section> <key> -- the value a keyfile gives a key inside one section
nm_value()
{
    awk -v section="[$2]" -v key="$3" -F= '
        $0 == section { inside = 1; next }
        /^\[/ { inside = 0 }
        inside && $1 == key { print $2; exit }
    ' "$1"
}

# persist_boot <newroot> <interface> <ip= value> -- run the whole handoff
#
# The last argument names the directory the handoff reads live profiles from. The test gives
# one that does not exist, so the profiles of the host this test runs on are never read.
persist_boot()
{
    PATH="$BIN:$PATH" BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" bash -c '
        lib="$1"; shift
        . "$lib"
        xcat_persist_ipv6_boot "$1" "$2" "$3" "$4" "$5"
    ' bash "$LIB" "$1" "$2" "$3" "$SYSNET" "${BATS_TEST_TMPDIR}/absent"
}

@test "an IPv6-only boot leaves the address and the route in a NetworkManager keyfile" {
    local root="${BATS_TEST_TMPDIR}/root" profile
    mkdir -p "$root"
    add_netdev ens7 'aa:bb:cc:dd:ee:ff'
    printf '3: ens7    inet6 2001:db8:149::20/64 scope global\n' >"${BATS_TEST_TMPDIR}/addr6"
    printf 'default via 2001:db8:149::1 dev ens7 metric 100\n' >"${BATS_TEST_TMPDIR}/route6"
    run persist_boot "$root" ens7 '[2001:db8:149::20]::::::none'
    [ "$status" -eq 0 ]
    profile="$root/etc/NetworkManager/system-connections/xcat-ens7.nmconnection"
    [ -f "$profile" ]
    [ "$(nm_value "$profile" ethernet mac-address)" = 'aa:bb:cc:dd:ee:ff' ]
    [ "$(nm_value "$profile" ipv6 address1)" = '2001:db8:149::20/64' ]
    [ "$(nm_value "$profile" ipv6 gateway)" = '2001:db8:149::1' ]
    [ "$(nm_value "$profile" ipv6 method)" = 'manual' ]
    [ "$(nm_value "$profile" ipv4 method)" = 'disabled' ]
    [ "$(stat -c '%a' "$profile")" = '600' ]
}

# The node is reached over IPv4, which NetworkManager configures from the dhcp4 lease of the
# booted system. A keyfile here would pin an address the node is not meant to keep.
@test "a dual-stack boot writes no keyfile and is not a failure" {
    local root="${BATS_TEST_TMPDIR}/root"
    mkdir -p "$root"
    add_netdev ens7 'aa:bb:cc:dd:ee:ff'
    printf '3: ens7    inet6 2001:db8:149::20/64 scope global\n' >"${BATS_TEST_TMPDIR}/addr6"
    printf '3: ens7    inet 192.0.2.20/24 scope global\n' >"${BATS_TEST_TMPDIR}/addr4"
    run persist_boot "$root" ens7 'dhcp'
    [ "$status" -eq 0 ]
    [ ! -d "$root/etc/NetworkManager/system-connections" ]
}

# NetworkManager refuses a keyfile whose mac-address is empty, and the interface is then left
# unmanaged. A loud failure sends the node to the panic path instead, which says why.
@test "an interface sysfs gives no MAC is a failure, not a keyfile without one" {
    local root="${BATS_TEST_TMPDIR}/root"
    mkdir -p "$root"
    printf '3: ens7    inet6 2001:db8:149::20/64 scope global\n' >"${BATS_TEST_TMPDIR}/addr6"
    run persist_boot "$root" ens7 'dhcp6'
    [ "$status" -ne 0 ]
    [ ! -f "$root/etc/NetworkManager/system-connections/xcat-ens7.nmconnection" ]
}

# dracut gives no interface name for a node booted with none of ifname=, netdev= and BOOTIF=.
# There is nothing to persist and nothing is wrong, so the handoff must not fail the boot.
@test "no interface named is not a failure" {
    local root="${BATS_TEST_TMPDIR}/root"
    mkdir -p "$root"
    run persist_boot "$root" '' 'dhcp6'
    [ "$status" -eq 0 ]
}
