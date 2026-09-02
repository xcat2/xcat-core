#!/usr/bin/env perl
# The genesis specs name their package after the target arch: xCAT-genesis-scripts-<tarch> and
# xCAT-genesis-base-<tarch>. %{tarch} comes from an %ifarch ladder, and an arch missing from that
# ladder leaves the macro UNEXPANDED instead of failing: rpm then builds a package literally named
# "xCAT-genesis-scripts-%{tarch}", buildrpms.pl cannot find the srpm it asked for, and the whole
# target build dies with a "Cannot find/open srpm" that names the right file.
#
# Expand each spec with rpmspec for every arch xCAT supports and assert the Name carries that arch.
use strict;
use warnings;

use FindBin;
use Test::More;

my $root = "$FindBin::Bin/../..";

sub command_exists { my ($c) = @_; return system("command -v $c >/dev/null 2>&1") == 0 }

plan skip_all => 'rpmspec is not installed' unless command_exists('rpmspec');

# arch under test => the tarch the spec must resolve it to (x86 and ppc64 are historical names
# genesis keeps; see genesis_tarch_from_targetarch in buildrpms.pl).
my %tarch = (
    x86_64  => 'x86_64',
    i686    => 'x86',
    ppc64le => 'ppc64',
    aarch64 => 'aarch64',
    riscv64 => 'riscv64',
);

my %spec = (
    'xCAT-genesis-scripts' => "$root/xCAT-genesis-scripts/xCAT-genesis-scripts.spec",
    'xCAT-genesis-base'    => "$root/xCAT-genesis-builder/xCAT-genesis-base.spec",
);

for my $pkg (sort keys %spec) {
    my $spec = $spec{$pkg};
    ok(-f $spec, "$pkg spec is present") or next;
    for my $arch (sort keys %tarch) {
        my $name = `rpmspec --target $arch -q --qf '%{NAME}' --define 'version 2.19.0' --define 'release snap0' @{[quotemeta $spec]} 2>/dev/null`;
        chomp $name;
        is($name, "$pkg-$tarch{$arch}", "$pkg on $arch is named $pkg-$tarch{$arch}");
        unlike($name, qr/%\{/, "$pkg on $arch leaves no unexpanded macro in its name");
    }
}

done_testing();
