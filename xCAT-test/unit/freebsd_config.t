#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_CONFIG_MODULE_DIR};
use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use MIME::Base64 qw(decode_base64);
use POSIX ();
use Test::More;
use xCAT::FreeBSDConfig;

my $root = abs_path(tempdir(CLEANUP => 1));
my $key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPu2fQbGvNixfzG3hYrKcXFP6eZDrZMDnuES0GhLWDPE';
sub write_file {
    my ($path, $text) = @_;
    open(my $handle, '>', $path) or die $!;
    print {$handle} $text or die $!;
    close($handle) or die $!;
}
sub rejected {
    my ($code, $pattern, $label) = @_;
    my $ok = eval { $code->(); 1 };
    ok(!$ok, "$label fails");
    like($@, $pattern, "$label reports its cause");
}
write_file("$root/cluster.pub", "$key\n");
write_file("$root/settings", "authorized_keys_file=$root/cluster.pub\n");
my $partition = "target_disk=vtbd0\ntarget_disk_ident=XCAT_TEST_SERIAL\nfilesystem=zfs\n";
write_file("$root/node1.disk", $partition);
my $settings = xCAT::FreeBSDConfig::load_settings('node1', "$root/settings", "$root/#NODE#.disk");
is($settings->{target_disk_ident}, 'XCAT_TEST_SERIAL', 'node-specific policy selects exact serial');
is($settings->{filesystem}, 'zfs', 'ZFS selection reaches settings');
is($settings->{swap_size}, '0', 'absent swap policy requests no swap');
is(decode_base64($settings->{authorized_key_base64}), "$key\n", 'plain verified key reaches configuration');
my $network = {master => '192.0.2.1', port => 3002, mac => '52:54:00:12:34:56',
    ipv4 => '192.0.2.10', netmask => '255.255.255.0', hostname => 'node1.example.test',
    dist_url => 'http://192.0.2.1:8080/install/freebsd15.1/dist', nameservers => '192.0.2.1,192.0.2.2'};
my $media = {release => '15.1-RELEASE', arch => 'x86_64', digest => 'd' x 64,
    files => {'usr/freebsd-dist/base.txz' => 'a' x 64, 'usr/freebsd-dist/kernel.txz' => 'b' x 64}};
my $generation = 'c' x 32;
my $rendered = xCAT::FreeBSDConfig::render('node1', $settings, $network, $media, $generation);
is($rendered, xCAT::FreeBSDConfig::render('node1', $settings, $network, $media, $generation),
    'rendering is deterministic');
write_file("$root/config", $rendered);
my $library = "$FindBin::Bin/../../xCAT-server/share/xcat/install/freebsd/xcat-install-lib.sh";
open(my $consumer, '-|', 'sh', '-c', '. "$1"; xcat_read_config "$2" || exit; printf "%s|%s|%s|%s|%s\n" "$XCAT_NODE" "$XCAT_GENERATION" "$XCAT_TARGET_DISK" "$XCAT_FILESYSTEM" "$XCAT_GATEWAY"',
    'sh', $library, "$root/config") or die $!;
my $received = do { local $/; <$consumer> };
ok(close($consumer), 'actual shell runtime accepts the generated configuration');
is($received, "node1|$generation|vtbd0|zfs|\n", 'runtime receives the exact generated fields');
my $fingerprint = xCAT::FreeBSDConfig::fingerprint('node1', $settings, $network, $media);
like($fingerprint, qr/\A[0-9a-f]{64}\z/, 'configuration has a content fingerprint');
is($fingerprint, xCAT::FreeBSDConfig::fingerprint('node1', $settings, $network, $media), 'same inputs reuse fingerprint');
isnt($fingerprint, xCAT::FreeBSDConfig::fingerprint('node1', {%$settings, target_disk_ident => 'OTHER'}, $network, $media),
    'disk identity changes fingerprint');
isnt($fingerprint, xCAT::FreeBSDConfig::fingerprint('node1', $settings, {%$network, port => 3003}, $media),
    'controller endpoint changes fingerprint');
isnt($fingerprint, xCAT::FreeBSDConfig::fingerprint('node1', $settings, $network, {%$media, digest => 'e' x 64}),
    'runtime image changes fingerprint even if distribution hashes match');
my $ufs = xCAT::FreeBSDConfig::render('node1', {%$settings, filesystem => 'ufs', swap_size => '2g'}, $network, $media, $generation);
like($ufs, qr/^filesystem=ufs\nswap_size=2g$/m, 'UFS and explicit swap remain available');

for my $case (
    ['target_disk', 'vtbd0; reboot', qr/disk/],
    ['target_disk_ident', '', qr/serial/],
    ['filesystem', 'ext4', qr/filesystem/],
    ['swap_size', 'auto', qr/swap/],
    ['authorized_key_base64', "bad\nvalue", qr/invalid/],
    ['extra', 'value', qr/Unsupported/],
) {
    rejected(sub { xCAT::FreeBSDConfig::render('node1', {%$settings, $case->[0] => $case->[1]}, $network, $media, $generation); },
        $case->[2], "invalid $case->[0]");
}
for my $case (
    ['master', '::1', qr/master/],
    ['ipv4', '192.0.2.256', qr/ipv4/],
    ['ipv4', '192.0.02.1', qr/ipv4/],
    ['netmask', '255.0.255.0', qr/netmask/],
    ['gateway', 'host.example.test', qr/gateway/],
    ['port', 65536, qr/port/],
    ['mac', '52:54:00:12:34', qr/MAC/],
    ['hostname', '../node1', qr/node name/],
    ['dist_url', 'http://192.0.2.1/install/../private', qr/URL/],
    ['nameservers', '192.0.2.1,', qr/name server/],
) {
    rejected(sub { xCAT::FreeBSDConfig::render('node1', $settings, {%$network, $case->[0] => $case->[1]}, $media, $generation); },
        $case->[2], "invalid network $case->[0]");
}
rejected(sub { xCAT::FreeBSDConfig::render('node1', $settings, $network, $media, 'invalid'); },
    qr/generation/, 'invalid generation');
rejected(sub { xCAT::FreeBSDConfig::render('node1', $settings, $network, {%$media, arch => 'aarch64'}, $generation); },
    qr/Unsupported media/, 'unsupported architecture');
rejected(sub { xCAT::FreeBSDConfig::render('node1', $settings, $network, {%$media, files => {}}, $generation); },
    qr/base_sha256/, 'missing distribution digest');
rejected(sub { xCAT::FreeBSDConfig::load_settings('../node1', "$root/settings", "$root/#NODE#.disk"); },
    qr/node name/, 'node path traversal');

for my $case (
    ["target_disk=vtbd0\ntarget_disk=vtbd1\n", qr/Duplicate/],
    ["target_disk=vtbd0\ncommand=reboot\n", qr/Unsupported/],
    ["target_disk=vtbd0\r\n", qr/control characters/],
    ["target_disk vtbd0\n", qr/key=value/],
) {
    write_file("$root/bad.disk", $case->[0]);
    rejected(sub { xCAT::FreeBSDConfig::load_settings('node1', "$root/settings", "$root/bad.disk"); },
        $case->[1], 'malformed policy');
}
write_file("$root/bad-key.pub", "command=\"reboot\" $key\n");
write_file("$root/bad-settings", "authorized_keys_file=$root/bad-key.pub\n");
rejected(sub { xCAT::FreeBSDConfig::load_settings('node1', "$root/bad-settings", "$root/node1.disk"); },
    qr/plain SSH/, 'authorized key options');
write_file("$root/bad-key.pub", 'x' x 16385);
rejected(sub { xCAT::FreeBSDConfig::load_settings('node1', "$root/bad-settings", "$root/node1.disk"); },
    qr/bounded regular/, 'oversized public key file');
write_file("$root/bad-key.pub", 'ssh-ed25519 AAAA' . "\n");
rejected(sub { xCAT::FreeBSDConfig::load_settings('node1', "$root/bad-settings", "$root/node1.disk"); },
    qr/verification failed/, 'invalid SSH wire key');
symlink("$root/node1.disk", "$root/link.disk") or die $!;
rejected(sub { xCAT::FreeBSDConfig::load_settings('node1', "$root/settings", "$root/link.disk"); },
    qr/Cannot open/, 'symlink policy');

for my $kind (qw(template policy key)) {
    for my $change (qw(writable-file parent-symlink writable-parent traversal dot fifo)) {
        my $base = "$root/$kind-$change";
        make_path("$base/input", "$base/outside");
        write_file("$base/input/settings", "authorized_keys_file=$base/input/key.pub\n");
        write_file("$base/input/disk", $partition);
        write_file("$base/input/key.pub", "$key\n");
        my $name = { template => 'settings', policy => 'disk', key => 'key.pub' }->{$kind};
        my $selected = "$base/input/$name";
        my ($template_path, $policy_path) = ("$base/input/settings", "$base/input/disk");
        if ($change eq 'writable-file') {
            chmod(0666, $selected) or die $!;
        } elsif ($change eq 'parent-symlink') {
            rename($selected, "$base/outside/$name") or die $!;
            symlink("$base/outside", "$base/alias") or die $!;
            $selected = "$base/alias/$name";
        } elsif ($change eq 'writable-parent') {
            rename($selected, "$base/outside/$name") or die $!;
            chmod(0777, "$base/outside") or die $!;
            $selected = "$base/outside/$name";
        } elsif ($change eq 'traversal') {
            $selected = "$base/outside/../input/$name";
        } elsif ($change eq 'dot') {
            $selected = "$base/input/./$name";
        } else {
            unlink($selected) or die $!;
            POSIX::mkfifo($selected, 0644) == 0 or die $!;
        }
        if ($kind eq 'template') {
            $template_path = $selected;
        } elsif ($kind eq 'policy') {
            $policy_path = $selected;
        } else {
            write_file($template_path, "authorized_keys_file=$selected\n");
        }
        local $SIG{ALRM} = sub { die "blocked configuration read\n"; };
        alarm(5);
        rejected(sub { xCAT::FreeBSDConfig::load_settings('node1', $template_path, $policy_path); },
            qr/Unsafe configuration|traversal|bounded regular/, "$kind $change");
        alarm(0);
    }
}

SKIP: {
    skip 'changing fixture ownership requires root', 6 unless $> == 0;
    for my $kind (qw(template policy key)) {
        my $base = "$root/$kind-foreign-owner";
        make_path($base);
        write_file("$base/settings", "authorized_keys_file=$base/key.pub\n");
        write_file("$base/disk", $partition);
        write_file("$base/key.pub", "$key\n");
        my $name = { template => 'settings', policy => 'disk', key => 'key.pub' }->{$kind};
        chown(65534, -1, "$base/$name") or die $!;
        rejected(sub { xCAT::FreeBSDConfig::load_settings('node1', "$base/settings", "$base/disk"); },
            qr/Unsafe configuration file/, "$kind foreign owner");
    }
}

done_testing();
