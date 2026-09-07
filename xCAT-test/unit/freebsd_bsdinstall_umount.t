#!/usr/bin/env perl
use strict;
use warnings;

use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $directory = $ENV{XCAT_FREEBSD_INSTALLER_DIR} || "$FindBin::Bin/../../xCAT-server/share/xcat/install/freebsd";
my $helper = "$directory/patch-bsdinstall-umount.sh";
my $native = "$FindBin::Bin/fixtures/freebsd15.1-bsdinstall-umount";
my $root = tempdir(CLEANUP => 1);
make_path("$root/bin");

sub write_file {
    my ($path, $content) = @_;
    open(my $fh, '>', $path) or die "$path: $!";
    print {$fh} $content;
    close($fh) or die "$path: $!";
}

sub read_file {
    my $path = shift;
    open(my $fh, '<', $path) or die "$path: $!";
    local $/;
    my $content = <$fh>;
    close($fh) or die "$path: $!";
    return $content;
}

sub run_shell {
    my ($code, @args) = @_;
    open(my $pipe, '-|', 'sh', '-c', $code . ' 2>&1', 'sh', @args) or die $!;
    local $/;
    my $output = <$pipe>;
    close($pipe);
    return ($? >> 8, $output // '');
}

write_file("$root/bin/sha256", <<'SHA256');
#!/bin/sh
openssl dgst -sha256 -r "$2" | awk '{print $1}'
SHA256
write_file("$root/bin/umount", <<'UMOUNT');
#!/bin/sh
printf '%s\n' "$*" >> "$FIXTURE_DIR/events"
if [ "$1" = -F ]; then
    cp "$2" "$FIXTURE_DIR/unmount-fstab"
    [ -s "$2" ] || exit 1
    exit "${FSTAB_UMOUNT_STATUS:-0}"
fi
exit 0
UMOUNT
chmod 0755, "$root/bin/sha256", "$root/bin/umount";
local $ENV{PATH} = "$root/bin:$ENV{PATH}";

is(sha256_hex(read_file($native)), '624ae8e292566b28bb6c5a37d14c6e98f06c1fe9b77712cf195982dfc0f9dec0',
    'fixture is the pinned native FreeBSD 15.1 cleanup helper');
is(system('sh', '-n', $helper), 0, 'build helper has shell syntax');
my ($patch_status, $patched) = run_shell('sh "$1" "$2"', $helper, $native);
is($patch_status, 0, 'production build helper accepts native source');
write_file("$root/patched", $patched);
is(system('sh', '-n', "$root/patched"), 0, 'generated cleanup helper has shell syntax');

write_file("$root/changed", read_file($native) . "\n");
my ($drift_status, $drift_output) = run_shell('sh "$1" "$2"', $helper, "$root/changed");
isnt($drift_status, 0, 'build helper rejects source drift');
like($drift_output, qr/Unsupported FreeBSD 15\.1 bsdinstall umount checksum/, 'source drift explains the rejected input');
isnt((run_shell('sh "$1" "$2"', $helper, "$root/missing"))[0], 0, 'missing native helper fails');
is((run_shell('sh "$1"', $helper))[0], 2, 'missing argument fails with usage status');

sub cleanup_case {
    my ($script, $fstab, $error, $packages, %options) = @_;
    my $case = tempdir(DIR => $root, CLEANUP => 1);
    make_path("$case/target/dev", "$case/tmp");
    make_path("$case/target/dist/packages") if $packages;
    write_file("$case/fstab", $fstab) unless $options{missing_input};
    local %ENV = (%ENV, FIXTURE_DIR => $case, BSDINSTALL_CHROOT => "$case/target",
        PATH_FSTAB => "$case/fstab", TMPDIR => $options{bad_output} ? "$case/missing" : "$case/tmp",
        FSTAB_UMOUNT_STATUS => $error);
    my ($status, $output) = run_shell('sh "$1"', $script);
    return ($status, -e "$case/events" ? read_file("$case/events") : '', $case, $output);
}

for my $fstab ('', "# Device Mountpoint FStype Options Dump Pass#\n", "/dev/ada0p2 none swap sw 0 0\n") {
    my ($status, $events, $case) = cleanup_case("$root/patched", $fstab, 0, 0);
    is($status, 0, 'cleanup succeeds without fstab mount entries');
    is($events, "$case/target/dev\n", 'devfs cleanup runs without empty-fstab unmount');
    is(-s "$case/tmp/bsdinstall-tmp-fstab" || 0, 0, 'generated mount list is empty');
}

my ($old_status, $old_events) = cleanup_case($native, '', 0, 0);
is($old_status, 1, 'exact unfixed native helper reproduces empty-fstab failure');
like($old_events, qr/^-F .* -a$/m, 'negative control reaches the erroneous empty-fstab unmount');

for my $failure (qw(missing_input bad_output)) {
    my ($status, $events) = cleanup_case("$root/patched", '', 0, 0, $failure => 1);
    isnt($status, 0, "$failure is not treated as a valid empty mount list");
    is($events, '', "$failure fails before unmounting filesystems");
}

for my $mount (
    ["/dev/ada0p1 /boot/efi msdosfs rw 2 2\n", '/boot/efi', 'msdosfs'],
    ["/dev/ada0p3 / ufs rw 1 1\n", '', 'ufs'],
) {
    for my $error (0, 7) {
        my ($status, $events, $case) = cleanup_case("$root/patched", $mount->[0], $error, 0);
        is($status, $error, 'nonempty fstab preserves the actual unmount result');
        is($events, "$case/target/dev\n-F $case/tmp/bsdinstall-tmp-fstab -a\n", 'devfs cleanup precedes filesystem unmount');
        like(read_file("$case/unmount-fstab"), qr/\Q$case\/target$mount->[1]\E\t\Q$mount->[2]\E\t/,
            'native mount-list generation prefixes the target root');
    }
}

{
    my ($status, $events, $case) = cleanup_case("$root/patched", '', 0, 1);
    is($status, 0, 'empty fstab does not skip package-media cleanup');
    is($events, "$case/target/dist/packages\n$case/target/dev\n", 'package media is unmounted before devfs');
    ok(!-e "$case/target/dist", 'package-media directories are removed');
}

done_testing();
