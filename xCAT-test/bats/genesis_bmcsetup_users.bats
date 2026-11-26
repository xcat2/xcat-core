#!/usr/bin/env bats

load 'helpers/bmc_sandbox'

setup()
{
    setup_bmc_fixture "${XCAT_TEST_BMCSETUP:-}"
}

@test 'bmcsetup disables only enabled non-target users' {
    run_genesis 0
    run cat "$fixture/disabled"
    [ "$status" -eq 0 ]
    [ "$output" = 4 ]
    grep -Fx -- '-d 0 user enable 2' "$fixture/calls"
    [ ! -e "$fixture/tmp/ipmicfg.xml" ]
}

@test 'bmcsetup leaves disabled non-target users alone' {
    sed -i 's/4   olduser.*/4   olduser          true    true       false      NO ACCESS/' "$fixture/users"
    run_genesis 0
    [ ! -e "$fixture/disabled" ]
    grep -Fx -- '-d 0 user enable 2' "$fixture/calls"
    [ ! -e "$fixture/tmp/ipmicfg.xml" ]
}

lan_calls()
{
    grep -E -- '^-d [0-9]+ lan (print|set [0-9]+ (ipsrc|ipaddr|netmask|defgw|vlan))' "$fixture/calls"
}

@test 'bmcsetup leaves matching LAN settings unchanged' {
    sed -i 's/<taggedvlan>off/<taggedvlan>42/' "$fixture/ipmicfg.xml"
    run_genesis 0
    run lan_calls
    [ "$output" = '-d 0 lan print 1
-d 0 lan print 1
-d 0 lan print 1
-d 0 lan print 1
-d 0 lan print 1' ]
    [ ! -e "$fixture/tmp/ipmicfg.xml" ]
}

@test 'bmcsetup rereads each LAN field after a failed write' {
    sed -i 's/<taggedvlan>off/<taggedvlan>42/' "$fixture/ipmicfg.xml"
    : >"$fixture/lan.0"
    echo 1 >"$fixture/failures"
    run_genesis 0
    run lan_calls
    [ "$output" = '-d 0 lan print 1
-d 0 lan set 1 ipsrc static
-d 0 lan print 1
-d 0 lan set 1 ipsrc static
-d 0 lan print 1
-d 0 lan set 1 ipaddr 192.0.2.2
-d 0 lan print 1
-d 0 lan set 1 ipaddr 192.0.2.2
-d 0 lan print 1
-d 0 lan set 1 netmask 255.255.255.0
-d 0 lan print 1
-d 0 lan set 1 netmask 255.255.255.0
-d 0 lan print 1
-d 0 lan set 1 defgw ipaddr 192.0.2.1
-d 0 lan print 1
-d 0 lan set 1 defgw ipaddr 192.0.2.1
-d 0 lan print 1
-d 0 lan set 1 vlan id 42
-d 0 lan print 1
-d 0 lan set 1 vlan id 42' ]
    run cat "$fixture/sleeps"
    [ "$output" = '5
1
1
1
1
1
1' ]
}

@test 'bmcsetup stops retrying when a refreshed LAN value matches' {
    sed -i 's/<taggedvlan>off/<taggedvlan>42/' "$fixture/ipmicfg.xml"
    : >"$fixture/lan.0.1"
    echo 99 >"$fixture/failures"
    run_genesis 0
    run lan_calls
    [ "$output" = '-d 0 lan print 1
-d 0 lan set 1 ipsrc static
-d 0 lan print 1
-d 0 lan print 1
-d 0 lan print 1
-d 0 lan print 1
-d 0 lan print 1' ]
}

@test 'bmcsetup retains the LAN write retry limit' {
    sed -i 's/<taggedvlan>off/<taggedvlan>42/' "$fixture/ipmicfg.xml"
    : >"$fixture/lan.0"
    echo 99 >"$fixture/failures"
    run_genesis 0
    local setting
    for setting in ipsrc ipaddr netmask defgw vlan; do
        [ "$(cat "$fixture/writes.0.$setting")" = 16 ]
    done
    [ "$(grep -c -- '^-d 0 lan print 1$' "$fixture/calls")" = 80 ]
    [ "$(grep -cx 1 "$fixture/sleeps")" = 81 ]
    [ ! -e "$fixture/tmp/ipmicfg.xml" ]
}

@test 'bmcsetup keeps LAN device indexes and the selected channel' {
    sed -i 's/<taggedvlan>off/<taggedvlan>42/' "$fixture/ipmicfg.xml"
    cat >>"$fixture/ipmicfg.xml" <<'XML'
<bmcip>198.51.100.2</bmcip>
<taggedvlan>43</taggedvlan>
<gateway>198.51.100.1</gateway>
<netmask>255.255.0.0</netmask>
XML
    : >"$fixture/lan.1"
    echo 3 >"$fixture/channel"
    run_genesis 0
    run lan_calls
    [ "$output" = '-d 1 lan print 3
-d 1 lan set 3 ipsrc static
-d 0 lan print 3
-d 0 lan print 3
-d 1 lan print 3
-d 1 lan set 3 ipaddr 198.51.100.2
-d 0 lan print 3
-d 1 lan print 3
-d 1 lan set 3 netmask 255.255.0.0
-d 0 lan print 3
-d 1 lan print 3
-d 1 lan set 3 defgw ipaddr 198.51.100.1
-d 0 lan print 3
-d 1 lan print 3
-d 1 lan set 3 vlan id 43' ]
}

@test 'bmcsetup retains usable LAN output when ipmitool reports a read error' {
    sed -i 's/<taggedvlan>off/<taggedvlan>42/' "$fixture/ipmicfg.xml"
    sed -i 's/IPMI Version : 2.0/IPMI Version : 1.5/' "$fixture/mcinfo"
    touch "$fixture/read-error"
    run_genesis 0
    [ "$(printf '%s\n' "$output" | grep -cx 'LAN read returned an error')" = 5 ]
    run lan_calls
    [ "$output" = '-d 0 lan print 1
-d 0 lan print 1
-d 0 lan print 1
-d 0 lan print 1
-d 0 lan print 1' ]
}

@test 'bmcsetup retains defaults for absent optional configuration fields' {
    sed -i '/taggedvlan\|gateway\|ipcfgmethod/d' "$fixture/ipmicfg.xml"
    : >"$fixture/lan.0"
    run_genesis 0
    run lan_calls
    [ "$output" = '-d 0 lan print 1
-d 0 lan set 1 ipsrc static
-d 0 lan print 1
-d 0 lan set 1 ipaddr 192.0.2.2
-d 0 lan print 1
-d 0 lan set 1 netmask 255.255.255.0' ]
    grep -Fx 'raw 0xc 1 1 0x14 0 0' "$fixture/calls"
    grep -Fx -- '-d 0 user set password 2 test-password' "$fixture/calls"
    [ ! -e "$fixture/tmp/ipmicfg.xml" ]
}

@test 'bmcsetup retries configuration retrieval before reading the complete reply' {
    sed '/bmcip/d' "$fixture/ipmicfg.xml" >"$fixture/ipmicfg.1.xml"
    run_genesis 0
    [ "$(cat "$fixture/retrievals")" = 2 ]
    run cat "$fixture/sleeps"
    [ "$output" = '5
15
1' ]
    grep -F 'FAILED TO RETRIEVE SETTINGS, RETRYING in 15 seconds' "$fixture/messages"
    grep -Fx -- '-d 0 user enable 2' "$fixture/calls"
    [ ! -e "$fixture/tmp/ipmicfg.xml" ]
}

@test 'bmcsetup uses configured user and long password values' {
    sed -i 's/USERID/operator/; s/test-password/01234567890123456789/; s/^/  /' "$fixture/ipmicfg.xml"
    sed -i 's/USERID/operator/' "$fixture/users"
    run_genesis 0
    grep -Fx -- '-d 0 user enable 2' "$fixture/calls"
    grep -Fx -- '-d 0 user set password 2 01234567890123456789 20' "$fixture/calls"
    run cat "$fixture/disabled"
    [ "$output" = 4 ]
    [ ! -e "$fixture/tmp/ipmicfg.xml" ]
}

@test 'bmcsetup reads the configured port in each vendor branch' {
    local manufacturer product port expected
    while IFS='|' read -r manufacturer product port expected; do
        printf 'Vendor %s product %s port %s\n' "$manufacturer" "$product" "$port"
        printf '%s\n' 'IPMI Version : 1.5' "Manufacturer ID : $manufacturer" \
            "Product ID : $product" >"$fixture/mcinfo"
        sed -i '/bmcport/d' "$fixture/ipmicfg.xml"
        printf '<bmcport>%s</bmcport>\n' "$port" >>"$fixture/ipmicfg.xml"
        rm -f "$fixture/calls"
        run_genesis 0
        grep -Fx -- "$expected" "$fixture/calls"
        [ ! -e "$fixture/tmp/ipmicfg.xml" ]
    done <<'CASES'
2|220|1|-d 0 raw 0xc 1 1 0xc0 1
2|100|1|-d 0 raw 0xc 1 1 0xc0 1
19046|1287|0|raw 0x32 0x71 0 1 0
19046|100|1|-d 0 raw 0xc 1 1 0xc0 1
674|100|1|raw 0x30 0x28 0x01 0x00
674|100|0 2 3|raw 0x30 0x28 0x03 0x04
10876|2437|0|raw 0x30 0x70 0x0c 1 1
10876|2437|1|raw 0x30 0x70 0x0c 1 0
343|149|1|-d 0 lan print 3
CASES
}
