use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Path qw/make_path/;
use File::Temp qw/tempdir/;
use Test::More;

use xCAT::DHCP::Backend::Kea;
use xCAT::Utils;

my $uses_shared_service_map = !xCAT::DHCP::Backend::Kea->can('_service_available');

sub write_unit {
    my ($path) = @_;

    open( my $fh, '>', $path ) or die "Unable to write $path: $!";
    close($fh);
}

my $fixture_root = tempdir( CLEANUP => 1 );
my $systemd_dir  = "$fixture_root/systemd";
my $sysv_dir     = "$fixture_root/init.d";
my $empty_dir    = "$fixture_root/empty";
my $extended_dir = "$fixture_root/extended";
make_path( $systemd_dir, $sysv_dir, $empty_dir, $extended_dir );

my %packaged_units = (
    'kea-dhcp4'      => 'kea-dhcp4-server',
    'kea-dhcp6'      => 'kea-dhcp6-server',
    'kea-dhcp-ddns'  => 'kea-dhcp-ddns-server',
    'kea-ctrl-agent' => 'kea-ctrl-agent',
);
foreach my $unit ( values %packaged_units ) {
    write_unit("$systemd_dir/$unit.service");
}

{
    no warnings 'redefine';

    my $systemd_backend = xCAT::DHCP::Backend::Kea->new(
        service_unit_dirs => [$systemd_dir],
        service_init_dirs => [$empty_dir],
    );
    foreach my $service ( sort keys %packaged_units ) {
        is(
            $systemd_backend->_kea_service($service),
            $packaged_units{$service},
            "$service resolves to its installed systemd unit",
        );
    }

    write_unit("$systemd_dir/kea-dhcp4.service");
    is(
        $systemd_backend->_kea_service('kea-dhcp4'),
        'kea-dhcp4',
        'the canonical systemd unit keeps candidate priority',
    );

    my $empty_backend = xCAT::DHCP::Backend::Kea->new(
        service_unit_dirs => [$empty_dir],
        service_init_dirs => [$empty_dir],
    );
    is(
        $empty_backend->_kea_service('custom-kea'),
        'custom-kea',
        'an unknown service keeps its requested name',
    );

    write_unit("$empty_dir/dhcp3-server.service");
    is(
        $empty_backend->_kea_service('dhcp'),
        'dhcp',
        'a non-Kea service is not resolved through the shared candidate table',
    );

    write_unit("$extended_dir/isc-kea-dhcp4-server.service");
    write_unit("$extended_dir/kea-ctrl-agent-server.service");
    my $extended_backend = xCAT::DHCP::Backend::Kea->new(
        service_unit_dirs => [$extended_dir],
        service_init_dirs => [$empty_dir],
    );
    is(
        $extended_backend->_kea_service('kea-dhcp4'),
        'kea-dhcp4',
        'the backend does not widen its established DHCP candidate subset',
    );
    is(
        $extended_backend->_kea_service('kea-ctrl-agent'),
        'kea-ctrl-agent',
        'the backend does not widen its established Control Agent candidate subset',
    );

    SKIP: {
        skip 'shared service-map filesystem search is not present before the refactor', 2
          unless $uses_shared_service_map;

        my $sysv_backend = xCAT::DHCP::Backend::Kea->new(
            service_unit_dirs => [$systemd_dir],
            service_init_dirs => [$sysv_dir],
        );
        unlink "$systemd_dir/kea-dhcp4.service";
        write_unit("$sysv_dir/kea-dhcp4");
        is(
            $sysv_backend->_kea_service('kea-dhcp4'),
            'kea-dhcp4-server',
            'a non-executable SysV script is ignored',
        );
        chmod 0755, "$sysv_dir/kea-dhcp4"
          or die "Unable to make the SysV fixture executable: $!";
        is(
            $sysv_backend->_kea_service('kea-dhcp4'),
            'kea-dhcp4',
            'an executable earlier SysV candidate wins over a later systemd candidate',
        );
        write_unit("$systemd_dir/kea-dhcp4.service");
    }

    if ($uses_shared_service_map) {
        my $search_spec;
        local *xCAT::Utils::servicemap = sub {
            ( undef, undef, $search_spec ) = @_;
            return;
        };

        is(
            xCAT::DHCP::Backend::Kea->new()->_kea_service('kea-dhcp4'),
            'kea-dhcp4',
            'an unresolved service keeps its requested name',
        );
        is_deeply(
            $search_spec->{searches},
            [
                {
                    paths => [
                        '/etc/systemd/system',
                        '/run/systemd/system',
                        '/usr/lib/systemd/system',
                        '/lib/systemd/system',
                    ],
                    suffix => '.service',
                },
                {
                    paths      => ['/etc/init.d'],
                    executable => 1,
                },
            ],
            'the default systemd and SysV search paths remain unchanged',
        );
    } else {
        is_deeply(
            xCAT::DHCP::Backend::Kea::_systemd_unit_dirs(),
            [
                '/etc/systemd/system',
                '/run/systemd/system',
                '/usr/lib/systemd/system',
                '/lib/systemd/system',
            ],
            'the default systemd search paths match before the refactor',
        );
    }

    my @systemd_calls;
    local *xCAT::Utils::enableservice = sub {
        my ( $class, $service ) = @_;
        push @systemd_calls, [ enable => $service ];
        return 0;
    };
    local *xCAT::Utils::checkservicestatus = sub {
        my ( $class, $service ) = @_;
        push @systemd_calls, [ status => $service ];
        return 0;
    };
    local *xCAT::Utils::runcmd = sub {
        my ( $class, $command, $output_mode ) = @_;
        push @systemd_calls, [ command => $command, $output_mode ];
        $::RUNCMD_RC = 0;
        return '';
    };
    local *xCAT::Utils::restartservice = sub {
        my ( $class, $service ) = @_;
        push @systemd_calls, [ restart => $service ];
        return 0;
    };

    my $restart = $systemd_backend->restart_services(
        ddns       => 1,
        ipv6       => 1,
        ctrl_agent => 1,
        enable     => 1,
    );
    is_deeply(
        $restart,
        {
            services => [
                'kea-dhcp-ddns-server',
                'kea-dhcp4',
                'kea-dhcp6-server',
                'kea-ctrl-agent',
            ],
        },
        'restart reports the resolved systemd units in lifecycle order',
    );
    is_deeply(
        \@systemd_calls,
        [
            [ enable  => 'kea-dhcp-ddns-server' ],
            [ status  => 'kea-dhcp-ddns-server' ],
            [ command => 'systemctl reload kea-dhcp-ddns-server', -1 ],
            [ enable  => 'kea-dhcp4' ],
            [ status  => 'kea-dhcp4' ],
            [ command => 'systemctl reload kea-dhcp4', -1 ],
            [ enable  => 'kea-dhcp6-server' ],
            [ status  => 'kea-dhcp6-server' ],
            [ command => 'systemctl reload kea-dhcp6-server', -1 ],
            [ enable  => 'kea-ctrl-agent' ],
            [ status  => 'kea-ctrl-agent' ],
            [ command => 'systemctl reload kea-ctrl-agent', -1 ],
        ],
        'systemd lifecycle calls preserve enable, status, and reload behavior',
    );

    {
        my @sysv_calls;
        local *xCAT::DHCP::Backend::Kea::_kea_service = sub { return 'kea-dhcp4-server'; };
        local *xCAT::Utils::checkservicestatus = sub {
            my ( $class, $service ) = @_;
            push @sysv_calls, [ status => $service ];
            return 0;
        };
        my $status = xCAT::DHCP::Backend::Kea->new()->check_services();
        is_deeply(
            $status,
            { services => ['kea-dhcp4-server'] },
            'service checks report a resolved SysV daemon name',
        );
        is_deeply(
            \@sysv_calls,
            [ [ status => 'kea-dhcp4-server' ] ],
            'service checks pass through a resolved SysV daemon name',
        );
    }

    {
        my @absent_calls;
        local *xCAT::DHCP::Backend::Kea::_kea_service = sub { return $_[1]; };
        local *xCAT::Utils::checkservicestatus = sub {
            my ( $class, $service ) = @_;
            push @absent_calls, [ status => $service ];
            return 1;
        };
        my $absent_status = xCAT::DHCP::Backend::Kea->new()->check_services();
        is_deeply(
            $absent_status,
            { error => 'kea-dhcp4 is not running. Please start the Kea DHCP service.' },
            'an absent unit preserves the canonical lifecycle error',
        );
        is_deeply(
            \@absent_calls,
            [ [ status => 'kea-dhcp4' ] ],
            'an absent unit is checked by its requested name',
        );
    }
}

done_testing();
