#!/usr/bin/env bash

load 'helpers/genesis_sandbox'

setup_bmc_fixture()
{
    setup_genesis_sandbox bmcsetup "${1:-}"
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
