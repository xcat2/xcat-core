#!/usr/bin/env perl
use strict;
use warnings;
use Carp qw(croak);
use File::Temp qw(tempdir);
use FindBin;
use IPC::Open3;
use Symbol qw(gensym);
use Test::More;

my $planner = "$FindBin::Bin/../../xCAT/postscripts/configzfs-freebsd.awk";
my $directory = tempdir(CLEANUP => 1);

sub write_file {
    my ($name, $bytes) = @_;
    open(my $out, '>', "$directory/$name") or croak $!;
    print {$out} $bytes;
    close($out) or croak $!;
    return "$directory/$name";
}

sub invoke {
    my (@arguments) = @_;
    my $errors = gensym();
    my $pid = open3(my $input, my $output, $errors, 'awk', '-f', $planner, @arguments);
    close($input) or croak $!;
    my $stdout = do { local $/ = undef; <$output> } // '';
    my $stderr = do { local $/ = undef; <$errors> } // '';
    close($output) or croak $!;
    close($errors) or croak $!;
    waitpid($pid, 0) == $pid or croak $!;
    return ($?, $stdout, $stderr);
}

sub base {
    return { format => 'xcat-freebsd-data-1', action => 'create', pool => 'tank',
        os_disks => 'vtbd0@OS0,vtbd1@OS1', topology => 'mirror', vdevs => 'vtbd2@DATA2,vtbd3@DATA3' };
}

sub compile {
    my ($policy) = @_;
    return invoke(write_file('policy', join('', map { "$_=$policy->{$_}\n" } sort keys %$policy)));
}

sub settings {
    my ($plan) = @_;
    my %settings;
    for my $row (grep { /^K\t/x } split(/\n/x, $plan)) {
        my @fields = split(/\t/x, $row);
        $settings{$fields[1]} = $fields[2];
    }
    return \%settings;
}

sub status {
    return "  pool: tank\n state: ONLINE\nconfig:\n\n" .
        "\tNAME                 STATE     READ WRITE CKSUM\n" .
        "\ttank                 ONLINE       0     0     0\n" .
        "\t  mirror-0           ONLINE       0     0     0\n" .
        "\t    /dev/vtbd2       ONLINE       0     0     0\n" .
        "\t    /dev/vtbd3       ONLINE       0     0     0\n" .
        "\nerrors: No known data errors\n";
}

sub verify {
    my ($plan, $native) = @_;
    return invoke('-v', 'mode=verify', write_file('plan', $plan), write_file('status', $native));
}

subtest 'dedicated pool defaults and native readback' => sub {
    my ($exit, $plan, $error) = compile(base());
    is($exit, 0, 'a dedicated mirrored data pool compiles');
    is($error, '', 'valid policy has no diagnostic');
    is_deeply(settings($plan), {format => 'xcat-freebsd-data-1', action => 'create', pool => 'tank',
        guid => '-', compression => 'lz4', ashift => '12', special_small_blocks => '0',
        encryption => 'off', keyfile => '-', mountpoint => '/data/tank'}, 'defaults are explicit');
    is_deeply([map { substr($_, 2) } grep { /^C\t/x } split(/\n/x, $plan)],
        ['mirror', '/dev/vtbd2', '/dev/vtbd3'], 'OS members cannot enter the create arguments');
    is((verify($plan, status()))[0], 0, 'the expected native mirror passes readback');
    my $import = base();
    @$import{qw(action guid encryption keyfile)} = ('import', '18446744073709551615', 'aes-256-gcm', '/etc/xcat/keys/tank.key');
    my ($import_exit, $import_plan) = compile($import);
    is($import_exit, 0, 'a full-width pool GUID and automatic raw key compile');
    is(settings($import_plan)->{guid}, '18446744073709551615', 'GUID precision is retained');
};

subtest 'auxiliary devices and mixed log groups' => sub {
    my $policy = base();
    @$policy{qw(log_vdevs cache_vdevs special_vdevs special_small_blocks)} =
        ('vtbd4@LOG4,vtbd5@LOG5;vtbd6@LOG6', 'vtbd7@CACHE7,vtbd8@CACHE8', 'vtbd9@SPECIAL9,vtbd10@SPECIAL10', 65536);
    my ($exit, $plan) = compile($policy);
    is($exit, 0, 'mirror, single log, two caches and redundant special devices compile');
    is_deeply([map { substr($_, 2) } grep { /^C\t/x } split(/\n/x, $plan)],
        [qw(mirror /dev/vtbd2 /dev/vtbd3 special mirror /dev/vtbd9 /dev/vtbd10 log /dev/vtbd6 mirror /dev/vtbd4 /dev/vtbd5 cache /dev/vtbd7 /dev/vtbd8)],
        'native arguments retain separate data, special, log and cache roles');
    # Native FreeBSD 15.1 output; only names and trailing whitespace are normalized.
    my $native;
    for my $fixture ('mixed', 'merged') {
        open(my $input, '<', "$FindBin::Bin/fixtures/freebsd15.1-zpool-$fixture-logs") or croak $!;
        my $bytes = do { local $/ = undef; <$input> };
        close($input) or croak $!;
        if ($fixture eq 'mixed') {
            $native = $bytes;
            is((verify($plan, $bytes))[0], 0, 'native creation retains a single log before a mirrored log');
        } else {
            isnt((verify($plan, $bytes))[0], 0, 'the former producer merges log groups and fails readback');
        }
    }
    my $wrong;
    $wrong = $native;
    $wrong =~ s/\tcache\n/\tlogs\n/x;
    isnt((verify($plan, $wrong))[0], 0, 'cache devices cannot masquerade as logs');
};

subtest 'invalid policy cannot emit a partial create plan' => sub {
    for my $change (
        { action => '' }, { action => 'destroy' }, { pool => 'zroot' }, { pool => 'tank;reboot' },
        { vdevs => 'vtbd0@OS0,vtbd3@DATA3' }, { vdevs => 'vtbd2@OS0,vtbd3@DATA3' },
        { vdevs => 'diskid/DISK-DATA2@DATA2,vtbd3@DATA3' }, { vdevs => 'vtbd2@DATA2' },
        { os_disks => '-' }, { os_disks => '' }, { log_vdevs => 'vtbd2@DATA2' },
        { topology => 'draid1' }, { topology => 'raid10' }, { compression => 'on' },
        { compression => 'zstd-20' }, { ashift => 8 }, { ashift => 17 },
        { special_small_blocks => 65536 }, { special_vdevs => 'vtbd4@SPECIAL4' },
        { special_small_blocks => 12345 }, { encryption => 'aes-256-gcm' },
        { encryption => 'prompt' }, { keyfile => '/etc/xcat/keys/tank.key' },
        { mountpoint => '/data/../etc' }, { mountpoint => '/' },
        { action => 'import', guid => '18446744073709551616' }, { action => 'import', guid => '0' },
        { action => 'import' }, { unsupported => 'yes' },
    ) {
        my $policy = { %{base()}, %$change };
        my ($exit, $plan, $error) = compile($policy);
        isnt($exit, 0, 'invalid ' . join(',', sort keys %$change) . ' is rejected');
        is($plan, '', 'no partial create plan escapes');
        like($error, qr/configzfs:/x, 'rejection identifies the policy problem');
    }
    for my $bytes ("format=xcat-freebsd-data-1\nformat=xcat-freebsd-data-1\n", "pool=tank\t\n", 'x' x 32769) {
        my ($exit, $plan) = invoke(write_file('malformed', $bytes));
        isnt($exit, 0, 'duplicate, control-character or oversized input is rejected');
        is($plan, '', 'malformed input emits no plan');
    }
};

subtest 'data topologies and special-device redundancy' => sub {
    for my $case (
        ['mirror', 'vtbd2@DATA2,vtbd3@DATA3,vtbd4@DATA4', 3, [qw(mirror /dev/vtbd2 /dev/vtbd3 /dev/vtbd4)]],
        ['raid10', 'vtbd2@DATA2,vtbd3@DATA3;vtbd4@DATA4,vtbd5@DATA5', 2,
            [qw(mirror /dev/vtbd2 /dev/vtbd3 mirror /dev/vtbd4 /dev/vtbd5)]],
        ['raidz1', 'vtbd2@DATA2,vtbd3@DATA3,vtbd4@DATA4', 2, [qw(raidz1 /dev/vtbd2 /dev/vtbd3 /dev/vtbd4)]],
        ['raidz2', 'vtbd2@DATA2,vtbd3@DATA3,vtbd4@DATA4,vtbd5@DATA5', 3,
            [qw(raidz2 /dev/vtbd2 /dev/vtbd3 /dev/vtbd4 /dev/vtbd5)]],
        ['raidz3', 'vtbd2@DATA2,vtbd3@DATA3,vtbd4@DATA4,vtbd5@DATA5,vtbd6@DATA6', 4,
            [qw(raidz3 /dev/vtbd2 /dev/vtbd3 /dev/vtbd4 /dev/vtbd5 /dev/vtbd6)]],
    ) {
        my $policy = { %{base()}, topology => $case->[0], vdevs => $case->[1] };
        my @special = map { 'vtbd' . (20 + $_) . '@SPECIAL' . $_ } 1 .. $case->[2];
        $policy->{special_vdevs} = join(',', @special);
        my ($exit, $plan) = compile($policy);
        is($exit, 0, "$case->[0] accepts matching special-device redundancy");
        is_deeply([map { substr($_, 2) } grep { /^C\t/x } split(/\n/x, $plan)],
            [@{$case->[3]}, 'special', 'mirror', map { '/dev/vtbd' . (20 + $_) } 1 .. $case->[2]],
            'native topology and all device roles are explicit');
        $policy->{special_vdevs} = join(',', @special, 'vtbd30@SPECIAL30');
        isnt((compile($policy))[0], 0, "$case->[0] rejects wider special groups that native creation refuses");
        pop @special;
        $policy->{special_vdevs} = join(',', @special);
        isnt((compile($policy))[0], 0, "$case->[0] rejects weaker special-device redundancy");
    }
    my $stripe = { %{base()}, topology => 'stripe', vdevs => 'vtbd2@DATA2' };
    is((compile($stripe))[0], 0, 'a dedicated stripe without special devices compiles');
    $stripe->{special_vdevs} = 'vtbd3@SPECIAL3,vtbd4@SPECIAL4';
    isnt((compile($stripe))[0], 0, 'a stripe rejects a special mirror before native creation');
    for my $compression (qw(off lz4 gzip gzip-1 gzip-6 gzip-9 zstd zstd-1 zstd-19)) {
        for my $ashift (9, 12, 16) {
            my ($exit, $plan) = compile({ %{base()}, compression => $compression, ashift => $ashift });
            is($exit, 0, "$compression and ashift $ashift compile");
            is(settings($plan)->{compression}, $compression eq 'gzip-6' ? 'gzip' : $compression,
                'compression agrees with native property readback');
            is(settings($plan)->{ashift}, "$ashift", 'ashift is retained');
        }
    }
};

subtest 'dRAID geometry and native distributed spares' => sub {
    my $policy = { %{base()}, topology => 'draid2:4d:8c:2s',
        vdevs => join(',', map { "vtbd$_\@DATA$_" } 2 .. 9),
        special_vdevs => join(',', map { "vtbd$_\@SPECIAL$_" } 10 .. 12),
        log_vdevs => 'vtbd13@LOG13,vtbd14@LOG14', cache_vdevs => 'vtbd15@CACHE15',
        encryption => 'aes-256-gcm', keyfile => '/etc/xcat/keys/tank.key', special_small_blocks => 65536 };
    my ($exit, $plan) = compile($policy);
    is($exit, 0, 'explicit dRAID with matching special redundancy and automatic encryption compiles');
    is_deeply([map { substr($_, 2) } grep { /^C\t/x } split(/\n/x, $plan)],
        ['draid2:4d:8c:2s', map({ "/dev/vtbd$_" } 2 .. 9), 'special', 'mirror',
        map({ "/dev/vtbd$_" } 10 .. 12), 'log', 'mirror', '/dev/vtbd13', '/dev/vtbd14', 'cache', '/dev/vtbd15'],
        'native arguments retain geometry and every device role');
    open(my $input, '<', "$FindBin::Bin/fixtures/freebsd15.1-zpool-draid") or croak $!;
    my $native = do { local $/ = undef; <$input> };
    close($input) or croak $!;
    is((verify($plan, $native))[0], 0, 'native FreeBSD creation and its two distributed spares pass readback');
    for my $change (
        [qr/draid2:4d:8c:2s-0/x, 'draid1:4d:8c:2s-0'],
        [qr/draid2:4d:8c:2s-0/x, 'draid2:3d:8c:2s-0'],
        [qr/draid2:4d:8c:2s-0/x, 'draid2:4d:9c:2s-0'],
        [qr/draid2:4d:8c:2s-0/x, 'draid2:4d:8c:1s-0'],
        [qr/draid2-0-1/x, 'draid2-0-2'], [qr/draid2-0-1/x, 'draid2-0-0'],
        [qr/AVAIL/x, 'INUSE'], [qr/\t\s+draid2-0-1[^\n]*\n/x, ''],
        [qr{/dev/vtbd9}x, '/dev/vtbd1'],
    ) {
        my $wrong = $native;
        $wrong =~ s/$change->[0]/$change->[1]/x or croak 'invalid dRAID fixture mutation';
        isnt((verify($plan, $wrong))[0], 0, 'changed geometry, spare state or data membership fails');
    }
    for my $topology (qw(draid draid1 draid0:4d:8c:1s draid4:4d:8c:1s
        draid2:04d:8c:2s draid2:0d:8c:2s draid2:4d:8c:3s draid2:4d:7c:1s draid2:4d:129c:1s)) {
        my ($bad, $partial) = compile({ %$policy, topology => $topology });
        isnt($bad, 0, "$topology cannot reach pool creation");
        is($partial, '', 'invalid geometry emits no partial plan');
    }
    for my $parity (1 .. 3) {
        my %simple = (%$policy, topology => "draid$parity:3d:8c:1s", special_vdevs => '-', special_small_blocks => 0);
        is((compile(\%simple))[0], 0, "parity $parity compiles");
        $simple{special_vdevs} = join(',', map { "vtbd$_\@SPECIAL$_" } 20 .. 20 + $parity);
        is((compile(\%simple))[0], 0, "parity $parity requires the corresponding special mirror");
        $simple{special_vdevs} =~ s/,[^,]+$//x;
        isnt((compile(\%simple))[0], 0, 'weaker special redundancy is rejected');
    }
    my %multiple = (%$policy, special_vdevs => '-', special_small_blocks => 0, log_vdevs => '-', cache_vdevs => '-',
        vdevs => $policy->{vdevs} . ';' . join(',', map { "vtbd$_\@DATA$_" } 16 .. 23));
    is((compile(\%multiple))[0], 0, 'multiple explicit dRAID vdevs compile');
    $multiple{vdevs} =~ s/,[^,]+$//x;
    isnt((compile(\%multiple))[0], 0, 'each dRAID vdev must match the declared child count');
};

subtest 'native topology and health must match exactly' => sub {
    my (undef, $plan) = compile(base());
    for my $change (
        [qr{/dev/vtbd3}x, '/dev/vtbd4'], [qr{mirror-0}x, 'raidz1-0'],
        [qr{ONLINE}x, 'DEGRADED'], [qr{No\ known\ data\ errors}x, '1 data error'],
        [qr{\t\s+/dev/vtbd3[^\n]*\n}x, ''], [qr{errors:[^\n]*}x, ''],
        [qr{\t\s+/dev/vtbd2[^\n]*}x, "\t    /dev/vtbd2 ONLINE 0 1 0"],
    ) {
        my $native = status();
        $native =~ s/$change->[0]/$change->[1]/x or croak 'invalid status fixture';
        isnt((verify($plan, $native))[0], 0, 'changed membership, redundancy, health or completeness is rejected');
    }
};

subtest 'native startup-cache identities' => sub {
    # Pool headers and GUIDs from native FreeBSD 15.1 zdb -C readback.
    my $native = "createproof:\n    pool_guid: 12448067557558924659\n" .
        "zroot:\n    pool_guid: 6329292263267649316\n" .
        "tank:\n    pool_guid: 5556949434698476598\n";
    my ($exit, $records, $error) = invoke('-v', 'mode=cache', write_file('cache', $native));
    is($exit, 0, 'all native startup pool identities are read');
    is($error, '', 'valid cache has no diagnostic');
    is_deeply([sort split(/\n/x, $records)], [
        "createproof\t12448067557558924659", "tank\t5556949434698476598", "zroot\t6329292263267649316"],
        'every pool retains its full-width identity');
    my ($duplicate, $deduplicated) = invoke('-v', 'mode=cache', write_file('cache', $native . $native));
    is($duplicate, 0, 'matching identities from both native cache paths are accepted');
    is_deeply([sort split(/\n/x, $deduplicated)], [sort split(/\n/x, $records)], 'duplicate caches do not duplicate pools');
    for my $invalid (
        $native . "tank:\n    pool_guid: 5556949434698476599\n",
        $native . "other:\n    pool_guid: 5556949434698476598\n",
        "tank:\n", "tank:\n    pool_guid: 0\n", "tank:\n    pool_guid: 18446744073709551616\n",
        "tank:\n    pool_guid: 12\n    pool_guid: 12\n", "tank;reboot:\n    pool_guid: 12\n",
    ) {
        my ($bad, $partial) = invoke('-v', 'mode=cache', write_file('cache', $invalid));
        isnt($bad, 0, 'ambiguous or incomplete cached identities are rejected');
        is($partial, '', 'no partial startup inventory escapes');
    }
    my ($empty, $none) = invoke('-v', 'mode=cache', write_file('cache', ''));
    is($empty, 0, 'a system without a cache has no existing cached pools');
    is($none, '', 'an absent cache invents no startup membership');
};

done_testing();
