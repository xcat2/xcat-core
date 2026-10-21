#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use Socket ();
use Test::More;
use xCAT::NetworkUtils;

ok(
    xCAT::NetworkUtils->isValidIp('192.0.2.10'),
    'dual-stack validator accepts IPv4'
);
ok(
    !xCAT::NetworkUtils->isValidIp('192.0.2.999'),
    'dual-stack validator rejects invalid IPv4'
);
ok(
    !xCAT::NetworkUtils->isValidIp('192.0.2.010'),
    'dual-stack validator preserves strict IPv4 octet syntax'
);
ok(
    !xCAT::NetworkUtils->isIpaddr('2001:db8::10'),
    'legacy IPv4-only validator remains IPv4-only'
);

my $has_core_ipv6_parser = defined(&Socket::inet_pton)
  && eval { defined(Socket::inet_pton(Socket::AF_INET6(), '::1')) };
my $has_socket6 = eval { require Socket6; 1 };
my $has_ipv6_parser = $has_core_ipv6_parser || $has_socket6;
my $has_core_resolver = defined(&Socket::getaddrinfo)
  && defined(&Socket::getnameinfo)
  && $has_core_ipv6_parser;

SKIP: {
    skip 'No IPv6 literal parser is available', 15 unless $has_ipv6_parser;

    foreach my $address (
        '2001:db8::10',
        '2001:0DB8:0000:0000:0000:0000:0000:0010',
        '::',
        '::1',
        '::ffff:192.0.2.10'
      )
    {
        ok(
            xCAT::NetworkUtils->isValidIp($address),
            "accepts IPv6 literal $address"
        );
    }

    foreach my $address (
        '2001:db8::g',
        '2001:db8::1::2',
        '2001:db8::10/64',
        'fe80::1%eth0',
        '[2001:db8::10]',
        " 2001:db8::10",
        "2001:db8::10\n",
        'node01.example.com'
      )
    {
        ok(
            !xCAT::NetworkUtils->isValidIp($address),
            "rejects non-literal address $address"
        );
    }

    ok(
        xCAT::NetworkUtils->isSameIPAddress(
            '2001:0db8:0000:0000:0000:0000:0000:0010',
            '2001:db8::10'
        ),
        'compares equivalent IPv6 spellings by packed address'
    );
    ok(
        !xCAT::NetworkUtils->isSameIPAddress('2001:db8::10', '2001:db8::11'),
        'distinguishes different IPv6 addresses'
    );
}

is(
    xCAT::NetworkUtils->getIPv6PrefixLength('2001:db8:7309::/64'),
    64,
    'extracts an IPv6 prefix from CIDR notation'
);
is(
    xCAT::NetworkUtils->getIPv6PrefixLength('2001:db8:7309::', '/64'),
    64,
    'accepts a separate numeric IPv6 prefix'
);
ok(
    !defined(xCAT::NetworkUtils->getIPv6PrefixLength('2001:db8::', 129)),
    'rejects an out-of-range IPv6 prefix'
);

SKIP: {
    skip 'No IPv6 literal parser is available', 6 unless $has_ipv6_parser;

    is(
        xCAT::NetworkUtils->getIPv6ReverseZone('2001:db8:7309::/64'),
        '0.0.0.0.9.0.3.7.8.b.d.0.1.0.0.2.ip6.arpa.',
        'formats an IPv6 reverse zone from packed address bytes'
    );
    is(
        xCAT::NetworkUtils->getIPv6ReverseZone('2001:db8:7309::', 64),
        '0.0.0.0.9.0.3.7.8.b.d.0.1.0.0.2.ip6.arpa.',
        'formats a reverse zone with a separate prefix'
    );
    is(
        xCAT::NetworkUtils->getIPv6ReverseZone('::/0'),
        'ip6.arpa.',
        'formats the IPv6 root reverse zone'
    );
    is(
        xCAT::NetworkUtils->getIPv6ReverseName('::1'),
        join('.', reverse(split(//, ('0' x 31) . '1'))) . '.ip6.arpa.',
        'formats a complete IPv6 PTR owner name'
    );
    is(
        xCAT::NetworkUtils->getIPv6ReverseName('::ffff:192.0.2.10'),
        join('.', reverse(split(//, '00000000000000000000ffffc000020a')))
          . '.ip6.arpa.',
        'formats an IPv4-mapped IPv6 PTR owner name'
    );
    ok(
        !defined(xCAT::NetworkUtils->getIPv6ReverseZone('2001:db8::/63')),
        'rejects a non-nibble-aligned reverse zone'
    );
}

{
    no warnings 'redefine';
    my %addresses = (
        nodev4   => { 4 => '192.0.2.10' },
        nodev6   => { 6 => '2001:db8::10' },
        nodedual => { 4 => '192.0.2.20', 6 => '2001:db8::20' },
        server6  => { 6 => '2001:db8::53' },
    );
    local *xCAT::NetworkUtils::getipaddr = sub {
        my $host = shift;
        $host = shift if defined($host) && $host eq 'xCAT::NetworkUtils';
        my %options = @_;
        return $addresses{$host}{4} if $options{OnlyV4};
        return $addresses{$host}{6} if $options{OnlyV6};
        return;
    };
    local *xCAT::NetworkUtils::my_ip_facing_family = sub {
        return (0, '2001:db8::1');
    };

    is(xCAT::NetworkUtils->node_address_family('nodev4'), 4, 'detects an IPv4 node');
    is(xCAT::NetworkUtils->node_address_family('nodev6'), 6, 'detects an IPv6-only node');
    is(xCAT::NetworkUtils->node_address_family('nodedual'), 4, 'preserves IPv4 preference for a dual-stack node');
    ok(xCAT::NetworkUtils->node_is_ipv6_only('nodev6'), 'identifies an IPv6-only node');
    ok(!xCAT::NetworkUtils->node_is_ipv6_only('nodedual'), 'does not classify a dual-stack node as IPv6-only');
    is(
        xCAT::NetworkUtils->ipv6_server_for_node('nodev6', 'server6'),
        '2001:db8::53',
        'resolves an explicit server in the IPv6 family'
    );
    is(
        xCAT::NetworkUtils->ipv6_server_for_node('nodev6', '2001:db8::54'),
        '2001:db8::54',
        'preserves a valid IPv6 server literal without resolver lookup'
    );
    is(
        xCAT::NetworkUtils->ipv6_server_for_node('nodev6', '<xcatmaster>'),
        '2001:db8::1',
        'selects the IPv6-facing address for the xCAT master token'
    );
}

is(
    xCAT::NetworkUtils->format_uri_host('192.0.2.10'),
    '192.0.2.10',
    'URI host formatting preserves IPv4'
);
is(
    xCAT::NetworkUtils->format_uri_host('node01.example.com'),
    'node01.example.com',
    'URI host formatting preserves hostnames'
);
is(
    xCAT::NetworkUtils->format_uri_host('_service.node01.example.com'),
    '_service.node01.example.com',
    'URI host formatting preserves xCAT-compatible underscore labels'
);
foreach my $host (
    'bad\\host',
    'foo%ZZ',
    'node..example.com',
    '-node.example.com',
    '192.0.2.999'
  )
{
    ok(
        !defined(xCAT::NetworkUtils->format_uri_host($host)),
        "URI host formatting rejects malformed host $host"
    );
}
is(
    xCAT::NetworkUtils->format_host_port('192.0.2.10', 3001),
    '192.0.2.10:3001',
    'host-port formatting preserves the IPv4 endpoint form'
);
{
    local %::hostiphash;
    is(
        xCAT::NetworkUtils->getipaddr('192.0.2.10', OnlyV4 => 1),
        '192.0.2.10',
        'OnlyV4 preserves an IPv4 literal'
    );
    ok(
        !exists($::hostiphash{'192.0.2.10'}{hostip}),
        'an OnlyV4 lookup does not populate the legacy cache'
    );
    is(
        xCAT::NetworkUtils->getipaddr('192.0.2.10'),
        '192.0.2.10',
        'legacy unrestricted lookup still returns the same IPv4 literal'
    );
}
is_deeply(
    [ xCAT::NetworkUtils->parse_host_port('192.0.2.10:3001') ],
    [ '192.0.2.10', '3001' ],
    'parses an IPv4 endpoint'
);
is_deeply(
    [ xCAT::NetworkUtils->parse_host_port('node01.example.com', 3002) ],
    [ 'node01.example.com', 3002 ],
    'applies a default port to a hostname'
);
ok(
    !defined(xCAT::NetworkUtils->format_host_port('192.0.2.10', 70000)),
    'rejects an out-of-range port'
);
is_deeply(
    [ xCAT::NetworkUtils->parse_host_port('node01.example.com:70000') ],
    [],
    'rejects an endpoint with an out-of-range port'
);
is_deeply(
    [ xCAT::NetworkUtils->parse_host_port('bad\\host:3001') ],
    [],
    'rejects an endpoint with a malformed hostname'
);

SKIP: {
    skip 'No IPv6 literal parser is available', 7 unless $has_ipv6_parser;

    is(
        xCAT::NetworkUtils->format_uri_host('2001:db8::10'),
        '[2001:db8::10]',
        'brackets an IPv6 URI host'
    );
    is(
        xCAT::NetworkUtils->format_uri_host('[2001:db8::10]'),
        '[2001:db8::10]',
        'does not double-bracket an IPv6 URI host'
    );
    is(
        xCAT::NetworkUtils->format_host_port('2001:db8::10', 3001),
        '[2001:db8::10]:3001',
        'formats a bracketed IPv6 endpoint'
    );
    is_deeply(
        [ xCAT::NetworkUtils->parse_host_port('[2001:db8::10]:3001') ],
        [ '2001:db8::10', '3001' ],
        'parses a bracketed IPv6 endpoint'
    );
    is_deeply(
        [ xCAT::NetworkUtils->parse_host_port('2001:db8::10', 3002) ],
        [ '2001:db8::10', 3002 ],
        'treats an unbracketed IPv6 literal as a host only'
    );
    is_deeply(
        [ xCAT::NetworkUtils->parse_host_port('[2001:db8::10]') ],
        [ '2001:db8::10', undef ],
        'parses a bracketed IPv6 host without a port'
    );
    is_deeply(
        [ xCAT::NetworkUtils->parse_host_port('[2001:db8::10]:70000') ],
        [],
        'rejects an IPv6 endpoint with an out-of-range port'
    );
}

SKIP: {
    skip 'No IPv6 literal parser is available', 4 unless $has_ipv6_parser;

    ok(
        xCAT::NetworkUtils::isInSameSubnet(
            '2001:db8:1::10', '2001:db8:1::', 64, 1
        ),
        'IPv6 subnet matching accepts addresses in the same prefix'
    );
    ok(
        !xCAT::NetworkUtils::isInSameSubnet(
            '2001:db8:2::10', '2001:db8:1::', 64, 1
        ),
        'IPv6 subnet matching rejects addresses outside the prefix'
    );
    ok(
        xCAT::NetworkUtils->ishostinsubnet(
            '2001:db8:1::10', '', '2001:db8:1::/64'
        ),
        'CIDR IPv6 membership works without Net::IP'
    );
    ok(
        !xCAT::NetworkUtils->ishostinsubnet(
            '2001:db8:2::10', '', '2001:db8:1::/64'
        ),
        'CIDR IPv6 non-membership works without Net::IP'
    );
}

{
    # getipaddr caches one address per host, and on a dual-stack host that is
    # the AAAA record. An OnlyV4 caller renders the result into nfsroot= and a
    # kernel command line, where an IPv6 literal does not parse, so the cache
    # must not answer an OnlyV4 request with its IPv6 entry.
    local %::hostiphash = ( 'cached.example.com' => { hostip => '2001:db8::50' } );
    my $v4 = xCAT::NetworkUtils->getipaddr('cached.example.com', OnlyV4 => 1);
    ok( !defined($v4) || $v4 !~ /:/,
        'an IPv6 cache entry is not served to an OnlyV4 caller' );

    local %::hostiphash = ( 'cached.example.com' => { hostip => '192.0.2.50' } );
    is( xCAT::NetworkUtils->getipaddr('cached.example.com', OnlyV4 => 1),
        '192.0.2.50', 'an IPv4 cache entry is served to an OnlyV4 caller' );
    is( xCAT::NetworkUtils->getipaddr('cached.example.com'),
        '192.0.2.50', 'and to a caller that asks for no family' );
}

{
    local %::hostiphash = (
        'cached-v4.example' => { hostip => '192.0.2.50' },
    );
    is(
        xCAT::NetworkUtils->getipaddr('cached-v4.example', OnlyV4 => 1),
        '192.0.2.50',
        'OnlyV4 preserves reuse of a valid legacy IPv4 cache entry'
    );
    is(
        $::hostiphash{'cached-v4.example'}{hostip_v4},
        '192.0.2.50',
        'legacy IPv4 cache reuse seeds the family-specific cache'
    );
}

SKIP: {
    skip 'Socket6 is required for family-specific resolution', 6 unless $has_socket6;

    local %::hostiphash;
    is(
        xCAT::NetworkUtils->getipaddr('2001:db8::10', OnlyV6 => 1),
        '2001:db8::10',
        'resolves an IPv6 literal with OnlyV6'
    );
    ok(
        !defined(xCAT::NetworkUtils->getipaddr('2001:db8::10', OnlyV4 => 1)),
        'an OnlyV6 cache entry cannot satisfy an OnlyV4 lookup'
    );
    is(
        $::hostiphash{'2001:db8::10'}{hostip_v6},
        '2001:db8::10',
        'stores an OnlyV6 result in the IPv6-specific cache'
    );
    ok(
        !exists($::hostiphash{'2001:db8::10'}{hostip}),
        'an OnlyV6 lookup does not contaminate the legacy cache'
    );
    isa_ok(
        xCAT::NetworkUtils->getipaddr(
            '2001:db8::10', OnlyV6 => 1, GetNumber => 1
        ),
        'Math::BigInt',
        'OnlyV6 numeric result'
    );
    ok(
        !defined(
            xCAT::NetworkUtils->getipaddr(
                '2001:db8::10', OnlyV4 => 1, GetNumber => 1
            )
        ),
        'an OnlyV6 numeric cache entry cannot satisfy an OnlyV4 lookup'
    );
}

SKIP: {
    skip 'Socket6 is required for multi-address cache tests', 4 unless $has_socket6;

    no warnings 'redefine';
    local *Socket6::getaddrinfo = sub {
        return (
            Socket::AF_INET(), Socket::SOCK_STREAM(), 6, 'first',  '',
            Socket::AF_INET(), Socket::SOCK_STREAM(), 6, 'second', '',
        );
    };
    local *Socket6::getnameinfo = sub {
        return $_[0] eq 'first' ? '192.0.2.10' : '192.0.2.20';
    };
    local %::hostiphash;

    is_deeply(
        [
            xCAT::NetworkUtils->getipaddr(
                'multi.socket6.example', GetAllAddresses => 1
            )
        ],
        [ '192.0.2.10', '192.0.2.20' ],
        'Socket6 returns all addresses in resolver order'
    );
    is(
        xCAT::NetworkUtils->getipaddr(
            'multi.socket6.example', OnlyV4 => 1
        ),
        '192.0.2.10',
        'Socket6 family cache preserves the first address'
    );

    my @numbers = xCAT::NetworkUtils->getipaddr(
        'multi-number.socket6.example',
        GetAllAddresses => 1,
        GetNumber       => 1
    );
    is(scalar(@numbers), 2, 'Socket6 returns all numeric addresses');
    is(
        xCAT::NetworkUtils->getipaddr(
            'multi-number.socket6.example', OnlyV4 => 1, GetNumber => 1
        )->bcmp($numbers[0]),
        0,
        'Socket6 numeric family cache preserves the first address'
    );
}

SKIP: {
    skip 'Core Socket IPv6 resolver is unavailable', 2 unless $has_core_resolver;

    my $child_code = <<'PERL';
BEGIN {
    unshift @INC, sub {
        die "Socket6 intentionally disabled\n" if $_[1] eq 'Socket6.pm';
        return;
    };
}
use xCAT::NetworkUtils;
die "core IPv6 validation failed\n"
  unless xCAT::NetworkUtils->isValidIp('2001:db8::10');
my $v6 = xCAT::NetworkUtils->getipaddr('2001:db8::10', OnlyV6 => 1);
die "core IPv6 lookup failed\n" unless defined($v6) && $v6 eq '2001:db8::10';
my $number = xCAT::NetworkUtils->getipaddr(
    '2001:db8::10', OnlyV6 => 1, GetNumber => 1
);
die "core numeric lookup failed\n" unless ref($number) eq 'Math::BigInt';
my $v4 = xCAT::NetworkUtils->getipaddr('2001:db8::10', OnlyV4 => 1);
die "core family filter failed\n" if defined($v4);
my @missing = xCAT::NetworkUtils->getipaddr(
    '2001:db8::g', OnlyV6 => 1, GetAllAddresses => 1
);
die "core failed lookup returned a phantom address\n" if @missing;
{
    no warnings 'redefine';
    local *xCAT::NetworkUtils::_local_ip_prefixes = sub {
        return ([ '2001:db8::1', 64 ]);
    };
    my @facing = xCAT::NetworkUtils->my_ip_facing_family('2001:db8::50', 6);
    die "core same-subnet selection failed\n"
      unless @facing == 2 && $facing[0] == 0 && $facing[1] eq '2001:db8::1';
}
{
    no warnings 'redefine';
    local *Socket::getaddrinfo = sub {
        return (
            '',
            { family => Socket::AF_INET(), addr => 'first' },
            { family => Socket::AF_INET(), addr => 'second' },
        );
    };
    local *Socket::getnameinfo = sub {
        my $ip = $_[0] eq 'first' ? '192.0.2.10' : '192.0.2.20';
        return ('', $ip, 0);
    };

    local %::hostiphash;
    my @all = xCAT::NetworkUtils->getipaddr(
        'multi.core.example', GetAllAddresses => 1
    );
    die "core address ordering failed\n"
      unless join(',', @all) eq '192.0.2.10,192.0.2.20';
    my $first = xCAT::NetworkUtils->getipaddr(
        'multi.core.example', OnlyV4 => 1
    );
    die "core family cache ordering failed\n"
      unless defined($first) && $first eq '192.0.2.10';

    my @numbers = xCAT::NetworkUtils->getipaddr(
        'multi-number.core.example',
        GetAllAddresses => 1,
        GetNumber       => 1
    );
    my $first_number = xCAT::NetworkUtils->getipaddr(
        'multi-number.core.example', OnlyV4 => 1, GetNumber => 1
    );
    die "core numeric family cache ordering failed\n"
      unless @numbers == 2 && $first_number->bcmp($numbers[0]) == 0;
}
print "core-socket-ok\n";
PERL

    open(
        my $child,
        '-|',
        $^X,
        "-I$FindBin::Bin/../../xCAT-server/lib",
        "-I$FindBin::Bin/../../xCAT-server/lib/perl",
        "-I$FindBin::Bin/../../perl-xCAT",
        '-e',
        $child_code
      ) or die "Unable to start core Socket resolver test: $!";
    my $output = do { local $/; <$child> };
    ok(close($child), 'core Socket resolver works when Socket6 cannot load');
    is($output, "core-socket-ok\n", 'core Socket fallback preserves family filtering');
}

{
    no warnings 'redefine';
    local *xCAT::NetworkUtils::_local_ip_prefixes = sub {
        return (
            [ '192.0.2.1',    24 ],
            [ '198.51.100.1', 24 ],
            [ '203.0.113.129', 25 ],
        );
    };
    is_deeply(
        [ xCAT::NetworkUtils->my_ip_facing_family('192.0.2.80', 4) ],
        [ 0, '192.0.2.1' ],
        'selects a same-subnet local IPv4 address without changing its form'
    );
    is(
        (xCAT::NetworkUtils->my_ip_facing_family('203.0.113.80', 4))[0],
        2,
        'reports when no local IPv4 address shares the peer subnet'
    );
    is_deeply(
        [ xCAT::NetworkUtils->my_ip_facing_family('203.0.113.200', 4) ],
        [ 0, '203.0.113.129' ],
        'handles a non-byte-aligned IPv4 prefix'
    );
}

SKIP: {
    skip 'An IPv6 resolver is required for IPv6 same-subnet selection', 5
      unless $has_socket6 || $has_core_resolver;

    no warnings 'redefine';
    local *xCAT::NetworkUtils::_local_ip_prefixes = sub {
        return (
            [ '2001:db8:100::1', 64 ],
            [ '2001:db8:100::2', 64 ],
            [ '2001:db8:200::1', 64 ],
            [ '2001:db8:400:0:8000::1', 65 ],
            [ '2001:db8:500::2', 127 ],
        );
    };
    is_deeply(
        [ xCAT::NetworkUtils->my_ip_facing_family('2001:db8:100::80', 6) ],
        [ 0, '2001:db8:100::1', '2001:db8:100::2' ],
        'selects all same-subnet local IPv6 addresses'
    );
    is(
        (xCAT::NetworkUtils->my_ip_facing_family('2001:db8:300::80', 6))[0],
        2,
        'reports when no local IPv6 address shares the peer subnet'
    );
    is(
        (xCAT::NetworkUtils->my_ip_facing_family('192.0.2.80', 6))[0],
        1,
        'rejects a peer that cannot resolve in the requested family'
    );
    is_deeply(
        [
            xCAT::NetworkUtils->my_ip_facing_family(
                '2001:db8:400:0:ffff::80', 6
            )
        ],
        [ 0, '2001:db8:400:0:8000::1' ],
        'handles a non-byte-aligned IPv6 prefix'
    );
    is_deeply(
        [ xCAT::NetworkUtils->my_ip_facing_family('2001:db8:500::3', 6) ],
        [ 0, '2001:db8:500::2' ],
        'handles an IPv6 /127 prefix'
    );
}

{
    package NetworkUtilsIPv6NetworksTable;
    sub new { return bless { closed => 0 }, shift; }
    sub getAllAttribs {
        return (
            { net => '192.0.2.0',       mask => '255.255.255.0', gateway => '192.0.2.1' },
            { net => '2001:db8:2::/64', mask => undef,           gateway => '2001:db8:2::1' },
            { net => '2001:db8:1::',    mask => '/64',           gateway => '<xcatmaster>' },
        );
    }
    sub close { $_[0]->{closed} = 1; }
}

{
    no warnings 'redefine';
    my $table = NetworkUtilsIPv6NetworksTable->new();
    local *xCAT::Table::new = sub { return $table; };
    local *xCAT::NetworkUtils::getipaddr = sub {
        my $candidate = shift;
        $candidate = shift if defined($candidate) && $candidate eq 'xCAT::NetworkUtils';
        my %opts = @_;
        return '2001:db8:1::50' if $candidate eq 'nodev6' && $opts{OnlyV6};
        return;
    };
    is_deeply(
        [ xCAT::NetworkUtils->getNodeNetworkCfg6('nodev6') ],
        [ '2001:db8:1::50', 'nodev6', '<xcatmaster>', '64' ],
        'IPv6 node network lookup returns the address, gateway, and normalized prefix'
    );
    ok($table->{closed}, 'IPv6 node network lookup closes the networks table');
    is_deeply(
        [ xCAT::NetworkUtils->getNodeNetworkCfg6('missing') ],
        [ undef, 'missing', undef, undef ],
        'IPv6 node network lookup reports a missing IPv6 address without inventing configuration'
    );
}

done_testing();
