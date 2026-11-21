#!/usr/bin/perl
# buildrpms.pl starts each worker with start_build_worker(sub { $pm->start(...) }). With
# --nproc=0, Parallel::ForkManager does not fork: start() returns 0 in the original process,
# and the caller runs the work itself. start_build_worker must let that process continue. It
# must not wait on the gate as a worker would, because the process holds the only writer.
use strict;
use warnings;
use Test::More;
use POSIX ();
use FindBin qw($Bin);
use lib "$Bin/../../build-utils/lib";
use Parallel::ForkManager;
use XCAT::BuildUtils ();

# Start one worker through a ForkManager with $max_procs, in a stand-in for buildrpms.pl.
# The stand-in exits 0 when the work runs in it, 1 when a forked worker ran the work and
# exited 0, 2 when start_build_worker did not return 0 or a pid, and 3 when the work ran in
# the stand-in after its process group changed.
sub run_worker_loop {
    my ($max_procs) = @_;
    my $builder = fork();
    die "fork: $!" unless defined $builder;
    unless ($builder) {
        open(STDOUT, '>', '/dev/null');
        open(STDERR, '>', '/dev/null');
        my ($self, $group) = ($$, getpgrp());
        my $pm  = Parallel::ForkManager->new($max_procs);
        my $pid = XCAT::BuildUtils::start_build_worker(sub { $pm->start('pkg') });
        POSIX::_exit(2) unless defined $pid;
        unless ($pid) {
            # The work. In a forked worker, $$ differs from the stand-in.
            POSIX::_exit(5) if $$ != $self;
            POSIX::_exit(3) if getpgrp() != $group;
            $pm->finish;
            $pm->wait_all_children;
            POSIX::_exit(0);
        }
        waitpid($pid, 0);
        POSIX::_exit($? == 5 << 8 ? 1 : 4);
    }
    waitpid($builder, 0);
    return $?;
}

my $status = run_worker_loop(0);
is($status & 127, 0, 'the builder is not ended by a signal with --nproc=0');
is($status >> 8, 0, 'with --nproc=0 the work runs in the original process and its original group');

$status = run_worker_loop(1);
is($status >> 8, 1, 'control: with --nproc=1 a forked worker runs the work');

done_testing();
