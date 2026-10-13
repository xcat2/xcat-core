#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;

my %before = %INC;
require xCAT::KVMUtils;
my @xcat_loaded = sort grep { m{^xCAT} and !exists $before{$_} } keys %INC;
is_deeply(\@xcat_loaded, ['xCAT/KVMUtils.pm'],
    'xCAT::KVMUtils loads no other xCAT module');
like($INC{'xCAT/KVMUtils.pm'}, qr{\Q$FindBin::Bin\E/\.\./\.\./perl-xCAT/},
    'xCAT::KVMUtils loads from the checkout');
ok(!exists $INC{'Sys/Virt.pm'}, 'xCAT::KVMUtils loads no libvirt binding');

sub profile { return xCAT::KVMUtils::guest_arch_profile(@_); }
sub cpu     { return xCAT::KVMUtils::guest_cpu(@_); }

# The domain capabilities of an aarch64 virt machine, as XMLin parses them with
# ForceArray => [ 'enum', 'value' ] and KeyAttr => []. The values without virtio are what
# libvirt 11.10 reports on a host whose aarch64 emulator carries no virtio-gpu device.
sub video_caps {
    my (@models) = @_;
    return {
        arch    => 'aarch64',
        devices => {
            video => {
                supported => 'yes',
                enum      => [ { name => 'modelType', value => [@models] } ],
            },
        },
    };
}
my $caps_without_virtio = video_caps(qw(vga cirrus none bochs ramfb));
my $caps_with_virtio    = video_caps(qw(vga virtio ramfb));
my $caps_without_video  = { arch => 'aarch64' };

# A riscv64 node on an x86_64 hypervisor. The guest architecture is not the host
# architecture, so the domain runs under emulation and states its own machine type.
my $riscv = profile('riscv64', 'x86_64');
is($riscv->{domtype}, 'qemu', 'a riscv64 guest on an x86_64 hypervisor is a qemu domain, not kvm');
is($riscv->{arch},     'riscv64', 'the domain arch is the arch of the node');
is($riscv->{machine},  'virt',    'a riscv64 guest uses the virt machine type');
is($riscv->{firmware}, 'efi',     'a riscv64 virt guest boots UEFI');
ok(!$riscv->{x86_features},
    'pae, acpi and apic are x86 features and are left out of a riscv64 guest');
ok(!$riscv->{bios},      'the SeaBIOS serial option is left out of a riscv64 guest');
ok(!$riscv->{usb_input}, 'the riscv64 virt machine has no USB controller, so it gets no USB tablet');
is(xCAT::KVMUtils::guest_video_model($riscv, undef, undef), 'virtio',
    'a riscv64 guest takes the virtio video model');

# An aarch64 node on an x86_64 hypervisor. The domain runs under emulation and needs a named
# CPU model: TCG has no host CPU, and with no <cpu> element the emulator turns on SVE.
my $arm = profile('aarch64', 'x86_64');
is($arm->{domtype},  'qemu',    'an aarch64 guest on an x86_64 hypervisor is a qemu domain, not kvm');
is($arm->{arch},     'aarch64', 'the domain arch of an aarch64 node is aarch64');
is($arm->{machine},  'virt',    'an aarch64 guest uses the virt machine type');
is($arm->{firmware}, 'efi',     'an aarch64 virt guest boots UEFI');
is_deeply(cpu($arm),
    { mode => 'custom', match => 'exact', model => { content => 'cortex-a57' } },
    'an emulated aarch64 guest states cortex-a57 as a custom CPU model');
is(xCAT::KVMUtils::guest_video_model($arm, undef, undef), 'vga',
    'an aarch64 guest falls back to vga when no hypervisor states its video models');
ok(!$arm->{x86_features},
    'pae, acpi and apic are x86 features and are left out of an aarch64 guest');
ok(!$arm->{bios},      'the SeaBIOS serial option is left out of an aarch64 guest');
ok(!$arm->{usb_input}, 'the aarch64 virt machine has no USB controller, so it gets no USB tablet');
ok(!$arm->{sound},     'an aarch64 guest gets no ich6 sound device');

# The video models of a machine type come from the emulator build, not from the architecture.
is(xCAT::KVMUtils::guest_video_model($arm, undef, $caps_without_virtio), 'vga',
    'an aarch64 guest takes vga from a hypervisor that offers no virtio video model');
is(xCAT::KVMUtils::guest_video_model($arm, undef, $caps_with_virtio), 'virtio',
    'an aarch64 guest takes virtio from a hypervisor that offers it');
is(xCAT::KVMUtils::guest_video_model($arm, undef, $caps_without_video), 'vga',
    'an aarch64 guest falls back to vga when the hypervisor states no video models');
is(xCAT::KVMUtils::guest_video_model($arm, 'ramfb', $caps_with_virtio), 'ramfb',
    'vm.vidmodel still names the video model of an aarch64 guest');
is(xCAT::KVMUtils::preferred_video_model($caps_with_virtio, [ 'bochs', 'ramfb', 'virtio' ], 'vga'),
    'ramfb', 'the first wanted model the hypervisor offers wins');

# An aarch64 node on an aarch64 hypervisor. KVM on ARM runs the host CPU and no other model.
my $arm_native = profile('aarch64', 'aarch64');
is($arm_native->{domtype}, 'kvm', 'an aarch64 guest on an aarch64 hypervisor is a kvm domain, not qemu');
is_deeply(cpu($arm_native), { mode => 'host-passthrough' },
    'a native aarch64 guest takes the host CPU and pins no cortex-a57 model');
is($arm_native->{arch},     'aarch64', 'a native aarch64 guest states arch aarch64');
is($arm_native->{machine},  'virt',    'a native aarch64 guest states machine virt');
is($arm_native->{firmware}, 'efi',     'a native aarch64 virt guest boots UEFI');
is(xCAT::KVMUtils::guest_video_model($arm_native, undef, $caps_with_virtio), 'virtio',
    'a native aarch64 guest takes virtio from a hypervisor that offers it');
is(xCAT::KVMUtils::guest_video_model($arm_native, undef, $caps_without_virtio), 'vga',
    'a native aarch64 guest takes vga from a hypervisor that offers no virtio video model');

# An aarch64 node on a POWER hypervisor. The CPU model, the CPU topology and the emulator are
# settings of a pseries guest, and this guest is not one.
my $arm_on_power = profile('aarch64', 'ppc64');
is($arm_on_power->{domtype}, 'qemu',    'an aarch64 guest on a POWER hypervisor is a qemu domain, not kvm');
is($arm_on_power->{arch},    'aarch64', 'an aarch64 guest on a POWER hypervisor keeps arch aarch64');
is($arm_on_power->{machine}, 'virt',    'an aarch64 guest on a POWER hypervisor keeps machine virt');
is_deeply(cpu($arm_on_power, cputype => 'POWER9', cores => 4, threads => 1),
    { mode => 'custom', match => 'exact', model => { content => 'cortex-a57' } },
    'an aarch64 guest on a POWER hypervisor takes no POWER CPU model or topology');
is(xCAT::KVMUtils::guest_emulator($arm_on_power, 'ppc64'), undef,
    'libvirt resolves the emulator of an aarch64 guest on a POWER hypervisor');

# vm.othersettings can name a CPU mode. TCG has no host CPU, so libvirt refuses both
# host-passthrough and host-model on an emulated domain.
is_deeply(cpu($arm, cpumode => 'host-passthrough'),
    { mode => 'custom', match => 'exact', model => { content => 'cortex-a57' } },
    'host-passthrough from vm.othersettings is left out of an emulated aarch64 domain');
is_deeply(cpu($arm, cpumode => 'host-model'),
    { mode => 'custom', match => 'exact', model => { content => 'cortex-a57' } },
    'host-model from vm.othersettings is left out of an emulated aarch64 domain');
is_deeply(cpu($arm_native, cpumode => 'host-model'), { mode => 'host-model' },
    'host-model from vm.othersettings replaces the host-passthrough default of a native aarch64 domain');

# A pseries guest keeps the arch, the CPU model and the topology of the hypervisor.
my $power = profile('ppc64le', 'ppc64le');
is($power->{domtype}, 'kvm',     'a POWER guest stays a kvm domain');
is($power->{arch},    'ppc64',   'ppc64le hypervisors keep arch ppc64');
is($power->{machine}, 'pseries', 'ppc64le hypervisors keep machine pseries');
is_deeply(cpu($power, cputype => 'POWER9', cores => 4, threads => 2),
    { model => 'POWER9', topology => { sockets => 1, cores => 4, threads => 2 } },
    'a POWER guest keeps the hypervisor CPU model and its CPU topology');
is_deeply(cpu($power, cpumode => 'host-model', cores => 1, threads => 1),
    { topology => { sockets => 1, cores => 1, threads => 1 } },
    'the pseries CPU replaces the cpumode of vm.othersettings');
is(xCAT::KVMUtils::guest_emulator($power, 'ppc64le'), undef,
    'libvirt resolves the emulator of a pseries guest on a ppc64le hypervisor');

my $power_ppc64 = profile('ppc64', 'ppc64');
is(xCAT::KVMUtils::guest_emulator($power_ppc64, 'ppc64'), '/usr/bin/qemu-system-ppc64',
    'a pseries guest on a ppc64 hypervisor keeps the qemu-system-ppc64 emulator');

# x86_64 on x86_64: libvirt picks the arch and the machine type.
my $x86 = profile('x86_64', 'x86_64');
is($x86->{domtype}, 'kvm', 'an x86_64 guest stays a kvm domain');
is($x86->{arch},    undef, 'an x86_64 guest states no arch');
is($x86->{machine}, undef, 'an x86_64 guest states no machine type');
ok($x86->{usb_input}, 'an x86_64 guest keeps the USB tablet');
is(cpu($x86), undef, 'an x86_64 guest states no cpu element');
is_deeply(cpu($x86, cpumode => 'host-passthrough'), { mode => 'host-passthrough' },
    'host-passthrough from vm.othersettings reaches a native x86_64 domain');
is(xCAT::KVMUtils::guest_video_model($x86, undef, $caps_with_virtio), 'vga',
    'an x86_64 guest keeps vga whatever the hypervisor offers');

# The disks of a guest. The virt machine has no IDE controller, so an ide disk or an hd*
# optical drive makes libvirt refuse a riscv64 or aarch64 domain.
foreach my $arch (qw(riscv64 aarch64)) {
    my $p = profile($arch, 'x86_64');
    my (undef, $model, $prefix) =
      xCAT::KVMUtils::split_disk_spec('/var/lib/libvirt/images/cn1.img', undef, $p->{disk_model});
    is($model,  'scsi', "a $arch disk is scsi, not ide");
    is($prefix, 'sd',   "a $arch disk is named sd*");
    is(xCAT::KVMUtils::cdrom_prefix($p, undef), 'sd', "a $arch optical drive is named sd*, not hd*");
}
my (undef, $x86_model) =
  xCAT::KVMUtils::split_disk_spec('/var/lib/libvirt/images/cn1.img', undef, $x86->{disk_model});
is($x86_model, 'ide', 'an x86_64 disk keeps the ide default');
is(xCAT::KVMUtils::cdrom_prefix($x86, undef), 'hd', 'an x86_64 optical drive keeps the hd* name');
is(xCAT::KVMUtils::cdrom_prefix($x86, 'virtio'), 'sd',
    'vmstoragemodel virtio names the optical drive sd*, not vd*');

done_testing();
