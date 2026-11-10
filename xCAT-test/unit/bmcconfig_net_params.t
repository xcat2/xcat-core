#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
BEGIN { $ENV{XCATROOT} = "$FindBin::Bin/../../xCAT-server"; }
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use Socket qw(inet_aton);
use Test::More;
use xCAT::BMCUtils;

# bmc_net_params gives bmcconfig the values it sends to bmcsetup in Genesis.

my @nets = (
    { net => '198.51.100.0', mask => '255.255.255.0', gateway => '198.51.100.1' },
    { net => '2001:db8:2::/64', mask => undef, gateway => '2001:db8:2::1' },
    { net => '192.0.2.0',    mask => '255.255.255.0', gateway => '192.0.2.1' },
    { net => '2001:db8:1::', mask => '/64',           gateway => '2001:db8:1::1' },
);

my @facing;
my %mn = (4 => '192.0.2.254', 6 => '2001:db8:1::fe');
my %opt = (
    resolve4 => sub { return $_[0] =~ /:/ ? undef : inet_aton($_[0]); },
    resolve6 => sub { return; },
    facing   => sub { push @facing, [@_]; return $mn{ $_[1] }; },
);

sub params {
    my ($bmc, $nets, %extra) = @_;
    return [ xCAT::BMCUtils::bmc_net_params($bmc, $nets || \@nets, %opt, %extra) ];
}

is_deeply(params('192.0.2.20'), [ '192.0.2.20', '255.255.255.0', '192.0.2.1' ],
    'an IPv4 BMC gets the netmask and gateway of the network that contains it');

is_deeply(params('bmc4', undef, resolve4 => sub { return inet_aton('192.0.2.21') }),
    [ '192.0.2.21', '255.255.255.0', '192.0.2.1' ],
    'an IPv4 BMC name is sent as its address');

my @xcatmaster = map { { %$_, gateway => '<xcatmaster>' } } @nets;
@facing = ();
is_deeply(params('192.0.2.20', \@xcatmaster), [ '192.0.2.20', '255.255.255.0', '192.0.2.254' ],
    'an IPv4 <xcatmaster> gateway becomes the MN address on that network');
is_deeply(\@facing, [ [ '192.0.2.20', 4 ] ], 'the IPv4 MN address is looked up for the BMC');

is_deeply(params('192.0.2.20', \@xcatmaster, facing => sub { return; }),
    [ '192.0.2.20', '255.255.255.0', '<xcatmaster>' ],
    'an IPv4 <xcatmaster> gateway that does not resolve is kept, as before');

my $unresolved = params('no-such-bmc', undef, resolve4 => sub { return; });
is($unresolved->[0], undef, 'a BMC name that does not resolve gives no address');
like($unresolved->[1], qr/Unable to resolve no-such-bmc/, 'and says the name did not resolve');

my $no_net = params('203.0.113.5');
is($no_net->[0], undef, 'an IPv4 BMC outside every network gives no address');
like($no_net->[1], qr/no appropriate network for 203\.0\.113\.5/, 'and names the address');

is_deeply(params('2001:db8:1::20'),
    [ '2001:db8:1::20', 64, '2001:db8:1::1', '2001:db8:1::' ],
    'an IPv6 BMC gets the prefix length, the gateway and the prefix of its network');

is_deeply(params('2001:db8:2::20'),
    [ '2001:db8:2::20', 64, '2001:db8:2::1', '2001:db8:2::' ],
    'the prefix length can also come from networks.net');

is_deeply(params('bmc6', undef, resolve6 => sub { return $_[0] eq 'bmc6' ? '2001:db8:1::21' : undef }),
    [ '2001:db8:1::21', 64, '2001:db8:1::1', '2001:db8:1::' ],
    'a BMC name with only an IPv6 address is sent as that address');

is_deeply(params('bmc46', undef,
        resolve4 => sub { return inet_aton('192.0.2.22') },
        resolve6 => sub { return '2001:db8:1::22' }),
    [ '192.0.2.22', '255.255.255.0', '192.0.2.1' ],
    'a BMC name with both address families keeps IPv4');

@facing = ();
is_deeply(params('2001:db8:1::20', \@xcatmaster),
    [ '2001:db8:1::20', 64, '2001:db8:1::fe', '2001:db8:1::' ],
    'an IPv6 <xcatmaster> gateway becomes the MN address on that network');
is_deeply(\@facing, [ [ '2001:db8:1::20', 6 ] ], 'the IPv6 MN address is looked up for the BMC');

is_deeply(params('2001:db8:1::20', \@xcatmaster, facing => sub { return; }),
    [ '2001:db8:1::20', 64, undef, '2001:db8:1::' ],
    'an IPv6 <xcatmaster> gateway that does not resolve is dropped');

my $no_net6 = params('2001:db8:9::20');
is($no_net6->[0], undef, 'an IPv6 BMC outside every network gives no address');
like($no_net6->[1], qr/no appropriate network for 2001:db8:9::20/, 'and names the address');

done_testing();
