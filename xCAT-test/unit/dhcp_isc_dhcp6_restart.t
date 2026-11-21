#!/usr/bin/env perl
# xCAT writes /etc/dhcp/dhcpd6.conf only for an IPv6 network. On a cluster with no IPv6
# network the file stays absent, which makedhcp reads as a configuration to replace, so a
# restart of dhcpd6 must not follow from that alone: the daemon has no subnet to serve.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;
use xCAT::DHCP::Backend::ISC;

sub needed { return xCAT::DHCP::Backend::ISC->dhcp6_restart_needed(@_) }

ok( !needed( changed => 1, ipv6 => 0 ),
    'an absent dhcpd6 configuration does not restart dhcpd6 when no network is IPv6' );
ok( needed( changed => 1, ipv6 => 1 ),
    'a replaced dhcpd6 configuration restarts dhcpd6 when a network is IPv6' );
ok( !needed( changed => 0, ipv6 => 1 ),
    'an unchanged dhcpd6 configuration restarts nothing' );
ok( !needed( changed => 0, ipv6 => 0 ), 'neither condition restarts nothing' );

done_testing();
