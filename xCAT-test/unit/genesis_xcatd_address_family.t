#!/usr/bin/perl
# Genesis must be told to reach xcatd in the family the node provisions in.
#
# destiny.pm picks the address for the xcatd= kernel argument with my_ip_facing, which resolves
# the peer with OnlyV4. An IPv6-only node is on the same link as the management node, so that call
# succeeds and returns the IPv4 address. Measured on xcat88-mn, whose compute node holds only
# 2001:db8:188::20:
#
#   imgfetch -n kernel http://[2001:db8:188::1]/tftpboot/xcat/genesis.kernel.x86_64
#   imgargs kernel ... xcatd=192.168.88.1:3001 destiny=shell
#
# The payload is fetched over IPv6 and the node is then told to report over IPv4. That was hidden
# while the cell also served an IPv4 pool. With the pool removed the node holds no IPv4 address at
# all, so Genesis boots and cannot reach xcatd, and discovery never completes.
#
# my_ip_facing_node picks the family from the node. It returns the same (error, value) pair as
# my_ip_facing, so every caller reads the result the same way.
use strict;
use warnings;
use Test::More tests => 7;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

require xCAT::NetworkUtils;

# An eval, not a bare call: a missing sub would end the file and report nothing.
sub facing {
    my ($node) = @_;
    my @out = eval { xCAT::NetworkUtils->my_ip_facing_node($node) };
    return @out ? @out : ( 1, 'my_ip_facing_node is not available' );
}

{
    no warnings 'redefine';

    # The two resolvers answer with the address of this management node in their own family, which
    # is what the real ones do on a dual-stack link: both succeed.
    local *xCAT::NetworkUtils::my_ip_facing = sub {
        my $peer = shift; $peer = shift if defined($peer) && $peer eq 'xCAT::NetworkUtils';
        return ( 0, '192.168.88.1' );
    };
    local *xCAT::NetworkUtils::my_ip_facing_family = sub {
        my $peer = shift; $peer = shift if defined($peer) && $peer eq 'xCAT::NetworkUtils';
        my $family = shift;
        return ( 1, "unexpected family $family" ) unless defined($family) && $family == 6;
        return ( 0, '2001:db8:188::1' );
    };

    local *xCAT::NetworkUtils::node_is_ipv6_only = sub { return 1; };
    my @v6 = facing('xcat88-cn');
    is( $v6[0], 0, 'an IPv6-only node resolves without error' );
    is( $v6[1], '2001:db8:188::1',
        'and gets the IPv6 address of the management node, not the IPv4 one' );

    local *xCAT::NetworkUtils::node_is_ipv6_only = sub { return 0; };
    my @v4 = facing('xcat54-cn');
    is( $v4[0], 0, 'a node that is not IPv6-only resolves without error' );
    is( $v4[1], '192.168.88.1', 'and keeps the IPv4 address it has always been given' );

    # The failure of the resolver must travel, not be swallowed into a false address.
    local *xCAT::NetworkUtils::node_is_ipv6_only = sub { return 1; };
    local *xCAT::NetworkUtils::my_ip_facing_family = sub { return ( 1, 'no IPv6 route to peer' ); };
    my @err = facing('xcat88-cn');
    is( $err[0], 1, 'a resolver error is reported rather than hidden' );
    like( $err[1], qr/no IPv6 route/, 'with the reason the resolver gave' );
}

# An IPv6 literal needs brackets or the port cannot be told from the address: xcatd=2001:db8::1:3001
# parses as a valid IPv6 address with no port at all.
is( xCAT::NetworkUtils::xcatd_cmdline_address( '2001:db8:188::1', '3001' ),
    '[2001:db8:188::1]:3001',
    'the xcatd= argument brackets an IPv6 literal' );
