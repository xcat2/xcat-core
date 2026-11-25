#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use File::Path qw(make_path);
use XCAT::Test::Lifecycle;

plan skip_all => 'Run as an ordinary user on Debian or Ubuntu'
    unless $^O eq 'linux' && $< != 0 && -f '/etc/debian_version';
my %packages = map { $_ => XCAT::Test::Lifecycle::build_deb($_) }
    qw(perl-xCAT xCAT-server xCATsn);

sub succeeds {
    my ($label, @result) = @_;
    is($result[0], 0, $label) or diag "$result[1]$result[2]";
}

for my $event (qw(remove upgrade)) {
    subtest "Debian $event UFTP listener" => sub {
        my $root = XCAT::Test::Lifecycle->new;
        $root->{live} = 1;
        $root->write('/calls', '');
        $root->record_command('/test-bin/systemctl');
        $root->record_command('/opt/xcat/share/xcat/scripts/xcatd-init-compat');
        succeeds("run the built Debian $event script",
            $root->deb_script($packages{'xCAT-server'}, 'prerm', $event, '2.19.1'));
        if ($event eq 'remove') {
            like($root->read('/calls'), qr/^systemctl <stop> <xcatd\.service>$/m,
                'removal stops xcatd');
            like($root->read('/calls'), qr/^systemctl <disable> <--now> <xcat-uftp-listener\.service>$/m,
                'removal stops and disables the UFTP listener');
        } else {
            unlike($root->read('/calls'), qr/xcat-uftp-listener/,
                'an upgrade leaves the UFTP listener alone');
        }
    };
}

sub record_root_stat {
    my ($root, $deny_pid1) = @_;
    $root->write('/stat-calls', '');
    $root->write('/deny-pid1', '') if $deny_pid1;
    $root->write('/test-bin/stat', <<'SH', oct('0755'));
#!/bin/sh
case "$3" in
    /|/proc/1/root/.) printf '%s\n' "$*" >> /stat-calls ;;
esac
if [ "$3" = /proc/1/root/. ] && [ -f /deny-pid1 ]; then
    echo 'PID1 root is unavailable' >&2
    exit 71
fi
exec /usr/bin/stat "$@"
SH
}

for my $live (0, 1) {
    for my $event (qw(upgrade remove purge abort-upgrade)) {
      for my $installed (0, 1) {
        my $root = XCAT::Test::Lifecycle->new;
        $root->{live} = $live;
        $root->record_command('/opt/xcat/sbin/restartxcatd') if $installed;
        $root->write('/calls', '');
        record_root_stat($root, 0);
        succeeds("Debian perl-xCAT $event (proc=$live)",
            $root->deb_script($packages{'perl-xCAT'}, 'postrm', $event, '2.20.0'));
        is($root->read('/calls'), $live && $installed && $event eq 'upgrade' ? "restartxcatd <-r>\n" : '',
            'only an upgrade with proc and an installed helper requests a fast reload');
        is($root->read('/stat-calls'), $live && $installed && $event eq 'upgrade'
            ? "-c %d:%i /\n-c %d:%i /proc/1/root/.\n" : '',
            'the upgrade and executable guards precede the proc and root probes');
      }
    }
}

for my $mode (qw(without-proc live proc-chroot systemd-chroot pid1-unavailable)) {
    subtest $mode => sub {
        my $root = XCAT::Test::Lifecycle->new;
        $root->{live} = $mode ne 'without-proc';
        $root->{chroot} = $mode =~ /chroot/ ? 1 : 0;
        my $active = $mode eq 'live';
        record_root_stat($root, $mode eq 'pid1-unavailable');
        {
            local $root->{deb} = $packages{'xCAT-server'};
            succeeds('unpack the server payload', $root->run('dpkg-deb', '-x', '/package.deb', '/unpacked'));
        }
        make_path(map { $root->path($_) } qw(/opt/xcat/lib /opt/xcat/sbin /opt/xcat/share/xcat /etc/apache2/conf-enabled));
        succeeds('stage packaged helpers', $root->run('cp', '-a',
            '/unpacked/opt/xcat/share/xcat/scripts', '/opt/xcat/share/xcat/'));
        succeeds('stage the packaged fast-restart command', $root->run('cp',
            '/unpacked/opt/xcat/sbin/restartxcatd', '/opt/xcat/sbin/'));
        symlink '/source/perl-xCAT', $root->path('/opt/xcat/lib/perl') or die "link Perl modules: $!";
        $root->write('/etc/os-release', $mode eq 'systemd-chroot'
            ? "ID=ubuntu\nVERSION_ID=24.04\n" : "ID=ubuntu\nVERSION_ID=14.04\n");
        make_path($root->path('/run/systemd/system')) if $mode eq 'systemd-chroot';
        succeeds('install the packaged legacy init script', $root->run('cp',
            '/opt/xcat/share/xcat/scripts/xcatd', '/etc/init.d/xcatd'));
        if ($mode eq 'systemd-chroot') {
            for my $service (qw(xcatd xcat-uftp-listener)) {
                succeeds("stage the $service unit", $root->run('cp',
                    "/unpacked/lib/systemd/system/$service.service", '/usr/lib/systemd/system/'));
                succeeds("enable $service in the image", $root->run('systemctl', 'enable', "$service.service"));
                ok(-l $root->path("/etc/systemd/system/multi-user.target.wants/$service.service"),
                    "$service starts with an enabled link");
            }
        } else {
            succeeds('register xcatd in the image', $root->run('update-rc.d', 'xcatd', 'defaults'));
            my @enabled = glob $root->path('/etc/rc?.d/S??xcatd');
            ok(@enabled, 'xcatd starts with enabled runlevels');
        }
        $root->write('/etc/profile.d/xcat.sh',
            "export XCATROOT=/opt/xcat\nexport PATH=/opt/xcat/sbin:/usr/sbin:/usr/bin:/sbin:/bin\n");
        unlink $root->path('/usr/sbin/policy-rc.d') or die "unlink policy fixture: $!"
            if -l $root->path('/usr/sbin/policy-rc.d');
        $root->write('/usr/sbin/policy-rc.d', <<'SH', oct('755'));
#!/bin/sh
printf '%s\n' "$*" >> /policy-calls
exit 101
SH
        $root->record_command('/opt/xcat/sbin/xcatd');
        $root->record_command('/etc/init.d/apache2');
        $root->write('/etc/init.d/apache2', $root->read('/etc/init.d/apache2') . <<'SH', oct('755'));
### BEGIN INIT INFO
# Provides: apache2
# Required-Start: $network
# Required-Stop:
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: Apache command boundary
### END INIT INFO
SH
        succeeds('register the Apache dependency', $root->run('update-rc.d', 'apache2', 'defaults'));
        $root->write('/calls', '');
        if ($root->{chroot}) {
            succeeds('proc is mounted inside a different process root', $root->run('/bin/sh', '-c',
                q{test -f /proc/cmdline && test "$(stat -c '%d:%i' /)" != "$(stat -c '%d:%i' /proc/1/root/.)"}));
        }
        if ($mode ne 'systemd-chroot') {
            succeeds('native service policy denies an explicit start',
                $root->run('invoke-rc.d', 'xcatd', 'start'));
            is($root->read('/calls'), '', 'the policy control cannot reach the daemon');
            like($root->read('/policy-calls'), qr/xcatd.*start/, 'the native dispatcher consulted policy');
        }
        my @configure = $root->deb_script($packages{'xCATsn'}, 'postinst', 'configure');
        succeeds('configure the service-node package', @configure);
        unlike($configure[2], qr/PID1 root is unavailable/, 'PID1 stat errors stay suppressed');
        is($root->read('/calls'), $active
            ? "xcatd <-p> </var/run/xcatd.pid>\napache2 <reload>\n" : '',
            'only the live root starts xcatd and reloads Apache');
        $root->write('/calls', '');
        succeeds('upgrade the Perl package through the real fast-restart command',
            $root->deb_script($packages{'perl-xCAT'}, 'postrm', 'upgrade', '2.20.0'));
        is($root->read('/calls'), $active ? "xcatd <-p> </var/run/xcatd.pid>\n" : '',
            'only the live root reaches xcatd through restartxcatd');

        $root->write('/sentinel.pl', <<'PERL');
use strict;
use warnings;
$0 = 'xcatd: lifecycle sentinel';
$SIG{TERM} = sub { open(my $fh, '>', '/stopped') or die $!; print {$fh} "TERM\n"; close($fh); exit 0; };
open(my $pid, '>', '/var/run/xcatd.pid') or die $!;
print {$pid} "$$\n";
close($pid) or die $!;
sleep 1 while 1;
PERL
        local $root->{deb} = $packages{'xCAT-server'};
        succeeds('unpack the server control scripts',
            $root->run('dpkg-deb', '-e', '/package.deb', '/tmp/server-control'));
        succeeds('remove the server while an isolated process is running',
            $root->run('/bin/sh', '-c', <<'SH', 'remove', $active ? 'live' : 'image'));
set -eu
mkdir -p /var/run
perl /sentinel.pl &
daemon=$!
trap 'kill -KILL "$daemon" 2>/dev/null || :; wait "$daemon" 2>/dev/null || :' EXIT
attempt=0
until test -s /var/run/xcatd.pid; do
    attempt=$((attempt + 1))
    test "$attempt" -lt 100 || exit 20
    sleep .05
done
/bin/sh /tmp/server-control/prerm remove
if [ "$1" = live ]; then
    test -f /stopped
    test ! -f /var/run/xcatd.pid
else
    kill -0 "$daemon"
    test ! -f /stopped
    test -f /var/run/xcatd.pid
fi
SH
        is(-e $root->path('/stopped') ? $root->read('/stopped') : '',
            $active ? "TERM\n" : '', 'only live-root removal signals the process');
        if ($mode eq 'systemd-chroot') {
            for my $service (qw(xcatd xcat-uftp-listener)) {
                ok(!-l $root->path("/etc/systemd/system/multi-user.target.wants/$service.service"),
                    "removal disables $service without starting the image");
            }
        } else {
            my @links = glob $root->path('/etc/rc?.d/S??xcatd');
            is_deeply(\@links, [], 'removal still disables offline service registration');
        }
    };
}
done_testing;
