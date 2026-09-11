#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Test::More;

# The scratch package below declares these; the test names them once each.
no warnings 'once';

my $source = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/kvm.pm";
open(my $source_fh, '<', $source) or die "open $source: $!";
my $content = do { local $/; <$source_fh> };
close($source_fh) or die "close $source: $!";

my @routines;
for my $name (qw(createstorage build_diskstruct guest_arch_profile getUnits
    default_storagemodel)) {
    my ($routine) = $content =~ /^(sub \Q$name\E\s*\{.*?^\})/ms;
    BAIL_OUT("could not extract $name from kvm.pm") unless $routine;
    push(@routines, $routine);
}

# kvm.pm needs a management node to load, so createstorage runs in a scratch package.
# get_filepath_by_url is the routine that reaches libvirt; it records the device name it is
# asked for, which is the name createstorage gives the volume of the node.
my $harness = <<'PERL';
package KVMStore;
our ($node, $confdata, $clonemethod, @asked);
sub getstorageformat    { my ($cfginfo) = @_; return $cfginfo->{storageformat}; }
sub get_filepath_by_url { my %args = @_; push(@asked, $args{dev}); return $args{dev}; }
sub oldCreateStorage    { push(@asked, 'oldCreateStorage'); }
sub get_multiple_paths_by_url { return {}; }
PERL

eval $harness . join("\n", @routines) . "\n1;\n";    ## no critic (BuiltinFunctions::ProhibitStringyEval)
BAIL_OUT("could not load the kvm storage routines: $@") if $@;

# The name createstorage gives the volume of one node. $stale is a capture left live in this
# block by an earlier successful match, which is the state createstorage runs in when a
# routine on the call path matched a pattern that has a group.
sub volume_dev {
    my (%args) = @_;
    my $storage = $args{storage} // 'dir:///var/lib/libvirt/images/';
    my $cfginfo = {
        node         => 'cn1',
        host         => 'hyp1',
        storage      => $storage,
        storagemodel => $args{storagemodel},
    };
    @KVMStore::asked = ();
    # The match must run in this block, and nothing may match after it: perl restores $1 when
    # the block that set it ends, and any later successful match replaces what it holds.
    my $subject = 'left by an earlier match: ' . ($args{stale} // '');
    $subject =~ /match: (.*)/ if defined $args{stale};
    # A match without a group empties $1, which is the clean state the other cases need.
    $subject =~ /^left/ unless defined $args{stale};
    KVMStore::createstorage($storage, undef, '30G', $cfginfo, 1);
    return $KVMStore::asked[0];
}

# dohyp sets storagemodel to scsi for every node it dispatches, whatever the architecture,
# before mkvm reaches createstorage. That default is what names the volume of a node whose
# vmstoragemodel is empty, and a riscv64 node depends on it: the riscv64 virt machine has no
# IDE controller, so its volume must be sd*.
is(volume_dev(storagemodel => 'scsi'), 'sda',
    'the scsi storage model names an sd* volume');

# A capture from a match made elsewhere must not name the volume. These are the values a
# routine on the mkvm call path can leave in $1.
is(volume_dev(storagemodel => 'scsi', stale => '/var/lib/libvirt/images/'), 'sda',
    'a path left by an earlier match does not name the volume');
is(volume_dev(storagemodel => 'scsi', stale => 'virtio'), 'sda',
    'a model name left by an earlier match does not name the volume');
is(volume_dev(storagemodel => 'virtio', stale => 'scsi'), 'vda',
    'an earlier match does not override vmstoragemodel either');

# The model stated on the vmstorage value, and vmstoragemodel, still name the volume.
is(volume_dev(storage => 'dir:///var/lib/libvirt/images/=scsi'), 'sda',
    'a model on the vmstorage value names an sd* volume');
is(volume_dev(storagemodel => 'virtio'), 'vda',
    'vmstoragemodel=virtio names a vd* volume');

# createstorage on its own defaults to ide. Nothing in the product reaches this today, because
# dohyp gives every node the default storage model first.
is(volume_dev(), 'hda', 'createstorage alone defaults to an hd* volume');

# So the sd* name of a node with no vmstoragemodel rests on that default, and a riscv64 node
# rests on the sd* name. Drive the two together, so a change to the default fails here rather
# than on a riscv64 node that stops booting.
is(volume_dev(storagemodel => KVMStore::default_storagemodel()), 'sda',
    'the default storage model names an sd* volume');

# build_diskstruct reads $1 the same way, for a disk backed by a plain file. The device name
# and the bus of that disk must come from the node, not from a match made elsewhere.
sub file_disk {
    my (%args) = @_;
    local $KVMStore::node     = 'cn1';
    local $KVMStore::confdata = {
        vm       => { cn1 => [ { host => 'hyp1', storage => '/var/lib/libvirt/images/cn1.img' } ] },
        nodetype => { cn1 => [ { arch => $args{arch} } ] },
        hyp1     => { cpumodel => 'x86_64' },
    };
    my $chatter = '';
    my $disks;
    my $subject = 'left by an earlier match: ' . ($args{stale} // '');
    $subject =~ /match: (.*)/ if defined $args{stale};
    $subject =~ /^left/ unless defined $args{stale};
    {
        open(my $capture, '>', \$chatter) or die "capture stdout: $!";
        local *STDOUT = $capture;
        ($disks) = KVMStore::build_diskstruct(undef);
    }
    return $disks->[0];
}

is(file_disk(arch => 'x86_64')->{target}->{bus}, 'ide',
    'a file-backed disk of an x86_64 node is ide');
is(file_disk(arch => 'x86_64', stale => 'virtio')->{target}->{bus}, 'ide',
    'a model name left by an earlier match does not choose the bus of a file-backed disk');
is(file_disk(arch => 'riscv64', stale => 'ide')->{target}->{dev}, 'sda',
    'a riscv64 file-backed disk keeps its sd* name whatever an earlier match left behind');

done_testing();
