#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $qeth_dir = File::Spec->catdir(
    $repo_root,
    qw(xCAT-genesis-base oe meta-xcat-genesis recipes-connectivity xcat-genesis-qeth)
);
my $qeth_script = File::Spec->catfile( $qeth_dir, qw(files genesis-qeth) );
my $qeth_service = File::Spec->catfile( $qeth_dir, qw(files xcat-genesis-qeth.service) );
my $qeth_recipe = File::Spec->catfile( $qeth_dir, 'xcat-genesis-qeth_1.0.bb' );
my $s390_tools_recipe = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-base oe meta-xcat-genesis recipes-support s390-tools
      s390-tools-znetconf_2.41.0.bb)
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
my $cmdline = File::Spec->catfile( $root, 'cmdline' );
my $configured = File::Spec->catfile( $root, 'configured' );
my $cio_settle = File::Spec->catfile( $root, 'cio_settle' );
my $unconfigured = File::Spec->catfile( $root, 'unconfigured' );
my $command_log = File::Spec->catfile( $root, 'commands.log' );
my $znetconf = File::Spec->catfile( $bin, 'znetconf' );
my $status = File::Spec->catfile( $bin, 'genesis-status' );

make_path($bin);
write_file(
    $znetconf,
    <<'SH', 0755
#!/bin/sh
printf 'znetconf %s\n' "$*" >>"$XCAT_TEST_LOG"
case "$1" in
    -c)
        cat "$XCAT_TEST_CONFIGURED"
        exit "${XCAT_TEST_CONFIGURED_STATUS:-0}"
        ;;
    -u)
        cat "$XCAT_TEST_UNCONFIGURED"
        exit "${XCAT_TEST_UNCONFIGURED_STATUS:-0}"
        ;;
    -a)
        [ "${XCAT_TEST_FAIL_CHANNELS:-}" != "$2" ]
        ;;
esac
SH
);
write_file(
    $status,
    <<'SH', 0755
#!/bin/sh
printf 'status %s\n' "$*" >>"$XCAT_TEST_LOG"
SH
);
write_file(
    File::Spec->catfile( $bin, 'logger' ),
    <<'SH', 0755
#!/bin/sh
printf 'logger %s\n' "$*" >>"$XCAT_TEST_LOG"
SH
);

my %base_environment = (
    PATH                        => "$bin:$ENV{PATH}",
    XCAT_CIO_SETTLE_FILE        => $cio_settle,
    XCAT_CMDLINE_FILE           => $cmdline,
    XCAT_STATUS_COMMAND         => $status,
    XCAT_TEST_CONFIGURED        => $configured,
    XCAT_TEST_LOG               => $command_log,
    XCAT_TEST_UNCONFIGURED      => $unconfigured,
    XCAT_ZNETCONF_COMMAND       => $znetconf,
);

sub run_qeth {
    my ( $command_line, $environment ) = @_;
    write_file( $cmdline, "$command_line\n" );
    write_file( $command_log, '' );
    write_file( $cio_settle, '' );
    write_file( $configured, $environment->{XCAT_TEST_CONFIGURED_OUTPUT} // '' );
    write_file( $unconfigured, $environment->{XCAT_TEST_UNCONFIGURED_OUTPUT} // '' );
    local %ENV = ( %ENV, %base_environment, %{$environment} );
    return system( '/bin/bash', $qeth_script ) >> 8;
}

sub command_log {
    return read_file($command_log);
}

is(
    run_qeth( 'console=ttysclp0 xcatd=192.0.2.1',
        { XCAT_TEST_UNCONFIGURED_STATUS => 31 } ),
    0,
    'a system without ccwgroup devices needs no qeth setup'
);
unlike( command_log(), qr/^znetconf -a /m, 'the no-device path activates nothing' );
is( read_file($cio_settle), "1\n", 'channel discovery waits for pending CIO work' );

is(
    run_qeth(
        'console=ttysclp0 xcatd=192.0.2.1',
        {
            XCAT_TEST_CONFIGURED_OUTPUT =>
              "0.0.0500,0.0.0501,0.0.0502 1731/01 OSA 10 qeth enc500 online\n"
        }
    ),
    0,
    'configured qeth devices need no activation'
);
unlike( command_log(), qr/^znetconf -a /m, 'configured devices are unchanged' );

is(
    run_qeth(
        'rd.znet=qeth,0600,0.0.0601,0.0.0602,portno=1 xcatd=192.0.2.1', {}
    ),
    0,
    'an explicit qeth triplet is accepted'
);
like(
    command_log(),
    qr/^znetconf -a 0\.0\.0600,0\.0\.0601,0\.0\.0602 -d qeth -o portno=1 -o layer2=1$/m,
    'explicit channels are normalized and default to layer 2'
);
like( command_log(), qr/^status network CONFIGURING_NETWORK qeth devices are ready$/m,
    'successful activation is published' );

is(
    run_qeth(
        'rd.znet=qeth,0.0.0600,0.0.0601,0.0.0602 '
          . 'rd.znet=qeth,0.0.0600,0.0.0601,0.0.0602 xcatd=192.0.2.1',
        {}
    ),
    0,
    'a duplicate qeth triplet is accepted once'
);
my @duplicate_activations =
  command_log() =~ /^znetconf -a 0\.0\.0600,0\.0\.0601,0\.0\.0602 /mg;
is( scalar @duplicate_activations, 1, 'duplicate qeth channels are not regrouped' );

is(
    run_qeth(
        'rd.znet=qeth,0.0.0610,0.0.0611,0.0.0612,layer2=0,portname=test '
          . 'xcatd=192.0.2.1',
        {}
    ),
    0,
    'explicit qeth options are accepted'
);
like(
    command_log(),
    qr/^znetconf -a 0\.0\.0610,0\.0\.0611,0\.0\.0612 -d qeth -o layer2=0 -o portname=test$/m,
    'an explicit layer setting is not overridden'
);

my $configured_channels = '0.0.0620,0.0.0621,0.0.0622';
is(
    run_qeth(
        "rd.znet=qeth,$configured_channels xcatd=192.0.2.1",
        { XCAT_TEST_CONFIGURED_OUTPUT => "$configured_channels 1731/01 OSA 10 qeth enc600 online\n" }
    ),
    0,
    'an already configured triplet is left unchanged'
);
unlike( command_log(), qr/^znetconf -a /m, 'configured qeth channels are not regrouped' );

my $automatic_channels = '0.0.0700,0.0.0701,0.0.0702';
is(
    run_qeth(
        'xcatd=192.0.2.1',
        {
            XCAT_TEST_UNCONFIGURED_OUTPUT =>
              "Scanning for network devices...\n"
              . "Device IDs                 Type    Card Type      CHPID Drv.\n"
              . "0.0.0710,0.0.0711          3088/60 LCS OSA         20 lcs\n"
              . "$automatic_channels 1731/01 OSA (QDIO)       10 qeth\n"
        }
    ),
    0,
    'unconfigured qeth devices are discovered'
);
like(
    command_log(),
    qr/^znetconf -a \Q$automatic_channels\E -d qeth -o layer2=1$/m,
    'discovered qeth devices are activated for DHCP'
);
unlike( command_log(), qr/^znetconf -a 0\.0\.0710/m,
    'other channel network types are not activated as qeth' );

is(
    run_qeth( 'xcatd=192.0.2.1', { XCAT_TEST_UNCONFIGURED_STATUS => 9 } ),
    9,
    'a qeth discovery error is returned'
);
like( command_log(), qr/^status network DEGRADED Unable to inspect qeth devices/m,
    'a discovery error is published' );

is(
    run_qeth(
        'rd.znet=ctc,0.0.0800,0.0.0801 xcatd=192.0.2.1',
        { XCAT_TEST_UNCONFIGURED_OUTPUT => "$automatic_channels 1731/01 OSA 10 qeth\n" }
    ),
    0,
    'a non-qeth rd.znet entry is not handled'
);
unlike( command_log(), qr/^znetconf -u$/m, 'explicit non-qeth setup disables qeth discovery' );
unlike( command_log(), qr/^znetconf -a /m, 'non-qeth channels are not activated as qeth' );

is(
    run_qeth( 'rd.znet=qeth,0.0.0900,0.0.0901 xcatd=192.0.2.1', {} ),
    1,
    'an incomplete qeth triplet fails'
);
like( command_log(), qr/^status network DEGRADED One or more qeth devices/m,
    'invalid boot parameters publish a degraded status' );

is(
    run_qeth(
        'rd.znet=qeth,0.0.0910,0.0.0911,0.0.0912,bad?=1 xcatd=192.0.2.1', {}
    ),
    1,
    'an invalid qeth option fails'
);
unlike( command_log(), qr/^znetconf -a /m, 'invalid options are rejected before activation' );

is(
    run_qeth(
        'rd.znet=qeth,0.0.0a00,0.0.0a01,0.0.0a02 '
          . 'rd.znet=qeth,0.0.0b00,0.0.0b01,0.0.0b02 xcatd=192.0.2.1',
        { XCAT_TEST_FAIL_CHANNELS => '0.0.0a00,0.0.0a01,0.0.0a02' }
    ),
    1,
    'failure of one qeth triplet is reported'
);
like( command_log(), qr/^znetconf -a 0\.0\.0b00,0\.0\.0b01,0\.0\.0b02 /m,
    'remaining qeth triplets are still attempted' );

my $service_contents = read_file($qeth_service);
like( $service_contents, qr/^ConditionArchitecture=s390x$/m,
    'the activation service is limited to s390x' );
like( $service_contents, qr/^ConditionKernelCommandLine=xcatd$/m,
    'the activation service requires a Genesis boot' );
like( $service_contents, qr/^Before=.*\bNetworkManager\.service\b/m,
    'qeth activation precedes NetworkManager' );
like( $service_contents, qr/^Before=.*\bxcat-genesis-network-state\.service\b/m,
    'qeth activation precedes management network selection' );
like( $service_contents, qr/^TimeoutStartSec=120$/m,
    'a stalled qeth command cannot block network startup indefinitely' );

ok( -f $qeth_recipe, 'the qeth service has an OpenEmbedded recipe' );
ok( -f $s390_tools_recipe, 'the minimal znetconf package has an OpenEmbedded recipe' );

done_testing();
