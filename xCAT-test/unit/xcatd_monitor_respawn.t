#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Regression: xcatd's install monitor (the child that listens on xcatiport / 3002 and receives node
# install-status updates and the "next" boot-flip request) was forked exactly ONCE at daemon startup.
# When it died the SIGCHLD reaper only cleared $pid_MON ($CHILDPID == $pid_MON -> $pid_MON = 0) and
# nothing re-forked it. So a single death of that child -- a stray signal, or a lost socket-takeover
# during an xcatd restart -- left xcatiport permanently dead while the main daemon kept running, and
# installing nodes could no longer report "booted" or request the boot flip until the WHOLE daemon was
# restarted (which is disruptive to concurrent operations). xcatd must instead respawn the monitor in
# its main service loop so it self-heals without a full restart.

use File::Spec;
use FindBin;
my $repo_root = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..', '..' ) );

sub slurp {
    my ($rel) = @_;
    my $path = File::Spec->catfile( $repo_root, split m{/}, $rel );
    local $/;
    open my $fh, '<', $path or return undef;
    <$fh>;
}

my $x = slurp('xCAT-server/sbin/xcatd');
plan skip_all => 'sbin/xcatd not found' unless defined $x;

like($x, qr/if\s*\(\s*!\$pid_MON\s*&&\s*!\$quit\s*&&\s*\$sport\s*\)/,
    'main loop re-forks the install monitor when it has died (!$pid_MON && !$quit && $sport)');

# The respawn must actually (re)enter the install-monitor service in the forked child.
like($x, qr/!\$pid_MON.*?do_installm_service;.*?xexit\(0\)/s,
    'the respawn child runs do_installm_service (re-serves xcatiport) and exits');

# The respawn must be rate limited. do_installm_service dies when it cannot bind xcatiport
# after its own retries -- e.g. while another instance still holds the socket. The child then
# exits, the SIGCHLD reaper clears $pid_MON, and an unguarded main loop re-forks immediately,
# producing a fork storm for as long as the port stays held and colliding with that function's
# own USR2 socket-takeover handshake. Respawns must therefore be spaced, and must give up
# (loudly) rather than retry forever.
like($x, qr/\$mon_respawn_(?:last|attempts)/,
    'the respawn is rate limited by recorded state (last attempt time / attempt count)');
like($x, qr/XCATD_MON_RESPAWN_INTERVAL|mon_respawn_interval/,
    'a minimum interval separates consecutive respawn attempts');
like($x, qr/XCATD_MON_RESPAWN_MAX|mon_respawn_max/,
    'the number of consecutive respawn attempts is capped');
like($x, qr/giving up|gave up/i,
    'exhausting the cap is reported rather than retried silently forever');

done_testing();
