#!/usr/bin/env perl
# The DHCPv6 client identifier that makedhcp reserves the IPv6 address of a node for. mac.duid selects
# it: firmware (the default) is the DUID-UUID that EDK2 firmware sends, canonical is vpd.uuid in RFC 4122
# byte order, and any other value is the DUID itself. ISC DHCP and Kea must build the same one.
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
use JSON ();
use Test::More;
use XCAT::Test::File qw(repo_path);

BEGIN {
    $ENV{XCATROOT} = repo_path('xCAT-server');
    $ENV{XCATCFG}  = 'SQLite:' . tempdir( CLEANUP => 1 );
}

use xCAT::DHCP::Backend::Kea;
use xCAT::DHCP::BootPolicy;
require( repo_path('xCAT-server/lib/xcat/plugins/dhcp.pm') );

# A table returns only the columns the plugin asks for, like the real one.
{
    package DUIDTable;

    # %asked counts the node rows that each table is asked for, %scans the reads of a whole table.
    our ( %rows, @networks, %asked, %scans );
    sub new { my ( $class, $name ) = @_; return bless { name => $name }, $class; }
    sub getNodesAttribs {
        my ( $self, $nodes, $cols ) = @_;
        $asked{ $self->{name} } += @$nodes;
        my %out;
        for my $node (@$nodes) {
            my $row = $rows{ $self->{name} }{$node} or next;
            $out{$node} = [ { map { exists $row->{$_} ? ( $_ => $row->{$_} ) : () } @$cols } ];
        }
        return \%out;
    }
    sub getAllAttribs {
        my ( $self, @cols ) = @_;
        return @networks if $self->{name} eq 'networks';
        $scans{ $self->{name} }++;
        my $table = $rows{ $self->{name} } || {};
        return map { my $node = $_; { node => $node, map { ( $_ => $table->{$node}{$_} ) } grep { $_ ne 'node' } @cols } } sort keys %$table;
    }
    sub getAllNodeAttribs {
        my ($self) = @_;
        $scans{ $self->{name} }++;
        return () unless $self->{name} eq 'nodelist';
        my %nodes = map { %{ $_ || {} } } values %rows;
        return map { { node => $_ } } sort keys %nodes;
    }
    # The where clause of dhcp6_client_duids: the mac rows that set a duid.
    sub getAllAttribsWhere {
        my ($self) = @_;
        $scans{"$self->{name} where"}++;
        my $table = $rows{ $self->{name} } || {};
        return map { { node => $_, duid => $table->{$_}{duid} } } grep { defined( $table->{$_}{duid} ) && $table->{$_}{duid} ne '' } sort keys %$table;
    }
    sub getNodeAttribs { return; }
    sub getAttribs     { return { username => 'xcat_key', password => 'dGVzdA==' }; }
    sub close          { return; }

    package DUIDISCBackend;
    sub name { return 'isc'; }
}

my $uuid = '12345678-1234-4bcd-9876-1234567890ab';
my $firmware  = '00:04:78:56:34:12:34:12:cd:4b:98:76:12:34:56:78:90:ab';
my $canonical = '00:04:12:34:56:78:12:34:4b:cd:98:76:12:34:56:78:90:ab';
my $literal   = '00:01:00:01:2e:4f:61:a0:02:00:00:00:00:64';
# The nil UUID that nodeimport writes to vpd.uuid for every PowerKVM node it creates.
my $nil = '00000000-0000-0000-0000-000000000000';
# $uuid with its first three fields byte-swapped: what xCAT stored before vpd.uuid held the UUID
# that the operating system reports. A firmware-order DUID made from it is the canonical order of
# $uuid, which no client sends.
my $swapped = '78563412-3412-cd4b-9876-1234567890ab';
my $invalid   = "but only firmware, canonical, or a DUID of colon-separated hexadecimal octets is supported.";

# The node, its mac.duid, its vpd.uuid, and the DUID that its reservation must match: undef when the
# node has no DUID, and an error when mac.duid is not valid.
my @cases = (
    [ 'cn01', undef,          $uuid,                                    $firmware, 'no duid gives the firmware order' ],
    [ 'cn02', ' FIRMWARE ',   '12345678-1234-4bcd-9876-1234567890ac',   '00:04:78:56:34:12:34:12:cd:4b:98:76:12:34:56:78:90:ac', 'firmware in any case and spacing' ],
    [ 'cn03', 'canonical',    '12345678-1234-4bcd-9876-1234567890ad',   '00:04:12:34:56:78:12:34:4b:cd:98:76:12:34:56:78:90:ad', 'canonical gives the RFC 4122 order' ],
    [ 'cn04', '00:01:00:01:2E:4F:61:A0:02:00:00:00:00:64', undef,       $literal,  'a DUID is used as given, in lowercase, without vpd.uuid' ],
    [ 'cn05', 'not-a-duid',   '12345678-1234-4bcd-9876-1234567890af',   { error => "The duid attribute of cn05 is 'not-a-duid', $invalid" }, 'a word that is not a policy is refused' ],
    [ 'cn06', '00:01',        '12345678-1234-4bcd-9876-1234567890b0',   { error => "The duid attribute of cn06 is '00:01', $invalid" }, 'a DUID of two octets is refused' ],
    [ 'cn07', undef,          undef,                                    undef,     'no vpd.uuid gives no DUID' ],
    [ 'cn08', 'canonical',    'not-a-uuid',                             undef,     'a malformed vpd.uuid gives no DUID' ],
    [ 'cn09', undef,          $nil,                                     undef,     'the nil vpd.uuid gives no DUID' ],
    [ 'cn10', undef,          $swapped,                                 $canonical, 'a byte-swapped vpd.uuid still gives its DUID' ],
);
my %case = map { $_->[0] => $_ } @cases;
my @nodes = map { $_->[0] } @cases;
my %address = map { $nodes[$_] => sprintf( '2001:db8:176::%x', 0x21 + $_ ) } 0 .. $#nodes;
my %mac     = map { $nodes[$_] => sprintf( '02:00:00:00:01:%02x', 0x21 + $_ ) } 0 .. $#nodes;

sub node_rows {
    my (%duid) = @_;
    return (
        noderes => { map { $_ => { netboot => 'grub2', tftpserver => '2001:db8:176::1' } } @nodes },
        mac     => { map { $_ => { mac => $mac{$_}, ( defined $duid{$_} ? ( duid => $duid{$_} ) : () ) } } @nodes },
        vpd     => { map { $_ => ( defined $case{$_}[2] ? { uuid => $case{$_}[2] } : {} ) } @nodes },
    );
}
my %settings = map { $_->[0] => $_->[1] } @cases;

my ( @errors, @warnings );
# Names resolve from %resolve, as /etc/hosts would. Addresses go to the real getipaddr.
our %resolve = map { $_ => { 6 => $address{$_} } } @nodes;
our %mgtifname;
my $real_getipaddr = \&xCAT::NetworkUtils::getipaddr;
my $getipaddr = sub {
    shift if @_ && defined( $_[0] ) && $_[0] eq 'xCAT::NetworkUtils';
    my ( $host, %opt ) = @_;
    return $real_getipaddr->( $host, %opt ) unless defined($host) && $resolve{$host};
    my $entry = $resolve{$host};
    return $entry->{4} if $opt{OnlyV4};
    return $entry->{6} if $opt{OnlyV6};
    return $entry->{6} // $entry->{4};
};
no warnings 'redefine';
local *xCAT::Table::new = sub { return DUIDTable->new( $_[1] ); };
local *xCAT::TableUtils::get_site_attribute = sub { return; };
local *xCAT::MsgUtils::trace = sub { return; };
local *xCAT_plugin::dhcp::getipaddr = $getipaddr;
local *xCAT::NetworkUtils::getipaddr = $getipaddr;
local *xCAT_plugin::dhcp::ipIsDynamic = sub { return 0; };
local $xCAT_plugin::dhcp::callback = sub {
    my ($resp) = @_;
    push @errors,   @{ $resp->{error}   || [] };
    push @warnings, @{ $resp->{warning} || [] };
    foreach my $node ( @{ $resp->{node} || [] } ) {
        push @errors,   map { "$node->{name}[0]: $_" } @{ $node->{error}   || [] };
        push @warnings, map { "$node->{name}[0]: $_" } @{ $node->{warning} || [] };
    }
};
use warnings 'redefine';

my $backend = xCAT::DHCP::Backend::Kea->new();
sub empty_config {
    return JSON::decode_json( $backend->render_dhcp6_config(
            { interfaces => ['eth0'], subnets => [ { id => 1, subnet => '2001:db8:176::/64', interface => 'eth0' } ] } ) );
}

# The Kea DHCPv6 reservations of the nodes.
sub kea_reservations {
    my ( $config, @wanted ) = @_;
    @errors = @warnings = ();
    return xCAT_plugin::dhcp::kea_build_node_reservations6( $backend, $config, \@wanted );
}

# The DUID of each DHCPv6 host that makedhcp creates through OMAPI on ISC DHCP, from the omshell input.
my $dir = tempdir( CLEANUP => 1 );
my $conf = "$dir/dhcpd.conf";
open( my $fh, '>', $conf ) or die "Cannot create $conf: $!";
print {$fh} "#xCAT generated dhcp configuration\n",
  "option space gpxe;\n",
  @{ xCAT::DHCP::BootPolicy->isc_ipxe_feature_option_lines() },
  "subnet 192.0.2.0 netmask 255.255.255.0 {\n",
  "} # 192.0.2.0/255.255.255.0 subnet_end\n";
close($fh) or die "Cannot close $conf: $!";
sub isc_commands {
    my (@wanted) = @_;
    my @sessions;
    @errors = @warnings = ();
    no warnings 'redefine';
    local @DUIDTable::networks = ( { net => '2001:db8:176::', mask => '/64', mgtifname => 'eth0' } );
    local *xCAT::DHCP::Backend::new_backend = sub { return bless {}, 'DUIDISCBackend'; };
    local *xCAT::Utils::isServiceNode = sub { return 0; };
    local *xCAT::Utils::isLinux = sub { return 1; };
    local *xCAT::Utils::isFIPS = sub { return 0; };
    local *xCAT::Utils::checkservicestatus = sub { return 0; };
    local *xCAT::NetworkUtils::determinehostname = sub { return ('mn'); };
    local *xCAT::NetworkUtils::nodeonmynet = sub { return 1; };
    local *xCAT::DBobjUtils::getnodetype = sub { return {}; };
    local *xCAT::DBobjUtils::getNetwkInfo = sub { return map { $_ => { mgtifname => $main::mgtifname{$_} // 'eth0' } } @wanted; };
    local *xCAT_plugin::dhcp::addnic = sub { return; };
    local *xCAT_plugin::dhcp::addnet = sub { return; };
    local *xCAT_plugin::dhcp::addnet6 = sub { return; };
    local *xCAT_plugin::dhcp::writeout = sub { return; };
    local *xCAT_plugin::dhcp::_open_omshell_writer = sub {
        push @sessions, '';
        open( my $out, '>', \$sessions[-1] ) or die "Cannot open an omshell buffer: $!";
        return $out;
    };
    local *xCAT_plugin::dhcp::_close_omshell_writer = sub { close( $_[0] ); return; };
    local $::XCATSITEVALS{externaldhcpservers};
    local $xCAT_plugin::dhcp::dhcpconffile = $conf;
    local $xCAT_plugin::dhcp::distro = 'rhels9.4';
    use warnings 'redefine';

    open( my $printed, '>', \my $text ) or die "Cannot open an output buffer: $!";
    my $selected = select($printed);
    my $died;
    eval {
        xCAT_plugin::dhcp::process_request( { _xcatpreprocessed => [1], node => [@wanted], arg => [] },
            $xCAT_plugin::dhcp::callback );
        1;
    } or $died = $@;
    select($selected);
    die "makedhcp died: $died" if $died;
    return \@sessions;
}

# The DUID of the host that each create block of the DHCPv6 omshell session names.
sub isc_hosts {
    my ($session) = @_;
    my %duid;
    while ( $session =~ /^new host\nset name = "([^"]+)"\nset dhcp-client-identifier = (\S+)\n(?:.*\n)*?create\n/mg ) {
        $duid{$1} = $2;
    }
    return \%duid;
}

# ---- Each backend builds the DUID that mac.duid selects --------------------------------------------
{
    local %DUIDTable::rows = node_rows(%settings);
    my $config = empty_config();
    my %kea = map { $_->{hostname} => $_ } @{ kea_reservations( $config, @nodes ) };
    my @kea_errors = sort @errors;
    my $sessions = isc_commands(@nodes);
    # The ISC path also reports a missing /etc/sysconfig/dhcpd, which depends on the host.
    my @isc_errors = sort grep { /duid attribute/ } @errors;
    my @isc_warnings = @warnings;
    is( scalar(@$sessions), 2, 'ISC: makedhcp opens a DHCPv4 and a DHCPv6 omshell session' );
    my $isc = isc_hosts( $sessions->[1] // '' );

    my @refused = sort map { $_->[3]{error} } grep { ref( $_->[3] ) } @cases;
    is_deeply( \@kea_errors, \@refused, 'Kea: makedhcp reports each invalid duid attribute' );
    is_deeply( [ map { s/^\S+: //r } @isc_errors ], \@refused, 'ISC: makedhcp reports each invalid duid attribute' );

    foreach my $case (@cases) {
        my ( $node, undef, undef, $want, $label ) = @$case;
        if ( ref($want) ) {
            ok( !$kea{$node}, "Kea: $node has no DHCPv6 reservation: $label" );
            ok( !$isc->{$node}, "ISC: $node has no DHCPv6 host: $label" );
        } elsif ( defined($want) ) {
            is( $kea{$node}{duid}, $want, "Kea: $node reserves its address for the DUID: $label" );
            is( $isc->{$node}, $want, "ISC: $node reserves its address for the DUID: $label" );
            is_deeply( $kea{$node}{'ip-addresses'}, [ $address{$node} ], "Kea: $node keeps its address" );
        } else {
            is( $kea{$node}{'hw-address'}, $mac{$node}, "Kea: $node falls back to its MAC: $label" );
            ok( !exists( $kea{$node}{duid} ), "Kea: $node has no DUID: $label" );
            ok( !$isc->{$node}, "ISC: $node has no DHCPv6 host: $label" );
        }
    }
    is_deeply(
        [ grep { /^cn(?:0[789]|10): / } @isc_warnings ],
        [
            'cn07: Skipping DHCPv6 setup due to missing vpd.uuid information.',
            'cn08: Skipping DHCPv6 setup: vpd.uuid is not a UUID.',
            'cn09: Skipping DHCPv6 setup: vpd.uuid is the nil UUID, a placeholder that every node shares.',
            'cn10: vpd.uuid looks byte-swapped, so the DHCPv6 reservation may not match the client.'
              . ' Set vpd.uuid to the UUID that the node reports, or set the duid attribute.',
        ],
        'ISC: a node without a usable vpd.uuid is skipped with the reason, and a suspect order is reported'
    );

    # makedhcp -d and -q find a reservation by the DUID that makedhcp gave it, and by nothing else.
    foreach my $case (@cases) {
        my ( $node, undef, undef, $want ) = @$case;
        my @duids = map { $_->{duid} } grep { $_->{duid} }
          @{ xCAT_plugin::dhcp::kea_reservation_matches_for_nodes( [$node] ) };
        is_deeply( \@duids, [ ( defined($want) && !ref($want) ) ? $want : () ], "Kea: query and delete of $node match only its DUID" );
    }
}

# ---- A change of mac.duid replaces the reservation --------------------------------------------------
# nodeset runs makedhcp again for the node, so the next boot state gets the reservation of the new value.
{
    my $config = empty_config();
    local %DUIDTable::rows = node_rows();
    my $first = kea_reservations( $config, 'cn01' );
    $backend->upsert_reservations( $config, $first, [] );

    local %DUIDTable::rows = node_rows( cn01 => 'canonical' );
    my $second = kea_reservations( $config, 'cn01' );
    my @stale;
    $backend->upsert_reservations( $config, $second, \@stale );
    my @kept = @{ $config->{Dhcp6}{subnet6}[0]{reservations} };
    is( scalar(@kept), 1, 'Kea: a node keeps one reservation after its duid attribute changes' );
    is( $kept[0]{duid}, $canonical, 'Kea: the reservation matches the new DUID' );
    is_deeply( $kept[0]{'ip-addresses'}, [ $address{cn01} ], 'Kea: the reservation keeps the address' );
    is( $kept[0]{'option-data'}[0]{data}, 'tftp://[2001:db8:176::1]/boot/grub2/grub2-cn01', 'Kea: the reservation keeps the bootfile-url' );
    is_deeply( [ map { $_->{duid} } @stale ], [$firmware], 'Kea: the replaced reservation is the one of the old DUID' );

    my $session = isc_commands('cn01')->[1] // '';
    like( $session, qr/^new host\nset name = "cn01"\nopen\nremove\nclose\n/m, 'ISC: the host of the old DUID is removed by name' );
    is( isc_hosts($session)->{cn01}, $canonical, 'ISC: the new host matches the new DUID' );

    foreach my $match ( @{ xCAT_plugin::dhcp::kea_reservation_matches_for_nodes( ['cn01'] ) } ) {
        $backend->delete_reservations( $config, $match );
    }
    is_deeply( $config->{Dhcp6}{subnet6}[0]{reservations}, [], 'Kea: makedhcp -d removes the reservation of the new DUID' );
}

# ---- The other byte order of a node is not its identity ---------------------------------------------
# Two nodes with one vpd.uuid: cn01 keeps the firmware order, cn03 selects canonical. Each update and
# delete of cn03 must leave the reservation of cn01, which holds the firmware order of the same UUID.
{
    my $config = empty_config();
    local %DUIDTable::rows = node_rows( cn03 => 'canonical' );
    $DUIDTable::rows{vpd}{cn03} = { uuid => $uuid };
    $backend->upsert_reservations( $config, kea_reservations( $config, 'cn01', 'cn03' ), [] );
    my %duid = map { $_->{hostname} => $_->{duid} } @{ $config->{Dhcp6}{subnet6}[0]{reservations} };
    is_deeply( \%duid, { cn01 => $firmware, cn03 => $canonical }, 'Kea: one UUID in two byte orders gives two reservations' );

    $backend->upsert_reservations( $config, kea_reservations( $config, 'cn03' ), [] );
    foreach my $match ( @{ xCAT_plugin::dhcp::kea_reservation_matches_for_nodes( ['cn03'] ) } ) {
        $backend->delete_reservations( $config, $match );
    }
    is_deeply( [ map { [ $_->{hostname}, $_->{duid} ] } @{ $config->{Dhcp6}{subnet6}[0]{reservations} } ],
        [ [ 'cn01', $firmware ] ], 'Kea: updating and deleting cn03 leaves the reservation of cn01' );
    my $session = isc_commands('cn03')->[1] // '';
    is( isc_hosts($session)->{cn03}, $canonical, 'ISC: cn03 creates its host for the canonical order' );
    unlike( $session, qr/\Q$firmware\E/, 'ISC: cn03 removes no host by the firmware order of its UUID' );
}

# ---- Two nodes with one DUID behave like two nodes with one MAC -------------------------------------
# The database is authoritative: makedhcp gives an identifier to the node that it updates and removes
# what another node held under it, for a DUID as for a MAC. cn03 is given the DUID of cn01, and two
# IPv4 nodes share a MAC in the same way.
{
    package DUIDParityV4Backend;
    sub subnet_id_for_ip { return 1; }
}
{
    my $hostnames = sub { [ map { $_->{hostname} } map { @{ $_->{reservations} || [] } } @{ $_[0]{ $_[1] }{ $_[2] } } ] };

    # The DUID: cn01 holds it, then cn03 is given it.
    local %DUIDTable::rows = node_rows();
    my $v6 = empty_config();
    $backend->upsert_reservations( $v6, kea_reservations( $v6, 'cn01' ), [] );
    $DUIDTable::rows{mac}{cn03}{duid} = $firmware;
    my $v6_deleted = JSON::decode_json( JSON::encode_json($v6) );
    $backend->delete_reservations( $v6_deleted, $_ ) for @{ xCAT_plugin::dhcp::kea_reservation_matches_for_nodes( ['cn03'] ) };
    $backend->upsert_reservations( $v6, kea_reservations( $v6, 'cn03' ), [] );
    my $v6_session = isc_commands('cn03')->[1] // '';

    # The MAC: v4a holds it, then v4b is given it.
    my $mac = '02:00:00:00:06:01';
    local %main::resolve = ( v4a => { 4 => '192.0.2.61' }, v4b => { 4 => '192.0.2.62' } );
    local %DUIDTable::rows = (
        noderes => { map { $_ => { netboot => 'xnba', tftpserver => '192.0.2.1' } } qw(v4a v4b) },
        mac     => { v4a => { mac => $mac }, v4b => { mac => '02:00:00:00:06:02' } },
    );
    my $v4 = JSON::decode_json( $backend->render_dhcp4_config( { interfaces => ['eth0'], subnets => [ { id => 1, subnet => '192.0.2.0/24' } ] } ) );
    $backend->upsert_reservations( $v4, xCAT_plugin::dhcp::kea_build_node_reservations( bless( {}, 'DUIDParityV4Backend' ), $v4, ['v4a'] ), [] );
    $DUIDTable::rows{mac}{v4b}{mac} = $mac;
    my $v4_deleted = JSON::decode_json( JSON::encode_json($v4) );
    $backend->delete_reservations( $v4_deleted, $_ ) for @{ xCAT_plugin::dhcp::kea_reservation_matches_for_nodes( ['v4b'] ) };
    $backend->upsert_reservations( $v4, xCAT_plugin::dhcp::kea_build_node_reservations( bless( {}, 'DUIDParityV4Backend' ), $v4, ['v4b'] ), [] );
    my $v4_session = isc_commands('v4b')->[0] // '';

    is_deeply( $hostnames->( $v6, 'Dhcp6', 'subnet6' ), ['cn03'], 'Kea: the node given a shared DUID takes the reservation' );
    is_deeply( $hostnames->( $v4, 'Dhcp4', 'subnet4' ), ['v4b'], 'Kea: as the node given a shared MAC does' );
    is_deeply( $hostnames->( $v6_deleted, 'Dhcp6', 'subnet6' ), [], 'Kea: makedhcp -d of the node given a shared DUID removes the reservation' );
    is_deeply( $hostnames->( $v4_deleted, 'Dhcp4', 'subnet4' ), [], 'Kea: as makedhcp -d of the node given a shared MAC does' );
    like( $v6_session, qr/^new host\nset dhcp-client-identifier = \Q$firmware\E\nopen\nremove\nclose\n/m,
        'ISC: the node given a shared DUID removes the host that holds it' );
    like( $v4_session, qr/^new host\nset hardware-address = \Q$mac\E\nopen\nremove\nclose\n/m,
        'ISC: as the node given a shared MAC does' );
}

# ---- An IPv6 node and an IPv4-only node with one vpd.uuid -------------------------------------------
# The IPv4-only node needs no DHCPv6 reservation, so the IPv6 node keeps its reservation as before the
# duid attribute existed.
{
    my $config = empty_config();
    local %main::resolve = ( %main::resolve, v4twin => { 4 => '192.0.2.21' } );
    local %DUIDTable::rows = node_rows();
    $DUIDTable::rows{vpd}{v4twin}     = { uuid => $uuid };
    $DUIDTable::rows{mac}{v4twin}     = { mac  => '02:00:00:00:04:21' };
    $DUIDTable::rows{noderes}{v4twin} = { netboot => 'grub2', tftpserver => '2001:db8:176::1' };
    my $reservations = kea_reservations( $config, 'cn01' );
    is_deeply( [@errors], [], 'Kea: an IPv6 node that shares its vpd.uuid with an IPv4-only node is no error' );
    is( ( $reservations->[0] || {} )->{duid}, $firmware, 'Kea: the IPv6 node keeps its reservation' );
    my $session = isc_commands('cn01')->[1] // '';
    is_deeply( [ grep { /DUID/ } @errors ], [], 'ISC: an IPv6 node that shares its vpd.uuid with an IPv4-only node is no error' );
    is( isc_hosts($session)->{cn01}, $firmware, 'ISC: the IPv6 node keeps its host' );
}

# ---- The DUID lookup reads the requested nodes, not every node --------------------------------------
# Discovery runs makedhcp once for each node it finds, so a lookup that read every node would make the
# discovery of N nodes read N times N rows.
{
    my @cluster = map { sprintf( 'cl%04d', $_ ) } 1 .. 1000;
    local %DUIDTable::rows = (
        mac => { map { $_ => { mac => '02:00:00:00:05:01', duid => 'canonical' } } @cluster },
        vpd => { map { $_ => { uuid => sprintf( '12345678-1234-4bcd-9876-%012d', substr( $_, 2 ) ) } } @cluster },
    );
    local %DUIDTable::asked = ();
    local %DUIDTable::scans = ();
    xCAT_plugin::dhcp::dhcp6_client_duids( [$_] ) for @cluster[ 0 .. 9 ];
    is( ( $DUIDTable::asked{mac} // 0 ) + ( $DUIDTable::asked{vpd} // 0 ), 20,
        'ten single-node requests in a cluster of 1000 nodes read the rows of those ten nodes only' );
    is_deeply( \%DUIDTable::scans, {}, 'and read no table in full' );
}

# ---- DHCPv4 and IPoIB identities do not depend on mac.duid ------------------------------------------
# The two IPv4-only nodes share one UUID, and the DHCPv6 subnet makes makedhcp build their DHCPv6 state
# too. Without an IPv6 address they need no DHCPv6 reservation, so no DUID of theirs fails the request.
{
    my %v4 = ( cn11 => '02:00:00:00:02:11', cn12 => 'b8:3f:d2:4a:68:aa' );
    my $v4_identity = sub {
        my ($duid) = @_;
        local %main::resolve   = ( cn11 => { 4 => '192.0.2.11' }, cn12 => { 4 => '192.0.2.12' } );
        local %main::mgtifname = ( cn12 => 'ib0' );
        local %DUIDTable::rows = (
            noderes => { map { $_ => { netboot => 'xnba', tftpserver => '192.0.2.1' } } keys %v4 },
            mac     => { map { $_ => { mac => $v4{$_}, ( defined $duid ? ( duid => $duid ) : () ) } } keys %v4 },
            vpd     => { map { $_ => { uuid => $uuid } } keys %v4 },
        );
        @errors = ();
        my $kea  = xCAT_plugin::dhcp::kea_build_node_reservations( bless( {}, 'DUIDV4Backend' ), {}, [ sort keys %v4 ] );
        my $kea6 = xCAT_plugin::dhcp::kea_build_node_reservations6( $backend, empty_config(), [ sort keys %v4 ] );
        my @kea_errors = @errors;
        my $sessions = isc_commands( sort keys %v4 );
        return { kea => $kea, kea6 => $kea6, kea_errors => \@kea_errors, isc => $sessions->[0],
            isc_errors => [ grep { /duid|DUID/ } @errors ] };
    };
    {
        package DUIDV4Backend;
        sub subnet_id_for_ip { return 1; }
    }
    my $without = $v4_identity->(undef);
    like( $without->{isc}, qr/set dhcp-client-identifier = b8:3f:d2:03:00:4a:68:aa\n/, 'ISC: the IPoIB node has its derived DHCPv4 client identifier' );
    is( scalar( @{ $without->{kea} } ), 2, 'Kea: both nodes have a DHCPv4 reservation' );
    foreach my $duid ( undef, 'canonical', $literal, 'not-a-duid' ) {
        my $with  = $v4_identity->($duid);
        my $label = defined($duid) ? "duid=$duid" : 'no duid';
        is_deeply( $with->{kea}, $without->{kea}, "Kea: $label leaves the DHCPv4 reservations unchanged" );
        is( $with->{isc}, $without->{isc}, "ISC: $label leaves the DHCPv4 and IPoIB hosts unchanged" );
        is_deeply( [ @{ $with->{kea6} }, @{ $with->{kea_errors} } ], [], "Kea: $label gives IPv4-only nodes no DHCPv6 reservation and no error" );
        is_deeply( $with->{isc_errors}, [], "ISC: $label is no error for IPv4-only nodes" );
    }
}

# ---- The nil vpd.uuid is a placeholder, not an identity ---------------------------------------------
# nodeimport writes '00000000-0000-0000-0000-000000000000' to vpd.uuid for every PowerKVM node, which
# is 32 valid hexadecimal digits. One DUID made from it would cover every such node, and each
# reservation would replace the one before it with nothing said.
{
    is( xCAT_plugin::dhcp::kea_duid_from_uuid( $nil, 'firmware' ), undef, 'the nil UUID gives no firmware-order DUID' );
    is( xCAT_plugin::dhcp::kea_duid_from_uuid($nil), undef, 'the nil UUID gives no canonical DUID' );
    is( xCAT_plugin::dhcp::kea_duid_from_uuid( '00000000-0000-0000-0000-000000000001', 'firmware' ),
        '00:04:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:01',
        'a UUID that differs from the nil UUID in one digit keeps its DUID' );
    is( xCAT_plugin::dhcp::kea_duid_from_uuid( 'ffffffff-ffff-ffff-ffff-ffffffffffff', 'firmware' ),
        '00:04:ff:ff:ff:ff:ff:ff:ff:ff:ff:ff:ff:ff:ff:ff:ff:ff',
        'an all-f vpd.uuid keeps its DUID: nothing in xCAT writes that value' );

    # Two PowerKVM nodes as nodeimport leaves them.
    my $config = empty_config();
    local %DUIDTable::rows = node_rows();
    $DUIDTable::rows{vpd}{$_} = { uuid => $nil } for qw(cn01 cn03);
    my $reservations = kea_reservations( $config, 'cn01', 'cn03' );
    my @kea_warnings = @warnings;
    $backend->upsert_reservations( $config, $reservations, [] );
    my @kept = sort { $a->{hostname} cmp $b->{hostname} } @{ $config->{Dhcp6}{subnet6}[0]{reservations} };
    is_deeply( [ map { $_->{hostname} } @kept ], [ 'cn01', 'cn03' ],
        'Kea: two nodes with the nil vpd.uuid keep one reservation each' );
    is_deeply( [ map { $_->{duid} } @kept ], [ undef, undef ], 'Kea: neither reservation is keyed on a DUID' );
    is_deeply( [ map { $_->{'hw-address'} } @kept ], [ $mac{cn01}, $mac{cn03} ],
        'Kea: each falls back to its own MAC, as a node with no vpd.uuid does' );
    is_deeply( [ map { $_->{'ip-addresses'}[0] } @kept ], [ $address{cn01}, $address{cn03} ],
        'Kea: each keeps its own address' );
    is_deeply( [ grep { /byte-swapped/ } @kea_warnings ], [],
        'Kea: the nil UUID is not reported as a byte order problem' );

    # makedhcp -q and -d of one of them must not find the other.
    my @matches = @{ xCAT_plugin::dhcp::kea_reservation_matches_for_nodes( ['cn01'] ) };
    is_deeply( [ map { $_->{duid} } grep { $_->{duid} } @matches ], [],
        'Kea: query and delete of cn01 match no DUID' );
    $backend->delete_reservations( $config, $_ ) for @matches;
    is_deeply( [ map { $_->{hostname} } @{ $config->{Dhcp6}{subnet6}[0]{reservations} } ], ['cn03'],
        'Kea: makedhcp -d of cn01 leaves the reservation of cn03' );

    my $session = isc_commands( 'cn01', 'cn03' )->[1] // '';
    is_deeply( isc_hosts($session), {}, 'ISC: neither node gets a DHCPv6 host' );
    is_deeply(
        [@warnings],
        [
            'cn01: Skipping DHCPv6 setup: vpd.uuid is the nil UUID, a placeholder that every node shares.',
            'cn03: Skipping DHCPv6 setup: vpd.uuid is the nil UUID, a placeholder that every node shares.',
        ],
        'ISC: each node is skipped with the nil UUID named as the reason'
    );
}

# ---- A vpd.uuid in the old byte order is reported, never rewritten ----------------------------------
# Before this work xCAT stored vpd.uuid with its first three fields swapped. Nothing can tell which
# spelling a given row holds, so makedhcp reports the rows whose version field sits where a swap puts
# it and leaves the value alone.
{
    my $swapped_note = 'vpd.uuid looks byte-swapped, so the DHCPv6 reservation may not match the client.'
      . ' Set vpd.uuid to the UUID that the node reports, or set the duid attribute.';

    is( xCAT_plugin::dhcp::dhcp6_uuid_looks_byte_swapped($swapped), 1, 'the swapped spelling of a version 4 UUID is detected' );
    is( xCAT_plugin::dhcp::dhcp6_uuid_looks_byte_swapped($uuid), 0, 'the UUID that the operating system reports is not' );
    is( xCAT_plugin::dhcp::dhcp6_uuid_looks_byte_swapped($nil), 0, 'the nil UUID is not' );
    is( xCAT_plugin::dhcp::dhcp6_uuid_looks_byte_swapped('not-a-uuid'), 0, 'a value that is not a UUID is not' );
    # What the check cannot know: a swap leaves a valid version in the first position about half the
    # time. '78563412-3412-2d4b-...' is the swapped spelling of '12345678-1234-4b2d-...' and reads
    # like a version 2 UUID, so the row is missed.
    is( xCAT_plugin::dhcp::dhcp6_uuid_looks_byte_swapped('78563412-3412-2d4b-9876-1234567890ab'), 0,
        'and a swap that leaves a valid version in the first position is missed' );

    # The harm the warning names: the firmware order of the swapped spelling is the canonical order of
    # the UUID that the node reports, which no client sends.
    is( xCAT_plugin::dhcp::kea_duid_from_uuid( $swapped, 'firmware' ), $canonical,
        'the firmware order of the swapped spelling is the canonical order of the real UUID' );
    is( $canonical, '00:04:12:34:56:78:12:34:4b:cd:98:76:12:34:56:78:90:ab', 'which is this DUID' );
    # The remedy the warning gives: duid=canonical sends the stored bytes in RFC 4122 order, which is
    # the DUID that EDK2 firmware builds from the real UUID.
    is( xCAT_plugin::dhcp::kea_duid_from_uuid($swapped), $firmware,
        'and duid=canonical on the swapped spelling gives the DUID that the firmware sends' );
    is( $firmware, '00:04:78:56:34:12:34:12:cd:4b:98:76:12:34:56:78:90:ab', 'which is this DUID' );

    # Each backend reports the node once, and still writes the reservation.
    my $config = empty_config();
    local %DUIDTable::rows = node_rows();
    $DUIDTable::rows{vpd}{cn01} = { uuid => $swapped };
    $DUIDTable::rows{mac}{cn01}{mac} = "$mac{cn01}|02:00:00:00:01:99!cn01-eth1";
    local %main::resolve = ( %main::resolve, 'cn01-eth1' => { 6 => '2001:db8:176::31' } );
    my $reservations = kea_reservations( $config, 'cn01' );
    is_deeply( [@warnings], ["cn01: $swapped_note"], 'Kea: the node is reported once, not once for each of its NICs' );
    is_deeply( [ map { $_->{duid} } @$reservations ], [ $canonical, $canonical ],
        'Kea: the reservation is still written with the DUID the stored value gives' );

    my $session = isc_commands('cn01')->[1] // '';
    is_deeply( [@warnings], ["cn01: $swapped_note"], 'ISC: the node is reported with the same text' );
    is( isc_hosts($session)->{cn01}, $canonical, 'ISC: the host is still created' );

    # A literal mac.duid does not read vpd.uuid, so there is nothing to report.
    $DUIDTable::rows{mac}{cn01}{duid} = $literal;
    kea_reservations( $config, 'cn01' );
    is_deeply( [ grep { /byte-swapped/ } @warnings ], [], 'Kea: a node whose duid attribute is a DUID is not reported' );
}

done_testing();
