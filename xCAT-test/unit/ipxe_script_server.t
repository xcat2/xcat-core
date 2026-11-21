#!/usr/bin/env perl
#
# The server an iPXE boot script names for a node.
#
# xnba.pm writes ${next-server} into the script and lets iPXE fill it from the DHCP offer.
# next-server is a DHCPv4 field, so an IPv6 node resolves it to nothing and every URL in the
# script loses its host. ipxe.pm runs the same code, so this reaches netboot=ipxe as well.
use strict;
use warnings;

use FindBin;
use Test::More tests => 7;

use lib "$FindBin::Bin/../../perl-xCAT";
use xCAT::NetworkUtils;

is( xCAT::NetworkUtils::ipxe_script_server(4, '192.0.2.1'), '${next-server}',
    'an IPv4 node keeps the iPXE variable, which iPXE fills from its own offer' );
is( xCAT::NetworkUtils::ipxe_script_server(undef, '192.0.2.1'), '${next-server}',
    'a node of unknown family keeps the variable, so nothing changes for it' );

# The script puts the server in a URL, so an IPv6 literal needs its brackets.
is( xCAT::NetworkUtils::ipxe_script_server(6, '2001:db8::1'), '[2001:db8::1]',
    'an IPv6 node carries the address, bracketed' );
is( xCAT::NetworkUtils::ipxe_script_server(6, 'mn.cluster.example'), 'mn.cluster.example',
    'a name is carried as it is, because a name needs no brackets' );

# Without a facing address there is nothing to name. ${next-server} would be worse than
# nothing: it resolves to the empty string and the URL loses its host silently.
is( xCAT::NetworkUtils::ipxe_script_server(6, undef), undef,
    'an IPv6 node with no facing address yields nothing' );
is( xCAT::NetworkUtils::ipxe_script_server(6, ''), undef,
    'and an empty facing address yields nothing' );

# The whole point is that the two families differ here.
isnt( xCAT::NetworkUtils::ipxe_script_server(6, '2001:db8::1'),
    xCAT::NetworkUtils::ipxe_script_server(4, '192.0.2.1'),
    'the two families are not given the same text' );
