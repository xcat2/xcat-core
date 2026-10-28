#!/usr/bin/env perl
# The linuxrc arguments sles.pm gives an IPv6-only node.
#
# linuxrc configures IPv4 by default, so an IPv6-only node sent an IPv4 DHCPDISCOVER, got
# "no/incomplete answer" and reported "Failed to download AutoYaST file" -- it never reached
# the install source. The node is configured statically, for the reason anaconda.pm configures
# EL statically: the firmware answers DHCPv6 with the RFC 6355 DUID-UUID that the reservation
# is keyed on, while the installer builds a DUID of its own that matches no reservation.
use strict;
use warnings;
## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

BEGIN {
    $ENV{XCATROOT} = repo_path('xCAT-server');
    $ENV{XCATCFG}  = 'SQLite:' . tempdir( CLEANUP => 1 );
}

use xCAT::NetworkUtils;
require( repo_path('xCAT-server/lib/xcat/plugins/sles.pm') );

our %cfg6;
our $nameservers;
no warnings 'redefine';
local *xCAT::NetworkUtils::getNodeNetworkCfg6 = sub {
    my $node = shift;
    $node = shift if defined($node) && $node eq 'xCAT::NetworkUtils';
    return @{ $cfg6{$node} || [] };
};
local *xCAT::NetworkUtils::ipv6_server_for_node = sub {
    my $node = shift;
    $node = shift if defined($node) && $node eq 'xCAT::NetworkUtils';
    return shift;
};
local *xCAT::NetworkUtils::getNodeNameservers = sub {
    my $nodes = shift;
    $nodes = shift if defined($nodes) && $nodes eq 'xCAT::NetworkUtils';
    return $nameservers;
};
use warnings 'redefine';

# A node with an address, a gateway and an IPv6 nameserver.
{
    local %cfg6 = ( cn1 => [ '2001:db8:156::10', 'cn1', '2001:db8:156::1', 64 ] );
    local $nameservers = { cn1 => '2001:db8:156::1,192.168.156.1' };
    my @args = xCAT_plugin::sles::static_ipv6_boot_args('cn1');
    is_deeply(
        \@args,
        [ 'ipv6only=1', 'hostip=2001:db8:156::10/64',
          'gateway=2001:db8:156::1', 'nameserver=2001:db8:156::1' ],
        'an IPv6-only node is configured statically, with no DHCP'
    );
}

# ipv6only is what makes linuxrc stop asking for IPv4; without it the rest is ignored.
{
    local %cfg6 = ( cn1 => [ '2001:db8:156::10', 'cn1', undef, 64 ] );
    local $nameservers = {};
    my @args = xCAT_plugin::sles::static_ipv6_boot_args('cn1');
    is( $args[0], 'ipv6only=1', 'the arguments start by turning IPv4 off' );
    is_deeply( \@args, [ 'ipv6only=1', 'hostip=2001:db8:156::10/64' ],
        'a node with no gateway and no nameserver still gets its address' );
}

# An IPv4 nameserver is not a nameserver linuxrc can reach on an IPv6-only node.
{
    local %cfg6 = ( cn1 => [ '2001:db8:156::10', 'cn1', '2001:db8:156::1', 64 ] );
    local $nameservers = { cn1 => '192.168.156.1' };
    my @args = xCAT_plugin::sles::static_ipv6_boot_args('cn1');
    is( scalar( grep { /^nameserver=/ } @args ), 0,
        'an IPv4 nameserver is left out' );
}

# Nothing to say about a node with no IPv6 configuration.
{
    local %cfg6 = ();
    local $nameservers = {};
    is_deeply( [ xCAT_plugin::sles::static_ipv6_boot_args('cn1') ], [],
        'a node with no IPv6 address gets no arguments' );
}
{
    local %cfg6 = ( cn1 => [ '2001:db8:156::10', 'cn1', undef, 'sixtyfour' ] );
    local $nameservers = {};
    is_deeply( [ xCAT_plugin::sles::static_ipv6_boot_args('cn1') ], [],
        'a malformed prefix gives no arguments' );
}

done_testing();
