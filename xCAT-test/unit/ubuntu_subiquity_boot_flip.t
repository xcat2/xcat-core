#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

# Regression: after Subiquity installs the OS the node MUST be flipped to local-disk boot, or it
# PXE-loops straight back into the installer and the installed OS -- with its sshd -- never
# boots. The diskful case then only ever reports
# "ssh: connect to host <cn> port 22: Connection refused".
#
# xCAT performs that flip when the node reports "next" to xcatd on the install-monitor port,
# which makes xcatd run "nodeset <node> next" and rewrite the node's xNBA script to fall through
# to the local disk. The in-target post-script tries this through updateflag.awk, but that
# depends on gawk's |& / /inet coprocess and on /usr/bin/awk being gawk -- on Ubuntu
# /usr/bin/awk is normally mawk, which has neither, so the flip fails silently.
#
# The template must therefore trigger the flip itself from the live installer, with no gawk
# dependency, and must NOT report success when it did not happen.

my $repo_root = File::Spec->rel2abs(
    File::Spec->catdir( $FindBin::Bin, '..', '..' )
);
my $path = File::Spec->catfile(
    $repo_root, 'xCAT-server', 'share', 'xcat', 'install', 'ubuntu', 'compute.subiquity.tmpl'
);
plan skip_all => 'compute.subiquity.tmpl not found' unless -f $path;

my $tmpl = do { local $/; open my $fh, '<', $path or die $!; <$fh> };

like( $tmpl, qr{/dev/tcp/\$xm/3002},
    'the flip contacts xcatd on the install-monitor port from the installer' );
like( $tmpl, qr{printf "next},
    'it sends the "next" token that makes xcatd run "nodeset <node> next"' );
like( $tmpl, qr{xm=#XCATVAR:XCATMASTER#},
    "the flip targets the node's own xcatmaster" );
like( $tmpl, qr{^\s*-\s*\['bash',\s*'-c',}m,
    'the flip runs under bash (dash has no /dev/tcp) via an argv list command' );

# A failed flip must be visible. The original form broke out of its retry loop as soon as the
# socket connected -- never on a confirmed exchange -- and ended in `true`, so a total failure
# looked exactly like success and the node silently reinstalled forever.
like( $tmpl, qr{ok=1},
    'success is recorded only after the exchange completes, not merely on connect' );
like( $tmpl, qr{FAILED to flip},
    'a failed flip is reported into the install log rather than passing silently' );

# The magic-SysRq forced reboot must be gone: toram already unmounts the NFS live root, so the
# shutdown hang it worked around cannot occur, and an unconditional timed reboot would race a
# slow install.
unlike( $tmpl, qr{sysrq-trigger},
    'no unconditional magic-SysRq reboot (toram removes the hang it worked around)' );

done_testing();
