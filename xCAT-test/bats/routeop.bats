#!/usr/bin/env bats

load 'helpers/shell_source'

setup()
{
    [ "$(uname -s)" = Linux ] || skip 'routeop filesystem isolation requires Linux'
    local bwrap utility
    bwrap=$(PATH=/usr/bin:/bin type -P bwrap) || {
        echo 'Install bubblewrap to run the routeop test' >&2
        return 1
    }
    for utility in bash cat dirname grep sed tr uname; do
        PATH=/usr/bin:/bin type -P "$utility" >/dev/null || {
            echo "Required utility is unavailable: $utility" >&2
            return 1
        }
    done
    postscripts=$(repo_path xCAT/postscripts)
    for utility in routeop xcatlib.sh; do
        [ -r "$postscripts/$utility" ] || {
            echo "Required postscript is unreadable: $postscripts/$utility" >&2
            return 1
        }
    done
    fixture="$BATS_TEST_TMPDIR/fixture"
    mkdir -p "$fixture/bin" "$fixture/etc/sysconfig/network"
    printf '%s\n' SLE VERSION=15 >"$fixture/etc/SUSE-brand"
    saved_routes="$fixture/etc/sysconfig/network/routes"
    : >"$fixture/routes"
    : >"$fixture/query"
    query_status=0
    mutation_status=0
    cat >"$fixture/bin/ip" <<'SH'
#!/bin/sh
arguments=$*
family=4
case "$1" in
    -4|-6) family=${1#-}; shift ;;
esac
case "$1 $2" in
    'route show'|'route list')
        shift 2
        [ "$1" != to ] || shift
        [ "$1" != exact ] || shift
        if [ "$family $*" = "$(cat /tmp/fixture/query)" ]; then
            cat /tmp/fixture/routes
        fi
        exit "$ROUTE_QUERY_STATUS"
        ;;
    'route add'|'route delete'|'route replace')
        printf '%s\n' "$arguments" >>/tmp/fixture/commands
        exit "$ROUTE_MUTATION_STATUS"
        ;;
    *) printf '%s\n' "unexpected ip $arguments" >>/tmp/fixture/commands; exit 97 ;;
esac
SH
    cat >"$fixture/bin/logger" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>/tmp/fixture/log
SH
    cat >"$fixture/bin/nmcli" <<'SH'
#!/bin/sh
printf '%s\n' "unexpected nmcli $*" >>/tmp/fixture/commands
exit 97
SH
    chmod +x "$fixture/bin/ip" "$fixture/bin/logger" "$fixture/bin/nmcli"
    sandbox=(env -i PATH=/usr/bin:/bin LC_ALL=C "$bwrap"
        --unshare-all --die-with-parent --new-session
        --ro-bind / / --tmpfs /tmp --tmpfs /run --proc /proc --dev /dev
        --bind "$fixture" /tmp/fixture --bind "$fixture/etc" /etc
        --ro-bind "$postscripts" /tmp/postscripts --chdir /tmp/fixture
        --setenv PATH /tmp/fixture/bin:/usr/bin:/bin --setenv LC_ALL C
        --setenv OSVER sles15)
    run "${sandbox[@]}" /bin/sh -c 'test -f /etc/SUSE-brand && test ! -e /etc/os-release'
    if [ "$status" -ne 0 ]; then
        echo "Cannot isolate routeop: $output" >&2
        return 1
    fi
}

run_routeop()
{
    : >"$fixture/commands"
    run "${sandbox[@]}" --setenv ROUTE_QUERY_STATUS "$query_status" \
        --setenv ROUTE_MUTATION_STATUS "$mutation_status" \
        /bin/bash /tmp/postscripts/routeop "$@" </dev/null
}

set_routes()
{
    printf '%s\n' "$1" >"$fixture/query"
    shift
    printf '%s\n' "$@" >"$fixture/routes"
}

assert_file()
{
    run cat "$1"
    [ "$status" -eq 0 ]
    [ "$output" = "$2" ]
}

assert_routes()
{
    run sed '/^[[:space:]]*$/d' "$saved_routes"
    [ "$status" -eq 0 ]
    [ "$output" = "$1" ]
}

assert_added_route()
{
    assert_routes "# xCAT_CONFIG_START
$1
# xCAT_CONFIG_END"
}

@test 'routeop adds IPv4 networks, hosts, and default routes' {
    local net mask destination saved
    while read -r net mask destination saved; do
        rm -f "$saved_routes"
        run_routeop add "$net" "$mask" 192.0.2.1 eth0
        [ "$status" -eq 0 ]
        assert_file "$fixture/commands" "route add $destination via 192.0.2.1"
        assert_added_route "$saved"
    done <<'CASES'
198.51.100.0 24 198.51.100.0/24 198.51.100.0/24 192.0.2.1 - eth0
192.0.2.44 32 192.0.2.44/32 192.0.2.44/32 192.0.2.1 - eth0
0.0.0.0 0 0.0.0.0/0 0.0.0.0/0 192.0.2.1 - eth0
default 0 default default 192.0.2.1 - eth0
CASES
}

@test 'routeop converts dotted IPv4 masks when adding routes' {
    local mask prefix
    while read -r mask prefix; do
        rm -f "$saved_routes"
        run_routeop add 198.51.0.0 "$mask" 192.0.2.1 eth0
        [ "$status" -eq 0 ]
        assert_file "$fixture/commands" "route add 198.51.0.0/$prefix via 192.0.2.1"
        assert_added_route "198.51.0.0 192.0.2.1 $mask eth0"
    done <<'CASES'
255.255.255.0 24
255.255.0.0 16
CASES
}

@test 'routeop adds IPv6 routes including compressed and mapped addresses' {
    local net
    for net in 2001:db8::44 2001:db8:: ::1 ::ffff:192.0.2.44; do
        rm -f "$saved_routes"
        run_routeop add "$net" 64 2001:db8:1::1 eth0
        [ "$status" -eq 0 ]
        assert_file "$fixture/commands" "-6 route add $net/64 via 2001:db8:1::1"
        assert_added_route "$net/64 2001:db8:1::1 - -"
    done
}

@test 'routeop adds IPv4 and IPv6 device routes' {
    run_routeop add 192.0.2.0 24 0.0.0.0 eth0
    [ "$status" -eq 0 ]
    assert_file "$fixture/commands" 'route add 192.0.2.0/24 dev eth0'
    assert_added_route '192.0.2.0/24 - - eth0'

    rm "$saved_routes"
    run_routeop add 2001:db8:: 64 :: eth0
    [ "$status" -eq 0 ]
    assert_file "$fixture/commands" '-6 route add 2001:db8::/64 dev eth0'
    assert_added_route '2001:db8::/64 :: - eth0'
}

@test 'routeop keeps matching IPv4 routes and does not duplicate saved entries' {
    local net mask destination saved
    while read -r net mask destination saved; do
        rm -f "$saved_routes"
        set_routes "4 $destination" "${destination%/32} via 192.0.2.1 dev eth0 proto static"
        local iteration
        for ((iteration=0; iteration<2; iteration++)); do
            run_routeop add "$net" "$mask" 192.0.2.1 eth0
            [ "$status" -eq 0 ]
            assert_file "$fixture/commands" ''
            assert_added_route "$saved"
        done
    done <<'CASES'
192.0.2.0 24 192.0.2.0/24 192.0.2.0/24 192.0.2.1 - eth0
192.0.2.0 255.255.255.0 192.0.2.0/24 192.0.2.0 192.0.2.1 255.255.255.0 eth0
192.0.2.44 32 192.0.2.44/32 192.0.2.44/32 192.0.2.1 - eth0
default 0 default default 192.0.2.1 - eth0
CASES
}

@test 'routeop distinguishes IPv4 gateway and interface tokens' {
    local gateway interface
    while read -r gateway interface; do
        set_routes '4 192.0.2.0/24' "192.0.2.0/24 via $gateway dev $interface proto static"
        run_routeop add 192.0.2.0 24 192.0.2.1 eth0
        [ "$status" -eq 0 ]
        assert_file "$fixture/commands" 'route add 192.0.2.0/24 via 192.0.2.1'
        assert_added_route '192.0.2.0/24 192.0.2.1 - eth0'
    done <<'CASES'
192.0.2.254 eth0
192.0.2.10 eth0
192.0.2.1 eth1
192.0.2.1 eth01
CASES
}

@test 'routeop finds a matching IPv4 route after nonmatching results' {
    set_routes '4 192.0.2.0/24' '192.0.2.0/24 via 192.0.2.254 dev eth0' \
        '192.0.2.0/24 via 192.0.2.1 dev eth1' \
        '192.0.2.0/24 via 192.0.2.1 dev eth0'
    run_routeop add 192.0.2.0 24 192.0.2.1 eth0
    [ "$status" -eq 0 ]
    assert_file "$fixture/commands" ''
    assert_added_route '192.0.2.0/24 192.0.2.1 - eth0'
}

@test 'routeop keeps existing IPv6 gateway and device routes' {
    set_routes '6 2001:db8::/64' '2001:db8::/64 via 2001:db8:1::1 dev eth0 proto static'
    run_routeop add 2001:db8:: 64 2001:db8:1::1 eth0
    [ "$status" -eq 0 ]
    assert_file "$fixture/commands" ''
    assert_added_route '2001:db8::/64 2001:db8:1::1 - -'

    rm "$saved_routes"
    set_routes '6 2001:db8::/64' '2001:db8::/64 dev eth0 proto static'
    run_routeop add 2001:db8:: 64 :: eth0
    [ "$status" -eq 0 ]
    assert_file "$fixture/commands" ''
    assert_added_route '2001:db8::/64 :: - eth0'
}

@test 'routeop does not treat a failed IPv6 lookup as an existing route' {
    set_routes '6 2001:db8::/64' '2001:db8::/64 via 2001:db8:1::1 dev eth0'
    query_status=2
    run_routeop add 2001:db8:: 64 2001:db8:1::1 eth0
    [ "$status" -eq 0 ]
    assert_file "$fixture/commands" '-6 route add 2001:db8::/64 via 2001:db8:1::1'
    assert_added_route '2001:db8::/64 2001:db8:1::1 - -'
}

@test 'routeop deletes an existing IPv4 route and preserves other saved routes' {
    set_routes '4 192.0.2.0/24' '192.0.2.0/24 via 192.0.2.1 dev eth0'
    printf '%s\n' '192.0.2.0 192.0.2.1 255.255.255.0 eth0' \
        '198.51.100.0 192.0.2.1 255.255.255.0 eth0' >"$saved_routes"
    run_routeop delete 192.0.2.0 255.255.255.0 192.0.2.1 eth0
    [ "$status" -eq 0 ]
    assert_file "$fixture/commands" 'route delete 192.0.2.0/24 via 192.0.2.1'
    assert_routes '198.51.100.0 192.0.2.1 255.255.255.0 eth0'
}

@test 'routeop removes saved IPv4 routes without deleting a missing live route' {
    printf '%s\n' '192.0.2.0 192.0.2.1 255.255.255.0 eth0' >"$saved_routes"
    run_routeop delete 192.0.2.0 255.255.255.0 192.0.2.1 eth0
    [ "$status" -eq 0 ]
    assert_file "$fixture/commands" ''
    assert_routes ''
}

@test 'routeop deletes an existing IPv6 route' {
    set_routes '6 2001:db8::/64' '2001:db8::/64 via 2001:db8:1::1 dev eth0'
    printf '%s\n' '2001:db8::/64 2001:db8:1::1 - -' >"$saved_routes"
    run_routeop delete 2001:db8:: 64 2001:db8:1::1 eth0
    [ "$status" -eq 0 ]
    assert_file "$fixture/commands" '-6 route delete 2001:db8::/64 via 2001:db8:1::1'
    assert_routes ''
}

@test 'routeop replaces IPv4 routes with the converted mask' {
    printf '%s\n' '192.0.2.0/24 192.0.2.254 - eth0' \
        '198.51.100.0/24 192.0.2.254 - eth0' >"$saved_routes"
    run_routeop replace 192.0.2.0 255.255.255.0 192.0.2.1 eth0
    [ "$status" -eq 0 ]
    assert_file "$fixture/commands" 'route replace 192.0.2.0/24 via 192.0.2.1'
    assert_routes '192.0.2.0/24 192.0.2.1 - eth0
198.51.100.0/24 192.0.2.254 - eth0'
}

@test 'routeop replaces IPv6 device routes' {
    run_routeop replace 2001:db8:: 64 :: eth0
    [ "$status" -eq 0 ]
    assert_file "$fixture/commands" '-6 route replace 2001:db8::/64 dev eth0'
    assert_routes '2001:db8::/64 :: - eth0'
}

@test 'routeop leaves saved routes unchanged when replacement fails' {
    printf '%s\n' '192.0.2.0/24 192.0.2.254 - eth0' >"$saved_routes"
    mutation_status=2
    run_routeop replace 192.0.2.0 24 192.0.2.1 eth0
    [ "$status" -eq 1 ]
    [[ "$output" == *'error code=2'* ]]
    assert_file "$fixture/commands" 'route replace 192.0.2.0/24 via 192.0.2.1'
    assert_routes '192.0.2.0/24 192.0.2.254 - eth0'
    [ -s "$fixture/log" ]
}
