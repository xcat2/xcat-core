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
require xCAT::Table;
require xCAT::DBobjUtils;

sub label {
    my ($image, $site) = @_;
    return sprintf('image %s and site %s', map({ defined $_ ? "'$_'" : 'unset' } $image, $site));
}

# The image value wins, and the site value applies only when the image does not set one.
for my $case ([ undef, undef, 'http' ], [ '', undef, 'http' ], [ ' ', 'uftp', 'uftp' ], [ undef, 'uftp', 'uftp' ],
    [ undef, ' UFTP ', 'uftp' ], [ 'http', 'uftp', 'http' ], [ 'Uftp', 'http', 'uftp' ], [ 'uftp', undef, 'uftp' ]) {
    my ($image, $site, $expected) = @$case;
    no warnings 'once';
    local %::XCATSITEVALS = (master => '192.0.2.1', defined $site ? (rootimgtransport => $site) : ());
    my ($transport, $error) = xCAT::SvrUtils->rootimg_transport($image);
    is($transport, $expected, label($image, $site) . " select $expected");
    is($error, undef, label($image, $site) . ' give no error');
}

# Another value is refused, and the error names the attribute that holds it.
for my $case ([ 'tftp', 'uftp', qr/^The rootimgtransport attribute of the image is 'tftp'/ ],
    [ undef, 'multicast', qr/^site\.rootimgtransport is 'multicast'/ ], [ '', 'yes', qr/^site\.rootimgtransport is 'yes'/ ]) {
    my ($image, $site, $message) = @$case;
    no warnings 'once';
    local %::XCATSITEVALS = (master => '192.0.2.1', rootimgtransport => $site);
    my ($transport, $error) = xCAT::SvrUtils->rootimg_transport($image);
    is($transport, undef, label($image, $site) . ' select no transport');
    like($error // '', $message, label($image, $site) . ' name the wrong value');
}

# The osimage object shows the attribute that the linuximage table holds.
xCAT::Table->new('osimage', -create => 1)->setAttribs({ imagename => 'image' },
    { imagetype => 'linux', provmethod => 'netboot', osvers => 'rhels9.6', osarch => 'x86_64', profile => 'compute' });
my (undef, $error) = xCAT::Table->new('linuximage', -create => 1)->setAttribs({ imagename => 'image' }, { rootimgtransport => 'uftp' });
is($error, undef, 'the linuximage table stores rootimgtransport');
my %objects = xCAT::DBobjUtils->getobjdefs({ image => 'osimage' });
is($objects{image}{rootimgtransport}, 'uftp', 'the osimage object shows rootimgtransport');

done_testing();
