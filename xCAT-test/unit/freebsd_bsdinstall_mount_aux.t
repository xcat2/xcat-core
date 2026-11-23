#!/usr/bin/env perl
use strict;
use warnings;

use Carp qw(croak);
use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

plan skip_all => 'requires native FreeBSD bsdconfig without mounted DVD packages'
    if $^O ne 'freebsd' || !-d '/usr/share/bsdconfig' || -e '/packages';
my $directory = $ENV{XCAT_FREEBSD_INSTALLER_DIR}
    || "$FindBin::Bin/../../xCAT-server/share/xcat/install/freebsd";
my $helper = "$directory/patch-bsdinstall-mount_aux.sh";
my $native = "$FindBin::Bin/fixtures/freebsd15.1-bsdinstall-mount_aux";
my $root = tempdir('xcat-mount-test.XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $digest = '39ecb2ae16c45198b5fbda31dbc41278417f07f60521ba458e530ffa4a720ecb';

sub read_file {
    my $path = shift;
    open(my $fh, '<', $path) or croak "$path: $!";
    local $/ = undef;
    my $data = <$fh>;
    close($fh) or croak "$path: $!";
    return $data // '';
}

sub write_file {
    my ($path, $data) = @_;
    open(my $fh, '>', $path) or croak "$path: $!";
    print {$fh} $data or croak "$path: $!";
    close($fh) or croak "$path: $!";
    return;
}

sub run {
    my @args = @_;
    open(my $pipe, '-|', '/bin/sh', '-c', 'exec "$@" 2>&1', 'sh', @args) or croak $!;
    local $/ = undef;
    my $data = <$pipe>;
    close($pipe);
    my $status = $?;
    return (($status & 127) ? 128 + ($status & 127) : $status >> 8, $data // '');
}

is(sha256_hex(read_file($native)), $digest, 'fixture is the pinned native mount helper');
my ($patch_status, $patched) = run('/bin/sh', $helper, $native);
is($patch_status, 0, 'patcher accepts the pinned native source');
BAIL_OUT('native mount patch failed') if $patch_status;
write_file("$root/patched", $patched);
is((run('/bin/sh', '-n', "$root/patched"))[0], 0, 'generated helper has shell syntax');
write_file("$root/changed", read_file($native) . "\n");
my ($drift_status, $drift_output) = run('/bin/sh', $helper, "$root/changed");
isnt($drift_status, 0, 'patcher rejects source drift');
unlike($drift_output, qr/^\#!/mx, 'source drift emits no executable script');

sub mount_case {
    my ($script, $status, $existing) = @_;
    my $case = tempdir(DIR => $root, CLEANUP => 1);
    make_path("$case/bin", "$case/target");
    make_path("$case/target/dev") if $existing;
    write_file("$case/bin/mount", <<'MOUNT');
#!/bin/sh
printf '%s\n' "$*" >> "$TEST_EVENTS"
exit "$TEST_MOUNT_STATUS"
MOUNT
    chmod(0755, "$case/bin/mount") == 1 or croak "Cannot set fixture mode: $!";
    local %ENV = (PATH => "$case/bin:/sbin:/bin:/usr/sbin:/usr/bin", LC_ALL => 'C',
        TERM => 'vt100', BSDINSTALL_CHROOT => "$case/target",
        TEST_EVENTS => "$case/events", TEST_MOUNT_STATUS => $status);
    my ($exit, $output) = run('/bin/sh', $script);
    return ($exit, read_file("$case/events"), $case, $output);
}

for my $existing (0, 1) {
    for my $error (0, 7, 42) {
        my ($status, $events, $case, $output) = mount_case("$root/patched", $error, $existing);
        is($status, $error ? 1 : 0, "devfs status $error is propagated with existing directory $existing")
            or diag $output;
        is($events, "-t devfs devfs $case/target/dev\n", 'native helper attempts exactly its target devfs mount');
    }
}
my ($old_status, $old_events, $old_case) = mount_case($native, 42, 0);
is($old_status, 0, 'exact native control hides the devfs mount failure');
is($old_events, "-t devfs devfs $old_case/target/dev\n", 'control reaches the same failing command');
is(sha256_hex(read_file($native)), $digest, 'native source is unchanged');
done_testing();
