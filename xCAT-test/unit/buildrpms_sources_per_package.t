#!/usr/bin/env perl
# buildrpms.pl staged every source tarball into one $HOME/rpmbuild/SOURCES while forking a child
# per package and target, so a build could read a truncated archive:
#
#   error: File /builddir/build/SOURCES/xCAT-test-2.20.0.tar.gz is smaller than 13 bytes
#
# Two packages of one target collide the same way: xCAT and xCATsn both write etc.tar.gz.
use strict;
use warnings;

use File::Spec ();
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../../build-utils/lib";
use Test::More;

use XCAT::BuildUtils qw(build_sources_dir prepare_build_sources_dir);

my $home = tempdir(CLEANUP => 1);

# The key is the package AND the target. Either one alone leaves a pair sharing a directory.
my $a = build_sources_dir('xCAT',   'openeuler-24.03sp4-x86_64', 'ci', $home);
my $b = build_sources_dir('xCATsn', 'openeuler-24.03sp4-x86_64', 'ci', $home);
my $c = build_sources_dir('xCAT',   'openeuler-22.03sp4-x86_64', 'ci', $home);
isnt($a, $b, 'two packages of one target stage into different directories');
isnt($a, $c, 'two targets of one package stage into different directories');

# Keyed like the mock chroot, so the staging directory and the chroot cannot disagree about
# which build owns which files.
is($a, "$home/rpmbuild/xCAT-openeuler-24.03sp4-x86_64-ci/SOURCES",
    'the directory is keyed like the mock chroot: package, target, uniqueext');
is(build_sources_dir('xCAT', 'openeuler-24.03sp4-x86_64', '', $home),
    "$home/rpmbuild/xCAT-openeuler-24.03sp4-x86_64/SOURCES",
    'an empty uniqueext adds no trailing separator');
isnt(build_sources_dir('xCAT', 'el9-x86_64', 'ci', $home),
     build_sources_dir('xCAT', 'el9-x86_64', 'other', $home),
    'two uniqueexts of one pair do not share, so two runs on one host cannot collide');

# A missing argument must not collapse the key back to the one shared directory.
for my $case (['package', undef, 'el9-x86_64'], ['target', 'xCAT', undef],
              ['empty package', '', 'el9-x86_64'], ['empty target', 'xCAT', '']) {
    my ($what, $pkg, $tg) = @$case;
    my $died = eval { build_sources_dir($pkg, $tg, 'ci', $home); 1 } ? 0 : 1;
    ok($died, "a missing $what is fatal rather than a shared directory");
    like($@, qr/build_sources_dir: (?:package|target) is required/,
        "the message names the missing argument for $what");
}

# prepare_build_sources_dir is what buildall calls: it must CREATE the directory, because
# staging into a path that does not exist is how the shared tree came to be created up front.
my $made = prepare_build_sources_dir('xCAT-test', 'openeuler-24.03sp4-x86_64', 'ci', $home);
ok(-d $made, 'the staging directory is created, not merely named');
my $again = prepare_build_sources_dir('xCAT-test', 'openeuler-24.03sp4-x86_64', 'ci', $home);
is($again, $made, 'a second call is idempotent and returns the same directory');

# Nothing writes beside the per-pair directories: a path that escaped $home/rpmbuild would put
# one build's sources where another build reads them.
my @dirs = map { build_sources_dir($_, 'el9-x86_64', 'ci', $home) } qw(xCAT xCATsn xCAT-test);
for my $d (@dirs) {
    like($d, qr{^\Q$home/rpmbuild/\E[^/]+/SOURCES$}, "$d is one level under rpmbuild");
}

done_testing;
