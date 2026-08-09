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

for my $package (qw(xcat xcat-probe xcat-test)) {
    like(
        $contents,
        qr{sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \Q$package\E\b},
        "$package installation is noninteractive"
    );
}

unlike( $contents, qr{yes\s*\|\s*(?:sudo\s+)?apt-get},
    'package input is not piped into maintainer scripts' );

done_testing();
