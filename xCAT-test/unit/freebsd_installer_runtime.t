#!/usr/bin/env perl
use strict;
use warnings;

use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use MIME::Base64 qw(encode_base64);
use Test::More;

my $directory = $ENV{XCAT_FREEBSD_INSTALLER_DIR} || "$FindBin::Bin/../../xCAT-server/share/xcat/install/freebsd";
my $library = "$directory/xcat-install-lib.sh";
ok(-f $library, 'the installed runtime library exists');

sub write_file {
    my ($file, $content) = @_;
    open(my $fh, '>', $file) or die "$file: $!";
    print {$fh} $content;
    close($fh) or die "$file: $!";
}

sub read_file {
    my $file = shift;
    return '' unless -e $file;
    open(my $fh, '<', $file) or die "$file: $!";
    local $/;
    my $content = <$fh>;
    close($fh);
    return $content;
}

sub configuration {
    my %changes = @_;
    my %fields = (
        format => 'xcat-freebsd-install-1', release => '15.1-RELEASE',
        node => 'node01', generation => 'a' x 32, master => '192.0.2.1', port => 3002,
        mac => '52:54:00:12:34:56', ipv4 => '192.0.2.20', netmask => '255.255.255.0',
        gateway => '', hostname => 'node01.example.test', target_disk => 'ada0',
        target_disk_ident => 'XCAT_TEST_DISK', filesystem => 'zfs', swap_size => '2g',
        dist_url => 'http://192.0.2.1/install/freebsd/dist',
        base_sha256 => sha256_hex('base archive'), kernel_sha256 => sha256_hex('kernel archive'),
        authorized_key_base64 => encode_base64('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPu2fQbGvNixfzG3hYrKcXFP6eZDrZMDnuES0GhLWDPE', ''),
        nameservers => '192.0.2.1,192.0.2.2', %changes,
    );
    return join('', map { "$_=$fields{$_}\n" } sort keys %fields);
}

sub fixture {
    my (%options) = @_;
    my $root = tempdir(CLEANUP => 1);
    make_path("$root/bin", "$root/labels", "$root/work");
    write_file("$root/config", configuration(%{$options{config} || {}}));
    write_file("$root/base.txz", 'base archive');
    write_file("$root/kernel.txz", 'kernel archive');
    write_file("$root/MANIFEST", "base.txz\t" . sha256_hex('base archive') . "\t10\tbase\tBase\ton\n" .
        "kernel.txz\t" . sha256_hex('kernel archive') . "\t5\tkernel\tKernel\ton\n");
    write_file("$root/disk", "Geom name: ada0\nMediasize: 8589934592 (8.0G)\nMode: r0w0e0\nident: XCAT_TEST_DISK\n");
    write_file("$root/pools", '');
    write_file("$root/geli", '');
    write_file("$root/partitions", "Geom name: ada0\nProviders:\n1. Name: ada0p3\nConsumers:\n1. Name: ada0\n\n" .
        "Geom name: ada1\nProviders:\n1. Name: ada1p3\nConsumers:\n1. Name: ada1\n");
    my %commands = (
        kldload => 'test ! -f "$FIXTURE_DIR/kldload-status-$2" || exit "$(cat "$FIXTURE_DIR/kldload-status-$2")"',
        geom => 'cat "$FIXTURE_DIR/disk"',
        geli => 'cat "$FIXTURE_DIR/geli"',
        sysctl => 'printf "ada0 ada1\\n"',
        gpart => 'test ! -f "$FIXTURE_DIR/gpart-status" || exit "$(cat "$FIXTURE_DIR/gpart-status")"; cat "$FIXTURE_DIR/partitions"',
        zdb => 'test ! -f "$FIXTURE_DIR/zdb-status-${2##*/}" || exit "$(cat "$FIXTURE_DIR/zdb-status-${2##*/}")";' .
            'test -f "$FIXTURE_DIR/labels/${2##*/}" || exit 2; cat "$FIXTURE_DIR/labels/${2##*/}"',
        zpool => 'case "$1" in list) cat "$FIXTURE_DIR/pools" ;; labelclear) ;; *) exit 1 ;; esac',
        fetch => 'cp "$FIXTURE_DIR/${5##*/}" "$4"',
        sha256 => 'openssl dgst -sha256 -r "$2" | awk "{print \\$1}"',
        nc => 'read -r protocol generation attempt phase; printf "phase %s\\n" "$phase" >> "$FIXTURE_DIR/events";' .
            'if [ -f "$FIXTURE_DIR/reject-$phase" ]; then printf "ready\\nerror\\n"; else printf "ready\\nfreebsd-install-v1 %s %s ok\\n" "$generation" "$phase"; fi',
        timeout => 'shift; exec "$@"',
        ifconfig => 'case "$*" in -l) printf "em0 em1 lo0\\n" ;; em0) printf "ether 52:54:00:12:34:56\\n" ;; em1) printf "ether 52:54:00:12:34:57\\n" ;; lo0) printf "inet 127.0.0.1\\n" ;; esac',
    );
    for my $name (keys %commands) {
        write_file("$root/bin/$name", "#!/bin/sh\nprintf '%s %s\\n' '$name' \"\$*\" >> \"\$FIXTURE_DIR/events\"\n$commands{$name}\n");
        chmod 0755, "$root/bin/$name";
    }
    write_file("$root/bin/bsdinstall", "#!/bin/sh\nprintf 'bsdinstall %s\\n' \"\$*\" >> '$root/events'\ntest ! -e '$root/install-fails'\n");
    chmod 0755, "$root/bin/bsdinstall";
    return $root;
}

sub run_runtime {
    my ($root, $code, @args) = @_;
    local %ENV = (%ENV, PATH => "$root/bin:$ENV{PATH}", FIXTURE_DIR => $root,
        XCAT_WORK => "$root/work", XCAT_ATTEMPT => 'b' x 32, XCAT_PROVISIONING_IF => 'em0');
    open(my $pipe, '-|', 'sh', '-c', '. "$1"; shift; ' . $code . ' 2>&1', 'sh', $library, "$root/config", @args) or die $!;
    local $/;
    my $output = <$pipe>;
    close($pipe);
    return ($? >> 8, $output // '');
}

for my $file (qw(xcat-install xcat-install-lib.sh buildmfsbsd.sh installerconfig.tmpl)) {
    is(system('sh', '-n', "$directory/$file"), 0, "$file has shell syntax");
}

for my $filesystem (qw(ufs zfs)) {
    my $root = fixture(config => {filesystem => $filesystem});
    my ($status, $output) = run_runtime($root, 'xcat_read_config "$1" && xcat_write_installer "$2"', "$directory/installerconfig.tmpl");
    is($status, 0, "$filesystem configuration renders");
    if ($filesystem eq 'zfs') {
        like($output, qr/^export ZFSBOOT_DISKS="ada0"$/m, 'ZFS uses only the selected disk');
        like($output, qr/^export ZFSBOOT_VDEV_TYPE="stripe"$/m, 'ZFS single-disk topology is explicit');
        unlike($output, qr/^PARTITIONS=/m, 'ZFS does not select the UFS partitioner');
    } else {
        like($output, qr/^PARTITIONS="ada0 GPT \{ 2g freebsd-swap, auto freebsd-ufs \/ \}"$/m, 'UFS renders an explicit GPT layout');
        unlike($output, qr/^export ZFSBOOT_DISKS=/m, 'UFS does not enable ZFS partitioning');
    }
}

for my $bad (
    [target_disk => 'md0'], [target_disk => 'ada0 ada1'], [target_disk => '/dev/ada0'],
    [target_disk_ident => ''], [generation => 'bad'], [base_sha256 => 'f' x 63],
    [filesystem => 'ext4'], [swap_size => '$(touch BAD)'], [port => 0],
    [mac => '52:54:00:12:34:xx'], [ipv4 => '192.0.2.256'], [ipv4 => '192.0.02.1'],
    [netmask => '255.0.255.0'], [netmask => '255.255.127.0'], [nameservers => '192.0.2.1,'],
    [dist_url => 'http://192.0.2.1/../dist'], [authorized_key_base64 => '$(id)'],
    [unknown => 'value'],
) {
    my $root = fixture(config => {$bad->[0] => $bad->[1]});
    my ($status) = run_runtime($root, 'xcat_read_config "$1"');
    isnt($status, 0, "rejects invalid $bad->[0]=$bad->[1]");
}

{
    my $root = fixture();
    is((run_runtime($root, 'xcat_read_config "$1" && xcat_validate_key "$XCAT_WORK/key"'))[0], 0, 'a real public key is accepted');
    for my $bad ('-----BEGIN OPENSSH PRIVATE KEY-----', 'ssh-ed25519 AAAAA') {
        write_file("$root/config", configuration(authorized_key_base64 => encode_base64($bad, '')));
        isnt((run_runtime($root, 'xcat_read_config "$1" && xcat_validate_key "$XCAT_WORK/key"'))[0], 0, 'private or malformed key material is rejected');
    }
}

{
    my $root = fixture();
    write_file("$root/config", read_file("$root/config") . "filesystem=ufs\n");
    isnt((run_runtime($root, 'xcat_read_config "$1"'))[0], 0, 'duplicate fields fail');
}

{
    my $root = fixture();
    my ($status, $output) = run_runtime($root, 'xcat_find_interface 52:54:00:12:34:56');
    is($status, 0, 'MAC lookup succeeds');
    is($output, "em0\n", 'MAC lookup selects only the provisioning NIC');
    isnt((run_runtime($root, 'xcat_find_interface 52:54:00:12:34:99'))[0], 0, 'unmatched MAC fails');
}

my $single_disk_labels = "pool_guid: 12345\nname: 'zroot'\nvdev_children: 1\nvdev_tree:\n    type: 'disk'\n";
for my $partitions ('', "Geom name: ada1\nProviders:\n1. Name: ada1p3\nConsumers:\n1. Name: ada1\n") {
    my $root = fixture();
    write_file("$root/partitions", $partitions);
    my ($status, $output) = run_runtime($root, 'xcat_read_config "$1" && xcat_scan_labels && printf "%s" "$XCAT_CLEAR_LABELS"');
    is($status, 0, 'an unpartitioned target with no ZFS labels is accepted');
    is($output, '', 'a blank disk has no labels to clear');
}
{
    my $root = fixture();
    write_file("$root/partitions", "Geom name: ada0\nProviders:\n1. Name: ada0s1\nConsumers:\n1. Name: ada0\n\n" .
        "Geom name: ada0s1\nProviders:\n1. Name: ada0s1a\nConsumers:\n1. Name: ada0s1\n");
    write_file("$root/labels/ada0s1a", $single_disk_labels);
    my ($status, $output) = run_runtime($root, 'xcat_read_config "$1" && xcat_scan_labels && printf "%s" "$XCAT_CLEAR_LABELS"');
    is($status, 0, 'nested partition providers are inspected');
    is($output, ' /dev/ada0s1a', 'nested ZFS labels resolve to the selected disk');
}
{
    my $root = fixture();
    write_file("$root/partitions", read_file("$root/partitions") .
        "\nGeom name: diskid/DISK-QM00001\nProviders:\n1. Name: diskid/DISK-QM00001p3\nConsumers:\n1. Name: diskid/DISK-QM00001\n");
    write_file("$root/labels/ada0p3", $single_disk_labels);
    my ($status, $output) = run_runtime($root, 'xcat_read_config "$1" && xcat_scan_labels && printf "%s" "$XCAT_CLEAR_LABELS"');
    is($status, 0, 'native disk-ID aliases do not prevent partition enumeration');
    is($output, ' /dev/ada0p3', 'duplicate disk-ID aliases do not duplicate selected label clearing');
}
for my $failure (
    ['kldload-status-zfs', '1'], ['kldload-status-geom_eli', '1'],
    ['kldload-status-zfs', '127'], ['kldload-status-geom_eli', '127'],
    ['gpart-status', '1'], ['gpart-status', '127'],
    ['zdb-status-ada0p3', '1'], ['zdb-status-ada0p3', '127'],
    ['zdb-status-ada1p3', '1'], ['zdb-status-ada1p3', '127'],
    ['labels/ada0p3', 'unrecognized valid label'], ['partitions', 'unrecognized partition list'],
    ['partitions', "Geom name: ada0\nProviders:\n1. Name: ../ada1\nConsumers:\n1. Name: ada0\n"],
) {
    my $root = fixture();
    write_file("$root/$failure->[0]", $failure->[1]);
    my ($status) = run_runtime($root, 'xcat_read_config "$1" && xcat_install_system "$2"', "$directory/installerconfig.tmpl");
    isnt($status, 0, "unreadable or malformed metadata fails: $failure->[0]=$failure->[1]");
    unlike(read_file("$root/events"), qr/phase begin|zpool labelclear|bsdinstall script/,
        'metadata failure stops before authorization or disk mutation');
}
{
    my $root = fixture();
    write_file("$root/labels/ada0p3", $single_disk_labels);
    my ($status, $output) = run_runtime($root, 'xcat_read_config "$1" && xcat_scan_labels && printf "%s\\n" "$XCAT_CLEAR_LABELS"');
    is($status, 0, 'existing single-disk zroot passes preflight');
    is($output, " /dev/ada0p3\n", 'label clearing selects only the authorized partition');
    write_file("$root/labels/ada1p3", $single_disk_labels);
    isnt((run_runtime($root, 'xcat_read_config "$1" && xcat_scan_labels'))[0], 0, 'zroot on an unselected disk fails before mutation');
    unlike(read_file("$root/events"), qr/zpool labelclear/, 'label scanning does not clear anything');
}
for my $topology ("vdev_children: 2", "vdev_children: 1\n    type: 'mirror'") {
    my $root = fixture();
    write_file("$root/labels/ada0p3", "pool_guid: 12345\nname: 'zroot'\n$topology\n");
    isnt((run_runtime($root, 'xcat_read_config "$1" && xcat_scan_labels'))[0], 0, 'a member of a multi-disk pool is not a reinstall target');
}
for my $bad (
    ['disk', "Geom name: ada0\nMediasize: 8589934592\nMode: r0w0e0\nident: OTHER_DISK\n"],
    ['disk', "Geom name: ada0\nMediasize: 8589934592\nMode: r1w1e1\nident: XCAT_TEST_DISK\n"],
    ['pools', "data\n"], ['geli', "ada1p3.eli ACTIVE ada1p3\n"],
) {
    my $root = fixture();
    write_file("$root/$bad->[0]", $bad->[1]);
    isnt((run_runtime($root, 'xcat_read_config "$1" && xcat_check_disk'))[0], 0, "unsafe disk state from $bad->[0] is rejected");
}

{
    my $root = fixture();
    write_file("$root/labels/ada0p3", $single_disk_labels);
    my ($status, $output) = run_runtime($root, 'xcat_read_config "$1" && xcat_install_system "$2"', "$directory/installerconfig.tmpl");
    is($status, 0, 'the production installer sequence succeeds with external commands isolated') or diag($output);
    my $events = read_file("$root/events");
    like($events, qr/kldload -n zfs.*kldload -n geom_eli.*zpool list.*geli status/s,
        'required kernel modules load before checking attached storage');
    like($events, qr/sha256 .*base\.txz.*sha256 .*kernel\.txz.*phase begin.*zpool labelclear -f \/dev\/ada0p3.*bsdinstall script.*phase complete/s,
        'both checksum checks precede authorization, selected label clearing, installer, and completion');
    unlike($events, qr/zpool labelclear[^\n]*ada1/, 'unselected disk labels are unchanged');
}

for my $failure (qw(checksum manifest begin installer complete)) {
    my $root = fixture();
    write_file("$root/labels/ada0p3", $single_disk_labels);
    write_file("$root/base.txz", 'bad archive') if $failure eq 'checksum';
    write_file("$root/MANIFEST", "base.txz\tbad\n") if $failure eq 'manifest';
    write_file("$root/reject-$failure", '') if $failure eq 'begin' || $failure eq 'complete';
    write_file("$root/install-fails", '') if $failure eq 'installer';
    my ($status, $output) = run_runtime($root, 'xcat_read_config "$1" && xcat_install_system "$2"', "$directory/installerconfig.tmpl");
    isnt($status, 0, "$failure failure stops installation");
    my $events = read_file("$root/events");
    if ($failure =~ /^(checksum|manifest|begin)$/) {
        unlike($events, qr/zpool labelclear|bsdinstall script/, "$failure failure does not modify the disk");
    }
    unlike($events, qr/phase complete/, 'failed installer does not report completion') if $failure eq 'installer';
}

done_testing;
