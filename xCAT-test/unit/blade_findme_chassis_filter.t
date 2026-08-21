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

# blade.pm cannot be loaded here, so lift out the routine and drive the real
# code on its own.
my ($routine) = $source =~ /(sub blade_nodes_from_mp \{.*?\n\}\n)/s;
BAIL_OUT('could not extract blade_nodes_from_mp from blade.pm') unless $routine;
eval "package BladeFilter; $routine 1;" or BAIL_OUT("could not evaluate the routine: $@");

sub blades { return BladeFilter::blade_nodes_from_mp(@_); }

# A chassis holds its management modules in the same table as its blades. Only
# the blades answer a blade inventory.
is_deeply(
    [ blades(
        { node => 'blade01', nodetype => 'blade' },
        { node => 'cmm01',   nodetype => 'cmm' },
        { node => 'blade02', nodetype => 'blade' },
        { node => 'mm01',    nodetype => 'mm' },
    ) ],
    [ 'blade01', 'blade02' ],
    'the management modules are left out of the inventory'
);

# The attribute is optional, so a row that names no hardware type still takes
# part, as it did before.
is_deeply(
    [ blades(
        { node => 'blade01' },
        { node => 'blade02', nodetype => undef },
        { node => 'blade03', nodetype => '' },
    ) ],
    [ 'blade01', 'blade02', 'blade03' ],
    'a row without a hardware type is kept'
);

# xCAT::PPCdb::add_systemX writes a management module that SLP found with an
# mpa of its own name, an id of 0 and no hardware type at all.
is_deeply(
    [ blades( { node => 'amm01', mpa => 'amm01', id => '0' } ) ], [],
    'a discovered management module without a hardware type is left out'
);

# The mp template that ships in xCAT/templates/e1350 gives its blades an mpa
# and a slot but no hardware type. Those rows are blades.
is_deeply(
    [ blades(
        { node => 'blade01', mpa => 'amm1', id => '1' },
        { node => 'amm1',    mpa => 'amm1', id => '0' },
        { node => 'blade14', mpa => 'amm1', id => '14' },
    ) ],
    [ 'blade01', 'blade14' ],
    'the chassis is left out and its blades are kept'
);

# The self reference decides, not the slot. A management module keeps its
# place whatever slot it gives, and a blade in slot 0 stays a blade.
is_deeply(
    [ blades( { node => 'mm01', mpa => 'mm01', id => '1' } ) ], [],
    'a management module with a slot is still left out' );
is_deeply(
    [ blades( { node => 'blade00', mpa => 'amm1', id => '0' } ) ], [ 'blade00' ],
    'a blade in slot 0 is kept' );

# A blade names another node as its management module.
is_deeply(
    [ blades( { node => 'cmm01', mpa => 'cmm01', nodetype => 'cmm' } ) ], [],
    'a management module is left out by its mpa as well as its type' );
is_deeply(
    [ blades( { node => 'blade01', mpa => undef } ) ], [ 'blade01' ],
    'a row that gives no mpa is kept' );

# The value comes from a table an operator writes by hand.
is_deeply( [ blades( { node => 'cmm01', nodetype => 'CMM' } ) ], [],
    'the hardware type is read whatever its case' );
is_deeply( [ blades( { node => 'mm01', nodetype => ' mm ' } ) ], [],
    'the hardware type is read around its spaces' );

# Only the two documented management module types go. A different value keeps
# the behaviour it had before, because the filter must not decide for a value
# that the schema does not give.
is_deeply( [ blades( { node => 'amm01', nodetype => 'amm' } ) ], [ 'amm01' ],
    'a hardware type that is not documented is left alone' );

# A name that merely contains the word is a blade, not a management module.
is_deeply( [ blades( { node => 'mm01', nodetype => 'blade' } ) ], [ 'mm01' ],
    'the hardware type decides, not the node name' );
is_deeply( [ blades( { node => 'commsblade', nodetype => 'blade' } ) ], [ 'commsblade' ],
    'a node name holding the word mm is kept' );

# Defensive input from a table read.
is_deeply( [ blades() ], [], 'an empty table yields no blades' );
is_deeply( [ blades( {}, { node => 'blade01', nodetype => 'blade' } ) ], [ 'blade01' ],
    'a row without a node name is skipped' );

# The caller reads both attributes, or the filter has nothing to work with,
# and the inventory request asks for the nodes that the filter gave back.
like( $source, qr/getAllNodeAttribs\(\[qw\(node nodetype mpa\)\]\)/,
    'the findme request reads the hardware type and the mpa from the table' );
like( $source,
    qr/my \@blades\s*=\s*blade_nodes_from_mp\(\@bladents\);.*?\$invreq\{node\}\s*=\s*\\\@blades;/s,
    'the inventory request carries the nodes that the filter kept' );

done_testing();
