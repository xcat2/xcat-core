#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../build-utils/lib";
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use Test::More;
use XCAT::BuildUtils qw(netboot_policy_artifacts);
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Process qw(run_command);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);

plan skip_all => 'build guards require Linux namespaces' unless $^O eq 'linux';
my $root = sandbox_root();
make_path("$root/source", "$root/home");
my ($rc, $output) = run_command('cp', '-a', repo_path('build-utils'), "$root/source/");
die "copy build tools: $output" if $rc;
my @profiles = netboot_policy_artifacts();
for my $relative (qw(builddebs.pl buildrpms.pl Version Release), @profiles) {
    make_path(dirname("$root/source/$relative"));
    copy(repo_path($relative), "$root/source/$relative") or die "copy $relative: $!";
}
copy('/etc/os-release', "$root/etc/os-release") or die $!;
write_text("$root/source/Gitepoch", "1600000000\n");
my $checker = "$root/source/build-utils/sync-netboot-policy";
($rc, $output) = run_command($^X, $checker, '--check');
is($rc, 0, 'the shipped profiles pass the policy check') or diag($output);

my $policy = "$root/source/build-utils/netboot-policy.sh";
write_text($policy, read_text($policy) . <<'SH');

xcat_disable_image_selinux()
{
    printf 'updated policy\n' >"$1/policy-probe"
}
SH
($rc, $output) = run_command($^X, $checker, '--check');
is($rc, 1, 'the checker rejects stale profiles');
for my $builder (qw(buildrpms.pl builddebs.pl)) {
    ($rc, $output) = sandbox_run($root, {
        writable => {"$root/source" => '/source'}, env => {HOME => '/fixture/home'}},
        '/bin/sh', '-c', 'cd /source && exec /usr/bin/perl "$@"',
        'netboot-build-test', "./$builder", '--package', 'xCAT-server');
    isnt($rc, 0, "$builder rejects stale netboot policy");
    like($output, qr/generated netboot policy is not current/, 'reports drift before package work');
    like($output, qr/\Q$_\E is out of date/, "identifies stale $_") for @profiles;
}
($rc, $output) = run_command($^X, $checker, '--write');
is($rc, 0, 'regenerates all profile copies') or diag($output);
($rc, $output) = run_command($^X, $checker, '--check');
is($rc, 0, 'regenerated profiles pass the check') or diag($output);
for my $profile (@profiles) {
    my $node = sandbox_root();
    copy("$root/source/$profile", "$node/postinstall") or die $!;
    ($rc, $output) = sandbox_run($node, {}, '/bin/sh', '/fixture/postinstall', '/target', 'rhels10', 'x86_64', 'compute');
    is($rc, 0, "$profile executes without its build source") or diag($output);
    is(-f "$node/target/policy-probe" ? read_text("$node/target/policy-probe") : undef,
        "updated policy\n", 'the complete profile executes the regenerated policy');
}

done_testing();
