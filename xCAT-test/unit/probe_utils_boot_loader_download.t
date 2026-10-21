#!/usr/bin/env perl
# xcatprobe osdeploy marks the boot loader stage when a node fetches its loader over TFTP. The file
# names below are the ones the TFTP log shows for each loader, and for downloads that are not one.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-probe/lib/perl";

use Test::More;

require probe_utils;

my @loaders = (
    'xcat/xnba.kpxe',
    'xcat/xnba.efi',
    'xcat/ipxe/i386/undionly.kpxe',
    'xcat/ipxe/x86_64-sb/snponly-shim.efi',
    'xcat/ipxe/x86_64-sb/snponly.efi',
    '/boot/grub2/powerpc-ieee1275/core.elf',
    '/yb/node/yaboot-cn01',
);
ok( probe_utils::boot_loader_download($_), "$_ is a boot loader download" ) for @loaders;

my @others = (
    'xcat/genesis.kernel.x86_64',
    'xcat/genesis.fs.x86_64.gz',
    'pxelinux.0',
    '/boot/grub2/grub2.ppc',
    'xcat/ipxeboot.kpxe',
);
ok( !probe_utils::boot_loader_download($_), "$_ is not a boot loader download" ) for @others;
ok( !probe_utils::boot_loader_download(undef), 'no file name is not a boot loader download' );

done_testing();
