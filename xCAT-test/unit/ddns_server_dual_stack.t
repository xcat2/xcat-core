#!/usr/bin/env perl
# makedns writes the address record of the name server itself into every zone file it creates,
# and it wrote one record. _preferred_ip_address returns the first IPv4 address, so a dual-stack
# server published an A record and no AAAA.
#
# An IPv6-only node resolves that name to reach the server. With no AAAA in the zone it gets
# nothing, or, behind a DNS64 translator, the synthesis of the IPv4 address.
#
# _server_ip_addresses keeps every valid address, IPv4 first, and the zone writer loops over it.
# _preferred_ip_address is unchanged: it still names one address for the error path, and
# ddns_ipv6.t holds that contract down.
use strict;
use warnings;

use FindBin;
BEGIN { $ENV{XCATROOT} = "$FindBin::Bin/../../xCAT-server"; }
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

$ENV{XCATCFG} ||= 'SQLite:/tmp';

my $source_ddns_plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/ddns.pm";
if (-f $source_ddns_plugin) { require $source_ddns_plugin }
else                        { require xCAT_plugin::ddns }

# The defect: a dual-stack server has to publish both records.
is_deeply(
    [ xCAT_plugin::ddns::_server_ip_addresses('2001:db8::10', '192.0.2.10') ],
    [ '192.0.2.10', '2001:db8::10' ],
    'a dual-stack server publishes both addresses, IPv4 first'
);

# The record type of each one is what decides A against AAAA in the zone file.
is(xCAT_plugin::ddns::_dns_record_type('192.0.2.10'),  'A',
    'the IPv4 address becomes an A record');
is(xCAT_plugin::ddns::_dns_record_type('2001:db8::10'), 'AAAA',
    'the IPv6 address becomes an AAAA record');

# An IPv6-only server still publishes its one record, so a single-stack cluster is unchanged.
is_deeply(
    [ xCAT_plugin::ddns::_server_ip_addresses('2001:db8::10') ],
    [ '2001:db8::10' ],
    'an IPv6-only server publishes its AAAA'
);
is_deeply(
    [ xCAT_plugin::ddns::_server_ip_addresses('192.0.2.10') ],
    [ '192.0.2.10' ],
    'an IPv4-only server publishes its A'
);

# A malformed address must not reach a zone file, where named refuses to load the whole zone.
is_deeply(
    [ xCAT_plugin::ddns::_server_ip_addresses('192.0.2.999', '192.0.2.10') ],
    [ '192.0.2.10' ],
    'an invalid address is dropped'
);

# The control: the one-address chooser keeps its own contract, which the error path reports and
# ddns_ipv6.t asserts.
is(
    xCAT_plugin::ddns::_preferred_ip_address('2001:db8::10', '192.0.2.10'),
    '192.0.2.10',
    'the single-address chooser still prefers IPv4'
);

done_testing();
