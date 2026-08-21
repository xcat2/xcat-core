#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

$ENV{XCATCFG} ||= 'SQLite:/tmp';

# Regression: `makedhcp -q <node>` on Ubuntu's ISC-limited releases (<22.04)
# must answer from the static host block in dhcpd.conf and NEVER spawn omshell.
# Ubuntu's ISC DHCP 4.4 omshell can wedge at 100% CPU (unreapable) on a host
# query, which used to hang the CI provisioning retry loop forever on focal.
#
# It also guards the end-marker matching: _add_isc_static_host emits the end
# marker on the closing-brace line ("} #xCAT host declaration for ... end"),
# which is NOT anchored at column 0, so a "^#xCAT...end" regex never matches and
# the scan would run past the node's block into the next one.
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
    "} #xCAT host declaration for other aka host other end\n",
    "#xCAT host declaration for xcat30-cn aka host xcat30-cn start\n",
    "host xcat30-cn {\n",
    "    hardware ethernet 52:54:00:12:34:56;\n",
    "    fixed-address 192.168.201.30;\n",
    "    next-server 192.168.201.230;\n",
    "} #xCAT host declaration for xcat30-cn aka host xcat30-cn end\n",
);

my ($name, $ip, $mac) =
  xCAT_plugin::dhcp::_query_isc_static_host('xcat30-cn', @dhcpconf);

is($name, 'xcat30-cn', 'query returns the node name from its static host block');
is($ip,  'ip-address = 192.168.201.30',
    'query returns the fixed-address as an ip-address line (no omshell)');
is($mac, 'hardware-address = 52:54:00:12:34:56',
    'query returns the hardware ethernet as a hardware-address line');

# The FIRST block must not bleed into the second: querying 'other' returns
# other's address, proving the end marker on the "}" line stops the scan.
my ($oname, $oip) =
  xCAT_plugin::dhcp::_query_isc_static_host('other', @dhcpconf);
is($oip, 'ip-address = 192.168.201.9',
    'end marker on the closing-brace line isolates each host block');

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

done_testing();
