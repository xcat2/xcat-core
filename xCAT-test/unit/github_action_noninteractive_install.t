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
        qr{sudo timeout \d+ env DEBIAN_FRONTEND=noninteractive apt-get (?:-o \S+ )*install -y \Q$package\E },
        "$package installation is noninteractive and bounded"
    );
}

unlike( $contents, qr{yes\s*\|\s*(?:sudo\s+)?apt-get},
    'package input is not piped into maintainer scripts' );

like(
    $workflow_contents,
    qr{sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y\b},
    'workflow dependency installation is noninteractive'
);

like(
    $contents,
    qr{next if\(\$file =~ /\\/opt\\/xcat\\/share\\/xcat\\/tools\\/autotest\\/unit\\//\);},
    'installed source-layout tests are excluded from syntax checks'
);

done_testing();
