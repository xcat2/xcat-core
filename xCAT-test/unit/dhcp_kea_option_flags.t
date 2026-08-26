#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use JSON qw(decode_json);
use Test::More;

use xCAT::DHCP::Backend::Kea;

my $backend = xCAT::DHCP::Backend::Kea->new( kea_version => '2.4.1' );

sub option_flags {
    return {
        name          => 'domain-name',
        data          => 'example.test',
        'always-send' => 1,
        'csv-format'  => 0,
        'never-send'  => 0,
    };
}

sub assert_boolean_flags {
    my ( $option, $scope ) = @_;

    foreach my $flag (qw/always-send csv-format never-send/) {
        is(
            ref( $option->{$flag} ),
            'JSON::PP::Boolean',
            "$scope renders $flag as a JSON boolean",
        );
    }
    ok( $option->{'always-send'}, "$scope preserves a true flag" );
    ok( !$option->{'csv-format'}, "$scope preserves a false flag" );
    ok( !$option->{'never-send'}, "$scope preserves a second false flag" );
}

my $dhcp4 = decode_json(
    $backend->render_dhcp4_config(
        {
            'option-data' => [ option_flags() ],
            subnet4       => [
                {
                    id            => 1,
                    subnet        => '192.0.2.0/24',
                    'option-data' => [ option_flags() ],
                    reservations  => [
                        {
                            'hw-address' => '00:11:22:33:44:55',
                            'ip-address' => '192.0.2.10',
                            'option-data' => [ option_flags() ],
                        },
                    ],
                    pools => [
                        {
                            pool          => '192.0.2.100 - 192.0.2.110',
                            'option-data' => [ option_flags() ],
                        },
                    ],
                },
            ],
        }
    )
)->{Dhcp4};

assert_boolean_flags( $dhcp4->{'option-data'}[0], 'DHCPv4 global option-data' );
assert_boolean_flags( $dhcp4->{subnet4}[0]{'option-data'}[0], 'DHCPv4 subnet option-data' );
assert_boolean_flags( $dhcp4->{subnet4}[0]{reservations}[0]{'option-data'}[0],
    'DHCPv4 reservation option-data' );
assert_boolean_flags( $dhcp4->{subnet4}[0]{pools}[0]{'option-data'}[0],
    'DHCPv4 pool option-data' );

my $dhcp6 = decode_json(
    $backend->render_dhcp6_config(
        {
            'option-data' => [ option_flags() ],
            subnet6       => [
                {
                    id            => 2,
                    subnet        => '2001:db8::/64',
                    'option-data' => [ option_flags() ],
                    reservations  => [
                        {
                            duid           => '00:01:00:01:de:ad:be:ef',
                            'ip-addresses' => ['2001:db8::10'],
                            'option-data'  => [ option_flags() ],
                        },
                    ],
                    pools => [
                        {
                            pool          => '2001:db8::100 - 2001:db8::110',
                            'option-data' => [ option_flags() ],
                        },
                    ],
                },
            ],
        }
    )
)->{Dhcp6};

assert_boolean_flags( $dhcp6->{'option-data'}[0], 'DHCPv6 global option-data' );
assert_boolean_flags( $dhcp6->{subnet6}[0]{'option-data'}[0], 'DHCPv6 subnet option-data' );
assert_boolean_flags( $dhcp6->{subnet6}[0]{reservations}[0]{'option-data'}[0],
    'DHCPv6 reservation option-data' );
assert_boolean_flags( $dhcp6->{subnet6}[0]{pools}[0]{'option-data'}[0],
    'DHCPv6 pool option-data' );

my @control_agent_payloads;
my $live_backend = xCAT::DHCP::Backend::Kea->new(
    kea_version => '2.4.1',
    control_agent_handler => sub {
        my ($payload) = @_;
        push @control_agent_payloads, $payload;
        return { ok => 1 };
    },
);
is_deeply(
    $live_backend->live_upsert_reservations(
        [
            {
                'hw-address' => '00:11:22:33:44:55',
                'ip-address' => '192.0.2.10',
                'option-data' => [ option_flags() ],
            },
        ],
    ),
    { ok => 1 },
    'live reservation update succeeds',
);
is( $control_agent_payloads[0]{command}, 'reservation-add',
    'live reservation update reaches the Kea add command' );
assert_boolean_flags(
    $control_agent_payloads[0]{arguments}{reservation}{'option-data'}[0],
    'live reservation option-data',
);

done_testing();
