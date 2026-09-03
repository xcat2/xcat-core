# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::RespawnUtils;

# Backoff for a parent that re-forks a child when it dies; xcatd's install monitor is the
# caller. The delay doubles from min_interval to max_interval and holds there.
#
# There is no attempt limit. A spent budget cannot be refilled: with no child alive nothing
# resets it, and the resource stays dead until xcatd restarts. A child that ran `healthy`
# seconds served, so its death resets the delay.
#
# Every sub returns a new state and leaves its argument alone, so exited() can run in a
# SIGCHLD handler.
#
# The state is a plain hash; call the subs below for the next state.
#
#   min_interval  shortest wait, and what a healthy run resets the delay to
#   max_interval  longest wait; the delay doubles up to this
#   healthy       seconds a child must survive to count as having served
#   delay         the wait after the next failure
#   next_at       earliest time() at which another attempt is allowed
#   started_at    when the running child was forked, undef when none is running
#   streak        children in a row that died young
#   reported      whether the ceiling was already logged for this streak

use strict;
use warnings;

# The tunables reach policy() straight from %ENV, so they can be empty or misspelt. Anything
# that is not a whole number is treated as unset.
sub _tunable {
    my ($value, $default) = @_;
    return $default unless defined($value) && $value =~ /^\s*\d+\s*$/;
    return $value + 0;
}

sub policy {
    my (%opt) = @_;

    my $min     = _tunable($opt{min_interval}, 5);
    my $max     = _tunable($opt{max_interval}, 300);
    my $healthy = _tunable($opt{healthy},      60);

    $min = 1    if $min < 1;     # 0 doubles to 0, which is a fork storm
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

sub due {
    my ($state, $now) = @_;
    return $now >= $state->{next_at} ? 1 : 0;
}

# Call before forking: the child can die and be reaped before fork() returns to the parent.
sub forked {
    my ($state, $now) = @_;
    return { %$state, started_at => $now };
}

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

# Keeps the log to one line per streak rather than one per attempt.
sub should_report {
    my ($state) = @_;
    return 0 if $state->{reported};
    return 0 if $state->{streak} < 1;
    return $state->{delay} >= $state->{max_interval} ? 1 : 0;
}

sub reported {
    my ($state) = @_;
    return { %$state, reported => 1 };
}

# --- Forking -----------------------------------------------------------------------------
# The one impure sub. Everything above is arithmetic.

# Fork a child, taking its body as a block:
#
#   xCAT::RespawnUtils::supervise { ...child... }
#       state => \$state, pid => \$pid, now => time();
#
# `state` and `pid` are references to the caller's own variables. The reaper matches the dead
# child against that pid and folds the death into that state, so both have to be in place
# while SIGCHLD is still blocked; values assigned from a return would land after it is let
# back in, and a child dying in the gap would be compared against a pid still holding 0.
#
# The (&@) prototype needs this module loaded with `use`. Under `require` the sub is unknown
# when the call is compiled, the block is read as a bare block, and its value arrives as the
# first argument.
#
# The block runs only in the child and is not expected to return. Passing a live `pid` is a
# no-op. Returns the new pid.
sub supervise (&@) {
    my ($child, %arg) = @_;
    my ($stateref, $pidref, $now) = @arg{qw(state pid now)};

    return $$pidref if $$pidref;

    require POSIX;
    require xCAT::Utils;

    my $mask = POSIX::SigSet->new(POSIX::SIGCHLD());
    POSIX::sigprocmask(POSIX::SIG_BLOCK(), $mask);

    $$stateref = forked($$stateref, $now);
    my $pid = xCAT::Utils->xfork;

    unless (defined $pid) {    # could not fork: count it and back off
        $$stateref = exited($$stateref, $now);
        $$pidref   = 0;
        POSIX::sigprocmask(POSIX::SIG_UNBLOCK(), $mask);
        return 0;
    }

    unless ($pid) {    # the child must not serve with SIGCHLD blocked
        POSIX::sigprocmask(POSIX::SIG_UNBLOCK(), $mask);
        $child->();
        POSIX::_exit(0);
    }

    $$pidref = $pid;    # in place before the reaper runs, or it matches a stale pid
    POSIX::sigprocmask(POSIX::SIG_UNBLOCK(), $mask);
    return $pid;
}

1;
