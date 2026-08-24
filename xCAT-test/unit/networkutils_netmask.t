#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;

require xCAT::NetworkUtils;

my @prefix_cases = (
    [ 0,  '0.0.0.0' ],
    [ 1,  '128.0.0.0' ],
    [ 24, '255.255.255.0' ],
    [ 32, '255.255.255.255' ],
);

foreach my $case (@prefix_cases) {
    my ( $prefix, $mask ) = @$case;
    is(
        xCAT::NetworkUtils::formatNetmask( $prefix, 1, 0 ),
        $mask,
        "prefix $prefix converts to $mask"
    );
    is(
        xCAT::NetworkUtils::formatNetmask( $mask, 0, 1 ),
        $prefix,
        "$mask converts to prefix $prefix"
    );
}

is(
    xCAT::NetworkUtils::formatNetmask( undef, 1, 0 ),
    undef,
    'undefined netmask input fails cleanly'
);
is(
    xCAT::NetworkUtils::formatNetmask( 24, 3, 0 ),
    undef,
    'unsupported input format fails cleanly'
);
is(
    xCAT::NetworkUtils::formatNetmask( 24, 1, 3 ),
    undef,
    'unsupported output format fails cleanly'
);

ok(
    xCAT::NetworkUtils::isInSameSubnet( '10.0.0.254', '10.0.0.0', '255.255.255.0', 0 ),
    'gateway inside an IPv4 subnet matches'
);
ok(
    !xCAT::NetworkUtils::isInSameSubnet( '192.0.2.1', '10.0.0.0', '255.255.255.0', 0 ),
    'gateway outside an IPv4 subnet does not match'
);

done_testing();
