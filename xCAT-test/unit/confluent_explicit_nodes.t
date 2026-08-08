#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $plugin = File::Spec->catfile( $repo_root, 'xCAT-server/lib/xcat/plugins/confluent.pm' );

plan skip_all => "$plugin not found" unless -r $plugin;

open( my $fh, '<', $plugin ) or die "Unable to read $plugin: $!";
my $source = do { local $/; <$fh> };
close($fh);

# A stand-in for the nodehm table, so the selection logic can be exercised
# without a database. getNodesAttribs leaves out nodes that have no row, which
# is what the plugin sees for a node that was never given console attributes.
{
    package StubNodehm;
    sub new { my ( $class, %rows ) = @_; return bless { rows => {%rows} }, $class; }
    sub getNodesAttribs {
        my ( $self, $noderange, $attrs ) = @_;
        my %out;
        foreach my $node (@$noderange) {
            next unless exists $self->{rows}{$node};
            $out{$node} = [ { %{ $self->{rows}{$node} } } ];
        }
        return \%out;
    }
    sub getAllNodeAttribs {
        my ( $self, $attrs ) = @_;
        return map { { %{ $self->{rows}{$_} } } } sort keys %{ $self->{rows} };
    }
}

# Extract the node-selection block from preprocess_request and run it directly,
# so this covers the shipped logic rather than a copy of it.
my ($block) = $source =~ m{
    ( my \s+ \@items; .*?
      push \s+ \@nodes, \s* \$_->\{node\}; \s* \n \s* \} )
}sx;

ok( $block, 'the node-selection block was located in preprocess_request()' )
  or BAIL_OUT('confluent.pm no longer matches the expected node-selection shape');

sub select_nodes {
    my ( $noderange, %rows ) = @_;
    my $hmtab  = StubNodehm->new(%rows);
    my $master = 'mn.example';
    my %cons_hash;
    my $code = 'sub { my ($noderange, $hmtab, $master, $cons_ref) = @_; my %cons_hash; '
      . $block
      . ' %$cons_ref = %cons_hash; return \@nodes; }';
    my $sub = eval $code;
    die "Unable to evaluate the extracted block: $@" if $@;
    my $nodes = $sub->( $noderange, $hmtab, $master, \%cons_hash );
    return ( $nodes, \%cons_hash );
}

my %rows = (
    withcons    => { node => 'withcons',    cons => 'ipmi' },
    withserial  => { node => 'withserial',  serialport => 0 },
    nocons      => { node => 'nocons' },
    withserver  => { node => 'withserver',  cons => 'ipmi', conserver => 'sn1.example' },
);

# An explicitly named node is configured even with no console attributes, and
# even with no nodehm row at all. The administrator asked for it by name.
my ( $explicit ) = select_nodes( ['nocons'], %rows );
is_deeply( $explicit, ['nocons'], 'an explicitly named node with no console attributes is still configured' );

my ( $missing ) = select_nodes( ['neverdefined'], %rows );
is_deeply( $missing, ['neverdefined'], 'an explicitly named node with no nodehm row is configured under its own name' );

my ( $mixed ) = select_nodes( [ 'withcons', 'nocons' ], %rows );
is_deeply( [ sort @$mixed ], [ 'nocons', 'withcons' ], 'an explicit noderange keeps both console-configured and console-less nodes' );

# Scanning the whole table must not change: nodes with no console configuration
# are still skipped, so every node in the cluster is not swept into confluent.
my ( $all ) = select_nodes( undef, %rows );
is_deeply(
    [ sort @$all ],
    [ 'withcons', 'withserial', 'withserver' ],
    'a full table scan still skips nodes that have no console configuration'
);
ok( !grep( { $_ eq 'nocons' } @$all ), 'a console-less node is not picked up by a full table scan' );

# Conserver routing is unaffected.
my ( undef, $cons_hash ) = select_nodes( [ 'withserver', 'withcons' ], %rows );
is_deeply( $cons_hash->{'sn1.example'}{nodes}, ['withserver'], 'a node keeps its explicit conserver' );
is_deeply( $cons_hash->{'mn.example'}{nodes}, ['withcons'], 'a node with no conserver falls back to the management node' );

# makeconfluentcfg looks the named nodes up a second time and reshapes the
# result. A node with no nodehm row yields an undefined entry there too, and
# without the node name it reaches confluent as an empty name rather than as
# the node that was asked for.
my ($adjust) = $source =~ m{
    ( my \s+ \@tmpcfgents1; \s*\n
      \s* foreach \s+ my \s+ \$ent \s+ \(\@cfgents1\) .*?
      \n \s* \} \n \s* \} \n )
}sx;

ok( $adjust, 'the explicit-node lookup adjustment was located in makeconfluentcfg()' )
  or BAIL_OUT('confluent.pm no longer matches the expected lookup-adjustment shape');

my $adjust_sub = eval 'sub { my (@cfgents1) = @_; ' . $adjust . ' return \@tmpcfgents1; }';
die "Unable to evaluate the extracted adjustment: $@" if $@;

my $reshaped = $adjust_sub->(
    { withcons => [ { node => 'withcons', cons => 'ipmi' } ] },
    { neverdefined => [] },
);
is( scalar(@$reshaped), 2, 'both named nodes survive the lookup adjustment' );
my ($carried) = grep { ($_->{node} || '') eq 'neverdefined' } @$reshaped;
ok( $carried, 'a named node with no nodehm row keeps its name through the adjustment' );
ok(
    !grep( { !defined( $_->{node} ) || $_->{node} eq '' } @$reshaped ),
    'no entry reaches confluent with an empty node name'
);

done_testing();
