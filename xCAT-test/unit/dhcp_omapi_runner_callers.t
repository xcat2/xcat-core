#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use Config;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use IPC::Open3;
use Symbol qw(gensym);
use Test::More;

use XCAT::Test::File qw(repo_path);
use xCAT::DHCP::OmapiRunner;

$ENV{XCATCFG} ||= 'SQLite:/tmp';

my $source_dhcp_plugin = repo_path('xCAT-server/lib/xcat/plugins/dhcp.pm');
require $source_dhcp_plugin;

sub write_file {
    my ( $path, $contents ) = @_;

    open( my $fh, '>', $path ) or die "Unable to create $path: $!";
    print {$fh} $contents or die "Unable to write $path: $!";
    close($fh) or die "Unable to close $path: $!";
}

sub read_file {
    my ($path) = @_;

    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh) or die "Unable to close $path: $!";
    return $contents;
}

my $workspace = tempdir( CLEANUP => 1 );
my $plugin_command_directory = File::Spec->catdir( $workspace, 'plugin-commands' );

{
    my $command = xCAT::DHCP::OmapiRunner->open_command_file($plugin_command_directory);
    my @open_arguments;
    my ( $handle, $writer );

    {
        no warnings qw(once redefine);
        local *xCAT::DHCP::OmapiRunner::open_command_file = sub {
            my ( $class, @arguments ) = @_;
            @open_arguments = @arguments;
            return $command;
        };
        ( $handle, $writer ) = xCAT_plugin::dhcp::_open_omshell_writer(
            { omshell_path => '/usr/bin/omshell' }
        );
    }

    is_deeply( \@open_arguments, [], 'makedhcp uses the runner default command directory' );
    is( fileno($handle), fileno( $command->{handle} ), 'makedhcp returns the runner command handle' );
    is_deeply(
        $writer,
        { command_file => $command->{path}, omshell_path => '/usr/bin/omshell' },
        'makedhcp retains the command path and omshell executable for closing'
    );
    close($handle) or die "Unable to close $command->{path}: $!";
    unlink $command->{path} or die "Unable to remove $command->{path}: $!";
}

foreach my $status (qw(completed terminated killed fork_error)) {
    subtest "makedhcp handles $status" => sub {
        my $command = xCAT::DHCP::OmapiRunner->open_command_file($plugin_command_directory);
        my @logs;
        my @run_arguments;
        my $run_contents;
        my $writer_closed_before_run;

        print { $command->{handle} } "connect\n" or die "Unable to write $command->{path}: $!";

        {
            no warnings qw(once redefine);
            local *xCAT::DHCP::OmapiRunner::run_command_file = sub {
                my ( $class, @arguments ) = @_;
                @run_arguments = @arguments;
                $writer_closed_before_run = !defined fileno( $command->{handle} );
                $run_contents = read_file( $arguments[0] );
                return $status;
            };
            local *xCAT_plugin::dhcp::syslog = sub { push @logs, [@_]; };
            xCAT_plugin::dhcp::_close_omshell_writer(
                $command->{handle},
                { command_file => $command->{path}, omshell_path => '/usr/bin/omshell' }
            );
        }

        is_deeply(
            \@run_arguments,
            [ $command->{path}, '/usr/bin/omshell' ],
            'makedhcp passes the command path and executable in order'
        );
        ok( $writer_closed_before_run, 'makedhcp closes the command file before the runner reads it' );
        is( $run_contents, "connect\n", 'makedhcp flushes the command file before the runner reads it' );
        ok( !-e $command->{path}, 'makedhcp removes the command file after the runner returns' );
        if ( $status eq 'completed' ) {
            is_deeply( \@logs, [], 'makedhcp does not log a completed command' );
        } else {
            is_deeply(
                \@logs,
                [ [ 'local4|err', 'omshell did not complete while updating DHCP reservations' ] ],
                'makedhcp logs a non-completed command once'
            );
        }
    };
}

my $fake_root = File::Spec->catdir( $workspace, 'fake-xcat' );
my $fake_perl = File::Spec->catdir( $fake_root, 'lib', 'perl' );
my $fake_dhcp = File::Spec->catdir( $fake_perl, 'xCAT', 'DHCP' );
my $dhcpop_command_directory = File::Spec->catdir( $workspace, 'dhcpop-commands' );
make_path( $fake_dhcp, $dhcpop_command_directory );

write_file(
    File::Spec->catfile( $fake_dhcp, 'Backend.pm' ),
    <<'MODULE'
package xCAT::DHCP::Backend;
use strict;
use warnings;

sub new_backend {
    return bless {}, __PACKAGE__;
}

sub name {
    return 'isc';
}

1;
MODULE
);

write_file(
    File::Spec->catfile( $fake_dhcp, 'OmapiPolicy.pm' ),
    <<'MODULE'
package xCAT::DHCP::OmapiPolicy;
use strict;
use warnings;

sub settings {
    return { key_name => 'omapi', omshell_path => '/usr/bin/omshell' };
}

sub omshell_preamble {
    return "server 127.0.0.1\n";
}

1;
MODULE
);

write_file(
    File::Spec->catfile( $fake_perl, 'xCAT', 'Table.pm' ),
    <<'MODULE'
package xCAT::Table;
use strict;
use warnings;

sub new {
    my $class = shift;
    return bless {}, $class;
}

sub getAttribs {
    return { password => 'secret' };
}

1;
MODULE
);

write_file(
    File::Spec->catfile( $fake_dhcp, 'OmapiRunner.pm' ),
    <<'MODULE'
package xCAT::DHCP::OmapiRunner;
use strict;
use warnings;

use Errno qw(EAGAIN);
use File::Temp qw(tempfile);

sub open_command_file {
    my ( $class, @arguments ) = @_;
    open( my $arguments, '>', $ENV{OMAPI_TEST_OPEN_ARGUMENTS} ) or die $!;
    print {$arguments} join("\n", @arguments) or die $!;
    close($arguments) or die $!;
    my ( $handle, $path ) = tempfile(
        'omshell.XXXXXX',
        DIR    => $ENV{OMAPI_TEST_COMMAND_DIRECTORY},
        UNLINK => 0,
    );
    open( my $record, '>', $ENV{OMAPI_TEST_PATH_RECORD} ) or die $!;
    print {$record} $path or die $!;
    close($record) or die $!;
    return { handle => $handle, path => $path };
}

sub run_command_file {
    my ( $class, $path, $omshell_path ) = @_;
    open( my $command, '<', $path ) or die $!;
    my $contents = do { local $/; <$command> };
    close($command) or die $!;
    open( my $capture, '>', $ENV{OMAPI_TEST_CAPTURE} ) or die $!;
    print {$capture} $contents or die $!;
    close($capture) or die $!;
    open( my $omshell_capture, '>', $ENV{OMAPI_TEST_OMSHELL_CAPTURE} ) or die $!;
    print {$omshell_capture} $omshell_path or die $!;
    close($omshell_capture) or die $!;
    $! = EAGAIN if $ENV{OMAPI_TEST_STATUS} eq 'fork_error';
    return $ENV{OMAPI_TEST_STATUS};
}

1;
MODULE
);

my $dhcpop = repo_path('xCAT-server/share/xcat/tools/dhcpop');

sub run_dhcpop {
    my ($status) = @_;
    my $capture = File::Spec->catfile( $workspace, "dhcpop-$status-capture" );
    my $open_arguments = File::Spec->catfile( $workspace, "dhcpop-$status-open-arguments" );
    my $omshell_capture = File::Spec->catfile( $workspace, "dhcpop-$status-omshell" );
    my $path_record = File::Spec->catfile( $workspace, "dhcpop-$status-path" );

    local $ENV{XCATROOT} = $fake_root;
    local $ENV{OMAPI_TEST_CAPTURE} = $capture;
    local $ENV{OMAPI_TEST_COMMAND_DIRECTORY} = $dhcpop_command_directory;
    local $ENV{OMAPI_TEST_OPEN_ARGUMENTS} = $open_arguments;
    local $ENV{OMAPI_TEST_OMSHELL_CAPTURE} = $omshell_capture;
    local $ENV{OMAPI_TEST_PATH_RECORD} = $path_record;
    local $ENV{OMAPI_TEST_STATUS} = $status;

    my ( $child_in, $child_out );
    my $child_err = gensym;
    my $pid = open3(
        $child_in,
        $child_out,
        $child_err,
        $Config{perlpath},
        $dhcpop,
        '-r',
        '-n',
        'node01',
    );
    close($child_in);
    my $stdout = do { local $/; <$child_out> } // '';
    my $stderr = do { local $/; <$child_err> } // '';
    waitpid( $pid, 0 );
    my $exit_status = $? >> 8;
    my $command_path = read_file($path_record);

    return {
        command        => read_file($capture),
        command_path   => $command_path,
        exit_status    => $exit_status,
        open_arguments => read_file($open_arguments),
        omshell_path   => read_file($omshell_capture),
        stderr         => $stderr,
        stdout         => $stdout,
    };
}

my $expected_command = <<'COMMAND';
server 127.0.0.1
connect
new host
set name = "node01"
open
remove
close
COMMAND

foreach my $status (qw(completed terminated killed fork_error)) {
    subtest "dhcpop handles $status" => sub {
        my $result = run_dhcpop($status);

        is( $result->{command}, $expected_command, 'dhcpop sends the expected OMAPI commands' );
        is( $result->{open_arguments}, '', 'dhcpop uses the runner default command directory' );
        is( $result->{omshell_path}, '/usr/bin/omshell', 'dhcpop passes the configured executable' );
        is( $result->{stdout}, '', 'dhcpop does not write to stdout' );
        if ( $status eq 'fork_error' ) {
            isnt( $result->{exit_status}, 0, 'dhcpop fails when the runner cannot fork' );
            like( $result->{stderr}, qr/Unable to start omshell:/, 'dhcpop reports the fork failure' );
            ok( -e $result->{command_path}, 'dhcpop preserves its legacy fork-failure cleanup ordering' );
            unlink $result->{command_path} or die "Unable to remove $result->{command_path}: $!";
        } else {
            is( $result->{exit_status}, 0, "dhcpop accepts the $status runner result" );
            is( $result->{stderr}, '', 'dhcpop does not report an accepted runner result' );
            ok( !-e $result->{command_path}, 'dhcpop removes the command file after an accepted result' );
        }
    };
}

done_testing();
