#!/usr/bin/env bats
#
# pre.sle and pre.sles run in the SUSE installer. Both read the install server out of the
# kernel command line and put it back into a URL: pre.sle substitutes it for
# XCATNEXTSERVERHOOK in the media_url of every install source xCAT::Template wrote.
#
# The derivation cut the authority at the first colon, which splits an IPv6 literal.
# "autoyast=http://[2001:db8::1]:80/install/autoinst/node01" yielded "[2001", so the
# media_url read "http://[2001:80/install/..." and YaST had no install source.

load 'helpers/shell_source'

setup()
{
    SLE="$(require_repo_file 'xCAT-server/share/xcat/install/scripts/pre.sle')"
    SLES="$(require_repo_file 'xCAT-server/share/xcat/install/scripts/pre.sles')"
}

# nextserver_for <script> <kernel command line> -- run the script's own derivation
# against a command line of our own, and print what it exports.
#
# The derivation is taken from the script rather than retyped, so a change to it is
# measured here. Only the path it reads is rewritten.
nextserver_for()
{
    local script="$1" cmdline="$2" name
    local snippet="${BATS_TEST_TMPDIR}/nextserver.sh"
    local fixture="${BATS_TEST_TMPDIR}/cmdline"

    printf '%s\n' "$cmdline" >"$fixture"
    : >"$snippet"
    for name in extract_url_host url_host_literal; do
        extract_shell_function "$script" "$name" >>"$snippet" 2>/dev/null
    done
    grep -E '^[[:space:]]*(NEXTSERVER_URL=|export nextserver=)' "$script" >>"$snippet" \
      || return 1
    sed -i "s#/proc/cmdline#${fixture}#g" "$snippet"

    (
        # shellcheck disable=SC1090
        . "$snippet" >/dev/null 2>&1
        printf '%s\n' "$nextserver"
    )
}

@test "pre.sle keeps the brackets of an IPv6 install server" {
    run nextserver_for "$SLE" \
      'ro install=http://[2001:db8::1]/install/leap15.6/x86_64/1 autoyast=http://[2001:db8::1]/install/autoinst/node01'
    [ "$status" -eq 0 ]
    [ "$output" = '[2001:db8::1]' ]
}

@test "pre.sle keeps the whole IPv6 address when the URL carries a port" {
    run nextserver_for "$SLE" \
      'ro autoyast=http://[2001:db8::1]:80/install/autoinst/node01 ipv6only=1'
    [ "$output" = '[2001:db8::1]' ]
}

@test "pre.sle leaves an IPv4 install server unbracketed" {
    run nextserver_for "$SLE" 'ro autoyast=http://192.0.2.1/install/autoinst/node01'
    [ "$status" -eq 0 ]
    [ "$output" = '192.0.2.1' ]
}

@test "pre.sle drops the port of an IPv4 install server" {
    run nextserver_for "$SLE" 'ro autoyast=http://192.0.2.1:80/install/autoinst/node01'
    [ "$output" = '192.0.2.1' ]
}

@test "pre.sle keeps a hostname install server" {
    run nextserver_for "$SLE" \
      'ro autoyast=http://mn01.cluster.example:80/install/autoinst/node01'
    [ "$output" = 'mn01.cluster.example' ]
}

@test "the media_url pre.sle builds from an IPv6 server is a URL" {
    local server media
    server="$(nextserver_for "$SLE" 'ro autoyast=http://[2001:db8::1]:80/install/autoinst/node01')"
    media="http://${server}:80/install/leap15.6/x86_64/1"
    [ "$media" = 'http://[2001:db8::1]:80/install/leap15.6/x86_64/1' ]
}

@test "pre.sles keeps the brackets of an IPv6 install server" {
    run nextserver_for "$SLES" \
      'ro autoyast=http://[2001:db8::1]:80/install/autoinst/node01'
    [ "$status" -eq 0 ]
    [ "$output" = '[2001:db8::1]' ]
}

@test "pre.sles leaves an IPv4 install server unbracketed" {
    run nextserver_for "$SLES" 'ro autoyast=http://192.0.2.1:80/install/autoinst/node01'
    [ "$output" = '192.0.2.1' ]
}
