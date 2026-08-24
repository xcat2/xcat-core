#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $source = "$FindBin::Bin/../../xCAT-server/sbin/xcatconfig";
open(my $source_fh, '<', $source) or die "open $source: $!";
my $content = do { local $/; <$source_fh> };
close($source_fh) or die "close $source: $!";

my ($routine) = $content =~ /^(sub _installed_genesis_architectures\s*\{.*?^\})/ms;
BAIL_OUT('could not extract _installed_genesis_architectures from xcatconfig')
  unless $routine;
eval $routine;
BAIL_OUT("could not load _installed_genesis_architectures: $@") if $@;

my $tmpdir = tempdir(CLEANUP => 1);
make_path(
    "$tmpdir/share/xcat/netboot/genesis/ppc64/fs",
    "$tmpdir/share/xcat/netboot/genesis/x86_64/fs",
    "$tmpdir/share/xcat/netboot/genesis-openembedded/aarch64",
    "$tmpdir/share/xcat/netboot/genesis-openembedded/ppc64le",
    "$tmpdir/share/xcat/netboot/genesis-openembedded/x86_64",
);

is_deeply(
    [ _installed_genesis_architectures($tmpdir) ],
    [ qw(aarch64 ppc64 ppc64le x86_64) ],
    'xcatconfig finds exact OpenEmbedded architectures and installed legacy images',
);

make_path("$tmpdir/share/xcat/netboot/genesis-openembedded/unsupported");
is_deeply(
    [ _installed_genesis_architectures($tmpdir) ],
    [ qw(aarch64 ppc64 ppc64le x86_64) ],
    'unknown directories are not passed to mknb',
);

done_testing();
