#!/usr/bin/perl
# A UEFI node that chainloads is two DHCPv6 clients, and the byte order of the DUID cannot tell
# them apart.
#
# dhcp6_client_duid_list derives both DUIDs from vpd.uuid and labels the byte-swapped one
# 'firmware' and the unswapped one 'ipxe', then gives each the boot file of that stage. Which
# label is right does not follow from vpd.uuid. Measured on xcat88-mn with Kea DHCPv6 at DEBUG,
# one boot of xcat88-cn:
#
#   SOLICIT  client-id 00:04:0c:3f:8d:41:...   <- the firmware, no option 15
#   SOLICIT  client-id 00:04:41:8d:3f:0c:...   <- iPXE, option 15 = 00:04:69:50:58:45
#
# vpd.uuid is 0c3f8d41-6a52-4e7b-9f10-2d8c54ab7731 and the libvirt domain carries its byte-swap,
# because getNodeUUID in kvm.pm swaps vpd.uuid when it writes the domain. The firmware reports the
# SMBIOS bytes of the domain uuid, which is vpd.uuid unswapped, and iPXE converts those to RFC
# 4122, which is the swap. A domain created from vpd.uuid directly gives the opposite pair, so
# both orders are real.
#
# The firmware therefore matched the reservation labelled 'ipxe' and was given an http:// URL,
# which a UEFI PXEv6 boot option cannot fetch: "PXE-E53: No boot filename received". iPXE matched
# the one labelled 'firmware', was given the shim a second time and stopped at
# "Failed to open ipxe.efi".
#
# The DHCPv4 path never had this problem because it splits the stages on what the client reports,
# the iPXE feature sub-options of option 175. Over DHCPv6 the equivalent report is option 15, the
# User Class, which iPXE sends as a length-prefixed "iPXE" and the firmware does not send at all.
use strict;
use warnings;
use Test::More tests => 16;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

require xCAT::DHCP::BootPolicy;

# --- the discriminator ---------------------------------------------------------------------
# Both subs are named here, because every assertion below reads a value one of them returns. An
# absent sub returns nothing, and nothing satisfies an assertion that an answer is empty -- so
# without these two the emptiness tests at the end would pass on an unfixed tree.
can_ok( 'xCAT::DHCP::BootPolicy', 'dhcp6_ipxe_user_class_test' );
can_ok( 'xCAT::DHCP::BootPolicy', 'kea_node_boot_classes6' );

my $ipxe = eval { xCAT::DHCP::BootPolicy->dhcp6_ipxe_user_class_test() } || '';
like( $ipxe, qr/option\[15\]/,
    'the iPXE test reads option 15, the DHCPv6 User Class' );
like( $ipxe, qr/'iPXE'/,
    'it compares against iPXE, the string iPXE puts in that option' );
like( $ipxe, qr/substring\(\s*option\[15\]\.hex\s*,\s*2\s*,\s*4\s*\)/,
    'it skips the two length octets the User Class option prefixes, so 00:04:69:50:58:45 matches' );
ok( ( length($ipxe) && $ipxe !~ /option\[1\]|duid/i ),
    'the discriminator names no DUID: byte order must not decide the stage' );

# --- the two per-node classes --------------------------------------------------------------
# Returns whatever the sub returned, so a missing sub gives undef and not an empty list. An
# empty list is a real answer here -- a node with no second stage -- and the two must not look
# the same to an assertion.
sub classes {
    my (%opts) = @_;
    my $out = eval { xCAT::DHCP::BootPolicy->kea_node_boot_classes6(%opts) };
    diag($@) if $@;
    return $out;
}

my $LOADER = 'tftp://[2001:db8:188::1]/xcat/ipxe/x86_64-sb/snponly-shim.efi';
my $SCRIPT = 'http://[2001:db8:188::1]/tftpboot/xcat/ipxe/nodes/xcat88-cn.uefi';
my @DUIDS  = (
    '00:04:0c:3f:8d:41:6a:52:4e:7b:9f:10:2d:8c:54:ab:77:31',
    '00:04:41:8d:3f:0c:52:6a:7b:4e:9f:10:2d:8c:54:ab:77:31',
);

my $got = classes(
    node       => 'xcat88-cn',
    duids      => [@DUIDS],
    loader_url => $LOADER,
    script_url => $SCRIPT,
);
is_deeply( [ map { ref } @{ $got || [] } ], [ 'HASH', 'HASH' ],
    'a chainloading node gets one class per boot stage' );

my %by_url;
foreach my $class ( @{ $got || [] } ) {
    foreach my $opt ( @{ $class->{'option-data'} || [] } ) {
        $by_url{ $opt->{data} } = $class if ( $opt->{name} || '' ) eq 'bootfile-url';
    }
}
my $fw_class   = $by_url{$LOADER};
my $ipxe_class = $by_url{$SCRIPT};
ok( $fw_class,   'one class serves the first-stage loader over tftp' );
ok( $ipxe_class, 'the other serves the boot script of the node' );

ok( ( length($ipxe) && ( $ipxe_class->{test} || '' ) =~ /\Q$ipxe\E/ ),
    'the boot script goes only to a client that reports itself as iPXE' );
like( $fw_class->{test} || '', qr/not\s*\(/,
    'the loader goes to a client that does not report itself as iPXE' );

# Both orders in both tests: whichever order the platform sends, the node is recognised.
foreach my $duid (@DUIDS) {
    ( my $hex = $duid ) =~ s/://g;
    ok( ( ( $fw_class->{test} || '' ) =~ /\Q$hex\E/i
          && ( $ipxe_class->{test} || '' ) =~ /\Q$hex\E/i ),
        "both classes match DUID $duid, so neither order is assumed" );
}

# --- a node that does not chainload needs none of this -------------------------------------
is_deeply( classes( node => 'n1', duids => [], loader_url => $LOADER, script_url => $SCRIPT ),
    [], 'a node with no DUID gets no boot classes' );
is_deeply( classes( node => 'n1', duids => [ $DUIDS[0] ], loader_url => undef, script_url => undef ),
    [], 'a node with no boot file gets no boot classes' );

# A grub2 node is loaded by its firmware and has one client, so its reservation still carries the
# URL and no class is needed. kea_node_boot_classes6 is called only for a chainloading method, so
# the guard that matters here is that it never invents a class without both URLs.
is_deeply( classes( node => 'n1', duids => [ $DUIDS[0] ], loader_url => $LOADER ),
    [], 'without a script URL there is no second stage to split off' );
