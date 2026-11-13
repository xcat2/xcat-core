#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";
use Test::More;
use imgutils;

# Builds a modules.d that holds the named dracut modules and nothing else.
sub modules_dir {
    my (@modules) = @_;
    my $dir = tempdir(CLEANUP => 1);
    make_path("$dir/$_") for @modules;
    return $dir;
}

# dracut 060 on noble. 40network takes network-legacy, so dracut writes the shell /init.
{
    my $dir = modules_dir(qw(35network-legacy 10systemd 11systemd-initrd 77dracut-systemd 97xcat));
    is(imgutils::dracut_netboot_modules($dir, 0), 'xcat nfs base network-legacy kernel-modules',
        'a dracut that holds network-legacy keeps the module list it had');
}

# dracut 110 on resolute. network-legacy is gone, so 40network takes systemd-networkd and dracut
# writes systemd as /init. systemd needs initrd.target, which the systemd-initrd module installs.
{
    my $dir = modules_dir(qw(10systemd 11systemd-initrd 77dracut-systemd 40network 74nfs 97xcat));
    is(imgutils::dracut_netboot_modules($dir, 0),
        'xcat nfs base network kernel-modules systemd systemd-initrd dracut-systemd',
        'a dracut without network-legacy gets the systemd modules its initial ramdisk needs');
}

# The module names carry no version prefix, so a number the next dracut picks must not matter.
{
    my $dir = modules_dir(qw(00systemd 01systemd-initrd 98dracut-systemd 97xcat));
    is(imgutils::dracut_netboot_modules($dir, 0),
        'xcat nfs base network kernel-modules systemd systemd-initrd dracut-systemd',
        'the systemd modules are found under the numbers an older dracut uses');
}

# A module that is not in the image cannot be put in the list.
{
    my $dir = modules_dir(qw(10systemd 97xcat));
    is(imgutils::dracut_netboot_modules($dir, 0), 'xcat nfs base network kernel-modules systemd',
        'only the systemd modules the image holds are named');
}

# 35network-legacy requires wicked, which a Debian image does not have.
{
    my $dir = modules_dir(qw(35network-legacy 10systemd 11systemd-initrd 77dracut-systemd 97xcat));
    is(imgutils::dracut_netboot_modules($dir, 1), 'xcat nfs base network kernel-modules',
        'an image with wicked keeps the network module and the list it had');
}

# genimage calls this before dracut runs, and the path comes from the image.
{
    my $dir = tempdir(CLEANUP => 1);
    is(imgutils::dracut_netboot_modules("$dir/absent", 0), 'xcat nfs base network kernel-modules',
        'a modules directory that does not exist returns the plain list');
}

done_testing();
