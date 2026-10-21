#!/usr/bin/env perl
# A KILLED BUILD MUST NOT KEEP THE CHECKOUT.
#
# The build lock is released in DESTROY, and perl does not run DESTROY when a signal ends the
# process. So a cancelled build left its lock directory behind, and the next build of that
# checkout died on
#     FATAL: another build of <path> already holds <dir> (held by [pid=NNNN])
# naming a pid that had already exited. One such directory blocked an openSUSE target across
# three consecutive runs before anyone looked at it.
#
# buildrpms.pl has released its lock on cancellation for some time. This covers the Debian
# builder doing the same, and the ORDER it must do it in: the command in flight is stopped
# before the lock is released, because handing the checkout to a second build while
# dpkg-buildpackage is still rewriting debian/changelog in it is worse than holding the lock a
# moment longer.
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use POSIX qw(WNOHANG);
use FindBin;
use lib "$FindBin::Bin/../../build-utils/lib";
use XCAT::BuildUtils ();

my $lockdir = tempdir(CLEANUP => 1);
my $ckout   = tempdir(CLEANUP => 1);

# ---------------------------------------------------------------------------
# 1. The lock is taken, and a second taker is refused. Without this the test below could pass
#    by the lock never having worked at all.
# ---------------------------------------------------------------------------
{
    my $l = XCAT::BuildUtils::take_build_lock($ckout, $lockdir);
    ok($l, 'a build takes the checkout lock');
    my $path = XCAT::BuildUtils::lock_path_for($ckout, $lockdir) . '.d';
    ok(-d $path, 'the lock directory exists while it is held');
    my $second = eval { XCAT::BuildUtils::take_build_lock($ckout, $lockdir) };
    ok(!$second, 'a second build of the same checkout is refused');
    like($@, qr/already holds/, 'and told which lock is held');
    undef $l;
    ok(!-d $path, 'releasing it removes the directory');
}

# ---------------------------------------------------------------------------
# 2. THE REGRESSION. Terminate the holder with SIGTERM, then take the lock again.
# ---------------------------------------------------------------------------
{
    my $path = XCAT::BuildUtils::lock_path_for($ckout, $lockdir) . '.d';
    my $ready = "$lockdir/ready";

    my $pid = fork();
    die "cannot fork\n" unless defined $pid;
    unless ($pid) {
        # the child is the build: it takes the lock, says so, and waits to be killed
        # exactly what builddebs.pl does -- not a hand-rolled equivalent, or this would pass
        # with the wiring removed and prove nothing.
        XCAT::BuildUtils::install_build_cancellation();
        my $l = XCAT::BuildUtils::take_build_lock($ckout, $lockdir);
        if (open(my $r, '>', $ready)) { close $r }
        sleep 30;
        POSIX::_exit(0);
    }

    # wait for the child to actually hold it, rather than guessing with a sleep
    my $held = 0;
    for (1 .. 100) { if (-e $ready) { $held = 1; last } select undef, undef, undef, 0.1 }
    ok($held, 'the build says it holds the lock');
    ok(-d $path, 'and the directory is there while it runs');

    kill 'TERM' => $pid;
    my $reaped = 0;
    for (1 .. 100) { if (waitpid($pid, WNOHANG) > 0) { $reaped = 1; last } select undef, undef, undef, 0.1 }
    ok($reaped, 'the build stops when it is terminated');

    ok(!-d $path, 'a TERMINATED build leaves no lock behind');

    # the point of all of it: the next build can run
    my $next = eval { XCAT::BuildUtils::take_build_lock($ckout, $lockdir) };
    ok($next, 'the next build of that checkout takes the lock')
        or diag("still refused: $@");
    undef $next;
}

# ---------------------------------------------------------------------------
# 3. The command in flight is STOPPED, not orphaned.
#    Checked from the parent, because the cancelled build re-raises the signal with the default
#    disposition and so never reaches an END block of its own. A distinctive sleep makes the
#    build subprocess findable; the pattern is bracketed so the search cannot match itself.
# ---------------------------------------------------------------------------
{
    my $started = "$lockdir/started3";
    my $marker  = '778349';                       # nothing else on this host sleeps for this long
    my $pid = fork();
    die "cannot fork\n" unless defined $pid;
    unless ($pid) {
        XCAT::BuildUtils::install_build_cancellation();
        my $l = XCAT::BuildUtils::take_build_lock($ckout, $lockdir);
        if (open(my $st, '>', $started)) { close $st }
        XCAT::BuildUtils::sh("sleep $marker");
        POSIX::_exit(0);
    }
    my $up = 0;
    for (1 .. 100) { if (-e $started) { $up = 1; last } select undef, undef, undef, 0.1 }
    ok($up, 'the build subprocess is running');
    my $live = `pgrep -f "[s]leep $marker" 2>/dev/null | wc -l`; chomp $live;
    cmp_ok($live, '>', 0, 'and the test can see it -- the control for the check below');

    kill 'TERM' => $pid;
    my $reaped = 0;
    for (1 .. 100) { if (waitpid($pid, WNOHANG) > 0) { $reaped = 1; last } select undef, undef, undef, 0.1 }
    ok($reaped, 'the cancelled build exits');

    my $left = 1;
    for (1 .. 50) {
        $left = `pgrep -f "[s]leep $marker" 2>/dev/null | wc -l`; chomp $left;
        last if $left == 0;
        select undef, undef, undef, 0.1;
    }
    is($left, 0, 'the build subprocess was stopped, not left running without its lock')
        or do { diag('orphaned build subprocess still holds the checkout');
                system("pkill -f '[s]leep $marker'") };
}

# ---------------------------------------------------------------------------
# 4. THE WHOLE PROCESS GROUP GOES, not just the shell.
#    Killing /bin/sh does not kill what it started: dpkg-buildpackage leaves workers behind, and
#    those keep writing the checkout after the lock would otherwise have been handed to the next
#    build. The command runs in its own process group so cancellation can take all of it.
# ---------------------------------------------------------------------------
{
    my $tag     = '661277';                     # the worker, a grandchild of the build
    my $started = "$lockdir/started4";
    my $pid = fork();
    die "cannot fork\n" unless defined $pid;
    unless ($pid) {
        XCAT::BuildUtils::install_build_cancellation();
        my $l = XCAT::BuildUtils::take_build_lock($ckout, $lockdir);
        if (open(my $st, '>', $started)) { close $st }
        # a shell that spawns a worker and waits: the worker is a GRANDCHILD of this process
        XCAT::BuildUtils::sh("sleep $tag & sleep $tag");
        POSIX::_exit(0);
    }
    my $up = 0;
    for (1 .. 100) { if (-e $started) { $up = 1; last } select undef, undef, undef, 0.1 }
    ok($up, 'the build started');

    my $workers = 0;
    for (1 .. 100) {
        $workers = `pgrep -f "[s]leep $tag" 2>/dev/null | wc -l`; chomp $workers;
        last if $workers >= 2;
        select undef, undef, undef, 0.1;
    }
    cmp_ok($workers, '>=', 2, 'the build has a worker of its own -- the control for the check below');

    kill 'TERM' => $pid;
    for (1 .. 100) { last if waitpid($pid, WNOHANG) > 0; select undef, undef, undef, 0.1 }

    my $left = 1;
    for (1 .. 100) {
        $left = `pgrep -f "[s]leep $tag" 2>/dev/null | wc -l`; chomp $left;
        last if $left == 0;
        select undef, undef, undef, 0.1;
    }
    is($left, 0, 'cancelling the build takes its workers with it, not just its shell')
        or do { diag('a build worker outlived the cancellation and can still write the checkout');
                system("pkill -f '[s]leep $tag'") };
}

# ---------------------------------------------------------------------------
# 5. A command killed by a signal reports as killed, not as success.
#    $? >> 8 is 0 for a signalled child, so a build stopped mid-way looked like it had worked.
# ---------------------------------------------------------------------------
{
    my $rc = -1;
    my $pid = fork();
    die "cannot fork\n" unless defined $pid;
    unless ($pid) {
        my $got = XCAT::BuildUtils::sh("kill -TERM \$\$");
        POSIX::_exit($got);
    }
    waitpid($pid, 0);
    $rc = $? >> 8;
    is($rc, 128 + 15, 'a command killed by SIGTERM reports 128+15, not 0');
}


done_testing();
