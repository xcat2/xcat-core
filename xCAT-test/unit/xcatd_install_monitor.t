#!/usr/bin/env perl
#
# Unit test for the two things xcatd itself has to get right about the install monitor --
# the child that listens on xcatiport for node install-status updates and the "next"
# boot-flip request. The pacing of the respawn is covered by xcatd_monitor_respawn.t; this
# file covers the daemon-side code that pacing depends on.
#
#   1. Every SIGCHLD handler that can be installed when the monitor dies has to account for
#      the death. The monitor is forked at startup, while generic_reaper is the handler --
#      ssl_reaper is only installed once the main service loop starts, and generic_reaper
#      comes back whenever connections are throttled. A death reaped by a handler that does
#      not clear $pid_MON leaves the daemon holding a dead pid, so the respawn in the
#      service loop never runs and xcatiport stays dead for the life of the daemon.
#
#   2. The respawned monitor must not carry the parent's other descriptors. It is forked
#      from the middle of the service loop, so besides the SSL listener and the udpctl
#      socket it also inherits the rescanplugins channel and any client connection the
#      parent has accepted but not yet handed to a worker. The monitor serves none of
#      those and outlives every one of them.
#
# xcatd cannot be loaded here: it needs the database, SSL, the plugin tree and
# /var/run/xcat, and it starts serving at the bottom of the file. So the routine and the
# fork block under test are lifted out of the program text and run in a scratch package
# against stand-in handles. BAIL_OUT if a lift stops matching, so this fails loudly rather
# than quietly covering nothing.

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;
use POSIX ();
use Socket;

use xCAT::RespawnUtils;

my $XCATD = "$FindBin::Bin/../../xCAT-server/sbin/xcatd";
plan skip_all => "xcatd not found at $XCATD" unless -r $XCATD;

my $src = do {
    open my $fh, '<', $XCATD or BAIL_OUT("cannot read $XCATD: $!");
    local $/;
    <$fh>;
};

# A named sub in xcatd, from "sub name {" to the closing brace in the first column.
sub lift_sub {
    my ($name) = @_;
    my ($body) = $src =~ /^(sub \s+ \Q$name\E \s* \{ .*? ^ \} )/msx;
    return $body;
}

# --- 1. whichever reaper is installed, a dead monitor is accounted for -------

my %reaper = map { $_ => lift_sub($_) } qw(generic_reaper ssl_reaper);
for my $name (sort keys %reaper) {
    BAIL_OUT("cannot lift $name out of xcatd -- the lift needs updating")
      unless $reaper{$name};
}

# reap_install_monitor is what this test asks xcatd to grow. Lift it when it is there, and
# supply a do-nothing stand-in when it is not, so the reapers still compile and the
# assertions below report a monitor death that went unnoticed -- which is the defect --
# instead of a syntax error.
my $shared = lift_sub('reap_install_monitor') || 'sub reap_install_monitor { }';

{
    my $scratch = join "\n",
      'package t::xcatd;',
      'no strict;',
      'no warnings;',
      'sub yield { }',
      $shared,
      $reaper{generic_reaper},
      $reaper{ssl_reaper},
      '1;';
    eval $scratch or BAIL_OUT("cannot compile the lifted reapers: $@");
}

# Fork a child, let it exit, and hand it to $reaper as the install monitor. Returns the
# pacing state the reaper left behind, or undef when it did not notice the death at all.
sub reap_a_dead_monitor {
    my ($reaper) = @_;

    my $pid = fork();
    BAIL_OUT("cannot fork: $!") unless defined $pid;
    POSIX::_exit(0) unless $pid;

    my $now = time();
    {
        no strict 'refs';
        ${'t::xcatd::pid_MON'}     = $pid;
        ${'t::xcatd::mon_respawn'} = xCAT::RespawnUtils::forked(
            xCAT::RespawnUtils::policy(min_interval => 5, max_interval => 300), $now);
    }

    # Wait for it to be reapable, then run the handler by hand rather than through the
    # signal: what is under test is what the handler does with the death, not delivery.
    local $SIG{CHLD} = 'DEFAULT';
    select(undef, undef, undef, 0.05) for 1 .. 4;

    no strict 'refs';
    &{"t::xcatd::$reaper"}();

    return undef if ${'t::xcatd::pid_MON'};
    return ${'t::xcatd::mon_respawn'};
}

for my $reaper (qw(generic_reaper ssl_reaper)) {
    subtest "$reaper accounts for a dead install monitor" => sub {
        my $pace = reap_a_dead_monitor($reaper);

        ok($pace, "$reaper cleared \$pid_MON, so the service loop can re-fork the monitor")
          or do {
            diag("$reaper reaped the monitor and left \$pid_MON holding its pid;"
                  . " nothing will ever respawn it");
            return;
          };
        ok(!defined $pace->{started_at},
            'the pacing was told the monitor exited, so the next respawn is scheduled');
        cmp_ok($pace->{streak}, '>', 0, 'the death counts towards the backoff');
    };
}

# --- 2. the respawned monitor drops what it inherited ------------------------

# Both supervise() blocks in xcatd: the startup fork and the respawn in the service loop.
my @blocks = $src =~ /xCAT::RespawnUtils::supervise \s* \{ (.*?) ^\s* \} \s* state \s* =>/msgx;
BAIL_OUT("expected two supervise blocks in xcatd, found " . scalar(@blocks))
  unless @blocks == 2;
my ($respawn) = grep { /\$listener/ } @blocks;
BAIL_OUT("cannot tell the respawn block from the startup one -- the lift needs updating")
  unless $respawn;

{
    my $stubs = join "\n",
      'package t::monitor;',
      'no strict;',
      'no warnings;',
      'our $served = 0;',
      'sub do_installm_service { $served++ }',
      'sub xexit { die "xexit\n" }',
      '1;';
    eval $stubs or BAIL_OUT("cannot compile the monitor stubs: $@");

    my $body = "package t::monitor; no strict; no warnings; sub become_monitor { $respawn }; 1;";
    eval $body or BAIL_OUT("cannot compile the lifted respawn block: $@");
}

# A connected pair of descriptors, so close() has something real to close.
sub a_socket {
    socketpair(my $near, my $far, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
      or BAIL_OUT("socketpair failed: $!");
    return ($near, $far);
}

subtest 'a respawned monitor keeps none of the descriptors it inherited' => sub {
    my %handle;
    my @keep;
    for my $name (qw(listener udpctl chreadpipe chwritepipe)) {
        my ($near, $far) = a_socket();
        $handle{$name} = $near;
        push @keep, $far;
    }
    my @pending;
    for (1 .. 3) {
        my ($near, $far) = a_socket();
        push @pending, $near;
        push @keep,    $far;
    }

    {
        no strict 'refs';
        ${"t::monitor::$_"} = $handle{$_} for keys %handle;
        ${'t::monitor::progname'} = \(my $title = 'xcatd');
        ${'t::monitor::pid_UDP'}  = 4242;
        @{'t::monitor::pendingconnections'} = @pending;
    }
    $t::monitor::served = 0;

    eval { t::monitor::become_monitor(); 1 };
    my $left = $@;

    is($left, "xexit\n", 'the block ran to the end and left through xexit');
    cmp_ok($t::monitor::served, '==', 1, 'and it entered do_installm_service on the way');

    for my $name (sort keys %handle) {
        ok(!defined fileno($handle{$name}), "the monitor closed the inherited $name");
    }

    my @open = grep { defined fileno($pending[$_]) } 0 .. $#pending;
    is_deeply(\@open, [],
        'the monitor closed the connections the parent had accepted but not yet dispatched')
      or diag("a client socket the monitor holds stays open for the life of the daemon,"
          . " long after the worker that served it has gone");

    no strict 'refs';
    is(${'t::monitor::pid_UDP'}, 0, 'and it no longer believes it owns the udp child');

    close($_) for @keep;
};

done_testing();
