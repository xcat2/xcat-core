#!/usr/bin/env perl
#
# The install monitor serves every installing node. It must not make one node wait for another.
#
# do_installm_service() used to accept a connection, resolve the peer to a node and dispatch the
# request in line. While it dispatched, nothing else was accepted, so a node whose 'nodeset
# next' takes three seconds cost every other node in the cluster three seconds, and a plugin
# that ended the process took the monitor with it.
#
# Each connection now has a handler process of its own. Requests for one node keep the order
# they arrived in, and the parent owns that order: it holds the later connections and forks the
# next one when it reaps the handler ahead of it. A handler that dies therefore cannot release
# the one behind it early.
#
# xcatd cannot be loaded here -- it needs the database, SSL, the plugin tree and /var/run/xcat,
# and it starts serving at the bottom of the file. So do_installm_service is lifted out of the
# program text and run in a scratch package against stand-in plugins, on a port of its own. The
# clients are real TCP clients and the times are wall-clock. die if the lift stops matching, so
# this fails loudly rather than quietly covering nothing.

use strict;
use warnings;

use File::Temp qw(tempdir);
use FindBin;
use IO::Socket::INET;
use POSIX ();
use Socket;
use Test::More;
use Time::HiRes qw(gettimeofday sleep time);

my $XCATD = "$FindBin::Bin/../../xCAT-server/sbin/xcatd";
die "xcatd not found at $XCATD\n" unless -r $XCATD;

my $SLOW   = 3;                                  # seconds one node's request spends in its plugin
my $SCRATCH = tempdir(CLEANUP => 1);
# One file per case. A handler left over from an earlier case outlives the monitor that forked
# it, and would otherwise append to the case that is running now.
my $EVENTS = "$SCRATCH/events";

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
my $reaper = lift_sub('reap_installm_kids')
  or die "xcatd no longer defines reap_installm_kids";
my $dequeue = lift_sub('dequeue_installm_request')
  or die "xcatd no longer defines dequeue_installm_request";

# Settings the lifted routine reads from file-scope variables xcatd declares but this file does
# not lift. Read the defaults out of the source, so a rename fails here instead of silently
# leaving the monitor with an undefined limit, no drain, or the host's pid file.
my ($MAXKIDS) = $src =~ /^my \s+ \$installm_maxkids \s* = \s* (\d+) ;/mx;
$MAXKIDS or die "xcatd no longer declares \$installm_maxkids";
my ($DRAIN) = $src =~ /^my \s+ \$installm_drain_seconds \s* = \s* (\d+) ;/mx;
$DRAIN or die "xcatd no longer declares \$installm_drain_seconds";
my ($PIDFILE) = $src =~ /^my \s+ \$installm_pidfile \s* = \s* "([^"]+)" ;/mx;
$PIDFILE or die "xcatd no longer declares \$installm_pidfile";

is($PIDFILE, '/var/run/xcat/installservice.pid',
    'the monitor still claims the pid file xcatd and its restart handshake use');

# One variable, so pointing it at the scratch tree below redirects the whole routine. A path
# written out again inside the routine would reach the host file whatever this test sets.
unlike($service, qr{/var/run/},
    'the monitor reaches its pid file only through $installm_pidfile');

# The monitor writes a pid file. Point it at the scratch tree: the live monitor's file is how a
# restarting xcatd tells the running one to let go of the port, and a test that runs as root
# would otherwise leave this process's pid in it.
my $SCRATCH_PIDFILE = "$SCRATCH/installservice.pid";
my @HOST_PIDFILE    = stat($PIDFILE);

# Every test client connects from 127.0.0.1, so the monitor's own reverse lookup cannot tell
# them apart. Name them in accept order instead.
our @PEER_QUEUE;

# Each entry answers one xfork: true forks, false fails. Empty means fork normally. A case sets
# it before the monitor starts, so the monitor's fork-failure fallback can be exercised.
our @FORK_PLAN;
BEGIN { *CORE::GLOBAL::gethostbyaddr = sub { return (shift(@main::PEER_QUEUE) || 'unknown', '') } }

# Whole microseconds. A %.3f stamp rounds, so an event can be recorded at a time LATER than the
# moment it was taken -- and an assertion that the event precedes a reading taken after it then
# fails on the rounding instead of on the order. gettimeofday rounds nothing.
sub now_us {
    my ($seconds, $micros) = gettimeofday();
    return $seconds * 1_000_000 + $micros;
}

# One line per plugin entry and exit, appended by whichever process is running it.
sub note_event {
    my ($what) = @_;
    open my $fh, '>>', $EVENTS or return;
    printf {$fh} "%s %d\n", $what, now_us();
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

# The index of the first event whose text matches, or -1.
sub event_index {
    my ($want) = @_;
    my @all = events();
    for my $i (0 .. $#all) {
        return $i if $all[$i] =~ /^\Q$want\E /;
    }
    return -1;
}

sub event_time {
    my ($want) = @_;
    my $i = event_index($want);
    return undef if $i < 0;
    my @all = events();
    my ($t) = $all[$i] =~ /\s(\d+)$/;
    return $t;
}

# Wait for an event, up to $limit seconds.
sub wait_for_event {
    my ($want, $limit) = @_;
    my $until = time() + ($limit || 10);
    while (time() < $until) {
        return 1 if event_index($want) >= 0;
        sleep 0.05;
    }
    return 0;
}

{
    my $scratch = join "\n",
      'package t::installm;',
      'no strict;',
      'no warnings;',
      'use Fcntl qw/:DEFAULT :flock/;',
      'use File::Path qw(mkpath);',
      'use IO::Socket::INET;',
      'use POSIX qw(WNOHANG :errno_h);',
      'use Socket;',
      'use Time::HiRes qw(sleep time);',
      'sub yield { }',
      'sub build_response { }',
      'sub fd_retrieve { return \"" }',
      'sub xexit { while (wait() > 0) { } POSIX::_exit($_[0] || 0) }',
      'sub noderange { return $_[0] }',
      # The stand-in decides what to do from the node and from the request argument, so several
      # requests for ONE node can behave differently: one slow, one fatal, one immediate.
      'sub plugin_command {',
      '    my ($request) = @_;',
      '    my $node = $request->{node}->[0] || $request->{_xcat_clienthost}->[0] || q{unknown};',
      '    my $arg  = ref($request->{arg}) ? ($request->{arg}->[0] || q{}) : q{};',
      '    main::note_event("start $node $arg");',
      '    POSIX::_exit(9) if $node eq q{diesnode} or $arg eq q{dieplease};',
      '    sleep ' . $SLOW . ' if $node =~ /^slow/ or $arg eq q{slow};',
      '    main::note_event("end $node $arg");',
      '    return { data => [] };',
      '}',
      $reaper,
      $dequeue,
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
    *xCAT::Utils::xfork                 = sub {
        if (@main::FORK_PLAN) { return undef unless shift @main::FORK_PLAN }
        return fork();
    };
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
    $t::installm::installm_maxkids       = $maxkids;
    $t::installm::installm_drain_seconds = $DRAIN;
    $t::installm::installm_pidfile       = $SCRATCH_PIDFILE;
    $t::installm::sport                  = $port;
    $t::installm::quit                   = 0;
    $t::installm::inet6support           = 0;
    $t::installm::rescanrselect          = t::rescan->new();
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

sub open_monitor {
    my ($port, @peers) = @_;
    my $pid = start_monitor($port, $MAXKIDS, @peers);
    my $up  = talk_to($port, 'installmonitor', 200)
      or do { kill 'KILL', $pid; die "the lifted monitor never bound port $port" };
    close $up;
    return $pid;
}

sub stop_monitor {
    my ($pid) = @_;
    kill 'KILL', $pid;
    waitpid($pid, 0);
    return;
}

# --- one node's slow request must not delay another node ----------------------

{
    $EVENTS = "$SCRATCH/events-slow-vs-other";
    my $port = free_port();
    my $mon  = open_monitor($port, qw(portprobe slownode othernode));

    my $first = talk_to($port, 'next');
    ok($first, 'the monitor accepted the first connection');
    wait_for_event('start slownode next', 10)
      or diag('the first request never reached its plugin');

    my $t0      = time();
    my $second  = talk_to($port, 'installstatus booted');
    my $greeting = $second ? scalar <$second> : undef;
    my $waited   = time() - $t0;

    is($greeting, "ready\n", 'the monitor greeted the second node');
    cmp_ok($waited, '<', 1,
        sprintf('a second node is greeted while the first is in its plugin (waited %.3fs)', $waited))
      or diag('the monitor serialises its nodes, so one slow request costs every node');

    close $first  if $first;
    close $second if $second;
    stop_monitor($mon);
}

# --- requests for one node keep their order, even when a handler dies ---------

{
    $EVENTS = "$SCRATCH/events-order";
    my $port = free_port();
    my $mon  = open_monitor($port, qw(portprobe ordernode ordernode ordernode));

    # Three connections from one node: the first slow, the second fatal to the process serving
    # it, the third immediate. The third must not be served before the first has finished.
    my $one = talk_to($port, 'installstatus slow');
    wait_for_event('start ordernode slow', 10)
      or diag('the first request never reached its plugin');
    my $two   = talk_to($port, 'installstatus dieplease');
    my $three = talk_to($port, 'installstatus last');

    ok(wait_for_event('end ordernode last', 30), 'the third request was served in the end');

    # Wait for both sides of the comparison. An event that has not happened is index -1, and
    # comparing against that would pass whatever the monitor did.
    ok(wait_for_event('end ordernode slow', 30), 'the first request finished');
    my $first_end   = event_index('end ordernode slow');
    my $third_start = event_index('start ordernode last');
    cmp_ok($first_end, '>=', 0, 'the first request is recorded as finished');
    cmp_ok($third_start, '>=', 0, 'the third request is recorded as started');
    cmp_ok($third_start, '>', $first_end,
        'the last request for a node starts only after the first one finished')
      or diag('a handler that died released the request behind it, so the order was lost');
    cmp_ok(event_index('start ordernode dieplease'), '>=', 0,
        'the request whose handler died did run');

    close $_ for grep { $_ } $one, $two, $three;
    stop_monitor($mon);
}

# --- a queued connection whose client goes away keeps the order ---------------

# One request runs for a node and two more are queued for it. The client of the middle one gives
# up. The parent holds queued connections unread, so dropping one must not let the request
# behind it overtake the request that is still running.
{
    $EVENTS = "$SCRATCH/events-abandoned";
    my $port = free_port();
    my $mon  = open_monitor($port, qw(portprobe gonenode gonenode gonenode));

    my $one = talk_to($port, 'installstatus slow');
    wait_for_event('start gonenode slow', 10)
      or diag('the first request never reached its plugin');
    my $two   = talk_to($port, 'installstatus middle');
    my $three = talk_to($port, 'installstatus last');
    close $two;
    $two = undef;

    ok(wait_for_event('end gonenode last', 30),
        'the request behind the abandoned one was served in the end');
    ok(wait_for_event('end gonenode slow', 30), 'the running request finished');
    my $running_end = event_index('end gonenode slow');
    my $last_start  = event_index('start gonenode last');
    cmp_ok($running_end, '>=', 0, 'the running request is recorded as finished');
    cmp_ok($last_start,  '>=', 0, 'the request behind the abandoned one is recorded as started');
    cmp_ok($last_start, '>', $running_end,
        'an abandoned queued connection does not release the request behind it')
      or diag('a client that gave up let a later request for the node overtake the running one');

    close $_ for grep { $_ } $one, $three;
    stop_monitor($mon);
}

# --- the fork-failure fallback answers in line, in order ----------------------

# A monitor that cannot fork answers the node itself. The request must be answered rather than
# dropped, and the node's next request must wait for that answer.
{
    $EVENTS = "$SCRATCH/events-nofork";
    my $port = free_port();
    @FORK_PLAN = (1, 0);    # the port probe gets a handler; the first real request does not
    my $mon = open_monitor($port, qw(portprobe forknode forknode));
    @FORK_PLAN = ();

    my $inline = talk_to($port, 'installstatus slow');
    ok(wait_for_event('start forknode slow', 20),
        'the monitor answered the request in line when it could not fork')
      or diag('a monitor that cannot fork drops the request instead of answering it itself');
    my $after = talk_to($port, 'installstatus after');

    ok(wait_for_event('end forknode after', 30), 'the next request for the node was served');
    my $inline_end  = event_index('end forknode slow');
    my $after_start = event_index('start forknode after');
    cmp_ok($inline_end, '>=', 0, 'the in-line request is recorded as finished');
    cmp_ok($after_start, '>', $inline_end,
        'the request after an in-line one starts only once the in-line one has finished')
      or diag('the fork-failure fallback released the next request before its own had finished');

    close $_ for grep { $_ } $inline, $after;
    stop_monitor($mon);
}

# --- a handler that dies must not take the monitor with it --------------------

{
    $EVENTS = "$SCRATCH/events-dies";
    my $port = free_port();
    my $mon  = open_monitor($port, qw(portprobe diesnode lastnode));

    my $dies = talk_to($port, 'installstatus booted');
    if ($dies) { scalar <$dies>; }
    sleep 0.5;

    my $after = talk_to($port, 'installstatus booted');
    my $still = $after ? scalar <$after> : undef;
    is($still, "ready\n", 'the monitor still serves nodes after a handler died')
      or diag('the request that killed the process serving it killed the whole install monitor');

    close $_ for grep { $_ } $dies, $after;
    stop_monitor($mon);
}

# --- the answer to a destiny advance follows the advance ----------------------

{
    $EVENTS = "$SCRATCH/events-advance";
    my $port = free_port();
    my $mon  = open_monitor($port, qw(portprobe slownode));

    my $c = talk_to($port, 'next');
    ok($c, 'the monitor accepted the destiny advance');
    my $ready = $c ? scalar <$c> : undef;
    is($ready, "ready\n", 'the greeting comes first');
    my $done    = $c ? scalar <$c> : undef;
    my $done_at = now_us();
    is($done, "done\n", 'the advance is answered');

    ok(wait_for_event('end slownode next', 30), 'the advance reached its plugin');
    my $end_at = event_time('end slownode next');
    cmp_ok($done_at, '>=', ($end_at || 0),
        'the node is released only after the destiny advance finished')
      or diag('the node is told to carry on before its boot target has been switched');

    close $c if $c;
    stop_monitor($mon);
}

# --- a request accepted before the stand-down is finished, not abandoned ------

{
    $EVENTS = "$SCRATCH/events-stand-down";
    my $port = free_port();
    my $mon  = open_monitor($port, qw(portprobe slownode));

    my $c = talk_to($port, 'next');
    ok($c, 'the monitor accepted the request');
    wait_for_event('start slownode next', 10)
      or diag('the request never reached its plugin');

    kill 'USR2', $mon;    # what xcatd sends the monitor when it is told to stop

    my $exited_at;
    my $until = time() + 30;
    while (time() < $until) {
        if (waitpid($mon, POSIX::WNOHANG()) == $mon) { $exited_at = now_us(); last }
        sleep 0.05;
    }
    ok(defined $exited_at, 'the monitor stood down');

    ok(wait_for_event('end slownode next', 30), 'the request in flight finished');
    my $end_at = event_time('end slownode next');
    cmp_ok(($exited_at || 0), '>=', ($end_at || 0),
        'the monitor waits for the request it accepted before it exits')
      or diag('the handlers are orphaned, and systemd kills whatever is left at the timeout');

    close $c if $c;
    stop_monitor($mon) unless defined $exited_at;
}

# --- the handlers must not multiply without bound ----------------------------

# A monitor allowed one handler at a time. Its second node must wait, because a thousand nodes
# netbooting must not become a thousand handlers; the rest of them wait in the listen backlog.
# On a monitor that forks without a limit this wait is gone.
{
    $EVENTS = "$SCRATCH/events-cap";
    my $port = free_port();
    my $mon  = start_monitor($port, 1, qw(portprobe slowcap nextcap));
    my $up   = talk_to($port, 'installmonitor', 200)
      or do { kill 'KILL', $mon; die "the capped monitor never bound port $port" };
    close $up;

    my $busy = talk_to($port, 'installstatus booted');
    if ($busy) { scalar <$busy>; scalar <$busy>; }   # ready, done -- its handler is the only one
    my $c0            = time();
    my $queued        = talk_to($port, 'installstatus booted');
    my $hello         = $queued ? scalar <$queued> : undef;
    my $queued_waited = time() - $c0;

    is($hello, "ready\n", 'the capped monitor served the queued node in the end');
    cmp_ok($queued_waited, '>=', 1,
        sprintf('a monitor at its handler limit leaves the next node in the backlog (waited %.3fs)',
            $queued_waited))
      or diag('the monitor accepted past its limit, so a netbooting cluster forks a handler per node');

    close $_ for grep { $_ } $busy, $queued;
    stop_monitor($mon);
}

# --- the per-node queue does not outlive the requests in it -------------------

# An empty queue entry for every node ever served is a leak no behavioural assertion catches,
# so the parent's own bookkeeping is checked directly.
{
    no warnings 'once';
    %t::installm::installm_busy  = ();
    %t::installm::installm_queue = (n1 => [ [ 'conn', '10.0.0.1' ] ]);

    my ($node, $conn, $peer) = t::installm::dequeue_installm_request();
    is($node, 'n1',         'the queued connection is taken for its own node');
    is($conn, 'conn',       'the connection comes back with it');
    is($peer, '10.0.0.1',   'and the peer address it was accepted from');
    is_deeply([ keys %t::installm::installm_queue ], [],
        'the queue entry is removed when it empties');

    %t::installm::installm_busy  = (n2 => 4242);
    %t::installm::installm_queue = ();
    my @none = t::installm::dequeue_installm_request();
    is(scalar @none, 0, 'a node with a live handler yields nothing to dequeue');
    is_deeply([ keys %t::installm::installm_queue ], [],
        'and asking about it creates no queue entry');
}

# The host's pid file is how a restarting xcatd tells the running monitor to let go of the
# port. Nothing here may have touched it.
{
    my @now = stat($PIDFILE);
    if (!@HOST_PIDFILE and !@now) {
        pass('the host pid file was absent before and after');
    } elsif (@HOST_PIDFILE and @now) {
        is("$now[7] $now[9]", "$HOST_PIDFILE[7] $HOST_PIDFILE[9]",
            'the host pid file is the size and age it was before');
    } else {
        fail('the host pid file was created or removed by this test');
    }
}

ok(-e $SCRATCH_PIDFILE, 'the monitor claimed the scratch pid file instead')
  or diag('the redirection is not reached, so the assertion above proves nothing');

done_testing();
