#!/usr/bin/env bats

load 'helpers/bmc_sandbox'

setup()
{
    setup_bmc_fixture
}

ipv6_config()
{
    cat >"$fixture/ipmicfg.xml" <<'XML'
<bmcip>2001:db8:1::20</bmcip>
<taggedvlan>off</taggedvlan>
<gateway>2001:db8:1::1</gateway>
<netmask>64</netmask>
<routerprefix>2001:db8:1::</routerprefix>
<username>USERID</username>
<password>test-password</password>
XML
}

lan_writes()
{
    grep -E -- '^-d [0-9]+ lan(6 set| print| set [0-9]+ (ipsrc|ipaddr|netmask|defgw))' "$fixture/calls"
}

@test 'bmcsetup gives the BMC a static IPv6 address and router' {
    ipv6_config
    run_genesis 0
    run lan_writes
    [ "$output" = '-d 0 lan6 set 1 nolock enables both
-d 0 lan6 set 1 nolock static_addr 0 enable 2001:db8:1::20 64
-d 0 lan6 set 1 nolock rtr_cfg both
-d 0 lan6 set 1 nolock static_rtr 1 2001:db8:1::1 00:00:00:00:00:00 2001:db8:1:: 64' ]
    grep -Fx -- '-d 0 user enable 2' "$fixture/calls"
    [ ! -e "$fixture/tmp/ipmicfg.xml" ]
}

@test 'bmcsetup sets no IPv6 router when xCAT sends no gateway' {
    ipv6_config
    sed -i '/gateway\|routerprefix/d' "$fixture/ipmicfg.xml"
    run_genesis 0
    run lan_writes
    [ "$output" = '-d 0 lan6 set 1 nolock enables both
-d 0 lan6 set 1 nolock static_addr 0 enable 2001:db8:1::20 64' ]
}

@test 'bmcsetup keeps IPv6 device indexes and the selected channel' {
    cat >"$fixture/ipmicfg.xml" <<'XML'
<bmcip>2001:db8:1::20</bmcip>
<gateway></gateway>
<netmask>64</netmask>
<routerprefix>2001:db8:1::</routerprefix>
<bmcip>2001:db8:2::20</bmcip>
<gateway>2001:db8:2::1</gateway>
<netmask>80</netmask>
<routerprefix>2001:db8:2::</routerprefix>
<username>USERID</username>
<password>test-password</password>
XML
    echo 3 >"$fixture/channel"
    run_genesis 0
    run lan_writes
    [ "$output" = '-d 0 lan6 set 3 nolock enables both
-d 0 lan6 set 3 nolock static_addr 0 enable 2001:db8:1::20 64
-d 1 lan6 set 3 nolock enables both
-d 1 lan6 set 3 nolock static_addr 0 enable 2001:db8:2::20 80
-d 1 lan6 set 3 nolock rtr_cfg both
-d 1 lan6 set 3 nolock static_rtr 1 2001:db8:2::1 00:00:00:00:00:00 2001:db8:2:: 80' ]
}

@test 'bmcsetup reports an IPv6 write that keeps failing and continues' {
    ipv6_config
    touch "$fixture/lan6-fails"
    run_genesis 0
    [ "$(grep -c -- '^-d 0 lan6 set 1 nolock static_addr 0 enable 2001:db8:1::20 64$' "$fixture/calls")" = 16 ]
    grep -F 'ipmitool lan6 set 1 static_addr 0 enable 2001:db8:1::20 64 failed' "$fixture/messages"
    grep -Fx -- '-d 0 user enable 2' "$fixture/calls"
}

# doxcat starts bmcsetup with XCATMASTER already exported. bmcsetup reads the
# address from the xcatd= kernel argument again.
doxcat_master()
{
    echo "BOOTIF=01-52-54-00-00-00-01 xcatd=$1" >"$fixture/cmdline"
    sandbox+=(--setenv XCATMASTER "$2")
}

@test 'bmcsetup reports BMC status to an IPv6 xcatd' {
    ipv6_config
    doxcat_master '[2001:db8::1]:3001' '2001:db8::1'
    run_genesis 0
    run cat "$fixture/flags"
    [ "$output" = '2001:db8::1 3002 installstatus bmcready' ]
    run cat "$fixture/allowcred"
    [ "$output" = '2001:db8::1' ]
}

@test 'bmcsetup reports BMC status to an IPv4 xcatd' {
    doxcat_master '192.0.2.1:3001' '192.0.2.1'
    run_genesis 0
    run cat "$fixture/flags"
    [ "$output" = '192.0.2.1 3002 installstatus bmcready' ]
    run cat "$fixture/allowcred"
    [ "$output" = '192.0.2.1' ]
}

openbmc()
{
    printf '%s\n' 'IPMI Version : 2.0' 'Manufacturer ID : 42817' 'Product ID : 16975' >"$fixture/mcinfo"
}

@test 'bmcsetup reports an OpenBMC ready when it reads back its IPv6 address' {
    openbmc
    ipv6_config
    cat >"$fixture/lan6.0" <<'LAN'
IPv6 Static Address 0:
    Enabled: yes
    Address: 2001:db8:1::20/64
    Status:  active
LAN
    doxcat_master '[2001:db8::1]:3001' '2001:db8::1'
    run_genesis 0
    run cat "$fixture/flags"
    [ "$output" = '2001:db8::1 3002 installstatus bmcready' ]
}

@test 'bmcsetup reports an OpenBMC failed when its IPv6 address does not read back' {
    openbmc
    ipv6_config
    cat >"$fixture/lan6.0" <<'LAN'
IPv6 Static Address 0:
    Enabled: no
    Address: ::/0
LAN
    doxcat_master '[2001:db8::1]:3001' '2001:db8::1'
    run_genesis 0
    run cat "$fixture/flags"
    [ "$output" = '2001:db8::1 3002 installstatus failed' ]
}

@test 'bmcsetup reports an OpenBMC ready when it reads back its IPv4 address' {
    openbmc
    doxcat_master '192.0.2.1:3001' '192.0.2.1'
    run_genesis 0
    run cat "$fixture/flags"
    [ "$output" = '192.0.2.1 3002 installstatus bmcready' ]
}

# openbmc_status <configured> <read back> -- give the OpenBMC the IPv6 address
# <configured>, let lan6 print report <read back>, and print the status that
# bmcsetup sends.
openbmc_status()
{
    openbmc
    ipv6_config
    sed -i "s|<bmcip>.*</bmcip>|<bmcip>$1</bmcip>|" "$fixture/ipmicfg.xml"
    cat >"$fixture/lan6.0" <<LAN
IPv6 Dynamic Address 0:
    Source/Type:    DHCPv6
    Address:        2001:db8:9::99/64
    Status:         active
IPv6 Static Address 0:
    Enabled:        yes
    Address:        $2
    Status:         active
LAN
    rm -f "$fixture/flags"
    doxcat_master '[2001:db8::1]:3001' '2001:db8::1'
    run_genesis 0 || return 1
    cat "$fixture/flags"
}

@test 'bmcsetup reports an OpenBMC ready for another spelling of its IPv6 address' {
    local configured readback
    while read -r configured readback; do
        run openbmc_status "$configured" "$readback"
        [ "$status" -eq 0 ]
        [ "$output" = '2001:db8::1 3002 installstatus bmcready' ] || {
            echo "$configured read back as $readback: $output"; return 1; }
    done <<'CASES'
2001:0db8:0001:0000:0000:0000:0000:0020 2001:db8:1::20/64
2001:DB8:1::20 2001:db8:1::20/64
2001:db8:1::20 2001:0DB8:1:0:0:0:0:20
2001:db8:1::20/64 2001:db8:1::20
2001:db8:1:0:0:0:0:20 2001:db8:1::20/64
CASES
}

@test 'bmcsetup reports an OpenBMC ready for a dotted-decimal spelling of its IPv6 address' {
    local configured readback
    while read -r configured readback; do
        run openbmc_status "$configured" "$readback"
        [ "$status" -eq 0 ]
        [ "$output" = '2001:db8::1 3002 installstatus bmcready' ] || {
            echo "$configured read back as $readback: $output"; return 1; }
    done <<'CASES'
2001:db8:1::192.0.2.20 2001:db8:1::c000:214/64
2001:db8:1::c000:214 2001:db8:1::192.0.2.20/64
2001:db8:1::192.0.2.20 2001:db8:1::192.0.2.20/64
::ffff:192.0.2.20 ::ffff:c000:214
CASES
}

@test 'bmcsetup reports an OpenBMC failed for a different dotted-decimal IPv6 address' {
    local configured readback
    while read -r configured readback; do
        run openbmc_status "$configured" "$readback"
        [ "$status" -eq 0 ]
        [ "$output" = '2001:db8::1 3002 installstatus failed' ] || {
            echo "$configured read back as $readback: $output"; return 1; }
    done <<'CASES'
2001:db8:1::192.0.2.20 2001:db8:1::c000:215/64
2001:db8:1::c000:214 2001:db8:1::192.0.2.21/64
2001:db8:1::c000:214 2001:db8:1::192.0.2.276/64
CASES
}

@test 'bmcsetup reports an OpenBMC failed for an IPv6 address that only shares a text prefix' {
    local configured readback
    while read -r configured readback; do
        run openbmc_status "$configured" "$readback"
        [ "$status" -eq 0 ]
        [ "$output" = '2001:db8::1 3002 installstatus failed' ] || {
            echo "$configured read back as $readback: $output"; return 1; }
    done <<'CASES'
2001:db8:1::2 2001:db8:1::20/64
2001:db8:1::20 2001:db8:1::2/64
2001:db8:1::20 2001:db8:1::200/64
2001:db8:1::20 12001:db8:1::20/64
CASES
}

@test 'bmcsetup reports an OpenBMC failed for an IPv4 address that only shares a text prefix' {
    openbmc
    sed -i 's/IP Address              : 192.0.2.2/IP Address              : 192.0.2.20/' "$fixture/lan.0"
    doxcat_master '192.0.2.1:3001' '192.0.2.1'
    run_genesis 0
    run cat "$fixture/flags"
    [ "$output" = '192.0.2.1 3002 installstatus failed' ]
}
