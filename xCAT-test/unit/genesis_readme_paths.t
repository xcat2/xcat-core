#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Test::More;

# The Genesis README is the build instructions: every command in it is meant to be pasted. A
# path that no longer exists is the whole document failing, and a rename is what breaks it --
# the directory was xCAT-genesis-builder until 2.19 and every path in the README carried that
# name. The file is the artifact here, so reading it is the test.

my $root   = "$FindBin::Bin/../..";
my $readme = "$root/xCAT-genesis-base/README.md";
plan skip_all => 'xCAT-genesis-base/README.md not found' unless -r $readme;

my $text = do { open my $fh, '<', $readme or die "$readme: $!"; local $/; <$fh> };

# Every in-tree path the README names, whatever directory it names -- a rename that half
# happened leaves the old name here, and a pattern matching only the new one would collect
# nothing and pass. .work is the build's own output directory and is not in the checkout.
my %named = map { $_ => 1 } grep { !m{/\.work/} }
    ($text =~ m{(xCAT-[A-Za-z0-9._-]+/[A-Za-z0-9._/-]+)}g);
my @named = sort keys %named;

# A fixed floor, so a pattern that stops matching cannot shrink the plan to nothing and pass.
my $EXPECTED_AT_LEAST = 5;
BAIL_OUT(sprintf('the README names %d in-tree paths, fewer than the %d it should',
                 scalar(@named), $EXPECTED_AT_LEAST))
    if @named < $EXPECTED_AT_LEAST;

plan tests => scalar(@named) + 2;

ok(-e "$root/$_", "the README names $_, and it is there") for @named;

my ($link) = $text =~ m{\]\((\.\./docs/[^)]+)\)};
ok($link, 'the README links to the architecture plan');
ok($link && -e "$root/xCAT-genesis-base/$link",
   'and the link resolves from the directory the README sits in');
