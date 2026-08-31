package xCAT::DHCP::OmapiRunner;

use strict;
use warnings;

use File::Temp qw(tempfile);
use POSIX qw(WNOHANG);
use Time::HiRes qw(sleep);

sub open_command_file {
    my ($class, $directory) = @_;

    $directory ||= $class->_command_directory();
    mkdir $directory unless -d $directory;

    my ($handle, $path) = tempfile('omshell.XXXXXX', DIR => $directory, UNLINK => 0);
    return { handle => $handle, path => $path };
}

sub run_command_file {
    my ( $class, $command_file, $omshell_path ) = @_;

    my $pid = $class->_fork();
    return 'fork_error' unless defined $pid;

    if ( $pid == 0 ) {
        open( STDIN,  '<', $command_file ) or exit 127;    ## no critic (InputOutput::RequireCheckedOpen)
        open( STDOUT, '>', '/dev/null' ) or exit 127;      ## no critic (InputOutput::RequireCheckedOpen)
        open( STDERR, '>', '/dev/null' ) or exit 127;      ## no critic (InputOutput::RequireCheckedOpen)
        exec {$omshell_path} $omshell_path;
        exit 127;
    }

    for ( 1 .. $class->_completion_attempts() ) {
        if ( waitpid( $pid, WNOHANG ) == $pid ) {
            sleep $class->_completion_delay();
            return 'completed';
        }
        sleep $class->_poll_interval();
    }

    kill 'TERM', $pid;
    for ( 1 .. $class->_termination_attempts() ) {
        return 'terminated' if waitpid( $pid, WNOHANG ) == $pid;
        sleep $class->_poll_interval();
    }

    kill 'KILL', $pid;
    waitpid( $pid, 0 );
    return 'killed';
}

sub _fork {
    return fork();
}

sub _completion_attempts {
    return 100;
}

sub _termination_attempts {
    return 20;
}

sub _poll_interval {
    return 0.1;
}

sub _completion_delay {
    return 1.0;
}

sub _command_directory {
    return '/tmp/xcat';
}

1;
