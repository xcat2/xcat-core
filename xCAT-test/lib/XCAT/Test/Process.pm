package XCAT::Test::Process;

use strict;
use warnings;

use Capture::Tiny qw(capture_merged);
use Exporter qw(import);

our @EXPORT_OK = qw(run_command);

sub run_command {
    my (@command) = @_;
    die "Command is required\n" unless @command;
    die "run_command must be called in list context\n" unless wantarray;

    my $error;
    my ( $output, $status ) = capture_merged {
        my $result = system { $command[0] } @command;
        $error = "$!" if $result == -1;
        return $result;
    };

    die "Unable to execute @command: $error\n" if $status == -1;
    die "Command @command terminated by signal " . ( $status & 127 ) . "\n"
      if $status & 127;
    return ( $status >> 8, $output );
}

1;
