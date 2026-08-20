#!/usr/bin/env perl
## no critic (TestingAndDebugging::ProhibitNoStrict)
use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

BEGIN {
    package xCAT::Table;
    our $servicenode;
    sub import { }
    sub new { return bless {}, shift; }
    sub getNodeAttribs { return { servicenode => $servicenode }; }
    $INC{'xCAT/Table.pm'} = 1;

    package xCAT::NodeRange;
    our %ranges;
    sub import {
        no strict 'refs';
        *{ caller() . '::noderange' } = \&noderange;
    }
    sub noderange {
        my ($name) = @_;
        return @{ $ranges{$name} || [] };
    }
    $INC{'xCAT/NodeRange.pm'} = 1;

    package xCAT::Zone;
    sub import { }
    $INC{'xCAT/Zone.pm'} = 1;

    package xCAT::Utils;
    our $service_node;
    sub import { }
    sub isAIX { return 0; }
    sub isServiceNode { return $service_node; }
    $INC{'xCAT/Utils.pm'} = 1;

    package xCAT::NetworkUtils;
    our %addresses;
    sub import { }
    sub getipaddr {
        my ($class, $endpoint) = @_;
        return @{ $addresses{$endpoint} || [] };
    }
    $INC{'xCAT/NetworkUtils.pm'} = 1;

    package xCAT::PasswordUtils;
    sub import { }
    $INC{'xCAT/PasswordUtils.pm'} = 1;

    package xCAT::TableUtils;
    our $master = '192.0.2.10';
    sub import { }
    sub get_site_attribute { return ($master); }
    $INC{'xCAT/TableUtils.pm'} = 1;

    package xCAT::MsgUtils;
    our @messages;
    sub import { }
    sub trace { push @messages, [@_]; }
    sub message {
        push @messages, [@_];
        my $callback = $_[3];
        $callback->($_[2]) if ref($callback) eq 'CODE';
    }
    $INC{'xCAT/MsgUtils.pm'} = 1;

    package xCAT::Client;
    our @responses;
    our ($exception, $request, $host, $trigger_timeout);
    sub import { }
    sub submit_request {
        ($request, my $callback) = @_;
        $host = $ENV{XCATHOST};
        die $exception if defined($exception);
        $SIG{ALRM}->() if $trigger_timeout;
        $callback->($_) for @responses;
    }
    $INC{'xCAT/Client.pm'} = 1;

    package LWP;
    sub import { }
    $INC{'LWP.pm'} = 1;

    package LWP::UserAgent;
    sub new { return bless {}, shift; }

    package HTTP::Request::Common;
    sub import {
        no strict 'refs';
        *{ caller() . '::GET' } = sub { return $_[0]; };
    }
    $INC{'HTTP/Request/Common.pm'} = 1;
}

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $plugin = File::Spec->catfile(
    $repo_root, qw(xCAT-server lib xcat plugins credentials.pm)
);
require $plugin;

sub reset_client {
    @xCAT::Client::responses = ();
    @xCAT::MsgUtils::messages = ();
    $xCAT::Client::exception = undef;
    $xCAT::Client::request = undef;
    $xCAT::Client::host = undef;
    $xCAT::Client::trigger_timeout = 0;
    $xCAT::TableUtils::master = '192.0.2.10';
}

my $commands = xCAT_plugin::credentials::handled_commands();
is( $commands->{getcredentials}, 'credentials',
    'credentials plugin still handles client requests' );
is( $commands->{signx509cert}, 'credentials',
    'credentials plugin handles delegated signing' );

$xCAT::Table::servicenode = 'service-a, service-b.example.test';
%xCAT::NetworkUtils::addresses = (
    '192.0.2.21'           => ['192.0.2.21'],
    '192.0.2.22'           => ['192.0.2.22'],
    '192.0.2.23'           => ['192.0.2.23'],
    '::ffff:192.0.2.22'    => ['::ffff:192.0.2.22'],
    'service-a'            => ['192.0.2.21'],
    'service-b'            => ['192.0.2.22'],
    'service-b-alias'      => ['192.0.2.22'],
    'service-b.example.test' => ['192.0.2.22'],
    'service-c'            => ['192.0.2.23'],
    'service-c.example.test' => ['192.0.2.23'],
);

ok(
    xCAT_plugin::credentials::_delegated_signer_allowed(
        {
            _xcat_authname  => ['root'],
            _xcat_clienthost => ['service-a'],
            _xcat_clientip   => ['192.0.2.21'],
        },
        'compute-01'
    ),
    'assigned authenticated service node may request a certificate'
);
ok(
    xCAT_plugin::credentials::_delegated_signer_allowed(
        {
            _xcat_authname   => ['root'],
            _xcat_clientfqdn => ['service-b.example.test'],
            _xcat_clientip   => ['192.0.2.22'],
        },
        'compute-01'
    ),
    'assigned service node may match its FQDN'
);
ok(
    xCAT_plugin::credentials::_delegated_signer_allowed(
        {
            _xcat_authname => ['root'],
            _xcat_clientip => ['192.0.2.22'],
        },
        'compute-01'
    ),
    'numeric peer address works without reverse DNS'
);
ok(
    xCAT_plugin::credentials::_delegated_signer_allowed(
        {
            _xcat_authname => ['root'],
            _xcat_clientip => ['::ffff:192.0.2.22'],
        },
        'compute-01'
    ),
    'IPv4-mapped peer address matches the assigned IPv4 service node'
);

$xCAT::Table::servicenode = '192.0.2.22';
ok(
    xCAT_plugin::credentials::_delegated_signer_allowed(
        {
            _xcat_authname  => ['root'],
            _xcat_clienthost => ['service-b'],
            _xcat_clientip   => ['192.0.2.22'],
        },
        'compute-01'
    ),
    'service node assignment may use an IP address'
);

$xCAT::Table::servicenode = 'service-b-alias';
ok(
    xCAT_plugin::credentials::_delegated_signer_allowed(
        {
            _xcat_authname => ['root'],
            _xcat_clientip => ['192.0.2.22'],
        },
        'compute-01'
    ),
    'service node assignment may use a resolvable alias'
);

$xCAT::Table::servicenode = 'service-b.example.test';
ok(
    !xCAT_plugin::credentials::_delegated_signer_allowed(
        {
            _xcat_authname   => ['root'],
            _xcat_clienthost => ['service-b'],
            _xcat_clientip   => ['192.0.2.23'],
        },
        'compute-01'
    ),
    'reverse DNS name cannot override a different peer address'
);

ok(
    !xCAT_plugin::credentials::_delegated_signer_allowed(
        {
            _xcat_authname   => ['root'],
            _xcat_clienthost => ['service-c'],
            _xcat_clientfqdn => ['service-c.example.test'],
            _xcat_clientip   => ['192.0.2.23'],
        },
        'compute-01'
    ),
    'resolved but unassigned service node is rejected'
);
ok(
    !xCAT_plugin::credentials::_delegated_signer_allowed(
        {
            _xcat_clienthost => ['service-b'],
            _xcat_clientip   => ['192.0.2.22'],
        },
        'compute-01'
    ),
    'unauthenticated request is rejected'
);
ok(
    !xCAT_plugin::credentials::_delegated_signer_allowed(
        { _xcat_authname => ['root'] }, 'compute-01'
    ),
    'authenticated request without a peer identity is rejected'
);

reset_client();
@xCAT::Client::responses = (
    {
        data => [
            {
                desc    => ['x509cert'],
                content => 'scalar certificate',
            }
        ]
    },
    { serverdone => [undef] },
);
my ($certificate, $error) =
  xCAT_plugin::credentials::_request_x509_from_master(
    'compute-01', 'certificate request'
  );
is( $certificate, 'scalar certificate',
    'delegated signer accepts the serialized xCAT response shape' );
is( $error, undef, 'successful delegated request has no error' );
is( $xCAT::Client::host, '192.0.2.10:3001',
    'delegated request targets site.master' );
is_deeply(
    $xCAT::Client::request,
    {
        command => ['signx509cert'],
        arg     => ['compute-01'],
        csr     => ['certificate request'],
    },
    'delegated request carries the node and CSR'
);

reset_client();
$xCAT::TableUtils::master = '2001:db8::10';
@xCAT::Client::responses = (
    {
        data => [
            {
                desc    => 'x509cert',
                content => ['array certificate'],
            }
        ]
    },
);
($certificate, $error) = xCAT_plugin::credentials::_request_x509_from_master(
    'compute-01', 'certificate request'
);
is( $certificate, 'array certificate',
    'delegated signer tolerates native array values' );
is( $xCAT::Client::host, '[2001:db8::10]:3001',
    'IPv6 management address is bracketed' );

reset_client();
@xCAT::Client::responses = (
    { error => ['Delegated certificate request denied'], errorcode => [1] }
);
($certificate, $error) = xCAT_plugin::credentials::_request_x509_from_master(
    'compute-01', 'certificate request'
);
is( $certificate, undef, 'management node rejection returns no certificate' );
like( $error, qr/Delegated certificate request denied\z/,
    'management node error is returned to the service node' );
like( $xCAT::MsgUtils::messages[-1]->[3],
    qr/Delegated certificate request denied\z/,
    'management node error is logged on the service node' );

reset_client();
$xCAT::Client::exception = "TLS handshake failed\n";
($certificate, $error) = xCAT_plugin::credentials::_request_x509_from_master(
    'compute-01', 'certificate request'
);
like( $error, qr/TLS handshake failed\z/,
    'client exception is preserved in the delegated error' );
like( $xCAT::MsgUtils::messages[-1]->[3], qr/TLS handshake failed\z/,
    'client exception is logged on the service node' );

reset_client();
$xCAT::Client::trigger_timeout = 1;
($certificate, $error) = xCAT_plugin::credentials::_request_x509_from_master(
    'compute-01', 'certificate request'
);
like( $error, qr/request timed out after 30 seconds\z/,
    'stalled management node request is bounded by a timeout' );

reset_client();
($certificate, $error) = xCAT_plugin::credentials::_request_x509_from_master(
    'compute-01', 'certificate request'
);
like( $error, qr/management node returned no certificate\z/,
    'empty management node response has a specific error' );

reset_client();
$xCAT::TableUtils::master = undef;
($certificate, $error) = xCAT_plugin::credentials::_request_x509_from_master(
    'compute-01', 'certificate request'
);
is( $error, 'The management node is not configured',
    'missing site.master has a specific error' );

$xCAT::Table::servicenode = 'service-a';
my @callback;
{
    no warnings 'redefine';
    local *xCAT_plugin::credentials::_sign_x509_certificate = sub {
        return 'signed certificate';
    };
    xCAT_plugin::credentials::process_request(
        {
            command          => ['signx509cert'],
            arg              => ['compute-01'],
            csr              => ['certificate request'],
            _xcat_authname   => ['root'],
            _xcat_clienthost => ['service-a'],
            _xcat_clientip   => ['192.0.2.21'],
        },
        sub { push @callback, shift; }
    );
}
is_deeply(
    \@callback,
    [
        {
            data => [
                {
                    content => ['signed certificate'],
                    desc    => ['x509cert'],
                }
            ]
        }
    ],
    'authorized delegated request returns only the signed certificate'
);

@callback = ();
xCAT_plugin::credentials::process_request(
    {
        command          => ['signx509cert'],
        arg              => ['compute-01'],
        csr              => ['certificate request'],
        _xcat_authname   => ['root'],
        _xcat_clienthost => ['service-c'],
        _xcat_clientip   => ['192.0.2.23'],
    },
    sub { push @callback, shift; }
);
is( $callback[0]->{errorcode}->[0], 1,
    'unauthorized delegated request returns an error' );

%xCAT::NodeRange::ranges = ( 'compute-01' => ['compute-01'] );
$xCAT::Utils::service_node = 1;
@callback = ();
{
    no warnings 'redefine';
    local *xCAT_plugin::credentials::ok_with_node = sub { return 1; };
    local *xCAT_plugin::credentials::_request_x509_from_master = sub {
        return ('delegated certificate', undef);
    };
    xCAT_plugin::credentials::process_request(
        {
            command          => ['getcredentials'],
            arg              => ['x509cert'],
            csr              => ['certificate request'],
            callback_port    => [123],
            _xcat_clienthost => ['compute-01'],
        },
        sub { push @callback, shift; }
    );
}
is( $callback[0]->{data}->[0]->{content}->[0], 'delegated certificate',
    'service-node getcredentials path returns the delegated certificate' );

@callback = ();
{
    no warnings 'redefine';
    local *xCAT_plugin::credentials::ok_with_node = sub { return 1; };
    local *xCAT_plugin::credentials::_request_x509_from_master = sub {
        return (undef, 'management node rejected the request');
    };
    xCAT_plugin::credentials::process_request(
        {
            command          => ['getcredentials'],
            arg              => ['x509cert'],
            csr              => ['certificate request'],
            callback_port    => [123],
            _xcat_clienthost => ['compute-01'],
        },
        sub { push @callback, shift; }
    );
}
is( $callback[0]->{error}->[0], 'management node rejected the request',
    'service-node getcredentials path returns the delegated error' );

SKIP: {
    my $openssl = 0;
    if (open(my $version, '-|', 'openssl', 'version')) {
        <$version>;
        $openssl = close($version);
    }
    skip 'openssl is not available', 3 unless $openssl;

    my $directory = tempdir(CLEANUP => 1);
    my $key = File::Spec->catfile($directory, 'test.key');
    open(my $saved_stderr, '>&', \*STDERR) or die "cannot save stderr";
    open(STDERR, '>', File::Spec->devnull()) or die "cannot redirect stderr";
    my $key_status = system('openssl', 'genrsa', '-out', $key, '2048');
    open(STDERR, '>&', $saved_stderr) or die "cannot restore stderr";
    close($saved_stderr);
    $key_status == 0 or die "cannot create test key";
    my @subjects = (
        [ valid    => '/CN=compute-01' ],
        [ multiple => '/CN=root/CN=compute-01' ],
        [ extra    => '/CN=compute-01/OU=cluster' ],
    );
    my %requests;
    foreach my $subject (@subjects) {
        my ($name, $distinguished_name) = @{$subject};
        my $request = File::Spec->catfile($directory, "$name.csr");
        system('openssl', 'req', '-new', '-key', $key,
            '-subj', $distinguished_name, '-out', $request) == 0
          or die "cannot create test CSR";
        $requests{$name} = $request;
    }

    ok( xCAT_plugin::credentials::_csr_subject_matches_node(
            $requests{valid}, 'compute-01'
        ),
        'single exact CN is accepted' );
    ok( !xCAT_plugin::credentials::_csr_subject_matches_node(
            $requests{multiple}, 'compute-01'
        ),
        'multiple CN values are rejected' );
    ok( !xCAT_plugin::credentials::_csr_subject_matches_node(
            $requests{extra}, 'compute-01'
        ),
        'additional subject attributes are rejected' );
}

done_testing();
