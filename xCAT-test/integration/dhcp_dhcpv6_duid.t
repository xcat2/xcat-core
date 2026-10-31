#!/usr/bin/env perl
# makedhcp reserves the IPv6 address of a node for the DHCPv6 client identifier that mac.duid selects.
# The test builds the reservations with the plugin from a private xCAT database, serves them with
# kea-dhcp6 and with dhcpd -6 in a network namespace, and sends DHCPv6 requests with each DUID from a
# second namespace, as UEFI firmware and an operating system send them.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/lib";

use File::Copy qw(copy);
use File::Path qw(make_path remove_tree);
use File::Temp qw(tempdir);
use IO::Handle;
use JSON ();
use POSIX ();
use Test::More;
use Time::HiRes ();

# The makedhcp step runs in the server namespace, where the node names resolve from its hosts file.
if ( @ARGV && $ARGV[0] eq '--makedhcp' ) {
    # The END blocks of the test belong to the process that created the namespaces.
    my $result = eval {
        die "The makedhcp step needs the private SQLite database of the test\n" unless ( $ENV{XCATCFG} // '' ) =~ /^SQLite:/;
        makedhcp_step( JSON::decode_json( $ARGV[1] ) );
    } || { errors => ["makedhcp died: $@"] };
    print JSON->new->canonical->encode($result), "\n";
    STDOUT->flush();
    POSIX::_exit(0);
}

# A private xCAT database. It must never be the database of the management node that runs the test.
my $work = tempdir( CLEANUP => 1 );
chmod 0755, $work or die "Unable to make $work traversable: $!";
$ENV{XCATCFG} = "SQLite:$work";

require xCAT::CommandUtils;
require xCAT::DHCP::OmapiPolicy;
require XCAT::Test::DHCP;
XCAT::Test::DHCP->import(qw(start_daemon process_running stop_daemons diag_file));

plan skip_all => 'root is required to run DHCP servers in network namespaces' unless $> == 0;
my ($dhcpd) = grep { -x $_ } qw(/usr/sbin/dhcpd /usr/local/sbin/dhcpd);
my $omapi = xCAT::DHCP::OmapiPolicy->settings( site_values => {} );
my $kea_dhcp6 = xCAT::CommandUtils::find_executable('kea-dhcp6');
my $kea_dhcp4 = xCAT::CommandUtils::find_executable('kea-dhcp4');
my @backends = ( ( $dhcpd && -x $omapi->{omshell_path} ? 'isc' : () ), ( $kea_dhcp6 && $kea_dhcp4 ? 'kea' : () ) );
plan skip_all => 'dhcpd with omshell, or kea-dhcp4 and kea-dhcp6, is required' unless @backends;

my $server_ns = "xcat-test-$$-s6";
my $client_ns = "xcat-test-$$-c6";
my $interface = "xd$$";
my ( @namespaces, %children );
END {
    stop_daemons( \%children );
    system( 'ip', 'netns', 'delete', $_ ) for @namespaces;
    remove_tree("/etc/netns/$server_ns") if $server_ns;
}
for my $namespace ( $server_ns, $client_ns ) {
    plan skip_all => 'ip netns is required' unless system("ip netns add $namespace >/dev/null 2>&1") == 0;
    push @namespaces, $namespace;
    # Without duplicate address detection the link-local addresses that DHCPv6 uses are ready at once.
    system( 'ip', 'netns', 'exec', $namespace, 'sysctl', '-qw', "net.ipv6.conf.$_.accept_dad=0" ) for qw(all default);
}
for my $command (
    [ $server_ns, 'link', 'set', 'lo', 'up' ],
    [ $client_ns, 'link', 'set', 'lo', 'up' ],
    [ $server_ns, 'link', 'add', "${interface}s", 'type', 'veth', 'peer', 'name', "${interface}c", 'netns', $client_ns ],
    [ $server_ns, 'address', 'add', '2001:db8:176::1/64', 'dev', "${interface}s", 'nodad' ],
    [ $server_ns, 'link', 'set', "${interface}s", 'up' ],
    [ $client_ns, 'link', 'set', "${interface}c", 'up' ],
  )
{
    my ( $namespace, @args ) = @$command;
    system( 'ip', '-n', $namespace, @args ) == 0 or BAIL_OUT("ip -n $namespace @args failed");
}

# IPv6 gives a link its link-local address once the link is operationally up, which follows the carrier.
for my $end ( [ $server_ns, "${interface}s" ], [ $client_ns, "${interface}c" ] ) {
    my ( $namespace, $link ) = @$end;
    my $ready;
    for ( 1 .. 100 ) {
        last if $ready = `ip -n $namespace -6 address show dev $link scope link` =~ /inet6 fe80:/;
        Time::HiRes::sleep(0.1);
    }
    BAIL_OUT("$link in $namespace has no link-local address") unless $ready;
}

# The nodes and their DHCPv6 clients. The UUIDs are synthetic, and the DUIDs are what a client sends:
# UEFI firmware the firmware order, a client that encodes the UUID itself the canonical order.
my $pool = qr/^2001:db8:176::1[0-9a-f]{3}$/;
my %node = (
    cn01 => { ip => '2001:db8:176::21', uuid => '12345678-1234-4bcd-9876-1234567890ab' },
    cn02 => { ip => '2001:db8:176::22', duid => '00:01:00:01:2e:4f:61:a0:02:00:00:00:00:22' },
    cn03 => { ip => '2001:db8:176::23', uuid => '12345678-1234-4bcd-9876-1234567890ad', duid => 'canonical' },
);
my %firmware = (
    cn01 => '00:04:78:56:34:12:34:12:cd:4b:98:76:12:34:56:78:90:ab',
    cn03 => '00:04:78:56:34:12:34:12:cd:4b:98:76:12:34:56:78:90:ad',
);
my %canonical = (
    cn01 => '00:04:12:34:56:78:12:34:4b:cd:98:76:12:34:56:78:90:ab',
    cn03 => '00:04:12:34:56:78:12:34:4b:cd:98:76:12:34:56:78:90:ad',
);
my $unknown = '00:04:00:00:00:00:00:00:40:00:80:00:00:00:00:00:00:99';
my $bootfile = sub { "tftp://[2001:db8:176::1]/boot/grub2/grub2-$_[0]" };

make_path("/etc/netns/$server_ns");
open( my $hosts, '>', "/etc/netns/$server_ns/hosts" ) or die "Cannot create the hosts file: $!";
print {$hosts} "127.0.0.1 localhost\n", ( map { "$node{$_}{ip} $_\n" } sort keys %node ), "192.0.2.24 cn04\n";
close($hosts) or die "Cannot close the hosts file: $!";

require xCAT::Table;
sub set_rows {
    my ( $table, $rows ) = @_;
    my $tab = xCAT::Table->new( $table, -create => 1 ) or die "Unable to open the $table table";
    $tab->setNodeAttribs( $_, $rows->{$_} ) for sort keys %$rows;
    $tab->close;
}
sub set_duid {
    my ( $name, $duid ) = @_;
    my $tab = xCAT::Table->new( 'mac', -create => 1 ) or die 'Unable to open the mac table';
    $tab->setNodeAttribs( $name, { duid => $duid } );
    $tab->close;
}
set_rows( 'nodelist', { map { $_ => { groups => 'all' } } keys %node } );
set_rows( 'mac',      { map { $_ => { mac => sprintf( '02:00:00:00:01:%s', substr( $_, -2 ) ), ( $node{$_}{duid} ? ( duid => $node{$_}{duid} ) : () ) } } keys %node } );
set_rows( 'vpd',      { map { $_ => { uuid => $node{$_}{uuid} } } grep { $node{$_}{uuid} } keys %node } );
set_rows( 'noderes',  { map { $_ => { netboot => 'grub2', tftpserver => '2001:db8:176::1' } } keys %node } );
{
    my $nettab = xCAT::Table->new( 'networks', -create => 1 ) or die 'Unable to open the networks table';
    $nettab->setAttribs( { netname => 'ci-dhcpv6' },
        { net => '2001:db8:176::', mask => '/64', mgtifname => "${interface}s", dynamicrange => '2001:db8:176::1000-2001:db8:176::1fff' } );
    $nettab->close;
}

# Run makedhcp in the server namespace: options for kea_process_request, or the ISC host commands.
sub makedhcp {
    my (%args) = @_;
    open( my $fh, '-|', 'ip', 'netns', 'exec', $server_ns, $^X, ( map { "-I$_" } grep { !ref } @INC ), $0, '--makedhcp',
        JSON::encode_json( { interface => "${interface}s", %args } ) )
      or die "Unable to run makedhcp: $!";
    local $/;
    my $output = <$fh>;
    close($fh);
    my $result = eval { JSON::decode_json( $output // '' ) } or BAIL_OUT("makedhcp gave no result: $output");
    return $result;
}

sub exchange {
    my ( $duid, %opts ) = @_;
    my $json = JSON::encode_json( { interface => "${interface}c", duid => $duid, request => $opts{request} ? 1 : 0 } );
    open( my $fh, '-|', 'ip', 'netns', 'exec', $client_ns, $^X, "-I$FindBin::Bin/lib",
        '-MXCAT::Test::DHCP', '-e', 'XCAT::Test::DHCP::dhcp6_exchange_main(@ARGV)', $json )
      or die "Unable to run the DHCPv6 client: $!";
    local $/;
    my $output = <$fh>;
    close($fh);
    my $result = eval { JSON::decode_json( $output // '' ) } or BAIL_OUT("the DHCPv6 client gave no result: $output");
    return $result;
}

# The address and bootfile-url that a client with $duid is offered, and the address of the Reply.
sub offered {
    my ( $duid, %opts ) = @_;
    my $result = exchange( $duid, %opts );
    my $advertise = $result->{advertise} || {};
    return ( $advertise->{address} // 'NO-ADDRESS', $advertise->{bootfile_url} // 'NO-BOOTFILE', ( $result->{reply} || {} )->{address} );
}

sub check_reserved {
    my ( $label, $duid, $name, %opts ) = @_;
    my ( $address, $url ) = offered($duid);
    is( $address, $node{$name}{ip}, "$label: the client gets the address of $name" );
    is( $url, $bootfile->($name), "$label: the client gets the bootfile-url of $name" ) unless $opts{no_bootfile};
}

sub check_pool {
    my ( $label, $duid ) = @_;
    my ( $address, $url ) = offered($duid);
    like( $address, $pool, "$label: the client gets a pool address" );
    is( $url, 'NO-BOOTFILE', "$label: the client gets no bootfile-url" );
}

sub wait_for_answer {
    my ( $pid, $log ) = @_;
    for ( 1 .. 20 ) {
        last unless process_running( $pid, \%children );
        return 1 if ( offered($unknown) )[0] ne 'NO-ADDRESS';
    }
    diag_file($log);
    BAIL_OUT('the DHCPv6 server did not answer');
}

# ---- Kea ------------------------------------------------------------------------------------------
if ( grep { $_ eq 'kea' } @backends ) {
    # Kea reads what it validates from /etc/kea under the AppArmor profile of Ubuntu.
    my $kea_dir = tempdir( ( -d '/etc/kea' && -w '/etc/kea' ? ( DIR => '/etc/kea' ) : () ), CLEANUP => 1 );
    chmod 0755, $kea_dir or die "Unable to make $kea_dir traversable: $!";
    make_path( "$kea_dir/run", "$kea_dir/data" );
    chmod 0750, "$kea_dir/run" or die "Unable to set the mode of $kea_dir/run: $!";
    local $ENV{KEA_CONTROL_SOCKET_DIR} = "$kea_dir/run";
    my $kea_copy = "$kea_dir/kea-dhcp6";
    copy( $kea_dhcp6, $kea_copy ) or die "Unable to copy $kea_dhcp6: $!";
    chmod 0755, $kea_copy or die "Unable to make $kea_copy executable: $!";
    my %kea = ( dhcp4 => "$kea_dir/kea-dhcp4.conf", dhcp6 => "$kea_dir/kea-dhcp6.conf", socket_dir => "$kea_dir/run" );
    my $leases = "$kea_dir/data/kea-leases6.csv";

    # Serve the configuration that makedhcp wrote, with the lease file of the test.
    my $serve = sub {
        stop_daemons( \%children );
        open( my $in, '<', $kea{dhcp6} ) or die "Cannot read $kea{dhcp6}: $!";
        my $config = JSON::decode_json( do { local $/; <$in> } );
        close($in);
        $config->{Dhcp6}{'lease-database'} = { type => 'memfile', name => $leases, persist => JSON::true, 'lfc-interval' => 0 };
        # Kea writes its own server DUID to /var/lib/kea unless it keeps it in memory.
        $config->{Dhcp6}{'server-id'} = { type => 'LL', persist => JSON::false };
        my $served = "$kea_dir/served-dhcp6.conf";
        open( my $out, '>', $served ) or die "Cannot create $served: $!";
        print {$out} JSON::encode_json($config);
        close($out) or die "Cannot close $served: $!";
        my $log = "$kea_dir/kea-dhcp6.log";
        local $ENV{KEA_DHCP_DATA_DIR} = "$kea_dir/data";
        local $ENV{KEA_PIDFILE_DIR}   = "$kea_dir/run";
        local $ENV{KEA_LOCKFILE_DIR}  = "$kea_dir/run";
        my $pid = start_daemon( undef, 'ip', $log, 'netns', 'exec', $server_ns, $kea_copy, '-c', $served );
        $children{$pid} = 1;
        return wait_for_answer( $pid, $log );
    };
    my $run = sub {
        my ( $label, @args ) = @_;
        my $result = makedhcp( backend => 'kea', kea => \%kea, @args );
        is_deeply( $result->{errors}, [], "Kea: $label reports no error" ) or diag( JSON::encode_json($result) );
        $serve->();
    };

    $run->( 'makedhcp -n', options => ['n'] );
    $run->( 'makedhcp', nodes => [ sort keys %node ] );

    # Without mac.duid the reservation keeps the UEFI behaviour: firmware order only.
    check_reserved( 'Kea, cn01 without duid, UEFI firmware', $firmware{cn01}, 'cn01' );
    check_pool( 'Kea, cn01 without duid, canonical client', $canonical{cn01} );
    check_reserved( 'Kea, cn02 with a DUID, its client', $node{cn02}{duid}, 'cn02' );
    check_reserved( 'Kea, cn03 with duid=canonical, canonical client', $canonical{cn03}, 'cn03' );
    check_pool( 'Kea, cn03 with duid=canonical, UEFI firmware', $firmware{cn03} );

    # cn04 has only an IPv4 address and the vpd.uuid of cn01. It needs no DHCPv6 reservation, so it
    # leaves the reservation of cn01 alone.
    set_rows( 'nodelist', { cn04 => { groups => 'all' } } );
    set_rows( 'mac',      { cn04 => { mac => '02:00:00:00:01:04' } } );
    set_rows( 'vpd',      { cn04 => { uuid => $node{cn01}{uuid} } } );
    set_rows( 'noderes',  { cn04 => { netboot => 'grub2', tftpserver => '2001:db8:176::1' } } );
    $run->( 'makedhcp of cn01 and of an IPv4-only node with its vpd.uuid', nodes => [ 'cn01', 'cn04' ] );
    check_reserved( 'Kea, cn01 beside an IPv4-only node with its vpd.uuid, UEFI firmware', $firmware{cn01}, 'cn01' );

    # One identity across the boot stages. Firmware and the operating system of cn03 send different
    # DUIDs, and only the operating system matches. The firmware lease is a pool address, so it never
    # holds the reserved one.
    my ( undef, undef, $firmware_lease ) = offered( $firmware{cn03}, request => 1 );
    like( $firmware_lease // '', $pool, 'Kea, cn03: the firmware leases a pool address' );
    my ( undef, undef, $os_lease ) = offered( $canonical{cn03}, request => 1 );
    is( $os_lease, $node{cn03}{ip}, 'Kea, cn03: the operating system then leases the reserved address' );

    # A client that keeps the firmware DUID, as the DHCPv6 lease file that xCAT writes on RHEL 6 does,
    # renews the lease of the firmware.
    my ( undef, undef, $uefi_lease ) = offered( $firmware{cn01}, request => 1 );
    is( $uefi_lease, $node{cn01}{ip}, 'Kea, cn01: the firmware leases the reserved address' );
    my ( undef, undef, $same_lease ) = offered( $firmware{cn01}, request => 1 );
    is( $same_lease, $node{cn01}{ip}, 'Kea, cn01: a later client with the same DUID gets the same address' );

    # A changed duid replaces the reservation, as nodeset does when it runs makedhcp again.
    set_duid( 'cn01', 'canonical' );
    $run->( 'makedhcp after duid=canonical', nodes => ['cn01'] );
    check_pool( 'Kea, cn01 after duid=canonical, UEFI firmware', $firmware{cn01} );

    # The firmware still holds a lease on the reserved address. Kea revokes it and gives the address
    # to the new DUID, and the old DUID gets a pool address.
    check_reserved( 'Kea, cn01 after duid=canonical, canonical client', $canonical{cn01}, 'cn01' );
    my ( undef, undef, $new_lease ) = offered( $canonical{cn01}, request => 1 );
    is( $new_lease, $node{cn01}{ip}, 'Kea, cn01 after duid=canonical: the canonical client leases the reserved address' );
    my ( undef, undef, $old_lease ) = offered( $firmware{cn01}, request => 1 );
    like( $old_lease // '', $pool, 'Kea, cn01 after duid=canonical: the firmware then leases a pool address' );

    open( my $in, '<', $kea{dhcp6} ) or die "Cannot read $kea{dhcp6}: $!";
    my $config = JSON::decode_json( do { local $/; <$in> } );
    close($in);
    my @cn01 = grep { $_->{hostname} eq 'cn01' } map { @{ $_->{reservations} || [] } } @{ $config->{Dhcp6}{subnet6} };
    is_deeply( [ map { $_->{duid} } @cn01 ], [ $canonical{cn01} ], 'Kea: makedhcp leaves one reservation for cn01' );

    # An invalid duid is an error, and the node keeps the reservation that it had.
    set_duid( 'cn02', 'not-a-duid' );
    my $refused = makedhcp( backend => 'kea', kea => \%kea, nodes => ['cn02'] );
    is_deeply( $refused->{errors}, ["The duid attribute of cn02 is 'not-a-duid', but only firmware, canonical, or a DUID of colon-separated hexadecimal octets is supported."],
        'Kea: makedhcp reports an invalid duid' );
    $serve->();
    check_reserved( 'Kea, cn02 after an invalid duid, the client of its old DUID', $node{cn02}{duid}, 'cn02' );
    set_duid( 'cn02', $node{cn02}{duid} );

    # makedhcp -d removes the reservation of the selected DUID.
    $run->( 'makedhcp -d', nodes => [ 'cn01', 'cn03' ], options => ['d'] );
    check_pool( 'Kea, cn01 after makedhcp -d, canonical client', $canonical{cn01} );
    check_pool( 'Kea, cn03 after makedhcp -d, canonical client', $canonical{cn03} );
    check_reserved( 'Kea, cn02 after makedhcp -d of other nodes, its client', $node{cn02}{duid}, 'cn02' );

    stop_daemons( \%children );
}

# ---- ISC ------------------------------------------------------------------------------------------
if ( grep { $_ eq 'isc' } @backends ) {
    set_duid( 'cn01', '' );
    # The dhcpd AppArmor profile of Ubuntu reads only /etc/dhcp and writes only /var/lib/dhcp/dhcpd6.leases*.
    my $secret  = 'eGNhdC10ZXN0LW9tYXBpLXNlY3JldC0wMQ==';
    my $isc_dir = tempdir( DIR => -d '/etc/dhcp' ? '/etc/dhcp' : '/etc', CLEANUP => 1 );
    my $leases  = -d '/var/lib/dhcp' ? "/var/lib/dhcp/dhcpd6.leases.xcat-test-$$" : "$isc_dir/dhcpd6.leases";
    END { unlink glob("$leases*") if $leases }
    open( my $fresh, '>', $leases ) or die "Cannot create $leases: $!";
    close($fresh);
    my $configuration = "$isc_dir/dhcpd6.conf";
    open( my $fh, '>', $configuration ) or die "Cannot create $configuration: $!";
    print {$fh} "#xCAT generated dhcp configuration\n",
      "ddns-update-style interim;\nignore client-updates;\n",
      "omapi-port 7912;\n",
      "key $omapi->{key_name} {\n  algorithm $omapi->{algorithm};\n  secret \"$secret\";\n};\n",
      "omapi-key $omapi->{key_name};\n",
      "subnet6 2001:db8:176::/64 {\n",
      "  authoritative;\n  default-lease-time 600;\n  max-lease-time 600;\n",
      "  range6 2001:db8:176::1000 2001:db8:176::1fff;\n",
      "}\n";
    close($fh) or die "Cannot close $configuration: $!";

    my $start = sub {
        stop_daemons( \%children );
        my $log = "$isc_dir/dhcpd6.log";
        my $pid = start_daemon( undef, 'ip', $log, 'netns', 'exec', $server_ns, $dhcpd, '-6', '-f', '-d',
            '-cf', $configuration, '-lf', $leases, '-pf', "$isc_dir/dhcpd6.pid", "${interface}s" );
        $children{$pid} = 1;
        return wait_for_answer( $pid, $log );
    };
    my $omshell = sub {
        my ($commands) = @_;
        my $input = "$isc_dir/omshell.in";
        open( my $in, '>', $input ) or die "Cannot create $input: $!";
        print {$in} xCAT::DHCP::OmapiPolicy->omshell_preamble( $omapi, secret => $secret, port => 7912 ), "connect\n", $commands;
        close($in) or die "Cannot close $input: $!";
        return scalar `ip netns exec $server_ns $omapi->{omshell_path} < $input 2>&1`;
    };
    my $run = sub {
        my ( $label, @nodes ) = @_;
        my $result = makedhcp( backend => 'isc', nodes => \@nodes );
        is_deeply( $result->{errors}, [], "ISC: $label reports no error" ) or diag( JSON::encode_json($result) );
        # makedhcp removes each conflicting host before it creates one, so "not found" answers are expected.
        my $output = $omshell->( $result->{commands} );
        unlike( $output, qr/not connected|bad key|eof in string|unknown token|can't create/i, "ISC: omshell connects and creates the hosts of $label" )
          or diag($output);
    };

    $start->();
    $run->( 'makedhcp', sort keys %node );
    for my $restart ( 0, 1 ) {
        my $when = $restart ? ', after a restart' : '';
        check_reserved( "ISC, cn01 without duid$when, UEFI firmware", $firmware{cn01}, 'cn01', no_bootfile => 1 );
        check_pool( "ISC, cn01 without duid$when, canonical client", $canonical{cn01} );
        check_reserved( "ISC, cn02 with a DUID$when, its client", $node{cn02}{duid}, 'cn02', no_bootfile => 1 );
        check_reserved( "ISC, cn03 with duid=canonical$when, canonical client", $canonical{cn03}, 'cn03', no_bootfile => 1 );
        check_pool( "ISC, cn03 with duid=canonical$when, UEFI firmware", $firmware{cn03} );
        # dhcpd reads the OMAPI hosts back from its lease file.
        $start->() unless $restart;
    }

    my ( undef, undef, $firmware_lease ) = offered( $firmware{cn03}, request => 1 );
    like( $firmware_lease // '', $pool, 'ISC, cn03: the firmware leases a pool address' );
    my ( undef, undef, $os_lease ) = offered( $canonical{cn03}, request => 1 );
    is( $os_lease, $node{cn03}{ip}, 'ISC, cn03: the operating system then leases the reserved address' );

    # A changed duid replaces the host, and dhcpd gives its fixed address to the new DUID at once.
    my ( undef, undef, $uefi_lease ) = offered( $firmware{cn01}, request => 1 );
    is( $uefi_lease, $node{cn01}{ip}, 'ISC, cn01: the firmware leases the reserved address' );
    set_duid( 'cn01', 'canonical' );
    $run->( 'makedhcp after duid=canonical', 'cn01' );
    check_reserved( 'ISC, cn01 after duid=canonical, canonical client', $canonical{cn01}, 'cn01', no_bootfile => 1 );
    check_pool( 'ISC, cn01 after duid=canonical, UEFI firmware', $firmware{cn01} );

    set_duid( 'cn01', 'not-a-duid' );
    my $refused = makedhcp( backend => 'isc', nodes => ['cn01'] );
    is_deeply( $refused->{errors}, ["cn01: The duid attribute of cn01 is 'not-a-duid', but only firmware, canonical, or a DUID of colon-separated hexadecimal octets is supported."],
        'ISC: makedhcp reports an invalid duid' );
    is( $refused->{commands}, '', 'ISC: makedhcp sends no OMAPI command for a node with an invalid duid' );
    $omshell->( $refused->{commands} ) if length( $refused->{commands} // '' );
    check_reserved( 'ISC, cn01 after an invalid duid, the client of its old DUID', $canonical{cn01}, 'cn01', no_bootfile => 1 );
    stop_daemons( \%children );
}

done_testing();

# ---- The makedhcp step ------------------------------------------------------------------------------
sub makedhcp_step {
    my ($args) = @_;

    # xcatd loads xCAT::DBobjUtils before any plugin runs.
    require xCAT::DBobjUtils;
    my $plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/dhcp.pm";
    if ( -f $plugin ) {
        require $plugin;
    } else {
        require xCAT_plugin::dhcp;
    }
    my ( @errors, @warnings );
    no warnings 'once';
    local $xCAT_plugin::dhcp::callback = sub {
        my ($resp) = @_;
        push @errors,   @{ $resp->{error}   || [] };
        push @warnings, @{ $resp->{warning} || [] };
        foreach my $node ( @{ $resp->{node} || [] } ) {
            push @errors,   map { "$node->{name}[0]: $_" } @{ $node->{error}   || [] };
            push @warnings, map { "$node->{name}[0]: $_" } @{ $node->{warning} || [] };
        }
    };

    my %result;
    if ( $args->{backend} eq 'kea' ) {
        require xCAT::DHCP::Backend::Kea;
        my $backend = XCATTestKeaBackend->new(
            dhcp4_config_file => $args->{kea}{dhcp4},
            dhcp6_config_file => $args->{kea}{dhcp6},
            kea_socket_dir    => $args->{kea}{socket_dir},
        );
        my %opt = map { $_ => 1 } @{ $args->{options} || [] };
        xCAT_plugin::dhcp::kea_process_request( $backend, { node => $args->{nodes} }, \%opt, { $args->{interface} => 1 }, 0 );
    } else {
        my $duids = xCAT_plugin::dhcp::dhcp6_client_duids( $args->{nodes} );
        $result{commands} = join '', map { xCAT_plugin::dhcp::addnode6( $_, $duids->{$_} ) // '' } @{ $args->{nodes} };
    }
    return { %result, errors => \@errors, warnings => \@warnings };
}

# The test serves the configuration itself: makedhcp starts no system service.
{
    package XCATTestKeaBackend;
    use parent -norequire, 'xCAT::DHCP::Backend::Kea';
    sub restart_services { return { services => [] }; }
    sub check_services   { return { services => [] }; }
}
