#!/usr/bin/env perl
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

plan skip_all => 'requires Linux root and mount/network namespaces' unless $^O eq 'linux' && $> == 0;
plan skip_all => 'namespaces unavailable' if system('unshare -mn -- true >/dev/null 2>&1');
plan skip_all => 'requires native rsyslogd, logger, ip and ss'
    if system('command -v rsyslogd logger ip ss >/dev/null');
my $source = $ENV{XCAT_SYSLOG_SOURCE_ROOT} || abs_path("$FindBin::Bin/../..");
my $tmp = tempdir(DIR => '/var/tmp', CLEANUP => !$ENV{XCAT_SYSLOG_KEEP});
diag("fixtures: $tmp") if $ENV{XCAT_SYSLOG_KEEP};
make_path("$tmp/bin");
sub write_file {
    my ($path, $contents) = @_;
    open(my $fh, '>', $path) or die "$path: $!";
    print {$fh} $contents;
    close($fh) or die "$path: $!";
}
sub read_file {
    my ($path) = @_;
    return '' unless -f $path;
    open(my $fh, '<', $path) or die "$path: $!";
    local $/;
    return <$fh> // '';
}
for my $name (qw(syslog xcatlib.sh)) {
    copy("$source/xCAT/postscripts/$name", "$tmp/bin/$name") or die $!;
}
write_file("$tmp/bin/systemctl", <<'SH');
#!/bin/bash
printf '%s\n' "$*" >> "$XCAT_SYSLOG_FIXTURE/services.log"
[ "$XCAT_SYSLOG_FAIL" = restart ] && exit 42
[ "$1" = restart ] || exit 43
if [ -s /run/rsyslog-test.pid ]; then
    kill "$(cat /run/rsyslog-test.pid)"
    for i in {1..50}; do [ -f /run/rsyslog-test.pid ] || break; sleep .1; done
fi
exec /usr/sbin/rsyslogd -i /run/rsyslog-test.pid -f /etc/rsyslog.conf
SH
write_file("$tmp/bin/logger", <<'SH');
#!/bin/bash
printf '%s\n' "$*" >> "$XCAT_SYSLOG_FIXTURE/logger.log"
SH
write_file("$tmp/bin/namespace", <<'SH');
#!/bin/bash
set -eu
mount --make-rprivate /
mount --bind "$XCAT_SYSLOG_FIXTURE/etc" /etc
mount --bind "$XCAT_SYSLOG_FIXTURE/log" /var/log
mount --bind "$XCAT_SYSLOG_FIXTURE/run" /run
mount --bind "$XCAT_SYSLOG_FIXTURE/state" /var/lib/rsyslog
ip link set lo up
trap 'for f in /run/*pid; do [ ! -f "$f" ] || kill "$(cat "$f")" 2>/dev/null || :; done' EXIT
/usr/sbin/rsyslogd -i /run/upstream.pid -f "$XCAT_SYSLOG_FIXTURE/upstream.conf"
for pass in 1 2; do
    set +e
    bash "$XCAT_SYSLOG_BIN/syslog" > "$XCAT_SYSLOG_FIXTURE/postscript-$pass.log" 2>&1
    rc=$?
    set -e
    echo "$rc" > "$XCAT_SYSLOG_FIXTURE/postscript-$pass.rc"
    cp /etc/rsyslog.conf "$XCAT_SYSLOG_FIXTURE/config-$pass"
    cp /etc/rsyslog.d/remote.conf "$XCAT_SYSLOG_FIXTURE/remote-$pass" 2>/dev/null || :
    [ "$rc" -eq 0 ] || break
done
set +e
/usr/sbin/rsyslogd -N1 -f /etc/rsyslog.conf > "$XCAT_SYSLOG_FIXTURE/parser.log" 2>&1
echo "$?" > "$XCAT_SYSLOG_FIXTURE/parser.rc"
set -e
ss -H -lun 'sport = :514' > "$XCAT_SYSLOG_FIXTURE/udp-514"
ss -H -ltn 'sport = :514' > "$XCAT_SYSLOG_FIXTURE/tcp-514"
if [ -s "$XCAT_SYSLOG_FIXTURE/udp-514" ]; then
    /usr/bin/logger -n 127.0.0.1 -P 514 -d -t xcat-syslog-test 'xcat-native-udp-proof'
fi
if [ -s "$XCAT_SYSLOG_FIXTURE/tcp-514" ]; then
    /usr/bin/logger -n 127.0.0.1 -P 514 -T -t xcat-syslog-test 'xcat-native-tcp-proof'
fi
if [ "$XCAT_SYSLOG_ROLE" = cn ]; then
    /usr/bin/logger -n 127.0.0.1 -P 1515 -d -t xcat-syslog-test 'xcat-native-cn-proof'
fi
for i in {1..30}; do
    if [ "$XCAT_SYSLOG_ROLE" = cn ]; then
        grep -q xcat-native-cn-proof /var/log/upstream 2>/dev/null && break
    else
        grep -q xcat-native-tcp-proof /var/log/messages /var/log/upstream 2>/dev/null && break
    fi
    sleep .1
done
SH
chmod 0755, "$tmp/bin/$_" for qw(systemctl logger namespace);
my $default = read_file('/etc/rsyslog.conf');
my $minimal = "global(workDirectory=\"/var/lib/rsyslog\")\ninclude(file=\"/etc/rsyslog.d/*.conf\" mode=\"optional\")\n*.info /var/log/messages\n";
my $modern = "module(\n load=\"imudp\"\n)\ninput(\n address=\"127.0.0.1\"\n port=\"514\"\n type=\"imudp\"\n)\nmodule(load=\"imtcp\")\ninput(type=\"imtcp\" address=\"127.0.0.1\" port=\"514\")\n";
my $legacy = "\$ModLoad imudp\n\$UDPServerRun 514\n\$ModLoad imtcp\n\$InputTCPServerRun 514\n";
my @cases = (
    ['native default MN', 'mn', 'openeuler24.03', $default],
    ['native default SN local', 'snlocal', 'openeuler24.03', $default],
    ['native default SN forwarding', 'snforward', 'openeuler24.03', $default],
    ['native CN forwarding', 'cn', 'openeuler24.03', $minimal],
    ['native os-release fallback', 'mn', '', $minimal],
    ['native nested modern admin', 'mn', 'openeuler24.03', $minimal, $modern],
    ['native same-line admin', 'mn', 'openeuler24.03', $minimal, "module(load=\"imudp\") input(type=\"imudp\" port=\"514\")\nmodule(load=\"imtcp\") input(type=\"imtcp\" port=\"514\")\n"],
    ['native quoted close admin', 'mn', 'openeuler24.03', $minimal, "module(load=\"imudp\")\ninput(type=\"imudp\" name=\"admin)receiver\" port=\"514\")\nmodule(load=\"imtcp\")\ninput(type=\"imtcp\" port=\"514\")\n"],
    ['native quoted attribute data', 'mn', 'openeuler24.03', $minimal, "module(load=\"imudp\")\ninput(type=\"imudp\" name=\"type='imudp',port='514'\" port=\"1515\")\nmodule(load=\"imtcp\")\ninput(type=\"imtcp\" port=\"514\")\n"],
    ['native legacy admin', 'snlocal', 'openeuler24.03', $minimal, $legacy],
    ['native module without listener', 'mn', 'openeuler24.03', $minimal, "module(load=\"imudp\")\nmodule(load=\"imtcp\")\n"],
    ['native commented admin', 'mn', 'openeuler24.03', $minimal, join('', map { "#$_\n" } split /\n/, $modern)],
    ['native block comments', 'mn', 'openeuler24.03', $minimal, "/*\n$modern*/\n"],
    ['legacy commented examples', 'mn', 'rhels9.6', $minimal . join('', map { "#$_\n" } split /\n/, $legacy)],
    ['legacy no examples', 'mn', 'rhels9.6', $minimal],
    ['native invalid configuration', 'mn', 'openeuler24.03', $minimal . "invalid_rsyslog_directive()\n", '', 'parser'],
    ['native restart failure', 'mn', 'openeuler24.03', $minimal, '', 'restart'],
);
my $number = 0;
for my $case (@cases) {
    my ($name, $role, $osver, $config, $admin, $failure) = @$case;
    $admin //= ''; $failure //= '';
    my $fixture = "$tmp/" . ++$number;
    make_path(map { "$fixture/$_" } qw(etc/rsyslog.d etc/admin log run state));
    write_file("$fixture/etc/os-release", 'ID="' . ($osver =~ /^rhels/ ? 'rhel' : 'openEuler') . "\"\n");
    write_file("$fixture/etc/xCATMN", '') if $role eq 'mn';
    if ($admin ne '') {
        write_file("$fixture/etc/rsyslog.d/admin.conf", "include(file=\"/etc/admin/receiver.conf\")\n");
        write_file("$fixture/etc/admin/receiver.conf", $admin);
    }
    if ($role eq 'cn') {
        write_file("$fixture/etc/rsyslog.d/admin.conf", "module(load=\"imudp\")\ninput(type=\"imudp\" port=\"1515\")\n");
    }
    write_file("$fixture/etc/rsyslog.conf", $config);
    write_file("$fixture/upstream.conf", "module(load=\"imudp\")\ninput(type=\"imudp\" port=\"1514\")\n*.* /var/log/upstream\n");
    local %ENV = (%ENV, PATH => "$tmp/bin:$ENV{PATH}", XCAT_SYSLOG_FIXTURE => $fixture,
        XCAT_SYSLOG_BIN => "$tmp/bin", XCAT_SYSLOG_FAIL => $failure, XCAT_SYSLOG_ROLE => $role,
        OSVER => $osver, NTYPE => ($role =~ /^sn/ ? 'service' : 'compute'),
        SVLOGLOCAL => ($role eq 'snlocal' ? 1 : 0), MASTER => '127.0.0.1:1514', SYSLOG => '');
    is(system('unshare', '-mn', '--', "$tmp/bin/namespace"), 0, "$name: isolated driver completed");
    my $rc = read_file("$fixture/postscript-1.rc");
    chomp $rc;
    die "Missing postscript status for $name" unless $rc =~ /^\d+$/;
    if ($failure) {
        isnt($rc, 0, "$name: failure reaches postscript exit");
        is(read_file("$fixture/logger.log"), '', "$name: no success log");
        is(read_file("$fixture/services.log"), '', "$name: invalid configuration is not restarted") if $failure eq 'parser';
        next;
    }
    is($rc, 0, "$name: first postscript succeeds");
    my $repeat = read_file("$fixture/postscript-2.rc");
    chomp $repeat;
    is($repeat, 0, "$name: repeat succeeds");
    is(read_file("$fixture/config-2"), read_file("$fixture/config-1"), "$name: main configuration is repeatable");
    is(read_file("$fixture/remote-2"), read_file("$fixture/remote-1"), "$name: forwarding configuration is repeatable");
    is(0 + read_file("$fixture/parser.rc"), 0, "$name: native parser accepts result");
    is(read_file("$fixture/etc/admin/receiver.conf"), $admin, "$name: administrator include preserved");
    if ($name =~ /^native (nested modern|same-line|quoted close|legacy) admin$/) {
        unlike(read_file("$fixture/config-2"), qr/^(?:module|input)\(/m,
            "$name: existing administrator receivers need no duplicate declarations");
    }
    my $receives = $role ne 'cn' && $name ne 'legacy no examples';
    for my $protocol (qw(udp tcp)) {
        is(!!length(read_file("$fixture/$protocol-514")), !!$receives, "$name: $protocol listener matches role");
        if ($receives) {
            my $destination = $role eq 'snforward' ? 'upstream' : 'messages';
            like(read_file("$fixture/log/$destination"), qr/xcat-native-$protocol-proof/, "$name: real $protocol traffic reaches $destination");
        }
    }
    if ($role eq 'cn') {
        like(read_file("$fixture/log/upstream"), qr/xcat-native-cn-proof/, "$name: real CN traffic forwards");
    }
    my $remote = read_file("$fixture/etc/rsyslog.d/remote.conf");
    if ($role eq 'cn' || $role eq 'snforward') {
        like($remote, qr/^\*\.\* \@127\.0\.0\.1:1514$/m, "$name: master forwarding retained");
    } else {
        unlike($remote, qr/^\*\.\* \@/m, "$name: local logs are not forwarded");
    }
}
done_testing();
