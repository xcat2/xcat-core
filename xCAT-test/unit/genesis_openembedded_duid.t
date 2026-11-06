#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path slurp_repo_file);

# The systemd unit and the recipe are the artifact. genesis-duid is shell and is tested in
# xCAT-test/bats/genesis_openembedded_duid.bats.

my $META    = 'xCAT-genesis-base/oe/meta-xcat-genesis';
my $NETWORK = "$META/recipes-connectivity/xcat-genesis-network";

#---
# =head3 contents_of
#
# Descriptions: Read a repository file, or return an empty string when it is absent.
#
# Arguments:
#   $relative - the path of the file, relative to the checkout
#
# Returns: the contents of the file, or an empty string
#
# A missing file has to fail each assertion that names it. slurp_repo_file dies instead,
# which names no assertion at all.
#---
sub contents_of {
    my ($relative) = @_;

    return -f repo_path($relative) ? slurp_repo_file($relative) : '';
}

my $service_contents = contents_of("$NETWORK/files/xcat-genesis-duid.service");
like( $service_contents, qr/^ConditionKernelCommandLine=xcatd$/m,
    'the client identifier service requires a Genesis boot' );
like( $service_contents, qr/^Before=.*\bNetworkManager\.service\b/m,
    'the client identifier is written before NetworkManager reads conf.d' );
like( $service_contents, qr/^Before=.*\bxcat-genesis-network-state\.service\b/m,
    'the client identifier is written before management network selection' );
like( $service_contents, qr{^ExecStart=/usr/libexec/xcat/genesis-duid$}m,
    'the service runs the client identifier script' );
like( $service_contents, qr/^Type=oneshot$/m,
    'the client identifier is written once per boot' );

my $recipe_contents = contents_of("$NETWORK/xcat-genesis-network_1.0.bb");
like( $recipe_contents, qr/^SYSTEMD_SERVICE:\$\{PN\} = "xcat-genesis-duid\.service"$/m,
    'the recipe enables the client identifier service' );
like( $recipe_contents, qr{\$\{D\}\$\{libexecdir\}/xcat/genesis-duid$}m,
    'the recipe installs the client identifier script' );

ok( -f repo_path("$NETWORK/files/genesis-duid"),
    'the client identifier script is in the OpenEmbedded layer' );

done_testing();
