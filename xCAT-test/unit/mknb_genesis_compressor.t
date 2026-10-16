#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $root = tempdir(CLEANUP => 1);
$ENV{XCATROOT} = repo_path('xCAT-server');
$ENV{XCATCFG} = "$root/config";
make_path($ENV{XCATCFG});
require(repo_path('xCAT-server/lib/xcat/plugins/mknb.pm'));

for my $case (
    [1, 1, 'lzma -C crc32 -9'],
    [1, 0, 'lzma -C crc32 -9'],
    [0, 1, 'xz --format=lzma -C crc32 -9'],
) {
    my ($lzma, $xz, $expected) = @$case;
    is(xCAT_plugin::mknb::genesis_lzma_command($lzma, $xz), $expected,
        "selects the LZMA command with lzma=$lzma xz=$xz");
}
is(xCAT_plugin::mknb::genesis_lzma_command(0, 0), undef,
    'no LZMA command is selected when neither compressor is available');

done_testing();
