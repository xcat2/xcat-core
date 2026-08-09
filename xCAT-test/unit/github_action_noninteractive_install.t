#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

my $script = File::Spec->catfile(
    $FindBin::Bin, '..', '..', 'github_action_xcat_test.pl'
);
open( my $fh, '<', $script ) or die "Unable to read $script: $!";
my $contents = do { local $/; <$fh> };
close($fh);

my $workflow = File::Spec->catfile(
    $FindBin::Bin, '..', '..', '.github', 'workflows', 'xcat_test.yml'
);
open( my $workflow_fh, '<', $workflow )
  or die "Unable to read $workflow: $!";
my $workflow_contents = do { local $/; <$workflow_fh> };
close($workflow_fh);

for my $package (qw(xcat xcat-probe xcat-test)) {
    like(
        $contents,
        qr{sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \Q$package\E\b},
        "$package installation is noninteractive"
    );
}

unlike( $contents, qr{yes\s*\|\s*(?:sudo\s+)?apt-get},
    'package input is not piped into maintainer scripts' );

like(
    $workflow_contents,
    qr{sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y\b},
    'workflow dependency installation is noninteractive'
);

done_testing();
