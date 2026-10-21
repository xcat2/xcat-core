#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl", "$FindBin::Bin/../../perl-xCAT";
use Carp qw(croak);
use File::Temp qw(tempdir);
use JSON;
use POSIX ();
use Test::More;
use xCAT::FreeBSDInstall;

my $root = tempdir(CLEANUP => 1);
my @servers = qw(192.0.2.11 192.0.2.12);
my %generations = ($servers[0] => 'a' x 32, $servers[1] => 'b' x 32);
my $attempt = 'c' x 32;
my $sequence = 0;

sub operation {
    my ($directory, $kind, $input) = @_;
    return xCAT::FreeBSDInstall::pool_request('node1', $kind, $input, directory => $directory);
}

sub fixture {
    my $directory = "$root/case-" . ++$sequence;
    my $prepared = operation($directory, 'prepare', {fingerprint => 'd' x 64, servers => [@servers]});
    for my $server (@servers) {
        operation($directory, 'register', {epoch => $prepared->{epoch}, server => $server,
            generation => $generations{$server}, fingerprint => 'e' x 64, master => $server});
    }
    return ($directory, $prepared->{epoch});
}

sub event {
    my ($directory, $epoch, $server, $phase, %overrides) = @_;
    return operation($directory, 'event', {epoch => $epoch, server => $server,
        generation => $generations{$server}, attempt => $attempt, phase => $phase, %overrides});
}

sub read_state {
    my $directory = shift;
    open(my $handle, '<', "$directory/node1.json") or croak 'Cannot read retained pool state';
    local $/ = undef;
    my $bytes = <$handle>;
    close($handle) or croak 'Cannot close retained pool state';
    return $bytes;
}

sub rejected {
    my ($action, $reason, $label) = @_;
    my $accepted = eval { $action->(); 1; };
    ok(!$accepted, "$label is rejected");
    like($@, $reason, "$label explains why");
    return;
}

subtest 'surviving service node owns the complete attempt' => sub {
    my ($directory, $epoch) = fixture();
    my $result = event($directory, $epoch, $servers[1], 'begin');
    is($result->{owner}, $servers[1], 'second prepared server can claim without the first server');
    is($result->{phase}, 'installing', 'claim is durable before acknowledgement');
    is(event($directory, $epoch, $servers[1], 'begin')->{owner}, $servers[1], 'identical begin retry succeeds');
    my $before = read_state($directory);
    rejected(sub { event($directory, $epoch, $servers[0], 'begin'); }, qr/Another[ ]service[ ]node/x, 'competing server');
    rejected(sub { event($directory, $epoch, $servers[1], 'begin', attempt => 'f' x 32); }, qr/Another[ ]service[ ]node/x, 'new attempt on incumbent');
    is(read_state($directory), $before, 'rejected claims leave durable state unchanged');
    is(event($directory, $epoch, $servers[1], 'completing')->{phase}, 'completing', 'owner starts final boot transition');
    is(event($directory, $epoch, $servers[1], 'complete')->{phase}, 'installed', 'owner completes');
    is(event($directory, $epoch, $servers[1], 'booted')->{phase}, 'booted', 'owner confirms disk boot');
    is(event($directory, $epoch, $servers[1], 'complete')->{phase}, 'booted', 'completion retry cannot regress disk-boot state');
    rejected(sub { event($directory, $epoch, $servers[0], 'begin'); }, qr/Another[ ]service[ ]node/x, 'stale standby after completion');
    rejected(sub { event($directory, $epoch, $servers[1], 'begin'); }, qr/Invalid[ ]pool[ ]installation[ ]transition/x, 'replayed installer after completion');
    return;
};

subtest 'offline cancellation fences every old server generation' => sub {
    my ($directory, $epoch) = fixture();
    event($directory, $epoch, $servers[0], 'begin');
    event($directory, $epoch, $servers[0], 'failed');
    rejected(sub { operation($directory, 'prepare', {fingerprint => 'd' x 64, servers => [@servers]}); },
        qr/nodeset[ ]offline/x, 'rearm without resolving failed attempt');
    is(operation($directory, 'cancel', {})->{phase}, 'cancelled', 'offline cancels the whole pool generation');
    rejected(sub { event($directory, $epoch, $servers[1], 'begin'); }, qr/not[ ]armed/x, 'standby after cancellation');
    my $next = operation($directory, 'prepare', {fingerprint => 'd' x 64, servers => [@servers]});
    isnt($next->{epoch}, $epoch, 'rearm creates a new generation');
    rejected(sub { event($directory, $epoch, $servers[0], 'begin'); }, qr/Stale[ ]pool/x, 'old epoch after rearm');
    rejected(sub { event($directory, $next->{epoch}, $servers[0], 'begin'); }, qr/not[ ]registered/x, 'old server generation under new epoch');
    return;
};

subtest 'preflight failure does not claim disks or prevent another server' => sub {
    my ($directory, $epoch) = fixture();
    my $result = event($directory, $epoch, $servers[0], 'failed');
    is($result->{phase}, 'prepared', 'failure before begin retains unclaimed state');
    ok(!exists($result->{owner}), 'preflight failure has no installation owner');
    is(event($directory, $epoch, $servers[1], 'begin')->{owner}, $servers[1], 'other prepared server can begin');
    return;
};

subtest 'registration and protocol binding reject near misses without writes' => sub {
    my ($directory, $epoch) = fixture();
    my $before = read_state($directory);
    my @invalid = (
        [{epoch => '0' x 32}, qr/Stale[ ]pool/x, 'wrong epoch'],
        [{server => '192.0.2.99'}, qr/not[ ]in[ ]this[ ]installation[ ]pool/x, 'foreign server'],
        [{generation => '0' x 32}, qr/not[ ]registered/x, 'wrong local generation'],
        [{attempt => 'g' x 32}, qr/Invalid[ ]pool[ ]installation[ ]attempt/x, 'nonhex attempt'],
        [{phase => 'installing'}, qr/Invalid[ ]pool[ ]installation[ ]phase/x, 'unknown event'],
        [{phase => 'complete'}, qr/has[ ]no[ ]owner/x, 'completion before claim'],
        [{extra => 1}, qr/Unexpected[ ]pool[ ]request[ ]fields/x, 'unknown request field'],
    );
    for my $case (@invalid) {
        my ($changes, $reason, $label) = @$case;
        rejected(sub { event($directory, $epoch, $servers[0], 'begin', %$changes); }, $reason, $label);
        is(read_state($directory), $before, "$label leaves state unchanged");
    }
    rejected(sub { operation($directory, 'register', {epoch => $epoch, server => $servers[0],
        generation => 'f' x 32, fingerprint => 'e' x 64, master => $servers[0]}); },
        qr/changed[ ]within/x, 'replacement registration in the same epoch');
    is(read_state($directory), $before, 'conflicting registration leaves state unchanged');
    return;
};

subtest 'concurrent servers receive exactly one durable claim' => sub {
    my ($directory, $epoch) = fixture();
    pipe(my $start_read, my $start_write) or croak 'Cannot create start pipe';
    my @children;
    for my $server (@servers) {
        my $pid = fork();
        croak 'Cannot fork competing server' unless defined($pid);
        if (!$pid) {
            close($start_write) or POSIX::_exit(3);
            my $byte = '';
            my $count = sysread($start_read, $byte, 1);
            POSIX::_exit(3) if !defined($count) || $count != 1;
            my $accepted = eval { event($directory, $epoch, $server, 'begin'); 1; };
            POSIX::_exit($accepted ? 0 : ($@ =~ /Another[ ]service[ ]node/x ? 1 : 2));
        }
        push @children, $pid;
    }
    close($start_read) or croak 'Cannot close start reader';
    my $written = syswrite($start_write, 'xx');
    croak 'Cannot release competing servers' if !defined($written) || $written != 2;
    close($start_write) or croak 'Cannot close start writer';
    my @statuses;
    for my $pid (@children) {
        croak 'Cannot reap competing server' if waitpid($pid, 0) != $pid;
        push @statuses, $?;
    }
    is_deeply([sort { $a <=> $b } @statuses], [0, 256], 'one claim succeeds and one receives ownership rejection');
    my $state = operation($directory, 'inspect', {});
    ok(scalar(grep { $_ eq $state->{owner} } @servers), 'retained owner belongs to the competing pair');
    is($state->{phase}, 'installing', 'winning claim is retained');
    return;
};

subtest 'invalid topology and unsafe state are rejected' => sub {
    for my $members ([], [($servers[0]) x 2], ['192.0.2.999'], ['192.0.2.01']) {
        my $directory = "$root/bad-" . ++$sequence;
        rejected(sub { operation($directory, 'prepare', {fingerprint => 'd' x 64, servers => $members}); },
            qr/(?:Invalid|Repeated)/x, 'invalid pool members');
        ok(!-e "$directory/node1.json", 'invalid pool has no published state');
    }
    my ($directory) = fixture();
    chmod(oct('0644'), "$directory/node1.json") == 1 or croak 'Cannot set unsafe fixture mode';
    rejected(sub { operation($directory, 'inspect', {}); }, qr/Unsafe[ ]state[ ]file/x, 'publicly readable pool state');
    chmod(oct('0600'), "$directory/node1.json") == 1 or croak 'Cannot restore fixture mode';
    return;
};

done_testing();
