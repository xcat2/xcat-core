#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Temp qw(tempdir);
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

# An InfiniBand node declares "hardware infiniband". Build the block with the writer, so
# the query reads what makedhcp writes rather than a hand-made copy of it.
my @ib_config;
xCAT_plugin::dhcp::_add_isc_static_host(
    'ibnode', 'ibnode',
    'ff:00:00:00:00:00:02:00:00:02:c9:00:00:02:c9:03:00:0a:6f:ba',
    32, 'ib0', '192.0.2.20', '', 1, \@ib_config,
);
my ($ibname, $ibip, $ibhw) =
  xCAT_plugin::dhcp::_query_isc_static_host('ibnode', @ib_config);
is($ibip, 'ip-address = 192.0.2.20',
    'an InfiniBand node reports the address of its reservation');
is($ibhw,
    'hardware-address = ff:00:00:00:00:00:02:00:00:02:c9:00:00:02:c9:03:00:0a:6f:ba',
    'an InfiniBand node reports the hardware address of its reservation');

# An Ethernet node on an InfiniBand interface gets a twin declaration inside the same
# markers. The query must answer with the primary declaration.
my @twin_config;
xCAT_plugin::dhcp::_add_isc_static_host(
    'twinnode', 'twinnode', 'b8:3f:d2:4a:68:aa', 1,
    'ib0', '192.0.2.21', '', 0, \@twin_config,
);
like(join('', @twin_config), qr/^host twinnode-xcat-ib \{$/m,
    'the writer produced the InfiniBand twin declaration the query must step over');
my ($tname, $tip, $thw) =
  xCAT_plugin::dhcp::_query_isc_static_host('twinnode', @twin_config);
is($thw, 'hardware-address = b8:3f:d2:4a:68:aa',
    'the twin declaration does not replace the primary hardware address');
is($tip, 'ip-address = 192.0.2.21',
    'the twin declaration does not replace the primary address');

# `makedhcp -q` runs with no configuration in memory, so the query reads dhcpd.conf. A
# file it cannot read must not look like a node without a reservation.
my $tmpdir   = tempdir(CLEANUP => 1);
my $conffile = "$tmpdir/dhcpd.conf";
open(my $wfh, '>', $conffile) or BAIL_OUT("cannot write $conffile: $!");
print $wfh @dhcpconf;
close($wfh);
open(my $efh, '>', "$tmpdir/empty.conf") or BAIL_OUT("cannot write empty.conf: $!");
close($efh);

{
    no warnings 'once';
    $xCAT_plugin::dhcp::dhcpconffile = $conffile;
}
my ($fname, $fip, $fhw, $ferr) =
  xCAT_plugin::dhcp::_query_isc_static_host('xcat30-cn');
is($ferr, undef, 'a readable dhcpd.conf reports no error');
is($fip, 'ip-address = 192.168.201.30',
    'the query reads the reservation from dhcpd.conf');

{
    no warnings 'once';
    $xCAT_plugin::dhcp::dhcpconffile = "$tmpdir/absent.conf";
}
my ($aname, $aip, $ahw, $aerr) =
  xCAT_plugin::dhcp::_query_isc_static_host('xcat30-cn');
like($aerr, qr/\Qabsent.conf\E/,
    'a dhcpd.conf the query cannot read is reported as an error');
is($aip, undef, 'a dhcpd.conf the query cannot read reports no address');

{
    no warnings 'once';
    $xCAT_plugin::dhcp::dhcpconffile = "$tmpdir/empty.conf";
}
my ($ename, $eip, $ehw, $eerr) =
  xCAT_plugin::dhcp::_query_isc_static_host('xcat30-cn');
is($eerr, undef, 'an empty dhcpd.conf is not an error');
is($eip, undef, 'an empty dhcpd.conf reports no reservation');

# listnode is what `makedhcp -q` calls. On an ISC-limited release it must pass the read
# failure to the caller instead of answering "no reservation found".
{
    no warnings 'once';
    $xCAT_plugin::dhcp::distro        = 'ubuntu22.04';
    $xCAT_plugin::dhcp::dhcpconffile  = "$tmpdir/absent.conf";
}
my @responses;
eval {
    local $SIG{ALRM} = sub { die "listnode did not return\n" };
    alarm 20;
    xCAT_plugin::dhcp::listnode('xcat30-cn', sub { push @responses, $_[0] });
    alarm 0;
    1;
};
alarm 0;
is(scalar(@responses), 1, 'a query answers once when dhcpd.conf cannot be read');
like($responses[0]->{error}->[0], qr/\Qabsent.conf\E/,
    'the query reports the unreadable dhcpd.conf to the caller');
is($responses[0]->{errorcode}->[0], 1, 'the query fails when dhcpd.conf cannot be read');

done_testing();
