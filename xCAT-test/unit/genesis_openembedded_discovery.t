#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(slurp_repo_file);

# The recipes are the artifact. The discovery scripts and the UDP sender run in the Genesis
# image and are tested in xCAT-test/bats/genesis_openembedded_discovery.bats.

my $META = 'xCAT-genesis-base/oe/meta-xcat-genesis';

my $recipe = slurp_repo_file(
    "$META/recipes-xcat/xcat-genesis-discovery/xcat-genesis-discovery_1.0.bb");
like( $recipe, qr/^RDEPENDS:\$\{PN\} = "bash coreutils gzip iproute2 openssl-bin util-linux-logger util-linux-lsblk"$/m,
    'discovery dependencies are explicit' );
like( $recipe, qr/xcat-genesis-discovery\.socket/,
    'discovery callback socket is packaged' );
like( $recipe, qr/xcat-genesis-credential\.socket/,
    'credential callback socket is packaged' );
like( $recipe, qr/\$\{CC\}.*genesis-udp-send\.c/s,
    'discovery UDP sender is compiled for the target' );
like( $recipe, qr/-std=c17.*-Werror/s,
    'discovery UDP sender uses the strict C build contract' );
like( $recipe, qr{\$\{libexecdir\}/xcat/genesis-udp-send},
    'discovery UDP sender is packaged' );

like( slurp_repo_file("$META/recipes-core/images/xcat-genesis-image.bb"),
    qr/\bxcat-genesis-discovery\b/,
    'base image includes the discovery client' );

done_testing();
