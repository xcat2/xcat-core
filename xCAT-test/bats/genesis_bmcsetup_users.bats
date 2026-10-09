#!/usr/bin/env bats

load 'helpers/genesis_sandbox'

setup()
{
    setup_genesis_sandbox bmcsetup
    cat >"$fixture/bin/ipmitool" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>/run/fixture/calls
[ "$1" != -d ] || shift 2
case "$1 $2" in
    '-V ') echo 'ipmitool version 1.8.19' ;;
    'mc info')
        printf '%s\n' 'IPMI Version : 2.0' 'Manufacturer ID : 10876' 'Product ID : 2437'
        ;;
    'channel info') echo 'Channel Medium Type : 802.3' ;;
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
    for utility in logger modprobe sleep updateflag.awk remoteimmsetup allowcred.awk; do
        printf '#!/bin/sh\nexit 0\n' >"$fixture/bin/$utility"
    done
    chmod +x "$fixture/bin/"*
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
