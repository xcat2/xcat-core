#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $root   = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $plugin = File::Spec->catfile( $root, 'xCAT-server', 'lib', 'xcat',
    'plugins', 'blade.pm' );
plan skip_all => 'blade.pm not found' unless -r $plugin;

open( my $fh, '<', $plugin ) or die "Unable to read $plugin: $!";
my $source = do { local $/; <$fh> };
close($fh);

# blade.pm needs a management node to load in full, so drive the entry decision
# on its own. The preprocessor answers a request before it reads any table, and
# that answer is what decides whether the findme handler ever runs.
my ($entry) = $source =~
  /(sub preprocess_request \{.*?\n    if \(\$command eq 'findme'\) \{ return \[\$request\]; \})/s;
BAIL_OUT('blade.pm does not hand a findme request on before the noderange check')
  unless $entry;

$entry .= "\n    return 'REACHED-NODERANGE-CHECK';\n}\n";
eval "package BladeEntry; $entry 1;" or BAIL_OUT("could not evaluate the entry: $@");

sub entry_for {
    my ($req) = @_;
    my @said;
    my $r = BladeEntry::preprocess_request( $req, sub { push @said, $_[0] } );
    return ( $r, \@said );
}

# This is the request a booting node sends: a command and its own details, and
# no node, because the node is what the request asks xCAT to find.
my ( $got, $said ) = entry_for(
    {
        command => ['findme'],
        arch    => ['x86_64'],
        uuid    => ['00000000-0000-0000-0000-000000000000'],
    }
);
is( ref $got, 'ARRAY', 'a findme request is handed on to the handler' );
is( scalar @$said, 0, 'a findme request draws no error from the preprocessor' );

# The request that comes back has to be the one that arrived, or the handler
# loses the client address that it matches the node by.
is( $got->[0]->{command}->[0], 'findme', 'the request that is handed on is the findme request' );

# A request that was already preprocessed elsewhere is still handed on.
( $got, $said ) = entry_for(
    { command => ['findme'], _xcatpreprocessed => [1] } );
is( ref $got, 'ARRAY', 'an already preprocessed findme request is handed on' );

# Every other command keeps the noderange requirement.
foreach my $command (qw(rpower rinv rvitals rbeacon)) {
    my ( $other, undef ) = entry_for( { command => [$command] } );
    isnt( ref $other, 'ARRAY',
        "a $command request without a noderange is not handed on" );
}

# The preprocessor used to drop a node from a findme request by its hardware
# type. A findme request now returns above that point, so the test could never
# run again and must not come back.
unlike( $source, qr/eq 'findme' and \$ent->\{nodetype\}/,
    'the preprocessor holds no findme test that cannot run' );

done_testing();
