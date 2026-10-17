#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_CONFIG_MODULE_DIR};
use Carp qw(croak);
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
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
sub runtime_library {
    my $directory = $ENV{XCAT_FREEBSD_INSTALLER_DIR}
      || "$FindBin::Bin/../../xCAT-server/share/xcat/install/freebsd";
    return "$directory/xcat-install-lib.sh";
}
my $library = runtime_library();
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

sub legacy_wire_cases {
    my $expected = "format=xcat-freebsd-install-1\nrelease=15.1-RELEASE\nnode=node1\n"
      . "generation=$generation\nmaster=192.0.2.1\nport=3002\nmac=52:54:00:12:34:56\n"
      . "ipv4=192.0.2.10\nnetmask=255.255.255.0\ngateway=\nhostname=node1.example.test\n"
      . "target_disk=vtbd0\ntarget_disk_ident=XCAT_TEST_SERIAL\nfilesystem=zfs\nswap_size=0\n"
      . "dist_url=http://192.0.2.1:8080/install/freebsd15.1/dist\n"
      . 'base_sha256=' . ('a' x 64) . "\nkernel_sha256=" . ('b' x 64) . "\n"
      . "authorized_key_base64=$settings->{authorized_key_base64}\nnameservers=192.0.2.1,192.0.2.2\n";
    is($rendered, $expected, 'legacy rendering retains its exact bytes and field order');
    my $zero_generation = '0' x 32;
    $expected =~ s/^generation=[0-9a-f]+$/generation=$zero_generation/mx;
    is($fingerprint, sha256_hex(('d' x 64) . "\n" . $expected),
        'legacy fingerprint retains the media prefix and zero-generation wire bytes');
    return;
}

sub pkgbase_inputs {
    my %selected_network = %$network;
    delete($selected_network{dist_url});
    $selected_network{install_url} = 'http://192.0.2.1:8080/install';
    return (\%selected_network, { package_plan_sha256 => '5' x 64,
        media => { format => 'xcat-mfsbsd-2', release => '15.1-RELEASE',
            arch => 'x86_64', digest => '3' x 64, files => { 'xcat/runtime.tsv' => '4' x 64 } } });
}

sub read_generated_config {
    my ($bytes, $script) = @_;
    write_file("$root/pkgbase-config", $bytes);
    open(my $reader, '-|', 'sh', '-c', '. "$1"; xcat_read_config "$2" || exit; ' . $script,
        'sh', $library, "$root/pkgbase-config") or croak $!;
    local $/ = undef;
    my $output = <$reader>;
    close($reader);
    return ($? >> 8, defined($output) ? $output : '');
}

sub pkgbase_fingerprint_cases {
    my ($selected_network, $install) = @_;
    my $boot = $install->{media};
    my $original = xCAT::FreeBSDConfig::fingerprint_pkgbase('node1', $settings, $selected_network, $install);
    like($original, qr/\A[0-9a-f]{64}\z/x, 'pkgbase configuration has a SHA256 fingerprint');
    is($original, xCAT::FreeBSDConfig::fingerprint_pkgbase('node1', $settings, $selected_network, $install),
        'the same pkgbase inputs retain their fingerprint');
    isnt($original, xCAT::FreeBSDConfig::fingerprint_pkgbase('node1', $settings, $selected_network,
        { %$install, package_plan_sha256 => '6' x 64 }),
        'a different package plan changes the fingerprint');
    isnt($original, xCAT::FreeBSDConfig::fingerprint_pkgbase('node1', $settings, $selected_network,
        { %$install, media => { %$boot, digest => '6' x 64 } }), 'a different boot artifact changes the fingerprint');
    isnt($original, xCAT::FreeBSDConfig::fingerprint_pkgbase('node1', $settings, $selected_network,
        { %$install, media => { %$boot, files => { 'xcat/runtime.tsv' => '6' x 64 } } }),
        'a different runtime descriptor changes the fingerprint');
    isnt($original, xCAT::FreeBSDConfig::fingerprint_pkgbase('node1', $settings,
        { %$selected_network, install_url => 'http://192.0.2.2/install' }, $install),
        'a different installation endpoint changes the fingerprint');
    isnt($original, xCAT::FreeBSDConfig::fingerprint_pkgbase('node1',
        { %$settings, target_disk_ident => 'ANOTHER_DISK' }, $selected_network, $install),
        'a different disk identity changes the pkgbase fingerprint');
    return;
}

sub pkgbase_install_input_cases {
    my ($selected_network, $install) = @_;
    for my $bad (undef, '', [], {}, { media => $install->{media} },
        { package_plan_sha256 => $install->{package_plan_sha256} },
        { %$install, generation => $generation },
        { media => $install->{media}, plan_digest => $install->{package_plan_sha256} }) {
        rejected(sub { xCAT::FreeBSDConfig::render_pkgbase('node1', $settings, $selected_network,
            $bad, $generation) }, qr/install[ ]inputs/ix, 'malformed immutable install inputs');
        rejected(sub { xCAT::FreeBSDConfig::fingerprint_pkgbase('node1', $settings, $selected_network,
            $bad) }, qr/install[ ]inputs/ix, 'fingerprinting validates the same install input roster');
    }
    rejected(sub { xCAT::FreeBSDConfig::render_pkgbase('node1', $settings, $selected_network,
        $install) }, qr/five[ ]arguments/ix, 'rendering requires a distinct generation argument');
    rejected(sub { xCAT::FreeBSDConfig::render_pkgbase('node1', $settings, $selected_network,
        $install, $generation, 'extra') }, qr/five[ ]arguments/ix, 'rendering rejects a sixth argument');
    rejected(sub { xCAT::FreeBSDConfig::fingerprint_pkgbase('node1', $settings, $selected_network,
        $install, $generation) }, qr/four[ ]arguments/ix, 'fingerprinting rejects a caller generation argument');
    return;
}

sub pkgbase_invalid_cases {
    my ($selected_network, $install) = @_;
    my $boot = $install->{media};
    for my $bad (undef, '', [], 'A' x 64, 'a' x 63, 'a' x 65, "a\n" . ('a' x 62)) {
        rejected(sub { xCAT::FreeBSDConfig::render_pkgbase('node1', $settings, $selected_network,
            { %$install, package_plan_sha256 => $bad }, $generation) }, qr/(?:plan|digest|sha256)/ix, 'invalid package plan pin');
        rejected(sub { xCAT::FreeBSDConfig::render_pkgbase('node1', $settings, $selected_network,
            { %$install, media => { %$boot, digest => $bad } }, $generation) },
            qr/(?:media|digest|sha256)/ix, 'invalid boot artifact pin');
        rejected(sub { xCAT::FreeBSDConfig::render_pkgbase('node1', $settings, $selected_network,
            { %$install, media => { %$boot, files => { 'xcat/runtime.tsv' => $bad } } }, $generation) },
            qr/(?:runtime|digest|sha256)/ix, 'invalid runtime descriptor pin');
    }
    rejected(sub { xCAT::FreeBSDConfig::render_pkgbase('node1', $settings, $selected_network,
        { %$install, media => { %$boot, files => {} } }, $generation) }, qr/runtime/ix, 'absent runtime descriptor');
    for my $case ([format => undef], [format => 'xcat-mfsbsd-1'], [release => '14.3-RELEASE'], [arch => 'amd64']) {
        rejected(sub { xCAT::FreeBSDConfig::render_pkgbase('node1', $settings, $selected_network,
            { %$install, media => { %$boot, @$case } }, $generation) }, qr/media/ix, 'incompatible boot media');
    }
    for my $field (qw(dist_url base_sha256 kernel_sha256)) {
        rejected(sub { xCAT::FreeBSDConfig::render_pkgbase('node1', { %$settings, $field => '' },
            $selected_network, $install, $generation) },
            qr/(?:Unsupported|setting)/ix, "pkgbase rendering rejects legacy field $field");
    }
    for my $field (qw(install_url package_plan_sha256 boot_media_sha256 runtime_sha256)) {
        rejected(sub { xCAT::FreeBSDConfig::render('node1', { %$settings, $field => '' },
            $network, $media, $generation) }, qr/Unsupported/ix, "legacy rendering rejects pkgbase field $field");
    }
    for my $url (undef, '', 'file:///install', 'http://192.0.2.1/install/../private', "http://192.0.2.1/install\nextra") {
        rejected(sub { xCAT::FreeBSDConfig::render_pkgbase('node1', $settings,
            { %$selected_network, install_url => $url }, $install, $generation) },
            qr/(?:install|URL)/ix, 'invalid installation URL');
    }
    rejected(sub { xCAT::FreeBSDConfig::render_pkgbase('node1', $settings, $selected_network,
        $install, 'bad-generation') }, qr/generation/ix, 'pkgbase generation must be pinned');
    rejected(sub { xCAT::FreeBSDConfig::render_pkgbase('node1', { %$settings, target_disk => 'ada0;reboot' },
        $selected_network, $install, $generation) }, qr/disk/ix, 'pkgbase retains disk field validation');
    rejected(sub { xCAT::FreeBSDConfig::render_pkgbase('node1', $settings,
        { %$selected_network, ipv4 => '192.0.2.256' }, $install, $generation) },
        qr/ipv4/ix, 'pkgbase retains network field validation');
    return;
}

sub pkgbase_size_cases {
    my ($selected_network, $install) = @_;
    my $small = xCAT::FreeBSDConfig::render_pkgbase('node1', { %$settings, authorized_key_base64 => 'A' },
        $selected_network, $install, $generation);
    my $key_size = 32768 - length($small) + 1;
    my $exact = xCAT::FreeBSDConfig::render_pkgbase('node1',
        { %$settings, authorized_key_base64 => 'A' x $key_size }, $selected_network, $install, $generation);
    is(length($exact), 32768, 'pkgbase renderer accepts exactly 32768 bytes');
    my ($status) = read_generated_config($exact, 'printf "accepted\n"');
    is($status, 0, 'the shell reader accepts the renderer byte limit');
    rejected(sub { xCAT::FreeBSDConfig::render_pkgbase('node1',
        { %$settings, authorized_key_base64 => 'A' x ($key_size + 1) },
        $selected_network, $install, $generation) },
        qr/(?:large|size|bound|32768)/ix, 'pkgbase renderer rejects 32769 bytes');
    return;
}

sub pkgbase_codec_cases {
    my ($selected_network, $install) = pkgbase_inputs();
    my $bytes = eval { xCAT::FreeBSDConfig::render_pkgbase('node1', $settings, $selected_network,
        $install, $generation) };
    is($@, '', 'pkgbase renderer accepts the pinned boot artifact and plan');
    return unless defined($bytes);
    is($bytes, xCAT::FreeBSDConfig::render_pkgbase('node1', $settings, $selected_network,
        $install, $generation), 'pkgbase rendering is deterministic');
    like($bytes, qr/\Aformat=xcat-freebsd-install-2\n/x, 'pkgbase configuration has its own format');
    unlike($bytes, qr/^(?:dist_url|base_sha256|kernel_sha256)=/mx, 'pkgbase configuration omits distribution fields');
    my ($status, $output) = read_generated_config($bytes,
        'printf "%s|%s|%s|%s|%s|%s|%s|%s\n" "$XCAT_NODE" "$XCAT_GENERATION" "$XCAT_TARGET_DISK" "$XCAT_FILESYSTEM"'
        . ' "$XCAT_INSTALL_URL" "$XCAT_PACKAGE_PLAN_SHA256" "$XCAT_BOOT_MEDIA_SHA256" "$XCAT_RUNTIME_SHA256"');
    is($status, 0, 'the actual shell reader accepts rendered pkgbase configuration');
    is($output, "node1|$generation|vtbd0|zfs|$selected_network->{install_url}|$install->{package_plan_sha256}|$install->{media}{digest}|"
        . "$install->{media}{files}{'xcat/runtime.tsv'}\n", 'the shell reader receives the exact node settings and all package pins');
    pkgbase_fingerprint_cases($selected_network, $install);
    pkgbase_install_input_cases($selected_network, $install);
    pkgbase_invalid_cases($selected_network, $install);
    pkgbase_size_cases($selected_network, $install);
    return;
}

subtest 'legacy configuration wire compatibility' => \&legacy_wire_cases;
subtest 'pkgbase configuration codec and identity' => \&pkgbase_codec_cases;

sub dedicated_os_policy_cases {
    my ($selected_network, $install) = pkgbase_inputs();
    my $media5 = { %{$install->{media}}, install_contract => 'xcat-freebsd-install-5' };
    my %policy = (filesystem => 'zfs', swap_size => '0', swap_mode => 'none',
        zfs_topology => 'mirror', zfs_vdevs => 'vtbd0@OS_A,vtbd1@OS_B',
        zfs_compression => 'lz4', authorized_key_base64 => $settings->{authorized_key_base64});
    my $render_policy = sub {
        my ($selected, $chosen_media) = @_;
        $chosen_media ||= $media5;
        my $boot = xCAT::FreeBSDConfig::boot_settings($selected, '', {}, $chosen_media);
        return xCAT::FreeBSDConfig::render_pkgbase('node1', $boot, $selected_network,
            { %$install, media => $chosen_media }, $generation);
    };
    my $bytes = $render_policy->(\%policy);
    like($bytes, qr/\Aformat=xcat-freebsd-install-5\n/x, 'new disk policies require their runtime contract');
    my $default_properties = qr/zfs_compression=lz4\nzfs_ashift=12\n/x;
    my $default_action = qr/disk_action=empty\npreserve_disks=-\n/x;
    like($bytes, qr/$default_properties$default_action\z/x,
        'defaults retain explicit compression, sector alignment and empty-disk safety');
    my ($status, $output) = read_generated_config($bytes,
        'printf "%s|%s|%s|%s\n" "$XCAT_ZFS_COMPRESSION" "$XCAT_ZFS_ASHIFT" "$XCAT_DISK_ACTION" "$XCAT_PRESERVE_DISKS"');
    is($status, 0, 'the native reader accepts the generated policy');
    is($output, "lz4|12|empty|-\n", 'the runtime receives exact defaults');
    for my $compression (qw(off lz4 gzip gzip-9 zstd zstd-19)) {
        for my $ashift (9, 12, 16) {
            my $configured = $render_policy->({ %policy, zfs_compression => $compression, zfs_ashift => $ashift,
                disk_action => 'erase', preserve_disks => 'vtbd2@DATA_A,vtbd3@DATA_B' });
            my ($accepted, $members) = read_generated_config($configured, 'xcat_preserved_members');
            is($accepted, 0, "$compression and ashift $ashift reach the native parser");
            is($members, "vtbd2\tDATA_A\t1\nvtbd3\tDATA_B\t1\n", 'data identities remain separate from OS members');
        }
    }
    my $gzip = $render_policy->({ %policy, zfs_compression => 'gzip-6' });
    like($gzip, qr/^zfs_compression=gzip$/mx, 'the controller emits the native gzip-6 alias');
    $gzip =~ s/^zfs_compression=gzip$/zfs_compression=gzip-6/mx;
    my ($gzip_status, $gzip_value) = read_generated_config($gzip, 'printf "%s" "$XCAT_ZFS_COMPRESSION"');
    is($gzip_status, 0, 'the native reader independently accepts gzip-6');
    is($gzip_value, 'gzip', 'native readback compares the canonical compression name');
    my $single = $render_policy->({ %policy, zfs_topology => 'stripe', zfs_vdevs => 'vtbd0@OS_A' });
    is((read_generated_config($single, 'xcat_zfs_members'))[1], "vtbd0\tOS_A\t1\n", 'one OS disk uses the same guarded policy');
    for my $older (3, 4) {
        rejected(sub { $render_policy->(\%policy, { %$media5, install_contract => "xcat-freebsd-install-$older" }) },
            qr/requires?/x, 'an old runtime cannot silently drop the disk policy');
    }
    for my $bad ([zfs_compression => 'on'], [zfs_compression => 'zstd-20'], [zfs_ashift => 8],
        [zfs_ashift => '012'], [zfs_ashift => 17], [disk_action => 'preserve-partitions'],
        [preserve_disks => ''], [preserve_disks => 'vtbd0@DATA'], [preserve_disks => 'vtbd2@OS_A'],
        [preserve_disks => 'vtbd2@DATA,vtbd3@DATA'], [preserve_disks => '/dev/vtbd2@DATA']) {
        rejected(sub { $render_policy->({ %policy, @$bad }) }, qr/(compression|ashift|action|disk)/ix,
            "invalid $bad->[0] is rejected by the controller");
        my $mutant = $bytes;
        $mutant =~ s/^\Q$bad->[0]\E=.*$/$bad->[0]=$bad->[1]/mx;
        isnt((read_generated_config($mutant, 'printf unsafe'))[0], 0, 'the native reader independently rejects the invalid field');
    }
    for my $field (qw(zfs_compression zfs_ashift disk_action preserve_disks)) {
        my $missing = $bytes;
        $missing =~ s/^\Q$field\E=.*\n//mx;
        isnt((read_generated_config($missing, 'printf unsafe'))[0], 0, "the native reader requires $field");
    }
    done_testing();
    return;
}
subtest 'dedicated OS disk properties and reinstall policy' => \&dedicated_os_policy_cases;

subtest 'ordered redundant ZFS policy and native codec' => sub {
    my ($selected_network, $install) = pkgbase_inputs();
    my $media3 = { %{$install->{media}}, install_contract => 'xcat-freebsd-install-3' };
    my $media4 = { %$media3, install_contract => 'xcat-freebsd-install-4' };
    my $legacy = xCAT::FreeBSDConfig::boot_settings($settings, '', {}, $media3);
    my $wire3 = xCAT::FreeBSDConfig::render_pkgbase('node1', $legacy, $selected_network,
        { %$install, media => $media3 }, $generation);
    my $legacy4 = xCAT::FreeBSDConfig::boot_settings($settings, '', {}, $media4);
    is_deeply($legacy4, $legacy, 'new media retains legacy boot settings');
    my $compatible = eval { xCAT::FreeBSDConfig::render_pkgbase('node1', $legacy4, $selected_network,
        { %$install, media => $media4 }, $generation) };
    is($compatible, $wire3, 'legacy policy retains format3 bytes on new media');

    my @cases = (
        ['mirror', 'vtbd1@B,vtbd0@A', "vtbd1\tB\t1\nvtbd0\tA\t1\n"],
        ['mirror', 'ada0@A,da1@B,nda2@C', "ada0\tA\t1\nda1\tB\t1\nnda2\tC\t1\n"],
        ['raid10', 'vtbd3@D,vtbd1@B;vtbd2@C,vtbd0@A', "vtbd3\tD\t1\nvtbd1\tB\t1\nvtbd2\tC\t2\nvtbd0\tA\t2\n"],
        ['raidz1', 'vtbd0@A,vtbd1@B,vtbd2@C', "vtbd0\tA\t1\nvtbd1\tB\t1\nvtbd2\tC\t1\n"],
        ['raidz2', 'vtbd0@A,vtbd1@B,vtbd2@C,vtbd3@D', "vtbd0\tA\t1\nvtbd1\tB\t1\nvtbd2\tC\t1\nvtbd3\tD\t1\n"],
        ['raidz3', 'vtbd0@A,vtbd1@B,vtbd2@C,vtbd3@D,vtbd4@E', "vtbd0\tA\t1\nvtbd1\tB\t1\nvtbd2\tC\t1\nvtbd3\tD\t1\nvtbd4\tE\t1\n"],
        ['raid10', 'vtbd0@A,vtbd1@B;vtbd2@C,vtbd3@D;vtbd4@E,vtbd5@F',
            "vtbd0\tA\t1\nvtbd1\tB\t1\nvtbd2\tC\t2\nvtbd3\tD\t2\nvtbd4\tE\t3\nvtbd5\tF\t3\n"],
        ['mirror', 'nvd99999@' . ('A' x 128) . ',vtbd0@a', 'nvd99999' . "\t" . ('A' x 128) . "\t1\nvtbd0\ta\t1\n"],
        ['mirror', join(',', map { "vtbd$_\@S$_" } 0 .. 15), join('', map { "vtbd$_\tS$_\t1\n" } 0 .. 15)],
    );
    my $wire4;
    for my $case (@cases) {
        my ($topology, $members, $expected) = @$case;
        write_file("$root/redundant.disk", "filesystem=zfs\nzfs_topology=$topology\nzfs_vdevs=$members\nswap_mode=none\n");
        my $loaded = eval { xCAT::FreeBSDConfig::load_settings('node1', "$root/settings", "$root/redundant.disk") };
        ok($loaded, "$topology policy loads with explicit ordered members");
        if (!$loaded) { diag($@); next; }
        is($loaded->{swap_size}, '0', 'omitted size retains zero-swap default');
        my $boot = xCAT::FreeBSDConfig::boot_settings($loaded, '', {}, $media4);
        my $bytes = eval { xCAT::FreeBSDConfig::render_pkgbase('node1', $boot, $selected_network,
            { %$install, media => $media4 }, $generation) };
        ok(defined($bytes), "$topology renders against a capable image");
        if (!defined($bytes)) { diag($@); next; }
        my $expected_wire = $wire3;
        $expected_wire =~ s/format=xcat-freebsd-install-3/format=xcat-freebsd-install-4/x;
        $expected_wire =~ s/target_disk=vtbd0\ntarget_disk_ident=XCAT_TEST_SERIAL\n/zfs_topology=$topology\nzfs_vdevs=$members\nswap_mode=none\n/x;
        is($bytes, $expected_wire, 'wire preserves declared member order and the exact field roster');
        my ($status, $records) = read_generated_config($bytes, 'xcat_zfs_members');
        is($status, 0, 'actual shell reader accepts the controller output');
        is($records, $expected, 'native reader preserves exact devices, serials and group membership');
        is(xCAT::FreeBSDConfig::render_pkgbase('node1', $boot, $selected_network,
            { %$install, media => $media4 }, $generation), $bytes, 'rendering is deterministic');
        for my $old_media ($install->{media}, $media3) {
            rejected(sub { xCAT::FreeBSDConfig::render_pkgbase('node1', $boot, $selected_network,
                { %$install, media => $old_media }, $generation) }, qr/requires.*install-4/x,
                'older image cannot receive a multi-disk request');
        }
        $wire4 = $bytes unless defined($wire4);
    }

    my %policy = (filesystem => 'zfs', swap_size => '0', swap_mode => 'none',
        zfs_topology => 'mirror', zfs_vdevs => 'vtbd0@A,vtbd1@B');
    my @bad = (
        [zfs_topology => 'stripe'], [zfs_topology => 'raidz'], [zfs_topology => 'MIRROR'],
        [zfs_vdevs => ''], [zfs_vdevs => 'vtbd0@A'], [zfs_vdevs => ',vtbd0@A,vtbd1@B'],
        [zfs_vdevs => 'vtbd0@A,vtbd1@B,'], [zfs_vdevs => 'vtbd0@A,,vtbd1@B'],
        [zfs_vdevs => 'vtbd0@A;vtbd1@B'], [zfs_vdevs => ';vtbd0@A,vtbd1@B'],
        [zfs_vdevs => 'vtbd0@A,vtbd1@B;'], [zfs_vdevs => 'vtbd0@A,vtbd1@B;;'],
        [zfs_vdevs => 'vtbd0@A,vtbd0@B'], [zfs_vdevs => 'vtbd0@A,vtbd1@A'],
        [zfs_vdevs => 'vtbd00@A,vtbd1@B'], [zfs_vdevs => 'vtbd100000@A,vtbd1@B'],
        [zfs_vdevs => '/dev/vtbd0@A,vtbd1@B'], [zfs_vdevs => 'diskid/A@A,vtbd1@B'],
        [zfs_vdevs => 'vtbd0@A@B,vtbd1@B'], [zfs_vdevs => 'vtbd0@,vtbd1@B'],
        [zfs_vdevs => 'vtbd0@A, vtbd1@B'], [zfs_vdevs => 'vtbd0@$(reboot),vtbd1@B'],
        [zfs_vdevs => 'vtbd0@`reboot`,vtbd1@B'], [zfs_vdevs => "vtbd0\@A\t,vtbd1\@B"],
        [zfs_vdevs => 'vtbd0@' . ('A' x 129) . ',vtbd1@B'],
        [zfs_vdevs => join(',', map { "vtbd$_\@S$_" } 0 .. 16)],
        [zfs_vdevs => 'A' x 4097], [filesystem => 'ufs'], [swap_size => '1g'],
        [swap_size => '00'], [swap_mode => 'mirror'], [swap_mode => ''],
    );
    my $canonical = $wire3;
    $canonical =~ s/format=xcat-freebsd-install-3/format=xcat-freebsd-install-4/x;
    $canonical =~ s/target_disk=vtbd0\ntarget_disk_ident=XCAT_TEST_SERIAL\n/zfs_topology=mirror\nzfs_vdevs=vtbd0\@A,vtbd1\@B\nswap_mode=none\n/x;
    my ($valid_status) = read_generated_config($canonical, 'printf accepted');
    is($valid_status, 0, 'independent valid format4 wire reaches the native parser');
    for my $bad (@bad) {
        my %changed = (%policy, @$bad);
        rejected(sub {
            my $boot = xCAT::FreeBSDConfig::boot_settings({ %changed, authorized_key_base64 => $settings->{authorized_key_base64} }, '', {}, $media4);
            xCAT::FreeBSDConfig::render_pkgbase('node1', $boot, $selected_network, { %$install, media => $media4 }, $generation);
        }, qr/ZFS|storage|disk|Striped|invalid/ix, "invalid $bad->[0] is rejected by the controller");
        my $mutant = $canonical;
        $mutant =~ s/^\Q$bad->[0]\E=.*$/$bad->[0]=$bad->[1]/mx;
        my ($status, $output) = read_generated_config($mutant, 'printf unsafe');
        isnt($status, 0, 'native parser independently rejects the invalid wire');
        is($output, '', 'invalid membership cannot reach the caller');
    }
    for my $case (['raid10', 'vtbd0@A,vtbd1@B'], ['raid10', 'vtbd0@A,vtbd1@B,vtbd2@C,vtbd3@D'],
        ['raid10', 'vtbd0@A;vtbd1@B,vtbd2@C,vtbd3@D'], ['raid10', 'vtbd0@A,vtbd1@B;vtbd2@C,vtbd0@D'],
        ['raidz1', 'vtbd0@A,vtbd1@B'], ['raidz2', 'vtbd0@A,vtbd1@B,vtbd2@C'],
        ['raidz3', 'vtbd0@A,vtbd1@B,vtbd2@C,vtbd3@D']) {
        my $mutant = $canonical;
        $mutant =~ s/^zfs_topology=.*$/zfs_topology=$case->[0]/mx;
        $mutant =~ s/^zfs_vdevs=.*$/zfs_vdevs=$case->[1]/mx;
        my ($status) = read_generated_config($mutant, 'printf unsafe');
        isnt($status, 0, "$case->[0] rejects invalid topology membership natively");
        write_file("$root/redundant.disk", "filesystem=zfs\nswap_mode=none\nzfs_topology=$case->[0]\nzfs_vdevs=$case->[1]\n");
        rejected(sub { xCAT::FreeBSDConfig::load_settings('node1', "$root/settings", "$root/redundant.disk") },
            qr/ZFS|Striped/x, 'policy loader rejects invalid topology membership');
    }
    for my $field (qw(zfs_topology zfs_vdevs swap_mode)) {
        my $missing = $canonical; $missing =~ s/^\Q$field\E=.*\n//mx;
        my ($status) = read_generated_config($missing, 'printf unsafe');
        isnt($status, 0, "native reader requires $field");
    }
    for my $extra ("target_disk=vtbd0\n", "target_disk_ident=A\n", "reinstall_pool_guid=123\n", "zfs_vdevs=vtbd0\@A,vtbd1\@B\n") {
        my ($status) = read_generated_config($canonical . $extra, 'printf unsafe');
        isnt($status, 0, 'mixed, obsolete or duplicate wire fields fail');
        write_file("$root/redundant.disk", "filesystem=zfs\nswap_mode=none\nzfs_topology=mirror\nzfs_vdevs=vtbd0\@A,vtbd1\@B\n" . $extra);
        rejected(sub { xCAT::FreeBSDConfig::load_settings('node1', "$root/settings", "$root/redundant.disk") },
            qr/combined|Unsupported|Duplicate/x, 'policy loader rejects mixed, obsolete or duplicate fields');
    }
    for my $format (1 .. 3) {
        my $old_wire = $canonical; $old_wire =~ s/install-4/install-$format/x;
        my ($status) = read_generated_config($old_wire, 'printf unsafe');
        isnt($status, 0, 'older format cannot carry multi-disk fields');
    }
    my $fingerprint = eval { xCAT::FreeBSDConfig::fingerprint_pkgbase('node1',
        { %$legacy, %policy, target_disk => undef }, $selected_network, { %$install, media => $media4 }) };
    ok(!defined($fingerprint) && $@, 'even an undefined scalar disk conflicts with membership');
    my %selected = (%$legacy, %policy); delete @selected{qw(target_disk target_disk_ident)};
    my $original = eval { xCAT::FreeBSDConfig::fingerprint_pkgbase('node1', \%selected, $selected_network, { %$install, media => $media4 }) };
    ok(defined($original), 'valid redundant policy has a fingerprint');
    if (defined($original)) {
        for my $members ('vtbd1@B,vtbd0@A', 'vtbd0@C,vtbd1@B') {
            isnt(xCAT::FreeBSDConfig::fingerprint_pkgbase('node1', { %selected, zfs_vdevs => $members },
                $selected_network, { %$install, media => $media4 }), $original, 'member identity or order changes generation input');
        }
        my %four = (%selected, zfs_vdevs => 'vtbd0@A,vtbd1@B,vtbd2@C,vtbd3@D');
        isnt(xCAT::FreeBSDConfig::fingerprint_pkgbase('node1', \%four, $selected_network, { %$install, media => $media4 }),
            xCAT::FreeBSDConfig::fingerprint_pkgbase('node1', { %four, zfs_topology => 'raidz1' },
                $selected_network, { %$install, media => $media4 }), 'topology changes generation input');
    }
};
done_testing();
