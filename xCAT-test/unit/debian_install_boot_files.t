#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

# The installer kernel and initrd sit in a different place on every Ubuntu media layout:
# netboot trees name them after the Debian architecture, live images keep them under
# casper, and a hardware-enablement kernel ships beside the release one. Build each layout
# on disk and ask the resolver, rather than reading the table that describes them.

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
my $plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/debian.pm";
plan skip_all => 'debian.pm not found' unless -r $plugin;
eval { require $plugin; 1 } or plan skip_all => "could not load debian.pm: $@";

sub media {
    my (@relative) = @_;
    my $root = tempdir(CLEANUP => 1);
    foreach my $path (@relative) {
        my $full = "$root/$path";
        ($full =~ m{^(.*)/[^/]+$}) and make_path($1);
        open(my $fh, '>', $full) or die "cannot create $full: $!";
        close($fh);
    }
    return $root;
}

sub resolved {
    my ($arch, $darch, $root) = @_;
    my ($kernel, $initrd) =
      xCAT_plugin::debian::install_boot_files($arch, $darch, $root);
    return unless defined $kernel;
    s/^\Q$root\E\/// for ($kernel, $initrd);
    return "$kernel|$initrd";
}

# --- x86_64 layouts, in the order the media are probed ---------------------
is(
    resolved('x86_64', 'amd64',
        media('install/netboot/ubuntu-installer/amd64/linux',
              'install/netboot/ubuntu-installer/amd64/initrd.gz')),
    'install/netboot/ubuntu-installer/amd64/linux|install/netboot/ubuntu-installer/amd64/initrd.gz',
    'a netboot tree is named after the Debian architecture',
);
is(
    resolved('x86_64', 'amd64', media('casper/vmlinuz', 'casper/initrd')),
    'casper/vmlinuz|casper/initrd',
    'a live image keeps its kernel under casper',
);
is(
    resolved('x86_64', 'amd64',
        media('casper/hwe-vmlinuz', 'casper/hwe-initrd', 'casper/vmlinuz', 'casper/initrd')),
    'casper/hwe-vmlinuz|casper/hwe-initrd',
    'the hardware-enablement kernel wins over the release kernel',
);
is(
    resolved('x86_64', 'amd64',
        media('install/hwe-netboot/ubuntu-installer/amd64/linux',
              'install/hwe-netboot/ubuntu-installer/amd64/initrd.gz',
              'casper/vmlinuz', 'casper/initrd')),
    'install/hwe-netboot/ubuntu-installer/amd64/linux|install/hwe-netboot/ubuntu-installer/amd64/initrd.gz',
    'a netboot tree wins over a live image on the same media',
);
is(
    resolved('x86_64', 'amd64', media('install/netboot/vmlinuz', 'install/netboot/initrd.gz')),
    'install/netboot/vmlinuz|install/netboot/initrd.gz',
    'the flat netboot layout resolves',
);

# --- ppc64 layouts ---------------------------------------------------------
is(
    resolved('ppc64', 'ppc64el',
        media('install/netboot/ubuntu-installer/ppc64el/vmlinux',
              'install/netboot/ubuntu-installer/ppc64el/initrd.gz')),
    'install/netboot/ubuntu-installer/ppc64el/vmlinux|install/netboot/ubuntu-installer/ppc64el/initrd.gz',
    'POWER keeps a vmlinux in its netboot tree',
);
is(
    resolved('ppc64le', 'ppc64el', media('install/vmlinux', 'install/netboot/initrd.gz')),
    'install/vmlinux|install/netboot/initrd.gz',
    'the kernel and the initrd may sit in different directories',
);
is(
    resolved('ppc64', 'ppc64el', media('casper/vmlinuz', 'casper/initrd')),
    undef,
    'POWER does not accept the x86 live layout',
);

# --- nothing to boot -------------------------------------------------------
is(resolved('x86_64', 'amd64', media('casper/vmlinuz')), undef,
    'a kernel without its initrd is not a match');
is(resolved('x86_64', 'amd64', media('README')), undef,
    'media with no installer resolves to nothing');
is(resolved('s390x', 's390x', media('casper/vmlinuz', 'casper/initrd')), undef,
    'an architecture the table does not describe resolves to nothing');

done_testing();
