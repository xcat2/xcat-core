#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Copy qw(copy);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_binary);
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Process qw(run_command);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);

plan skip_all => 'build guards require Linux namespaces' unless $^O eq 'linux';
my $root = sandbox_root();
make_path("$root/source", "$root/home");
my ($rc, $output) = run_command('cp', '-a', repo_path('build-utils'), "$root/source/");
die "copy build tools: $output" if $rc;
for my $relative (qw(builddebs.pl buildrpms.pl Version Release),
    'xCAT-genesis-scripts/usr/lib/xcat/fips.sh', 'xCAT/postscripts/xcatlib.sh') {
    make_path(dirname("$root/source/$relative"));
    copy(repo_path($relative), "$root/source/$relative") or die "copy $relative: $!";
}
copy('/etc/os-release', "$root/etc/os-release") or die "copy OS identity: $!";
write_binary("$root/source/Gitepoch", "1600000000\n");
my $source = "$root/source/build-utils/fips-policy.sh";
write_binary($source, read_binary($source) . "\nxcat_policy_probe() { :; }\n");
for my $builder (qw(buildrpms.pl builddebs.pl)) {
    for my $package (qw(xCAT xCAT-genesis-scripts)) {
        ($rc, $output) = sandbox_run($root, {
            writable => {"$root/source" => '/source'},
            env => {HOME => '/fixture/home'}},
            '/bin/sh', '-c', 'cd /source && exec /usr/bin/perl "$@"',
            'fips-build-test', "./$builder", '--package', $package);
        isnt($rc, 0, "$builder rejects stale policy for $package");
        like($output, qr/generated FIPS policy is not current/,
            'the builder reports policy drift before package work');
    }
}

done_testing();
