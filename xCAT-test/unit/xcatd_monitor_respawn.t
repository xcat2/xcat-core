#!/usr/bin/env perl
#
# Unit test for the pacing that keeps xcatd's install monitor alive -- the child that
# listens on xcatiport for node install-status updates and the "next" boot-flip request.
#
# The monitor used to be forked exactly once at daemon startup. When it died the SIGCHLD
# reaper only cleared $pid_MON and nothing re-forked it, so a single death of that child
# (a stray signal, or a lost socket takeover during an xcatd restart) left xcatiport dead
# while the main daemon kept running: installing nodes could no longer report booted or
# request the boot flip until the WHOLE daemon was restarted.
#
# Respawning has to be paced -- do_installm_service dies when it cannot bind the port, so
# while something else holds xcatiport every respawn is a fast, futile fork that also
# re-enters that function's USR2 socket-takeover handshake. But pacing must never become
# giving up: a retry budget that runs out cannot be refilled, because with no monitor
# alive nothing is left to reset it. The port would then stay dead until xcatd is
# restarted -- exactly the failure the respawn exists to remove, just reached more slowly.
#
# So the property under test is: the monitor comes back on its OWN, at a bounded rate, no
# matter how long it has been failing. xcatd cannot be run in a unit test (it needs the
# database, SSL, the plugin tree and /var/run/xcat), so the pacing lives in
# xCAT::RespawnUtils as pure functions -- given a state and a time they return the next
# state, touching no clock and no globals. This drives those functions directly: first
# over a virtual clock, for the schedule and the never-give-up property, and then for real
# against a genuinely held TCP port -- fail several times, release the port, and require
# that the monitor recovers by itself.

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;
use POSIX qw(WNOHANG);
use IO::Socket::INET;

require xCAT::RespawnUtils;

# Every monitor stand-in forked below is registered here, so a failed assertion that
# returns early out of the fork test cannot leave one sleeping on the port. The children
# leave via POSIX::_exit, which skips this block, so only the parent ever runs it.
my @spawned;
END { kill 'TERM', grep { $_ } @spawned if @spawned; }

sub due         { return xCAT::RespawnUtils::due(@_) }
sub forked      { return xCAT::RespawnUtils::forked(@_) }
sub exited      { return xCAT::RespawnUtils::exited(@_) }
sub should_rept { return xCAT::RespawnUtils::should_report(@_) }
sub mark_rept   { return xCAT::RespawnUtils::reported(@_) }

# Drive the pacing over a virtual clock in which every monitor dies the instant it is
# forked -- i.e. the port stays held for the whole window. Returns the times a respawn was
# allowed, which is the schedule the daemon would actually fork on.
sub attempts_while_failing {
    my ( $pace, $seconds ) = @_;
    my @at;
    for my $now ( 0 .. $seconds ) {
        next unless due( $pace, $now );
        push @at, $now;
        $pace = forked( $pace, $now );
        $pace = exited( $pace, $now );    # could not bind: died at once
    }
    return @at;
}

sub gaps_between {
    my (@at) = @_;
    return map { $at[$_] - $at[ $_ - 1 ] } 1 .. $#at;
}

# --- the softlock the review caught -----------------------------------------
subtest 'a monitor that keeps failing is still being retried much later' => sub {
    my $pace = xCAT::RespawnUtils::policy(
        min_interval => 1,
        max_interval => 4,
        healthy      => 60,
    );
    my @at = attempts_while_failing( $pace, 10_000 );

    cmp_ok( scalar(@at), '>', 100,
        'the daemon is still forking monitors after ~3 hours of continuous failure' );
    cmp_ok( $at[-1], '>=', 9_990,
        'the last attempt is at the END of the window -- retrying never stopped' );

    # ...and it is still paced while doing so: at the 4s ceiling the window admits ~2500
    # attempts, where an unpaced loop would fork as fast as fork() returns.
    cmp_ok( scalar(@at), '<=', 10_000 / 4 + 5,
        'attempts stay spaced by the ceiling rather than becoming a fork storm' );
};

# --- the shape of the pacing ------------------------------------------------
subtest 'the delay doubles from the minimum up to a ceiling and stays there' => sub {
    my $pace = xCAT::RespawnUtils::policy(
        min_interval => 1,
        max_interval => 8,
        healthy      => 60,
    );
    my @gaps = gaps_between( attempts_while_failing( $pace, 200 ) );

    is_deeply( [ @gaps[ 0 .. 5 ] ], [ 1, 2, 4, 8, 8, 8 ],
        'gaps back off 1,2,4,8 then hold at the 8s ceiling' );
    is( scalar( grep { $_ > 8 } @gaps ), 0, 'no gap ever exceeds the ceiling' );
};

subtest 'a policy cannot be built with a delay that fails to back off' => sub {
    my $zero = xCAT::RespawnUtils::policy( min_interval => 0, max_interval => 300 );
    cmp_ok( $zero->{min_interval}, '>=', 1,
        'a zero minimum is raised -- 0 doubles to 0, which is a fork storm' );

    my $inverted = xCAT::RespawnUtils::policy( min_interval => 60, max_interval => 5 );
    cmp_ok( $inverted->{max_interval}, '>=', $inverted->{min_interval},
        'a ceiling below the floor is raised to it' );

    my $default = xCAT::RespawnUtils::policy();
    is( $default->{min_interval}, 5,   'unset options fall back to the default floor' );
    is( $default->{max_interval}, 300, '...and the default ceiling' );
    is( $default->{healthy},      60,  '...and the default healthy uptime' );
};

subtest 'hitting the ceiling is reported once per failure streak' => sub {
    my $pace = xCAT::RespawnUtils::policy(
        min_interval => 1,
        max_interval => 4,
        healthy      => 60,
    );

    my $reports = 0;
    for my $now ( 0 .. 100 ) {
        next unless due( $pace, $now );
        if ( should_rept($pace) ) { $reports++; $pace = mark_rept($pace); }
        $pace = forked( $pace, $now );
        $pace = exited( $pace, $now );
    }
    is( $reports, 1, 'a monitor that cannot start is logged once, not on every attempt' );
};

# --- recovery, on the virtual clock -----------------------------------------
subtest 'a monitor that served resets the backoff when it later dies' => sub {
    my $pace = xCAT::RespawnUtils::policy(
        min_interval => 1,
        max_interval => 8,
        healthy      => 60,
    );

    # burn the backoff up to the ceiling against a held port
    for my $now ( 0 .. 20 ) {
        next unless due( $pace, $now );
        $pace = exited( forked( $pace, $now ), $now );
    }
    is( $pace->{delay}, 8, 'the backoff is sitting at the ceiling' );

    # then one gets the socket and serves for two minutes before dying
    $pace = forked( $pace, 100 );
    $pace = exited( $pace, 220 );

    ok( due( $pace, 220 ),
        'the death of a healthy monitor is retried at once, not after the old backoff' );
    is( $pace->{streak}, 0, 'the failure streak is cleared by a monitor that served' );

    # and the streak starts over from the minimum rather than from the ceiling
    $pace = exited( forked( $pace, 220 ), 220 );
    ok( !due( $pace, 220 ), 'the retry after that is paced again' );
    ok( due( $pace, 221 ), '...by the minimum interval, not by the old ceiling' );
};

subtest 'the pacing functions are pure' => sub {
    my $pace = xCAT::RespawnUtils::policy( min_interval => 1, max_interval => 8 );
    my %before = %$pace;

    my $after = exited( forked( $pace, 10 ), 11 );

    is_deeply( $pace, \%before, 'exited()/forked() leave the state they were given alone' );
    isnt( $after, $pace, 'they return a new state rather than the same reference' );
    is( due( $pace, 0 ), due( $pace, 0 ), 'due() is free of side effects' );
};

# --- the real thing: fail several times, release the port, recover ----------
subtest 'the monitor comes back on its own once the port is released' => sub {
    my $holder = IO::Socket::INET->new(
        LocalAddr => '127.0.0.1',
        LocalPort => 0,
        Proto     => 'tcp',
        ReuseAddr => 1,
        Listen    => 8,
    );
    plan skip_all => "cannot bind a loopback port here: $!" unless $holder;

    my $port    = $holder->sockport;
    my $healthy = 2;
    my $pace    = xCAT::RespawnUtils::policy(
        min_interval => 1,
        max_interval => 2,
        healthy      => $healthy,
    );

    my ( $mon_pid, $mon_forked_at ) = ( 0, 0 );
    my ( @forks, @deaths );

    # One turn of the daemon's service loop: reap the monitor if it died, then re-fork it
    # if the pacing says a respawn is due. The child stands in for do_installm_service:
    # the part of it the pacing reacts to is that it binds xcatiport or dies, and the rest
    # needs the whole daemon to run at all.
    my $pump = sub {
        if ($mon_pid) {
            if ( waitpid( $mon_pid, WNOHANG ) == $mon_pid ) {
                push @deaths, [ $mon_pid, $mon_forked_at, time() ];
                $pace    = exited( $pace, time() );
                $mon_pid = 0;
            }
        }
        if ( !$mon_pid && due( $pace, time() ) ) {
            my $now = time();
            $pace = forked( $pace, $now );
            my $pid = fork();
            die "fork failed: $!" unless defined $pid;
            if ( !$pid ) {
                close($holder) if $holder;    # never hold the port from inside a child
                my $sock = IO::Socket::INET->new(
                    LocalAddr => '127.0.0.1',
                    LocalPort => $port,
                    Proto     => 'tcp',
                    ReuseAddr => 1,
                    Listen    => 8,
                );
                POSIX::_exit(1) unless $sock;    # could not bind: died, as the real one does
                sleep 3600;                      # bound the port and serve
                POSIX::_exit(0);
            }
            $mon_pid       = $pid;
            $mon_forked_at = $now;
            push @forks,   $now;
            push @spawned, $pid;
        }
        select( undef, undef, undef, 0.05 );
    };

    my $deadline = time() + 60;

    # (1) the port is held: monitors must fail repeatedly, without a fork storm
    $pump->() while ( @deaths < 3 && time() < $deadline );
    cmp_ok( scalar(@deaths), '>=', 3,
        'the monitor is retried several times while the port is held' )
      or return;
    cmp_ok( scalar(@forks), '<=', 12,
        'those retries are paced by the backoff, not forked as fast as fork() returns' );
    is( scalar( grep { $_->[2] - $_->[1] >= $healthy } @deaths ), 0,
        'every monitor so far died young -- none of them got the socket' );

    # (2) release the port -- nothing else changes, the daemon is not restarted
    my $released = time();
    close($holder);
    undef $holder;

    # (3) it must recover by itself
    $pump->()
      while ( !( $mon_pid && time() - $mon_forked_at >= $healthy + 1 )
        && time() < $deadline );

    ok( $mon_pid && time() - $mon_forked_at >= $healthy + 1,
        'a respawned monitor binds the freed port and stays up -- no xcatd restart' )
      or return;
    cmp_ok( $mon_forked_at - $released, '<=', 5,
        'recovery lands within the backoff ceiling of the port becoming free' );

    # (4) and after that healthy run the pacing is back to prompt
    my $forks_before = scalar(@forks);
    kill 'TERM', $mon_pid;
    $pump->() while ( @forks == $forks_before && time() < $deadline );

    cmp_ok( scalar(@forks), '>', $forks_before,
        'killing the healthy monitor gets it replaced again' );
    cmp_ok( $forks[-1] - $deaths[-1][2], '<=', 2,
        'that replacement is prompt: the healthy run reset the backoff' );

    kill 'TERM', $mon_pid if $mon_pid;
    waitpid( $mon_pid, 0 ) if $mon_pid;
};

done_testing();
