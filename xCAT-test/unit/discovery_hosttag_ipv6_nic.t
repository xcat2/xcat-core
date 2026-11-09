#!/usr/bin/perl
# The hostname tag for a discovered IPv6 NIC.
#
# The IPv4 path asks gethosttag, which reads an A record and my_if_netmap -- netstat -rn, which
# prints IPv4 routes only. So the decision for an IPv6 nic is made from the addresses themselves:
# a nic in the same network as the node's own address IS the node, and that is what sets
# $localnic and stops process_request returning "No nic found in deploy network".
use strict;
use warnings;
use Test::More tests => 10;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

require xCAT::DiscoveryUtils;

can_ok( 'xCAT::DiscoveryUtils', 'hosttag_for_ipv6_nic' );

my %used;
is( xCAT::DiscoveryUtils::hosttag_for_ipv6_nic(
        'seqdisc1', '2001:db8:188::21', 'eth0', '2001:db8:188::31', 64, \%used ),
    'seqdisc1', 'a nic in the network of the node is the node itself' );

is( xCAT::DiscoveryUtils::hosttag_for_ipv6_nic(
        'seqdisc1', '2001:db8:188::21', 'eth1', '2001:db8:99::31', 64, \%used ),
    undef, 'a nic on another network is not the node' );

# The v4 path owns a v4 nic; this helper must not answer for one.
is( xCAT::DiscoveryUtils::hosttag_for_ipv6_nic(
        'seqdisc1', '2001:db8:188::21', 'eth0', '192.168.88.31', 24, \%used ),
    undef, 'an IPv4 nic is left to the IPv4 path' );

is( xCAT::DiscoveryUtils::hosttag_for_ipv6_nic(
        'seqdisc1', undef, 'eth0', '2001:db8:188::31', 64, \%used ),
    undef, 'with no address for the node there is nothing to compare' );

# A second nic on the node's own network must not claim the node's name twice.
my %taken = ( seqdisc1 => 1 );
is( xCAT::DiscoveryUtils::hosttag_for_ipv6_nic(
        'seqdisc1', '2001:db8:188::21', 'eth2', '2001:db8:188::32', 64, \%taken ),
    'seqdisc1-eth2', 'a second nic on that network takes an interface-qualified name' );

# NetworkManager installs a DHCPv6 lease as a /128 and takes the on-link route from the router
# advertisement, so Genesis reports the boot nic as 2001:db8:188::1004/128. A /128 names one
# address and no network, so the network comes from the xCAT networks table.
my @networks = ( [ '2001:db8:188::', 64 ] );
my %fresh;
is( xCAT::DiscoveryUtils::hosttag_for_ipv6_nic(
        'seqdisc1', '2001:db8:188::21', 'eth0', '2001:db8:188::1004', 128, \%fresh, \@networks ),
    'seqdisc1', 'a /128 DHCPv6 lease in the network of the node is the node itself' );

is( xCAT::DiscoveryUtils::hosttag_for_ipv6_nic(
        'seqdisc1', '2001:db8:188::21', 'eth0', '2001:db8:99::1004', 128, \%fresh, \@networks ),
    undef, 'a /128 lease on another network is not the node' );

is( xCAT::DiscoveryUtils::hosttag_for_ipv6_nic(
        'seqdisc1', '2001:db8:188::21', 'eth0', '2001:db8:188::1004', 128, \%fresh ),
    undef, 'with no networks to compare a /128 against, it is not the node' );

# The rows as makenetworks writes them: an IPv6 net carries its own /len and the mask is /len.
is_deeply( xCAT::DiscoveryUtils::ipv6_networks( [
            { net => '192.168.88.0',      mask => '255.255.255.0' },
            { net => '2001:db8:188::/64', mask => '/64' },
            { net => '2001:db8:99::',     mask => '/56' },
        ] ),
    [ [ '2001:db8:188::', 64 ], [ '2001:db8:99::', 56 ] ],
    'the IPv6 rows of the networks table, with the IPv4 row left out' );
