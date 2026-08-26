#!/usr/bin/env perl
use strict;
use warnings;

use Carp qw(croak);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";
use Test::More;

use XCAT::Test::File qw(repo_path);
use imgutils;

my @cases = (
    [ 'rh', 'x86', [qw(tg3 bnx2 bnx2x e1000 e1000e igb mlx_en mlx5_core virtio_net be2net)] ],
    [ 'rh', 'x86_64', [qw(tg3 bnx2 bnx2x e1000 e1000e igb mlx_en mlx5_core virtio_net be2net)] ],
    [ 'rh', 'aarch64', [qw(tg3 bnx2 bnx2x e1000e igb mlx_en mlx5_core virtio_net)] ],
    [ 'rh', 'ppc64', [qw(e1000 e1000e igb ibmveth ehea)] ],
    [ 'rh', 's390x', [qw(qdio ccwgroup)] ],
    [ 'sles', 'x86', [qw(tg3 bnx2 bnx2x e1000 e1000e virtio_net virtio_balloon igb mlx4_en mlx5_core be2net)] ],
    [ 'sles', 'x86_64', [qw(tg3 bnx2 bnx2x e1000 e1000e virtio_net virtio_balloon igb mlx4_en mlx5_core be2net)] ],
    [ 'sles', 'ppc64', [qw(tg3 e1000 e1000e igb ibmveth ehea be2net)] ],
    [ 'sles', 's390x', [qw(qdio ccwgroup qeth qeth_l2 qeth_l3)] ],
    [ 'ubuntu', 'x86', [qw(tg3 bnx2 bnx2x e1000 e1000e igb mlx_en mlx5_core virtio_net overlay)] ],
    [ 'ubuntu', 'x86_64', [qw(tg3 bnx2 bnx2x e1000 e1000e igb mlx_en mlx5_core virtio_net overlay)] ],
    [ 'ubuntu', 'ppc64el', [qw(tg3 bnx2 bnx2x e1000 e1000e igb ibmveth ehea mlx_en mlx4_en mlx5_core virtio_net overlay)] ],
    [ 'ubuntu', 'ppc64', [qw(e1000 e1000e igb ibmveth ehea)] ],
    [ 'ubuntu', 's390x', [qw(qdio ccwgroup)] ],
);

foreach my $case (@cases) {
    my ( $family, $arch, $expected ) = @{$case};
    is_deeply(
        [ imgutils::default_net_drivers( $family, $arch ) ],
        $expected,
        "$family $arch uses the expected default network drivers",
    );
}

is_deeply(
    [ imgutils::default_net_drivers( 'unknown', 'x86_64' ) ],
    [],
    'an unknown image family has no default drivers',
);

sub create_target_kernel {
    my (%args) = @_;
    my $root = tempdir( CLEANUP => 1 );
    my $kernelver = 'test-kernel';
    my $module_root = "$root/lib/modules/$kernelver";
    make_path($module_root);

    foreach my $path (@{ $args{'files'} || [] }) {
        my $full_path = "$module_root/$path";
        make_path(dirname($full_path));
        write_text($full_path, 'module');
    }
    write_text(
        "$module_root/modules.dep",
        join('', map { "$_:\n" } @{ $args{'dependencies'} || [] }),
    );
    write_text(
        "$module_root/modules.builtin",
        join('', map { "$_\n" } @{ $args{'builtins'} || [] }),
    );
    return ( $root, $kernelver );
}

{
    my $mlx5 = 'kernel/drivers/net/ethernet/mellanox/mlx5/core/mlx5_core.ko.xz';
    my ( $root, $kernelver ) = create_target_kernel(
        files        => [$mlx5],
        dependencies => [$mlx5],
    );
    is_deeply(
        [ imgutils::resolve_mellanox_default_net_drivers(
            $root,
            $kernelver,
            [qw(e1000.ko)],
            qw(tg3.ko mlx_en.ko mlx5_core.ko),
        ) ],
        [qw(e1000.ko tg3.ko mlx5_core.ko)],
        'an EL10-like target uses mlx5_core without stale mlx_en or mlx4_en',
    );
}

{
    my $mlx4 = 'kernel/drivers/net/ethernet/mellanox/mlx4/mlx4_en.ko.xz';
    my ( $root, $kernelver ) = create_target_kernel(
        files        => [$mlx4],
        dependencies => [$mlx4],
    );
    is_deeply(
        [ imgutils::resolve_mellanox_default_net_drivers(
            $root, $kernelver, [], qw(mlx_en.ko),
        ) ],
        [qw(mlx4_en.ko)],
        'an older in-box kernel resolves the legacy placeholder to mlx4_en',
    );
}

{
    my $mlx_en = 'updates/mlnx-ofed/drivers/net/mlx_en.ko.zst';
    my ( $root, $kernelver ) = create_target_kernel(
        files        => [$mlx_en],
        dependencies => [$mlx_en],
    );
    is_deeply(
        [ imgutils::resolve_mellanox_default_net_drivers(
            $root, $kernelver, [], qw(mlx_en.ko),
        ) ],
        [qw(mlx_en.ko)],
        'a real legacy MLNX_OFED mlx_en module is retained',
    );
}

{
    my ( $root, $kernelver ) = create_target_kernel();
    is_deeply(
        [ imgutils::resolve_mellanox_default_net_drivers(
            $root,
            $kernelver,
            [],
            qw(tg3.ko mlx_en.ko mlx4_en.ko mlx5_core.ko),
        ) ],
        [qw(tg3.ko)],
        'unavailable optional Mellanox defaults are omitted',
    );
}

{
    my @paths = (
        'weak-updates/vendor/mlx4_en.ko.xz',
        'extra/vendor/mlx5_core.ko.zst',
    );
    my ( $root, $kernelver ) = create_target_kernel(files => \@paths);
    my %available = imgutils::target_kernel_module_availability(
        $root, $kernelver, qw(mlx4_en mlx5_core),
    );
    ok($available{'mlx4_en'}, 'a recursively installed .ko.xz module is available');
    ok($available{'mlx5_core'}, 'a recursively installed .ko.zst module is available');
}

{
    my @paths = (
        'weak-updates/vendor/mlx4_en.ko.xz',
        'extra/vendor/mlx5_core.ko.zst',
    );
    my ( $root, $kernelver ) = create_target_kernel(
        files        => \@paths,
        dependencies => \@paths,
    );
    is_deeply(
        [ imgutils::resolve_mellanox_default_net_drivers(
            $root,
            $kernelver,
            [],
            qw(mlx_en.ko mlx4_en.ko mlx5_core.ko mlx5_core.ko),
        ) ],
        [qw(mlx4_en.ko mlx5_core.ko)],
        'resolved Mellanox defaults are deduplicated',
    );
}

{
    my $mlx5 = 'kernel/drivers/net/ethernet/mellanox/mlx5/core/mlx5_core.ko.xz';
    my ( $root, $kernelver ) = create_target_kernel(
        files        => [$mlx5],
        dependencies => [$mlx5],
    );
    is_deeply(
        [ imgutils::resolve_mellanox_default_net_drivers(
            $root,
            $kernelver,
            [qw(mlx_en.ko e1000.ko)],
            qw(mlx_en.ko mlx5_core.ko),
        ) ],
        [qw(mlx_en.ko e1000.ko mlx5_core.ko)],
        'a missing explicitly requested driver is not discarded as an optional default',
    );
}

{
    my $mlx4 = 'kernel/drivers/net/ethernet/mellanox/mlx4/mlx4_en.ko.xz';
    my ( $root, $kernelver ) = create_target_kernel(
        files        => [$mlx4],
        dependencies => [$mlx4],
    );
    is_deeply(
        [ imgutils::resolve_mellanox_default_net_drivers(
            $root,
            $kernelver,
            [qw(mlx_en.ko mlx4_en.ko e1000.ko)],
            qw(tg3.ko),
        ) ],
        [qw(mlx4_en.ko e1000.ko tg3.ko)],
        'an explicitly requested legacy alias resolves to the in-box mlx4 driver',
    );
}

{
    my $builtin = 'kernel/drivers/net/ethernet/mellanox/mlx5/core/mlx5_core.ko';
    my ( $root, $kernelver ) = create_target_kernel(builtins => [$builtin]);
    my %available = imgutils::target_kernel_module_availability(
        $root, $kernelver, qw(mlx5_core),
    );
    ok($available{'mlx5_core'}, 'modules.builtin identifies an available target module');
}

my $tmpdir = tempdir( CLEANUP => 1 );
my $modprobe_log = "$tmpdir/modprobe.log";
my $fake_modprobe = "$tmpdir/modprobe";
write_text(
    $fake_modprobe,
    "#!/bin/sh\nprintf '%s\\n' \"\$1\" >>\"\$MODPROBE_LOG\"\n" .
    "case \" \${FAIL_MODPROBE:-} \" in\n" .
    "    *\" \$1 \"*) exit 1 ;;\n" .
    "esac\n" .
    "exit 0\n",
);
chmod( 0755, $fake_modprobe ) or croak "chmod $fake_modprobe: $!";

sub run_mellanox_loader {
    return system(
        repo_path('xCAT-genesis-scripts/usr/sbin/loadmlxeth'),
        $fake_modprobe,
    ) >> 8;
}

{
    local %ENV = (
        %ENV,
        MODPROBE_LOG => $modprobe_log,
    );
    is(
        run_mellanox_loader(),
        0,
        'the Genesis Mellanox loader succeeds when both modules load',
    );
}
is(
    read_text($modprobe_log),
    "mlx4_en\nmlx5_core\n",
    'the Genesis loader requests both Mellanox Ethernet driver generations',
);

unlink($modprobe_log) or croak "unlink $modprobe_log: $!";
{
    local %ENV = (
        %ENV,
        FAIL_MODPROBE => 'mlx4_en',
        MODPROBE_LOG  => $modprobe_log,
    );
    is(run_mellanox_loader(), 0,
        'the Genesis Mellanox loader succeeds when mlx5 loads');
}
is(
    read_text($modprobe_log),
    "mlx4_en\nmlx5_core\n",
    'a failed mlx4 load does not suppress the independent mlx5 attempt',
);

unlink($modprobe_log) or croak "unlink $modprobe_log: $!";
{
    local %ENV = (
        %ENV,
        FAIL_MODPROBE => 'mlx5_core',
        MODPROBE_LOG  => $modprobe_log,
    );
    is(run_mellanox_loader(), 0,
        'the Genesis Mellanox loader succeeds when mlx4 loads');
}
is(
    read_text($modprobe_log),
    "mlx4_en\nmlx5_core\n",
    'the Genesis loader tries both generations before reporting failure',
);

unlink($modprobe_log) or croak "unlink $modprobe_log: $!";
{
    local %ENV = (
        %ENV,
        FAIL_MODPROBE => 'mlx4_en mlx5_core',
        MODPROBE_LOG  => $modprobe_log,
    );
    isnt(run_mellanox_loader(), 0,
        'the Genesis Mellanox loader fails when neither module loads');
}
is(
    read_text($modprobe_log),
    "mlx4_en\nmlx5_core\n",
    'both generations are attempted when neither module loads',
);

done_testing();
