#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use IO::Select;
use IPC::Open3;
use Symbol qw(gensym);
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $discovery_dir = File::Spec->catdir(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-xcat xcat-genesis-discovery)
);
my $discover_script = File::Spec->catfile(
    $discovery_dir, qw(files genesis-discover)
);
my $callback_script = File::Spec->catfile(
    $discovery_dir, qw(files genesis-discovery-callback)
);
my $getcert_script = File::Spec->catfile(
    $discovery_dir, qw(files genesis-getcert)
);
my $credential_callback_script = File::Spec->catfile(
    $discovery_dir, qw(files genesis-credential-callback)
);
my $udp_sender_source = File::Spec->catfile(
    $discovery_dir, qw(files genesis-udp-send.c)
);
my $status_script = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-init files genesis-status)
);

sub write_file {
    my ( $path, $contents, $mode ) = @_;
    open( my $fh, '>', $path ) or die "Unable to write $path: $!";
    print {$fh} $contents;
    close($fh);
    chmod( $mode, $path ) if defined($mode);
}

sub read_file {
    my ($path) = @_;
    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh);
    return $contents;
}

sub run_script {
    my ( $script, $environment, $input ) = @_;
    local %ENV = ( %ENV, %{$environment} );
    if ( defined($input) ) {
        open( my $pipe, '|-', '/bin/bash', $script )
          or die "Unable to run $script: $!";
        print {$pipe} $input;
        close($pipe);
        return $? >> 8;
    }
    return system( '/bin/bash', $script ) >> 8;
}

sub read_callback_before_eof {
    my ( $script, $environment, $input ) = @_;
    local %ENV = ( %ENV, %{$environment} );
    my ( $child_in, $child_out );
    my $child_err = gensym;
    my $pid = open3( $child_in, $child_out, $child_err,
        '/bin/bash', $script );
    print {$child_in} $input;
    my $ready = IO::Select->new($child_out)->can_read(2);
    my $response = $ready ? <$child_out> : undef;
    close($child_in);
    waitpid( $pid, 0 );
    return $response;
}

my $root = tempdir( CLEANUP => 1 );
my $bin = File::Spec->catdir( $root, 'bin' );
my $state_dir = File::Spec->catdir( $root, 'run' );
my $key_dir = File::Spec->catdir( $root, 'keys' );
my $proc_root = File::Spec->catdir( $root, 'proc' );
my $dmi_dir = File::Spec->catdir(
    $root, qw(sys devices virtual dmi id)
);
my $eth0 = File::Spec->catdir( $root, qw(sys class net eth0) );
my $driver = File::Spec->catdir( $root, qw(drivers virtio_net) );
my $network_file = File::Spec->catfile( $state_dir, 'genesis.env' );
my $response_file = File::Spec->catfile( $state_dir, 'discovery-response' );
my $packet_file = File::Spec->catfile( $root, 'packet.xml' );
my $credential_request = File::Spec->catfile( $root, 'credential-request.xml' );
my $credential_response = File::Spec->catfile( $root, 'credential-response.xml' );
my $metadata_file = File::Spec->catfile( $state_dir, 'xcat-response.env' );
my $command_log = File::Spec->catfile( $root, 'commands.log' );
my $uptime = File::Spec->catfile( $root, 'uptime' );

make_path( $bin, $state_dir, $key_dir, $proc_root, $dmi_dir,
    File::Spec->catdir( $eth0, 'device' ), $driver,
    File::Spec->catdir( $root, 'dev' ) );
symlink( $driver, File::Spec->catfile( $eth0, 'device', 'driver' ) )
  or die "Unable to create driver link: $!";
write_file( File::Spec->catfile( $eth0, 'address' ),
    "52:54:00:00:00:02\n" );
write_file( File::Spec->catfile( $eth0, 'device', 'uevent' ),
    "PCI_SLOT_NAME=0000:00:03.0\n" );
write_file( File::Spec->catfile( $eth0, 'device', 'physical_slot' ),
    "Slot 4\n" );
write_file( File::Spec->catfile( $root, 'dev', 'ipmi0' ), '' );
write_file( File::Spec->catfile( $dmi_dir, 'sys_vendor' ),
    "Acme & Co\n" );
write_file( File::Spec->catfile( $dmi_dir, 'product_name' ),
    "Rack <Node>\n" );
write_file( File::Spec->catfile( $dmi_dir, 'product_serial' ),
    "SN-0042\n" );
write_file( File::Spec->catfile( $dmi_dir, 'product_uuid' ),
    "00112233-4455-6677-8899-aabbccddeeff\n" );
write_file( File::Spec->catfile( $proc_root, 'cpuinfo' ), <<'CPU' );
processor : 0
model name : Test CPU & Controller
processor : 1
CPU
write_file( File::Spec->catfile( $proc_root, 'meminfo' ),
    "MemTotal:       2097152 kB\n" );
write_file( $uptime, "42.00 80.00\n" );
write_file( $network_file, <<'ENV' );
XCATDEST=192.0.2.10:3001
XCATMASTER=192.0.2.10
XCATPORT=3001
XCAT_INTERFACE=eth0
XCAT_SOURCE_ADDRESS=192.0.2.98
ENV

write_file( File::Spec->catfile( $bin, 'logger' ),
    "#!/bin/sh\nexit 0\n", 0755 );
write_file( File::Spec->catfile( $bin, 'uname' ), <<'SH', 0755 );
#!/bin/sh
[ "$1" = "-m" ] && printf '%s\n' "${XCAT_TEST_ARCH-x86_64}"
SH
write_file( File::Spec->catfile( $bin, 'ipmitool' ), <<'SH', 0755 );
#!/bin/sh
case "$*" in
    'mc info') exit 0 ;;
    'sol info') printf '%s\n' 'Payload Channel : 1' ;;
    'lan print 1'|'lan print')
        printf '%s\n' 'IP Address Source : Static Address' \
            'IP Address : 192.0.2.101' \
            'MAC Address : 52:54:00:aa:bb:cc'
        ;;
esac
SH
write_file( File::Spec->catfile( $bin, 'lldpcli' ), <<'SH', 0755 );
#!/bin/sh
printf '%s\n' 'lldp.eth0.chassis.name=switch01' \
    'lldp.eth0.chassis.mgmt-ip=192.0.2.2' \
    'lldp.eth0.chassis.descr=Test switch' \
    'lldp.eth0.port.descr=Ethernet1/4'
SH
write_file( File::Spec->catfile( $bin, 'lsblk' ), <<'SH', 0755 );
#!/bin/sh
printf '%s\n' 'vda 21474836480 disk' 'vda1 1073741824 part'
SH
write_file( File::Spec->catfile( $bin, 'ip' ), <<'SH', 0755 );
#!/bin/sh
case "$*" in
    '-4 -o address show dev eth0 scope global')
        [ -z "$XCAT_TEST_IPV4" ] \
            || printf '2: eth0 inet %s scope global eth0\n' "$XCAT_TEST_IPV4"
        ;;
    '-6 -o address show dev eth0 scope global')
        [ -z "$XCAT_TEST_IPV6" ] \
            || printf '2: eth0 inet6 %s scope global eth0\n' "$XCAT_TEST_IPV6"
        ;;
esac
SH
write_file( File::Spec->catfile( $bin, 'openssl' ), <<'SH', 0755 );
#!/bin/sh
printf 'openssl %s\n' "$*" >>"$XCAT_TEST_LOG"
case "$1" in
    genpkey)
        while [ "$#" -gt 0 ]; do
            if [ "$1" = '-out' ]; then
                printf '%s\n' key >"$2"
                break
            fi
            shift
        done
        ;;
    pkey)
        case " $* " in
            *' -pubout '*)
                printf '%s\n' '-----BEGIN PUBLIC KEY-----' 'UFVCS0VZ' \
                    '-----END PUBLIC KEY-----'
                ;;
        esac
        ;;
    dgst)
        while [ "$#" -gt 0 ]; do
            if [ "$1" = '-out' ]; then
                printf '%s\n' signature >"$2"
                break
            fi
            shift
        done
        ;;
    base64) printf '%s' U0lH ;;
    req)
        while [ "$#" -gt 0 ]; do
            if [ "$1" = '-out' ]; then
                printf '%s\n' '-----BEGIN CERTIFICATE REQUEST-----' 'Q1NS' \
                    '-----END CERTIFICATE REQUEST-----' >"$2"
                break
            fi
            shift
        done
        ;;
    s_client)
        cat >"$XCAT_TEST_CREDENTIAL_REQUEST"
        cat "$XCAT_TEST_CREDENTIAL_RESPONSE"
        ;;
    x509) exit 0 ;;
esac
SH
write_file( File::Spec->catfile( $bin, 'timeout' ), <<'SH', 0755 );
#!/bin/sh
shift
exec "$@"
SH
write_file( File::Spec->catfile( $bin, 'send-discovery' ), <<'SH', 0755 );
#!/bin/sh
gzip -dc "$1" >"$XCAT_TEST_PACKET"
printf '%s %s\n' "$2" "$3" >>"$XCAT_TEST_LOG"
printf '%s\n' "$XCAT_TEST_RESPONSE" >"$XCAT_DISCOVERY_RESPONSE_FILE"
SH
write_file( File::Spec->catfile( $bin, 'network-refresh' ), <<'SH', 0755 );
#!/bin/sh
printf 'network-refresh %s\n' "$1" >>"$XCAT_TEST_LOG"
SH

my %environment = (
    PATH                         => "$bin:$ENV{PATH}",
    XCAT_DISCOVERY_ATTEMPTS      => 1,
    XCAT_DISCOVERY_RESPONSE_FILE => $response_file,
    XCAT_DISCOVERY_RETRY_SECONDS => 1,
    XCAT_DISCOVERY_SEND_COMMAND => File::Spec->catfile( $bin,
        'send-discovery' ),
    XCAT_KEY_DIR        => $key_dir,
    XCAT_METADATA_FILE  => $metadata_file,
    XCAT_NETWORK_FILE   => $network_file,
    XCAT_NETWORK_REFRESH_COMMAND => File::Spec->catfile( $bin,
        'network-refresh' ),
    XCAT_PROC_ROOT      => $proc_root,
    XCAT_STATE_DIR      => $state_dir,
    XCAT_STATUS_COMMAND => $status_script,
    XCAT_STATUS_DIR     => File::Spec->catdir( $state_dir, 'status' ),
    XCAT_SYS_ROOT       => $root,
    XCAT_TEST_LOG       => $command_log,
    XCAT_TEST_PACKET    => $packet_file,
    XCAT_TEST_IPV4      => '192.0.2.98/24',
    XCAT_TEST_IPV6      => '',
    XCAT_TEST_CREDENTIAL_REQUEST  => $credential_request,
    XCAT_TEST_CREDENTIAL_RESPONSE => $credential_response,
    XCAT_TEST_RESPONSE  => 'restart (eth0)',
    XCAT_TEST_ARCH      => 'x86_64',
    XCAT_UPTIME_FILE    => $uptime,
);

is( run_script( $discover_script, \%environment ), 0,
    'discovery accepts an xCAT node match' );
my $packet = read_file($packet_file);
like( $packet, qr{<command>findme</command>},
    'discovery sends a findme request' );
like( $packet, qr{<arch>x86_64</arch>},
    'discovery sends the canonical architecture' );
unlike( $packet, qr{<nodetype>virtual</nodetype>},
    'physical DMI does not claim a virtual node' );
like( $packet, qr{<cpucount>2</cpucount>},
    'discovery reports the processor count' );
like( $packet, qr{<cputype>Test CPU &amp; Controller</cputype>},
    'discovery escapes inventory text' );
like( $packet, qr{<memory>2048MB</memory>},
    'discovery reports memory' );
like( $packet, qr{<disksize>vda:20GB</disksize>},
    'discovery reports disk capacity' );
like( $packet,
    qr{<mtm>Acme &amp; Co:Rack &lt;Node&gt;</mtm>},
    'discovery escapes system identity' );
like( $packet,
    qr{<mac>virtio_net\|eth0\|52:54:00:00:00:02\|192\.0\.2\.98/24</mac>},
    'discovery reports the management NIC' );
like( $packet, qr{<location>Slot 4</location>},
    'discovery reports the NIC location' );
like( $packet, qr{<switchname>switch01</switchname>},
    'discovery reports the LLDP neighbor' );
like( $packet, qr{<switchport>Ethernet1/4</switchport>},
    'discovery reports the LLDP port' );
like( $packet, qr{<bmcinband>1</bmcinband>},
    'discovery reports in-band BMC access' );
like( $packet, qr{<bmc>192\.0\.2\.101</bmc>},
    'discovery reports a static BMC address' );
like( $packet, qr{<bmcmac>52:54:00:aa:bb:cc</bmcmac>},
    'discovery reports the BMC MAC address' );
like( $packet, qr{<sha512sig>\nU0lH\n</sha512sig>},
    'discovery signs the inventory' );
is( read_file($command_log) =~ /192\.0\.2\.10 3001/ ? 1 : 0, 1,
    'discovery sends to the selected xCAT endpoint' );
like( read_file($command_log), qr/^network-refresh restart \(eth0\)$/m,
    'discovery applies the assigned network identity' );
like(
    read_file(
        File::Spec->catfile( $state_dir, 'status', 'discovery.env' )
    ),
    qr/^STATE=READY$/m,
    'discovery publishes completion'
);

write_file( $network_file, <<'ENV' );
XCATDEST=[2001:db8::10]:3001
XCATMASTER=2001:db8::10
XCATPORT=3001
XCAT_INTERFACE=eth0
XCAT_SOURCE_ADDRESS=2001:db8::98
ENV
$environment{XCAT_TEST_IPV4} = '';
$environment{XCAT_TEST_IPV6} = '2001:db8::98/64';
is( run_script( $discover_script, \%environment ), 0,
    'discovery accepts an IPv6-only network' );
$packet = read_file($packet_file);
like( $packet,
    qr{<mac>virtio_net\|eth0\|52:54:00:00:00:02\|2001:db8::98/64</mac>},
    'IPv6 supplies the legacy management NIC address' );
like( $packet, qr{<ip6address>2001:db8::98/64</ip6address>},
    'discovery reports the IPv6 interface address' );
unlike( $packet, qr{<ip4address>},
    'an IPv6-only interface does not claim an IPv4 address' );
like( read_file($command_log), qr/^2001:db8::10 3001$/m,
    'discovery sends to the IPv6 xCAT endpoint' );
$environment{XCAT_TEST_IPV4} = '192.0.2.98/24';
$environment{XCAT_TEST_IPV6} = '';

write_file( File::Spec->catfile( $dmi_dir, 'sys_vendor' ), "QEMU\n" );
$environment{XCAT_TEST_RESPONSE} = 'processed';
isnt( run_script( $discover_script, \%environment ), 0,
    'an unmatched discovery request fails' );
like( read_file($packet_file), qr{<nodetype>virtual</nodetype>},
    'virtual DMI is reported to xCAT' );
like(
    read_file(
        File::Spec->catfile( $state_dir, 'status', 'discovery.env' )
    ),
    qr/^CODE=DISCOVERY_NOT_MATCHED$/m,
    'an unmatched node has a specific failure code'
);

unlink(
    File::Spec->catfile( $dmi_dir, 'sys_vendor' ),
    File::Spec->catfile( $dmi_dir, 'product_name' ),
    File::Spec->catfile( $dmi_dir, 'product_serial' ),
    File::Spec->catfile( $dmi_dir, 'product_uuid' ),
);
my $device_tree = File::Spec->catdir( $proc_root, 'device-tree' );
make_path($device_tree);
write_file( File::Spec->catfile( $device_tree, 'model' ),
    "IBM,9009-42A\0" );
write_file( File::Spec->catfile( $device_tree, 'system-id' ),
    "IBM,02AB123\0" );
write_file( File::Spec->catfile( $proc_root, 'cpuinfo' ),
    "cpu : POWER9\ncpu : POWER9\nplatform : PowerNV\n" );
$environment{XCAT_TEST_ARCH} = 'ppc64le';
$environment{XCAT_TEST_RESPONSE} = 'restart';
is( run_script( $discover_script, \%environment ), 0,
    'Power discovery accepts device-tree identity' );
$packet = read_file($packet_file);
like( $packet, qr{<arch>ppc64le</arch>},
    'Power discovery keeps the canonical architecture' );
like( $packet, qr{<mtm>9009-42A</mtm>},
    'Power discovery reports the machine type' );
like( $packet, qr{<serial>02AB123</serial>},
    'Power discovery reports the system serial' );
like( $packet, qr{<platform>PowerNV</platform>},
    'Power discovery reports the firmware platform' );
like( $packet, qr{<cpucount>2</cpucount>},
    'Power discovery counts processor records' );
like( $packet,
    qr{<uuid>9009-42a-02ab123-525400000002</uuid>},
    'Power discovery creates a stable fallback UUID' );

unlink($response_file);
is( run_script( $callback_script, \%environment, "restart (eth0)" ), 0,
    'callback accepts a restart response' );
is( read_file($response_file), "restart (eth0)\n",
    'callback records the requested interface' );
isnt( run_script( $callback_script, \%environment, "malformed" ), 0,
    'callback rejects an unknown response' );

write_file( $metadata_file, <<'ENV' );
XCAT_NODE_NAME=node042
XCAT_DESTINY=standby
ENV
write_file( $credential_response, <<'XML' );
<xcatresponse>
<data><content>
-----BEGIN CERTIFICATE-----
Q0VSVA==
-----END CERTIFICATE-----
</content></data>
</xcatresponse>
XML
is( run_script( $getcert_script, \%environment ), 0,
    'certificate client installs an xCAT certificate' );
is( read_file( File::Spec->catfile( $key_dir, 'cert.pem' ) ), <<'PEM',
-----BEGIN CERTIFICATE-----
Q0VSVA==
-----END CERTIFICATE-----
PEM
    'certificate client stores only the PEM certificate'
);
my $certificate_request = read_file($credential_request);
like( $certificate_request, qr{<command>getcredentials</command>},
    'certificate client requests x509 credentials' );
like( $certificate_request, qr{<callback_port>300</callback_port>},
    'certificate client declares the privileged callback port' );
like( $certificate_request, qr{<sha512sig>\nU0lH\n</sha512sig>},
    'certificate request is signed by the discovery identity' );
like( read_file($command_log),
    qr{openssl s_client -connect \[2001:db8::10\]:3001 -quiet},
    'certificate client keeps the bracketed IPv6 endpoint' );
like(
    read_file(
        File::Spec->catfile( $state_dir, 'status', 'credentials.env' )
    ),
    qr/^STATE=READY$/m,
    'certificate client publishes completion'
);

write_file( $metadata_file, "XCAT_NODE_NAME=invalid/name\n" );
isnt( run_script( $getcert_script, \%environment ), 0,
    'certificate client rejects an unsafe node name' );
like(
    read_file(
        File::Spec->catfile( $state_dir, 'status', 'credentials.env' )
    ),
    qr/^CODE=CERTIFICATE_NODE_IDENTITY_MISSING$/m,
    'missing confirmed identity has a specific failure code'
);

is( run_script( $credential_callback_script, \%environment,
        "CREDOKBYYOU?" ),
    0, 'credential callback accepts the xCAT challenge' );
is(
    read_callback_before_eof(
        $credential_callback_script, \%environment, "CREDOKBYYOU?\n"
    ),
    "CREDOKBYME\n",
    'credential callback answers before xcatd closes the connection'
);
isnt( run_script( $credential_callback_script, \%environment, "unknown" ), 0,
    'credential callback rejects an unknown challenge' );

my $recipe = read_file(
    File::Spec->catfile( $discovery_dir, 'xcat-genesis-discovery_1.0.bb' )
);
like( $recipe, qr/^RDEPENDS:\$\{PN\} = "bash coreutils gzip iproute2 openssl-bin util-linux-lsblk"$/m,
    'discovery dependencies are explicit' );
like( $recipe, qr/xcat-genesis-discovery\.socket/,
    'discovery callback socket is packaged' );
like( $recipe, qr/xcat-genesis-credential\.socket/,
    'credential callback socket is packaged' );
like( $recipe, qr/\$\{CC\}.*genesis-udp-send\.c/s,
    'discovery UDP sender is compiled for the target' );
like( $recipe, qr/-std=c17.*-Werror/s,
    'discovery UDP sender uses the strict C build contract' );
like( $recipe, qr{\$\{libexecdir\}/xcat/genesis-udp-send},
    'discovery UDP sender is packaged' );

my $udp_sender = read_file($udp_sender_source);
like( $udp_sender, qr/^\s*SOURCE_PORT = 301,$/m,
    'discovery sender uses the legacy privileged source port' );
like( $udp_sender, qr/^\s*hints\.ai_family = AF_UNSPEC;$/m,
    'discovery sender resolves both address families' );
like( $udp_sender, qr/source4->sin_port = htons\(SOURCE_PORT\)/,
    'discovery sender binds the IPv4 source port' );
like( $udp_sender, qr/source6->sin6_port = htons\(SOURCE_PORT\)/,
    'discovery sender binds the IPv6 source port' );
like( read_file($discover_script), qr{/usr/libexec/xcat/genesis-udp-send},
    'discovery uses the source-port-aware UDP sender' );

my $image = read_file(
    File::Spec->catfile(
        $repo_root,
        qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core images xcat-genesis-image.bb)
    )
);
like( $image, qr/\bxcat-genesis-discovery\b/,
    'base image includes the discovery client' );

done_testing();
