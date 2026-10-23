#!/usr/bin/env perl
# The Socket6 half of the getipaddr link-local order. A management node that
# carries Socket6 takes this path and no other, so site.master gets its value
# from here. The core Socket half is in networkutils_getipaddr_routable_first.t.
#
# Socket6::getaddrinfo answers a flat list of five-element records, which is a
# different shape from the core resolver, and the branch orders each shape with
# its own helper.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

# NetworkUtils decides which resolver path to use from "require Socket6", read
# once at load into a file-scoped lexical. The stub below satisfies that
# require, so this file measures the Socket6 path on a host that has no
# Socket6 - which is the condition the unit suite runs in.
our @resolver_answer;

BEGIN {
    package Socket6;
    use strict;
    use warnings;
    sub AI_NUMERICHOST { return 4 }
    sub NI_NUMERICHOST { return 1 }
    sub AF_INET        { return 2 }

    sub getaddrinfo {
        my ( $host, $service, $family, $socktype, $protocol, $flags ) = @_;
        return () unless @main::resolver_answer;
        my @flat;
        foreach my $address (@main::resolver_answer) {
            push @flat,
              ( $address =~ /:/ ? 10 : 2 ),
              1, 6, "SOCKADDR:$address", "$address.example.com";
        }
        return @flat;
    }

    sub getnameinfo {
        my $addr = shift;
        return () unless defined($addr) && $addr =~ /^SOCKADDR:(.+)$/;
        return ($1);
    }

    sub inet_pton {
        my ( $family, $address ) = @_;
        return Socket::inet_pton( $family == 10 ? Socket::AF_INET6() : Socket::AF_INET(),
            $address );
    }
    $INC{'Socket6.pm'} = __FILE__;
}

use xCAT::NetworkUtils;

sub resolve {
    my ( $answer, @extra ) = @_;
    @resolver_answer = @{$answer};
    %::hostiphash    = ();
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

is( resolve( ['fe80::1'] ),
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
    'getipaddr answers undef when the resolver answers nothing' );

done_testing();
