#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl", "$FindBin::Bin/../../perl-xCAT";
use File::Temp qw(tempdir);
use Errno qw(EAGAIN);
use IO::Select;
use IO::Socket::INET;
use Socket qw(AF_UNIX SOCK_STREAM PF_UNSPEC);
use Test::More;
use xCAT::FreeBSDInstall;

BEGIN {
    $INC{'xCAT/Table.pm'} = __FILE__;
    $INC{'xCAT/NetworkUtils.pm'} = __FILE__;
}
{
    package xCAT::NetworkUtils;
    our $address = '192.0.2.10';
    sub clearcache { return; }
    sub getipaddr { return $address; }
}
{
    package xCAT::Table;
    our (%entries, $unavailable);
    sub new { return undef if $unavailable; return bless { name => $_[1] }, $_[0]; }
    sub getNodeAttribs { return $entries{$_[0]->{name}}{$_[1]}; }
    sub close { return; }
}

my $temporary = tempdir(CLEANUP => 1);
my $sequence = 0;
my $attempt = 'b' x 32;

sub fixture {
    my $directory = "$temporary/state-" . ++$sequence;
    my $generation = xCAT::FreeBSDInstall::prepare('node1', 'a' x 64, directory => $directory);
    %xCAT::Table::entries = (chain => { node1 => { currstate => 'install' } },
        nodelist => { node1 => { status => 'booting' } });
    $xCAT::Table::unavailable = 0;
    return ($directory, $generation);
}

sub dispatch {
    my ($request) = @_;
    my ($command, $node, $argument) = map { $request->{$_}[0] } qw(command node arg);
    if ($command eq 'nodeset') {
        $xCAT::Table::entries{chain}{$node}{currstate} = $argument;
    } elsif ($command eq 'updatenodestat') {
        $xCAT::Table::entries{nodelist}{$node}{status} = $argument;
    } else {
        die "Unexpected command $command\n";
    }
    return {};
}

sub status {
    my ($directory, $generation, $phase, $run, $peer) = @_;
    $run ||= \&dispatch;
    $peer = '192.0.2.10' unless defined($peer);
    return xCAT::FreeBSDInstall::handle_status('node1', $peer,
        "freebsd-install-v1 $generation $attempt $phase\n", $run, directory => $directory);
}

sub rejected {
    my ($code, $pattern, $label) = @_;
    my $ok = eval { $code->(); 1 };
    ok(!$ok, "$label fails");
    like($@, $pattern, "$label reports the reason");
}

my ($directory, $generation) = fixture();
my @requests;
my $run = sub { push @requests, $_[0]; return dispatch($_[0]); };
is(status($directory, $generation, 'begin', $run), "freebsd-install-v1 $generation begin ok\n",
    'begin acknowledges a confirmed installing status');
is(status($directory, $generation, 'complete', $run), "freebsd-install-v1 $generation complete ok\n",
    'completion acknowledges confirmed local boot and installed status');
is(status($directory, $generation, 'booted', $run, '::ffff:192.0.2.10'),
    "freebsd-install-v1 $generation booted ok\n", 'IPv4-mapped source can report first boot');
is_deeply(\@requests, [
    {command => ['updatenodestat'], node => ['node1'], arg => ['installing']},
    {command => ['nodeset'], node => ['node1'], arg => ['boot']},
    {command => ['updatenodestat'], node => ['node1'], arg => ['installed']},
    {command => ['updatenodestat'], node => ['node1'], arg => ['booted']},
], 'completion changes boot policy before installed status');
status($directory, $generation, 'booted', sub { die 'must not run'; });
status($directory, $generation, 'complete', sub { die 'must not run'; });
is($xCAT::Table::entries{nodelist}{node1}{status}, 'booted', 'duplicate completion preserves first-boot status');

for my $peer ('192.0.2.11', '', 'node1', '2001:db8::10') {
    my ($root, $token) = fixture();
    rejected(sub { status($root, $token, 'begin', sub { die 'must not run'; }, $peer); },
        qr/Unexpected installation client/, 'incorrect source');
    is(xCAT::FreeBSDInstall::state('node1', directory => $root)->{phase}, 'prepared',
        'source mismatch leaves the generation unclaimed');
}
{
    my ($root, $token) = fixture();
    local $xCAT::NetworkUtils::address = 0;
    rejected(sub { status($root, $token, 'begin'); }, qr/Unexpected installation client/, 'unresolved node address');
}

for my $failure (
    ['top-level error', {error => ['cannot write']}],
    ['top-level error code', {errorcode => [0, 1]}],
    ['node error', {node => [{name => ['node1'], error => ['cannot write']}]}],
    ['later node error', {node => [{name => ['node1']}, {name => ['node1'], errorcode => [1]}]}],
    ['nested response error', {xcatresponse => [{node => [{errorcode => [1]}]}]}],
    ['missing response', undef],
    ['invalid response', []],
    ['invalid node record', {node => [undef, {errorcode => [1]}]}],
    ['invalid node container', {node => {errorcode => [1]}}],
) {
    my ($root, $token) = fixture();
    status($root, $token, 'begin');
    my @seen;
    rejected(sub { status($root, $token, 'complete', sub {
        push @seen, $_[0]->{command}[0];
        return $failure->[1];
    }); }, qr/failed|response/, $failure->[0]);
    is_deeply(\@seen, ['nodeset'], 'failed boot command prevents installed status');
    is(xCAT::FreeBSDInstall::state('node1', directory => $root)->{phase}, 'completing',
        'boot command error leaves completion retryable');
    status($root, $token, 'complete');
    is(xCAT::FreeBSDInstall::state('node1', directory => $root)->{phase}, 'installed',
        'retry after command recovery completes');
}

for my $phase (qw(begin complete booted failed)) {
    my ($root, $token) = fixture();
    status($root, $token, 'begin') if $phase eq 'complete' || $phase eq 'booted';
    status($root, $token, 'complete') if $phase eq 'booted';
    rejected(sub { status($root, $token, $phase, sub {
        return dispatch($_[0]) if $_[0]->{command}[0] eq 'nodeset';
        return {errorcode => [1]};
    }); }, qr/updatenodestat failed/, "$phase status command error");
    is(xCAT::FreeBSDInstall::state('node1', directory => $root)->{phase},
        {begin => 'installing', complete => 'completing', booted => 'installed', failed => 'failed'}->{$phase},
        "$phase status error does not commit successful completion");
}

for my $missed (qw(nodeset updatenodestat)) {
    my ($root, $token) = fixture();
    status($root, $token, 'begin');
    my @seen;
    rejected(sub { status($root, $token, 'complete', sub {
        push @seen, $_[0]->{command}[0];
        return {} if $_[0]->{command}[0] eq $missed;
        return dispatch($_[0]);
    }); }, qr/was not updated/, "$missed silent write failure");
    is(scalar(@seen), $missed eq 'nodeset' ? 1 : 2, 'failed readback stops the command sequence');
    is(xCAT::FreeBSDInstall::state('node1', directory => $root)->{phase}, 'completing',
        'readback failure remains retryable');
}
{
    my ($root, $token) = fixture();
    local $xCAT::Table::unavailable = 1;
    rejected(sub { status($root, $token, 'begin', sub { die 'must not dispatch'; }); },
        qr/Cannot open node resources/, 'database unavailable');
    is(xCAT::FreeBSDInstall::state('node1', directory => $root)->{phase}, 'prepared',
        'database failure cannot claim installation ownership');
}
{
    my ($root, $token) = fixture();
    rejected(sub { status($root, $token, 'begin', sub { die "dispatcher failed\n"; }); },
        qr/dispatcher failed/, 'dispatcher exception');
}

{
    my ($root, $token) = fixture();
    my %tokens = (node1 => $token);
    for my $node (qw(node2 node3)) {
        $tokens{$node} = xCAT::FreeBSDInstall::prepare($node, 'a' x 64, directory => $root);
    }
    for my $node (keys %tokens) {
        xCAT::FreeBSDInstall::transition($node, "freebsd-install-v1 $tokens{$node} $attempt begin\n",
            sub {}, directory => $root);
    }
    pipe(my $entered, my $enter) or die $!;
    pipe(my $release, my $resume) or die $!;
    pipe(my $rescan_read, my $rescan_write) or die $!;
    my $listener = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => 0,
        Listen => 1, ReuseAddr => 1) or die $!;
    my $port = $listener->sockport;
    $enter->autoflush(1);
    $resume->autoflush(1);
    my @workers;
    local $SIG{ALRM} = sub { kill 'KILL', @workers; die "Status worker test timed out\n"; };
    alarm(20);
    my $launch = sub {
        my ($node, $action, $message) = @_;
        socketpair(my $client, my $server, AF_UNIX, SOCK_STREAM, PF_UNSPEC) or die $!;
        $server->autoflush(1);
        print {$server} "ready\n";
        my $pid = xCAT::FreeBSDInstall::start_status_worker($node, '192.0.2.10',
            $message || "freebsd-install-v1 $tokens{$node} $attempt complete\n", $server, $action,
            directory => $root, limit => 2,
            cleanup => sub { close($client); close($listener); close($rescan_read); close($rescan_write); },
            log => sub {
                open(my $log, '>>', "$root/worker-errors") or die $!;
                print {$log} $_[0];
                close($log);
            });
        push @workers, $pid if $pid;
        return ($pid, $client);
    };
    my $slow = sub {
        if ($_[0]->{command}[0] eq 'nodeset') {
            print {$enter} "entered\n";
            die 'missing worker release' unless sysread($release, my $byte, 1);
        }
        return dispatch($_[0]);
    };
    my ($first, $first_client) = $launch->('node1', $slow);
    ok($first > 0, 'slow status action runs in a child');
    is(scalar(<$entered>), "entered\n", 'the child entered the actual status action');
    my ($duplicate, $duplicate_client) = $launch->('node1', \&dispatch);
    is($duplicate, 0, 'one node cannot consume multiple workers');
    is(do { local $/; <$duplicate_client> }, "ready\n", 'busy responses never acknowledge an unperformed transition');
    close($duplicate_client);
    my ($second, $second_client) = $launch->('node2', $slow);
    ok($second > 0, 'another node starts while the first is blocked');
    my @ready = IO::Select->new($entered)->can_read(2);
    ok(scalar(@ready), 'the second action executes before the first is released');
    is(scalar(<$entered>), "entered\n", 'the second action executes concurrently') if @ready;
    close($listener);
    close($rescan_write);
    my $replacement = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => $port,
        Listen => 1, ReuseAddr => 1);
    ok($replacement, 'active workers release the inherited listening socket');
    close($replacement) if $replacement;
    my @eof = IO::Select->new($rescan_read)->can_read(2);
    ok(@eof && sysread($rescan_read, my $byte, 1) == 0,
        'active workers release inherited rescan writers');
    close($rescan_read);
    my ($full, $full_client) = $launch->('node3', \&dispatch);
    is($full, 0, 'the configured worker limit bounds concurrency');
    is(do { local $/; <$full_client> }, "ready\n", 'pool saturation does not send a success acknowledgment');
    close($full_client);
    print {$resume} 'RR';
    for my $entry (['node1', $first, $first_client], ['node2', $second, $second_client]) {
        my ($node, $pid, $client) = @$entry;
        next unless $pid;
        is(do { local $/; <$client> }, "ready\nfreebsd-install-v1 $tokens{$node} complete ok\n",
            'the acknowledgment follows the completed action');
        close($client);
        waitpid($pid, 0);
        is($? >> 8, 0, 'the status worker exits successfully');
    }
    my ($third, $third_client) = $launch->('node3', \&dispatch);
    ok($third > 0, 'reaped worker slots are reusable');
    is(do { local $/; <$third_client> }, "ready\nfreebsd-install-v1 $tokens{node3} complete ok\n",
        'a retried status is acknowledged after saturation clears');
    close($third_client);
    waitpid($third, 0);
    my ($bad, $bad_client) = $launch->('node3', \&dispatch, "freebsd-install-v1 malformed\n");
    is(do { local $/; <$bad_client> }, "ready\n", 'a rejected protocol request receives no success acknowledgment');
    close($bad_client);
    waitpid($bad, 0);
    is($? >> 8, 1, 'a rejected worker exits with failure');
    open(my $log, '<', "$root/worker-errors") or die $!;
    like(do { local $/; <$log> }, qr/Invalid installation status/, 'the expected rejection is sent to the status logger');
    close($log);
    alarm(0);
}

for my $signal (qw(ALRM KILL)) {
    my ($root, $token) = fixture();
    status($root, $token, 'begin');
    pipe(my $entered, my $enter) or die $!;
    pipe(my $blocked, my $release) or die $!;
    $enter->autoflush(1);
    socketpair(my $client, my $server, AF_UNIX, SOCK_STREAM, PF_UNSPEC) or die $!;
    $server->autoflush(1);
    my $pid = xCAT::FreeBSDInstall::start_status_worker('node1', '192.0.2.10',
        "freebsd-install-v1 $token $attempt complete\n", $server,
        sub { print {$enter} "entered\n"; sysread($blocked, my $byte, 1); return dispatch($_[0]); },
        directory => $root, limit => 1, cleanup => sub { close($client); }, log => sub {});
    local $SIG{ALRM} = sub { kill 'KILL', $pid; die "Interrupted worker test timed out\n"; };
    alarm(10);
    is(scalar(<$entered>), "entered\n", "$signal fixture reaches the real completion action");
    kill($signal, $pid) == 1 or die $!;
    is(do { local $/; <$client> } || '', '', "$signal interruption sends no completion acknowledgment");
    close($client);
    waitpid($pid, 0);
    is($signal eq 'ALRM' ? $? >> 8 : $? & 127, $signal eq 'ALRM' ? 1 : 9,
        "$signal terminates the interrupted worker");
    is(xCAT::FreeBSDInstall::state('node1', directory => $root)->{phase}, 'completing',
        "$signal leaves the durable transition retryable");
    socketpair(my $retry_client, my $retry_server, AF_UNIX, SOCK_STREAM, PF_UNSPEC) or die $!;
    $retry_server->autoflush(1);
    my $retry = xCAT::FreeBSDInstall::start_status_worker('node1', '192.0.2.10',
        "freebsd-install-v1 $token $attempt complete\n", $retry_server, \&dispatch,
        directory => $root, limit => 1, cleanup => sub { close($retry_client); }, log => sub {});
    ok($retry > 0, "$signal does not leak the node or worker slot");
    is(do { local $/; <$retry_client> }, "freebsd-install-v1 $token complete ok\n",
        "$signal retry acknowledges the completed action");
    close($retry_client);
    waitpid($retry, 0);
    is($? >> 8, 0, "$signal retry worker exits successfully");
    alarm(0);
}

{
    my ($root, $token) = fixture();
    socketpair(my $client, my $server, AF_UNIX, SOCK_STREAM, PF_UNSPEC) or die $!;
    my (@errors, $actions, $cleanups);
    $actions = $cleanups = 0;
    my $pid;
    {
        no warnings qw(once redefine);
        local *xCAT::Utils::xfork = sub { $! = EAGAIN; return; };
        $pid = xCAT::FreeBSDInstall::start_status_worker('node1', '192.0.2.10',
            "freebsd-install-v1 $token $attempt begin\n", $server,
            sub { $actions++; }, directory => $root,
            cleanup => sub { $cleanups++; }, log => sub { push @errors, $_[0]; });
    }
    is($pid, 0, 'a failed fork returns a retryable response without throwing');
    is(do { local $/; <$client> } || '', '', 'a failed fork closes the connection without acknowledgment');
    close($client);
    is($actions, 0, 'a failed fork cannot execute status actions');
    is($cleanups, 0, 'a failed fork does not close parent-owned listener descriptors');
    like($errors[0], qr/^Cannot start status worker:/, 'a failed fork uses the FreeBSD status logger');
    is(xCAT::FreeBSDInstall::state('node1', directory => $root)->{phase}, 'prepared',
        'a failed fork leaves installation ownership unchanged');
}

subtest 'status worker deadlines' => sub {
    for my $case (
        ['legacy', 'freebsd-install-v1 ' . ('a' x 32) . " $attempt begin\n", 60],
        ['boot delivery', 'freebsd-install-postscripts-v1 ' . ('a' x 32) . " $attempt " . ('c' x 64) . "\n", 7200],
        ['malformed boot', "freebsd-install-postscripts-v1 malformed\n", 60],
    ) {
        my ($label, $message, $bound) = @$case;
        socketpair(my $client, my $server, AF_UNIX, SOCK_STREAM, PF_UNSPEC) or die $!;
        pipe(my $reader, my $writer) or die $!;
        my $pid = xCAT::FreeBSDInstall::start_status_worker('deadline', '192.0.2.10',
            $message, $server, \&dispatch,
            cleanup => sub {
                close($client);
                close($reader);
                print {$writer} alarm(0), "\n";
                close($writer);
                die "Deadline observed before dispatch\n";
            }, log => sub {});
        close($writer);
        ok($pid > 0, "$label runs in the actual status worker");
        my $remaining = <$reader>;
        close($reader);
        ok(defined($remaining) && $remaining >= $bound - 5 && $remaining <= $bound,
            "$label installs its bounded alarm");
        is(do { local $/; <$client> } || '', '', "$label observation does not acknowledge an action");
        close($client);
        waitpid($pid, 0);
        is($? >> 8, 1, "$label observation ends before changing state");
    }
};

done_testing();
