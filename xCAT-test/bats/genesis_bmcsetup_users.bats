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
    'channel getaccess') echo 'Fixed Name : No' ;;
    'user list') cat /run/fixture/users ;;
    'user disable') printf '%s\n' "$3" >>/run/fixture/disabled ;;
esac
exit 0
SH
    cat >"$fixture/bin/getipmi" <<'SH'
#!/bin/sh
cp /run/fixture/ipmicfg.xml /tmp/ipmicfg.xml
SH
    local utility
    for utility in modprobe updateflag.awk remoteimmsetup allowcred.awk; do
        printf '#!/bin/sh\nexit 0\n' >"$fixture/bin/$utility"
    done
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
