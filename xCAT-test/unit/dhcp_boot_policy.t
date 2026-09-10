use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

use xCAT::DHCP::BootPolicy;

my $fallback_classes = xCAT::DHCP::BootPolicy->kea_client_classes();
is( scalar @$fallback_classes, 6, 'Kea boot policy omits xNBA classes when xNBA loaders are unavailable' );
my %fallback_by_name = map { $_->{name} => $_ } @$fallback_classes;
# Naming a loader that is not on disk costs the client a timeout it cannot
# diagnose, and pxelinux.0 in its place boots something nobody asked for. With
# no BIOS loader present the class is simply not written, and such a client is
# served an address and told nothing to fetch.
ok( !exists $fallback_by_name{'xcat-bios'}, 'no BIOS class is written when the BIOS loader is not there' );
ok( !exists $fallback_by_name{'xcat-etherboot'}, 'and no Etherboot class either, since it names the same file' );
ok( !exists $fallback_by_name{'xcat-xnba-bios'}, 'xNBA user-class is not advertised without xNBA kpxe' );

my $classes = xCAT::DHCP::BootPolicy->kea_client_classes(xnba_kpxe => 1, xnba_efi => 1);
is( scalar @$classes, 9, 'Kea boot policy renders expected xNBA client classes' );

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

# UEFI HTTP boot: firmware that boots over HTTP sends architecture id 28 and only
# accepts an offer whose boot file is a URL and whose reply is tagged HTTPClient.
my $httpboot = xCAT::DHCP::BootPolicy->kea_httpboot_network_classes(
    net         => '10.0.0.0',
    prefix      => 24,
    next_server => '10.0.0.1',
    tftpdir     => '/tftpboot',
);
is_deeply(
    $httpboot,
    [
        {
            name             => 'xcat-riscv64-http-10.0.0.0_24',
            test             => 'option[93].hex == 0x001c',
            additional_only  => 1,
            'boot-file-name' => 'http://10.0.0.1/tftpboot/boot/grub2/grub2.riscv64',
            'option-data'    => [
                {
                    name          => 'vendor-class-identifier',
                    data          => 'HTTPClient',
                    'always-send' => 1,
                },
            ],
        },
    ],
    'RISC-V HTTP boot clients are offered the boot loader as a URL, tagged HTTPClient'
);

my $httpboot_port = xCAT::DHCP::BootPolicy->kea_httpboot_network_classes(
    net         => '10.0.0.0',
    prefix      => 24,
    next_server => '10.0.0.1',
    httpport    => '8080',
    tftpdir     => '/srv/tftpboot',
);
is(
    $httpboot_port->[0]{'boot-file-name'},
    'http://10.0.0.1:8080/tftpboot/boot/grub2/grub2.riscv64',
    'the HTTP boot URL follows the configured HTTP port and web alias'
);

is_deeply(
    xCAT::DHCP::BootPolicy->kea_httpboot_network_classes(
        net            => '10.0.0.0',
        prefix         => 24,
        next_server    => '10.0.0.1',
        loader_present => sub { 0 },
    ),
    [],
    'no HTTP boot class is offered while the boot loader is missing'
);
is_deeply(
    xCAT::DHCP::BootPolicy->kea_httpboot_network_classes( net => '10.0.0.0', prefix => 24 ),
    [],
    'HTTP boot classes need a next server'
);
is(
    scalar @{ xCAT::DHCP::BootPolicy->kea_httpboot_network_classes(
            net            => '10.0.0.0',
            prefix         => 24,
            next_server    => '10.0.0.1',
            loader_present => sub { $_[0] eq '/tftpboot/boot/grub2/grub2.riscv64' },
        ) },
    1,
    'the boot loader of the architecture is what is looked for'
);
unlike(
    join( ' ', grep { defined } map { $_->{'boot-file-name'} } @$classes ),
    qr{http://},
    'the global class list keeps HTTP boot out: it needs the address of the management node',
);
# The fallback names 0x001c only to stand out of its way, which is not the same
# as answering it.
foreach my $global (@$classes) {
    isnt( $global->{test}, 'option[93].hex == 0x001c',
        "$global->{name} does not answer the HTTP boot architecture globally" );
}

# A discovery of a few thousand machines takes every pool address through a PXE
# ROM first, and a cluster-default lease holds each one for half a day after
# the ROM is done with it.
is( $by_name{'xcat-pxe-lease'}{'valid-lifetime'}, 600,
    'firmware is given a short lease so the address comes back quickly' );
is( $by_name{'xcat-pxe-lease'}{test}, "substring(option[60].hex,0,9) == 'PXEClient'",
    'recognised by the same nine bytes of the vendor class the ISC class matches on' );
ok( !exists $by_name{'xcat-pxe-lease'}{'boot-file-name'},
    'and it says nothing about what to boot, so it competes with no other class' );
is( $fallback_by_name{'xcat-pxe-lease'}{'valid-lifetime'}, 600,
    'the short lease does not depend on any loader being installed' );

# Etherboot predates option 93 entirely: it announces itself in option 60 and
# says nothing about its architecture. ISC has always keyed on that vendor
# class; Kea keyed on option 93 alone, so an Etherboot ROM asking for a BIOS
# loader was served an address and told nothing to fetch.
is( $by_name{'xcat-etherboot'}{test}, "option[60].text == 'Etherboot-5.4'",
    'Etherboot is recognised by the only thing it says about itself' );
is( $by_name{'xcat-etherboot'}{'boot-file-name'}, 'xcat/xnba.kpxe',
    'and is given the same BIOS loader as an option 93 BIOS client' );

# ISC ends its if/else chain with a bare `filename "/yaboot";`, so a client
# announcing an architecture nothing matched still leaves with something to
# fetch. Kea evaluates every class on its own and has no else, so the same
# answer has to be written as the negation of everything else that answers.
my $fallback = $by_name{'xcat-fallback'};
ok( $fallback, 'the class list ends with the answer for an unrecognised client' );
is( $fallback->{'boot-file-name'}, '/yaboot',
    'which is the boot file the ISC chain falls through to' );
foreach my $arch (qw(0x0000 0x0002 0x0007 0x0009 0x000b 0x000c 0x000e 0x0010 0x001b 0x001c 0x001f)) {
    like( $fallback->{test}, qr/\Qnot (option[93].hex == $arch)\E/,
        "the fallback stands out of the way of client architecture $arch" );
}
like( $fallback->{test}, qr/\Qnot (option[60].text == 'Etherboot-5.4')\E/,
    'and out of the way of Etherboot, which names no architecture' );
like( $fallback->{test}, qr/\Qnot (substring(option[60].text,0,11) == 'onie_vendor')\E/,
    'and of ONIE, which is answered per network' );
like( $fallback->{test}, qr/\Qoption[77]\E/,
    'and of a chainloaded xNBA second stage' );
my $exclusions = () = $fallback->{test} =~ /\bnot \(/g;
my $conjunctions = () = $fallback->{test} =~ /\) and not \(/g;
is( $conjunctions, $exclusions - 1,
    'every exclusion holds at once: one class matching is enough to disqualify the fallback' );
is( $classes->[-1]{name}, 'xcat-fallback',
    'the fallback is written last, after every class it defers to' );

# ONIE carries the address of the management node in a URL, so like the other
# URL-bearing policy it belongs to the network rather than the global list.
my $onie = xCAT::DHCP::BootPolicy->kea_onie_network_classes(
    net         => '10.0.0.0',
    prefix      => 24,
    next_server => '10.0.0.1',
);
is_deeply(
    $onie,
    [
        {
            name            => 'xcat-onie-10.0.0.0_24',
            test            => "substring(option[60].text,0,11) == 'onie_vendor'",
            additional_only => 1,
            'option-data'   => [
                {
                    name          => 'www-server',
                    data          => 'http://10.0.0.1/install/onie/onie-installer',
                    'always-send' => 1,
                },
            ],
        },
    ],
    'an ONIE switch is pointed at the installer over HTTP, as the ISC path does',
);
is(
    xCAT::DHCP::BootPolicy->kea_onie_network_classes(
        net => '10.0.0.0', prefix => 24, next_server => '10.0.0.1', httpport => 8080,
    )->[0]{'option-data'}[0]{data},
    'http://10.0.0.1:8080/install/onie/onie-installer',
    'a non-default HTTP port is carried in the ONIE installer URL',
);
is_deeply(
    xCAT::DHCP::BootPolicy->kea_onie_network_classes( net => '10.0.0.0', prefix => 24 ),
    [],
    'no ONIE class without a next server: there would be no address to point at',
);

my $s390x = xCAT::DHCP::BootPolicy->kea_s390x_network_classes(
    net    => '10.0.0.0',
    prefix => 24,
);
is_deeply(
    $s390x,
    [
        {
            name            => 'xcat-s390x-qemu-10.0.0.0_24',
            test            => 'option[93].hex == 0x001f',
            additional_only => 1,
            'option-data'   => [
                {
                    name          => 'conf-file',
                    data          => 's390x/10.0.0.0_24',
                    'always-send' => 1,
                },
            ],
        },
    ],
    's390x firmware receives its supported network configuration method',
);

done_testing();
