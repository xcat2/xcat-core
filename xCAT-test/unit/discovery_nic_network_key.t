#!/usr/bin/perl
# Which network a discovered NIC is on, for either address family.
#
# nodediscover.pm computed this with unpack("N", inet_aton($ip)) behind an
# if ($ip =~ /\d+\.\d+\.\d+\.\d+/) gate, so a NIC reported as 2001:db8:188::31/64 skipped the
# branch entirely, $localnic stayed 0 and process_request returned "No nic found in deploy
# network". The OpenEmbedded image sends address=${ipv4_address:-$ipv6_address}, so over IPv6 the
# NIC record carries the v6 address.
use strict;
use warnings;
use Test::More tests => 8;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

require xCAT::DiscoveryUtils;

can_ok( 'xCAT::DiscoveryUtils', 'nic_network_key' );

# IPv4 must come out byte-for-byte as the old arithmetic did.
is( xCAT::DiscoveryUtils::nic_network_key( '10.0.0.212', 8 ), '10.0.0.0',
    'an IPv4 nic keys on its network, as before' );
is( xCAT::DiscoveryUtils::nic_network_key( '192.168.88.21', 24 ), '192.168.88.0',
    'and at a /24' );

is( xCAT::DiscoveryUtils::nic_network_key( '2001:db8:188::31', 64 ), '2001:db8:188::',
    'an IPv6 nic keys on its network' );
# A prefix that is not a whole number of bytes must mask bits, not bytes.
is( xCAT::DiscoveryUtils::nic_network_key( '2001:db8:188:1::5', 60 ), '2001:db8:188::',
    'a /60 masks within the fourth group' );
is( xCAT::DiscoveryUtils::nic_network_key( '2001:db8:188:1::5', 64 ), '2001:db8:188:1::',
    'and the same address at /64 is a different network' );

is( xCAT::DiscoveryUtils::nic_network_key( 'not-an-address', 64 ), undef,
    'a value that is no address keys nothing' );
is( xCAT::DiscoveryUtils::nic_network_key( undef, 64 ), undef, 'and neither does no address' );
