#!/usr/bin/env perl
use strict;
use warnings;

use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

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
        geom => 'test "$*" = "disk list" || exit 90
            count=0; test ! -f "$FIXTURE_DIR/geom-count" || count=$(cat "$FIXTURE_DIR/geom-count")
            count=$((count+1)); printf "%s\n" "$count" > "$FIXTURE_DIR/geom-count"
            for f in "$FIXTURE_DIR"/ada*.geom; do
                if [ "$count" -gt 1 ] && [ -f "$f.changed" ]; then cat "$f.changed"; else cat "$f"; fi
            done',
        sysctl => 'case "$*" in
            "-n kern.disks") cat "$FIXTURE_DIR/disks" ;;
            "-n kern.geom.conftxt") cat "$FIXTURE_DIR/graph" ;;
            *) exit 90 ;;
            esac',
        stat => 'test "$1" = -f && test "$2" = "%HT:%r" || exit 90
            cat "$FIXTURE_DIR/${3##*/}.stat"',
        zpool => 'test "$*" = "list -H -o name" || exit 90; cat "$FIXTURE_DIR/pools"',
        geli => 'test "$*" = "status -s" || exit 90; cat "$FIXTURE_DIR/geli"',
        gpart => 'test "$*" = list || exit 90; cat "$FIXTURE_DIR/partitions"',
        zdb => 'test "$1" = -l || exit 90
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
            case "$dst" in "$FIXTURE_DIR"/work/storage.*/zero|"$FIXTURE_DIR"/work/storage.*/window) ;; *) exit 90 ;; esac
            if [ "$src" = /dev/zero ]; then
                test "$block" = 1048576 && test "$count" = 1 || exit 90
                cp "$FIXTURE_DIR/ada0.head.zero" "$dst"; exit
            fi
            name=${src#/dev/}; region=tail; test "$skip" != 0 || region=head
            test "$((block*count))" -eq 1048576 || exit 90
            if [ "$region" = tail ]; then test "$((block*skip))" -eq 8588886016 || exit 90; fi
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
    open(my $pipe, '-|', 'sh', '-c', '. "$1"; if [ "$2" = xcat_erase_os_disks ]; then "$2" "$FIXTURE_DIR/before.snapshot"; else "$2"; fi 2>"$FIXTURE_DIR/stderr"', 'sh', $library, $operation) or die $!;
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

done_testing();
