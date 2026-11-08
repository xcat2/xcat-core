#!/usr/bin/env perl
# One node has up to four DHCPv6 clients and one IPv6 address: the firmware, iPXE, the Genesis
# image and the installed OS. A Kea reservation holds the address for ONE identifier, and Kea
# refuses the same address on a second reservation -- "There's already reservation for this
# address/prefix" -- so a reservation cannot answer them all.
#
# Measured on 2026-11-08: the OpenEmbedded Genesis image sends the DUID-UUID in firmware byte
# order, not the DUID-LL that dhcp6_client_duid_list assumes. It therefore matched the reservation
# that holds no address, took 2001:db8:188::1005 from the dynamic pool, and xcatd could not name
# it -- CERTIFICATE_ACTION_FAILED, "Node unassigned".
#
# A client class can match every DUID form of the node, and a pool of one address can be gated on
# that class, so the address reaches whichever client solicits. A reserved address is excluded
# from every pool, so the address must leave the reservation for the gate to work.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;
use xCAT::DHCP::BootPolicy;

my $NODE     = 'cn01';
my $IP       = '2001:db8:188::20';
my $FIRMWARE = '00:04:0c:3f:8d:41:6a:52:4e:7b:9f:10:2d:8c:54:ab:77:31';
my $IPXE     = '00:04:41:8d:3f:0c:52:6a:7b:4e:9f:10:2d:8c:54:ab:77:31';
my $LL       = '00:03:00:01:42:41:09:50:e8:a6';

can_ok( 'xCAT::DHCP::BootPolicy', 'kea_node_address_class6' );
can_ok( 'xCAT::DHCP::BootPolicy', 'kea_node_address_pool6' );

# The raw answer, so an assertion on emptiness cannot be satisfied by a missing subroutine.
sub addr_class {
    my (%opts) = @_;
    my $out = eval { xCAT::DHCP::BootPolicy->kea_node_address_class6(%opts) };
    diag($@) if $@;
    return $out;
}

sub addr_pool {
    my (%opts) = @_;
    my $out = eval { xCAT::DHCP::BootPolicy->kea_node_address_pool6(%opts) };
    diag($@) if $@;
    return $out;
}

my $class = addr_class( node => $NODE, duids => [ $FIRMWARE, $IPXE, $LL ] );

is( ref($class), 'HASH', 'a node with several DUID forms gets one address class' );
is( ( $class || {} )->{name}, "$NODE-addr6", 'the class is named after the node' );

my $test = ( $class || {} )->{test} || '';
foreach my $duid ( $FIRMWARE, $IPXE, $LL ) {
    ( my $hex = $duid ) =~ s/://g;
    ok( ( length($test) && index( $test, "0x$hex" ) >= 0 ),
        "the class matches the DUID $duid" );
}
ok( ( length($test) && $test =~ /\boption\[1\]\.hex\b/ ),
    'the class reads the client identifier option' );
ok( ( length($test) && $test =~ /\bor\b/ ),
    'the DUID forms are alternatives, so any one of them matches' );

is_deeply(
    ( $class || {} )->{'user-context'},
    { 'xcat-node' => $NODE, 'xcat-purpose' => 'addr6' },
    'the class is tagged, so a later makedhcp can find and replace it'
);

# A node with one client holds its address in its reservation, and needs no pool of its own.
is_deeply( addr_class( node => $NODE, duids => [$FIRMWARE] ),
    undef, 'a node with one DUID form gets no address class' );
is_deeply( addr_class( node => $NODE, duids => [] ),
    undef, 'a node with no DUID gets no address class' );
is_deeply( addr_class( duids => [ $FIRMWARE, $IPXE ] ),
    undef, 'an address class needs the node name' );

my $pool = addr_pool( node => $NODE, ip => $IP );
is( ref($pool), 'HASH', 'the node gets a pool of its own address' );
is( ( $pool || {} )->{pool}, "$IP - $IP",
    'the pool holds exactly the address of the node' );
is( ( $pool || {} )->{'client-class'}, "$NODE-addr6",
    'the pool is gated on the address class, so no other node can take the address' );
is_deeply( addr_pool( node => $NODE ), undef, 'a pool needs an address' );
is_deeply( addr_pool( ip => $IP ),     undef, 'a pool needs the node name' );

done_testing();
