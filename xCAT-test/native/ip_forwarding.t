#!/usr/bin/env perl
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP;
use Test::More;

plan skip_all => 'requires Linux root with mount and network namespaces'
    unless $^O eq 'linux' && $> == 0;
plan skip_all => 'mount and network namespaces unavailable'
    if system('unshare -mn -- true >/dev/null 2>&1');
plan skip_all => 'requires native sysctl, grep and sed'
    if system('command -v sysctl grep sed >/dev/null');
my $source = $ENV{XCAT_FORWARD_SOURCE_ROOT} || abs_path("$FindBin::Bin/../..");
my $tmp = tempdir(DIR => '/var/tmp', CLEANUP => !$ENV{XCAT_FORWARD_KEEP});
diag("fixtures: $tmp") if $ENV{XCAT_FORWARD_KEEP};
make_path("$tmp/bin");

sub write_file {
    my ($path, $data) = @_;
    open(my $f, '>', $path) or die "$path: $!";
    print {$f} $data;
    close($f) or die "$path: $!";
}
sub read_file {
    my ($path) = @_;
    open(my $f, '<', $path) or die "$path: $!";
    local $/;
    return <$f> // '';
}
my $host_config = read_file('/etc/sysctl.conf');
my $host_forwarding = read_file('/proc/sys/net/ipv4/ip_forward');
my $host_mount = readlink('/proc/self/ns/mnt');
my $host_net = readlink('/proc/self/ns/net');
my $sysctl = `command -v sysctl`; chomp $sysctl;

write_file("$tmp/bin/no", <<'SH');
#!/bin/sh
printf '%s\n' "$*" >> "$XCAT_FORWARD_FIXTURE/no.log"
exit "${XCAT_FORWARD_AIX_RC:-0}"
SH
write_file("$tmp/namespace", <<'SH');
#!/bin/bash
set -eu
[ "$(readlink /proc/self/ns/mnt)" != "$XCAT_FORWARD_HOST_MOUNT" ]
[ "$(readlink /proc/self/ns/net)" != "$XCAT_FORWARD_HOST_NET" ]
mount --make-rprivate /
mount --bind "$XCAT_FORWARD_FIXTURE/etc" /etc
"$XCAT_FORWARD_SYSCTL" -qw net.ipv4.ip_forward="$XCAT_FORWARD_INITIAL"
exec /usr/bin/perl "$XCAT_FORWARD_RUNNER"
SH
write_file("$tmp/call-helper.pl", <<'CHILD');
use strict;
use warnings;
use lib "$ENV{XCAT_FORWARD_SOURCE_ROOT}/perl-xCAT";
use xCAT::Utils;
use xCAT::NetworkUtils;
use JSON::PP;
my $rc;
if ($ENV{XCAT_FORWARD_AIX}) {
    no warnings 'redefine';
    local *xCAT::Utils::isLinux = sub { 0 };
    $rc = xCAT::NetworkUtils->setup_ip_forwarding($ENV{XCAT_FORWARD_ENABLE});
} else {
    $rc = xCAT::NetworkUtils->setup_ip_forwarding($ENV{XCAT_FORWARD_ENABLE});
}
open(my $f, '<', '/proc/sys/net/ipv4/ip_forward') or die $!;
my $current = <$f>; close($f); chomp $current;
print JSON::PP->new->encode({rc => $rc, forwarding => $current,
    mount_namespace => scalar(readlink('/proc/self/ns/mnt')),
    network_namespace => scalar(readlink('/proc/self/ns/net'))}), "\n";
CHILD
chmod 0755, "$tmp/namespace", "$tmp/bin/no";

my @cases = (
    ['legacy spaced enable', "net.ipv4.ip_forward = 0\n", 1],
    ['legacy spaced disable', "net.ipv4.ip_forward = 1\n", 0],
    ['legacy commented compact', "#net.ipv4.ip_forward=0\n", 1],
    ['legacy commented spaced', "#net.ipv4.ip_forward = 1\n", 0],
    ['absent assignment', "# Other settings remain\n", 1,
        "# Other settings remain\nnet.ipv4.ip_forward = 1\n"],
    ['already enabled', "net.ipv4.ip_forward = 1\n", 1],
    ['compact enable', "net.ipv4.ip_forward=0\n", 1],
    ['compact disable', "net.ipv4.ip_forward=1\n", 0],
    ['space before equals', "net.ipv4.ip_forward =0\n", 1],
    ['space after equals', "net.ipv4.ip_forward= 0\n", 1],
    ['tab separators', "net.ipv4.ip_forward\t=\t0\n", 1],
    ['indented assignment', " \tnet.ipv4.ip_forward=0\n", 1],
    ['trailing comment', "net.ipv4.ip_forward=0 # Previous setting\n", 1],
    ['multiple active assignments', "net.ipv4.ip_forward=0\nnet.ipv4.ip_forward = 0\n", 1,
        "net.ipv4.ip_forward = 1\nnet.ipv4.ip_forward = 1\n"],
    ['neighboring keys retained', "net.ipv4.ip_forward=0\nnet.ipv4.ip_forward_use_pmtu=1\nnet.ipv6.conf.all.forwarding=0\n# Keep this comment\n", 1,
        "net.ipv4.ip_forward = 1\nnet.ipv4.ip_forward_use_pmtu=1\nnet.ipv6.conf.all.forwarding=0\n# Keep this comment\n"],
    ['AIX enable', "# Linux fixture untouched\n", 1, "# Linux fixture untouched\n", 1, 0],
    ['AIX disable', "# Linux fixture untouched\n", 0, "# Linux fixture untouched\n", 1, 0],
    ['AIX existing return contract', "# Linux fixture untouched\n", 1, "# Linux fixture untouched\n", 1, 37],
);
my $number = 0;
for my $case (@cases) {
    my ($name, $input, $enable, $expected, $aix, $aix_status) = @$case;
    $expected //= "net.ipv4.ip_forward = $enable\n";
    my $fixture = "$tmp/case-" . ++$number;
    make_path("$fixture/etc/sysctl.d");
    write_file("$fixture/etc/sysctl.conf", $input);
    symlink '../sysctl.conf', "$fixture/etc/sysctl.d/99-sysctl.conf" or die $!;
    for my $file (qw(ld.so.cache os-release openEuler-release)) {
        copy("/etc/$file", "$fixture/etc/$file") or die $! if -f "/etc/$file";
    }
    subtest $name => sub {
        local %ENV = (%ENV, XCAT_FORWARD_SOURCE_ROOT => $source,
            XCAT_FORWARD_FIXTURE => $fixture, XCAT_FORWARD_RUNNER => "$tmp/call-helper.pl",
            XCAT_FORWARD_HOST_MOUNT => $host_mount, XCAT_FORWARD_HOST_NET => $host_net,
            XCAT_FORWARD_SYSCTL => $sysctl, XCAT_FORWARD_INITIAL => 1 - $enable,
            XCAT_FORWARD_ENABLE => $enable, XCAT_FORWARD_AIX => $aix || 0,
            XCAT_FORWARD_AIX_RC => $aix_status || 0,
            PATH => "$tmp/bin:/usr/sbin:/usr/bin:/sbin:/bin", LC_ALL => 'C');
        for my $pass (1, 2) {
            my $pid = fork(); die $! unless defined $pid;
            if (!$pid) {
                open(STDIN, '<', '/dev/null') or die $!;
                open(STDOUT, '>', "$fixture/result-$pass.json") or die $!;
                open(STDERR, '>', "$fixture/stderr-$pass.log") or die $!;
                exec('unshare', '-mn', '--', "$tmp/namespace") or die $!;
            }
            waitpid($pid, 0);
            my $status = (($? & 127) ? 128 + ($? & 127) : $? >> 8);
            is($status, 0, "pass $pass invokes the full production module in isolation");
            if ($status) { diag(read_file("$fixture/stderr-$pass.log")); next; }
            my $result = decode_json(read_file("$fixture/result-$pass.json"));
            is($result->{rc}, 0, "pass $pass preserves the helper return contract");
            isnt($result->{mount_namespace}, $host_mount, "pass $pass uses a separate mount namespace");
            isnt($result->{network_namespace}, $host_net, "pass $pass uses a separate network namespace");
            is(read_file("$fixture/etc/sysctl.conf"), $expected, "pass $pass persists only the expected assignment");
            is(read_file("$fixture/etc/sysctl.d/99-sysctl.conf"), $expected, "pass $pass retains the sysctl.d alias");
            is(0 + $result->{forwarding}, $aix ? 1 - $enable : $enable,
                "pass $pass has the expected real kernel forwarding state");
        }
        if ($aix) {
            is(read_file("$fixture/no.log"), "-o ipforwarding=$enable\n" x 2,
                'AIX keeps its existing native command and arguments');
        } else {
            ok(!-e "$fixture/no.log", 'Linux never invokes the AIX command');
        }
    };
}
is(read_file('/etc/sysctl.conf'), $host_config, 'host sysctl configuration is unchanged');
is(read_file('/proc/sys/net/ipv4/ip_forward'), $host_forwarding, 'host forwarding state is unchanged');
is(readlink('/proc/self/ns/mnt'), $host_mount, 'test process retained its original mount namespace');
is(readlink('/proc/self/ns/net'), $host_net, 'test process retained its original network namespace');
done_testing();
