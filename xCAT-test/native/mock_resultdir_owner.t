#!/usr/bin/env perl
# mock_build_owner must give the uid and gid mock itself builds as, so it runs mock's own
# loader. prepare_mock_resultdirs must leave nothing in a result directory that this uid
# cannot write. CI runs this file as root in a Fedora container.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../build-utils/lib";
use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use POSIX ();
use Test::More;
use XCAT::BuildUtils qw(mock_build_owner prepare_mock_resultdirs);

plan skip_all => 'requires the mock Python library'
    if system('python3 -c "import mockbuild.config" >/dev/null 2>&1') != 0;

# Flush before the forks below, or each child repeats this file's TAP output on exit.
$| = 1;

my $conf = tempdir(CLEANUP => 1);
make_path("$conf/templates");
write_text("$conf/templates/owner.tpl",
    "config_opts['chrootuid'] = 1000\nconfig_opts['chrootgid'] = 1000\n");

my %cfg = (
    'inline-comment' => "config_opts['chrootuid'] = 1001  # build user\n"
        . "config_opts['chrootgid'] = 1001  # build group\n",
    'double-quoted' => qq(config_opts["chrootuid"] = 1001\nconfig_opts["chrootgid"] = 1001\n),
    'included'      => "include('templates/owner.tpl')\n",
    'set-after-include' => "include('templates/owner.tpl')\n"
        . "config_opts['chrootuid'] = 1001\nconfig_opts['chrootgid'] = 1001\n",
    'include-after-set' => "config_opts['chrootuid'] = 1001\nconfig_opts['chrootgid'] = 1001\n"
        . "include('templates/owner.tpl')\n",
    'plain' => "config_opts['root'] = 'plain'\n",
);
write_text("$conf/$_.cfg", $cfg{$_}) for keys %cfg;

is_deeply([ mock_build_owner('inline-comment', $conf) ], [ 1001, 1001 ],
    'an assignment with an inline comment counts');
is_deeply([ mock_build_owner('double-quoted', $conf) ], [ 1001, 1001 ],
    'an assignment with a double-quoted key counts');
is_deeply([ mock_build_owner('included', $conf) ], [ 1000, 1000 ],
    'an include resolves against the configuration directory');
is_deeply([ mock_build_owner('set-after-include', $conf) ], [ 1001, 1001 ],
    'an assignment after an include overrides it');
is_deeply([ mock_build_owner('include-after-set', $conf) ], [ 1000, 1000 ],
    'an include after an assignment overrides it');
my $mock_gid = (getgrnam 'mock')[2];
is_deeply([ mock_build_owner('plain', $conf) ], [ $<, $mock_gid ],
    'with no chrootuid, mock builds as the caller and the mock group');

SKIP: {
    skip 'giving files to uid 1000 requires root', 13 if $> != 0;

    # A root build that stopped part way left root-owned 0644 logs and a source rpm.
    my $tmp = tempdir(CLEANUP => 1);
    chmod 0755, $tmp or die "Cannot make $tmp traversable: $!\n";
    my @dirs = ("$tmp/dist/openeuler-24.03-ppc64le/rpms", "$tmp/dist/openeuler-24.03-ppc64le/rpms/SRPMS");
    make_path(@dirs);
    my @logs = map { my $d = $_; map { "$d/$_" } qw(build.log root.log state.log hw_info.log installed_pkgs.log) } @dirs;
    my @stale = (@logs, "$dirs[1]/xCAT-2.19.1-1.src.rpm");
    for my $file (@stale) {
        write_text($file, "interrupted\n");
        chmod 0644, $file;
    }
    chmod 0755, $tmp, "$tmp/dist", "$tmp/dist/openeuler-24.03-ppc64le";

    prepare_mock_resultdirs('included', $conf, @dirs);
    ok(writable_as(1000, 1000, $_), "uid 1000 can append to $_") for @stale[0 .. $#logs];
    ok(writable_as(1000, 1000, $stale[-1]), 'uid 1000 can replace the stale source rpm');
    ok(writable_as(1000, 1000, "$_/new.log"), "uid 1000 can create a file in $_") for @dirs;
}

done_testing();

# Fork, take the uid and gid, and append one line to $file.
sub writable_as {
    my ($uid, $gid, $file) = @_;
    my $pid = fork // die "fork: $!\n";
    if ($pid == 0) {
        $) = "$gid $gid";    # drop root from the supplementary groups
        POSIX::setgid($gid) or POSIX::_exit(2);
        POSIX::setuid($uid) or POSIX::_exit(2);
        open(my $fh, '>>', $file) or POSIX::_exit(1);
        print {$fh} "retry\n" or POSIX::_exit(1);
        close $fh or POSIX::_exit(1);
        POSIX::_exit(0);
    }
    waitpid($pid, 0);
    return $? == 0;
}
