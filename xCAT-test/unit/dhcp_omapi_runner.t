#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Config;
use Errno qw(EAGAIN);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use xCAT::DHCP::OmapiRunner;

{
    package XCAT::Test::FastOmapiRunner;
    use parent 'xCAT::DHCP::OmapiRunner';

    our $COMMAND_DIRECTORY;

    sub _completion_attempts {
        return 1000;
    }

    sub _termination_attempts {
        return 100;
    }

    sub _poll_interval {
        return 0.01;
    }

    sub _completion_delay {
        return 0.01;
    }

    sub _command_directory {
        my $class = shift;
        return $COMMAND_DIRECTORY || $class->SUPER::_command_directory();
    }
}

{
    package XCAT::Test::ReadyOmapiRunner;
    use parent -norequire, 'XCAT::Test::FastOmapiRunner';
    use POSIX qw(WNOHANG);
    use Time::HiRes qw(sleep);

    our $READY_MARKER;
    our $COMPLETION_ATTEMPTS  = 10;
    our $TERMINATION_ATTEMPTS = 1000;

    sub _fork {
        my $pid = fork();
        return $pid unless $pid;

        for ( 1 .. 1000 ) {
            return $pid if $READY_MARKER && -f $READY_MARKER;
            die 'OMAPI test child exited before reaching its ready state'
              if waitpid( $pid, WNOHANG ) == $pid;
            sleep 0.01;
        }

        kill 'KILL', $pid;
        waitpid( $pid, 0 );
        die 'OMAPI test child did not reach its ready state';
    }

    sub _completion_attempts {
        return $COMPLETION_ATTEMPTS;
    }

    sub _termination_attempts {
        return $TERMINATION_ATTEMPTS;
    }
}

{
    package XCAT::Test::ForkErrorOmapiRunner;
    use parent -norequire, 'XCAT::Test::FastOmapiRunner';
    use Errno qw(EAGAIN);

    sub _fork {
        $! = EAGAIN;
        return;
    }
}

{
    package XCAT::Test::InheritedDatabaseHandle;

    sub new {
        my ( $class, $marker ) = @_;
        return bless { marker => $marker }, $class;
    }

    sub DESTROY {
        my ($self) = @_;
        return if $self->{InactiveDestroy};

        open( my $fh, '>', $self->{marker} ) or die "Unable to create $self->{marker}: $!";
        print {$fh} "destroyed\n" or die "Unable to write $self->{marker}: $!";
        close($fh) or die "Unable to close $self->{marker}: $!";
    }
}

sub write_executable {
    my ( $path, $contents ) = @_;

    open( my $fh, '>', $path ) or die "Unable to create $path: $!";
    print {$fh} $contents or die "Unable to write $path: $!";
    close($fh) or die "Unable to close $path: $!";
    chmod 0755, $path or die "Unable to make $path executable: $!";
}

sub write_command_file {
    my ( $directory, $contents ) = @_;

    my $command = XCAT::Test::FastOmapiRunner->open_command_file($directory);
    print { $command->{handle} } $contents or die "Unable to write $command->{path}: $!";
    close( $command->{handle} ) or die "Unable to close $command->{path}: $!";
    return $command->{path};
}

sub cleanup_command_file {
    my ($path) = @_;

    ok( unlink($path), 'the caller can remove the completed command file' );
    ok( !-e $path, 'the command file is gone after caller cleanup' );
}

my $workspace = tempdir( CLEANUP => 1 );
my $command_directory = File::Spec->catdir( $workspace, 'commands' );
my $capture = File::Spec->catfile( $workspace, 'captured-input' );
my $success = File::Spec->catfile( $workspace, 'success' );

is(
    xCAT::DHCP::OmapiRunner->_command_directory(),
    '/tmp/xcat',
    'the production command directory remains /tmp/xcat'
);
is( xCAT::DHCP::OmapiRunner->_completion_attempts(), 100, 'the completion window remains 100 polls' );
is( xCAT::DHCP::OmapiRunner->_termination_attempts(), 20, 'the TERM grace period remains 20 polls' );
is( xCAT::DHCP::OmapiRunner->_poll_interval(), 0.1, 'the process poll interval remains 0.1 seconds' );
is( xCAT::DHCP::OmapiRunner->_completion_delay(), 1.0, 'the post-completion delay remains one second' );

my $default_command;
{
    local $XCAT::Test::FastOmapiRunner::COMMAND_DIRECTORY = $command_directory;
    $default_command = XCAT::Test::FastOmapiRunner->open_command_file();
}
is( ref($default_command), 'HASH', 'the command file is returned as a named record' );
ok( $default_command->{handle}, 'the command record includes its writable handle' );
like(
    $default_command->{path},
    qr{\A\Q$command_directory\E/omshell\.},
    'omitting the directory uses the configured command directory'
);
close( $default_command->{handle} ) or die "Unable to close $default_command->{path}: $!";
unlink $default_command->{path} or die "Unable to remove $default_command->{path}: $!";

write_executable(
    $success,
    <<"SCRIPT"
#!$Config{perlpath}
use strict;
use warnings;
my \$contents = do { local \$/; <STDIN> };
open(my \$fh, '>', \$ENV{OMAPI_TEST_CAPTURE}) or die \$!;
print {\$fh} \$contents or die \$!;
close(\$fh) or die \$!;
print "discarded stdout\n";
warn "discarded stderr\n";
SCRIPT
);

my $command_file = write_command_file( $command_directory, "connect\nclose\n" );
ok( -d $command_directory, 'the command directory is created when absent' );
ok( -f $command_file, 'a persistent command file is created for omshell' );

local $ENV{OMAPI_TEST_CAPTURE} = $capture;
my $parent_stdout = File::Spec->catfile( $workspace, 'parent-stdout' );
my $parent_stderr = File::Spec->catfile( $workspace, 'parent-stderr' );
my $success_status;
{
    open( my $saved_stdout, '>&', \*STDOUT ) or die "Unable to preserve stdout: $!";
    open( my $saved_stderr, '>&', \*STDERR ) or die "Unable to preserve stderr: $!";
    open( STDOUT, '>', $parent_stdout ) or die "Unable to create $parent_stdout: $!";
    open( STDERR, '>', $parent_stderr ) or die "Unable to create $parent_stderr: $!";
    $success_status = XCAT::Test::FastOmapiRunner->run_command_file( $command_file, $success );
    open( STDOUT, '>&', $saved_stdout ) or die "Unable to restore stdout: $!";
    open( STDERR, '>&', $saved_stderr ) or die "Unable to restore stderr: $!";
    close($saved_stdout) or die "Unable to close preserved stdout: $!";
    close($saved_stderr) or die "Unable to close preserved stderr: $!";
}
is( $success_status, 'completed', 'a normally exiting command is reported as completed' );

open( my $capture_fh, '<', $capture ) or die "Unable to read $capture: $!";
my $captured = do { local $/; <$capture_fh> };
close($capture_fh) or die "Unable to close $capture: $!";
is( $captured, "connect\nclose\n", 'the command file is connected to child stdin' );
is( -s $parent_stdout, 0, 'child stdout is redirected away from the caller' );
is( -s $parent_stderr, 0, 'child stderr is redirected away from the caller' );
ok( -e $command_file, 'the runner leaves cleanup timing to its caller' );
cleanup_command_file($command_file);

my $child_database_cleanup = File::Spec->catfile( $workspace, 'child-database-cleanup' );
$command_file = write_command_file( $command_directory, "connect\n" );
{
    local $::XCAT_DBHS = {
        inherited => XCAT::Test::InheritedDatabaseHandle->new($child_database_cleanup),
    };
    is(
        XCAT::Test::FastOmapiRunner->run_command_file(
            $command_file, File::Spec->catfile( $workspace, 'missing-omshell' )
        ),
        'completed',
        'legacy exec failure remains a completed child process'
    );
    ok( !-e $child_database_cleanup, 'exec failure does not destroy an inherited database handle' );
    $::XCAT_DBHS->{inherited}->{InactiveDestroy} = 1;
}
cleanup_command_file($command_file);

$command_file = write_command_file( $command_directory, "connect\n" );
$! = 0;
my $fork_status = XCAT::Test::ForkErrorOmapiRunner->run_command_file( $command_file, $success );
my $fork_errno = 0 + $!;
is( $fork_status, 'fork_error', 'fork failure is reported separately from child completion' );
is( $fork_errno, EAGAIN, 'fork failure leaves the operating-system error available to the caller' );
ok( -e $command_file, 'fork failure preserves caller-owned cleanup ordering' );
cleanup_command_file($command_file);

my $term_marker = File::Spec->catfile( $workspace, 'term-seen' );
my $term_ready = File::Spec->catfile( $workspace, 'term-ready' );
my $term_aware = File::Spec->catfile( $workspace, 'term-aware' );
write_executable(
    $term_aware,
    <<"SCRIPT"
#!$Config{perlpath}
use strict;
use warnings;
\$SIG{TERM} = sub {
    open(my \$fh, '>', \$ENV{OMAPI_TEST_MARKER}) or die \$!;
    print {\$fh} "TERM\n" or die \$!;
    close(\$fh) or die \$!;
    exit 0;
};
open(my \$ready_fh, '>', \$ENV{OMAPI_TEST_READY}) or die \$!;
print {\$ready_fh} "ready\n" or die \$!;
close(\$ready_fh) or die \$!;
do { local \$/; <STDIN> };
while (1) { select undef, undef, undef, 0.1; }
SCRIPT
);

$command_file = write_command_file( $command_directory, "connect\n" );
my $term_status;
{
    local $ENV{OMAPI_TEST_MARKER} = $term_marker;
    local $ENV{OMAPI_TEST_READY} = $term_ready;
    local $XCAT::Test::ReadyOmapiRunner::READY_MARKER = $term_ready;
    $term_status = XCAT::Test::ReadyOmapiRunner->run_command_file( $command_file, $term_aware );
}
is( $term_status, 'terminated', 'a hung command that handles TERM is reported as terminated' );
ok( -f $term_marker, 'the timed-out command receives TERM before any KILL' );
cleanup_command_file($command_file);

my $kill_ready = File::Spec->catfile( $workspace, 'kill-ready' );
my $term_ignoring = File::Spec->catfile( $workspace, 'term-ignoring' );
write_executable(
    $term_ignoring,
    <<"SCRIPT"
#!$Config{perlpath}
use strict;
use warnings;
\$SIG{TERM} = 'IGNORE';
open(my \$fh, '>', \$ENV{OMAPI_TEST_READY}) or die \$!;
print {\$fh} "ready\n" or die \$!;
close(\$fh) or die \$!;
do { local \$/; <STDIN> };
while (1) { select undef, undef, undef, 0.1; }
SCRIPT
);

$command_file = write_command_file( $command_directory, "connect\n" );
my $kill_status;
{
    local $ENV{OMAPI_TEST_READY} = $kill_ready;
    local $XCAT::Test::ReadyOmapiRunner::READY_MARKER = $kill_ready;
    local $XCAT::Test::ReadyOmapiRunner::TERMINATION_ATTEMPTS = 10;
    $kill_status = XCAT::Test::ReadyOmapiRunner->run_command_file( $command_file, $term_ignoring );
}
is( $kill_status, 'killed', 'a hung command that ignores TERM is reported as killed' );
ok( -f $kill_ready, 'the TERM-ignoring command reached its wait state before KILL' );
cleanup_command_file($command_file);

done_testing();
