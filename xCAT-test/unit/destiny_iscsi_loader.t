#!/usr/bin/env perl
# nodeset iscsiboot accepts an x86 node without iSCSI boot data when this server has a loader that can
# SAN-boot it: an undionly.kpxe in the TFTP root, or the BIOS file of the loader of the netboot method
# of the node. Each case builds a TFTP tree that holds one candidate file, or none.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;

use xCAT::DHCP::BootPolicy;

sub tree_with {
    my ($file) = @_;
    my $root = tempdir( CLEANUP => 1 );
    if ($file) {
        ( my $dir = "$root/$file" ) =~ s{/[^/]+$}{};
        make_path($dir);
        open( my $fh, '>', "$root/$file" ) or die "write $file: $!";
        close($fh);
    }
    return $root;
}

# Each case: the file in the tree, and whether it is enough for an xnba node and for an ipxe node.
my @cases = (
    [ undef,                             0, 0, 'no loader' ],
    [ 'undionly.kpxe',                   1, 1, 'an undionly.kpxe in the TFTP root' ],
    [ 'xcat/xnba.kpxe',                  1, 0, 'the xNBA loader' ],
    [ 'xcat/ipxe/i386/undionly.kpxe',    0, 1, 'the upstream BIOS loader' ],
    [ 'xcat/ipxe/x86_64-sb/snponly-shim.efi', 0, 0, 'only the upstream UEFI loader' ],
);
for my $case (@cases) {
    my ( $file, $xnba, $ipxe, $name ) = @$case;
    my $root = tree_with($file);
    is( xCAT::DHCP::BootPolicy->x86_san_loader_present( tftpdir => $root, method => 'xnba' ),
        $xnba, "xnba: $name " . ( $xnba ? 'is enough' : 'is not enough' ) );
    is( xCAT::DHCP::BootPolicy->x86_san_loader_present( tftpdir => "$root/", method => 'ipxe' ),
        $ipxe, "ipxe: $name " . ( $ipxe ? 'is enough' : 'is not enough' ) );
}
is( xCAT::DHCP::BootPolicy->x86_san_loader_present( tftpdir => tree_with('xcat/xnba.kpxe') ), 1,
    'a node without a netboot method is checked like an xnba node' );

done_testing();
