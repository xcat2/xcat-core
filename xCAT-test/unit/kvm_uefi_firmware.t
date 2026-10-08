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

use File::Temp qw(tempdir);
use FindBin;
use Test::More;
use XML::LibXML;

# The plugin package declares the variables below; this test names each of them once.
no warnings 'once';

my $repo = "$FindBin::Bin/../..";

BEGIN {
    # kvm.pm loads the xCAT database, the monitoring dispatcher, the thread helper and the
    # libvirt binding. None of them builds the domain XML.
    package Sys::Virt;
    our $VERSION = '11.0.0';

    package Thread;
    sub import {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::yield"} = sub { return };
        return;
    }

    package xCAT::Utils;
    sub genpassword { return 'password' }
    sub genUUID     { return '00000000-0000-0000-0000-000000000002' }

    sub import {
        my ( undef, @names ) = @_;
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::$_"} = \&{"xCAT::Utils::$_"} for @names;
        return;
    }

    package xCAT::VMCommon;
    sub getMacAddresses { return ('52:54:00:00:00:01') }

    package xCAT::Table;
    sub new { return }

    package xCAT::GlobalDef;

    package xCAT::NodeRange;

    package xCAT::Usage;

    package xCAT::TableUtils;

    package xCAT::ServiceNodeUtils;

    package xCAT::DBobjUtils;

    package xCAT::SvrUtils;

    package xCAT_monitoring::monitorctrl;

    package main;
    $INC{'Sys/Virt.pm'}                    = __FILE__;
    $INC{'Thread.pm'}                      = __FILE__;
    $INC{'xCAT_monitoring/monitorctrl.pm'} = __FILE__;
    for my $module (
        qw(GlobalDef NodeRange VMCommon Table Usage Utils TableUtils
        ServiceNodeUtils DBobjUtils SvrUtils)
      )
    {
        $INC{"xCAT/$module.pm"} = __FILE__;
    }

    # kvm.pm puts $XCATROOT/lib/perl in front of the checkout. Point it at an empty directory,
    # so the test cannot measure a product installed weeks ago.
    $ENV{XCATROOT} = File::Temp::tempdir( CLEANUP => 1 );
}

# xcatd loads the plugins from their files.
my $inc = tempdir( CLEANUP => 1 );
symlink( "$repo/xCAT-server/lib/xcat/plugins", "$inc/xCAT_plugin" ) or die "symlink: $!";
unshift @INC, $inc, "$repo/xCAT-server/lib/perl", "$repo/perl-xCAT";
require xCAT_plugin::kvm;

# One compute node on one hypervisor, the way process_request hands them to the domain builder.
sub node_tables {
    my (%attrib) = @_;
    return {
        vm => {
            cn1 => [
                {
                    host    => 'hyp1',
                    memory  => 4096,
                    cpus    => 2,
                    nics    => 'br0',
                    storage => '/var/lib/libvirt/images/cn1.img',
                    (
                        defined $attrib{othersettings}
                          ? ( othersettings => $attrib{othersettings} )
                          : ()
                    ),
                    (
                        defined $attrib{bootorder}
                          ? ( bootorder => $attrib{bootorder} )
                          : ()
                    ),
                }
            ]
        },
        nodetype => { cn1 => [ { arch => $attrib{arch} || 'x86_64', os => 'alma10.0' } ] },
        vpd      => { cn1 => [ { uuid => 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' } ] },
        hyp1     => { cpumodel => $attrib{cpumodel} || 'x86_64' },
    };
}

# Build the domain XML of that node. Returns the XML, or the refusal the builder returned.
sub domain_xml {
    my (%attrib) = @_;
    local $xCAT_plugin::kvm::node        = 'cn1';
    local $xCAT_plugin::kvm::confdata    = node_tables(%attrib);
    local $xCAT_plugin::kvm::updatetable = {};
    my ( $xml, $errstr );
    my $chatter = '';
    {
        open( my $capture, '>', \$chatter ) or die "capture stdout: $!";
        local *STDOUT = $capture;
        ( $xml, $errstr ) = xCAT_plugin::kvm::build_xmldesc('cn1');
    }
    return ( $xml, $errstr );
}

sub os_element {
    my ($xml) = @_;
    die "build_xmldesc returned no XML\n" unless defined $xml and !ref $xml;
    my ($os) = XML::LibXML->load_xml( string => $xml )->findnodes('/domain/os');
    die "the domain XML carries no <os> element\n" unless $os;
    return $os;
}

# The elements and the attributes of <os>, without the indentation XML::Simple adds.
sub os_shape {
    my ($xml) = @_;
    ( my $shape = os_element($xml)->toString() ) =~ s/>\s+</></g;
    return $shape;
}

sub attribute {
    my ( $xml, $xpath, $name ) = @_;
    my ($node) = XML::LibXML->load_xml( string => $xml )->findnodes($xpath);
    return undef unless $node;
    return $node->getAttribute($name);
}

# A node that asks for UEFI.
my ($uefi) = domain_xml( othersettings => 'firmware:efi' );
is( attribute( $uefi, '/domain/os', 'firmware' ), 'efi',
    'firmware:efi puts firmware="efi" on <os>, which is how libvirt selects a UEFI firmware' );
is( attribute( $uefi, '/domain/os/type', 'machine' ), 'q35',
    'the UEFI node is placed on q35, the only machine type the x86_64 OVMF descriptors target' );
is( attribute( $uefi, '/domain/os/bios', 'useserial' ), 'yes',
    'the UEFI node keeps <bios useserial="yes"/>, so its boot still reaches the serial console' );

# q35 has no IDE controller, so libvirt refuses a domain whose disks state the ide bus.
is( attribute( $uefi, '/domain/devices/disk[1]/target', 'bus' ), 'scsi',
    'the disk of the UEFI node is scsi, a bus q35 can carry' );
like( attribute( $uefi, '/domain/devices/disk[2]/target', 'dev' ), qr/^sd/,
    'and its optical drive is named sd*, not hd*' );

# A node that names its own machine type keeps it. q35 is a default, not an override.
my ($named_machine) = domain_xml( othersettings => 'firmware:efi;machine:pc-q35-rhel9.4.0' );
is( attribute( $named_machine, '/domain/os/type', 'machine' ), 'pc-q35-rhel9.4.0',
    'firmware:efi leaves a machine type the node names alone' );

# The SMBIOS block of a discovery guest. cluster-test.pl stores a masked domain XML in
# kvm_nodedata, and kvm.pm builds the guest from that stored XML through reconfigvm. Give
# reconfigvm the masked UEFI domain and a boot order to change, so it rewrites <os>.
sub smbios_masked {
    my ($xml) = @_;
    my $doc = XML::LibXML->load_xml( string => $xml );
    my ($domain) = $doc->findnodes('/domain');
    my ($os)     = $doc->findnodes('/domain/os');
    my $sysinfo  = $doc->createElement('sysinfo');
    $sysinfo->setAttribute( 'type', 'smbios' );
    my $system = $doc->createElement('system');
    for my $pair ( [ manufacturer => 'Supermicro' ], [ product => 'Super Server' ] ) {
        my $entry = $doc->createElement('entry');
        $entry->setAttribute( 'name', $pair->[0] );
        $entry->appendText( $pair->[1] );
        $system->appendChild($entry);
    }
    $sysinfo->appendChild($system);
    $domain->appendChild($sysinfo);
    my $mode = $doc->createElement('smbios');
    $mode->setAttribute( 'mode', 'sysinfo' );
    $os->appendChild($mode);
    return $doc->toString();
}

sub reconfigured {
    my ( $xml, %attrib ) = @_;
    local $xCAT_plugin::kvm::node     = 'cn1';
    local $xCAT_plugin::kvm::confdata = node_tables(%attrib);
    local $xCAT_plugin::kvm::parser   = XML::LibXML->new();
    my $rewritten = xCAT_plugin::kvm::reconfigvm( 'cn1', $xml );
    die "reconfigvm rewrote nothing, so the test measures no rewrite\n" unless $rewritten;
    return $rewritten;
}

my $rebuilt = reconfigured( smbios_masked($uefi), bootorder => 'hd,net' );
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
my ($plain) = domain_xml();
is( os_shape($plain),
    '<os><bios useserial="yes"/><boot dev="network"/><boot dev="hd"/><type>hvm</type></os>',
    'an x86_64 node that asks for nothing states no firmware and no machine type' );

is( attribute( $plain, '/domain/devices/disk[1]/target', 'bus' ), 'ide',
    'and keeps the ide disk bus of the machine type it has always had' );

my ($other_keys) = domain_xml( othersettings => 'cpumode:host-passthrough' );
is( attribute( $other_keys, '/domain/os', 'firmware' ), undef,
    'another vm.othersettings key does not select a firmware' );

# A value libvirt cannot select is refused by name. A typo must not quietly leave the node on
# SeaBIOS, because the node then fails a long way from here.
my ( $refused, $errstr ) = domain_xml( othersettings => 'firmware:uefi' );
like( $errstr, qr/firmware:uefi/,
    'firmware:uefi is refused and the refusal names the value that was read' );

done_testing();
