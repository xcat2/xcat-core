#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
BEGIN { $ENV{XCATROOT} = "$FindBin::Bin/../../xCAT-server"; }
use POSIX ();
use Time::HiRes qw(usleep);
use Test::More;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/lib/xcat";

my $source = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/credentials.pm";
require $source;
pass('credentials plugin loads successfully');

my $allowcred = "$FindBin::Bin/../../xCAT/postscripts/allowcred.awk";
open(my $allowcred_fh, '<', $allowcred) or die "Unable to read $allowcred: $!";
my $allowcred_source = do { local $/; <$allowcred_fh> };
close($allowcred_fh);
like(
    $allowcred_source,
    qr/"MASTER_IP" in ENVIRON/,
    'shipped credential callback selects its listener family from the resolved master'
);
like(
    $allowcred_source,
    qr{listener = "/inet6/tcp/" port "/0/0"},
    'shipped credential callback has an IPv6 listener path'
);

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

my $has_inet6 = eval {
    require Socket6;
    require IO::Socket::INET6;
    1;
};
SKIP: {
    skip 'IO::Socket::INET6 and Socket6 are unavailable', 4 unless $has_inet6;

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

SKIP: {
    skip 'IPv6 loopback sockets are unavailable', 2 unless $has_inet6;
    my $listener = IO::Socket::INET6->new(
        LocalAddr => '::1',
        LocalPort => 0,
        Listen    => 1,
        Proto     => 'tcp',
        ReuseAddr => 1,
    );
    skip 'IPv6 loopback listener could not be created', 2 unless $listener;

    my $port = $listener->sockport();
    my $pid  = fork();
    skip 'fork is unavailable', 2 unless defined($pid);
    if ($pid == 0) {
        local $SIG{ALRM} = sub { POSIX::_exit(2); };
        alarm(8);
        my $peer = $listener->accept();
        POSIX::_exit(3) unless $peer;
        my $challenge = <$peer>;
        if (defined($challenge) && $challenge eq "CREDOKBYYOU?\n") {
            print {$peer} "CREDOKBYME\n";
            close($peer);
            POSIX::_exit(0);
        }
        POSIX::_exit(4);
    }

    close($listener);
    is(
        xCAT_plugin::credentials::ok_with_node( '::1', [ 0, $port ] ),
        1,
        'plain callback completes over a real IPv6 loopback socket'
    );
    waitpid( $pid, 0 );
    is( $?, 0, 'IPv6 callback server received the unchanged challenge' );
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

my $gawk;
for my $directory (split(/:/, $ENV{PATH} || '')) {
    my $candidate = "$directory/gawk";
    if (-x $candidate) {
        $gawk = $candidate;
        last;
    }
}

SKIP: {
    skip 'gawk IPv6 networking is unavailable', 2 unless $has_inet6 && $gawk;

    my $reservation = IO::Socket::INET6->new(
        LocalAddr => '::1',
        LocalPort => 0,
        Listen    => 1,
        Proto     => 'tcp',
        ReuseAddr => 1,
    );
    skip 'IPv6 loopback port reservation failed', 2 unless $reservation;
    my $port = $reservation->sockport();
    close($reservation);

    my $pid = fork();
    skip 'fork is unavailable', 2 unless defined($pid);
    if ($pid == 0) {
        $ENV{MASTER_IP} = '::1';
        $ENV{XCAT_CREDENTIAL_CALLBACK_PORT} = $port;
        open(STDOUT, '>', '/dev/null');
        open(STDERR, '>', '/dev/null');
        exec($gawk, '-f', $allowcred) or POSIX::_exit(127);
    }

    my $socket;
    for (1 .. 40) {
        $socket = IO::Socket::INET6->new(
            PeerAddr => '::1',
            PeerPort => $port,
            Proto    => 'tcp',
            Timeout  => 1,
        );
        last if $socket;
        usleep(100_000);
    }
    ok($socket, 'actual shipped callback accepts an IPv6 loopback connection');

    my $response;
    if ($socket) {
        print {$socket} "CREDOKBYYOU?\n";
        local $SIG{ALRM} = sub { die "credential callback read timed out\n"; };
        eval {
            alarm(5);
            $response = <$socket>;
            alarm(0);
        };
        alarm(0);
        close($socket);
    }
    is($response, "CREDOKBYME\n", 'actual shipped callback completes the credential challenge over IPv6');

    kill('TERM', $pid);
    waitpid($pid, 0);
}

done_testing();
