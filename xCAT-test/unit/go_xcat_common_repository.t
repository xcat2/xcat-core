#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $go_xcat = "$FindBin::Bin/../../xCAT-server/share/xcat/tools/go-xcat";
my $tmpdir = tempdir(CLEANUP => 1);
my $driver = "$tmpdir/driver.sh";

open(my $driver_fh, '>', $driver) or die "open $driver: $!";
print {$driver_fh} <<'DRIVER';
#!/bin/bash
set -euo pipefail

export GO_XCAT_LIBRARY_ONLY=1
source "$GO_XCAT_SOURCE"

TMP_DIR=$TEST_TMP
GO_XCAT_DEFAULT_BASE_URL=https://repo.example.invalid
GO_XCAT_DEP_REPOSITORY_IDS=(xcat-dep)

yum() { :; }

download_file() {
    printf '%s\n' "$1" >>"$DOWNLOAD_LOG"
    [[ ${COMMON_PRESENT:-0} == 1 ]] || return 1
    : >"$2"
}

add_repo_by_url_yum_or_zypper() {
    printf '%s %s\n' "$1" "$2" >>"$ADD_LOG"
}

add_xcat_dep_common_repo_yum_or_zypper "$@"
printf '%s\n' "${GO_XCAT_DEP_REPOSITORY_IDS[*]}" >"$ID_LOG"
DRIVER
close($driver_fh) or die "close $driver: $!";
chmod(0755, $driver) or die "chmod $driver: $!";

sub run_case {
    my ($name, $present, @arguments) = @_;
    my $case_dir = "$tmpdir/$name";
    make_path($case_dir);
    local %ENV = (
        %ENV,
        ADD_LOG        => "$case_dir/add.log",
        COMMON_PRESENT => $present,
        DOWNLOAD_LOG   => "$case_dir/download.log",
        GO_XCAT_SOURCE => $go_xcat,
        ID_LOG         => "$case_dir/id.log",
        TEST_TMP       => $case_dir,
    );
    my $status = system('bash', $driver, @arguments);
    return ($status >> 8, $case_dir);
}

sub read_file {
    my ($path) = @_;
    return '' unless -f $path;
    open(my $fh, '<', $path) or die "open $path: $!";
    my $content = do { local $/; <$fh> };
    close($fh) or die "close $path: $!";
    return $content;
}

my ($status, $case_dir) = run_case('remote-present', 1, '', 'latest');
is($status, 0, 'an available common repository is accepted');
is(
    read_file("$case_dir/download.log"),
    "https://repo.example.invalid/yum/latest/xcat-dep/common/repodata/repomd.xml\n",
    'the default repository is probed before it is enabled',
);
is(
    read_file("$case_dir/add.log"),
    "https://repo.example.invalid/yum/latest/xcat-dep/common xcat-dep-common\n",
    'the common repository uses its own repository ID',
);
is(read_file("$case_dir/id.log"), "xcat-dep xcat-dep-common\n",
    'common packages are included in repository listings');

($status, $case_dir) = run_case('remote-missing', 0, '', '2.18');
is($status, 0, 'a release without the common repository remains usable');
is(read_file("$case_dir/add.log"), '', 'a missing common repository is not enabled');
is(read_file("$case_dir/id.log"), "xcat-dep\n",
    'legacy package listings remain unchanged when common is absent');

($status, $case_dir) = run_case(
    'repo-file', 1, 'https://repo.example.invalid/custom/xcat-dep.repo', 'latest'
);
is($status, 0, 'a custom repository file remains supported');
is(read_file("$case_dir/download.log"), '',
    'the common URL is not guessed from a custom repository file');
is(read_file("$case_dir/add.log"), '',
    'a custom repository file does not enable an unrelated repository');

my $local_root = "$tmpdir/local-repository";
make_path("$local_root/common/repodata");
open(my $repomd_fh, '>', "$local_root/common/repodata/repomd.xml") or die $!;
close($repomd_fh) or die $!;
($status, $case_dir) = run_case('local-present', 0, $local_root, 'latest');
is($status, 0, 'a local common repository is accepted');
is(
    read_file("$case_dir/add.log"),
    "$local_root/common xcat-dep-common\n",
    'the local common repository is enabled beside the distribution repository',
);

done_testing();
