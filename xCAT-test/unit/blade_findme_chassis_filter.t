#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $plugin = File::Spec->catfile( $FindBin::Bin, '..', '..',
    'xCAT-server', 'lib', 'xcat', 'plugins', 'blade.pm' );
plan skip_all => 'blade.pm not found' unless -r $plugin;

open( my $fh, '<', $plugin ) or die "Unable to read $plugin: $!";
my $source = do { local $/; <$fh> };
close($fh);

# blade.pm needs a management node to load, so lift the routine out and drive
# the real code on its own.
my ($routine) = $source =~ /(sub blade_nodes_from_mp \{.*?\n\}\n)/s;
BAIL_OUT('could not extract blade_nodes_from_mp from blade.pm') unless $routine;
eval "package BladeFilter; $routine 1;" or BAIL_OUT("could not evaluate the routine: $@");

sub blades { return [ sort( BladeFilter::blade_nodes_from_mp(@_) ) ]; }

# xCAT::PPCdb::add_systemX writes a management module with its own name as the
# mpa and no hardware type. The mp template in xCAT/templates/e1350 writes the
# blades of that chassis with an mpa and a slot and no hardware type either,
# so the chassis is what tells the two apart.
my @chassis = (
    { node => 'amm1',    mpa => 'amm1', id => '0' },
    { node => 'blade01', mpa => 'amm1', id => '1' },
    { node => 'blade14', mpa => 'amm1', id => '14' },
);
is_deeply( blades(@chassis), [ 'blade01', 'blade14' ],
    'the blades of a chassis are asked and the chassis is not' );

# A row that gives blade as its hardware type needs no chassis.
is_deeply( blades( { node => 'x220a', nodetype => 'blade' } ), ['x220a'],
    'a row that names its hardware type is asked' );
is_deeply( blades( { node => 'x240a', nodetype => ' BLADE ' } ), ['x240a'],
    'the hardware type is read whatever its case and spacing' );

# lsslp writes the rest of this table. None of it answers a blade inventory.
foreach my $type (qw(mm cmm pbmc fsp bpa hmc ivm cec frame lpar imm2)) {
    is_deeply( blades( { node => "dev_$type", nodetype => $type } ), [],
        "a $type is not asked for a blade inventory" );
}

# Hardware that gives a type of its own is left alone even when it names a
# chassis, or a Power BMC that shares a rack with a chassis joins the inventory.
is_deeply(
    blades(
        { node => 'cmm01',  mpa => 'cmm01', nodetype => 'cmm' },
        { node => 'pbmc02', mpa => 'cmm01', nodetype => 'pbmc' },
    ),
    [],
    'a Power BMC that names a chassis is still not asked'
);

# Only a management module owns blades. A row that hangs off another blade is
# not a blade of a chassis.
is_deeply(
    blades(
        { node => 'x220a', nodetype => 'blade' },
        { node => 'weird', mpa => 'x220a' },
    ),
    ['x220a'],
    'a row whose chassis is not a management module is not asked'
);

# A management module that lsslp wrote through its cmm branch names itself and
# gives a hardware type.
is_deeply(
    blades(
        { node => 'cmm01',   mpa => 'cmm01', nodetype => 'cmm' },
        { node => 'bladeA',  mpa => 'cmm01', id => '1' },
    ),
    ['bladeA'],
    'a chassis that gives its hardware type still owns its blades'
);

# Without the chassis there is nothing to reach the blade through.
is_deeply( blades( { node => 'orphan', mpa => 'absentchassis' } ), [],
    'a row whose chassis is not in the table is not asked' );
is_deeply( blades( { node => 'lonely' } ), [],
    'a row with no hardware type and no chassis is not asked' );

# Defensive input from a table read.
is_deeply( blades(), [], 'an empty table asks nothing' );
is_deeply( blades( {}, { node => 'x220b', nodetype => 'blade' } ), ['x220b'],
    'a row without a node name is skipped' );

# The caller has to read the two attributes the routine needs, and has to stop
# before the work that reads the arp table when nothing is left to ask.
like( $source, qr/getAllNodeAttribs\(\[qw\(node nodetype mpa\)\]\)/,
    'the findme request reads the hardware type and the chassis' );
like( $source,
    qr/my \@blades\s*=\s*blade_nodes_from_mp\(\@bladents\);.*?unless \(\@blades\) \{ return; \}/s,
    'the handler returns when the table holds no blades' );

done_testing();
