#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Slurper qw(read_lines);
use Test::More;

# A case that no bundle names is a case no run selects. The six SELinux cases were in no
# bundle and in no pipeline conf, so none of them had ever run, and eight checks that
# could never pass went unnoticed for that reason.
my $root = "$FindBin::Bin/../..";
my $dir  = "$root/xCAT-test/autotest/testcase/selinux";

my @cases;
foreach my $file (sort glob("$dir/cases*")) {
    push @cases, map { /^start:(\S+)/ ? $1 : () } read_lines($file);
}
ok(scalar(@cases) >= 6, "the selinux testcase files declare @{[scalar @cases]} cases");

my %bundled;
foreach my $bundle (sort glob("$root/xCAT-test/autotest/bundle/*.bundle")) {
    $bundled{$_} = 1 for grep { /\S/ } read_lines($bundle);
}
ok(scalar(keys %bundled) > 100, "the bundles name @{[scalar keys %bundled]} cases in total");

my @orphans = grep { !$bundled{$_} } @cases;
is_deeply(\@orphans, [], 'every selinux case is named by a bundle');

my @mn = grep { /\S/ } read_lines("$root/xCAT-test/autotest/bundle/selinux_mn.bundle");
my %mn = map { $_ => 1 } @mn;
foreach my $case (@cases) {
    next unless $case =~ /_cn_/;
    ok(!$mn{$case}, "$case needs a compute node, so the management node bundle leaves it out");
}

done_testing();
