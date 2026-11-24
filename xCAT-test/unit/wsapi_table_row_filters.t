#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../perl-xCAT";
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);
use xCAT::Table;

local $ENV{XCATCFG} = tempdir(CLEANUP => 1);
require(repo_path('xCAT-server/lib/xcat/plugins/tabutils.pm'));

my $networks = xCAT::Table->new('networks', -create => 1);
$networks->setAttribs({ netname => 'lab-a' }, { net => '10.0.0.0', mask => '255.0.0.0' });
$networks->setAttribs({ netname => 'lab-b' }, { net => '11.0.0.0', mask => '255.0.0.0' });
$networks->setAttribs({ netname => 'lab-c' }, { net => '12.0.0.0', mask => '255.255.0.0' });

sub daemon_responses {
    my ($request) = @_;
    my @responses;
    xCAT_plugin::tabutils::process_request($request, sub { push @responses, shift });
    return \@responses;
}

sub read_networks {
    my ($filters, @columns) = @_;
    return daemon_responses({
        command   => ['getAttribs'],
        table     => ['networks'],
        rowformat => ['rows'],
        keys      => [$filters],
        attr      => \@columns,
    })->[0];
}

my $matching = read_networks({ mask => ['255.0.0.0'] }, 'netname');
is_deeply($matching->{table}->[0]->{tablename}, ['networks'], 'filtered response uses the table envelope');
is_deeply(
    [sort { $a->{netname} cmp $b->{netname} } @{ $matching->{table}->[0]->{row} }],
    [{ netname => 'lab-a' }, { netname => 'lab-b' }],
    'all matching rows are returned with just the projected column',
);

my $single = read_networks({ netname => ['lab-c'] }, 'ALL');
is_deeply(
    $single->{table}->[0]->{row},
    [{ netname => 'lab-c', net => '12.0.0.0', mask => '255.255.0.0' }],
    'one match still uses a row array and ALL includes its populated columns',
);

is_deeply(
    read_networks({ netname => ['unknown'] }, 'netname'),
    { errorcode => 1, error => 'No table rows matched specified keys or attributes' },
    'a valid filter with no match retains the existing error',
);
is_deeply(
    read_networks({ masks => ['255.0.0.0'] }, 'ALL'),
    { errorcode => 1, error => 'No such column in table networks: masks' },
    'an unknown filter column gets a specific error',
);
is_deeply(
    read_networks({ mask => ['255.0.0.0'] }, 'masks'),
    { errorcode => 1, error => 'No such column in table networks: masks' },
    'an unknown projected column gets a specific error',
);

my $legacy = daemon_responses({
    command => ['getAttribs'],
    table   => ['networks'],
    keys    => [{ mask => ['255.0.0.0'] }],
    attr    => ['netname'],
});
is_deeply([keys %{ $legacy->[0] }], ['netname'], 'a legacy XML request receives a flat response');
is(scalar @{ $legacy->[0]->{netname} }, 1, 'a legacy XML request still returns a single row');

is_deeply(
    daemon_responses({
        command => ['delEntries'],
        table   => [{ name => ['networks'], attr => [{ masks => ['255.0.0.0'] }] }],
    }),
    [{ errorcode => 1, error => 'No such column in table networks: masks' }],
    'an unknown delete filter is rejected before deletion',
);
is(scalar $networks->getAllAttribs('netname'), 3, 'the invalid delete leaves all rows intact');

is_deeply(
    daemon_responses({
        command => ['delEntries'],
        table   => [{ name => ['networks'], attr => [{ mask => ['255.0.0.0'] }] }],
    }),
    [],
    'a valid delete retains the successful empty response',
);
is_deeply(
    [$networks->getAllAttribs('netname')],
    [{ netname => 'lab-c' }],
    'a valid delete removes only the matching rows',
);

done_testing();
