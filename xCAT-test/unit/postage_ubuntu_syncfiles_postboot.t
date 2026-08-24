#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

# Regression: on Ubuntu/Debian the DISKFUL install runs a node's postscripts inside the
# installer's in-target chroot -- before the node has booted as itself. The syncfiles
# postscript works by asking the management node to scp files INTO the running node, which
# cannot happen in that phase: the not-yet-booted node has no sshd for the MN to reach, so the
# push times out, syncfiles exits 1, and the node reports status=failed even though the OS
# installed perfectly.
#
# syncfiles must therefore move to the postbootscripts set, which runs on the booted node
# where ssh is already listening. Two things bound that move:
#
#   * It applies to the DISKFUL install path only. netboot and statelite already run their
#     postscripts on the booted node, so moving syncfiles there changes working behaviour for
#     no reason. EL/SLES are unaffected either way -- their postscripts already run on the
#     booted node.
#   * syncfiles must run BEFORE the existing postbootscripts, since a postbootscript may
#     consume the files it synchronises. Appending it would invert that.

my $repo_root = File::Spec->rel2abs(
    File::Spec->catdir( $FindBin::Bin, '..', '..' )
);
my $path = File::Spec->catfile( $repo_root, 'xCAT-server', 'lib', 'perl', 'xCAT', 'Postage.pm' );
plan skip_all => "Postage.pm not found" unless -f $path;

my $src = do { local $/; open my $fh, '<', $path or die $!; <$fh> };

# Isolate the deferral block so the assertions below cannot accidentally match code elsewhere.
my ($block) = $src =~ /(\n[^\n]*ubuntu\|debian[^\n]*\n(?:.*?\n)*?[^\n]*syncfiles(?:.*?\n)*?\s*\}\n\s*\}\n)/;
ok( defined $block, 'found the syncfiles deferral block in makescript' )
  or do { done_testing(); exit };

like( $block, qr/\$os\s*=~\s*.\^\(\?:ubuntu\|debian\)/,
    'the move is guarded to ubuntu/debian nodes only' );

like( $block, qr/\$diskful_install|\bnodesetstate\b|\bprovmethod\b/,
    'the move is guarded to the diskful install path (not netboot/statelite)' );

like( $block, qr/\$postscripts\s*=~\s*s\/\^\[[^\]]*\]\*syncfiles/,
    'syncfiles is stripped from the in-target postscripts list' );

like( $block, qr/\$postbootscripts\s*=\s*"[^"]*syncfiles[^"]*"\s*\.\s*\$postbootscripts/,
    'syncfiles is PREPENDED to postbootscripts, so it runs before scripts that consume its files' );

unlike( $block, qr/\$postbootscripts\s*\.=\s*"syncfiles/,
    'syncfiles is not appended after the existing postbootscripts' );

# The strip and the re-add must be paired, so a node with no syncfiles postscript never
# acquires a spurious one.
like( $block, qr/if\s*\(.*?\$postscripts.*?syncfiles.*?\)\s*\{\s*.*?\$postbootscripts/s,
    'syncfiles is only added to postbootscripts when it was present in postscripts' );

done_testing();
