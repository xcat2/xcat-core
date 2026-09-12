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

# Two architectures the chain did not name, so a client announcing either fell
# through to the /yaboot default: a ppc64 machine, which cannot boot yaboot at
# all, and an x86-64 UEFI machine fetching over HTTP, the same firmware and
# loader as 0x0007. The Kea policy has always matched both.
like(
    $rendered,
    qr/client-architecture = 00:0c \{ #ppc64 grub2\n\s+filename "\/boot\/grub2\/grub2\.ppc";/,
    'a ppc64 client is given grub2.ppc rather than the yaboot fallback',
);
like(
    $rendered,
    qr/client-architecture = 00:10 \{ #x86_64 uefi http boot\n\s+filename "xcat\/xnba\.efi";/,
    'the x86-64 UEFI HTTP boot id is given the same loader as 0x0007',
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

my $ppc64_pos    = index($rendered, 'client-architecture = 00:0c');
my $uefi_http_pos = index($rendered, 'client-architecture = 00:10');
cmp_ok($ppc64_pos,     '>', -1, 'the ppc64 branch is rendered at all');
cmp_ok($ppc64_pos,     '<', $fallback_pos, 'a ppc64 client never reaches the fallback');
cmp_ok($uefi_http_pos, '>', -1, 'the x86-64 UEFI HTTP branch is rendered at all');
cmp_ok($uefi_http_pos, '<', $fallback_pos, 'an HTTP-booting x86-64 client never reaches the fallback');
like($rendered, qr/filename "\/yaboot";\n\s*\}\n\z/, 'the policy ends with the existing yaboot fallback');

# The chainload test: a second stage announcing user class xNBA has to be
# recognised in both the encodings firmware sends.
#
# RFC 3004 length-prefixes each string in option 77, so the same loader appears
# as "xNBA" or as "\x04xNBA". Recognising only the bare form hands a conforming
# loader the first stage again and it chainloads forever. The Kea side has always
# accepted both, so the ISC side has to agree.
#
# suffix() takes the last four bytes, which is "xNBA" either way. One expression
# rather than an alternation, because dhcpd has no parenthesised grouping --
# `if (a or b) and c {` is rejected with "left brace expected".
foreach my $case (
    [ '"',   'a config file written directly' ],
    [ '\\"', 'a statement passed through omshell' ],
  )
{
    my ($quote, $context) = @{$case};
    my $test = xCAT::DHCP::BootPolicy->isc_xnba_user_class_test(quote => $quote);

    is( $test, "suffix(option user-class-identifier, 4) = ${quote}xNBA${quote}",
        "both encodings are matched by one suffix test, for $context" );

    unlike( $test, qr/^\(/,
        "the test is not wrapped in parentheses dhcpd cannot parse, for $context" );
    unlike( $test, qr/\bor\b/,
        "the test is a single expression, needing no grouping, for $context" );
}

is( xCAT::DHCP::BootPolicy->isc_xnba_user_class_test(),
    xCAT::DHCP::BootPolicy->isc_xnba_user_class_test(quote => '"'),
    'a config file is the default quoting' );

# ...and the per-network policy uses it, rather than its own bare comparison.
foreach my $arch (qw(00:00 00:09 00:07)) {
    like( $rendered,
        qr/\Qsuffix(option user-class-identifier, 4) = "xNBA"\E and option client-architecture = \Q$arch\E/,
        "the xNBA branch for client architecture $arch accepts both encodings" );
}

unlike( $rendered, qr/option user-class-identifier = "xNBA" and/,
    'no xNBA branch is left matching the bare encoding alone' );

# The short lease firmware is given, so a pool address taken by a PXE ROM comes
# back in ten minutes rather than half a day. A maximum alone shortened nothing:
# dhcpd applies the subnet's min-lease-time after the maximum.
my $pxe_class = join '', @{ xCAT::DHCP::BootPolicy->isc_pxe_lease_class_lines() };
like( $pxe_class, qr/match if substring \(option vendor-class-identifier, 0, 9\) = "PXEClient";/,
    'the class matches the vendor class firmware announces' );
foreach my $bound (qw(min-lease-time default-lease-time max-lease-time)) {
    like( $pxe_class, qr/\b\Q$bound\E 600;/,
        "$bound is named, so the subnet default cannot outrank the class" );
}
is(
    xCAT::DHCP::BootPolicy->kea_pxe_lease_client_class()->{'valid-lifetime'},
    600,
    'and both backends land on the same number',
);

# A loader that is not on disk is not named: naming one costs the client a full
# TFTP timeout it cannot diagnose. The Kea side has always left the class out.
{
    my @asked;
    my %present = map { $_ => 1 } (
        '/srv/tftp/xcat/xnba.efi',
        '/srv/tftp/boot/grub2/grub2.riscv64',
    );
    my $partial = join '', @{ xCAT::DHCP::BootPolicy->isc_client_architecture_lines(
            next_server    => '192.0.2.10',
            portsuffix     => '',
            tftpdir        => '/srv/tftp',
            net            => '192.0.2.0',
            prefix         => 24,
            loader_present => sub { push @asked, $_[0]; return $present{ $_[0] } },
        ) };

    unlike( $partial, qr/xnba\.kpxe/,
        'a BIOS client is not sent after a kpxe loader that was never built' );
    like( $partial, qr/xnba\.efi/,
        'and the UEFI loader that is there is still offered' );

    # The second stage is fetched over HTTP, but it is the first stage that
    # asks for it, so it is gated on the same file.
    unlike( $partial, qr{/xcat/xnba/nets/192\.0\.2\.0_24"},
        'no BIOS second stage is advertised without the first stage to reach it' );
    like( $partial, qr{/xcat/xnba/nets/192\.0\.2\.0_24\.uefi"},
        'the UEFI second stage is advertised, because its first stage exists' );

# Dropping the branch is only half the rule. ISC evaluates these as one if/else
# chain, so a BIOS client whose branch is gone falls to the /yaboot catch-all and
# is handed a loader nobody chose -- the substitution S-12 forbids. What is left
# behind is a branch that matches the same client and says nothing.
    like( $partial,
        qr/option client-architecture = 00:00 \{ #the loader for this client is not on disk\n\s*\}/,
        'a BIOS client whose loader is missing is matched and told nothing' );
    like( $partial,
        qr/option vendor-class-identifier = "Etherboot-5\.4" \{ #the loader for this client is not on disk/,
        'and so is the Etherboot client that would have been sent to the same file' );
    unlike( $partial, qr/00:07 \{ #the loader/,
        'an architecture whose loader is there keeps its real branch' );

    # Position is the whole point: a suppressing branch after the fallback
    # would never be reached.
    ok( index( $partial, 'option client-architecture = 00:00 { #the loader' )
          < index( $partial, 'filename "/yaboot"' ),
        'the client is stopped before the chain reaches the fallback' );

    is( scalar( grep { $_ eq '/srv/tftp/boot/grub2/grub2.riscv64' } @asked ), 1,
        'the riscv64 HTTP branch is probed under the configured tftp directory' );

    # Whatever is dropped, what is left has to still be one chain: dhcpd
    # rejects a leading "} else if" and refuses to start.
    like( $partial, qr/\A    if /, 'the first surviving branch opens the chain' );
    unlike( $partial, qr/\n    \} else if [^\n]*\n\s*\}\n    \} else if /,
        'no branch is left dangling between two chains' );
    is( scalar( () = $partial =~ /^    \}\n/mg ), 1,
        'and the chain is closed exactly once' );
}

{
    # Nothing on disk at all: the branches naming files xCAT never builds stay,
    # and a client matching none of them reaches the fallback rather than a parse
    # error.
    my $bare = join '', @{ xCAT::DHCP::BootPolicy->isc_client_architecture_lines(
            next_server    => '192.0.2.10',
            portsuffix     => '',
            tftpdir        => '/srv/tftp',
            net            => '192.0.2.0',
            prefix         => 24,
            loader_present => sub { return 0 },
        ) };

    like( $bare, qr/\A    if option client-architecture = 00:02 /,
        'the chain opens on the first branch that survives' );
    like( $bare, qr/filename "\/yaboot";\n\s*\}\n\z/,
        'and still ends at the fallback' );
    unlike( $bare, qr/HTTPClient/,
        'the riscv64 HTTP branch goes with the image it would have served' );
}

done_testing();
