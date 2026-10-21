#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
BEGIN { $ENV{XCATROOT} = "$FindBin::Bin/../../xCAT-server"; }
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Temp qw(tempdir);
use Socket ();
use Test::More;

$ENV{XCATCFG}  ||= 'SQLite:/tmp';

my $source_ddns_plugin =
  "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/ddns.pm";
if (-f $source_ddns_plugin) {
    require $source_ddns_plugin;
} else {
    require xCAT_plugin::ddns;
}

ok(xCAT_plugin::ddns::isvalidip('192.0.2.10'), 'makedns accepts IPv4');
ok(!xCAT_plugin::ddns::isvalidip('192.0.2.999'), 'makedns rejects invalid IPv4');
ok(!xCAT_plugin::ddns::isvalidip('192.0.2x10'), 'makedns rejects malformed IPv4');
ok(
    xCAT_plugin::ddns::isvalidip('192.0.2.010'),
    'makedns preserves leading-zero detection for its caller'
);
is(
    xCAT_plugin::ddns::_preferred_ip_address(
        '2001:db8::10',
        '192.0.2.10'
    ),
    '192.0.2.10',
    'dual-stack DNS host preserves IPv4 preference'
);
is(xCAT_plugin::ddns::_dns_record_type('192.0.2.10'), 'A', 'IPv4 uses an A record');

my $has_core_ipv6_parser = defined(&Socket::inet_pton)
  && eval { defined(Socket::inet_pton(Socket::AF_INET6(), '::1')) };
my $has_ipv6_parser = $has_core_ipv6_parser
  || eval { require Socket6; 1 };

{
    no warnings qw(once redefine);
    my @families;
    local *xCAT::NetworkUtils::my_ip_facing = sub {
        push @families, 4;
        return (0, '192.0.2.1');
    };
    local *xCAT::NetworkUtils::my_ip_facing_family = sub {
        my ($class, $peer, $family) = @_;
        push @families, $family;
        return (0, '2001:db8:1::1');
    };

    is_deeply(
        [ xCAT_plugin::ddns::_local_addresses_for_network('192.0.2.0') ],
        ['192.0.2.1'],
        'IPv4 DNS-network ownership retains the legacy facing-address path'
    );
    is_deeply(
        [ xCAT_plugin::ddns::_local_addresses_for_network('2001:db8:1::/64') ],
        ['2001:db8:1::1'],
        'IPv6 DNS-network ownership strips CIDR and uses the IPv6 facing path'
    );
    is_deeply(\@families, [4, 6], 'DNS-network ownership selects the matching address family');
}

SKIP: {
    skip 'No IPv6 literal parser is available', 9 unless $has_ipv6_parser;

    ok(xCAT_plugin::ddns::isvalidip('2001:db8::10'), 'makedns accepts IPv6');
    ok(xCAT_plugin::ddns::isvalidip('2001:DB8::10'), 'makedns accepts uppercase IPv6');
    ok(
        xCAT_plugin::ddns::isvalidip('::ffff:192.0.2.10'),
        'makedns accepts IPv4-mapped IPv6'
    );
    ok(!xCAT_plugin::ddns::isvalidip('2001:db8::g'), 'makedns rejects invalid IPv6');
    is(
        xCAT_plugin::ddns::_preferred_ip_address('2001:db8::10'),
        '2001:db8::10',
        'IPv6-only DNS host uses its IPv6 address'
    );
    is(
        xCAT_plugin::ddns::_dns_record_type('2001:db8::10'),
        'AAAA',
        'IPv6 uses an AAAA record'
    );
    my $ctx = {
        aliases       => { node01 => {} },
        currip        => '2001:db8::10',
        currname      => 'node01.example.com',
        currnode      => 'node01',
        currrevname   => '0.1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa.',
        deletemode    => 1,
        nodeips       => { node01 => {} },
        nsmap         => { 'example.com.' => 'dns.example.com' },
        updatesbyzone => {},
    };

    xCAT_plugin::ddns::find_nameserver_for_dns($ctx, 'example.com.');
    my $updates = $ctx->{updatesbyzone}->{'example.com.'};
    ok(
        grep($_ eq 'node01.example.com. IN AAAA 2001:db8::10', @{$updates}),
        'IPv6 delete queues the current AAAA record'
    );
    ok(
        grep($_ eq 'node01.example.com. AAAA', @{$updates}),
        'IPv6 delete queues a wildcard AAAA cleanup'
    );

    my $dbdir = tempdir(CLEANUP => 1);
    my $zone_context = {
        adzones      => {},
        dbdir        => $dbdir,
        hoststab     => { dns => [ { ip => '2001:db8::53' } ] },
        zonestotouch => { 'example.com.' => 1 },
    };

    {
        no warnings qw(once redefine);
        local *xCAT_plugin::ddns::hostname = sub { return 'dns'; };
        local *xCAT::NetworkUtils::getNodeDomains = sub {
            return { dns => 'example.com' };
        };
        local *xCAT::SvrUtils::sendmsg = sub { return; };
        xCAT_plugin::ddns::update_zones($zone_context);
    }

    open(my $zone_fh, '<', "$dbdir/db.example.com.")
      or die "Cannot read generated IPv6 zone: $!";
    my $zone_contents = do { local $/; <$zone_fh> };
    close($zone_fh);

    like(
        $zone_contents,
        qr/^dns\.example\.com\.\s+IN AAAA\s+2001:db8::53$/m,
        'new static zone uses AAAA glue for an IPv6-only DNS server'
    );
}

SKIP: {
    skip 'No IPv6 literal parser is available for reverse-zone conversion', 11
      unless $has_ipv6_parser;

    is(
        xCAT::NetworkUtils->getIPv6ReverseName('::'),
        join('.', ('0') x 32) . '.ip6.arpa.',
        'all-zero IPv6 PTR owner contains all 32 nibbles'
    );
    my @zero_network_zones =
      xCAT_plugin::ddns::getzonesfornet({ net => '::/128' });
    is(
        $zero_network_zones[0],
        join('.', ('0') x 32) . '.ip6.arpa.',
        'all-zero IPv6 network produces its full reverse zone'
    );
    my @default_route_zones =
      xCAT_plugin::ddns::getzonesfornet({ net => '::/0' });
    is(
        $default_route_zones[0],
        'ip6.arpa.',
        'IPv6 /0 produces the root reverse zone without looping'
    );
    my $default_route_ctx = {
        hoststab => {
            default01 => [ { ip => '2001:db8::1' } ],
        },
        nets => {
            '::/0' => {
                mask => xCAT::NetworkUtils->getipaddr('::', GetNumber => 1),
                netn => xCAT::NetworkUtils->getipaddr('::', GetNumber => 1),
            },
        },
    };
    my @default_route_entity_zones =
      xCAT_plugin::ddns::get_reverse_zones_for_entity(
        $default_route_ctx,
        'default01'
      );
    is(
        $default_route_entity_zones[0],
        'ip6.arpa.',
        'IPv6 /0 associates an entity with the root reverse zone'
    );
    is(
        xCAT::NetworkUtils->getIPv6ReverseName('::1'),
        join('.', reverse(split(//, ('0' x 31) . '1'))) . '.ip6.arpa.',
        'IPv6 PTR owner contains all 32 nibbles for a leading-zero address'
    );
    is(
        xCAT_plugin::ddns::_dns_reverse_name('::ffff:192.0.2.10'),
        join('.', reverse(split(//, '00000000000000000000ffffc000020a')))
          . '.ip6.arpa.',
        'IPv4-mapped IPv6 uses a 32-nibble IPv6 PTR owner'
    );

    xCAT::NetworkUtils->clearcache();
    my $network_number = xCAT::NetworkUtils->getipaddr(
        '2001:db8:7309::',
        GetNumber => 1
    );
    my $network_mask = xCAT::NetworkUtils->getipaddr(
        'ffff:ffff:ffff:ffff::',
        GetNumber => 1
    );
    my @reverse_zones =
      xCAT_plugin::ddns::getzonesfornet({ net => '2001:db8:7309::/64' });
    is(
        $reverse_zones[0],
        '0.0.0.0.9.0.3.7.8.b.d.0.1.0.0.2.ip6.arpa.',
        'IPv6 /64 produces the expected reverse zone'
    );
    my @split_mask_reverse_zones = xCAT_plugin::ddns::getzonesfornet(
        { net => '2001:db8:7309::', mask => '64' }
    );
    is(
        $split_mask_reverse_zones[0],
        '0.0.0.0.9.0.3.7.8.b.d.0.1.0.0.2.ip6.arpa.',
        'IPv6 network with a separate numeric mask produces the expected reverse zone'
    );
    is_deeply(
        [ xCAT_plugin::ddns::getzonesfornet({ net => '2001:db8:7309::' }) ],
        [],
        'IPv6 network without a prefix terminates without generating a reverse zone'
    );

    my $ctx = {
        hoststab => {
            node01 => [ { ip => '2001:db8:7309::1234' } ],
        },
        nets => {
            '2001:db8:7309::/64' => {
                mask => $network_mask,
                netn => $network_number,
            },
        },
    };
    my @node_reverse_zones =
      xCAT_plugin::ddns::get_reverse_zones_for_entity($ctx, 'node01');
    is(
        $node_reverse_zones[0],
        $reverse_zones[0],
        'zone generation preserves the network number used for PTR association'
    );

    my $mapped_network = '::ffff:192.0.2.0/120';
    my $mapped_ctx = {
        hoststab => {
            mapped01 => [ { ip => '::ffff:192.0.2.10' } ],
        },
        nets => {
            $mapped_network => {
                mask => xCAT::NetworkUtils->getipaddr(
                    'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ff00',
                    GetNumber => 1
                ),
                netn => xCAT::NetworkUtils->getipaddr(
                    '::ffff:192.0.2.0',
                    GetNumber => 1
                ),
            },
        },
    };
    my @mapped_zones =
      xCAT_plugin::ddns::get_reverse_zones_for_entity($mapped_ctx, 'mapped01');
    my @expected_mapped_zones =
      xCAT_plugin::ddns::getzonesfornet({ net => $mapped_network });
    is(
        $mapped_zones[0],
        $expected_mapped_zones[0],
        'IPv4-mapped IPv6 network is associated with its ip6.arpa zone'
    );
}

done_testing();
