#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../../perl-xCAT";
require xCAT::Version;

# xcatd tells a real version mismatch (different release) from a same-release
# build difference by comparing xCAT::Version->Release. Release must strip the
# build-specific decoration the build stamps onto the version string, so nodes
# at the same release built from different snapshots are not reported as a
# version mismatch.

my $va = "Version 2.18.2 (git commit aaaaaaaaaaaaaaaa)";
my $vb = "Version 2.18.2 (git commit bbbbbbbbbbbbbbbb)";
my $vc = "Version 2.19.0 (git commit cccccccccccccccc)";

is(xCAT::Version->Release($va), "Version 2.18.2",
    'Release strips the git-commit decoration');
is(xCAT::Version->Release($va), xCAT::Version->Release($vb),
    'the same release built from different snapshots compares equal');
isnt(xCAT::Version->Release($va), xCAT::Version->Release($vc),
    'a real release difference is still reported');

# A string with no decoration is returned unchanged.
is(xCAT::Version->Release("Version 2.18.2"), "Version 2.18.2",
    'a version without decoration is left as is');

done_testing();
