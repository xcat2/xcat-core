#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';

use FindBin;
BEGIN { $ENV{XCATROOT} = "$FindBin::Bin/../../xCAT-server"; }
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;
use xCAT::InstUtils;

{
    package InstUtilsNodeResTable;
    sub new { return bless {}, shift; }
    sub getNodesAttribs {
        my ($self, $nodes) = @_;
        return {
            v6fallback => [ {} ],
            v6explicit => [ { xcatmaster => 'masterdual.example.test' } ],
            v6explicitbad => [ { xcatmaster => 'master4only.example.test' } ],
            v6facingbad => [ {} ],
            v4fallback => [ {} ],
        };
    }
    sub close { return; }
}

my %addresses = (
    v6fallback               => { OnlyV6 => '2001:db8:1::20' },
    v6explicit               => { OnlyV6 => '2001:db8:1::21' },
    v6explicitbad            => { OnlyV6 => '2001:db8:1::22' },
    v6facingbad              => { OnlyV6 => '2001:db8:1::23' },
    v4fallback               => { OnlyV4 => '192.0.2.20' },
    'masterdual.example.test' => {
        OnlyV4 => '192.0.2.1',
        OnlyV6 => '2001:db8:1::1',
    },
    'master4only.example.test' => { OnlyV4 => '192.0.2.2' },
);
my @facing_calls;

{
    no warnings 'redefine';
    local *xCAT::Table::new = sub { return InstUtilsNodeResTable->new(); };
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
        return (1, 'no IPv6-facing server') if $node eq 'v6facingbad';
        return (0, '2001:db8:1::1');
    };

    my $servers = xCAT::InstUtils->get_server_nodes(
        sub { }, [qw(v6fallback v6explicit v6explicitbad v6facingbad v4fallback)]
    );
    is_deeply(
        $servers->{'2001:db8:1::1'},
        [qw(v6fallback v6explicit)],
        'IPv6-only nodes select an IPv6-facing or explicitly configured master'
    );
    is_deeply(
        $servers->{'192.0.2.1'},
        [qw(v4fallback)],
        'IPv4 nodes retain the legacy IPv4-facing master'
    );
    is_deeply(
        $servers->{''},
        [qw(v6explicitbad v6facingbad)],
        'unresolved explicit and facing masters remain in the caller error bucket'
    );
    is_deeply(
        \@facing_calls,
        [ [v6fallback => 6], [v6facingbad => 6], [v4fallback => 4] ],
        'fallback master discovery follows each node address family'
    );
}

done_testing();
