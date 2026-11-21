#!/usr/bin/env perl
# A management node resolves its own name to every address on it, and a
# link-local address is usually first. xcatconfig writes that answer into
# site.master and site.nameservers, which reach every node through DHCP, DNS
# and the kernel command line, so a link-local address there is unusable: a
# node on another link cannot reach it, and the %zone form is not a literal any
# consumer accepts.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;
use xCAT::NetworkUtils;

my @cases = (
    [   'a global IPv6 address outranks a link-local one',
        [ 'fe80::5054:ff:fe12:3456', '2001:db8::50' ],
        '2001:db8::50',
    ],
    [   'an IPv4 address outranks a link-local IPv6 address',
        [ 'fe80::5054:ff:fe12:3456', '192.0.2.154' ],
        '192.0.2.154',
    ],
    [   'the zone identifier is removed from the address that is returned',
        [ 'fe80::5054:ff:fe12:3456%mgmt0' ],
        'fe80::5054:ff:fe12:3456',
    ],
    [   'a link-local address is still returned when it is the only one',
        [ 'fe80::1%eth0' ],
        'fe80::1',
    ],
    [   'an IPv4 link-local address outranks nothing but another link-local',
        [ '169.254.1.1', '192.0.2.154' ],
        '192.0.2.154',
    ],
    [   'the first address wins when none is link-local',
        [ '2001:db8::50', '192.0.2.154' ],
        '2001:db8::50',
    ],
    [   'order is kept among link-local addresses',
        [ 'fe80::2', 'fe80::3' ],
        'fe80::2',
    ],
);

foreach my $case (@cases) {
    my ( $why, $addresses, $expected ) = @{$case};
    my @ordered = xCAT::NetworkUtils->prefer_routable_addresses( @{$addresses} );
    is( $ordered[0], $expected, $why );
}

is_deeply(
    [ xCAT::NetworkUtils->prefer_routable_addresses(
            'fe80::1%eth0', '192.0.2.154', 'fe80::2', '2001:db8::50' ) ],
    [ '192.0.2.154', '2001:db8::50', 'fe80::1', 'fe80::2' ],
    'every routable address comes before every link-local one, order kept inside each group'
);

is_deeply( [ xCAT::NetworkUtils->prefer_routable_addresses() ],
    [], 'an empty list stays empty' );
# getipaddr reaches the resolver through one of two code paths, and only the
# Socket6 one runs on a management node that has Socket6 installed. Both order
# their results, so both are covered here. Socket6::getaddrinfo answers a flat
# list of five-element records, so the records move and their elements do not.
{
    no warnings 'once', 'redefine';
    local *Socket6::NI_NUMERICHOST = sub { 1 };
    local *Socket6::getnameinfo = sub {
        my %address_of = (
            PACKED_LINKLOCAL => 'fe80::5054:ff:fe12:3456',
            PACKED_GLOBAL    => '2001:db8::50',
            PACKED_V4        => '192.0.2.154',
            PACKED_BROKEN    => undef,
        );
        return ( $address_of{ $_[0] } );
    };

    my @flat = (
        10, 1, 6, 'PACKED_LINKLOCAL', 'linklocal.example',
        2,  1, 6, 'PACKED_V4',        'v4.example',
        10, 1, 6, 'PACKED_GLOBAL',    'global.example',
    );
    my @ordered = xCAT::NetworkUtils::_socket6_addrinfo_routable_first(@flat);
    is( scalar(@ordered), 15, 'every record survives the reorder' );
    is_deeply( [ @ordered[ 3, 8, 13 ] ],
        [ 'PACKED_V4', 'PACKED_GLOBAL', 'PACKED_LINKLOCAL' ],
        'the link-local record moves behind both routable records' );
    is_deeply( [ @ordered[ 0 .. 4 ] ],
        [ 2, 1, 6, 'PACKED_V4', 'v4.example' ],
        'the five elements of a record stay with that record' );

    my @with_broken = xCAT::NetworkUtils::_socket6_addrinfo_routable_first(
        10, 1, 6, 'PACKED_BROKEN', 'broken.example',
        10, 1, 6, 'PACKED_GLOBAL', 'global.example',
    );
    is( $with_broken[3], 'PACKED_GLOBAL',
        'a record whose address cannot be read goes last, not first' );

    is_deeply( [ xCAT::NetworkUtils::_socket6_addrinfo_routable_first( 1, 2, 3 ) ],
        [ 1, 2, 3 ],
        'a list that is not a whole number of records is returned untouched' );
}

is_deeply(
    [ xCAT::NetworkUtils->prefer_routable_addresses( undef, '', '192.0.2.154' ) ],
    ['192.0.2.154'], 'undef and empty entries are dropped' );

done_testing();
