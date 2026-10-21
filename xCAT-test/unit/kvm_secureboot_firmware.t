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
# <loader secure='yes'/> is the requirement libvirt reads during firmware selection. Measured
# with libvirt 11.10.0 on rome01: <os firmware='efi'> with that element resolves to
# OVMF_CODE.secboot.fd and <smm state='on'/>, and the same domain with
# <firmware><feature enabled='no' name='secure-boot'/></firmware> resolves to OVMF_CODE.fd.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;

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

done_testing();
