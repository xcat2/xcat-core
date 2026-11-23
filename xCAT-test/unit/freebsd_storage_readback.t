#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $directory = $ENV{XCAT_FREEBSD_INSTALLER_DIR} || "$FindBin::Bin/../../xCAT-server/share/xcat/install/freebsd";

sub read_file {
    my ($path) = @_;
    open(my $in, '<', $path) or die "$path: $!";
    local $/;
    my $bytes = <$in>;
    close($in) or die "$path: $!";
    return $bytes // '';
}

sub write_file {
    my ($path, $bytes) = @_;
    open(my $out, '>', $path) or die "$path: $!";
    print {$out} $bytes;
    close($out) or die "$path: $!";
}

my $root = tempdir(CLEANUP => 1);
make_path("$root/bin", "$root/work");
my $guard = read_file("$directory/xcat-storage");
my $functions = '';
# Execute the production readers without entering the destructive dispatcher.
for my $name (qw(storage_pool storage_table storage_labels)) {
    my ($body) = $guard =~ /^(\Q$name\E\(\)\n\{\n.*?^\}\n)/ms;
    die "Missing production reader $name" unless defined($body);
    $functions .= $body;
}
write_file("$root/readers.sh", $functions);

my %commands = (
    zpool => 'case "$*" in
        "list -H -o name,guid") cat "$FIXTURE_DIR/pools" ;;
        "status -LP zroot") cat "$FIXTURE_DIR/status" ;;
        *) exit 90 ;;
        esac',
    zfs => 'case "$*" in
        "get -Hp -o value special_small_blocks zroot") printf "4096\\n" ;;
        "get -H -o value compression zroot") printf "lz4\\n" ;;
        *) exit 90 ;;
        esac',
    zdb => 'case "$*" in
        "-C zroot") printf "    ashift: 12\\n" ;;
        "-l /dev/ada7p1") cat "$FIXTURE_DIR/cache-label" ;;
        *) exit 90 ;;
        esac',
    gpart => 'test "$*" = "list -a" || exit 90; cat "$FIXTURE_DIR/partitions"',
    stat => 'test "$*" = "-f %HT:%r /dev/ada2p1" || exit 90; printf "Character Device:302\\n"',
);
for my $name (keys %commands) {
    write_file("$root/bin/$name", "#!/bin/sh\nprintf '%s %s\\n' '$name' \"\$*\" >> \"\$FIXTURE_DIR/events\"\n$commands{$name}\n");
    chmod 0755, "$root/bin/$name" or die $!;
}

my $generation = 'c' x 32;
my $guid = '18446744073709551610';
write_file("$root/work/guid", "$guid\n");
write_file("$root/pools", "zroot\t$guid\n");
my $status = <<"STATUS";
  pool: zroot
 state: ONLINE
config:

        NAME                                           STATE     READ WRITE CKSUM
        zroot                                          ONLINE       0     0     0
          mirror-0                                     ONLINE       0     0     0
            /dev/gpt/z${generation}0                   ONLINE       0     0     0
            /dev/gpt/z${generation}1                   ONLINE       0     0     0
        special
          mirror-1                                     ONLINE       0     0     0
            /dev/gpt/a${generation}0                   ONLINE       0     0     0
            /dev/gpt/a${generation}1                   ONLINE       0     0     0
        logs
          /dev/gpt/a${generation}2                     ONLINE       0     0     0
          mirror-3                                     ONLINE       0     0     0
            /dev/gpt/a${generation}3                   ONLINE       0     0     0
            /dev/gpt/a${generation}4                   ONLINE       0     0     0
        cache
          /dev/gpt/a${generation}5                     ONLINE       0     0     0

errors: No known data errors
STATUS
my $table = <<'TABLE';
Geom name: ada2
scheme: GPT
state: OK
modified: false
first: 34
last: 16777182
entries: 128
Providers:
1. Name: ada2p1
   Mediasize: 8587837440
   Sectorsize: 512
   Mode: r1w1e2
   offset: 1048576
   index: 1
   type: freebsd-zfs
   label: special-a
   rawuuid: 12345678-1234-1234-1234-123456789012
Consumers:
1. Name: ada2
TABLE
my $cache = <<"CACHE";
LABEL 0
    version: 5000
    state: 4
    guid: 18331623171503817866
    ashift: 12
    path: '/dev/gpt/a${generation}5'
    labels = 0 1 2 3
L2ARC device header
    magic: 6504978260106102853
    version: 1
    pool_guid: $guid
    flags: 1
CACHE
write_file("$root/status", $status);
write_file("$root/partitions", $table);
write_file("$root/cache-label", $cache);

sub run_reader {
    my ($name, @arguments) = @_;
    local %ENV = (%ENV, PATH => "$root/bin:$ENV{PATH}", FIXTURE_DIR => $root,
        storage_work => "$root/work", storage_guid => $guid, storage_phase => 'created',
        storage_boot => 'BIOS', storage_root_index => 2,
        storage_members => "ada0\tSERIAL0\t1\nada1\tSERIAL1\t1",
        storage_snapshot => "ada2\tSERIAL2\tspecial:1\t8589934592\t512\tr0w0e0\t102",
        storage_all_members => "ada7\tSERIAL7\tcache:1",
        XCAT_FORMAT => 'xcat-freebsd-install-6', XCAT_FILESYSTEM => 'zfs',
        XCAT_SWAP_SIZE => 0, XCAT_SWAP_MODE => 'none', XCAT_GENERATION => $generation,
        XCAT_ZFS_TOPOLOGY => 'mirror', XCAT_ZFS_VDEVS => 'ada0@SERIAL0,ada1@SERIAL1',
        XCAT_ZFS_SPECIAL_VDEVS => 'ada2@SERIAL2,ada3@SERIAL3',
        XCAT_ZFS_LOG_VDEVS => 'ada4@SERIAL4,ada5@SERIAL5;ada6@SERIAL6',
        XCAT_ZFS_CACHE_VDEVS => 'ada7@SERIAL7', XCAT_ZFS_SPECIAL_SMALL_BLOCKS => 4096,
        XCAT_ZFS_COMPRESSION => 'lz4', XCAT_ZFS_ASHIFT => 12);
    open(my $pipe, '-|', 'sh', '-c',
        'set -eu; . "$1"; . "$2"; shift 2; "$@" 2>"$FIXTURE_DIR/stderr"',
        'sh', "$directory/xcat-install-lib.sh", "$root/readers.sh", $name, @arguments) or die $!;
    local $/;
    my $output = <$pipe> // '';
    close($pipe);
    return ($? >> 8, $output, read_file("$root/stderr"));
}

subtest 'pool readback checks configured grouping and stable paths' => sub {
    my ($rc, $output, $error) = run_reader('storage_pool');
    is($rc, 0, 'the configured special mirror, singleton log, mirrored log and cache pass') or diag($error);
    for my $change ('missing special group', 'wrong group', 'raw path', 'wrong group member', 'I/O errors') {
        my $changed = $status;
        if ($change eq 'missing special group') {
            $changed =~ s/^[ ]{8}special\n//mx;
        } elsif ($change eq 'wrong group') {
            $changed =~ s/mirror-3/raidz1-3/x;
        } elsif ($change eq 'raw path') {
            $changed =~ s{\Q/dev/gpt/a${generation}3\E}{/dev/ada4p1}x;
        } elsif ($change eq 'wrong group member') {
            $changed =~ s{\Q/dev/gpt/a${generation}2\E}{/dev/gpt/a${generation}4}x;
        } else {
            $changed =~ s/ONLINE[ ]+0[ ]+0[ ]+0/ONLINE 0 1 0/x;
        }
        isnt($changed, $status, "$change fixture changes the producer output");
        write_file("$root/status", $changed);
        isnt((run_reader('storage_pool'))[0], 0, "$change is rejected after pool creation");
    }
    write_file("$root/status", $status);
};

subtest 'partition readback requires the stable-label open mode' => sub {
    my ($rc, $output, $error) = run_reader('storage_table', 1);
    is($rc, 0, 'the imported GPT-label provider is accepted') or diag($error);
    like($output, qr/^P\tada2\t1\tada2p1\tfreebsd-zfs\t/mx, 'the actual provider is returned');
    for my $mode ('r1w1e1', 'r0w0e0') {
        my $changed = $table;
        $changed =~ s/r1w1e2/$mode/x;
        write_file("$root/partitions", $changed);
        isnt((run_reader('storage_table', 1))[0], 0, "$mode cannot substitute for the GPT-label open mode");
    }
    write_file("$root/partitions", $table);
};

subtest 'cache readback checks ownership and all label copies' => sub {
    my ($rc, $output, $error) = run_reader('storage_labels', 0);
    is($rc, 0, 'the selected pool owns all four cache-label copies') or diag($error);
    is($output, "ada7\t$guid\t-\t18331623171503817866\n", 'readback returns the native cache vdev identity');
    for my $change ('foreign owner', 'missing copy', 'duplicate copy') {
        my $changed = $cache;
        if ($change eq 'foreign owner') {
            $changed =~ s/$guid/18446744073709551611/gx;
        } elsif ($change eq 'missing copy') {
            $changed =~ s/labels[ ]=[ ]0[ ]1[ ]2[ ]3/labels = 0 1 2/x;
        } else {
            $changed =~ s/labels[ ]=[ ]0[ ]1[ ]2[ ]3/labels = 0 1 2 2/x;
        }
        write_file("$root/cache-label", $changed);
        isnt((run_reader('storage_labels', 0))[0], 0, "$change cannot pass cache readback");
    }
};

unlike(read_file("$root/events"), qr/^(zpool[ ](create|destroy|remove|labelclear)|gpart[ ](create|destroy|add|modify))/mx,
    'all readback cases use query commands only');
done_testing();
