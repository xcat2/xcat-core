#!/usr/bin/perl
# A DHCPv6 client with no reservation must still be told what to boot.
#
# Sequential discovery starts with a node xCAT has never seen: it has no DUID in the dhcp6duid
# table and no reservation, so kea_node_reservations6 writes nothing for it. The subnet has a
# dynamicrange, so Kea answers it with an address -- measured on xcat88-mn, where an unknown
# client took 2001:db8:188::1000 from the pool. What it never gets is option 59, bootfile-url,
# because that option is written only inside a reservation. The node boots nothing and
# seq_discovery_ipv6 fails before it powers the node on.
#
# DHCPv4 solves this with client classes keyed on option 93, the client system architecture, each
# naming a boot file. RFC 5970 gives DHCPv6 the same registry in option 61 and the boot file URL
# in option 59, so the same shape works. Two things were missing:
#
#   render_dhcp6_config dropped client-classes entirely. render_dhcp4_config renders them.
#   _render_subnet6 dropped the additional-class list. _render_subnet4 renders it.
#
# So classes could not reach the config even once something built them.
use strict;
use warnings;
use Test::More tests => 18;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use JSON;

require xCAT::DHCP::Backend::Kea;
require xCAT::DHCP::BootPolicy;

my $backend = xCAT::DHCP::Backend::Kea->new( kea_version => '3.0.1' );

# --- the renderer must carry classes into Dhcp6 -------------------------------------------------
my $json = decode_json(
    $backend->render_dhcp6_config({
        interfaces     => ['eth1'],
        subnets        => [ { id => 10001, subnet => '2001:db8:188::/64',
                              additional_client_classes => ['xcat-uefi6-x64'] } ],
        'client-classes' => [
            { name => 'xcat-uefi6-x64',
              test => 'option[61].hex == 0x0007',
              'option-data' => [ { name => 'bootfile-url', data => 'tftp://[2001:db8:188::1]/x' } ] },
        ],
    })
);

ok( exists $json->{Dhcp6}{'client-classes'},
    'render_dhcp6_config emits client-classes' )
    or diag 'Dhcp6 keys: ' . join( ' ', sort keys %{ $json->{Dhcp6} } );
is( scalar @{ $json->{Dhcp6}{'client-classes'} || [] }, 1, 'it keeps the one class it was given' );
is( $json->{Dhcp6}{'client-classes'}[0]{name}, 'xcat-uefi6-x64', 'with its name' );
is( $json->{Dhcp6}{'client-classes'}[0]{test}, 'option[61].hex == 0x0007',
    'and its option 61 architecture test' );
is( $json->{Dhcp6}{'client-classes'}[0]{'option-data'}[0]{name}, 'bootfile-url',
    'and the bootfile-url it supplies' );

# Kea 3.0.1 takes the modern spelling, the same choice _render_subnet4 already makes.
my $sn = $json->{Dhcp6}{subnet6}[0];
is_deeply( $sn->{'evaluate-additional-classes'}, ['xcat-uefi6-x64'],
           '_render_subnet6 scopes the class to the subnet that named it' );

# --- the classes themselves ---------------------------------------------------------------------
my $host = '[2001:db8:188::1]';

# An eval, not a bare call: a missing sub would end the file and the assertions below would report
# nothing at all. Absent builder and wrong classes must both read as a failure here.
sub classes6 {
    my (%opts) = @_;
    my $out = eval { xCAT::DHCP::BootPolicy->kea_client_classes6(%opts) };
    return $out && ref($out) eq 'ARRAY' ? $out : [];
}

my $classes = classes6( uri_host => $host, ipxe_uefi => 1, tftpdir => '/tftpboot' );

my ($x64) = grep { $_->{test} =~ /0x0007/ } @$classes;
ok( $x64, 'an x86_64 UEFI class is built' );
is( $x64 && $x64->{'option-data'}[0]{data},
    "tftp://$host/xcat/ipxe/x86_64-sb/snponly-shim.efi",
    'it hands the signed iPXE shim, the same first stage a reserved node gets' );

my ($aa) = grep { $_->{test} =~ /0x000b/ } @$classes;
is( $aa && $aa->{'option-data'}[0]{data}, "tftp://$host/boot/grub2/grub2.aarch64",
    'aarch64 gets its grub2 loader' );

my ($rv) = grep { $_->{test} =~ /0x001b/ } @$classes;
is( $rv && $rv->{'option-data'}[0]{data}, "tftp://$host/boot/grub2/grub2.riscv64",
    'riscv64 gets its grub2 loader' );

# Naming a file the TFTP server does not have costs the client a timeout it cannot diagnose, which
# is the reason the DHCPv4 classes check the loader before naming it.
my $no_loader = classes6( uri_host => $host, ipxe_uefi => 0, tftpdir => '/tftpboot' );
is( scalar( grep { $_->{test} =~ /0x0007/ } @$no_loader ), 0,
    'with no iPXE shim on disk the x86_64 class is left out rather than pointing at nothing' );

# --- the SECOND stage, which is what a findme needs ---------------------------------------------
# The class above answers the firmware and hands it the shim. The shim starts iPXE, which solicits
# again carrying the iPXE user class. A client xCAT has never seen matches no per-node class, so
# its only match is the architecture class above and it is handed the shim a second time. It never
# fetches a kernel and never sends a findme. mknb writes a per-network script that carries
# destiny=discover and no node name; nothing named it over DHCPv6.
my $withnet = classes6( uri_host => $host, ipxe_uefi => 1, tftpdir => '/tftpboot',
                        net => '2001:db8:188::', prefix => 64 );
my ($second) = grep { $_->{test} =~ /iPXE/ } @$withnet;
ok( $second, 'an iPXE second-stage class is built for the network' );
is( $second && $second->{'option-data'}[0]{data},
    "http://$host/tftpboot/xcat/ipxe/nets/2001:db8:188::_64.uefi",
    'and it names the per-network script mknb wrote, the one carrying destiny=discover' );
like( $second ? $second->{test} : '', qr/option\[61\]/,
      'it is scoped to an x86_64 UEFI client, not to every iPXE client' );

# Ordering is half the fix. Kea takes the first class that defines an option, so the second stage
# must be offered before the architecture class that names the shim.
my ($ipxe_at) = grep { $withnet->[$_]{test} =~ /iPXE/ } 0 .. $#$withnet;
my ($arch_at) =
  grep { $withnet->[$_]{test} =~ /0x0007/ && $withnet->[$_]{test} !~ /iPXE/ } 0 .. $#$withnet;
ok( defined($ipxe_at) && defined($arch_at) && $ipxe_at < $arch_at,
    'the second stage is matched before the first, or iPXE is handed the shim again' );

# --- each class answers only the network that lists it ------------------------------------------
# The classes of every network are global in Dhcp6, and the subnet list only adds them to its own
# clients. A class without the additional-only flag is also evaluated for every client of every
# subnet, so a discovery client on the second network is handed the URL of the first.
my $two = $backend->render_dhcp6_config({
    interfaces => ['eth1'],
    subnets    => [
        { id => 1, subnet => '2001:db8:188::/64', additional_client_classes => [ map { $_->{name} } @$withnet ] },
    ],
    'client-classes' => $withnet,
});
my $rendered = decode_json($two)->{Dhcp6}{'client-classes'} || [];
is( scalar(@$rendered), scalar(@$withnet), 'every per-network class is rendered' );
is_deeply( [ map { $_->{name} } grep { !( $_->{'only-in-additional-list'} ) } @$rendered ], [],
    'and each one is evaluated only for a subnet that lists it' );

# --- the discovery script is fetched from the HTTP port of the site -----------------------------
# The per-node script URL follows site.httpport. The per-network one must too, or with
# httpport=8080 an unknown node loads iPXE and cannot fetch its network script.
my $on8080 = classes6( uri_host => $host, ipxe_uefi => 1, tftpdir => '/tftpboot',
                       net => '2001:db8:188::', prefix => 64, httpport => 8080 );
my ($second8080) = grep { $_->{test} =~ /iPXE/ } @$on8080;
is( $second8080 && $second8080->{'option-data'}[0]{data},
    "http://$host:8080/tftpboot/xcat/ipxe/nets/2001:db8:188::_64.uefi",
    'the second-stage URL carries site.httpport' );
