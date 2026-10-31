#!/usr/bin/env bats
#
# xcatdsklspost downloads the postscripts and the generated mypostscript over
# HTTP from the management or service node. The server value it is given is a
# "host:port" string, so an IPv6 management node has to be split and rebuilt
# with brackets before it goes into a URL. XCATDSKLSPOST_SOURCE_ONLY makes the
# script define its helpers and return without running its main body.

load 'helpers/shell_source'

setup()
{
    SCRIPT="$(require_repo_file 'xCAT/postscripts/xcatdsklspost')"
    XCATDSKLSPOST_SOURCE_ONLY=1
    export XCATDSKLSPOST_SOURCE_ONLY
    # shellcheck disable=SC1090
    . "$SCRIPT"
}

@test "parsehttpserver splits a bracketed IPv6 authority into host and port" {
    [ "$(parsehttpserver '[2001:db8::1]:8080' 'server')" = '2001:db8::1' ]
    [ "$(parsehttpserver '[2001:db8::1]:8080' 'port')" = '8080' ]
}

@test "a bracketed IPv6 authority with no port gets the default port" {
    [ "$(parsehttpserver '[2001:db8::1]' 'server')" = '2001:db8::1' ]
    [ "$(parsehttpserver '[2001:db8::1]' 'port')" = '80' ]
}

@test "an unbracketed IPv6 literal is not split at its last colon" {
    [ "$(parsehttpserver '2001:db8::1' 'server')" = '2001:db8::1' ]
    [ "$(parsehttpserver '2001:db8::1' 'port')" = '80' ]
}

@test "IPv4 and hostname authorities keep their existing behaviour" {
    [ "$(parsehttpserver '192.0.2.10:8080' 'server')" = '192.0.2.10' ]
    [ "$(parsehttpserver '192.0.2.10:8080' 'port')" = '8080' ]
    [ "$(parsehttpserver '192.0.2.10' 'port')" = '80' ]
    [ "$(parsehttpserver 'mn01' 'server')" = 'mn01' ]
    [ "$(parsehttpserver 'mn01' 'port')" = '80' ]
}

@test "format_host_port rebuilds an authority a URL can carry" {
    [ "$(format_host_port '2001:db8::1' '80')" = '[2001:db8::1]:80' ]
    [ "$(format_host_port '192.0.2.10' '80')" = '192.0.2.10:80' ]
}

@test "the two helpers compose, so an authority survives a round trip" {
    local raw host port
    for raw in '[2001:db8::1]:8080' '192.0.2.10:8080' 'mn01:80'; do
        host="$(parsehttpserver "$raw" 'server')"
        port="$(parsehttpserver "$raw" 'port')"
        [ "$(format_host_port "$host" "$port")" = "$raw" ]
    done
}
