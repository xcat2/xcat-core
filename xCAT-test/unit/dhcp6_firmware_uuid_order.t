#!/usr/bin/env perl
# Which byte order of vpd.uuid the firmware of a node sends in its DUID-UUID, which decides which
# DHCPv6 client of the node the reserved address belongs to.
#
# EDK2 copies the SMBIOS UUID bytes into its DUID, and SMBIOS 2.6 and later store the first three
# fields little-endian, so on a physical node the firmware sends the byte swap of the vpd.uuid
# text. A KVM guest that xCAT defines is the other way round: getNodeUUID writes the byte swap of
# vpd.uuid into the libvirt domain, qemu stores THAT little-endian, and the two swaps cancel. The
# firmware of such a guest sends vpd.uuid unswapped, which is the RFC 4122 or canonical order.
#
# Measured 2026-11-08 on xcat88-cn: the firmware and the OpenEmbedded Genesis image both sent
# 00:04:0c:3f:8d:41:... from vpd.uuid 0c3f8d41-6a52-4e7b-..., the canonical order, while iPXE sent
# the swap. The address was reserved for the swap, so Genesis took a dynamic address and xcatd
# could not name it.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;
use xCAT::DHCP::BootPolicy;

can_ok( 'xCAT::DHCP::BootPolicy', 'dhcp6_firmware_uuid_order' );

sub order_for {
    my (@args) = @_;
    my $out = eval { xCAT::DHCP::BootPolicy->dhcp6_firmware_uuid_order(@args) };
    diag($@) if $@;
    return $out;
}

is( order_for('kvm'), 'canonical',
    'xCAT defines the domain of a kvm node, so its firmware sends vpd.uuid unswapped' );
is( order_for('KVM'), 'canonical', 'the mgt value is matched without regard to case' );

foreach my $mgt ( 'ipmi', 'openbmc', 'hmc', 'blade', '' ) {
    is( order_for($mgt), 'firmware',
        "a node managed by '$mgt' has firmware that swaps the bytes of vpd.uuid" );
}
is( order_for(undef), 'firmware', 'a node with no mgt attribute is treated as physical' );
is( order_for(),      'firmware', 'no argument is treated as physical' );

done_testing();
