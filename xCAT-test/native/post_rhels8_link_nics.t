#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;

use XCAT::Test::File qw(repo_path);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);
use XCAT::Test::Template qw(template_database render_template);

plan skip_all => 'kickstart %post execution requires Linux' unless $^O eq 'linux';
my $database = template_database();
my $script = "$database/post.rhels8";
render_template($database, repo_path('xCAT-server/share/xcat/install/scripts/post.rhels8'), $script,
    'node', '', '/install/media', 'rh', undef, {xcatmaster => '192.0.2.1'});

my %device = (
    e1000e    => ['/sys/devices/pci0000:00/0000:00:03.0', '/sys/bus/pci/drivers/e1000e'],
    cdc_ether => ['/sys/devices/pci0000:00/0000:00:14.0/usb1/1-4/1-4:1.0', '/sys/bus/usb/drivers/cdc_ether'],
    r8152     => ['/sys/devices/pci0000:00/0000:00:14.0/usb1/1-2/1-2:1.0', '/sys/bus/usb/drivers/r8152'],
);

# Each NIC has an ifcfg file with ONBOOT=no, a driver (or no sysfs entry) and a link state.
sub run_post {
    my (%nics) = @_;
    my $root = sandbox_root();
    make_path("$root/etc/sysconfig/network-scripts", "$root/link");
    for my $nic (keys %nics) {
        my ($driver, $link) = @{$nics{$nic}};
        write_text("$root/etc/sysconfig/network-scripts/ifcfg-$nic", "DEVICE=$nic\nBOOTPROTO=dhcp\nONBOOT=no\n");
        write_text("$root/link/$nic", '') if $link;
        next unless $driver;
        my ($bus, $module) = @{$device{$driver}};
        my $device = "$bus/$nic";
        make_path("$root$device", "$root$module", "$root/sys/class/net/$nic");
        symlink($device, "$root/sys/class/net/$nic/device") or die $!;
        symlink($module, "$root$device/driver") or die $!;
    }
    write_text("$root/bin/ethtool",
        "#!/bin/sh\n[ -e \"/fixture/link/\$1\" ] && state=yes || state=no\nprintf '\\tLink detected: %s\\n' \"\$state\"\n");
    write_text("$root/bin/nmcli", "#!/bin/sh\nprintf '%s\\n' \"\$*\" >>/fixture/nmcli.calls\n");
    chmod 0755, "$root/bin/ethtool", "$root/bin/nmcli" or die $!;
    write_text("$root/post.sh", read_text($script));
    my ($rc, $log) = sandbox_run($root, {read_only => {"$root/sys" => '/sys'}}, '/bin/bash', '/fixture/post.sh');
    is($rc, 0, 'post.rhels8 completes') or diag($log);
    my %onboot = map {
        my ($value) = read_text("$root/etc/sysconfig/network-scripts/ifcfg-$_") =~ /^ONBOOT=(\w+)$/m;
        ($_ => $value)
    } keys %nics;
    return (\%onboot, -e "$root/nmcli.calls" ? read_text("$root/nmcli.calls") : '');
}

{
    my ($onboot, $nmcli) = run_post(
        eno1 => ['e1000e', 1], usb0 => ['cdc_ether', 1], enx1 => ['r8152', 1], eno2 => ['e1000e', 0],
        renamed0 => [undef, 1],
    );
    is_deeply($onboot, {eno1 => 'yes', usb0 => 'no', enx1 => 'yes', eno2 => 'no', renamed0 => 'yes'},
        'activates the NICs with link, a USB Ethernet adapter included, except the USB NIC of the BMC');
    is($nmcli, '', 'leaves the NetworkManager profiles to the ifcfg files');
}

{
    my ($onboot, $nmcli) = run_post(eno1 => ['e1000e', 0], usb0 => ['cdc_ether', 1]);
    is_deeply($onboot, {eno1 => 'no', usb0 => 'no'}, 'does not activate a USB NIC that is the only one with link');
    like($nmcli, qr/^-g NAME,STATE con show$/m, 'falls back to the connections active in the installer');
}

done_testing();
