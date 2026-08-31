#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

my $plugin = File::Spec->catfile( $FindBin::Bin, '..', '..',
    'xCAT-server', 'lib', 'xcat', 'plugins', 'confluent.pm' );
plan skip_all => 'confluent.pm not found' unless -r $plugin;

open( my $fh, '<', $plugin ) or die "Unable to read $plugin: $!";
my $source = do { local $/; <$fh> };
close($fh);

# confluent.pm needs a management node to load, so drive the shaping of the
# switch rows on its own. This mirrors the merge the command performs.
sub shape {
    my @rows = @_;
    my ( %cfgenthash, %cfgnichash );
    foreach my $nent (@rows) {
        next unless ( defined $nent->{node} );
        if ( defined $nent->{interface} and length $nent->{interface} ) {
            foreach ( keys %$nent ) {
                $cfgnichash{ $nent->{node} }->{ $nent->{interface} }->{$_} = $nent->{$_};
            }
            $cfgenthash{ $nent->{node} }->{node} = $nent->{node};
        } else {
            foreach ( keys %$nent ) {
                $cfgenthash{ $nent->{node} }->{$_} = $nent->{$_};
            }
        }
    }
    return ( \%cfgenthash, \%cfgnichash );
}

# A node has one row for each interface. Keeping only one of them loses the
# port of every other interface, which is what this export exists to carry.
my ( $flat, $pernic ) = shape(
    { node => 'n1', switch => 'sw1', port => '1', interface => 'eth0' },
    { node => 'n1', switch => 'sw2', port => '9', interface => 'ib0' },
);
is( scalar keys %{ $pernic->{n1} }, 2, 'a node with two interfaces keeps both' );
is( $pernic->{n1}{eth0}{switch}, 'sw1', 'the first interface keeps its switch' );
is( $pernic->{n1}{eth0}{port},   '1',   'the first interface keeps its port' );
is( $pernic->{n1}{ib0}{switch},  'sw2', 'the second interface keeps its switch' );
is( $pernic->{n1}{ib0}{port},    '9',   'the second interface keeps its port' );
is( $flat->{n1}{switch}, undef, 'a row naming an interface gives no plain switch' );
is( $flat->{n1}{port},   undef, 'a row naming an interface gives no plain port' );

# The node has to reach the configuration for its interfaces to be written. A
# node whose rows all name an interface is only in the per interface data, so
# the node itself must still be recorded.
is( $flat->{n1}{node}, 'n1', 'a node known only by its interfaces is still exported' );

# A row that names no interface keeps the plain names.
( $flat, $pernic ) = shape( { node => 'n2', switch => 'sw3', port => '4' } );
is( $flat->{n2}{switch}, 'sw3', 'a row with no interface gives the plain switch' );
is( $flat->{n2}{port},   '4',   'a row with no interface gives the plain port' );
is( $pernic->{n2}, undef, 'a row with no interface adds no interface entry' );

# An empty switch table must leave the configuration untouched.
( $flat, $pernic ) = shape();
is_deeply( $flat,   {}, 'an empty switch table adds no node entry' );
is_deeply( $pernic, {}, 'an empty switch table adds no interface entry' );

# A row without a node name cannot be placed.
( $flat, $pernic ) = shape( { switch => 'sw4', port => '2' } );
is_deeply( $flat,   {}, 'a row with no node is skipped' );
is_deeply( $pernic, {}, 'a row with no node adds no interface entry' );

# The command has to read the switch table, and read it in both branches. The
# branch that takes no node range must not read these columns from nodepos,
# which does not have them.
like( $source, qr/my \$switchtab = xCAT::Table->new\('switch'\)/,
    'the command opens the switch table' );
like( $source,
    qr/\@cfgents4 = \$switchtab->getNodesAttribs\(\$nodes, \[ 'node', 'switch', 'port', 'interface' \]\)/,
    'a node range reads the switch table for those nodes' );
like( $source,
    qr/\@cfgents4 = \$switchtab->getAllNodeAttribs\(\[ 'node', 'switch', 'port', 'interface' \]\)/,
    'no node range reads the whole switch table' );
unlike( $source, qr/\$nodepostab->getAllNodeAttribs\(\[ 'node', 'switch'/,
    'the switch columns are never read from nodepos' );

# The exported names are what confluent reads.
like( $source, qr/\$parameters\{'net\.switch'\} = \$cfgent->\{switch\}/,
    'the plain switch is exported' );
like( $source, qr/\$parameters\{'net\.switchport'\} = \$cfgent->\{port\}/,
    'the plain port is exported' );
like( $source, qr/\$parameters\{"net\.\$nic\.switch"\}/,
    'the switch of each interface is exported' );
like( $source, qr/\$parameters\{"net\.\$nic\.switchport"\}/,
    'the port of each interface is exported' );
like( $source, qr/\$cfgenthash\{ \$nent->\{node\} \}->\{node\} = \$nent->\{node\}/,
    'a node known only by its interfaces is recorded for the export' );

done_testing();
