#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path slurp_repo_file);

my $scriptlib = repo_path(
    File::Spec->catfile(
        'xCAT-server', 'share', 'xcat', 'install', 'scripts', 'scriptlib'
    )
);
-r $scriptlib or BAIL_OUT("$scriptlib is required");

is( system( 'bash', '-n', $scriptlib ), 0,
    'the install script library has valid Bash syntax' );

my $tmpdir = tempdir( CLEANUP => 1 );
my $test_bin = File::Spec->catdir( $tmpdir, 'bin' );
my $empty_bin = File::Spec->catdir( $tmpdir, 'empty-bin' );
make_path( $test_bin, $empty_bin );

my $nmcli_log = File::Spec->catfile( $tmpdir, 'nmcli.log' );
my $message_log = File::Spec->catfile( $tmpdir, 'messages.log' );
my $fake_nmcli = File::Spec->catfile( $test_bin, 'nmcli' );
write_file( $fake_nmcli, <<'SH' );
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
write_file( $driver, <<'SH' );
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
    read_file($nmcli_log),
    command_line( '-g', 'NAME,STATE', 'con', 'show' )
      . command_line( 'con', 'mod', 'primary uplink',
        'connection.autoconnect', 'yes' )
      . command_line( 'con', 'mod', 'storage fabric',
        'connection.autoconnect', 'yes' ),
    'inactive, loopback, and blank connections are skipped without splitting names'
);
is( read_file($message_log), '',
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
    read_file($message_log),
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
    read_file($message_log),
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
is( read_file($message_log), '',
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
is( read_file($nmcli_log), '', 'nmcli is not invoked when it is unavailable' );
is( read_file($message_log), '',
    'missing nmcli does not produce a connection activation message' );

my $rhels8 = stage_rendered_postscript('post.rhels8');
my $rhels10 = stage_rendered_postscript('post.rhels10');

is(
    run_program(
        $rhels8,
        connections => "primary uplink:activated\n",
        debug        => '1'
    ),
    0,
    'the EL8 and EL9 install postscript uses the shared helper'
);
is(
    read_file($message_log),
    message_line(
        '192.0.2.10', 'info',
        'set connection primary uplink to be activated on system boot',
        '/var/log/xcat/xcat.log'
    ),
    'the EL8 and EL9 caller preserves connection activation logging'
);
is(
    read_file($nmcli_log),
    command_line( '-g', 'NAME,STATE', 'con', 'show' )
      . command_line( 'con', 'mod', 'primary uplink',
        'connection.autoconnect', 'yes' ),
    'the EL8 and EL9 caller passes the connection name unchanged'
);

is(
    run_program(
        $rhels10,
        connections => "primary uplink:activated\n",
        debug        => '1'
    ),
    0,
    'the EL10 install postscript uses the shared helper'
);
is( read_file($message_log), '',
    'the EL10 caller keeps connection activation logging disabled' );
is(
    read_file($nmcli_log),
    command_line( '-g', 'NAME,STATE', 'con', 'show' )
      . command_line( 'con', 'mod', 'primary uplink',
        'connection.autoconnect', 'yes' ),
    'the EL10 caller passes the connection name unchanged'
);

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

    write_file( $nmcli_log, '' );
    write_file( $message_log, '' );

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

sub stage_rendered_postscript {
    my ($name) = @_;
    my $postscript = slurp_repo_file(
        File::Spec->catfile(
            'xCAT-server', 'share', 'xcat', 'install', 'scripts', $name
        )
    );
    my $library = slurp_repo_file(
        File::Spec->catfile(
            'xCAT-server', 'share', 'xcat', 'install', 'scripts', 'scriptlib'
        )
    );
    my $include = '#INCLUDE:#ENV:XCATROOT#/share/xcat/install/scripts/scriptlib#';
    $postscript =~ s/^\Q$include\E$/$library/m
      or BAIL_OUT("Unable to render the scriptlib include in $name");

    my $preamble = <<'SH';
compgen() { return 1; }
sed() { :; }
msgutil_r() {
    {
        printf 'msgutil_r'
        for argument in "$@"; do
            printf '\t<%s>' "$argument"
        done
        printf '\n'
    } >>"$XCAT_TEST_MESSAGE_LOG"
}
SH
    $postscript =~ s/\A(#![^\n]*\n)/$1$preamble/
      or BAIL_OUT("Unable to stage the test preamble in $name");

    my $destination = File::Spec->catfile( $tmpdir, $name );
    write_file( $destination, $postscript );
    chmod 0755, $destination
      or die "Unable to make $destination executable: $!";
    return $destination;
}

sub write_file {
    my ( $path, $contents ) = @_;
    open( my $fh, '>:raw', $path ) or die "Unable to write $path: $!";
    print {$fh} $contents;
    close($fh) or die "Unable to close $path: $!";
}

sub read_file {
    my ($path) = @_;
    open( my $fh, '<:raw', $path ) or die "Unable to read $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh) or die "Unable to close $path: $!";
    return $contents;
}
