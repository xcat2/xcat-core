#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;

use xCAT::DHCP::BootPolicy;

my $rendered = join '', @{ xCAT::DHCP::BootPolicy->isc_client_architecture_lines(
        next_server => '192.0.2.10',
        portsuffix  => ':8080',
        tftpdir     => '/srv/tftp',
        net         => '192.0.2.0',
        prefix      => 24,
    ) };

like(
    $rendered,
    qr/client-architecture = 00:0b \{ #aaarch64\n\s+filename "boot\/grub2\/grub2\.aarch64";/,
    'the ISC policy renders the aarch64 boot branch',
);
like(
    $rendered,
    qr/client-architecture = 00:1b \{ #riscv64 uefi\n\s+filename "boot\/grub2\/grub2\.riscv64";/,
    'the ISC policy renders the riscv64 TFTP boot branch',
);
like(
    $rendered,
    qr/client-architecture = 00:1c \{ #riscv64 uefi http boot\n\s+option vendor-class-identifier "HTTPClient";\n\s+filename "http:\/\/192\.0\.2\.10:8080\/tftpboot\/boot\/grub2\/grub2\.riscv64";/,
    'the ISC policy renders the riscv64 HTTP boot branch with the subnet URL',
);
like(
    $rendered,
    qr/option conf-file = "http:\/\/192\.0\.2\.10:8080\/tftpboot\/pxelinux\.cfg\/p\/192\.0\.2\.0_24";/,
    'the existing OPAL branch keeps its subnet URL',
);

my @riscv_ids = $rendered =~ /client-architecture = (00:1[9a-e])/g;
is_deeply(
    \@riscv_ids,
    [ '00:1b', '00:1c' ],
    'only the RISC-V 64-bit UEFI architecture ids are mapped',
);

my $aarch64_pos  = index($rendered, 'client-architecture = 00:0b');
my $tftp_pos     = index($rendered, 'client-architecture = 00:1b');
my $http_pos     = index($rendered, 'client-architecture = 00:1c');
my $opal_pos     = index($rendered, 'client-architecture = 00:0e');
my $fallback_pos = index($rendered, 'substring(filename,0,1) = null');

cmp_ok($aarch64_pos, '<', $tftp_pos,     'riscv64 follows the aarch64 branch');
cmp_ok($tftp_pos,    '<', $http_pos,     'the TFTP branch precedes the HTTP branch');
cmp_ok($http_pos,    '<', $opal_pos,     'the HTTP branch precedes the OPAL branch');
cmp_ok($http_pos,    '<', $fallback_pos, 'the HTTP branch is reachable before the fallback');
like($rendered, qr/filename "\/yaboot";\n\s*\}\n\z/, 'the policy ends with the existing yaboot fallback');

done_testing();
