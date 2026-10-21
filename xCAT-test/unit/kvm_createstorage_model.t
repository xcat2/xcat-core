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

# The volume name createstorage and build_diskstruct give the first disk of a node: the
# device prefix of its storage model, then "a". $stale is a capture left live in this block
# by an earlier successful match, which is the state createstorage runs in when a routine on
# the call path matched a pattern that has a group.
sub volume_dev {
    my (%args) = @_;
    my $storage = $args{storage} // 'dir:///var/lib/libvirt/images/';
    my @defaults = @{ $args{defaults} // [] };

    # The match must run in this block, and nothing may match after it: perl restores $1 when
    # the block that set it ends, and any later successful match replaces what it holds.
    my $subject = 'left by an earlier match: ' . ($args{stale} // '');
    $subject =~ /match: (.*)/ if defined $args{stale};
    # A match without a group empties $1, which is the clean state the other cases need.
    $subject =~ /^left/ unless defined $args{stale};
    my ($location, $model, $prefix) = xCAT::KVMUtils::split_disk_spec($storage, @defaults);
    return { location => $location, model => $model, dev => $prefix . 'a' };
}

# dohyp sets storagemodel to scsi for every node it dispatches, whatever the architecture,
# before mkvm reaches createstorage. The riscv64 virt machine has no IDE controller, so its
# volume must be sd*.
is(volume_dev(defaults => ['scsi'])->{dev}, 'sda', 'the scsi storage model names an sd* volume');

# A capture from a match made elsewhere must not name the volume.
is(volume_dev(defaults => ['scsi'], stale => '/var/lib/libvirt/images/')->{dev}, 'sda',
    'a path left by an earlier match does not name the volume');
is(volume_dev(defaults => ['scsi'], stale => 'virtio')->{dev}, 'sda',
    'a model name left by an earlier match does not name the volume');
is(volume_dev(defaults => ['virtio'], stale => 'scsi')->{dev}, 'vda',
    'an earlier match does not override vmstoragemodel either');
is(volume_dev(defaults => [ undef, 'ide' ], stale => 'virtio')->{model}, 'ide',
    'a model name left by an earlier match does not choose the bus of a file-backed disk');

# The model stated on the vmstorage value, and vmstoragemodel, still name the volume.
my $stated = volume_dev(storage => 'dir:///var/lib/libvirt/images/=scsi', defaults => ['virtio']);
is($stated->{dev}, 'sda', 'a model on the vmstorage value names an sd* volume');
is($stated->{location}, 'dir:///var/lib/libvirt/images/',
    'the model suffix is cut from the location of the volume');
is(volume_dev(defaults => ['virtio'])->{dev}, 'vda', 'vmstoragemodel=virtio names a vd* volume');

# createstorage on its own defaults to ide. Nothing in the product reaches this today: dohyp
# gives every node the default storage model first.
is(volume_dev()->{dev}, 'hda', 'createstorage alone defaults to an hd* volume');

is(volume_dev(defaults => [ xCAT::KVMUtils::default_storagemodel() ])->{dev}, 'sda',
    'the default storage model names an sd* volume');

done_testing();
