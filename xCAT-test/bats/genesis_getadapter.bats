#!/usr/bin/env bats

load 'helpers/genesis_sandbox'

setup()
{
    setup_genesis_sandbox getadapter
    type -P cmp >/dev/null || {
        echo 'Install diffutils to compare adapter requests' >&2
        return 1
    }
    master=''
    openssl_status=0
    openssl_stdout=''
    openssl_stderr=''
    : >"$fixture/pci"
    : >"$fixture/var/lib/dhclient/dhclient.leases"
    cat >"$fixture/expected.xml" <<'XML'
<xcatrequest>
<command>getadapter</command>
<action>update</action>
</xcatrequest>
XML
    cat >"$fixture/bin/lspci" <<'SH'
#!/bin/sh
cat /run/fixture/pci
SH
    cat >"$fixture/bin/udevadm" <<'SH'
#!/bin/sh
cat "/run/fixture/udev-${2##*/}"
SH
    printf '#!/bin/sh\nexit 0\n' >"$fixture/bin/ip"
    cat >"$fixture/bin/openssl" <<'SH'
#!/bin/sh
printf '%s\n' "$@" >/run/fixture/openssl.args
cat >/run/fixture/sent.xml
printf '%s' "$OPENSSL_STDOUT"
printf '%s' "$OPENSSL_STDERR" >&2
exit "$OPENSSL_STATUS"
SH
    chmod +x "$fixture/bin/"*
}

run_getadapter()
{
    run_genesis "$openssl_status" --setenv XCATMASTER "$master" \
        --setenv OPENSSL_STATUS "$openssl_status" \
        --setenv OPENSSL_STDOUT "$openssl_stdout" \
        --setenv OPENSSL_STDERR "$openssl_stderr"
    if [ "$output" != '' ]; then
        printf '%s\n' "$output" >&2
        return 1
    fi
}

assert_file()
{
    run cat "$1"
    [ "$status" -eq 0 ]
    [ "$output" = "$2" ]
}

assert_transmission()
{
    cmp "$fixture/tmp/adapterinfo" "$fixture/sent.xml"
    cmp "$fixture/expected.xml" "$fixture/sent.xml"
    assert_file "$fixture/openssl.args" "$1"
    assert_file "$fixture/tmp/adapterscan.log" "$2"
}

@test 'getadapter reports each missing PCI adapter in scan order' {
    master=192.0.2.1
    mkdir "$fixture/sys/class/net/eth0"
    printf '%s\n' 'aa:bb:cc:dd:ee:ff' >"$fixture/sys/class/net/eth0/address"
    printf '%s\n' 'E: INTERFACE=eth0' \
        'E: DEVPATH=/devices/pci0000:00/0000:01:00.0/net/eth0' >"$fixture/udev-eth0"
    cat >"$fixture/pci" <<'PCI'
01:00.0 Ethernet controller: Existing Ethernet Adapter
02:00.0 Ethernet controller: Mellanox Ethernet Adapter
03:00.0 Network controller: Mellanox Network Adapter
04:00.0 Network controller: Wireless Adapter
05:00.0 Audio device: Example Audio Device
06:00.0 Infiniband controller: Mellanox Technologies MT27800
PCI
    cat >"$fixture/expected.xml" <<'XML'
<xcatrequest>
<command>getadapter</command>
<action>update</action>
<nic>
<interface>eth0</interface>
<pcilocation>/pci0000:00/0000:01:00.0</pcilocation>
<mac>aa:bb:cc:dd:ee:ff</mac>
</nic>
<nic>
<pcilocation>02:00.0</pcilocation>
<model> Mellanox Ethernet Adapter</model>
</nic>
<nic>
<pcilocation>03:00.0</pcilocation>
<model>Mellanox Network Adapter</model>
</nic>
<nic>
<pcilocation>04:00.0</pcilocation>
<model>Wireless Adapter</model>
</nic>
<nic>
<pcilocation>06:00.0</pcilocation>
<model>Mellanox Technologies MT27800</model>
</nic>
</xcatrequest>
XML
    run_getadapter
    assert_transmission 's_client
-connect
192.0.2.1:3001' 'transmit scan result without customer certificate to 192.0.2.1'
}

@test 'getadapter ignores unrelated PCI devices' {
    master=192.0.2.1
    printf '%s\n' '05:00.0 Audio device: Example Audio Device' >"$fixture/pci"
    run_getadapter
    assert_transmission 's_client
-connect
192.0.2.1:3001' 'transmit scan result without customer certificate to 192.0.2.1'
}

@test 'getadapter prefers the master and preserves TLS failure and output' {
    master=198.51.100.10
    printf '%s\n' 'option dhcp-server-identifier 192.0.2.20;' >"$fixture/var/lib/dhclient/dhclient.leases"
    openssl_status=7
    openssl_stdout=$'TLS output\n'
    openssl_stderr=$'TLS error\n'
    run_getadapter
    assert_transmission 's_client
-connect
198.51.100.10:3001' 'transmit scan result without customer certificate to 198.51.100.10
TLS output
TLS error'
}

@test 'getadapter sends both client credentials to the master' {
    master=198.51.100.11
    printf '%s\n' 'option dhcp-server-identifier 192.0.2.21;' >"$fixture/var/lib/dhclient/dhclient.leases"
    touch "$fixture/etc/xcat/cert.pem" "$fixture/etc/xcat/certkey.pem"
    openssl_status=8
    openssl_stdout=$'authenticated TLS output\n'
    openssl_stderr=$'authenticated TLS error\n'
    run_getadapter
    assert_transmission 's_client
-key
/etc/xcat/certkey.pem
-cert
/etc/xcat/cert.pem
-connect
198.51.100.11:3001' 'using /etc/xcat/certkey.pem and /etc/xcat/cert.pem to transmit scan result to 198.51.100.11
authenticated TLS output
authenticated TLS error'
}

@test 'getadapter replaces stale adapter data and appends transmission output' {
    master=198.51.100.14
    printf '%s\n' 'stale adapter data' >"$fixture/tmp/adapterinfo"
    printf '%s\n' 'stale scan log' >"$fixture/tmp/adapterscan.log"
    openssl_stdout=$'replacement TLS output\n'
    run_getadapter
    assert_transmission 's_client
-connect
198.51.100.14:3001' 'rm -f /tmp/adapterinfo
transmit scan result without customer certificate to 198.51.100.14
replacement TLS output'
}

@test 'getadapter uses the latest DHCP server without client credentials' {
    printf '%s\n' 'option dhcp-server-identifier 192.0.2.30;' \
        'option dhcp-server-identifier 198.51.100.30;' >"$fixture/var/lib/dhclient/dhclient.leases"
    openssl_status=9
    run_getadapter
    assert_transmission 's_client
-connect
198.51.100.30:3001' 'transmit scan result without customer certificate to 198.51.100.30'
}

@test 'getadapter sends both client credentials to the DHCP server' {
    printf '%s\n' 'option dhcp-server-identifier 198.51.100.31;' >"$fixture/var/lib/dhclient/dhclient.leases"
    touch "$fixture/etc/xcat/cert.pem" "$fixture/etc/xcat/certkey.pem"
    run_getadapter
    assert_transmission 's_client
-key
/etc/xcat/certkey.pem
-cert
/etc/xcat/cert.pem
-connect
198.51.100.31:3001' 'using /etc/xcat/certkey.pem and /etc/xcat/cert.pem to transmit scan result to 198.51.100.31'
}

@test 'getadapter does not send a certificate without its key' {
    master=198.51.100.12
    touch "$fixture/etc/xcat/cert.pem"
    run_getadapter
    assert_transmission 's_client
-connect
198.51.100.12:3001' 'transmit scan result without customer certificate to 198.51.100.12'
}

@test 'getadapter does not send a key without its certificate' {
    master=198.51.100.13
    touch "$fixture/etc/xcat/certkey.pem"
    run_getadapter
    assert_transmission 's_client
-connect
198.51.100.13:3001' 'transmit scan result without customer certificate to 198.51.100.13'
}

@test 'getadapter keeps the generated request without a transmission target' {
    run_getadapter
    cmp "$fixture/expected.xml" "$fixture/tmp/adapterinfo"
    [ ! -e "$fixture/openssl.args" ]
    [ ! -e "$fixture/sent.xml" ]
    [ ! -e "$fixture/tmp/adapterscan.log" ]
}
