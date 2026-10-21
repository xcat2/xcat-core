#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Carp qw(croak);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use MIME::Base64 qw(encode_base64);
use Test::More;
use xCAT::FreeBSDConfig;

my $directory = $ENV{XCAT_FREEBSD_INSTALLER_DIR} || "$FindBin::Bin/../../xCAT-server/share/xcat/install/freebsd";
my $root = tempdir(CLEANUP => 1);
my $media = { format => 'xcat-mfsbsd-2', release => '15.1-RELEASE', arch => 'x86_64',
    digest => 'a' x 64, files => { 'xcat/runtime.tsv' => 'b' x 64 }, install_contract => 'xcat-freebsd-install-3' };
my $install = { media => $media, package_plan_sha256 => 'c' x 64 };
my $network = { master => '192.0.2.1', port => '3002', mac => '52:54:00:12:34:56',
    ipv4 => '192.0.2.10', netmask => '255.255.255.0', gateway => '192.0.2.1',
    hostname => 'node1.example.test', nameservers => '192.0.2.1', install_url => 'http://192.0.2.1/install' };
my $disk = { target_disk => 'vtbd0', target_disk_ident => 'TEST_DISK', filesystem => 'ufs',
    swap_size => '0', authorized_key_base64 => encode_base64("ssh-ed25519 AAAA\n", '') };

sub write_file {
    my ($path, $text) = @_;
    open(my $file, '>', $path) or croak $!;
    print {$file} $text or croak $!;
    close($file) or croak $!;
    return;
}

sub read_file {
    my $path = shift;
    open(my $file, '<', $path) or croak $!;
    local $/ = undef;
    my $text = <$file>;
    close($file) or croak $!;
    return $text;
}

sub rejected {
    my ($operation, $pattern, $label) = @_;
    my $ok = eval { $operation->(); 1 };
    ok(!$ok, $label);
    like($@, $pattern, "$label explains why");
    return;
}

sub render {
    my $settings = shift;
    return xCAT::FreeBSDConfig::render_pkgbase('node1', $settings, $network, $install, 'd' x 32);
}

sub shell {
    my ($script, @args) = @_;
    local $ENV{LC_ALL} = 'C';
    open(my $pipe, '-|', 'sh', '-c', '. "$1"; shift; ' . $script, 'xcat-test',
        "$directory/xcat-install-lib.sh", @args) or croak $!;
    local $/ = undef;
    my $text = <$pipe>;
    close($pipe);
    my $status = $?;
    return ($status >> 8 || ($status & 127), $text || '');
}

sub read_config {
    my ($text, $script) = @_;
    write_file("$root/config", $text);
    return shell('xcat_read_config "$1" || exit 1; shift; ' . ($script || ':'), "$root/config");
}

my $settings = xCAT::FreeBSDConfig::boot_settings({ %$disk, bootstrap => 'static' },
    'hint.example=install R::hint.example=target R::boot_verbose=yes',
    { serialport => '1', serialspeed => '115200', serialflow => 'hard' }, $media);
my $bytes = render($settings);
my ($status, $output) = read_config($bytes, 'printf "%s|%s|%s|%s\n" "$XCAT_BOOTSTRAP" "$XCAT_CONSOLE_PORT" "$XCAT_CONSOLE_SPEED" "$XCAT_CONSOLE_FLOW"');
is($status, 0, 'runtime accepts enhanced controller configuration');
is($output, "static|1|115200|hard\n", 'runtime consumes exact bootstrap and console settings');
like($bytes, qr/\Aformat=xcat-freebsd-install-3\n/x, 'enhanced configuration declares its own contract');
is(scalar(split(/\n/x, $bytes)), 27, 'enhanced wire contract has exactly 27 fields');
my $loader = xCAT::FreeBSDConfig::render_loader_settings($settings, $network);
like($loader, qr/^hint\.example="install"$/mx, 'unprefixed option reaches installer loader');
unlike($loader, qr/target|boot_verbose/mx, 'persistent options do not reach installer loader');
like($loader, qr/^xcat_bootstrap_ipv4="192\.0\.2\.10"$/mx, 'static address precedes configuration fetch');
like($loader, qr/^comconsole_port="0x2f8"$/mx, 'xCAT COM2 uses the native I/O port');
like($loader, qr/^hw\.uart\.console="io:0x2f8,br:115200"$/mx, 'kernel console pins port and speed');
($status, $output) = read_config($bytes, 'xcat_boot_options "$XCAT_TARGET_BOOT_OPTIONS_BASE64"');
is($status, 0, 'runtime decodes target boot options');
is($output, "boot_verbose=\"YES\"\nhint.example=\"target\"\n", 'runtime preserves only R:: options with canonical values');

write_file("$root/template", "#!/bin/sh\nset -eu\n");
write_file("$root/config", $bytes);
($status, $output) = shell('xcat_read_config "$1" || exit 1; XCAT_WORK=/tmp/work; xcat_write_installer "$2" "$3"',
    "$root/config", "$root/template", "$directory/xcat-install-lib.sh");
is($status, 0, 'installer generator accepts enhanced settings');
my $loader_start = "cat >> /boot/loader.conf <<'XCAT_LOADER_SETTINGS'\n";
my ($target_loader) = $output =~ /\Q$loader_start\E(.*?)^XCAT_LOADER_SETTINGS\n/msx;
is($target_loader, "boot_verbose=\"YES\"\nhint.example=\"target\"\n"
    . "comconsole_port=\"0x2f8\"\ncomconsole_speed=\"115200\"\nconsole=\"comconsole,\${console}\"\n"
    . "boot_serial=\"YES\"\nboot_multicons=\"YES\"\nhw.uart.console=\"io:0x2f8,br:115200\"\n"
    . "hint.uart.1.at=\"acpi\"\nhint.uart.1.port=\"0x2f8\"\n",
    'actual installer persists the target options and native console settings');
like($output, qr/xcatserial:np:nc:sp\#115200:hw:/x, 'login terminal requests the selected hardware flow control');
ok(index($output, 'ttyu1 "/usr/libexec/getty xcatserial" vt100 on insecure') >= 0,
    'selected serial login is enabled without root autologin');

subtest 'multi-disk rendering retains member order and boot settings' => sub {
    my $capable = { %$media, install_contract => 'xcat-freebsd-install-4' };
    for my $case (
        ['mirror', 'vtbd2@C,vtbd0@A', 'vtbd2 vtbd0'],
        ['raid10', 'vtbd3@D,vtbd1@B;vtbd2@C,vtbd0@A', 'vtbd3 vtbd1 vtbd2 vtbd0'],
        ['raidz1', 'vtbd2@C,vtbd0@A,vtbd1@B', 'vtbd2 vtbd0 vtbd1'],
        ['raidz2', 'vtbd3@D,vtbd1@B,vtbd2@C,vtbd0@A', 'vtbd3 vtbd1 vtbd2 vtbd0'],
        ['raidz3', 'vtbd4@E,vtbd2@C,vtbd0@A,vtbd3@D,vtbd1@B', 'vtbd4 vtbd2 vtbd0 vtbd3 vtbd1'],
    ) {
        my ($topology, $vdevs, $ordered) = @$case;
        my %selected = (%$settings, filesystem => 'zfs', swap_size => '0', swap_mode => 'none',
            zfs_topology => $topology, zfs_vdevs => $vdevs);
        delete @selected{qw(target_disk target_disk_ident)};
        my $config = xCAT::FreeBSDConfig::render_pkgbase('node1', \%selected, $network,
            { %$install, media => $capable }, 'd' x 32);
        write_file("$root/config", $config);
        my ($code, $rendered) = shell('xcat_read_config "$1" || exit 1; XCAT_WORK=/tmp/work; xcat_write_installer "$2" "$3"',
            "$root/config", "$root/template", "$directory/xcat-install-lib.sh");
        is($code, 0, "$topology installer renders");
        like($rendered, qr/^export[ ]ZFSBOOT_DISKS="\Q$ordered\E"$/mx, 'disk order reaches native bsdinstall');
        like($rendered, qr/^export[ ]ZFSBOOT_VDEV_TYPE="\Q$topology\E"$/mx, 'the declared topology reaches native bsdinstall');
        unlike($rendered, qr/^PARTITIONS=/mx, 'redundant ZFS does not select the UFS partitioner');
        my ($persistent) = $rendered =~ /\Q$loader_start\E(.*?)^XCAT_LOADER_SETTINGS\n/msx;
        is($persistent, $target_loader, 'persistent options and console settings survive multi-disk rendering');
        ($code) = read_config($config, 'XCAT_BOOTSTRAP_MODE=dhcp; xcat_check_bootstrap');
        isnt($code, 0, 'multi-disk installation rejects a mismatched bootstrap mode');
        ($code) = read_config($config, 'XCAT_BOOTSTRAP_MODE=static; XCAT_BOOTSTRAP_IPV4=$XCAT_IPV4; '
            . 'XCAT_BOOTSTRAP_NETMASK=$XCAT_NETMASK; XCAT_BOOTSTRAP_GATEWAY=$XCAT_GATEWAY; xcat_check_bootstrap');
        is($code, 0, 'multi-disk installation accepts the matching static bootstrap');
    }
};

subtest 'every setting enters the generation identity' => sub {
    my $original = xCAT::FreeBSDConfig::fingerprint_pkgbase('node1', $settings, $network, $install);
    my %changes = (bootstrap => 'dhcp', console_port => '0', console_speed => '19200', console_flow => 'none',
        install_boot_options_base64 => encode_base64("hint.example=\"changed\"\n", ''),
        target_boot_options_base64 => encode_base64("hint.example=\"changed\"\n", ''));
    for my $key (sort keys %changes) {
        isnt(xCAT::FreeBSDConfig::fingerprint_pkgbase('node1', { %$settings, $key => $changes{$key} }, $network, $install),
            $original, "$key changes the fingerprint");
    }
};

subtest 'capability admission and defaults' => sub {
    my %old = %$media;
    delete $old{install_contract};
    is_deeply(xCAT::FreeBSDConfig::boot_settings($disk, '', {}, \%old), $disk, 'old media keeps default wire settings');
    my $default = xCAT::FreeBSDConfig::boot_settings($disk, '', {}, $media);
    my ($default_status, $default_output) = read_config(render($default), 'printf "%s|%s\n" "$XCAT_BOOTSTRAP" "$XCAT_CONSOLE_PORT"');
    is($default_status, 0, 'new media accepts explicit defaults');
    is($default_output, "dhcp|none\n", 'defaults retain DHCP and firmware console');
    my $static_disk = { %$disk, bootstrap => 'static' };
    for my $request ([$disk, 'hint.example=1', {}], [$disk, 'R::hint.example=1', {}],
        [$static_disk, '', {}], [$disk, '', { serialport => '0', serialspeed => '9600' }]) {
        rejected(sub { xCAT::FreeBSDConfig::boot_settings(@$request, \%old) }, qr/require.*runtime/x, 'old runtime rejects enhanced request');
    }
    for my $console ({ serialport => '4', serialspeed => '9600' }, { serialport => '0' },
        { serialport => '0', serialspeed => '9600', serialflow => 'soft' }, { serialspeed => '9600' }) {
        rejected(sub { xCAT::FreeBSDConfig::boot_settings($disk, '', $console, $media) },
            qr/(?:console|Console|serial)/x, 'invalid console policy');
    }
};

subtest 'runtime rejects malformed and executable options' => sub {
    for my $options ("console=\"comconsole\"\n", "hint.uart.0.port=\"0x2f8\"\n", "xcat_config_url=\"bad\"\n",
        "exec=\"reboot\"\n", "foo_before=\"reboot\"\n", "hint.a=\"1\"\nhint.a=\"2\"\n",
        "hint.z=\"1\"\nhint.a=\"2\"\n", "foo_load=\"yes\"\n", "hint.a=\"\${bad}\"\n", "hint.a=\"x\"",
        "hint.a=\"x\"\n\n", "hint.a=\"x\"\0\n") {
        my $encoded = encode_base64($options, '');
        rejected(sub { render({ %$settings, target_boot_options_base64 => $encoded }) },
            qr/(?:option|assignment)/ix, 'controller rejects invalid target stream');
        my $invalid = $bytes;
        $invalid =~ s/^target_boot_options_base64=.*$/target_boot_options_base64=$encoded/mx;
        ($status) = read_config($invalid);
        isnt($status, 0, 'runtime independently rejects the same invalid stream');
    }
    for my $key (qw(bootstrap console_port console_speed console_flow install_boot_options_base64 target_boot_options_base64)) {
        my $missing = $bytes;
        $missing =~ s/^\Q$key\E=.*\n//mx;
        ($status) = read_config($missing);
        isnt($status, 0, "runtime requires $key even when its value may be empty");
    }
    my $legacy = $bytes;
    $legacy =~ s/xcat-freebsd-install-3/xcat-freebsd-install-2/x;
    ($status) = read_config($legacy);
    isnt($status, 0, 'old contract rejects enhanced fields');
};

subtest 'controller and runtime agree on bounds and console ports' => sub {
    my @ports = qw(0x3f8 0x2f8 0x3e8 0x2e8);
    for my $port (0 .. 3) {
        my $selected = xCAT::FreeBSDConfig::boot_settings($disk, '',
            { serialport => "$port", serialspeed => '19200' }, $media);
        my ($code, $native) = read_config(render($selected), 'xcat_console_settings');
        is($code, 0, "runtime accepts serial port $port");
        my $controller = xCAT::FreeBSDConfig::render_loader_settings($selected, $network);
        $controller =~ s/^xcat_bootstrap="dhcp"\n//mx;
        is($native, $controller, "installation and target render the same console for port $port");
        like($native, qr/^comconsole_port="\Q$ports[$port]\E"$/mx, "port $port has its native I/O address");
        my $binding = "hint.uart.$port.at=\"acpi\"\nhint.uart.$port.port=\"$ports[$port]\"";
        like($native, qr/^\Q$binding\E$/mx,
            "port $port pins the login device to the selected hardware address");
    }
    my $small = render({ %$settings, authorized_key_base64 => 'A' });
    my $exact = render({ %$settings, authorized_key_base64 => 'A' x (32769 - length($small)) });
    is(length($exact), 32768, 'enhanced configuration uses the existing aggregate byte bound');
    my ($code) = read_config($exact);
    is($code, 0, 'runtime accepts the exact aggregate bound');
    ($code) = read_config($exact . "\n");
    isnt($code, 0, 'runtime rejects one byte beyond the aggregate bound');
    for my $invalid ([bootstrap => 'automatic'], [console_port => '4'], [console_speed => '115201'], [console_flow => 'soft']) {
        my ($key, $value) = @$invalid;
        my $bad = $bytes;
        $bad =~ s/^\Q$key\E=.*$/$key=$value/mx;
        ($code) = read_config($bad);
        isnt($code, 0, "runtime rejects invalid $key independently");
    }
};

subtest 'network bootstrap uses only the MAC-selected interface' => sub {
    make_path("$root/env");
    write_file("$root/env/xcat_bootstrap", "static\n");
    write_file("$root/env/xcat_bootstrap_ipv4", "192.0.2.10\n");
    write_file("$root/env/xcat_bootstrap_netmask", "255.255.255.0\n");
    write_file("$root/env/xcat_bootstrap_gateway", "192.0.2.1\n");
    my $commands = 'fixture=$1; shift; kenv() { cat "$fixture/env/$2"; }; '
      . 'ifconfig() { case "$1" in -l) printf "em0 em1 lo0\n";; '
      . 'em0) printf "ether 52:54:00:00:00:01\n";; '
      . 'em1) if [ "$#" -eq 1 ]; then printf "ether 52:54:00:12:34:56\n"; '
      . 'else printf "ifconfig %s\n" "$*" >> "$fixture/calls"; fi;; esac; }; '
      . 'dhclient() { printf "dhclient %s\n" "$*" >> "$fixture/calls"; }; '
      . 'route() { printf "route %s\n" "$*" >> "$fixture/calls"; }; '
      . 'XCAT_PROVISIONING_IF=$(xcat_find_interface 52:54:00:12:34:56) || exit 1; '
      . 'xcat_bootstrap_network || exit 1; xcat_read_config "$fixture/config" || exit 1; xcat_check_bootstrap';
    write_file("$root/config", $bytes);
    write_file("$root/calls", '');
    ($status) = shell($commands, $root);
    is($status, 0, 'static bootstrap matches the fetched configuration');
    is(read_file("$root/calls"), "ifconfig em1 inet 192.0.2.10 netmask 255.255.255.0 up\nroute add default 192.0.2.1\n",
        'static bootstrap configures only the selected interface and gateway, without DHCP');
    write_file("$root/env/xcat_bootstrap_ipv4", "192.0.2.11\n");
    ($status) = shell($commands, $root);
    isnt($status, 0, 'configuration mismatch stops before installation');
    write_file("$root/env/xcat_bootstrap_netmask", "255.0.255.0\n");
    write_file("$root/calls", '');
    ($status) = shell($commands, $root);
    isnt($status, 0, 'invalid static mask fails');
    is(read_file("$root/calls"), '', 'invalid static settings issue no network commands');
    write_file("$root/env/xcat_bootstrap", "dhcp\n");
    write_file("$root/config", render({ %$settings, bootstrap => 'dhcp' }));
    ($status) = shell($commands, $root);
    is($status, 0, 'DHCP bootstrap matches the configuration');
    is(read_file("$root/calls"), "dhclient em1\n", 'DHCP runs only on the MAC-selected interface');
};

done_testing();
