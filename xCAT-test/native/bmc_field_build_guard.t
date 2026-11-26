#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../build-utils/lib";
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_binary);
use Test::More;
use XCAT::BuildUtils qw(bmc_field_artifacts);
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Process qw(run_command);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);

plan skip_all => 'build guards require Linux namespaces' unless $^O eq 'linux';
my $root = sandbox_root();
make_path("$root/source", "$root/home");
my ($rc, $output) = run_command('cp', '-a', repo_path('build-utils'), "$root/source/");
die "copy build tools: $output" if $rc;
my @scripts = bmc_field_artifacts();
for my $relative (qw(builddebs.pl buildrpms.pl Version Release), @scripts,
    'xCAT-genesis-scripts/usr/lib/xcat/fips.sh', 'xCAT/postscripts/xcatlib.sh') {
    make_path(dirname("$root/source/$relative"));
    copy(repo_path($relative), "$root/source/$relative") or die "copy $relative: $!";
}
copy('/etc/os-release', "$root/etc/os-release") or die "copy OS identity: $!";
write_binary("$root/source/Gitepoch", "1600000000\n");
my $source = "$root/source/build-utils/bmc-fields.sh";
write_binary($source, read_binary($source) . "\nprintf 'shared-reader-probe\\n'\n");
my @before = map { scalar read_binary("$root/source/$_") } @scripts;
for my $builder (qw(buildrpms.pl builddebs.pl)) {
    for my $package (qw(xCAT xCAT-genesis-scripts)) {
        ($rc, $output) = sandbox_run($root, {
            writable => {"$root/source" => '/source'},
            env => {HOME => '/fixture/home'}},
            '/bin/sh', '-c', 'cd /source && exec /usr/bin/perl "$@"',
            'bmc-build-test', "./$builder", '--package', $package);
        isnt($rc, 0, "$builder rejects stale readers for $package");
        like($output, qr/generated BMC fields are not current/,
            'the builder reports reader drift before package work');
        for my $script (@scripts) {
            like($output, qr/\Q$script\E is out of date/,
                "$builder identifies stale $script for $package");
        }
        is_deeply([map { scalar read_binary("$root/source/$_") } @scripts], \@before,
            'the build guard changes neither runtime script');
    }
}
($rc, $output) = run_command($^X, "$root/source/build-utils/sync-bmc-fields", '--write');
is($rc, 0, 'the generation command refreshes the isolated source scripts') or die $output;
write_binary("$root/bin/ipmitool", "#!/bin/sh\nexit 1\n");
chmod 0755, "$root/bin/ipmitool" or die "chmod IPMI fixture: $!";
for my $script (@scripts) {
    ($rc, $output) = sandbox_run($root,
        {read_only => {"$root/source" => '/source'}},
        '/bin/bash', "/source/$script");
    is($rc, 1, "$script stops at its unavailable IPMI tool");
    like($output, qr/^shared-reader-probe$/m,
        "$script executes the newly generated block inside the sandbox");
}
done_testing();
