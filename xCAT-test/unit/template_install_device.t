#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

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
is( $setname,    'eth1',    'netplan is given the interface to rename to' );
is( $macaddress, lc($MAC1), 'netplan is given the address, lower cased' );

( $setname, $macaddress ) =
  xCAT::Template::subiquity_install_netcfg( '', '', $MAC1, $NODE );
is( $setname,    '',        'netplan renames nothing when no interface is named' );
is( $macaddress, lc($MAC1), 'netplan still matches on the address' );

{
    package Local::TemplateInstallTable;

    sub getNodeAttribs {
        my ($self) = @_;
        return $self->{row};
    }

    sub setNodeAttribs {
        my ( $self, undef, $attrs ) = @_;
        $self->{written} = { %{$attrs} };
        return 1;
    }
}

# Exercise kickstartnetwork itself with in-memory table objects. This verifies
# the generated kickstart line rather than the text of Template.pm.
sub kickstart_network {
    my ( $installnic, $primarynic, $macentry, $mode ) = @_;

    my $mactab = bless { row => { mac => $macentry } }, 'Local::TemplateInstallTable';
    my $nrtab = bless {
        row => {
            installnic => $installnic,
            primarynic => $primarynic,
        }
      },
      'Local::TemplateInstallTable';
    my $hoststab = bless {}, 'Local::TemplateInstallTable';
    my $autoula_mac;

    no warnings qw(redefine once);
    local *xCAT::Table::new = sub {
        my ( undef, $table ) = @_;
        return $mactab   if $table eq 'mac';
        return $nrtab    if $table eq 'noderes';
        return $hoststab if $table eq 'hosts';
        die "Unexpected table $table";
    };
    local *xCAT::Template::autoulaaddress = sub {
        ($autoula_mac) = @_;
        return 'fd00::1';
    };
    local $::XCATSITEVALS{managedaddressmode} = $mode || 'dhcp';

    my $line = xCAT::Template::kickstartnetwork();
    return ( $line, $autoula_mac, $hoststab->{written} );
}

sub ks_device {
    my ($line) = kickstart_network(@_);
    return $line =~ /--device=(\S+)/ ? $1 : undef;
}

is( ks_device( '', '', $MAC1 ), lc($MAC1),
    'a node setting neither attribute keeps the address it has today' );
is( ks_device( 'eth1', '', $MAC1 ), 'eth1',
    'a node setting installnic names that interface' );
is( ks_device( $MAC2, '', $MAC1 ), lc($MAC2),
    'a node whose installnic carries an address names that address' );

# The defect this closes: a bare multi address entry resolves to the LAST
# address, which need not be the adapter that deploys the node. Setting
# installnic must override that.
my $BARE = "$MAC1|$MAC2";
is( ks_device( '', '', $BARE ), lc($MAC2),
    'a bare multi address entry alone still resolves to the last address' );
is( ks_device( 'eth0', '', $BARE ), 'eth0',
    'installnic overrides a bare multi address entry' );

# An interface name is case sensitive. A node on POWER carries names such as
# enP1p12s0f0, which no longer name a device once they are lower cased. Only
# an address may be lower cased.
my $MIXED = 'enP1p12s0f0';
is( ks_device( $MIXED, '', $MAC1 ), $MIXED,
    'the kickstart keeps the case of the interface name' );
is( ks_device( '', $MIXED, $MAC1 ), $MIXED,
    'the kickstart keeps the case of a primarynic interface name' );
my ($mixedset) = xCAT::Template::subiquity_install_netcfg( $MIXED, '', $MAC1, $NODE );
is( $mixedset, $MIXED, 'Ubuntu keeps the case of the interface name too' );
is( ks_device( '', '', uc($MAC1) ), lc($MAC1),
    'an address is still lower cased' );

# autoula must derive the address from the hardware address even when the
# kickstart selects an interface by name.
my ( $autoula_line, $autoula_mac, $hostattrs ) =
  kickstart_network( $MIXED, '', $MAC1, 'autoula' );
is( $autoula_line,
    "network --onboot=yes --bootproto=static --device=$MIXED --noipv4 --ipv6=fd00::1",
    'autoula keeps the selected interface in the kickstart line' );
is( $autoula_mac, lc($MAC1),
    'autoula derives the address from the MAC, not the interface name' );
is( $hostattrs->{ip}, 'fd00::1', 'the generated ULA is saved in the hosts table' );

done_testing();
