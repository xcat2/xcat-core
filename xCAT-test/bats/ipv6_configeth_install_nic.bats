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

# ---------------------------------------------------------------------------
# The keyfile configeth renders during Anaconda's chrooted %post.
#
# nmcli cannot persist a connection into the target root there, so the profile is rendered with
# "nmcli --offline" into a temporary file and moved into place. A node whose profile keeps IPv4
# enabled waits for a DHCPv4 lease that never arrives, and a temporary file left behind in
# system-connections is read by NetworkManager as a second profile for the same interface.

# render_keyfile <keyfile> <nmcli exit status> -- run the real function with nmcli stubbed to
# echo the arguments it was given, so the profile shows what reached it.
render_keyfile()
{
    local file lib bin keyfile="$1" rc="$2"
    file="$(require_repo_file 'xCAT/postscripts/configeth')"
    lib="${BATS_TEST_TMPDIR}/keyfile.sh"
    extract_shell_function "$file" 'configure_install_nic_ipv6_connection' >"$lib" || return 1
    extract_shell_function "$file" 'configure_install_nic_ipv6_keyfile' >>"$lib" || return 1

    bin="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "$bin"
    cat >"$bin/nmcli" <<NMSTUB
#!/bin/sh
for a in "\$@"; do printf '%s\n' "\$a"; done
exit $rc
NMSTUB
    chmod 0755 "$bin/nmcli"

    PATH="$bin:$PATH" bash -c '
        . "$1"
        configure_install_nic_ipv6_keyfile xcat-ens3 ens3 \
            2001:db8:149::20 64 2001:db8:149::1 \
            "2001:db8:149::1 2001:db8:149::2" ipv6.cluster 9000 "$2"
    ' bash "$lib" "$keyfile"
}

@test "the rendered keyfile carries the address, gateway, DNS and search list" {
    local keyfile="${BATS_TEST_TMPDIR}/nm/xcat-ens3.nmconnection"
    run render_keyfile "$keyfile" 0
    [ "$status" -eq 0 ]
    [ -f "$keyfile" ]
    grep -qx 'ipv6.addresses' "$keyfile"
    grep -qx '2001:db8:149::20/64' "$keyfile"
    grep -qx '2001:db8:149::1' "$keyfile"
    grep -qx '2001:db8:149::1 2001:db8:149::2' "$keyfile"
    grep -qx 'ipv6.cluster' "$keyfile"
}

# A profile that leaves IPv4 on makes the installed node wait for a lease that never comes.
@test "the rendered keyfile disables IPv4" {
    local keyfile="${BATS_TEST_TMPDIR}/nm/xcat-ens3.nmconnection"
    run render_keyfile "$keyfile" 0
    [ "$status" -eq 0 ]
    grep -qx 'ipv4.method' "$keyfile"
    grep -qx 'disabled' "$keyfile"
    grep -qx 'manual' "$keyfile"
}

@test "the rendered keyfile is readable only by root" {
    local keyfile="${BATS_TEST_TMPDIR}/nm/xcat-ens3.nmconnection"
    run render_keyfile "$keyfile" 0
    [ "$status" -eq 0 ]
    [ "$(stat -c '%a' "$keyfile")" = '600' ]
}

# NetworkManager reads every file in system-connections, so a leftover temporary file is a
# second profile for the same interface.
@test "a failed render leaves no temporary file beside the keyfile" {
    local keyfile="${BATS_TEST_TMPDIR}/nm/xcat-ens3.nmconnection"
    run render_keyfile "$keyfile" 1
    [ "$status" -ne 0 ]
    [ ! -f "$keyfile" ]
    refute_grep -q . <(find "${BATS_TEST_TMPDIR}/nm" -name '*.xcat.*' -print)
}
