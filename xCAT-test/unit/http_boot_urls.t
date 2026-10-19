#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use Test::More;
use xCAT::DHCP::BootPolicy;

my $root = tempdir(CLEANUP => 1);
make_path("$root/boot/grub2");
write_text("$root/boot/grub2/grub2.riscv64", 'loader');
my %network = (net => '192.0.2.0', prefix => 24, next_server => '192.0.2.1');

for my $case ([undef, ''], ['', ''], [0, ''], ['0', ''], ['80', ''], ['080', ':080'], ['8080', ':8080']) {
    my ($port, $suffix) = @$case;
    my $base = "http://192.0.2.1$suffix";
    my $http = xCAT::DHCP::BootPolicy->kea_httpboot_network_classes(
        %network, httpport => $port, tftpdir => $root,
    );
    is_deeply([map { $_->{'boot-file-name'} } @$http], ["$base/tftpboot/boot/grub2/grub2.riscv64"],
        'HTTP boot preserves the site port default');

    my $onie = xCAT::DHCP::BootPolicy->kea_onie_network_classes(%network, httpport => $port);
    is($onie->[0]{'option-data'}[0]{data}, "$base/install/onie/onie-installer",
        'ONIE preserves the site port default');

    my $net = xCAT::DHCP::BootPolicy->kea_xnba_network_classes(
        %network, httpport => $port, ipxe_bios => 1, ipxe_uefi => 1,
    );
    is_deeply([map { $_->{'boot-file-name'} } @$net], [
        "$base/tftpboot/xcat/ipxe/nets/192.0.2.0_24",
        "$base/tftpboot/xcat/ipxe/nets/192.0.2.0_24.uefi",
    ], 'BIOS and UEFI discovery URLs preserve the site port default');

    my $node = xCAT::DHCP::BootPolicy->kea_xnba_node_classes(nodes => [{
        node => 'cn1', mac => '52:54:00:00:00:01', netboot => 'ipxe',
        next_server => '192.0.2.1', httpport => $port,
    }]);
    is_deeply([map { $_->{'boot-file-name'} } @$node], [
        "$base/tftpboot/xcat/ipxe/nodes/cn1",
        "$base/tftpboot/xcat/ipxe/nodes/cn1.uefi",
        'xcat/ipxe/i386/undionly.kpxe',
        'xcat/ipxe/x86_64-sb/snponly-shim.efi',
    ], 'per-node BIOS and UEFI URLs preserve the site port default');
}

done_testing();
