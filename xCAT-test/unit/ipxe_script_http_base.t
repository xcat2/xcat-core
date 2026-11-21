#!/usr/bin/perl
# Every URL in a per-network iPXE boot script needs a host.
#
# mknb writes one script per network under xcat/ipxe/nets, and that script is what an unknown
# client boots: it carries destiny=discover and no node name, so the Genesis image asks to be
# discovered. The script used ${next-server} for the server in every URL. DHCPv4 fills that from
# the siaddr of the offer; DHCPv6 has no next-server option at all, so iPXE leaves it empty and
# the fetch has no host. Measured on xcat88-mn: the per-NODE script, which boots, carries
# http://[2001:db8:188::1]/... while the per-NETWORK script carried http://${next-server}/...
use strict;
use warnings;
use Test::More tests => 7;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

require xCAT::NetworkUtils;

can_ok( 'xCAT::NetworkUtils', 'ipxe_script_http_base' );

my $v6 = xCAT::NetworkUtils::ipxe_script_http_base( '2001:db8:188::1', '[2001:db8:188::1]', '' );
is( $v6, 'http://[2001:db8:188::1]',
    'an IPv6 network carries the address of the management node, because DHCPv6 has no next-server' );
unlike( $v6, qr/next-server/, 'and nothing is left for iPXE to fill in' );

is( xCAT::NetworkUtils::ipxe_script_http_base( '192.168.88.1', '192.168.88.1', '' ),
    'http://${next-server}',
    'an IPv4 network keeps ${next-server}, which its offer fills in' );

is( xCAT::NetworkUtils::ipxe_script_http_base( '2001:db8:188::1', '[2001:db8:188::1]', ':8080' ),
    'http://[2001:db8:188::1]:8080', 'the port suffix is kept on an IPv6 network' );
is( xCAT::NetworkUtils::ipxe_script_http_base( '192.168.88.1', '192.168.88.1', ':8080' ),
    'http://${next-server}:8080', 'the port suffix is kept on an IPv4 network' );

# A network with no address of its own must not produce a URL with a bracketed empty host.
is( xCAT::NetworkUtils::ipxe_script_http_base( undef, undef, '' ),
    'http://${next-server}', 'an unknown family falls back to the DHCPv4 form' );
