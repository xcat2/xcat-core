#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

# The ISC dhcpd subnet block in dhcp.pm maps DHCP option 93 (client system
# architecture) to a boot file. The block is rendered inside a large
# database-backed subroutine, so this pins the shipped source text: every
# architecture branch must appear before the catch-all that hands unknown
# clients /yaboot, otherwise the branch is unreachable.

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $plugin = File::Spec->catfile( $repo_root, 'xCAT-server', 'lib', 'xcat', 'plugins', 'dhcp.pm' );

plan skip_all => "$plugin not found" unless -r $plugin;

open( my $fh, '<', $plugin ) or die "Unable to read $plugin: $!";
my $source = do { local $/; <$fh> };
close($fh);

my %branch = (
    aarch64 => qr/client-architecture = 00:0b \{[^\n]*\n\s*push \@netent, "\s*filename \\"boot\/grub2\/grub2\.aarch64\\";/,
    riscv64 => qr/client-architecture = 00:1b \{[^\n]*\n\s*push \@netent, "\s*filename \\"boot\/grub2\/grub2\.riscv64\\";/,
    opal    => qr/client-architecture = 00:0e \{/,
    yaboot  => qr/substring\(filename,0,1\) = null \{[^\n]*\n\s*push \@netent, "\s*filename \\"\/yaboot\\";/,
);

my %pos;
for my $name ( sort keys %branch ) {
    ok( $source =~ $branch{$name}, "the ISC subnet block renders the $name branch" )
      or next;
    $pos{$name} = $-[0];
}

SKIP: {
    skip 'not every branch was found', 3 unless 4 == scalar keys %pos;
    cmp_ok( $pos{aarch64}, '<', $pos{riscv64}, 'riscv64 follows the aarch64 branch' );
    cmp_ok( $pos{riscv64}, '<', $pos{opal},    'riscv64 is rendered before the POWER OPAL branch' );
    cmp_ok( $pos{riscv64}, '<', $pos{yaboot},  'riscv64 is rendered before the /yaboot fallback, so it is reachable' );
}

my @riscv_ids = $source =~ /client-architecture = (00:1[9a-e])/g;
is_deeply( \@riscv_ids, ['00:1b'], 'only the RISC-V 64-bit UEFI architecture id (27) is mapped' );

done_testing();
