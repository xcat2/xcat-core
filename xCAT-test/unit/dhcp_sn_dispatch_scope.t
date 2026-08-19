#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $plugin = File::Spec->catfile( $repo_root, 'xCAT-server/lib/xcat/plugins/dhcp.pm' );

plan skip_all => "$plugin not found" unless -r $plugin;

open( my $fh, '<', $plugin ) or die "Unable to read $plugin: $!";
my $source = do { local $/; <$fh> };
close($fh);

# The dispatch loop that fans a node-targeted makedhcp out to service nodes.
my ($loop) = $source =~ m{
    ( my \s+ %servingsn .*? foreach \s+ my \s+ \$s \s+ \(\@snlist\) .*? \n \s* \} \n )
}sx;

ok( $loop, 'the service node dispatch loop was located' )
  or BAIL_OUT('dhcp.pm no longer matches the expected dispatch shape');

like(
    $loop,
    qr/getSNformattedhash\(\\\@nodes/,
    'the named nodes are mapped to their service nodes'
);
like(
    $loop,
    qr/next \s+ if \s+ \(keys\(%servingsn\) \s* && \s* !exists\(\$servingsn\{\$s\}\)\)/x,
    'a service node serving none of the named nodes is skipped'
);

# Regenerating the networks must still reach every dhcp server, because a
# dynamic range does not belong to any node.
like(
    $loop,
    qr/unless \s* \(\$opt\{n\}\)/x,
    'network regeneration is exempt from the node based restriction'
);

# Empty mapping must fall back to the previous fan-out rather than silently
# dispatching to nothing.
my ($guard) = $loop =~ /(next\s+if\s+\(keys\(%servingsn\)[^\n]*)/;
like(
    $guard,
    qr/keys\(%servingsn\)\s*&&/,
    'an unmapped noderange still reaches every service node'
);

# The pre-existing conditions in the loop must survive.
like( $loop, qr/scalar \@nodes == 1 and \$nodes\[0\] eq \$s/, 'the self dispatch guard is retained' );
like( $loop, qr/\$issn && exists\(\$iphash\{\$s\}\)/,          'the service node self skip is retained' );

done_testing();
