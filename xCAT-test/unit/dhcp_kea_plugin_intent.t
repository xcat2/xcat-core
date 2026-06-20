use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage, TestingAndDebugging::ProhibitNoStrict, TestingAndDebugging::ProhibitNoWarnings)
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Temp qw(tempdir);
use Test::More;

BEGIN {
    package xCAT::Table;
    our $networks;
    sub new {
        my ( $class, $name ) = @_;
        return $name eq 'networks' ? $networks : undef;
    }
    $INC{'xCAT/Table.pm'} = __FILE__;

    package xCAT::TableUtils;
    sub getTftpDir { return '/tftpboot'; }
    sub get_site_attribute { return; }
    $INC{'xCAT/TableUtils.pm'} = __FILE__;

    package xCAT::Utils;
    sub osver { return 'rhels9'; }
    sub runcmd { return; }
    $INC{'xCAT/Utils.pm'} = __FILE__;

    package xCAT::NetworkUtils;
    sub import {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::getipaddr"} = \&getipaddr;
    }
    sub getipaddr { return '10.0.0.1'; }
    sub my_ip_facing { return ( 0, '10.0.0.1' ); }
    sub thishostisnot { return 0; }
    sub ip_forwarding_enabled { return 0; }
    sub nodeonmynet { return 1; }
    $INC{'xCAT/NetworkUtils.pm'} = __FILE__;

    package xCAT::ServiceNodeUtils;
    sub getSNList { return; }
    $INC{'xCAT/ServiceNodeUtils.pm'} = __FILE__;

    package xCAT::NodeRange;
    $INC{'xCAT/NodeRange.pm'} = __FILE__;
}

my $source_dhcp_plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/dhcp.pm";
if ( -f $source_dhcp_plugin ) {
    require $source_dhcp_plugin;
} else {
    require xCAT_plugin::dhcp;
}

{
    package DHCPKeaIntentNetTable;
    sub new {
        my ( $class, $entry ) = @_;
        return bless { entry => $entry }, $class;
    }
    sub getAllAttribs {
        my ( $self, @attrs ) = @_;
        return { domain => $self->{entry}{domain} } if @attrs == 1 && $attrs[0] eq 'domain';
        return { %{ $self->{entry} } };
    }
    sub getAttribs {
        my ($self) = @_;
        return { %{ $self->{entry} } };
    }
    sub close { return; }
}

my %network_entry = (
    net          => '10.0.0.0',
    mask         => '255.255.255.0',
    mgtifname    => 'eth0',
    dynamicrange => '10.0.0.100-10.0.0.150',
    domain       => 'cluster.test',
    tftpserver   => '<xcatmaster>',
);

ok(xCAT_plugin::dhcp::dhcpd_sysconfig_uses_interface_key('opensuse-leap15.6'), 'openSUSE Leap head node uses SUSE dhcpd interface key');
ok(xCAT_plugin::dhcp::dhcpd_sysconfig_uses_interface_key('leap15.6'), 'Leap head node osver uses SUSE dhcpd interface key');
ok(!xCAT_plugin::dhcp::dhcpd_sysconfig_uses_interface_key('opensuse-tumbleweed'), 'generic openSUSE names do not enable Leap-specific dhcpd handling');

{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $fake_ip = "$tmpdir/ip";
    open(my $ip_fh, '>', $fake_ip) or die "Cannot write fake ip command: $!";
    print {$ip_fh} "#!/bin/sh\n";
    print {$ip_fh} "cat <<'EOF'\n";
    print {$ip_fh} "default via 192.168.1.1 dev eth1 proto dhcp\n";
    print {$ip_fh} "10.0.0.0/24 dev eth0 proto kernel scope link src 10.0.0.1\n";
    print {$ip_fh} "192.168.1.0/24 dev eth1 proto kernel scope link src 192.168.1.20\n";
    print {$ip_fh} "EOF\n";
    close($ip_fh);
    chmod 0755, $fake_ip;

    no warnings 'redefine';
    local *xCAT_plugin::dhcp::kea_command_path = sub {
        my ($command) = @_;
        return $fake_ip if $command eq 'ip';
        return;
    };

    is_deeply(
        [ xCAT_plugin::dhcp::local_ipv4_routes() ],
        [
            [ '0.0.0.0',     'eth1', '0.0.0.0',       'G' ],
            [ '10.0.0.0',    'eth0', '255.255.255.0', '' ],
            [ '192.168.1.0', 'eth1', '255.255.255.0', '' ],
        ],
        'local IPv4 route detection prefers ip route output'
    );
}

{
    my $tmpdir = tempdir(CLEANUP => 1);
    my $fake_netstat = "$tmpdir/netstat";
    open(my $netstat_fh, '>', $fake_netstat) or die "Cannot write fake netstat command: $!";
    print {$netstat_fh} "#!/bin/sh\n";
    print {$netstat_fh} "cat <<'EOF'\n";
    print {$netstat_fh} "Kernel IP routing table\n";
    print {$netstat_fh} "Destination     Gateway         Genmask         Flags   MSS Window  irtt Iface\n";
    print {$netstat_fh} "0.0.0.0         192.168.1.1     0.0.0.0         UG        0 0          0 eth1\n";
    print {$netstat_fh} "10.0.0.0        0.0.0.0         255.255.255.0   U         0 0          0 eth0\n";
    print {$netstat_fh} "EOF\n";
    close($netstat_fh);
    chmod 0755, $fake_netstat;

    no warnings 'redefine';
    local *xCAT_plugin::dhcp::kea_command_path = sub {
        my ($command) = @_;
        return $fake_netstat if $command eq 'netstat';
        return;
    };

    is_deeply(
        [ xCAT_plugin::dhcp::local_ipv4_routes() ],
        [
            [ '0.0.0.0',  'eth1', '0.0.0.0',       'UG' ],
            [ '10.0.0.0', 'eth0', '255.255.255.0', 'U' ],
        ],
        'local IPv4 route detection falls back to netstat output'
    );
}

{
    no warnings 'redefine';
    local *xCAT_plugin::dhcp::kea_ipv4_routes = sub {
        return (
            [ '10.0.0.0',    'eth0',  '255.255.255.0', '' ],
            [ '192.168.1.0', 'enp3s0', '255.255.255.0', '' ],
        );
    };
    local *xCAT_plugin::dhcp::kea_boot_client_classes = sub { return []; };
    local *xCAT_plugin::dhcp::kea_option_defs = sub { return []; };
    local *xCAT_plugin::dhcp::kea_global_option_data = sub { return []; };
    local *xCAT_plugin::dhcp::kea_dhcp_lease_time = sub { return 43200; };
    local *xCAT_plugin::dhcp::kea_control_agent_enabled = sub { return 0; };

    local $xCAT::Table::networks = DHCPKeaIntentNetTable->new( \%network_entry );

    my $intent = xCAT_plugin::dhcp::kea_build_dhcp4_intent( bless({}, 'DHCPKeaIntentBackend'), {} );

    is_deeply( $intent->{interfaces}, ['eth0'], 'empty dhcpinterfaces infers the local provisioning interface' );
    is( scalar @{ $intent->{subnets} }, 1, 'empty dhcpinterfaces still renders local routed subnet' );
    is( $intent->{subnets}[0]{subnet}, '10.0.0.0/24', 'rendered subnet comes from local route' );
}

{
    no warnings 'redefine';
    local *xCAT::NetworkUtils::thishostisnot = sub { return 1; };

    my $nettab = DHCPKeaIntentNetTable->new(
        {
            %network_entry,
            dhcpserver => 'service-node-a',
        }
    );

    my $subnet = xCAT_plugin::dhcp::kea_subnet4_intent( $nettab, '10.0.0.0', '255.255.255.0', 'eth0', 0, 1, 80 );
    ok( !defined( $subnet->{dynamicrange} ), 'non-owning Kea server does not render dynamic pool' );
}

{
    no warnings 'redefine';
    local *xCAT::NetworkUtils::thishostisnot = sub { return 0; };

    my $nettab = DHCPKeaIntentNetTable->new(
        {
            %network_entry,
            dhcpserver => 'service-node-a',
        }
    );

    my $subnet = xCAT_plugin::dhcp::kea_subnet4_intent( $nettab, '10.0.0.0', '255.255.255.0', 'eth0', 0, 1, 80 );
    is( $subnet->{dynamicrange}, $network_entry{dynamicrange}, 'owning Kea server renders dynamic pool' );
}

{
    # Regression: networks.nameservers / site.nameservers default to the
    # <xcatmaster> placeholder.  Kea D2 rejects a non-IP dns-servers ip-address,
    # so kea_build_ddns_intent must resolve <xcatmaster> to the management IP
    # facing the network (via my_ip_facing) before rendering DDNS domains.
    no warnings 'redefine';
    local *xCAT_plugin::dhcp::kea_ddns_enabled = sub { 1 };
    local *xCAT_plugin::dhcp::kea_ddns_key     = sub { ( 'HMAC-SHA256', 'YWJjMTIz' ); };

    local $xCAT::Table::networks = DHCPKeaIntentNetTable->new(
        {
            %network_entry,
            nameservers => '<xcatmaster>',
        }
    );

    my $ddns_intent = xCAT_plugin::dhcp::kea_build_ddns_intent();

    ok( $ddns_intent && !$ddns_intent->{error}, 'kea_build_ddns_intent succeeds with <xcatmaster> nameservers' );
    ok( scalar @{ $ddns_intent->{forward_domains} || [] }, 'kea_build_ddns_intent renders a forward DDNS domain' );
    ok( scalar @{ $ddns_intent->{reverse_domains} || [] }, 'kea_build_ddns_intent renders a reverse DDNS domain' );

    my @dns_ips =
      map { $_->{'ip-address'} }
      map { @{ $_->{'dns-servers'} || [] } }
      ( @{ $ddns_intent->{forward_domains} || [] }, @{ $ddns_intent->{reverse_domains} || [] } );

    ok( scalar @dns_ips, 'rendered DDNS domains carry dns-servers' );
    foreach my $ip (@dns_ips) {
        isnt( $ip, '<xcatmaster>', 'DDNS dns-server ip-address is never the literal <xcatmaster> placeholder' );
        is( $ip, '10.0.0.1', 'DDNS dns-server ip-address resolves to the management IP facing the network' );
        like( $ip, qr/^\d+\.\d+\.\d+\.\d+$/, 'DDNS dns-server ip-address is a valid IPv4 literal' );
    }
}

{
    # Regression: a service node (noderes.servicenode set, groups=service) must
    # get a Kea host reservation exactly like a regular compute node.  The Kea
    # reservation builder loops over every requested node without filtering on
    # service-node membership, so kea_build_node_reservations must emit an
    # ip/mac/hostname reservation whose next-server is resolved (via
    # my_ip_facing) to the management server that serves the node's subnet.
    package DHCPKeaResTable;
    sub new { my ( $class, $rows ) = @_; return bless { rows => $rows }, $class; }
    sub getNodesAttribs {
        my ( $self, $nodes, $attrs ) = @_;
        my %out;
        $out{$_} = [ $self->{rows}{$_} || {} ] for @$nodes;
        return \%out;
    }
    sub close { return; }

    package main;

    my %res_tables = (
        noderes  => DHCPKeaResTable->new( { 'svc01' => { netboot => 'xnba', servicenode => '192.168.201.20', tftpserver => '<xcatmaster>' } } ),
        chain    => DHCPKeaResTable->new( { 'svc01' => {} } ),
        nodetype => DHCPKeaResTable->new( { 'svc01' => { arch => 'x86_64', provmethod => 'install', os => 'rhels9' } } ),
        iscsi    => DHCPKeaResTable->new( {} ),
        mac      => DHCPKeaResTable->new( { 'svc01' => { mac => '42:d7:c0:a8:c9:15' } } ),
    );

    no warnings 'redefine';
    local *xCAT::Table::new = sub {
        my ( $class, $name ) = @_;
        return $res_tables{$name};
    };
    my $svc_getipaddr = sub {
        my ( $host, %opt ) = @_;
        return if $opt{OnlyV6};
        return '192.168.201.21';
    };
    local *xCAT::NetworkUtils::getipaddr = $svc_getipaddr;
    # dhcp.pm imports getipaddr into its own namespace at use-time, so override
    # the imported copy as well.
    local *xCAT_plugin::dhcp::getipaddr = $svc_getipaddr;
    local *xCAT::NetworkUtils::my_ip_facing = sub { return ( 0, '192.168.201.20' ); };
    local *xCAT_plugin::dhcp::ipIsDynamic = sub { return 0; };

    my @errors;
    local $xCAT_plugin::dhcp::callback = sub {
        my $resp = shift;
        push @errors, @{ $resp->{error} } if $resp->{error};
    };

    my $backend = bless {}, 'DHCPKeaResBackend';
    {
        package DHCPKeaResBackend;
        sub subnet_id_for_ip { return 1; }
    }

    my $reservations = xCAT_plugin::dhcp::kea_build_node_reservations( $backend, {}, ['svc01'] );

    is( scalar(@errors), 0, 'service node reservation builds without errors' );
    is( scalar( @{ $reservations || [] } ), 1, 'service node yields exactly one Kea host reservation' );
    my $r = $reservations->[0] || {};
    is( $r->{'ip-address'},  '192.168.201.21',    'service node reservation carries the node IP' );
    is( $r->{'hw-address'},  '42:d7:c0:a8:c9:15', 'service node reservation carries the node MAC' );
    is( $r->{hostname},      'svc01',             'service node reservation carries the hostname' );
    is( $r->{'next-server'}, '192.168.201.20',    'service node reservation next-server resolves to the serving management IP' );
}

done_testing();
