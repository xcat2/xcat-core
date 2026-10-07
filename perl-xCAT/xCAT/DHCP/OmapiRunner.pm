package xCAT::DHCP::OmapiRunner;

use strict;
use warnings;

use File::Temp qw(tempfile);
use POSIX qw(WNOHANG);
use Time::HiRes qw(sleep);
use xCAT::Utils;

sub open_command_file {
    my ($class, $directory) = @_;

    $directory ||= $class->_command_directory();
    mkdir $directory unless -d $directory;

    my ($handle, $path) = tempfile('omshell.XXXXXX', DIR => $directory, UNLINK => 0);
    return { handle => $handle, path => $path };
}

sub run_command_file {
    my ( $class, $command_file, $omshell_path, $options ) = @_;
    $options ||= {};

    my $pid = $class->_fork();
    return 'fork_error' unless defined $pid;

    if ( $pid == 0 ) {
        open( STDIN,  '<', $command_file ) or exit 127;    ## no critic (InputOutput::RequireCheckedOpen)
        if ($options->{output_handle}) {
            open( STDOUT, '>&', $options->{output_handle} ) or exit 127;    ## no critic (InputOutput::RequireCheckedOpen)
        } else {
            open( STDOUT, '>', '/dev/null' ) or exit 127;      ## no critic (InputOutput::RequireCheckedOpen)
        }
        open( STDERR, '>', '/dev/null' ) or exit 127;      ## no critic (InputOutput::RequireCheckedOpen)
        exec {$omshell_path} $omshell_path;
        exit 127;
    }

    for ( 1 .. $class->_completion_attempts() ) {
        if ( waitpid( $pid, WNOHANG ) == $pid ) {
            return 'failed' if $options->{require_success} && $?;
            sleep $class->_completion_delay() unless $options->{skip_completion_delay};
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

sub key_algorithm_error {
    my ($class, $settings) = @_;
    return unless $settings->{needs_omshell_key_algorithm};

    my $command = File::Temp->new(TMPDIR => 1);
    my $output = File::Temp->new(TMPDIR => 1);
    # The missing-argument diagnostic proves recognition without connecting or sending a secret.
    print {$command} "key-algorithm\n" or die "Write omshell probe: $!";
    close($command) or die "Close omshell probe: $!";
    my $status = $class->run_command_file(
        $command->filename, $settings->{omshell_path},
        { output_handle => $output, require_success => 1, skip_completion_delay => 1 }
    );
    seek($output, 0, 0) or die "Read omshell probe: $!";
    my $text = do { local $/; <$output> };
    return if $status eq 'completed' && defined($text)
        && $text =~ /(?:^|> )missing or invalid algorithm name\r?\nusage: key-algori(?:th|t)m <algorithm name>/m;

    return "Cannot verify key-algorithm support in $settings->{omshell_path}. "
        . "OMAPI with $settings->{algorithm} requires a compatible omshell. "
        . "Upgrade ISC DHCP or set site.dhcpomshellpath to a compatible binary.";
}

sub _fork {
    return xCAT::Utils->xfork();
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
