#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );

sub read_file {
    my ($file) = @_;
    my $path = File::Spec->catfile( $repo_root, $file );

    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh);

    return $contents;
}

my $spec = read_file('xCAT-server/xCAT-server.spec');
unlike( $spec, qr/\bdnf\s+download\b/, 'xCAT-server RPM scripts do not download packages' );
unlike( $spec, qr{/install/dhcp_pkgs}, 'xCAT-server RPM scripts do not write hidden DHCP package directories' );

my $anaconda = read_file('xCAT-server/lib/xcat/plugins/anaconda.pm');
unlike( $anaconda, qr{/install/dhcp_pkgs}, 'copycds does not inject hidden DHCP package directories into pkgdir' );

my @pkglist_files = qw(
  xCAT-server/share/xcat/netboot/rh/compute.rhels10.ppc64le.pkglist
  xCAT-server/share/xcat/netboot/rh/compute.rhels10.x86_64.pkglist
);

my %el10_pkglist_aliases = (
    'xCAT-server/share/xcat/netboot/rocky/compute.rocky10.ppc64le.pkglist' => '../rh/compute.rhels10.ppc64le.pkglist',
    'xCAT-server/share/xcat/netboot/rocky/compute.rocky10.x86_64.pkglist'  => '../rh/compute.rhels10.x86_64.pkglist',
);

foreach my $file ( sort keys %el10_pkglist_aliases ) {
    my $path = File::Spec->catfile( $repo_root, $file );
    is( readlink($path), $el10_pkglist_aliases{$file}, "$file uses the EL10 package list" );
}

foreach my $file (@pkglist_files) {
    my $path = File::Spec->catfile( $repo_root, $file );
    open( my $fh, '<', $path ) or die "Unable to read $path: $!";

    my @packages;
    while ( my $line = <$fh> ) {
        chomp $line;
        next if $line =~ /^\s*(?:#|$)/;
        push @packages, $line;
    }
    close($fh);

    my %packages = map { $_ => 1 } @packages;
    ok( $packages{'NetworkManager'}, "$file uses NetworkManager for EL10 DHCP handling" );
    ok( !$packages{'dhclient'},      "$file avoids removed dhclient package" );
    ok( !$packages{'dhcp-client'},   "$file avoids removed dhcp-client package" );
}

done_testing();
