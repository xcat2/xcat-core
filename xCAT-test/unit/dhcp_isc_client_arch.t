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
like(
    $rendered,
    qr/client-architecture = 00:1f \{ #QEMU s390x\n\s+option conf-file = "s390x\/192\.0\.2\.0_24";/,
    'QEMU s390x receives its network configuration',
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

# The chainload test: a second stage announcing user class xNBA has to be
# recognised in both the encodings firmware sends.
#
# RFC 3004 length-prefixes each string in option 77, so the same loader appears
# on the wire either as "xNBA" or as "\x04xNBA" depending on how it was built.
# Recognising only the bare form hands a conforming loader the first stage
# again, and it chainloads itself forever -- a node that never finishes booting
# and never says why. The Kea side of this plugin has always accepted both
# (kea_xnba_user_class_test); the ISC side has to agree, or the same machine
# boots on one backend and loops on the other.
foreach my $case (
    [ '"',   'a config file written directly' ],
    [ '\\"', 'a statement passed through omshell' ],
  )
{
    my ($quote, $context) = @{$case};
    my $test = xCAT::DHCP::BootPolicy->isc_xnba_user_class_test(quote => $quote);

    like( $test, qr/\Qoption user-class-identifier = ${quote}xNBA${quote}\E/,
        "the bare user class is matched, for $context" );
    like( $test, qr/\Qsubstring(option user-class-identifier, 1, 4) = ${quote}xNBA${quote}\E/,
        "the RFC 3004 length-prefixed user class is matched, for $context" );

    # dhcpd's `if` is a single expression: without the parentheses the trailing
    # `and option client-architecture = ...` binds to the second alternative
    # only, and every xNBA client is served the first branch whatever its
    # architecture.
    like( $test, qr/^\(.*\)$/s,
        "the alternation is parenthesised so it can be and-ed with a further test, for $context" );
}

is( xCAT::DHCP::BootPolicy->isc_xnba_user_class_test(),
    xCAT::DHCP::BootPolicy->isc_xnba_user_class_test(quote => '"'),
    'a config file is the default quoting' );

# ...and the per-network policy uses it, rather than its own bare comparison.
foreach my $arch (qw(00:00 00:09 00:07)) {
    like( $rendered,
        qr/\Qsubstring(option user-class-identifier, 1, 4) = "xNBA")\E and option client-architecture = \Q$arch\E/,
        "the xNBA branch for client architecture $arch accepts both encodings" );
}

unlike( $rendered, qr/(?<!\()option user-class-identifier = "xNBA" and/,
    'no xNBA branch is left matching the bare encoding alone' );

done_testing();
