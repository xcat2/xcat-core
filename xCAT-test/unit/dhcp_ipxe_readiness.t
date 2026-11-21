#!/usr/bin/env perl
# makedhcp warns when a server that serves x86 discovery cannot give unknown clients the upstream
# loader: a loader file is missing from its TFTP directory, or mknb has not written the network
# scripts under xcat/ipxe/nets. Each case builds a TFTP tree in a scratch directory.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;

use xCAT::DHCP::BootPolicy;

my $bios = 'xcat/ipxe/i386/undionly.kpxe';
my $uefi = 'xcat/ipxe/x86_64-sb/snponly-shim.efi';
my $payload = 'xcat/ipxe/x86_64-sb/snponly.efi';

sub tree_with {
    my (@files) = @_;
    my $root = tempdir( CLEANUP => 1 );
    for my $file (@files) {
        ( my $dir = "$root/$file" ) =~ s{/[^/]+$}{};
        make_path($dir);
        open( my $fh, '>', "$root/$file" ) or die "write $file: $!";
        close($fh);
    }
    return $root;
}

sub warnings_for { return [ xCAT::DHCP::BootPolicy->upstream_loader_warnings( tftpdir => $_[0] ) ] }

is_deeply( warnings_for( tree_with() ), [], 'a server without x86 network boot scripts gets no warning' );
is_deeply( warnings_for( tree_with( $bios, $uefi, $payload, 'xcat/ipxe/nets/192.0.2.0_24' ) ), [], 'a ready server gets no warning' );

# An upgraded server before mknb: the xNBA scripts are there, the upstream ones and ipxe-xcat are not.
my $upgraded = tree_with('xcat/xnba/nets/192.0.2.0_24');
my $warnings = warnings_for($upgraded);
is( scalar @$warnings, 4, 'an upgraded server before mknb and ipxe-xcat gets four warnings' );
like( $warnings->[0], qr{\Q$upgraded/$bios\E is missing}, 'one for the upstream BIOS loader' );
like( $warnings->[1], qr{\Q$upgraded/$uefi\E is missing}, 'one for the shim of the upstream UEFI loader' );
like( $warnings->[2], qr{\Q$upgraded/$payload\E is missing}, 'one for the UEFI loader that the shim loads' );
like( $warnings->[3], qr{\Q$upgraded\E/xcat/ipxe/nets has no network boot script.*Run mknb}, 'and one for the network scripts' );

$warnings = warnings_for( tree_with( $bios, $payload, 'xcat/ipxe/nets/192.0.2.0_24' ) );
is( scalar @$warnings, 1, 'a missing shim alone gets one warning' );
like( $warnings->[0], qr{/\Q$uefi\E is missing}, 'for the shim' );
$warnings = warnings_for( tree_with( $bios, $uefi, 'xcat/ipxe/nets/192.0.2.0_24' ) );
is( scalar @$warnings, 1, 'a shim without the loader it loads gets one warning' );
like( $warnings->[0], qr{/\Q$payload\E is missing}, 'for that loader' );
like( warnings_for( tree_with('xcat/xnba/nets/x') . '/' )->[0], qr{[^/]/xcat/ipxe/i386}, 'a trailing slash on the TFTP directory is dropped' );
$warnings = warnings_for( tree_with( $bios, $uefi, $payload, 'xcat/xnba/nets/x', 'xcat/ipxe/nets/sub/x' ) );
is( scalar @$warnings, 1, 'a directory under xcat/ipxe/nets is not a network boot script' );
like( $warnings->[0], qr{xcat/ipxe/nets has no network boot script}, 'so the network scripts are still missing' );

# ---- A NODE whose own loader is missing, which upstream_loader_warnings cannot see -----------
# upstream_loader_warnings reads the SITE TFTP directory and runs on makedhcp -n and -a only. A
# node carries its own noderes.tftpdir, and makedhcp <node> never calls it at all, so
# dhcp6_bootfile_url_for_node dropped the DHCPv6 boot file with nothing said anywhere: makedhcp
# exited 0 and the node sat at a firmware timeout.
my $ready = tree_with($uefi);
my @none = xCAT::DHCP::BootPolicy->dhcp6_missing_loader_warning(
    node => "cn01", tftpdir => $ready, loader => $uefi );
is( scalar @none, 0, "a node whose loader is on disk gets no warning" );

my $missing_dir = tree_with();
my ($warning) = xCAT::DHCP::BootPolicy->dhcp6_missing_loader_warning(
    node => "cn01", tftpdir => $missing_dir, loader => $uefi );
like( $warning, qr{\Q$missing_dir/$uefi\E},
      "a node whose loader is absent gets a warning naming the FULL PATH it looked for" );
like( $warning, qr{\bcn01\b}, "... and the node, so a per-node tftpdir is attributable" );
like( $warning, qr/no DHCPv6 boot file/,
      "... and the consequence, which is the thing the silence hid" );
like( $warning, qr/ipxe-xcat/, "... and the package that supplies the loader" );

# A trailing slash on the tftpdir must not double in the path, or the warning names a file that
# never existed and the reader looks in the wrong place.
($warning) = xCAT::DHCP::BootPolicy->dhcp6_missing_loader_warning(
    node => "cn01", tftpdir => "$missing_dir/", loader => $uefi );
like( $warning, qr{\Q$missing_dir/$uefi\E}, "a trailing slash on the TFTP directory is dropped" );
unlike( $warning, qr{//}, "... and no doubled separator is left in the path" );

# No tftpdir and no loader are not a missing file. dhcp6_bootfile_url_for_node keeps the boot
# file in both cases, so a warning here would be a false alarm on every such node.
for my $case ( [ "an unset tftpdir", { tftpdir => undef, loader => $uefi } ],
               [ "an empty tftpdir", { tftpdir => "",    loader => $uefi } ],
               [ "an unset loader",  { tftpdir => $missing_dir, loader => undef } ] )
{
    my @quiet = xCAT::DHCP::BootPolicy->dhcp6_missing_loader_warning(
        node => "cn01", %{ $case->[1] } );
    is( scalar @quiet, 0, "$case->[0] is not reported as a missing loader" );
}

done_testing();
