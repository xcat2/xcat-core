#!/usr/bin/env perl
# xcatconfig writes site.master from getipaddr of the management node name, and
# a management node resolves its own name to its link-local address as well as
# to a routable one. A node on another link cannot reach fe80::/10, so getipaddr
# must answer the routable address. getipaddr reaches the resolver through two
# paths and each orders its own answer. This file covers the core Socket path;
# networkutils_getipaddr_socket6_routable_first.t covers the Socket6 path.
use strict;
use warnings;

# The path getipaddr takes is decided by a file-scoped lexical that NetworkUtils
# reads once at load. An undef %INC entry makes its "require Socket6" die, so
# the core Socket path runs here whether or not the host carries Socket6.
BEGIN { $INC{'Socket6.pm'} = undef; }

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Socket ();
use Test::More;
use xCAT::NetworkUtils;

plan skip_all => 'The core Socket resolver is not available'
  unless defined(&Socket::getaddrinfo) && defined(&Socket::getnameinfo);

# Socket::getaddrinfo answers a list of hashes whose addr is a packed
# sockaddr. The stub carries the literal in that field, and the getnameinfo
# stub reads it back, so a case states its resolver answer as addresses.
my @resolver_answer;

sub addrinfo_entry {
    my $address = shift;
    return {
        family   => ( $address =~ /:/ ? Socket::AF_INET6() : Socket::AF_INET() ),
        socktype => Socket::SOCK_STREAM(),
        protocol => 6,
        addr     => "SOCKADDR:$address",
    };
}

my @asked_family;

no warnings qw(once redefine);
local *Socket::getaddrinfo = sub {
    my ( $host, $service, $hints ) = @_;
    push @asked_family, $hints->{family};
    return ('Name or service not known') unless @resolver_answer;
    return ( undef, map { addrinfo_entry($_) } @resolver_answer );
};
local *Socket::getnameinfo = sub {
    my $addr = shift;
    return ('Unreadable address') unless defined($addr) && $addr =~ /^SOCKADDR:(.+)$/;
    return ( undef, $1 );
};

sub resolve {
    my ( $answer, @extra ) = @_;
    @resolver_answer   = @{$answer};
    %::hostiphash      = ();
    return xCAT::NetworkUtils->getipaddr( 'mn.example.com', @extra );
}

is( resolve( [ 'fe80::4054:ff:fec9:9ad2', '2001:db8::50' ] ),
    '2001:db8::50',
    'getipaddr answers the routable address when the resolver lists link-local first'
);

is( resolve( [ 'fe80::4054:ff:fec9:9ad2', '192.0.2.154' ] ),
    '192.0.2.154',
    'getipaddr answers the IPv4 address when the resolver lists link-local first'
);

is( resolve( [ '169.254.3.4', '192.0.2.154' ] ),
    '192.0.2.154',
    'getipaddr skips an IPv4 link-local address for a routable one'
);

is( resolve( [ 'fe80::1' ] ),
    'fe80::1',
    'getipaddr still answers a link-local address when it is the only one'
);

is( resolve( [ '2001:db8::50', '192.0.2.154' ] ),
    '2001:db8::50',
    'getipaddr keeps the resolver order when no address is link-local'
);

is_deeply(
    [ resolve( [ 'fe80::1', '2001:db8::50', '192.0.2.154' ], GetAllAddresses => 1 ) ],
    [ '2001:db8::50', '192.0.2.154', 'fe80::1' ],
    'GetAllAddresses lists every routable address before the link-local one'
);

is( resolve( [ 'fe80::4054:ff:fec9:9ad2', '2001:db8::50' ], OnlyV6 => 1 ),
    '2001:db8::50',
    'an OnlyV6 lookup answers the routable IPv6 address, not the link-local one'
);

is(
    resolve( [ 'fe80::1', '2001:db8::50' ], GetNumber => 1 )->bstr(),
    Math::BigInt->new('42540766411282592856903984951653826640')->bstr(),
    'GetNumber answers the number of the routable address'
);

is( resolve( [] ), undef,
    'getipaddr answers undef when the resolver reports an error' );

done_testing();
