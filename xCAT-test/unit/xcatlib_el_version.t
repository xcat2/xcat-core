#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $xcatlib = File::Spec->catfile(
    $FindBin::Bin, '..', '..', 'xCAT', 'postscripts', 'xcatlib.sh'
);
my $nicutils = File::Spec->catfile(
    $FindBin::Bin, '..', '..', 'xCAT', 'postscripts', 'nicutils.sh'
);
my $routeop = File::Spec->catfile(
    $FindBin::Bin, '..', '..', 'xCAT', 'postscripts', 'routeop'
);

sub extra_parameter_path {
    my ( $osver, $report_rematch ) = @_;
    $report_rematch //= '';
    my $script = <<'BASH';
source "$1"
source "$2"
query_extra_params()
{
    array_extra_param_names=(mtu)
    array_extra_param_values=(9000)
}

grep()
{
    return 0
}
sed()
{
    printf '%s\n' legacy-write
}
nmcli()
{
    case "$1 $2" in
        'con modify') printf '%s\n' el9-nmcli ;;
        'con reload') printf '%s\n' legacy-reload ;;
        *) return 2 ;;
    esac
}
OSVER=$3
add_extra_params_nmcli eth0 test0
if [ "$4" = rematch ]; then
    printf '%s|%s|%s|%s\n' \
        "${#BASH_REMATCH[@]}" \
        "${BASH_REMATCH[0]-}" \
        "${BASH_REMATCH[1]-}" \
        "${BASH_REMATCH[2]-}"
fi
BASH

    open(
        my $output,
        '-|',
        'bash',
        '--noprofile',
        '--norc',
        '-c',
        $script,
        'bash',
        $xcatlib,
        $nicutils,
        $osver,
        $report_rematch
    ) or die "Unable to run EL postscript workflow: $!";

    my $result = do { local $/; <$output> };
    close($output) or die "EL postscript workflow failed: $?";
    chomp $result;
    return $result;
}

sub route_path_without_current_helper {
    my ($stale_library) = @_;
    my $tempdir = tempdir( CLEANUP => 1 );
    my $runner = File::Spec->catfile( $tempdir, 'routeop-runner' );

    if ($stale_library) {
        my $old_xcatlib = File::Spec->catfile( $tempdir, 'xcatlib.sh' );
        open( my $library, '>', $old_xcatlib )
          or die "Unable to create old xcatlib stub: $!";
        print {$library} "# Older xcatlib without xcat_is_el9_or_later\n";
        close($library) or die "Unable to close old xcatlib stub: $!";
    }

    my $script = <<'BASH';
exec 2>&1
uname()
{
    printf '%s\n' "$ROUTE_TEST_UNAME"
}
nmcli()
{
    return 0
}
report_route_path()
{
    if [ "$ROUTE_TEST_UNSET_HELPER" = 1 ]; then
        unset -f xcat_is_el9_or_later
    fi
    OS_name=redhat
    OSVER=rhel9
    if redhat_uses_nmcli_routes; then
        printf '%s\n' el9-nmcli
    else
        printf '%s\n' legacy-route
    fi
}
trap report_route_path EXIT
source "$1" noop 192.0.2.0 24 192.0.2.1 eth0
BASH

    local $ENV{ROUTE_TEST_UNAME} = 'Linux';
    local $ENV{ROUTE_TEST_UNSET_HELPER} = $stale_library ? 0 : 1;
    open(
        my $output,
        '-|',
        'bash',
        '--noprofile',
        '--norc',
        '-c',
        $script,
        $runner,
        $routeop
    ) or die "Unable to run routeop workflow: $!";

    my $result = do { local $/; <$output> };
    close($output) or die "routeop workflow failed: $?";
    chomp $result;
    return $result;
}

my @accepted = (
    [ 'rhel9',          'RHEL 9' ],
    [ 'rhels9.6',       'legacy RHEL spelling with a point release' ],
    [ 'alma9',          'AlmaLinux short spelling' ],
    [ 'almalinux9.5',   'AlmaLinux long spelling with a point release' ],
    [ 'rocky10',        'Rocky Linux 10' ],
    [ 'centos10-stream', 'CentOS 10 stream suffix' ],
    [ 'ol10',           'Oracle Linux 10' ],
);

for my $case (@accepted) {
    is(
        extra_parameter_path( $case->[0] ),
        'el9-nmcli',
        "$case->[1] uses the EL9 NetworkManager path"
    );
}

my @rejected = (
    [ 'rhel8.10',      'RHEL 8' ],
    [ 'rhels8',        'legacy RHEL 8 spelling' ],
    [ 'alma8',         'AlmaLinux 8 short spelling' ],
    [ 'almalinux8.10', 'AlmaLinux 8 long spelling' ],
    [ 'rocky8',        'Rocky Linux 8' ],
    [ 'centos8',       'CentOS 8' ],
    [ 'ol8',           'Oracle Linux 8' ],
    [ 'redhat9',       'unsupported Red Hat spelling' ],
    [ 'ubuntu24.04',   'unrelated distribution' ],
    [ '',              'missing OS version' ],
);

for my $case (@rejected) {
    is(
        extra_parameter_path( $case->[0] ),
        "legacy-write\nlegacy-reload",
        "$case->[1] uses the legacy ifcfg path"
    );
}

is(
    route_path_without_current_helper(0),
    'el9-nmcli',
    'routeop preserves EL9 routing when xcatlib is unavailable'
);

is(
    route_path_without_current_helper(1),
    'el9-nmcli',
    'routeop preserves EL9 routing with an older xcatlib'
);

is(
    extra_parameter_path( 'rhel9', 'rematch' ),
    "el9-nmcli\n3|rhel9|rhel|9",
    'EL9 workflow preserves successful regex captures'
);

is(
    extra_parameter_path( 'rhel8', 'rematch' ),
    "legacy-write\nlegacy-reload\n0|||",
    'legacy workflow preserves failed regex captures'
);

done_testing();
