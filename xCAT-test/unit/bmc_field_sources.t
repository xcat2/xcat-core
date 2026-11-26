#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../build-utils/lib";
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_binary);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::BuildUtils qw(bmc_field_artifacts sync_bmc_fields);
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Process qw(run_command);

my @scripts = bmc_field_artifacts();
is_deeply(\@scripts,
    ['xCAT-genesis-scripts/usr/bin/bmcsetup', 'xCAT/postscripts/bmcsetup'],
    'both standalone scripts are registered as generated artifacts');
my $source = 'build-utils/bmc-fields.sh';
is_deeply(sync_bmc_fields(root => repo_path('.'))->{stale}, [],
    'both committed scripts match the shared field readers');
my $root = tempdir(CLEANUP => 1);
for my $relative ($source, @scripts, 'build-utils/sync-bmc-fields',
    'build-utils/lib/XCAT/BuildUtils.pm') {
    make_path(dirname("$root/$relative"));
    copy(repo_path($relative), "$root/$relative") or die "copy $relative: $!";
}
my @mode = (oct('0640'), oct('0750'));
for my $i (0 .. $#scripts) {
    chmod($mode[$i], "$root/$scripts[$i]") or die "chmod: $!";
}
my @original = map { scalar read_binary("$root/$_") } @scripts;
my $canonical = read_binary("$root/$source");
write_binary("$root/$source", "$canonical\nprintf 'shared-reader-probe\\n'\n");
my ($rc, $output) = run_command($^X, "$root/build-utils/sync-bmc-fields", '--check');
is($rc, 1, 'the command rejects stale generated readers');
for my $script (@scripts) {
    like($output, qr/\Q$script\E is out of date; run build-utils\/sync-bmc-fields --write/,
        "the diagnostic identifies $script");
}
is_deeply([map { scalar read_binary("$root/$_") } @scripts], \@original,
    'checking drift changes neither script');
my $write = sync_bmc_fields(root => $root, mode => 'write');
is_deeply($write->{written}, \@scripts, 'generation updates both scripts');
is_deeply([map { (stat("$root/$scripts[$_]"))[2] & oct('0777') } 0 .. $#scripts],
    \@mode, 'generation preserves each artifact mode');
is_deeply(sync_bmc_fields(root => $root)->{stale}, [], 'generated artifacts pass the check');
is_deeply(sync_bmc_fields(root => $root, mode => 'write')->{written}, [],
    'a second generation is a no-op');

my @generated = map { scalar read_binary("$root/$_") } @scripts;
for my $case (
    ['empty source', sub { write_binary("$root/$source", '') }, qr/BMC fields is empty/],
    ['unterminated source', sub { write_binary("$root/$source", 'config_field() { :; }') },
        qr/BMC fields must end with a newline/],
    ['missing second block', sub { write_binary("$root/$scripts[1]", "#!/bin/sh\n") },
        qr/\Q$scripts[1]\E must contain one BMC fields block/],
    ['duplicated second block', sub { write_binary("$root/$scripts[1]", $generated[1] x 2) },
        qr/\Q$scripts[1]\E must contain one BMC fields block/],
) {
    write_binary("$root/$source", "$canonical\nprintf stale\n");
    write_binary("$root/$scripts[$_]", $generated[$_]) for 0 .. $#scripts;
    $case->[1]->();
    my @before = map { scalar read_binary("$root/$_") } @scripts;
    for my $mode (qw(check write)) {
        my $result = eval { sync_bmc_fields(root => $root, mode => $mode) };
        is($result, undef, "$mode rejects $case->[0]");
        like($@, $case->[2], 'the error identifies the invalid build input');
        is_deeply([map { scalar read_binary("$root/$_") } @scripts], \@before,
            'invalid input leaves both artifacts untouched');
    }
}
done_testing();
