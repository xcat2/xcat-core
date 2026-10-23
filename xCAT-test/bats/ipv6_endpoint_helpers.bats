#!/usr/bin/env bats
#
# Every xCAT endpoint a node reads is "host:port", and an IPv6 literal already
# contains colons. Four scripts carry a helper that splits such a value and
# reassembles it with brackets. They are separate copies because a node has no
# shared shell library at the point each one runs: xcatroot runs inside the
# dracut initrd, xcatpostinit1.netboot before /xcatpost is populated, and
# xcatinstallpost in the installer root. The copies must agree, so each one is
# driven with the same table.

load 'helpers/shell_source'

ENDPOINT_SCRIPTS=(
    'xCAT/postscripts/xcatinstallpost'
    'xCAT/postscripts/xcatpostinit1.netboot'
    'xCAT-server/share/xcat/netboot/rh/dracut_105/stateless/xcatroot'
)

# host_for <script> <endpoint> -- run that script's xcat_endpoint_host
host_for()
{
    local file lib
    file="$(require_repo_file "$1")"
    lib="${BATS_TEST_TMPDIR}/endpoint.sh"
    extract_shell_function "$file" 'xcat_endpoint_host' >"$lib" || return 1
    # shellcheck disable=SC1090
    . "$lib"
    xcat_endpoint_host "$2"
}

@test "an IPv4 endpoint keeps its address and loses the port" {
    for script in "${ENDPOINT_SCRIPTS[@]}"; do
        run host_for "$script" '192.0.2.10:3001'
        [ "$status" -eq 0 ]
        [ "$output" = '192.0.2.10' ]
    done
}

@test "a bracketed IPv6 endpoint yields the address without brackets or port" {
    for script in "${ENDPOINT_SCRIPTS[@]}"; do
        run host_for "$script" '[2001:db8::1]:3001'
        [ "$status" -eq 0 ]
        [ "$output" = '2001:db8::1' ]
    done
}

@test "an unbracketed IPv6 literal is returned whole, not split at a colon" {
    for script in "${ENDPOINT_SCRIPTS[@]}"; do
        run host_for "$script" '2001:db8::1'
        [ "$status" -eq 0 ]
        [ "$output" = '2001:db8::1' ]
    done
}

@test "a hostname with no port is returned unchanged" {
    for script in "${ENDPOINT_SCRIPTS[@]}"; do
        run host_for "$script" 'mn01.cluster.example'
        [ "$status" -eq 0 ]
        [ "$output" = 'mn01.cluster.example' ]
    done
}

@test "xcatinstallpost strips the quotes mypostscript writes around a value" {
    run host_for 'xCAT/postscripts/xcatinstallpost' "'[2001:db8::1]:3001'"
    [ "$status" -eq 0 ]
    [ "$output" = '2001:db8::1' ]
}

# authority_for <script> <host> <port> -- run that script's format_host_port
authority_for()
{
    local file lib
    file="$(require_repo_file "$1")"
    lib="${BATS_TEST_TMPDIR}/authority.sh"
    { extract_shell_function "$file" 'xcat_endpoint_host'
      extract_shell_function "$file" 'format_host_port'; } >"$lib" || return 1
    # shellcheck disable=SC1090
    . "$lib"
    format_host_port "$2" "$3"
}

@test "format_host_port brackets an IPv6 host and leaves an IPv4 host bare" {
    run authority_for 'xCAT/postscripts/xcatinstallpost' '2001:db8::1' 3001
    [ "$status" -eq 0 ]
    [ "$output" = '[2001:db8::1]:3001' ]

    run authority_for 'xCAT/postscripts/xcatinstallpost' '192.0.2.10' 3001
    [ "$status" -eq 0 ]
    [ "$output" = '192.0.2.10:3001' ]
}

@test "format_host_port does not bracket an address that already carries them" {
    run authority_for 'xCAT/postscripts/xcatinstallpost' '[2001:db8::1]:80' 3001
    [ "$status" -eq 0 ]
    [ "$output" = '[2001:db8::1]:3001' ]
}

# The EL10 install post-script builds its endpoints from a bare address rather
# than from an endpoint string, so it carries format_uri_host instead.
el10_authority()
{
    local file lib
    file="$(require_repo_file 'xCAT-server/share/xcat/install/scripts/post.xcat.rhels10')"
    lib="${BATS_TEST_TMPDIR}/el10.sh"
    { extract_shell_function "$file" 'format_uri_host'
      extract_shell_function "$file" 'format_host_port'; } >"$lib" || return 1
    # shellcheck disable=SC1090
    . "$lib"
    format_host_port "$1" "$2"
}

@test "the EL10 install post-script brackets an IPv6 management address" {
    run el10_authority '2001:db8::1' 3001
    [ "$status" -eq 0 ]
    [ "$output" = '[2001:db8::1]:3001' ]
}

@test "the EL10 install post-script leaves an IPv4 address and a name bare" {
    run el10_authority '192.0.2.10' 3001
    [ "$status" -eq 0 ]
    [ "$output" = '192.0.2.10:3001' ]

    run el10_authority 'mn01' 3001
    [ "$status" -eq 0 ]
    [ "$output" = 'mn01:3001' ]
}

@test "the EL10 install post-script does not double-bracket" {
    run el10_authority '[2001:db8::1]' 3001
    [ "$status" -eq 0 ]
    [ "$output" = '[2001:db8::1]:3001' ]
}
