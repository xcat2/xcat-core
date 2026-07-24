#!/usr/bin/env perl
use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage)

use FindBin;
use Test::More;

BEGIN {
    package xCAT::Table;
    $INC{'xCAT/Table.pm'} = __FILE__;

    package xCAT::Utils;
    $INC{'xCAT/Utils.pm'} = __FILE__;

    package xCAT::TableUtils;
    $INC{'xCAT/TableUtils.pm'} = __FILE__;

    package xCAT::NetworkUtils;
    $INC{'xCAT/NetworkUtils.pm'} = __FILE__;

    package xCAT::ServiceNodeUtils;
    $INC{'xCAT/ServiceNodeUtils.pm'} = __FILE__;
}

my $plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/networks.pm";
$plugin = "$ENV{XCATROOT}/lib/perl/xCAT_plugin/networks.pm" unless -f $plugin;
require $plugin;

ok(
    !xCAT_plugin::networks::_ignore_ipv6_route('2001:db8:1::/64 dev eth0 proto kernel'),
    'a directly connected global IPv6 network is considered',
);

my @ignored_routes = (
    [ 'fe80::/128 dev eth0 proto kernel',         'link-local prefix' ],
    [ 'unreachable 2001:db8:2::/64 metric 1024', 'unreachable route' ],
    [ 'default via 2001:db8::1 dev eth0',         'default route' ],
    [ '  nexthop via fe80::1 dev eth0 weight 1',  'multipath nexthop continuation' ],
    [ '2001:db8:3::/64 via 2001:db8::1 dev eth0', 'gatewayed route' ],
    [ '::1 dev lo proto kernel metric 256',       'loopback route' ],
);

for my $case (@ignored_routes) {
    ok(xCAT_plugin::networks::_ignore_ipv6_route($case->[0]), "$case->[1] is ignored");
}

done_testing();
