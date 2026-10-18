#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Copy qw(copy);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_binary);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Process qw(run_command);

my $sync = 'build-utils/sync-fips-policy';
my $source = 'build-utils/fips-policy.sh';
my @libraries = ('xCAT-genesis-scripts/usr/lib/xcat/fips.sh', 'xCAT/postscripts/xcatlib.sh');
my ($rc, $output) = run_command($^X, repo_path($sync), '--check');
is($rc, 0, 'committed runtime artifacts match the canonical policy') or diag($output);
is($output, '', 'a current artifact check is quiet');

my $root = tempdir(CLEANUP => 1);
for my $relative ($sync, $source, @libraries) {
    make_path(dirname("$root/$relative"));
    copy(repo_path($relative), "$root/$relative") or die "copy $relative: $!";
}
my %modes = ($libraries[0] => oct('0644'), $libraries[1] => oct('0755'));
for my $relative (@libraries) {
    chmod($modes{$relative}, "$root/$relative") or die "chmod $relative: $!";
}
my @original = map { scalar read_binary("$root/$_") } @libraries;
my $policy = read_binary("$root/$source");
write_binary("$root/$source", $policy . "\nxcat_policy_probe() { printf canonical; }\n");
($rc, $output) = run_command($^X, "$root/$sync", '--check');
is($rc, 1, 'a changed canonical policy invalidates both artifacts');
for my $relative (@libraries) {
    like($output, qr/\Q$relative\E is out of date/, 'check identifies the stale artifact');
}
is_deeply([map { scalar read_binary("$root/$_") } @libraries], \@original,
    'check does not modify stale artifacts');
($rc, $output) = run_command($^X, "$root/$sync", '--write');
is($rc, 0, 'write refreshes both artifacts') or diag($output);
for my $relative (@libraries) {
    is((stat("$root/$relative"))[2] & oct('0777'), $modes{$relative},
        "generation preserves the mode of $relative");
    my $shell = $relative eq $libraries[0] ? 'sh' : 'bash';
    ($rc, $output) = run_command($shell, '-c', '. "$1"; xcat_policy_probe',
        'fips-artifact-test', "$root/$relative");
    is($rc, 0, 'the generated artifact provides the updated policy');
    is($output, 'canonical', 'the generated artifact executes canonical content');
}
my @rendered = map { scalar read_binary("$root/$_") } @libraries;
($rc, $output) = run_command($^X, "$root/$sync", '--write');
is($rc, 0, 'repeated generation succeeds');
is_deeply([map { scalar read_binary("$root/$_") } @libraries], \@rendered,
    'generation is idempotent');
for my $relative (@libraries) {
    is((stat("$root/$relative"))[2] & oct('0777'), $modes{$relative},
        "repeated generation preserves the mode of $relative");
}
($rc, $output) = run_command($^X, "$root/$sync", '--check');
is($rc, 0, 'refreshed artifacts pass the check');

my $unterminated = $policy;
$unterminated =~ s/\n+\z//;
write_binary("$root/$source", $unterminated);
for my $mode (qw(--check --write)) {
    ($rc, $output) = run_command($^X, "$root/$sync", $mode);
    isnt($rc, 0, "$mode rejects a policy without a final newline");
    like($output, qr/FIPS policy must end with a newline/,
        'the error identifies the unterminated policy');
    is_deeply([map { scalar read_binary("$root/$_") } @libraries], \@rendered,
        'an unterminated policy leaves both artifacts untouched');
}

unlink "$root/$source" or die "unlink policy: $!";
($rc, $output) = run_command($^X, "$root/$sync", '--write');
isnt($rc, 0, 'a missing source fails generation');
is_deeply([map { scalar read_binary("$root/$_") } @libraries], \@rendered,
    'a missing source leaves both artifacts untouched');
write_binary("$root/$source", $policy);
write_binary("$root/$libraries[0]", "#!/bin/sh\n");
($rc, $output) = run_command($^X, "$root/$sync", '--write');
isnt($rc, 0, 'a missing insertion block fails generation');
is(read_binary("$root/$libraries[0]"), "#!/bin/sh\n",
    'generation does not replace a malformed artifact');

done_testing();
