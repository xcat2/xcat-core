#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(slurp_repo_file);

# The recipe and the systemd unit are the artifact. genesis-metrics and oe/report are shell and
# are tested in xCAT-test/bats/genesis_openembedded_metrics.bats.

my $INIT = 'xCAT-genesis-base/oe/meta-xcat-genesis/recipes-core/xcat-genesis-init';

my $recipe_contents = slurp_repo_file("$INIT/xcat-genesis-init_1.0.bb");
like( $recipe_contents, qr/file:\/\/genesis-metrics/,
    'metrics collector is included in the init package' );
like( $recipe_contents, qr/SYSTEMD_SERVICE.*?xcat-genesis-metrics\.service/s,
    'metrics service is enabled with the init package' );

my $service_contents = slurp_repo_file("$INIT/files/xcat-genesis-metrics.service");
like( $service_contents,
    qr/Requires=xcat-genesis-register\.service\nAfter=xcat-genesis-register\.service/,
    'metrics are captured after successful registration' );
like( $service_contents,
    qr{ExecStart=/usr/libexec/xcat/genesis-metrics --output /run/xcat/metrics\.env},
    'metrics are stored in the runtime state directory' );

done_testing();
