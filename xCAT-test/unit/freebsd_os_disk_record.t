#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl", "$FindBin::Bin/../../perl-xCAT";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_STATE_MODULE_DIR}, $ENV{XCAT_FREEBSD_CONFIG_MODULE_DIR};
use Carp qw(croak);
use Cwd qw(abs_path);
use File::Temp qw(tempdir);
use JSON;
use Storable qw(dclone);
use Test::More;
use xCAT::FreeBSDConfig;
use xCAT::FreeBSDInstall;

my $root = abs_path(tempdir(CLEANUP => 1));
my $sequence = 0;
my $attempt = 'b' x 32;
my $json = JSON->new->canonical;
my $planner = abs_path("$FindBin::Bin/../../xCAT/postscripts/configzfs-freebsd.awk");
my $mirror = {filesystem => 'zfs', zfs_topology => 'mirror', zfs_vdevs => 'auto:2',
    zfs_log_vdevs => '-', zfs_cache_vdevs => '-', zfs_special_vdevs => '-'};
my $members = 'vtbd0@OS0,vtbd1@OS1';

sub write_file {
    my ($path, $bytes) = @_;
    open(my $file, '>', $path) or croak $!;
    print {$file} $bytes or croak $!;
    close($file) or croak $!;
    return;
}

sub read_state {
    my $directory = shift;
    open(my $file, '<', "$directory/node1.json") or croak $!;
    my $state = $json->decode(do { local $/; <$file> });
    close($file) or croak $!;
    return $state;
}

sub rejected {
    my ($code, $pattern, $label) = @_;
    my $ok = eval { $code->(); 1 };
    ok(!$ok, "$label is rejected");
    like($@, $pattern, "$label explains the failure");
    return;
}

sub prepare {
    my ($policy) = @_;
    my $directory = "$root/state-" . ++$sequence;
    my $generation = xCAT::FreeBSDInstall::prepare('node1', 'a' x 64,
        directory => $directory, os_policy => $policy);
    return ($directory, $generation);
}

sub begin {
    my ($directory, $generation, $selected, $action) = @_;
    return xCAT::FreeBSDInstall::transition('node1',
        "freebsd-install-v2 $generation $attempt begin $selected\n",
        $action || sub { return; }, directory => $directory);
}

sub phase {
    my ($directory, $generation, $phase) = @_;
    return xCAT::FreeBSDInstall::transition('node1',
        "freebsd-install-v1 $generation $attempt $phase\n", sub { return; }, directory => $directory);
}

sub load_policy {
    my ($text, $record) = @_;
    write_file("$root/partitionfile", $text);
    return xCAT::FreeBSDConfig::load_settings('node1', "$root/template", "$root/partitionfile", $planner, $record);
}

write_file("$root/key.pub", "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPu2fQbGvNixfzG3hYrKcXFP6eZDrZMDnuES0GhLWDPE\n");
write_file("$root/template", "authorized_keys_file=$root/key.pub\n");
my $automatic = "filesystem=zfs\nzfs_topology=mirror\nzfs_vdevs=auto:2\nswap_mode=none\n";

subtest 'authorization retains the selected layout before disk mutation' => sub {
    my ($directory, $generation) = prepare($mirror);
    rejected(sub { phase($directory, $generation, 'begin'); }, qr/disk[ ]reporting/x, 'begin without a record');
    for my $bad ('vtbd0@OS0', 'vtbd0@OS0,vtbd0@OS1', 'vtbd0@OS0,vtbd1@OS0',
        'vtbd0@OS0;vtbd1@OS1', 'auto:2', 'vtbd0@OS0,vtbd100000@OS1') {
        my $ok = eval { begin($directory, $generation, $bad); 1 };
        ok(!$ok, "invalid membership $bad stops before authorization");
        is(read_state($directory)->{phase}, 'prepared', 'rejection does not claim the installation');
    }
    my $actions = 0;
    my $reply = eval { begin($directory, $generation, $members, sub {
        my ($phase, $state) = @_;
        is($phase, 'begin', 'only begin authorizes the disk operation');
        is_deeply(read_state($directory)->{os_disks}, $state->{os_disks}, 'record is durable before the action');
        ++$actions;
    }); };
    is($reply, "freebsd-install-v2 $generation begin ok\n", 'controller acknowledges resolved disk membership');
    return unless $reply;
    is($actions, 1, 'valid begin reaches the installation action');
    my $record = read_state($directory)->{os_disks};
    is_deeply($record, {generation => $generation, attempt => $attempt,
        layout => {%$mirror, zfs_vdevs => $members}}, 'record binds members, layout, generation and attempt');
    is(begin($directory, $generation, $members), $reply, 'identical begin can be retried after a lost acknowledgement');
    rejected(sub { begin($directory, $generation, 'vtbd2@OS2,vtbd3@OS3'); }, qr/record[ ]changed/x,
        'different disks in the same attempt');
    rejected(sub { begin($directory, 'f' x 32, $members); }, qr/Stale/x, 'stale generation');
    phase($directory, $generation, 'complete');
    phase($directory, $generation, 'booted');
    xCAT::FreeBSDInstall::cancel('node1', directory => $directory);
    my $next = xCAT::FreeBSDInstall::prepare('node1', 'c' x 64, directory => $directory,
        os_policy => $record->{layout}, previous_os_disks => $record);
    isnt($next, $generation, 'reinstall has a new generation');
    is_deeply(read_state($directory)->{os_disks}, $record, 'rearming retains the previous disk identities');
    rejected(sub { xCAT::FreeBSDInstall::prepare('node1', 'd' x 64, directory => $directory,
        previous_os_disks => undef); }, qr/record[ ]changed/x, 'record changed since configuration was compiled');
    begin($directory, $next, $members);
    is(read_state($directory)->{os_disks}{generation}, $next, 'reinstall updates the record before its disk operation');
    phase($directory, $next, 'failed');
    xCAT::FreeBSDInstall::cancel('node1', directory => $directory);
    is(read_state($directory)->{os_disks}{generation}, $next, 'failed installation retains the recovery identities');
    xCAT::FreeBSDInstall::prepare('node1', 'e' x 64, directory => $directory);
    my $legacy = read_state($directory)->{generation};
    phase($directory, $legacy, 'begin');
    ok(!exists(read_state($directory)->{os_disks}), 'unrecorded legacy installation invalidates the previous record');
    xCAT::FreeBSDInstall::cancel('node1', directory => $directory);
    xCAT::FreeBSDInstall::prepare('node1', 'f' x 64, directory => $directory);
    is(read_state($directory)->{os_disk_history}, 1, 'legacy installation history survives a later preparation');
};

subtest 'unstarted failures retain automatic retry on fixed owners and pools' => sub {
    my ($directory, $generation) = prepare($mirror);
    phase($directory, $generation, 'failed');
    xCAT::FreeBSDInstall::cancel('node1', directory => $directory);
    my $retry = xCAT::FreeBSDInstall::prepare('node1', 'c' x 64, directory => $directory, os_policy => $mirror);
    is(read_state($directory)->{os_disk_history}, 0, 'failure before begin does not claim fixed-owner disks');
    my $reply = eval { begin($directory, $retry, $members); };
    ok($reply, 'fixed-owner retry can report its first selection');

    my $pool_directory = "$root/unstarted-pool";
    my $rpc = sub { return xCAT::FreeBSDInstall::pool_request('node1', @_, directory => $pool_directory); };
    my $prepared = $rpc->('prepare', {fingerprint => 'a' x 64, servers => ['192.0.2.11']});
    my $epoch = $prepared->{epoch};
    my $registered = eval { $rpc->('register', {epoch => $epoch, server => '192.0.2.11', generation => 'c' x 32,
        fingerprint => 'd' x 64, master => '192.0.2.11', os_policy => $mirror}); };
    ok($registered, 'automatic pool preparation registers') or return;
    my $result = $rpc->('event', {epoch => $epoch, server => '192.0.2.11', generation => 'c' x 32,
        attempt => $attempt, phase => 'failed'});
    is($result->{os_disk_history}, 0, 'failure before begin does not claim pool disks');
    $rpc->('cancel', {});
    $prepared = $rpc->('prepare', {fingerprint => 'f' x 64, servers => ['192.0.2.11']});
    is($prepared->{os_disk_history}, 0, 'pool retry retains its unstarted state');

    my $old = read_state($directory);
    delete @{$old}{qw(os_disk_history os_disks)};
    $old->{phase} = 'cancelled';
    write_file("$directory/node1.json", $json->encode($old) . "\n");
    xCAT::FreeBSDInstall::prepare('node1', 'e' x 64, directory => $directory);
    is(read_state($directory)->{os_disk_history}, 1, 'attempt from a pre-marker server retains conservative history');
};

subtest 'automatic reinstall compiles only the retained OS membership' => sub {
    my $record = {generation => 'a' x 32, attempt => $attempt, layout => {%$mirror, zfs_vdevs => $members}};
    my $settings = eval { load_policy($automatic . "disk_action=erase\n", $record); };
    ok($settings, 'automatic mirror reinstall compiles with its retained record');
    return unless $settings;
    is($settings->{zfs_vdevs}, $members, 'native policy contains the exact previous OS members');
    is($settings->{disk_action}, 'erase', 'erasure remains explicit');
    ok(!exists($settings->{disk_selection}), 'reinstall cannot select a different blank disk');
    rejected(sub { load_policy($automatic, $record); }, qr/disk_action=erase/x, 'repeating blank-only selection');
    rejected(sub { load_policy($automatic . "disk_action=erase\n"); }, qr/retained[ ]OS[ ]disk[ ]record/x, 'reinstall without a record');
    rejected(sub { load_policy($automatic . "disk_action=erase\npreserve_disks=vtbd0\@OS0\n", $record); },
        qr/overlap/x, 'preserved OS member');
    rejected(sub { load_policy($automatic . "disk_action=erase\nzfs_log_vdevs=vtbd8\@LOG\n", $record); },
        qr/layout[ ]differs/x, 'changing auxiliary membership during automatic reinstall');
    for my $policy (
        "filesystem=zfs\nzfs_topology=mirror\nzfs_vdevs=auto:3\nswap_mode=none\n",
        "filesystem=zfs\nzfs_topology=raidz1\nzfs_vdevs=auto:3\nswap_mode=none\n",
        "filesystem=ufs\ntarget_disk=auto\n") {
        my $ok = eval { load_policy($policy . "disk_action=erase\n", $record); 1 };
        ok(!$ok, 'incompatible requested layout cannot reuse the record');
    }
    rejected(sub { load_policy("filesystem=zfs\nzfs_topology=raidz1\nzfs_vdevs=auto:3\nswap_mode=none\ndisk_action=erase\n",
        {%$record, layout => {%$mirror, zfs_vdevs => "$members,vtbd4\@OS4"}}); },
        qr/layout[ ]differs/x, 'same-width topology change');
    my $data = "[pool tank]\naction=import\nguid=12345\ntopology=mirror\nvdevs=vtbd2\@DATA2,vtbd3\@DATA3\n";
    my $with_data = load_policy($automatic . "disk_action=erase\n$data", $record);
    is($with_data->{preserve_disks}, 'vtbd2@DATA2,vtbd3@DATA3', 'dedicated data disks remain protected');
    like($with_data->{data_storage}{pools}[0]{policy}, qr/^os_disks=vtbd0\@OS0,vtbd1\@OS1$/mx,
        'data-pool policy excludes the resolved OS disks');
    $data =~ s/vtbd2\@DATA2/vtbd2\@OS0/x;
    rejected(sub { load_policy($automatic . "disk_action=erase\n$data", $record); }, qr/overlap/x,
        'data-pool identity conflicts with a recorded OS disk');
    is(load_policy($automatic)->{disk_selection}, 'empty', 'first installation still selects only blank disks');
};

subtest 'scalar UFS and ZFS records and mirrored groups retain their shape' => sub {
    for my $filesystem (qw(ufs zfs)) {
        my ($directory, $generation) = prepare({filesystem => $filesystem, target_disk => 'auto'});
        my $reply = eval { begin($directory, $generation, 'vtbd0@autodisk0'); };
        ok($reply, "$filesystem scalar selection is recorded");
        next unless $reply;
        my $record = read_state($directory)->{os_disks};
        my $settings = load_policy("filesystem=$filesystem\ntarget_disk=auto\ndisk_action=erase\n", $record);
        is_deeply([@{$settings}{qw(target_disk target_disk_ident)}], ['vtbd0', 'autodisk0'],
            "$filesystem uses its recorded scalar identity");
        ok(!exists($settings->{disk_selection}), "$filesystem reinstall has no blank-disk fallback");
        my $other = $filesystem eq 'ufs' ? 'zfs' : 'ufs';
        rejected(sub { load_policy("filesystem=$other\ntarget_disk=auto\ndisk_action=erase\n", $record); },
            qr/layout[ ]differs/x, "$filesystem filesystem-only change");
        rejected(sub { load_policy("filesystem=$filesystem\ntarget_disk=auto\ndisk_action=erase\npreserve_disks=vtbd9\@autodisk0\n", $record); },
            qr/overlap/x, "$filesystem preserved serial conflict");
    }
    my $policy = {%$mirror, zfs_topology => 'raid10', zfs_vdevs => 'auto:2;auto:2',
        zfs_log_vdevs => 'vtbd4@LOG', zfs_cache_vdevs => 'vtbd5@CACHE',
        zfs_special_vdevs => 'vtbd6@SPECIAL0,vtbd7@SPECIAL1'};
    my ($directory, $generation) = prepare($policy);
    my $selected = "$members;vtbd2\@OS2,vtbd3\@OS3";
    my $reply = eval { begin($directory, $generation, $selected); };
    ok($reply, 'striped-mirror membership is recorded');
    return unless $reply;
    is_deeply(read_state($directory)->{os_disks}{layout}, {%$policy, zfs_vdevs => $selected},
        'mirror groups and auxiliary roles are retained separately');
};

subtest 'pool coordinator retains the same record across service-node changes' => sub {
    my $directory = "$root/pool";
    my $rpc = sub { return xCAT::FreeBSDInstall::pool_request('node1', @_, directory => $directory); };
    my $prepared = $rpc->('prepare', {fingerprint => 'a' x 64, servers => ['192.0.2.11', '192.0.2.12']});
    my $epoch = $prepared->{epoch};
    my $registered = eval {
        for my $server (qw(192.0.2.11 192.0.2.12)) {
            my $generation = ($server eq '192.0.2.11' ? 'a' : 'c') x 32;
            $rpc->('register', {epoch => $epoch, server => $server, generation => $generation,
                fingerprint => 'd' x 64, master => $server, os_policy => $mirror});
        }
        1;
    };
    ok($registered, 'service nodes register the prepared disk policy');
    diag($@) unless $registered;
    return unless $registered;
    my $event = {epoch => $epoch, server => '192.0.2.12', generation => 'c' x 32, attempt => $attempt, phase => 'begin'};
    rejected(sub { $rpc->('event', $event); }, qr/reporting[ ]differs/x, 'pool begin without selected disks');
    my $result = eval { $rpc->('event', {%$event, members => $members}); };
    ok($result, 'registered service node claims the disk-aware installation');
    return unless $result;
    is($result->{owner}, '192.0.2.12', 'coordinator records the selected service node');
    is_deeply($result->{os_disks}, read_state($directory)->{os_disks}, 'coordinator acknowledgement follows durable record publication');
    rejected(sub { $rpc->('event', {%$event, members => 'vtbd8@NEW8,vtbd9@NEW9'}); },
        qr/record[ ]changed/x, 'same owner cannot change the selected set');
    rejected(sub { $rpc->('event', {%$event, members => $members, server => '192.0.2.11', generation => 'a' x 32}); },
        qr/Another[ ]service[ ]node/x, 'another service node cannot take the installation');
    my $record = $result->{os_disks};
    for my $phase (qw(completing complete booted)) { $rpc->('event', {%$event, phase => $phase}); }
    $rpc->('cancel', {});
    $prepared = $rpc->('prepare', {fingerprint => 'f' x 64, servers => ['192.0.2.11', '192.0.2.12']});
    is_deeply($prepared->{os_disks}, $record, 'new service-pool epoch retains previous OS membership');
    my $settings = load_policy($automatic . "disk_action=erase\n", $prepared->{os_disks});
    is($settings->{zfs_vdevs}, $members, 'standby can compile reinstall without the previous owner or installed OS');
    $epoch = $prepared->{epoch};
    $rpc->('register', {epoch => $epoch, server => '192.0.2.11', generation => 'e' x 32,
        fingerprint => 'f' x 64, master => '192.0.2.11', os_policy => $record->{layout}});
    rejected(sub { $rpc->('register', {epoch => $epoch, server => '192.0.2.12', generation => 'e' x 32,
        fingerprint => 'f' x 64, master => '192.0.2.12', os_policy => $mirror}); },
        qr/different[ ]OS[ ]disk[ ]policies/x, 'standby prepared a different disk policy');
    my $bad = read_state($directory);
    $bad->{pool}{os_policy}{extra} = 'invalid';
    write_file("$directory/node1.json", $json->encode($bad) . "\n");
    rejected(sub { $rpc->('inspect', {}); }, qr/retained[ ]OS[ ]disk[ ]policy/x,
        'noncanonical coordinator policy');
};

subtest 'invalid retained records cannot be read or authorize installation' => sub {
    my ($directory, $generation) = prepare($mirror);
    my $ok = eval { begin($directory, $generation, $members); 1; };
    ok($ok, 'valid record is available for corruption controls') or return;
    my $valid = read_state($directory);
    for my $case (
        [sub { $_[0]{os_disks}{layout}{zfs_vdevs} = 'auto:2'; }, qr/unresolved/x],
        [sub { $_[0]{os_disks}{extra} = 'invalid'; }, qr/Invalid[ ]retained[ ]OS[ ]disk[ ]record/x],
        [sub { delete $_[0]{os_disks}{layout}{zfs_log_vdevs}; }, qr/Invalid[ ]retained[ ]OS[ ]disk[ ]policy/x],
        [sub { $_[0]{os_disks}{attempt} = []; }, qr/Invalid[ ]retained[ ]OS[ ]disk[ ]record/x],
        [sub { $_[0]{os_disk_history} = 0; }, qr/Invalid[ ]OS[ ]disk[ ]history/x],
        [sub { $_[0]{os_disk_rebind} = 1; }, qr/Invalid[ ]OS[ ]disk[ ]rebind/x],
        [sub { $_[0]{padding} = 'x' x 65536; }, qr/Unsafe[ ]state[ ]file/x]) {
        my $bad = dclone($valid); $case->[0]->($bad);
        write_file("$directory/node1.json", $json->encode($bad) . "\n");
        rejected(sub { xCAT::FreeBSDInstall::state('node1', directory => $directory); }, $case->[1],
            'malformed, unresolved, noncanonical or oversized state');
    }
    my $legacy = "$root/legacy-without-policy";
    my $token = xCAT::FreeBSDInstall::prepare('node1', 'a' x 64, directory => $legacy);
    rejected(sub { begin($legacy, $token, $members); }, qr/reporting[ ]differs/x,
        'v2 begin without a prepared disk policy');
};

done_testing;
