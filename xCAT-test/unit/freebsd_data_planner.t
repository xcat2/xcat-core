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
        ('vtbd4@LOG4,vtbd5@LOG5', 'vtbd7@CACHE7,vtbd8@CACHE8', 'vtbd9@SPECIAL9,vtbd10@SPECIAL10', 65536);
    my ($exit, $plan) = compile($policy);
    is($exit, 0, 'mirrored log, two caches and redundant special devices compile');
    is_deeply([map { substr($_, 2) } grep { /^C\t/x } split(/\n/x, $plan)],
        [qw(mirror /dev/vtbd2 /dev/vtbd3 special mirror /dev/vtbd9 /dev/vtbd10 log mirror /dev/vtbd4 /dev/vtbd5 cache /dev/vtbd7 /dev/vtbd8)],
        'native arguments retain separate data, special, log and cache roles');
    my $native = status();
    $native =~ s/\nerrors:/\tspecial\n\t  mirror-1 ONLINE 0 0 0\n\t    \/dev\/vtbd9 ONLINE 0 0 0\n\t    \/dev\/vtbd10 ONLINE 0 0 0\n\tlogs\n\t  mirror-2 ONLINE 0 0 0\n\t    \/dev\/vtbd4 ONLINE 0 0 0\n\t    \/dev\/vtbd5 ONLINE 0 0 0\n\tcache\n\t  \/dev\/vtbd7 ONLINE 0 0 0\n\t  \/dev\/vtbd8 ONLINE 0 0 0\n\nerrors:/x;
    is((verify($plan, $native))[0], 0, 'native readback accepts the mirrored log');
    my $wrong = $native;
    $wrong =~ s{\t[ ]{4}/dev/vtbd5}{\t  /dev/vtbd5}x or croak 'invalid log fixture';
    isnt((verify($plan, $wrong))[0], 0, 'moving a mirrored log member outside its mirror is rejected');
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
        is($exit, 0, "$case->[0] accepts sufficient special-device redundancy");
        is_deeply([map { substr($_, 2) } grep { /^C\t/x } split(/\n/x, $plan)],
            [@{$case->[3]}, 'special', 'mirror', map { '/dev/vtbd' . (20 + $_) } 1 .. $case->[2]],
            'native topology and all device roles are explicit');
        pop @special;
        $policy->{special_vdevs} = join(',', @special);
        isnt((compile($policy))[0], 0, "$case->[0] rejects weaker special-device redundancy");
    }
    for my $compression (qw(off lz4 gzip gzip-1 gzip-9 zstd zstd-1 zstd-19)) {
        for my $ashift (9, 12, 16) {
            my ($exit, $plan) = compile({ %{base()}, compression => $compression, ashift => $ashift });
            is($exit, 0, "$compression and ashift $ashift compile");
            is(settings($plan)->{compression}, $compression, 'compression is retained');
            is(settings($plan)->{ashift}, "$ashift", 'ashift is retained');
        }
    }
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

done_testing();
