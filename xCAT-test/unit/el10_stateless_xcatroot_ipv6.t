#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir tempfile);
use FindBin;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $xcatroot = File::Spec->catfile(
    $repo_root,
    'xCAT-server/share/xcat/netboot/rh/dracut_105/stateless/xcatroot'
);

open( my $source_fh, '<', $xcatroot ) or die "Unable to read $xcatroot: $!";
my $source = do { local $/; <$source_fh> };
close($source_fh);

is( system( 'bash', '-n', $xcatroot ), 0, 'EL10 stateless xcatroot passes bash syntax validation' );

my ($helpers) = $source =~ m{\A\#!/bin/bash\n(.*?)^log_label=}ms;
ok( defined($helpers), 'test harness extracts the production helper functions' );

my ( $helper_fh, $helper_path ) = tempfile( SUFFIX => '.sh', UNLINK => 1 );
print {$helper_fh} <<'HEADER';
#!/bin/bash
set -u
ip() {
    case "$*" in
        "-6 -o addr show dev eth1 scope global")
            echo "3: eth1 inet6 2001:db8:2::21/64 scope global"
            ;;
        "-6 route show default dev eth1")
            echo "default via fe80::1 dev eth1 metric 1024"
            ;;
        *)
            return 1
            ;;
    esac
}
HEADER
print {$helper_fh} $helpers;
print {$helper_fh} <<'DISPATCH';
case "$1" in
    endpoint)
        shift
        xcat_endpoint_host "$@"
        ;;
    is-ipv6)
        shift
        xcat_is_ipv6_boot "$@"
        ;;
    persist)
        shift
        persist_ipv6_nm_connection "$@"
        ;;
    *)
        exit 64
        ;;
esac
DISPATCH
close($helper_fh);

sub run_helper {
    my @args = @_;
    open( my $fh, '-|', 'bash', $helper_path, @args )
      or die "Unable to run helper harness: $!";
    my $output = do { local $/; <$fh> };
    close($fh);
    return ( $output // '', $? >> 8 );
}

my @endpoint_cases = (
    [ '192.0.2.10:3001',       '192.0.2.10',       'IPv4 endpoint keeps the legacy host value' ],
    [ 'head.example.test:3001', 'head.example.test', 'hostname endpoint keeps the legacy host value' ],
    [ '[2001:db8::10]:3001',    '2001:db8::10',     'bracketed IPv6 endpoint yields the raw server address' ],
    [ '[2001:db8::10]',         '2001:db8::10',     'bracketed IPv6 host without a port is accepted' ],
    [ '2001:db8::10',           '2001:db8::10',     'unbracketed IPv6 host is not truncated at a colon' ],
);

foreach my $case (@endpoint_cases) {
    my ( $output, $rc ) = run_helper( 'endpoint', $case->[0] );
    is( $rc, 0, "$case->[2] succeeds" );
    chomp($output);
    is( $output, $case->[1], $case->[2] );
}

for my $iparg ( 'dhcp6', 'eth0:dhcp6', 'eth0:dhcp6:1500' ) {
    my ( undef, $rc ) = run_helper( 'is-ipv6', $iparg, 'eth0' );
    is( $rc, 0, "ip=$iparg is recognized as an IPv6 boot" );
}
my ( undef, $ipv4_rc ) = run_helper( 'is-ipv6', 'dhcp', '' );
isnt( $ipv4_rc, 0, 'the legacy ip=dhcp argument is not treated as IPv6' );

my $tmpdir = tempdir( CLEANUP => 1 );
my $runtime_connections = File::Spec->catdir( $tmpdir, 'runtime-connections' );
my $copied_root = File::Spec->catdir( $tmpdir, 'copied-root' );
make_path($runtime_connections);
my $runtime_profile = File::Spec->catfile( $runtime_connections, 'initrd.nmconnection' );
open( my $profile_fh, '>', $runtime_profile ) or die "Unable to write $runtime_profile: $!";
print {$profile_fh} "[connection]\nid=initrd\n[ipv6]\nmethod=dhcp\n";
close($profile_fh);

my ( undef, $copy_rc ) = run_helper(
    'persist', $copied_root, 'eth0', '02:00:00:00:00:10', $runtime_connections
);
is( $copy_rc, 0, 'runtime NetworkManager profile persistence succeeds' );
my $copied_profile = File::Spec->catfile(
    $copied_root, 'etc', 'NetworkManager', 'system-connections', 'initrd.nmconnection'
);
ok( -f $copied_profile, 'the initrd NetworkManager profile is copied into the stateless root' );
is(
    ( stat($copied_profile) )[2] & oct('07777'),
    oct('0600'),
    'the persisted NetworkManager profile has private permissions'
);

my $fallback_root = File::Spec->catdir( $tmpdir, 'fallback-root' );
my $empty_source = File::Spec->catdir( $tmpdir, 'empty-connections' );
make_path($empty_source);
my ( undef, $fallback_rc ) = run_helper(
    'persist', $fallback_root, 'eth1', '02:00:00:00:00:11', $empty_source
);
is( $fallback_rc, 0, 'IPv6 NetworkManager fallback profile generation succeeds' );
my $fallback_profile = File::Spec->catfile(
    $fallback_root, 'etc', 'NetworkManager', 'system-connections', 'xcat-eth1.nmconnection'
);
open( my $fallback_fh, '<', $fallback_profile ) or die "Unable to read $fallback_profile: $!";
my $fallback = do { local $/; <$fallback_fh> };
close($fallback_fh);
like( $fallback, qr/^interface-name=eth1$/m, 'fallback profile binds to the boot interface' );
like( $fallback, qr/^mac-address=02:00:00:00:00:11$/m, 'fallback profile binds to the boot MAC' );
like( $fallback, qr/^\[ipv4\]\nmethod=disabled$/m, 'fallback profile does not enable IPv4' );
like( $fallback, qr/^\[ipv6\]\nmethod=manual$/m, 'fallback profile keeps the static IPv6 handoff after pivot' );
like( $fallback, qr/^address1=2001:db8:2::21\/64$/m, 'fallback profile persists the live IPv6 address and prefix' );
like( $fallback, qr/^gateway=fe80::1$/m, 'fallback profile persists the live IPv6 default gateway' );
unlike( $fallback, qr/^method=dhcp$/m, 'fallback profile does not reintroduce DHCPv6 identity drift' );
is(
    ( stat($fallback_profile) )[2] & oct('07777'),
    oct('0600'),
    'fallback NetworkManager profile has private permissions'
);

like(
    $source,
    qr/^MASTER="\$\(xcat_endpoint_host "\$XCATMASTER"\)"$/m,
    'the runtime derives logger and updateflag host from the endpoint parser'
);
like(
    $source,
    qr{/tmp/updateflag "\$MASTER" "\$XCATIPORT" "installstatus netbooting"},
    'updateflag receives the raw server host and the independent install port'
);
like(
    $source,
    qr/SYSLOGHOST=\(-n "\$MASTER"\)/,
    'remote logger receives the raw server host as one argument'
);
like(
    $source,
    qr/curl --fail --output "\$FILENAME" -- "\$imgurl"/,
    'curl receives the bracketed IPv6 URL and output filename as quoted arguments'
);
unlike(
    $source,
    qr/DHCPV6C=yes/,
    'the EL10 stateless pivot does not create a competing DHCPv6 ifcfg profile'
);
like(
    $source,
    qr/rm -f "\$NEWROOT\/etc\/sysconfig\/network-scripts\/ifcfg-\$ETHX"/,
    'the IPv6 path removes a stale legacy ifcfg profile'
);
like(
    $source,
    qr/echo "BOOTPROTO=dhcp" >> "\$NEWROOT\/etc\/sysconfig\/network-scripts\/ifcfg-\$ETHX"/,
    'the existing IPv4 DHCP fallback remains intact'
);

done_testing();
