#!/usr/bin/env perl
use strict;
use warnings;

use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Copy qw(copy);
use Test::More;
use XCAT::Test::Chroot qw(stage_binary);

my $directory = $ENV{XCAT_FREEBSD_INSTALLER_DIR} || "$FindBin::Bin/../../xCAT-server/share/xcat/install/freebsd";
my $library = "$directory/xcat-install-lib.sh";

sub write_file {
    my ($path, $bytes) = @_;
    open(my $out, '>', $path) or die "$path: $!";
    print {$out} $bytes;
    close($out) or die "$path: $!";
}

sub read_file {
    my ($path) = @_;
    open(my $in, '<', $path) or die "$path: $!";
    local $/;
    my $bytes = <$in>;
    close($in) or die "$path: $!";
    return $bytes // '';
}

sub fixture {
    my ($count) = @_;
    $count ||= 3;
    my $root = tempdir(CLEANUP => 1);
    make_path("$root/bin", "$root/work", "$root/labels");
    my (@members, @expected, @disks, @graph);
    for my $index (0 .. $count) {
        my $name = "ada$index";
        push @disks, $name;
        push @members, "$name\@SERIAL$index" if $index < $count;
        push @expected, join("\t", $name, "SERIAL$index", 1, 8589934592, 512, 'r0w0e0', 100 + $index) . "\n"
            if $index < $count;
        write_file("$root/$name.geom", "Geom name: $name\nProviders:\n1. Name: $name\n" .
            "   Mediasize: 8589934592 (8G)\n   Sectorsize: 512\n   Mode: r0w0e0\n   ident: SERIAL$index\n\n");
        write_file("$root/$name.stat", 'Character Device:' . (100 + $index) . "\n");
        write_file("$root/$name.size", "8589934592\n");
        write_file("$root/$name.head", "\0" x 1048576);
        write_file("$root/$name.tail", "\0" x 1048576);
        push @graph, "0 DISK $name 8589934592 512 hd 16 sc 63\n" .
            "1 LABEL diskid/DISK-SERIAL$index 8589934592 512 i 0 o 0\n";
    }
    write_file("$root/disks", join(' ', @disks) . "\n");
    write_file("$root/graph", join('', @graph));
    write_file("$root/members", join(',', @members));
    write_file("$root/expected", join('', @expected));
    write_file("$root/pools", '');
    write_file("$root/geli", '');
    write_file("$root/partitions", '');
    my %commands = (
        geom => 'test "$1 $2" = "disk list" || exit 90
            count=0; test ! -f "$FIXTURE_DIR/geom-count" || count=$(cat "$FIXTURE_DIR/geom-count")
            count=$((count+1)); printf "%s\n" "$count" > "$FIXTURE_DIR/geom-count"
            for f in "$FIXTURE_DIR"/ada*.geom; do
                test -z "${3:-}" || test "$f" = "$FIXTURE_DIR/$3.geom" || continue
                if [ "$count" -gt 1 ] && [ -f "$f.changed" ]; then cat "$f.changed"; else cat "$f"; fi
            done',
        sysctl => 'case "$*" in
            "-n kern.disks") cat "$FIXTURE_DIR/disks" ;;
            "-n kern.geom.conftxt") cat "$FIXTURE_DIR/graph" ;;
            "-n vm.swap_total") printf "0\n" ;;
            "-n hw.physmem") printf "8589934592\n" ;;
            *) exit 90 ;;
            esac',
        stat => 'test "$1" = -f && test "$2" = "%HT:%r" || exit 90
            cat "$FIXTURE_DIR/${3##*/}.stat"',
        zpool => 'test "$*" = "list -H -o name" || exit 90; cat "$FIXTURE_DIR/pools"',
        geli => 'test "$*" = "status -s" || exit 90; cat "$FIXTURE_DIR/geli"',
        gpart => 'test "$*" = list || exit 90; cat "$FIXTURE_DIR/partitions"',
        zdb => 'case "$1" in -l|-ll) ;; *) exit 90 ;; esac
            name=${2##*/}; test ! -f "$FIXTURE_DIR/zdb-status-$name" || exit "$(cat "$FIXTURE_DIR/zdb-status-$name")"
            test -f "$FIXTURE_DIR/labels/$name" || exit 2; cat "$FIXTURE_DIR/labels/$name"',
        sha256 => 'test "$*" = -q || exit 90; openssl dgst -sha256 | awk \'{print $NF}\'',
        fstyp => 'test "$1" = -u || exit 90
            name=${2##*/}
            if [ -f "$FIXTURE_DIR/fstyp-$name" ]; then
                cat "$FIXTURE_DIR/fstyp-$name"; exit "$(cat "$FIXTURE_DIR/fstyp-status-$name")"
            fi
            printf "fstyp: /dev/%s: filesystem not recognized\n" "$name" >&2; exit 1',
        dd => 'src= dst= block= skip=0 count=
            for arg do
                case "$arg" in if=*) src=${arg#if=} ;; of=*) dst=${arg#of=} ;; bs=*) block=${arg#bs=} ;;
                    skip=*) skip=${arg#skip=} ;; count=*) count=${arg#count=} ;; *) exit 90 ;; esac
            done
            case "$dst" in "$FIXTURE_DIR"/work/storage.*/zero|"$FIXTURE_DIR"/work/storage.*/window|\
                "$FIXTURE_DIR"/work/pkgbase-work/storage.*/zero|"$FIXTURE_DIR"/work/pkgbase-work/storage.*/window) ;; *) exit 90 ;; esac
            if [ "$src" = /dev/zero ]; then
                test "$block" = 1048576 && test "$count" = 1 || exit 90
                cp "$FIXTURE_DIR/ada0.head.zero" "$dst"; exit
            fi
            name=${src#/dev/}; region=tail; test "$skip" != 0 || region=head
            test "$((block*count))" -eq 1048576 || exit 90
            if [ "$region" = tail ]; then
                size=$(cat "$FIXTURE_DIR/$name.size") || exit 90
                test "$((block*skip))" -eq "$((size-1048576))" || exit 90
            fi
            test ! -f "$FIXTURE_DIR/dd-fail-$name-$region" || exit 1
            cp "$FIXTURE_DIR/$name.$region" "$dst"',
    );
    write_file("$root/ada0.head.zero", "\0" x 1048576);
    for my $name (keys %commands) {
        write_file("$root/bin/$name", "#!/bin/sh\nprintf '%s %s\\n' '$name' \"\$*\" >> \"\$FIXTURE_DIR/events\"\n" .
            "test ! -f \"\$FIXTURE_DIR/fail-$name\" || exit 1\n$commands{$name}\n");
        chmod 0755, "$root/bin/$name" or die $!;
    }
    return $root;
}

sub run_preflight {
    my ($root, $overrides, $operation) = @_;
    $overrides ||= {};
    $operation ||= 'xcat_check_zfs_initial';
    local %ENV = (%ENV, PATH => "$root/bin:$ENV{PATH}", FIXTURE_DIR => $root,
        XCAT_WORK => "$root/work", XCAT_FORMAT => 'xcat-freebsd-install-4',
        XCAT_FILESYSTEM => 'zfs', XCAT_ZFS_TOPOLOGY => 'mirror',
        XCAT_ZFS_VDEVS => read_file("$root/members"), XCAT_SWAP_SIZE => '0', XCAT_SWAP_MODE => 'none', %$overrides);
    my %before = map { $_ => sha256_hex(read_file($_)) } glob("$root/ada*.head $root/ada*.tail");
    open(my $pipe, '-|', 'sh', '-c', '. "$1"; if [ "$2" = xcat_erase_os_disks ]; then "$2" "$FIXTURE_DIR/before.snapshot";
        elif [ "$2" = xcat_resolve_disks ]; then
            xcat_read_config "$XCAT_WORK/config" && "$2" && cat "$XCAT_WORK/config";
        else "$2"; fi 2>"$FIXTURE_DIR/stderr"', 'sh', $library, $operation) or die $!;
    local $/;
    my $output = <$pipe> // '';
    close($pipe);
    my $status = $? >> 8;
    my %after = map { $_ => sha256_hex(read_file($_)) } keys %before;
    is_deeply(\%after, \%before, 'all selected and unrelated disk bytes are unchanged');
    return ($status, $output, read_file("$root/stderr"));
}

sub reject {
    my ($root, $message, $reason) = @_;
    my ($status, $output, $error) = run_preflight($root);
    isnt($status, 0, $message);
    is($output, '', 'rejection publishes no partial disk snapshot');
    like($error, $reason, 'rejection identifies its cause') if $reason;
}

subtest 'ordered complete initial disk set' => sub {
    for my $count (2, 3, 16) {
        my $root = fixture($count);
        my ($status, $output, $error) = run_preflight($root);
        is($status, 0, "$count members pass native preflight");
        is($output, read_file("$root/expected"), 'snapshot preserves exact identities, geometry and ordering');
        is($error, '', 'accepted preflight has no diagnostic');
    }
    my $root = fixture();
    my $geometry = read_file("$root/ada1.geom");
    $geometry =~ s/Sectorsize: 512/Sectorsize: 4096/;
    write_file("$root/ada1.geom", $geometry);
    my $graph = read_file("$root/graph");
    $graph =~ s{((?:DISK ada1|LABEL diskid/DISK-SERIAL1) 8589934592) 512}{$1 4096}g;
    write_file("$root/graph", $graph);
    my $expected = read_file("$root/expected");
    $expected =~ s/ada1\tSERIAL1\t1\t8589934592\t512/ada1\tSERIAL1\t1\t8589934592\t4096/;
    my ($status, $output, $error) = run_preflight($root);
    is($status, 0, '4096-byte sectors use the declared geometry');
    is($output, $expected, 'mixed supported sector sizes remain explicit in the snapshot');
    is($error, '', 'supported sector sizes have no diagnostic');
};

subtest 'identity, capacity and active-use failures at every member' => sub {
    for my $index (0 .. 2) {
        for my $case (
            ['wrong identity', "ident: SERIAL$index", 'ident: REPLACED'],
            ['insufficient capacity', '8589934592', '4294966784'],
            ['active consumer', 'Mode: r0w0e0', 'Mode: r1w0e0'],
            ['unsupported sector', 'Sectorsize: 512', 'Sectorsize: 520'],
        ) {
            my $root = fixture();
            my $data = read_file("$root/ada$index.geom");
            $data =~ s/\Q$case->[1]\E/$case->[2]/ or die 'fixture replacement failed';
            write_file("$root/ada$index.geom", $data);
            my $reason = $case->[0] eq 'active consumer' ? qr/disk is in use/ : qr/Cannot identify the complete ZFS disk set/;
            reject($root, "$case->[0] on member $index fails", $reason);
            my $events = -e "$root/events" ? read_file("$root/events") : '';
            unlike($events, qr/^dd /m, 'the complete set is checked before disk reads');
        }
    }
};

subtest 'ambiguous and incomplete inventories' => sub {
    for my $case (
        ['disks', "ada0 ada1 ada3\n"], ['disks', "ada0 ada1 ada2 ada2 ada3\n"],
        ['ada1.stat', "Character Device:100\n"], ['ada1.stat', "Symbolic Link:101\n"],
        ['ada1.stat', "Character Device:101\nCharacter Device:102\n"],
        ['ada1.geom', 'unrecognized inventory'],
    ) {
        my $root = fixture();
        write_file("$root/$case->[0]", $case->[1]);
        reject($root, "ambiguous $case->[0] fails");
    }
    for my $change (
        ['ada1', 'ident: SERIAL1', 'ident:'],
        ['ada3', 'ident: SERIAL3', 'ident: SERIAL1'],
        ['ada1', '1. Name: ada1', '1. Name: ada2'],
        ['ada1', 'Sectorsize: 512', "Sectorsize: 512\nSectorsize: 512"],
        ['ada1', '8589934592', '8589934593'],
        ['ada1', '8589934592', '9007199254740992'],
    ) {
        my $root = fixture();
        my $data = read_file("$root/$change->[0].geom");
        $data =~ s/\Q$change->[1]\E/$change->[2]/ or die 'fixture replacement failed';
        write_file("$root/$change->[0].geom", $data);
        reject($root, "ambiguous $change->[1] fails");
    }
};

subtest 'provider and metadata rejection' => sub {
    for my $entry (
        '1 PART ada1p1 8588886016 512 i 1 o 1048576 ty freebsd-zfs',
        '1 MIRROR mirror/root 8589934080 512',
        '1 ELI ada1.eli 8589934080 512',
        '1 LABEL ufs/oldroot 8589934592 512 i 0 o 0',
        '1 LABEL diskid/DISK-WRONG 8589934592 512 i 0 o 0',
        '2 LABEL diskid/DISK-SERIAL1 8589934592 512 i 0 o 0',
    ) {
        my $root = fixture();
        my $graph = read_file("$root/graph");
        $graph =~ s{1 LABEL diskid/DISK-SERIAL1[^\n]*}{$entry};
        write_file("$root/graph", $graph);
        reject($root, 'an existing provider is rejected', qr/existing layout or provider/);
    }
    for my $case (['pools', "otherpool\n"], ['geli', "ada3.eli ACTIVE ada3\n"],
        ['labels/ada1', "pool_guid: 123\nname: 'otherpool'\n"],
        ['labels/ada3', "pool_guid: 456\nname: 'zroot'\n"]) {
        my $root = fixture();
        write_file("$root/$case->[0]", $case->[1]);
        reject($root, "existing $case->[0] prevents installation");
    }
    my $root = fixture();
    write_file("$root/labels/ada3", "pool_guid: 456\nname: 'unrelated'\n");
    is((run_preflight($root))[0], 0, 'an unrelated exported pool is preserved and tolerated');
};

subtest 'boundary reads and filesystem inspection fail closed' => sub {
    for my $index (0 .. 2) {
        for my $region (qw(head tail)) {
            for my $data ("X" . ("\0" x 1048575), "\0" x 1048575) {
                my $root = fixture();
                write_file("$root/ada$index.$region", $data);
                reject($root, "nonzero or short $region on member $index fails", qr/metadata or an unreadable boundary/);
            }
            my $root = fixture();
            write_file("$root/dd-fail-ada$index-$region", '');
            reject($root, "failed $region read on member $index fails", qr/metadata or an unreadable boundary/);
        }
    }
    for my $case (
        [0, "ufs\n"], [1, "fstyp: fread: Input/output error\nfstyp: /dev/ada1: filesystem not recognized\n"],
        [1, "fstyp: /dev/ada1: Permission denied\n"], [2, "fstyp: /dev/ada1: filesystem not recognized\n"],
    ) {
        my $root = fixture();
        write_file("$root/fstyp-ada1", $case->[1]);
        write_file("$root/fstyp-status-ada1", "$case->[0]\n");
        reject($root, 'filesystem or inspection failure is rejected', qr/filesystem or cannot be inspected/);
    }
};

subtest 'failed observations and changing membership' => sub {
    for my $name (qw(geom sysctl stat zpool geli gpart zdb fstyp dd)) {
        my $root = fixture();
        write_file("$root/fail-$name", '');
        reject($root, "failed $name observation rejects the request");
    }
    my $root = fixture();
    my $data = read_file("$root/ada2.geom");
    $data =~ s/Mode: r0w0e0/Mode: r1w0e0/;
    write_file("$root/ada2.geom.changed", $data);
    reject($root, 'a change during preflight fails', qr/disk set changed during preflight/);
};

subtest 'whole OS disk reinstall preserves separate identities and rejects foreign storage' => sub {
    my %policy = (XCAT_FORMAT => 'xcat-freebsd-install-5', XCAT_DISK_ACTION => 'erase',
        XCAT_ZFS_COMPRESSION => 'lz4', XCAT_ZFS_ASHIFT => '12', XCAT_PRESERVE_DISKS => 'ada3@SERIAL3');
    my $root = fixture();
    write_file("$root/labels/ada0", "pool_guid: 123\nname: 'zroot'\n");
    write_file("$root/labels/ada3", "pool_guid: 456\nname: 'tank'\n");
    my ($status, $output, $error) = run_preflight($root, \%policy, 'xcat_check_zfs_reinstall');
    is($status, 0, 'explicit OS erase accepts OS labels and separate exported data') or diag($error);
    like($output, qr/preserved\nada3\tSERIAL3\t/x, 'the preserved identity is bound into the prewrite snapshot');
    like($output, qr/labels\nada0[ ][0-9a-f]{64}\n/x, 'old OS metadata is bound before any write');
    for my $bad ([XCAT_DISK_ACTION => 'empty'], [XCAT_PRESERVE_DISKS => 'ada0@SERIAL0'],
        [XCAT_PRESERVE_DISKS => 'ada3@WRONG'], [XCAT_PRESERVE_DISKS => 'ada4@MISSING']) {
        isnt((run_preflight($root, { %policy, @$bad }, 'xcat_check_zfs_reinstall'))[0], 0,
            "invalid $bad->[0] prevents OS erase");
    }
    write_file("$root/labels/ada3", "pool_guid: 123\nname: 'zroot'\n");
    isnt((run_preflight($root, \%policy, 'xcat_check_zfs_reinstall'))[0], 0,
        'an OS pool member outside the selected disks prevents partial erase');
    write_file("$root/labels/ada3", "pool_guid: 456\nname: 'tank'\n");
    write_file("$root/labels/ada0", "pool_guid: 456\nname: 'tank'\n");
    isnt((run_preflight($root, \%policy, 'xcat_check_zfs_reinstall'))[0], 0,
        'a data pool on a selected disk is not mistaken for the OS');
    write_file("$root/labels/ada0", "pool_guid: 123\nname: 'zroot'\n");
    my $graph = read_file("$root/graph");
    $graph =~ s{1[ ]LABEL[ ]diskid/DISK-SERIAL0[^\n]*}{1 ELI ada0.eli 8589934080 512}x;
    write_file("$root/graph", $graph);
    isnt((run_preflight($root, \%policy, 'xcat_check_zfs_reinstall'))[0], 0,
        'an unsupported active provider cannot be erased as a plain OS disk');
    done_testing();
};

sub efi_label_guard_case {
    subtest 'native FAT labels are confined to EFI partitions' => sub {
        my %policy = (XCAT_FORMAT => 'xcat-freebsd-install-5', XCAT_DISK_ACTION => 'erase',
            XCAT_ZFS_COMPRESSION => 'lz4', XCAT_ZFS_ASHIFT => '12', XCAT_PRESERVE_DISKS => 'ada3@SERIAL3');
        my $root = fixture();
        # Native FreeBSD 15.1 PART/LABEL rows, with the fixture provider renamed.
        my $native = "0 DISK ada0 8589934592 512 hd 16 sc 63\n"
            . "1 PART ada0p1 67108864 512 i 1 o 20480 ty efi xs GPT xt c12a7328-f81f-11d2-ba4b-00a0c93ec93b\n"
            . "2 LABEL msdosfs/XCAT_EFI 67108864 512 i 0 o 0\n";
        my $graph = read_file("$root/graph");
        $graph =~ s/0[ ]DISK[ ]ada0[^\n]*\n1[ ]LABEL[^\n]*\n/$native/x;
        write_file("$root/partitions", "Geom name: ada0\nscheme: GPT\nstate: OK\nmodified: false\nMode: r0w0e0\n");
        write_file("$root/graph", $graph);
        my ($status, $output, $error) = run_preflight($root, \%policy, 'xcat_check_zfs_reinstall');
        is($status, 0, 'a native FAT label below an EFI partition permits whole-disk reinstall') or diag($error);
        like($output, qr/preserved\nada3\tSERIAL3\t/x, 'the separate data drive remains pinned');
        for my $change (
            [qr/ty[ ]efi/x, 'ty freebsd-zfs'],
            [qr{msdosfs/XCAT_EFI}x, 'mirror/userdata'],
            [qr/2[ ]LABEL/x, '2 ELI'],
        ) {
            my $invalid = $graph;
            $invalid =~ s/$change->[0]/$change->[1]/x;
            write_file("$root/graph", $invalid);
            isnt((run_preflight($root, \%policy, 'xcat_check_zfs_reinstall'))[0], 0,
                'a FAT label under another type or an unsupported consumer cannot authorize erase');
        }
    };
    return;
}

sub reinstall_guard_cases {
    subtest 'native GPT UFS labels are confined to their filesystem partition' => sub {
        my %policy = (XCAT_FORMAT => 'xcat-freebsd-install-5', XCAT_DISK_ACTION => 'erase',
            XCAT_ZFS_COMPRESSION => 'lz4', XCAT_ZFS_ASHIFT => '12', XCAT_PRESERVE_DISKS => 'ada3@SERIAL3');
        my $root = fixture();
        my $geometry = read_file("$root/ada0.geom");
        $geometry =~ s/8589934592/17179869184/gx;
        write_file("$root/ada0.geom", $geometry);
        # FreeBSD 15 native conftxt, with only the disk and UFS label names replaced.
        my $native = "0 DISK ada0 17179869184 512 hd 16 sc 63\n"
            . "1 PART ada0p3 16642433024 512 i 3 o 537415680 ty freebsd-ufs xs GPT xt 516e7cb6-6ecf-11d6-8ff8-00022d09712b\n"
            . "2 LABEL ufsid/0123456789abcdef 16642433024 512 i 0 o 0\n"
            . "1 PART ada0p2 524288 512 i 2 o 536891392 ty freebsd-boot xs GPT xt 83bd6b9d-7f41-11dc-be0b-001560b84f0f\n"
            . "1 PART ada0p1 536870912 512 i 1 o 20480 ty freebsd-swap xs GPT xt 516e7cb5-6ecf-11d6-8ff8-00022d09712b\n";
        my $graph = read_file("$root/graph");
        $graph =~ s/0[ ]DISK[ ]ada0[^\n]*\n1[ ]LABEL[^\n]*\n/$native/x;
        write_file("$root/partitions", "Geom name: ada0\nscheme: GPT\nstate: OK\nmodified: false\nMode: r0w0e0\n");
        for my $label ('ufsid/0123456789abcdef', 'ufs/oldroot') {
            my $accepted = $graph;
            $accepted =~ s{ufsid/0123456789abcdef}{$label}x;
            write_file("$root/graph", $accepted);
            my ($status, $output, $error) = run_preflight($root, \%policy, 'xcat_check_zfs_reinstall');
            is($status, 0, "$label below a GPT UFS partition permits whole-disk reinstall") or diag($error);
            like($output, qr/preserved\nada3\tSERIAL3\t/x, 'the separate disk remains pinned');
        }
        for my $change (
            [qr/freebsd-ufs/x, 'freebsd-zfs'],
            [qr{ufsid/0123456789abcdef}x, 'mirror/userdata'],
            [qr/2[ ]LABEL/x, '2 ELI'],
        ) {
            my $invalid = $graph;
            $invalid =~ s/$change->[0]/$change->[1]/x;
            write_file("$root/graph", $invalid);
            isnt((run_preflight($root, \%policy, 'xcat_check_zfs_reinstall'))[0], 0,
                'a label on another partition type or an unsupported consumer prevents erase');
        }
    };

    subtest 'erase rechecks the accepted snapshot before any destructive command' => sub {
        my %policy = (XCAT_FORMAT => 'xcat-freebsd-install-5', XCAT_DISK_ACTION => 'erase',
            XCAT_ZFS_COMPRESSION => 'lz4', XCAT_ZFS_ASHIFT => '12', XCAT_PRESERVE_DISKS => 'ada3@SERIAL3');
        for my $change ('saved snapshot', 'preserved identity', 'OS labels') {
            my $root = fixture();
            my ($status, $snapshot, $error) = run_preflight($root, \%policy, 'xcat_check_zfs_reinstall');
            is($status, 0, 'the controller can acknowledge the initial snapshot') or diag($error);
            write_file("$root/before.snapshot", $snapshot);
            if ($change eq 'saved snapshot') {
                write_file("$root/before.snapshot", $snapshot . "changed\n");
            } elsif ($change eq 'preserved identity') {
                my $disk = read_file("$root/ada3.geom");
                $disk =~ s/SERIAL3/REPLACED/x;
                write_file("$root/ada3.geom", $disk);
            } else {
                write_file("$root/labels/ada0", "pool_guid: 123\nname: 'zroot'\n");
            }
            write_file("$root/events", '');
            isnt((run_preflight($root, \%policy, 'xcat_erase_os_disks'))[0], 0, "$change invalidates erase");
            unlike(read_file("$root/events"), qr/^(zpool[ ]labelclear|gpart[ ]destroy|dd[ ].*of=\/dev\/)/mx,
                'the failed guard invokes no label clearing, partition destruction or disk write');
        }
    };
    return;
}
reinstall_guard_cases();
efi_label_guard_case();

subtest 'OS auxiliary members and L2ARC ownership are checked before erase' => sub {
    my %policy = (XCAT_FORMAT => 'xcat-freebsd-install-6', XCAT_DISK_ACTION => 'erase',
        XCAT_GENERATION => ('c' x 32),
        XCAT_ZFS_COMPRESSION => 'lz4', XCAT_ZFS_ASHIFT => '12', XCAT_PRESERVE_DISKS => 'ada7@SERIAL7',
        XCAT_ZFS_VDEVS => 'ada0@SERIAL0,ada1@SERIAL1',
        XCAT_ZFS_SPECIAL_VDEVS => 'ada2@SERIAL2,ada3@SERIAL3',
        XCAT_ZFS_LOG_VDEVS => 'ada4@SERIAL4,ada5@SERIAL5',
        XCAT_ZFS_CACHE_VDEVS => 'ada6@SERIAL6', XCAT_ZFS_SPECIAL_SMALL_BLOCKS => '0');
    my $pool_guid = '18446744073709551610';
    my $cache_label = "LABEL 0\n    version: 5000\n    state: 4\n    guid: 18331623171503817866\n"
        . "    ashift: 12\n    path: '/dev/ada6'\n    labels = 0 1 2 3\n"
        . "L2ARC device header\n    magic: 6504978260106102853\n    version: 1\n"
        . "    pool_guid: $pool_guid\n    flags: 1\n";
    my $make = sub {
        my $root = fixture(7);
        for my $i (0 .. 5) {
            write_file("$root/labels/ada$i", "LABEL 0\n    state: 1\n    name: 'zroot'\n    pool_guid: $pool_guid\n");
        }
        write_file("$root/labels/ada6", $cache_label);
        write_file("$root/labels/ada7", "LABEL 0\n    state: 1\n    name: 'tank'\n    pool_guid: 18446744073709551611\n");
        return $root;
    };
    my $root = $make->();
    my ($rc, $snapshot, $error) = run_preflight($root, \%policy, 'xcat_check_zfs_reinstall');
    is($rc, 0, 'matching native cache header ownership permits OS reinstall') or diag($error);
    like($snapshot, qr/^ada6\tSERIAL6\tcache:1\t/mx, 'cache identity joins the destructive snapshot');
    like($snapshot, qr/preserved\nada7\tSERIAL7\t/x, 'the data disk remains protected');
    for my $member (1, 3, 5) {
        my $root = $make->();
        my $geometry = read_file("$root/ada$member.geom");
        $geometry =~ s/8589934592/8623489024/gx;
        write_file("$root/ada$member.geom", $geometry);
        my ($size_rc, $size_output, $size_error) = run_preflight($root, \%policy, 'xcat_check_zfs_reinstall');
        isnt($size_rc, 0, "a mismatched group containing ada$member prevents reinstall");
        like($size_error, qr/must[ ]have[ ]equal[ ]capacities/x, 'preflight reports the capacity mismatch');
        unlike(read_file("$root/events"), qr/^(zpool[ ]labelclear|gpart[ ]destroy|dd[ ].*of=\/dev\/)/mx,
            'mismatched capacities cause no destructive operation');
    }
    {
        my $root = $make->();
        for my $member (2 .. 6) {
            my $geometry = read_file("$root/ada$member.geom");
            my $size = $member < 4 ? 2147483648 : $member < 6 ? 1073741824 : 536870912;
            $geometry =~ s/8589934592/$size/gx;
            write_file("$root/ada$member.geom", $geometry);
        }
        is((run_preflight($root, \%policy, 'xcat_zfs_disk_inventory'))[0], 0,
            'independent primary, special, log and cache groups can have different capacities');
    }
    for my $change ('foreign cache', 'missing cache owner', 'invalid cache magic', 'invalid cache version', 'bad label checksum', 'foreign log', 'missing special',
        'preserved overlap', 'unselected root cache', 'different root GUID', 'destroyed data pool',
        'partly overwritten data labels', 'cache changed before erase') {
        my $root = $make->();
        my %changed = %policy;
        if ($change eq 'foreign cache' || $change eq 'cache changed before erase') {
            if ($change eq 'cache changed before erase') {
                my ($before_rc, $before) = run_preflight($root, \%changed, 'xcat_check_zfs_reinstall');
                is($before_rc, 0, 'the unchanged snapshot is initially accepted');
                write_file("$root/before.snapshot", $before);
            }
            my $foreign = $cache_label;
            if ($change eq 'cache changed before erase') {
                $foreign =~ s/ashift:[ ]12/ashift: 13/x;
            } else {
                $foreign =~ s/$pool_guid/18446744073709551611/gx;
            }
            write_file("$root/labels/ada6", $foreign);
            if ($change eq 'cache changed before erase') {
                my ($changed_rc, $changed_snapshot) = run_preflight($root, \%changed, 'xcat_check_zfs_reinstall');
                is($changed_rc, 0, 'the changed cache still belongs to the selected root pool');
                isnt($changed_snapshot, read_file("$root/before.snapshot"), 'the valid changed cache alters the accepted snapshot');
            }
        } elsif ($change eq 'missing cache owner') {
            my $missing = $cache_label; $missing =~ s/    pool_guid:[^\n]*\n//x;
            write_file("$root/labels/ada6", $missing);
        } elsif ($change eq 'invalid cache magic' || $change eq 'invalid cache version') {
            my $invalid = $cache_label;
            $invalid =~ s/magic:[ ]6504978260106102853/magic: 6504978260106102852/x if $change eq 'invalid cache magic';
            $invalid =~ s/version:[ ]1/version: 2/x if $change eq 'invalid cache version';
            write_file("$root/labels/ada6", $invalid);
        } elsif ($change eq 'bad label checksum') {
            my $invalid = $cache_label;
            $invalid =~ s/LABEL[ ]0/LABEL 0 (Bad label cksum)/x;
            write_file("$root/labels/ada6", $invalid);
        } elsif ($change eq 'foreign log') {
            write_file("$root/labels/ada4", "state: 1\nname: 'tank'\npool_guid: 123\n");
        } elsif ($change eq 'missing special') {
            write_file("$root/disks", "ada0 ada1 ada2 ada4 ada5 ada6 ada7\n");
        } elsif ($change eq 'preserved overlap') {
            $changed{XCAT_PRESERVE_DISKS} = 'ada6@SERIAL6';
        } elsif ($change eq 'unselected root cache') {
            $changed{XCAT_ZFS_CACHE_VDEVS} = '-';
        } elsif ($change eq 'destroyed data pool') {
            write_file("$root/labels/ada7", "LABEL 0\n    state: 2\n    name: 'tank'\n    pool_guid: 18446744073709551611\n");
        } elsif ($change eq 'partly overwritten data labels') {
            write_file("$root/labels/ada7", "failed to unpack label 0\nLABEL 1\n    state: 1\n    name: 'tank'\n    pool_guid: 18446744073709551611\n");
        } else {
            write_file("$root/labels/ada1", "state: 1\nname: 'zroot'\npool_guid: 18446744073709551611\n");
        }
        write_file("$root/events", '');
        my $operation = $change eq 'cache changed before erase' ? 'xcat_erase_os_disks' : 'xcat_check_zfs_reinstall';
        my ($rejected_rc, $rejected_output, $rejected_error) = run_preflight($root, \%changed, $operation);
        isnt($rejected_rc, 0, "$change prevents erase");
        like($rejected_error, qr/OS[ ]or[ ]preserved[ ]disk[ ]state[ ]changed[ ]before[ ]reinstall/x,
            'erase rejects the changed snapshot after ownership succeeds') if $change eq 'cache changed before erase';
        unlike(read_file("$root/events"), qr/^(zpool[ ]labelclear|gpart[ ]destroy|dd[ ].*of=\/dev\/)/mx,
            'rejection performs no destructive operation');
    }
};

sub automatic_config {
    my ($root, %changes) = @_;
    my %config = (format => 'xcat-freebsd-install-5', release => '15.1-RELEASE',
        node => 'node1', hostname => 'node1', generation => 'a' x 32,
        master => '192.0.2.1', port => 3002, ipv4 => '192.0.2.2', netmask => '255.255.255.0',
        gateway => '', nameservers => '', mac => '52:54:00:12:34:56',
        filesystem => 'zfs', swap_size => '0', swap_mode => 'none',
        zfs_topology => 'mirror', zfs_vdevs => 'auto:2', zfs_compression => 'lz4', zfs_ashift => 12,
        disk_action => 'empty', disk_selection => 'empty', preserve_disks => '-',
        install_url => 'http://192.0.2.1/install', package_plan_sha256 => 'b' x 64,
        boot_media_sha256 => 'c' x 64, runtime_sha256 => 'd' x 64, authorized_key_base64 => 'AAAA',
        bootstrap => 'dhcp', console_port => 'none', console_speed => 0, console_flow => 'none',
        install_boot_options_base64 => '', target_boot_options_base64 => '', %changes);
    delete $config{$_} for grep { !defined($config{$_}) } keys %config;
    write_file("$root/work/config", join('', map { "$_=$config{$_}\n" } sort keys %config));
}

subtest 'automatic selection excludes protected and occupied disks before resolving identities' => sub {
    my $root = fixture(4);
    automatic_config($root, preserve_disks => 'ada0@SERIAL0');
    write_file("$root/ada1.head", 'USED' . ("\0" x (1048576 - 4)));
    my ($status, $config, $error) = run_preflight($root, {}, 'xcat_resolve_disks');
    is($status, 0, 'discovery succeeds with two eligible disks');
    like($config, qr/^zfs_vdevs=ada2\@SERIAL2,ada3\@SERIAL3$/mx, 'stable order resolves actual identities');
    unlike($config, qr/^disk_selection=/mx, 'the storage guard receives an explicit configuration');
    like($config, qr/^preserve_disks=ada0\@SERIAL0$/mx, 'protected identities reach the concrete policy');
    my $events = -e "$root/events" ? read_file("$root/events") : '';
    unlike($events, qr/dd[ ]if=\/dev\/ada0/mx, 'a protected disk is excluded before content reads');
    like($error, qr/selected[ ]OS[ ]disks[ ]ada2\@SERIAL2,ada3\@SERIAL3/x, 'the selected identities are reported');
};

subtest 'automatic group sizes and scalar filesystems resolve through the same inventory guards' => sub {
    for my $case (
        ['stripe', 'auto:1', 'ada0@SERIAL0'],
        ['raid10', 'auto:2;auto:2', 'ada0@SERIAL0,ada1@SERIAL1;ada2@SERIAL2,ada3@SERIAL3'],
        ['raidz2', 'auto:4', 'ada0@SERIAL0,ada1@SERIAL1,ada2@SERIAL2,ada3@SERIAL3'],
    ) {
        my $root = fixture(4);
        automatic_config($root, zfs_topology => $case->[0], zfs_vdevs => $case->[1]);
        my ($status, $config) = run_preflight($root, {}, 'xcat_resolve_disks');
        is($status, 0, "$case->[0] automatic layout resolves");
        like($config, qr/^zfs_vdevs=\Q$case->[2]\E$/mx, 'group boundaries are retained');
    }
    for my $filesystem (qw(ufs zfs)) {
        my $root = fixture(1);
        automatic_config($root, format => 'xcat-freebsd-install-3', filesystem => $filesystem,
            target_disk => 'auto', map { $_ => undef } qw(zfs_topology zfs_vdevs swap_mode zfs_compression zfs_ashift disk_action));
        my ($status, $config) = run_preflight($root, {}, 'xcat_resolve_disks');
        is($status, 0, "$filesystem scalar automatic layout resolves");
        like($config, qr/^target_disk=ada0$/mx, 'scalar target is concrete');
        like($config, qr/^target_disk_ident=SERIAL0$/mx, 'scalar identity comes from GEOM');
    }
};

subtest 'automatic selection fails closed without a complete safe disk set' => sub {
    for my $case (qw(insufficient duplicate active malformed erase changed)) {
        my $root = fixture(1);
        automatic_config($root);
        if ($case eq 'insufficient') { write_file("$root/ada1.tail", 'USED' . ("\0" x (1048576 - 4))); }
        if ($case eq 'duplicate' || $case eq 'active' || $case eq 'changed') {
            my $data = read_file("$root/ada1.geom");
            $data =~ s/SERIAL1/SERIAL0/x if $case eq 'duplicate';
            $data =~ s/r0w0e0/r1w0e0/x if $case eq 'active';
            $data =~ s/SERIAL1/REPLACED/x if $case eq 'changed';
            write_file("$root/ada1.geom" . ($case eq 'changed' ? '.changed' : ''), $data);
        }
        automatic_config($root, zfs_vdevs => 'auto:2;ada2@SERIAL2') if $case eq 'malformed';
        automatic_config($root, disk_action => 'erase') if $case eq 'erase';
        my $before = read_file("$root/work/config");
        my ($status) = run_preflight($root, {}, 'xcat_resolve_disks');
        isnt($status, 0, "$case cannot publish a disk selection");
        is(read_file("$root/work/config"), $before, 'the original configuration remains unchanged');
    }
};

subtest 'automatic candidates satisfy swap capacity and ZFS sector alignment' => sub {
    my $root = fixture(2);
    my $geometry = read_file("$root/ada0.geom");
    $geometry =~ s/8589934592/5368709120/gx;
    write_file("$root/ada0.geom", $geometry);
    write_file("$root/ada0.size", "5368709120\n");
    my $graph = read_file("$root/graph");
    $graph =~ s/ada0[ ]8589934592/ada0 5368709120/gx or die 'Missing disk fixture';
    $graph =~ s{diskid/DISK-SERIAL0[ ]8589934592}{diskid/DISK-SERIAL0 5368709120}gx or die 'Missing label fixture';
    write_file("$root/graph", $graph);
    automatic_config($root, format => 'xcat-freebsd-install-3', filesystem => 'ufs',
        target_disk => 'auto', swap_size => '4G',
        map { $_ => undef } qw(zfs_topology zfs_vdevs swap_mode zfs_compression zfs_ashift disk_action));
    my ($status, $config, $error) = run_preflight($root, {}, 'xcat_resolve_disks');
    is($status, 0, 'a disk with sufficient space for swap and root is available') or diag($error);
    like($config, qr/^target_disk=ada1$/mx, 'smallest blank disk is skipped when swap would leave too little root space');

    $root = fixture(2);
    $geometry = read_file("$root/ada0.geom");
    $geometry =~ s/Sectorsize:[ ]512/Sectorsize: 4096/gx or die 'Missing sector fixture';
    write_file("$root/ada0.geom", $geometry);
    $graph = read_file("$root/graph");
    $graph =~ s/(?:ada0|diskid\/DISK-SERIAL0)[ ]8589934592[ ]\K512/4096/gx or die 'Missing graph fixture';
    write_file("$root/graph", $graph);
    automatic_config($root, zfs_ashift => 9);
    ($status, $config, $error) = run_preflight($root, {}, 'xcat_resolve_disks');
    is($status, 0, 'two disks compatible with the configured ashift are available') or diag($error);
    like($config, qr/^zfs_vdevs=ada1\@SERIAL1,ada2\@SERIAL2$/mx,
        'a larger-sector disk is excluded before choosing a complete mirror');
};
subtest 'scalar installation resolves before staging and rechecks after begin' => sub {
    plan(skip_all => 'Installer command fixtures require a Linux lab root') unless $^O eq 'linux' && $> == 0;
    my $jail = tempdir(CLEANUP => 1);
    make_path(map { "$jail/$_" } qw(runtime xcat dev usr/libexec/bsdinstall));
    stage_binary($jail, $_) for ('/bin/sh', '/bin/timeout', map { "/usr/bin/$_" }
        qw(awk cat cut sort mktemp tr wc cmp rm cp mv chmod mkdir dirname basename openssl env grep base64 date sleep));
    copy($library, "$jail/runtime/library") or die $!;
    copy("$directory/installerconfig.tmpl", "$jail/runtime/template") or die $!;
    write_file("$jail/xcat/runtime.tsv", "fixture runtime\n");
    write_file("$jail/dev/null", '');
    write_file("$jail/usr/libexec/bsdinstall/pkgbase", <<'PKGBASE');
#!/bin/sh
test "$1" = --xcat-prepare-1 || exit 90
grep -q '^target_disk=ada0$' "$2" || exit 91
root=${3%/work/pkgbase-work}
printf 'prepared\n' >> "$root/events"
PKGBASE
    chmod(oct('0755'), "$jail/usr/libexec/bsdinstall/pkgbase") or die $!;
    for my $case (qw(unchanged changed unavailable)) {
        my $root = fixture(1);
        write_file("$root/events", '');
        automatic_config($root, format => 'xcat-freebsd-install-3', filesystem => 'ufs', target_disk => 'auto',
            map { $_ => undef } qw(zfs_topology zfs_vdevs swap_mode zfs_compression zfs_ashift disk_action));
        write_file("$root/change-on-begin", '') if $case eq 'changed';
        if ($case eq 'unavailable') {
            write_file("$root/ada0.head", 'USED');
            write_file("$root/ada1.head", 'USED');
        }
        my %commands = (
            kldload => 'exit 0',
            mount => 'grep -q "^target_disk=ada0$" "$FIXTURE_DIR/work/config" || exit 91
                printf "workspace\n" >> "$FIXTURE_DIR/events"',
            nc => 'read -r protocol generation attempt phase members
                printf "phase %s\n" "$phase" >> "$FIXTURE_DIR/events"
                if [ "$phase" = begin ] && [ -f "$FIXTURE_DIR/change-on-begin" ]; then
                    printf USED > "$FIXTURE_DIR/ada0.head"
                fi
                printf "ready\n%s %s %s ok\n" "$protocol" "$generation" "$phase"',
            bsdinstall => "printf 'bsdinstall boundary\\n' >> '$root/events'\ncp \"\$2\" '$root/invoked-installer'\nexit 19",
        );
        for my $command (keys %commands) {
            write_file("$root/bin/$command", "#!/bin/sh\n$commands{$command}\n");
            chmod(oct('0755'), "$root/bin/$command") or die $!;
        }
        make_path("$jail$root");
        system('cp', '-a', "$root/.", "$jail$root") == 0 or die 'Cannot stage installer fixture';
        my $result = xCAT::FreeBSDPkg::run_command(['/usr/sbin/chroot', $jail, '/bin/sh', '-c',
            '. "$1"; xcat_read_config "$XCAT_WORK/config" && xcat_install_system "$2" "$1"',
            'sh', '/runtime/library', '/runtime/template'], cwd => $jail,
            environment => {PATH => "$root/bin:/usr/bin:/bin", LC_ALL => 'C', FIXTURE_DIR => $root,
                XCAT_WORK => "$root/work", XCAT_ATTEMPT => 'b' x 32, XCAT_PROVISIONING_IF => 'em0'}, timeout => 20);
        is($result->{signal}, 0, "$case exits without a signal");
        ok(!$result->{failure}, "$case finishes within the fixture deadline") or diag($result->{stderr});
        my $events = read_file("$jail$root/events");
        if ($case eq 'unchanged') {
            like($events, qr/workspace.*prepared.*phase[ ]begin.*bsdinstall[ ]boundary/sx,
                'a resolved unchanged disk reaches the installer after preparation and authorization') or diag($result->{stderr});
            my $invoked = -f "$jail$root/invoked-installer" ? read_file("$jail$root/invoked-installer") : '';
            like($invoked, qr/^PARTITIONS="ada0[ ]GPT/mx,
                'the actual destructive caller receives the resolved disk');
        } elsif ($case eq 'changed') {
            like($events, qr/phase[ ]begin/x, 'disk content changes after the real begin handshake');
            unlike($events, qr/bsdinstall[ ]boundary/x, 'changed disk content cannot reach the destructive caller');
        } else {
            unlike($events, qr/workspace|prepared|phase[ ]begin|bsdinstall[ ]boundary/x,
                'failed selection cannot stage packages or request destructive authorization');
        }
    }
};
done_testing();
