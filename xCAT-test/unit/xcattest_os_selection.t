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
