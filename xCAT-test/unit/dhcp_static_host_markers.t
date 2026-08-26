#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

$ENV{XCATCFG} ||= 'SQLite:/tmp';

my $source_dhcp_plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/dhcp.pm";
if ( -f $source_dhcp_plugin ) {
    require $source_dhcp_plugin;
} else {
    require xCAT_plugin::dhcp;
}

my @config;

my @infiniband_config;
xCAT_plugin::dhcp::_add_isc_static_host(
    'node00', 'node00', 'b8:3f:d2:03:00:4a:68:aa', 32,
    'ib0', '192.0.2.10', '', 1, \@infiniband_config,
);
like(
    join( '', @infiniband_config ),
    qr/^\s*hardware infiniband b8:3f:d2:03:00:4a:68:aa;$/m,
    'the static-host fallback keeps an explicit InfiniBand hardware type',
);
unlike(
    join( '', @infiniband_config ),
    qr/^\s*hardware ethernet b8:3f:d2:03:00:4a:68:aa;$/m,
    'the static-host fallback does not label an InfiniBand identity as Ethernet',
);

my @dashed_mac_config;
xCAT_plugin::dhcp::_add_isc_static_host(
    'node00', 'node00', 'B8-3F-D2-4A-68-AA', 1,
    'eth0', '192.0.2.11', '', 0, \@dashed_mac_config,
);
like(
    join( '', @dashed_mac_config ),
    qr/^\s*hardware ethernet b8:3f:d2:4a:68:aa;$/m,
    'the static-host fallback emits a valid canonical dashed MAC',
);

xCAT_plugin::dhcp::_add_isc_static_host(
    'node01', 'node01', '00:11:22:33:44:55', 1,
    'eth0', '192.0.2.1', '', 0, \@config,
);
xCAT_plugin::dhcp::_add_isc_static_host(
    'node02', 'node02', '00:11:22:33:44:66', 1,
    'eth0', '192.0.2.2', '', 0, \@config,
);

like(
    join( '', @config ),
    qr/^#xCAT host declaration for node01 aka host node01 end$/m,
    'the static host end marker occupies its own line',
);

xCAT_plugin::dhcp::_delete_isc_static_host('node01', \@config);
my $remaining = join( '', @config );
unlike($remaining, qr/\bnode01\b/, 'the selected static host is removed');
like($remaining, qr/\bnode02\b/, 'the following static host is preserved');

my @legacy_config = (
    "#xCAT host declaration for node01 aka host node01 start\n",
    "host node01 {\n",
    "    hardware ethernet 00:11:22:33:44:55;\n",
    "    fixed-address 192.0.2.1;\n",
    "} #xCAT host declaration for node01 aka host node01 end\n",
    "#xCAT host declaration for node02 aka host node02 start\n",
    "host node02 {\n",
    "    hardware ethernet 00:11:22:33:44:66;\n",
    "    fixed-address 192.0.2.2;\n",
    "} #xCAT host declaration for node02 aka host node02 end\n",
);
xCAT_plugin::dhcp::_delete_isc_static_host('node01', \@legacy_config);
my $legacy_remaining = join( '', @legacy_config );
unlike($legacy_remaining, qr/\bnode01\b/,
    'a static host written by an older xCAT release is removed');
like($legacy_remaining, qr/\bnode02\b/,
    'deleting an old-format host preserves the following host');

my @multi_host_config;
xCAT_plugin::dhcp::_add_isc_static_host(
    'node03', 'node03', '00:11:22:33:44:77', 1,
    'eth0', '192.0.2.3', '', 0, \@multi_host_config,
);
xCAT_plugin::dhcp::_add_isc_static_host(
    'node03', 'node03-ib', '00:11:22:33:44:88', 32,
    'ib0', '192.0.2.3', '', 1, \@multi_host_config,
);
my $multi_host = join( '', @multi_host_config );
like($multi_host, qr/^host node03 \{$/m,
    'adding a second identity preserves the first host for a node');
like($multi_host, qr/^host node03-ib \{$/m,
    'adding a second identity records its own host for the node');

my @prefix_config;
xCAT_plugin::dhcp::_add_isc_static_host(
    'node01', 'node01', '00:11:22:33:44:99', 1,
    'eth0', '192.0.2.1', '', 0, \@prefix_config,
);
xCAT_plugin::dhcp::_add_isc_static_host(
    'node01-ib', 'node01-ib', '00:11:22:33:44:aa', 1,
    'eth0', '192.0.2.4', '', 0, \@prefix_config,
);
xCAT_plugin::dhcp::_delete_isc_static_host('node01', \@prefix_config);
my $prefix_remaining = join( '', @prefix_config );
unlike($prefix_remaining, qr/^host node01 \{$/m,
    'node-wide deletion removes the exact node');
like($prefix_remaining, qr/^host node01-ib \{$/m,
    'node-wide deletion preserves a node with the same prefix');

my @replacement_config;
xCAT_plugin::dhcp::_add_isc_static_host(
    'node04', 'node04-old', '00:11:22:33:44:bb', 1,
    'eth0', '192.0.2.5', '', 0, \@replacement_config,
);
xCAT_plugin::dhcp::_add_isc_static_host(
    'node04', 'node04-old-ib', '00:11:22:33:44:cc', 32,
    'ib0', '192.0.2.5', '', 1, \@replacement_config,
);
xCAT_plugin::dhcp::_add_isc_static_host(
    'node05', 'node05', '00:11:22:33:44:dd', 1,
    'eth0', '192.0.2.6', '', 0, \@replacement_config,
);
ok(
    xCAT_plugin::dhcp::_begin_isc_static_host_update(
        'node04', 1, \@replacement_config,
    ),
    'removing stale identities marks the static configuration as changed',
);
xCAT_plugin::dhcp::_add_isc_static_host(
    'node04', 'node04-current', '00:11:22:33:44:ee', 1,
    'eth0', '192.0.2.5', '', 0, \@replacement_config,
);
my $replacement = join( '', @replacement_config );
unlike($replacement, qr/^host node04-old(?:-ib)? \{$/m,
    're-registering a node removes identities that are no longer present');
like($replacement, qr/^host node04-current \{$/m,
    're-registering a node writes its current identity');
like($replacement, qr/^host node05 \{$/m,
    're-registering a node preserves other nodes');
ok(
    !xCAT_plugin::dhcp::_begin_isc_static_host_update(
        'node04', 0, \@replacement_config,
    ),
    'a disabled static update leaves the configuration unchanged',
);

done_testing();
