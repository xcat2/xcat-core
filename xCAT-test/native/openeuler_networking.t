#!/usr/bin/env perl
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

plan skip_all => 'requires Linux root with mount and network namespaces'
  unless $^O eq 'linux' && $> == 0;
my $probe = system('unshare -mn -- true >/dev/null 2>&1');
plan skip_all => 'mount and network namespaces are unavailable' if $probe;
plan skip_all => 'requires an existing /install mount point' unless -d '/install';

my $source = $ENV{XCAT_NETWORK_SOURCE_ROOT} || abs_path("$FindBin::Bin/../..");
my $tmp = tempdir(CLEANUP => 1);
my $bin = "$tmp/bin";
make_path($bin);

sub write_file {
    my ($path, $text) = @_;
    open(my $fh, '>', $path) or die "$path: $!";
    print {$fh} $text;
    close($fh) or die "$path: $!";
}

sub read_file {
    my ($path) = @_;
    return '' unless -f $path;
    open(my $fh, '<', $path) or die "$path: $!";
    local $/;
    return <$fh> // '';
}

write_file("$bin/double", <<'SH');
#!/bin/bash
command=${0##*/}
printf '%s' "$command" >> "$XCAT_NET_LOG"
printf '\t<%s>' "$@" >> "$XCAT_NET_LOG"
printf '\n' >> "$XCAT_NET_LOG"
case "$command" in
    systemctl)
        case "$*" in
            'show --property=ActiveState NetworkManager') echo ActiveState=active ;;
            *) echo ActiveState=inactive ;;
        esac ;;
    ip)
        case "$*" in
            *'route show '*|*'route show')
                [ -n "$XCAT_NET_ROUTE" ] && echo "$XCAT_NET_ROUTE"
                ;;
            *'route add '*|*'route delete '*|*'route replace '*) exit "${XCAT_NET_IP_RC:-0}" ;;
            'addr show') printf '2: eth8: <BROADCAST> state UP\n3: eth9: <BROADCAST> state UP\n' ;;
            'link show '*) echo "2: ${*:3}: <BROADCAST,UP> state UP" ;;
        esac ;;
    nmcli)
        case "$*" in
            '-g GENERAL.CONNECTION device show '*)
                [ "$XCAT_NET_NO_CONNECTION" = 1 ] || echo 'storage fabric'
                ;;
            '-g NAME,DEVICE connection show --active') ;;
            'connection show eth8') exit 1 ;;
            '-g connection.uuid connection show '*) echo 01234567-89ab-cdef-0123-456789abcdef ;;
            '-t -f UUID,FILENAME connection show')
                echo "01234567-89ab-cdef-0123-456789abcdef:${XCAT_NET_FILENAME:-/etc/sysconfig/network-scripts/ifcfg-xcat-bond-bond8}"
                ;;
            '-g ipv4.routes connection show '*) echo '198.51.100.0/24 192.0.2.9,203.0.113.0/24 192.0.2.8' ;;
            '-g GENERAL.STATE device show '*) echo '100 (connected)' ;;
            '-g NAME connection show') ;;
            'dev show '*) echo 'GENERAL.CONNECTION: --' ;;
            'con show '*) echo 'GENERAL.STATE: activated' ;;
            'connection modify '*) exit "${XCAT_NET_NM_RC:-0}" ;;
            'device reapply '*) exit "${XCAT_NET_REAPPLY_RC:-0}" ;;
        esac ;;
    route) exit 0 ;;
    sleep) exit 0 ;;
    *) exit 0 ;;
esac
exit 0
SH
chmod 0755, "$bin/double";
for my $command (qw(ip nmcli systemctl logger route ifup ifdown modprobe sleep)) {
    symlink 'double', "$bin/$command" or die $!;
}

write_file("$tmp/namespace", <<'SH');
#!/bin/bash
set -e
mount --make-rprivate /
mount --bind "$XCAT_NET_FIXTURE/etc" /etc
mount --bind "$XCAT_NET_FIXTURE/run" /run
mount --bind "$XCAT_NET_FIXTURE/install" /install
exec "$@"
SH
chmod 0755, "$tmp/namespace";

write_file("$tmp/local-route", <<'PERL');
use strict;
use warnings;
use JSON::PP;
require "$ENV{XCAT_NETWORK_SOURCE_ROOT}/xCAT-server/lib/xcat/plugins/route.pm";
my $op = shift;
my @responses;
my $callback = sub { push @responses, $_[0] };
my $rc = $op eq 'add'
  ? xCAT_plugin::route::set_route($callback, @ARGV)
  : xCAT_plugin::route::delete_route($callback, @ARGV);
print JSON::PP->new->encode(\@responses), "\n";
exit $rc;
PERL

my $case_number = 0;
sub run_case {
    my (%case) = @_;
    my $fixture = "$tmp/case-" . ++$case_number;
    make_path(map { "$fixture/$_" } qw(etc/sysconfig/network-scripts etc/sysconfig/network
        etc/network/interfaces.d etc/modprobe.d etc/NetworkManager/system-connections
        etc/systemd/system run install/postscripts db));
    write_file("$fixture/etc/os-release", $case{release} // "ID=openEuler\nVERSION_ID=24.03\nNAME=openEuler\n");
    write_file("$fixture/etc/network/interfaces", "auto eth8\niface eth8 inet static\n");
    write_file("$fixture/etc/systemd/system/NetworkManager.service", '');
    write_file("$fixture/etc/$case{marker}", $case{marker_text} // '') if $case{marker};
    for my $file (qw(routeop xcatlib.sh)) {
        symlink "$source/xCAT/postscripts/$file", "$fixture/install/postscripts/$file" or die $!;
    }
    local %ENV = (%ENV,
        PATH => "$bin:$source/xCAT/postscripts:/usr/sbin:/usr/bin:/sbin:/bin",
        XCAT_NET_FIXTURE => $fixture, XCAT_NET_LOG => "$fixture/commands",
        XCAT_NETWORK_SOURCE_ROOT => $source, XCATROOT => "$source/xCAT-server",
        PERL5LIB => "$source/perl-xCAT:$source/xCAT-server/lib/perl",
        XCATCFG => "SQLite:$fixture/db", OSVER => '',
        INSTALLNIC => 'eth0', UPDATENODE => 1, NODE => 'network-fixture',
        NETWORKS_LINES => 1,
        NETWORKS_LINE1 => 'netname=storage||net=192.0.2.0||mask=255.255.255.0||mtu=||',
        NICIPS => 'bond8!192.0.2.44', NICNETWORKS => 'bond8!storage',
        XCAT_NET_ROUTE => '', XCAT_NET_NO_CONNECTION => '', XCAT_NET_NM_RC => 0,
        XCAT_NET_IP_RC => 0, XCAT_NET_REAPPLY_RC => 0, XCAT_NET_FILENAME => '',
        %{ $case{env} // {} });
    my @command = $case{local_route}
      ? ('perl', "$tmp/local-route", @{ $case{args} })
      : ('bash', "$source/xCAT/postscripts/$case{script}", @{ $case{args} // [] });
    my $pid = fork();
    die $! unless defined $pid;
    if (!$pid) {
        open(STDOUT, '>', "$fixture/output") or die $!;
        open(STDERR, '>&', \*STDOUT) or die $!;
        exec('unshare', '-mn', '--', "$tmp/namespace", @command);
        die $!;
    }
    waitpid($pid, 0);
    return ((($? & 127) ? 128 + ($? & 127) : $? >> 8), read_file("$fixture/commands"), read_file("$fixture/output"), $fixture);
}

for my $case (
    ['add', '198.51.100.0', '255.255.255.0', '192.0.2.1', '+ipv4.routes', '198.51.100.0/24 192.0.2.1'],
    ['delete', '198.51.100.0', '24', '192.0.2.1', '-ipv4.routes', '198.51.100.0/24 192.0.2.1'],
    ['replace', '198.51.100.0', '24', '192.0.2.1', '+ipv4.routes', '198.51.100.0/24 192.0.2.1'],
    ['add', '2001:db8:8::', '64', 'fe80::1', '+ipv6.routes', '2001:db8:8::/64 fe80::1'],
    ['delete', '2001:db8:8::', '64', 'fe80::1', '-ipv6.routes', '2001:db8:8::/64 fe80::1'],
    ['replace', 'default', '0', '192.0.2.1', 'ipv4.gateway', '192.0.2.1'],
    ['delete', 'default', '0', '192.0.2.1', 'ipv4.gateway', ''],
) {
    my ($op, $net, $mask, $gw, $property, $value) = @$case;
    my ($rc, $log, $output, $fixture) = run_case(script => 'routeop', args => [$op, $net, $mask, $gw, 'eth8']);
    is($rc, 0, "$op $net succeeds on native openEuler") or diag $output;
    like($log, qr/connection>\t<modify>\t<storage fabric>\t<\Q$property\E>\t<\Q$value\E>/,
        "$op $net persists through the resolved NM connection");
    like($log, qr/nmcli\t<device>\t<reapply>\t<eth8>/, "$op $net applies the active NM route state");
    unlike($log, qr/^ip\t<(?:-6>\t<)?route>\t<(?:add|delete|replace)>/m,
        "$op $net has one runtime route owner");
    ok(!-e "$fixture/etc/sysconfig/static-routes" && !-e "$fixture/etc/sysconfig/static-routes-ipv6",
        "$op $net does not create legacy route files");
}

for my $failure (
    ['no connection', {XCAT_NET_NO_CONNECTION => 1}],
    ['NM rejects persistence', {XCAT_NET_NM_RC => 42}],
    ['active NM connection rejects reapply', {XCAT_NET_REAPPLY_RC => 42}],
) {
    my ($rc, $log, $output) = run_case(script => 'routeop', args => ['add', '198.51.100.0', '24', '192.0.2.1', 'eth8'], env => $failure->[1]);
    isnt($rc, 0, "native route failure is returned: $failure->[0]") or diag $output;
}

for my $case (
    ['EL8', 'rhels8', 'redhat-release', 'Red Hat Enterprise Linux release 8.10', 'etc/sysconfig/static-routes'],
    ['SLES', 'sles15', 'SuSE-release', 'SUSE Linux Enterprise Server 15', 'etc/sysconfig/network/routes'],
    ['Debian', 'debian12', 'debian_version', '12', 'etc/network/interfaces.d/eth8'],
) {
    my ($name, $osver, $marker, $marker_text, $path) = @$case;
    my ($rc, $log, $output, $fixture) = run_case(script => 'routeop', args => ['add', '198.51.100.0', '24', '192.0.2.1', 'eth8'],
        release => "ID=test\n", marker => $marker, marker_text => $marker_text, env => {OSVER => $osver});
    is($rc, 0, "$name retains route success") or diag $output;
    like(read_file("$fixture/$path"), qr/198\.51\.100\.0/, "$name retains its existing persistence owner");
    unlike($log, qr/nmcli\t<connection>\t<modify>/, "$name does not switch to NM persistence");
}

{
    my ($rc, $log, $output) = run_case(script => 'routeop', args => ['add', '198.51.100.0', '24', '192.0.2.1', 'eth8'],
        release => "ID=rhel\nVERSION_ID=9.6\n", marker => 'redhat-release', env => {OSVER => 'rhels9'});
    is($rc, 0, 'EL9 retains route success') or diag $output;
    like($log, qr/<\+ipv4.routes>/, 'EL9 retains NM persistence');
}

for my $op (qw(add delete)) {
    my ($rc, $log, $output) = run_case(local_route => 1, args => [$op, '198.51.100.0', '24', '192.0.2.1', 'gateway', 'eth8']);
    is($rc, 0, "local $op route succeeds through the real plugin") or diag $output;
    like($log, qr/nmcli\t<connection>\t<modify>/, "local $op route reaches routeop NM persistence");
}
{
    my ($rc, $log, $output) = run_case(local_route => 1, args => ['add', '198.51.100.0', '24', '192.0.2.1', 'gateway', 'eth8'], env => {XCAT_NET_NM_RC => 42});
    isnt($rc, 0, 'local plugin returns routeop failure');
    like($output, qr/routeop failed with exit code/, 'local plugin reports routeop failure through its callback');
}

for my $osver ('openeuler20.03', 'openeuler22.03', 'openeuler24.03', '') {
    my ($rc, $log, $output) = run_case(script => 'configbond', args => ['bond8', 'eth8@eth9', 'mode=1@miimon=100'], env => {OSVER => $osver});
    is($rc, 0, "native configbond accepts OSVER '$osver'") or diag $output;
    like($log, qr/<type>\t<bond>.*<bond.options>\t<mode=1,miimon=100>.*<ipv4.addresses>\t<192.0.2.44\/24>/,
        "native configbond preserves address and explicit options for '$osver'");
    unlike($log, qr/^if(?:up|down)\t/m, 'native bond avoids legacy activation');
}

for my $storage ('ifcfg', 'keyfile') {
    my $filename = $storage eq 'keyfile'
      ? '/etc/NetworkManager/system-connections/xcat-bond-bond8.nmconnection'
      : '/etc/sysconfig/network-scripts/ifcfg-xcat-bond-bond8';
    my ($rc, $log, $output, $fixture) = run_case(script => 'confignetwork', env => {
        NICDEVICES => 'bond8!eth8|eth9', NICTYPES => 'bond8!bond,eth8!ethernet,eth9!ethernet',
        NICEXTRAPARAMS => 'bond8!connection.autoconnect-priority=17', XCAT_NET_FILENAME => $filename,
    });
    is($rc, 0, "confignetwork configures native $storage bond") or diag $output;
    like($log, qr/<type>\t<bond>/, 'confignetwork reaches existing NM bond creation');
    like($log, qr/<bond.options>\t<mode=802.3ad,miimon=100>/,
        'confignetwork retains the existing Ethernet bond defaults');
    if ($storage eq 'keyfile') {
        like($log, qr/<con>\t<modify>\t<xcat-bond-bond8>\t<connection.autoconnect-priority>\t<17>/,
            'keyfile extras use NM properties');
        ok(!-e "$fixture/etc/sysconfig/network-scripts/ifcfg-xcat-bond-bond8", 'keyfile extras do not create an ifcfg file');
    } else {
        like(read_file("$fixture$filename"), qr/connection.autoconnect-priority=17/,
            'ifcfg extras retain existing file persistence');
    }
}

for my $storage ('ifcfg', 'keyfile') {
    my $filename = $storage eq 'keyfile'
      ? '/etc/NetworkManager/system-connections/xcat-eth8.nmconnection'
      : '/etc/sysconfig/network-scripts/ifcfg-xcat-eth8';
    my ($rc, $log, $output, $fixture) = run_case(script => 'confignetwork', env => {
        NICDEVICES => '', NICTYPES => 'eth8!ethernet', NICIPS => 'eth8!192.0.2.44',
        NICNETWORKS => 'eth8!storage', NICEXTRAPARAMS => 'eth8!connection.autoconnect-priority=17',
        XCAT_NET_FILENAME => $filename,
    });
    is($rc, 0, "confignetwork configures native $storage Ethernet") or diag $output;
    if ($storage eq 'keyfile') {
        like($log, qr/<con>\t<modify>\t<xcat-eth8>\t<connection.autoconnect-priority>\t<17>/,
            'configeth applies keyfile extras as NM properties');
    } else {
        like(read_file("$fixture$filename"), qr/connection.autoconnect-priority=17/,
            'configeth preserves ifcfg extras');
    }
}

done_testing();
