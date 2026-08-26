#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;
BEGIN {
    $ENV{XCATROOT} = "$FindBin::Bin/../../xCAT-server";
}

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";

require anaconda;
require geninitrd;
use imgutils;

my $media = tempdir(CLEANUP => 1);
my $pxeboot = File::Spec->catdir($media, 'images', 'pxeboot');
make_path($pxeboot);
write_text(File::Spec->catfile($pxeboot, 'vmlinuz'), "kernel\n");
write_text(File::Spec->catfile($pxeboot, 'initrd.img'), "initrd\n");

my @paths = xCAT_plugin::anaconda::_install_media_pxeboot_paths($media, 'riscv64');
is_deeply(
    \@paths,
    [ File::Spec->catfile($pxeboot, 'vmlinuz'), File::Spec->catfile($pxeboot, 'initrd.img') ],
    'riscv64 installer media use the images/pxeboot kernel and initrd',
);
is_deeply(
    [ xCAT_plugin::anaconda::_install_media_pxeboot_paths($media, 'x86_64') ],
    \@paths,
    'x86_64 keeps the existing images/pxeboot layout',
);
is_deeply(
    [ xCAT_plugin::anaconda::_install_media_pxeboot_paths($media, 'aarch64') ],
    \@paths,
    'aarch64 keeps the existing images/pxeboot layout',
);
is_deeply(
    [ xCAT_plugin::anaconda::_install_media_pxeboot_paths($media, 'ppc64') ],
    [],
    'POWER media continue through their separate layout',
);
unlink(File::Spec->catfile($pxeboot, 'initrd.img'));
is_deeply(
    [ xCAT_plugin::anaconda::_install_media_pxeboot_paths($media, 'riscv64') ],
    [ File::Spec->catfile($pxeboot, 'vmlinuz'), undef ],
    'an incomplete pxeboot media pair preserves the existing partial lookup result',
);

is(
    xCAT_plugin::anaconda::_driver_disk_kernel_version('/tmp/rpm/boot/vmlinuz-6.12.0-55.riscv64'),
    '6.12.0-55.riscv64',
    'driver-disk kernel updates recognise riscv64 kernels',
);
is(
    xCAT_plugin::anaconda::_driver_disk_kernel_version('/tmp/rpm/boot/vmlinuz-6.12.0-55.x86_64'),
    '6.12.0-55.x86_64',
    'driver-disk kernel updates still recognise x86_64 kernels',
);
is(
    xCAT_plugin::anaconda::_driver_disk_kernel_version('/tmp/rpm/boot/not-a-kernel-riscv64'),
    undef,
    'driver-disk kernel parsing rejects unrelated files',
);

ok(
    xCAT_plugin::geninitrd::_uses_x86_install_media_layout('riscv64', 'rocky10'),
    'EL riscv64 media use the installer pxeboot layout',
);
ok(
    !xCAT_plugin::geninitrd::_uses_x86_install_media_layout('riscv64', 'sles15'),
    'SLES riscv64 media do not enter the EL layout',
);
ok(
    xCAT_plugin::geninitrd::_uses_x86_install_media_layout('x86_64', 'sles15'),
    'x86_64 SLES media retain their existing outer architecture route',
);
ok(
    !xCAT_plugin::geninitrd::_uses_x86_install_media_layout('ppc64le', 'rocky10'),
    'POWER media retain their separate architecture route',
);

is_deeply(
    [ imgutils::default_net_drivers( 'rh', 'riscv64' ) ],
    [qw(e1000 e1000e igb ixgbe r8169 tg3 bnx2x mlx5_core virtio_net)],
    'riscv64 diskless images receive the intended default network drivers',
);
is_deeply(
    [ imgutils::resolver_library_paths('riscv64') ],
    [ 'lib64/libnss_dns.so.2', 'lib64/libresolv.so.2' ],
    'riscv64 images take resolver libraries from lib64',
);
is_deeply(
    [ imgutils::resolver_library_paths('ppc64') ],
    [ 'lib/libnss_dns.so.2', 'lib/libresolv.so.2' ],
    'POWER images retain the lib resolver paths',
);

is(
    xCAT_plugin::anaconda::_default_crashkernel_args('riscv64', '/dev/vda2', 0, '', ''),
    ' crashkernel=256M dump=/dev/vda2 ',
    'riscv64 images reserve the existing default crash kernel size',
);
is(
    xCAT_plugin::anaconda::_default_crashkernel_args('x86_64', '/dev/sda2', 0, '', ''),
    ' crashkernel=128M dump=/dev/sda2 ',
    'x86_64 keeps its existing default crash kernel arguments',
);
is(
    xCAT_plugin::anaconda::_default_crashkernel_args('ppc64', '/dev/sda2', 0, '', ''),
    ' crashkernel=256M@64M dump=/dev/sda2 ',
    'POWER keeps its existing default crash kernel arguments',
);
is(
    xCAT_plugin::anaconda::_default_crashkernel_args('ppc64', 'nfs', 1, 'net,host:/dump', 'nfs://host/dump'),
    ' fadump=on fadump_reserve_mem=512M fadump_target=net,host:/dump fadump_default=noreboot dump=nfs://host/dump ',
    'POWER fadump keeps its existing default arguments',
);

done_testing();
