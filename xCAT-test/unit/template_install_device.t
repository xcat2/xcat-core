#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

my $root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
BEGIN {
    push @INC,
      File::Spec->catdir( $FindBin::Bin, '..', '..', 'perl-xCAT' ),
      File::Spec->catdir( $FindBin::Bin, '..', '..', 'xCAT-server', 'lib', 'perl' );
}

eval { require xCAT::Template; 1 }
  or plan skip_all => "xCAT::Template not loadable: $@";

my $NODE = 'n1';
my $MAC1 = 'AA:BB:CC:DD:EE:01';
my $MAC2 = 'AA:BB:CC:DD:EE:02';

# The order is installnic, then primarynic, then mac.mac. Either attribute may
# name an interface or carry an address.
my $p = xCAT::Template::install_device_params( '', '', $MAC1, $NODE );
is( $p->{mac}, $MAC1, 'with neither attribute set the address comes from mac.mac' );
is( $p->{nicname}, undef, 'with neither attribute set no interface is named' );

$p = xCAT::Template::install_device_params( 'eth1', '', $MAC1, $NODE );
is( $p->{nicname}, 'eth1', 'installnic naming an interface wins' );
is( $p->{mac},     $MAC1,  'the address is still resolved alongside the interface' );

$p = xCAT::Template::install_device_params( '', 'eth2', $MAC1, $NODE );
is( $p->{nicname}, 'eth2', 'primarynic is used when installnic is not set' );

$p = xCAT::Template::install_device_params( 'eth1', 'eth2', $MAC1, $NODE );
is( $p->{nicname}, 'eth1', 'installnic beats primarynic' );

$p = xCAT::Template::install_device_params( $MAC2, '', $MAC1, $NODE );
is( $p->{mac},     $MAC2,  'installnic carrying an address names that address' );
is( $p->{nicname}, undef,  'installnic carrying an address names no interface' );

$p = xCAT::Template::install_device_params( 'mac', '', $MAC1, $NODE );
is( $p->{mac},     $MAC1, 'the keyword mac falls back to mac.mac' );
is( $p->{nicname}, undef, 'the keyword mac names no interface' );

# A mac.mac entry may hold several addresses. The entry tagged with the node
# name is the one that belongs to the node.
$p = xCAT::Template::install_device_params( '', '', "$MAC1!$NODE|$MAC2!other", $NODE );
is( $p->{mac}, $MAC1, 'the tagged entry for the node is selected' );

# Ubuntu keeps its own return shape over the same resolution.
my ( $setname, $macaddress ) =
  xCAT::Template::subiquity_install_netcfg( 'eth1', '', $MAC1, $NODE );
is( $setname,    'eth1',      'netplan is given the interface to rename to' );
is( $macaddress, lc($MAC1),   'netplan is given the address, lower cased' );

( $setname, $macaddress ) =
  xCAT::Template::subiquity_install_netcfg( '', '', $MAC1, $NODE );
is( $setname,    '',        'netplan renames nothing when no interface is named' );
is( $macaddress, lc($MAC1), 'netplan still matches on the address' );

# The kickstart names one device. It takes the interface when one is named and
# the address otherwise, and it lower cases either.
sub ks_device {
    my ( $installnic, $primarynic, $macentry, $nodename ) = @_;
    my $params =
      xCAT::Template::install_device_params( $installnic, $primarynic, $macentry, $nodename );
    my $macaddr = defined( $params->{mac} ) ? lc( $params->{mac} ) : '';
    return defined( $params->{nicname} ) ? $params->{nicname} : $macaddr;
}

is( ks_device( '', '', $MAC1, $NODE ), lc($MAC1),
    'a node setting neither attribute keeps the address it has today' );
is( ks_device( 'eth1', '', $MAC1, $NODE ), 'eth1',
    'a node setting installnic names that interface' );
is( ks_device( $MAC2, '', $MAC1, $NODE ), lc($MAC2),
    'a node whose installnic carries an address names that address' );

# The defect this closes: a bare multi address entry resolves to the LAST
# address, which need not be the adapter that deploys the node. Setting
# installnic must override that.
my $BARE = "$MAC1|$MAC2";
is( ks_device( '', '', $BARE, $NODE ), lc($MAC2),
    'a bare multi address entry alone still resolves to the last address' );
is( ks_device( 'eth0', '', $BARE, $NODE ), 'eth0',
    'installnic overrides a bare multi address entry' );

# An interface name is case sensitive. A node on POWER carries names such as
# enP1p12s0f0, which no longer name a device once they are lower cased. Only
# an address may be lower cased.
my $MIXED = 'enP1p12s0f0';
is( ks_device( $MIXED, '', $MAC1, $NODE ), $MIXED,
    'the kickstart keeps the case of the interface name' );
is( ks_device( '', $MIXED, $MAC1, $NODE ), $MIXED,
    'the kickstart keeps the case of a primarynic interface name' );
my ($mixedset) = xCAT::Template::subiquity_install_netcfg( $MIXED, '', $MAC1, $NODE );
is( $mixedset, $MIXED, 'Ubuntu keeps the case of the interface name too' );
is( ks_device( '', '', uc($MAC1), $NODE ), lc($MAC1),
    'an address is still lower cased' );

# The source has to keep the unique local address built from the hardware
# address, not from the device name.
my $src = File::Spec->catfile( $root, 'xCAT-server', 'lib', 'perl', 'xCAT', 'Template.pm' );
open( my $fh, '<', $src ) or die "Unable to read $src: $!";
my $source = do { local $/; <$fh> };
close($fh);

my ($ksbody) = $source =~ /\nsub kickstartnetwork \{(.*?)\n\}\n/s;
ok( defined($ksbody), 'the kickstartnetwork body was located' );

like( $ksbody, qr/install_device_params\(/,
    'the kickstart resolves the device through the shared helper' );
unlike( $ksbody, qr/parseMacTabEntry/,
    'the kickstart no longer names the device from mac.mac alone' );
like( $ksbody, qr/my \$ulaaddr = autoulaaddress\(\$macaddr\)/,
    'the unique local address is built from the address, not the device name' );
unlike( $ksbody, qr/lc\(\$params->\{nicname\}\)/,
    'the kickstart never lower cases the interface name' );
my ($ubbody) = $source =~ /\nsub subiquity_install_netcfg \{(.*?)\n\}\n/s;
ok( defined($ubbody), 'the subiquity_install_netcfg body was located' );
like( $ubbody, qr/install_device_params\(/, 'Ubuntu shares the same helper' );
unlike( $ubbody, qr/gen_net_boot_params|parseMacTabEntry/,
    'Ubuntu no longer re-derives the resolution itself' );

done_testing();
