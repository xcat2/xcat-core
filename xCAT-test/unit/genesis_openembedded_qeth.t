#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path slurp_repo_file);

# The systemd unit and the recipes are the artifact. genesis-qeth is shell and is tested in
# xCAT-test/bats/genesis_openembedded_qeth.bats.

my $META = 'xCAT-genesis-base/oe/meta-xcat-genesis';
my $QETH = "$META/recipes-connectivity/xcat-genesis-qeth";

my $service_contents = slurp_repo_file("$QETH/files/xcat-genesis-qeth.service");
like( $service_contents, qr/^ConditionArchitecture=s390x$/m,
    'the activation service is limited to s390x' );
like( $service_contents, qr/^ConditionKernelCommandLine=xcatd$/m,
    'the activation service requires a Genesis boot' );
like( $service_contents, qr/^Before=.*\bNetworkManager\.service\b/m,
    'qeth activation precedes NetworkManager' );
like( $service_contents, qr/^Before=.*\bxcat-genesis-network-state\.service\b/m,
    'qeth activation precedes management network selection' );
like( $service_contents, qr/^TimeoutStartSec=120$/m,
    'a stalled qeth command cannot block network startup indefinitely' );

ok( -f repo_path("$QETH/xcat-genesis-qeth_1.0.bb"),
    'the qeth service has an OpenEmbedded recipe' );
ok( -f repo_path("$META/recipes-support/s390-tools/s390-tools-znetconf_2.41.0.bb"),
    'the minimal znetconf package has an OpenEmbedded recipe' );

done_testing();
