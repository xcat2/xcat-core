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
use File::Slurper qw(read_binary write_binary write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../../build-utils/lib";
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::Process qw(run_command);

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

subtest 'reproducible archive' => sub {
    write_binary("$checkout/xCAT-probe/z-last", "last\0\xff");
    write_binary("$checkout/xCAT-probe/a-first", 'first');
    chmod(0755, "$checkout/xCAT-probe/xcatprobe") or die $!;
    stage_xcat_probe_sources($checkout, $sources, $version, $epoch);
    my $first = read_binary($tarball);
    utime($epoch + 100, $epoch + 100, "$checkout/xCAT-probe/xcatprobe") or die $!;
    stage_xcat_probe_sources($checkout, $sources, $version, $epoch);
    is(scalar(read_binary($tarball)), $first, 'source mtimes do not change archive bytes at a fixed epoch');
    is(unpack('V', substr($first, 4, 4)), 0, 'gzip header carries no timestamp');
    is((stat($tarball))[2] & 0777, 0644, 'published archive remains readable');
    my $tar = Archive::Tar->new($tarball);
    my @names = $tar->list_files;
    is_deeply(\@names, [sort @names], 'members are sorted by name');
    for my $file ($tar->get_files) {
        is($file->uid, 0, $file->name . ' has normalized owner');
        is($file->gid, 0, $file->name . ' has normalized group');
        is($file->uname, '', $file->name . ' has no owner name');
        is($file->gname, '', $file->name . ' has no group name');
        is($file->mtime, $epoch, $file->name . ' uses the requested epoch');
    }
    is($tar->get_content('xCAT-probe/z-last'), "last\0\xff", 'binary payload is retained');
    my ($executable) = $tar->get_files('xCAT-probe/xcatprobe');
    is($executable->mode & 0777, 0755, 'source executable mode is retained');
    is(scalar(read_binary("$checkout/xCAT-probe/z-last")), "last\0\xff", 'checkout bytes are untouched');
};

subtest 'archive failures' => sub {
    my $tools = tempdir(CLEANUP => 1);
    write_text("$tools/tar", <<'SH');
#!/bin/sh
while [ "$#" -gt 0 ]; do
    if [ "$1" = -cf ]; then
        shift
        printf 'incomplete archive' > "$1"
        exit 37
    fi
    shift
done
exit 38
SH
    chmod(0755, "$tools/tar") or die $!;
    my @command = ($^X, '-I', "$FindBin::Bin/../../build-utils/lib",
        '-MXCAT::BuildUtils=stage_xcat_probe_sources', '-e', 'stage_xcat_probe_sources(@ARGV)',
        $checkout, $sources, $version, $epoch);
    my $before = read_binary($tarball);
    {
        local $ENV{PATH} = "$tools:$ENV{PATH}";
        my ($rc, $output) = run_command(@command);
        isnt($rc, 0, 'failed archive creation stops the caller');
        like($output, qr/Error creating \Q$tarball\E/, 'the failure names the requested archive');
    }
    is(scalar(read_binary($tarball)), $before, 'failed creation preserves the published archive');
    is_deeply([glob("$sources/.xCAT-probe-*")], [], 'failed creation leaves no temporary archive after exit');
    unlink($tarball) or die $!;
    mkdir($tarball) or die $!;
    write_binary("$tarball/sentinel", 'existing directory');
    my ($rc, $output) = run_command(@command);
    isnt($rc, 0, 'a refused publication stops the caller');
    like($output, qr/Unable to publish \Q$tarball\E/, 'the rename failure is explicit');
    is(scalar(read_binary("$tarball/sentinel")), 'existing directory', 'failed rename preserves the destination');
    is_deeply([glob("$sources/.xCAT-probe-*")], [], 'failed rename leaves no temporary archive after exit');
};

done_testing;
