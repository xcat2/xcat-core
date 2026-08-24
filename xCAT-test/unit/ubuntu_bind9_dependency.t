#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

# Regression: xCAT manages the cluster DNS with `makedns`, which drives named, so a management
# node (and a service node) requires a DNS server as surely as it requires a DHCP backend.
# bind9 was only a Recommends, which is installed only while the system's APT recommendation
# policy asks for it -- nothing guarantees named is on the node.
#
# On an Ubuntu 26.04 management node it was not there: no /usr/sbin/named, `makedns` failed with
# "failed to start named", and provisioning broke before a node was ever deployed.
#
# Make bind9 a hard Depends on both metapackages so the DNS backend is guaranteed regardless of
# that policy, mirroring the existing "isc-dhcp-server | kea" Depends.

my $repo_root = File::Spec->rel2abs(
    File::Spec->catdir( $FindBin::Bin, '..', '..' )
);

sub read_file {
    my ($filename) = @_;
    open( my $fh, '<', $filename ) or die "Unable to read $filename: $!";
    my $content = do { local $/; <$fh> };
    close($fh);
    return $content;
}

foreach my $pkg ( [ 'xCAT', 'xcat' ], [ 'xCATsn', 'xcatsn' ] ) {
    my ( $dir, $name ) = @$pkg;
    my $control = read_file( File::Spec->catfile( $repo_root, $dir, 'debian', 'control' ) );

    my ($depends)    = $control =~ /^Depends:\s*(.*)$/m;
    my ($recommends) = $control =~ /^Recommends:\s*(.*)$/m;

    ok( defined $depends, "$name debian/control has a Depends line" );

    like( $depends, qr/(?:^|,)\s*bind9\s*(?:,|$)/,
        "$name Depends on bind9 (required by makedns, so not a Recommends)" );

    unlike( $recommends, qr/(?:^|,)\s*bind9\s*(?:,|$)/,
        "$name no longer carries bind9 as a Recommends" );
}

done_testing();
