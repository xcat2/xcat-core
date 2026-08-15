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

sub slurp { my ($p) = @_; local $/; open my $fh, '<', $p or return undef; <$fh> }

my $x = slurp('xCAT-server/sbin/xcatd');
plan skip_all => 'sbin/xcatd not found' unless defined $x;

like($x, qr/if\s*\(\s*!\$pid_MON\s*&&\s*!\$quit\s*&&\s*\$sport\s*\)/,
    'main loop re-forks the install monitor when it has died (!$pid_MON && !$quit && $sport)');

# The respawn must actually (re)enter the install-monitor service in the forked child.
like($x, qr/!\$pid_MON.*?do_installm_service;.*?xexit\(0\)/s,
    'the respawn child runs do_installm_service (re-serves xcatiport) and exits');

done_testing();
