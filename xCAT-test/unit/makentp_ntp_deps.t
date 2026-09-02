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
my ($args)    = $source =~ /^(# Handle command line arguments\n.*?)^if \[ "\$\{#NTP_SERVERS\[@\]\}"/ms;
my ($select)  = $source =~ /^(# The requested backend is a preference.*?)^if \[ -n "\$\{USE_NTPD\}"/ms;
my ($body)    = $source =~ /^(check_exec_or_exit cp cat logger grep\n.*?)^CHRONY_CONF=/ms;
BAIL_OUT('could not take the helper functions from setupntp')          unless $helpers;
BAIL_OUT('could not take the daemon setup section from setupntp')      unless $body;
BAIL_OUT('could not take the argument parsing from setupntp')          unless $args;
BAIL_OUT('could not take the backend selection from setupntp')         unless $select;

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

# systemd-timesyncd used to be checked here, over $body -- the section from
# `check_exec_or_exit cp cat logger grep` onwards, which only the chrony path reaches. The
# stop/disable has moved above the ntpd hand-off so it runs on both paths, which puts it outside
# this window; setupntp_timesyncd_both_backends.t drives both paths and asserts it there.

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

# --- the backend the management node chose must reach the node ------------
# makentp selects the daemon from site.ntpbackend through xCAT::NTP::Backend and passes it here,
# so a cluster told to use ntpd does not get chrony on every node that happens to have it.
foreach my $case (
    # argv                          chronyd present?   expected daemon
    [ '--backend ntpd  pool.ntp.org', 'nothing', 'ntpd',   'ntpd is honoured even where chronyd is installed' ],
    [ '--backend chrony pool.ntp.org','nothing', 'chrony', 'chrony is honoured' ],
    [ 'pool.ntp.org',                 'nothing', 'chrony', 'with no backend given the probe still picks chrony' ],
    [ 'pool.ntp.org',                 'chronyd', 'ntpd',   'with no backend given and no chronyd it falls back' ],
    [ '--backend chrony pool.ntp.org','chronyd', 'ntpd',   'chrony requested but absent falls back rather than failing' ],
    [ '--use-ntpd pool.ntp.org',      'nothing', 'ntpd',   'the legacy --use-ntpd flag still forces ntpd' ],
) {
    my ($argv, $missing, $want, $name) = @$case;
    my $root = File::Temp::tempdir(CLEANUP => 1);
    my $prelude = "logger() { printf '%s\\n' \"\$*\" >>\"$root/log\"; return 0; }\n"
        . "check_executes() { for c in \"\$@\"; do [ \"\$c\" = \"$missing\" ] && return 1; done; return 0; }\n"
        . "log_label=xcat\nset -- $argv\n";
    my $out = `bash -c 'exec 2>/dev/null; $prelude$args$select
printf "USE_NTPD=%s\\n" "\${USE_NTPD:-}"' 2>/dev/null`;
    my $got = ($out =~ /USE_NTPD=yes/) ? 'ntpd' : 'chrony';
    is($got, $want, $name);
}

done_testing();
