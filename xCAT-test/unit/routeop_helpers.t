#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempfile);
use FindBin;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $routeop = File::Spec->catfile( $repo_root, 'xCAT', 'postscripts', 'routeop' );
my $xcatlib = File::Spec->catfile( $repo_root, 'xCAT', 'postscripts', 'xcatlib.sh' );

open( my $routeop_fh, '<', $routeop ) or die "Unable to read $routeop: $!";
my $routeop_source = do { local $/; <$routeop_fh> };
close($routeop_fh);

my ($definitions) =
  $routeop_source =~ /\A(.*?)(?=^if \[ "\$op" = "add" \]; then)/ms;
BAIL_OUT('Unable to extract routeop function definitions') unless $definitions;

my ( $runner_fh, $runner ) = tempfile( UNLINK => 1 );
print {$runner_fh} $definitions;
print {$runner_fh} <<'BASH';

case "$ROUTE_TEST_ACTION" in
    classify)
        if is_ipv6_route "$ROUTE_TEST_NET"; then
            printf '%s\n' ipv6
        else
            printf '%s\n' ipv4
        fi
        ;;
    prefix)
        source "$ROUTE_TEST_XCATLIB"
        ipv4_route_prefix "$ROUTE_TEST_MASK"
        ;;
    route_exists)
        source "$ROUTE_TEST_XCATLIB"
        uname()
        {
            printf '%s\n' Linux
        }
        ip()
        {
            printf '%s\n' "$*" > "$ROUTE_TEST_LOG"
            case "$ROUTE_TEST_SCENARIO" in
                ipv4-network)
                    printf '%s\n' '192.0.2.0/24 via 192.0.2.1 dev eth0 proto static'
                    ;;
                ipv4-host)
                    printf '%s\n' '192.0.2.44 via 192.0.2.1 dev eth0 proto static'
                    ;;
                ipv4-default)
                    printf '%s\n' 'default via 192.0.2.1 dev eth0 proto static'
                    ;;
                ipv6-network)
                    printf '%s\n' '2001:db8::/64 via fe80::1 dev eth0 proto static'
                    ;;
                empty)
                    ;;
                *)
                    exit 2
                    ;;
            esac
        }

        if [ "$ROUTE_TEST_GLOBAL_IFNAME" = 1 ]; then
            ifname=$ROUTE_TEST_IFNAME
            route_exists "$ROUTE_TEST_NET" "$ROUTE_TEST_MASK" "$ROUTE_TEST_GW"
        else
            route_exists "$ROUTE_TEST_NET" "$ROUTE_TEST_MASK" "$ROUTE_TEST_GW" "$ROUTE_TEST_IFNAME"
        fi
        ;;
    *)
        exit 2
        ;;
esac
BASH
close($runner_fh);

sub run_routeop_helper {
    my (%environment) = @_;
    local %ENV = ( %ENV, %environment, ROUTE_TEST_XCATLIB => $xcatlib );

    open(
        my $fh,
        '-|',
        'bash',
        '--noprofile',
        '--norc',
        $runner,
        'noop',
        '192.0.2.0',
        '24',
        '0.0.0.0',
        'eth0'
    ) or die "Unable to run routeop helper: $!";

    my $output = do { local $/; <$fh> };
    close($fh);
    my $status = $? >> 8;
    chomp $output;

    return ( $status, $output );
}

my @classification_cases = (
    [ '192.0.2.44',        'ipv4', 'IPv4 host route' ],
    [ '198.51.100.0',      'ipv4', 'IPv4 network route' ],
    [ 'default',           'ipv4', 'default route' ],
    [ '2001:db8::44',      'ipv6', 'IPv6 host route' ],
    [ '2001:db8::',        'ipv6', 'IPv6 network route' ],
    [ '::1',               'ipv6', 'compressed IPv6 route' ],
    [ '::ffff:192.0.2.44', 'ipv6', 'IPv4-mapped IPv6 route' ],
);

foreach my $case (@classification_cases) {
    my ( $status, $family ) = run_routeop_helper(
        ROUTE_TEST_ACTION => 'classify',
        ROUTE_TEST_NET    => $case->[0],
    );
    is( $status, 0, "$case->[2] classification succeeds" );
    is( $family, $case->[1], "$case->[2] keeps delimiter classification" );
}

my @prefix_cases = (
    [ '0',             '0',  'zero prefix' ],
    [ '24',            '24', 'numeric prefix' ],
    [ '255.255.255.0', '24', 'dotted class C mask' ],
    [ '255.255.0.0',   '16', 'dotted class B mask' ],
);

foreach my $case (@prefix_cases) {
    my ( $status, $prefix ) = run_routeop_helper(
        ROUTE_TEST_ACTION => 'prefix',
        ROUTE_TEST_MASK   => $case->[0],
    );
    is( $status, 0, "$case->[2] conversion succeeds" );
    is( $prefix, $case->[1], "$case->[2] keeps its route prefix" );
}

sub route_exists_case {
    my (%case) = @_;
    my ( $log_fh, $log ) = tempfile( UNLINK => 1 );
    close($log_fh);

    my ( $status, $exists ) = run_routeop_helper(
        ROUTE_TEST_ACTION        => 'route_exists',
        ROUTE_TEST_SCENARIO      => $case{scenario},
        ROUTE_TEST_NET           => $case{net},
        ROUTE_TEST_MASK          => $case{mask},
        ROUTE_TEST_GW            => $case{gateway},
        ROUTE_TEST_IFNAME        => $case{ifname},
        ROUTE_TEST_GLOBAL_IFNAME => $case{global_ifname} // 0,
        ROUTE_TEST_LOG           => $log,
    );

    open( my $log_read, '<', $log ) or die "Unable to read route query log: $!";
    my $query = do { local $/; <$log_read> };
    close($log_read);
    chomp $query;

    is( $status, 0, "$case{name} check succeeds" );
    is( $exists, $case{exists}, "$case{name} existence result" );
    is( $query, $case{query}, "$case{name} route query" );
}

my @route_exists_cases = (
    # name, scenario, net, mask, gateway, interface, global interface, exists, query
    [ 'IPv4 network route', 'ipv4-network', '192.0.2.0', '24', '192.0.2.1', 'eth0', 0, '1', 'route show 192.0.2.0/24' ],
    [ 'IPv4 dotted-mask route', 'ipv4-network', '192.0.2.0', '255.255.255.0', '192.0.2.1', 'eth0', 0, '1', 'route show 192.0.2.0/24' ],
    [ 'IPv4 host route', 'ipv4-host', '192.0.2.44', '32', '192.0.2.1', 'eth0', 0, '1', 'route show 192.0.2.44/32' ],
    [ 'IPv4 route using the global interface', 'ipv4-network', '192.0.2.0', '24', '192.0.2.1', 'eth0', 1, '1', 'route show 192.0.2.0/24' ],
    [ 'IPv4 route with a different gateway', 'ipv4-network', '192.0.2.0', '24', '192.0.2.254', 'eth0', 0, '0', 'route show 192.0.2.0/24' ],
    [ 'IPv4 route with a different interface', 'ipv4-network', '192.0.2.0', '24', '192.0.2.1', 'eth1', 0, '0', 'route show 192.0.2.0/24' ],
    [ 'IPv4 default route', 'ipv4-default', 'default', '0', '192.0.2.1', 'eth0', 0, '1', 'route show default' ],
    [ 'IPv6 network route', 'ipv6-network', '2001:db8::', '64', 'fe80::1', 'eth0', 0, '1', '-6 route show 2001:db8::/64' ],
    [ 'IPv6 device route', 'ipv6-network', '2001:db8::', '64', '', 'eth0', 0, '1', '-6 route show 2001:db8::/64' ],
    [ 'missing IPv6 network route', 'empty', '2001:db8::', '64', 'fe80::1', 'eth0', 0, '0', '-6 route show 2001:db8::/64' ],
);

foreach my $case (@route_exists_cases) {
    route_exists_case(
        name          => $case->[0],
        scenario      => $case->[1],
        net           => $case->[2],
        mask          => $case->[3],
        gateway       => $case->[4],
        ifname        => $case->[5],
        global_ifname => $case->[6],
        exists        => $case->[7],
        query         => $case->[8],
    );
}

done_testing();
