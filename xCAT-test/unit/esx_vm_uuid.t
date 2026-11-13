#!/usr/bin/env perl
# vpd.uuid holds the system UUID that the guest reports, and makedhcp derives the DHCPv6 DUID of a
# node from it. VMware writes uuid.bios into the SMBIOS type 1 structure unencoded, so the UUID that
# an ESX guest reports depends on the version of the SMBIOS entry point its firmware builds: a guest
# behind a 2.7 entry point reports the first three fields swapped, and a guest behind a 2.4 entry
# point reports them unchanged. The esx plugin must therefore convert config.uuid per VM.
#
# The expected values come from the measurement in VersatusHPC/xcat-internal issue 349, on ESXi
# 9.1.0 (build 25370933), 8.0.3 (build 25429389) and 7.0.3 (build 24784741). Every guest had
# uuid.bios = "12 34 56 78 12 34 4b cd-98 76 12 34 56 78 90 ab", a guest ISO printed product_uuid
# and the SMBIOS entry point, and a UEFI guest booted over PXEv6 while the host captured its DUID.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

BEGIN {
    $ENV{XCATROOT} = repo_path('xCAT-server');
    $ENV{XCATCFG}  = 'SQLite:' . tempdir( CLEANUP => 1 );
}

use xCAT::VMCommon;
require( repo_path('xCAT-server/lib/xcat/plugins/dhcp.pm') );

# uuid.bios of every measured VM, which is config.uuid.
my $config = '12345678-1234-4bcd-9876-1234567890ab';

# What a guest behind an SMBIOS 2.7 entry point reports, from product_uuid in the guest.
my $reported_27 = '78563412-3412-cd4b-9876-1234567890ab';

# The DUID that the UEFI guest sent over PXEv6: 00:04 and the raw SMBIOS bytes.
my $pxev6_duid = '00:04:12:34:56:78:12:34:4b:cd:98:76:12:34:56:78:90:ab';

# EFI firmware builds an SMBIOS 2.7 entry point at every measured hardware version. 8 to 22 on
# ESXi 9.1, and 11, 13, 17, 19, 20 and 21 on 8.0 and 7.0.
my @efi_27 = ( 8, 9, 10, 11, 12, 13, 17, 19, 20, 21, 22 );

# BIOS firmware builds an SMBIOS 2.7 entry point from hardware version 12. Measured at 12 and 13 on
# ESXi 8.0 and 7.0, and at 13, 17 and 22 on 9.1.
my @bios_27 = ( 12, 13, 17, 22 );

# BIOS firmware builds an SMBIOS 2.4 entry point up to hardware version 11. Measured at 8 and 11 on
# ESXi 9.1 and at 11 on 8.0 and 7.0.
my @bios_24 = ( 8, 11 );

foreach my $version (@efi_27) {
    is( xCAT::VMCommon::esx_guest_uuid( $config, 'efi', "vmx-$version" ), $reported_27,
        "an efi vmx-$version guest reports config.uuid swapped" );
    is( xCAT::VMCommon::esx_guest_uuid( $reported_27, 'efi', "vmx-$version" ), $config,
        "and mkvm gives an efi vmx-$version guest config.uuid swapped back from vpd.uuid" );
    is( xCAT_plugin::dhcp::kea_duid_from_uuid( $reported_27, 'firmware' ), $pxev6_duid,
        "the default reservation of an efi vmx-$version guest is the DUID its firmware sends" );
}

foreach my $version (@bios_27) {
    is( xCAT::VMCommon::esx_guest_uuid( $config, 'bios', "vmx-$version" ), $reported_27,
        "a bios vmx-$version guest reports config.uuid swapped" );
    is( xCAT::VMCommon::esx_guest_uuid( $reported_27, 'bios', "vmx-$version" ), $config,
        "and mkvm gives a bios vmx-$version guest config.uuid swapped back from vpd.uuid" );
}

# BIOS network boot is IPv4 only, so these guests reserve no DHCPv6 address. The UUID they report
# is still what vpd.uuid and rinv must carry.
foreach my $version (@bios_24) {
    is( xCAT::VMCommon::esx_guest_uuid( $config, 'bios', "vmx-$version" ), $config,
        "a bios vmx-$version guest reports config.uuid unchanged" );
    is( xCAT::VMCommon::esx_guest_uuid( $config, 'bios', $version ), $config,
        "and a bare hardware version $version reads the same as vmx-$version" );
}

# The host default firmware and hardware version are both newer than hardware version 11, so a VM
# that names neither reads the SMBIOS 2.7 tables.
is( xCAT::VMCommon::esx_guest_uuid( $config, undef, undef ), $reported_27,
    'a guest of unknown firmware and hardware version reports config.uuid swapped' );
is( xCAT::VMCommon::esx_guest_uuid( $config, 'bios', undef ), $reported_27,
    'a bios guest of unknown hardware version reports config.uuid swapped' );
is( xCAT::VMCommon::esx_guest_uuid( $config, 'efi', undef ), $reported_27,
    'an efi guest of unknown hardware version reports config.uuid swapped' );
is( xCAT::VMCommon::esx_guest_uuid( $config, 'BIOS', 'vmx-11' ), $config,
    'the firmware name is matched without regard to case' );
is( xCAT::VMCommon::esx_guest_uuid( undef, 'efi', 'vmx-17' ), undef, 'a guest with no UUID converts to no UUID' );

# mkvm learns the firmware and the hardware version from vm.othersettings, because a
# VirtualMachineConfigSpec carries both as fields and extraConfig does not apply them.
my ( $spec, $extra ) = xCAT::VMCommon::esx_vmx_settings('firmware=efi');
is_deeply( $spec, { firmware => 'efi' }, 'othersettings firmware=efi selects efi firmware' );
is_deeply( $extra, [], 'and leaves no extraConfig option' );

( $spec, $extra ) = xCAT::VMCommon::esx_vmx_settings('virtualHW.version=11');
is_deeply( $spec, { version => 'vmx-11' }, 'othersettings virtualHW.version=11 selects hardware version 11' );

( $spec, $extra ) = xCAT::VMCommon::esx_vmx_settings('virtualHW.version=vmx-13');
is_deeply( $spec, { version => 'vmx-13' }, 'othersettings virtualHW.version=vmx-13 selects hardware version 13' );

( $spec, $extra ) = xCAT::VMCommon::esx_vmx_settings('firmware=BIOS;virtualHW.version=11;isolation.tools.copy.disable=TRUE;sched.mem.pin');
is_deeply( $spec, { firmware => 'bios', version => 'vmx-11' }, 'othersettings names both fields in any case' );
is_deeply( $extra, [ [ 'isolation.tools.copy.disable', 'TRUE' ], [ 'sched.mem.pin', undef ] ],
    'and every other setting stays an extraConfig option' );

( $spec, $extra ) = xCAT::VMCommon::esx_vmx_settings(undef);
is_deeply( $spec,  {}, 'an empty vm.othersettings names no field' );
is_deeply( $extra, [], 'and no extraConfig option' );

# The chain that mkvm follows: vpd.uuid and vm.othersettings give config.uuid of the new VM.
foreach my $case (
    [ 'firmware=bios;virtualHW.version=11', $config,      'a bios vmx-11 guest' ],
    [ 'firmware=bios;virtualHW.version=13', $reported_27, 'a bios vmx-13 guest' ],
    [ 'firmware=efi;virtualHW.version=11',  $reported_27, 'an efi vmx-11 guest' ],
    [ undef,                                $reported_27, 'a guest that names neither' ],
  )
{
    my ( $othersettings, $expected, $label ) = @$case;
    my ($fields) = xCAT::VMCommon::esx_vmx_settings($othersettings);
    is( xCAT::VMCommon::esx_guest_uuid( $config, $fields->{firmware}, $fields->{version} ), $expected,
        "mkvm gives $label a config.uuid that its guest reports as vpd.uuid" );
}

done_testing();
