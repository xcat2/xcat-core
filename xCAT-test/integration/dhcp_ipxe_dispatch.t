#!/usr/bin/env perl
# makedhcp picks the boot file of an x86 client from its netboot method, its architecture, its user
# class and the iPXE feature options it reports in option 175. The test runs dhcpd and kea-dhcp4 in
# a network namespace with the rules that BootPolicy renders, sends relayed DHCPDISCOVER packets for
# each kind of client from a second namespace, and checks the boot file of each offer.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/lib";

use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use JSON ();
use Test::More;

use xCAT::CommandUtils;
use xCAT::DHCP::Backend::Kea;
use xCAT::DHCP::BootPolicy;
use xCAT::DHCP::OmapiPolicy;
use XCAT::Test::DHCP qw(start_daemon process_running stop_daemons diag_file);

plan skip_all => 'root is required to run DHCP servers in network namespaces' unless $> == 0;
my ($dhcpd) = grep { -x $_ } qw(/usr/sbin/dhcpd /usr/local/sbin/dhcpd);
my $omapi = xCAT::DHCP::OmapiPolicy->settings( site_values => {} );
my $kea_dhcp4 = xCAT::CommandUtils::find_executable('kea-dhcp4');
my @backends = ( ( $dhcpd && -x $omapi->{omshell_path} ? 'isc' : () ), ( $kea_dhcp4 ? 'kea' : () ) );
plan skip_all => 'dhcpd with omshell, or kea-dhcp4, is required' unless @backends;

my $server_ns = "xcat-test-$$-s";
my $client_ns = "xcat-test-$$-c";
my ( @namespaces, %children );
END {
    stop_daemons( \%children );
    system( 'ip', 'netns', 'delete', $_ ) for @namespaces;
}
for my $namespace ( $server_ns, $client_ns ) {
    plan skip_all => 'ip netns is required' unless system("ip netns add $namespace >/dev/null 2>&1") == 0;
    push @namespaces, $namespace;
}
my $interface = "xt$$";
for my $command (
    [ $server_ns, 'link', 'set', 'lo', 'up' ],
    [ $client_ns, 'link', 'set', 'lo', 'up' ],
    [ $server_ns, 'link', 'add', "${interface}s", 'type', 'veth', 'peer', 'name', "${interface}c", 'netns', $client_ns ],
    [ $server_ns, 'address', 'add', '192.0.2.1/24', 'dev', "${interface}s" ],
    [ $client_ns, 'address', 'add', '192.0.2.2/24', 'dev', "${interface}c" ],
    [ $server_ns, 'link', 'set', "${interface}s", 'up' ],
    [ $client_ns, 'link', 'set', "${interface}c", 'up' ],
  )
{
    my ( $namespace, @args ) = @$command;
    system( 'ip', '-n', $namespace, @args ) == 0 or BAIL_OUT("ip -n $namespace @args failed");
}

# The nodes: one of each method that installs, one of each that boots from SAN, and, on ISC, one of
# each in the boot state of an iSCSI node.
my %xnba       = ( name => 'cn01', mac => '52:54:00:00:10:01', ip => '192.0.2.11', netboot => 'xnba' );
my %ipxe       = ( name => 'cn04', mac => '52:54:00:00:10:04', ip => '192.0.2.14', netboot => 'ipxe' );
my %xnba_san   = ( name => 'cn03', mac => '52:54:00:00:10:03', ip => '192.0.2.13', netboot => 'xnba', iscsi => 1 );
my %ipxe_san   = ( name => 'cn06', mac => '52:54:00:00:10:06', ip => '192.0.2.16', netboot => 'ipxe', iscsi => 1 );
my %xnba_iscsi = ( name => 'cn02', mac => '52:54:00:00:10:02', ip => '192.0.2.12', netboot => 'xnba', iscsi => 1 );
my %ipxe_iscsi = ( name => 'cn05', mac => '52:54:00:00:10:05', ip => '192.0.2.15', netboot => 'ipxe', iscsi => 1 );
my $unknown = '52:54:00:00:10:09';
my $network = 'http://192.0.2.1/tftpboot/xcat/ipxe/nets/192.0.2.0_24';
my %first   = (
    xnba => { bios => 'xcat/xnba.kpxe',               uefi => 'xcat/xnba.efi' },
    ipxe => { bios => 'xcat/ipxe/i386/undionly.kpxe', uefi => 'xcat/ipxe/x86_64-sb/snponly-shim.efi' },
);

# The option 175 of an iPXE build: its bus-id, then one byte for each feature.
my %feature = ( iscsi => 17, http => 19, bzimage => 24, pxe => 33, efi => 36 );
sub ipxe { return [ [ 177, '01000000000000' ], map { [ $feature{$_}, '01' ] } @_ ] }

# The rows of a node that installs: each client, and the boot file it gets.
sub node_rows {
    my ($node) = @_;
    my $method = $node->{netboot};
    my $script = "http://192.0.2.1/tftpboot/xcat/$method/nodes/$node->{name}";
    my %loader = %{ $first{$method} };
    my ( $bios_script, $uefi_script ) = $method eq 'ipxe' ? ( $script, "$script.uefi" ) : @loader{qw(bios uefi)};
    my %c = ( mac => $node->{mac} );
    # UEFI firmware reports architecture 7 or 9. The ISC host statements of an xnba node give nothing
    # to a client on 9 that is not xNBA, as they did before, so these rows are for ipxe nodes.
    my @arch9 = $method eq 'ipxe' ? (
        [ 'firmware PXE, UEFI arch 9', { arch => 9 }, $loader{uefi} ],
        [ 'iPXE with HTTP and EFI, UEFI arch 9', { arch => 9, user_class => 'iPXE', ipxe => ipxe(qw(http efi)) }, $uefi_script ],
        [ 'iPXE without EFI, UEFI arch 9', { arch => 9, user_class => 'iPXE', ipxe => ipxe(qw(http)) }, $loader{uefi} ],
    ) : ();
    return map { [ "$method node, $_->[0]", { %c, %{ $_->[1] } }, $_->[2] ] } @arch9, (
        [ 'firmware PXE, BIOS', { arch => 0 }, $loader{bios} ],
        [ 'firmware PXE, UEFI', { arch => 7 }, $loader{uefi} ],
        [ 'xNBA, BIOS', { arch => 0, user_class => 'xNBA', ipxe => ipxe(qw(http bzimage pxe iscsi)) }, $script ],
        [ 'xNBA, UEFI arch 7', { arch => 7, user_class => 'xNBA', ipxe => ipxe(qw(http efi iscsi)) }, "$script.uefi" ],
        [ 'xNBA, UEFI arch 9', { arch => 9, user_class => 'xNBA', ipxe => ipxe(qw(http efi iscsi)) }, "$script.uefi" ],
        [ 'iPXE with HTTP, bzImage and PXE, BIOS', { arch => 0, user_class => 'iPXE', ipxe => ipxe(qw(http bzimage pxe)) }, $bios_script ],
        [ 'iPXE without HTTP, BIOS',    { arch => 0, user_class => 'iPXE', ipxe => ipxe(qw(bzimage pxe)) }, $loader{bios} ],
        [ 'iPXE without bzImage, BIOS', { arch => 0, user_class => 'iPXE', ipxe => ipxe(qw(http pxe)) },    $loader{bios} ],
        [ 'iPXE without PXE, BIOS',     { arch => 0, user_class => 'iPXE', ipxe => ipxe(qw(http bzimage)) }, $loader{bios} ],
        [ 'iPXE with HTTP and EFI, UEFI', { arch => 7, user_class => 'iPXE', ipxe => ipxe(qw(http efi)) }, $uefi_script ],
        [ 'iPXE without HTTP, UEFI', { arch => 7, user_class => 'iPXE', ipxe => ipxe(qw(efi)) },  $loader{uefi} ],
        [ 'iPXE without EFI, UEFI',  { arch => 7, user_class => 'iPXE', ipxe => ipxe(qw(http)) }, $loader{uefi} ],
        [ 'iPXE without option 175, BIOS', { arch => 0, user_class => 'iPXE' }, $loader{bios} ],
        [ 'iPXE with its sub-options reversed, BIOS', { arch => 0, user_class => 'iPXE', ipxe => [ reverse @{ ipxe(qw(http bzimage pxe)) } ] }, $bios_script ],
    );
}

# The rows of a SAN node that installs: iPXE hooks its iSCSI root path first, so the script of an
# ipxe node needs iSCSI. An xnba node gives its script to xNBA only.
sub san_rows {
    my ($node) = @_;
    my $method = $node->{netboot};
    my $script = "http://192.0.2.1/tftpboot/xcat/$method/nodes/$node->{name}";
    my %loader = %{ $first{$method} };
    my $ipxe = $method eq 'ipxe';
    my %c = ( mac => $node->{mac} );
    return map { [ "$method SAN node installing, $_->[0]", { %c, %{ $_->[1] } }, $_->[2] ] } (
        [ 'xNBA, BIOS', { arch => 0, user_class => 'xNBA', ipxe => ipxe(qw(http bzimage pxe iscsi)) }, $script ],
        [ 'iPXE with iSCSI, BIOS',    { arch => 0, user_class => 'iPXE', ipxe => ipxe(qw(http bzimage pxe iscsi)) }, $ipxe ? $script : $loader{bios} ],
        [ 'iPXE without iSCSI, BIOS', { arch => 0, user_class => 'iPXE', ipxe => ipxe(qw(http bzimage pxe)) },       $loader{bios} ],
        [ 'iPXE with iSCSI, UEFI',    { arch => 7, user_class => 'iPXE', ipxe => ipxe(qw(http efi iscsi)) }, $ipxe ? "$script.uefi" : $loader{uefi} ],
        [ 'iPXE without iSCSI, UEFI', { arch => 7, user_class => 'iPXE', ipxe => ipxe(qw(http efi)) },       $loader{uefi} ],
    );
}

my @node_rows = ( node_rows( \%xnba ), node_rows( \%ipxe ) );
my @san_rows  = ( san_rows( \%xnba_san ), san_rows( \%ipxe_san ) );
my @network_rows = (
    [ 'unknown node, firmware PXE, BIOS', { mac => $unknown, arch => 0 }, $first{ipxe}{bios} ],
    [ 'unknown node, firmware PXE, UEFI', { mac => $unknown, arch => 7 }, $first{ipxe}{uefi} ],
    [ 'unknown node, iPXE with every feature, BIOS', { mac => $unknown, arch => 0, user_class => 'iPXE', ipxe => ipxe(qw(http bzimage pxe)) }, $network ],
    [ 'unknown node, iPXE with every feature, UEFI', { mac => $unknown, arch => 7, user_class => 'iPXE', ipxe => ipxe(qw(http efi)) }, "$network.uefi" ],
    [ 'unknown node, iPXE without HTTP, BIOS', { mac => $unknown, arch => 0, user_class => 'iPXE', ipxe => ipxe(qw(bzimage pxe)) }, $first{ipxe}{bios} ],
    [ 'unknown node, xNBA with every feature, BIOS', { mac => $unknown, arch => 0, user_class => 'xNBA', ipxe => ipxe(qw(http bzimage pxe)) }, $network ],
);
# In the boot state ISC gives a SAN client the empty file name. ISC tests the bus ID that every iPXE
# sends for an xnba node, and Kea the iSCSI feature for both methods, so Kea has rows of its own.
my @iscsi_rows = (
    [ 'xnba iSCSI node, iPXE with iSCSI',    { mac => $xnba_iscsi{mac}, arch => 0, user_class => 'iPXE', ipxe => ipxe(qw(http bzimage pxe iscsi)) }, '' ],
    [ 'xnba iSCSI node, iPXE without iSCSI', { mac => $xnba_iscsi{mac}, arch => 0, user_class => 'iPXE', ipxe => ipxe(qw(http bzimage pxe)) },       '' ],
    [ 'ipxe iSCSI node, iPXE with iSCSI',    { mac => $ipxe_iscsi{mac}, arch => 0, user_class => 'iPXE', ipxe => ipxe(qw(http bzimage pxe iscsi)) }, '' ],
    [ 'ipxe iSCSI node, iPXE without iSCSI', { mac => $ipxe_iscsi{mac}, arch => 0, user_class => 'iPXE', ipxe => ipxe(qw(http bzimage pxe)) },       $first{ipxe}{bios} ],
    [ 'ipxe iSCSI node, firmware PXE, UEFI arch 7', { mac => $ipxe_iscsi{mac}, arch => 7 }, $first{ipxe}{uefi} ],
    [ 'ipxe iSCSI node, firmware PXE, UEFI arch 9', { mac => $ipxe_iscsi{mac}, arch => 9 }, $first{ipxe}{uefi} ],
    [ 'ipxe iSCSI node, iPXE with iSCSI, UEFI', { mac => $ipxe_iscsi{mac}, arch => 7, user_class => 'iPXE', ipxe => ipxe(qw(http efi iscsi)) }, '' ],
);

my @kea_iscsi_rows = (
    [ 'xnba iSCSI node, firmware PXE, BIOS', { mac => $xnba_iscsi{mac}, arch => 0 }, $first{xnba}{bios} ],
    [ 'xnba iSCSI node, iPXE without iSCSI', { mac => $xnba_iscsi{mac}, arch => 0, user_class => 'iPXE', ipxe => ipxe(qw(http bzimage pxe)) }, $first{xnba}{bios} ],
    [ 'xnba iSCSI node, iPXE with iSCSI',    { mac => $xnba_iscsi{mac}, arch => 0, user_class => 'iPXE', ipxe => ipxe(qw(http bzimage pxe iscsi)) }, '' ],
    [ 'ipxe iSCSI node, firmware PXE, BIOS', { mac => $ipxe_iscsi{mac}, arch => 0 }, $first{ipxe}{bios} ],
    [ 'ipxe iSCSI node, iPXE without iSCSI', { mac => $ipxe_iscsi{mac}, arch => 0, user_class => 'iPXE', ipxe => ipxe(qw(http bzimage pxe)) }, $first{ipxe}{bios} ],
    [ 'ipxe iSCSI node, iPXE with iSCSI',    { mac => $ipxe_iscsi{mac}, arch => 0, user_class => 'iPXE', ipxe => ipxe(qw(http bzimage pxe iscsi)) }, '' ],
    [ 'ipxe iSCSI node, firmware PXE, UEFI arch 7', { mac => $ipxe_iscsi{mac}, arch => 7 }, $first{ipxe}{uefi} ],
    [ 'ipxe iSCSI node, iPXE with iSCSI, UEFI',     { mac => $ipxe_iscsi{mac}, arch => 7, user_class => 'iPXE', ipxe => ipxe(qw(http efi iscsi)) }, '' ],
);

sub boot_file {
    my ($client) = @_;
    my $json = JSON::encode_json( { %$client, relay => '192.0.2.2', server => '192.0.2.1' } );
    open( my $fh, '-|', 'ip', 'netns', 'exec', $client_ns, $^X, "-I$FindBin::Bin/lib",
        '-MXCAT::Test::DHCP', '-e', 'XCAT::Test::DHCP::relay_discover_main(@ARGV)', $json )
      or die "Unable to run the DHCP client: $!";
    my $file = <$fh>;
    close($fh);
    chomp( $file //= 'NO-OFFER' );
    return $file;
}

sub check_rows {
    my ( $label, @rows ) = @_;
    is( boot_file( $_->[1] ), $_->[2], "$label: $_->[0]" ) for @rows;
}

sub wait_for_offers {
    my ( $pid, $log ) = @_;
    for ( 1 .. 20 ) {
        last unless process_running( $pid, \%children );
        return 1 if boot_file( { mac => $unknown, arch => 0 } ) ne 'NO-OFFER';
    }
    diag_file($log);
    BAIL_OUT('the DHCP server did not answer');
}

# ---- ISC ------------------------------------------------------------------------------------------
# The dhcpd AppArmor profile of Ubuntu reads only /etc/dhcp and writes only /var/lib/dhcp/dhcpd.leases*.
my $secret = 'eGNhdC10ZXN0LW9tYXBpLXNlY3JldC0wMQ==';
my $isc_dir = tempdir( DIR => -d '/etc/dhcp' ? '/etc/dhcp' : '/etc', CLEANUP => 1 );
my $leases = -d '/var/lib/dhcp' ? "/var/lib/dhcp/dhcpd.leases.xcat-test-$$" : "$isc_dir/dhcpd.leases";
END { unlink glob("$leases*") if $leases }

sub omshell {
    my ($commands) = @_;
    my $input = "$isc_dir/omshell.in";
    open( my $fh, '>', $input ) or die "Cannot create $input: $!";
    print {$fh} xCAT::DHCP::OmapiPolicy->omshell_preamble( $omapi, secret => $secret, port => 7911 ), "connect\n", $commands;
    close($fh) or die "Cannot close $input: $!";
    return scalar `ip netns exec $server_ns $omapi->{omshell_path} < $input 2>&1`;
}

sub start_isc {
    my $configuration = "$isc_dir/dhcpd.conf";
    open( my $fh, '>', $configuration ) or die "Cannot create $configuration: $!";
    print {$fh} "option conf-file code 209 = text;\n",
      "option space gpxe;\n",
      "option gpxe-encap-opts code 175 = encapsulate gpxe;\n",
      "option gpxe.bus-id code 177 = string;\n",
      @{ xCAT::DHCP::BootPolicy->isc_ipxe_feature_option_lines() },
      "option user-class-identifier code 77 = string;\n",
      "option client-architecture code 93 = unsigned integer 16;\n",
      "option www-server code 114 = string;\n",
      "default-lease-time 600;\nmax-lease-time 600;\nping-check false;\n",
      "omapi-port 7911;\n",
      "key $omapi->{key_name} {\n  algorithm $omapi->{algorithm};\n  secret \"$secret\";\n};\n",
      "omapi-key $omapi->{key_name};\n",
      "subnet 192.0.2.0 netmask 255.255.255.0 {\n",
      "  range 192.0.2.100 192.0.2.110;\n",
      @{ xCAT::DHCP::BootPolicy->isc_client_architecture_lines(
            next_server => '192.0.2.1',
            portsuffix  => '',
            net         => '192.0.2.0',
            prefix      => 24,
        ) },
      "}\n";
    close($fh) or die "Cannot close $configuration: $!";

    my $log = "$isc_dir/dhcpd.log";
    my $pid = start_daemon( undef, 'ip', $log, 'netns', 'exec', $server_ns, $dhcpd, '-f', '-d',
        '-cf', $configuration, '-lf', $leases, '-pf', "$isc_dir/dhcpd.pid", "${interface}s" );
    $children{$pid} = 1;
    return wait_for_offers( $pid, $log );
}

sub isc_hosts {
    my %common = ( loader_present => 1, next_server => '192.0.2.1', portsuffix => '' );
    my @hosts = (
        [ \%xnba,       { uefi => 1, currstate => 'install rhels9' } ],
        [ \%ipxe,       { uefi => 1, currstate => 'install rhels9' } ],
        [ \%xnba_san,   { uefi => 1, currstate => 'install rhels9' } ],
        [ \%ipxe_san,   { uefi => 1, currstate => 'install rhels9' } ],
        [ \%xnba_iscsi, { currstate => 'boot' } ],
        [ \%ipxe_iscsi, { currstate => 'boot' } ],
    );
    my $commands = '';
    for my $host (@hosts) {
        my ( $node, $opts ) = @$host;
        my $statements = xCAT::DHCP::BootPolicy->isc_node_boot_statements(
            %common, %$opts, netboot => $node->{netboot}, iscsi => $node->{iscsi}, node => $node->{name} );
        $commands .= "new host\nset name = \"$node->{name}\"\nset hardware-address = $node->{mac}\n"
          . "set hardware-type = 1\nset ip-address = $node->{ip}\nset statements = \"$statements\"\ncreate\nclose\n";
    }
    return omshell($commands);
}

if ( grep { $_ eq 'isc' } @backends ) {
    open( my $fresh, '>', $leases ) or die "Cannot create $leases: $!";
    close($fresh);
    start_isc();
    my $created = isc_hosts();
    unlike( $created, qr/can't|error|eof in string|unknown token|not connected/i, 'ISC: OMAPI creates the hosts' )
      or diag($created);
    check_rows( 'ISC', @node_rows, @network_rows, @san_rows, @iscsi_rows );

    # dhcpd reads the host statements back from dhcpd.leases, where it saved them without parentheses.
    stop_daemons( \%children );
    start_isc();
    check_rows( 'ISC after a restart', @node_rows, @san_rows, @iscsi_rows );
    stop_daemons( \%children );
}

# ---- Kea ------------------------------------------------------------------------------------------
if ( grep { $_ eq 'kea' } @backends ) {
    # The Kea classes get the local-boot guard from the plugin, as makedhcp gives them.
    local $ENV{XCATCFG} = $ENV{XCATCFG} || 'SQLite:/tmp';
    my $dhcp_plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/dhcp.pm";
    if ( -f $dhcp_plugin ) {
        require $dhcp_plugin;
    } else {
        require xCAT_plugin::dhcp;
    }
    my $kea_dir = tempdir( CLEANUP => 1 );
    chmod 0755, $kea_dir or die "Unable to make $kea_dir traversable: $!";
    # The kea-dhcp4 AppArmor profile of Ubuntu writes only the files of the system service. No profile
    # confines a copy of kea-dhcp4, so the test keeps its files in a temporary directory.
    my $kea_copy = "$kea_dir/kea-dhcp4";
    copy( $kea_dhcp4, $kea_copy ) or die "Unable to copy $kea_dhcp4: $!";
    chmod 0755, $kea_copy or die "Unable to make $kea_copy executable: $!";
    make_path( "$kea_dir/run", "$kea_dir/data" );
    local $ENV{KEA_CONTROL_SOCKET_DIR} = "$kea_dir/run";
    local $ENV{KEA_DHCP_DATA_DIR}      = "$kea_dir/data";
    local $ENV{KEA_PIDFILE_DIR}        = "$kea_dir/run";
    local $ENV{KEA_LOCKFILE_DIR}       = "$kea_dir/run";
    my $backend = xCAT::DHCP::Backend::Kea->new( kea_socket_dir => "$kea_dir/run" );

    # The server has the upstream loader files, as ipxe-xcat installs them.
    my %upstream = ( ipxe_bios => 1, ipxe_uefi => 1 );
    my $network_classes = xCAT::DHCP::BootPolicy->kea_xnba_network_classes(
        net => '192.0.2.0', prefix => 24, next_server => '192.0.2.1', %upstream );
    my $run_kea = sub {
        my ( $label, $option_defs, $globals, $xnba_files, $extra, @rows ) = @_;
        my $config = JSON::decode_json( $backend->render_dhcp4_config(
                {
                    interfaces       => ["${interface}s"],
                    'lease-database' => { type => 'memfile', name => "$kea_dir/data/kea-leases4.csv", persist => JSON::false },
                    'option-def'     => $option_defs,
                    'client-classes' => [
                        @$extra,
                        @{ xCAT::DHCP::BootPolicy->kea_xnba_node_classes(
                                %$xnba_files,
                                nodes => [
                                    map { { node => $_->{name}, mac => $_->{mac}, next_server => '192.0.2.1', netboot => $_->{netboot}, iscsi => $_->{iscsi} } }
                                      \%xnba, \%ipxe, \%xnba_san, \%ipxe_san
                                ],
                            ) },
                        @$globals,
                        @$network_classes,
                    ],
                    subnets => [
                        {
                            id           => 1,
                            subnet       => '192.0.2.0/24',
                            dynamicrange => '192.0.2.100-192.0.2.110',
                            next_server  => '192.0.2.1',
                            additional_client_classes => [ map { $_->{name} } @$network_classes ],
                        },
                    ],
                }
            ) );

        # The test sends relayed unicast packets, which need no raw socket.
        $config->{Dhcp4}{'interfaces-config'}{'dhcp-socket-type'} = 'udp';
        xCAT_plugin::dhcp::kea_apply_localboot_guard($config);
        my $path = "$kea_dir/kea-dhcp4.conf";
        open( my $fh, '>', $path ) or die "Cannot create $path: $!";
        print {$fh} JSON::encode_json($config);
        close($fh) or die "Cannot close $path: $!";

        my $log = "$kea_dir/kea-dhcp4.log";
        my $pid = start_daemon( undef, 'ip', $log, 'netns', 'exec', $server_ns, $kea_copy, '-c', $path );
        $children{$pid} = 1;
        wait_for_offers( $pid, $log );
        check_rows( $label, @rows );
        stop_daemons( \%children );
    };

    my @old_defs = ( { name => 'conf-file', code => 209, type => 'string', space => 'dhcp4' } );
    my @defs = ( @old_defs, @{ xCAT::DHCP::BootPolicy->kea_ipxe_option_defs() } );
    my $globals = xCAT::DHCP::BootPolicy->kea_client_classes(%upstream);
    my %xnba_files = ( xnba_kpxe => 1, xnba_efi => 1 );
    $run_kea->( 'Kea', \@defs, $globals, {%xnba_files}, [], @node_rows, @network_rows, @san_rows );

    # A SAN node in the boot state gets the loader of its method only on a client without iSCSI. A
    # client with iSCSI gets no boot file, though the subnet offers its network scripts.
    my $san_nodes = [ map { { node => $_->{name}, mac => $_->{mac}, netboot => $_->{netboot}, iscsi => 1, san_boot => 1 } } \%xnba_iscsi, \%ipxe_iscsi ];
    my @san_boot = (
        @{ xCAT::DHCP::BootPolicy->kea_xnba_node_classes( xnba_kpxe => 1, xnba_efi => 1, nodes => $san_nodes ) },
        xCAT::DHCP::BootPolicy->kea_localboot_client_class( macs => [ map { { node => $_->{node}, mac => $_->{mac}, san => 1 } } @$san_nodes ] ),
    );
    $run_kea->( 'Kea, SAN nodes in the boot state', \@defs, $globals, {%xnba_files}, \@san_boot, @kea_iscsi_rows );

    # Without the local xNBA UEFI file the UEFI clients of an xnba node still get that file, as in ISC, and
    # not the upstream loader and the discovery script that the global classes give unknown clients.
    $run_kea->( 'Kea, no xNBA UEFI file', \@defs, $globals, { xnba_kpxe => 1 }, [], map { [ "xnba node, $_->[0]", { mac => $xnba{mac}, %{ $_->[1] } }, $first{xnba}{uefi} ] } (
            [ 'firmware PXE, UEFI', { arch => 7 } ],
            [ 'iPXE with HTTP and EFI, UEFI', { arch => 7, user_class => 'iPXE', ipxe => ipxe(qw(http efi)) } ],
        ) );

    # With the local xNBA UEFI file only, the UEFI clients of an xnba node still get xNBA and then the
    # node script, as the global UEFI class gives only the upstream loader.
    $run_kea->( 'Kea, no xNBA BIOS file', \@defs, $globals, { xnba_efi => 1 }, [], map { [ "xnba node, $_->[0]", { mac => $xnba{mac}, %{ $_->[1] } }, $_->[2] ] } (
            [ 'firmware PXE, UEFI', { arch => 7 }, $first{xnba}{uefi} ],
            [ 'xNBA, UEFI arch 7', { arch => 7, user_class => 'xNBA', ipxe => ipxe(qw(http efi iscsi)) }, "http://192.0.2.1/tftpboot/xcat/xnba/nodes/$xnba{name}.uefi" ],
        ) );

    # makedhcp without -n adds the iPXE feature options to the configuration of an older makedhcp -n,
    # and keeps the x86 global classes that it wrote, which give xNBA to every client.
    my $upgraded = { 'option-def' => [@old_defs] };
    xCAT::DHCP::BootPolicy->kea_declare_ipxe_features($upgraded);
    my $xnba_test = "(option[77].exists and (option[77].text == 'xNBA' or option[77].hex == 0x784e4241 or substring(option[77].hex,1,4) == 'xNBA'))";
    my @old_globals = (
        { name => 'xcat-bios', test => "option[93].hex == 0x0000 and not ($xnba_test)", 'boot-file-name' => 'xcat/xnba.kpxe' },
        {
            name             => 'xcat-uefi-x64',
            test             => "(option[93].hex == 0x0007 or option[93].hex == 0x0009 or option[93].hex == 0x0010) and not ($xnba_test)",
            'boot-file-name' => 'xcat/xnba.efi',
        },
    );
    $run_kea->( 'Kea, upgraded', $upgraded->{'option-def'}, \@old_globals, {%xnba_files}, [], grep { $_->[0] =~ /^ipxe / } @node_rows, @san_rows );
}

done_testing();
