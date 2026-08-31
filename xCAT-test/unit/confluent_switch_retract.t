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

# The payload the command sends for a node confluent already holds. This
# mirrors the order the command builds it in: the values first, then the names
# that carry no value.
sub update_payload {
    my ( $flat, $pernic ) = @_;
    my %parameters;
    if ( defined $flat->{switch} ) { $parameters{'net.switch'}     = $flat->{switch} }
    if ( defined $flat->{port} )   { $parameters{'net.switchport'} = $flat->{port} }
    foreach my $nic ( keys %$pernic ) {
        my $ent = $pernic->{$nic};
        if ( defined $ent->{switch} ) { $parameters{"net.$nic.switch"}     = $ent->{switch} }
        if ( defined $ent->{port} )   { $parameters{"net.$nic.switchport"} = $ent->{port} }
    }
    foreach my $topo ( 'net.switch', 'net.switchport' ) {
        $parameters{$topo} = undef unless ( exists $parameters{$topo} );
    }
    $parameters{'net.*.switch'}     = undef;
    $parameters{'net.*.switchport'} = undef;
    return \%parameters;
}

# A node xCAT holds no topology for must name every topology attribute with no
# value, so confluent removes what it still holds.
my $p = update_payload( {}, {} );
ok( exists $p->{'net.switch'},       'a node with no topology names the plain switch' );
is( $p->{'net.switch'}, undef,       'the plain switch carries no value' );
ok( exists $p->{'net.switchport'},   'a node with no topology names the plain port' );
is( $p->{'net.switchport'}, undef,   'the plain port carries no value' );
is( $p->{'net.*.switch'},     undef, 'every interface switch is named with no value' );
is( $p->{'net.*.switchport'}, undef, 'every interface port is named with no value' );

# A value the switch table holds must survive beside the names that clear.
$p = update_payload( { switch => 'sw1', port => '1' }, {} );
is( $p->{'net.switch'},     'sw1', 'a held plain switch keeps its value' );
is( $p->{'net.switchport'}, '1',   'a held plain port keeps its value' );
is( $p->{'net.*.switch'}, undef,   'the interface wildcard still clears' );

# The interface case. Confluent removes what the wildcard matches before it
# sets the rest of the request, so the current interface survives.
$p = update_payload( {}, { ib0 => { switch => 'sw2', port => '9' } } );
is( $p->{'net.ib0.switch'},     'sw2', 'the current interface keeps its switch' );
is( $p->{'net.ib0.switchport'}, '9',   'the current interface keeps its port' );
is( $p->{'net.*.switch'}, undef, 'the interface wildcard clears the rest' );
is( $p->{'net.switch'},   undef, 'a node with only an interface clears the plain switch' );

# A renamed interface: only the new name carries a value, and the wildcard
# removes the old one.
$p = update_payload( {}, { ens1f0 => { switch => 'sw3', port => '4' } } );
is( $p->{'net.ens1f0.switch'}, 'sw3', 'the new interface name carries the switch' );
ok( !exists $p->{'net.eth0.switch'}, 'the old interface name is not named on its own' );
is( $p->{'net.*.switch'}, undef, 'the old interface name is removed by the wildcard' );

# The wildcard cannot stand in for the names that carry no interface, so those
# have to be named separately. This is why both forms are in the payload.
SKIP: {
    eval { require File::FnMatch; 1 }
      or skip 'File::FnMatch not available', 1;
    ok( !File::FnMatch::fnmatch( 'net.*.switch', 'net.switch' ),
        'the interface wildcard does not match the plain name' );
}
# Same check without the optional module, using the rule the wildcard follows.
ok( 'net.switch' !~ /^net\..+\.switch$/,
    'the plain name needs its own clear because the wildcard cannot match it' );
ok( 'net.ib0.switch' =~ /^net\..+\.switch$/,
    'an interface name is what the wildcard matches' );

# The command has to clear only where there is something to clear.
my ($body) = $source =~ /\nsub donodeent \{(.*?)\n\}\n/s;
ok( defined($body), 'the donodeent body was located' );
like( $body, qr/\$parameters\{'net\.\*\.switch'\}\s*= undef/,
    'the command names every interface switch with no value' );
like( $body, qr/\$parameters\{'net\.\*\.switchport'\}\s*= undef/,
    'the command names every interface port with no value' );
like( $body, qr/\$parameters\{\$topo\} = undef unless \(exists \$parameters\{\$topo\}\)/,
    'a held value is never replaced by a clear' );

my ($updatebranch) =
  $body =~ /if \(exists \$currnodes\{\$node\}\) \{(.*?)\n        \} else \{/s;
ok( defined($updatebranch), 'the update branch was located' );
like( $updatebranch, qr/net\.\*\.switch/,
    'the clears are on the branch that updates a node confluent holds' );

my ($createbranch) = $body =~ /\n        \} else \{(.*)$/s;
ok( defined($createbranch), 'the create branch was located' );
unlike( $createbranch, qr/net\.\*\.switch/,
    'the branch that creates a node sends no clear' );

# The transport has to turn no value into a JSON null, which is what confluent
# reads as a request to remove an attribute.
my $tlv = File::Spec->catfile( $FindBin::Bin, '..', '..',
    'xCAT-server', 'lib', 'xcat', 'Confluent', 'TLV.pm' );
SKIP: {
    skip 'TLV.pm not found', 1 unless -r $tlv;
    open( my $tf, '<', $tlv ) or die $!;
    my $tsrc = do { local $/; <$tf> };
    close($tf);
    like( $tsrc, qr/\$self->\{json\}->utf8->encode\(\$data\)/,
        'the payload is encoded as JSON, which carries no value as null' );
}

done_testing();
