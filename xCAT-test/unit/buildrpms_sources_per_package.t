#!/usr/bin/env perl
# buildrpms.pl forks a child per package and target. Each child stages its source
# tarballs into a directory named for its pid, and the parent deletes it after the child.
use strict;
use warnings;

use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../../build-utils/lib";
use Test::More;

use XCAT::BuildUtils qw(build_sources_base build_sources_dir prepare_build_sources_dir
    remove_build_sources_dir sweep_build_sources_dirs);

my $home = tempdir(CLEANUP => 1);
my $base = build_sources_base($home);
is($base, "$home/rpmbuild/sources", 'the base directory is under the rpmbuild tree');

# Two live processes on one host never have the same pid. The host name keeps two
# hosts apart when $HOME is on NFS.
my $a = build_sources_dir($base, 101, 'hosta');
my $b = build_sources_dir($base, 102, 'hosta');
my $c = build_sources_dir($base, 101, 'hostb');
isnt($a, $b, 'two pids stage into different directories');
isnt($a, $c, 'one pid on two hosts stages into different directories');
is($a, "$base/SOURCES.hosta.101", 'the directory name carries the host and the pid');
is(build_sources_dir($base, undef, 'hosta'), "$base/SOURCES.hosta.$$",
    'the pid defaults to the calling process');

ok(!eval { build_sources_dir($base, 'x1', 'hosta'); 1 }, 'a pid that is not a number is fatal');
like($@, qr/build_sources_dir: pid 'x1' is not a number/, 'and the message names the pid');
ok(!eval { build_sources_dir('', 101, 'hosta'); 1 }, 'an empty base is fatal');
like($@, qr/build_sources_dir: no base directory/, 'and the message names the base');

# A directory with the same name is left by a dead process that had this pid.
make_path($a);
write_text("$a/stale.tar.gz", "old\n");
my $made = prepare_build_sources_dir($base, 101, 'hosta');
is($made, $a, 'prepare returns the directory of that pid');
ok(-d $made, 'the staging directory is created');
opendir(my $dh, $made) or die "cannot read $made: $!\n";
my @left = grep { !/^\.\.?$/ } readdir $dh;
closedir $dh;
is_deeply(\@left, [], 'the staging directory is created empty');
remove_build_sources_dir($base, 101, 'hosta');

# The parent calls remove_build_sources_dir when it reaps a child, whatever its exit.
for my $how ('success', 'failure') {
    my $dir = prepare_build_sources_dir($base, 201, 'hosta');
    write_text("$dir/xCAT-test-2.20.0.tar.gz", "payload\n");
    my $pid = fork // die "fork: $!\n";
    if ($pid == 0) {
        require POSIX;
        POSIX::_exit($how eq 'success' ? 0 : 1);
    }
    waitpid($pid, 0);
    is($? >> 8, $how eq 'success' ? 0 : 1, "the child exits for $how");
    ok(remove_build_sources_dir($base, 201, 'hosta'), "remove reports the directory gone after $how");
    ok(!-e $dir, "the directory is deleted after $how");
}
ok(remove_build_sources_dir($base, 202, 'hosta'), 'removing a directory that does not exist is not an error');

# The sweep deletes the directories of dead pids on this host only.
my %alive = (301 => 1);
my $is_alive = sub { $alive{ $_[0] } };
my $dead  = prepare_build_sources_dir($base, 300, 'hosta');
my $live  = prepare_build_sources_dir($base, 301, 'hosta');
my $other = prepare_build_sources_dir($base, 300, 'hostb');
make_path("$base/unrelated");
my @swept = sweep_build_sources_dirs($base, 'hosta', $is_alive);
is_deeply(\@swept, [$dead], 'the sweep reports the directory of the dead pid');
ok(!-e $dead, 'the directory of a dead pid is deleted');
ok(-d $live, 'the directory of a live pid is kept');
ok(-d $other, 'the directory of another host is kept');
ok(-d "$base/unrelated", 'a directory with another name is kept');

# The default liveness check: this process is alive, a reaped child is not.
my $own = prepare_build_sources_dir($base, $$, 'hosta');
my $gone = fork // die "fork: $!\n";
if ($gone == 0) { require POSIX; POSIX::_exit(0) }
waitpid($gone, 0);
my $reaped = prepare_build_sources_dir($base, $gone, 'hosta');
sweep_build_sources_dirs($base, 'hosta');
ok(-d $own, 'the default check keeps the directory of a running process');
ok(!-e $reaped, 'the default check deletes the directory of a reaped process');

is_deeply([sweep_build_sources_dirs("$home/absent", 'hosta', $is_alive)], [],
    'a missing base directory is not an error');

done_testing;
