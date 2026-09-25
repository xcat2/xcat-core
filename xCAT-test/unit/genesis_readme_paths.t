#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path slurp_repo_file);

# The Genesis README is the build instructions: every command in it is meant to be pasted. A
# path that no longer exists is the whole document failing, and a rename is what breaks it --
# the directory was xCAT-genesis-builder until 2.19 and every path in the README carried that
# name. The file is the artifact here, so reading it is the test.

my $README = 'xCAT-genesis-base/README.md';
plan skip_all => "$README not found" unless -r repo_path($README);

my $text = slurp_repo_file($README);

# Every in-tree path the README names, whatever directory it names -- a rename that half
# happened leaves the old name here, and a pattern matching only the new one would collect
# nothing and pass. .work is the build's own output directory and is not in the checkout.
my %named = map { $_ => 1 } grep { !m{/\.work/} }
    ($text =~ m{(xCAT-[A-Za-z0-9._-]+/[A-Za-z0-9._/-]+)}g);
my @named = sort keys %named;

# A fixed floor, so a pattern that stops matching cannot shrink the plan to nothing and pass.
my $EXPECTED_AT_LEAST = 5;
die sprintf("the README names %d in-tree paths, fewer than the %d it should\n",
            scalar(@named), $EXPECTED_AT_LEAST)
    if @named < $EXPECTED_AT_LEAST;

ok(-e repo_path($_), "the README names $_, and it is there") for @named;

my ($link) = $text =~ m{\]\((\.\./docs/[^)]+)\)};
ok($link, 'the README links to the architecture plan');
ok($link && -e repo_path("docs/" . ($link =~ s{^\.\./docs/}{}r)),
   'and the link resolves from the directory the README sits in');

done_testing();
