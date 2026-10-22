#!/usr/bin/env perl
# An x86_64 KVM guest asks libvirt for UEFI with Secure Boot on with vm.othersettings
# "firmware:efi-secureboot".
#
# firmware:efi alone states no requirement about Secure Boot. libvirt then takes the firmware
# descriptor of highest priority that fits the guest, and that order is host policy: the same
# node boots with Secure Boot on on one hypervisor and off on another, and the domain reports
# neither. A node that must boot signed binaries has to say so, so that a hypervisor without a
# Secure Boot firmware refuses the domain instead of starting it unverified.
#
# <loader secure='yes'/> is not that requirement on its own. libvirt reads it as the secure-boot
# feature, and a firmware with secure-boot and an empty key store boots an unsigned binary. The
# two x86_64 descriptors of an EL 10 host name the same OVMF_CODE.secboot.fd and differ in the
# nvram template: 30-edk2-ovmf-x64-sb-enrolled.json takes OVMF_VARS.secboot.fd, which holds the
# keys, and 40-edk2-ovmf-x64-sb.json takes OVMF_VARS.fd, which does not. Only descriptor
# priority picks the first one, and priority is host policy.
#
# So the domain asks for enrolled-keys as well. Measured with libvirt 11.10.0 on rome01, with
# the 30- descriptor masked for one connection: the domain that states <loader secure='yes'/>
# alone starts on OVMF_VARS.fd with enrolled-keys resolved to no, and the domain that asks for
# enrolled-keys is refused with "Unable to find 'efi' firmware that is compatible with the
# current configuration".
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;
use XML::LibXML;
use XML::Simple qw(XMLout);

require xCAT::KVMUtils;

# The firmware and the profile that build_xmldesc reads for one x86_64 node.
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
    my ($profile) = @_;
    return xCAT::KVMUtils::guest_os( $profile, hyp_cpumodel => 'x86_64' );
}

is( xCAT::KVMUtils::requested_firmware('firmware:efi-secureboot'),
    'efi-secureboot', 'firmware:efi-secureboot is read whole, not truncated to efi' );
is( xCAT::KVMUtils::firmware_error( 'efi-secureboot', 'cn1' ),
    undef, 'and it is a firmware libvirt can select, so it is not refused' );

my $sb    = node_profile('firmware:efi-secureboot');
my $sb_os = os_of($sb);
is( $sb_os->{firmware}, 'efi',
    'firmware:efi-secureboot puts firmware="efi" on <os>, which starts the firmware selection' );
is( $sb_os->{loader}->{secure}, 'yes',
    'and <loader secure="yes"/>, which narrows that selection to a Secure Boot firmware' );
is( $sb_os->{type}->{machine}, 'q35',
    'the Secure Boot node is placed on q35, the only machine type the x86_64 OVMF descriptors target' );
is( $sb->{disk_model}, 'scsi', 'and its disks take the scsi bus, because q35 has no IDE controller' );
is( $sb_os->{bios}->{useserial}, 'yes',
    'and it keeps <bios useserial="yes"/>, so its boot still reaches the serial console' );

# firmware:efi must keep stating nothing about Secure Boot. A site that asked only for UEFI
# gets the firmware its hypervisor prefers, as it did before.
my $uefi_os = os_of( node_profile('firmware:efi') );
is( $uefi_os->{firmware}, 'efi', 'firmware:efi still asks for UEFI' );
is( $uefi_os->{loader},   undef, 'and states no Secure Boot requirement' );
is( os_of( node_profile(undef) )->{loader},
    undef, 'a node that asks for no firmware states no Secure Boot requirement either' );

# A value libvirt cannot select is refused by name, and the refusal names both values a node
# may ask for. A typo must not leave the node on a firmware it did not ask for.
my $error = xCAT::KVMUtils::firmware_error( 'efi-secure', 'cn1' );
like( $error, qr/firmware:efi-secure\b/, 'a value that is not a firmware is refused by name' );
like( $error, qr/firmware:efi-secureboot/,
    'and the refusal names firmware:efi-secureboot, so the typo can be corrected from it' );

# vm.othersettings can name a machine type, and guest_os writes it over the one the profile
# chose. An x86_64 node that asks for efi is moved to q35 by guest_arch_profile, because every
# x86_64 OVMF descriptor targets pc-q35-* only, so a machine: setting naming i440fx takes the
# node to a machine type no UEFI firmware fits. libvirt then answers "Unable to find 'efi'
# firmware that is compatible with the current configuration", which names neither the node nor
# either setting.
my $conflict = xCAT::KVMUtils::firmware_machine_error( 'efi-secureboot', 'pc', 'x86_64', 'cn1' );
like( $conflict, qr/\bcn1\b/, 'the refusal names the node' );
like( $conflict, qr/firmware:efi-secureboot/, 'and the firmware the node asked for' );
like( $conflict, qr/machine:pc\b/,           'and the machine type that cannot carry it' );
like( $conflict, qr/q35/, 'and the machine type that can, so the conf can be corrected from it' );

like( xCAT::KVMUtils::firmware_machine_error( 'efi', 'pc-i440fx-rhel10.0.0', 'x86_64', 'cn1' ),
    qr/machine:pc-i440fx-rhel10\.0\.0/, 'a versioned i440fx is refused by name' );

is( xCAT::KVMUtils::firmware_machine_error( 'efi-secureboot', 'q35', 'x86_64', 'cn1' ),
    undef, 'q35 is not refused' );

# xCAT does not know which machine types a hypervisor offers, so it judges only the i440fx
# family, whose descriptors carry no UEFI firmware. libvirt reports any other machine type it
# cannot use, and reg_linux_diskless_installation_flat relies on mkvm accepting machine:invalid
# so that it can measure the provisioning failure that follows.
is( xCAT::KVMUtils::firmware_machine_error( 'efi-secureboot', 'invalid', 'x86_64', 'cn1' ),
    undef, 'a machine type xCAT does not know is left to libvirt' );
is( xCAT::KVMUtils::firmware_machine_error( 'efi', 'pc-q35-rhel10.2.0', 'x86_64', 'cn1' ),
    undef, 'and so is a machine type that carries a UEFI firmware' );
is( xCAT::KVMUtils::firmware_machine_error( 'efi', 'pc-q35-rhel9.4.0', 'x86_64', 'cn1' ),
    undef, 'a versioned q35 is not refused' );
is( xCAT::KVMUtils::firmware_machine_error( 'efi-secureboot', undef, 'x86_64', 'cn1' ),
    undef, 'a node that names no machine type is not refused' );
is( xCAT::KVMUtils::firmware_machine_error( undef, 'pc', 'x86_64', 'cn1' ),
    undef, 'a node that asks for no firmware keeps i440fx' );
is( xCAT::KVMUtils::firmware_machine_error( 'efi', 'virt', 'riscv64', 'cn1' ),
    undef, 'the machine types of another architecture are not judged here' );

# <firmware> carries the features libvirt filters the descriptors by. It is not in the hash
# guest_os returns: the firmware attribute of <os> and the <firmware> child of <os> are one key
# of one hash for XMLout, and the attribute is the one that starts the selection. So
# add_firmware_features adds the element to the domain XMLout wrote, which is what kvm.pm does.
my $features = xCAT::KVMUtils::firmware_features($sb);
is_deeply(
    $features,
    [ { name => 'secure-boot', enabled => 'yes' }, { name => 'enrolled-keys', enabled => 'yes' } ],
    'a Secure Boot node asks for secure-boot and for enrolled-keys'
);
is_deeply( xCAT::KVMUtils::firmware_features( node_profile('firmware:efi') ),
    [], 'firmware:efi asks for no firmware feature' );
is_deeply( xCAT::KVMUtils::firmware_features( node_profile(undef) ),
    [], 'and neither does a node that asks for no firmware' );
is_deeply( xCAT::KVMUtils::firmware_features(undef), [], 'and neither does an undefined profile' );

# The domain as kvm.pm writes it: the <os> of guest_os, then the features.
sub domain_of {
    my ($profile) = @_;
    my $os = XMLout( os_of($profile), RootName => 'os' );
    $os =~ s/^<\?xml[^>]*\?>\s*//;
    return xCAT::KVMUtils::add_firmware_features( "<domain type='kvm'>\n$os\n</domain>\n",
        xCAT::KVMUtils::firmware_features($profile) );
}

sub feature_enabled {
    my ( $xml, $name ) = @_;
    my ($node) =
      XML::LibXML->load_xml( string => $xml )
      ->findnodes("/domain/os/firmware/feature[\@name='$name']");
    return defined($node) ? $node->getAttribute('enabled') : undef;
}

my $sb_domain = domain_of($sb);
is( feature_enabled( $sb_domain, 'enrolled-keys' ),
    'yes', 'the domain of a Secure Boot node asks for a firmware whose keys are enrolled' );
is( feature_enabled( $sb_domain, 'secure-boot' ),
    'yes', 'and for one that verifies what it boots' );
is( XML::LibXML->load_xml( string => $sb_domain )->findnodes('/domain/os')->[0]
      ->getAttribute('firmware'),
    'efi', 'and it keeps firmware="efi" on <os>, which is what starts the firmware selection' );
is( XML::LibXML->load_xml( string => $sb_domain )->findnodes('/domain/os/loader')->[0]
      ->getAttribute('secure'),
    'yes', 'and keeps <loader secure="yes"/> beside the features' );

# A node that asked only for UEFI gets no <firmware>, so it keeps taking the descriptor its
# hypervisor prefers.
foreach my $othersettings ( 'firmware:efi', undef ) {
    my $name = defined($othersettings) ? $othersettings : 'no firmware';
    my $domain = domain_of( node_profile($othersettings) );
    is_deeply(
        [ XML::LibXML->load_xml( string => $domain )->findnodes('/domain/os/firmware') ],
        [], "$name states no firmware feature" );
}

is( xCAT::KVMUtils::add_firmware_features( "<domain type='kvm'><os/></domain>", [] ),
    "<domain type='kvm'><os/></domain>",
    'a domain that asks for no feature is returned unchanged, not re-serialised' );
is( xCAT::KVMUtils::add_firmware_features( "<domain type='kvm'/>", $features ),
    "<domain type='kvm'/>", 'a domain with no <os> is returned unchanged' );

done_testing();
