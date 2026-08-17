#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

my $plugin_path = defined $ENV{XCATROOT} ? "$ENV{XCATROOT}/lib/perl/xCAT_plugin/debian.pm" : '';
$plugin_path = "xCAT-server/lib/xcat/plugins/debian.pm"
    unless -f $plugin_path;

plan skip_all => "debian.pm not found" unless -f $plugin_path;

my $src = do { local $/; open my $fh, '<', $plugin_path or die $!; <$fh> };

like($src, qr/autoinstall ip=dhcp boot=casper netboot=nfs/,
    'subiquity bootparams enable autoinstall (boot=casper is required for casper to process netboot=nfs)');
like($src, qr/ds=nocloud-net;s=http:\/\//, 'subiquity bootparams point at NoCloud seed');
like($src, qr/\$kcmdline\s*\.=\s*" ---";/, 'subiquity bootparams end with installer argument separator');

done_testing();
