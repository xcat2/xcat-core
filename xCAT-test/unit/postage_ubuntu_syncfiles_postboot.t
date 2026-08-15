#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Regression: on Ubuntu/Debian the node's *postscripts* execute inside the subiquity/curtin
# in-target chroot during install -- before the node has booted as itself. The `syncfiles`
# postscript asks the management node to scp files *into* the running node; in the in-target
# phase the not-yet-booted node has no sshd for the MN to reach, so the push times out,
# syncfiles exits 1, and the node reports status=failed even though the OS installed fine.
# makescript() must move `syncfiles` out of the postscripts set and into the postbootscripts
# set for ubuntu/debian nodes so it runs on the booted node (ssh.socket up -> push succeeds).
# EL must be left untouched (its postscripts already run on the booted node).

sub slurp { my ($p) = @_; local $/; open my $fh, '<', $p or return undef; <$fh> }

my $p = 'xCAT-server/lib/perl/xCAT/Postage.pm';
my $x = slurp($p);
plan skip_all => "$p not found" unless defined $x;

# The move must be guarded to ubuntu/debian only (EL/SLES unaffected).
like($x, qr/\$os\s*=~\s*\/\^\(ubuntu\|debian\)/,
    'syncfiles move is guarded to ubuntu/debian nodes only');

# It must remove syncfiles from the in-target postscripts string...
like($x, qr/\$postscripts\s*=~\s*s\/\^\[.*\]\*syncfiles/,
    'syncfiles is stripped from the in-target postscripts list');

# ...and re-add it to the postbootscripts (booted-node) list.
like($x, qr/\$postbootscripts\s*\.=\s*"syncfiles\\n"/,
    'syncfiles is appended to the postbootscripts list');

# The strip/append must be paired (append only happens when the strip matched), so a node
# that has no syncfiles postscript is never given a spurious one.
like($x, qr/if\s*\(defined\(\$postscripts\).*?syncfiles.*?\)\s*\{\s*.*?\$postbootscripts/s,
    'syncfiles is only added to postbootscripts when it was present in postscripts');

done_testing();
