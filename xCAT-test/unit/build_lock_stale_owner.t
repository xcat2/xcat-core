#!/usr/bin/perl
# A build killed with SIGKILL or by the OOM-killer runs no handler, so it leaves its lock
# behind. Every later build of the same target then fails until an operator removes the lock by
# hand -- /var/lock/buildrpms.openeuler-20.03sp4-x86_64.lock.d did that for seven days.
#
# The build lock is an XCAT::NFSLock, whose protocol recovers a lock whose owner is provably
# dead. The protocol itself is tested in xcat-dep's t/nfslock_borrow_recovery.t. These checks
# cover what xcat-core adds: that the build lock recovers from a killed holder, that a live
# holder is still refused, and that the refusal says what actually happened -- contention and a
# mkdir that failed outright are different problems and used to print the same sentence.
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use POSIX ();
use FindBin qw($Bin);
use lib "$Bin/../../build-utils/lib";
use XCAT::BuildUtils qw(take_build_lock);

my $CKOUT = '/opt/builds/devel/xcat-core';
my $TMP   = tempdir(CLEANUP => 1);
my $DIR   = XCAT::BuildUtils::lock_path_for($CKOUT, $TMP) . '.d';

# ---- a holder killed with SIGKILL strands nothing --------------------------------------
# The defect, stated as the property that fixes it. This cannot pass on a lock with no
# recovery: the directory outlives the process and the next acquirer fails on it.
pipe(my $ready, my $tell) or die "pipe: $!";
my $holder = fork();
die "fork: $!" unless defined $holder;
if (!$holder) {
    close $ready;
    my $got = eval { take_build_lock($CKOUT, $TMP) };
    syswrite($tell, defined($got) ? "held\n" : "failed\n");
    # Hold until killed. _exit is never reached; it is here so a stray wake cannot run the END
    # blocks or flush the parent's inherited buffers.
    sleep 300;
    POSIX::_exit(0);
}
close $tell;
my $said = <$ready> // '';
close $ready;
is($said, "held\n", 'a child process takes the build lock');
ok(-d $DIR, 'control: the lock directory exists while that child holds it');

my $blocked = eval { take_build_lock($CKOUT, $TMP) };
ok(!defined $blocked, 'while the holder lives, a second build is refused');
my $refusal = $@ // '';
like($refusal, qr/another build still holds/, 'and the refusal reports contention');
like($refusal, qr/still held after [0-9]+ retr\w+ by pid \Q$holder\E\b/,
    'and names the pid that holds it, so a live holder is told from any other failure');
like($refusal, qr/\Q$CKOUT\E/, 'which names the checkout that is building');

# ---- a lock that cannot be created is not reported as a concurrent build ----------------
# Every acquire failure used to print "another build already holds", with the contention advice,
# so an ENOENT or an EACCES sent the operator looking for a build that does not exist.
{
    my $advice = "serialize them, or pass a distinct --mock-uniqueext\n";
    my $got = eval {
        XCAT::BuildUtils::acquire_lock_dir("$TMP/absent/xcatbld-x.lock.d", 'target zz', $advice);
    };
    my $said = $@ // '';
    ok(!defined $got, 'a lock under a directory that does not exist is refused');
    like($said, qr/No such file or directory/, 'and the refusal carries the error that happened');
    unlike($said, qr/another build still holds|\Q$advice\E/,
        'and claims no concurrent build, and prints no advice about one');
}

kill 'KILL', $holder;
waitpid($holder, 0);
ok(!kill(0, $holder), 'the holder is gone, killed with a signal it cannot handle');

my $after = eval { take_build_lock($CKOUT, $TMP) };
ok(defined $after, 'the build lock is recovered after its holder is SIGKILLed')
    or diag "take_build_lock died: $@";

# ---- a different checkout is never blocked ---------------------------------------------
# The lock is keyed on the checkout, so two checkouts build at once. Asserted here because the
# recovery above must not have widened what one lock excludes.
my $other = eval { take_build_lock('/opt/builds/stable/xcat-core', $TMP) };
ok(defined $other, 'a build of a different checkout runs beside it');

undef $after;
ok(!-d $DIR, 'releasing the lock removes its directory');

# ---- a signal handler can release what DESTROY will not ---------------------------------
# DESTROY does not run when a signal ends the process, so cancel_build calls
# release_build_locks instead. That reaches a lock only while the lock is in the registry.
{
    my $signalled = '/opt/builds/signal/xcat-core';
    my $its_dir   = XCAT::BuildUtils::lock_path_for($signalled, $TMP) . '.d';
    my $lock      = take_build_lock($signalled, $TMP);
    ok(-d $its_dir, 'control: the lock directory exists while the guard is held');
    XCAT::BuildUtils::release_build_locks();
    ok(!-d $its_dir, 'release_build_locks frees a lock whose guard is still in scope');
}

# No lock state may survive, on any path above.
undef $other;
my @left = glob("$TMP/*.lock.d*");
is_deeply(\@left, [], 'no lock directory or borrow is left behind');

done_testing();
