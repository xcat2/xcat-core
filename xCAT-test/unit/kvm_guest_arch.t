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
for my $name (qw(build_xmldesc guest_arch_profile build_oshash build_diskstruct getUnits)) {
    my ($routine) = $content =~ /^(sub \Q$name\E\s*\{.*?^\})/ms;
    die("could not extract $name from kvm.pm") unless $routine;
    push(@routines, $routine);
}

# kvm.pm needs a management node to load, so the domain builder runs in a scratch package.
# Only the routines that reach libvirt or the xCAT database are replaced; the domain builder
# itself is the code under test.
my $harness = <<'PERL';
package KVMArch;
use XML::Simple qw(XMLout);
our ($node, $confdata, $updatetable, $hypconn);
sub getNodeUUID      { return '00000000-0000-0000-0000-000000000001'; }
sub get_multiple_paths_by_url { return {}; }
sub build_nicstruct  { return []; }
sub genpassword      { return 'password'; }
PERL

eval $harness . join("\n", @routines) . "\n1;\n";    ## no critic (BuiltinFunctions::ProhibitStringyEval)
die("could not load the kvm domain builder: $@") if $@;

# Build one domain for a node of $guest_arch on a hypervisor that reports $hyp_cpumodel.
# %opt carries the hypervisor cputype and the vm.othersettings of the node.
sub domain_xml {
    my ($guest_arch, $hyp_cpumodel, %opt) = @_;
    local $KVMArch::node     = 'cn1';
    local $KVMArch::confdata = {
        vm => {
            cn1 => [ {
                    host   => 'hyp1',
                    memory => 8192,
                    cpus   => 4,
                    (defined $opt{othersettings}
                          ? (othersettings => $opt{othersettings}) : ()),
                    (defined $opt{vidmodel} ? (vidmodel => $opt{vidmodel}) : ()),
            } ]
        },
        nodetype => { cn1 => [ { arch => $guest_arch, os => 'rocky10.2' } ] },
        hyp1     => { cpumodel => $hyp_cpumodel, cputype => $opt{cputype} },
    };
    local $KVMArch::hypconn    = $opt{hypconn};
    local $KVMArch::updatetable = {};
    my $xml = KVMArch::build_xmldesc('cn1');
    die("build_xmldesc returned no XML for $guest_arch on $hyp_cpumodel")
      unless defined $xml and !ref $xml;
    return $xml;
}

# A hypervisor connection that answers one domain capabilities document.
{

    package CapsConn;
    sub new { my ($class, $xml) = @_; return bless { xml => $xml }, $class; }
    sub get_domain_capabilities { return $_[0]->{xml}; }
}

# The modelType enum of an aarch64 virt machine, as libvirt 11.10 reports it on a host whose
# aarch64 emulator carries no virtio-gpu device. libvirt refuses a domain that names virtio
# there.
my $caps_without_virtio = <<'CAPS';
<domainCapabilities>
  <arch>aarch64</arch>
  <devices>
    <video supported='yes'>
      <enum name='modelType'>
        <value>vga</value>
        <value>cirrus</value>
        <value>none</value>
        <value>bochs</value>
        <value>ramfb</value>
      </enum>
    </video>
  </devices>
</domainCapabilities>
CAPS

my $caps_with_virtio = <<'CAPS';
<domainCapabilities>
  <arch>aarch64</arch>
  <devices>
    <video supported='yes'>
      <enum name='modelType'>
        <value>vga</value>
        <value>virtio</value>
        <value>ramfb</value>
      </enum>
    </video>
  </devices>
</domainCapabilities>
CAPS

my $caps_without_video = "<domainCapabilities><arch>aarch64</arch></domainCapabilities>\n";

sub os_type_element {
    my ($xml) = @_;
    my ($attrs) = $xml =~ m{<type\b([^>]*)>hvm</type>}s;
    return defined $attrs ? $attrs : '';
}

# A riscv64 node on an x86_64 hypervisor. The guest architecture is not the host
# architecture, so the domain runs under emulation and states its own machine type.
my $riscv = domain_xml('riscv64', 'x86_64');
like($riscv, qr/<domain\b[^>]*\btype="qemu"/,
    'a riscv64 guest on an x86_64 hypervisor is a qemu domain, not kvm');
like(os_type_element($riscv), qr/\barch="riscv64"/,
    'the domain arch is the arch of the node');
like(os_type_element($riscv), qr/\bmachine="virt"/,
    'a riscv64 guest uses the virt machine type');
like($riscv, qr/<os\b[^>]*\bfirmware="efi"/,
    'a riscv64 virt guest boots UEFI');
unlike($riscv, qr/<(?:pae|acpi|apic)\b/,
    'pae, acpi and apic are x86 features and are left out of a riscv64 guest');
unlike($riscv, qr/<bios\b/,
    'the SeaBIOS serial option is left out of a riscv64 guest');
unlike($riscv, qr/<input\b/,
    'the riscv64 virt machine has no USB controller, so it gets no USB tablet');

# An aarch64 node on an x86_64 hypervisor. The guest arch is not the host arch, so the domain
# runs under emulation and needs a named CPU model: TCG has no host CPU, and with no <cpu>
# element the emulator turns on SVE, which stops the guest in its firmware.
my $arm = domain_xml('aarch64', 'x86_64');
like($arm, qr/<domain\b[^>]*\btype="qemu"/,
    'an aarch64 guest on an x86_64 hypervisor is a qemu domain, not kvm');
like(os_type_element($arm), qr/\barch="aarch64"/,
    'the domain arch of an aarch64 node is aarch64');
like(os_type_element($arm), qr/\bmachine="virt"/,
    'an aarch64 guest uses the virt machine type');
like($arm, qr/<os\b[^>]*\bfirmware="efi"/,
    'an aarch64 virt guest boots UEFI');
like($arm, qr{<cpu\b[^>]*\bmode="custom"[^>]*>\s*<model>cortex-a57</model>}s,
    'an emulated aarch64 guest states cortex-a57 as a custom CPU model');
like($arm, qr/<model\b[^>]*\btype="vga"/,
    'an aarch64 guest falls back to vga when no hypervisor states its video models');
unlike($arm, qr/<(?:pae|acpi|apic)\b/,
    'pae, acpi and apic are x86 features and are left out of an aarch64 guest');
unlike($arm, qr/<bios\b/,
    'the SeaBIOS serial option is left out of an aarch64 guest');
unlike($arm, qr/<input\b/,
    'the aarch64 virt machine has no USB controller, so it gets no USB tablet');

# The video models of a machine type come from the emulator build, not from the architecture.
# libvirt refuses a domain that names a model the emulator of the hypervisor has no device
# for, so the model comes from the capabilities of that hypervisor.
my $arm_no_virtio =
  domain_xml('aarch64', 'x86_64', hypconn => CapsConn->new($caps_without_virtio));
like($arm_no_virtio, qr/<model\b[^>]*\btype="vga"/,
    'an aarch64 guest takes vga from a hypervisor that offers no virtio video model');

my $arm_virtio =
  domain_xml('aarch64', 'x86_64', hypconn => CapsConn->new($caps_with_virtio));
like($arm_virtio, qr/<model\b[^>]*\btype="virtio"/,
    'an aarch64 guest takes virtio from a hypervisor that offers it');

my $arm_no_video =
  domain_xml('aarch64', 'x86_64', hypconn => CapsConn->new($caps_without_video));
like($arm_no_video, qr/<model\b[^>]*\btype="vga"/,
    'an aarch64 guest falls back to vga when the hypervisor states no video models');

my $arm_vidmodel = domain_xml('aarch64', 'x86_64',
    hypconn => CapsConn->new($caps_with_virtio), vidmodel => 'ramfb');
like($arm_vidmodel, qr/<model\b[^>]*\btype="ramfb"/,
    'vm.vidmodel still names the video model of an aarch64 guest');

# An aarch64 node on an aarch64 hypervisor. The guest arch is the host arch, so the domain runs
# under KVM. KVM on ARM runs the host CPU and no other model, and libvirt reports
# host-passthrough as unsupported for an emulated aarch64 domain.
my $arm_native = domain_xml('aarch64', 'aarch64');
like($arm_native, qr/<domain\b[^>]*\btype="kvm"/,
    'an aarch64 guest on an aarch64 hypervisor is a kvm domain, not qemu');
like($arm_native, qr/<cpu\b[^>]*\bmode="host-passthrough"/,
    'a native aarch64 guest takes the host CPU');
unlike($arm_native, qr{<model>cortex-a57</model>},
    'a native aarch64 guest pins no cortex-a57 model');
like(os_type_element($arm_native), qr/\barch="aarch64"/,
    'a native aarch64 guest states arch aarch64');
like(os_type_element($arm_native), qr/\bmachine="virt"/,
    'a native aarch64 guest states machine virt');
like($arm_native, qr/<os\b[^>]*\bfirmware="efi"/,
    'a native aarch64 virt guest boots UEFI');

# An aarch64 node on a POWER hypervisor. The CPU model, the CPU topology and the emulator are
# settings of a pseries guest, and this guest is not one.
my $arm_on_power = domain_xml('aarch64', 'ppc64', cputype => 'POWER9');
like($arm_on_power, qr/<domain\b[^>]*\btype="qemu"/,
    'an aarch64 guest on a POWER hypervisor is a qemu domain, not kvm');
like(os_type_element($arm_on_power), qr/\barch="aarch64"/,
    'an aarch64 guest on a POWER hypervisor keeps arch aarch64');
like(os_type_element($arm_on_power), qr/\bmachine="virt"/,
    'an aarch64 guest on a POWER hypervisor keeps machine virt');
unlike($arm_on_power, qr/\bmodel="POWER9"/,
    'an aarch64 guest takes no POWER CPU model from the hypervisor');
unlike($arm_on_power, qr/<topology\b/,
    'an aarch64 guest takes no pseries CPU topology from the hypervisor');
unlike($arm_on_power, qr{<emulator>},
    'libvirt resolves the emulator of an aarch64 guest on a POWER hypervisor');
like($arm_on_power, qr{<model>cortex-a57</model>},
    'an aarch64 guest on a POWER hypervisor still states cortex-a57');

# vm.othersettings can name a CPU mode. TCG has no host CPU, so libvirt refuses both
# host-passthrough and host-model on an emulated domain.
my $arm_passthrough =
  domain_xml('aarch64', 'x86_64', othersettings => 'cpumode:host-passthrough');
unlike($arm_passthrough, qr/\bmode="host-passthrough"/,
    'host-passthrough from vm.othersettings is left out of an emulated aarch64 domain');
like($arm_passthrough, qr{<model>cortex-a57</model>},
    'the emulated aarch64 guest keeps cortex-a57 when host-passthrough is left out');

my $arm_native_hostmodel =
  domain_xml('aarch64', 'aarch64', othersettings => 'cpumode:host-model');
like($arm_native_hostmodel, qr/<cpu\b[^>]*\bmode="host-model"/,
    'host-model from vm.othersettings reaches a native aarch64 domain');
unlike($arm_native_hostmodel, qr/\bmode="host-passthrough"/,
    'the mode from vm.othersettings replaces the host-passthrough default');

# POWER is unchanged: a pseries guest keeps the arch, the CPU model and the topology of the
# hypervisor.
my $power = domain_xml('ppc64le', 'ppc64le', cputype => 'POWER9');
like($power, qr/<domain\b[^>]*\btype="kvm"/, 'a POWER guest stays a kvm domain');
like(os_type_element($power), qr/\barch="ppc64"/,   'ppc64le hypervisors keep arch ppc64');
like(os_type_element($power), qr/\bmachine="pseries"/, 'ppc64le hypervisors keep machine pseries');
like($power, qr/<cpu\b[^>]*\bmodel="POWER9"/, 'a POWER guest keeps the hypervisor CPU model');
like($power, qr/<topology\b[^>]*\bcores="4"/, 'a POWER guest keeps its CPU topology');
unlike($power, qr{<model>cortex-a57</model>}, 'a POWER guest states no aarch64 CPU model');

# A ppc64 hypervisor names its own emulator, and a pseries guest still gets it.
my $power_ppc64 = domain_xml('ppc64', 'ppc64', cputype => 'POWER9');
like($power_ppc64, qr{<emulator>/usr/bin/qemu-system-ppc64</emulator>},
    'a pseries guest on a ppc64 hypervisor keeps the qemu-system-ppc64 emulator');

# x86_64 on x86_64 is unchanged: libvirt picks the arch and the machine type.
my $x86 = domain_xml('x86_64', 'x86_64');
like($x86, qr/<domain\b[^>]*\btype="kvm"/, 'an x86_64 guest stays a kvm domain');
unlike(os_type_element($x86), qr/\barch=/,    'an x86_64 guest states no arch');
unlike(os_type_element($x86), qr/\bmachine=/, 'an x86_64 guest states no machine type');
like($x86, qr/<input\b[^>]*\bbus="usb"/, 'an x86_64 guest keeps the USB tablet');
unlike($x86, qr/<cpu\b/, 'an x86_64 guest states no cpu element');

my $x86_passthrough =
  domain_xml('x86_64', 'x86_64', othersettings => 'cpumode:host-passthrough');
like($x86_passthrough, qr/<cpu\b[^>]*\bmode="host-passthrough"/,
    'host-passthrough from vm.othersettings reaches a native x86_64 domain');

# The disks of a riscv64 guest. The virt machine has no IDE controller, so an ide disk or an
# hd* optical drive makes libvirt refuse the domain.
sub disk_struct {
    my ($guest_arch) = @_;
    local $KVMArch::node     = 'cn1';
    local $KVMArch::confdata = {
        vm       => { cn1 => [ { host => 'hyp1', storage => '/var/lib/libvirt/images/cn1.img' } ] },
        nodetype => { cn1 => [ { arch => $guest_arch } ] },
        hyp1     => { cpumodel => 'x86_64' },
    };
    my $chatter = '';
    my $disks;
    {
        open(my $capture, '>', \\$chatter) or die "capture stdout: $!";
        local *STDOUT = $capture;
        ($disks) = KVMArch::build_diskstruct(undef);
    }
    return $disks;
}

my $riscv_disks = disk_struct('riscv64');
is($riscv_disks->[0]->{target}->{bus}, 'scsi', 'a riscv64 disk is scsi, not ide');
like($riscv_disks->[0]->{target}->{dev}, qr/^sd/, 'a riscv64 disk is named sd*');
is($riscv_disks->[1]->{device}, 'cdrom', 'the guest still gets an optical drive');
like($riscv_disks->[1]->{target}->{dev}, qr/^sd/, 'a riscv64 optical drive is named sd*, not hd*');

my $arm_disks = disk_struct('aarch64');
is($arm_disks->[0]->{target}->{bus}, 'scsi', 'an aarch64 disk is scsi, not ide');
like($arm_disks->[0]->{target}->{dev}, qr/^sd/, 'an aarch64 disk is named sd*');
like($arm_disks->[1]->{target}->{dev}, qr/^sd/, 'an aarch64 optical drive is named sd*, not hd*');

my $x86_disks = disk_struct('x86_64');
is($x86_disks->[0]->{target}->{bus}, 'ide', 'an x86_64 disk keeps the ide default');
like($x86_disks->[1]->{target}->{dev}, qr/^hd/, 'an x86_64 optical drive keeps the hd* name');

done_testing();
