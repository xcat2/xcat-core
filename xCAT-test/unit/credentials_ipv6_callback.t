#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
BEGIN { $ENV{XCATROOT} = "$FindBin::Bin/../../xCAT-server"; }
use Test::More;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/lib/xcat";

# credentials.pm loads Socket6 and IO::Socket::INET6 with an eval and records
# the result in a file-scoped lexical at load time, so the IPv6 branch of
# _open_callback_socket is unreachable on a host without them - which is the
# host the unit suite runs on. These stubs satisfy that eval, so the branch is
# measured everywhere, and each test replaces the constructor it needs.
BEGIN {
    package Socket6;
    $INC{'Socket6.pm'} = __FILE__;

    package IO::Socket::INET6;
    sub new { return; }
    $INC{'IO/Socket/INET6.pm'} = __FILE__;
}

my $source = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/credentials.pm";
require $source;
pass('credentials plugin loads successfully');

{
    package CredentialsCallbackTest::Socket;
}

{
    package CredentialsCallbackTest::Handle;
    our $printed = '';

    sub TIEHANDLE { return bless {}, shift; }
    sub PRINT {
        shift;
        $printed .= join( '', @_ );
        return 1;
    }
    sub READLINE { return "CREDOKBYME\n"; }
}

{
    package CredentialsCallbackTest::Select;
    sub add      { return 1; }
    sub can_read { return 1; }
}

{
    package CredentialsCallbackTest::Browser;
    our @uris;
    sub timeout { return 1; }
    sub request {
        my ( $self, $request ) = @_;
        push @uris, $request->uri->as_string;
        return bless {
            _content => 'Ciphers supported in s_server binary'
        }, 'CredentialsCallbackTest::Response';
    }
}

{
    package CredentialsCallbackTest::Response;
    sub is_success { return 1; }
}

is(
    xCAT_plugin::credentials::_callback_https_uri( '192.0.2.21', 300 ),
    'https://192.0.2.21:300/',
    'IPv4 callback URI remains unchanged'
);
is(
    xCAT_plugin::credentials::_callback_https_uri( 'node.example.test', 300 ),
    'https://node.example.test:300/',
    'hostname callback URI remains unchanged'
);
is(
    xCAT_plugin::credentials::_callback_https_uri( '2001:db8::21', 300 ),
    'https://[2001:db8::21]:300/',
    'IPv6 callback URI uses a bracketed authority'
);
is(
    xCAT_plugin::credentials::_callback_https_uri( '[2001:db8::21]', 300 ),
    'https://[2001:db8::21]:300/',
    'already-bracketed IPv6 callback URI is not double-bracketed'
);
ok(
    !defined( xCAT_plugin::credentials::_callback_https_uri( '2001:db8::21', 70000 ) ),
    'malformed callback endpoint is rejected'
);

{
    my ( %inet6_args, $inet4_calls );
    no warnings 'redefine';
    local *IO::Socket::INET6::new = sub {
        shift;
        %inet6_args = @_;
        return bless {}, 'CredentialsCallbackTest::Socket';
    };
    local *IO::Socket::INET::new = sub {
        $inet4_calls++;
        return bless {}, 'CredentialsCallbackTest::Socket';
    };

    my $socket = xCAT_plugin::credentials::_open_callback_socket( '2001:db8::21', 300 );
    isa_ok( $socket, 'CredentialsCallbackTest::Socket', 'IPv6 callback socket' );
    is_deeply(
        \%inet6_args,
        {
            PeerAddr => '2001:db8::21',
            PeerPort => 300,
            Proto    => 'tcp',
        },
        'family-neutral constructor receives the complete IPv6 literal and privileged port'
    );
    is( $inet4_calls || 0, 0, 'successful IPv6 socket does not enter the IPv4 fallback' );

    local *IO::Socket::INET6::new = sub { return; };
    my %fallback_args;
    local *IO::Socket::INET::new = sub {
        shift;
        %fallback_args = @_;
        return bless {}, 'CredentialsCallbackTest::Socket';
    };
    $socket = xCAT_plugin::credentials::_open_callback_socket( '192.0.2.21', 300 );
    is_deeply(
        \%fallback_args,
        {
            PeerAddr => '192.0.2.21',
            PeerPort => 300,
            Proto    => 'tcp',
        },
        'original IPv4 socket path remains the fallback'
    );
}

{
    no warnings qw(once redefine);
    local *CALLBACK_SOCKET;
    tie *CALLBACK_SOCKET, 'CredentialsCallbackTest::Handle';
    local *xCAT_plugin::credentials::_open_callback_socket = sub {
        is_deeply(
            [@_],
            [ '2001:db8::21', 300 ],
            'plain callback probes the complete IPv6 address and port'
        );
        return \*CALLBACK_SOCKET;
    };
    local *IO::Select::new = sub {
        return bless {}, 'CredentialsCallbackTest::Select';
    };

    $CredentialsCallbackTest::Handle::printed = '';
    is(
        xCAT_plugin::credentials::ok_with_node( '2001:db8::21', [ 0, 300 ] ),
        1,
        'plain IPv6 callback accepts the expected node response'
    );
    is(
        $CredentialsCallbackTest::Handle::printed,
        "CREDOKBYYOU?\n",
        'plain callback sends the credential challenge unchanged'
    );
    untie *CALLBACK_SOCKET;
}

{
    no warnings qw(once redefine);
    local *LWP::UserAgent::new = sub {
        return bless {}, 'CredentialsCallbackTest::Browser';
    };
    local $SIG{ALRM};
    @CredentialsCallbackTest::Browser::uris = ();

    is(
        xCAT_plugin::credentials::ok_with_node( '2001:db8::21', [ 1, 300 ] ),
        1,
        'HTTPS IPv6 callback accepts the expected s_server response'
    );
    is_deeply(
        \@CredentialsCallbackTest::Browser::uris,
        ['https://[2001:db8::21]:300/'],
        'ok_with_node sends HTTPS probe to the bracketed IPv6 authority'
    );
}

done_testing();
