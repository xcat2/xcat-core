#!/usr/bin/env bats
#
# configeth replaces the connection the installer created for the install NIC.
# On an IPv6 install it has to read the live address back first, and a DHCPv6
# lease is not written to the dhclient lease file the IPv4 path reads, so the
# address comes from "ip -6 addr show" instead. An address marked temporary,
# tentative, deprecated or dadfailed is not usable and must not be chosen.

load 'helpers/shell_source'

# run_discover <preferred> <ip -6 addr output> -- returns the chosen CIDR
run_discover()
{
    local file lib bin
    file="$(require_repo_file 'xCAT/postscripts/configeth')"
    lib="${BATS_TEST_TMPDIR}/configeth.sh"
    extract_shell_function "$file" 'discover_install_nic_ipv6' >"$lib" || return 1

    bin="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "$bin"
    printf '%s\n' "$2" >"${BATS_TEST_TMPDIR}/addr"
    cat >"$bin/ip" <<'IPSTUB'
#!/bin/sh
case "$*" in
*"-6 -o addr show"*)
    # The real ip(8) applies "scope global"; the stub has to as well, or a
    # link-local address reaches a caller that asked for a global one.
    case "$*" in
    *"scope global"*) grep -v 'scope link' "${BATS_TEST_TMPDIR}/addr" || true ;;
    *) cat "${BATS_TEST_TMPDIR}/addr" ;;
    esac
    ;;
*"-6 route show default"*) echo "default via 2001:db8::1 dev ens3 metric 100" ;;
*"-o link show"*) echo "2: ens3: <UP> mtu 9000 state UP" ;;
*) exit 1 ;;
esac
IPSTUB
    # A test that reaches NetworkManager measures the host, not this function.
    printf '#!/bin/sh\nexit 1\n' >"$bin/nmcli"
    chmod 0755 "$bin"/*

    PATH="$bin:$PATH" BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" bash -c '
        . "$1"
        discover_install_nic_ipv6 ens3 "$2" || exit $?
        printf "%s/%s %s %s\n" "$str_inst_ipv6" "$str_inst_ipv6_prefix" \
            "$str_inst_ipv6_gateway" "$str_inst_mtu"
    ' bash "$lib" "$1"
}

@test "a single global address is chosen with its prefix, gateway and MTU" {
    run run_discover '' '3: ens3    inet6 2001:db8::50/64 scope global \       valid_lifetime forever preferred_lft forever'
    [ "$status" -eq 0 ]
    [ "$output" = '2001:db8::50/64 2001:db8::1 9000' ]
}

@test "a temporary privacy address is not chosen over a stable one" {
    run run_discover '' '3: ens3    inet6 2001:db8::dead/64 scope global temporary dynamic
3: ens3    inet6 2001:db8::50/64 scope global dynamic'
    [ "$status" -eq 0 ]
    [ "${output% * *}" = '2001:db8::50/64' ]
}

@test "a tentative, deprecated or dadfailed address is never chosen" {
    local flag
    for flag in tentative deprecated dadfailed; do
        run run_discover '' "3: ens3    inet6 2001:db8::bad/64 scope global $flag
3: ens3    inet6 2001:db8::50/64 scope global dynamic"
        [ "$status" -eq 0 ]
        [ "${output% * *}" = '2001:db8::50/64' ]
    done
}

@test "the address xCAT asked for wins over the first usable one" {
    run run_discover '2001:db8::99' '3: ens3    inet6 2001:db8::50/64 scope global dynamic
3: ens3    inet6 2001:db8::99/64 scope global dynamic'
    [ "$status" -eq 0 ]
    [ "${output% * *}" = '2001:db8::99/64' ]
}

@test "no usable global address is a failure, not an empty answer" {
    run run_discover '' '3: ens3    inet6 fe80::1/64 scope link'
    [ "$status" -ne 0 ]
}
