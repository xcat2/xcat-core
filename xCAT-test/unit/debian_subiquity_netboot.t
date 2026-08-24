#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Regression: the Ubuntu (subiquity) diskful install netboots the live installer over NFS.
# The kernel command line built in debian.pm must satisfy TWO casper requirements or the
# installer never boots and the node PXE-loops forever (surfacing to the test as
# "ssh: connect ... port 22: Connection refused"):
#
#   1. boot=casper -- without it casper does not process netboot=nfs at all; it scans the
#      local disks, finds nothing, and panics "Unable to find a medium containing a live
#      file system", dropping to the initramfs emergency shell.
#
#   2. nfsroot must be a literal IP, NOT a hostname. casper mounts the live filesystem with
#      klibc's nfsmount, which does NOT resolve hostnames -- it fails with
#      "nfsmount: can't parse IP address '<mn-hostname>'". (busybox/util-linux `mount -t nfs`
#      resolves names, which is why manual mounts work while casper's does not.) The instserver
#      must therefore be passed through xCAT::NetworkUtils->getipaddr() before it is put in
#      nfsroot=. The ds=...http URL is fetched later by cloud-init in the booted live system,
#      where normal DNS works, so only nfsroot needs the IP.

sub slurp { my ($p) = @_; local $/; open my $fh, '<', $p or return undef; <$fh> }

my $deb = slurp('xCAT-server/lib/xcat/plugins/debian.pm');
plan skip_all => 'debian.pm not found' unless defined $deb;

# The exact netboot fragment is unique to the subiquity install cmdline, so match it directly
# instead of trying to slice one of the several using_subiquity() blocks.
like($deb, qr/\bboot=casper\b/,
    'subiquity netboot kcmdline includes boot=casper (else casper scans local disks and panics)');
like($deb, qr/autoinstall ip=dhcp boot=casper netboot=nfs nfsroot=\$\{nfsip\}:/,
    'subiquity kcmdline is: autoinstall ip=dhcp boot=casper netboot=nfs nfsroot=<ip>');
like($deb, qr/getipaddr\(\$instserver\)/,
    'instserver is resolved to an IP via getipaddr for nfsroot (klibc nfsmount cannot resolve hostnames)');
unlike($deb, qr/nfsroot=\$\{instserver\}:/,
    'nfsroot does NOT use the bare instserver hostname (would break klibc nfsmount)');

# The subiquity netboot cmdline must include 'toram' so casper copies the squashfs into RAM and
# unmounts the NFS source -- otherwise the end-of-install reboot wedges in systemd-shutdown on a
# D-state process doing I/O to the still-mounted NFS root, and the node never boots the installed disk.
like($deb, qr/\btoram\b/,
    'subiquity netboot cmdline includes toram (run from RAM, no NFS root at shutdown -> no reboot hang)');
unlike($deb, qr/nfsroot=[^ ]*,soft/,
    'nfsroot does NOT append ,soft (casper takes the whole nfsroot value as the path, which breaks the mount)');

done_testing();
