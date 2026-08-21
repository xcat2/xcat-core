#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use FindBin;

# Issue #7454: configeth must configure Ubuntu/Debian networking with netplan
# (Ubuntu 18.04+ ignores /etc/network/interfaces.d/*). This exercises the netplan
# writer helpers end-to-end and checks the generated /etc/netplan drop-in.

my $conf = "$FindBin::Bin/../../xCAT/postscripts/configeth";
plan skip_all => "configeth not found" unless -f $conf;

# configeth must branch to netplan for debian when netplan_active=1.
{
    open my $fh, '<', $conf or die $!;
    local $/;
    my $src = <$fh>;
    like($src, qr/netplan_active=1.*command -v netplan/s,
        'configeth detects netplan and sets netplan_active');
    like($src, qr/str_os_type"\s*=\s*"debian"\s*\]\s*&&\s*\[\s*"\$netplan_active"\s*=\s*"1"/,
        'configipv4/ipv6 branch to netplan for debian when netplan is active');
    like($src, qr/netplan apply/,
        'the interface is brought up with netplan apply, not ifup, on netplan nodes');
}

# Run the extracted helpers and validate the rendered netplan YAML.
my $tmp = "$FindBin::Bin/netplan_drv.$$.sh";
open my $out, '>', $tmp or die $!;
print $out <<"BASH";
set -e
NETPLAN_DIR=\$(mktemp -d)
export NETPLAN_DIR
str_default_token='__no_value__'
# source ONLY the three netplan helper functions out of configeth
eval "\$(sed -n '/^netplan_file()/,/^}/p; /^write_netplan_addr()/,/^}/p; /^write_netplan_route()/,/^}/p' '$conf')"
write_netplan_addr eth1 192.168.5.10/24 1500
write_netplan_addr eth1 192.168.6.10/24 __no_value__
write_netplan_addr eth1 2001:db8::10/64 __no_value__
write_netplan_addr eth1 192.168.5.10/24 __no_value__   # duplicate must be a no-op
write_netplan_route eth1 default 2001:db8::1
echo "NETPLAN_FILE=\$(netplan_file eth1)"
echo "===YAML==="
cat "\$(netplan_file eth1)"
BASH
close $out;

my $res = `bash '$tmp' 2>&1`;
unlink $tmp;

like($res, qr/90-xcat-eth1\.yaml/, 'netplan_file names the per-NIC drop-in');
like($res, qr/- 192\.168\.5\.10\/24/, 'first IPv4 address written');
like($res, qr/- 192\.168\.6\.10\/24/, 'second IPv4 address (alias) written to the same NIC');
like($res, qr/- 2001:db8::10\/64/, 'IPv6 address written to the same NIC');
like($res, qr/mtu: 1500/, 'MTU written');
like($res, qr/via: 2001:db8::1/, 'IPv6 default gateway written as a route');
is(scalar(() = $res =~ /- 192\.168\.5\.10\/24/g), 1, 'duplicate address is not written twice');

# The rendered YAML must actually parse (structure is valid netplan).
my ($yaml) = $res =~ /===YAML===\n(.*)/s;
SKIP: {
    my $have_yaml = do { my $r = `python3 -c 'import yaml' 2>&1`; $? == 0 };
    skip 'python3 yaml not available', 2 unless $have_yaml && defined $yaml;
    open my $yf, '>', "$FindBin::Bin/np.$$.yaml"; print $yf $yaml; close $yf;
    my $chk = `python3 -c 'import sys,yaml; d=yaml.safe_load(open("$FindBin::Bin/np.$$.yaml")); e=d["network"]["ethernets"]["eth1"]; print("ADDRS",len(e["addresses"])); print("MTU",e["mtu"])' 2>&1`;
    unlink "$FindBin::Bin/np.$$.yaml";
    like($chk, qr/ADDRS 3/, 'valid netplan YAML with 3 addresses on eth1');
    like($chk, qr/MTU 1500/, 'valid netplan YAML with mtu 1500');
}

done_testing();
