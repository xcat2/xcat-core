#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path remove_tree);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $source = "$FindBin::Bin/../../xCAT-server/sbin/xcatconfig";
open(my $source_fh, '<', $source) or die "open $source: $!";
my $content = do { local $/; <$source_fh> };
close($source_fh) or die "close $source: $!";

my @routines;
for my $name (qw(_installed_genesis_architectures _genesis_architectures_to_build)) {
    my ($routine) = $content =~ /^(sub \Q$name\E\s*\{.*?^\})/ms;
    BAIL_OUT("could not extract $name from xcatconfig") unless $routine;
    push(@routines, $routine);
}
eval join("\n", @routines); ## no critic (BuiltinFunctions::ProhibitStringyEval)
BAIL_OUT("could not load Genesis architecture helpers: $@") if $@;

my $tmpdir = tempdir(CLEANUP => 1);
make_path(
    "$tmpdir/share/xcat/netboot/genesis/ppc64/fs",
    "$tmpdir/share/xcat/netboot/genesis/x86_64/fs",
    "$tmpdir/share/xcat/netboot/genesis-openembedded/aarch64",
    "$tmpdir/share/xcat/netboot/genesis-openembedded/ppc64le",
    "$tmpdir/share/xcat/netboot/genesis-openembedded/x86_64",
);
my $symlink_target = "$tmpdir/openembedded-riscv64";
make_path($symlink_target);
symlink(
    $symlink_target,
    "$tmpdir/share/xcat/netboot/genesis-openembedded/riscv64",
) or die "create OpenEmbedded directory symlink: $!";

is_deeply(
    [ _installed_genesis_architectures($tmpdir) ],
    [ qw(aarch64 ppc64 ppc64le riscv64 x86_64) ],
    'xcatconfig finds exact OpenEmbedded architectures, symlinks, and legacy images',
);

is_deeply(
    [ _genesis_architectures_to_build($tmpdir, 0) ],
    [ qw(aarch64 ppc64le riscv64 x86_64) ],
    'an ordinary xCAT update rebuilds only installed OpenEmbedded images',
);
is_deeply(
    [ _genesis_architectures_to_build($tmpdir, 1) ],
    [ qw(aarch64 ppc64 ppc64le riscv64 x86_64) ],
    'a legacy package trigger rebuilds every installed Genesis image',
);

make_path("$tmpdir/share/xcat/netboot/genesis-openembedded/unsupported");
is_deeply(
    [ _installed_genesis_architectures($tmpdir) ],
    [ qw(aarch64 ppc64 ppc64le riscv64 x86_64) ],
    'unknown directories are not passed to mknb',
);

remove_tree("$tmpdir/share/xcat/netboot/genesis/ppc64");
my $legacy_target = "$tmpdir/legacy-ppc64";
make_path("$legacy_target/fs");
symlink($legacy_target, "$tmpdir/share/xcat/netboot/genesis/ppc64")
  or die "create legacy directory symlink: $!";
is_deeply(
    [ _installed_genesis_architectures($tmpdir) ],
    [ qw(aarch64 ppc64 ppc64le riscv64 x86_64) ],
    'legacy Genesis directory symlinks remain supported',
);

done_testing();
