#!/usr/bin/env perl
use strict;
use warnings;

use Carp qw(croak);
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
        nc => 'read -r protocol generation attempt phase members; printf "phase %s\\n" "$phase" >> "$FIXTURE_DIR/events";' .
            'count=0; test ! -f "$FIXTURE_DIR/nc-count" || count=$(cat "$FIXTURE_DIR/nc-count"); count=$((count+1)); printf "%s\\n" "$count" > "$FIXTURE_DIR/nc-count";' .
            'if [ -f "$FIXTURE_DIR/reject-$phase" ] || { test -f "$FIXTURE_DIR/nc-busy" && test "$count" -le "$(cat "$FIXTURE_DIR/nc-busy")"; }; then printf "ready\\n"; else printf "ready\\n%s %s %s ok\\n" "$protocol" "$generation" "$phase"; fi',
        date => 'if test -f "$FIXTURE_DIR/clock"; then cat "$FIXTURE_DIR/clock"; else printf "0\\n"; fi',
        sleep => 'now=0; test ! -f "$FIXTURE_DIR/clock" || now=$(cat "$FIXTURE_DIR/clock"); printf "%s\\n" "$((now+$1))" > "$FIXTURE_DIR/clock"',
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

{
    my $root = fixture();
    write_file("$root/bin/fetch", <<'SH');
#!/bin/sh
now=0
test ! -f "$FIXTURE_DIR/clock" || now=$(cat "$FIXTURE_DIR/clock")
if test "$now" -lt 12; then printf partial > "$4"; exit 1; fi
cp "$FIXTURE_DIR/config" "$4"
SH
    chmod 0755, "$root/bin/fetch";
    is((run_runtime($root, 'XCAT_BOOT_NETWORK_BASE64=present; xcat_fetch_config http://192.0.2.1/config'))[0],
        0, 'configuration download waits for a delayed virtual network');
    is(read_file("$root/work/config"), read_file("$root/config"), 'retry returns the complete configuration');
    unlink("$root/clock") or croak $!;
    isnt((run_runtime($root, 'XCAT_BOOT_NETWORK_BASE64=; xcat_fetch_config http://192.0.2.1/config'))[0],
        0, 'legacy physical networking retains its single download attempt');
    write_file("$root/bin/fetch", "#!/bin/sh\nprintf partial > \"\$4\"\nexit 1\n");
    isnt((run_runtime($root, 'XCAT_BOOT_NETWORK_BASE64=present; xcat_fetch_config http://192.0.2.1/config'))[0],
        0, 'an unavailable virtual network reaches a bounded failure');
    ok(!-e "$root/work/config", 'a failed download leaves no partial configuration');
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
    isnt((run_runtime($root, 'xcat_find_interface ""'))[0], 0, 'an absent boot MAC cannot select loopback');
}

{
    my $root = fixture();
    write_file("$root/nc-busy", '4');
    is((run_runtime($root, 'xcat_read_config "$1" && xcat_status complete'))[0], 0,
        'completion survives more than three busy controller responses');
    is(read_file("$root/nc-count"), "5\n", 'completion retries until the matching acknowledgment');
    like(read_file("$root/events"), qr/nc -w 65 /, 'the client allows the full controller command deadline');
    write_file("$root/reject-booted", '');
    isnt((run_runtime($root, 'xcat_read_config "$1" && xcat_status booted'))[0], 0,
        'an unavailable controller eventually fails without an acknowledgment');
    is(read_file("$root/clock"), "920\n", 'status retries stop after fifteen minutes');
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

sub pkgbase_configuration {
    my $bytes = configuration();
    $bytes =~ s/^format=xcat-freebsd-install-1$/format=xcat-freebsd-install-2/mx;
    $bytes =~ s/^(?:dist_url|base_sha256|kernel_sha256)=[^\n]*\n//gmx;
    return $bytes . "install_url=http://192.0.2.1/install\npackage_plan_sha256=" . ('3' x 64)
      . "\nboot_media_sha256=" . ('4' x 64) . "\nruntime_sha256=" . ('5' x 64) . "\n";
}

sub config_value {
    my ($bytes, $field, $value) = @_;
    my $changed = $bytes =~ s/^\Q$field\E=[^\n]*\n/$field=$value\n/mx;
    croak "Fixture field is absent: $field" unless $changed == 1;
    return $bytes;
}

sub parse_bytes {
    my $bytes = shift;
    my $root = fixture();
    write_file("$root/config", $bytes);
    return run_runtime($root, 'xcat_read_config "$1"');
}

sub config_roster_cases {
    my @common = qw(format release node generation master port mac ipv4 netmask gateway hostname
        target_disk target_disk_ident filesystem swap_size authorized_key_base64 nameservers);
    for my $case (
        ['legacy', configuration(), [qw(dist_url base_sha256 kernel_sha256)]],
        ['pkgbase', pkgbase_configuration(), [qw(install_url package_plan_sha256 boot_media_sha256 runtime_sha256)]],
    ) {
        my ($label, $bytes, $specific) = @$case;
        is((parse_bytes($bytes))[0], 0, "$label complete roster is accepted");
        for my $field (@common, @$specific) {
            my $missing = $bytes;
            $missing =~ s/^\Q$field\E=[^\n]*\n//mx;
            my ($status) = parse_bytes($missing);
            if ($label eq 'legacy' && ($field eq 'gateway' || $field eq 'nameservers')) {
                is($status, 0, "legacy $field remains optional");
            } else {
                isnt($status, 0, "$label rejects absent $field");
            }
        }
    }
    for my $field (qw(dist_url base_sha256 kernel_sha256)) {
        isnt((parse_bytes(pkgbase_configuration() . "$field=\n"))[0], 0,
            "pkgbase rejects an empty legacy $field field");
    }
    for my $field (qw(install_url package_plan_sha256 boot_media_sha256 runtime_sha256)) {
        isnt((parse_bytes(configuration() . "$field=\n"))[0], 0,
            "legacy rejects an empty pkgbase $field field");
    }
    for my $field (qw(package_plan_sha256 boot_media_sha256 runtime_sha256)) {
        for my $bad ('', 'a' x 63, 'A' x 64, 'a' x 65) {
            isnt((parse_bytes(config_value(pkgbase_configuration(), $field, $bad)))[0], 0,
                "pkgbase rejects a malformed $field");
        }
        isnt((parse_bytes(pkgbase_configuration() . "$field=" . ('3' x 64) . "\n"))[0], 0,
            "pkgbase rejects duplicate $field");
    }
    isnt((parse_bytes(pkgbase_configuration() . "unknown=value\n"))[0], 0, 'pkgbase rejects an unknown field');
    for my $url ('', 'file:///install', 'http://192.0.2.1/install/../private') {
        isnt((parse_bytes(config_value(pkgbase_configuration(), 'install_url', $url)))[0], 0,
            'pkgbase reader rejects an invalid installation URL');
    }
    for my $field (qw(node hostname)) {
        is((parse_bytes(config_value(pkgbase_configuration(), $field, 'a' x 247)))[0], 0,
            "pkgbase accepts a 247-character $field");
        isnt((parse_bytes(config_value(pkgbase_configuration(), $field, 'a' x 248)))[0], 0,
            "pkgbase rejects a 248-character $field");
    }
    return;
}

sub config_reset_cases {
    my $root = fixture();
    write_file("$root/pkgbase-config", pkgbase_configuration());
    my ($status, $output) = run_runtime($root, <<'SEQUENCE', "$root/pkgbase-config");
xcat_read_config "$1" || exit
printf 'legacy|%s|%s|%s|%s\n' "$XCAT_INSTALL_URL" "$XCAT_PACKAGE_PLAN_SHA256" "$XCAT_BOOT_MEDIA_SHA256" "$XCAT_RUNTIME_SHA256"
xcat_read_config "$2" || exit
printf 'pkgbase|%s|%s|%s|%s\n' "$XCAT_PACKAGE_PLAN_SHA256" "$XCAT_DIST_URL" "$XCAT_BASE_SHA256" "$XCAT_KERNEL_SHA256"
xcat_read_config "$1" || exit
printf 'legacy-again|%s|%s|%s|%s\n' "$XCAT_INSTALL_URL" "$XCAT_PACKAGE_PLAN_SHA256" "$XCAT_BOOT_MEDIA_SHA256" "$XCAT_RUNTIME_SHA256"
SEQUENCE
    is($status, 0, 'one shell reads legacy, pkgbase and legacy configurations');
    is($output, "legacy||||\npkgbase|" . ('3' x 64) . "|||\nlegacy-again||||\n",
        'each read clears the fields owned by the other configuration version');
    return;
}

sub config_byte_cases {
    for my $case (['legacy', configuration()], ['pkgbase', pkgbase_configuration()]) {
        my ($label, $bytes) = @$case;
        my $small = config_value($bytes, 'authorized_key_base64', 'A');
        my $key_size = 32768 - length($small) + 1;
        my $exact = config_value($small, 'authorized_key_base64', 'A' x $key_size);
        is(length($exact), 32768, "$label fixture is exactly 32768 bytes");
        is((parse_bytes($exact))[0], 0, "$label accepts the exact byte limit");
        my $large = config_value($small, 'authorized_key_base64', 'A' x ($key_size + 1));
        isnt((parse_bytes($large))[0], 0, "$label rejects 32769 bytes");
    }
    my $legacy = configuration();
    chop($legacy);
    is((parse_bytes("\n# retained legacy comment\n" . $legacy))[0], 0,
        'legacy accepts blank lines, comments and an unterminated final record');
    my $v2 = pkgbase_configuration();
    for my $case (
        ['missing final LF', substr($v2, 0, -1)],
        ['blank line', "\n$v2"],
        ['comment line', "# not a v2 record\n$v2"],
        ['NUL inside a valid node name', config_value($v2, 'node', "node\0" . '01')],
        ['non-ASCII node name', config_value($v2, 'node', "node\xc3\xa9")],
        ['control byte', config_value($v2, 'target_disk_ident', "XCAT\tTEST")],
        ['carriage return', config_value($v2, 'target_disk_ident', "XCAT_TEST_DISK\r")],
    ) {
        isnt((parse_bytes($case->[1]))[0], 0, "pkgbase rejects $case->[0]");
    }
    return;
}

sub pkgbase_install_refusal {
    my $root = fixture();
    write_file("$root/config", pkgbase_configuration());
    my ($status, $output) = run_runtime($root,
        'xcat_read_config "$1" || exit 91; printf "parsed-pkgbase\n"; xcat_install_system "$2"',
        "$directory/installerconfig.tmpl");
    isnt($status, 0, 'pkgbase installation remains unavailable');
    like($output, qr/^parsed-pkgbase\n/mx, 'a valid parsed configuration reaches the installation refusal');
    like($output, qr/Pkgbase[ ]installation[ ]runtime[ ]is[ ]not[ ]available/x,
        'the runtime reports the missing pkgbase adapter');
    is(read_file("$root/events"), '', 'pkgbase refusal invokes no fixture command');
    ok(!-e "$root/work/installerconfig", 'pkgbase refusal creates no installer script');
    ok(!-e "$root/work/dist", 'pkgbase refusal stages no distribution payload');
    return;
}

subtest 'configuration version rosters' => \&config_roster_cases;
subtest 'configuration reads clear version-specific fields' => \&config_reset_cases;
subtest 'configuration byte and line bounds' => \&config_byte_cases;
subtest 'parsed pkgbase configuration cannot start installation' => \&pkgbase_install_refusal;
subtest 'pkgbase begin reports its resolved primary members' => sub {
    my $root = fixture();
    write_file("$root/config", pkgbase_configuration());
    write_file("$root/bin/nc", <<'SHELL');
#!/bin/sh
read -r protocol generation attempt phase members
printf '%s|%s|%s\n' "$protocol" "$phase" "$members" >> "$FIXTURE_DIR/status-wire"
printf 'ready\n%s %s %s ok\n' "$protocol" "$generation" "$phase"
SHELL
    chmod 0755, "$root/bin/nc";
    my ($status) = run_runtime($root, 'xcat_read_config "$1" && xcat_status begin && xcat_status complete');
    is($status, 0, 'native status exchange accepts disk-aware authorization');
    is(read_file("$root/status-wire"), "freebsd-install-v2|begin|ada0\@XCAT_TEST_DISK\nfreebsd-install-v1|complete|\n",
        'only begin carries the concrete selected OS identity');
    write_file("$root/status-wire", '');
    ($status) = run_runtime($root, 'xcat_read_config "$1" || exit; XCAT_FORMAT=xcat-freebsd-install-5; '
        . 'XCAT_FILESYSTEM=zfs; XCAT_SWAP_MODE=none; XCAT_SWAP_SIZE=0; XCAT_ZFS_TOPOLOGY=raid10; '
        . 'XCAT_ZFS_VDEVS="ada0@OS0,ada1@OS1;ada2@OS2,ada3@OS3"; xcat_status begin');
    is($status, 0, 'grouped native membership reaches authorization');
    is(read_file("$root/status-wire"), "freebsd-install-v2|begin|ada0\@OS0,ada1\@OS1;ada2\@OS2,ada3\@OS3\n",
        'wire preserves the original mirror groups');
};
done_testing;
