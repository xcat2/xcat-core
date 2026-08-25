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

require sles;

sub write_file {
    my ($path) = @_;
    open(my $fh, '>', $path) or die "open $path: $!";
    print {$fh} "test\n";
    close($fh) or die "close $path: $!";
}

my $tftp = tempdir(CLEANUP => 1);
make_path("$tftp/xcat");

my $kernel = "$tftp/xcat/genesis.kernel.x86_64";
my $lzma = "$tftp/xcat/genesis.fs.x86_64.lzma";
my $gzip = "$tftp/xcat/genesis.fs.x86_64.gz";
write_file($_) for ($kernel, $lzma);
select(undef, undef, undef, 1.1);
write_file($gzip);

my ($selected_kernel, $selected_initrd) =
  xCAT_plugin::sles::_find_genesis_boot_files($tftp, 'x86_64');
is($selected_kernel, 'genesis.kernel.x86_64',
    'SLES selects the matching Genesis kernel');
is($selected_initrd, 'genesis.fs.x86_64.gz',
    'SLES selects the newer gzip initramfs');

select(undef, undef, undef, 1.1);
write_file($lzma);
($selected_kernel, $selected_initrd) =
  xCAT_plugin::sles::_find_genesis_boot_files($tftp, 'x86_64');
is($selected_initrd, 'genesis.fs.x86_64.lzma',
    'SLES keeps a newer legacy initramfs usable');

unlink($gzip);
($selected_kernel, $selected_initrd) =
  xCAT_plugin::sles::_find_genesis_boot_files($tftp, 'x86_64');
is($selected_initrd, 'genesis.fs.x86_64.lzma',
    'SLES accepts the legacy initramfs by itself');

unlink($lzma);
($selected_kernel, $selected_initrd) =
  xCAT_plugin::sles::_find_genesis_boot_files($tftp, 'x86_64');
is($selected_kernel, undef, 'a missing initramfs yields no partial boot selection');
is($selected_initrd, undef, 'a missing initramfs leaves both paths undefined');

done_testing();
