#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Slurper qw(read_binary write_binary);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $scriptlib = repo_path(
    File::Spec->catfile(
        'xCAT-server', 'share', 'xcat', 'install', 'scripts', 'scriptlib'
    )
);
-r $scriptlib or die("$scriptlib is required");

is( system( 'bash', '-n', $scriptlib ), 0,
    'the install script library has valid Bash syntax' );

my $tmpdir = tempdir( CLEANUP => 1 );
my $test_bin = File::Spec->catdir( $tmpdir, 'bin' );
my $empty_bin = File::Spec->catdir( $tmpdir, 'empty-bin' );
make_path( $test_bin, $empty_bin );

my $nmcli_log = File::Spec->catfile( $tmpdir, 'nmcli.log' );
my $message_log = File::Spec->catfile( $tmpdir, 'messages.log' );
my $fake_nmcli = File::Spec->catfile( $test_bin, 'nmcli' );
write_binary( $fake_nmcli, <<'SH' );
#!/bin/sh
{
    printf 'nmcli'
    for argument in "$@"; do
        printf '\t<%s>' "$argument"
    done
    printf '\n'
} >>"$XCAT_TEST_NMCLI_LOG"

if [ "$#" -eq 4 ] && [ "$1" = '-g' ] && [ "$2" = 'NAME,STATE' ] &&
    [ "$3" = 'con' ] && [ "$4" = 'show' ]; then
    printf '%s' "$XCAT_TEST_NMCLI_OUTPUT"
fi
SH
chmod 0755, $fake_nmcli or die "Unable to make $fake_nmcli executable: $!";

my $driver = File::Spec->catfile( $tmpdir, 'run-helper' );
write_binary( $driver, <<'SH' );
#!/bin/bash
msgutil_r() {
    {
        printf 'msgutil_r'
        for argument in "$@"; do
            printf '\t<%s>' "$argument"
        done
        printf '\n'
    } >>"$XCAT_TEST_MESSAGE_LOG"
}
. "$XCAT_TEST_SCRIPTLIB"
xcat_enable_active_nm_autoconnect "$@"
SH
chmod 0755, $driver or die "Unable to make $driver executable: $!";

my $connections = join( "\n",
    'primary uplink:activated', 'backup:deactivated',
    'lo:activated',            'storage fabric:activated',
    ':activated',              '' ) . "\n";

is( run_program( $driver, connections => $connections ), 0,
    'the helper updates active non-loopback connections' );
is(
    scalar read_binary($nmcli_log),
    command_line( '-g', 'NAME,STATE', 'con', 'show' )
      . command_line( 'con', 'mod', 'primary uplink',
        'connection.autoconnect', 'yes' )
      . command_line( 'con', 'mod', 'storage fabric',
        'connection.autoconnect', 'yes' ),
    'inactive, loopback, and blank connections are skipped without splitting names'
);
is( scalar read_binary($message_log), '',
    'logging stays disabled when the caller does not request it' );

is(
    run_program(
        $driver,
        arguments   => ['1'],
        connections => "primary uplink:activated\n",
        debug        => '1'
    ),
    0,
    'the helper accepts the legacy logging mode'
);
is(
    scalar read_binary($message_log),
    message_line(
        '192.0.2.10', 'info',
        'set connection primary uplink to be activated on system boot',
        '/var/log/xcat/xcat.log'
    ),
    'debug mode logs the same connection activation message'
);

is(
    run_program(
        $driver,
        arguments   => ['1'],
        connections => "primary uplink:activated\n",
        debug        => '2'
    ),
    0,
    'the helper preserves extended debug logging'
);
is(
    scalar read_binary($message_log),
    message_line(
        '192.0.2.10', 'info',
        'set connection primary uplink to be activated on system boot',
        '/var/log/xcat/xcat.log'
    ),
    'extended debug mode logs the same connection activation message'
);

is(
    run_program(
        $driver,
        arguments   => ['1'],
        connections => "primary uplink:activated\n",
        debug        => '0'
    ),
    0,
    'the legacy logging mode also supports non-debug operation'
);
is( scalar read_binary($message_log), '',
    'non-debug operation does not emit the optional message' );

is(
    run_program(
        $driver,
        arguments   => ['1'],
        connections => "primary uplink:activated\n",
        debug        => '1',
        nmcli        => 0
    ),
    0,
    'the helper is a successful no-op without nmcli'
);
is( scalar read_binary($nmcli_log), '',
    'nmcli is not invoked when it is unavailable' );
is( scalar read_binary($message_log), '',
    'missing nmcli does not produce a connection activation message' );

done_testing();

sub command_line {
    return join( '', 'nmcli', map { "\t<$_>" } @_ ) . "\n";
}

sub message_line {
    return join( '', 'msgutil_r', map { "\t<$_>" } @_ ) . "\n";
}

sub run_program {
    my ( $program, %options ) = @_;
    my $arguments = $options{arguments} // [];
    my $has_nmcli = exists( $options{nmcli} ) ? $options{nmcli} : 1;

    write_binary( $nmcli_log, '' );
    write_binary( $message_log, '' );

    local %ENV = %ENV;
    $ENV{PATH} = $has_nmcli ? "$test_bin:$ENV{PATH}" : $empty_bin;
    $ENV{XCATDEBUGMODE} = $options{debug} // '0';
    $ENV{MASTER_IP} = '192.0.2.10';
    $ENV{XCAT_TEST_MESSAGE_LOG} = $message_log;
    $ENV{XCAT_TEST_NMCLI_LOG} = $nmcli_log;
    $ENV{XCAT_TEST_NMCLI_OUTPUT} = $options{connections} // '';
    $ENV{XCAT_TEST_SCRIPTLIB} = $scriptlib;

    my $status = system( '/bin/bash', $program, @{$arguments} );
    return $status == -1 ? 255 : $status >> 8;
}
