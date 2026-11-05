#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";
use Test::More;
use imgutils;

for my $case (
    [ [qw(6.8.0-99-generic 6.8.0-100-generic)], '6.8.0-100-generic', 'an ABI of 100 is newer than an ABI of 99' ],
    [ [qw(6.10.0-1-generic 6.9.0-1-generic)],   '6.10.0-1-generic',  'kernel 6.10 is newer than kernel 6.9' ],
    [ [qw(6.8.0-100-generic 7.0.0-42-generic)], '7.0.0-42-generic',  'a newer kernel wins over a larger ABI' ],
    [ [qw(7.0.0-42-generic)],                   '7.0.0-42-generic',  'an image with one kernel gets that kernel' ],
) {
    my ($releases, $newest, $label) = @$case;
    is(imgutils::newest_kernel_version(@$releases), $newest, $label);
    is(imgutils::newest_kernel_version(reverse @$releases), $newest, "$label, in either order");
}

is(imgutils::newest_kernel_version(), undef, 'an image without a kernel gets no kernel release');

done_testing();
