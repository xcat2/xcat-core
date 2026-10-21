#!/usr/bin/env perl
# XCAT::BuildUtils FIPS policy generation.
#
# buildrpms.pl and builddebs.pl call sync_fips_policy before they package xCAT or
# xCAT-genesis-scripts, so a runtime library that no longer matches the canonical
# policy cannot reach a package. Every assertion below runs the sub and reads its
# answer; none of them runs the build-utils/sync-fips-policy script, which is a
# thin caller with nothing of its own to measure.
use strict;
use warnings;

use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_binary);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../build-utils/lib";
use Test::More;
use XCAT::BuildUtils qw(fips_policy_artifacts fips_policy_plan sync_fips_policy);
use XCAT::Test::File qw(repo_path);

my $source = 'build-utils/fips-policy.sh';
my @libraries = fips_policy_artifacts();
is_deeply(\@libraries,
    ['xCAT-genesis-scripts/usr/lib/xcat/fips.sh', 'xCAT/postscripts/xcatlib.sh'],
    'both runtime libraries carry a generated policy block');

# The committed tree. A stale block here would ship in a package.
my $committed = sync_fips_policy(root => repo_path('.'), mode => 'check');
is_deeply($committed->{stale}, [], 'the committed libraries match the canonical policy');
is_deeply($committed->{messages}, [], 'a current check reports no diagnostic');
is_deeply($committed->{written}, [], 'a check writes nothing');
is($committed->{mode}, 'check', 'the answer names the mode that ran');

# Everything below runs against a copy, so a failed assertion cannot leave the
# checkout's own libraries rewritten.
my $root = tempdir(CLEANUP => 1);
for my $relative ($source, @libraries) {
    make_path(dirname("$root/$relative"));
    copy(repo_path($relative), "$root/$relative") or die "copy $relative: $!";
}
my %mode = ($libraries[0] => oct('0644'), $libraries[1] => oct('0755'));
chmod($mode{$_}, "$root/$_") or die "chmod $_: $!" for @libraries;
my @committed_text = map { scalar read_binary("$root/$_") } @libraries;

my $policy = read_binary("$root/$source");
write_binary("$root/$source", $policy . "\nxcat_policy_probe() { printf canonical; }\n");

# A plan reports what generation would write and writes nothing itself.
my $plan = fips_policy_plan(root => $root);
is_deeply([map { $_->{relative} } @{$plan->{artifacts}}], \@libraries,
    'the plan covers both libraries in generation order');
is_deeply([map { $_->{stale} } @{$plan->{artifacts}}], [1, 1],
    'a changed policy makes both libraries stale');
like($plan->{block}, qr/xcat_policy_probe/, 'the block carries the changed policy');
for my $artifact (@{$plan->{artifacts}}) {
    like($artifact->{rendered}, qr/xcat_policy_probe/,
        "the plan renders the changed policy into $artifact->{relative}");
    unlike($artifact->{current}, qr/xcat_policy_probe/,
        "the plan leaves $artifact->{relative} unchanged on disk");
}
is_deeply([map { scalar read_binary("$root/$_") } @libraries], \@committed_text,
    'a plan writes nothing');

my $check = sync_fips_policy(root => $root, mode => 'check');
is_deeply($check->{stale}, \@libraries, 'a check names every stale library');
is_deeply($check->{written}, [], 'a check writes nothing when libraries are stale');
is(scalar @{$check->{messages}}, scalar @libraries, 'a check reports one diagnostic per stale library');
for my $relative (@libraries) {
    like((grep { /\Q$relative\E/ } @{$check->{messages}})[0],
        qr/is out of date; run build-utils\/sync-fips-policy --write/,
        "the diagnostic for $relative says how to fix it");
}
is_deeply([map { scalar read_binary("$root/$_") } @libraries], \@committed_text,
    'a check does not modify a stale library');

my $write = sync_fips_policy(root => $root, mode => 'write');
is($write->{mode}, 'write', 'the answer names the write mode');
is_deeply($write->{written}, \@libraries, 'a write names every library it rewrote');
is_deeply($write->{stale}, \@libraries, 'a write reports which libraries were stale');
is_deeply([map { scalar read_binary("$root/$_") } @libraries],
    [map { $_->{rendered} } @{$plan->{artifacts}}],
    'a write stores exactly what the plan rendered');
is_deeply([map { (stat("$root/$_"))[2] & oct('0777') } @libraries],
    [map { $mode{$_} } @libraries], 'a write preserves the mode of each library');

my @generated = map { scalar read_binary("$root/$_") } @libraries;
my $again = sync_fips_policy(root => $root, mode => 'write');
is_deeply($again->{stale}, [], 'a second write finds nothing stale');
is_deeply($again->{written}, [], 'a second write rewrites nothing');
is_deeply([map { scalar read_binary("$root/$_") } @libraries], \@generated,
    'generation is idempotent');
is_deeply([map { (stat("$root/$_"))[2] & oct('0777') } @libraries],
    [map { $mode{$_} } @libraries], 'a second write preserves the mode of each library');
is_deeply(sync_fips_policy(root => $root, mode => 'check')->{stale}, [],
    'a check passes on generated libraries');

# Every rejected input leaves both libraries alone, in both modes. A write that
# stopped half way would ship one library generated and one stale.
for my $case (
    ['a policy with no final newline', sub { my $text = $policy; $text =~ s/\n+\z//;
            write_binary("$root/$source", $text) }, qr/FIPS policy must end with a newline/],
    ['an empty policy', sub { write_binary("$root/$source", '') },
        qr/FIPS policy is empty/],
    ['a missing policy', sub { unlink "$root/$source" or die "unlink: $!" },
        qr/\Qfips-policy.sh\E/],
    ['a library with no policy block', sub { write_binary("$root/$source", $policy);
            write_binary("$root/$libraries[0]", "#!/bin/sh\n") },
        qr/\Q$libraries[0]\E must contain one FIPS policy block/],
    ['a library with two policy blocks', sub {
            write_binary("$root/$libraries[0]", $generated[0] . $generated[0]) },
        qr/\Q$libraries[0]\E must contain one FIPS policy block/],
    ['a library that is a symbolic link', sub {
            write_binary("$root/$libraries[0]", $generated[0]);
            rename("$root/$libraries[0]", "$root/$libraries[0]-real") or die "rename: $!";
            symlink("$root/$libraries[0]-real", "$root/$libraries[0]") or die "symlink: $!" },
        qr/\Q$libraries[0]\E must be a regular file/],
) {
    my ($name, $break, $expected) = @{$case};
    $break->();
    my @before = map { -l "$root/$_" ? '' : scalar read_binary("$root/$_") } @libraries;
    for my $mode (qw(check write)) {
        my $answer = eval { sync_fips_policy(root => $root, mode => $mode) };
        is($answer, undef, "$mode rejects $name");
        like($@, $expected, "the $mode error identifies $name");
    }
    is_deeply([map { -l "$root/$_" ? '' : scalar read_binary("$root/$_") } @libraries],
        \@before, "$name leaves both libraries untouched");
}

unlink "$root/$libraries[0]" or die "unlink link: $!";
rename("$root/$libraries[0]-real", "$root/$libraries[0]") or die "restore: $!";
for my $mode ('', 'Write', 'check ', 'rewrite') {
    my $answer = eval { sync_fips_policy(root => $root, mode => $mode) };
    is($answer, undef, "mode '$mode' is rejected");
    like($@, qr/FIPS policy mode must be check or write/,
        "the error names the modes that exist, not '$mode'");
}
my $answer = eval { fips_policy_plan() };
is($answer, undef, 'a plan without a root is rejected');
like($@, qr/fips_policy_plan needs a root/, 'the error asks for a root');

done_testing();
