#!/usr/bin/env bats
#
# The IPv6 default route of a SUSE node, written into /etc/sysconfig/network/routes.
#
# The route was never written: the condition read "[ a ] -a [ b ]", which is not a shell
# operator, so bash reported "too many arguments" and took the else path on every run. The
# duplicate check then spelled the character class "[:space:]" instead of "[[:space:]]", so it
# matched none of the routes already in the file and would have appended one each run.

load 'helpers/shell_source'

route()
{
    local file lib
    file="$(require_repo_file 'xCAT/postscripts/configeth')"
    lib="${BATS_TEST_TMPDIR}/configeth.sh"
    extract_shell_function "$file" 'add_suse_ipv6_default_route' >"$lib" || return 1

    bash -c '
        . "$1"
        add_suse_ipv6_default_route "$2" "$3" "$4"
    ' sh "$lib" "$1" "${2:-<xcatmaster>}" "${ROUTES}"
}

setup()
{
    ROUTES="${BATS_TEST_TMPDIR}/routes"
    : >"$ROUTES"
    export ROUTES
}

@test "a real gateway is written as the default route" {
    run route 2001:db8::ffff
    [ "$status" -eq 0 ]
    [ "$(cat "$ROUTES")" = "default 2001:db8::ffff - -" ]
}

@test "the route is written once, however many times the postscript runs" {
    route 2001:db8::ffff
    route 2001:db8::ffff
    route 2001:db8::ffff
    [ "$(grep -c . "$ROUTES")" -eq 1 ]
}

@test "a second gateway is added beside the first, not instead of it" {
    route 2001:db8::ffff
    route 2001:db8::1
    [ "$(grep -c . "$ROUTES")" -eq 2 ]
}

@test "the default token is the management node, so it is not written" {
    run route '<xcatmaster>'
    [ "$status" -eq 0 ]
    [ ! -s "$ROUTES" ]
}

@test "a gateway naming xcatmaster is not written either" {
    run route 'xcatmaster.cluster'
    [ "$status" -eq 0 ]
    [ ! -s "$ROUTES" ]
}

@test "an empty gateway is not written" {
    run route ''
    [ "$status" -eq 0 ]
    [ ! -s "$ROUTES" ]
}

@test "the condition is a valid shell test, so bash reports nothing on stderr" {
    # The original emitted "[: too many arguments" here and skipped the branch.
    run route 2001:db8::ffff
    [ "$status" -eq 0 ]
    [[ "$output" != *"too many arguments"* ]]
}
