#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;

my %before = %INC;
require xCAT::KVMUtils;
my @xcat_loaded = sort grep { m{^xCAT} and !exists $before{$_} } keys %INC;
is_deeply(\@xcat_loaded, ['xCAT/KVMUtils.pm'], 'xCAT::KVMUtils loads no other xCAT module');

# A disk on a libvirt storage pool states the bus of the device name it is given. libvirt
# reads the same names the same way: hd* is ide, sd* is scsi, vd* is virtio.
is(xCAT::KVMUtils::pool_disk_bus('hda'), 'ide',    'an hd* disk on a storage pool is ide');
is(xCAT::KVMUtils::pool_disk_bus('sda'), 'scsi',   'an sd* disk on a storage pool is scsi');
is(xCAT::KVMUtils::pool_disk_bus('vda'), 'virtio', 'a vd* disk on a storage pool is virtio');
is(xCAT::KVMUtils::pool_disk_bus('xvda'), undef,
    'a pool disk with any other name states no bus, and libvirt chooses one');

# The riscv64 virt machine has no IDE controller, so a riscv64 node depends on its volume
# name being sd*, and on its optical drive being sd* too.
my $riscv = xCAT::KVMUtils::guest_arch_profile('riscv64', 'x86_64');
is(xCAT::KVMUtils::pool_disk_bus('sda'), 'scsi', 'a riscv64 pool disk is scsi, not ide');
is(xCAT::KVMUtils::cdrom_prefix($riscv, 'scsi'), 'sd',
    'the riscv64 optical drive is named sd*, not hd*');

done_testing();
