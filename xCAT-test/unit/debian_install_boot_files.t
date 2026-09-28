#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

# The installer kernel and initrd sit in a different place on every Ubuntu media layout.
# Build each layout on disk and ask the resolver, rather than read the table that
# describes them.

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

# --- riscv64 -------------------------------------------------------------
is(
    resolved('riscv64', 'riscv64', media('casper/vmlinux', 'casper/initrd')),
    'casper/vmlinux|casper/initrd',
    'the riscv64 live image keeps its kernel under a different name',
);
is(
    resolved('riscv64', 'riscv64', media('casper/vmlinuz', 'casper/initrd')),
    undef,
    'riscv64 does not accept the kernel name the other live images use',
);

# The Ubuntu ppc64el live-server ISO carries no netboot tree. 22.04 and 24.04 ship the
# hardware-enablement pair under casper beside the release pair; 26.04 ships the release
# pair only.
is(
    resolved('ppc64le', 'ppc64el', media('casper/vmlinux', 'casper/initrd')),
    'casper/vmlinux|casper/initrd',
    'the POWER live image keeps its kernel under casper',
);
is(
    resolved('ppc64le', 'ppc64el',
        media('casper/hwe-vmlinux', 'casper/hwe-initrd', 'casper/vmlinux', 'casper/initrd')),
    'casper/hwe-vmlinux|casper/hwe-initrd',
    'the POWER hardware-enablement kernel wins over the release kernel',
);
is(
    resolved('ppc64le', 'ppc64el',
        media('install/netboot/ubuntu-installer/ppc64el/vmlinux',
              'install/netboot/ubuntu-installer/ppc64el/initrd.gz',
              'casper/vmlinux', 'casper/initrd')),
    'install/netboot/ubuntu-installer/ppc64el/vmlinux|install/netboot/ubuntu-installer/ppc64el/initrd.gz',
    'a POWER netboot tree still wins over a live image on the same media',
);

# mkinstall asks this routine, so it accepts every media install_boot_files resolves.
can_ok('xCAT_plugin::debian', 'install_media_is_bootable');
is(
    xCAT_plugin::debian::install_media_is_bootable('ppc64le', 'ppc64el',
        media('casper/vmlinux', 'casper/initrd')),
    1,
    'a POWER live image is bootable media',
);
is(
    xCAT_plugin::debian::install_media_is_bootable('ppc64le', 'ppc64el',
        media('install/netboot/ubuntu-installer/ppc64el/vmlinux',
              'install/netboot/ubuntu-installer/ppc64el/initrd.gz')),
    1,
    'a POWER netboot tree is bootable media',
);
is(
    xCAT_plugin::debian::install_media_is_bootable('ppc64le', 'ppc64el', media('README')),
    0,
    'media with no installer is not bootable media',
);
is(
    xCAT_plugin::debian::install_media_is_bootable('x86_64', 'amd64',
        media('casper/vmlinuz', 'casper/initrd')),
    1,
    'an x86 live image is bootable media',
);

# --- nothing to boot -------------------------------------------------------
is(resolved('x86_64', 'amd64', media('casper/vmlinuz')), undef,
    'a kernel without its initrd is not a match');
is(resolved('x86_64', 'amd64', media('README')), undef,
    'media with no installer resolves to nothing');
is(resolved('s390x', 's390x', media('casper/vmlinuz', 'casper/initrd')), undef,
    'an architecture the table does not describe resolves to nothing');

done_testing();
