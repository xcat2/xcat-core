#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

my $repo_root = $ENV{XCAT_REPO_ROOT}
  || File::Spec->catdir( $FindBin::Bin, '..', '..' );
unshift @INC, File::Spec->catdir( $repo_root, 'perl-xCAT' );
require xCAT::NetworkUtils;

subtest 'isIpv4addr accepts host addresses' => sub {
    my @accepted = qw(10.0.0.1 192.168.0.1 172.16.254.10 255.255.255.255);
    foreach my $address (@accepted) {
        ok( xCAT::NetworkUtils->isIpv4addr($address), "$address is accepted" );
    }
    ok( xCAT::NetworkUtils::isIpv4addr('10.0.0.1'),
        'the function form works without a class argument' );
    ok( xCAT::NetworkUtils->isIpaddr('10.0.0.1'),
        'the deprecated isIpaddr alias still answers' );
    ok( !xCAT::NetworkUtils->isIpaddr('fe80::1'),
        'the alias keeps the strict IPv4 contract' );
};

subtest 'isIpv4addr rejects invalid or ambiguous forms' => sub {
    my @rejected = (
        [ '192.168.001.010',  'leading-zero octets are octal to some resolvers' ],
        [ '0.1.2.3',          'a host address cannot start with zero' ],
        [ '0.0.0.0',          'all-zero is a call-site policy, not a host address' ],
        [ '256.1.1.1',        'octet above 255' ],
        [ '1.2.3',            'three-part form' ],
        [ '1.2.3.4.5',        'five-part form' ],
        [ 'fe80::1',          'IPv6 is outside the IPv4 contract' ],
        [ 'bmc.example.test', 'hostnames are not addresses' ],
        [ '',                 'empty value' ],
    );
    foreach my $case (@rejected) {
        my ( $value, $reason ) = @{$case};
        ok( !xCAT::NetworkUtils->isIpv4addr($value), "'$value' is rejected: $reason" );
    }
    ok( !xCAT::NetworkUtils->isIpv4addr(undef), 'undef is rejected' );
};

subtest 'isIpv6addr validates IPv6 syntax' => sub {
    my @accepted = ( 'fe80::1', '::1', '::', '2001:db8::1', '::ffff:10.1.1.1' );
    foreach my $address (@accepted) {
        ok( xCAT::NetworkUtils->isIpv6addr($address), "$address is accepted" );
    }
    my @rejected = (
        [ 'not:an:ip',    'colon text is not an address' ],
        [ ':::::',        'malformed compression' ],
        [ 'fe80::zzzz',   'invalid hex digits' ],
        [ 'fe80::1%eth0', 'zone identifiers are platform-dependent and rejected' ],
        [ '10.0.0.1',     'IPv4 is outside the IPv6 contract' ],
        [ '',             'empty value' ],
    );
    foreach my $case (@rejected) {
        my ( $value, $reason ) = @{$case};
        ok( !xCAT::NetworkUtils->isIpv6addr($value), "'$value' is rejected: $reason" );
    }
    ok( !xCAT::NetworkUtils->isIpv6addr(undef), 'undef is rejected' );
    ok( xCAT::NetworkUtils::isIpv6addr('::1'),
        'the function form works without a class argument' );
};

sub socket6_fallback_ok {
    ok( !defined &Socket::inet_pton, 'core inet_pton is absent' );
    ok( xCAT::NetworkUtils->isIpv6addr('2001:db8::1'),
        'a valid IPv6 address is accepted through Socket6' );
    ok( !xCAT::NetworkUtils->isIpv6addr('fe80::zzzz'),
        'an invalid IPv6 address is still rejected through Socket6' );
    return;
}

subtest 'isIpv6addr falls back to Socket6 without core inet_pton' => sub {
    no warnings qw(once redefine);
    if ( defined &Socket6::inet_pton ) {
        local *Socket::inet_pton;
        socket6_fallback_ok();
        return;
    }
    plan skip_all => 'neither core inet_pton nor Socket6 is available'
      unless defined &Socket::inet_pton;

    # lend the core implementation to Socket6 so the fallback path runs
    # where Socket6 is not installed
    my $core_pton = \&Socket::inet_pton;
    my $af6       = Socket::AF_INET6();
    local *Socket6::inet_pton = sub { return $core_pton->(@_) };
    local *Socket6::AF_INET6  = sub { return $af6 };
    local *Socket::inet_pton;
    socket6_fallback_ok();
};

subtest 'isValidIp accepts both families and nothing else' => sub {
    ok( xCAT::NetworkUtils->isValidIp('10.0.0.1'), 'IPv4 delegates to isIpv4addr' );
    ok( xCAT::NetworkUtils->isValidIp('fe80::1'),  'IPv6 delegates to isIpv6addr' );
    my @rejected = (
        'not:an:ip', 'fe80::1%eth0', '192.168.001.010', '0.0.0.0',
        'bmc.example.test', '',
    );
    foreach my $value (@rejected) {
        ok( !xCAT::NetworkUtils->isValidIp($value), "'$value' is rejected" );
    }
    ok( !xCAT::NetworkUtils->isValidIp(undef), 'undef is rejected' );
    ok( xCAT::NetworkUtils::isValidIp('10.0.0.1'),
        'the function form works without a class argument' );
};

done_testing();
