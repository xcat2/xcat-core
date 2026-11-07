#!/usr/bin/perl
# start_build_worker releases a gated worker by writing one byte to a pipe. When the worker
# dies after the record and before that write, the pipe has no reader. A write to it must
# fail with EPIPE and take the failure path. SIGPIPE must not end the build process, because
# a signal skips the cleanup that restores the checkout and releases the lock.
use strict;
use warnings;
use Test::More;
use POSIX ();
use FindBin qw($Bin);
use lib "$Bin/../../build-utils/lib";
use XCAT::BuildUtils ();

# A held lock whose attach the test controls.
{
    package FakeLock;
    sub new     { my ($class, $attach) = @_; return bless { attach => $attach }, $class }
    sub attach  { my ($self, $pgid) = @_; return $self->{attach}->($pgid) }
    sub detach  { return 1 }
    sub release { return 0 }
}

# Run start_build_worker in a stand-in for the builder, with the default SIGPIPE disposition.
# $attach runs as the record step. Returns the stand-in's wait status.
# Exit 2: the worker was refused. Exit 1: the worker was released.
sub launch_with {
    my ($attach) = @_;
    my $builder = fork();
    die "fork: $!" unless defined $builder;
    unless ($builder) {
        open(STDOUT, '>', '/dev/null');
        open(STDERR, '>', '/dev/null');
        $SIG{PIPE} = 'DEFAULT';
        local @XCAT::BuildUtils::LIVE_LOCKS = (FakeLock->new($attach));
        my ($pid, $ok) = XCAT::BuildUtils::start_build_worker();
        POSIX::_exit(3) unless defined $pid;
        POSIX::_exit(0) unless $pid;    # the released worker
        waitpid($pid, 0);
        POSIX::_exit($ok ? 1 : 2);
    }
    waitpid($builder, 0);
    return $?;
}

# ---- the worker dies after the record and before the release ---------------------------
{
    my $status = launch_with(sub {
        my ($pgid) = @_;
        kill('KILL', $pgid);
        waitpid($pgid, 0);
        return 1;
    });
    is($status & 127, 0, 'the builder is not ended by a signal when the worker dies before release');
    is($status >> 8, 2, 'and start_build_worker reports the worker as not released');
}

# ---- control: a live worker is released ------------------------------------------------
{
    my $status = launch_with(sub { 1 });
    is($status & 127, 0, 'control: the builder exits normally');
    is($status >> 8, 1, 'control: start_build_worker releases a live worker');
}

done_testing();
