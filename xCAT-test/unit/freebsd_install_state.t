#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Temp qw(tempdir);
use JSON;
use Test::More;
use xCAT::FreeBSDInstall;

my $temporary = tempdir(CLEANUP => 1);
my $fingerprint = 'a' x 64;
my $attempt = 'b' x 32;
my $other_attempt = 'c' x 32;
my $sequence = 0;

sub fixture {
    my $directory = "$temporary/state-" . ++$sequence;
    my $generation = xCAT::FreeBSDInstall::prepare('node1', $fingerprint, directory => $directory);
    return ($directory, $generation);
}

sub disk_state {
    my ($directory) = @_;
    open(my $handle, '<', "$directory/node1.json") or die $!;
    local $/;
    my $state = decode_json(<$handle>);
    close($handle) or die $!;
    return $state;
}

sub write_state {
    my ($directory, $state) = @_;
    open(my $handle, '>', "$directory/node1.json") or die $!;
    print {$handle} encode_json($state) or die $!;
    close($handle) or die $!;
}

sub status {
    my ($directory, $generation, $phase, $action, $nonce) = @_;
    $nonce = $attempt unless defined($nonce);
    return xCAT::FreeBSDInstall::transition('node1',
        "freebsd-install-v1 $generation $nonce $phase\n", $action || sub {}, directory => $directory);
}

sub rejects {
    my ($code, $pattern, $name) = @_;
    my $ok = eval { $code->(); 1 };
    ok(!$ok, "$name fails");
    like($@, $pattern, "$name reports the reason");
}

my ($directory, $generation) = fixture();
like($generation, qr/\A[0-9a-f]{32}\z/, 'prepare generates a nonce');
is(xCAT::FreeBSDInstall::prepare('node1', $fingerprint, directory => $directory), $generation,
    'repeated preparation reuses the unchanged configuration');
is(disk_state($directory)->{phase}, 'prepared', 'preparation is persisted');
is((stat($directory))[2] & 0777, 0700, 'state directory is private');
is((stat("$directory/node1.json"))[2] & 0777, 0600, 'state file is private');
is((stat("$directory/node1.lock"))[2] & 0777, 0600, 'lock file is private');
my @actions;
my $action = sub {
    my ($phase) = @_;
    push @actions, $phase;
    my $state = disk_state($directory);
    is($state->{attempt}, $attempt, "$phase action sees the bound attempt on disk");
    is($state->{phase}, {begin => 'installing', complete => 'completing', booted => 'installed'}->{$phase},
        "$phase action follows the required persistent phase");
};
is(status($directory, $generation, 'begin', $action), "freebsd-install-v1 $generation begin ok\n",
    'begin is acknowledged after its action');
rejects(sub { xCAT::FreeBSDInstall::prepare('node1', $fingerprint, directory => $directory); },
    qr/Stop the node/, 'active installation rearm');
is(status($directory, $generation, 'begin', $action), "freebsd-install-v1 $generation begin ok\n",
    'same attempt can retry begin after losing its reply');
rejects(sub { status($directory, $generation, 'begin', undef, $other_attempt); },
    qr/Another installation attempt/, 'another boot attempt');
rejects(sub { status($directory, 'd' x 32, 'complete'); }, qr/Stale/, 'old generation');
rejects(sub { status($directory, $generation, 'booted'); }, qr/not complete/, 'early boot notification');
is(status($directory, $generation, 'complete', $action), "freebsd-install-v1 $generation complete ok\n",
    'complete is acknowledged after its action and persistence');
is(disk_state($directory)->{phase}, 'installed', 'completion records installed');
is(status($directory, $generation, 'complete', sub { die 'must not repeat'; }),
    "freebsd-install-v1 $generation complete ok\n", 'duplicate completion does not repeat its action');
rejects(sub { status($directory, $generation, 'begin'); }, qr/cannot begin/, 'installed generation reinstall');
rejects(sub { status($directory, $generation, 'failed'); }, qr/cannot fail/, 'late failure notification');
is(status($directory, $generation, 'booted', $action), "freebsd-install-v1 $generation booted ok\n",
    'first boot is acknowledged after its action');
is(disk_state($directory)->{phase}, 'booted', 'first boot is persisted');
status($directory, $generation, 'booted', sub { die 'must not repeat'; });
status($directory, $generation, 'complete', sub { die 'must not repeat'; });
is_deeply(\@actions, [qw(begin begin complete booted)], 'only eligible actions run');
my $next = xCAT::FreeBSDInstall::prepare('node1', $fingerprint, directory => $directory);
isnt($next, $generation, 'explicit preparation after first boot creates a fresh generation');
ok(!exists(disk_state($directory)->{attempt}), 'new generation drops the previous attempt');
rejects(sub { status($directory, $generation, 'complete'); }, qr/Stale/, 'delayed old completion after rearm');

for my $phase (qw(begin complete booted)) {
    my ($root, $token) = fixture();
    status($root, $token, 'begin') unless $phase eq 'begin';
    status($root, $token, 'complete') if $phase eq 'booted';
    rejects(sub { status($root, $token, $phase, sub { die "action failed\n"; }); }, qr/action failed/,
        "$phase action error");
    is(disk_state($root)->{phase}, {begin => 'installing', complete => 'completing', booted => 'installed'}->{$phase},
        "$phase error leaves retryable state");
    my $retried = 0;
    status($root, $token, $phase, sub { ++$retried; });
    is($retried, 1, "$phase retry executes the failed action");
}

for my $initial (qw(prepared installing completing)) {
    my ($root, $token) = fixture();
    status($root, $token, 'begin') unless $initial eq 'prepared';
    eval { status($root, $token, 'complete', sub { die "retry\n"; }); } if $initial eq 'completing';
    status($root, $token, 'failed');
    is(disk_state($root)->{phase}, 'failed', "failure from $initial is persisted");
    status($root, $token, 'failed');
    rejects(sub { status($root, $token, 'begin'); }, qr/cannot begin/, 'failed generation cannot resume');
    rejects(sub { xCAT::FreeBSDInstall::prepare('node1', $fingerprint, directory => $root); },
        qr/Stop the node/, 'failed generation cannot rearm implicitly');
    is(xCAT::FreeBSDInstall::cancel('node1', directory => $root), 1, 'offline cancels existing state');
    rejects(sub { status($root, $token, 'begin'); }, qr/not armed/, 'cancelled generation');
    isnt(xCAT::FreeBSDInstall::prepare('node1', $fingerprint, directory => $root), $token,
        'cancel permits explicit preparation with a new generation');
}

my ($changed_dir, $changed_token) = fixture();
isnt(xCAT::FreeBSDInstall::prepare('node1', 'f' x 64, directory => $changed_dir), $changed_token,
    'configuration change invalidates an unstarted generation');
rejects(sub { status($changed_dir, $changed_token, 'begin'); }, qr/Stale/, 'replaced configuration');
for my $message ('', 'freebsd-install-v2', "freebsd-install-v1 $next $attempt begin\nextra",
    "freebsd-install-v1 $next $attempt begin\r\n", "freebsd-install-v1 $next $attempt unknown\n") {
    rejects(sub { xCAT::FreeBSDInstall::transition('node1', $message, sub {}, directory => $directory); },
        qr/Invalid installation status/, 'malformed status message');
}
rejects(sub { xCAT::FreeBSDInstall::transition('node1', "freebsd-install-v1 $next $attempt begin", undef,
    directory => $directory); }, qr/Missing installation action/, 'missing action');
for my $node ('../node1', '/node1', '.node1', "node1\n", '', 'x' x 256) {
    rejects(sub { xCAT::FreeBSDInstall::prepare($node, $fingerprint, directory => $directory); },
        qr/Invalid node name/, 'invalid node identifier');
}
rejects(sub { xCAT::FreeBSDInstall::prepare('node1', 'invalid', directory => $directory); },
    qr/fingerprint/, 'invalid configuration fingerprint');
is(xCAT::FreeBSDInstall::state('missing', directory => $directory), undef, 'missing state is distinguishable');
is(xCAT::FreeBSDInstall::cancel('missing', directory => $directory), 0, 'cancel does not create armed state');

for my $change (
    sub { $_[0]->{node} = 'node2'; },
    sub { $_[0]->{generation} = 'bad'; },
    sub { $_[0]->{phase} = 'unknown'; },
    sub { $_[0]->{version} = 2; },
    sub { $_[0]->{phase} = 'installing'; },
) {
    my ($root) = fixture();
    my $state = disk_state($root);
    $change->($state);
    write_state($root, $state);
    rejects(sub { xCAT::FreeBSDInstall::state('node1', directory => $root); },
        qr/Invalid state|no installation attempt/, 'corrupt state');
}
for my $target (qw(directory state lock)) {
    my ($root) = fixture();
    my $path = $target eq 'directory' ? $root : "$root/node1." . ($target eq 'state' ? 'json' : 'lock');
    rename($path, "$path.original") or die $!;
    symlink("$path.original", $path) or die $!;
    rejects(sub { xCAT::FreeBSDInstall::state('node1', directory => $root); },
        qr/Unsafe|Cannot/, "$target symlink");
}
for my $target (qw(directory state lock)) {
    my ($root) = fixture();
    my $path = $target eq 'directory' ? $root : "$root/node1." . ($target eq 'state' ? 'json' : 'lock');
    chmod($target eq 'directory' ? 0755 : 0644, $path) or die $!;
    rejects(sub { xCAT::FreeBSDInstall::state('node1', directory => $root); }, qr/Unsafe/, "$target public access");
}

my ($race_dir, $race_token) = fixture();
my (@children, @readers);
for my $nonce ($attempt, $other_attempt) {
    pipe(my $reader, my $writer) or die $!;
    my $pid = fork();
    die "fork: $!" unless defined($pid);
    if (!$pid) {
        close($reader);
        my $ok = eval { status($race_dir, $race_token, 'begin', undef, $nonce); 1 };
        print {$writer} $ok ? 'accepted' : 'rejected';
        close($writer);
        require POSIX;
        POSIX::_exit(0);
    }
    close($writer);
    push @children, $pid;
    push @readers, $reader;
}
my @outcomes;
{
    local $SIG{ALRM} = sub { die "Concurrent state transitions timed out\n"; };
    alarm(15);
    for my $reader (@readers) {
        local $/;
        push @outcomes, scalar(<$reader>);
        close($reader);
    }
    waitpid($_, 0) for @children;
    alarm(0);
}
is_deeply([sort @outcomes], [qw(accepted rejected)], 'concurrent boots cannot both own the generation');
is(xCAT::FreeBSDInstall::state('node1', directory => $race_dir)->{phase}, 'installing',
    'concurrent transition leaves valid persisted state');

done_testing();
