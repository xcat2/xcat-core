#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use File::Temp qw(tempdir);
use IO::Handle;
use POSIX ();
use Test::More;

require xCAT::Utils;

# The lock files live in /var/lock/xcat, so the test keeps them in a directory of its own.
my $lock_dir = tempdir(CLEANUP => 1);
{
    no warnings 'redefine';
    *xCAT::Utils::lock_dir = sub { return $lock_dir };
}

# A process holds a lock, a second one waits for it, and a third tries it after the release.
my $holder = xCAT::Utils->acquire_lock('kit', 1);
ok($holder, 'the first process takes the lock');
pipe(my $from_waiter, my $to_parent) or die "cannot make a pipe: $!";
my $pid = fork() // die "cannot fork: $!";
if (!$pid) {
    close($from_waiter);
    my $lock = xCAT::Utils->acquire_lock('kit', 0);
    print {$to_parent} ($lock ? "held\n" : "failed\n");
    $to_parent->flush;
    sleep 60;
    POSIX::_exit(0);
}
close($to_parent);

# The second process waits in flock on the file of the first one.
sleep 2;
xCAT::Utils->release_lock($holder, 1);
my $waiter = <$from_waiter>;
is($waiter, "held\n", 'the waiting process takes the lock after its release');
my $third = xCAT::Utils->acquire_lock('kit', 1);
ok(!$third, 'a third process cannot take the lock while the waiting process holds it');
kill('KILL', $pid);
waitpid($pid, 0);
done_testing();
