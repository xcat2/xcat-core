#!/usr/bin/env bats

load 'helpers/script_sandbox'

setup()
{
    setup_script_sandbox cat dirname grep sed tr uname logger awk cut head rm touch mkdir mv
    local ip_binary
    ip_binary=$(PATH=/usr/sbin:/sbin:/usr/bin:/bin type -P ip) || return 1
    cp -L "$ip_binary" "$fixture/bin/ip"
    mkdir -p "$fixture/etc/sysconfig/network"
    printf '%s\n' SLE VERSION=15 >"$fixture/etc/SUSE-brand"
    sandbox+=(--ro-bind "$(repo_path xCAT/postscripts)" /tmp/postscripts
        --setenv OSVER sles15 --uid 0 --gid 0 --cap-add CAP_NET_ADMIN)
    cat >"$fixture/bin/route-test" <<'SH'
#!/bin/bash
set -eu
ip link set lo up
for dev in test0 test1; do
    ip link add "$dev" type dummy
    ip link set "$dev" up
    ip -6 address add fe80::2/64 dev "$dev" nodad
    ip -6 address add 2001:db8:1::2/64 dev "$dev" nodad
done
exec /bin/bash -eu -c "$1"
SH
    chmod +x "$fixture/bin/route-test"
}

run_routes()
{
    run "${sandbox[@]}" /bin/bash /bin/route-test "$1"
    [ "$status" -eq 0 ]
}

@test 'routeop installs and repeats a link-local gateway route on its device' {
    run_routes '
        for pass in 1 2; do
            /tmp/postscripts/routeop add 2001:db8:2:: 64 fe80::1 test0
            ip -6 route show 2001:db8:2::/64 |
                grep -q "2001:db8:2::/64 via fe80::1 dev test0"
        done
        test "$(grep -c "^2001:db8:2::/64 fe80::1 - test0$" /etc/sysconfig/network/routes)" = 1
    '
}

@test 'routeop does not confuse a link-local route on another device' {
    run_routes '
        ip -6 route add 2001:db8:2::/64 via fe80::1 dev test1 metric 2000
        /tmp/postscripts/routeop add 2001:db8:2:: 64 fe80::1 test0
        ip -6 route show 2001:db8:2::/64 | grep -q "2001:db8:2::/64 via fe80::1 dev test0"
        ip -6 route show 2001:db8:2::/64 | grep -q "2001:db8:2::/64 via fe80::1 dev test1"
    '
}

@test 'routeop replaces and deletes the scoped gateway without deleting a neighbor' {
    run_routes '
        /tmp/postscripts/routeop replace 2001:db8:2:: 64 fe80::1 test0
        ip -6 route show 2001:db8:2::/64 | grep -q "2001:db8:2::/64 via fe80::1 dev test0"
        /tmp/postscripts/routeop replace 2001:db8:2:: 64 fe80::3 test0
        ip -6 route show 2001:db8:2::/64 | grep -q "2001:db8:2::/64 via fe80::3 dev test0"
        grep -qx "2001:db8:2::/64 fe80::3 - test0" /etc/sysconfig/network/routes
        ip -6 route add 2001:db8:2::/64 via fe80::3 dev test1 metric 512
        /tmp/postscripts/routeop delete 2001:db8:2:: 64 fe80::3 test0
        test -z "$(ip -6 route show 2001:db8:2::/64 via fe80::3 dev test0)"
        ip -6 route show 2001:db8:2::/64 | grep -q "2001:db8:2::/64 via fe80::3 dev test1"
        test -z "$(sed "/^[[:space:]]*$/d" /etc/sysconfig/network/routes)"
    '
}

@test 'routeop scopes expanded and upper-case link-local gateways' {
    run_routes '
        /tmp/postscripts/routeop replace 2001:db8:2:: 64 FE80:0000:0000:0000:0000:0000:0000:0001 test0
        ip -6 route show 2001:db8:2::/64 | grep -q "2001:db8:2::/64 via fe80::1 dev test0"
        grep -qx "2001:db8:2::/64 FE80:0000:0000:0000:0000:0000:0000:0001 - test0" /etc/sysconfig/network/routes
    '
}

@test 'routeop leaves persistence unchanged when a scoped replacement fails' {
    run_routes '
        echo "2001:db8:2::/64 fe80::1 - test0" >/etc/sysconfig/network/routes
        if /tmp/postscripts/routeop replace 2001:db8:2:: 64 fe80::3 missing0; then exit 1; fi
        grep -qx "2001:db8:2::/64 fe80::1 - test0" /etc/sysconfig/network/routes
        test -z "$(ip -6 route show 2001:db8:2::/64)"
    '
}

@test 'routeop retains global-gateway and connected-route behavior' {
    run_routes '
        /tmp/postscripts/routeop replace 2001:db8:2:: 64 2001:db8:1::1 test0
        ip -6 route show 2001:db8:2::/64 | grep -q "via 2001:db8:1::1"
        grep -qx "2001:db8:2::/64 2001:db8:1::1 - -" /etc/sysconfig/network/routes
        /tmp/postscripts/routeop replace 2001:db8:3:: 64 :: test0
        ip -6 route show 2001:db8:3::/64 | grep -q "dev test0"
        grep -qx "2001:db8:3::/64 :: - test0" /etc/sysconfig/network/routes
    '
}

@test 'routeop deletes exact SLES records and older unscoped entries' {
    run_routes '
        printf "%s\n" "2001:db8:2::/64 fe80::1 - test0" \
            "2001:db8:2::/64 fe80::1 - test01" \
            "2001:db8:3::/64 fe80::1 - -" >/etc/sysconfig/network/routes
        /tmp/postscripts/routeop delete 2001:db8:2:: 64 fe80::1 test0
        /tmp/postscripts/routeop delete 2001:db8:3:: 64 fe80::1 test0
        test "$(cat /etc/sysconfig/network/routes)" = "2001:db8:2::/64 fe80::1 - test01"
    '
}

@test 'routeop replaces an unscoped SLES entry without matching another device' {
    run_routes '
        printf "%s\n" "2001:db8:2::/64 fe80::1 - -" \
            "2001:db8:2::/64 fe80::1 - test01" >/etc/sysconfig/network/routes
        /tmp/postscripts/routeop add 2001:db8:2:: 64 fe80::1 test0
        test "$(grep -c "^2001:db8:2::/64 fe80::1 - test0$" /etc/sysconfig/network/routes)" = 1
        grep -qx "2001:db8:2::/64 fe80::1 - test01" /etc/sysconfig/network/routes
        test "$(grep -c " - -$" /etc/sysconfig/network/routes)" = 0
    '
}

@test 'routeop treats dotted interface names literally in saved routes' {
    run_routes '
        ip link add test0.1 type dummy
        ip link set test0.1 up
        printf "%s\n" "2001:db8:2::/64 fe80::1 - test0x1" >/etc/sysconfig/network/routes
        /tmp/postscripts/routeop add 2001:db8:2:: 64 fe80::1 test0.1
        grep -Fqx "2001:db8:2::/64 fe80::1 - test0.1" /etc/sysconfig/network/routes
        /tmp/postscripts/routeop delete 2001:db8:2:: 64 fe80::1 test0.1
        test "$(sed "/^#/d;/^$/d" /etc/sysconfig/network/routes)" = "2001:db8:2::/64 fe80::1 - test0x1"
    '
}

@test 'routeop retains the device in legacy Red Hat route6 files' {
    run_routes '
        rm /etc/SUSE-brand
        touch /etc/redhat-release
        mkdir -p /etc/sysconfig/network-scripts
        export OSVER=rhels8
        /tmp/postscripts/routeop replace 2001:db8:2:: 64 fe80::1 test0
        test "$(cat /etc/sysconfig/network-scripts/route6-test0)" = "2001:db8:2::/64 via fe80::1 dev test0"
        ip -6 route show 2001:db8:2::/64 | grep -q "via fe80::1 dev test0"
        printf "%s\n" "test0 2001:db8:2::/64 fe80::1" "test01 2001:db8:2::/64 fe80::1" >/etc/sysconfig/static-routes-ipv6
        /tmp/postscripts/routeop delete 2001:db8:2:: 64 fe80::1 test0
        test ! -s /etc/sysconfig/network-scripts/route6-test0
        test "$(cat /etc/sysconfig/static-routes-ipv6)" = "test01 2001:db8:2::/64 fe80::1"
        test -z "$(ip -6 route show 2001:db8:2::/64)"
        echo "2001:db8:2::/64 via fe80::1" >/etc/sysconfig/network-scripts/route6-test0
        /tmp/postscripts/routeop delete 2001:db8:2:: 64 fe80::1 test0
        test ! -s /etc/sysconfig/network-scripts/route6-test0
    '
}

@test 'routeop scopes Debian interface up and down gateway commands' {
    run_routes '
        rm /etc/SUSE-brand
        touch /etc/debian_version
        mkdir -p /etc/network/interfaces.d
        printf "%s\n" "#XCAT_CONFIG" "source /etc/network/interfaces.d/*" >/etc/network/interfaces
        export OSVER=ubuntu24.04
        for layout in last middle; do
            printf "%s\n" "auto test0" "iface test0 inet manual" >/etc/network/interfaces.d/test0
            printf "%s\n" "  up route -A inet6 add 2001:db8:2::/64 gw fe80::1" \
                "  down route -A inet6 del 2001:db8:2::/64 gw fe80::1" \
                "post-up ip -6 route replace 2001:db8:2::/64 via fe80::1" >>/etc/network/interfaces.d/test0
            if [ "$layout" = middle ]; then echo "iface test1 inet manual" >>/etc/network/interfaces.d/test0; fi
            /tmp/postscripts/routeop add 2001:db8:2:: 64 fe80::1 test0
            grep -Fxq "  up route -A inet6 add 2001:db8:2::/64 gw fe80::1 dev test0" /etc/network/interfaces.d/test0
            grep -Fxq "  down route -A inet6 del 2001:db8:2::/64 gw fe80::1 dev test0" /etc/network/interfaces.d/test0
            if grep -Fxq "post-up ip -6 route replace 2001:db8:2::/64 via fe80::1" /etc/network/interfaces.d/test0; then exit 1; fi
            /tmp/postscripts/routeop delete 2001:db8:2:: 64 fe80::1 test0
            test "$(grep -c "2001:db8:2::" /etc/network/interfaces.d/test0)" = 0
            /tmp/postscripts/routeop replace 2001:db8:2:: 64 fe80::1 test0
            grep -Fxq "post-up ip -6 route replace 2001:db8:2::/64 via fe80::1 dev test0" /etc/network/interfaces.d/test0
            ip -6 route show 2001:db8:2::/64 | grep -q "via fe80::1 dev test0"
            /tmp/postscripts/routeop delete 2001:db8:2:: 64 fe80::1 test0
            test "$(grep -c "2001:db8:2::" /etc/network/interfaces.d/test0)" = 0
        done
    '
}
