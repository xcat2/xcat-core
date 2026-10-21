#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Capture::Tiny qw(capture);
use JSON qw(decode_json encode_json);
use Storable qw(dclone);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $driver = repo_path('xCAT-test/unit/fixtures/dhcp/dispatch.pl');
my @cases = (
    {
        name          => 'named nodes reach only their DHCP service nodes',
        nodes         => [qw(node1 node2)],
        service_nodes => [qw(sn3 sn2 sn1)],
        noderes       => { node1 => { servicenode => 'sn1' }, node2 => { servicenode => 'sn2' } },
        destinations  => [ undef, qw(sn2 sn1) ],
        networks      => [ { net => '192.0.2.0', dynamicrange => '192.0.2.100-192.0.2.200', dhcpserver => 'sn1' } ],
    },
    {
        name         => 'one serving node excludes unrelated servers',
        nodes        => ['node2'],
        noderes      => { node2 => { servicenode => 'sn2', xcatmaster => 'sn1' } },
        destinations => [ undef, 'sn2' ],
    },
    {
        name         => 'service-node pools reach both serving DHCP nodes',
        nodes        => ['node1'],
        noderes      => { node1 => { servicenode => 'sn1,sn2' } },
        destinations => [ undef, qw(sn1 sn2) ],
    },
    {
        name         => 'nodes without resource rows fall back to the manager',
        nodes        => ['node1'],
        destinations => [undef],
    },
    {
        name         => 'manager mapping is not an empty mapping',
        nodes        => ['node1'],
        noderes      => { node1 => {} },
        destinations => [undef],
    },
    {
        name         => 'an unmapped node with no site master retains all-server fallback',
        nodes        => ['node1'],
        site_master  => '',
        destinations => [ undef, qw(sn1 sn2 sn3) ],
        messages     => [ [ 'SW', "site.master is not set!\n" ] ],
    },
    {
        name         => 'a mapping outside the DHCP inventory stays local',
        nodes        => ['node1'],
        noderes      => { node1 => { servicenode => 'sn4' } },
        destinations => [undef],
    },
    {
        name                 => 'preprocessed requests are returned without another fan-out',
        nodes                => ['node1'],
        preprocessed         => 1,
        incoming_destination => 'sn1',
        noderes              => { node1 => { servicenode => 'sn2' } },
        destinations         => [undef],
    },
    {
        name         => 'network regeneration reaches every DHCP server',
        args         => ['-n'],
        noderes      => { node1 => { servicenode => 'sn1' } },
        destinations => [ undef, qw(sn1 sn2 sn3) ],
    },
    {
        name         => 'network regeneration ignores a supplied noderange',
        args         => ['-n'],
        nodes        => ['node1'],
        output_nodes => [],
        noderes      => { node1 => { servicenode => 'sn1' } },
        destinations => [ undef, qw(sn1 sn2 sn3) ],
    },
    {
        name         => 'a service node is not sent its own single-node request',
        nodes        => ['sn1'],
        noderes      => { sn1 => { servicenode => 'sn1' } },
        destinations => [undef],
    },
    {
        name         => 'a service node in a multi-node request is not excluded',
        nodes        => [qw(sn1 node1)],
        noderes      => { sn1 => { servicenode => 'sn1' }, node1 => { servicenode => 'sn1' } },
        destinations => [ undef, 'sn1' ],
    },
    {
        name            => 'service-node origin reaches the manager and other serving nodes',
        nodes           => ['node1'],
        is_service_node => 1,
        local_names     => [qw(sn2 192.0.2.2)],
        service_nodes   => [qw(sn1 192.0.2.2 sn3)],
        noderes         => { node1 => { servicenode => 'sn1,192.0.2.2' } },
        destinations    => [ undef, qw(mn sn1) ],
    },
    {
        name         => 'a manager does not apply the service-node self guard',
        nodes        => ['node1'],
        local_names  => ['sn1'],
        noderes      => { node1 => { servicenode => 'sn1' } },
        destinations => [ undef, 'sn1' ],
    },
    {
        name          => 'without DHCP service nodes only the local request remains',
        nodes         => ['node1'],
        service_nodes => [],
        destinations  => [undef],
    },
    {
        name         => 'local-only mode suppresses remote dispatch',
        args         => ['-l'],
        nodes        => ['node1'],
        noderes      => { node1 => { servicenode => 'sn1' } },
        destinations => [undef],
    },
    {
        name            => 'a service node without a DHCP hierarchy stays local',
        nodes           => ['node1'],
        service_nodes   => [],
        is_service_node => 1,
        local_names     => ['sn1'],
        destinations    => [undef],
    },
    {
        name         => 'an incomplete hierarchical network prevents dispatch',
        nodes        => ['node1'],
        networks     => [ { net => '192.0.2.0', dynamicrange => '192.0.2.100-192.0.2.200' } ],
        destinations => [],
        errors       => [ { error => ['Hierarchy requested, therefore networks.dhcpserver must be set for net=192.0.2.0'], errorcode => [1] } ],
    },
);

for my $case (@cases) {
    subtest $case->{name} => sub {
        my $request = {
            command           => ['makedhcp'],
            arg               => $case->{args} || [],
            username          => ['operator'],
            _xcatpreprocessed => [ $case->{preprocessed} || 0 ],
            environment       => ['sentinel=value'],
        };
        $request->{node} = $case->{nodes} if exists $case->{nodes};
        $request->{_xcatdest} = $case->{incoming_destination} if exists $case->{incoming_destination};
        my @expected;
        for my $destination (@{ $case->{destinations} }) {
            my $outgoing = dclone($request);
            $outgoing->{node} = $case->{output_nodes} || $case->{nodes} || [];
            $outgoing->{_xcatpreprocessed} = [1];
            $outgoing->{_xcatdest} = $destination if defined $destination;
            push @expected, $outgoing;
        }
        my %fixture = (
            request         => $request,
            service_nodes   => $case->{service_nodes} || [qw(sn1 sn2 sn3)],
            noderes         => $case->{noderes} || {},
            local_names     => $case->{local_names} || ['mn'],
            is_service_node => $case->{is_service_node} || 0,
            site_master     => exists($case->{site_master}) ? $case->{site_master} : 'mn',
            networks        => $case->{networks} || [],
        );
        my ( $stdout, $stderr, $status ) = capture {
            system( $^X, $driver, encode_json(\%fixture) );
        };
        is( $status, 0, 'the plugin runs successfully' );
        is( $stderr, '', 'the plugin produces no stderr' );
        return if $status;
        my $result = eval { decode_json($stdout) };
        is( ref($result), 'HASH', 'the driver reports a result' );
        return unless ref($result) eq 'HASH';
        is_deeply( $result->{requests}, \@expected, 'destinations, order and request contents match' );
        is_deeply( $result->{errors}, $case->{errors} || [], 'callback errors match' );
        is_deeply( $result->{messages}, $case->{messages} || [], 'diagnostics match' );
    };
}

done_testing();
