#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';

use FindBin;
BEGIN { $ENV{XCATROOT} = "$FindBin::Bin/../../xCAT-server"; }
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;
use xCAT::Postage;

my %addresses = (
    nodev4                    => { OnlyV4 => '192.0.2.20' },
    nodev6                    => { OnlyV6 => '2001:db8:1::20' },
    nodedual                  => { OnlyV4 => '192.0.2.30', OnlyV6 => '2001:db8:1::30' },
    'masterdual.example.test' => { OnlyV4 => '192.0.2.1', OnlyV6 => '2001:db8:1::1' },
);
my @facing_calls;

{
    no warnings 'redefine';
    local *xCAT::NetworkUtils::getipaddr = sub {
        my $host = shift;
        $host = shift if defined($host) && $host eq 'xCAT::NetworkUtils';
        my %options = @_;
        my $entry = $addresses{$host} || {};
        return $entry->{OnlyV6} if $options{OnlyV6};
        return $entry->{OnlyV4} if $options{OnlyV4};
        return $entry->{OnlyV4} || $entry->{OnlyV6};
    };
    local *xCAT::NetworkUtils::my_ip_facing = sub {
        my $node = pop @_;
        push @facing_calls, [$node, 4];
        return (0, '192.0.2.1');
    };
    local *xCAT::NetworkUtils::my_ip_facing_family = sub {
        my ($class, $node, $family) = @_;
        push @facing_calls, [$node, $family];
        return (0, '2001:db8:1::1');
    };

    is_deeply(
        [ xCAT::Postage::_facing_addresses_for_node('nodev6') ],
        [0, '2001:db8:1::1'],
        'IPv6-only postscript generation selects an IPv6-facing master'
    );
    is_deeply(
        [ xCAT::Postage::_facing_addresses_for_node('nodev4') ],
        [0, '192.0.2.1'],
        'IPv4 postscript generation retains the legacy facing-master path'
    );
    is(
        xCAT::Postage::_resolve_server_for_node(
            'nodev6', 'masterdual.example.test'
        ),
        '2001:db8:1::1',
        'IPv6-only mypostscript resolves a dual-stack master in the node family'
    );
    is(
        xCAT::Postage::_resolve_server_for_node(
            'nodedual', 'masterdual.example.test'
        ),
        '192.0.2.1',
        'dual-stack mypostscript preserves IPv4 preference'
    );
    is_deeply(
        \@facing_calls,
        [ [nodev6 => 6], [nodev4 => 4] ],
        'facing-master discovery records the expected family decisions'
    );
}

done_testing();
