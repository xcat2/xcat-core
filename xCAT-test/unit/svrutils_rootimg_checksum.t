#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Temp qw(tempdir);
use Test::More;

my $fixture = tempdir(CLEANUP => 1);
$ENV{XCATCFG} = "SQLite:$fixture";
require xCAT::SvrUtils;

# The image value wins, and the site value applies only when the image does not set one.
for my $case ([ undef, undef, 1 ], [ '', undef, 1 ], [ undef, 'no', 0 ], [ undef, '0', 0 ], [ undef, 'yes', 1 ],
    [ 'no', undef, 0 ], [ 'NO', 'yes', 0 ], [ ' 0 ', 'yes', 0 ], [ 'yes', 'no', 1 ], [ '1', 'no', 1 ], [ '', 'no', 0 ]) {
    my ($image, $site, $enabled) = @$case;
    no warnings 'once';
    local %::XCATSITEVALS = (master => '192.0.2.1', defined $site ? (rootimgchecksum => $site) : ());
    is(xCAT::SvrUtils->rootimg_checksum_enabled($image) ? 1 : 0, $enabled,
        sprintf('image %s and site %s turn the check %s', map({ defined $_ ? "'$_'" : 'unset' } $image, $site), $enabled ? 'on' : 'off'));
}

done_testing();
