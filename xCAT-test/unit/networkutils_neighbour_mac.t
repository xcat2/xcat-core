#!/usr/bin/env perl
# Sequential discovery resolves the address a findme arrived from to a MAC, and looks that
# MAC up in the mac table. Five plugins carried the same arp(8) parse, which reads the IPv4
# table and matched the address as a regular expression. The parse now takes the table text,
# so a table from either tool is a fixture here instead of the test host's own cache.
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

my $arp_table = <<'TABLE';
Address                  HWtype  HWaddress           Flags Mask            Iface
192.168.201.10           ether   52:54:00:aa:bb:cc   C                     ens7
192.168.201.11                   (incomplete)                              ens7
192.168.201.120          ether   52:54:00:11:22:33   C                     ens7
TABLE

my $ip6_table = <<'TABLE';
2001:db8:177::2 dev ens7 lladdr 52:54:00:aa:bb:cc router REACHABLE
2001:db8:177::3 dev ens7  FAILED
fe80::5054:ff:feaa:bbcc dev ens7 lladdr 52:54:00:aa:bb:cc router STALE
2001:db8:177::4 dev ens7 lladdr 52:54:00:de:ad:be STALE
TABLE

my $ip4_table = <<'TABLE';
192.168.201.10 dev ens7 lladdr 52:54:00:aa:bb:cc REACHABLE
192.168.201.11 dev ens7  INCOMPLETE
TABLE

# IPv4, from arp(8): the format the five plugins read before.
is(
    xCAT::NetworkUtils->mac_from_neighbour_table($arp_table, '192.168.201.10'),
    '52:54:00:aa:bb:cc',
    'the MAC of an IPv4 neighbour comes out of the arp table',
);
is(
    xCAT::NetworkUtils->mac_from_neighbour_table($arp_table, '192.168.201.11'),
    undef,
    'an incomplete arp entry has no MAC',
);
# The address used to be interpolated into a regular expression, where a dot matched
# any character, so 192.168.201.1 matched the row of 192.168.201.120 and the wrong
# node was named.
is(
    xCAT::NetworkUtils->mac_from_neighbour_table($arp_table, '192.168.201.1'),
    undef,
    'an address that is a prefix of another row does not match that row',
);
is(
    xCAT::NetworkUtils->mac_from_neighbour_table($arp_table, '192.168.201.99'),
    undef,
    'an address the table does not hold has no MAC',
);

# IPv6, from ip(8): the case that returned nothing at all.
is(
    xCAT::NetworkUtils->mac_from_neighbour_table($ip6_table, '2001:db8:177::2'),
    '52:54:00:aa:bb:cc',
    'the MAC of an IPv6 neighbour comes out of the IPv6 neighbour table',
);
is(
    xCAT::NetworkUtils->mac_from_neighbour_table($ip6_table, '2001:0db8:0177:0000:0000:0000:0000:0002'),
    '52:54:00:aa:bb:cc',
    'the same address written in full matches the same row',
);
is(
    xCAT::NetworkUtils->mac_from_neighbour_table($ip6_table, '2001:db8:177::3'),
    undef,
    'a failed IPv6 entry carries no lladdr and so no MAC',
);
is(
    xCAT::NetworkUtils->mac_from_neighbour_table($ip6_table, 'fe80::5054:ff:feaa:bbcc%ens7'),
    '52:54:00:aa:bb:cc',
    'a scoped link-local address matches its unscoped row',
);
is(
    xCAT::NetworkUtils->mac_from_neighbour_table($ip6_table, '2001:db8:177::9'),
    undef,
    'an IPv6 address the table does not hold has no MAC',
);

# ip(8) also prints the IPv4 table in that format.
is(
    xCAT::NetworkUtils->mac_from_neighbour_table($ip4_table, '192.168.201.10'),
    '52:54:00:aa:bb:cc',
    'an IPv4 row printed by ip(8) is read as well',
);
is(
    xCAT::NetworkUtils->mac_from_neighbour_table($ip4_table, '192.168.201.11'),
    undef,
    'an incomplete ip(8) entry has no MAC',
);

# An upper-case table is one table.
is(
    xCAT::NetworkUtils->mac_from_neighbour_table(
        "2001:DB8:177::2 dev ens7 lladdr 52:54:00:AA:BB:CC REACHABLE\n",
        '2001:db8:177::2',
    ),
    '52:54:00:aa:bb:cc',
    'the MAC is returned in lower case, as the mac table holds it',
);

# A twenty-byte InfiniBand address is a link-layer address too.
is(
    xCAT::NetworkUtils->mac_from_neighbour_table(
        "192.168.201.10 dev ib0 lladdr 80:00:02:08:fe:80:00:00:00:00:00:00:00:02:c9:03:00:1a:2b:3c REACHABLE\n",
        '192.168.201.10',
    ),
    '80:00:02:08:fe:80:00:00:00:00:00:00:00:02:c9:03:00:1a:2b:3c',
    'an InfiniBand link-layer address is read whole',
);

is(xCAT::NetworkUtils->mac_from_neighbour_table(undef, '192.168.201.10'), undef,
    'no table means no MAC');
is(xCAT::NetworkUtils->mac_from_neighbour_table($arp_table, undef), undef,
    'no address means no MAC');
is(xCAT::NetworkUtils->mac_from_neighbour_table($arp_table, 'not-an-address'), undef,
    'an address that does not parse means no MAC');

done_testing();
