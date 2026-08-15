#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Regression: the Ubuntu (subiquity) diskful install netboots the live installer over NFS
# (casper netboot=nfs). At end-of-install Subiquity issues a graceful `systemctl reboot`, but
# systemd-shutdown then HANGS forever waiting for an lvm/pvscan process wedged in uninterruptible
# (D-state) I/O on the NFS-mounted live-installer root being torn down -- it cannot SIGKILL a
# D-state process, so the machine never reboots and never power-cycles into the freshly installed
# disk. The provision then times out even though the on-disk install is perfect (verified: a hard
# reset boots the installed OS cleanly).
#
# The template must therefore schedule a FORCED reboot (magic-sysrq 'b') as a safety net so the
# node power-cycles into local disk regardless of the hung graceful shutdown.

sub slurp { my ($p) = @_; local $/; open my $fh, '<', $p or return undef; <$fh> }

my $tmpl = slurp('xCAT-server/share/xcat/install/ubuntu/compute.subiquity.tmpl');
plan skip_all => 'compute.subiquity.tmpl not found' unless defined $tmpl;

like($tmpl, qr{/proc/sysrq-trigger},
    'late-commands force a reboot via magic-sysrq (safety net for the NFS-root shutdown hang)');
like($tmpl, qr{echo\s+1\s*>\s*/proc/sys/kernel/sysrq},
    'magic-sysrq is enabled before triggering the forced reboot');
like($tmpl, qr{echo\s+b\s*>\s*/proc/sysrq-trigger},
    'the forced reboot uses sysrq "b" (immediate reboot, bypassing the hung systemd-shutdown)');

done_testing();
