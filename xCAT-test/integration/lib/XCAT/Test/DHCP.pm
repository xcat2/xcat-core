package XCAT::Test::DHCP;

# Process helpers for the integration tests that run a DHCP daemon. They signal only the processes
# that a test started, never a daemon found by name.

use strict;
use warnings;

use Exporter qw(import);
use POSIX qw(WNOHANG _exit setgid setuid);
use Test::More ();
use Time::HiRes qw(sleep);

our @EXPORT_OK = qw(
  start_daemon
  process_running
  stop_daemons
  wait_for_socket
  wait_for_file
  diag_file
);

sub start_daemon {
    my ( $account, $command, $log, @args ) = @_;
    my $pid = fork();
    die "Unable to fork $command: $!" unless defined $pid;
    if ($pid == 0) {
        open(STDOUT, '>', $log) or child_exit("Unable to write $log: $!");
        open(STDERR, '>&', \*STDOUT) or child_exit("Unable to redirect stderr: $!");
        _assume_account($account) if $account;
        {
            no warnings 'exec';
            exec { $command } $command, @args;
            child_exit("Unable to exec $command: $!");
        }
    }
    return $pid;
}

sub _assume_account {
    my ($account) = @_;

    $) = "$account->{gid} $account->{gid}";
    defined( setgid( $account->{gid} ) )
      or child_exit("Unable to set group identity to $account->{gid}: $!");
    my @group_ids = split /\s+/, $);
    $( == $account->{gid} && @group_ids && !grep { $_ != $account->{gid} } @group_ids
      or child_exit("The child did not assume group identity $account->{gid}");
    defined( setuid( $account->{uid} ) )
      or child_exit("Unable to set user identity to $account->{uid}: $!");
    $> == $account->{uid} && $< == $account->{uid}
      or child_exit("The child did not assume user identity $account->{uid}");
}

sub child_exit {
    my ($message) = @_;

    warn "$message\n";
    _exit(127);
}

sub wait_for_socket {
    my ( $pid, $socket_path, $children ) = @_;

    for (1 .. 100) {
        return 0 unless process_running( $pid, $children );
        return 1 if -S $socket_path;
        sleep 0.1;
    }

    return 0;
}

sub wait_for_file {
    my ( $pid, $path, $children ) = @_;

    for (1 .. 100) {
        return 0 unless process_running( $pid, $children );
        return 1 if -f $path;
        sleep 0.1;
    }

    return 0;
}

sub process_running {
    my ( $pid, $children ) = @_;

    my $waited = waitpid( $pid, WNOHANG );
    return 1 if $waited == 0;

    delete $children->{$pid};
    return 0;
}

sub stop_daemons {
    my ($children) = @_;

    my @pids = keys %$children;
    kill 'TERM', @pids if @pids;
    foreach my $pid (@pids) {
        for (1 .. 50) {
            last unless process_running( $pid, $children );
            sleep 0.1;
        }
        next unless exists $children->{$pid};

        kill 'KILL', $pid;
        waitpid( $pid, 0 );
        delete $children->{$pid};
    }

    return;
}

sub diag_file {
    my ($path) = @_;

    return unless -e $path;
    open( my $fh, '<', $path ) or return;
    local $/;
    my $content = <$fh>;
    close($fh) or Test::More::diag("Unable to close $path: $!");
    Test::More::diag($content) if defined($content) && $content ne '';

    return;
}

1;
