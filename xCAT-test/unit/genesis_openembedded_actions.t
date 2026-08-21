#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $action_script = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-init files genesis-action)
);
my $status_script = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-init files genesis-status)
);
my $functions_file = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-init files genesis-functions)
);
my $action_service = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-init files xcat-genesis-action.service)
);
my $init_recipe = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-init xcat-genesis-init_1.0.bb)
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

my $root = tempdir( CLEANUP => 1 );
my $bin = File::Spec->catdir( $root, 'bin' );
my $state_dir = File::Spec->catdir( $root, 'run' );
my $status_dir = File::Spec->catdir( $state_dir, 'status' );
my $approved_dir = File::Spec->catdir( $root, 'actions' );
my $destiny_file = File::Spec->catfile( $state_dir, 'destiny' );
my $metadata_file = File::Spec->catfile( $state_dir, 'xcat-response.env' );
my $network_file = File::Spec->catfile( $state_dir, 'genesis.env' );
my $certificate_file = File::Spec->catfile( $root, 'cert.pem' );
my $uptime_file = File::Spec->catfile( $root, 'uptime' );
my $command_log = File::Spec->catfile( $root, 'commands.log' );
my $getdestiny_queue = File::Spec->catfile( $root, 'getdestiny.queue' );
my $nextdestiny_queue = File::Spec->catfile( $root, 'nextdestiny.queue' );

make_path( $bin, $state_dir, $status_dir, $approved_dir );
write_file( $network_file, <<'ENV' );
XCATDEST=192.0.2.10:3001
XCATMASTER=192.0.2.10
XCATPORT=3001
XCAT_INTERFACE=eth0
XCAT_SOURCE_ADDRESS=192.0.2.98
ENV
write_file( $uptime_file, "42.00 80.00\n" );

write_file( File::Spec->catfile( $bin, 'logger' ), <<'SH', 0755 );
#!/bin/sh
printf 'logger %s\n' "$*" >>"$XCAT_TEST_LOG"
SH
write_file( File::Spec->catfile( $bin, 'getdestiny' ), <<'SH', 0755 );
#!/bin/sh
printf 'getdestiny %s\n' "$*" >>"$XCAT_TEST_LOG"
metadata=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --metadata) metadata=$2; shift 2 ;;
        *) shift ;;
    esac
done
[ -s "$XCAT_TEST_GETDESTINY_QUEUE" ] || exit 1
response=$(head -n 1 "$XCAT_TEST_GETDESTINY_QUEUE")
tail -n +2 "$XCAT_TEST_GETDESTINY_QUEUE" >"$XCAT_TEST_GETDESTINY_QUEUE.new"
mv "$XCAT_TEST_GETDESTINY_QUEUE.new" "$XCAT_TEST_GETDESTINY_QUEUE"
if [ -n "$metadata" ]; then
    printf '%s\n' 'XCAT_NODE_NAME=node042' "XCAT_DESTINY=$response" >"$metadata"
fi
printf '%s\n' "$response"
SH
write_file( File::Spec->catfile( $bin, 'nextdestiny' ), <<'SH', 0755 );
#!/bin/sh
printf 'nextdestiny %s\n' "$*" >>"$XCAT_TEST_LOG"
[ -s "$XCAT_TEST_NEXTDESTINY_QUEUE" ] || exit 1
response=$(head -n 1 "$XCAT_TEST_NEXTDESTINY_QUEUE")
tail -n +2 "$XCAT_TEST_NEXTDESTINY_QUEUE" >"$XCAT_TEST_NEXTDESTINY_QUEUE.new"
mv "$XCAT_TEST_NEXTDESTINY_QUEUE.new" "$XCAT_TEST_NEXTDESTINY_QUEUE"
printf '%s\n' "$response"
SH
write_file( File::Spec->catfile( $bin, 'discover' ), <<'SH', 0755 );
#!/bin/sh
printf '%s\n' discover >>"$XCAT_TEST_LOG"
SH
write_file( File::Spec->catfile( $bin, 'getcert' ), <<'SH', 0755 );
#!/bin/sh
printf '%s\n' getcert >>"$XCAT_TEST_LOG"
: >"$XCAT_TEST_CERTIFICATE_FILE"
SH
write_file( File::Spec->catfile( $bin, 'reboot-control' ), <<'SH', 0755 );
#!/bin/sh
printf 'reboot-control %s\n' "$*" >>"$XCAT_TEST_LOG"
SH
write_file( File::Spec->catfile( $bin, 'poweroff-control' ), <<'SH', 0755 );
#!/bin/sh
printf 'poweroff-control %s\n' "$*" >>"$XCAT_TEST_LOG"
SH
write_file( File::Spec->catfile( $bin, 'ipmitool' ), <<'SH', 0755 );
#!/bin/sh
printf 'ipmitool %s\n' "$*" >>"$XCAT_TEST_LOG"
[ "${XCAT_TEST_IPMI-0}" = 1 ]
SH
write_file( File::Spec->catfile( $approved_dir, 'inventory' ), <<'SH', 0755 );
#!/bin/sh
printf 'inventory' >>"$XCAT_TEST_LOG"
printf ' <%s>' "$@" >>"$XCAT_TEST_LOG"
printf '\n' >>"$XCAT_TEST_LOG"
SH
write_file( File::Spec->catfile( $approved_dir, 'bmcsetup' ), <<'SH', 0755 );
#!/bin/sh
printf '%s\n' bmcsetup >>"$XCAT_TEST_LOG"
SH

my %base_environment = (
    PATH                         => "$bin:$ENV{PATH}",
    XCAT_STATE_DIR               => $state_dir,
    XCAT_STATUS_COMMAND          => $status_script,
    XCAT_STATUS_DIR              => $status_dir,
    XCAT_DESTINY_FILE            => $destiny_file,
    XCAT_METADATA_FILE           => $metadata_file,
    XCAT_NETWORK_FILE            => $network_file,
    XCAT_DISCOVER_COMMAND        => File::Spec->catfile( $bin, 'discover' ),
    XCAT_CERTIFICATE_COMMAND     => File::Spec->catfile( $bin, 'getcert' ),
    XCAT_CERTIFICATE_FILE        => $certificate_file,
    XCAT_GETDESTINY_COMMAND      => File::Spec->catfile( $bin, 'getdestiny' ),
    XCAT_NEXTDESTINY_COMMAND     => File::Spec->catfile( $bin, 'nextdestiny' ),
    XCAT_ACTION_COMMAND_DIR      => $approved_dir,
    XCAT_REBOOT_COMMAND          => File::Spec->catfile( $bin, 'reboot-control' ),
    XCAT_POWEROFF_COMMAND        => File::Spec->catfile( $bin, 'poweroff-control' ),
    XCAT_ACTION_POLL_SECONDS     => 0,
    XCAT_ACTION_REQUEST_TIMEOUT  => 2,
    XCAT_ACTION_OPERATION_TIMEOUT => 2,
    XCAT_ACTION_MAX_STEPS        => 1,
    XCAT_UPTIME_FILE             => $uptime_file,
    XCAT_GENESIS_FUNCTIONS       => $functions_file,
    XCAT_TEST_LOG                => $command_log,
    XCAT_TEST_GETDESTINY_QUEUE   => $getdestiny_queue,
    XCAT_TEST_NEXTDESTINY_QUEUE  => $nextdestiny_queue,
    XCAT_TEST_CERTIFICATE_FILE   => $certificate_file,
);

sub run_action {
    my ( $action, %options ) = @_;

    unlink( $command_log, $certificate_file );
    unlink( File::Spec->catfile( $status_dir, 'action.env' ) );
    write_file( $destiny_file, "$action\n" );
    write_file( $getdestiny_queue,
        $options{getdestiny} // "$action\n" );
    write_file( $nextdestiny_queue,
        $options{nextdestiny} // "standby\n" );
    write_file( $certificate_file, "certificate\n" )
      unless $options{without_certificate};
    local %ENV = ( %ENV, %base_environment,
        XCAT_ACTION_MAX_STEPS => ( $options{maximum_steps} // 1 ),
        XCAT_TEST_IPMI        => ( $options{ipmi} // 0 ) );
    my $status = system( '/bin/bash', $action_script ) >> 8;
    my $log = -r $command_log ? read_file($command_log) : '';
    my $action_status = File::Spec->catfile( $status_dir, 'action.env' );
    my $record = -r $action_status ? read_file($action_status) : '';
    return ( $status, $log, $record );
}

my ( $status, $log, $record ) = run_action(
    'discover', getdestiny => "standby\n" );
is( $status, 0, 'discovery action completes' );
like( $log, qr/^discover$/m, 'discovery action sends inventory' );
like( $log, qr/^getcert$/m, 'discovery action enrolls a certificate' );
ok( index( $log, "discover\n" ) < index( $log, 'getdestiny ' ),
    'registered discovery runs before the next xCAT query' );
like( read_file($destiny_file), qr/^standby$/,
    'discovery loads the assigned node action' );

( $status, $log, $record ) = run_action(
    'shell', getdestiny => "install test-image\n" );
is( $status, 0, 'shell action becomes a managed wait state' );
unlike( $log, qr{(?:^|/)bash(?:\s|$)}, 'shell action does not open a local shell' );
like( read_file($destiny_file), qr/^install test-image$/,
    'wait state accepts a remote action change' );

( $status, $log, $record ) = run_action(
    'standby', getdestiny => "standby\nstandby\n",
    without_certificate => 1, maximum_steps => 2 );
is( $status, 0, 'standby action polls xCAT' );
like( $log, qr/^getcert$/m, 'known nodes obtain a missing certificate' );
like( $record, qr/^STATE=IDLE$/m, 'standby publishes an idle state' );
like( $record, qr/^VERIFIED_SECONDS=42$/m,
    'standby records its latest successful xCAT contact' );

for my $action (qw(osimage ondiscover)) {
    ( $status, $log, $record ) = run_action($action);
    is( $status, 0, "$action action completes" );
    like( $log, qr/^nextdestiny /m, "$action advances the action chain" );
}

( $status, $log, $record ) = run_action(
    'runcmd=inventory storage safe;reboot' );
is( $status, 0, 'approved command completes' );
like( $log, qr/^inventory <storage> <safe;reboot>$/m,
    'approved command arguments are not evaluated by a shell' );
like( $log, qr/^nextdestiny /m, 'approved command advances the chain' );

( $status, $log, $record ) = run_action('runcmd=bmcsetup');
is( $status, 0, 'BMC setup action completes' );
like( $log, qr/^bmcsetup$/m, 'sequential discovery can run BMC setup' );
like( $log, qr/^nextdestiny /m, 'BMC setup advances the action chain' );

( $status, $log, $record ) = run_action('runcmd=unpackaged');
isnt( $status, 0, 'unpackaged command is rejected' );
like( $record, qr/^CODE=ACTION_COMMAND_NOT_APPROVED$/m,
    'unpackaged command has a specific failure code' );

for my $case (
    [ runimage => 'UNSAFE_LEGACY_ACTION' ],
    [ configraid => 'LEGACY_STORAGE_ACTION' ],
    [ sysclone => 'LEGACY_SYSCLONE_ACTION' ],
) {
    ( $status, $log, $record ) = run_action( $case->[0] );
    isnt( $status, 0, "$case->[0] fails closed" );
    like( $record, qr/^CODE=\Q$case->[1]\E$/m,
        "$case->[0] reports its migration status" );
}

for my $action (qw(boot reboot)) {
    ( $status, $log, $record ) = run_action( $action, ipmi => 1 );
    is( $status, 0, "$action action completes" );
    like( $log, qr/^nextdestiny /m, "$action advances the chain" );
    like( $log, qr/^ipmitool chassis bootdev pxe$/m,
        "$action requests a one-time network boot" );
    like( $log, qr/^reboot-control reboot$/m, "$action requests a reboot" );
}

for my $action (qw(install netboot statelite)) {
    ( $status, $log, $record ) = run_action($action);
    is( $status, 0, "$action action completes" );
    unlike( $log, qr/^nextdestiny /m,
        "$action preserves the server-selected chain position" );
    like( $log, qr/^reboot-control reboot$/m, "$action requests a reboot" );
}

( $status, $log, $record ) = run_action('shutdown');
is( $status, 0, 'shutdown action completes' );
like( $log, qr/^poweroff-control poweroff$/m,
    'shutdown action requests a poweroff' );

( $status, $log, $record ) = run_action('error=policy denied');
isnt( $status, 0, 'xCAT error action fails' );
like( $record, qr/^CODE=XCAT_ACTION_ERROR$/m,
    'xCAT error remains visible' );

( $status, $log, $record ) = run_action('unknown');
isnt( $status, 0, 'unknown action fails' );
like( $record, qr/^CODE=XCAT_ACTION_UNSUPPORTED$/m,
    'unknown action has a specific failure code' );

( $status, $log, $record ) = run_action(
    'standby', getdestiny => '', without_certificate => 0 );
is( $status, 0, 'a failed refresh uses the previously received action' );
like( $record, qr/^STATE=DEGRADED$/m,
    'a failed action poll remains visible' );

my $service = read_file($action_service);
like( $service, qr/^Requires=xcat-genesis-register\.service$/m,
    'action execution requires registration' );
unlike( $service, qr/^Restart=/m,
    'a fatal action remains failed for diagnosis' );
unlike( $service, qr/^StartLimitIntervalSec=/m,
    'the action service has no unlimited restart policy' );

my $recipe = read_file($init_recipe);
like( $recipe, qr/\bxcat-genesis-discovery\b/,
    'action runtime includes discovery support' );
like( $recipe, qr/file:\/\/genesis-action/,
    'action executor is packaged' );
like( $recipe, qr/file:\/\/genesis-network-refresh/,
    'discovery network refresh is packaged' );
like( $recipe, qr/\bxcat-genesis-action\.service\b/,
    'action service is enabled' );

done_testing();
