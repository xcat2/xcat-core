#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use IO::Socket::INET;
use POSIX qw(WNOHANG);
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $network_script = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-init files genesis-network-state)
);
my $network_refresh_script = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-init files genesis-network-refresh)
);
my $register_script = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-init files genesis-register)
);
my $status_script = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-init files genesis-status)
);
my $maintenance_shell_script = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-init files genesis-maintenance-shell)
);
my $functions_file = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-init files genesis-functions)
);
my $getdestiny_script = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-scripts usr bin getdestiny)
);
my $nextdestiny_script = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-scripts usr bin nextdestiny)
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
    my ( $script, $environment, @arguments ) = @_;
    local %ENV = ( %ENV, %{$environment} );
    return system( '/bin/bash', $script, @arguments ) >> 8;
}

sub capture_command {
    my ( $environment, @command ) = @_;
    local %ENV = ( %ENV, %{$environment} );
    open( my $fh, '-|', @command ) or die "Unable to run @command: $!";
    my $output = do { local $/; <$fh> };
    close($fh);
    return ( $? >> 8, $output );
}

sub terminate_command {
    my ( $environment, @command ) = @_;
    my $pid = fork();
    die "Unable to fork signal test: $!" unless defined($pid);
    if ( $pid == 0 ) {
        local %ENV = ( %ENV, %{$environment} );
        open( STDOUT, '>', File::Spec->devnull() ) or exit 125;
        open( STDERR, '>', File::Spec->devnull() ) or exit 125;
        exec @command;
        exit 125;
    }

    select( undef, undef, undef, 0.2 );
    kill 'TERM', $pid;
    for ( 1 .. 30 ) {
        my $result = waitpid( $pid, WNOHANG );
        return $? >> 8 if $result == $pid;
        select( undef, undef, undef, 0.1 );
    }
    kill 'KILL', $pid;
    waitpid( $pid, 0 );
    return undef;
}

my $root = tempdir( CLEANUP => 1 );
my $bin = File::Spec->catdir( $root, 'bin' );
my $state_dir = File::Spec->catdir( $root, 'run' );
my $sys_class_net = File::Spec->catdir( $root, 'sys', 'class', 'net' );
my $eth0 = File::Spec->catdir( $sys_class_net, 'eth0' );
my $eth1 = File::Spec->catdir( $sys_class_net, 'eth1' );
my $cmdline = File::Spec->catfile( $root, 'cmdline' );
my $uptime = File::Spec->catfile( $root, 'uptime' );
my $command_log = File::Spec->catfile( $root, 'commands.log' );
my $destiny_response = File::Spec->catfile( $root, 'destiny-response.xml' );
my $destiny_metadata = File::Spec->catfile( $state_dir, 'xcat-response.env' );
my $listener = IO::Socket::INET->new(
    LocalAddr => '127.0.0.1',
    LocalPort => 0,
    Listen    => 2,
    ReuseAddr => 1,
) or die "Unable to open test listener: $!";
my $listener_port = $listener->sockport();
my $listener_pid = fork();
die "Unable to fork test listener: $!" unless defined($listener_pid);
if ( $listener_pid == 0 ) {
    for ( 1 .. 4 ) {
        my $client = $listener->accept() or exit 1;
        close($client);
    }
    exit 0;
}

make_path( $bin, $state_dir, $eth0, $eth1 );
write_file( File::Spec->catfile( $eth0, 'address' ),
    "52:54:00:00:00:35\n" );
write_file( File::Spec->catfile( $eth0, 'operstate' ), "up\n" );
write_file( $uptime, "123.45 456.78\n" );
write_file(
    File::Spec->catfile( $bin, 'logger' ),
    <<'SH', 0755
#!/bin/sh
printf 'logger %s\n' "$*" >>"$XCAT_TEST_LOG"
[ -z "${XCAT_TEST_LOGGER_FAIL-}" ]
SH
);
write_file(
    File::Spec->catfile( $bin, 'ip' ),
    <<'SH', 0755
#!/bin/sh
case "$*" in
    '-4 -o route get '*) printf '%s\n' "$XCAT_TEST_ROUTE" ;;
    '-4 -o address show dev eth0 scope global')
        printf '%s\n' '2: eth0 inet 192.0.2.98/24 scope global eth0'
        ;;
esac
SH
);
write_file(
    File::Spec->catfile( $bin, 'nmcli' ),
    <<'SH', 0755
#!/bin/sh
printf 'nmcli %s\n' "$*" >>"$XCAT_TEST_LOG"
case "$*" in
    '-t -f DEVICE,TYPE device status')
        printf '%s\n' 'eth0:ethernet' 'eth1:ethernet' 'lo:loopback'
        ;;
    '-g GENERAL.CON-UUID device show eth0')
        printf '%s\n' 'connection-eth0'
        ;;
    '-g GENERAL.CON-UUID device show eth1')
        printf '%s\n' 'connection-eth1'
        ;;
    '-g GENERAL.STATE device show '*) printf '%s\n' '100 (connected)' ;;
    '--terse --escape no -g IP4.DNS,IP6.DNS device show eth0')
        printf '%s\n' "${XCAT_TEST_DNS-192.0.2.53 | 2001:db8::53}"
        ;;
    '--wait 30 device connect eth0')
        [ -z "${XCAT_TEST_CONNECT_FAIL-}" ] || exit 1
        ;;
esac
SH
);
write_file(
    File::Spec->catfile( $bin, 'network-state-refresh' ),
    <<'SH', 0755
#!/bin/sh
printf '%s\n' 'network-state-refresh' >>"$XCAT_TEST_LOG"
SH
);
write_file(
    File::Spec->catfile( $bin, 'getdestiny' ),
    <<'SH', 0755
#!/bin/sh
printf 'getdestiny %s\n' "$*" >>"$XCAT_TEST_LOG"
metadata=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --metadata) metadata=$2; shift 2 ;;
        *) shift ;;
    esac
done
if [ -n "$metadata" ]; then
    cat >"$metadata" <<'ENV'
XCAT_NODE_NAME=node042
XCAT_DESTINY=osimage=test-image
XCAT_IMAGE_SERVER=192.0.2.10
XCAT_KERNEL=/tftp/vmlinuz
XCAT_INITRD=/tftp/initrd
XCAT_KERNEL_COMMAND_LINE=console=ttyS0 quiet
ENV
fi
printf '%s\n' "${XCAT_TEST_DESTINY-standby}"
SH
);
write_file(
    File::Spec->catfile( $bin, 'openssl' ),
    <<'SH', 0755
#!/bin/sh
printf 'openssl %s\n' "$*" >>"$XCAT_TEST_LOG"
[ -z "${XCAT_TEST_OPENSSL_DELAY-}" ] \
    || exec sleep "$XCAT_TEST_OPENSSL_DELAY"
cat "$XCAT_TEST_RESPONSE_FILE"
SH
);

my %environment = (
    PATH               => "$bin:$ENV{PATH}",
    XCAT_CMDLINE_FILE  => $cmdline,
    XCAT_STATE_DIR     => $state_dir,
    XCAT_STATUS_COMMAND => $status_script,
    XCAT_STATUS_DIR    => File::Spec->catdir( $state_dir, 'status' ),
    XCAT_SYS_CLASS_NET => $sys_class_net,
    XCAT_TEST_LOG      => $command_log,
    XCAT_TEST_RESPONSE_FILE => $destiny_response,
    XCAT_TEST_ROUTE    => '127.0.0.1 via 192.0.2.1 dev eth0 src 192.0.2.98',
    XCAT_UPTIME_FILE   => $uptime,
    XCAT_GENESIS_FUNCTIONS => $functions_file,
    XCAT_REGISTRATION_ATTEMPTS => 1,
    XCAT_REGISTRATION_RETRY_SECONDS => 0,
    XCAT_REGISTRATION_REQUEST_TIMEOUT => 1,
);

write_file(
    $destiny_response,
    <<'XML'
<xcatresponse>
<node>
<name>node042</name>
<destiny>osimage=test-image</destiny>
<kernel>/tftp/vmlinuz</kernel>
<initrd>/tftp/initrd</initrd>
<kcmdline>console=ttyS0 quiet</kcmdline>
<imgserver>192.0.2.10</imgserver>
</node>
</xcatresponse>
XML
);
my ( $destiny_status, $destiny_output ) = capture_command(
    \%environment,
    '/bin/bash', $getdestiny_script,
    '192.0.2.10:3001', '--once', '--metadata', $destiny_metadata
);
is( $destiny_status, 0, 'getdestiny accepts a complete response' );
is( $destiny_output, "osimage=test-image\n",
    'getdestiny preserves the complete action' );
is(
    read_file($destiny_metadata),
    <<'ENV',
XCAT_NODE_NAME=node042
XCAT_DESTINY=osimage=test-image
XCAT_IMAGE_SERVER=192.0.2.10
XCAT_KERNEL=/tftp/vmlinuz
XCAT_INITRD=/tftp/initrd
XCAT_KERNEL_COMMAND_LINE=console=ttyS0 quiet
ENV
    'getdestiny records the response metadata'
);

write_file( $destiny_response, "<xcatresponse><error>denied</error></xcatresponse>\n" );
( $destiny_status, $destiny_output ) = capture_command(
    \%environment,
    '/bin/bash', $getdestiny_script,
    '192.0.2.10:3001', '--once', '--metadata', $destiny_metadata
);
isnt( $destiny_status, 0, 'getdestiny rejects an error response' );
is( read_file($destiny_metadata), <<'ENV',
XCAT_NODE_NAME=node042
XCAT_DESTINY=osimage=test-image
XCAT_IMAGE_SERVER=192.0.2.10
XCAT_KERNEL=/tftp/vmlinuz
XCAT_INITRD=/tftp/initrd
XCAT_KERNEL_COMMAND_LINE=console=ttyS0 quiet
ENV
    'a failed request preserves prior metadata'
);

write_file(
    $destiny_response,
    <<'XML'
<xcatresponse>
<node>
<name>node042</name>
<destiny>install rocky9.7-x86_64-compute</destiny>
<kernel>/tftp/vmlinuz</kernel>
<initrd>/tftp/initrd</initrd>
<kcmdline>console=ttyS0 quiet</kcmdline>
<imgserver>192.0.2.10</imgserver>
</node>
</xcatresponse>
XML
);
( $destiny_status, $destiny_output ) = capture_command(
    \%environment,
    '/bin/bash', $nextdestiny_script,
    '192.0.2.10:3001', '--once', '--metadata', $destiny_metadata
);
is( $destiny_status, 0, 'nextdestiny accepts a complete response' );
is( $destiny_output, "install rocky9.7-x86_64-compute\n",
    'nextdestiny preserves a legacy action with arguments' );
like( read_file($destiny_metadata),
    qr/^XCAT_DESTINY=install rocky9\.7-x86_64-compute$/m,
    'nextdestiny records the complete action' );

write_file( $destiny_response,
    "<xcatresponse><error>chain unavailable</error></xcatresponse>\n" );
( $destiny_status, $destiny_output ) = capture_command(
    \%environment,
    '/bin/bash', $nextdestiny_script,
    '192.0.2.10:3001', '--once'
);
is( $destiny_status, 0, 'nextdestiny returns a server error as an action' );
is( $destiny_output, "error=chain unavailable\n",
    'nextdestiny preserves legacy error handling' );

write_file( $destiny_response, "<xcatresponse/>\n" );
( $destiny_status, $destiny_output ) = capture_command(
    \%environment,
    '/bin/bash', $nextdestiny_script,
    '192.0.2.10:3001', '--once'
);
isnt( $destiny_status, 0, 'nextdestiny rejects an incomplete response' );

( $destiny_status, $destiny_output ) = capture_command(
    \%environment,
    '/bin/bash', $nextdestiny_script, '192.0.2.10:3001'
);
is( $destiny_status, 0, 'legacy nextdestiny returns an incomplete response' );
is( $destiny_output, "error=No destiny command received\n",
    'legacy nextdestiny leaves retry pacing to doxcat' );

{
    my %signal_environment = (
        %environment,
        XCAT_TEST_OPENSSL_DELAY => 30,
    );
    is(
        terminate_command(
            \%signal_environment,
            '/bin/bash', $getdestiny_script, '192.0.2.10:3001'
        ),
        143,
        'SIGTERM stops getdestiny during a request'
    );
    is(
        terminate_command(
            \%signal_environment,
            '/bin/bash', $nextdestiny_script, '192.0.2.10:3001'
        ),
        143,
        'SIGTERM stops nextdestiny during a request'
    );
}

write_file(
    $cmdline,
    "xcatd=127.0.0.1:$listener_port BOOTIF=01-52-54-00-00-00-35\n"
);
is( run_script( $network_script, \%environment ), 0,
    'network state accepts DHCP boot state' );
is(
    read_file( File::Spec->catfile( $state_dir, 'genesis.env' ) ),
    "XCATDEST=127.0.0.1:$listener_port\n"
      . "XCATMASTER=127.0.0.1\n"
      . "XCATPORT=$listener_port\n"
      . <<'ENV',
XCAT_INTERFACE=eth0
XCAT_SOURCE_ADDRESS=192.0.2.98
XCAT_SOURCE_PREFIXED_ADDRESS=192.0.2.98/24
XCAT_GATEWAY=192.0.2.1
XCAT_DNS_SERVERS=192.0.2.53,2001:db8::53
XCAT_NETWORK_METHOD=auto
XCAT_LINK_STATE=up
XCAT_MAC_ADDRESS=52:54:00:00:00:35
XCAT_VERIFIED_SECONDS=123
ENV
    'network state is written atomically'
);
is(
    read_file(
        File::Spec->catfile( $state_dir, 'status', 'network.env' )
    ),
    <<'ENV',
SCHEMA=1
STATE=READY
DETAIL=Management network ready on eth0
STARTED_SECONDS=123
UPDATED_SECONDS=123
VERIFIED_SECONDS=123
ENV
    'network readiness publishes status'
);
{
    my %failed_logger_environment = (
        %environment,
        XCAT_TEST_LOGGER_FAIL => 1,
    );
    is( run_script( $network_script, \%failed_logger_environment ), 0,
        'network readiness does not depend on logging' );
}

my $safe_network_state = read_file(
    File::Spec->catfile( $state_dir, 'genesis.env' )
);
my $injection_marker = File::Spec->catfile( $root, 'injected' );
my %unsafe_network_environment = (
    %environment,
    XCAT_TEST_DNS => "192.0.2.53;touch$injection_marker",
);
isnt( run_script( $network_script, \%unsafe_network_environment ), 0,
    'unsafe generated network state is rejected' );
is(
    read_file( File::Spec->catfile( $state_dir, 'genesis.env' ) ),
    $safe_network_state,
    'unsafe data does not replace prior network state'
);
ok( !-e $injection_marker, 'generated network data is never evaluated' );
like(
    read_file( File::Spec->catfile( $state_dir, 'status', 'network.env' ) ),
    qr/^CODE=UNSAFE_NETWORK_STATE$/m,
    'unsafe generated state has a specific failure code'
);

write_file( $command_log, '' );
$environment{XCAT_NETWORK_STATE_COMMAND} = File::Spec->catfile(
    $bin, 'network-state-refresh' );
is( run_script( $network_refresh_script, \%environment, 'restart (eth0)' ),
    0, 'discovery refreshes its DHCP identity' );
my $refresh_log = read_file($command_log);
like( $refresh_log, qr/^nmcli --wait 10 device disconnect eth1$/m,
    'forced interface selection disconnects other Ethernet devices' );
like( $refresh_log, qr/^nmcli --wait 10 device disconnect eth0$/m,
    'the discovery interface releases its temporary lease' );
like( $refresh_log, qr/^nmcli --wait 30 device connect eth0$/m,
    'the discovery interface requests its assigned lease' );
like( $refresh_log, qr/^network-state-refresh$/m,
    'network state is rebuilt after DHCP renewal' );

write_file( $command_log, '' );
my %failed_refresh_environment = (
    %environment,
    XCAT_TEST_CONNECT_FAIL => 1,
);
isnt(
    run_script(
        $network_refresh_script, \%failed_refresh_environment,
        'restart (eth0)'
    ),
    0,
    'a failed DHCP renewal returns an error'
);
$refresh_log = read_file($command_log);
like(
    $refresh_log,
    qr/^nmcli --wait 30 connection up uuid connection-eth0 ifname eth0$/m,
    'a failed renewal restores the management connection'
);
like(
    $refresh_log,
    qr/^nmcli --wait 30 connection up uuid connection-eth1 ifname eth1$/m,
    'a failed renewal restores other disconnected connections'
);
unlike( $refresh_log, qr/^network-state-refresh$/m,
    'failed renewal does not publish incomplete network state' );
delete $environment{XCAT_NETWORK_STATE_COMMAND};

write_file(
    $cmdline,
    "xcatd=127.0.0.1:$listener_port BOOTIF=01-52-54-00-00-00-35 "
      . 'hostip=192.0.2.98 netmask=255.255.255.192 '
      . "gateway=192.0.2.1\n"
);
write_file( $command_log, '' );
is( run_script( $network_script, \%environment ), 0,
    'network state accepts static boot settings' );
like( read_file($command_log), qr/ipv4\.addresses 192\.0\.2\.98\/26/,
    'dotted netmask becomes a CIDR prefix' );

write_file(
    $cmdline,
    "xcatd=127.0.0.1:$listener_port BOOTIF=01-52-54-00-00-00-35 "
      . 'hostip=2001:db8::98/64 netmask=64 '
      . "gateway=2001:db8::1\n"
);
write_file( $command_log, '' );
is( run_script( $network_script, \%environment ), 0,
    'network state accepts static IPv6 boot settings' );
like( read_file($command_log),
    qr/ipv4\.method disabled ipv6\.method manual ipv6\.addresses 2001:db8::98\/64 ipv6\.gateway 2001:db8::1/,
    'static IPv6 disables IPv4 and configures the IPv6 route' );

write_file(
    $cmdline,
    "xcatd=127.0.0.1:$listener_port BOOTIF=01-52-54-00-00-00-35 "
      . "hostip=192.0.2.98 netmask=255.255.255.0\n"
);
isnt( run_script( $network_script, \%environment ), 0,
    'partial static settings fail closed' );
like(
    read_file(
        File::Spec->catfile( $state_dir, 'status', 'network.env' )
    ),
    qr/^STATE=FAILED$/m,
    'network failure replaces the prior status'
);
like(
    read_file(
        File::Spec->catfile( $state_dir, 'status', 'network.env' )
    ),
    qr/^CODE=INVALID_STATIC_NETWORK$/m,
    'network failure identifies the rejected configuration'
);

$environment{XCATDEST} = '192.0.2.213:3001';
write_file( $command_log, '' );
write_file( $cmdline, "xcatd=192.0.2.213:3001 destiny=shell\n" );
is( run_script( $register_script, \%environment ), 0,
    'registration accepts a kernel destiny' );
is( read_file( File::Spec->catfile( $state_dir, 'destiny' ) ), "shell\n",
    'kernel destiny remains authoritative' );
like( read_file($command_log), qr/getdestiny 192\.0\.2\.213:3001/,
    'kernel destiny still records xCAT contact' );
like(
    read_file(
        File::Spec->catfile( $state_dir, 'status', 'registration.env' )
    ),
    qr/^STATE=ACTION_RECEIVED$/m,
    'registration records the received action'
);
like(
    read_file(
        File::Spec->catfile( $state_dir, 'status', 'registration.env' )
    ),
    qr/^ACTION=shell\nTARGET=\nNODE_NAME=node042$/m,
    'registration publishes confirmed identity and the selected action'
);
{
    my %failed_logger_environment = (
        %environment,
        XCAT_TEST_LOGGER_FAIL => 1,
    );
    is( run_script( $register_script, \%failed_logger_environment ), 0,
        'successful registration does not depend on logging' );
}

write_file( $command_log, '' );
write_file( $cmdline, "xcatd=192.0.2.213:3001\n" );
is( run_script( $register_script, \%environment ), 0,
    'registration requests a missing destiny' );
is( read_file( File::Spec->catfile( $state_dir, 'destiny' ) ), "standby\n",
    'xCAT supplies a missing destiny' );

$environment{XCAT_TEST_DESTINY} = '';
isnt( run_script( $register_script, \%environment ), 0,
    'registration rejects an empty destiny' );
is( read_file( File::Spec->catfile( $state_dir, 'destiny' ) ), "standby\n",
    'an empty destiny does not replace prior state' );
like(
    read_file(
        File::Spec->catfile( $state_dir, 'status', 'registration.env' )
    ),
    qr/^STATE=FAILED$/m,
    'registration failure replaces the prior status'
);
like(
    read_file(
        File::Spec->catfile( $state_dir, 'status', 'registration.env' )
    ),
    qr/^CODE=XCAT_RESPONSE_UNAVAILABLE\nRECOVERY=/m,
    'registration failure includes a recovery hint'
);

$environment{XCAT_TEST_DESTINY} = 'install rocky9.7-x86_64-compute';
is( run_script( $register_script, \%environment ), 0,
    'registration accepts a legacy action with arguments' );
like(
    read_file(
        File::Spec->catfile( $state_dir, 'status', 'registration.env' )
    ),
    qr/^ACTION=install\nTARGET=rocky9\.7-x86_64-compute$/m,
    'registration separates the action from its argument'
);

{
    local %ENV = ( %ENV, %environment );
    is( system( '/bin/sh', $status_script, 'console', 'DEGRADED',
            "bad\n\tvalue\x01" ) >> 8,
        0, 'status helper accepts a valid record' );
    like(
        read_file(
            File::Spec->catfile( $state_dir, 'status', 'console.env' )
        ),
        qr/^DETAIL=bad  value$/m,
        'status detail is reduced to printable text'
    );
    write_file( $uptime, "130.00 500.00\n" );
    is( system( '/bin/sh', $status_script, 'console', 'DEGRADED',
            'waiting for operator', 'CODE=OPERATOR_WAIT',
            'RECOVERY=Review diagnostics' ) >> 8,
        0, 'status helper accepts structured fields' );
    is(
        read_file(
            File::Spec->catfile( $state_dir, 'status', 'console.env' )
        ),
        <<'ENV',
SCHEMA=1
STATE=DEGRADED
DETAIL=waiting for operator
STARTED_SECONDS=123
UPDATED_SECONDS=130
CODE=OPERATOR_WAIT
RECOVERY=Review diagnostics
ENV
        'status helper preserves the stage start time'
    );
    open( my $saved_stderr, '>&', \*STDERR )
      or die "Unable to duplicate stderr: $!";
    open( STDERR, '>', File::Spec->devnull() )
      or die "Unable to redirect stderr: $!";
    isnt( system( '/bin/sh', $status_script, '../console', 'READY' ) >> 8,
        0, 'status helper rejects an unsafe component' );
    isnt( system( '/bin/sh', $status_script, 'console', 'UNKNOWN' ) >> 8,
        0, 'status helper rejects an unknown state' );
    isnt( system( '/bin/sh', $status_script, 'console', 'READY', '',
            'ATTEMPT=invalid' ) >> 8,
        0, 'status helper rejects invalid numeric fields' );
    open( STDERR, '>&', $saved_stderr )
      or die "Unable to restore stderr: $!";
}

my $component_status_dir = File::Spec->catdir( $state_dir, 'status' );
for my $component (qw(network extensions registration action)) {
    my $state = $component eq 'extensions' ? 'FAILED' :
      $component eq 'action' ? 'IDLE' : 'READY';
    write_file(
        File::Spec->catfile( $component_status_dir, "$component.env" ),
        "STATE=$state\n"
    );
}
my ( $shell_status, $shell_output ) = capture_command(
    \%environment,
    '/bin/bash', '-c',
    'printf "exit\\n" | /bin/bash "$1" 2>&1',
    'genesis-maintenance-shell', $maintenance_shell_script
);
is( $shell_status, 0, 'maintenance shell exits cleanly' );
like(
    $shell_output,
    qr/^Overall state: FAILED$/m,
    'maintenance shell reports an extension failure as the overall state'
);

write_file(
    File::Spec->catfile( $component_status_dir, 'extensions.env' ),
    "STATE=READY\n"
);
( $shell_status, $shell_output ) = capture_command(
    \%environment,
    '/bin/bash', '-c',
    'printf "exit\\n" | /bin/bash "$1" 2>&1',
    'genesis-maintenance-shell', $maintenance_shell_script
);
like(
    $shell_output,
    qr/^Overall state: IDLE$/m,
    'maintenance shell prefers the current action state'
);

waitpid( $listener_pid, 0 );
is( $? >> 8, 0, 'network readiness probes the xCAT port' );

done_testing();
