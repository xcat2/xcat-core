#!/usr/bin/env perl
# buildrpms.pl staged the xCAT-probe source tarball before it forked a child per package, but
# the staging directory is set in that child. The destination was therefore composed from an
# empty string, and every RPM target died before it built anything:
#
#   Can't rename('.xCAT-probe-2.20.0.UNf6IG', '/xCAT-probe-2.20.0.tar.gz'):
#       Invalid cross-device link at ./buildrpms.pl line 386
#
# The staging directory is an argument now, so an unset one is refused instead of composing a
# path outside the build.
use strict;
use warnings;

use Archive::Tar ();
use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../../build-utils/lib";
use Test::More;

use XCAT::BuildUtils qw(XCAT_PROBE_HELPERS stage_xcat_probe_sources);

my $epoch   = 1600000000;
my $version = '9.9.9';

# A checkout holds xCAT-probe beside the perl-xCAT modules xcatprobe loads at runtime.
my $checkout = tempdir(CLEANUP => 1);
make_path("$checkout/xCAT-probe/subcmds", "$checkout/perl-xCAT/xCAT");
write_text("$checkout/xCAT-probe/xcatprobe",        "#!/usr/bin/perl\n");
write_text("$checkout/xCAT-probe/subcmds/xcatmn",   "#!/usr/bin/perl\n");
write_text("$checkout/perl-xCAT/xCAT/$_", "package xCAT::" . ($_ =~ s/\.pm$//r) . ";\n1;\n")
    for XCAT_PROBE_HELPERS;

my $sources = tempdir(CLEANUP => 1);
my $tarball = stage_xcat_probe_sources($checkout, $sources, $version, $epoch);

is($tarball, "$sources/xCAT-probe-$version.tar.gz",
    'the archive is named for the version and published in the staging directory it was given');
ok(-f $tarball, 'the archive exists where the return value says it does');

my %member = map { $_ => 1 } Archive::Tar->new($tarball)->list_files;
ok($member{'xCAT-probe/xcatprobe'},      'the archive carries the package sources');
ok($member{'xCAT-probe/subcmds/xcatmn'}, 'the archive carries the subcommands');
ok($member{"xCAT-probe/lib/perl/xCAT/$_"}, "$_ is staged where xcatprobe loads it")
    for XCAT_PROBE_HELPERS;

# Nothing is left beside the archive: a temporary name that survived would reach the src.rpm.
opendir(my $dh, $sources) or die "opendir $sources: $!\n";
my @left = sort grep { !/^\.{1,2}$/ } readdir $dh;
closedir $dh;
is_deeply(\@left, ["xCAT-probe-$version.tar.gz"],
    'the staging directory holds the published archive and no temporary file');

# The regression. An unset staging directory must be refused, not interpolated: the build that
# passed one had no directory of its own yet, and the archive left the build tree entirely.
for my $case (['an unset staging directory', undef], ['an empty staging directory', '']) {
    my ($what, $dir) = @$case;
    my $ok = eval { stage_xcat_probe_sources($checkout, $dir, $version, $epoch); 1 };
    ok(!$ok, "$what is refused");
    like($@, qr/stage_xcat_probe_sources: staging directory is required/,
        "the message names the staging directory for $what");
}

# A directory that does not exist is the same defect one step later -- the child had not created
# its staging directory yet -- and it must not be created here.
my $absent = "$sources/not-created-yet";
my $ok = eval { stage_xcat_probe_sources($checkout, $absent, $version, $epoch); 1 };
ok(!$ok, 'a staging directory that does not exist is refused');
like($@, qr/\Qstage_xcat_probe_sources: no staging directory $absent\E/,
    'the message names the directory that is missing');
ok(!-e $absent, 'the missing staging directory is not created');

# A missing version would publish xCAT-probe-.tar.gz, which no spec names as its Source.
my $noversion = eval { stage_xcat_probe_sources($checkout, $sources, '', $epoch); 1 };
ok(!$noversion, 'a missing version is refused');
like($@, qr/stage_xcat_probe_sources: version is required/, 'the message names the version');

# A checkout without xCAT-probe is reported as the checkout it is, not as a tar failure.
my $bare = tempdir(CLEANUP => 1);
my $nosrc = eval { stage_xcat_probe_sources($bare, $sources, $version, $epoch); 1 };
ok(!$nosrc, 'a checkout without xCAT-probe is refused');
like($@, qr/\QNo directory xCAT-probe in $bare\E/, 'the message names the checkout');

done_testing;
