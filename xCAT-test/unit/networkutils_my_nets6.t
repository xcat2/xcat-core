#!/usr/bin/env perl
# my_nets6 answers the question my_nets cannot: which IPv6 networks does this host serve.
# my_nets stays IPv4-only because lsslp.pm and PPCdb.pm read its keys with dotted-quad
# arithmetic, so an IPv6 key there is a wrong answer and not a new one.
use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage, TestingAndDebugging::ProhibitNoWarnings)

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;

BEGIN {
    package xCAT::Table;
    sub new { return bless {}, shift; }
    sub getAllAttribs { return; }
    $INC{'xCAT/Table.pm'} = __FILE__;

    package xCAT::TableUtils;
    sub get_site_attribute { return; }
    $INC{'xCAT/TableUtils.pm'} = __FILE__;
}

require xCAT::NetworkUtils;

my @prefixes;
{
    no warnings 'redefine';
    # The address probe reads the running host's interfaces. The networks under test are
    # the ones this list declares.
    *xCAT::NetworkUtils::_local_ip_prefixes = sub {
        my ($family) = @_;
        return $family == 6 ? @prefixes : ();
    };
}

# ipv6_network_address masks an address down to its prefix.
is(xCAT::NetworkUtils->ipv6_network_address('2001:db8:177::1', 64), '2001:db8:177::',
    'a /64 address is masked to its network');
is(xCAT::NetworkUtils->ipv6_network_address('2001:db8:177:abcd::5', 60), '2001:db8:177:abc0::',
    'a prefix that is not a byte boundary masks the partial byte');
is(xCAT::NetworkUtils->ipv6_network_address('2001:db8:177::1', 128), '2001:db8:177::1',
    'a /128 address is its own network');
is(xCAT::NetworkUtils->ipv6_network_address('2001:db8:177::1', 0), '::',
    'a /0 address masks to the unspecified address');
is(xCAT::NetworkUtils->ipv6_network_address('fe80::1%eth0', 10), 'fe80::',
    'a scoped literal is masked after the scope is removed');
is(xCAT::NetworkUtils->ipv6_network_address('192.0.2.1', 24), undef,
    'an IPv4 address is not an IPv6 network');
is(xCAT::NetworkUtils->ipv6_network_address('2001:db8::1', 129), undef,
    'a prefix longer than 128 bits is refused');
is(xCAT::NetworkUtils->ipv6_network_address('2001:db8::1', 'sixty-four'), undef,
    'a prefix that is not a number is refused');
is(xCAT::NetworkUtils->ipv6_network_address(undef, 64), undef,
    'a missing address is refused');

# my_nets6 keys its entries the way my_nets keys its IPv4 entries, so mknb and DHCP
# name the same network boot script.
@prefixes = ( [ '2001:db8:177::1', 64 ] );
is_deeply(
    xCAT::NetworkUtils->my_nets6(),
    { '2001:db8:177::/64' => '2001:db8:177::1' },
    'one global address becomes one network keyed <network>/<prefixlen>',
);

@prefixes = (
    [ '2001:db8:177::1', 64 ],
    [ '2001:db8:177::9', 64 ],
    [ '2001:db8:178::1', 64 ],
);
is_deeply(
    xCAT::NetworkUtils->my_nets6(),
    {
        '2001:db8:177::/64' => '2001:db8:177::9',
        '2001:db8:178::/64' => '2001:db8:178::1',
    },
    'the default behavior keeps the last address of each network, as my_nets does',
);
is_deeply(
    xCAT::NetworkUtils->my_nets6('all'),
    {
        '2001:db8:177::/64' => [ '2001:db8:177::1', '2001:db8:177::9' ],
        '2001:db8:178::/64' => ['2001:db8:178::1'],
    },
    'all mode keeps every address of each network in operating-system order',
);

# A malformed entry is left out instead of becoming a network named after nothing.
@prefixes = ( [ '2001:db8:177::1', 64 ], [ 'not-an-address', 64 ] );
is_deeply(
    xCAT::NetworkUtils->my_nets6('all'),
    { '2001:db8:177::/64' => ['2001:db8:177::1'] },
    'an address that does not parse is skipped',
);

@prefixes = ();
is(xCAT::NetworkUtils->my_nets6(), undef, 'a host with no global IPv6 address returns no networks');
is(xCAT::NetworkUtils->my_nets6('all'), undef, 'all mode returns no networks either');

done_testing();
