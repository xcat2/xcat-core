#!/usr/bin/perl
# A discovered node must be resolvable before its MAC is recorded.
#
# nodediscover.pm gated that on inet_aton($node), which answers only for IPv4. A node whose only
# address is IPv6 -- the pool node of seq_discovery_ipv6 carries ip=2001:db8:188::21 -- failed the
# gate, so process_request logged "Can not resolve IP for the matching node" and returned.
# update_discovery_data runs after every one of those early returns, so no discoverydata row was
# written, no mac was set and makedhcp never ran. Measured: tabdump discoverydata empty on
# xcat88-mn after a full seq_discovery_ipv6 run.
use strict;
use warnings;
use Test::More tests => 7;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

require xCAT::DiscoveryUtils;

can_ok( 'xCAT::DiscoveryUtils', 'discovery_address_usable' );

is( xCAT::DiscoveryUtils::discovery_address_usable('2001:db8:188::21'), 1,
    'an IPv6 address is usable, which is the whole defect' );
is( xCAT::DiscoveryUtils::discovery_address_usable('192.168.88.21'), 1,
    'an IPv4 address stays usable -- every green discovery cell depends on this' );
is( xCAT::DiscoveryUtils::discovery_address_usable(undef), 0, 'no address is not usable' );
is( xCAT::DiscoveryUtils::discovery_address_usable(''),    0, 'an empty address is not usable' );
is( xCAT::DiscoveryUtils::discovery_address_usable('seqdisc1'), 0,
    'a name that never resolved is not an address' );
# A link-local carries a scope and names no node on the provisioning network.
is( xCAT::DiscoveryUtils::discovery_address_usable('fe80::1%eth0'), 0,
    'a scoped link-local is not usable' );
