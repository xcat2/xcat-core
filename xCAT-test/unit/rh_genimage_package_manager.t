#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;

use imgutils;

my @version_cases = (
    [ 'rhel8',                 8,     'RHEL' ],
    [ 'rhels8.10',            8,     'RHEL Server' ],
    [ 'rhelc5',               5,     'RHEL Client' ],
    [ 'rhelhpc7.2',           7,     'RHEL ComputeNode' ],
    [ 'rhels7.5-alternate',    7,     'RHEL alternate-media suffix' ],
    [ 'centos7.9',             7,     'CentOS Linux' ],
    [ 'centos-stream9',        9,     'CentOS Stream' ],
    [ 'rocky9.6',              9,     'Rocky Linux' ],
    [ 'alma8.10',              8,     'AlmaLinux short name' ],
    [ 'almalinux9.4',          9,     'AlmaLinux long name' ],
    [ 'ol8.4.0',               8,     'Oracle Linux' ],
    [ 'rhels10.0',             10,    'two-digit RHEL Server' ],
    [ 'fedora42',              undef, 'reachable unsupported Fedora' ],
    [ 'SL7.9',                 undef, 'reachable unsupported Scientific Linux' ],
    [ 'RHEL9',                 undef, 'case-mismatched distribution' ],
    [ 'rhels',                 undef, 'missing major version' ],
    [ '',                      undef, 'empty version' ],
    [ undef,                   undef, 'undefined version' ],
);

for my $case (@version_cases) {
    my ( $version, $expected, $description ) = @{$case};
    is(
        imgutils::el_major_version($version),
        $expected,
        "$description resolves to the expected EL major version"
    );
}

sub installroot_command_for {
    my ( $version, $dnf_available, $non_interactive ) = @_;

    return imgutils::rpm_installroot_command(
        $version, '/var/tmp/root-image', $non_interactive, $dnf_available
    );
}

my $el7_command = installroot_command_for( 'rhels7.9', 1, '-y' );
like( $el7_command, qr/^yum -y /, 'EL7 keeps yum as its package manager' );
unlike( $el7_command, qr/--releasever=/, 'EL7 omits releasever' );
unlike( $el7_command, qr/--setopt=module_platform_id=/, 'EL7 omits module platform configuration' );

my $el8_command = installroot_command_for( 'rhels8.10', 1, '-y' );
like( $el8_command, qr/^dnf -y /, 'EL8 uses dnf when it is available' );
like( $el8_command, qr/--releasever=8 /, 'EL8 sets releasever at the package-manager boundary' );
like( $el8_command, qr/--setopt=module_platform_id=platform:el8 /, 'EL8 sets its module platform' );

my $el9_dnf_command = installroot_command_for( 'centos-stream9', 1, '-y' );
like( $el9_dnf_command, qr/^dnf -y /, 'EL9 uses dnf when it is available' );
like( $el9_dnf_command, qr/--installroot=\/var\/tmp\/root-image\//, 'EL9 preserves the requested installroot' );
like( $el9_dnf_command, qr/--releasever=9 /, 'EL9 sets releasever from the parsed major version' );
like( $el9_dnf_command, qr/--setopt=module_platform_id=platform:el9 /, 'EL9 sets its module platform' );

my $el9_yum_command = installroot_command_for( 'centos-stream9', 0, '-y' );
like( $el9_yum_command, qr/^yum -y /, 'EL9 falls back to yum when dnf is unavailable' );
like( $el9_yum_command, qr/--releasever=9 /, 'the EL9 yum fallback keeps releasever' );
like( $el9_yum_command, qr/--setopt=module_platform_id=platform:el9 /, 'the EL9 yum fallback keeps its module platform' );

my $el10_command = installroot_command_for( 'rhels10.0', 1, '-y' );
like( $el10_command, qr/--releasever=10 /, 'EL10 preserves its two-digit releasever' );
like( $el10_command, qr/--setopt=module_platform_id=platform:el10 /, 'EL10 preserves its two-digit module platform' );

my $unsupported_command = installroot_command_for( 'fedora42', 1, '-y' );
like( $unsupported_command, qr/^yum -y /, 'unsupported distributions keep the yum fallback' );
unlike( $unsupported_command, qr/--releasever=/, 'unsupported distributions omit releasever' );
unlike( $unsupported_command, qr/--setopt=module_platform_id=/, 'unsupported distributions omit module platform configuration' );

my $interactive_command = installroot_command_for( 'rhels8.10', 1, undef );
like( $interactive_command, qr/^dnf  -c /, 'interactive mode omits the non-interactive package-manager option' );

done_testing();
