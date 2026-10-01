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
plan skip_all => 'requires native rsyslogd, systemctl, systemd-detect-virt and chroot'
    if system('command -v rsyslogd systemctl systemd-detect-virt chroot >/dev/null');
my $source = $ENV{XCAT_SYSLOG_SOURCE_ROOT} || abs_path("$FindBin::Bin/../..");
my $tmp = tempdir(DIR => '/var/tmp', CLEANUP => !$ENV{XCAT_SYSLOG_KEEP});
diag("fixtures: $tmp") if $ENV{XCAT_SYSLOG_KEEP};
make_path("$tmp/bin");
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
for my $name (qw(syslog xcatlib.sh)) {
    copy("$source/xCAT/postscripts/$name", "$tmp/bin/$name") or die $!;
}
write_file("$tmp/bin/systemctl", <<'SH');
#!/bin/bash
printf '%s\n' "$*" >> "/evidence/services-$XCAT_SYSLOG_PHASE.log"
/usr/bin/systemctl "$@" > "/evidence/systemctl-$XCAT_SYSLOG_PHASE.log" 2>&1
rc=$?
echo "$rc" > "/evidence/systemctl-$XCAT_SYSLOG_PHASE.rc"
cat "/evidence/systemctl-$XCAT_SYSLOG_PHASE.log"
exit "$rc"
SH
write_file("$tmp/bin/logger", <<'SH');
#!/bin/bash
printf '%s\n' "$*" >> /evidence/logger.log
SH
write_file("$tmp/bin/run", <<'SH');
#!/bin/bash
set -eu
mount --make-rprivate /
root="$XCAT_SYSLOG_FIXTURE/root"
for path in usr bin sbin lib lib64; do
    [ -d "/$path" ] || continue
    mount --bind "/$path" "$root/$path"
    mount -o remount,bind,ro "$root/$path"
done
mount --bind "$XCAT_SYSLOG_BIN" "$root/postscripts"
mount -o remount,bind,ro "$root/postscripts"
mount --bind "$XCAT_SYSLOG_FIXTURE/evidence" "$root/evidence"
mount -t proc -o ro proc "$root/proc"
mount -t tmpfs -o mode=755,nosuid tmpfs "$root/dev"
touch "$root/dev/null"
mount --bind /dev/null "$root/dev/null"
set +e
chroot "$root" /usr/bin/systemd-detect-virt --quiet --chroot > "$XCAT_SYSLOG_FIXTURE/evidence/detect.log" 2>&1
echo "$?" > "$XCAT_SYSLOG_FIXTURE/evidence/detect.rc"
chroot "$root" /usr/bin/env PATH=/postscripts:/usr/sbin:/usr/bin:/sbin:/bin XCAT_SYSLOG_PHASE=baseline \
    /bin/bash -c '. /postscripts/xcatlib.sh; restartservice syslog' > "$XCAT_SYSLOG_FIXTURE/evidence/helper.log" 2>&1
echo "$?" > "$XCAT_SYSLOG_FIXTURE/evidence/helper.rc"
for pass in 1 2; do
    chroot "$root" /usr/bin/env PATH=/postscripts:/usr/sbin:/usr/bin:/sbin:/bin XCAT_SYSLOG_PHASE=postscript \
        /bin/bash /postscripts/syslog > "$XCAT_SYSLOG_FIXTURE/evidence/postscript-$pass.log" 2>&1
    rc=$?
    echo "$rc" > "$XCAT_SYSLOG_FIXTURE/evidence/postscript-$pass.rc"
    [ "$rc" -eq 0 ] || break
done
chroot "$root" /usr/sbin/rsyslogd -N1 -f /etc/rsyslog.conf > "$XCAT_SYSLOG_FIXTURE/evidence/parser.log" 2>&1
echo "$?" > "$XCAT_SYSLOG_FIXTURE/evidence/parser.rc"
exit 0
SH
chmod 0755, "$tmp/bin/$_" for qw(systemctl logger run);
my $minimal = "global(workDirectory=\"/var/lib/rsyslog\")\ninclude(file=\"/etc/rsyslog.d/*.conf\" mode=\"optional\")\n*.info /var/log/messages\n";
for my $case (['mn', 0], ['snlocal', 0], ['snforward', 0], ['cn', 0], ['mn', 1], ['cn', 1]) {
    my ($role, $invalid) = @$case;
    my $name = "$role " . ($invalid ? 'invalid' : 'valid') . ' native chroot';
    my $fixture = "$tmp/$role-$invalid";
    make_path("$fixture/evidence", map { "$fixture/root/$_" }
        qw(usr bin sbin lib lib64 postscripts evidence proc dev run tmp etc/rsyslog.d var/log var/lib/rsyslog));
    copy('/etc/ld.so.cache', "$fixture/root/etc/ld.so.cache") or die $!;
    write_file("$fixture/root/etc/os-release", "ID=openEuler\n");
    write_file("$fixture/root/etc/xCATMN", '') if $role eq 'mn';
    write_file("$fixture/root/etc/rsyslog.conf", $minimal . ($invalid ? "invalid_rsyslog_directive()\n" : ''));
    local %ENV = (%ENV, XCAT_SYSLOG_FIXTURE => $fixture, XCAT_SYSLOG_BIN => "$tmp/bin",
        OSVER => ($ENV{XCAT_SYSLOG_OSVER} || 'openeuler24.03'), NTYPE => ($role =~ /^sn/ ? 'service' : 'compute'),
        SVLOGLOCAL => ($role eq 'snlocal' ? 1 : 0), MASTER => '127.0.0.1:1514', SYSLOG => '');
    is(system('unshare', '-mn', '--', "$tmp/bin/run"), 0, "$name: isolated driver completed");
    my $evidence = "$fixture/evidence";
    is(read_file("$evidence/detect.rc"), "0\n", "$name: native helper detects the actual chroot");
    is(read_file("$evidence/systemctl-baseline.rc"), "0\n", "$name: actual systemctl defers successfully");
    like(read_file("$evidence/systemctl-baseline.log"), qr/Running in chroot,\s*ignoring/i,
        "$name: native systemctl identifies service deferral");
    is(read_file("$evidence/helper.rc"), "1\n", "$name: shared restart helper retains its existing contract");
    is(read_file("$evidence/services-postscript.log"), '', "$name: postscript does not attempt service activation");
    if ($invalid) {
        is(read_file("$evidence/postscript-1.rc"), "1\n", "$name: parser failure reaches the postscript exit");
        is(read_file("$evidence/parser.rc"), "1\n", "$name: actual native parser rejects the configuration");
        is(read_file("$evidence/logger.log"), '', "$name: no success log follows invalid configuration");
    } else {
        is(read_file("$evidence/postscript-1.rc"), "0\n", "$name: configuration completes successfully");
        is(read_file("$evidence/postscript-2.rc"), "0\n", "$name: repeated configuration succeeds");
        is(read_file("$evidence/parser.rc"), "0\n", "$name: actual native parser accepts the result");
        like(read_file("$evidence/logger.log"), qr/rsyslog version 8 setup/, "$name: completed configuration is logged");
    }
}
done_testing();
