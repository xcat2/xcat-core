#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::KvmPlugin qw(load_kvm_plugin);

my @installed = load_kvm_plugin();
is_deeply(\@installed, [], 'kvm.pm and the xCAT modules it uses load from the checkout');

# kvm.pm declares the package variables set below; the test names each one once.
no warnings 'once';

# Build the disks of a node of $arch whose vmstorage is a libvirt pool holding the volumes
# in $pool: a path => { device, format } map, the shape get_multiple_paths_by_url returns.
sub pool_disks {
    my ($arch, $pool) = @_;
    local $xCAT_plugin::kvm::node     = 'cn1';
    local $xCAT_plugin::kvm::confdata = {
        vm => { cn1 => [ {
            host         => 'hyp1',
            storage      => 'dir:///var/lib/libvirt/images/',
            storagecache => 'writeback',
        } ] },
        nodetype => { cn1 => [ { arch => $arch } ] },
        hyp1     => { cpumodel => 'x86_64' },
    };
    # get_multiple_paths_by_url is the only routine build_diskstruct calls that reaches
    # libvirt. The stub answers what the storage pool holds for the node.
    no warnings 'redefine';
    local *xCAT_plugin::kvm::get_multiple_paths_by_url = sub { return $pool; };
    my $chatter = '';
    my $disks;
    {
        open(my $capture, '>', \$chatter) or die "capture stdout: $!";
        local *STDOUT = $capture;
        ($disks) = xCAT_plugin::kvm::build_diskstruct(undef);
    }
    die('build_diskstruct returned no disks') unless ref $disks eq 'ARRAY';
    return $disks;
}

# One volume in the pool, named <node>.<device>.<format>. The disk is the first element;
# the optical drive build_diskstruct always appends is the second.
sub pool_disk {
    my ($arch, $device) = @_;
    my $path = "/var/lib/libvirt/images/cn1.$device.qcow2";
    return pool_disks($arch, { $path => { device => $device, format => 'qcow2' } })->[0];
}

# A disk on a libvirt storage pool states the bus of the device name it is given. libvirt
# reads the same names the same way: hd* is ide, sd* is scsi, vd* is virtio.
is(pool_disk('x86_64', 'hda')->{target}->{bus}, 'ide',
    'an hd* disk on a storage pool is ide');
is(pool_disk('x86_64', 'sda')->{target}->{bus}, 'scsi',
    'an sd* disk on a storage pool is scsi');
is(pool_disk('x86_64', 'vda')->{target}->{bus}, 'virtio',
    'a vd* disk on a storage pool is virtio');

# The device name is the name of the volume in the pool, and stays it. The riscv64 virt
# machine has no IDE controller, so a riscv64 node depends on that name being sd*.
my $riscv = pool_disk('riscv64', 'sda');
is($riscv->{target}->{dev}, 'sda', 'a riscv64 pool disk keeps the sd* name of its volume');
is($riscv->{target}->{bus}, 'scsi', 'a riscv64 pool disk is scsi, not ide');

my $riscv_all = pool_disks('riscv64',
    { '/var/lib/libvirt/images/cn1.sda.qcow2' => { device => 'sda', format => 'qcow2' } });
is($riscv_all->[1]->{device}, 'cdrom', 'the riscv64 guest still gets an optical drive');
like($riscv_all->[1]->{target}->{dev}, qr/^sd/,
    'the riscv64 optical drive is named sd*, not hd*');

done_testing();
