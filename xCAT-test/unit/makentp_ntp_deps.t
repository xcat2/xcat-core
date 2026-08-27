#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Temp qw(tempdir);
use Test::More;

# A stock Ubuntu MN broke three ways: a missing hwclock aborted the whole NTP setup,
# systemd-timesyncd kept fighting the daemon being configured, and the xcat package pulled in no
# daemon that can serve time. The first two are behaviours of the script, so run it; the third is
# a property of the packaging manifests, so read those.

my $repo = "$FindBin::Bin/../..";
my $setupntp_path = "$repo/xCAT/postscripts/setupntp";
plan skip_all => 'setupntp not found' unless -r $setupntp_path;
plan skip_all => 'setupntp targets Linux management nodes' unless $^O eq 'linux';

open(my $fh, '<', $setupntp_path) or die "open $setupntp_path: $!";
my @lines = <$fh>;
close $fh;
my $source = join '', @lines;

# setupntp forces its own PATH and exits unless UID is 0, so it cannot be stubbed from outside
# or run unprivileged. Drive its own helper functions with shell functions instead: bash resolves
# those ahead of PATH, and both `type` and `command -v` report them as present.
my ($helpers) = $source =~ /\A(.*?)^\[ "\$\{UID\}" -eq "0" \]/ms;
my ($body)    = $source =~ /^(check_exec_or_exit cp cat logger grep\n.*?)^CHRONY_CONF=/ms;
BAIL_OUT('could not take the helper functions from setupntp')          unless $helpers;
BAIL_OUT('could not take the daemon setup section from setupntp')      unless $body;

sub run_setupntp {
    my (%opt) = @_;
    my $root = tempdir(CLEANUP => 1);

    # Record every call the section makes, and answer as the case requires.
    my $doubles = <<"BASH";
log() { printf '%s\\n' "\$*" >>"$root/calls"; }
systemctl()   { log "systemctl \$*"; return 0; }
timedatectl() { log "timedatectl \$*"; return 0; }
chronyd()     { log "chronyd \$*"; return 0; }
logger()      { log "logger \$*"; return 0; }
rm()          { log "rm \$*"; return 0; }
BASH
    $doubles .= $opt{hwclock}
      ? qq{hwclock() { log "hwclock \$*"; return 0; }\n}
      # hwclock genuinely absent: hide it from both probes the script can use
      : qq{command() { if [ "\$1" = "-v" ] && [ "\$2" = "hwclock" ]; then return 1; fi; builtin command "\$@"; }\n}
        . qq{type() { if [ "\$1" = "hwclock" ]; then return 1; fi; builtin type "\$@"; }\n};

    $doubles .= "declare -a NTP_SERVERS=(" . ($opt{server} ? qq{"$opt{server}"} : '') . ")\n";
    $doubles .= "log_label=xcat\n";

    my $rc = system('bash', '-c', $doubles . $helpers . $body);

    my $calls = '';
    if (open my $ch, '<', "$root/calls") { local $/; $calls = <$ch>; close $ch }
    return { rc => $rc >> 8, calls => $calls };
}

# --- a management node with no hwclock: the bug this fix exists for --------
{
    my $r = run_setupntp(hwclock => 0);

    is($r->{rc}, 0, 'setupntp completes on a node with no hwclock instead of aborting');
    like($r->{calls}, qr/^chronyd .*-q/m,
        'the system clock is still stepped, which is the part that never needed hwclock');
    unlike($r->{calls}, qr/^hwclock/m, 'and no attempt is made to use the missing hwclock');
    like($r->{calls}, qr/hwclock not present/,
        'the skipped RTC persist is reported rather than passing silently');
}

# --- a management node that has hwclock ------------------------------------
{
    my $r = run_setupntp(hwclock => 1);

    is($r->{rc}, 0, 'setupntp completes on a node that has hwclock');
    like($r->{calls}, qr/^hwclock --systohc --utc$/m,
        'the stepped system clock is persisted to the RTC when hwclock is available');
    like($r->{calls}, qr/^chronyd .*-q/m, 'the clock is stepped in this case too');
}

# --- systemd-timesyncd must yield to the NTP daemon ------------------------
foreach my $case ([ 'with hwclock', 1 ], [ 'without hwclock', 0 ]) {
    my ($name, $hwclock) = @$case;
    my $r = run_setupntp(hwclock => $hwclock);

    like($r->{calls}, qr/^systemctl stop systemd-timesyncd\.service$/m,
        "$name: systemd-timesyncd is stopped so it stops disciplining the clock");
    like($r->{calls}, qr/^systemctl disable systemd-timesyncd\.service$/m,
        "$name: systemd-timesyncd is disabled so it does not come back on the next boot");
}

# --- the configured NTP server reaches the clock step ----------------------
{
    my $r = run_setupntp(hwclock => 1, server => 'ntp.example.com');
    like($r->{calls}, qr/^chronyd .*server ntp\.example\.com iburst/m,
        'the clock is stepped against the NTP server the node was given');
}
{
    my $r = run_setupntp(hwclock => 1);
    like($r->{calls}, qr/^chronyd .*pool pool\.ntp\.org iburst/m,
        'a node given no NTP server falls back to the public pool');
}

# --- the packaging must supply a daemon that can serve time ----------------
# These are manifest contents, not behaviour: there is nothing to execute.
sub slurp { my $p = shift; open my $h, '<', "$repo/$p" or return undef; local $/; <$h> }

my $ctrl = slurp('xCAT/debian/control');
SKIP: {
    skip 'debian/control not found', 2 unless defined $ctrl;
    like($ctrl, qr/^Depends:.*\bchrony \| ntp\b/m,
        'the xcat debian package depends on a server-capable NTP daemon');
    like($ctrl, qr/^Recommends:.*\butil-linux-extra\b/m,
        'and recommends the package that carries hwclock on noble and later');
}

my $spec = slurp('xCAT/xCAT.spec');
SKIP: {
    skip 'xCAT.spec not found', 1 unless defined $spec;
    like($spec, qr/^Requires:\s*\(chrony or ntp\)/m,
        'the xCAT rpm requires a server-capable NTP daemon');
}

done_testing();
