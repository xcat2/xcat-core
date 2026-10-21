#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Test::More;

# xCAT decides that an Ubuntu osimage uses the Subiquity installer from the NAME of the template
# it resolved: xCAT_plugin::debian::using_subiquity matches /subiquity/ in the path. That decision
# controls the netboot kernel command line. A template whose name does not match it makes xCAT
# boot the live-server initrd with the debian-installer preseed arguments, without boot=casper and
# without nfsroot, and the node never finds a live filesystem.
#
# The compute profile has compute.subiquity.tmpl. The service profile had only service.tmpl, so an
# Ubuntu 24.04 service node took the preseed path.

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use xCAT::SvrUtils;

my $plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/debian.pm";
plan skip_all => 'debian.pm not found' unless -r $plugin;
eval { require $plugin; 1 } or plan skip_all => "could not load debian.pm: $@";

my $share = "$FindBin::Bin/../../xCAT-server/share/xcat/install/ubuntu";
plan skip_all => "$share not found" unless -d $share;

# get_file_name takes genos as its last argument. update_tables_with_templates passes 'subiquity'
# for every Ubuntu 20.04 and later osimage.
sub resolved {
    my ($profile, $osver, $genos) = @_;
    return xCAT::SvrUtils::get_tmpl_file_name($share, $profile, $osver, 'x86_64', $genos);
}

for my $profile (qw(compute service)) {
    my $tmpl = resolved($profile, 'ubuntu24.04', 'subiquity');
    ok(defined $tmpl && -r $tmpl, "$profile: Ubuntu 24.04 resolves an install template");
    ok(xCAT_plugin::debian::using_subiquity('ubuntu24.04', $tmpl),
        "$profile: the Ubuntu 24.04 template xCAT resolved is a Subiquity one");
}

# Ubuntu 18.04 predates Subiquity and keeps the preseed path. genos stays the os version there.
for my $profile (qw(compute service)) {
    my $tmpl = resolved($profile, 'ubuntu18.04', 'ubuntu18.04');
    ok(defined $tmpl && -r $tmpl, "$profile: Ubuntu 18.04 resolves an install template");
    ok(!xCAT_plugin::debian::using_subiquity('ubuntu18.04', $tmpl),
        "$profile: Ubuntu 18.04 keeps the debian-installer template");
}

# The service template must carry the autoinstall document Subiquity reads. A file named for
# Subiquity that holds a preseed would satisfy using_subiquity and still not install.
my $service = resolved('service', 'ubuntu24.04', 'subiquity');
SKIP: {
    skip 'no service template resolved', 3 unless defined $service && -r $service;
    my $text = do { local $/; open my $fh, '<', $service or die "$service: $!"; <$fh> };
    like($text, qr/^#cloud-config/,  'the service template is a cloud-config document');
    like($text, qr/^autoinstall:/m,  '... carrying an autoinstall section');
    unlike($text, qr/^d-i /m,        '... and no debian-installer preseed directives');
}

done_testing();
