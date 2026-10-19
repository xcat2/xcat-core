#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_CONFIG_MODULE_DIR};
use Carp qw(croak);
use Cwd qw(abs_path);
use File::Temp qw(tempdir);
use MIME::Base64 qw(decode_base64);
use Test::More;
use xCAT::FreeBSDConfig;
use xCAT::FreeBSDPkg;
use xCAT::FreeBSDStorage;

my $root = abs_path(tempdir(CLEANUP => 1));
my $scripts = abs_path("$FindBin::Bin/../../xCAT/postscripts");
sub write_file {
    my ($path, $text) = @_;
    open(my $file, '>', $path) or croak $!;
    print {$file} $text or croak $!;
    close($file) or croak $!;
    return $path;
}
write_file("$root/key.pub", "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPu2fQbGvNixfzG3hYrKcXFP6eZDrZMDnuES0GhLWDPE\n");
write_file("$root/settings", "authorized_keys_file=$root/key.pub\n");
my $os = "[os]\nfilesystem=zfs\nzfs_topology=mirror\nzfs_vdevs=vtbd0\@OS0,vtbd1\@OS1\nswap_mode=none\n";
my $pool = "[pool tank]\naction=create\ntopology=mirror\nvdevs=vtbd2\@DATA2,vtbd3\@DATA3\n";
my $children = "[dataset tank/projects]\ncompression=zstd-3\nquota=1T\n"
  . "[dataset tank/projects/team]\nrecordsize=1M\nrefquota=100G\nreservation=0\nrefreservation=none\natime=off\n";
my $system = "[dataset zroot/usr/local]\ncompression=lz4\nrecordsize=128K\n"
  . "[dataset zroot/var/log]\nquota=1G\n";
sub settings {
    my $text = shift;
    write_file("$root/node.disk", $text);
    return xCAT::FreeBSDConfig::load_settings('node1', "$root/settings", "$root/node.disk", "$scripts/configzfs-freebsd.awk");
}
sub compile_plan {
    my $policy = shift;
    my $result = xCAT::FreeBSDPkg::run_command(['/usr/bin/awk', '-f', "$scripts/configzfs-datasets.awk",
        write_file("$root/datasets", $policy)], environment => { LC_ALL => 'C' }, timeout => 15,
        stdout_limit => 65536, stderr_limit => 4096);
    return $result;
}
sub rejected {
    my ($text, $pattern, $label) = @_;
    my $result = eval { settings($text); };
    ok(!$result, "$label is rejected before preparation");
    like($@, $pattern, "$label reports its cause");
    return;
}
my $selected = eval { settings($os . $pool . $children . $system); };
ok($selected, 'OS and data dataset sections compile through load_settings');
if (!$selected) { diag($@); done_testing(); exit; }
my $storage = delete $selected->{data_storage};
my $data = $storage->{pools}[0]{datasets};
my $data_plan = compile_plan($data);
is($data_plan->{exitcode}, 0, 'native data planner accepts the delivered declaration');
is($data_plan->{stdout}, "tank/projects\tmountpoint=/data/tank/projects,canmount=on,compression=zstd-3,quota=1099511627776\n"
    . "tank/projects/team\tmountpoint=/data/tank/projects/team,canmount=on,recordsize=1048576,atime=off,refquota=107374182400,reservation=none,refreservation=none\n",
    'child order, inherited path and numeric properties are deterministic');
my $os_plan = compile_plan(decode_base64($selected->{zfs_datasets_base64}));
is($os_plan->{exitcode}, 0, 'native OS planner accepts the delivered declaration');
like($os_plan->{stdout}, qr{^zroot/ROOT/default\tmountpoint=/,canmount=on$}mx, 'native boot environment is retained');
like($os_plan->{stdout}, qr{^zroot/usr\tmountpoint=/usr,canmount=off$}mx, 'native unmounted parent is retained');
my %os_rows = map { split(/\t/x, $_, 2) } split(/\n/x, $os_plan->{stdout});
is($os_rows{'zroot/usr/local'}, 'mountpoint=/usr/local,canmount=on,compression=lz4,recordsize=131072',
    'custom OS dataset is created with its own mounted filesystem');
is($os_rows{'zroot/var/log'}, 'mountpoint=/var/log,canmount=on,exec=off,setuid=off,quota=1073741824',
    'overrides preserve installer security properties');
is(scalar(split(/\n/x, $os_plan->{stdout})), 14, 'all thirteen native datasets and one custom child are retained');
is_deeply(xCAT::FreeBSDStorage::files('node1', $storage), {
    'tank.conf' => $storage->{pools}[0]{policy}, 'tank.datasets' => $data, pools => "tank\n" },
    'dataset declaration uses the same private pool payload');
my $os_only = settings($os . $system);
ok(!exists($os_only->{data_storage}), 'OS-only dataset declarations need no data postscript');
my $ufs = settings("filesystem=ufs\ntarget_disk=vtbd0\ntarget_disk_ident=OS0\n" . $pool . $children);
ok(exists($ufs->{data_storage}{pools}[0]{datasets}), 'UFS OS can provision datasets in dedicated ZFS data pools');
my $encrypted = settings($os . $pool . "encryption=aes-256-gcm\nkey_source=passwd\n" . $children);
is($encrypted->{data_storage}{pools}[0]{datasets}, $data, 'children carry no independent encryption settings');
my $reordered = settings($os . $system . $children . $pool);
is($reordered->{data_storage}{pools}[0]{datasets}, $data, 'declaration order does not change policy');
my $mounts = settings($os . $pool . "[dataset tank/projects]\nmountpoint=/data/tank/work\n[dataset tank/projects/team]\n");
like(compile_plan($mounts->{data_storage}{pools}[0]{datasets})->{stdout}, qr{tank/projects/team\tmountpoint=/data/tank/work/team,}x,
    'child default mountpoint follows the declared parent mountpoint');
my $dotted = settings($os . $pool . "mountpoint=/srv/archive.v2\n[dataset tank/projects]\n[dataset tank/projects/team]\n");
is(compile_plan($dotted->{data_storage}{pools}[0]{datasets})->{stdout},
    "tank/projects\tmountpoint=/srv/archive.v2/projects,canmount=on\n"
      . "tank/projects/team\tmountpoint=/srv/archive.v2/projects/team,canmount=on\n",
    'dataset paths retain the pool planner dotted mountpoint');
my $hyphen = settings($os . $pool . "mountpoint=/srv/-scratch\n[dataset tank/projects]\nmountpoint=/srv/-scratch/work\n");
is(compile_plan($hyphen->{data_storage}{pools}[0]{datasets})->{stdout},
    "tank/projects\tmountpoint=/srv/-scratch/work,canmount=on\n",
    'custom child mountpoint retains the valid pool root prefix');
my $deep_sections = join('', map { "[dataset tank/$_]\n" } qw(a a/b a/b/c a/b/c/d a/b/c/d/e a/b/c/d/e/f a/b/c/d/e/f/g));
my $deep = settings($os . $pool . $deep_sections . "mountpoint=/data/tank/a/b/c/d/e/f/g\n");
my %deep_rows = map { split(/\t/x, $_, 2) } split(/\n/x, compile_plan($deep->{data_storage}{pools}[0]{datasets})->{stdout});
is($deep_rows{'tank/a/b/c/d/e/f/g'}, 'mountpoint=/data/tank/a/b/c/d/e/f/g,canmount=on',
    'custom mountpoint accepts the full supported dataset depth');
for my $case (
    ["[dataset other/home]\n", qr/declared[ ]pool/x, 'unknown pool'],
    ["[dataset tank]\n", qr/another[ ]pool/x, 'pool root'],
    ["[dataset tank/../etc]\n", qr/Invalid.*name/x, 'parent traversal'],
    ["[dataset tank/a//b]\n", qr/Invalid.*name/x, 'empty component'],
    ["[dataset tank/a/b]\n", qr/parent[ ]dataset/x, 'undeclared parent'],
    ["[dataset tank/a]\n[dataset tank/a]\n", qr/Duplicate[ ]dataset/x, 'duplicate section'],
    ["[dataset tank/a]\nquota=1G\nquota=2G\n", qr/Duplicate[ ]dataset/x, 'duplicate property'],
    ["[dataset tank/a]\nmountpoint=/srv/tank/a\n", qr/outside[ ]its[ ]parent/x, 'escaped data mount'],
    ["[dataset tank/a]\nmountpoint=/data/tank/same\n[dataset tank/b]\nmountpoint=/data/tank/same\n", qr/Overlapping/x, 'duplicate mount'],
    ["[dataset tank/a]\nmountpoint=/data/tank/work\n[dataset tank/b]\nmountpoint=/data/tank/work/b\n", qr/Overlapping/x, 'nested sibling mount'],
    ["[dataset zroot/ROOT/default]\ncompression=lz4\n", qr/Reserved[ ]OS/x, 'boot environment override'],
    ["[dataset zroot/boot]\n", qr/Reserved[ ]OS/x, 'boot filesystem'],
    ["[dataset zroot/usr]\nmountpoint=/other\n", qr/OS[ ]dataset[ ]mountpoints/x, 'system mount relocation'],
    ["[dataset tank/a]\nencryption=off\n", qr/Unsupported.*property/x, 'child encryption override'],
    ["[dataset tank/a]\ncanmount=off\n", qr/Unsupported.*property/x, 'mount behavior override'],
    ["[dataset tank/a]\nrecordsize=3K\n", qr/recordsize/x, 'non-power recordsize'],
    ["[dataset tank/a]\nrecordsize=2M\n", qr/recordsize/x, 'recordsize beyond portable limit'],
    ["[dataset tank/a]\nquota=5P\n", qr/exceeds/x, 'oversized quota'],
    ["[dataset tank/a]\nquota=-1\n", qr/size/x, 'negative quota'],
    ["[dataset tank/a]\ncompression=lz4;reboot\n", qr/compression/x, 'shell injection'],
    ["[dataset tank/a]\natime=yes\n", qr/atime/x, 'invalid boolean'],
) { rejected($os . $pool . $case->[0], $case->[1], $case->[2]); }
rejected("filesystem=zfs\ntarget_disk=vtbd0\ntarget_disk_ident=OS0\n$system", qr/explicit[ ]ZFS[ ]disk/x, 'scalar OS dataset policy');
my $network = { master => '192.0.2.1', port => 3002, mac => '52:54:00:12:34:56',
    ipv4 => '192.0.2.2', netmask => '255.255.255.0', gateway => '', hostname => 'node1.example.test',
    install_url => 'http://192.0.2.1/install/freebsd/node1', nameservers => '' };
my $media = { format => 'xcat-mfsbsd-2', release => '15.1-RELEASE', arch => 'x86_64', digest => 'd' x 64,
    files => { 'xcat/runtime.tsv' => 'e' x 64 }, install_contract => 'xcat-freebsd-install-6',
    dataset_contract => 'xcat-freebsd-datasets-1' };
my $boot = xCAT::FreeBSDConfig::boot_settings($selected, '', {}, $media);
my $install = { media => $media, package_plan_sha256 => 'f' x 64 };
my $wire = xCAT::FreeBSDConfig::render_pkgbase('node1', $boot, $network, $install, 'a' x 32);
like($wire, qr/^zfs_datasets_base64=\Q$selected->{zfs_datasets_base64}\E$/mx, 'OS declarations are pinned in installer configuration');
my %old = %$media;
delete $old{dataset_contract};
my $legacy = eval { xCAT::FreeBSDConfig::render_pkgbase('node1', $boot, $network, { %$install, media => \%old }, 'a' x 32); };
ok(!$legacy, 'older runtime cannot silently ignore OS datasets');
like($@, qr/xcat-freebsd-datasets-1/x, 'missing runtime capability is explicit');
done_testing();
