#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(slurp_repo_file);

# The systemd unit and the recipe are the artifact. genesis-action is shell and is tested in
# xCAT-test/bats/genesis_openembedded_actions.bats.

my $INIT = 'xCAT-genesis-base/oe/meta-xcat-genesis/recipes-core/xcat-genesis-init';

my $service = slurp_repo_file("$INIT/files/xcat-genesis-action.service");
like( $service, qr/^ConditionKernelCommandLine=xcatd$/m,
    'action execution requires an xCAT boot' );
like( $service, qr/^Requires=xcat-genesis-register\.service$/m,
    'action execution requires registration' );
unlike( $service, qr/^Restart=/m,
    'a fatal action remains failed for diagnosis' );
unlike( $service, qr/^StartLimitIntervalSec=/m,
    'the action service has no unlimited restart policy' );

my $recipe = slurp_repo_file("$INIT/xcat-genesis-init_1.0.bb");
like( $recipe, qr/\bxcat-genesis-discovery\b/,
    'action runtime includes discovery support' );
like( $recipe, qr/file:\/\/genesis-action/,
    'action executor is packaged' );
like( $recipe, qr/file:\/\/genesis-network-refresh/,
    'discovery network refresh is packaged' );
like( $recipe, qr/\bxcat-genesis-action\.service\b/,
    'action service is enabled' );

done_testing();
