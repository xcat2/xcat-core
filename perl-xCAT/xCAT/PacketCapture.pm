package xCAT::PacketCapture;

use strict;
use warnings;

use File::Temp qw(tempfile);
use POSIX qw(_exit sigprocmask WNOHANG SIG_BLOCK SIG_SETMASK SIGINT SIGTERM);

sub start {
    my ($class, $tcpdump, $interface, $on_reap) = @_;
    my ($handle, $file) = tempfile('detect_dhcpd.XXXXXX', TMPDIR => 1, UNLINK => 1);
    close($handle);
    my $self = bless {
        file => $file,
        on_reap => $on_reap,
        stop_signals => POSIX::SigSet->new(SIGINT, SIGTERM),
        signal_mask => POSIX::SigSet->new(),
    }, $class;

    # Keep INT and TERM blocked until the parent can stop its child.
    sigprocmask(SIG_BLOCK, $self->{stop_signals}, $self->{signal_mask});
    my $pid = fork;
    unless (defined $pid) {
        sigprocmask(SIG_SETMASK, $self->{signal_mask});
        return;
    }
    if ($pid == 0) {
        sigprocmask(SIG_SETMASK, $self->{signal_mask});
        open(STDOUT, '>', $file) or _exit(1);
        open(STDERR, '>', '/dev/null');
        exec($tcpdump, '-i', $interface, 'port', '68', '-n', '-vvvvvv') or _exit(1);
    }
    $self->{pid} = $pid;
    $SIG{INT} = $SIG{TERM} = sub { $self->stop(); exit 1; };
    sigprocmask(SIG_SETMASK, $self->{signal_mask});
    return $self;
}

sub file {
    return $_[0]->{file};
}

sub pid {
    return $_[0]->{pid};
}

sub stop {
    my ($self) = @_;
    # Block repeated interrupts until the owned child is reaped.
    sigprocmask(SIG_BLOCK, $self->{stop_signals});
    my $child = delete $self->{pid};
    unless ($child) {
        sigprocmask(SIG_SETMASK, $self->{signal_mask});
        return '';
    }
    my $reaped = waitpid($child, WNOHANG);
    my $early = ($reaped == $child) ? 1 : 0;
    if ($reaped == 0) {
        kill 'TERM', $child;
        foreach (1 .. 50) {
            last if ($reaped = waitpid($child, WNOHANG)) != 0;
            select(undef, undef, undef, 0.1);
        }
        if ($reaped == 0) {
            kill 'KILL', $child;
            $reaped = waitpid($child, 0);
        }
    }
    sigprocmask(SIG_SETMASK, $self->{signal_mask});
    return 'could not be reaped' if $reaped != $child;
    my ($signal, $status) = ($? & 127, $? >> 8);
    $self->{on_reap}->($child) if $self->{on_reap};
    my $how = $signal ? "on signal $signal" : "with status $status";
    return "ended before the capture window did, $how" if $early;
    return '' if $signal == 15 || (!$signal && !$status);
    return "left the capture $how";
}

1;

__END__

=head1 NAME

xCAT::PacketCapture - tcpdump lifecycle for standalone DHCP detection commands

=head1 METHODS

=head2 start

Start tcpdump with its resolved path and interface. Return the capture object,
or undef when fork fails. An optional callback receives the reaped child PID.
The caller owns the capture window and must call C<stop> before reading C<file>.
C<pid> returns the child PID until C<stop> takes ownership of its cleanup.

This owner installs process-wide INT and TERM handlers that stop the capture
and exit 1. They remain installed after C<stop>. Use one capture per standalone
command, not inside a daemon. The private file is removed at process exit.

=head2 stop

Stop and reap the child once. Return an empty string for a clean stop, or a
diagnostic for an early exit, failure, or forced kill after the TERM grace period.

=cut
