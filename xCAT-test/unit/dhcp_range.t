use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

use xCAT::DHCP::Range;

my $pair = xCAT::DHCP::Range->parse('10.0.0.10-10.0.0.20');
is( $pair->{family}, 4, 'IPv4 range is detected' );
is( $pair->{start}, '10.0.0.10', 'range start is parsed' );
is( $pair->{end}, '10.0.0.20', 'range end is parsed' );
is( xCAT::DHCP::Range->isc_range($pair), '10.0.0.10 10.0.0.20', 'ISC range uses space separator' );
is( xCAT::DHCP::Range->kea_pool($pair), '10.0.0.10 - 10.0.0.20', 'Kea pool uses JSON pool syntax' );

my $padded_pair = xCAT::DHCP::Range->parse(" \t10.0.0.10-10.0.0.20\r\n");
is( $padded_pair->{source}, '10.0.0.10-10.0.0.20', 'surrounding range whitespace is removed' );

is_deeply(
    [ xCAT::DHCP::Range->isc_ranges('10.0.0.10,10.0.0.20;10.0.1.10 10.0.1.20') ],
    [ '10.0.0.10 10.0.0.20', '10.0.1.10 10.0.1.20' ],
    'multiple ranges are normalized for ISC'
);

is_deeply(
    [ xCAT::DHCP::Range->kea_pools('10.0.0.10,10.0.0.20;10.0.1.10 10.0.1.20') ],
    [
        { pool => '10.0.0.10 - 10.0.0.20' },
        { pool => '10.0.1.10 - 10.0.1.20' },
    ],
    'multiple ranges are normalized for Kea pools'
);

my $cidr = xCAT::DHCP::Range->parse('192.168.50.0/30');
is( xCAT::DHCP::Range->isc_range($cidr), '192.168.50.0 192.168.50.3', 'IPv4 CIDR is expanded for ISC' );
is( xCAT::DHCP::Range->kea_pool($cidr), '192.168.50.0 - 192.168.50.3', 'IPv4 CIDR is expanded for Kea' );

my ( $start, $end ) = xCAT::DHCP::Range->bounds($cidr);
is( "$start", '3232248320', 'CIDR start numeric bound is tracked' );
is( "$end", '3232248323', 'CIDR end numeric bound is tracked' );

my $zero_start = xCAT::DHCP::Range->parse('0.0.0.0-0.0.0.10');
is( xCAT::DHCP::Range->isc_range($zero_start), '0.0.0.0 0.0.0.10', 'zero-valued range starts are preserved' );

SKIP: {
    skip 'Socket6 is not installed', 3 unless eval { require Socket6; 1 };
    my $cidr6 = xCAT::DHCP::Range->parse('2001:db8::/120');
    is( $cidr6->{family}, 6, 'IPv6 CIDR is detected' );
    is( xCAT::DHCP::Range->isc_range($cidr6), '2001:db8::/120', 'IPv6 CIDR is preserved for ISC DHCPv6' );
    is( xCAT::DHCP::Range->kea_pool($cidr6), '2001:db8::/120', 'IPv6 CIDR is preserved for Kea DHCPv6' );
}

is_deeply( xCAT::DHCP::Range->parse_dynamic_ranges(undef), [], 'undefined range list returns no ranges' );
is( xCAT::DHCP::Range->parse('not-a-range'), undef, 'invalid range returns undef' );

done_testing();
