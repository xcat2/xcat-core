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
    BAIL_OUT("could not extract $name from kvm.pm") unless $routine;
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
BAIL_OUT("could not load the kvm domain builder: $@") if $@;

# Build one domain for a node of $guest_arch on a hypervisor that reports $hyp_cpumodel.
sub domain_xml {
    my ($guest_arch, $hyp_cpumodel) = @_;
    local $KVMArch::node     = 'cn1';
    local $KVMArch::confdata = {
        vm       => { cn1 => [ { host => 'hyp1', memory => 8192, cpus => 4 } ] },
        nodetype => { cn1 => [ { arch => $guest_arch, os => 'rocky10.2' } ] },
        hyp1     => { cpumodel => $hyp_cpumodel },
    };
    local $KVMArch::updatetable = {};
    my $xml = KVMArch::build_xmldesc('cn1');
    BAIL_OUT("build_xmldesc returned no XML for $guest_arch on $hyp_cpumodel")
      unless defined $xml and !ref $xml;
    return $xml;
}

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

# POWER is unchanged: the arch still comes from the hypervisor there.
my $power = domain_xml('ppc64le', 'ppc64le');
like($power, qr/<domain\b[^>]*\btype="kvm"/, 'a POWER guest stays a kvm domain');
like(os_type_element($power), qr/\barch="ppc64"/,   'ppc64le hypervisors keep arch ppc64');
like(os_type_element($power), qr/\bmachine="pseries"/, 'ppc64le hypervisors keep machine pseries');

# x86_64 on x86_64 is unchanged: libvirt picks the arch and the machine type.
my $x86 = domain_xml('x86_64', 'x86_64');
like($x86, qr/<domain\b[^>]*\btype="kvm"/, 'an x86_64 guest stays a kvm domain');
unlike(os_type_element($x86), qr/\barch=/,    'an x86_64 guest states no arch');
unlike(os_type_element($x86), qr/\bmachine=/, 'an x86_64 guest states no machine type');
like($x86, qr/<input\b[^>]*\bbus="usb"/, 'an x86_64 guest keeps the USB tablet');

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

my $x86_disks = disk_struct('x86_64');
is($x86_disks->[0]->{target}->{bus}, 'ide', 'an x86_64 disk keeps the ide default');
like($x86_disks->[1]->{target}->{dev}, qr/^hd/, 'an x86_64 optical drive keeps the hd* name');

done_testing();
