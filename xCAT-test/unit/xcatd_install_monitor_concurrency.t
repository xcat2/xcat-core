#!/usr/bin/env perl
#
# The install monitor serves every installing node. It must not make one node wait for another.
#
# do_installm_service() accepts a connection, resolves the peer to a node and dispatches the
# request. While it dispatches, nothing else is accepted, so a node whose 'nodeset next' takes
# three seconds costs every other node in the cluster three seconds. What the monitor does have
# to keep is the order within one node: a 'nodeset next' and an 'installstatus' for the same
# node write the same chain row, which is why an earlier per-request fork was reverted.
#
# xcatd cannot be loaded here -- it needs the database, SSL, the plugin tree and /var/run/xcat,
# and it starts serving at the bottom of the file. So do_installm_service is lifted out of the
# program text and run in a scratch package against stand-in plugins, on a port of its own. The
# clients are real TCP clients and the times are wall-clock. die if the lift stops matching, so
# this fails loudly rather than quietly covering nothing.

use strict;
use warnings;

use FindBin;
use IO::Socket::INET;
use POSIX ();
use Socket;
use Test::More;
use Time::HiRes qw(sleep time);

my $XCATD = "$FindBin::Bin/../../xCAT-server/sbin/xcatd";
plan skip_all => "xcatd not found at $XCATD" unless -r $XCATD;

my $SLOW    = 3;    # seconds one node's request spends in its plugin
my $EVENTS  = "/tmp/xcatd-installm-events.$$";
my $PIDFILE = '/var/run/xcat/installservice.pid';

my $src = do {
    open my $fh, '<', $XCATD or die "cannot read $XCATD: $!";
    local $/;
    <$fh>;
};

# A named sub in xcatd, from "sub name {" to the closing brace in the first column.
sub lift_sub {
    my ($name) = @_;
    my ($body) = $src =~ /^(sub \s+ \Q$name\E \s* \{ .*? ^ \} )/msx;
    return $body;
}

my $service = lift_sub('do_installm_service')
  or die "cannot lift do_installm_service out of xcatd -- the lift needs updating";

# reap_installm_kids is what this test asks xcatd to grow. Supply a stand-in when it is not
# there yet, so the lifted routine still compiles and the assertions below report a monitor
# that serializes its nodes -- which is the defect -- instead of a compile error.
my $reaper = lift_sub('reap_installm_kids') || 'sub reap_installm_kids { }';

# The limit on live handlers is xcatd's, not this test's. Without it the scratch package holds
# an undefined limit, which reads as zero and stops the monitor accepting anything.
my ($MAXKIDS) = $src =~ /^my \$installm_maxkids \s* = \s* (\d+) ;/mx;
$MAXKIDS ||= 64;

# Every test client connects from 127.0.0.1, so the monitor's own reverse lookup cannot tell
# them apart. Name them in accept order instead: one connection opens the port, the next two
# are one node, then a second node, then a node whose plugin kills the process serving it, then
# a last node to ask whether the monitor is still there.
our @PEER_QUEUE = qw(portprobe slownode slownode othernode diesnode lastnode);
BEGIN { *CORE::GLOBAL::gethostbyaddr = sub { return (shift(@main::PEER_QUEUE) || 'unknown', '') } }

# One line per plugin entry and exit, appended by whichever process is running it.
sub note_event {
    my ($what) = @_;
    open my $fh, '>>', $EVENTS or return;
    printf {$fh} "%s %.3f\n", $what, time();
    close $fh;
    return;
}

sub events {
    open my $fh, '<', $EVENTS or return ();
    my @lines = <$fh>;
    close $fh;
    chomp @lines;
    return @lines;
}

{
    my $scratch = join "\n",
      'package t::installm;',
      'no strict;',
      'no warnings;',
      'use Fcntl qw/:DEFAULT :flock/;',
      'use File::Path qw(mkpath);',
      'use IO::Socket::INET;',
      'use POSIX qw(WNOHANG);',
      'use Socket;',
      'use Time::HiRes qw(sleep time);',
      'sub yield { }',
      'sub build_response { }',
      'sub fd_retrieve { return \"" }',
      'sub xexit { while (wait() > 0) { } POSIX::_exit($_[0] || 0) }',
      'sub noderange { return $_[0] }',
      'sub plugin_command {',
      '    my ($request) = @_;',
      '    my $node = $request->{node}->[0] || $request->{_xcat_clienthost}->[0] || q{unknown};',
      '    main::note_event("start $node");',
      '    POSIX::_exit(9) if $node eq q{diesnode};',
      '    sleep ' . $SLOW . ' if $node =~ /^slow/;',
      '    main::note_event("end $node");',
      '    return { data => [] };',
      '}',
      $reaper,
      $service,
      '1;';
    eval $scratch or die "cannot compile the lifted install monitor: $@";
}

{
    # Stand-ins for the xCAT modules the lifted routine calls through. None of them can reach a
    # database from here.
    no warnings 'once';
    *xCAT::MsgUtils::trace              = sub { };
    *xCAT::MsgUtils::message            = sub { };
    *xCAT::NetworkUtils::clearcache     = sub { };
    *xCAT::NetworkUtils::getNodeDomains = sub { return {} };
    *xCAT::TableUtils::getTftpDir       = sub { return '/tmp' };
    *xCAT::Utils::xfork                 = sub { return fork() };
    *t::rescan::new                     = sub { return bless {}, shift };
    *t::rescan::can_read                = sub { return () };
}

# A free port: bind one, read it back, release it. The monitor binds it again for itself.
sub free_port {
    my $probe = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => 0,
        Listen => 1, Proto => 'tcp', ReuseAddr => 1)
      or die "cannot find a free port: $!";
    my $port = $probe->sockport();
    close $probe;
    return $port;
}

# Start a monitor of its own on $port, naming its peers in accept order.
sub start_monitor {
    my ($port, $maxkids, @peers) = @_;

    @PEER_QUEUE = @peers;
    my $pid = fork();
    die "cannot fork the monitor: $!" unless defined $pid;
    return $pid if $pid;

    # Detach the monitor and every process it forks from the harness pipe: a lingering child
    # that holds prove's stdout makes a failure look like a hang.
    open STDOUT, '>', '/dev/null';
    open STDERR, '>', '/dev/null';
    no warnings 'once';
    $t::installm::installm_maxkids = $maxkids;
    $t::installm::sport            = $port;
    $t::installm::quit             = 0;
    $t::installm::inet6support     = 0;
    $t::installm::rescanrselect    = t::rescan->new();
    t::installm::do_installm_service();
    POSIX::_exit(0);
}

# Connect, send one request, and return the connection. The first connection to a monitor is
# what tells this test the port is bound, so it is retried.
sub talk_to {
    my ($port, $request, $tries) = @_;

    my $c;
    for (1 .. ($tries || 1)) {
        last if $c = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port,
            Proto => 'tcp', Timeout => 30);
        sleep 0.05;
    }
    return undef unless $c;
    $c->autoflush(1);
    print {$c} "$request\n";
    return $c;
}

my $PORT = free_port();

# The monitor writes its pid file to a fixed path it shares with a real xcatd. Put back
# whatever was there.
my $saved_pidfile;
if (open my $fh, '<', $PIDFILE) { local $/; $saved_pidfile = <$fh>; close $fh; }

my $server = start_monitor($PORT, $MAXKIDS, @PEER_QUEUE);

sub talk_to_monitor { return talk_to($PORT, $_[0]) }

sub cleanup {
    kill 'KILL', $server;
    waitpid($server, 0);
    unlink $EVENTS;
    if (defined $saved_pidfile) {
        if (open my $fh, '>', $PIDFILE) { print {$fh} $saved_pidfile; close $fh; }
    } else {
        unlink $PIDFILE;
    }
    return;
}

# Wait for the monitor to bind. This connection is the 'portprobe' peer.
my $up = talk_to($PORT, 'installmonitor', 200)
  or do { kill 'KILL', $server; die "the lifted monitor never bound port $PORT" };
close $up;

# --- one node's slow request must not delay another node ----------------------

my $first = talk_to_monitor('next');
unless ($first) {
    fail('the monitor accepted the first connection');
    cleanup();
    done_testing();
    exit 0;
}
pass('the monitor accepted the first connection');
scalar <$first>;    # ready
scalar <$first>;    # done -- the request is now in the plugin

my $second = talk_to_monitor('next');    # the same node again
sleep 0.3;                               # let it be accepted before the next node connects

my $t0       = time();
my $other    = talk_to_monitor('next');    # a different node
my $greeting = $other ? scalar <$other> : undef;
my $waited   = time() - $t0;

is($greeting, "ready\n", 'the monitor greeted the second node');
cmp_ok($waited, '<', 1,
    sprintf('a second node is served while the first is busy (waited %.3fs)', $waited))
  or diag(sprintf('the monitor took %.3fs to greet a node that had nothing to do with the'
      . ' %ds request already running, so every installing node waits for the slowest one',
        $waited, $SLOW));

# --- requests for one node must not run at the same time ----------------------

for (1 .. 300) {
    last if scalar(grep { /^end slownode/ } events()) >= 2;
    sleep 0.1;
}
my @ev     = events();
my @starts = sort { $a <=> $b } map { (split ' ')[2] } grep { /^start slownode/ } @ev;
my @ends   = sort { $a <=> $b } map { (split ' ')[2] } grep { /^end slownode/ } @ev;
is(scalar @starts, 2, 'both requests for the busy node ran');
is(scalar @ends,   2, 'and both finished');
SKIP: {
    skip 'the busy node did not run twice', 1 unless @starts == 2 and @ends == 2;
    cmp_ok($starts[1], '>=', $ends[0],
        'the second request for the same node started only after the first finished')
      or diag('two requests for one node ran at the same time; they write the same chain row');
}

# --- a handler that dies must not take the monitor with it --------------------

my $dies = talk_to_monitor('next');
if ($dies) { scalar <$dies>; close $dies; }
sleep 0.5;
my $after = talk_to_monitor('next');
my $still = $after ? scalar <$after> : undef;
is($still, "ready\n", 'the monitor still serves nodes after a handler died')
  or diag('the request that killed the process serving it killed the whole install monitor');

cleanup();

# --- the handlers must not multiply without bound ----------------------------

# A second monitor, allowed one handler at a time. Its second node must wait, because a
# thousand nodes netbooting must not become a thousand children; the rest of them wait in the
# listen backlog. On a monitor that forks without a limit this wait is gone.
my $capped_port = free_port();
my $capped      = start_monitor($capped_port, 1, qw(portprobe slowcap nextcap));
my $capped_up   = talk_to($capped_port, 'installmonitor', 200)
  or do { kill 'KILL', $capped; die "the capped monitor never bound port $capped_port" };
close $capped_up;

my $busy = talk_to($capped_port, 'next');
if ($busy) { scalar <$busy>; scalar <$busy>; }    # ready, done -- its handler is now the only one
my $c0      = time();
my $queued  = talk_to($capped_port, 'next');
my $hello   = $queued ? scalar <$queued> : undef;
my $queued_waited = time() - $c0;

is($hello, "ready\n", 'the capped monitor served the queued node in the end');
cmp_ok($queued_waited, '>=', 1,
    sprintf('a monitor at its handler limit leaves the next node in the backlog (waited %.3fs)',
        $queued_waited))
  or diag('the monitor accepted past its limit, so a netbooting cluster forks a child per node');

kill 'KILL', $capped;
waitpid($capped, 0);

done_testing();
