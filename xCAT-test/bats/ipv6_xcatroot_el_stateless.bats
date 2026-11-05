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
      extract_shell_function "$XCATROOT_SCRIPT" 'persist_ipv6_nm_connection'; } >"$LIB"

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
