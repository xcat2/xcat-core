#!/usr/bin/env perl
# The file makedhcp writes the DHCPv6 configuration to, per distro.
#
# ISC serves DHCPv4 and DHCPv6 from two files in the same directory. dhcp.pm derived the v6
# file only inside the branch that switches the v4 file to /etc/dhcp/dhcpd.conf. openSUSE
# ships /etc/dhcpd.conf, so that branch never ran, the v6 file stayed undef, and makedhcp
# wrote no IPv6 configuration at all. dhcpd6 then exited with "No subnet6 declaration for
# eth1" and no node could get an IPv6 lease.
use strict;
use warnings;
## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

BEGIN {
    $ENV{XCATROOT} = repo_path('xCAT-server');
    $ENV{XCATCFG}  = 'SQLite:' . tempdir( CLEANUP => 1 );
}

require( repo_path('xCAT-server/lib/xcat/plugins/dhcp.pm') );

# The v6 file sits beside the v4 one, whatever directory the distro puts it in.
is( xCAT_plugin::dhcp::dhcp6_conf_file_for('/etc/dhcpd.conf'),
    '/etc/dhcpd6.conf', 'openSUSE keeps both files in /etc' );
is( xCAT_plugin::dhcp::dhcp6_conf_file_for('/etc/dhcp/dhcpd.conf'),
    '/etc/dhcp/dhcpd6.conf', 'dhcp 4.x keeps both files in /etc/dhcp' );
is( xCAT_plugin::dhcp::dhcp6_conf_file_for('/etc/dhcp3/dhcpd.conf'),
    '/etc/dhcp3/dhcpd6.conf', 'the old Debian layout keeps both files in /etc/dhcp3' );

# AIX serves DHCP from dhcpsd.cnf and has no ISC v6 file to write.
is( xCAT_plugin::dhcp::dhcp6_conf_file_for('/etc/dhcpsd.cnf'),
    undef, 'an AIX configuration file yields no DHCPv6 file' );
is( xCAT_plugin::dhcp::dhcp6_conf_file_for(undef),
    undef, 'no DHCPv4 file yields no DHCPv6 file' );

# The wiring: whatever this host resolved the v4 file to, the v6 file is its sibling. This is
# the assertion the openSUSE layout failed, and it holds on every layout.
is( $xCAT_plugin::dhcp::dhcp6conffile,
    xCAT_plugin::dhcp::dhcp6_conf_file_for($xCAT_plugin::dhcp::dhcpconffile),
    'the module derives the DHCPv6 file from the DHCPv4 file it chose' );
ok( defined $xCAT_plugin::dhcp::dhcp6conffile,
    'this host has a DHCPv6 configuration file to write' );

# The dynamic range of an IPv6 subnet. addrangedetection keys the ranges on networks.net,
# which has no prefix length, while addnet6 names the subnet "<net>/<prefix>". The lookup
# missed, so no range6 was written and a client whose DUID matches no reservation -- the SUSE
# installer, which uses its own DUID rather than the firmware's -- received no address.
{
    local %xCAT_plugin::dhcp::netcfgs = (
        '2001:db8:156::' => { range => '2001:db8:156::1000 2001:db8:156::1fff' },
        '192.168.156.0'  => { range => '192.168.156.100 192.168.156.200' },
    );
    is( xCAT_plugin::dhcp::dynamic_range_for('2001:db8:156::/64'),
        '2001:db8:156::1000 2001:db8:156::1fff',
        'the range of an IPv6 subnet is found under the network address' );
    is( xCAT_plugin::dhcp::dynamic_range_for('2001:db8:156::'),
        '2001:db8:156::1000 2001:db8:156::1fff',
        'the bare network address still finds its range' );
    is( xCAT_plugin::dhcp::dynamic_range_for('192.168.156.0'),
        '192.168.156.100 192.168.156.200',
        'an IPv4 subnet is unchanged' );
    is( xCAT_plugin::dhcp::dynamic_range_for('2001:db8:999::/64'),
        undef, 'a subnet with no range reports none' );
    is( xCAT_plugin::dhcp::dynamic_range_for(undef), undef, 'no subnet reports no range' );
}

done_testing();
