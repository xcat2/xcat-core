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
        [ 'fe80::4054:ff:fec9:9ad2', '2001:db8::50' ],
        '2001:db8::50',
    ],
    [   'an IPv4 address outranks a link-local IPv6 address',
        [ 'fe80::4054:ff:fec9:9ad2', '192.0.2.154' ],
        '192.0.2.154',
    ],
    [   'the zone identifier is removed from the address that is returned',
        [ 'fe80::4054:ff:fec9:9ad2%mgmt0' ],
        'fe80::4054:ff:fec9:9ad2',
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
is_deeply(
    [ xCAT::NetworkUtils->prefer_routable_addresses( undef, '', '192.0.2.154' ) ],
    ['192.0.2.154'], 'undef and empty entries are dropped' );

done_testing();
