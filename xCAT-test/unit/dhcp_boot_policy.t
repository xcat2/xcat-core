use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

use xCAT::DHCP::BootPolicy;

my $fallback_classes = xCAT::DHCP::BootPolicy->kea_client_classes();
is( scalar @$fallback_classes, 6, 'Kea boot policy omits the x86 classes when the x86 loaders are unavailable' );
my %fallback_by_name = map { $_->{name} => $_ } @$fallback_classes;
# Naming a loader that is not on disk costs the client a timeout it cannot
# diagnose, and pxelinux.0 in its place boots something nobody asked for. With
# no BIOS loader present the class is simply not written, and such a client is
# served an address and told nothing to fetch.
ok( !exists $fallback_by_name{'xcat-bios'}, 'no BIOS class is written when the BIOS loader is not there' );
ok( !exists $fallback_by_name{'xcat-etherboot'}, 'and no Etherboot class either, since it names the same file' );
ok( !exists $fallback_by_name{'xcat-xnba-bios'}, 'xNBA user-class is not advertised without xNBA kpxe' );

my $classes = xCAT::DHCP::BootPolicy->kea_client_classes(ipxe_bios => 1, ipxe_uefi => 1);
is( scalar @$classes, 9, 'Kea boot policy renders the expected client classes with the upstream loader' );

my %by_name = map { $_->{name} => $_ } @$classes;
like( $by_name{'xcat-uefi-x64'}{test}, qr/0x0007/, 'UEFI x64 class matches architecture 7' );
like( $by_name{'xcat-uefi-x64'}{test}, qr/0x0009/, 'UEFI x64 class matches architecture 9' );
like( $by_name{'xcat-uefi-x64'}{test}, qr/0x0010/, 'UEFI x64 class matches HTTP boot architecture 16' );
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
                    code          => 114,
                    data          => 'http://10.0.0.1/install/onie/onie-installer',
                    'always-send' => 1,
                },
            ],
        },
    ],
    'an ONIE switch is pointed at the installer over HTTP, as the ISC path does',
);

# The option is named by code and not by name on purpose. "www-server" means
# option 114 in xCAT's dhcpd.conf, which declares it that way, and option 72 to
# Kea, which does not -- and option 72 holds IPv4 addresses, so a URL in it
# stops kea-dhcp4 from starting.
is( $onie->[0]{'option-data'}[0]{code}, 114,
    'the installer URL is option 114, the one ONIE reads' );
ok( !exists $onie->[0]{'option-data'}[0]{name},
    'and it is not named www-server, which is a different option to Kea' );
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

# ---- xNBA output, pinned ------------------------------------------------------------------------
# The node classes and host statements below are what the renderers produced before the x86 loader
# became selectable, byte for byte. They must not change while a node uses the xNBA loader.
my $xnba_user_class = q{(option[77].exists and (option[77].text == 'xNBA' or option[77].hex == 0x784e4241 or substring(option[77].hex,1,4) == 'xNBA'))};
my $uefi_x64        = q{(option[93].hex == 0x0007 or option[93].hex == 0x0009 or option[93].hex == 0x0010)};

my $xnba_context = { 'xcat-mac' => '52:54:4b:10:00:11', 'xcat-node' => 'cn01', 'xcat-purpose' => 'xnba-second-stage' };
is_deeply(
    [ @{ xCAT::DHCP::BootPolicy->kea_xnba_node_classes(
        xnba_efi => 1,
        nodes    => [ { node => 'cn01', mac => '52:54:4B:10:00:11', next_server => '192.0.2.10', httpport => '8080' } ],
    ) }[ 0, 1 ] ],
    [
        {
            name             => 'xcat-xnba-cn01-52544b100011-bios',
            test             => "$xnba_user_class and option[93].hex == 0x0000 and pkt4.mac == 0x52544b100011",
            'boot-file-name' => 'http://192.0.2.10:8080/tftpboot/xcat/xnba/nodes/cn01',
            'user-context'   => $xnba_context,
        },
        {
            name             => 'xcat-xnba-cn01-52544b100011-uefi',
            test             => "$xnba_user_class and $uefi_x64 and pkt4.mac == 0x52544b100011",
            'boot-file-name' => 'http://192.0.2.10:8080/tftpboot/xcat/xnba/nodes/cn01.uefi',
            'user-context'   => $xnba_context,
        },
    ],
    'the node classes give the node scripts to xNBA clients only'
);
# ISC host statements, as dhcp.pm wrote them for node cn01 before they moved into BootPolicy.
my %statements = (
    bios => q{if suffix(option user-class-identifier, 4) = \"xNBA\" and option client-architecture = 00:00 { filename = \"http://192.0.2.10:8080/tftpboot/xcat/xnba/nodes/cn01\"; } else if option client-architecture = 00:00 { filename = \"xcat/xnba.kpxe\"; } else { filename = \"\"; }},
    uefi => q{if suffix(option user-class-identifier, 4) = \"xNBA\" and option client-architecture = 00:00 { always-broadcast on; filename = \"http://192.0.2.10:8080/tftpboot/xcat/xnba/nodes/cn01\"; } else if suffix(option user-class-identifier, 4) = \"xNBA\" and option client-architecture = 00:09 { filename = \"http://192.0.2.10:8080/tftpboot/xcat/xnba/nodes/cn01.uefi\"; } else if suffix(option user-class-identifier, 4) = \"xNBA\" and option client-architecture = 00:07 { filename = \"http://192.0.2.10:8080/tftpboot/xcat/xnba/nodes/cn01.uefi\"; } else if option client-architecture = 00:07 { filename = \"xcat/xnba.efi\"; } else if option client-architecture = 00:00 { filename = \"xcat/xnba.kpxe\"; } else { filename = \"\"; }},
    at_boot => q{filename = \"\";},
    iscsi_boot => q{if option client-architecture = 00:00 and not exists gpxe.bus-id { filename = \"xcat/xnba.kpxe\"; } else { filename = \"\"; } },
    iscsi_iscsiboot => q{if option client-architecture = 00:00 and not exists gpxe.bus-id { filename = \"xcat/xnba.kpxe\"; } else { filename = \"\"; } },
    winshell_proxy => q{if option client-architecture = 00:00 or option client-architecture = 00:07 or option client-architecture = 00:09 { filename = \"\"; option vendor-class-identifier \"PXEClient\"; } else { filename = \"\"; }},
    winshell => q{if suffix(option user-class-identifier, 4) = \"xNBA\" and option client-architecture = 00:00 { always-broadcast on; filename = \"http://192.0.2.10:8080/tftpboot/xcat/xnba/nodes/cn01\"; } else if option client-architecture = 00:07 or option client-architecture = 00:09 { filename = \"\"; option vendor-class-identifier \"PXEClient\"; } else if option client-architecture = 00:00 { filename = \"xcat/xnba.kpxe\"; } else { filename = \"\"; }},
    windows_install => q{if suffix(option user-class-identifier, 4) = \"xNBA\" and option client-architecture = 00:00 { always-broadcast on; filename = \"http://192.0.2.10:8080/tftpboot/xcat/xnba/nodes/cn01\"; } else if option client-architecture = 00:07 or option client-architecture = 00:09 { filename = \"\"; option vendor-class-identifier \"PXEClient\"; } else if option client-architecture = 00:00 { filename = \"xcat/xnba.kpxe\"; } else { filename = \"\"; }},
    pxe_iscsi => q{if exists gpxe.bus-id { filename = \"\"; } else if exists client-architecture { filename = \"xcat/xnba.kpxe\"; } },
    pxe => q{if option vendor-class-identifier = \"ScaleMP\" { filename = \"vsmp/pxelinux.0\"; } else { filename = \"pxelinux.0\"; }},
);
my @statement_cases = (
    [ bios            => { netboot => 'xnba', uefi => 0, currstate => 'install rhels9' } ],
    [ uefi            => { netboot => 'xnba', uefi => 1, currstate => 'install rhels9' } ],
    [ at_boot         => { netboot => 'xnba', uefi => 1, currstate => 'boot' } ],
    [ iscsi_boot      => { netboot => 'xnba', uefi => 1, currstate => 'boot', iscsi => 1 } ],
    [ iscsi_iscsiboot => { netboot => 'xnba', uefi => 0, currstate => 'iscsiboot', iscsi => 1 } ],
    [ winshell_proxy  => { netboot => 'xnba', uefi => 1, currstate => 'winshell', proxydhcp => sub { 1 } } ],
    [ winshell        => { netboot => 'xnba', uefi => 1, currstate => 'winshell', proxydhcp => sub { 0 } } ],
    [ windows_install => { netboot => 'xnba', uefi => 2, currstate => 'install win2022', proxydhcp => sub { 0 } } ],
    [ pxe_iscsi       => { netboot => 'pxe',  uefi => 0, currstate => 'boot', iscsi => 1 } ],
    [ at_boot         => { netboot => 'pxe',  uefi => 0, currstate => 'iscsiboot' } ],
    [ pxe             => { netboot => 'pxe',  uefi => 0, currstate => 'install rhels9' } ],
);
for my $case (@statement_cases) {
    my ( $name, $opts ) = @$case;
    is(
        xCAT::DHCP::BootPolicy->isc_node_boot_statements(
            %$opts,
            loader_present => 1,
            node           => 'cn01',
            next_server    => '192.0.2.10',
            portsuffix     => ':8080',
        ),
        $statements{$name},
        "ISC host statements for the $name case"
    );
}
for my $netboot (qw(xnba pxe)) {
    is(
        xCAT::DHCP::BootPolicy->isc_node_boot_statements( netboot => $netboot, loader_present => 0, node => 'cn01' ),
        '',
        "no ISC host statement for netboot $netboot without the xNBA BIOS file"
    );
}
is(
    xCAT::DHCP::BootPolicy->isc_node_boot_statements( netboot => 'grub2', loader_present => 1, node => 'cn01' ),
    '',
    'no ISC host statement for a netboot method that does not use the x86 loader'
);
my $proxy_asked = 0;
xCAT::DHCP::BootPolicy->isc_node_boot_statements(
    netboot => 'xnba', loader_present => 1, uefi => 1, currstate => 'install rhels9', node => 'cn01',
    proxydhcp => sub { $proxy_asked++; 1 },
);
is( $proxy_asked, 0, 'the proxy DHCP daemon is looked up only for a Windows boot' );

# ---- netboot=ipxe nodes --------------------------------------------------------------------------
# An ipxe node gets the upstream loader whether or not it is on this server, and its boot script
# only when it reports the iPXE features that script needs. The first-stage classes negate exactly
# the same test.
my $bios_next = 'option[175].option[19].exists and option[175].option[24].exists and option[175].option[33].exists';
my $uefi_next = 'option[175].option[19].exists and option[175].option[36].exists';
my $context   = { 'xcat-mac' => '52:54:00:00:00:01', 'xcat-node' => 'cn01', 'xcat-purpose' => 'ipxe-boot' };
my %ipxe_node = ( node => 'cn01', mac => '52:54:00:00:00:01', next_server => '192.0.2.10', netboot => 'ipxe' );
is_deeply(
    [ @{ xCAT::DHCP::BootPolicy->kea_xnba_node_classes( nodes => [ {%ipxe_node} ] ) }[ 0, 1 ] ],
    [
        {
            name             => 'xcat-ipxe-cn01-525400000001-bios',
            test             => "$bios_next and option[93].hex == 0x0000 and pkt4.mac == 0x525400000001",
            'boot-file-name' => 'http://192.0.2.10/tftpboot/xcat/ipxe/nodes/cn01',
            'user-context'   => $context,
        },
        {
            name             => 'xcat-ipxe-cn01-525400000001-uefi',
            test             => "$uefi_next and $uefi_x64 and pkt4.mac == 0x525400000001",
            'boot-file-name' => 'http://192.0.2.10/tftpboot/xcat/ipxe/nodes/cn01.uefi',
            'user-context'   => $context,
        },
    ],
    'an ipxe node gets its script with the iPXE features it needs, with no local file'
);

# iPXE hooks the iSCSI root path of a SAN node before it runs the script, so the script of a SAN
# node goes only to a client with iSCSI.
my $san_bios = "$bios_next and option[175].option[17].exists";
my $san_uefi = "$uefi_next and option[175].option[17].exists";
is_deeply(
    [ map { [ $_->{name}, $_->{test} ] } @{ xCAT::DHCP::BootPolicy->kea_xnba_node_classes( nodes => [ { %ipxe_node, iscsi => 1 } ] ) } ],
    [
        [ 'xcat-ipxe-cn01-525400000001-bios', "$san_bios and option[93].hex == 0x0000 and pkt4.mac == 0x525400000001" ],
        [ 'xcat-ipxe-cn01-525400000001-uefi', "$san_uefi and $uefi_x64 and pkt4.mac == 0x525400000001" ],
        [ 'xcat-ipxe-cn01-525400000001-bios-first-stage', "option[93].hex == 0x0000 and not ($san_bios) and pkt4.mac == 0x525400000001" ],
        [ 'xcat-ipxe-cn01-525400000001-uefi-first-stage', "$uefi_x64 and not ($san_uefi) and pkt4.mac == 0x525400000001" ],
    ],
    'a SAN ipxe node gets its script only with iSCSI, and the upstream loader otherwise'
);

my %xnba_node = ( node => 'cn02', mac => '52:54:00:00:00:02', next_server => '192.0.2.10', netboot => 'xnba' );
is_deeply(
    xCAT::DHCP::BootPolicy->kea_xnba_node_classes( xnba_efi => 1, nodes => [ {%ipxe_node}, { %xnba_node, iscsi => 1 } ] ),
    [
        @{ xCAT::DHCP::BootPolicy->kea_xnba_node_classes( xnba_efi => 1, nodes => [ {%ipxe_node} ] ) },
        @{ xCAT::DHCP::BootPolicy->kea_xnba_node_classes( xnba_efi => 1, nodes => [ { node => 'cn02', mac => '52:54:00:00:00:02', next_server => '192.0.2.10' } ] ) },
    ],
    'an xnba node beside an ipxe node keeps the classes of a node with no method, also when it boots from SAN'
);

is_deeply(
    xCAT::DHCP::BootPolicy->kea_ipxe_option_defs(),
    [
        { name => 'gpxe-encap-opts', code => 175, space => 'dhcp4', type => 'empty', encapsulate => 'gpxe' },
        { name => 'iscsi',   code => 17, space => 'gpxe', type => 'uint8' },
        { name => 'http',    code => 19, space => 'gpxe', type => 'uint8' },
        { name => 'bzimage', code => 24, space => 'gpxe', type => 'uint8' },
        { name => 'pxe',     code => 33, space => 'gpxe', type => 'uint8' },
        { name => 'efi',     code => 36, space => 'gpxe', type => 'uint8' },
    ],
    'Kea decodes option 175 and the iPXE feature indicators'
);

my $isc_bios_next = 'exists gpxe.http and exists gpxe.bzimage and exists gpxe.pxe';
my $isc_uefi_next = 'exists gpxe.http and exists gpxe.efi';
my $isc_san       = 'exists gpxe.iscsi';
my $script        = 'http://192.0.2.10:8080/tftpboot/xcat/ipxe/nodes/cn01';
my $up_bios       = 'xcat/ipxe/i386/undionly.kpxe';
my $up_uefi       = 'xcat/ipxe/x86_64-sb/snponly-shim.efi';
my %ipxe_statements = (
    bios            => qq{if option client-architecture = 00:00 { if $isc_bios_next { filename = \\"$script\\"; } else { filename = \\"$up_bios\\"; } } else { filename = \\"\\"; }},
    uefi            => qq{if option client-architecture = 00:00 { if $isc_bios_next { always-broadcast on; filename = \\"$script\\"; } else { filename = \\"$up_bios\\"; } } else if option client-architecture = 00:09 or option client-architecture = 00:07 { if $isc_uefi_next { filename = \\"$script.uefi\\"; } else { filename = \\"$up_uefi\\"; } } else { filename = \\"\\"; }},
    iscsi_boot      => qq{if option client-architecture = 00:00 and not $isc_san { filename = \\"$up_bios\\"; } else if option client-architecture = 00:07 and not $isc_san { filename = \\"$up_uefi\\"; } else if option client-architecture = 00:09 and not $isc_san { filename = \\"$up_uefi\\"; } else { filename = \\"\\"; } },
    iscsi_install   => qq{if option client-architecture = 00:00 { if $isc_bios_next and $isc_san { always-broadcast on; filename = \\"$script\\"; } else { filename = \\"$up_bios\\"; } } else if option client-architecture = 00:09 or option client-architecture = 00:07 { if $isc_uefi_next and $isc_san { filename = \\"$script.uefi\\"; } else { filename = \\"$up_uefi\\"; } } else { filename = \\"\\"; }},
    winshell        => qq{if option client-architecture = 00:00 { if $isc_bios_next { always-broadcast on; filename = \\"$script\\"; } else { filename = \\"$up_bios\\"; } } else if option client-architecture = 00:07 or option client-architecture = 00:09 { filename = \\"\\"; option vendor-class-identifier \\"PXEClient\\"; } else { filename = \\"\\"; }},
    winshell_proxy  => $statements{winshell_proxy},
);
my @ipxe_cases = (
    [ bios           => { uefi => 0, currstate => 'install rhels9' } ],
    [ uefi           => { uefi => 1, currstate => 'install rhels9' } ],
    [ iscsi_boot     => { uefi => 1, currstate => 'boot', iscsi => 1 } ],
    [ iscsi_install  => { uefi => 1, currstate => 'install rhels9', iscsi => 1 } ],
    [ winshell       => { uefi => 1, currstate => 'winshell', proxydhcp => sub { 0 } } ],
    [ winshell_proxy => { uefi => 1, currstate => 'winshell', proxydhcp => sub { 1 } } ],
);
for my $case (@ipxe_cases) {
    my ( $name, $opts ) = @$case;
    is(
        xCAT::DHCP::BootPolicy->isc_node_boot_statements(
            %$opts,
            netboot        => 'ipxe',
            loader_present => 0,
            node           => 'cn01',
            next_server    => '192.0.2.10',
            portsuffix     => ':8080',
        ),
        $ipxe_statements{$name},
        "ISC host statements of an ipxe node for the $name case, with no local xNBA file"
    );
}

# dhcpd saves host statements in dhcpd.leases without parentheses, so no ipxe statement may depend
# on them.
my @grouped = map { $_->[0] } grep {
    xCAT::DHCP::BootPolicy->isc_node_boot_statements( %{ $_->[1] }, netboot => 'ipxe', node => 'cn01', next_server => '192.0.2.10' ) =~ /[()]/
} @ipxe_cases;
is_deeply( \@grouped, [], 'no ISC host statement of an ipxe node depends on parentheses' );

my %declared = map { /^option gpxe\.(\w+) code/ ? ( $1 => 1 ) : () } @{ xCAT::DHCP::BootPolicy->isc_ipxe_feature_option_lines() };
my @undeclared = grep { !$declared{$_} } join( ' ', values %ipxe_statements ) =~ /gpxe\.([\w-]+)/g;
is_deeply( \@undeclared, [], 'the ISC header declares every iPXE feature that an ipxe node statement tests' );

# ---- unknown x86 clients --------------------------------------------------------------------------
# A client without a node definition gets the upstream loader when this server has it, and the
# Genesis script of its network once it reports the iPXE features it needs. As for xNBA, a loader
# that is not on disk is not named, and neither is the second stage that it would fetch.
my %x86_names = map { $_ => 1 } qw(xcat-bios xcat-etherboot xcat-uefi-x64);
my $x86_global = sub {
    return [ grep { $x86_names{ $_->{name} } } @{ xCAT::DHCP::BootPolicy->kea_client_classes(@_) } ];
};
is_deeply(
    $x86_global->( ipxe_bios => 1, ipxe_uefi => 1 ),
    [
        {
            name             => 'xcat-bios',
            test             => "option[93].hex == 0x0000 and not ($bios_next)",
            'boot-file-name' => 'xcat/ipxe/i386/undionly.kpxe',
        },
        {
            name             => 'xcat-etherboot',
            test             => "option[60].text == 'Etherboot-5.4'",
            'boot-file-name' => 'xcat/ipxe/i386/undionly.kpxe',
        },
        {
            name             => 'xcat-uefi-x64',
            test             => "$uefi_x64 and not ($uefi_next)",
            'boot-file-name' => 'xcat/ipxe/x86_64-sb/snponly-shim.efi',
        },
    ],
    'the global x86 classes give the upstream loader to every client that cannot fetch its script'
);
is_deeply( $x86_global->( xnba_kpxe => 1, xnba_efi => 1 ), [], 'the xNBA files on this server name no global x86 class' );
is_deeply( [ map { $_->{name} } @{ $x86_global->( ipxe_uefi => 1 ) } ], ['xcat-uefi-x64'],
    'without the upstream BIOS loader, neither BIOS nor Etherboot clients are named a loader' );

my %net = ( net => '192.0.2.0', prefix => 24, next_server => '192.0.2.10' );
is_deeply(
    xCAT::DHCP::BootPolicy->kea_xnba_network_classes( %net, httpport => '8080', ipxe_bios => 1, ipxe_uefi => 1 ),
    [
        {
            name             => 'xcat-ipxe-net-192.0.2.0_24-bios',
            test             => "$bios_next and option[93].hex == 0x0000",
            'boot-file-name' => 'http://192.0.2.10:8080/tftpboot/xcat/ipxe/nets/192.0.2.0_24',
            additional_only  => 1,
        },
        {
            name             => 'xcat-ipxe-net-192.0.2.0_24-uefi',
            test             => "$uefi_next and $uefi_x64",
            'boot-file-name' => 'http://192.0.2.10:8080/tftpboot/xcat/ipxe/nets/192.0.2.0_24.uefi',
            additional_only  => 1,
        },
    ],
    'the network classes give the network scripts under xcat/ipxe/nets to clients with the iPXE features'
);
is( xCAT::DHCP::BootPolicy->kea_xnba_network_classes( %net, ipxe_bios => 1 )->[0]{'boot-file-name'},
    'http://192.0.2.10/tftpboot/xcat/ipxe/nets/192.0.2.0_24', 'the default HTTP port stays out of the network script URL' );
is_deeply( [ map { $_->{name} } @{ xCAT::DHCP::BootPolicy->kea_xnba_network_classes( %net, ipxe_uefi => 1 ) } ],
    ['xcat-ipxe-net-192.0.2.0_24-uefi'], 'a network script is offered only with the loader that fetches it' );
is_deeply( xCAT::DHCP::BootPolicy->kea_xnba_network_classes( net => '192.0.2.0', prefix => 24, ipxe_bios => 1, ipxe_uefi => 1 ), [],
    'the network classes need a next server' );

# The global classes now give the upstream loader, so an xnba node carries the first stage of xNBA
# when this server has the xNBA BIOS file, as it has its ISC host statements.
my %xnba_first = ( node => 'cn02', mac => '52:54:00:00:00:02', next_server => '192.0.2.10', netboot => 'xnba' );
my $xnba_first_context = { 'xcat-mac' => '52:54:00:00:00:02', 'xcat-node' => 'cn02', 'xcat-purpose' => 'xnba-first-stage' };
is_deeply(
    [ @{ xCAT::DHCP::BootPolicy->kea_xnba_node_classes( xnba_kpxe => 1, xnba_efi => 1, nodes => [ {%xnba_first} ] ) }[ 2, 3 ] ],
    [
        {
            name             => 'xcat-xnba-cn02-525400000002-bios-first-stage',
            test             => "option[93].hex == 0x0000 and not ($xnba_user_class) and pkt4.mac == 0x525400000002",
            'boot-file-name' => 'xcat/xnba.kpxe',
            'user-context'   => $xnba_first_context,
        },
        {
            name             => 'xcat-xnba-cn02-525400000002-uefi-first-stage',
            test             => "$uefi_x64 and not ($xnba_user_class) and pkt4.mac == 0x525400000002",
            'boot-file-name' => 'xcat/xnba.efi',
            'user-context'   => $xnba_first_context,
        },
    ],
    'an xnba node gets xNBA from its own first-stage classes'
);
is_deeply(
    [ map { [ $_->{name}, $_->{'boot-file-name'} ] } @{ xCAT::DHCP::BootPolicy->kea_xnba_node_classes( xnba_kpxe => 1, nodes => [ {%xnba_first} ] ) } ],
    [
        [ 'xcat-xnba-cn02-525400000002-bios', 'http://192.0.2.10/tftpboot/xcat/xnba/nodes/cn02' ],
        [ 'xcat-xnba-cn02-525400000002-bios-first-stage', 'xcat/xnba.kpxe' ],
        [ 'xcat-xnba-cn02-525400000002-uefi-first-stage', 'xcat/xnba.efi' ],
    ],
    'without the local xNBA UEFI file, an xnba node still gets it for UEFI, as in ISC'
);
is_deeply(
    [ map { $_->{name} } @{ xCAT::DHCP::BootPolicy->kea_xnba_node_classes( nodes => [ {%xnba_first} ] ) } ],
    ['xcat-xnba-cn02-525400000002-bios'],
    'without the local xNBA BIOS file, an xnba node has no first-stage classes, as it has no ISC host statements'
);
is_deeply(
    [ map { [ $_->{name}, $_->{'boot-file-name'} ] }
          grep { $_->{name} =~ /-first-stage$/ } @{ xCAT::DHCP::BootPolicy->kea_xnba_node_classes( nodes => [ {%ipxe_node} ] ) } ],
    [
        [ 'xcat-ipxe-cn01-525400000001-bios-first-stage', 'xcat/ipxe/i386/undionly.kpxe' ],
        [ 'xcat-ipxe-cn01-525400000001-uefi-first-stage', 'xcat/ipxe/x86_64-sb/snponly-shim.efi' ],
    ],
    'an ipxe node without a SAN disk carries the upstream loader in its own first-stage classes'
);

my @x86_lines = @{ xCAT::DHCP::BootPolicy->isc_client_architecture_lines(
        next_server => '192.0.2.10',
        portsuffix  => ':8080',
        net         => '192.0.2.0',
        prefix      => 24,
    ) }[ 0 .. 16 ];
is_deeply(
    \@x86_lines,
    [
        "    if $isc_bios_next and option client-architecture = 00:00 { #x86, iPXE second stage\n",
        "        always-broadcast on;\n",
        "        filename = \"http://192.0.2.10:8080/tftpboot/xcat/ipxe/nets/192.0.2.0_24\";\n",
        "    } else if $isc_uefi_next and option client-architecture = 00:09 { #x86, iPXE second stage\n",
        "        filename = \"http://192.0.2.10:8080/tftpboot/xcat/ipxe/nets/192.0.2.0_24.uefi\";\n",
        "    } else if $isc_uefi_next and option client-architecture = 00:07 { #x86-64 UEFI, iPXE second stage\n",
        "        filename = \"http://192.0.2.10:8080/tftpboot/xcat/ipxe/nets/192.0.2.0_24.uefi\";\n",
        "    } else if option client-architecture = 00:00  { #x86\n",
        "        filename \"xcat/ipxe/i386/undionly.kpxe\";\n",
        "    } else if option vendor-class-identifier = \"Etherboot-5.4\"  { #x86\n",
        "        filename \"xcat/ipxe/i386/undionly.kpxe\";\n",
        "    } else if option client-architecture = 00:07 { #x86_64 uefi\n ",
        "        filename \"xcat/ipxe/x86_64-sb/snponly-shim.efi\";\n",
        "    } else if option client-architecture = 00:09 { #x86_64 uefi alternative id\n ",
        "        filename \"xcat/ipxe/x86_64-sb/snponly-shim.efi\";\n",
        "    } else if option client-architecture = 00:10 { #x86_64 uefi http boot\n ",
        "        filename \"xcat/ipxe/x86_64-sb/snponly-shim.efi\";\n",
    ],
    'the ISC x86 lines apply the same test and name the upstream loader and xcat/ipxe/nets'
);
my @tested = join( ' ', @x86_lines ) =~ /gpxe\.([\w-]+)/g;
is_deeply( [ grep { !$declared{$_} } @tested ], [], 'the ISC header declares every iPXE feature that the x86 lines test' );

done_testing();
