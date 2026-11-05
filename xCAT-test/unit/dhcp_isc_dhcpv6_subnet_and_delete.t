#!/usr/bin/env perl
#
# Two gaps in the ISC DHCPv6 path.
#
# A conf may write networks.net with no prefix length, and addrangedetection keys %netcfgs on
# that value, while addnet6 names a subnet "<net>/<prefix>" from the "ip -6 route" output. The
# range lookup already falls back to the bare net; the domain and the resolver lookups did not,
# so the subnet6 carried no domain-search list and no name servers.
#
# makedhcp -d removed the DHCPv4 host alone. The DHCPv6 host is a separate omapi object on a
# separate port, so the reservation outlived the node it belonged to.
use strict;
use warnings;
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More tests => 19;

$ENV{XCATCFG} ||= 'SQLite:/tmp';

my $source_dhcp_plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/dhcp.pm";
if ( -f $source_dhcp_plugin ) {
    require $source_dhcp_plugin;
} else {
    require xCAT_plugin::dhcp;
}

my $LONG = '2001:db8:149::/64';
my $BARE = '2001:db8:149::';

# The resolver list reaches the statement through dhcp6_resolvers_for_network, which resolves
# names. The stub keeps the value it was handed, so the statement shows what the networks row
# carried rather than what this host can look up.
no warnings 'redefine';
*xCAT_plugin::dhcp::dhcp6_resolvers_for_network = sub {
    my ( undef, $nameservers ) = @_;
    return $nameservers;
};
use warnings 'redefine';

# ---------------------------------------------------------------------------
# The lookup, under the name the networks table uses and under the long name.

%xCAT_plugin::dhcp::netcfgs = (
    $BARE => {
        domain      => 'ipv6.cluster',
        nameservers => '2001:db8:149::1',
        ddnsdomain  => 'ddns.ipv6.cluster',
        range       => '2001:db8:149::1000 2001:db8:149::1fff',
    },
);

my $cfg = xCAT_plugin::dhcp::net_config_for($LONG);
is( $cfg->{domain}, 'ipv6.cluster',
    'the domain of a prefixless networks row is found under the subnet name' );
is( $cfg->{nameservers}, '2001:db8:149::1',
    'the nameservers of a prefixless networks row are found under the subnet name' );
is( $cfg->{ddnsdomain}, 'ddns.ipv6.cluster',
    'the ddnsdomain of a prefixless networks row is found under the subnet name' );

# dynamic_range_for already fell back, and is left alone. It is the control: a lookup that
# stops falling back takes the three assertions above with it and leaves this one standing.
is( xCAT_plugin::dhcp::dynamic_range_for($LONG),
    '2001:db8:149::1000 2001:db8:149::1fff',
    'the range lookup still answers for the same subnet' );

is( xCAT_plugin::dhcp::net_config_for('2001:db8:999::/64'), undef,
    'a subnet with no networks row has no configuration' );
is( xCAT_plugin::dhcp::net_config_for(undef), undef,
    'no subnet name yields no configuration' );

# A row written WITH the prefix still wins, so the fallback adds a name and replaces none.
%xCAT_plugin::dhcp::netcfgs = (
    $LONG => { domain => 'long.cluster' },
    $BARE => { domain => 'bare.cluster' },
);
is( xCAT_plugin::dhcp::net_config_for($LONG)->{domain}, 'long.cluster',
    'the row written with a prefix length is preferred over the bare one' );

# ---------------------------------------------------------------------------
# The statements the subnet6 carries.

%xCAT_plugin::dhcp::netcfgs = ();
my @statements = xCAT_plugin::dhcp::isc_dhcp6_subnet_statements(
    net           => $LONG,
    config        => {
        domain      => 'ipv6.cluster',
        nameservers => '2001:db8:149::1,2001:db8:149::2',
    },
    site_domain   => 'site.cluster',
    alldomains    => [ 'ipv6.cluster', 'other.cluster' ],
    domain_search => 1,
);
my $subnet = join( '', @statements );

like( $subnet, qr/^\s*option domain-search\s+"ipv6\.cluster", "other\.cluster";$/m,
    'the subnet6 carries the domain-search list of its own network' );
like( $subnet, qr/^\s*option dhcp6\.name-servers 2001:db8:149::1,2001:db8:149::2;$/m,
    'the subnet6 carries the nameservers the networks row configured' );
like( $subnet, qr/^\s*option domain-name "ipv6\.cluster";$/m,
    'the network domain is the domain-name, not the site domain' );
unlike( $subnet, qr/"ipv6\.cluster", "ipv6\.cluster"/,
    'the own domain is not repeated in the search list' );

# With no network domain the site domain names the subnet, and there is no search list to write.
my $sited = join( '', xCAT_plugin::dhcp::isc_dhcp6_subnet_statements(
    net => $LONG, config => {}, site_domain => 'site.cluster',
    alldomains => ['site.cluster'], domain_search => 1,
) );
like( $sited, qr/^\s*option domain-name "site\.cluster";$/m,
    'a network with no domain falls back to the site domain' );
unlike( $sited, qr/domain-search/,
    'a network with no domain gets no domain-search statement' );

# sles10 and rh5 dhcpd reject the option, and dhcpd refuses the whole file on one it does not know.
my $old = join( '', xCAT_plugin::dhcp::isc_dhcp6_subnet_statements(
    net => $LONG, config => { domain => 'ipv6.cluster' },
    alldomains => ['ipv6.cluster'], domain_search => 0,
) );
unlike( $old, qr/domain-search/,
    'domain-search is withheld where dhcpd does not know the option' );

# ---------------------------------------------------------------------------
# makedhcp -d reaches the DHCPv6 host.

my $written = '';
open my $omshell6, '>', \$written or die "Cannot open an in-memory handle: $!";
is( xCAT_plugin::dhcp::delnode6( 'node01', $omshell6 ), 1,
    'a delete with an open DHCPv6 session reports that it acted' );
close $omshell6;

like( $written, qr/^set name = "node01"\n/m,
    'makedhcp -d names the node whose DHCPv6 host it removes' );
like( $written, qr/^open\nremove\nclose\n/m,
    'and opens the host and removes it' );

# A node that holds no DHCPv6 address has no session, so nothing is written and nothing dies.
is( xCAT_plugin::dhcp::delnode6( 'node01', undef ), 0,
    'a delete with no DHCPv6 session writes nothing' );
is( xCAT_plugin::dhcp::delnode6_commands(''), '',
    'an empty node name yields no commands' );
