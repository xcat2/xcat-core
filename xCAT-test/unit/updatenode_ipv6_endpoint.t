#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Test::More;

my $source = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/updatenode.pm";
open(my $fh, '<', $source) or die "Unable to read $source: $!";
my $content = do { local $/; <$fh> };
close($fh);

my @formatted = $content =~ /my \$httpendpoint = xCAT::NetworkUtils->format_host_port\(\$snkey, \$httpport\);/g;
is(
    scalar(@formatted),
    2,
    'postscript and software-update paths format the HTTP endpoint centrally'
);

my @commands = $content =~ /xcatdsklspost [^\n]+ -[mM] '\$httpendpoint' /g;
is(
    scalar(@commands),
    3,
    'all updatenode xcatdsklspost commands quote the IPv6-safe endpoint'
);

unlike(
    $content,
    qr/xcatdsklspost [^\n]+ -[mM] \$snkey:\$httpport /,
    'updatenode does not concatenate an unbracketed IPv6 host and HTTP port'
);

is(
    scalar(() = $content =~ /unless \(defined\(\$httpendpoint\)\)/g),
    2,
    'both endpoint-building paths reject an invalid server authority'
);

done_testing();
