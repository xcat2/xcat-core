use strict;
use warnings;

BEGIN { $ENV{XCATROOT} = '/nonexistent-xcat-test'; $ENV{XCATCFG} = 'SQLite:/tmp'; }
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Temp qw(tempdir);
use Test::More;
use DBI;
use xCAT::Table;
use xCAT::FreeBSDNetwork;
use xCAT::DHCP::Backend::Kea;

my $dhcp_plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/dhcp.pm";
require $dhcp_plugin;
our %XCATSITEVALS;

my $planner = "$FindBin::Bin/../../xCAT/postscripts/confignetwork-freebsd.awk";
my $uuid = '01234567-89ab-cdef-0123-456789abcdef';
my $duid = '00:04:01:23:45:67:89:ab:cd:ef:01:23:45:67:89:ab:cd:ef';
my $networks = [{ netname => 'data', net => '192.0.2.0', mask => '255.255.255.0', mtu => '2044' },
    { netname => 'ethernet', net => '192.0.3.0', mask => '255.255.255.0', mtu => '1500' }];
my $nics = { nictypes => 'ib0!Infiniband', nicips => 'ib0!192.0.2.10',
    nicnetworks => 'ib0!data', nicextraparams => 'ib0!BOOTPROTO=dhcp' };

sub reservation_plan { return xCAT::FreeBSDNetwork::dhcp4_reservations($_[0], $networks, $_[1], $planner); }

sub compare_native_plan {
    my ($nics, $reservations, $label) = @_;
    my %env = (LC_ALL => 'C', NETWORKS_LINES => 2,
        NETWORKS_LINE1 => 'netname=data||net=192.0.2.0||mask=255.255.255.0||mtu=2044',
        NETWORKS_LINE2 => 'netname=ethernet||net=192.0.3.0||mask=255.255.255.0||mtu=1500',
        IPADDR => '198.51.100.10', MASTER_IP => '198.51.100.1');
    $env{uc($_)} = $nics->{$_} || '' for qw(nictypes nicdevices nicips nicnetworks nicextraparams);
    my $native = xCAT::FreeBSDPkg::run_command(
        ['/usr/bin/awk', '-v', 'bootnic=vtnet0', '-v', 'configure_boot=0', '-f', $planner],
        environment => \%env, timeout => 10);
    is($native->{exitcode}, 0, "$label native application plan compiles") or diag($native->{stderr});
    my (%ib, %dhcp);
    for my $line (split(/\n/, $native->{stdout})) {
        my ($kind, $nic, $ip) = split(/\t/, $line);
        $ib{$nic} = 1 if $kind eq 'G';
        $dhcp{$nic} = $ip if $kind eq 'H';
    }
    is_deeply({ map { $_->{interface} => $_->{address} } @$reservations },
        { map { $_ => $dhcp{$_} } grep { $ib{$_} } keys %dhcp },
        "$label server reservation selection matches the native application plan");
}

my $physical = reservation_plan($nics, $uuid);
is_deeply($physical, [{ interface => 'ib0', address => '192.0.2.10',
    client_id => "ff:92:bc:48:24:$duid" }], 'physical IPoIB uses the native client option 61 identity');
compare_native_plan($nics, $physical, 'physical port');
my $guid_policy = { %$nics, nicextraparams => 'ib0!dhcp4=true PORT_GUID=01:23:45:67:89:ab:cd:ef' };
is_deeply(reservation_plan($guid_policy, $uuid), $physical, 'dhcp4 spelling and port GUID retain the client identity');
compare_native_plan($guid_policy, $physical, 'dhcp4 and port GUID');

for my $case (
    ['vlan10', 'ib0!Infiniband,vlan10!vlan', 'vlan10!ib0', 'PKEY=0x800a', 'ac:5a:f1:f1'],
    ['lagg0', 'ib0!Infiniband,ib1!Infiniband,lagg0!bond-infiniband', 'lagg0!ib0|ib1', 'LAGGPROTO=failover', 'f6:00:46:ec']) {
    my ($nic, $types, $devices, $options, $iaid) = @$case;
    my $policy = { nictypes => $types, nicdevices => $devices, nicips => "$nic!192.0.2.10",
        nicnetworks => "$nic!data", nicextraparams => "$nic!$options BOOTPROTO=dhcp" };
    my $got = reservation_plan($policy, $uuid);
    is_deeply($got, [{ interface => $nic, address => '192.0.2.10', client_id => "ff:$iaid:$duid" }],
        "$nic uses its own IAID and the node UUID");
    compare_native_plan($policy, $got, $nic);
}

for my $boot ('static', 'dhcp') {
    my $mixed = { nictypes => 'ib0!infiniband,vtnet1!ethernet',
        nicips => 'ib0!192.0.2.10,vtnet1!192.0.3.11', nicnetworks => 'ib0!data,vtnet1!ethernet',
        nicextraparams => "ib0!BOOTPROTO=$boot,vtnet1!BOOTPROTO=dhcp" };
    compare_native_plan($mixed, reservation_plan($mixed, $uuid), "$boot IPoIB with Ethernet DHCP");
}

is_deeply(reservation_plan({ %$nics, nicextraparams => '' }, undef), [], 'static IPoIB does not require a DHCP UUID');
is_deeply(reservation_plan({ nictypes => 'vtnet0!ethernet' }, undef), [], 'Ethernet does not acquire an IPoIB reservation');
for my $invalid (undef, '', 'not-a-uuid', '00000000-0000-0000-0000-000000000000',
    'ffffffff-ffff-ffff-ffff-ffffffffffff', "$uuid\n") {
    my $ok = eval { reservation_plan($nics, $invalid); 1 };
    ok(!$ok, 'an invalid UUID cannot produce a reservation');
    like($@, qr/vpd[.]uuid/, 'the diagnostic names the inventory field');
}
for my $change (
    { nicips => 'ib0!192.0.3.10' }, { nicips => '' },
    { nicextraparams => 'ib0!BOOTPROTO=dhcp CONNECTED_MODE=yes' },
    { nicextraparams => 'ib0!BOOTPROTO=dhcp UNKNOWN=yes' },
    { nictypes => 'ib0!Infiniband,ib1!Infiniband,lagg0!lagg', nicdevices => 'lagg0!ib0|ib1',
      nicips => 'lagg0!192.0.2.10', nicnetworks => 'lagg0!data',
      nicextraparams => 'lagg0!BOOTPROTO=dhcp LAGGPROTO=lacp' }) {
    my $ok = eval { reservation_plan({ %$nics, %$change }, $uuid); 1 };
    ok(!$ok, 'invalid address or topology fails before reservation publication');
}

my @config;
my $entry = { %{ $physical->[0] }, hostname => 'compute-xcat-ipoib-ib0' };
xCAT_plugin::dhcp::_add_isc_static_host('compute', 'compute', '52:54:00:00:00:01',
    1, 'eth0', '198.51.100.10', '', 0, \@config);
my @ethernet = @config;
xCAT_plugin::dhcp::_isc_ipoib_update('compute', [$entry], \@config);
my @ib_first;
xCAT_plugin::dhcp::_isc_ipoib_update('compute', [$entry], \@ib_first);
push @ib_first, @ethernet;
my (undef, $boot_ip) = xCAT_plugin::dhcp::_query_isc_static_host('compute', @ib_first);
is($boot_ip, 'ip-address = 198.51.100.10', 'an earlier IPoIB block does not supply the boot query address');
my (undef, $quoted_ip) = xCAT_plugin::dhcp::_parse_omshell_host_output('compute', 'ip-address = "d@(2"');
is($quoted_ip, 'ip-address = 100.64.40.50', 'printable OMAPI IPv4 bytes decode to a dotted address');
like(join('', @config), qr/host-identifier option dhcp-client-identifier \Q$entry->{client_id}\E;/,
    'ISC matches option 61 without an Ethernet hardware declaration');
is_deeply(xCAT_plugin::dhcp::_isc_ipoib_hosts('compute', \@config),
    [{ map { $_ => $entry->{$_} } qw(hostname address client_id) }], 'ISC query reads the generated reservation');
xCAT_plugin::dhcp::_isc_ipoib_update('compute-01', [{ %$entry, hostname => 'compute-01-xcat-ipoib-ib0' }], \@config);
my $stable = join('', @config);
xCAT_plugin::dhcp::_isc_ipoib_update('compute', [$entry], \@config);
is(join('', @config), $stable, 'an unchanged ISC reservation keeps its position among other nodes');
xCAT_plugin::dhcp::_isc_ipoib_update('compute', [{ %$entry, hostname => 'compute-xcat-ipoib-ib9', address => '192.0.2.11' }], \@config);
is_deeply([map { $_->{hostname} } @{ xCAT_plugin::dhcp::_isc_ipoib_hosts('compute', \@config) }],
    ['compute-xcat-ipoib-ib9'], 'ISC update removes the old interface name');
xCAT_plugin::dhcp::_isc_ipoib_update('compute', [], \@config);
is_deeply(xCAT_plugin::dhcp::_isc_ipoib_hosts('compute', \@config), [], 'ISC deletion removes all owned IPoIB hosts');
is(scalar @{ xCAT_plugin::dhcp::_isc_ipoib_hosts('compute-01', \@config) }, 1,
    'ISC deletion preserves a node with a shared name prefix');
like(join('', @config), qr/\Q@{[join('', @ethernet)]}\E/, 'ISC update and deletion preserve the Ethernet boot host');

my $backend = xCAT::DHCP::Backend::Kea->new(kea_version => '2.4.1');
my $config = { Dhcp4 => { 'match-client-id' => JSON::false, 'host-reservation-identifiers' => ['hw-address'],
    subnet4 => [{ id => 1, subnet => '192.0.2.0/24' }, { id => 2, subnet => '198.51.100.0/24' }] } };
my $reservations = xCAT_plugin::dhcp::_kea_ipoib_reservations($backend, $config, 'compute', [$entry]);
$backend->upsert_reservations($config, $reservations);
ok(xCAT_plugin::dhcp::_kea_ipoib_matching($config, $reservations), 'Kea matching change requires a reload');
ok($config->{Dhcp4}{subnet4}[0]{'match-client-id'}, 'Kea enables client identifiers for the IPoIB subnet');
ok(!$config->{Dhcp4}{'match-client-id'}, 'the global Ethernet lease matching default is retained');
ok(!exists $config->{Dhcp4}{subnet4}[1]{'match-client-id'}, 'an unrelated subnet is unchanged');
is_deeply($config->{Dhcp4}{'host-reservation-identifiers'}, ['hw-address', 'client-id'], 'explicit identifier lists also permit option 61');
is(scalar @{ $backend->query_reservations($config, { 'client-id' => $entry->{client_id} }) }, 1,
    'Kea queries client-id reservations');
my $collision = eval { xCAT_plugin::dhcp::_kea_ipoib_reservations($backend, $config, 'other', [$entry]); 1 };
ok(!$collision, 'another node cannot replace a reservation with the same client ID or address');
like($@, qr/conflicts with another Kea host/, 'the identity conflict is reported');
my $owner = xCAT_plugin::dhcp::_kea_ipoib_owner('compute');
is(scalar @{ $backend->query_reservations($config, $owner) }, 1, 'ownership finds the reservation without current NIC or UUID inventory');
is(scalar @{ $backend->delete_reservations($config, { 'ip-address' => $entry->{address} }) }, 0,
    'an IP-only legacy deletion cannot remove an owned IPoIB reservation');
is(scalar @{ $backend->query_reservations($config, { 'ip-address' => $entry->{address} }) }, 1,
    'IP lookup still finds the reservation for conflict checks');
is(scalar @{ $backend->delete_reservations($config, xCAT_plugin::dhcp::_kea_ipoib_owner('compute-01')) }, 0,
    'Kea ownership does not match a name prefix');
is(scalar @{ $backend->delete_reservations($config, $owner) }, 1, 'Kea deletes by owner after an interface is removed');

{
    no warnings qw(once redefine);
    my @commands;
    local *xCAT::DHCP::Backend::Kea::control_agent_command = sub {
        my ($self, $command, $arguments) = @_;
        push @commands, [$command, $arguments];
        return { ok => 1 };
    };
    $backend->live_delete_reservations($reservations);
    is_deeply($commands[0], ['reservation-del', { 'subnet-id' => 1,
        'operation-target' => 'memory', 'identifier-type' => 'client-id', identifier => $entry->{client_id} }],
        'live Kea deletion uses the complete client identifier');
}

{
    no warnings qw(once redefine);
    my $directory = tempdir(CLEANUP => 1);
    xCAT_plugin::dhcp::_freebsd_ipoib_reset();
    local $XCATSITEVALS{externaldhcpservers} = 'dhcp.example.test';
    local *xCAT_plugin::dhcp::_isc_ipoib_state_directory = sub { return $directory; };
    local *xCAT_plugin::dhcp::_omapi_settings = sub {
        return { key_name => 'test-key', algorithm => 'hmac-sha256', port => 7911 };
    };
    local *xCAT_plugin::dhcp::_omapi_passwd_entry = sub { return { password => 'test-only' }; };
    my $old = 'compute-xcat-ipoib-ib9';
    xCAT_plugin::dhcp::_isc_ipoib_save_names('compute', [$old]);
    my @commands;
    local *xCAT_plugin::dhcp::_run_omshell = sub {
        push @commands, $_[0];
        return ("can't open object: not found\n") if $_[0] =~ /\Q$old\E/ && $_[0] !~ /\nremove\n/;
        return ("ip-address = c0:00:02:0a\n", "can't open object: not found\n")
            if $_[0] =~ /new host\nset (?:ip-address|dhcp-client-identifier)/;
        return ();
    };
    my $ok = eval { xCAT_plugin::dhcp::_isc_ipoib_external_update('compute', [$entry]); 1 };
    ok(!$ok, 'failed OMAPI readback is an error');
    is_deeply(xCAT_plugin::dhcp::_isc_ipoib_external_names('compute'),
        ['compute-xcat-ipoib-ib0', $old], 'failed external updates retain both cleanup names for retry');
    like($commands[0], qr/server dhcp[.]example[.]test\n/, 'OMAPI targets the configured external server');
    like(join('', @commands), qr/set dhcp-client-identifier = \Q$entry->{client_id}\E\n/,
        'OMAPI creation uses the full option 61 identity');
    my $pending_size = -s xCAT_plugin::dhcp::_isc_ipoib_state_path('compute');
    $ok = eval { xCAT_plugin::dhcp::_isc_ipoib_external_update('compute', [$entry]); 1 };
    ok(!$ok, 'a repeated failed readback still reports failure');
    is(-s xCAT_plugin::dhcp::_isc_ipoib_state_path('compute'), $pending_size,
        'repeating the same failed update does not grow the ownership journal');
    my $other = { %$entry, hostname => 'other-xcat-ipoib-ib0', client_id => "ff:00:00:00:01:$duid" };
    @commands = ();
    $ok = eval { xCAT_plugin::dhcp::_isc_ipoib_external_update('other', [$other]); 1 };
    ok(!$ok, 'a failed verify still reserves the pending address against another owner');
    like($@, qr/conflicts with another ISC host/, 'pending address conflict survives cache rebuild');
    is(scalar(@commands), 0, 'a retained cross-owner conflict needs no remote scan or write');
    local *xCAT_plugin::dhcp::_run_omshell = sub {
        my $command = shift;
        return () if $command =~ /\nremove\n/;
        return ("can't open object: not found\n") if $command =~ /\Q$old\E/;
        return ("name = \"$entry->{hostname}\"\n", "ip-address = c0:00:02:0a\n",
            "dhcp-client-identifier = $entry->{client_id}\n");
    };
    xCAT_plugin::dhcp::_isc_ipoib_external_update('compute', [$entry]);
    is_deeply(xCAT_plugin::dhcp::_isc_ipoib_external_names('compute'), [$entry->{hostname}],
        'verified external updates discard removed names');
    xCAT_plugin::dhcp::_freebsd_ipoib_reset();
    my $queries = 0;
    {
        local *xCAT_plugin::dhcp::_run_omshell = sub { ++$queries; die 'unexpected remote lookup'; };
        my $hosts = xCAT_plugin::dhcp::_isc_ipoib_external_hosts({}, '');
        is($hosts->[0]{address}, $entry->{address}, 'verified address inventory survives a new request');
        is($queries, 0, 'a new request checks other owners without an OMAPI scan');
    }
    local *xCAT_plugin::dhcp::_run_omshell = sub { return ("can't open object: not found\n"); };
    xCAT_plugin::dhcp::_isc_ipoib_external_update('compute', []);
    is_deeply(xCAT_plugin::dhcp::_isc_ipoib_external_names('compute'), [],
        'verified external deletion clears the ownership inventory');
    ok(!-e xCAT_plugin::dhcp::_isc_ipoib_state_path('compute'), 'deletion removes the empty inventory file');
}

{
    no warnings qw(once redefine);
    my %table_rows;
    my ($mac_reads, $owner_reads) = (0, 0);
    local *xCAT::Table::new = sub { return bless { name => $_[1] }, $_[0]; };
    local *xCAT::Table::getNodeAttribs = sub { return $table_rows{$_[0]{name}}{$_[1]}; };
    local *xCAT::Table::getNodesAttribs = sub {
        my ($self, $nodes) = @_;
        return { map { $_ => [$table_rows{$self->{name}}{$_}] } grep { $table_rows{$self->{name}}{$_} } @$nodes };
    };
    local *xCAT::Table::getAllAttribs = sub { return values %{ $table_rows{$_[0]{name}} || {} }; };
    local *xCAT::Table::getAllEntries = sub {
        ++$owner_reads;
        return [map { +{ node => $_, %{ $table_rows{$_[0]{name}}{$_} } } } keys %{ $table_rows{$_[0]{name}} || {} }];
    };
    local *xCAT::Table::getAllNodeAttribs = sub {
        ++$mac_reads if $_[0]{name} eq 'mac';
        my $rows = $table_rows{$_[0]{name}} || {};
        return map { +{ node => $_, %{ $rows->{$_} } } } keys %$rows;
    };
    local *xCAT::TableUtils::getInstallDir = sub { return "$FindBin::Bin/../../xCAT"; };
    local *xCAT::TableUtils::get_site_attribute = sub { return; };
    local *xCAT_plugin::dhcp::getipaddr = sub { return $_[0] eq 'data-alias' ? '192.0.2.10' : '198.51.100.10'; };
    local *xCAT::MsgUtils::trace = sub { return; };
    my @messages;
    local @ARGV;
    my $mask = umask;
    xCAT_plugin::dhcp::process_request({ _xcatpreprocessed => [0], arg => ['-q', '-a'] }, sub { push @messages, @_ });
    umask $mask;
    %table_rows = (
        nodelist => { compute => { node => 'compute' } },
        nodetype => { compute => { os => 'freebsd15.1' } },
        noderes => { compute => { xcatmaster => '198.51.100.1', netboot => 'pxe' } },
        nics => { compute => { %$nics } },
        networks => { data => $networks->[0] },
        vpd => { compute => { uuid => $uuid } },
        mac => { compute => { mac => '52:54:00:00:00:01' } },
    );
    my $nt = $table_rows{nodetype}{compute};
    my $got = xCAT_plugin::dhcp::_freebsd_ipoib_reservations('compute', $nt);
    is($got->[0]{client_id}, $entry->{client_id}, 'the table reader reaches the shared planner');
    $table_rows{nics}{compute}{nicextraparams} = 'ib0!dhcp4=true';
    is_deeply(xCAT_plugin::dhcp::_freebsd_ipoib_reservations('compute', $nt), $got,
        'the makedhcp table reader accepts the documented dhcp4 spelling');
    is($mac_reads, 1, 'multiple node plans share one MAC inventory scan');
    $table_rows{nics}{compute}{nicips} = 'ib0!|compute|192.0.2.10|';
    is_deeply(xCAT_plugin::dhcp::_freebsd_ipoib_reservations('compute', $nt), $got,
        'per-interface address expressions match postscript expansion');
    $table_rows{mac}{compute}{mac} .= '!data-alias';
    xCAT_plugin::dhcp::_freebsd_ipoib_reset();
    my $ok = eval { xCAT_plugin::dhcp::_freebsd_ipoib_reservations('compute', $nt); 1 };
    ok(!$ok, 'an IPoIB reservation cannot take a planned MAC alias address');
    like($@, qr/conflicts with MAC reservation data-alias/, 'the planned MAC conflict identifies the alias');
    $table_rows{mac}{compute}{mac} = '52:54:00:00:00:01';
    xCAT_plugin::dhcp::_freebsd_ipoib_reset();
    $table_rows{vpd}{compute}{uuid} = 'bad';
    my $cfg = { Dhcp4 => { subnet4 => [
        { id => 1, subnet => '192.0.2.0/24' }, { id => 2, subnet => '198.51.100.0/24' }] } };
    my (@deleted, @accepted);
    my $hosts = xCAT_plugin::dhcp::kea_build_node_reservations($backend, $cfg, ['compute'], \@deleted, \@accepted);
    is(scalar(@$hosts), 1, 'invalid IPoIB inventory still publishes the Ethernet boot reservation');
    is($hosts->[0]{'hw-address'}, '52:54:00:00:00:01', 'the retained reservation uses the boot MAC');
    is_deeply(\@accepted, ['compute'], 'IPv6 and boot-class updates retain the node');
    ok(grep($_->{error}, @messages), 'invalid IPoIB inventory is reported explicitly');
    $table_rows{vpd}{compute}{uuid} = $uuid;
    my $old = xCAT_plugin::dhcp::_kea_ipoib_reservations($backend, $cfg, 'old-name', [$entry]);
    $backend->upsert_reservations($cfg, $old);
    xCAT_plugin::dhcp::_kea_ipoib_prune($backend, $cfg, \@deleted);
    $hosts = xCAT_plugin::dhcp::kea_build_node_reservations($backend, $cfg, ['compute'], \@deleted);
    is(scalar(@$hosts), 2, 'a renamed node can reclaim its IPoIB reservation');
    is(scalar(@deleted), 1, 'the removed node owner is deleted before replacement');
    $backend->upsert_reservations($cfg, $hosts);
    @deleted = ();
    $hosts = xCAT_plugin::dhcp::kea_build_node_reservations($backend, $cfg, ['compute'], \@deleted);
    is(scalar(@deleted), 0, 'Kea upsert does not pre-delete identities that it will replace itself');
    $backend->upsert_reservations($cfg, $hosts);
    my @previous;
    xCAT_plugin::dhcp::_isc_ipoib_update('compute', [$entry], \@previous);
    xCAT_plugin::dhcp::_isc_ipoib_update('old-name', [{ %$entry, hostname => 'old-name-xcat-ipoib-ib0' }], \@previous);
    xCAT_plugin::dhcp::_isc_ipoib_prune(\@previous);
    is_deeply([xCAT_plugin::dhcp::_isc_ipoib_owners(\@previous)], ['compute'], 'ISC prunes only a removed node owner');
    my @regenerated = ("subnet 192.0.2.0 netmask 255.255.255.0 { }\n");
    xCAT_plugin::dhcp::_isc_ipoib_restore(\@previous, \@regenerated);
    is_deeply(xCAT_plugin::dhcp::_isc_ipoib_hosts('compute', \@regenerated),
        [{ map { $_ => $entry->{$_} } qw(hostname address client_id) }],
        'ISC network regeneration retains served IPoIB reservations');
    is($owner_reads, 1, 'pruning and regeneration share one complete node inventory read');
    my $cache_host = { %$entry, hostname => 'cache-node-xcat-ipoib-ib0', address => '198.51.100.10' };
    xCAT_plugin::dhcp::_isc_ipoib_update('cache-node', [$cache_host]);
    $ok = eval { xCAT_plugin::dhcp::_isc_ipoib_boot_allowed('compute'); 1 };
    ok(!$ok, 'the live ISC index rejects a boot address collision');
    xCAT_plugin::dhcp::_begin_isc_static_host_update('cache-node', 1);
    ok(xCAT_plugin::dhcp::_isc_ipoib_boot_allowed('compute'), 'fallback group removal updates the live ISC index');
    xCAT_plugin::dhcp::_isc_ipoib_update('cache-node', [$cache_host]);
    $ok = eval { xCAT_plugin::dhcp::_isc_ipoib_boot_allowed('compute'); 1 };
    ok(!$ok, 'restoring an owned group restores its conflict protection');
    xCAT_plugin::dhcp::_isc_ipoib_update('cache-node', []);
    ok(xCAT_plugin::dhcp::_isc_ipoib_boot_allowed('compute'), 'owned deletion removes the live index entry');
    {
        my $directory = tempdir(CLEANUP => 1);
        local $XCATSITEVALS{externaldhcpservers} = 'dhcp.example.test';
        local *xCAT_plugin::dhcp::_isc_ipoib_state_directory = sub { return $directory; };
        local *xCAT_plugin::dhcp::_omapi_settings = sub { die 'unexpected OMAPI settings lookup'; };
        xCAT_plugin::dhcp::_freebsd_ipoib_reset();
        xCAT_plugin::dhcp::_isc_ipoib_save_names('compute', [$entry->{hostname}], [$entry]);
        $ok = eval { xCAT_plugin::dhcp::_isc_ipoib_boot_allowed('compute'); 1 };
        ok($ok, 'verified external ownership needs no OMAPI credentials for an unrelated boot update') or diag($@);
    }
    my $before = join('', @previous);
    xCAT_plugin::dhcp::_freebsd_ipoib_reset();
    local *xCAT::Table::getAllEntries = sub { return; };
    $ok = eval { xCAT_plugin::dhcp::_isc_ipoib_prune(\@previous); 1 };
    ok(!$ok, 'a node inventory read failure prevents pruning');
    is(join('', @previous), $before, 'a failed node inventory read preserves reservations');
    my $saved = $backend->encode_config($cfg);
    $ok = eval { xCAT_plugin::dhcp::_kea_ipoib_prune($backend, $cfg, \@deleted); 1 };
    ok(!$ok, 'Kea also rejects an unreadable owner inventory');
    is($backend->encode_config($cfg), $saved, 'Kea preserves reservations after a database read failure');
}

{
    no warnings qw(once redefine);
    my $directory = tempdir(CLEANUP => 1);
    my $dsn = "dbi:SQLite:dbname=$directory/owners.sqlite";
    my $reader = DBI->connect($dsn, '', '', { RaiseError => 0, PrintError => 0, AutoCommit => 1 });
    my $writer = DBI->connect($dsn, '', '', { RaiseError => 1, AutoCommit => 1 });
    $reader->do('CREATE TABLE nodelist (node TEXT PRIMARY KEY, disable TEXT)');
    $reader->do("INSERT INTO nodelist VALUES ('compute', NULL)");
    $reader->sqlite_busy_timeout(1);
    my $table = bless { dbh => $reader, tabname => 'nodelist' }, 'xCAT::Table';
    local *xCAT::Table::new = sub { return $table; };
    local *xCAT::Table::trace_db = sub { return; };
    my @owned;
    xCAT_plugin::dhcp::_isc_ipoib_update('compute', [$entry], \@owned);
    my $before = join('', @owned);
    my $cfg = { Dhcp4 => { subnet4 => [{ id => 1, subnet => '192.0.2.0/24' }] } };
    $backend->upsert_reservations($cfg,
        xCAT_plugin::dhcp::_kea_ipoib_reservations($backend, $cfg, 'compute', [$entry]));
    my $saved = $backend->encode_config($cfg);
    $writer->do('BEGIN EXCLUSIVE');
    ok(!defined($table->getAllEntries(1)), 'a locked database returns a read failure instead of an empty inventory');
    xCAT_plugin::dhcp::_freebsd_ipoib_reset();
    my $ok = eval { xCAT_plugin::dhcp::_isc_ipoib_prune(\@owned); 1 };
    ok(!$ok, 'a real SQLite execution error stops ISC pruning');
    is(join('', @owned), $before, 'a real SQLite execution error preserves the ISC reservation');
    $ok = eval { xCAT_plugin::dhcp::_kea_ipoib_prune($backend, $cfg, []); 1 };
    ok(!$ok, 'a real SQLite execution error stops Kea pruning');
    is($backend->encode_config($cfg), $saved, 'a real SQLite execution error preserves the Kea reservation');
    $writer->do('ROLLBACK');
    is_deeply($table->getAllEntries(1), [{ node => 'compute', disable => undef }], 'inventory reads recover after the lock is released');
    $reader->do('DELETE FROM nodelist');
    is_deeply($table->getAllEntries(1), [], 'a successful empty-table read is distinct from failure');
    xCAT_plugin::dhcp::_freebsd_ipoib_reset();
    xCAT_plugin::dhcp::_isc_ipoib_prune(\@owned);
    is_deeply(\@owned, [], 'a successfully read empty inventory allows stale-owner cleanup');
    $reader->do("INSERT INTO nodelist VALUES ('compute', NULL), ('other', NULL), ('third', NULL)");
    $reader->do('ALTER TABLE nodelist RENAME TO owner_data');
    my $calls = 0;
    $reader->sqlite_create_function('owner_value', 1, sub { die 'interrupted read' if ++$calls > 1; return $_[0]; });
    $reader->do('CREATE VIEW nodelist AS SELECT owner_value(node) AS node, disable FROM owner_data');
    ok(!defined($table->getAllEntries(1)), 'a failed fetch does not return a partial owner inventory');
    cmp_ok($calls, '>', 1, 'the fetch control fails after reading begins');
}

done_testing();
