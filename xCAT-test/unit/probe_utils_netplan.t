#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../xCAT-probe/lib/perl";

use File::Temp qw(tempdir);
use Test::More;

require probe_utils;

my %netplan = (
    'ethernets.eth0'           => 'renderer: networkd',
    'ethernets.eth0.addresses' => "- 10.0.0.2/24\n",
    'ethernets.eth0.dhcp4'     => 'false',
    'ethernets.eth1'           => 'renderer: networkd',
    'ethernets.eth1.addresses' => "- \"10.0.0.3/24\"\n",
    'ethernets.eth1.dhcp4'     => 'false',
    'ethernets.eth4'           => 'renderer: networkd',
    'ethernets.eth4.addresses' => "- 10.0.0.4/24\n",
    'ethernets.eth4.dhcp4'     => 'true',
    'vlans.bond0\.123'           => 'renderer: networkd',
    'vlans.bond0\.123.addresses' => "- 10.0.123.5/24\n",
);

{
    no warnings 'redefine';
    local *probe_utils::_command_available = sub { return $_[0] eq 'netplan' ? 1 : 0; };
    local *probe_utils::_netplan_get = sub { return $netplan{ $_[0] }; };

    ok(probe_utils::_netplan_has_static_ip('eth0', '10.0.0.2'), 'static netplan address is detected');
    ok(!probe_utils::_netplan_has_static_ip('eth0', '10.0.0.99'), 'wrong address is not treated as static');
    ok(probe_utils::_netplan_has_static_ip('eth1', '10.0.0.3'), 'quoted netplan address is detected');
    ok(!probe_utils::_netplan_has_static_ip('eth4', '10.0.0.4'), 'dhcp4 true is not treated as static');
    ok(probe_utils::_netplan_has_static_ip('bond0.123', '10.0.123.5'), 'dotted VLAN interface is escaped for netplan get');
}

sub write_file {
    my ($file, $contents) = @_;

    open(my $fh, '>', $file) or die "Unable to write $file: $!";
    print $fh $contents;
    close $fh;
}

my $networkd_dir = tempdir(CLEANUP => 1);
my $fake_bin = tempdir(CLEANUP => 1);

write_file("$networkd_dir/10-netplan-eth2.network", <<'EOF');
[Match]
Name=eth2

[Network]
Address=10.0.2.5/24
EOF

write_file("$networkd_dir/10-netplan-eth3.network", <<'EOF');
[Match]
Name=eth3

[Network]
Address=10.0.3.5/24
DHCP=ipv4
EOF

write_file("$networkd_dir/10-netplan-eth20.network", <<'EOF');
[Match]
Name=eth20

[Network]
Address=10.0.20.5/24
EOF

my $fake_netplan = "$fake_bin/netplan";
write_file($fake_netplan, <<'EOF');
#!/bin/sh
echo "netplan get is not supported" >&2
exit 1
EOF
chmod oct('755'), $fake_netplan;

{
    no warnings 'redefine';
    local *probe_utils::_networkd_config_dirs = sub { return ($networkd_dir); };

    ok(probe_utils::_networkd_has_static_ip('eth2', '10.0.2.5'), 'networkd fallback detects generated static address');
    ok(!probe_utils::_networkd_has_static_ip('eth2', '10.0.2.99'), 'networkd fallback rejects wrong address');
    ok(!probe_utils::_networkd_has_static_ip('eth3', '10.0.3.5'), 'networkd fallback rejects DHCP-enabled IPv4 config');
    ok(!probe_utils::_networkd_has_static_ip('eth2', '10.0.20.5'), 'networkd fallback requires exact interface match');
}

{
    no warnings 'redefine';
    local *probe_utils::_command_available = sub { return $_[0] eq 'netplan' ? 1 : 0; };
    local *probe_utils::_netplan_get = sub { return; };
    local *probe_utils::_networkd_config_dirs = sub { return ($networkd_dir); };

    ok(probe_utils::_netplan_has_static_ip('eth2', '10.0.2.5'), 'old netplan without get falls back to generated networkd config');
}

{
    no warnings 'redefine';
    local $ENV{PATH} = "$fake_bin:$ENV{PATH}";
    local *probe_utils::_networkd_config_dirs = sub { return ($networkd_dir); };

    ok(probe_utils::_netplan_has_static_ip('eth2', '10.0.2.5'), 'unsupported netplan get command uses generated networkd fallback');
}

{
    no warnings 'redefine';
    local *probe_utils::_command_available = sub { return $_[0] eq 'netplan' ? 1 : 0; };
    local *probe_utils::_netplan_get = sub { return 'null'; };
    local *probe_utils::_networkd_config_dirs = sub { return ($networkd_dir); };

    ok(!probe_utils::_netplan_has_static_ip('eth2', '10.0.2.5'), 'supported netplan get remains authoritative when no netplan key matches');
}

done_testing();
