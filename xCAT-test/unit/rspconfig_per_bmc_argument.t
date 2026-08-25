#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;
use lib File::Spec->catdir( $FindBin::Bin, '..', '..',
    'xCAT-server', 'lib', 'perl' );
use xCAT::BMCUtils;

sub setting {
    my ( $subcommand, $argument, $bmcnum ) = @_;
    return xCAT::BMCUtils::rspconfig_bmc_setting(
        $subcommand, $argument, $bmcnum );
}

sub pick {
    my ( $argument, $bmcnum ) = @_;
    return setting( 'ip', $argument, $bmcnum )->{argument};
}

my $per_bmc = {};
foreach my $subcommand (qw(ip netmask gateway community snmpdest alert garp thermprofile)) {
    my $selection = setting( $subcommand, 'first,second', 1 );
    $per_bmc->{$subcommand} = exists $selection->{session_subcommand};
}

# A single value reaches every BMC, which is what a node with one BMC needs
# and what every existing command line looks like.
is( pick( '10.0.0.5', 1 ), '10.0.0.5', 'a single value serves the first BMC' );
is( pick( '10.0.0.5', 2 ), '10.0.0.5', 'a single value serves a later BMC too' );

# A list gives one setting per BMC, in session order.
is( pick( '10.0.0.5,10.0.0.6', 1 ), '10.0.0.5', 'the first BMC takes the first value' );
is( pick( '10.0.0.5,10.0.0.6', 2 ), '10.0.0.6', 'the second BMC takes the second value' );
is( pick( '10.0.0.5,10.0.0.6,10.0.0.7', 3 ), '10.0.0.7', 'the third BMC takes the third value' );

# A list too short reports nothing rather than an empty setting, so the caller
# can tell the operator instead of writing a blank value into a BMC.
is( pick( '10.0.0.5,10.0.0.6', 3 ), undef, 'a list shorter than the BMC number yields nothing' );

# An empty element carries no setting, so it reads as missing rather than
# reaching the address encoders, which reject an empty string outright.
is( pick( '10.0.0.5,', 2 ), undef, 'an empty element yields nothing' );
is( pick( ',10.0.0.6', 1 ), undef, 'a leading empty element yields nothing' );

# Defensive input.
is( pick( undef, 1 ), undef, 'an undefined argument stays undefined' );
is( pick( '10.0.0.5,10.0.0.6' ), '10.0.0.5', 'a missing BMC number reads as the first' );
is( pick( '10.0.0.5,10.0.0.6', 0 ), '10.0.0.5', 'a zero BMC number reads as the first' );

# The netmask and gateway settings travel the same path.
is( pick( '255.255.255.0,255.255.254.0', 2 ), '255.255.254.0', 'a netmask list follows the BMC number' );

# Only the settings the man page advertises take a list. Every other
# subcommand keeps its argument whole, because a comma can belong to the value,
# as it does in a free form SNMP community string.
ok( $per_bmc->{$_},  "$_ takes one value per BMC" )      for qw(ip netmask gateway);
ok( !$per_bmc->{$_}, "$_ keeps its argument whole" )     for qw(community snmpdest alert garp thermprofile);

my $selected = setting( 'ip', '10.0.0.5,10.0.0.6', 2 );
is( $selected->{session_subcommand}, 'ip=10.0.0.6',
    'the follow-up subcommand holds the value of its own BMC' );
ok( !exists $selected->{error}, 'a complete list reports no mismatch' );

my $short = setting( 'gateway', '10.0.0.1,10.0.0.2', 3 );
like( $short->{error}, qr/does not carry a setting for BMC 3/,
    'a short list reports which BMC has no setting' );

my $thermal = setting( 'thermprofile', 'balanced,maximum', 2 );
is( $thermal->{argument}, 'balanced,maximum',
    'the thermal profile keeps its argument whole' );
ok( !exists $thermal->{session_subcommand},
    'the thermal profile does not rewrite the session' );

done_testing();
