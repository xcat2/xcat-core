#!/usr/bin/env perl
# radvd has to be installed, because makedhcp writes its configuration.
#
# configure_router_advertisements writes /etc/radvd.conf for every IPv6 network in the networks
# table and then starts the service. No package declared radvd, so on a management node that
# did not happen to carry it the file was written and nothing read it. A client that follows
# RFC 4861 starts DHCPv6 only when an advertisement sets the managed flag, and takes its
# on-link prefix and default route from the advertisement, so an IPv6-only node received one
# address with a prefix length of 128 and no route to its server.
#
# Measured on an Ubuntu management node on 2026-10-30: radvd.service was "not-found" while
# /etc/radvd.conf held the right configuration, and the compute node's installer answered
# "wget: can't connect to remote host: Cannot assign requested address".
#
# The manifests are the artifact here, so they are read rather than executed.
use strict;
use warnings;

use File::Slurper qw(read_text);
use File::Spec;
use FindBin;
use Test::More;

my $root = File::Spec->catdir( $FindBin::Bin, '..', '..' );

# The management node and the service node both answer DHCP, so both write radvd.conf.
my %rpm = (
    'xCAT/xCAT.spec'     => 'xCAT',
    'xCATsn/xCATsn.spec' => 'xCATsn',
);
foreach my $file ( sort keys %rpm ) {
    my $path = File::Spec->catfile( $root, $file );
    SKIP: {
        skip "$file not found", 1 unless -f $path;
        my $text = read_text($path);
        like( $text, qr/^Requires:\s*radvd\s*$/m,
            "$rpm{$file} requires radvd" );
    }
}

my %deb = (
    'xCAT/debian/control'     => 'xcat',
    'xCATsn/debian/control'   => 'xcatsn',
);
foreach my $file ( sort keys %deb ) {
    my $path = File::Spec->catfile( $root, $file );
    SKIP: {
        skip "$file not found", 2 unless -f $path;
        my $text = read_text($path);
        my ($depends) = $text =~ /^Depends:\s*(.*)$/m;
        ok( defined($depends), "$deb{$file} has a Depends line" );
        # A Recommends is not enough: the apt 3.0 solver drops them, which is what took
        # bind9 out of the Ubuntu 26.04 install and left makedns with no named.
        like( $depends, qr/(?:^|,)\s*radvd\s*(?:,|$)/,
            "$deb{$file} depends on radvd, not merely recommends it" );
    }
}

done_testing();
