#!/usr/bin/perl
# A build lock whose owner is dead is recovered unless it records a live process group. So a
# process the build starts must be recorded BEFORE it runs: a worker that runs first can outlive
# a killed parent, and a second build then takes the lock while the first one still writes.
#
# These checks cover the three ways a worker could run unrecorded: the record fails, the parent
# dies before it records, and a Perl builder forked by Parallel::ForkManager runs between two
# sh() calls with no group of its own on the lock.
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use POSIX ();
use FindBin qw($Bin);
use lib "$Bin/../../build-utils/lib";
use Parallel::ForkManager;
use XCAT::BuildUtils qw(take_build_lock);

# A held lock whose attach the test controls.
{
    package FakeLock;
    sub new     { my ($class, $attach) = @_; return bless { attach => $attach }, $class }
    sub attach  { my ($self, $pgid) = @_; return $self->{attach}->($pgid) }
    sub detach  { return 1 }
    sub release { return 0 }
}

my $TMP = tempdir(CLEANUP => 1);

# A bounded read of one byte.
sub await_byte {
    my ($fh, $seconds) = @_;
    my $mask = '';
    vec($mask, fileno($fh), 1) = 1;
    return undef unless select(my $ready = $mask, undef, undef, $seconds);
    my $got = sysread($fh, my $byte, 1);
    return defined($got) && $got == 1 ? $byte : undef;
}

# True once no process is left in the group or with that pid.
sub gone_within {
    my ($pid, $seconds) = @_;
    for (1 .. $seconds * 10) {
        return 1 if !kill(0, -$pid) && $!{ESRCH} && !kill(0, $pid) && $!{ESRCH};
        select undef, undef, undef, 0.1;
    }
    return 0;
}

# ---- a record that fails stops the command --------------------------------------------
{
    my $marker = "$TMP/ran-after-failed-record";
    my $rc = do {
        local @XCAT::BuildUtils::LIVE_LOCKS = (FakeLock->new(sub { 0 }));
        local $SIG{__WARN__} = sub { };
        XCAT::BuildUtils::sh(": > $marker");
    };
    is($rc, 127, 'sh() fails when a held lock cannot record the process group');
    ok(!-e $marker, 'and the command never ran');

    my $control = "$TMP/ran-after-record";
    my $ok = do {
        local @XCAT::BuildUtils::LIVE_LOCKS = (FakeLock->new(sub { 1 }));
        XCAT::BuildUtils::sh(": > $control");
    };
    is($ok, 0, 'control: sh() runs the command when the record succeeds');
    ok(-e $control, 'control: and the command wrote its file');
}

# ---- a parent that dies before it records starts nothing ------------------------------
# The fake attach ends the parent with _exit, which runs no handler, like SIGKILL would.
{
    my $marker = "$TMP/ran-after-parent-died";
    my $pgfile = "$TMP/worker-pgid";
    my $parent = fork();
    die "fork: $!" unless defined $parent;
    unless ($parent) {
        local @XCAT::BuildUtils::LIVE_LOCKS = (FakeLock->new(sub {
            my ($pgid) = @_;
            if (open(my $fh, '>', $pgfile)) { print {$fh} $pgid; close $fh }
            POSIX::_exit(0);
        }));
        XCAT::BuildUtils::sh(": > $marker");
        POSIX::_exit(1);
    }
    waitpid($parent, 0);
    my $pgid = do { open(my $fh, '<', $pgfile) or die "no $pgfile: $!"; local $/; <$fh> };
    like($pgid, qr/\A[1-9][0-9]*\z/, 'control: the parent reached the record and died there');
    ok(gone_within($pgid, 20), 'the command process is gone');
    ok(!-e $marker, 'and it never ran the command');
}

# ---- a pid that is not a child of this process is never recorded ----------------------
# A recorded group that is always alive, such as group 1, makes the lock unrecoverable. The
# release_repository.t schedule stub returns 1 from Parallel::ForkManager::start.
{
    my @attached;
    # No child holds the read end of the gate, so a write to it raises SIGPIPE.
    local $SIG{PIPE} = "IGNORE";
    my ($pid, $ok) = do {
        local @XCAT::BuildUtils::LIVE_LOCKS = (FakeLock->new(sub { push @attached, @_; 1 }));
        XCAT::BuildUtils::start_build_worker(sub { getppid() });
    };
    is($pid, getppid(), 'control: start_build_worker returns the pid the fork gave');
    is($ok, 0, 'start_build_worker reports no record for a pid that is not its child');
    is_deeply(\@attached, [], 'and no held lock records that group');
}

# ---- the record exists before the worker runs -----------------------------------------
{
    my $ckout = '/opt/builds/record-first/xcat-core';
    my $dir   = XCAT::BuildUtils::lock_path_for($ckout, $TMP) . '.d';
    my $lock  = take_build_lock($ckout, $TMP);
    my $seen  = "$TMP/record-seen";
    my ($pid, $ok) = XCAT::BuildUtils::start_build_worker();
    die "fork: $!" unless defined $pid;
    unless ($pid) {
        my @mine = glob("$dir/workers/$$.*");
        if (open(my $fh, '>', $seen)) { print {$fh} scalar(@mine); close $fh }
        POSIX::_exit(0);
    }
    is($ok, 1, 'start_build_worker reports the record');
    waitpid($pid, 0);
    my $count = do { open(my $fh, '<', $seen) or die "no $seen: $!"; local $/; <$fh> };
    is($count, 1, 'the worker finds its own group recorded on the lock when it starts');
    XCAT::BuildUtils::detach_build_workers($pid);
    undef $lock;
    ok(!-d $dir, 'control: the lock is released once the worker is reaped and detached');
}

# ---- a ForkManager builder keeps the lock after its parent is killed ------------------
# buildrpms.pl runs each package build as a Perl ForkManager child, which writes files between
# its sh() calls. The child stands still here, in Perl, with no sh() command running.
{
    my $ckout = '/opt/builds/forkmanager/xcat-core';
    my $dir   = XCAT::BuildUtils::lock_path_for($ckout, $TMP) . '.d';
    pipe(my $up_r,   my $up_w)   or die "pipe: $!";
    pipe(my $stop_r, my $stop_w) or die "pipe: $!";

    my $wrapper = fork();
    die "fork: $!" unless defined $wrapper;
    unless ($wrapper) {
        close($up_r);
        my $lock = eval { take_build_lock($ckout, $TMP) };
        POSIX::_exit(1) unless $lock;
        my $pm = Parallel::ForkManager->new(1);
        my $builder = XCAT::BuildUtils::start_build_worker(sub { $pm->start });
        unless ($builder) {
            close($stop_w);
            syswrite($up_w, 'b');
            sysread($stop_r, my $go, 1);
            POSIX::_exit(0);
        }
        close($stop_r);
        close($stop_w);
        syswrite($up_w, 'w');
        sleep 300;
        POSIX::_exit(0);
    }
    close($up_w);
    close($stop_r);
    my $first  = await_byte($up_r, 20) // '';
    my $second = await_byte($up_r, 20) // '';
    is(join('', sort $first, $second), 'bw', 'control: the wrapper holds the lock and its builder runs');

    my @record = glob("$dir/workers/*");
    is(scalar(@record), 1, 'the builder is recorded on the lock');
    my ($builder) = ($record[0] // '') =~ m{/([0-9]+)\.[0-9]+\z};

    kill('KILL', $wrapper);
    waitpid($wrapper, 0);
    ok(defined($builder) && kill(0, -$builder), 'control: the builder outlives its killed parent');

    my $taken = eval { take_build_lock($ckout, $TMP) };
    ok(!defined $taken, 'a second build is refused while the builder runs');
    like($@ // '', qr/process group $builder\b/, 'and the refusal names the builder');

    # The other half: once the builder exits, the lock is recoverable.
    close($stop_w);
    ok(gone_within($builder, 20), 'control: the builder exits');
    my $after = eval { take_build_lock($ckout, $TMP) };
    ok(defined $after, 'then a second build takes the lock') or diag("refused: $@");
    undef $after;
    undef $taken;
    close($up_r);
}

my @left = glob("$TMP/*.lock.d*");
is_deeply(\@left, [], 'no lock directory or borrow is left behind');

done_testing();
