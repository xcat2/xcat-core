#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(slurp_repo_file);

# The recipe is the artifact. The signer, the exporter and genesis-sysext are shell and are
# tested in xCAT-test/bats/genesis_openembedded_extensions.bats.

my $recipe_text = slurp_repo_file(
    'xCAT-genesis-base/oe/meta-xcat-genesis/recipes-core/xcat-genesis-extensions/xcat-genesis-extensions_1.0.bb');
like( $recipe_text, qr/\$\{localstatedir\}\/lib\/xcat\/genesis\/extensions/,
    'the image creates the extension staging directory' );
like( $recipe_text, qr/^XCAT_GENESIS_EXTENSION_BUNDLE \?\?= ""$/m,
    'site layers can stage an exported extension bundle' );

done_testing();
