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

sub twin { return xCAT_plugin::dhcp::_infiniband_twin_mac( $_[0] ); }

is(
    xCAT_plugin::dhcp::normalize_mac('B8-3F-D2-4A-68-AA'),
    'b8:3f:d2:4a:68:aa',
    'the shared MAC normalizer canonicalizes case and separators',
);
is( twin('b8:3f:d2:4a:68:aa'), 'b8:3f:d2:03:00:4a:68:aa',
    'the port GUID of the first adapter is derived from its mac' );
is( twin('b8:3f:d2:4a:68:b2'), 'b8:3f:d2:03:00:4a:68:b2',
    'the port GUID of the second adapter is derived from its mac' );
is( twin('b8-3f-d2-4a-68-aa'), 'b8:3f:d2:03:00:4a:68:aa',
    'a dash-separated mac produces a canonical InfiniBand identity' );
is( length( twin('b8:3f:d2:4a:68:aa') ), 23,
    'the derived address is eight bytes' );

foreach my $other ( 'b8:3f:d2:03:00:4a:68:aa', '00:11:22:33:44', '', 'notamac' ) {
    is( twin($other), undef, "'$other' gives no derived address" );
}
is( twin(undef), undef, 'no mac gives no derived address' );
ok(
    xCAT_plugin::dhcp::_infiniband_identity_present(
        'b8:3f:d2:4a:68:aa!node01',
        'b8:3f:d2:03:00:4a:68:aa!node01-ib',
    ),
    'an explicit InfiniBand identity is detected in a node mac list',
);
ok(
    !xCAT_plugin::dhcp::_infiniband_identity_present(
        'b83fd203004a68aa!node01-ib',
    ),
    'a colonless address rejected by addnode is not treated as an identity',
);
ok(
    xCAT_plugin::dhcp::_infiniband_identity_present(
        'b8-3f-d2-03-00-4a-68-aa!node01-ib',
    ),
    'a valid dashed InfiniBand identity is detected in a node mac list',
);
ok(
    !xCAT_plugin::dhcp::_infiniband_identity_present(
        'b8:3f:d2:4a:68:aa!node01',
    ),
    'an Ethernet-only mac list needs the derived identity',
);
is(
    xCAT_plugin::dhcp::_hardware_type_for('b8:3f:d2:4a:68:aa', 'eth0'),
    1,
    'an Ethernet interface uses the Ethernet hardware type',
);
is(
    xCAT_plugin::dhcp::_hardware_type_for(
        'b8:3f:d2:03:00:4a:68:aa', 'ib0'
    ),
    32,
    'an eight-byte fabric address uses the InfiniBand hardware type',
);
is(
    xCAT_plugin::dhcp::_hardware_type_for('b8:3f:d2:4a:68:aa', 'hf0'),
    37,
    'an HFI interface uses the HFI hardware type',
);

is(
    xCAT_plugin::dhcp::_node_host_statements('node01', ''),
    'ddns-hostname \"node01\"; send host-name \"node01\";',
    'the default host statements identify the node',
);
is(
    xCAT_plugin::dhcp::_node_host_statements(
        'node01', 'filename = \"bootfile\";'
    ),
    'ddns-hostname \"node01\"; send host-name \"node01\";filename = \"bootfile\";',
    'node identity is prepended to existing host statements',
);
is(
    xCAT_plugin::dhcp::_noip_hostname('node01', 'B8:3F:D2:4A:68:AA'),
    'node01-noipB83FD24A68AA',
    'the denied-host name preserves the legacy MAC case',
);
is(
    xCAT_plugin::dhcp::_noip_hostname('node01', 'B8-3F-D2-4A-68-AA'),
    'node01-noipB8-3F-D2-4A-68-AA',
    'the denied-host name preserves legacy dash separators',
);

my $create_commands = <<'OMAPI';
new host
set name = "node01-xcat-ib"
open
remove
close
new host
set name = "node01-xcat-ib"
set hardware-address = b8:3f:d2:03:00:4a:68:aa
set dhcp-client-identifier = b8:3f:d2:03:00:4a:68:aa
set hardware-type = 32
set ip-address = 192.0.2.10
set statements = "ddns-hostname \"node01\"; send host-name \"node01\";"
create
close
OMAPI

is(
    xCAT_plugin::dhcp::_infiniband_twin_create_commands(
        'node01', 'b8:3f:d2:4a:68:aa', 1, 'ib0', '192.0.2.10',
        'ddns-hostname \"node01\"; send host-name \"node01\";', 1, 0
    ),
    $create_commands,
    'an Ethernet identity on an IPoIB network creates the InfiniBand twin',
);

is(
    xCAT_plugin::dhcp::_infiniband_twin_create_commands(
        'node01', 'b8:3f:d2:4a:68:aa', 1, '!service!ib0', '192.0.2.10',
        'ddns-hostname \"node01\"; send host-name \"node01\";', 1, 0
    ),
    $create_commands,
    'a relayed IPoIB interface creates the InfiniBand twin',
);

is(
    xCAT_plugin::dhcp::_infiniband_twin_create_commands(
        'node01', 'b8:3f:d2:4a:68:aa', 1, 'ib0', 'DENIED', '', 1, 0
    ),
    join( '', ( split( /^/m, $create_commands ) )[ 0 .. 9 ] )
      . "set statements = \"deny booting;\"\ncreate\nclose\n",
    'a denied Ethernet identity creates a denied InfiniBand twin',
);

is(
    xCAT_plugin::dhcp::_infiniband_twin_create_commands(
        'node01', 'b8:3f:d2:4a:68:aa', 32, 'ib0', '192.0.2.10', '', 1, 1
    ),
    undef,
    'an existing InfiniBand identity does not create another twin',
);
is(
    xCAT_plugin::dhcp::_infiniband_twin_create_commands(
        'node01', 'b8:3f:d2:4a:68:aa', 1, 'eth0', '192.0.2.10', '', 1, 0
    ),
    undef,
    'an Ethernet network does not create an InfiniBand twin',
);

my $create_without_cleanup = <<'OMAPI';
new host
set name = "node01-xcat-ib"
set hardware-address = b8:3f:d2:03:00:4a:68:aa
set dhcp-client-identifier = b8:3f:d2:03:00:4a:68:aa
set hardware-type = 32
set ip-address = 192.0.2.10
set statements = "ddns-hostname \"node01\"; send host-name \"node01\";"
create
close
OMAPI
is(
    xCAT_plugin::dhcp::_infiniband_twin_create_commands(
        'node01', 'b8:3f:d2:4a:68:aa', 1, 'ib0', '192.0.2.10',
        'ddns-hostname \"node01\"; send host-name \"node01\";', 0, 0
    ),
    $create_without_cleanup,
    'the Ubuntu-limited OMAPI path creates the twin without a failed-open cleanup',
);
my $create_without_address = $create_without_cleanup;
$create_without_address =~ s/^set ip-address = .*\n//m;
is(
    xCAT_plugin::dhcp::_infiniband_twin_create_commands(
        'node01', 'b8:3f:d2:4a:68:aa', 1, 'ib0', undef,
        'ddns-hostname \"node01\"; send host-name \"node01\";', 0, 0
    ),
    $create_without_address,
    'an unresolved IP omits only the twin address',
);
is(
    xCAT_plugin::dhcp::_infiniband_twin_create_commands(
        'node01', 'b8:3f:d2:4a:68:aa', 1, 'ib0', '192.0.2.10', '', 1, 1
    ),
    undef,
    'an explicit InfiniBand identity suppresses the derived twin',
);

is_deeply(
    [ xCAT_plugin::dhcp::_infiniband_twin_static_lines(
        'node01', 'b8:3f:d2:4a:68:aa', 1, 'ib0', '192.0.2.10',
        'option host-name "node01";', 0
    ) ],
    [
        "host node01-xcat-ib {\n",
        "    hardware infiniband b8:3f:d2:03:00:4a:68:aa;\n",
        "    fixed-address 192.0.2.10;\n",
        "    option host-name \"node01\";\n",
        "}\n",
    ],
    'the static-host fallback declares the derived InfiniBand identity',
);

my $delete_name_commands = <<'OMAPI';
new host
set name = "node01-xcat-ib"
open
remove
close
OMAPI
my $delete_address_commands = <<'OMAPI';
new host
set hardware-address = b8:3f:d2:03:00:4a:68:aa
set hardware-type = 32
open
remove
close
OMAPI

is(
    xCAT_plugin::dhcp::_hardware_address_delete_commands(
        'b8:3f:d2:4a:68:aa', 1
    ),
    "new host\nset hardware-address = b8:3f:d2:4a:68:aa\nopen\nremove\nclose\n",
    'Ethernet cleanup keeps the legacy hardware-address lookup',
);
is(
    xCAT_plugin::dhcp::_hardware_address_delete_commands(
        'b8:3f:d2:03:00:4a:68:aa', 32
    ),
    $delete_address_commands,
    'InfiniBand cleanup includes its OMAPI hardware type',
);

my @delete_commands = xCAT_plugin::dhcp::_infiniband_twin_delete_commands(
    'node01', 'b8:3f:d2:4a:68:aa', 1, 'ib0', 1, 0
);
is_deeply(
    \@delete_commands,
    [ $delete_name_commands, $delete_address_commands ],
    'removing a node produces separate name and address cleanup commands',
);
my @moved_network_delete_commands =
  xCAT_plugin::dhcp::_infiniband_twin_delete_commands(
    'node01', 'b8-3f-d2-4a-68-aa', 1, 'eth0', 1, 1
  );
is_deeply(
    \@moved_network_delete_commands,
    [ $delete_name_commands, undef ],
    'removing a moved node cleans up its old twin by name only',
);
my @limited_delete_commands =
  xCAT_plugin::dhcp::_infiniband_twin_delete_commands(
    'node01', 'b8:3f:d2:4a:68:aa', 1, 'ib0', 0, 0
  );
is_deeply(
    \@limited_delete_commands,
    [ $delete_name_commands, undef ],
    'the Ubuntu-limited OMAPI path still removes the twin by name',
);
my @limited_ethernet_delete_commands =
  xCAT_plugin::dhcp::_infiniband_twin_delete_commands(
    'node01', 'b8:3f:d2:4a:68:aa', 1, 'eth0', 0, 0
  );
is_deeply(
    \@limited_ethernet_delete_commands,
    [],
    'the Ubuntu-limited OMAPI path avoids a failed-open cleanup on Ethernet',
);

my @moved_network_update_commands =
  xCAT_plugin::dhcp::_infiniband_twin_update_commands(
    'node01', 'b8:3f:d2:4a:68:aa', 1, 'eth0', '192.0.2.10',
    'ddns-hostname \"node01\"; send host-name \"node01\";', 1, 0
  );
is_deeply(
    \@moved_network_update_commands,
    [ $delete_name_commands, undef, undef ],
    're-registering a node on Ethernet removes its former twin by name only',
);

my @infiniband_update_commands =
  xCAT_plugin::dhcp::_infiniband_twin_update_commands(
    'node01', 'b8:3f:d2:4a:68:aa', 1, 'ib0', '192.0.2.10',
    'ddns-hostname \"node01\"; send host-name \"node01\";', 1, 0
  );
is_deeply(
    \@infiniband_update_commands,
    [ $delete_name_commands, $delete_address_commands, $create_without_cleanup ],
    're-registering an IPoIB node replaces its generated twin',
);

my @limited_update_commands =
  xCAT_plugin::dhcp::_infiniband_twin_update_commands(
    'node01', 'b8:3f:d2:4a:68:aa', 1, 'ib0', '192.0.2.10',
    'ddns-hostname \"node01\"; send host-name \"node01\";', 0, 0
  );
is_deeply(
    \@limited_update_commands,
    [ undef, undef, $create_without_cleanup ],
    'the limited OMAPI path does not attempt a failed-open cleanup',
);

my @explicit_identity_update_commands =
  xCAT_plugin::dhcp::_infiniband_twin_update_commands(
    'node01', 'b8:3f:d2:4a:68:aa', 1, 'ib0', '192.0.2.10',
    'ddns-hostname \"node01\"; send host-name \"node01\";', 1, 1
  );
is_deeply(
    \@explicit_identity_update_commands,
    [ $delete_name_commands, undef, undef ],
    'updating an explicit InfiniBand identity does not remove it by address',
);

# The mgtifname of a network can name more than one interface, separated by !.
# The InfiniBand interface is not always the last one, so a test that only
# matches the last name leaves a node on ib0!eth0 without its second entry.
foreach my $ifname (qw(ib0 ib0.8001 eth0!ib0 ib0!eth0 ib0!ib1 bond0!ib2)) {
    ok( xCAT_plugin::dhcp::_is_infiniband_interface($ifname),
        "'$ifname' is served by an InfiniBand interface" );
}
foreach my $ifname (qw(eth0 eth0!eth1 bond0 hf0)) {
    ok( !xCAT_plugin::dhcp::_is_infiniband_interface($ifname),
        "'$ifname' is not served by an InfiniBand interface" );
}
ok( !xCAT_plugin::dhcp::_is_infiniband_interface(undef),
    'a network with no interface name is not served by InfiniBand' );

done_testing();
