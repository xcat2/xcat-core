#!/usr/bin/env perl
# xcatprobe discovery marks the boot loader stage of an unknown node when it fetches its pxelinux
# configuration or its network boot script. The file names are the ones the TFTP and HTTP logs show.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-probe/lib/perl";

use Test::More;

require probe_utils;

my @starts = (
    '/tftpboot/xcat/ipxe/nets/192.0.2.0_24',
    '/tftpboot/xcat/ipxe/nets/192.0.2.0_24.uefi',
    '/tftpboot/xcat/xnba/nets/192.0.2.0_24',
    '/tftpboot/pxelinux.cfg/C0000200',
);
ok( probe_utils::discovery_boot_download($_), "$_ starts the discovery" ) for @starts;

my @others = (
    '/tftpboot/xcat/ipxe/nodes/cn01',
    '/tftpboot/xcat/ipxe/i386/undionly.kpxe',
    '/tftpboot/xcat/genesis.kernel.x86_64',
);
ok( !probe_utils::discovery_boot_download($_), "$_ does not" ) for @others;
ok( !probe_utils::discovery_boot_download(undef), 'no file name does not' );

done_testing();
