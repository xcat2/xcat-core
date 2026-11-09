#!/usr/bin/env perl
# The DHCPv6 client identifier that makedhcp reserves the IPv6 address of a node for. mac.duid selects
# it: firmware (the default) is the DUID-UUID that EDK2 firmware sends, canonical is vpd.uuid in RFC 4122
# byte order, ll is the DUID-LL built from the MAC, and any other value is the DUID itself. ISC DHCP and
# Kea must build the same one.
#
# A ppc64le node takes the DUID-LL with no attribute set, because SLOF sends one and sends no UUID at
# all, so a DUID-UUID reservation can never match it.
use strict;
use warnings;
## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Basename qw(dirname);
use File::Path qw(make_path);
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

    # The IPv4 reservations are rendered to prove that nothing on that path changed, so the
    # subnet of an address is answered without a configuration to look it up in.
    package DUIDKeaV4Backend;
    sub subnet_id_for_ip { return 1; }
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
my $invalid   = "but only firmware, canonical, ll, or a DUID of colon-separated hexadecimal octets is supported.";
# The DUID-LL that SLOF and the ieee1275 grub2 both build from the MAC of the node: DUID type 3 and
# hardware type 1, then the address. The MACs are asserted below, so these values are checkable.
my $ll_cn11 = '00:03:00:01:02:00:00:00:01:2b';
my $ll_cn13 = '00:03:00:01:02:00:00:00:01:2d';
my $ll_cn14 = '00:03:00:01:02:00:00:00:01:2e';
my $ll_cn15 = '00:03:00:01:02:00:00:00:01:2f';

# The node, its mac.duid, its vpd.uuid, the DUID that its reservation must match, a label, and the
# nodetype.arch of the node. The DUID is undef when the node has no DUID, and an error when mac.duid is
# not valid. The arch defaults to x86_64.
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
    # SLOF sends 00:03:00:01:<mac> and never a UUID, so a DUID-UUID reservation cannot match a
    # ppc64le node and it was never offered a boot file.
    [ 'cn11', undef,          $uuid,                                    $ll_cn11,  'a ppc64le node takes the DUID-LL its firmware sends', 'ppc64le' ],
    [ 'cn12', 'firmware',     '12345678-1234-4bcd-9876-1234567890b1',   '00:04:78:56:34:12:34:12:cd:4b:98:76:12:34:56:78:90:b1', 'an explicit firmware order is still honoured on ppc64le', 'ppc64le' ],
    [ 'cn13', 'll',           $uuid,                                    $ll_cn13,  'll selects the DUID-LL whatever the architecture' ],
    # A DUID-LL needs no UUID, which is the whole point: vpd.uuid is not read at all.
    [ 'cn14', undef,          undef,                                    $ll_cn14,  'a ppc64le node with no vpd.uuid still gets a DUID', 'ppc64le' ],
    [ 'cn15', undef,          $nil,                                     $ll_cn15,  'and the nil vpd.uuid does not stop one either', 'ppc64le' ],
);
my %case = map { $_->[0] => $_ } @cases;
my @nodes = map { $_->[0] } @cases;
my %address = map { $nodes[$_] => sprintf( '2001:db8:176::%x', 0x21 + $_ ) } 0 .. $#nodes;
my %mac     = map { $nodes[$_] => sprintf( '02:00:00:00:01:%02x', 0x21 + $_ ) } 0 .. $#nodes;
# The DUID-LL cases above name the identifier in full, so the MAC each one is built from is asserted
# rather than derived twice.
is( $mac{cn11}, '02:00:00:00:01:2b', 'the MAC that the first DUID-LL case is built from' );
is( $mac{cn13}, '02:00:00:00:01:2d', 'the MAC that the explicit-ll case is built from' );
is( $mac{cn14}, '02:00:00:00:01:2e', 'the MAC that the no-uuid case is built from' );
is( $mac{cn15}, '02:00:00:00:01:2f', 'the MAC that the nil-uuid case is built from' );

our %mgt_of;

sub node_rows {
    my (%duid) = @_;
    return (
        noderes => { map { $_ => { netboot => 'grub2', tftpserver => '2001:db8:176::1' } } @nodes },
        mac     => { map { $_ => { mac => $mac{$_}, ( defined $duid{$_} ? ( duid => $duid{$_} ) : () ) } } @nodes },
        vpd     => { map { $_ => ( defined $case{$_}[2] ? { uuid => $case{$_}[2] } : {} ) } @nodes },
        # The architecture decides which identifier the firmware of the node sends.
        nodetype => { map { $_ => { arch => ( $case{$_}[5] || 'x86_64' ) } } @nodes },
        # mgt says whether xCAT defines the domain of the node, which decides the byte order its
        # firmware reads back out of SMBIOS.
        nodehm => { map { $_ => { mgt => ( $mgt_of{$_} || '' ) } } @nodes },
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
# dhcpinterfaces decides which interfaces makedhcp answers on, and the router
# advertisements follow the same selection. Without it the set is discovered from the
# interfaces of the host the suite runs on, and the branch under test would be whichever
# those happen to be.
our $dhcpinterfaces = 'eth0';
# The interface of the IPv6 network under test. isc_commands localizes the networks
# table itself, so a caller cannot override it from outside.
our $ra_mgtifname = 'eth0';
# Whether radvd is reported running. A start that failed leaves the configuration
# already correct, so the service has to be examined on every call.
our $radvd_running = 1;
local *xCAT::TableUtils::get_site_attribute = sub {
    my ($class, $attribute) = @_;
    $attribute = $class unless defined($attribute);
    return $dhcpinterfaces if $attribute eq 'dhcpinterfaces';
    return;
};
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
# The two per-node client classes of a chainloading node, keyed by the URL each one serves.
# A chainloading node is answered by these and not by its reservation: Kea gives a reservation's
# option data precedence over a class's, so one URL in the reservation would answer both boot
# stages with it.
sub boot_classes6 {
    my (@nodes) = @_;
    my %by_url;
    foreach my $class ( @{ xCAT_plugin::dhcp::kea_node_boot_classes6_for_nodes( \@nodes ) } ) {
        foreach my $option ( @{ $class->{'option-data'} || [] } ) {
            $by_url{ $option->{data} } = $class if ( $option->{name} || '' ) eq 'bootfile-url';
        }
    }
    return \%by_url;
}

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
our @restarted;
our @forwarded;
# The OS that makedhcp believes it runs on. Without this the sysconfig decisions follow the
# host the suite runs on, and the branch under test is whichever that host happens to take.
our $osver = 'rhels9.4';

sub isc_commands {
    my (@wanted) = @_;
    my @sessions;
    @errors = @warnings = ();
    @restarted = @forwarded = ();
    no warnings 'redefine';
    # Without this the test restarts the dhcp services of the host it runs on.
    local *xCAT::Utils::restartservice = sub {
        shift if @_ && defined( $_[0] ) && $_[0] eq 'xCAT::Utils';
        push @restarted, $_[0];
        return 0;
    };
    local @DUIDTable::networks = ( { net => '2001:db8:176::', mask => '/64', mgtifname => $ra_mgtifname } );
    local *xCAT::DHCP::Backend::new_backend = sub { return bless {}, 'DUIDISCBackend'; };
    local *xCAT::Utils::osver = sub { return $osver; };
    local *xCAT::Utils::isServiceNode = sub { return 0; };
    local *xCAT::Utils::isLinux = sub { return 1; };
    local *xCAT::Utils::isFIPS = sub { return 0; };
    local *xCAT::Utils::checkservicestatus = sub {
        return $radvd_running ? 0 : 3;
    };
    local *xCAT::Utils::enableservice = sub { return 0; };
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
    # Without these two the test writes the host's /etc/radvd.conf and sets its sysctls.
    local $xCAT_plugin::dhcp::radvdconffile = "$dir/radvd.conf";
    local *xCAT_plugin::dhcp::enable_ipv6_forwarding = sub {
        push @forwarded, $_[0];
        return;
    };
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

# ---- RFC 5970 option 59: both backends deliver the same boot file URL -----------------------
# Without option 59 the firmware takes the reserved address and has nothing to load, so it
# releases the address and solicits again. dhcp6_bootfile_url_for_node is the one place the URL
# is built, and both backends call it, so the two must agree.
{
    local %DUIDTable::rows = node_rows(%settings);
    # cn07 asks for xnba, which does not read option 59, so it must get none.
    $DUIDTable::rows{noderes}{cn07} = { netboot => 'xnba', tftpserver => '2001:db8:176::1' };

    my $config = empty_config();
    my %kea = map { $_->{hostname} => $_ } @{ kea_reservations( $config, 'cn01', 'cn07' ) };
    my $sessions = isc_commands( 'cn01', 'cn07' );
    my $isc6 = $sessions->[1] // '';

    my ($kea_opt) = grep { $_->{name} eq 'bootfile-url' } @{ $kea{cn01}{'option-data'} || [] };
    my $kea_url = $kea_opt && $kea_opt->{data};
    my ($isc_url) = $isc6 =~ /option dhcp6\.bootfile-url \\"([^\\]+)\\"/;

    like( $kea_url, qr{^tftp://\[2001:db8:176::1\]/boot/grub2/},
        'Kea: the grub2 node gets a bootfile-url from the bracketed IPv6 server' );
    is( $isc_url, $kea_url,
        'ISC and Kea deliver the same bootfile-url for the same node' );
    ok( $kea_opt && $kea_opt->{'always-send'},
        'Kea sends the bootfile-url even when the client does not ask for it' );

    my ($kea_none) = grep { $_->{name} eq 'bootfile-url' } @{ $kea{cn07}{'option-data'} || [] };
    is( $kea_none, undef, 'Kea: an xnba node gets no bootfile-url' );
    unlike( $isc6, qr/set name = "cn07"\n(?:[^\n]*\n)*?option dhcp6\.bootfile-url/,
        'ISC: an xnba node gets no bootfile-url' );
}

# ---- An ipxe node gets the UEFI loader over DHCPv6 -------------------------------------------
# The firmware that solicits over DHCPv6 is UEFI, and the iPXE build xCAT ships reports dhcpv6
# and ipv6 where the xnba loader does not. Without option 59 such a node takes the reserved
# address and has nothing to load.
{
    local %DUIDTable::rows = node_rows(%settings);

    my $present = tempdir( CLEANUP => 1 );
    my $loader  = 'xcat/ipxe/x86_64-sb/snponly-shim.efi';
    make_path( dirname("$present/$loader") );
    open( my $fh, '>', "$present/$loader" ) or die "cannot write the loader: $!";
    print {$fh} "loader\n";
    close($fh);
    my $absent = tempdir( CLEANUP => 1 );

    $DUIDTable::rows{noderes}{cn02} =
      { netboot => 'ipxe', tftpserver => '2001:db8:176::1', tftpdir => $present };
    # cn01 and cn02 both take the firmware order, so the reservation that holds the address is
    # the one the firmware matches and the shim is the boot file under test. cn03 takes the
    # canonical order, which is the order iPXE sends, so its first reservation carries the boot
    # script instead -- the ordering case below.
    $DUIDTable::rows{noderes}{cn01} =
      { netboot => 'ipxe', tftpserver => '2001:db8:176::1', tftpdir => $absent };

    my $config = empty_config();
    # The second reservation of a chainloading node carries no hostname, so it is not keyed here.
    my %kea = map { $_->{hostname} => $_ }
      grep { defined $_->{hostname} } @{ kea_reservations( $config, 'cn02', 'cn01' ) };

    my ($with) = grep { $_->{name} eq 'bootfile-url' } @{ $kea{cn02}{'option-data'} || [] };
    is( $with, undef, 'the reservation of an ipxe node names no boot file' );
    my $cn02_classes = boot_classes6('cn02');
    ok( $cn02_classes->{"tftp://[2001:db8:176::1]/$loader"},
        'an ipxe node gets the UEFI loader from the bracketed IPv6 server, through its class' );

    # Naming a file the TFTP server does not have costs the client a timeout it cannot
    # diagnose, so no option is better than a wrong one. The node gets no class at all rather
    # than a class naming a file that is not there.
    is_deeply( xCAT_plugin::dhcp::kea_node_boot_classes6_for_nodes( ['cn01'] ), [],
        'an ipxe node whose loader is not on disk gets no boot class' );

    # BUT IT MUST NOT BE SILENT. makedhcp exits 0 either way, so a node with no boot file and no
    # warning reaches a firmware timeout and no log on the management node says why. The warning
    # names the path that was looked for, because the node carries its own noderes.tftpdir and
    # the reader cannot derive it from the site value.
    my @loader = grep { /snponly-shim\.efi/ } @warnings;
    is( scalar @loader, 1, 'the absent loader is reported exactly once for the node' );
    like( $loader[0], qr/\Qcn01:\E/, 'the warning is attributed to the node' );
    like( $loader[0], qr{\Q$absent/$loader\E},
        'and names the full path that was looked for, which is the node tftpdir and not the site one' );
    is( scalar( grep { /\Q$present\E/ } @warnings ), 0,
        'and the node whose loader IS on disk is not reported' );
}

# ---- Each backend builds the DUID that mac.duid selects --------------------------------------------
{
    local %DUIDTable::rows = node_rows(%settings);
    my $config = empty_config();
    # A client that holds no address carries no hostname, so the reservation of each node is the
    # one keyed here.
    my %kea = map { $_->{hostname} => $_ }
      grep { defined $_->{hostname} } @{ kea_reservations( $config, @nodes ) };
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

    # makedhcp -d and -q find a reservation by the DUIDs that makedhcp gave it, and by nothing
    # else. A DUID-UUID says the node reports a UUID, so the Genesis image is a client of its own
    # there and the DUID-LL it sends was reserved beside the UUID.
    foreach my $case (@cases) {
        my ( $node, undef, undef, $want ) = @$case;
        my @duids = map { $_->{duid} } grep { $_->{duid} }
          @{ xCAT_plugin::dhcp::kea_reservation_matches_for_nodes( [$node] ) };
        my @expected = ( defined($want) && !ref($want) ) ? ($want) : ();
        push @expected, '00:03:00:01:' . $mac{$node} if @expected && $want =~ /\A00:04:/;
        is_deeply( \@duids, \@expected, "Kea: query and delete of $node match the DUIDs it reserved" );
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
    is( scalar(@kept), 2, 'Kea: a node keeps one reservation for each of its clients after its duid attribute changes' );
    is( $kept[0]{duid}, $canonical, 'Kea: the reservation matches the new DUID' );
    is_deeply( $kept[0]{'ip-addresses'}, [ $address{cn01} ], 'Kea: the reservation keeps the address' );
    is( $kept[0]{'option-data'}[0]{data}, 'tftp://[2001:db8:176::1]/boot/grub2/grub2-cn01', 'Kea: the reservation keeps the bootfile-url' );
    # The DUID-LL is not built from vpd.uuid, so it is rewritten unchanged. The entry of the old
    # UUID order is the one that goes.
    is_deeply( [ map { $_->{duid} } @stale ], [ $firmware, '00:03:00:01:' . $mac{cn01} ],
        'Kea: the replaced reservation is the one of the old DUID' );

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
    # The clients that hold no address carry no hostname, so the addressed reservations are the
    # ones keyed here.
    my %duid = map { $_->{hostname} => $_->{duid} }
      grep { defined $_->{hostname} } @{ $config->{Dhcp6}{subnet6}[0]{reservations} };
    is_deeply( \%duid, { cn01 => $firmware, cn03 => $canonical }, 'Kea: one UUID in two byte orders gives two reservations' );

    $backend->upsert_reservations( $config, kea_reservations( $config, 'cn03' ), [] );
    foreach my $match ( @{ xCAT_plugin::dhcp::kea_reservation_matches_for_nodes( ['cn03'] ) } ) {
        $backend->delete_reservations( $config, $match );
    }
    is_deeply( [ map { [ $_->{hostname}, $_->{duid} ] }
          grep { defined $_->{hostname} } @{ $config->{Dhcp6}{subnet6}[0]{reservations} } ],
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
    # The reservation that holds the address is the one with a hostname, and it is the one a
    # shared identifier moves from node to node.
    my $hostnames = sub { [ grep { defined } map { $_->{hostname} } map { @{ $_->{reservations} || [] } } @{ $_[0]{ $_[1] }{ $_[2] } } ] };

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
    # Each NIC keeps an address of its own. The Genesis client holds none, and it is identified
    # by a DUID of the node, so one entry answers it for both NICs.
    is_deeply( [ map { $_->{duid} } @$reservations ],
        [ $canonical, '00:03:00:01:' . $mac{cn01}, $canonical ],
        'Kea: the reservation is still written with the DUID the stored value gives' );

    my $session = isc_commands('cn01')->[1] // '';
    is_deeply( [@warnings], ["cn01: $swapped_note"], 'ISC: the node is reported with the same text' );
    is( isc_hosts($session)->{cn01}, $canonical, 'ISC: the host is still created' );

    # A duid attribute of any kind is the decision the warning asks for, so none of the three
    # values is reported. Before this, firmware and canonical were reported and the remedy the
    # text names could not silence it.
    foreach my $choice ( $literal, 'firmware', 'canonical' ) {
        @warnings = ();
        $DUIDTable::rows{mac}{cn01}{duid} = $choice;
        kea_reservations( $config, 'cn01' );
        is_deeply( [ grep { /byte-swapped/ } @warnings ], [],
            "Kea: a node with duid=$choice is not reported" );
    }

    # And the default still reports it, so the three above are not passing for want of a warning.
    @warnings = ();
    delete $DUIDTable::rows{mac}{cn01}{duid};
    kea_reservations( $config, 'cn01' );
    is_deeply( [ grep { /byte-swapped/ } @warnings ], ["cn01: $swapped_note"],
        'Kea: a node with no duid attribute is still reported' );
}

# ---- The DHCPv6 reservation names the boot file (RFC 5970 option 59) ------------------------------
# Without the option the firmware takes the reserved address and has nothing to load. EDK2 then
# reports "PXE-E21: Remote boot cancelled" and falls through to the next boot entry, which reads
# like a DHCP failure although the address was granted.
{
    local %DUIDTable::rows = node_rows(%settings);
    my $sessions = isc_commands(@nodes);
    my $v6       = $sessions->[1] // '';

    my @urls  = $v6 =~ m{dhcp6\.bootfile-url\s*\\?"?(tftp:[^"\\;]+)}g;
    my @hosts = sort keys %{ isc_hosts($v6) };
    diag( "hosts created: " . scalar(@hosts) . " (@hosts), urls: " . scalar(@urls) );
    is( scalar(@urls), scalar(@hosts), 'ISC: every DHCPv6 host that is created gets a boot file URL' );
    is( $urls[0], "tftp://[2001:db8:176::1]/boot/grub2/grub2-$nodes[0]",
        'ISC: the URL brackets the IPv6 boot server and names the node loader' );

    # ISC runs DHCPv6 as a second daemon, so restarting dhcpd alone leaves it stopped or
    # holding the previous configuration. The node then gets no address at all.
    is( scalar( grep { $_ eq 'dhcp6' } @restarted ), 1,
        'ISC: makedhcp restarts the DHCPv6 daemon, which is a service of its own' );

    # No EL or openEuler dhcp package ships /etc/sysconfig/dhcpd6, and dhcpd6 does not need
    # it: ISC dhcpd listens on the interfaces its subnet declarations name. Only an OS outside
    # the DHCPD_INTERFACE family reaches this decision, so the OS is named here.
    {
        local $osver = 'openeuler24.03';
        isc_commands(@nodes);
        unlike( join( ' ', @errors ), qr{/etc/sysconfig/dhcpd6},
            'ISC: a missing /etc/sysconfig/dhcpd6 is not reported as an error' );
    }

    # A node that cannot netboot over IPv6 must get no URL: only the grub2 loaders read one.
    local %DUIDTable::rows = node_rows(%settings);
    $DUIDTable::rows{noderes}{ $nodes[0] }{netboot} = 'xnba';
    my $mixed = isc_commands(@nodes)->[1] // '';
    my @mixed_urls  = $mixed =~ m{dhcp6\.bootfile-url\s*\\?"?(tftp:[^"\\;]+)}g;
    my @mixed_hosts = sort keys %{ isc_hosts($mixed) };
    is( scalar(@mixed_urls), scalar(@mixed_hosts) - 1, 'ISC: an xnba node gets no DHCPv6 boot file URL' );
    unlike( join( '', @mixed_urls ), qr/\Q$nodes[0]\E/,
        'ISC: the URL that is left belongs to the grub2 nodes' );
}

# ---- the IPv6 networks announce a prefix and a route --------------------------------------
# A client that follows RFC 4861 uses DHCPv6 only when a router advertisement sets the managed
# flag, and the on-link prefix and the default route come from the advertisement, not from the
# DHCPv6 lease. So makedhcp has to configure radvd, and the interface has to forward.
{
    local %DUIDTable::rows = node_rows(%settings);
    my $file = "$dir/radvd.conf";
    unlink($file);
    isc_commands('cn01');

    ok( -e $file, 'makedhcp writes the radvd configuration' );
    my $written = do { local ( @ARGV, $/ ) = ($file); <> };
    like( $written, qr/^interface eth0$/m,
        'the configuration names the interface of the IPv6 network' );
    like( $written, qr/AdvSendAdvert\s+on;/,
        'the interface sends advertisements' );
    like( $written, qr/AdvManagedFlag\s+on;/,
        'the managed flag is set, so a client starts DHCPv6' );
    like( $written, qr{\Qprefix 2001:db8:176::/64\E},
        'the prefix of the network is announced' );
    is_deeply( \@forwarded, ['eth0'],
        'forwarding is turned on, because radvd sends nothing on an interface that does not forward' );
}

# ---- the advertisement follows the interface selection -----------------------------------
# site.dhcpinterfaces names the interfaces this server answers on. An advertisement on any
# other interface offers this host as a router to a LAN the administrator kept it off.
is( xCAT_plugin::dhcp::ra_interface_is_served( 'eth0', { eth1 => 1 } ), 0,
    'an interface DHCP does not serve gets no advertisement' );
is( xCAT_plugin::dhcp::ra_interface_is_served( 'eth1', { eth1 => 1 } ), 1,
    'an interface DHCP serves does' );
is( xCAT_plugin::dhcp::ra_interface_is_served( 'eth0', {} ), 1,
    'an empty set is no restriction' );
is( xCAT_plugin::dhcp::ra_interface_is_served( 'eth0', undef ), 1,
    'and neither is an absent one' );
is( xCAT_plugin::dhcp::ra_interface_is_served( '', { eth1 => 1 } ), 0,
    'a network with no mgtifname is skipped' );

# ---- radvd is examined on every call -----------------------------------------------------
# The configuration was the only trigger, so a start that failed left the file already
# correct and a later makedhcp never tried again while the service stayed down.
is( xCAT_plugin::dhcp::radvd_needs_restart( 1, 1 ), 1, 'a changed file restarts radvd' );
is( xCAT_plugin::dhcp::radvd_needs_restart( 1, 0 ), 1, 'and so does a changed file with the service down' );
is( xCAT_plugin::dhcp::radvd_needs_restart( 0, 0 ), 1, 'an unchanged file with the service down restarts it' );
is( xCAT_plugin::dhcp::radvd_needs_restart( 0, 1 ), 0, 'an unchanged file with the service up leaves it alone' );

# configure_router_advertisements is driven directly, because process_request reaches it
# only on some paths and the question here is what the sub itself does on a repeat call.
{
    my $file = "$dir/radvd-direct.conf";
    unlink($file);
    local $xCAT_plugin::dhcp::radvdconffile = $file;
    local @DUIDTable::networks =
      ( { net => '2001:db8:176::', mask => '/64', mgtifname => 'eth0' } );

    my @restarts;
    my @enabled;
    my $up = 0;
    no warnings 'redefine';
    local *xCAT::Table::new = sub { return DUIDTable->new( $_[1] ); };
    local *xCAT_plugin::dhcp::enable_ipv6_forwarding = sub { return; };
    local *xCAT::Utils::enableservice = sub { push @enabled, $_[1]; return 0; };
    local *xCAT::Utils::checkservicestatus = sub { return $up ? 0 : 3; };
    local *xCAT::Utils::restartservice = sub { push @restarts, $_[1]; $up = 1; return 0; };
    use warnings 'redefine';
    local $::XCATSITEVALS{externaldhcpservers};
    my @warn;
    my $cb = sub { push @warn, @{ $_[0]->{warning} || [] } };

    xCAT_plugin::dhcp::configure_router_advertisements( $cb, { eth0 => 1 } );
    is_deeply( \@restarts, ['radvd'], 'the first call writes the file and starts radvd' );
    ok( -s $file, '... and the configuration is on disk' );
    is_deeply( \@enabled, ['radvd'], '... with the service enabled' );

    @restarts = ();
    xCAT_plugin::dhcp::configure_router_advertisements( $cb, { eth0 => 1 } );
    is_deeply( \@restarts, [],
        'an unchanged configuration with radvd up does not restart it' );

    # The service goes down with the configuration already correct, which is what a failed
    # first start leaves behind. The old code returned on the file alone and never retried.
    $up = 0;
    @restarts = ();
    xCAT_plugin::dhcp::configure_router_advertisements( $cb, { eth0 => 1 } );
    is_deeply( \@restarts, ['radvd'],
        'an unchanged configuration with radvd down starts it again' );
    is_deeply( \@warn, [], 'and none of the three calls warned' );
}

# restartservice answers -1 when the service is not installed, and the exit status of the
# command otherwise. Only the -1 was reported, so a radvd that failed to start was silent.
{
    my $file = "$dir/radvd-rc.conf";
    unlink($file);
    local $xCAT_plugin::dhcp::radvdconffile = $file;
    local @DUIDTable::networks =
      ( { net => '2001:db8:176::', mask => '/64', mgtifname => 'eth0' } );
    no warnings 'redefine';
    local *xCAT::Table::new = sub { return DUIDTable->new( $_[1] ); };
    local *xCAT_plugin::dhcp::enable_ipv6_forwarding = sub { return; };
    local *xCAT::Utils::enableservice = sub { return 0; };
    local *xCAT::Utils::checkservicestatus = sub { return 3; };
    our $restart_rc = 1;
    local *xCAT::Utils::restartservice = sub { return $restart_rc };
    use warnings 'redefine';
    local $::XCATSITEVALS{externaldhcpservers};

    my @warn;
    my $cb = sub { push @warn, @{ $_[0]->{warning} || [] } };
    xCAT_plugin::dhcp::configure_router_advertisements( $cb, { eth0 => 1 } );
    is( scalar(@warn), 1, 'a radvd that exits nonzero is reported' );
    like( $warn[0], qr/\bexit 1\b/, '... with the status it exited with' );
    unlike( $warn[0], qr/not installed/, '... and not as a missing package' );

    @warn = ();
    { local $restart_rc = -1;
      xCAT_plugin::dhcp::configure_router_advertisements( $cb, { eth0 => 1 } ); }
    is( scalar(@warn), 1, 'a radvd that is not installed is still reported' );
    like( $warn[0], qr/not installed/, '... as a missing package' );
}

# The whole path: a network on an interface DHCP does not serve writes no advertisement.
{
    local %DUIDTable::rows = node_rows(%settings);
    local $ra_mgtifname  = 'eth9';
    local $dhcpinterfaces = 'eth0';
    my $file = "$dir/radvd.conf";
    unlink($file);
    isc_commands('cn01');
    ok( !-e $file || -z $file,
        'a network on an unserved interface announces nothing' );
}

# ---- A chainloading node is two DHCPv6 clients, with two DUIDs ------------------------------
# EDK2 copies the SMBIOS UUID into its DUID-UUID in the order SMBIOS stores it, and iPXE converts
# the same bytes to RFC 4122 order first. So a netboot=ipxe node solicits twice with two DUIDs. A
# reservation for one of them answers the firmware and leaves iPXE with no boot file, and iPXE
# then prints "Nothing to boot". The second client also needs the boot script, not the shim: the
# shim loads ipxe.efi from its own directory, which iPXE cannot do.
{
    local %DUIDTable::rows = node_rows(%settings);

    my $present = tempdir( CLEANUP => 1 );
    my $shim    = 'xcat/ipxe/x86_64-sb/snponly-shim.efi';
    make_path( dirname("$present/$shim") );
    open( my $fh, '>', "$present/$shim" ) or die "cannot write the loader: $!";
    print {$fh} "loader\n";
    close($fh);

    # cn01 takes the firmware order, cn03 the canonical one, so the two cover both ways round.
    foreach my $node (qw(cn01 cn03)) {
        $DUIDTable::rows{noderes}{$node} =
          { netboot => 'ipxe', tftpserver => '2001:db8:176::1', tftpdir => $present };
    }

    my $config = empty_config();
    # cn02 keeps the grub2 of node_rows. It is the control, and not cn10: the firmware order of
    # the byte-swapped vpd.uuid of cn10 is the canonical order of the vpd.uuid of cn01, so the two
    # nodes would share a DUID here.
    my @all = @{ kea_reservations( $config, 'cn01', 'cn03', 'cn02' ) };
    my %url;
    foreach my $reservation (@all) {
        my ($option) = grep { $_->{name} eq 'bootfile-url' } @{ $reservation->{'option-data'} || [] };
        $url{ $reservation->{duid} } = $option && $option->{data};
    }
    my @cn01 = grep { $_->{duid} eq $firmware or $_->{duid} eq $canonical } @all;
    my $cn02_duid = '00:04:78:56:34:12:34:12:cd:4b:98:76:12:34:56:78:90:ac';

    my $shim_url   = "tftp://[2001:db8:176::1]/$shim";
    my $script_url = 'http://[2001:db8:176::1]/tftpboot/xcat/ipxe/nodes/cn01.uefi';

    is( scalar(@cn01), 2,
        'an ipxe node is reserved for both of the DUIDs its two clients send' );
    my ($first)  = grep { $_->{duid} eq $firmware } @cn01;
    my ($second) = grep { $_->{duid} eq $canonical and !defined $_->{hostname} } @cn01;
    is( $url{$firmware}, undef,
        'neither reservation of a chainloading node names a boot file' );
    my ($second_option) = grep { $_->{name} eq 'bootfile-url' } @{ $second->{'option-data'} || [] };
    is( $second_option, undef, '... including the one that holds no address' );

    # Which order the firmware sends does not follow from vpd.uuid: it reports the SMBIOS bytes
    # of the domain uuid, and getNodeUUID writes that as the byte-swap of vpd.uuid for a KVM
    # guest. So both classes match both orders and option 15 alone decides the stage.
    my $cn01_classes = boot_classes6('cn01');
    ( my $firmware_hex  = $firmware )  =~ s/://g;
    ( my $canonical_hex = $canonical ) =~ s/://g;
    foreach my $pair ( [ $shim_url, 'the UEFI shim' ], [ $script_url, 'the boot script' ] ) {
        my $test = ( $cn01_classes->{ $pair->[0] } || {} )->{test} || '';
        ok( ( $test =~ /\Q$firmware_hex\E/i && $test =~ /\Q$canonical_hex\E/i ),
            "the class serving $pair->[1] matches both UUID orders of the node" );
    }
    ok( $cn01_classes->{$script_url}{test} =~ /option\[15\]/,
        'and the boot script is given only to a client that reports itself as iPXE' );

    # Kea refuses a second reservation for one address, and _reservation_matches treats a shared
    # hostname as the same reservation, so the second entry carries neither.
    is( $second->{'ip-addresses'}, undef, 'the second client reserves no address' );
    is( $second->{hostname},       undef, '... and no hostname' );
    is_deeply( $first->{'ip-addresses'}, [ $address{cn01} ],
        'the address stays on the reservation of the first client' );
    is( $first->{hostname}, 'cn01', '... with the hostname' );

    # mac.duid names the client that keeps the address. cn03 asks for the canonical order, so its
    # iPXE entry holds the address and the firmware entry is the one without it.
    my $cn03_canonical = '00:04:12:34:56:78:12:34:4b:cd:98:76:12:34:56:78:90:ad';
    my $cn03_firmware  = '00:04:78:56:34:12:34:12:cd:4b:98:76:12:34:56:78:90:ad';
    my ($cn03_addressed) = grep { defined $_->{hostname} && $_->{hostname} eq 'cn03' } @all;
    is( $cn03_addressed->{duid}, $cn03_canonical,
        'mac.duid still decides which client keeps the reserved address' );
    ok( exists $url{$cn03_firmware},
        '... and the other client is reserved for as well' );
    is( $url{$cn03_firmware}, undef, '... carrying no boot file of its own' );
    ok( boot_classes6('cn03')->{$shim_url},
        '... because the loader comes from the class of the node' );

    # A grub2 node is loaded by the firmware and asks for nothing more, so a second reservation
    # would be an entry no client matches.
    is( scalar( grep { defined $_->{hostname} && $_->{hostname} eq 'cn02' } @all ), 1,
        'a grub2 node keeps one reservation' );
    is( scalar( grep { !defined $_->{hostname} && $_->{duid} =~ /\A00:04:/ } @all ), 2,
        'and only the two ipxe nodes add a second DUID-UUID' );

    # makedhcp -d removes a reservation by what it is keyed on, so a delete that names one DUID
    # leaves the other entry behind.
    my %matched = map { ( $_->{duid} || '' ) => 1 }
      @{ xCAT_plugin::dhcp::kea_reservation_matches_for_nodes( ['cn01'] ) };
    ok( $matched{$firmware} && $matched{$canonical},
        'makedhcp -d of an ipxe node names both of its DUIDs' );

    # A node with no MAC has no reservation, and its classes must go with it. The classes match
    # the DUID, not the MAC, so a node kept only by its classes still boots its own script, takes
    # its own destiny and never sends the findme that sequential discovery waits for.
    {
        local $DUIDTable::rows{mac}{cn01}{mac} = '';
        is_deeply( kea_reservations( empty_config(), 'cn01' ), [],
            'a node with no MAC gets no DHCPv6 reservation' );
        is_deeply( boot_classes6('cn01'), {}, '... and no per-node boot class' );
    }
    ok( boot_classes6('cn01')->{$script_url}, 'the same node with its MAC back gets its classes' );
    my %grub2 = map { ( $_->{duid} || '' ) => 1 }
      @{ xCAT_plugin::dhcp::kea_reservation_matches_for_nodes( ['cn02'] ) };
    is_deeply( [ sort grep { length } keys %grub2 ], [ sort ( $cn02_duid, '00:03:00:01:' . $mac{cn02} ) ],
        'and of a grub2 node names only the DUIDs it reserved' );

    # ISC DHCP gives one address to one host, so the second client is a host of its own there too.
    my $sessions = isc_commands( 'cn01', 'cn02' );
    my $hosts = isc_hosts( $sessions->[1] // '' );
    is( $hosts->{'cn01-ipxe'}, $canonical,
        'ISC: the second client of an ipxe node is a host keyed on the DUID iPXE sends' );
    is( $hosts->{cn01}, $firmware, '... beside the host of the firmware' );
    is( $hosts->{'cn02-ipxe'}, undef, 'ISC: a grub2 node has one host' );
    my ($statements) = ( $sessions->[1] // '' ) =~
      /^set name = "cn01-ipxe"\nset dhcp-client-identifier = \S+\nset statements = "(.*)";\ncreate$/m;
    is( $statements, 'if substring(option dhcp6.user-class, 2, 4) = \\"iPXE\\" { '
          . 'option dhcp6.bootfile-url \\"' . $script_url . '\\"; } else { '
          . 'option dhcp6.bootfile-url \\"' . $shim_url . '\\"; }',
        'ISC: that host gives iPXE the boot script and any other client the shim' );
}

# ---- The Genesis image is a third client, and it sends a DUID-LL ----------------------------
# The OpenEmbedded Genesis image ships one NetworkManager file, 10-xcat-genesis.conf, and its
# whole DHCPv6 identity policy is ipv6.dhcp-duid=ll. So the image sends the DUID-LL of the
# provisioning NIC, which matches neither order of vpd.uuid, and a node reserved for its UUID
# alone gets no answer once Genesis runs. The DUID-LL is derived from the MAC, so it is reserved
# beside the two UUID orders instead of in place of them: one node, three clients.
{
    local %DUIDTable::rows = node_rows(%settings);

    my $present = tempdir( CLEANUP => 1 );
    my $shim    = 'xcat/ipxe/x86_64-sb/snponly-shim.efi';
    make_path( dirname("$present/$shim") );
    open( my $fh, '>', "$present/$shim" ) or die "cannot write the loader: $!";
    print {$fh} "loader\n";
    close($fh);

    # cn01 takes the firmware order, cn04 holds a DUID of its own and cn13 asks for ll. All three
    # chainload, so the two that keep one reservation keep it because of mac.duid and not because
    # iPXE is absent.
    foreach my $node (qw(cn01 cn04 cn13)) {
        $DUIDTable::rows{noderes}{$node} =
          { netboot => 'ipxe', tftpserver => '2001:db8:176::1', tftpdir => $present };
    }

    is( $mac{cn01}, '02:00:00:00:01:21', 'the MAC that the DUID-LL of the chainloading node is built from' );
    is( $mac{cn02}, '02:00:00:00:01:22', 'and the MAC of the node that the firmware boots directly' );
    my $ll_cn01 = '00:03:00:01:02:00:00:00:01:21';
    my $ll_cn02 = '00:03:00:01:02:00:00:00:01:22';

    my $shim_url   = "tftp://[2001:db8:176::1]/$shim";
    my $script_url = 'http://[2001:db8:176::1]/tftpboot/xcat/ipxe/nodes/cn01.uefi';

    my $config = empty_config();
    my @cn01 = @{ kea_reservations( $config, 'cn01' ) };
    is_deeply( [ map { $_->{duid} } @cn01 ], [ $firmware, $canonical, $ll_cn01 ],
        'an ipxe node is reserved for the firmware order, the RFC 4122 order, and the DUID-LL' );

    # Kea refuses a second reservation for one address, and _reservation_matches treats a shared
    # hostname as the same reservation, so only the first client carries either.
    is_deeply( $cn01[0]->{'ip-addresses'}, [ $address{cn01} ], 'the first client keeps the address' );
    is( $cn01[0]->{hostname}, 'cn01', '... and the hostname' );
    is( scalar( grep { defined $_->{hostname} || $_->{'ip-addresses'} } @cn01 ), 1,
        'and no other client of the node carries either' );

    my @option = map {
        my ($found) = grep { $_->{name} eq 'bootfile-url' } @{ $_->{'option-data'} || [] };
        $found;
    } @cn01;
    # Only the Genesis client is answered from its reservation. The two UUID-order clients are
    # the chainload stages, and a reservation cannot tell them apart.
    is( scalar( grep { $_ && $_->{'always-send'} } @option ), 1,
        'one of the three clients is sent a boot file URL from its reservation' );
    is( $option[0], undef, 'the firmware is not given one there' );
    is( $option[1], undef, '... nor is iPXE' );
    my $classes = boot_classes6('cn01');
    ok( $classes->{$shim_url},   'the firmware is given the UEFI shim by its class' );
    ok( $classes->{$script_url}, 'and iPXE the boot script by its own' );
    is( $option[2] && $option[2]->{data}, $shim_url,
        'and the Genesis client the same file as the firmware' );

    # The Genesis image boots whatever loaded it, so a node that the firmware boots directly
    # sends the DUID-LL as well. It never runs iPXE, so the RFC 4122 order is left out.
    my @cn02 = @{ kea_reservations( $config, 'cn02' ) };
    is_deeply( [ map { $_->{duid} } @cn02 ],
        [ '00:04:78:56:34:12:34:12:cd:4b:98:76:12:34:56:78:90:ac', $ll_cn02 ],
        'a grub2 node is reserved for its firmware and for Genesis, and not for iPXE' );
    is_deeply( $cn02[0]->{'ip-addresses'}, [ $address{cn02} ],
        'the firmware of that node still keeps its address' );
    is( $cn02[1]->{hostname}, undef, 'and the Genesis client of it holds none' );

    # mac.duid names one client and one DUID. Neither value is built from vpd.uuid, so there is
    # no second order to derive and nothing to add: the node answers as the operator said.
    my @cn13 = @{ kea_reservations( $config, 'cn13' ) };
    is( scalar(@cn13), 1, 'a node that asks for ll keeps the single reservation it asked for' );
    is( $cn13[0]->{duid}, $ll_cn13, '... keyed on the DUID-LL' );
    is_deeply( $cn13[0]->{'ip-addresses'}, [ $address{cn13} ], '... which keeps the address' );

    my @cn04 = @{ kea_reservations( $config, 'cn04' ) };
    is( scalar(@cn04), 1, 'a node with a DUID of its own keeps a single reservation too' );
    is( $cn04[0]->{duid}, $literal, '... keyed on that DUID, as given' );

    # makedhcp -d removes a reservation by what it is keyed on, so a delete that does not name
    # the DUID-LL leaves that entry behind with the boot file of a node it removed.
    my %matched = map { ( $_->{duid} || '' ) => 1 }
      @{ xCAT_plugin::dhcp::kea_reservation_matches_for_nodes( ['cn01'] ) };
    ok( $matched{$ll_cn01}, 'makedhcp -d of an ipxe node names its DUID-LL as well' );
    my %grub2 = map { ( $_->{duid} || '' ) => 1 }
      @{ xCAT_plugin::dhcp::kea_reservation_matches_for_nodes( ['cn02'] ) };
    ok( $grub2{$ll_cn02}, 'and of a grub2 node names the DUID-LL it reserved' );

    # ISC DHCP gives one address to one host, so the Genesis client is a host of its own there.
    my $sessions = isc_commands( 'cn01', 'cn02' );
    my $hosts = isc_hosts( $sessions->[1] // '' );
    is( $hosts->{'cn01-genesis'}, $ll_cn01,
        'ISC: the Genesis client of an ipxe node is a host keyed on the DUID-LL' );
    is( $hosts->{'cn01-ipxe'}, $canonical, '... beside the host of iPXE' );
    is( $hosts->{cn01}, $firmware, '... and the host of the firmware' );
    is( $hosts->{'cn02-genesis'}, $ll_cn02, 'ISC: a grub2 node gets that host as well' );
    is( $hosts->{'cn02-ipxe'}, undef, '... and no host for a client it never runs' );

    my $removed = '';
    open( my $session, '>', \$removed ) or die "Cannot open an omshell buffer: $!";
    xCAT_plugin::dhcp::delnode6( 'cn01', $session );
    close($session);
    like( $removed, qr/^set name = "cn01-genesis"\nopen\nremove\n/m,
        'ISC: makedhcp -d removes the host of the Genesis client' );
    like( $removed, qr/^set name = "cn01-ipxe"\nopen\nremove\n/m, '... and the host of iPXE' );

    # No IPv4 behaviour changes. A DUID identifies a DHCPv6 client, so a DHCPv4 reservation is
    # keyed on the hardware address of the NIC whatever mac.duid holds.
    {
        local $resolve{cn01} = { 4 => '192.0.2.21', 6 => $address{cn01} };
        no warnings 'redefine';
        local *xCAT_plugin::dhcp::next_server_for_node = sub { return ( '192.0.2.1', '192.0.2.1' ); };
        local *xCAT_plugin::dhcp::kea_boot_for_node    = sub { return {}; };
        use warnings 'redefine';
        my $v4 = xCAT_plugin::dhcp::kea_build_node_reservations(
            bless( {}, 'DUIDKeaV4Backend' ), {}, ['cn01'] );
        is_deeply( [ map { $_->{'hw-address'} } @$v4 ], [ $mac{cn01} ],
            'the node keeps its one IPv4 reservation, keyed on its MAC' );
        ok( !grep( { $_->{duid} } @$v4 ), 'and no DUID reaches a DHCPv4 reservation' );
    }
}

# ---- mac.duid=canonical makes iPXE the client that holds the address ------------------------
# The canonical order is the DUID that iPXE sends, so the host named after the node answers iPXE
# and the firmware gets the host <node>-firmware. iPXE that is given the shim again never reaches
# the boot script of the node.
{
    local %DUIDTable::rows = node_rows(%settings);

    my $present = tempdir( CLEANUP => 1 );
    my $shim    = 'xcat/ipxe/x86_64-sb/snponly-shim.efi';
    make_path( dirname("$present/$shim") );
    open( my $fh, '>', "$present/$shim" ) or die "cannot write the loader: $!";
    print {$fh} "loader\n";
    close($fh);
    $DUIDTable::rows{noderes}{cn03} =
      { netboot => 'ipxe', tftpserver => '2001:db8:176::1', tftpdir => $present };

    my $cn03_canonical = '00:04:12:34:56:78:12:34:4b:cd:98:76:12:34:56:78:90:ad';
    my $cn03_firmware  = '00:04:78:56:34:12:34:12:cd:4b:98:76:12:34:56:78:90:ad';
    my $shim_url   = "tftp://[2001:db8:176::1]/$shim";
    my $script_url = 'http://[2001:db8:176::1]/tftpboot/xcat/ipxe/nodes/cn03.uefi';

    my $session = isc_commands('cn03')->[1] // '';
    my $hosts = isc_hosts($session);
    is( $hosts->{cn03}, $cn03_canonical, 'ISC: the host of a canonical node is keyed on the DUID iPXE sends' );
    is( $hosts->{'cn03-firmware'}, $cn03_firmware, '... and the firmware has a host of its own' );

    # Option 15 decides the stage on both hosts, so each gives iPXE the boot script and the
    # firmware the shim, whichever client its DUID belongs to.
    my %stage;
    while ( $session =~ /^set name = "([^"]+)"\nset dhcp-client-identifier = \S+\nset statements = "[^\n]*?if substring\(option dhcp6\.user-class, 2, 4\) = \\"iPXE\\" \{ option dhcp6\.bootfile-url \\"([^\\]+)\\"; \} else \{ option dhcp6\.bootfile-url \\"([^\\]+)\\"; \}";$/mg ) {
        $stage{$1} = [ $2, $3 ];
    }
    is_deeply( $stage{cn03}, [ $script_url, $shim_url ],
        'ISC: the host of the canonical order gives iPXE the boot script and the firmware the shim' );
    is_deeply( $stage{'cn03-firmware'}, [ $script_url, $shim_url ],
        'ISC: and so does the host of the firmware order' );

    # makedhcp -d removes the DHCPv6 hosts by name, so a name it does not list stays behind with
    # the boot file of a node that makedhcp reported as removed.
    my $removed = '';
    open( my $out, '>', \$removed ) or die "Cannot open an omshell buffer: $!";
    xCAT_plugin::dhcp::delnode6( 'cn03', $out );
    close($out);
    like( $removed, qr/^set name = "cn03-firmware"\nopen\nremove\n/m,
        'ISC: makedhcp -d removes the host of the firmware client' );
}

# ---- A change of netboot removes the reservation of a client that no longer solicits ---------
# netboot=ipxe gives the node an entry for iPXE that holds no address and no hostname. After a
# change to grub2 nothing keys on that entry any more, so neither the update nor makedhcp -d
# found it, and the DUID of iPXE stayed reserved with the boot script of the old method.
{
    local %DUIDTable::rows = node_rows(%settings);

    my $present = tempdir( CLEANUP => 1 );
    my $shim    = 'xcat/ipxe/x86_64-sb/snponly-shim.efi';
    make_path( dirname("$present/$shim") );
    open( my $fh, '>', "$present/$shim" ) or die "cannot write the loader: $!";
    print {$fh} "loader\n";
    close($fh);
    my $ipxe  = { netboot => 'ipxe',  tftpserver => '2001:db8:176::1', tftpdir => $present };
    my $grub2 = { netboot => 'grub2', tftpserver => '2001:db8:176::1' };

    my $config = empty_config();
    $DUIDTable::rows{noderes}{cn01} = $ipxe;
    $backend->upsert_reservations( $config, kea_reservations( $config, 'cn01' ), [] );
    my @before = map { $_->{duid} } @{ $config->{Dhcp6}{subnet6}[0]{reservations} };
    ok( ( grep { $_ eq $canonical } @before ), 'Kea: an ipxe node has an entry for iPXE' );

    $DUIDTable::rows{noderes}{cn01} = $grub2;
    my @stale;
    $backend->upsert_reservations( $config, kea_reservations( $config, 'cn01' ), \@stale );
    my @after = map { $_->{duid} } @{ $config->{Dhcp6}{subnet6}[0]{reservations} };
    ok( !( grep { $_ eq $canonical } @after ), 'Kea: after a change to grub2 the entry for iPXE is gone' );
    ok( ( grep { ( $_->{duid} // '' ) eq $canonical } @stale ),
        '... and it is in the replaced list, so the Control Agent deletes it too' );

    # The same leftover reached through makedhcp -d: the entry of iPXE is written, then the node
    # changes to grub2 and is deleted.
    $config = empty_config();
    $DUIDTable::rows{noderes}{cn01} = $ipxe;
    $backend->upsert_reservations( $config, kea_reservations( $config, 'cn01' ), [] );
    $DUIDTable::rows{noderes}{cn01} = $grub2;
    foreach my $match ( @{ xCAT_plugin::dhcp::kea_reservation_matches_for_nodes( ['cn01'] ) } ) {
        $backend->delete_reservations( $config, $match );
    }
    is_deeply( [ map { $_->{duid} } @{ $config->{Dhcp6}{subnet6}[0]{reservations} } ], [],
        'Kea: makedhcp -d after a change of netboot removes every entry of the node' );

    # ISC DHCP: the host of iPXE is removed by name when the node no longer chainloads.
    $DUIDTable::rows{noderes}{cn01} = $grub2;
    my $session = isc_commands('cn01')->[1] // '';
    like( $session, qr/^new host\nset name = "cn01-ipxe"\nopen\nremove\nclose\n/m,
        'ISC: a grub2 node removes the host that iPXE had' );
}

# ---- dhcpinterfaces=* serves every interface, and so does the advertisement ------------------
# Kea accepts the wildcard. The advertisement looked the interface name up literally, so a
# wildcard served no interface and radvd was given no configuration.
is( xCAT_plugin::dhcp::ra_interface_is_served( 'eth0', { '*' => 1 } ), 1,
    'the wildcard serves an interface that it does not name' );
{
    my $file = "$dir/radvd-wildcard.conf";
    unlink($file);
    local $xCAT_plugin::dhcp::radvdconffile = $file;
    local @DUIDTable::networks =
      ( { net => '2001:db8:176::', mask => '/64', mgtifname => 'eth0' } );
    no warnings 'redefine';
    local *xCAT::Table::new = sub { return DUIDTable->new( $_[1] ); };
    local *xCAT_plugin::dhcp::enable_ipv6_forwarding = sub { return; };
    local *xCAT::Utils::enableservice = sub { return 0; };
    local *xCAT::Utils::checkservicestatus = sub { return 0; };
    local *xCAT::Utils::restartservice = sub { return 0; };
    use warnings 'redefine';
    local $::XCATSITEVALS{externaldhcpservers};
    xCAT_plugin::dhcp::configure_router_advertisements( sub { }, { '*' => 1 } );
    my $written = -e $file ? do { local ( @ARGV, $/ ) = ($file); <> } : '';
    like( $written, qr/^interface eth0$/m, 'dhcpinterfaces=* announces the IPv6 network on its interface' );
}

# ---- The last IPv6 network removed withdraws the advertisement --------------------------------
# radvd kept the old configuration, so the host went on announcing a prefix and a default route
# for a network that xCAT no longer serves.
{
    my $file = "$dir/radvd-withdraw.conf";
    unlink($file);
    local $xCAT_plugin::dhcp::radvdconffile = $file;
    local @DUIDTable::networks =
      ( { net => '2001:db8:176::', mask => '/64', mgtifname => 'eth0' } );
    my ( @stopped, @disabled );
    no warnings 'redefine';
    local *xCAT::Table::new = sub { return DUIDTable->new( $_[1] ); };
    local *xCAT_plugin::dhcp::enable_ipv6_forwarding = sub { return; };
    local *xCAT::Utils::enableservice = sub { return 0; };
    local *xCAT::Utils::checkservicestatus = sub { return 0; };
    local *xCAT::Utils::restartservice = sub { return 0; };
    local *xCAT::Utils::stopservice = sub { push @stopped, $_[1]; return 0; };
    local *xCAT::Utils::disableservice = sub { push @disabled, $_[1]; return 0; };
    use warnings 'redefine';
    local $::XCATSITEVALS{externaldhcpservers};
    my @warn;
    my $cb = sub { push @warn, @{ $_[0]->{warning} || [] } };

    xCAT_plugin::dhcp::configure_router_advertisements( $cb, { eth0 => 1 } );
    ok( -s $file, 'the IPv6 network is announced first' );
    is_deeply( \@stopped, [], '... and radvd is not stopped while a network remains' );

    @DUIDTable::networks = ( { net => '192.0.2.0', mask => '255.255.255.0', mgtifname => 'eth0' } );
    xCAT_plugin::dhcp::configure_router_advertisements( $cb, { eth0 => 1 } );
    is_deeply( \@stopped, ['radvd'], 'radvd is stopped when no IPv6 network remains' );
    ok( !-e $file, '... and its configuration is removed, so a restart does not announce it again' );
    is_deeply( \@disabled, ['radvd'], '... and the service is disabled' );
    is_deeply( \@warn, [], 'and the withdrawal warns about nothing' );

    # A radvd configuration that xCAT did not write belongs to the administrator.
    open( my $own, '>', $file ) or die "Cannot write $file: $!";
    print {$own} "interface eth5 { AdvSendAdvert on; };\n";
    close($own);
    @stopped = ();
    xCAT_plugin::dhcp::configure_router_advertisements( $cb, { eth0 => 1 } );
    is_deeply( \@stopped, [], 'a radvd configuration that xCAT did not write is left alone' );
    ok( -s $file, '... and stays on disk' );
}

# A KVM guest that xCAT defines reads its own UUID back in the other order. getNodeUUID writes
# the byte swap of vpd.uuid into the libvirt domain and qemu stores that little-endian in SMBIOS,
# so the two swaps cancel and the firmware sends vpd.uuid unswapped. Measured on xcat88-cn: the
# firmware and the Genesis image both sent the canonical order while iPXE sent the swap. The
# reserved address has to be on the order the firmware sends, because a host reservation is what
# applies to every IA of a client and the image solicits with a different IAID than the firmware.
{
    # The address holder of cn01 with each mgt value. node_rows reads %mgt_of, so %mgt_of is set
    # before the rows are built.
    my %holder_for;
    foreach my $mgt ( 'kvm', '' ) {
        local %mgt_of          = ( cn01 => $mgt );
        local %DUIDTable::rows = node_rows();
        $DUIDTable::rows{noderes}{cn01} =
          { netboot => 'ipxe', tftpserver => '2001:db8:176::1' };

        my $config = empty_config();
        my ($holder) = grep { $_->{'ip-addresses'} }
          @{ kea_reservations( $config, 'cn01' ) };
        $holder_for{$mgt} = $holder;
    }

    ok( $holder_for{kvm}, 'a kvm node still reserves its address' );
    is( ( $holder_for{kvm} || {} )->{duid}, $canonical,
        'the address of a kvm node is reserved for the canonical order, which its firmware sends' );
    is_deeply( ( $holder_for{kvm} || {} )->{'ip-addresses'}, [ $address{cn01} ],
        '... and it is the address of the node' );
    is( ( $holder_for{''} || {} )->{duid}, $firmware,
        'a node xCAT does not define keeps the address on the byte-swapped order' );
}


# ---- ISC: the boot stage, not the DUID, decides the boot file --------------------------------
# Which UUID order the firmware of a guest sends depends on the UUID its libvirt domain was given,
# so the label of a DUID does not name the client that sends it. With mgt=kvm the labels were
# reversed: ISC gave the boot script to the firmware and the shim to iPXE, and the node booted
# neither. Kea splits the stages on option 15, which iPXE sends and the firmware does not. ISC
# must make the same split on every host that holds a UUID order of the node.
{
    local %mgt_of = ( cn01 => 'kvm' );
    local %DUIDTable::rows = node_rows(%settings);

    my $present = tempdir( CLEANUP => 1 );
    my $shim    = 'xcat/ipxe/x86_64-sb/snponly-shim.efi';
    make_path( dirname("$present/$shim") );
    open( my $fh, '>', "$present/$shim" ) or die "cannot write the loader: $!";
    print {$fh} "loader\n";
    close($fh);
    $DUIDTable::rows{noderes}{cn01} =
      { netboot => 'ipxe', tftpserver => '2001:db8:176::1', tftpdir => $present };

    my $shim_url   = "tftp://[2001:db8:176::1]/$shim";
    my $script_url = 'http://[2001:db8:176::1]/tftpboot/xcat/ipxe/nodes/cn01.uefi';
    my $by_stage   = 'if substring(option dhcp6.user-class, 2, 4) = \\"iPXE\\" { '
      . 'option dhcp6.bootfile-url \\"' . $script_url . '\\"; } else { '
      . 'option dhcp6.bootfile-url \\"' . $shim_url . '\\"; }';

    my $session = ( isc_commands('cn01') )->[1] // '';
    my %host_of = reverse %{ isc_hosts($session) };
    my %statements;
    while ( $session =~ /^set name = "([^"]+)"\nset dhcp-client-identifier = \S+\nset statements = "(.*)";$/mg ) {
        $statements{$1} = $2;
    }

    foreach my $order ( [ $canonical, 'canonical' ], [ $firmware, 'firmware' ] ) {
        my $host = $host_of{ $order->[0] } // '';
        my $text = $statements{$host} // '';
        $text =~ s/^ddns-hostname \\"cn01\\"; //;
        is( $text, $by_stage,
            "ISC: the host of the $order->[1] order gives the boot script to iPXE and the shim to any other client" );
    }
}

# ---- The per-network discovery script follows site.httpport ---------------------------------
# The per-node script URL reads site.httpport. The per-network classes that kea_boot_client_classes6
# builds for an unknown node must read it too, or with httpport=8080 that node loads iPXE and
# cannot fetch the script of its network.
{
    no warnings 'redefine';
    local *xCAT::NetworkUtils::my_ip_facing_family = sub { return ( 0, '2001:db8:176::1' ); };
    local *xCAT_plugin::dhcp::kea_ipxe_loader_flags = sub { return ( ipxe_bios => 0, ipxe_uefi => 1 ); };
    local *xCAT::TableUtils::get_site_attribute = sub {
        my ( $class, $attribute ) = @_;
        return $attribute eq 'httpport' ? ('8080') : ();
    };
    use warnings 'redefine';

    my ($second) = grep { $_->{test} =~ /iPXE/ }
      @{ xCAT_plugin::dhcp::kea_boot_client_classes6( '2001:db8:176::/64', 1 ) };
    is( $second && $second->{'option-data'}[0]{data},
        'http://[2001:db8:176::1]:8080/tftpboot/xcat/ipxe/nets/2001:db8:176::_64.uefi',
        'the discovery script of a network is fetched from site.httpport' );
}

done_testing();
