# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::RespawnUtils;

# Pacing for a parent that has to keep a child alive; xcatd's install monitor is the caller.
#
# The child is re-forked whenever it dies, but not as fast as fork() returns -- it may be
# dying because a resource it needs is held by someone else, and retrying flat out burns CPU
# and interferes with whatever handshake it performs to claim that resource. So attempts back
# off, doubling from min_interval to max_interval and then holding there.
#
# It never stops retrying. A retry budget that runs out cannot be refilled, because with no
# child alive nothing is left to reset it, so the resource would stay unserved until the whole
# daemon is restarted -- the failure the respawn exists to prevent. A child that stayed up
# `healthy` seconds evidently did claim its resource and serve, so its death resets the delay
# and only a real streak of failures to start builds the backoff up.
#
# Every function returns a NEW state and never mutates the one it is handed. That is what
# makes them safe to call from a SIGCHLD handler: the result is complete before the caller's
# assignment installs it, so a signal cannot catch the pacing half-written.
#
# The state is a plain hash. Callers may read these; use the functions below to get the next
# state rather than writing to them.
#
#   min_interval  shortest wait between attempts, and what a healthy run resets the delay to
#   max_interval  longest wait -- the delay doubles up to this and then stays here
#   healthy       how long a child must survive before we count it as having served
#   delay         how long to wait after the NEXT failure
#   next_at       earliest time() at which another attempt is allowed
#   started_at    when the running child was forked, or undef when none is running
#   streak        how many children in a row have died young
#   reported      whether we have already logged that this streak reached the ceiling

use strict;
use warnings;

# Everything up to the "Forking" section below is pure arithmetic: it reads only the state it
# is handed, returns a new one, and touches no clock, no globals and no processes. Keep it
# that way -- that is what lets the pacing be tested on a made-up clock instead of in real
# seconds, and what makes exited() safe to call from a signal handler.

# Read one tunable, falling back to the default unless it really looks like a whole number.
sub _tunable {
    my ($value, $default) = @_;
    return $default unless defined($value) && $value =~ /^\s*\d+\s*$/;
    return $value + 0;
}

# Start pacing a child from scratch. Anything the caller leaves out gets a sensible default.
sub policy {
    my (%opt) = @_;

    my $min     = _tunable($opt{min_interval}, 5);
    my $max     = _tunable($opt{max_interval}, 300);
    my $healthy = _tunable($opt{healthy},      60);

    $min = 1    if $min < 1;
    $max = $min if $max < $min;

    return {
        min_interval => $min,
        max_interval => $max,
        healthy      => $healthy,
        delay        => $min,
        next_at      => 0,
        started_at   => undef,
        streak       => 0,
        reported     => 0,
    };
}

# Is it time to try again yet? This can say "not yet", but it never says "no more".
sub due {
    my ($state, $now) = @_;
    return $now >= $state->{next_at} ? 1 : 0;
}

# Note that we are about to fork, so we can tell later how long the child lasted. Call this
# before forking: the child can die and be reaped before fork() even returns to us.
sub forked {
    my ($state, $now) = @_;
    return { %$state, started_at => $now };
}

# Note that the child died, and decide when to try again -- straight away if it had been up
# long enough to have served, later and later if it keeps failing to start.
sub exited {
    my ($state, $now) = @_;

    my %next = (%$state, started_at => undef);

    if (defined($state->{started_at})
        and ($now - $state->{started_at}) >= $state->{healthy}) {

        $next{delay}    = $state->{min_interval};
        $next{next_at}  = $now;
        $next{streak}   = 0;
        $next{reported} = 0;
    } else {
        $next{streak}  = $state->{streak} + 1;
        $next{next_at} = $now + $state->{delay};
        $next{delay}   = ($state->{delay} * 2 > $state->{max_interval})
          ? $state->{max_interval}
          : $state->{delay} * 2;
    }

    return \%next;
}

# Has this run of failures just hit the ceiling, and not been mentioned yet? Keeps the log to
# one line per streak instead of one per attempt.
sub should_report {
    my ($state) = @_;
    return 0 if $state->{reported};
    return 0 if $state->{streak} < 1;
    return $state->{delay} >= $state->{max_interval} ? 1 : 0;
}

# Remember that we have already logged the ceiling for this streak.
sub reported {
    my ($state) = @_;
    return { %$state, reported => 1 };
}

# --- Forking -----------------------------------------------------------------------------
# The one impure sub. Everything above only does arithmetic; this actually forks.

# Fork a child and keep the pacing straight while doing it. Takes the child's body as a
# block, then `state`, `pid` and `now`, and hands back the state and the new pid:
#
#   ($state, $pid) = xCAT::RespawnUtils::supervise { ...child... }
#                       state => $state, pid => $pid, now => time();
#
# The (&@) prototype is what allows the leading block. It needs this module loaded with
# `use`, not `require`: under `require` the sub is unknown when the call is compiled, the
# block is then read as a bare block, and its value arrives as the first argument.
#
# Two orderings in here are easy to get wrong and are the reason this is not left to callers.
# The attempt is recorded before the fork, because the child can die and be reaped before
# fork() returns to us. And SIGCHLD is blocked across the fork and the assignment, because a
# reaper that matches on the pid would otherwise compare against a stale one, miss the death,
# and leave the caller believing a dead child is still alive.
#
# The block is only ever entered in the child and is not expected to return; if it does, the
# child exits quietly rather than falling back into the parent's code. Passing a live `pid`
# is a no-op, so a caller that forgets to check is not punished with a second child.
sub supervise (&@) {
    my ($child, %arg) = @_;
    my ($state, $pid, $now) = @arg{qw(state pid now)};

    return ($state, $pid) if $pid;    # already running; nothing to do

    require POSIX;
    require xCAT::Utils;

    $state = forked($state, $now);

    my $mask = POSIX::SigSet->new(POSIX::SIGCHLD());
    POSIX::sigprocmask(POSIX::SIG_BLOCK(), $mask);
    $pid = xCAT::Utils->xfork;
    POSIX::sigprocmask(POSIX::SIG_UNBLOCK(), $mask);

    return (exited($state, $now), 0) unless defined $pid;    # could not fork: back off

    unless ($pid) {
        $child->();
        POSIX::_exit(0);
    }
    return ($state, $pid);
}

1;
