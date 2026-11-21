#!/usr/bin/env perl
#
# The server an iPXE boot script names for ONE node, and what happens when there is none.
#
# xnba.pm starts the script server at ${next-server} and replaced it only when the IPv6 lookup
# answered: "$script_server = $resolved if defined $resolved". So an IPv6 node for which this
# server has no facing address kept the DHCPv4 variable. An IPv6 client resolves it to the empty
# string, every URL in the script loses its host, and nodeset reports success. ipxe.pm runs the
# same code with SCRIPTS set to xcat/ipxe, so netboot=ipxe takes the same path.
#
# The decision is a sub so it can be called here. The two lookups it makes are stubbed at the
# Perl level, which is what lets the three outcomes be driven without a cluster.
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../../perl-xCAT";
use xCAT::NetworkUtils;

# $family is what node_address_family answers, @facing what my_ip_facing_family answers.
sub server_for {
    my ( $family, @facing ) = @_;
    no warnings 'redefine';
    local *xCAT::NetworkUtils::node_address_family  = sub { return $family };
    local *xCAT::NetworkUtils::my_ip_facing_family  = sub { return @facing };
    return xCAT::NetworkUtils->ipxe_script_server_for_node('cn01');
}

my ( $server, $error ) = server_for( 4, 0, '192.0.2.1' );
is( $server, '${next-server}', 'an IPv4 node keeps the variable iPXE fills from its own offer' );
is( $error, undef, 'and is not an error' );

( $server, $error ) = server_for( undef, 0, '192.0.2.1' );
is( $server, '${next-server}', 'a node of unknown family keeps the variable, so nothing changes' );
is( $error, undef, 'and is not an error either' );

( $server, $error ) = server_for( 6, 0, '2001:db8::1' );
is( $server, '[2001:db8::1]', 'an IPv6 node carries the facing address, bracketed for a URL' );
is( $error, undef, 'and is not an error' );

# THE OUTCOME THAT USED TO BE SILENT. No facing IPv6 address means there is no host to put in
# any URL of the script, so nodeset must say so rather than write a script that cannot work.
( $server, $error ) = server_for( 6, 1, 'no IPv6 interface faces cn01' );
is( $server, undef, 'an IPv6 node with no facing address gets no server' );
isnt( $error, undef, 'and the caller is given an error, not the DHCPv4 variable' );
like( $error, qr/\bcn01\b/, 'the error names the node' );
like( $error, qr/IPv6/, 'and the family, because the IPv4 lookup may well have answered' );
unlike( $error // '', qr/\Qnext-server\E/,
        'the error does not offer the variable as a fallback, which resolves to nothing' );

# The empty answer is the same outcome: my_ip_facing_family reports success with no address when
# the interface exists and carries no global address.
( $server, $error ) = server_for( 6, 0, '' );
is( $server, undef, 'an empty facing address is no address' );
isnt( $error, undef, 'and is reported' );
( $server, $error ) = server_for( 6, 0, undef );
is( $server, undef, 'and so is an undefined one' );
isnt( $error, undef, 'which is also reported' );

# The whole point is that the two families differ. A sub that answered the same for both would
# satisfy every assertion above except this one.
my ($v4) = server_for( 4, 0, '192.0.2.1' );
my ($v6) = server_for( 6, 0, '2001:db8::1' );
isnt( $v4, $v6, 'the two families are not given the same text' );

done_testing();
