#!/usr/bin/env perl
#
# Unit test for xcatd's respawn of the install monitor -- the child that listens on
# xcatiport for node install-status updates and the "next" boot-flip request.
#
# The monitor is forked exactly ONCE at daemon startup. When it dies the SIGCHLD reaper
# only clears $pid_MON and nothing re-forks it, so a single death of that child (a stray
# signal, or a lost socket takeover during an xcatd restart) leaves xcatiport dead while
# the main daemon keeps running: installing nodes can no longer report booted or request
# the boot flip until the WHOLE daemon is restarted.
#
# Respawning has to be paced -- do_installm_service dies when it cannot bind the port, so
# while something else holds xcatiport every respawn is a fast, futile fork that also
# re-enters that function's USR2 socket-takeover handshake. But pacing must never become
# giving up: a retry budget that runs out cannot be refilled, because with no monitor
# alive nothing is left to reset it. The port would then stay dead until xcatd is
# restarted -- exactly the failure the respawn exists to remove, just reached more slowly.
#
# So the property under test is: the monitor comes back on its OWN, at a bounded rate, no
# matter how long it has been failing. The test drives xcatd's real pacing code -- the
# 'mon-respawn-policy' region is extracted from the script VERBATIM and executed here, the
# same way build_ubunturepo_lock.t drives build-ubunturepo's real lock -- first over a
# virtual clock (the backoff schedule), then for real against a genuinely held TCP port:
# fail several times, release the port, and require that the monitor recovers by itself.

use strict;
use warnings;

use FindBin;
use Test::More;
use POSIX qw(WNOHANG);
use IO::Socket::INET;

# Every monitor stand-in forked below is registered here, so a failed assertion that
# returns early out of the fork test cannot leave one sleeping on the port. The children
# leave via POSIX::_exit, which skips this block, so only the parent ever runs it.
my @spawned;
END { kill 'TERM', grep { $_ } @spawned if @spawned; }

my $script = "$FindBin::Bin/../../xCAT-server/sbin/xcatd";
ok( -f $script, "found xcatd at $script" )
  or BAIL_OUT("xCAT-server/sbin/xcatd not found");

my $src = do { local ( @ARGV, $/ ) = $script; <> };

# --- the review property, read straight off the source -----------------------
# A permanent give-up reintroduces the very softlock this respawn removes, so xcatd must
# not contain one. Keep this cheap check next to the behavioural ones: it names the
# regression in one line if someone re-adds an attempt cap. Full-line comments are
# stripped first -- this is a claim about the code, and the code is surrounded by prose
# explaining why giving up would be wrong.
# (ok() rather than unlike(), so a failure names the regression instead of dumping xcatd)
my $code = join "\n", grep { !/^\s*#/ } split /\n/, $src;
ok( $code !~ qr/giv(?:e|ing|es)\s+up/i,
    'xcatd never logs giving up on the install monitor (no permanent stop-trying path)' );
ok( $code !~ qr/\$mon_respawn_attempts\b/,
    'the respawn is not gated on an exhaustible attempt budget' );

# --- wiring: the main loop and the reaper must go through the policy ---------
ok( $src =~ qr/if\s*\(\s*!\$pid_MON\s*&&\s*!\$quit\s*&&\s*\$sport\s*&&\s*mon_respawn_due\(/,
    'the main loop re-forks the monitor only when the policy says a respawn is due' );
ok( $src =~ qr/!\$pid_MON.*?do_installm_service;.*?xexit\(0\)/s,
    'the respawned child re-enters do_installm_service (re-serves xcatiport) and exits' );
ok( $src =~ qr/\$CHILDPID\s*==\s*\$pid_MON.*?mon_respawn_exited\(/s,
    'the SIGCHLD reaper reports the monitor exit to the policy' );
# The monitor forked at startup must be recorded too, or its uptime is unknown and the
# death of a monitor that had served for months would be paced as though it had just
# failed to start.
ok( $src =~ qr/mon_respawn_forked\(time\(\)\);\s*\S[^\n]*\n\$pid_MON\s*=\s*xCAT::Utils->xfork;/,
    'the monitor forked at daemon startup is recorded with the policy as well' );

# --- extract xcatd's real pacing code so the rest can drive it ---------------
my ($region) =
  $src =~ /^# BEGIN mon-respawn-policy\n(.*?)^# END mon-respawn-policy\n/ms;
ok( defined $region, "xcatd carries an extractable 'mon-respawn-policy' region" )
  or diag( "xcatd has no marked 'mon-respawn-policy' region, so its respawn pacing "
      . "cannot be exercised -- only asserted about by grep." );

if ( defined $region ) {

    # Compile the region into a throwaway package. It reads only %ENV and its own lexicals,
    # so a fresh package per case gives each one a clean, independently tuned policy.
    my $pkg_seq = 0;
    sub load_policy {
        my (%tune) = @_;
        local $ENV{XCATD_MON_RESPAWN_MIN_INTERVAL} = $tune{min};
        local $ENV{XCATD_MON_RESPAWN_MAX_INTERVAL} = $tune{max};
        local $ENV{XCATD_MON_RESPAWN_HEALTHY}      = $tune{healthy};

        my $pkg = 'MonRespawnPolicy' . ++$pkg_seq;
        my $ok = eval "package $pkg;\nuse strict;\nuse warnings;\n$region\n1;\n";
        die "the mon-respawn-policy region did not compile: $@" unless $ok;

        my %p;
        for my $fn (qw(due forked exited hit_ceiling)) {
            my $code = $pkg->can("mon_respawn_$fn")
              or die "the mon-respawn-policy region does not define mon_respawn_$fn()";
            $p{$fn} = $code;
        }
        return \%p;
    }

    # Drive the policy over a virtual clock in which every monitor dies the instant it is
    # forked -- i.e. the port stays held for the whole window. Returns the times it was
    # willing to try again, which is the schedule the daemon would actually fork on.
    sub attempts_while_failing {
        my ( $p, $seconds ) = @_;
        my @at;
        for my $now ( 0 .. $seconds ) {
            next unless $p->{due}->($now);
            push @at, $now;
            $p->{forked}->($now);
            $p->{exited}->($now);    # could not bind: died at once
        }
        return @at;
    }

    sub gaps_between {
        my (@at) = @_;
        return map { $at[$_] - $at[ $_ - 1 ] } 1 .. $#at;
    }

    # --- the softlock the review caught -------------------------------------
    subtest 'a monitor that keeps failing is still being retried much later' => sub {
        my $p  = load_policy( min => 1, max => 4, healthy => 60 );
        my @at = attempts_while_failing( $p, 10_000 );

        cmp_ok( scalar(@at), '>', 100,
            'the daemon is still forking monitors after ~3 hours of continuous failure' );
        cmp_ok( $at[-1], '>=', 9_990,
            'the last attempt is at the END of the window -- retrying never stopped' );

        # ...and it is still paced while doing so: at the 4s ceiling the window admits
        # ~2500 attempts, where an unpaced loop would fork as fast as fork() returns.
        cmp_ok( scalar(@at), '<=', 10_000 / 4 + 5,
            'attempts stay spaced by the ceiling rather than becoming a fork storm' );
    };

    # --- the shape of the pacing --------------------------------------------
    subtest 'the delay doubles from the minimum up to a ceiling and stays there' => sub {
        my $p    = load_policy( min => 1, max => 8, healthy => 60 );
        my @at   = attempts_while_failing( $p, 200 );
        my @gaps = gaps_between(@at);

        is_deeply( [ @gaps[ 0 .. 5 ] ], [ 1, 2, 4, 8, 8, 8 ],
            'gaps back off 1,2,4,8 then hold at the 8s ceiling' );
        is( scalar( grep { $_ > 8 } @gaps ), 0, 'no gap ever exceeds the ceiling' );
    };

    subtest 'hitting the ceiling is reported once per failure streak' => sub {
        my $p = load_policy( min => 1, max => 4, healthy => 60 );

        my $reports = 0;
        for my $now ( 0 .. 100 ) {
            next unless $p->{due}->($now);
            $reports++ if $p->{hit_ceiling}->();
            $p->{forked}->($now);
            $p->{exited}->($now);
        }
        is( $reports, 1,
            'a monitor that cannot start is logged once, not on every attempt' );
    };

    # --- recovery, on the virtual clock -------------------------------------
    subtest 'a monitor that served resets the backoff when it later dies' => sub {
        my $p = load_policy( min => 1, max => 8, healthy => 60 );

        # burn the budget down to the ceiling on a held port
        attempts_while_failing( $p, 20 );

        # then one gets the socket and serves for two minutes before dying
        my $up = 100;
        $p->{forked}->($up);
        $p->{exited}->( $up + 120 );

        ok( $p->{due}->( $up + 120 ),
            'the death of a healthy monitor is retried at once, not after the old backoff' );

        # and the streak starts over from the minimum rather than from the ceiling
        $p->{forked}->( $up + 120 );
        $p->{exited}->( $up + 120 );
        ok( !$p->{due}->( $up + 120 ), 'the retry after that is paced again' );
        ok( $p->{due}->( $up + 121 ), '...by the minimum interval, not by the old ceiling' );
    };

    # --- the real thing: fail several times, release the port, recover ------
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
        my $p = load_policy( min => 1, max => 2, healthy => $healthy );

        my ( $mon_pid, $mon_forked_at ) = ( 0, 0 );
        my ( @forks, @deaths );

        # One turn of the daemon's service loop: reap the monitor if it died, then re-fork
        # it if the policy says a respawn is due. The child stands in for
        # do_installm_service: the part of it the policy reacts to is that it binds
        # xcatiport or dies, and the rest needs the whole daemon (DB, SSL, plugins,
        # /var/run/xcat) to run at all.
        my $pump = sub {
            if ($mon_pid) {
                if ( waitpid( $mon_pid, WNOHANG ) == $mon_pid ) {
                    push @deaths, [ $mon_pid, $mon_forked_at, time() ];
                    $p->{exited}->( time() );
                    $mon_pid = 0;
                }
            }
            if ( !$mon_pid && $p->{due}->( time() ) ) {
                my $now = time();
                $p->{forked}->($now);
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

        # (2) release the port -- nothing else about the daemon changes, it is not restarted
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
}

done_testing();
