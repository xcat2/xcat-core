#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::Lifecycle;
use XCAT::Test::RPM;

plan skip_all => 'Run as an ordinary user on a native Debian or RPM distribution'
    unless $^O eq 'linux' && $< != 0 && (-f '/etc/debian_version' || -f '/etc/redhat-release');
my $debian = -f '/etc/debian_version';
my $first = $debian ? XCAT::Test::Lifecycle::build_deb('xCAT') : XCAT::Test::RPM->build('xCAT', 1);
my $second = $debian ? $first : XCAT::Test::RPM->build('xCAT', 2);
my $warning = "WARNING: mknb did not complete, so the Genesis netboot image may be missing or out of date.\n" .
    "         See /var/log/xcat/upgrade.log, then rerun 'mknb <arch>' once the cause is resolved.\n";

sub install_package {
    my ($root, $package, @options) = @_;
    return $debian ? $root->install_deb($package) : $root->install($package, @options);
}

for my $case (qw(fresh success warning stderr-warning historic-warning command-failure warning-failure temporary-failure excluded-postscripts)) {
    subtest $case => sub {
        my $root = $debian ? XCAT::Test::Lifecycle->new : XCAT::Test::RPM->new;
        $root->write('/opt/xcat/share/xcat/scripts/xHRM', '');
        $root->record_command('/etc/init.d/apache2');
        $root->write('/opt/xcat/sbin/xcatconfig', <<'SHELL', 0755);
#!/bin/sh
printf '%s\n' "$*" >> /config-calls
if [ -f /command-output ]; then cat /command-output; fi
if [ -f /command-error ]; then cat /command-error >&2; fi
if [ -f /command-status ]; then exit "$(cat /command-status)"; fi
SHELL
        my @options;
        if ($case eq 'excluded-postscripts') {
            $root->write('/install/postscripts/.keep', '');
            if ($debian) {
                $root->write('/etc/dpkg/dpkg.cfg.d/xcat-test', "path-exclude=/install/postscripts/*\n");
            } else {
                @options = ('--excludepath', '/install/postscripts');
            }
        }
        if ($case ne 'fresh') {
            my ($status, $out, $err) = install_package($root, $first, @options);
            is($status, 0, 'install the prior package') or diag "$out$err";
            unlike($err, qr/scriptlet failed|scriptlet failure/i, 'prior package scriptlets complete');
        }
        $root->write('/config-calls', '');
        my $prior = $case eq 'historic-warning' ? "old command returned error code\n" : "earlier log\n";
        $root->write('/var/log/xcat/upgrade.log', $prior);
        $root->write('/test-bin/date', "#!/bin/sh\nprintf 'upgrade timestamp\\n'\n", 0755);
        my $output = $case eq 'warning' || $case eq 'warning-failure' ? "command returned error code 17\n" : "current output\n";
        my $error = $case eq 'stderr-warning' ? "command returned error code 17\n" : "current stderr\n";
        $root->write('/command-output', $output);
        $root->write('/command-error', $error);
        my $failed = $case eq 'command-failure' || $case eq 'warning-failure';
        $root->write('/command-status', "17\n") if $failed;
        if ($case eq 'temporary-failure') {
            $root->write('/test-bin/mktemp', <<'SH', oct('755'));
#!/bin/sh
case "$1" in
    /tmp/xcat-upgrade.*) echo 'temporary allocation failed' >&2; exit 19 ;;
esac
exec /usr/bin/mktemp "$@"
SH
        }
        for my $service (qw(installservice udpservice mainservice)) {
            $root->write("/tmp/xcat/$service.pid", "$service pid\n");
        }
        my ($status, $out, $err) = install_package($root, $second, @options);
        is(-e $root->path('/install/postscripts/configinterface') ? 1 : 0,
            $case eq 'excluded-postscripts' ? 0 : 1, 'node postscript payload follows the exclusion policy');
        my $stopped = $debian && ($failed || $case eq 'temporary-failure');
        is($status == 0 ? 1 : 0, $stopped ? 0 : 1, 'transaction retains its failure policy') or diag "$out$err";
        unlike($err, qr/scriptlet failed|scriptlet failure/i, 'RPM scriptlet finishes') unless $debian;
        is($root->read('/config-calls'), $case eq 'temporary-failure' ? '' : $case eq 'fresh' ? "-i\n" : "-u -V\n",
            'package invokes the correct configuration action');
        my $expected_log = $prior;
        if ($case ne 'fresh') {
            $expected_log .= "upgrade timestamp\n";
            $expected_log .= $output . $error unless $stopped || $case eq 'temporary-failure';
        }
        is($root->read('/var/log/xcat/upgrade.log'), $expected_log, 'log appends only the output reached by this transaction');
        my $warnings = join '', $out =~ /^(WARNING: mknb[^\n]*\n         See [^\n]*\n)/mg;
        my $warned = !$stopped && ($case eq 'warning' || $case eq 'warning-failure' || $case eq 'stderr-warning');
        is($warnings, $warned ? $warning : '', 'only the current captured failure triggers the warning');
        unlike($out, qr/^current (?:output|stderr)$/m, 'upgrade output stays in the log') unless $case eq 'fresh';
        my @temporary = glob $root->path('/tmp/xcat-upgrade.*');
        is(scalar @temporary, $debian && $failed ? 1 : 0, 'temporary capture retains caller cleanup policy');
        is($root->read('/tmp/' . (split m{/}, $temporary[0])[-1]), $output . $error,
            'failed Debian command retains captured diagnostics') if @temporary;
        if ($debian) {
            is(-e $root->path('/tmp/xCAT_upgrade.tmp') ? 1 : 0, $stopped ? 1 : 0, 'upgrade marker follows transaction completion');
        }
        for my $service (qw(installservice udpservice mainservice)) {
            my $destination = $case eq 'fresh' ? '/tmp/xcat' : '/var/run/xcat';
            is($root->read("$destination/$service.pid"), "$service pid\n", 'PID relocation remains in the caller');
        }
    };
}

done_testing;
