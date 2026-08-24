#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-probe/lib/perl";

use Test::More;

require probe_utils;

ok(
    probe_utils::dhcp_query_reply_matches(
        'xcatmntest: ip-address = 10.10.0.254, hardware-address = aa:aa:aa:aa:aa:aa',
        'xcatmntest',
        '10.10.0.254',
        'aa:aa:aa:aa:aa:aa',
    ),
    'ISC-style makedhcp query output with comma matches'
);

ok(
    probe_utils::dhcp_query_reply_matches(
        'xcatmntest: ip-address = 10.10.0.254 hardware-address = aa:aa:aa:aa:aa:aa',
        'xcatmntest',
        '10.10.0.254',
        'aa:aa:aa:aa:aa:aa',
    ),
    'Kea-style makedhcp query output without comma matches'
);

is(
    probe_utils::dhcp_query_reply_mac(
        'node01: ip-address = 192.0.2.10 hardware-address = AA:BB:CC:DD:EE:FF',
        'node01',
        '192.0.2.10',
    ),
    'AA:BB:CC:DD:EE:FF',
    'DHCP query MAC is extracted without normalizing display case'
);

ok(
    !probe_utils::dhcp_query_reply_matches(
        'xcatmntest: ip-address = 10.10.0.99 hardware-address = aa:aa:aa:aa:aa:aa',
        'xcatmntest',
        '10.10.0.254',
        'aa:aa:aa:aa:aa:aa',
    ),
    'mismatched IP does not match'
);

done_testing();
