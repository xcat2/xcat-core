#!/usr/bin/env perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use xCAT::Test::OS;

sub a_system {
    my (%files) = @_;
    my $root = tempdir(CLEANUP => 1);
    make_path("$root/etc");
    for my $name (sort keys %files) {
        open my $fh, '>', "$root/etc/$name" or die "write $root/etc/$name: $!";
        print {$fh} $files{$name};
        close $fh or die "close $root/etc/$name: $!";
    }
    return $root;
}

my $OPENEULER_OS_RELEASE = <<'REL';
NAME="openEuler"
VERSION="24.03 (LTS-SP4)"
ID="openEuler"
VERSION_ID="24.03"
PRETTY_NAME="openEuler 24.03 (LTS-SP4)"
REL


is(xCAT::Test::OS::current_os(a_system('os-release'        => $OPENEULER_OS_RELEASE,
                                       'openEuler-release' => "openEuler release 24.03 (LTS-SP4)\n",
                                       'system-release'    => "openEuler release 24.03 (LTS-SP4)\n")),
   'openeuler24.03sp4',
   'openEuler 24.03 SP4 is named, with the release copycds puts in its osimage names');

is(xCAT::Test::OS::current_os(a_system('redhat-release' => "AlmaLinux release 10.2 (Lavender Lion)\n",
                                       'os-release'     => $OPENEULER_OS_RELEASE)),
   'rhels10',
   '/etc/redhat-release decides before /etc/os-release, so openEuler must not ship one');

my $sp3 = $OPENEULER_OS_RELEASE;
$sp3 =~ s/LTS-SP4/LTS-SP3/;
is(xCAT::Test::OS::current_os(a_system('os-release' => $sp3)), 'openeuler24.03sp3',
   'a different service pack is a different name');

my $lts = $OPENEULER_OS_RELEASE;
$lts =~ s/VERSION="24\.03 \(LTS-SP4\)"/VERSION="22.03 (LTS)"/;
is(xCAT::Test::OS::current_os(a_system('os-release' => $lts)), 'openeuler22.03',
   'a release with no service pack carries no sp token');

is(xCAT::Test::OS::current_os(a_system('os-release' => qq{NAME="Fedora Linux"\nID=fedora\n})),
   undef, 'a distribution whose ID is not openEuler is not openEuler');

is(xCAT::Test::OS::current_os(a_system('redhat-release' => "AlmaLinux release 9.4 (Seafoam Ocelot)\n",
                                       'os-release' => qq{ID="almalinux"\n})),
   'rhels9', 'a Red Hat family system is rhels plus its major version');
is(xCAT::Test::OS::current_os(a_system('lsb-release' => "DISTRIB_ID=Ubuntu\n")), 'ubuntu',
   'Ubuntu is named from lsb-release');
is(xCAT::Test::OS::current_os(a_system('os-release' => qq{ID="sles"\nVERSION="15-SP6"\n})), 'sles',
   'SLES is named from os-release');

# openSUSE. /etc/os-release carries ID="opensuse-leap" and no "sles" anywhere, and Leap ships
# none of redhat-release, lsb-release or SuSE-release, so current_os fell through its os-release
# arm and returned undef. xcattest then warned "Use of uninitialized value $currentos" four
# times per case and rejected every one: "Test case reg_linux_diskfull_installation_flat has an
# invalid OS option - Linux / There is no valid case to run". 328 of the shipped cases declare
# os:Linux, so an openSUSE management node ran none of them, and the two cases were skipped
# rather than failed -- no result at all.
#
# Measured 2026-10-24 on xcat20-mn, an openSUSE Leap 15.6 management node: current_os answered
# UNDEF, /etc/os-release holds ID="opensuse-leap" and VERSION_ID="15.6", and none of the three
# fallback files exist.
#
# openSUSE answers with the SLE family rather than a name of its own, which was decided on
# 2026-09-18 for the same bug against the routine xcattest carried before xCAT::Test::OS
# existed. Leap and SLE of the same major share a package set, sles.pm claims leap15, and
# xcat.org publishes the Leap dependencies under sles15. It also lets the 18 cases written
# os:sles select a Leap node, which a separate name would not.
my $LEAP_OS_RELEASE = <<'REL';
NAME="openSUSE Leap"
VERSION="15.6"
ID="opensuse-leap"
ID_LIKE="suse opensuse"
VERSION_ID="15.6"
PRETTY_NAME="openSUSE Leap 15.6"
REL

is(xCAT::Test::OS::current_os(a_system('os-release' => $LEAP_OS_RELEASE)), 'sles',
   'openSUSE Leap is the SLE family whose package set it shares');

my $leap16 = $LEAP_OS_RELEASE;
$leap16 =~ s/15\.6/16.0/g;
is(xCAT::Test::OS::current_os(a_system('os-release' => $leap16)), 'sles',
   'at any Leap version, so a new release needs no change here');

# Leap 42.3, which the sles12 cell runs, spells its ID without the -leap suffix.
my $leap42 = $LEAP_OS_RELEASE;
$leap42 =~ s/ID="opensuse-leap"/ID="opensuse"/;
$leap42 =~ s/15\.6/42.3/g;
is(xCAT::Test::OS::current_os(a_system('os-release' => $leap42)), 'sles',
   'the older spelling, ID="opensuse", is recognised too');

is(xCAT::Test::OS::current_os(
       a_system('os-release' => qq{NAME="openSUSE Tumbleweed"\nID="opensuse-tumbleweed"\n})),
   'sles', 'Tumbleweed answers rather than falling through silently');

# The thing that actually broke: an empty answer matches no os: restriction at all.
my @linux = xCAT::Test::OS::linux_aliases();
ok(scalar(grep { xCAT::Test::OS::current_os(a_system('os-release' => $LEAP_OS_RELEASE)) =~ /$_/i } @linux),
   'an openSUSE Leap management node matches an os:Linux case');
is(xCAT::Test::OS::current_os(a_system()), 'aix',
   'a system with none of the release files is aix, as before');


my @aliases = xCAT::Test::OS::linux_aliases();
for my $family (qw(rhels sles ubuntu openeuler)) {
    ok(scalar(grep { $_ eq $family } @aliases), "os:Linux includes $family");
}

my $current = 'openeuler24.03sp4';
ok(scalar(grep { $current =~ /$_/i } @aliases),
   'an openEuler management node matches an os:Linux case');

done_testing();
