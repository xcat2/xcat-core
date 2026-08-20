use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

use xCAT::DHCP::BootPolicy;

my $fallback_classes = xCAT::DHCP::BootPolicy->kea_client_classes();
is( scalar @$fallback_classes, 5, 'Kea boot policy omits xNBA classes when xNBA loaders are unavailable' );
my %fallback_by_name = map { $_->{name} => $_ } @$fallback_classes;
is( $fallback_by_name{'xcat-bios'}{'boot-file-name'}, 'pxelinux.0', 'BIOS clients fall back to pxelinux.0 without xNBA loaders' );
ok( !exists $fallback_by_name{'xcat-xnba-bios'}, 'xNBA user-class is not advertised without xNBA kpxe' );

my $classes = xCAT::DHCP::BootPolicy->kea_client_classes(xnba_kpxe => 1, xnba_efi => 1);
is( scalar @$classes, 6, 'Kea boot policy renders expected xNBA client classes' );

my %by_name = map { $_->{name} => $_ } @$classes;
is( $by_name{'xcat-bios'}{'boot-file-name'}, 'xcat/xnba.kpxe', 'BIOS clients receive xNBA kpxe' );
like( $by_name{'xcat-bios'}{test}, qr/not \(\(option\[77\]\.exists/, 'generic BIOS class excludes xNBA second-stage clients' );
like( $by_name{'xcat-uefi-x64'}{test}, qr/0x0007/, 'UEFI x64 class matches architecture 7' );
like( $by_name{'xcat-uefi-x64'}{test}, qr/0x0009/, 'UEFI x64 class matches architecture 9' );
like( $by_name{'xcat-uefi-x64'}{test}, qr/0x0010/, 'UEFI x64 class matches HTTP boot architecture 16' );
like( $by_name{'xcat-uefi-x64'}{test}, qr/not \(\(option\[77\]\.exists/, 'generic UEFI class excludes xNBA second-stage clients' );
is( $by_name{'xcat-aarch64'}{'boot-file-name'}, 'boot/grub2/grub2.aarch64', 'AArch64 clients receive grub2 boot file' );
is( $by_name{'xcat-ppc64'}{'boot-file-name'}, '/boot/grub2/grub2.ppc', 'POWER clients receive grub2 Open Firmware boot file' );
is( $by_name{'xcat-ppc64'}{test}, 'option[93].hex == 0x000c', 'POWER class keeps existing POWER architecture id' );
is( $by_name{'xcat-riscv64'}{'boot-file-name'}, 'boot/grub2/grub2.riscv64', 'RISC-V 64-bit UEFI clients receive the riscv64 grub2 boot file' );
is( $by_name{'xcat-riscv64'}{test}, 'option[93].hex == 0x001b', 'RISC-V 64-bit UEFI class matches IANA client architecture 27 only' );
is( $fallback_by_name{'xcat-riscv64'}{'boot-file-name'}, 'boot/grub2/grub2.riscv64', 'riscv64 clients get grub2 even without xNBA loaders' );
unlike( join( ' ', map { $_->{test} } @$classes ), qr/0x001[9ade]/, 'no class claims the RISC-V 32-bit or 128-bit architecture ids' );

my $xnba_classes = xCAT::DHCP::BootPolicy->kea_xnba_node_classes(
    xnba_efi => 1,
    nodes    => [
        {
            node        => 'cn01',
            mac         => '52:54:4b:10:00:11',
            next_server => '10.241.10.1',
            httpport    => '80',
        },
    ],
);
is( scalar @$xnba_classes, 2, 'xNBA node policy renders BIOS and UEFI second-stage classes' );
my %xnba_by_name = map { $_->{name} => $_ } @$xnba_classes;
my $xnba_bios = $xnba_by_name{'xcat-xnba-cn01-52544b100011-bios'};
ok( $xnba_bios, 'xNBA BIOS second-stage class is named by node and MAC' );
like( $xnba_bios->{test}, qr/option\[77\]\.text == 'xNBA'/, 'xNBA second-stage class matches text user-class' );
like( $xnba_bios->{test}, qr/substring\(option\[77\]\.hex,1,4\) == 'xNBA'/, 'xNBA second-stage class matches tuple-encoded user-class' );
like( $xnba_bios->{test}, qr/pkt4\.mac == 0x52544b100011/, 'xNBA second-stage class matches the node MAC' );
is( $xnba_bios->{'boot-file-name'}, 'http://10.241.10.1/tftpboot/xcat/xnba/nodes/cn01', 'xNBA BIOS class returns the node script URL without the default HTTP port' );
is( $xnba_bios->{'user-context'}{'xcat-purpose'}, 'xnba-second-stage', 'xNBA class carries removable user-context' );
is( $xnba_by_name{'xcat-xnba-cn01-52544b100011-uefi'}{'boot-file-name'}, 'http://10.241.10.1/tftpboot/xcat/xnba/nodes/cn01.uefi', 'xNBA UEFI class returns the UEFI node script URL without the default HTTP port' );
like( $xnba_by_name{'xcat-xnba-cn01-52544b100011-uefi'}{test}, qr/0x0007/, 'xNBA UEFI class matches standard UEFI PXE architecture 7' );
like( $xnba_by_name{'xcat-xnba-cn01-52544b100011-uefi'}{test}, qr/0x0009/, 'xNBA UEFI class matches alternate UEFI PXE architecture 9' );
like( $xnba_by_name{'xcat-xnba-cn01-52544b100011-uefi'}{test}, qr/0x0010/, 'xNBA UEFI class matches UEFI HTTP boot architecture 16' );

my $altport_classes = xCAT::DHCP::BootPolicy->kea_xnba_node_classes(
    xnba_efi => 1,
    nodes    => [
        {
            node        => 'cn02',
            mac         => '52:54:4b:10:00:12',
            next_server => '10.241.10.1',
            httpport    => '8080',
        },
        {
            node        => 'cn03',
            mac         => '52:54:4b:10:00:13',
            next_server => '10.241.10.1',
        },
    ],
);
my %altport_by_name = map { $_->{name} => $_ } @$altport_classes;
is( $altport_by_name{'xcat-xnba-cn02-52544b100012-bios'}{'boot-file-name'}, 'http://10.241.10.1:8080/tftpboot/xcat/xnba/nodes/cn02', 'a non-default HTTP port is kept in the node script URL' );
is( $altport_by_name{'xcat-xnba-cn02-52544b100012-uefi'}{'boot-file-name'}, 'http://10.241.10.1:8080/tftpboot/xcat/xnba/nodes/cn02.uefi', 'a non-default HTTP port is kept in the UEFI node script URL' );
is( $altport_by_name{'xcat-xnba-cn03-52544b100013-bios'}{'boot-file-name'}, 'http://10.241.10.1/tftpboot/xcat/xnba/nodes/cn03', 'an unset HTTP port falls back to the default and is omitted' );

my $combined_classes = xCAT::DHCP::BootPolicy->kea_client_classes(
    xnba_kpxe         => 1,
    xnba_efi          => 1,
    xnba_node_classes => $xnba_classes,
);
is( $combined_classes->[0]{name}, 'xcat-xnba-cn01-52544b100011-bios', 'node-specific xNBA classes have priority over generic boot classes' );

my $network_classes = xCAT::DHCP::BootPolicy->kea_xnba_network_classes(
    net         => '192.0.2.0',
    prefix      => 24,
    next_server => '192.0.2.10',
    httpport    => '8080',
    xnba_kpxe   => 1,
    xnba_efi    => 1,
);
is( scalar @$network_classes, 2, 'xNBA network policy renders BIOS and UEFI fallback classes' );
my %network_by_name = map { $_->{name} => $_ } @$network_classes;
my $network_bios = $network_by_name{'xcat-xnba-net-192.0.2.0_24-bios'};
ok( $network_bios, 'xNBA network BIOS class is named by subnet' );
is(
    $network_bios->{'boot-file-name'},
    'http://192.0.2.10:8080/tftpboot/xcat/xnba/nets/192.0.2.0_24',
    'xNBA network BIOS class returns the subnet script URL'
);
like( $network_bios->{test}, qr/option\[77\]\.text == 'xNBA'/, 'xNBA network class matches the xNBA user class' );
like( $network_bios->{test}, qr/option\[93\]\.hex == 0x0000/, 'xNBA network BIOS class matches BIOS clients' );
unlike( $network_bios->{test}, qr/pkt4\.mac/, 'xNBA network fallback does not require a known MAC' );
ok( $network_bios->{additional_only}, 'xNBA network fallback is limited to its owning subnet' );
is(
    $network_by_name{'xcat-xnba-net-192.0.2.0_24-uefi'}{'boot-file-name'},
    'http://192.0.2.10:8080/tftpboot/xcat/xnba/nets/192.0.2.0_24.uefi',
    'xNBA network UEFI class returns the subnet UEFI script URL'
);
like(
    $network_by_name{'xcat-xnba-net-192.0.2.0_24-uefi'}{test},
    qr/0x0010/,
    'xNBA network UEFI class matches HTTP boot clients'
);

is_deeply(
    xCAT::DHCP::BootPolicy->kea_xnba_network_classes(
        net         => '192.0.2.0',
        prefix      => 24,
        next_server => '192.0.2.10',
        xnba_kpxe   => 1,
    ),
    [
        {
            name             => 'xcat-xnba-net-192.0.2.0_24-bios',
            test             => xCAT::DHCP::BootPolicy::xnba_user_class_test()
              . ' and option[93].hex == 0x0000',
            'boot-file-name' => 'http://192.0.2.10/tftpboot/xcat/xnba/nets/192.0.2.0_24',
            additional_only  => 1,
        },
    ],
    'xNBA network policy omits unavailable loaders and the default HTTP port'
);
is_deeply(
    xCAT::DHCP::BootPolicy->kea_xnba_network_classes(
        net       => '192.0.2.0',
        prefix    => 24,
        xnba_kpxe => 1,
    ),
    [],
    'xNBA network policy requires a next server'
);

done_testing();
