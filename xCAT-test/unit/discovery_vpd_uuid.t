#!/usr/bin/perl
# A discovered node needs its UUID recorded, or it cannot be given an address over DHCPv6.
#
# dhcp6_client_duids builds the DHCPv6 identity of a node from vpd.uuid. There is no dhcp6duid
# table. Sequential discovery writes mac, hosts, ipmi, nodepos, nodelist, nodehm and chain for
# the node it assigns, and never wrote vpd, so the reservation fell back to a DUID-LL built from
# the MAC -- which none of the three boot stages sends. Measured on xcat88-mn: the firmware, iPXE
# and the Genesis image all send a DUID-UUID.
#
# The findme request already carries the value. Both images read product_uuid and say why: "makedhcp
# derives the firmware DUID from vpd.uuid, so report the UUID that dmidecode prints."
use strict;
use warnings;
use Test::More tests => 8;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

require xCAT::DiscoveryUtils;

can_ok( 'xCAT::DiscoveryUtils', 'vpd_attribs_from_findme' );

my $real = xCAT::DiscoveryUtils::vpd_attribs_from_findme(
    { uuid => ['0C3F8D41-6A52-4E7B-9F10-2D8C54AB7731'] } );
is( $real->{uuid}, '0c3f8d41-6a52-4e7b-9f10-2d8c54ab7731',
    'a UUID from SMBIOS is recorded, in one case so the DUID is built the same way every boot' );

# The OpenEmbedded image synthesises "<machine type>-<serial>-<first mac>" when the firmware
# reports no product_uuid. That is not a UUID, and a DUID built from it would match no client.
my $made_up = xCAT::DiscoveryUtils::vpd_attribs_from_findme(
    { uuid => ['kvm-unknown-42:2a:32:70:a2:01'] } );
is_deeply( $made_up, {}, 'the synthesised fallback of the image is not recorded as a UUID' );

is_deeply( xCAT::DiscoveryUtils::vpd_attribs_from_findme( {} ), {},
           'a request carrying no uuid records nothing' );
is_deeply( xCAT::DiscoveryUtils::vpd_attribs_from_findme(undef), {},
           'and neither does no request at all' );

# Called as a class method, which is how the plugins reach the other helpers of this module.
my $as_class = xCAT::DiscoveryUtils->vpd_attribs_from_findme(
    { uuid => ['0c3f8d41-6a52-4e7b-9f10-2d8c54ab7731'] } );
is( $as_class->{uuid}, '0c3f8d41-6a52-4e7b-9f10-2d8c54ab7731', 'the class form works too' );

# A bare string, which is what a hand-built request can carry.
my $plain = xCAT::DiscoveryUtils::vpd_attribs_from_findme(
    { uuid => '0c3f8d41-6a52-4e7b-9f10-2d8c54ab7731' } );
is( $plain->{uuid}, '0c3f8d41-6a52-4e7b-9f10-2d8c54ab7731', 'an unwrapped value is read as well' );

is_deeply( xCAT::DiscoveryUtils::vpd_attribs_from_findme( { uuid => [''] } ), {},
           'an empty element records nothing' );
