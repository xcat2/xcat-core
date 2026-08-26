#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Test::More;

# The Ubuntu live installer (Subiquity) is booted over NFS. Three things on the kernel command
# line decide whether it boots at all and whether the node can reboot into the disk afterwards:
#
#   boot=casper  without it casper never processes netboot=nfs -- it scans local disks, finds no
#                live media and panics into the initramfs shell, which PXE-loops.
#   nfsroot=IP   casper mounts the live filesystem with klibc's nfsmount, which has no resolver,
#                so a hostname there fails with "can't parse IP address".
#   toram        casper copies the squashfs to RAM and unmounts the NFS source. Without it the
#                NFS root stays mounted, systemd-shutdown blocks forever on I/O to it and the
#                node never power-cycles into the disk it just installed.
#
# Build the command line for real and inspect it, rather than reading the source that builds it.

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
my $plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/debian.pm";
plan skip_all => 'debian.pm not found' unless -r $plugin;
eval { require $plugin; 1 } or plan skip_all => "could not load debian.pm: $@";

my $cmdline = xCAT_plugin::debian::subiquity_kcmdline(
    'nofb utf8 auto xcatd=xcatmn',    # what mkinstall has built so far
    '10.0.0.1',                       # instserver resolved to a literal IP
    '/install/ubuntu24.04/x86_64',    # pkgdir exported over NFS
    'xcatmn',                         # instserver by name
    '80',                             # httpport
    'node01',                         # node
);

# --- the three settings the installer cannot boot without ------------------
like($cmdline, qr/(?:^| )boot=casper(?: |$)/,
    'casper is told to boot, so it processes netboot=nfs instead of scanning disks');
like($cmdline, qr{(?:^| )nfsroot=10\.0\.0\.1:/install/ubuntu24\.04/x86_64(?: |$)},
    'nfsroot names the install server by IP, which klibc nfsmount can parse');
like($cmdline, qr/(?:^| )toram(?: |$)/,
    'toram copies the live filesystem to RAM so the NFS root is unmounted before shutdown');

unlike($cmdline, qr/nfsroot=xcatmn:/,
    'nfsroot never carries a hostname, which klibc nfsmount cannot resolve');
unlike($cmdline, qr/nfsroot=[^ ]*,/,
    'no mount options are appended to nfsroot -- casper takes the whole value as the path');

# --- the rest of the line ---------------------------------------------------
like($cmdline, qr/(?:^| )autoinstall(?: |$)/, 'the installer runs unattended');
like($cmdline, qr/(?:^| )ip=dhcp(?: |$)/,     'the live system configures its NIC by DHCP');
like($cmdline, qr/(?:^| )netboot=nfs(?: |$)/, 'the live filesystem is fetched over NFS');

# cloud-init fetches the seed later, in the booted live system, where DNS works -- so this one
# keeps the install server's name rather than its address.
like($cmdline, qr{(?:^| )ds=nocloud-net;s=http://xcatmn:80/install/autoinst/node01/(?: |$)},
    'the cloud-init seed URL addresses the install server by name');

is((split / /, $cmdline)[-1], '---',
    'the line ends with the separator that divides installer arguments from kernel arguments');

# What mkinstall had already built is preserved, not replaced.
like($cmdline, qr/^nofb utf8 auto xcatd=xcatmn /,
    'the command line built so far is kept ahead of the installer arguments');

# A non-default HTTP port reaches the seed URL.
{
    my $alt = xCAT_plugin::debian::subiquity_kcmdline(
        'base', '10.0.0.1', '/pkgdir', 'xcatmn', '8080', 'node02');
    like($alt, qr{ds=nocloud-net;s=http://xcatmn:8080/install/autoinst/node02/},
        'the seed URL carries the configured HTTP port and node');
}

done_testing();
