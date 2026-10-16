#!/usr/bin/env perl
# An x86_64 KVM guest asks libvirt for UEFI with vm.othersettings "firmware:efi". A guest that
# does not ask keeps SeaBIOS, so a site that never wanted UEFI sees no change.
#
# Two things the guest already has must survive the firmware selection. <bios useserial='yes'/>
# puts the boot of the guest on the serial console, which is where the CI reads every boot
# signal. The SMBIOS block gives the guest bare-metal DMI strings; without them sequential
# discovery refuses the node as a virtual machine.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;
use XML::LibXML;

my %before = %INC;
require xCAT::KVMUtils;
my @xcat_loaded = sort grep { m{^xCAT} and !exists $before{$_} } keys %INC;
is_deeply( \@xcat_loaded, ['xCAT/KVMUtils.pm'], 'xCAT::KVMUtils loads no other xCAT module' );

# The firmware and the profile that build_xmldesc and build_diskstruct read for one x86_64 node.
sub node_profile {
    my ($othersettings) = @_;
    my $confdata = {
        vm       => { cn1 => [ { host => 'hyp1', othersettings => $othersettings } ] },
        nodetype => { cn1 => [ { arch => 'x86_64' } ] },
    };
    my $firmware =
      xCAT::KVMUtils::requested_firmware( xCAT::KVMUtils::vm_othersettings( $confdata, 'cn1' ) );
    return xCAT::KVMUtils::guest_arch_profile( 'x86_64', 'x86_64', $firmware );
}

sub os_of {
    my ( $profile, %args ) = @_;
    return xCAT::KVMUtils::guest_os( $profile, hyp_cpumodel => 'x86_64', %args );
}

# The bus build_diskstruct gives the first disk, and the prefix of the optical drive.
sub disk_bus {
    my ($profile) = @_;
    my ( undef, $model ) = xCAT::KVMUtils::split_disk_spec( '/var/lib/libvirt/images/cn1.img',
        undef, $profile->{disk_model} );
    return $model;
}

# A node that asks for UEFI.
my $uefi    = node_profile('firmware:efi');
my $uefi_os = os_of($uefi);
is( $uefi_os->{firmware}, 'efi',
    'firmware:efi puts firmware="efi" on <os>, which is how libvirt selects a UEFI firmware' );
is( $uefi_os->{type}->{machine}, 'q35',
    'the UEFI node is placed on q35, the only machine type the x86_64 OVMF descriptors target' );
is( $uefi_os->{bios}->{useserial}, 'yes',
    'the UEFI node keeps <bios useserial="yes"/>, so its boot still reaches the serial console' );

# q35 has no IDE controller, so libvirt refuses a domain whose disks state the ide bus.
is( disk_bus($uefi), 'scsi', 'the disk of the UEFI node is scsi, a bus q35 can carry' );
is( xCAT::KVMUtils::cdrom_prefix( $uefi, undef ), 'sd',
    'and its optical drive is named sd*, not hd*' );

# A node that names its own machine type keeps it. q35 is a default, not an override.
my $named = node_profile('firmware:efi;machine:pc-q35-rhel9.4.0');
is( os_of( $named, machine => 'pc-q35-rhel9.4.0' )->{type}->{machine}, 'pc-q35-rhel9.4.0',
    'firmware:efi leaves a machine type the node names alone' );

# The SMBIOS block of a discovery guest. cluster-test.pl stores a masked domain XML in
# kvm_nodedata, and kvm.pm builds the guest from that stored XML through reconfigvm. Give
# reconfigure_domain the masked UEFI domain and a boot order to change, so it rewrites <os>.
my $masked = <<'XML';
<domain type="kvm">
  <name>cn1</name>
  <memory>4194304</memory>
  <vcpu>2</vcpu>
  <os firmware="efi">
    <type machine="q35">hvm</type>
    <bios useserial="yes"/>
    <boot dev="network"/>
    <boot dev="hd"/>
    <smbios mode="sysinfo"/>
  </os>
  <clock offset="utc"/>
  <sysinfo type="smbios">
    <system>
      <entry name="manufacturer">Supermicro</entry>
      <entry name="product">Super Server</entry>
    </system>
  </sysinfo>
</domain>
XML

sub attribute {
    my ( $xml, $xpath, $name ) = @_;
    my ($node) = XML::LibXML->load_xml( string => $xml )->findnodes($xpath);
    return undef unless $node;
    return $node->getAttribute($name);
}

my $rebuilt = xCAT::KVMUtils::reconfigure_domain( $masked,
    clock_offset => xCAT::KVMUtils::clock_offset( undef, 'alma10.0' ),
    bootorder    => 'hd,net' );
die "reconfigure_domain rewrote nothing, so the test measures no rewrite\n" unless $rebuilt;
is_deeply(
    [ map { $_->getAttribute('dev') }
          XML::LibXML->load_xml( string => $rebuilt )->findnodes('/domain/os/boot') ],
    [ 'hd', 'network' ],
    'reconfigure_domain writes the boot order of the node'
);
is( attribute( $rebuilt, '/domain/sysinfo', 'type' ), 'smbios',
    'the rebuilt UEFI guest keeps the <sysinfo type="smbios"> block with its DMI strings' );
is( attribute( $rebuilt, '/domain/os/smbios', 'mode' ), 'sysinfo',
    'and keeps <smbios mode="sysinfo"/>, which is what makes the guest read that block' );
is( attribute( $rebuilt, '/domain/os', 'firmware' ), 'efi',
    'and still asks for UEFI after the rewrite' );
is( attribute( $rebuilt, '/domain/os/bios', 'useserial' ), 'yes',
    'and still puts its boot on the serial console' );

# A node that asks for nothing. <os> is the only element the firmware selection touches, so it
# is held down whole.
my $plain = node_profile(undef);
is_deeply(
    os_of($plain),
    {
        type => { content   => 'hvm' },
        bios => { useserial => 'yes' },
        boot => [ { dev => 'network' }, { dev => 'hd' } ],
    },
    'an x86_64 node that asks for nothing states no firmware and no machine type'
);
is( disk_bus($plain), 'ide', 'and keeps the ide disk bus of the machine type it has always had' );

is( os_of( node_profile('cpumode:host-passthrough') )->{firmware}, undef,
    'another vm.othersettings key does not select a firmware' );

# Reading the setting must not create the row it reads. An rvalue dereference chain
# autovivifies its intermediate links, so $confdata->{vm}->{$node}->[0]->{othersettings} makes
# a vm row exist for a node that is not a VM, and a later truth test on that row answers yes.
{
    my $confdata = { nodetype => { cn9 => [ { arch => 'x86_64' } ] } };
    is( xCAT::KVMUtils::vm_othersettings( $confdata, 'cn9' ), undef,
        'vm_othersettings answers undef for a node with no vm row' );
    ok( !exists $confdata->{vm}, 'and the read autovivified no vm table in confdata' );
}
{
    my $confdata = { vm => { cn8 => [ { host => 'hyp1' } ] } };
    is( xCAT::KVMUtils::vm_othersettings( $confdata, 'cn9' ), undef,
        'vm_othersettings answers undef for a node absent from a populated vm table' );
    ok( !exists $confdata->{vm}->{cn9}, 'and the read autovivified no row for that node' );
    is_deeply( $confdata, { vm => { cn8 => [ { host => 'hyp1' } ] } },
        'and left confdata as it was' );
}

# reconfigvm takes the clock offset, memory and CPU count of the node into the stored domain.
is( xCAT::KVMUtils::clock_offset( undef, 'win2019' ), 'localtime', 'a Windows guest keeps localtime' );
is( xCAT::KVMUtils::clock_offset( undef, 'alma10.0' ), 'utc', 'every other guest uses utc' );
is( xCAT::KVMUtils::clock_offset( 'localtime', 'alma10.0' ), 'localtime', 'and vm.clockoffset wins' );
my $resized = xCAT::KVMUtils::reconfigure_domain( $masked,
    clock_offset => 'localtime', memory => 2097152, vcpus => 4 );
is( attribute( $resized, '/domain/clock', 'offset' ), 'localtime',
    'reconfigure_domain writes the clock offset' );
my $resized_doc = XML::LibXML->load_xml( string => $resized );
is( $resized_doc->findvalue('/domain/memory'), '2097152', 'and the memory' );
is( $resized_doc->findvalue('/domain/vcpu'),   '4',       'and the CPU count' );
is( xCAT::KVMUtils::reconfigure_domain( $masked, clock_offset => 'utc', bootorder => 'net,hd' ),
    0, 'a domain that already matches the node is not rewritten' );
is( xCAT::KVMUtils::reconfigure_domain( $masked, clock_offset => 'utc' ),
    0, 'and neither is one for a node with no boot order' );

# A ppc64le hypervisor gets no SeaBIOS serial option.
ok( !exists xCAT::KVMUtils::guest_os( $plain, hyp_cpumodel => 'ppc64le' )->{bios},
    'a guest on a ppc64le hypervisor states no <bios>' );

# A value libvirt cannot select is refused by name. A typo must not quietly leave the node on
# SeaBIOS, because the node then fails a long way from here.
my $uefi_typo = xCAT::KVMUtils::requested_firmware('firmware:uefi');
like( xCAT::KVMUtils::firmware_error( $uefi_typo, 'cn1' ), qr/firmware:uefi/,
    'firmware:uefi is refused and the refusal names the value that was read' );
is( xCAT::KVMUtils::firmware_error( 'efi', 'cn1' ), undef, 'firmware:efi is not refused' );

done_testing();
