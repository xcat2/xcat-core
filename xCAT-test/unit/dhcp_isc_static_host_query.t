#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

$ENV{XCATCFG} ||= 'SQLite:/tmp';

# `makedhcp -q <node>` must answer from dhcpd.conf and never spawn omshell: Ubuntu's ISC
# DHCP 4.4 omshell can wedge at 100% CPU, unreapable, which hung the CI provisioning retry
# loop on focal.
my $source_dhcp_plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/dhcp.pm";
if ( -f $source_dhcp_plugin ) {
    require $source_dhcp_plugin;
} else {
    require xCAT_plugin::dhcp;
}

# Two static host blocks exactly as _add_isc_static_host writes them, so both
# the query parse and the end-marker isolation are exercised.
my @dhcpconf = (
    "#xCAT host declaration for other aka host other start\n",
    "host other {\n",
    "    hardware ethernet 52:54:00:aa:bb:cc;\n",
    "    fixed-address 192.168.201.9;\n",
    "}\n",
    "#xCAT host declaration for other aka host other end\n",
    "#xCAT host declaration for xcat30-cn aka host xcat30-cn start\n",
    "host xcat30-cn {\n",
    "    hardware ethernet 52:54:00:12:34:56;\n",
    "    fixed-address 192.168.201.30;\n",
    "    next-server 192.168.201.230;\n",
    "}\n",
    "#xCAT host declaration for xcat30-cn aka host xcat30-cn end\n",
);

my ($name, $ip, $mac) =
  xCAT_plugin::dhcp::_query_isc_static_host('xcat30-cn', @dhcpconf);

is($name, 'xcat30-cn', 'query returns the node name from its static host block');
is($ip,  'ip-address = 192.168.201.30',
    'query returns the fixed-address as an ip-address line (no omshell)');
is($mac, 'hardware-address = 52:54:00:12:34:56',
    'query returns the hardware ethernet as a hardware-address line');

# The FIRST block must not bleed into the second: querying 'other' returns
# other's address, proving the end marker stops the scan.
my ($oname, $oip) =
  xCAT_plugin::dhcp::_query_isc_static_host('other', @dhcpconf);
is($oip, 'ip-address = 192.168.201.9', 'the end marker isolates each host block');

# An older xCAT release wrote the end marker on the closing-brace line. The query must
# still read a dhcpd.conf that carries those markers.
my @legacy = (
    "#xCAT host declaration for legacy-cn aka host legacy-cn start\n",
    "host legacy-cn {\n",
    "    hardware ethernet 52:54:00:de:ad:be;\n",
    "    fixed-address 192.168.201.40;\n",
    "} #xCAT host declaration for legacy-cn aka host legacy-cn end\n",
    "#xCAT host declaration for after aka host after start\n",
    "host after {\n",
    "    hardware ethernet 52:54:00:de:ad:bf;\n",
    "    fixed-address 192.168.201.41;\n",
    "}\n",
    "#xCAT host declaration for after aka host after end\n",
);
my ($lname, $lip) = xCAT_plugin::dhcp::_query_isc_static_host('legacy-cn', @legacy);
is($lip, 'ip-address = 192.168.201.40',
    'the query reads a host block written by an older xCAT release');

# A node without a static block yields nothing (no false hit, no omshell).
my ($nn, $ni, $nm) =
  xCAT_plugin::dhcp::_query_isc_static_host('absent-node', @dhcpconf);
is($ni, undef, 'a node with no static host block returns no ip');

# The mitigation predicate must be TRUE exactly for the releases whose omshell
# hangs (20.04 / 22.04) and FALSE for 24.04+, so the query fallback engages
# precisely where the hang occurs.
ok('ubuntu20'    =~ /^ubuntu(20|20\.04|22|22\.04)/, 'ubuntu20 is ISC-omapi-limited');
ok('ubuntu20.04' =~ /^ubuntu(20|20\.04|22|22\.04)/, 'ubuntu20.04 is ISC-omapi-limited');
ok('ubuntu22.04' =~ /^ubuntu(20|20\.04|22|22\.04)/, 'ubuntu22.04 is ISC-omapi-limited');
ok('ubuntu24.04' !~ /^ubuntu(20|20\.04|22|22\.04)/, 'ubuntu24.04 is NOT ISC-omapi-limited (uses Kea)');

# A node name that prefixes another must not match its block: "compute" must not
# answer with "compute-01"'s address.
my @similar = (
    "#xCAT host declaration for compute aka host compute start\n",
    "host compute {\n",
    "    hardware ethernet 52:54:00:00:00:01;\n",
    "    fixed-address 192.168.201.11;\n",
    "}\n",
    "#xCAT host declaration for compute aka host compute end\n",
    "#xCAT host declaration for compute-01 aka host compute-01 start\n",
    "host compute-01 {\n",
    "    hardware ethernet 52:54:00:00:00:02;\n",
    "    fixed-address 192.168.201.12;\n",
    "}\n",
    "#xCAT host declaration for compute-01 aka host compute-01 end\n",
);

my ($cname, $cip) = xCAT_plugin::dhcp::_query_isc_static_host('compute', @similar);
is($cip, 'ip-address = 192.168.201.11',
    'querying "compute" does not match the "compute-01" block');

my ($c1name, $c1ip) = xCAT_plugin::dhcp::_query_isc_static_host('compute-01', @similar);
is($c1ip, 'ip-address = 192.168.201.12',
    'querying "compute-01" returns its own block');

done_testing();
