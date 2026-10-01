#!/usr/bin/env bats
#
# Genesis discovery in the OpenEmbedded image. genesis-discover builds the findme inventory
# from a scratch sysfs, procfs and DMI tree and hands it to a send command; the callbacks
# record the xCAT answers; genesis-getcert enrolls a certificate. ipmitool, lldpcli, lsblk,
# ip, openssl, uname and logger are scratch scripts. genesis-udp-send.c is compiled and sends
# to a local UDP listener.

load 'helpers/shell_source'

DISCOVERY='xCAT-genesis-base/oe/meta-xcat-genesis/recipes-xcat/xcat-genesis-discovery/files'

setup()
{
    DISCOVER="$(require_repo_file "$DISCOVERY/genesis-discover")"
    CALLBACK="$(require_repo_file "$DISCOVERY/genesis-discovery-callback")"
    GETCERT="$(require_repo_file "$DISCOVERY/genesis-getcert")"
    CREDENTIAL_CALLBACK="$(require_repo_file "$DISCOVERY/genesis-credential-callback")"

    root="$BATS_TEST_TMPDIR"
    bin="$root/bin"
    state_dir="$root/run"
    proc="$root/proc"
    dmi="$root/sys/devices/virtual/dmi/id"
    eth0="$root/sys/class/net/eth0"
    packet="$root/packet.xml"
    mkdir -p "$bin" "$state_dir" "$root/keys" "$proc" "$dmi" "$eth0/device" \
        "$root/drivers/virtio_net" "$root/dev"
    ln -s "$root/drivers/virtio_net" "$eth0/device/driver"
    printf '52:54:00:00:00:02\n' >"$eth0/address"
    printf 'PCI_SLOT_NAME=0000:00:03.0\n' >"$eth0/device/uevent"
    printf 'Slot 4\n' >"$eth0/device/physical_slot"
    : >"$root/dev/ipmi0"
    printf 'Acme & Co\n' >"$dmi/sys_vendor"
    printf 'Rack <Node>\n' >"$dmi/product_name"
    printf 'SN-0042\n' >"$dmi/product_serial"
    printf '00112233-4455-6677-8899-aabbccddeeff\n' >"$dmi/product_uuid"
    printf '%s\n' 'processor : 0' 'vendor_id : Test Vendor' \
        'model name : Test CPU & Controller' 'processor : 1' >"$proc/cpuinfo"
    printf 'MemTotal:       2097152 kB\n' >"$proc/meminfo"
    printf '42.00 80.00\n' >"$root/uptime"
    printf '%s\n' XCATDEST=192.0.2.10:3001 XCATMASTER=192.0.2.10 XCATPORT=3001 \
        XCAT_INTERFACE=eth0 XCAT_SOURCE_ADDRESS=192.0.2.98 >"$state_dir/genesis.env"

    printf '#!/bin/sh\n[ -z "${XCAT_TEST_LOGGER_FAIL-}" ]\n' >"$bin/logger"
    printf '#!/bin/sh\n[ "$1" = "-m" ] && printf "%%s\\n" "${XCAT_TEST_ARCH-x86_64}"\n' >"$bin/uname"
    cat >"$bin/ipmitool" <<'SH'
#!/bin/sh
case "$*" in
    'mc info') exit 0 ;;
    'sol info')
        [ -z "${XCAT_TEST_NO_SOL-}" ] || exit 1
        printf '%s\n' 'Payload Channel : 1'
        ;;
    'lan print 1'|'lan print')
        printf '%s\n' 'IP Address Source : Static Address' \
            'IP Address : 192.0.2.101' \
            'MAC Address : 52:54:00:aa:bb:cc'
        ;;
esac
SH
    cat >"$bin/lldpcli" <<'SH'
#!/bin/sh
printf '%s\n' 'lldp.eth0.chassis.name=switch01' \
    'lldp.eth0.chassis.mgmt-ip=192.0.2.2' \
    'lldp.eth0.chassis.descr=Test switch' \
    'lldp.eth0.port.descr=Ethernet1/4'
SH
    cat >"$bin/lsblk" <<'SH'
#!/bin/sh
[ -z "${XCAT_TEST_LSBLK_FAIL-}" ] || exit 1
printf '%s\n' 'vda 21474836480 disk' 'vda1 1073741824 part'
SH
    cat >"$bin/ip" <<'SH'
#!/bin/sh
[ -z "${XCAT_TEST_IP_FAIL-}" ] || exit 1
case "$*" in
    '-4 -o address show dev eth0 scope global')
        [ -z "$XCAT_TEST_IPV4" ] || printf '2: eth0 inet %s scope global eth0\n' "$XCAT_TEST_IPV4"
        ;;
    '-6 -o address show dev eth0 scope global')
        [ -z "$XCAT_TEST_IPV6" ] || printf '2: eth0 inet6 %s scope global eth0\n' "$XCAT_TEST_IPV6"
        ;;
esac
SH
    cat >"$bin/openssl" <<'SH'
#!/bin/sh
printf 'openssl %s\n' "$*" >>"$XCAT_TEST_LOG"
out_file() {
    while [ "$#" -gt 0 ]; do
        if [ "$1" = '-out' ]; then printf '%s\n' "$2"; return; fi
        shift
    done
}
case "$1" in
    genpkey) printf '%s\n' key >"$(out_file "$@")" ;;
    pkey)
        case " $* " in
            *' -pubout '*)
                printf '%s\n' '-----BEGIN PUBLIC KEY-----' 'UFVCS0VZ' '-----END PUBLIC KEY-----'
                ;;
        esac
        ;;
    dgst) printf '%s\n' signature >"$(out_file "$@")" ;;
    base64) printf '%s' U0lH ;;
    req)
        printf '%s\n' '-----BEGIN CERTIFICATE REQUEST-----' 'Q1NS' \
            '-----END CERTIFICATE REQUEST-----' >"$(out_file "$@")"
        ;;
    s_client)
        cat >"$XCAT_TEST_CREDENTIAL_REQUEST"
        cat "$XCAT_TEST_CREDENTIAL_RESPONSE"
        ;;
    x509) exit 0 ;;
esac
SH
    cat >"$bin/send-discovery" <<'SH'
#!/bin/sh
gzip -dc "$1" >"$XCAT_TEST_PACKET"
printf '%s %s\n' "$2" "$3" >>"$XCAT_TEST_LOG"
printf '%s\n' "$XCAT_TEST_RESPONSE" >"$XCAT_DISCOVERY_RESPONSE_FILE"
SH
    printf '#!/bin/sh\nprintf "network-refresh %%s\\n" "$1" >>"$XCAT_TEST_LOG"\n' >"$bin/network-refresh"
    chmod 0755 "$bin"/*

    export PATH="$bin:$PATH"
    export XCAT_DISCOVERY_ATTEMPTS=1
    export XCAT_DISCOVERY_RESPONSE_FILE="$state_dir/discovery-response"
    export XCAT_DISCOVERY_RETRY_SECONDS=1
    export XCAT_DISCOVERY_SEND_COMMAND="$bin/send-discovery"
    export XCAT_KEY_DIR="$root/keys"
    export XCAT_METADATA_FILE="$state_dir/xcat-response.env"
    export XCAT_NETWORK_FILE="$state_dir/genesis.env"
    export XCAT_NETWORK_REFRESH_COMMAND="$bin/network-refresh"
    export XCAT_PROC_ROOT="$proc"
    export XCAT_STATE_DIR="$state_dir"
    export XCAT_STATUS_COMMAND="$(require_repo_file 'xCAT-genesis-base/oe/meta-xcat-genesis/recipes-core/xcat-genesis-init/files/genesis-status')"
    export XCAT_STATUS_DIR="$state_dir/status"
    export XCAT_SYS_ROOT="$root"
    export XCAT_TEST_LOG="$root/commands.log"
    export XCAT_TEST_PACKET="$packet"
    export XCAT_TEST_IPV4=192.0.2.98/24
    export XCAT_TEST_IPV6=
    export XCAT_TEST_CREDENTIAL_REQUEST="$root/credential-request.xml"
    export XCAT_TEST_CREDENTIAL_RESPONSE="$root/credential-response.xml"
    export XCAT_TEST_RESPONSE='restart (eth0)'
    export XCAT_TEST_ARCH=x86_64
    export XCAT_UPTIME_FILE="$root/uptime"
    : >"$XCAT_TEST_LOG"
}

discover()
{
    run /bin/bash "$DISCOVER"
}

# The packet holds a line, or several lines, exactly.
in_packet()
{
    grep -Fqx -- "$1" "$packet" || { printf 'not in packet: %s\n' "$1" >&2; return 1; }
}

not_in_packet()
{
    ! grep -Fq -- "$1" "$packet"
}

@test "discovery sends a findme inventory of the x86_64 node to the selected xCAT endpoint" {
    discover
    [ "$status" -eq 0 ]
    in_packet '<command>findme</command>'
    in_packet '<arch>x86_64</arch>'
    not_in_packet '<nodetype>virtual</nodetype>'
    in_packet '<cpucount>2</cpucount>'
    in_packet '<cputype>Test CPU &amp; Controller</cputype>'
    in_packet '<memory>2048MB</memory>'
    in_packet '<disksize>vda:20GB</disksize>'
    in_packet '<mtm>Acme &amp; Co:Rack &lt;Node&gt;</mtm>'
    in_packet '<mac>virtio_net|eth0|52:54:00:00:00:02|192.0.2.98/24</mac>'
    in_packet '<location>Slot 4</location>'
    in_packet '<switchname>switch01</switchname>'
    in_packet '<switchport>Ethernet1/4</switchport>'
    in_packet '<bmcinband>1</bmcinband>'
    in_packet '<bmc>192.0.2.101</bmc>'
    in_packet '<bmcmac>52:54:00:aa:bb:cc</bmcmac>'
    grep -A2 -x '<sha512sig>' "$packet" | paste -sd' ' | grep -qx '<sha512sig> U0lH </sha512sig>'
    grep -qx '192.0.2.10 3001' "$XCAT_TEST_LOG"
    grep -qx 'network-refresh restart (eth0)' "$XCAT_TEST_LOG"
    grep -qx STATE=READY "$XCAT_STATUS_DIR/discovery.env"
}

@test "successful discovery does not depend on logging" {
    XCAT_TEST_LOGGER_FAIL=1 discover
    [ "$status" -eq 0 ]
}

@test "discovery tolerates devices disappearing during inventory" {
    XCAT_TEST_LSBLK_FAIL=1 XCAT_TEST_IP_FAIL=1 discover
    [ "$status" -eq 0 ]
    not_in_packet '<disksize>'
    in_packet '<mac>virtio_net|eth0|52:54:00:00:00:02|</mac>'
}

@test "discovery accepts a BMC without SOL support, on the default LAN channel" {
    XCAT_TEST_NO_SOL=1 discover
    [ "$status" -eq 0 ]
    in_packet '<bmcmac>52:54:00:aa:bb:cc</bmcmac>'
}

@test "discovery accepts an IPv6-only network and sends to the IPv6 endpoint" {
    printf '%s\n' 'XCATDEST=[2001:db8::10]:3001' XCATMASTER=2001:db8::10 XCATPORT=3001 \
        XCAT_INTERFACE=eth0 XCAT_SOURCE_ADDRESS=2001:db8::98 >"$state_dir/genesis.env"
    XCAT_TEST_IPV4='' XCAT_TEST_IPV6=2001:db8::98/64 discover
    [ "$status" -eq 0 ]
    in_packet '<mac>virtio_net|eth0|52:54:00:00:00:02|2001:db8::98/64</mac>'
    in_packet '<ip6address>2001:db8::98/64</ip6address>'
    not_in_packet '<ip4address>'
    grep -qx '2001:db8::10 3001' "$XCAT_TEST_LOG"
}

@test "an unmatched discovery fails with a specific code, and virtual DMI is reported" {
    printf 'QEMU\n' >"$dmi/sys_vendor"
    XCAT_TEST_RESPONSE=processed discover
    [ "$status" -ne 0 ]
    in_packet '<nodetype>virtual</nodetype>'
    grep -qx CODE=DISCOVERY_NOT_MATCHED "$XCAT_STATUS_DIR/discovery.env"
}

@test "Power discovery reports the device-tree identity" {
    rm "$dmi"/*
    mkdir -p "$proc/device-tree"
    printf 'IBM,9009-42A\0' >"$proc/device-tree/model"
    printf 'IBM,02AB123\0' >"$proc/device-tree/system-id"
    printf 'cpu : POWER9\ncpu : POWER9\nplatform : PowerNV\n' >"$proc/cpuinfo"
    XCAT_TEST_ARCH=ppc64le XCAT_TEST_RESPONSE=restart discover
    [ "$status" -eq 0 ]
    in_packet '<arch>ppc64le</arch>'
    in_packet '<mtm>9009-42A</mtm>'
    in_packet '<serial>02AB123</serial>'
    in_packet '<platform>PowerNV</platform>'
    in_packet '<cpucount>2</cpucount>'
    in_packet '<uuid>9009-42a-02ab123-525400000002</uuid>'
}

@test "s390x discovery reports the closest guest identity from proc sysinfo" {
    rm "$dmi"/*
    printf '%s\n' 'Manufacturer:         IBM' 'Type:                 3931' \
        'Model:                701 A01' 'Sequence Code:        0000000012345' \
        'Plant:                02' 'LPAR Name:            LP4KVM09' \
        'LPAR UUID:            93724168-fda3-429b-8b28-a5d245dcb3ff' \
        'VM00 Name:            GENESIS1' 'VM00 Control Program: KVM/Linux' \
        'VM00 UUID:            82038f2a-1344-aaf7-1a85-2a7250be2076' >"$proc/sysinfo"
    printf '%s\n' 'vendor_id       : IBM/S390' 'processor 0: version = 00' \
        'processor 1: version = 00' >"$proc/cpuinfo"
    XCAT_TEST_ARCH=s390x XCAT_TEST_RESPONSE=restart discover
    [ "$status" -eq 0 ]
    in_packet '<arch>s390x</arch>'
    in_packet '<nodetype>virtual</nodetype>'
    in_packet '<mtm>3931-A01</mtm>'
    not_in_packet '<serial>'
    in_packet '<platform>KVM/Linux</platform>'
    in_packet '<cpucount>2</cpucount>'
    in_packet '<cputype>IBM/S390</cputype>'
    in_packet '<uuid>82038f2a-1344-aaf7-1a85-2a7250be2076</uuid>'
}

@test "a UUID-less s390x guest omits the shared serial and keeps the MAC-based identity" {
    rm "$dmi"/*
    printf '%s\n' 'Manufacturer:         IBM' 'Type:                 3931' \
        'Model:                701 A01' \
        'LPAR UUID:            93724168-fda3-429b-8b28-a5d245dcb3ff' \
        'VM00 Control Program: KVM/Linux' >"$proc/sysinfo"
    printf 'vendor_id       : IBM/S390\n' >"$proc/cpuinfo"
    XCAT_TEST_ARCH=s390x XCAT_TEST_RESPONSE=restart discover
    [ "$status" -eq 0 ]
    not_in_packet '<serial>'
    in_packet '<uuid>3931-a01-unknown-525400000002</uuid>'
}

@test "without a send command, discovery sends through the source-port-aware UDP sender" {
    unset XCAT_DISCOVERY_SEND_COMMAND
    discover
    [[ "$output" == *'/usr/libexec/xcat/genesis-udp-send'* ]]
}

@test "the discovery callback records a restart response and rejects an unknown one" {
    run /bin/bash -c 'printf "%s" "restart (eth0)" | /bin/bash "$1"' callback "$CALLBACK"
    [ "$status" -eq 0 ]
    [ "$(cat "$XCAT_DISCOVERY_RESPONSE_FILE")" = 'restart (eth0)' ]
    run /bin/bash -c 'printf "%s" malformed | /bin/bash "$1"' callback "$CALLBACK"
    [ "$status" -ne 0 ]
}

@test "the certificate client installs only the PEM certificate from a signed x509 request" {
    printf '%s\n' 'XCATDEST=[2001:db8::10]:3001' XCATMASTER=2001:db8::10 XCATPORT=3001 \
        XCAT_INTERFACE=eth0 XCAT_SOURCE_ADDRESS=2001:db8::98 >"$state_dir/genesis.env"
    printf '%s\n' XCAT_NODE_NAME=node042 XCAT_DESTINY=standby >"$XCAT_METADATA_FILE"
    printf '%s\n' '<xcatresponse>' '<data><content>' '-----BEGIN CERTIFICATE-----' 'Q0VSVA==' \
        '-----END CERTIFICATE-----' '</content></data>' '</xcatresponse>' >"$XCAT_TEST_CREDENTIAL_RESPONSE"
    run /bin/bash "$GETCERT"
    [ "$status" -eq 0 ]
    [ "$(cat "$XCAT_KEY_DIR/cert.pem")" = '-----BEGIN CERTIFICATE-----
Q0VSVA==
-----END CERTIFICATE-----' ]
    grep -qx '<command>getcredentials</command>' "$XCAT_TEST_CREDENTIAL_REQUEST"
    grep -qx '<callback_port>300</callback_port>' "$XCAT_TEST_CREDENTIAL_REQUEST"
    grep -A2 -x '<sha512sig>' "$XCAT_TEST_CREDENTIAL_REQUEST" | paste -sd' ' | grep -qx '<sha512sig> U0lH </sha512sig>'
    grep -Fq 'openssl s_client -connect [2001:db8::10]:3001 -quiet' "$XCAT_TEST_LOG"
    grep -qx STATE=READY "$XCAT_STATUS_DIR/credentials.env"
    XCAT_TEST_LOGGER_FAIL=1 run /bin/bash "$GETCERT"
    [ "$status" -eq 0 ]
}

@test "the certificate client rejects an unsafe node name with a specific code" {
    printf '%s\n' XCAT_NODE_NAME=invalid/name >"$XCAT_METADATA_FILE"
    run /bin/bash "$GETCERT"
    [ "$status" -ne 0 ]
    grep -qx CODE=CERTIFICATE_NODE_IDENTITY_MISSING "$XCAT_STATUS_DIR/credentials.env"
}

@test "the credential callback answers the xCAT challenge before xcatd closes the connection" {
    run /bin/bash -c 'printf "%s" "CREDOKBYYOU?" | /bin/bash "$1"' callback "$CREDENTIAL_CALLBACK"
    [ "$status" -eq 0 ]
    coproc CB { /bin/bash "$CREDENTIAL_CALLBACK" 2>/dev/null; }
    printf 'CREDOKBYYOU?\n' >&"${CB[1]}"
    answer=
    IFS= read -t 2 -r answer <&"${CB[0]}" || true
    eval "exec ${CB[1]}>&-"
    wait "$CB_PID" || true
    [ "$answer" = CREDOKBYME ]
    run /bin/bash -c 'printf "%s" unknown | /bin/bash "$1"' callback "$CREDENTIAL_CALLBACK"
    [ "$status" -ne 0 ]
}

# Compile genesis-udp-send.c with the recipe's strict flags, and start a UDP listener on a
# loopback address. The listener writes the sender's source port and the payload it got.
start_udp_sender_test()
{
    local family="$1" address="$2"
    command -v cc >/dev/null || skip 'cc is required'
    [ "$(id -u)" -eq 0 ] || skip 'binding source port 301 needs root'
    cc -std=c17 -Wall -Wextra -Werror -o "$root/genesis-udp-send" \
        "$(require_repo_file "$DISCOVERY/genesis-udp-send.c")"
    perl -MSocket -MIO::Socket::IP -e '
        my $s = IO::Socket::IP->new(LocalHost => $ARGV[0], LocalPort => 0, Proto => "udp")
            or exit 3;
        open(my $p, ">", "$ARGV[1].port") or die; print {$p} $s->sockport, "\n"; close $p;
        $s->recv(my $data, 65535) or die;
        open(my $o, ">", "$ARGV[1].got") or die; print {$o} $s->peerport, " ", $data; close $o;
    ' "$address" "$root/udp-$family" </dev/null >/dev/null 2>&1 3>&- &
    listener=$!
    for _ in $(seq 50); do [ -s "$root/udp-$family.port" ] && break; sleep 0.1; done
    [ -s "$root/udp-$family.port" ] || { wait "$listener"; skip "no $family loopback"; }
}

@test "the UDP sender sends the discovery packet from source port 301 over IPv4" {
    start_udp_sender_test ipv4 127.0.0.1
    printf 'findme' >"$root/packet"
    run "$root/genesis-udp-send" "$root/packet" 127.0.0.1 "$(cat "$root/udp-ipv4.port")"
    [ "$status" -eq 0 ]
    wait "$listener"
    [ "$(cat "$root/udp-ipv4.got")" = '301 findme' ]
}

@test "the UDP sender resolves an IPv6 endpoint and sends from source port 301" {
    start_udp_sender_test ipv6 ::1
    printf 'findme' >"$root/packet"
    run "$root/genesis-udp-send" "$root/packet" ::1 "$(cat "$root/udp-ipv6.port")"
    [ "$status" -eq 0 ]
    wait "$listener"
    [ "$(cat "$root/udp-ipv6.got")" = '301 findme' ]
}
