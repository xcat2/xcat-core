#!/usr/bin/env perl
#
# The router advertisement an IPv6 provision network needs.
#
# makedhcp writes the DHCPv6 reservations and nothing announces the prefix or the route.
# Measured on an IPv6-only alma10.1 cluster: iPXE sends a router solicitation and uses DHCPv6
# only when an advertisement sets the managed flag, so with no advertisement it answered
# "No configuration methods succeeded" and never solicited; and a diskless node that did
# solicit got one address with prefix_len=128 and no route.
use strict;
use warnings;

use FindBin;
use Test::More tests => 10;

use lib "$FindBin::Bin/../../perl-xCAT";
use xCAT::NetworkUtils;

my $one = xCAT::NetworkUtils::radvd_config(
    [ { interface => 'eth1', prefix => '2001:db8:149::/64' } ] );

like( $one, qr{^interface eth1$}m, 'the advertisement names the interface xCAT serves' );
like( $one, qr{prefix 2001:db8:149::/64}, 'and the prefix of the network' );

# Without the managed flag a client never starts DHCPv6, which is what stopped iPXE.
like( $one, qr{AdvManagedFlag on;}, 'the managed flag sends the client to DHCPv6' );
like( $one, qr{AdvSendAdvert on;}, 'and the advertisement is actually sent' );

# The address comes from DHCPv6, which holds the reservations. An autonomous prefix would
# give the node a second, unreserved address by SLAAC.
like( $one, qr{AdvAutonomous off;}, 'the prefix is not autonomous, so DHCPv6 keeps the address' );
like( $one, qr{AdvOnLink on;}, 'the prefix is on-link, which is what gives the node its route' );

# A cluster can serve more than one IPv6 network.
my $two = xCAT::NetworkUtils::radvd_config( [
    { interface => 'eth1', prefix => '2001:db8:149::/64' },
    { interface => 'eth2', prefix => '2001:db8:150::/64' },
] );
like( $two, qr{interface eth1}, 'two networks give two interfaces' );
like( $two, qr{interface eth2}, 'and the second one is named too' );

# An IPv4 cluster must get no configuration at all, or radvd would be started for nothing.
is( xCAT::NetworkUtils::radvd_config( [ { interface => 'eth1', prefix => '192.168.1.0/24' } ] ),
    undef, 'an IPv4 network yields no configuration' );
is( xCAT::NetworkUtils::radvd_config( [] ), undef,
    'a cluster with no IPv6 network yields no configuration' );
