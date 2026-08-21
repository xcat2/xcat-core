#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Regression: makentp/setupntp configure a server-capable NTP daemon (chronyd/ntpd) on the MN.
# On a minimal Ubuntu 24.04 MN chrony was absent (Ubuntu ships only the client-only
# systemd-timesyncd), hwclock moved to util-linux-extra (absent) so setupntp aborted its whole NTP
# setup, and timesyncd was left fighting the NTP daemon -- reding reg_linux_diskfull_installation_flat.

sub slurp { my ($p) = @_; local $/; open my $fh, '<', $p or return undef; <$fh> }

my $setupntp = slurp('xCAT/postscripts/setupntp');
SKIP: {
    skip 'setupntp not found', 4 unless defined $setupntp;
    unlike($setupntp, qr/check_exec_or_exit[^\n]*\bhwclock\b/,
        'setupntp does NOT hard-require hwclock in check_exec_or_exit');
    like($setupntp, qr/command -v hwclock/,
        'setupntp guards its hwclock use so a missing hwclock is non-fatal');
    like($setupntp, qr/systemctl\s+(?:stop|disable)\s+systemd-timesyncd/,
        'setupntp stops/disables systemd-timesyncd so it does not fight the NTP daemon');
    like($setupntp, qr/chronyd\s+-f\s+\S*\s+-q/,
        'setupntp still steps the system clock via a one-shot chronyd -q');
}

my $ctrl = slurp('xCAT/debian/control');
SKIP: {
    skip 'debian/control not found', 2 unless defined $ctrl;
    like($ctrl, qr/^Depends:.*\bchrony \| ntp\b/m,
        'xcat debian package Depends on chrony | ntp (server-capable NTP daemon)');
    like($ctrl, qr/^Recommends:.*\butil-linux-extra\b/m,
        'xcat debian package Recommends util-linux-extra (provides hwclock on noble+)');
}

my $spec = slurp('xCAT/xCAT.spec');
SKIP: {
    skip 'xCAT.spec not found', 1 unless defined $spec;
    like($spec, qr/^Requires:\s*\(chrony or ntp\)/m,
        'xCAT rpm Requires (chrony or ntp) for makentp');
}

my $makentp = slurp('xCAT-server/lib/xcat/plugins/makentp.pm');
SKIP: {
    skip 'makentp.pm not found', 1 unless defined $makentp;
    like($makentp, qr/xCAT::NTP::Backend->choose/,
        'makentp selects the NTP daemon through the xCAT::NTP::Backend selector');
}

done_testing();
