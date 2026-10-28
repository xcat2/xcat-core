#!/usr/bin/env bats
#
# The post.xcat scripts build the URLs a node downloads its postscripts from. An IPv6
# management node address already contains colons, so "http://$MASTER_IP:$HTTPPORT/..."
# is not a URL and curl and wget both refuse it. The node then halts in %post, and xCAT
# records status=failed after the install itself succeeded.
#
# Three scripts carry the same work and each needs the helper: post.xcat.rhels10 for EL 10,
# post.xcat.ng for openEuler, EL 8, EL 9 and CentOS 8, and post.xcat for the Ubuntu and
# SUSE post scripts that include it. They are separate copies because the node has no
# shared shell library at the point each one runs, so the copies are driven with one table.

load 'helpers/shell_source'

POST_SCRIPTS=(
    'xCAT-server/share/xcat/install/scripts/post.xcat.rhels10'
    'xCAT-server/share/xcat/install/scripts/post.xcat.ng'
    'xCAT-server/share/xcat/install/scripts/post.xcat'
)

# host_for <script> <address> -- run that script's own format_uri_host
host_for()
{
    local file lib
    file="$(require_repo_file "$1")"
    lib="${BATS_TEST_TMPDIR}/uri_host.sh"
    extract_shell_function "$file" 'format_uri_host' >"$lib" || return 1
    [ -s "$lib" ] || return 1
    # shellcheck disable=SC1090
    . "$lib"
    format_uri_host "$2"
}

@test "an IPv4 management node address is used as it stands" {
    for script in "${POST_SCRIPTS[@]}"; do
        run host_for "$script" '192.0.2.1'
        [ "$status" -eq 0 ]
        [ "$output" = '192.0.2.1' ]
    done
}

@test "an IPv6 management node address is bracketed" {
    for script in "${POST_SCRIPTS[@]}"; do
        run host_for "$script" '2001:db8::1'
        [ "$status" -eq 0 ]
        [ "$output" = '[2001:db8::1]' ]
    done
}

@test "an address that is already bracketed is not bracketed again" {
    for script in "${POST_SCRIPTS[@]}"; do
        run host_for "$script" '[2001:db8::1]'
        [ "$status" -eq 0 ]
        [ "$output" = '[2001:db8::1]' ]
    done
}

@test "a hostname is used as it stands" {
    for script in "${POST_SCRIPTS[@]}"; do
        run host_for "$script" 'xcatmn.cluster'
        [ "$status" -eq 0 ]
        [ "$output" = 'xcatmn.cluster' ]
    done
}

@test "no download URL interpolates the management node address unbracketed" {
    for script in "${POST_SCRIPTS[@]}"; do
        file="$(require_repo_file "$script")"
        run grep -cE 'http://\$\{?MASTER_IP\}?' "$file"
        # grep -c prints 0 and exits 1 when nothing matches, which is the passing case.
        [ "$output" = '0' ]
    done
}
