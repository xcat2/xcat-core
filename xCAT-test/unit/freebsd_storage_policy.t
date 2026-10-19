#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_CONFIG_MODULE_DIR};
use Carp qw(croak);
use Cwd qw(abs_path);
use File::Temp qw(tempdir);
use Test::More;
use xCAT::FreeBSDConfig;

my $root = abs_path(tempdir(CLEANUP => 1));
my $planner = abs_path("$FindBin::Bin/../../xCAT/postscripts/configzfs-freebsd.awk");
my $key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPu2fQbGvNixfzG3hYrKcXFP6eZDrZMDnuES0GhLWDPE';
sub write_file {
    my ($path, $text) = @_;
    open(my $file, '>', $path) or croak $!;
    print {$file} $text or croak $!;
    close($file) or croak $!;
    return;
}
write_file("$root/key.pub", "$key\n");
write_file("$root/settings", "authorized_keys_file=$root/key.pub\n");
my $os = "filesystem=zfs\nzfs_topology=mirror\nzfs_vdevs=vtbd0\@OS0,vtbd1\@OS1\nswap_mode=none\n";
my $tank = "[pool tank]\naction=create\ntopology=mirror\nvdevs=vtbd2\@DATA2,vtbd3\@DATA3\n";
my $archive = "[pool archive]\naction=create\ntopology=draid1:2d:4c:1s\n"
  . "vdevs=vtbd4\@DATA4,vtbd5\@DATA5,vtbd6\@DATA6,vtbd7\@DATA7\ncompression=zstd-3\nashift=13\n";
sub settings {
    my $text = shift;
    write_file("$root/node1.disk", $text);
    return xCAT::FreeBSDConfig::load_settings('node1', "$root/settings", "$root/#NODE#.disk", $planner);
}
sub rejects {
    my ($text, $pattern, $label) = @_;
    my $result = eval { settings($text); };
    ok(!$result, "$label is rejected before preparation");
    like($@, $pattern, "$label reports the cause");
    return;
}

my $legacy = settings($os);
ok(!exists($legacy->{data_storage}), 'legacy OS-only policy has no automatic data operation');
my $explicit = eval { settings("[os]\n$os"); };
is_deeply($explicit, $legacy, 'explicit OS section preserves legacy settings');
my $multi = eval { settings("[os]\n$os$tank$archive"); };
ok($multi, 'partitionfile compiles the OS and two data pools through the native planner');
if (!$multi) { diag($@); done_testing(); exit; }
my $pools = $multi->{data_storage}{pools};
is_deeply([map { $_->{name} } @$pools], [qw(archive tank)], 'named pools have deterministic order');
is($multi->{preserve_disks}, join(',', map { "vtbd$_\@DATA$_" } 2 .. 7),
    'every data disk is automatically protected from OS erasure');
like($pools->[0]{policy}, qr/^topology=draid1:2d:4c:1s$/mx, 'dRAID geometry survives compilation');
like($pools->[0]{policy}, qr/^compression=zstd-3$/mx, 'pool compression is independent of the OS');
like($pools->[0]{policy}, qr/^ashift=13$/mx, 'pool alignment is independent of the OS');
like($pools->[1]{policy}, qr/^compression=lz4$/mx, 'default compression is explicit in the delivered policy');
like($pools->[1]{policy}, qr/^os_disks=vtbd0\@OS0,vtbd1\@OS1$/mx, 'OS identities are derived, not administrator supplied');
is_deeply(settings("$os$archive$tank"), $multi, 'section ordering does not change the compiled declaration');
my $preserved = settings($os . "preserve_disks=vtbd8\@KEEP\n" . $tank);
is($preserved->{preserve_disks}, 'vtbd2@DATA2,vtbd3@DATA3,vtbd8@KEEP', 'explicit preservation adds to derived data members');
my $auxiliary = settings($os . $tank . "log_vdevs=vtbd8\@LOG\ncache_vdevs=vtbd9\@CACHE\n"
    . "special_vdevs=vtbd10\@SPECIAL0,vtbd11\@SPECIAL1\nspecial_small_blocks=4096\n");
is($auxiliary->{preserve_disks}, 'vtbd10@SPECIAL0,vtbd11@SPECIAL1,vtbd2@DATA2,vtbd3@DATA3,vtbd8@LOG,vtbd9@CACHE',
    'SLOG, L2ARC and special members are also protected');
my $import = $tank;
$import =~ s/action=create/action=import\nguid=18446744073709551615/x;
like(settings($os . $import)->{data_storage}{pools}[0]{policy}, qr/^guid=18446744073709551615$/mx,
    'reinstall retains the full unsigned pool identity');
my $encrypted = settings($os . $tank . "encryption=aes-256-gcm\nkey_source=passwd\n");
is($encrypted->{data_storage}{pools}[0]{key_source}, 'passwd', 'encryption selects enrolled table credentials');
like($encrypted->{data_storage}{pools}[0]{policy}, qr{^keyfile=/etc/xcat/keys/tank[.]key$}mx,
    'the generated native policy uses the fixed private node path');
unlike($encrypted->{data_storage}{pools}[0]{policy}, qr/key_source/x, 'controller credential selection is not a native policy field');
my $named_os = $tank;
$named_os =~ s/pool[ ]tank/pool os/x;
is(settings($os . $named_os)->{data_storage}{pools}[0]{name}, 'os', 'a pool named os remains distinct from the OS section');
for my $filesystem (qw(ufs zfs)) {
    my $scalar = settings("filesystem=$filesystem\ntarget_disk=vtbd0\ntarget_disk_ident=OS0\n$tank");
    is($scalar->{target_disk}, 'vtbd0', "$filesystem single-disk OS retains its target");
    like($scalar->{data_storage}{pools}[0]{policy}, qr/^os_disks=vtbd0\@OS0$/mx,
        "$filesystem single-disk OS is excluded from the data policy");
}
for my $invalid (
    ["$tank", qr/OS[ ]disk[ ]policy/x, 'missing OS section'],
    ["$os$tank$tank", qr/Duplicate[ ]data[ ]pool[ ]section/x, 'duplicate pool'],
    ["$os$tank\naction=import\n", qr/Duplicate[ ]data[ ]pool[ ]setting/x, 'duplicate setting'],
    ["[os]\n$os\n[os]\n", qr/precede[ ]data[ ]pools/x, 'duplicate OS section'],
    ["$os$tank\n[os]\n", qr/precede[ ]data[ ]pools/x, 'late OS section'],
    ["$os$tank\ncommand=destroy\n", qr/Unsupported[ ]data[ ]pool[ ]setting/x, 'unknown pool option'],
    ["$os$tank\nos_disks=vtbd9\@OVERRIDE\n", qr/Unsupported[ ]data[ ]pool[ ]setting/x, 'OS identity override'],
    ["$os$tank\nkeyfile=/tmp/key\n", qr/Unsupported[ ]data[ ]pool[ ]setting/x, 'key path override'],
    ["$os$tank\nencryption=aes-256-gcm\n", qr/key_source=passwd/x, 'missing key selection'],
    ["$os$tank\nkey_source=passwd\n", qr/requires[ ]encrypted[ ]data/x, 'key without encryption'],
    ["$os$tank\nencryption=aes-256-gcm\nkey_source=file\n", qr/key_source=passwd/x, 'unsupported key selection'],
    ["$os$tank\nmountpoint=/data/shared\n$archive\nmountpoint=/data/shared\n", qr/distinct[ ]mountpoints/x, 'mountpoint collision'],
) { rejects(@$invalid); }
for my $case (
    ['action=create', 'action=import', qr/preserved[ ]pool[ ]GUID/x, 'import without GUID'],
    ['vtbd2@DATA2', 'vtbd0@DATA2', qr/overlap/x, 'OS device reuse'],
    ['vtbd2@DATA2', 'vtbd2@OS0', qr/overlap/x, 'OS serial reuse'],
    ['vtbd2@DATA2', 'vtbd02@DATA2', qr/Invalid[ ]device/x, 'leading zero device unit'],
    ['vtbd2@DATA2', 'vtbd100000@DATA2', qr/Invalid[ ]device/x, 'oversized device unit'],
    ['pool tank', 'pool zroot', qr/Invalid[ ]data[ ]pool/x, 'reserved OS pool name'],
) {
    my ($old, $new, $pattern, $label) = @$case;
    my $bad = $tank;
    $bad =~ s/\Q$old\E/$new/x;
    rejects($os . $bad, $pattern, $label);
}
for my $reuse (['vtbd4@DATA4', 'vtbd2@DATA4'], ['vtbd4@DATA4', 'vtbd4@DATA2']) {
    my $bad = $archive;
    $bad =~ s/\Q$reuse->[0]\E/$reuse->[1]/x;
    rejects($os . $tank . $bad, qr/distinct[ ]device[ ]names[ ]and[ ]serials/x, 'cross-pool identity reuse');
}
done_testing();
