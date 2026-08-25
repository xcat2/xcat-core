#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

BEGIN {
    $ENV{XCATROOT} = "$FindBin::Bin/../../xCAT-server";
}

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins";

require anaconda;

sub write_file {
    my ($path) = @_;
    open(my $fh, '>', $path) or die "open $path: $!";
    print {$fh} "test\n";
    close($fh) or die "close $path: $!";
}

my $tftp = tempdir(CLEANUP => 1);
make_path("$tftp/xcat");
for my $path (qw(
  genesis.kernel.ppc64
  genesis.kernel.ppc64le
  genesis.fs.ppc64.lzma
  genesis.fs.ppc64le.gz
)) {
    write_file("$tftp/xcat/$path");
}

my ($kernel, $initrd) =
  xCAT_plugin::anaconda::_find_genesis_boot_files($tftp, 'ppc64');
is($kernel, 'genesis.kernel.ppc64',
    'the legacy POWER kernel lookup is an exact architecture match');
is($initrd, 'genesis.fs.ppc64.lzma',
    'the legacy POWER initramfs lookup is an exact architecture match');
unlike($kernel, qr/\n/, 'the selected kernel path contains one file');

($kernel, $initrd) =
  xCAT_plugin::anaconda::_find_genesis_boot_files($tftp, 'ppc64le');
is($kernel, 'genesis.kernel.ppc64le',
    'the OpenEmbedded POWER kernel remains independently selectable');
is($initrd, 'genesis.fs.ppc64le.gz',
    'the OpenEmbedded POWER initramfs remains independently selectable');

unlink("$tftp/xcat/genesis.fs.ppc64le.gz");
($kernel, $initrd) =
  xCAT_plugin::anaconda::_find_genesis_boot_files($tftp, 'ppc64le');
is($kernel, undef, 'a missing initramfs yields no partial boot selection');
is($initrd, undef, 'a missing initramfs leaves both paths undefined');

done_testing();
