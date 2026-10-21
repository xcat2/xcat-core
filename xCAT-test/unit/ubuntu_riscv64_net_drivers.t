#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Test::More;

# Without a driver list the Ubuntu netboot image ships no network module at all, and a node
# whose NIC is not built into the kernel cannot reach its root filesystem. QEMU hides this,
# because virtio-net is built into the Ubuntu riscv64 kernel; a machine with an r8169 or an
# e1000e does not boot.

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";
require imgutils;

my @riscv = imgutils::default_net_drivers( 'ubuntu', 'riscv64' );
ok( scalar @riscv, 'a riscv64 Ubuntu image is given network drivers' );

for my $driver (qw(virtio_net e1000 e1000e igb r8169 tg3 mlx5_core)) {
    ok( scalar( grep { $_ eq $driver } @riscv ), "the list carries $driver" );
}

# Every Ubuntu row carries overlay, because the netboot root is an overlay mount.
ok( scalar( grep { $_ eq 'overlay' } @riscv ), 'the list carries overlay' );

# The architectures that already worked must keep the drivers they had.
is_deeply(
    [ imgutils::default_net_drivers( 'ubuntu', 'x86_64' ) ],
    [qw(tg3 bnx2 bnx2x e1000 e1000e igb mlx_en mlx5_core virtio_net overlay)],
    'x86_64 keeps its drivers' );
ok( scalar( imgutils::default_net_drivers( 'ubuntu', 'ppc64el' ) ),
    'ppc64el keeps its drivers' );
is_deeply( [ imgutils::default_net_drivers( 'ubuntu', 'sparc' ) ], [],
    'an architecture with no entry still gets an empty list' );

done_testing();
