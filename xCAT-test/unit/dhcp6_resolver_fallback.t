#!/usr/bin/env perl
#
# The resolver an IPv6-only node is given.
#
# site.nameservers holds IPv4 addresses, and the IPv6 network row's nameservers column is
# normally empty. Both DHCPv6 backends therefore wrote no DNS server for such a node, and
# the router advertisement carried no RDNSS. Measured on an IPv6-only Ubuntu 24.04 node: it
# netbooted, fetched its media over IPv6 and reached "curtin: Installation finished", then
# subiquity failed in its package step. The node console said "no search or nameservers found
# in /run/net-*.conf /run/net6-*.conf", and apt cannot resolve a mirror with no resolver.
#
# The management node answers DNS on the provisioning network. Measured with dig against an
# IPv6 cluster management node: a cluster name and an external name both resolve over IPv6.
# That address is what <xcatmaster> names for IPv4, so it is the fallback here.
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

require( repo_path('xCAT-server/lib/xcat/plugins/dhcp.pm') );
use xCAT::NetworkUtils;

my $NET  = '2001:db8:147::/64';
my $MN6  = '2001:db8:147::1';
my $DNS6 = '2001:db8::53';

# The management node's own address on the provisioning network, which is what
# my_ip_facing_family answers for a peer in that prefix.
my $facing_ok = sub { return ( 0, $MN6 ); };

# A cluster whose management node has no address on this network at all.
my $facing_none = sub { return ( 2, 'The IPv6 address of node is in an undefined subnet' ); };

# The real getipaddr drops a leading package name, because callers use both calling forms.
my $v6_getipaddr = sub {
    my $host = shift;
    $host = shift if defined($host) && $host eq 'xCAT::NetworkUtils';
    my %options = @_;
    return unless $options{OnlyV6};
    return $DNS6 if defined($host) && $host eq 'dns6.example.test';
    return;
};

#-------------------------------------------------------------------------------
# The chooser. One sub decides the resolver, so the three consumers cannot disagree.
#-------------------------------------------------------------------------------

{
    local *xCAT::NetworkUtils::my_ip_facing_family = $facing_ok;
    local *xCAT::NetworkUtils::getipaddr           = $v6_getipaddr;
    local *xCAT_plugin::dhcp::getipaddr            = $v6_getipaddr;

    # A network that names its own IPv6 resolver keeps it. The fallback must not override a
    # value the operator set.
    is( xCAT_plugin::dhcp::dhcp6_resolvers_for_network( $NET, 'dns6.example.test' ),
        $DNS6, 'a configured IPv6 nameserver is used as it stands' );

    # site.nameservers is IPv4, which is the normal cluster. Before the fallback this
    # returned nothing and the node was given no resolver.
    is( xCAT_plugin::dhcp::dhcp6_resolvers_for_network( $NET, '192.0.2.53' ),
        $MN6, 'an IPv4-only nameserver list falls back to the management node' );

    is( xCAT_plugin::dhcp::dhcp6_resolvers_for_network( $NET, '' ),
        $MN6, 'an empty nameserver list falls back to the management node' );

    is( xCAT_plugin::dhcp::dhcp6_resolvers_for_network( $NET, undef ),
        $MN6, 'no nameserver column falls back to the management node' );

    # Both forms of the prefix appear in the networks table.
    is( xCAT_plugin::dhcp::dhcp6_resolvers_for_network( '2001:db8:147::', '192.0.2.53' ),
        $MN6, 'the fallback works for a net value with no prefix length' );
}

{
    local *xCAT::NetworkUtils::my_ip_facing_family = $facing_none;
    local *xCAT::NetworkUtils::getipaddr           = $v6_getipaddr;
    local *xCAT_plugin::dhcp::getipaddr            = $v6_getipaddr;

    # Writing a resolver that does not exist is worse than writing none: the node waits for
    # a server that never answers.
    is( xCAT_plugin::dhcp::dhcp6_resolvers_for_network( $NET, '192.0.2.53' ),
        undef, 'a management node with no address on the network yields no resolver' );
}

#-------------------------------------------------------------------------------
# Consumer 1: the Kea subnet6.
#-------------------------------------------------------------------------------

{
    local *xCAT::NetworkUtils::my_ip_facing_family = $facing_ok;
    local *xCAT::NetworkUtils::getipaddr           = $v6_getipaddr;
    local *xCAT_plugin::dhcp::getipaddr            = $v6_getipaddr;
    local *xCAT::NetworkUtils::thishostisnot       = sub { return 1; };

    my $subnet = xCAT_plugin::dhcp::kea_subnet6_intent(
        {
            net         => $NET,
            mask        => '64',
            domain      => 'cluster.lab',
            nameservers => '192.0.2.53',
        },
        'eth1', 0, 10001
    );

    my ($dns) = grep { $_->{name} eq 'dns-servers' } @{ $subnet->{option_data} || [] };
    ok( $dns, 'the Kea subnet6 carries a dns-servers option for an IPv6-only node' );
    is( $dns && $dns->{data}, $MN6, 'and it names the management node' );
}

#-------------------------------------------------------------------------------
# Consumer 2: the ISC subnet6. The statement it wrote was not a dhcpd statement.
#-------------------------------------------------------------------------------

{
    local *xCAT::NetworkUtils::my_ip_facing_family = $facing_ok;
    local *xCAT::NetworkUtils::getipaddr           = $v6_getipaddr;
    local *xCAT_plugin::dhcp::getipaddr            = $v6_getipaddr;

    my $line = xCAT_plugin::dhcp::isc_dhcp6_nameserver_statement( $NET, '192.0.2.53' );
    like( $line, qr/\Aoption dhcp6\.name-servers /,
        'ISC names the RFC 3646 option, not a bare nameservers keyword' );
    like( $line, qr/\Q$MN6\E/, 'and carries the management node address' );
    like( $line, qr/;\s*\z/,   'and ends the statement' );

    # dhcpd refuses the whole file on an unknown statement, so the old spelling must be gone.
    unlike( $line, qr/\A\s*nameservers\b/, 'the bare nameservers keyword is not written' );
}

{
    local *xCAT::NetworkUtils::my_ip_facing_family = $facing_none;
    local *xCAT::NetworkUtils::getipaddr           = $v6_getipaddr;
    local *xCAT_plugin::dhcp::getipaddr            = $v6_getipaddr;

    is( xCAT_plugin::dhcp::isc_dhcp6_nameserver_statement( $NET, '192.0.2.53' ),
        undef, 'no resolver means no statement, rather than an empty one' );
}

#-------------------------------------------------------------------------------
# Consumer 3: the router advertisement. dracut reads RDNSS when DHCPv6 is not used for DNS.
#-------------------------------------------------------------------------------

my $ra = xCAT::NetworkUtils::radvd_config(
    [ { interface => 'eth1', prefix => $NET, rdnss => $MN6 } ] );

like( $ra, qr/RDNSS \Q$MN6\E/, 'the advertisement carries an RDNSS option' );
like( $ra, qr/AdvRDNSSLifetime \d+;/, 'and a lifetime, or a client discards it' );

# The RDNSS block belongs to the interface, not inside the prefix block.
like( $ra, qr/\};\s*\n\s*RDNSS/, 'RDNSS sits beside the prefix block, not inside it' );

my $ra_none = xCAT::NetworkUtils::radvd_config(
    [ { interface => 'eth1', prefix => $NET } ] );
unlike( $ra_none, qr/RDNSS/, 'a network with no resolver gets no RDNSS option' );

done_testing();
