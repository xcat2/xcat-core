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

done_testing();
