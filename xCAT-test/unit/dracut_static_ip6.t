#!/usr/bin/env perl
#
# The dracut ip= parameter of an IPv6-only node.
#
# either6 asks dracut for DHCPv6. DHCPv6 assigns one address with a prefix length of 128 and
# carries no route, and an xCAT provision network sends no router advertisement: radvd is not
# installed and net.ipv6.conf.<nic>.forwarding is 0. A node configured that way has an address
# and no route, and the dracut hook that fetches the root image reports
# "Connecting to [2001:db8:147::1]:80... failed: Network is unreachable." Measured on an
# IPv6-only Ubuntu 24.04 node, whose Kea lease records prefix_len=128.
use strict;
use warnings;

use FindBin;
use Test::More tests => 9;

use lib "$FindBin::Bin/../../perl-xCAT";
use xCAT::NetworkUtils;

is( xCAT::NetworkUtils::dracut_static_ip6('2001:db8:147::10', '2001:db8:147::1', 64, 'eth0'),
    'ip=[2001:db8:147::10]::[2001:db8:147::1]:64::eth0:none',
    'the node is given its address, its gateway and its prefix length' );

# dracut reads a literal only in brackets. Without them it splits the address on its colons
# and takes the first group as the whole field.
like( xCAT::NetworkUtils::dracut_static_ip6('2001:db8:147::10', '2001:db8:147::1', 64, 'eth0'),
    qr{\Qip=[2001:db8:147::10]\E}, 'the address is bracketed' );
like( xCAT::NetworkUtils::dracut_static_ip6('2001:db8:147::10', '2001:db8:147::1', 64, 'eth0'),
    qr{\Q[2001:db8:147::1]\E}, 'and so is the gateway' );

# A node with no gateway still needs the prefix, which is what gives it the on-link route.
is( xCAT::NetworkUtils::dracut_static_ip6('2001:db8:147::10', '', 64, 'eth0'),
    'ip=[2001:db8:147::10]:::64::eth0:none',
    'a node with no gateway keeps its prefix length' );

is( xCAT::NetworkUtils::dracut_static_ip6('2001:db8:147::10', '2001:db8:147::1', 64, ''),
    'ip=[2001:db8:147::10]::[2001:db8:147::1]:64:::none',
    'a node with no interface name leaves that field empty' );

# Without an address or a usable prefix there is nothing to configure, and dracut must be
# left to its own answer rather than given a malformed parameter.
is( xCAT::NetworkUtils::dracut_static_ip6(undef, '2001:db8:147::1', 64, 'eth0'),
    undef, 'no address yields no parameter' );
is( xCAT::NetworkUtils::dracut_static_ip6('2001:db8:147::10', '2001:db8:147::1', undef, 'eth0'),
    undef, 'no prefix yields no parameter' );
is( xCAT::NetworkUtils::dracut_static_ip6('2001:db8:147::10', '2001:db8:147::1', 129, 'eth0'),
    undef, 'a prefix above 128 yields no parameter' );
is( xCAT::NetworkUtils::dracut_static_ip6('2001:db8:147::10', '2001:db8:147::1', 'sixty', 'eth0'),
    undef, 'a prefix that is not a number yields no parameter' );
