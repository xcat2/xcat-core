#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my @pkglist_files = qw(
  xCAT-server/share/xcat/netboot/rh/compute.rhels10.aarch64.pkglist
  xCAT-server/share/xcat/netboot/rh/compute.rhels10.ppc64le.pkglist
  xCAT-server/share/xcat/netboot/rh/compute.rhels10.x86_64.pkglist
);

my %el10_pkglist_aliases = (
    'xCAT-server/share/xcat/netboot/alma/compute.alma10.aarch64.pkglist'   => '../rh/compute.rhels10.aarch64.pkglist',
    'xCAT-server/share/xcat/netboot/rocky/compute.rocky10.aarch64.pkglist' => '../rh/compute.rhels10.aarch64.pkglist',
    'xCAT-server/share/xcat/netboot/rocky/compute.rocky10.ppc64le.pkglist' => '../rh/compute.rhels10.ppc64le.pkglist',
    'xCAT-server/share/xcat/netboot/rocky/compute.rocky10.x86_64.pkglist'  => '../rh/compute.rhels10.x86_64.pkglist',
);

foreach my $file ( sort keys %el10_pkglist_aliases ) {
    my $path = repo_path($file);
    is( readlink($path), $el10_pkglist_aliases{$file}, "$file uses the EL10 package list" );
}

foreach my $file (@pkglist_files) {
    my $path = repo_path($file);
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
