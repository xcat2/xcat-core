#!/usr/bin/env perl
use strict;
use warnings;

use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

plan skip_all => 'requires native FreeBSD bsdconfig includes'
    unless $^O eq 'freebsd' && -d '/usr/share/bsdconfig';
my $native = $ENV{XCAT_FREEBSD_NATIVE_SCRIPT} || '/usr/libexec/bsdinstall/script';
my $patcher = $ENV{XCAT_FREEBSD_SCRIPT_PATCHER}
    || "$FindBin::Bin/../../xCAT-server/share/xcat/install/freebsd/patch-bsdinstall-script.sh";
my $task = tempdir('xcat-script-test.XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $native_digest = '1683193f5d36338d3a3db10322a0953222bcee357715819e0f8996e48c192788';

sub read_file {
    my $path = shift;
    return '' unless -e $path;
    open(my $fh, '<', $path) or die "$path: $!";
    local $/;
    my $data = <$fh>;
    close($fh) or die "$path: $!";
    return $data // '';
}

sub write_file {
    my ($path, $data) = @_;
    open(my $fh, '>', $path) or die "$path: $!";
    print {$fh} $data or die "$path: $!";
    close($fh) or die "$path: $!";
}

sub run {
    open(my $pipe, '-|', '/bin/sh', '-c', 'exec "$@" 2>&1', 'sh', @_) or die $!;
    local $/;
    my $data = <$pipe>;
    close($pipe);
    my $status = $?;
    return (($status & 127) ? 128 + ($status & 127) : $status >> 8, $data // '');
}

BAIL_OUT('native bsdinstall script does not match the release')
    unless sha256_hex(read_file($native)) eq $native_digest;
my ($patch_status, $patched) = run('/bin/sh', $patcher, $native);
is($patch_status, 0, 'patcher accepts the pinned native script');
BAIL_OUT('native script patch failed') if $patch_status;
write_file("$task/patched", $patched);
is((run('/bin/sh', '-n', "$task/patched"))[0], 0, 'generated native script has shell syntax');
write_file("$task/changed", read_file($native) . "\n");
my ($changed_status, $changed_output) = run('/bin/sh', $patcher, "$task/changed");
isnt($changed_status, 0, 'patcher rejects source drift');
like($changed_output, qr/Unsupported FreeBSD 15\.1 bsdinstall script checksum/,
    'source drift reports the failed identity check');
unlike($changed_output, qr/^#!/m, 'source drift emits no executable script');

sub failure_case {
    my ($script, $mode, $filesystem, $storage) = @_;
    my $root = tempdir('failure.XXXXXX', DIR => $task, CLEANUP => 1);
    make_path("$root/bin", "$root/tmp", "$root/target");
    write_file("$root/fstab", '');
    write_file("$root/debug", "native installer error\n");
    write_file("$root/config", "false\n");
    write_file("$root/bin/bsdinstall", <<'BSDINSTALL');
#!/bin/sh
printf 'bsdinstall %s\n' "$*" >> "$TEST_EVENTS"
[ "$1" = umount ]
BSDINSTALL
    write_file("$root/bin/bsddialog", <<'BSDDIALOG');
#!/bin/sh
printf 'dialog %s\n' "$*" >> "$TEST_EVENTS"
exit 0
BSDDIALOG
    write_file("$root/bin/zpool", <<'ZPOOL');
#!/bin/sh
printf 'zpool %s\n' "$*" >> "$TEST_EVENTS"
[ "$*" = 'export zroot' ]
ZPOOL
    chmod(0755, "$root/bin/bsdinstall", "$root/bin/bsddialog", "$root/bin/zpool") == 3
        or die "Cannot make command fixtures executable: $!";
    local %ENV = (PATH => "$root/bin:/sbin:/bin:/usr/sbin:/usr/bin", LC_ALL => 'C',
        TERM => 'vt100', TMPDIR => "$root/tmp", TEST_EVENTS => "$root/events",
        BSDINSTALL_CHROOT => "$root/target", BSDINSTALL_TMPETC => "$root/tmpetc",
        BSDINSTALL_LOG => "$root/debug", debugFile => "$root/debug",
        PATH_FSTAB => "$root/fstab", ZFSBOOT_DISKS => ($filesystem eq 'zfs' ? 'vtbd0' : ''));
    $ENV{nonInteractive} = $mode if defined($mode);
    $ENV{XCAT_STORAGE_WORK} = "$root/storage" if $storage;
    my ($status, $output) = run('/usr/bin/timeout', '-k', '2', '15',
        '/bin/sh', $script, "$root/config");
    return ($status, read_file("$root/events"), $output);
}

for my $filesystem (qw(ufs zfs)) {
    my ($old_status, $old_events, $old_output) = failure_case($native, 'YES', $filesystem);
    is($old_status, 1, "$filesystem exact native negative control fails") or diag $old_output;
    like($old_events, qr/^dialog .*--textbox/m,
        "$filesystem exact native negative control opens the error textbox");
    for my $mode ('YES', 'NO', '', undef) {
        my $label = defined($mode) ? "'$mode'" : 'unset';
        my ($status, $events, $output) = failure_case("$task/patched", $mode, $filesystem);
        is($status, 1, "$filesystem failure remains nonzero for mode $label") or diag $output;
        my $cleanup = $filesystem eq 'zfs' ? qr/^zpool export zroot$/m : qr/^bsdinstall umount$/m;
        like($events, $cleanup, "$filesystem native failure cleanup still runs for mode $label");
        unlike($events, qr/^bsdinstall (?!umount)/m, 'the failure fixture never partitions a disk');
        if (defined($mode) && $mode eq 'YES') {
            unlike($events, qr/^dialog /m, 'unattended failure opens no error dialogue');
        } else {
            like($events, qr/^dialog .*--textbox/m, 'interactive native error dialogue is preserved');
        }
    }
    my ($guard_status, $guard_events, $guard_output) = failure_case("$task/patched", 'YES', $filesystem, 1);
    is($guard_status, 1, "$filesystem guarded failure remains nonzero") or diag $guard_output;
    unlike($guard_events, qr/^(?:zpool export|bsdinstall umount)/m,
        "$filesystem guarded failure does not clean up a pool or mount by name");
    unlike($guard_events, qr/^dialog /m, "$filesystem guarded failure remains unattended");
    my ($native_guard_status, $native_guard_events, $native_guard_output) = failure_case($native, 'YES', $filesystem, 1);
    is($native_guard_status, 1, "$filesystem native control reaches the same failure") or diag $native_guard_output;
    like($native_guard_events, qr/^(?:zpool export|bsdinstall umount)/m,
        "$filesystem native control performs the unsafe automatic cleanup");
}
is(sha256_hex(read_file($native)), $native_digest, 'native bsdinstall source remains unchanged');
done_testing();
