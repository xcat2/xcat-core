#!/usr/bin/env bats

load 'helpers/genesis_sandbox'

setup()
{
    setup_genesis_sandbox bmcsetup
    cat >"$fixture/bin/ipmitool" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>/run/fixture/calls
device=0
if [ "$1" = -d ]; then
    device=$2
    shift 2
fi
case "$1 $2" in
    '-V ') echo 'ipmitool version 1.8.19' ;;
    'mc info') cat /run/fixture/mcinfo ;;
    'channel info')
        [ "$3" = "$(cat /run/fixture/channel)" ] || exit 1
        echo 'Channel Medium Type : 802.3'
        ;;
    'lan print')
        counter=/run/fixture/queries.$device
        count=0
        [ ! -f "$counter" ] || count=$(cat "$counter")
        count=$((count + 1))
        echo "$count" >"$counter"
        if [ -f "/run/fixture/lan.$device.$count" ]; then
            cat "/run/fixture/lan.$device.$count"
        else
            cat "/run/fixture/lan.$device"
        fi
        if [ -f /run/fixture/read-error ]; then
            echo 'LAN read returned an error' >&2
            exit 1
        fi
        ;;
    'lan set')
        case "$4" in
            ipsrc|ipaddr|netmask|defgw|vlan)
                counter=/run/fixture/writes.$device.$4
                count=0
                [ ! -f "$counter" ] || count=$(cat "$counter")
                count=$((count + 1))
                echo "$count" >"$counter"
                [ "$count" -gt "$(cat /run/fixture/failures)" ] || exit 1
                ;;
        esac
        ;;
    'lan6 set')
        [ ! -f /run/fixture/lan6-fails ] || exit 1
        ;;
    'lan6 print') cat "/run/fixture/lan6.$device" 2>/dev/null ;;
    'channel getaccess') echo 'Fixed Name : No' ;;
    'user list') cat /run/fixture/users ;;
    'user disable') printf '%s\n' "$3" >>/run/fixture/disabled ;;
    'raw 0xc')
        [ "$3 $4 $5" != '2 1 0xc0' ] || echo '00 01'
        ;;
    'raw 0x3a')
        case "$3" in
            0x50) echo '59 55 4f 4f' ;;
            0xb) echo 0 ;;
        esac
        ;;
    'raw 0x32')
        [ "$3" != 0x72 ] || echo ' 01'
        ;;
esac
exit 0
SH
    cat >"$fixture/bin/getipmi" <<'SH'
#!/bin/sh
counter=/run/fixture/retrievals
count=0
[ ! -f "$counter" ] || count=$(cat "$counter")
count=$((count + 1))
echo "$count" >"$counter"
if [ -f "/run/fixture/ipmicfg.$count.xml" ]; then
    cp "/run/fixture/ipmicfg.$count.xml" /tmp/ipmicfg.xml
else
    cp /run/fixture/ipmicfg.xml /tmp/ipmicfg.xml
fi
SH
    local utility
    for utility in modprobe remoteimmsetup; do
        printf '#!/bin/sh\nexit 0\n' >"$fixture/bin/$utility"
    done
    cat >"$fixture/bin/updateflag.awk" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>/run/fixture/flags
SH
    cat >"$fixture/bin/allowcred.awk" <<'SH'
#!/bin/sh
printf '%s\n' "$XCATMASTER" >>/run/fixture/allowcred
SH
    cat >"$fixture/bin/sleep" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>/run/fixture/sleeps
SH
    cat >"$fixture/bin/logger" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>/run/fixture/messages
SH
    chmod +x "$fixture/bin/"*
    printf '%s\n' 'IPMI Version : 2.0' 'Manufacturer ID : 10876' 'Product ID : 2437' >"$fixture/mcinfo"
    echo 1 >"$fixture/channel"
    echo 0 >"$fixture/failures"
    cat >"$fixture/lan.0" <<'LAN'
IP Address Source       : Static Address
IP Address              : 192.0.2.2
Subnet Mask             : 255.255.255.0
Default Gateway IP      : 192.0.2.1
802.1q VLAN ID           : 42
LAN
    cat >"$fixture/ipmicfg.xml" <<'XML'
<bmcip>192.0.2.2</bmcip>
<taggedvlan>off</taggedvlan>
<gateway>192.0.2.1</gateway>
<netmask>255.255.255.0</netmask>
<username>USERID</username>
<password>test-password</password>
<ipcfgmethod>static</ipcfgmethod>
XML
    cat >"$fixture/users" <<'USERS'
ID  Name             Callin  Link Auth  IPMI Msg   Channel Priv Limit
1                    true    false      false      NO ACCESS
2   USERID           true    true       true       ADMINISTRATOR
3                    true    false      false      NO ACCESS
4   olduser          true    true       true       ADMINISTRATOR
5   viewer           true    true       false      NO ACCESS
USERS
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
