#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

my $repo_root = $ENV{XCAT_REPO_ROOT}
  || File::Spec->catdir( $FindBin::Bin, '..', '..' );
unshift @INC, File::Spec->catdir( $repo_root, 'perl-xCAT' );

# parse_args never opens the database, so keep the table layer and the
# driver out of the test
BEGIN {
    package xCAT::Table;
    sub import { }
    sub new { return bless {}, shift; }
    $INC{'xCAT/Table.pm'} = 1;
    $INC{'DBI.pm'}        = 1;
}

require xCAT::PPCmac;

# xcatd loads the usage table before it dispatches a plugin
require xCAT::Usage;

# both endpoints resolve through the networks table; one subnet is enough
# to reach the address checks
no warnings qw(once redefine);
local *xCAT::DBobjUtils::getNetwkInfo = sub {
    my ( $class, $endpoints ) = @_;
    return map { $_ => { net => '192.0.2.0', gateway => '192.0.2.1' } }
      @{$endpoints};
};

sub parse {
    my (@args) = @_;
    my $request = { command => 'getmacs', node => ['lpar1'], arg => \@args };
    return xCAT::PPCmac::parse_args($request);
}

sub rejection {
    my ($result) = @_;
    return ref($result) eq 'ARRAY' ? $result->[0] : undef;
}

subtest 'valid addresses reach the ping options' => sub {
    my $result = parse(qw(-D -S 192.0.2.10 -G 192.0.2.1 -C 192.0.2.20));
    is( ref $result, 'HASH', 'IPv4 endpoints are accepted' );
    is_deeply(
        [ @{$result}{qw(C G S)} ],
        [qw(192.0.2.20 192.0.2.1 192.0.2.10)],
        'the addresses are kept as given'
    );
    $result = parse(qw(-D -S 2001:db8::10 -G 2001:db8::1 -C 2001:db8::20));
    is( ref $result, 'HASH', 'IPv6 endpoints are accepted' );
};

subtest 'only the gateway may be all zeros' => sub {
    my $result = parse(qw(-D -S 192.0.2.10 -G 0.0.0.0 -C 192.0.2.20));
    is( ref $result, 'HASH', 'an all-zero gateway is accepted' );
    is( $result->{G}, '0.0.0.0', 'the gateway is passed through' );

    is( rejection( parse(qw(-D -S 0.0.0.0 -G 192.0.2.1 -C 192.0.2.20)) ),
        'Invalid IP address: 0.0.0.0', 'an all-zero server is rejected' );
    is( rejection( parse(qw(-D -S 0.0.0.0 -G 0.0.0.0 -C 192.0.2.20)) ),
        'Invalid IP address: 0.0.0.0',
        'an all-zero server is rejected even when the gateway is all zeros' );
    is( rejection( parse(qw(-D -S 192.0.2.10 -G 0.0.0.0 -C 0.0.0.0)) ),
        'Invalid IP address: 0.0.0.0',
        'an all-zero client is rejected even when the gateway is all zeros' );
};

subtest 'malformed addresses are rejected' => sub {
    is( rejection( parse(qw(-D -S 192.0.2.10 -G 192.0.2.1 -C 192.168.001.010)) ),
        'Invalid IP address: 192.168.001.010',
        'leading-zero octets are rejected' );
    is( rejection( parse(qw(-D -S 192.0.2.10 -G 192.0.2.1 -C 999.1.1.1)) ),
        'Invalid IP address: 999.1.1.1', 'an octet above 255 is rejected' );
    is( rejection( parse(qw(-D -S not:an:ip -G 192.0.2.1 -C 192.0.2.20)) ),
        'Invalid IP address: not:an:ip', 'colon text is not an address' );
};

done_testing();
