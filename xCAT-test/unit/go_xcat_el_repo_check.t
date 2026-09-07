#!/usr/bin/env perl
use strict;
use warnings;

use File::Temp qw(tempdir);
use FindBin;
use Test::More;

# go-xcat checked for the EPEL and CRB repositories on EL9 only, and only when the version
# carried a minor number, so CentOS Stream was never checked. On EL10 a management node without
# them failed inside dnf install with a dependency error instead of the message that names the
# missing repository, and the CRB message proposed a CentOS Stream repository file with
# signature checks disabled. The probe used dnf list, which an installed copy of the probe
# package satisfies, and which reports a failed query as a missing repository. The check
# functions are taken from the shipped script and run against a dnf stand-in that answers for
# each probe and records what was asked.

my $go_xcat = "$FindBin::Bin/../../xCAT-server/share/xcat/tools/go-xcat";
plan skip_all => 'go-xcat not found' unless -r $go_xcat;

my $tmpdir = tempdir( CLEANUP => 1 );
my $driver = "$tmpdir/driver.sh";
my $calls  = "$tmpdir/calls";
open( my $fh, '>', $driver ) or die "open $driver: $!";
print {$fh} <<'DRIVER';
#!/bin/bash
set -uo pipefail
eval "$(awk '
    /^function (repo_carries|el9?_epel_and_crb_check|install_packages_(dnf|yum))\(\)/ { copy = 1 }
    copy { print }
    copy && /^}$/ { copy = 0 }
' "$GO_XCAT_SOURCE")"
EL9_EPEL_TEST_RPM="perl-Crypt-CBC"; EL_EPEL_TEST_RPM="perl-Crypt-CBC"
EL9_CRB_TEST_RPM="perl-IO-Tty";     EL_CRB_TEST_RPM="perl-IO-Tty"
# repoquery prints the name when an enabled repository carries the package and nothing
# otherwise, and fails with a message when the repositories cannot be read. list -q exits 1
# when neither a repository nor the installed set has the package.
dnf() {
    echo "$*" >> "$CALLS"
    if [[ ${QUERY_FAIL:-0} == 1 ]]; then
        echo "Error: Failed to download metadata for repo 'epel'" >&2
        return 1
    fi
    [[ ${QUERY_WARNS:-0} == 1 ]] && echo "Warning: repository 'extras' metadata is stale" >&2
    local has=0
    case "$*" in
        *perl-Crypt-CBC*) has="$EPEL_HAS" ;;
        *perl-IO-Tty*)    has="$CRB_HAS" ;;
    esac
    # A source repository answers for the name unless the query is limited to binary architectures.
    [[ ${SOURCE_ONLY:-0} == 1 && "$*" != *"--arch"* ]] && has=1
    case "$1" in
        repoquery) [[ $has == 1 ]] && { echo "${@: -1}"; echo "${@: -1}"; }; return 0 ;;
        list)      [[ $has == 1 ]] && return 0; return 1 ;;
    esac
    return 0
}
yum() { dnf "$@"; }
# ENTRY=dnf or yum runs the installer function go-xcat dispatches to, which owns the check.
case "${ENTRY:-check}" in
    dnf) install_packages_dnf -y xCAT ;;
    yum) install_packages_yum -y xCAT ;;
    *)   if declare -F el_epel_and_crb_check >/dev/null; then el_epel_and_crb_check dnf; else el9_epel_and_crb_check dnf; fi ;;
esac
DRIVER
close($fh);

# Runs the check as go-xcat would on a host of this distro and version. Returns the exit status,
# the output, and the probes the dnf stand-in saw.
sub check {
    my (%host) = @_;
    unlink $calls;
    local $ENV{GO_XCAT_SOURCE}        = $go_xcat;
    local $ENV{CALLS}                 = $calls;
    local $ENV{GO_XCAT_LINUX_DISTRO}  = $host{distro} || 'rocky';
    local $ENV{GO_XCAT_LINUX_VERSION} = $host{version};
    local $ENV{GO_XCAT_ARCH}          = 'x86_64';
    local $ENV{EPEL_HAS}              = $host{epel} ? 1 : 0;
    local $ENV{CRB_HAS}               = $host{crb}  ? 1 : 0;
    local $ENV{QUERY_FAIL}            = $host{query_fail} ? 1 : 0;
    local $ENV{QUERY_WARNS}           = $host{query_warns} ? 1 : 0;
    local $ENV{SOURCE_ONLY}           = $host{source_only} ? 1 : 0;
    local $ENV{ENTRY}                 = $host{entry} || 'check';
    my $out = `bash '$driver' 2>&1`;
    my $rc  = $? >> 8;
    my @probes;
    if ( open( my $cfh, '<', $calls ) ) { chomp( @probes = <$cfh> ); close($cfh); }
    return ( $rc, $out, join( ';', @probes ) );
}

my ( $rc, $out, $probes );

( $rc, $out, $probes ) = check( version => '9.5', epel => 1, crb => 1 );
is( $rc, 0, 'EL9 with EPEL and CRB passes' );
like( $probes, qr/perl-Crypt-CBC.*;.*perl-IO-Tty/, '... after probing both repositories' );
like( $probes, qr/^repoquery /, '... through repoquery, which an installed copy does not satisfy' );
like( $probes, qr/--arch x86_64,noarch/, '... limited to the binary architectures' );

( $rc, $out, $probes ) = check( version => '9.5', epel => 0, crb => 1 );
is( $rc, 1, 'EL9 without EPEL stops' );
like( $out, qr/epel-release-latest-9\.noarch/, '... and names the EL9 EPEL release package' );

( $rc, $out, $probes ) = check( version => '10.2', epel => 1, crb => 1 );
is( $rc, 0, 'EL10 with EPEL and CRB passes' );
like( $probes, qr/perl-Crypt-CBC.*;.*perl-IO-Tty/, '... after probing both repositories' );

( $rc, $out, $probes ) = check( version => '10.2', epel => 0, crb => 1 );
is( $rc, 1, 'EL10 without EPEL stops' );
like( $out, qr/requires EPEL repository/,        '... and names the missing repository' );
like( $out, qr/epel-release-latest-10\.noarch/, '... and the EL10 EPEL release package' );

( $rc, $out, $probes ) = check( distro => 'rhel', version => '10.2', epel => 1, crb => 0 );
is( $rc, 1, 'EL10 without CRB stops' );
like( $out, qr/requires CRB repository/,                '... and names the missing repository' );
like( $out, qr/'dnf update epel-release' and then 'crb enable'/, '... with a current crb helper, which covers RHEL under RHSM and RHUI' );
unlike( $out, qr/gpgcheck=0|centos-crb|subscription-manager/, '... and no repository file or subscription-only command' );

( $rc, $out, $probes ) = check( version => '10.2', epel => 0, crb => 1, source_only => 1 );
is( $rc, 1, 'a source repository does not stand in for the binary one' );
like( $out, qr/requires EPEL repository/, '... so the missing repository is still reported' );

( $rc, $out, $probes ) = check( distro => 'ol', version => '10.1', epel => 1, crb => 0 );
is( $rc, 1, 'Oracle Linux 10 without CRB stops' );
like( $out, qr/dnf config-manager --enable ol10_codeready_builder/, '... with the command that enables its CodeReady Builder' );

( $rc, $out, $probes ) = check( version => '10.2', epel => 1, crb => 1, query_fail => 1 );
is( $rc, 1, 'a failed repository query stops' );
like( $out, qr/Failed to download metadata/, '... with the package manager error' );
unlike( $out, qr/requires EPEL repository/, '... and not as a missing repository' );

( $rc, $out, $probes ) = check( version => '10.2', epel => 0, crb => 1, query_warns => 1 );
is( $rc, 1, 'a warning on stderr does not stand in for a package' );
like( $out, qr/requires EPEL repository/, '... so the missing repository is still reported' );

( $rc, $out, $probes ) = check( version => '10.2', epel => 1, crb => 1, query_warns => 1 );
is( $rc, 0, 'a warning beside a real match does not fail the check' );

( $rc, $out, $probes ) = check( distro => 'centos', version => '10', epel => 0, crb => 0 );
is( $rc, 1, 'CentOS Stream 10, which reports the major version alone, is checked' );
like( $out, qr/requires EPEL repository/, '... and told about EPEL' );

( $rc, $out, $probes ) = check( version => '8.10', epel => 0, crb => 0 );
is( $rc, 0, 'EL8 is not checked' );
is( $probes, '', '... and nothing is probed' );

( $rc, $out, $probes ) = check( distro => 'fedora', version => '42', epel => 0, crb => 0 );
is( $rc, 0, 'Fedora is not checked' );

# The installer functions go-xcat dispatches to run the check before they install anything.
foreach my $entry (qw(dnf yum)) {
    ( $rc, $out, $probes ) = check( entry => $entry, version => '10.2', epel => 0, crb => 1 );
    is( $rc, 1, "install_packages_$entry on EL10 without EPEL stops" );
    like( $out, qr/requires EPEL repository/, '... with the EPEL message' );
    unlike( $probes, qr/install/, '... before anything is installed' );

    ( $rc, $out, $probes ) = check( entry => $entry, version => '10.2', epel => 1, crb => 1 );
    is( $rc, 0, "install_packages_$entry on EL10 with EPEL and CRB installs" );
    like( $probes, qr/perl-IO-Tty.*;.*install initscripts.*;.*install xCAT/, '... after the check passed' );
}

done_testing();
