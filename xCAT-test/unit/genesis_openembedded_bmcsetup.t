#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(slurp_repo_file);

# The recipes are the artifact: bitbake reads these lines to build the image. The wrapper and
# the legacy BMC scripts are shell and are tested in xCAT-test/bats/genesis_openembedded_bmcsetup.bats.

my $META = 'xCAT-genesis-base/oe/meta-xcat-genesis';
my $recipe_text = slurp_repo_file(
    "$META/recipes-xcat/xcat-genesis-bmcsetup/xcat-genesis-bmcsetup_1.0.bb");

for my $source (qw(bmcsetup getipmi remoteimmsetup updateflag.awk)) {
    like( $recipe_text, qr/file:\/\/\Q$source\E\b/,
        "$source is sourced from the existing Genesis implementation" );
}
like( $recipe_text,
    qr{\$\{libexecdir\}/xcat/genesis/actions/bmcsetup},
    'bmcsetup is installed as an approved action' );
like( $recipe_text, qr/\bxcat-genesis-discovery\b/,
    'the BMC action uses the credential callback socket' );
like( $recipe_text, qr/\bgawk\b/,
    'the legacy status callback has its required awk implementation' );
like( slurp_repo_file("$META/recipes-core/images/xcat-genesis-image.bb"),
    qr/\bxcat-genesis-bmcsetup\b/,
    'the base Genesis image includes BMC setup' );

done_testing();
