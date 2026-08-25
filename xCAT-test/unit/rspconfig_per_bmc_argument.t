#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $plugin = File::Spec->catfile( $root,
    'xCAT-server', 'lib', 'xcat', 'plugins', 'ipmi.pm' );
plan skip_all => 'ipmi.pm not found' unless -r $plugin;

my $lib = File::Spec->catdir( $root, 'xCAT-server', 'lib', 'perl' );
my $module = File::Spec->catfile( $lib, 'xCAT', 'BMCUtils.pm' );
my $direct_module = -r $module;
my ( $source, $per_bmc );

if ($direct_module) {
    unshift @INC, $lib;
    require xCAT::BMCUtils;
} else {
    open( my $fh, '<', $plugin ) or die "Unable to read $plugin: $!";
    $source = do { local $/; <$fh> };
    close($fh);

    my ($routine) = $source =~ /(sub per_bmc_argument \{.*?\n\}\n)/s;
    my ($gate)    = $source =~ /(my %per_bmc_subcommand = map.*?;)/s;
    BAIL_OUT('could not extract per_bmc_argument from ipmi.pm') unless $routine;
    BAIL_OUT('could not extract the per BMC subcommand set from ipmi.pm') unless $gate;
    eval "package BmcArg; $gate $routine sub gate { return \\%per_bmc_subcommand } 1;"
      or BAIL_OUT("could not evaluate per_bmc_argument: $@");
    $per_bmc = BmcArg::gate();
}

sub setting {
    my ( $subcommand, $argument, $bmcnum ) = @_;
    if ($direct_module) {
        return xCAT::BMCUtils::rspconfig_bmc_setting(
            $subcommand, $argument, $bmcnum );
    }
    return { argument => $argument }
      unless $per_bmc->{$subcommand} and defined $argument and $argument =~ /,/;
    my $value = BmcArg::per_bmc_argument( $argument, $bmcnum );
    return { error => 1 } unless defined $value;
    return {
        argument           => $value,
        session_subcommand => "$subcommand=$value",
    };
}

sub pick {
    my ( $argument, $bmcnum ) = @_;
    return setting( 'ip', $argument, $bmcnum )->{argument};
}

if ($direct_module) {
    $per_bmc = {};
    foreach my $subcommand (qw(ip netmask gateway community snmpdest alert garp thermprofile)) {
        my $selection = setting( $subcommand, 'first,second', 1 );
        $per_bmc->{$subcommand} = exists $selection->{session_subcommand};
    }
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

unless ($direct_module) {
    like( $source, qr/if \(\$per_bmc_subcommand\{\$subcommand\} and \$argument =~ \/,\/\)/,
        'the caller splits only the settings that take a list' );

    # The follow-up callbacks read the subcommand again, so the session has to
    # hold the value of its own BMC by then.
    like( $source, qr/\$sessdata->\{subcommand\} = "\$subcommand=\$argument";/,
        'the session keeps the value of its own BMC for the follow-up' );

    like( $source,
        qr/unless \(defined \$bmcvalue\) \{\s*\n\s*\$callback->\(\{ errorcode => \[1\], error => \["The value \$argument does not carry a setting for BMC/,
        'the caller reports a short list instead of sending it' );
    like( $source, qr/if \(\$subcommand eq "thermprofile"\) \{\n\s*return idpxthermprofile\(\$argument\);/,
        'the thermal profile is answered before the per BMC split' );
}

done_testing();
