use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage, TestingAndDebugging::ProhibitNoStrict, TestingAndDebugging::ProhibitNoWarnings)
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";

use File::Temp qw(tempdir);
use Socket ();
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
    sub formatNetmask {
        my ( $mask, $orig_type, $new_type ) = @_;
        my $mask_number;

        if ( $orig_type == 0 ) {
            $mask_number = unpack( 'N', Socket::inet_aton($mask) );
        } elsif ( $orig_type == 1 ) {
            $mask_number = ( 2**$mask - 1 ) << ( 32 - $mask );
        } else {
            return;
        }

        return Socket::inet_ntoa( pack( 'N', $mask_number ) ) if $new_type == 0;
        if ( $new_type == 1 ) {
            my $binary_mask = unpack( 'B32', pack( 'N', $mask_number ) );
            return $binary_mask =~ tr/1/1/;
        }
        return;
    }
    sub isInSameSubnet {
        my ( $ip1, $ip2, $mask, $mask_type ) = @_;
        return unless $mask_type == 0;

        my $mask_number = unpack( 'N', Socket::inet_aton($mask) );
        my $ip1_number  = unpack( 'N', Socket::inet_aton($ip1) );
        my $ip2_number  = unpack( 'N', Socket::inet_aton($ip2) );
        return ( $ip1_number & $mask_number ) == ( $ip2_number & $mask_number );
    }
    $INC{'xCAT/NetworkUtils.pm'} = __FILE__;

    package xCAT::ServiceNodeUtils;
    sub getSNList { return; }
    $INC{'xCAT/ServiceNodeUtils.pm'} = __FILE__;

    package xCAT::NodeRange;
    $INC{'xCAT/NodeRange.pm'} = __FILE__;
}

require xCAT::Utils;
{
    no warnings 'redefine';
    *xCAT::Utils::osver = sub { return 'rhels9'; };
    *xCAT::Utils::runcmd = sub { return; };
}

my $source_dhcp_plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/dhcp.pm";
if ( -f $source_dhcp_plugin ) {
    require $source_dhcp_plugin;
} else {
    require xCAT_plugin::dhcp;
}
require xCAT::DHCP::Backend::Kea;

{
    package DHCPKeaIntentBackend;
    our @ISA = ('xCAT::DHCP::Backend::Kea');
    sub host_cmds_hook_path { return '/test/libdhcp_host_cmds.so'; }
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
    my $tmpdir = tempdir(CLEANUP => 1);
    my $fake_ip = "$tmpdir/ip";
    open(my $ip_fh, '>', $fake_ip) or die "Cannot write fake ip command: $!";
    print {$ip_fh} "#!/bin/sh\n";
    print {$ip_fh} "cat <<'EOF'\n";
    print {$ip_fh} "0.0.0.0/0 dev eth0 proto kernel scope link\n";
    print {$ip_fh} "128.0.0.0/1 dev eth1 proto kernel scope link\n";
    print {$ip_fh} "192.0.2.0/24 dev eth24 proto kernel scope link\n";
    print {$ip_fh} "198.51.100.7/32 dev eth32 proto kernel scope link\n";
    print {$ip_fh} "203.0.113.0/not-a-prefix dev invalid proto kernel scope link\n";
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
            [ '0.0.0.0',      'eth0',  '0.0.0.0',         '' ],
            [ '128.0.0.0',    'eth1',  '128.0.0.0',       '' ],
            [ '192.0.2.0',    'eth24', '255.255.255.0',   '' ],
            [ '198.51.100.7', 'eth32', '255.255.255.255', '' ],
        ],
        'local IPv4 route detection converts boundary prefixes and ignores malformed prefixes'
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
    local *xCAT::NetworkUtils::thishostisnot = sub { return 0; };

    my @prefix_cases = (
        [ '0.0.0.0',         '0.0.0.0',         0 ],
        [ '128.0.0.0',       '128.0.0.0',       1 ],
        [ '192.0.2.0',       '255.255.255.0',  24 ],
        [ '198.51.100.7',    '255.255.255.255', 32 ],
    );

    foreach my $case (@prefix_cases) {
        my ( $net, $mask, $prefix ) = @$case;
        my $nettab = DHCPKeaIntentNetTable->new(
            {
                %network_entry,
                net          => $net,
                mask         => $mask,
                dynamicrange => undef,
                gateway      => undef,
            }
        );
        my $subnet = xCAT_plugin::dhcp::kea_subnet4_intent( $nettab, $net, $mask, 'eth0', 0, 1, 80 );
        is( $subnet->{subnet}, "$net/$prefix", "$mask renders as prefix $prefix" );
    }
}

{
    no warnings 'redefine';
    local *xCAT::NetworkUtils::thishostisnot = sub { return 0; };

    my $same_subnet_table = DHCPKeaIntentNetTable->new(
        {
            %network_entry,
            gateway => '10.0.0.254',
        }
    );
    my $same_subnet = xCAT_plugin::dhcp::kea_subnet4_intent(
        $same_subnet_table, '10.0.0.0', '255.255.255.0', 'eth0', 0, 1, 80
    );
    ok( !$same_subnet->{error}, 'gateway in the subnet remains valid' );

    my $different_subnet_table = DHCPKeaIntentNetTable->new(
        {
            %network_entry,
            gateway => '192.0.2.1',
        }
    );
    my $different_subnet = xCAT_plugin::dhcp::kea_subnet4_intent(
        $different_subnet_table, '10.0.0.0', '255.255.255.0', 'eth0', 0, 1, 80
    );
    is(
        $different_subnet->{error},
        'Specified gateway 192.0.2.1 is not valid for 10.0.0.0/255.255.255.0, must be on same network',
        'gateway outside the subnet keeps the existing error'
    );
}

{
    no warnings 'redefine';
    local *xCAT_plugin::dhcp::kea_ipv4_routes = sub {
        return ([ '10.0.0.0', 'eth0', '255.255.255.0', '' ]);
    };
    local *xCAT_plugin::dhcp::kea_boot_client_classes = sub { return []; };
    local *xCAT_plugin::dhcp::kea_option_defs = sub { return []; };
    local *xCAT_plugin::dhcp::kea_global_option_data = sub { return []; };
    local *xCAT_plugin::dhcp::kea_dhcp_lease_time = sub { return 43200; };
    local *xCAT_plugin::dhcp::kea_control_agent_enabled = sub { return 1; };

    my $backend = DHCPKeaIntentBackend->new(kea_socket_dir => '/run/kea-xcat-test');

    local $xCAT::Table::networks = DHCPKeaIntentNetTable->new( \%network_entry );
    my $dhcp4_intent = xCAT_plugin::dhcp::kea_build_dhcp4_intent( $backend, { eth0 => 1 } );
    is(
        $dhcp4_intent->{'control-socket'}{'socket-name'},
        '/run/kea-xcat-test/kea4-ctrl-socket',
        'DHCPv4 intent uses the backend-selected Control Agent socket path'
    );

    local $xCAT::Table::networks = DHCPKeaIntentNetTable->new(
        {
            %network_entry,
            net          => 'fd00::/64',
            dynamicrange => undef,
        }
    );
    my $dhcp6_intent = xCAT_plugin::dhcp::kea_build_dhcp6_intent( $backend, { eth0 => 1 } );
    is(
        $dhcp6_intent->{'control-socket'}{'socket-name'},
        '/run/kea-xcat-test/kea6-ctrl-socket',
        'DHCPv6 intent uses the backend-selected Control Agent socket path'
    );
}

{
    package DHCPKeaRegenerateBackend;
    sub load_dhcp4_config {
        $_[0]->{loads}++;
        return { error => 'existing Kea configuration must not be loaded by makedhcp -n' };
    }
    sub write_dhcp4_config {
        my ( $self, $intent, %opts ) = @_;
        $self->{written_intent} = $intent;
        $self->{write_options}  = \%opts;
        return {};
    }
    sub restart_services {
        my ( $self, %opts ) = @_;
        $self->{restart_options} = \%opts;
        return {};
    }

    package main;

    my $network_intent = {
        interfaces       => ['eth0'],
        'client-classes' => [ { name => 'xcat-generic' } ],
        subnets           => [ { id => 1, subnet => '192.0.2.0/24' } ],
    };

    no warnings 'redefine';
    local *xCAT_plugin::dhcp::kea_build_dhcp4_intent = sub { return $network_intent; };
    local *xCAT_plugin::dhcp::kea_build_dhcp6_intent = sub { return { subnets => [] }; };
    local *xCAT_plugin::dhcp::kea_build_ddns_intent = sub { return; };
    local *xCAT_plugin::dhcp::kea_control_agent_enabled = sub { return 0; };
    local *xCAT::MsgUtils::message = sub { return; };
    local *xCAT::MsgUtils::trace = sub { return; };
    local $::XCATSITEVALS{externaldhcpservers};

    my @errors;
    my $capture_response = sub {
        my $response = shift;
        push @errors, @{ $response->{error} || [] };
    };
    my $saved_umask = umask;
    my $saved_ignorecase = $Getopt::Long::ignorecase;
    {
        local @ARGV;
        xCAT_plugin::dhcp::process_request(
            {
                _xcatpreprocessed => [0],
                arg               => [ '-q', '-a' ],
            },
            $capture_response
        );
    }
    umask $saved_umask;
    $Getopt::Long::ignorecase = $saved_ignorecase;
    Getopt::Long::Configure('pass_through');
    @errors = ();

    my $backend = bless { loads => 0 }, 'DHCPKeaRegenerateBackend';
    xCAT_plugin::dhcp::kea_process_request( $backend, {}, { n => 1 }, { eth0 => 1 }, 0 );

    is( $backend->{loads}, 0, 'makedhcp -n does not parse the previous Kea configuration' );
    is_deeply(
        $backend->{written_intent},
        $network_intent,
        'makedhcp -n writes only the newly generated network intent'
    );
    ok( $backend->{write_options}{backup_existing}, 'makedhcp -n backs up the replaced Kea configuration' );
    ok( $backend->{restart_options}{enable}, 'makedhcp -n enables and restarts Kea after replacement' );
    is_deeply( \@errors, [], 'makedhcp -n replacement completes without errors' );
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

my @normalized_mac_cases = (
    [ 'Aa:Bb:Cc:Dd:Ee:Ff',          'aa:bb:cc:dd:ee:ff',          'six-octet colon MAC is lowercased' ],
    [ '01-23-45-67-89-AB-CD',       '01:23:45:67:89:ab:cd',       'seven-octet hyphen MAC is canonicalized' ],
    [ '01:23:45:67:89:AB:CD:EF',    '01:23:45:67:89:ab:cd:ef',    'eight-octet colon MAC is lowercased' ],
    [ '01-23-45-67-89-AB-CD-EF-01', '01:23:45:67:89:ab:cd:ef:01', 'nine-octet hyphen MAC is canonicalized' ],
);

foreach my $case (@normalized_mac_cases) {
    my ( $input, $expected, $description ) = @$case;
    is( xCAT_plugin::dhcp::kea_normalize_mac($input), $expected, $description );
}

my @invalid_mac_cases = (
    [ undef,                              'undefined MAC is rejected' ],
    [ '',                                 'empty MAC is rejected' ],
    [ '00:11:22:33:44',                   'five-octet MAC is rejected' ],
    [ '00:11:22:33:44:55:66:77:88:99',    'ten-octet MAC is rejected' ],
    [ '00:11-22:33:44:55',                'mixed MAC separators are rejected' ],
    [ 'gg:11:22:33:44:55',                'non-hexadecimal MAC is rejected' ],
    [ '001122334455',                      'compact MAC is rejected' ],
    [ "00:11:22:33:44:55\n",              'MAC with a trailing newline is rejected' ],
    [ ' 00:11:22:33:44:55',               'MAC with leading whitespace is rejected' ],
);

foreach my $case (@invalid_mac_cases) {
    my ( $input, $description ) = @$case;
    ok( !defined( xCAT_plugin::dhcp::kea_normalize_mac($input) ), $description );
}

{
    my %mac_tables = (
        noderes => DHCPKeaResTable->new(
            {
                macnode  => {},
                duidnode => {},
            }
        ),
        chain    => DHCPKeaResTable->new( {} ),
        nodetype => DHCPKeaResTable->new( {} ),
        iscsi    => DHCPKeaResTable->new( {} ),
        mac      => DHCPKeaResTable->new(
            {
                macnode => {
                    mac => 'Aa-Bb-Cc-Dd-Ee-Ff!node6|01-23-45-67-89-AB-CD-EF-01!node9|not-a-mac!badmac',
                },
                duidnode => {
                    mac => 'not-a-mac!duid-alias',
                },
            }
        ),
        vpd => DHCPKeaResTable->new(
            {
                duidnode => {
                    uuid => '00112233-4455-6677-8899-aabbccddeeff',
                },
            }
        ),
    );

    no warnings 'redefine';
    local *xCAT::Table::new = sub {
        my ( $class, $name ) = @_;
        return $mac_tables{$name};
    };
    local *xCAT_plugin::dhcp::getipaddr = sub {
        my ( $host, %opt ) = @_;
        return '2001:db8::25' if $opt{OnlyV6};
        return '192.0.2.25';
    };
    local *xCAT_plugin::dhcp::ipIsDynamic = sub { return 0; };
    local *xCAT_plugin::dhcp::kea_next_server_for_node = sub { return ( '192.0.2.1', '192.0.2.1' ); };
    local *xCAT_plugin::dhcp::kea_boot_for_node = sub { return {}; };

    my $backend = bless {}, 'DHCPKeaMacBackend';
    {
        package DHCPKeaMacBackend;
        sub subnet_id_for_ip { return 1; }
    }

    my @errors;
    my $capture_error = sub {
        my $resp = shift;
        push @errors, @{ $resp->{error} } if $resp->{error};
    };
    local *xCAT::MsgUtils::message = sub { return; };
    local *xCAT::MsgUtils::trace = sub { return; };
    my $saved_umask = umask;
    my $saved_ignorecase = $Getopt::Long::ignorecase;
    {
        local @ARGV;

        # A conflicting option pair initializes the plugin's lexical callback
        # and returns before any DHCP backend or service work begins.
        xCAT_plugin::dhcp::process_request(
            {
                _xcatpreprocessed => [0],
                arg               => [ '-q', '-a' ],
            },
            $capture_error
        );
    }
    umask $saved_umask;
    $Getopt::Long::ignorecase = $saved_ignorecase;
    Getopt::Long::Configure('pass_through');

    my $reservations4 = xCAT_plugin::dhcp::kea_build_node_reservations( $backend, {}, [ 'macnode', 'duidnode' ] );
    is_deeply(
        [ map { $_->{'hw-address'} } @$reservations4 ],
        [ 'aa:bb:cc:dd:ee:ff', '01:23:45:67:89:ab:cd:ef:01' ],
        'IPv4 reservations use canonical MAC addresses and omit malformed entries'
    );
    is_deeply(
        \@errors,
        [ 'Invalid mac address not-a-mac for macnode', 'Invalid mac address not-a-mac for duidnode' ],
        'IPv4 reservations preserve invalid-MAC errors'
    );

    @errors = ();
    my $reservations6 = xCAT_plugin::dhcp::kea_build_node_reservations6( $backend, {}, [ 'macnode', 'duidnode' ] );
    is_deeply(
        [ map { $_->{'hw-address'} } @$reservations6 ],
        [ 'aa:bb:cc:dd:ee:ff', '01:23:45:67:89:ab:cd:ef:01' ],
        'IPv6 reservations use canonical MAC addresses and omit malformed entries'
    );
    is_deeply(
        \@errors,
        [ 'Invalid mac address not-a-mac for macnode', 'Invalid mac address not-a-mac for duidnode' ],
        'IPv6 reservations report malformed MACs even when a DUID is available'
    );
    ok( !grep( { $_->{duid} } @$reservations6 ), 'malformed MAC does not create a DUID-based IPv6 reservation' );

    my $matches = xCAT_plugin::dhcp::kea_reservation_matches_for_nodes( [ 'macnode', 'duidnode' ] );
    is_deeply(
        [ map { $_->{'hw-address'} } grep { $_->{'hw-address'} } @$matches ],
        [ 'aa:bb:cc:dd:ee:ff', '01:23:45:67:89:ab:cd:ef:01' ],
        'query and delete matches use canonical MAC addresses and omit malformed entries'
    );
    ok(
        grep( { ( $_->{hostname} || '' ) eq 'badmac' } @$matches ),
        'query and delete retain alias matches when the associated MAC is malformed'
    );
    ok(
        grep( { ( $_->{duid} || '' ) eq '00:04:00:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff' } @$matches ),
        'query and delete retain DUID matches when the associated MAC is malformed'
    );
}

{
    my %lookup_tables = (
        noderes => DHCPKeaResTable->new(
            {
                unresolved01 => {},
                valid01      => {},
            }
        ),
        chain    => DHCPKeaResTable->new( {} ),
        nodetype => DHCPKeaResTable->new( {} ),
        iscsi    => DHCPKeaResTable->new( {} ),
        mac      => DHCPKeaResTable->new(
            {
                unresolved01 => { mac => '00:11:22:33:44:55' },
                valid01      => { mac => '00:11:22:33:44:66' },
            }
        ),
    );

    no warnings 'redefine';
    local *xCAT::Table::new = sub {
        my ( $class, $name ) = @_;
        return $lookup_tables{$name};
    };
    local *xCAT_plugin::dhcp::getipaddr = sub {
        my ($host) = @_;
        return $host eq 'valid01' ? '192.0.2.30' : undef;
    };
    local *xCAT_plugin::dhcp::ipIsDynamic = sub { return 0; };
    local *xCAT_plugin::dhcp::kea_next_server_for_node = sub { return ( '192.0.2.1', '192.0.2.1' ); };
    local *xCAT_plugin::dhcp::kea_boot_for_node = sub { return {}; };
    local *xCAT::MsgUtils::message = sub { return; };
    local *xCAT::MsgUtils::trace = sub { return; };

    my ( @warnings, @errors );
    my $capture_response = sub {
        my $response = shift;
        push @warnings, @{ $response->{warning} || [] };
        push @errors,   @{ $response->{error}   || [] };
    };
    my $saved_umask = umask;
    my $saved_ignorecase = $Getopt::Long::ignorecase;
    {
        local @ARGV;
        xCAT_plugin::dhcp::process_request(
            {
                _xcatpreprocessed => [0],
                arg               => [ '-q', '-a' ],
            },
            $capture_response
        );
    }
    umask $saved_umask;
    $Getopt::Long::ignorecase = $saved_ignorecase;
    Getopt::Long::Configure('pass_through');
    @warnings = ();
    @errors   = ();

    {
        package DHCPKeaLookupBackend;
        sub subnet_id_for_ip { return 1; }
    }
    my $backend = bless {}, 'DHCPKeaLookupBackend';
    my $reservations = xCAT_plugin::dhcp::kea_build_node_reservations(
        $backend,
        {},
        [ 'unresolved01', 'valid01' ]
    );

    if ( ref($reservations) eq 'HASH' && $reservations->{error} ) {
        push @errors, $reservations->{error};
        $reservations = [];
    }

    is_deeply(
        [ map { $_->{hostname} } @$reservations ],
        ['valid01'],
        'an unresolved hostname does not block later valid Kea reservations'
    );
    is_deeply(
        \@warnings,
        ['The hostname unresolved01 of node unresolved01 could not be resolved.'],
        'an unresolved Kea hostname reports the ISC-compatible warning'
    );
    is_deeply( \@errors, [], 'an unresolved Kea hostname does not abort the request' );
}

{
    my %xnba_tables = (
        noderes => DHCPKeaResTable->new( { xnba01 => { netboot => 'xnba' } } ),
        mac     => DHCPKeaResTable->new( { xnba01 => { mac => 'AA-BB-CC-DD-EE-FF' } } ),
    );

    no warnings 'redefine';
    local *xCAT::Table::new = sub {
        my ( $class, $name ) = @_;
        return $xnba_tables{$name};
    };
    local *xCAT_plugin::dhcp::kea_next_server_for_node = sub { return ( '192.0.2.1', '192.0.2.1' ); };

    my $classes = xCAT_plugin::dhcp::kea_xnba_client_classes_for_nodes(['xnba01']);
    my ($bios_class) = grep { $_->{name} =~ /-bios\z/ } @$classes;
    ok( $bios_class, 'hyphenated xNBA MAC produces a BIOS client class' );
    is(
        $bios_class ? $bios_class->{'user-context'}{'xcat-mac'} : undef,
        'aa:bb:cc:dd:ee:ff',
        'xNBA client-class context stores the canonical MAC address'
    );
}

{
    # Regression: a node whose mac table entry uses the *NOIP* sentinel for a
    # secondary NIC (e.g. "mac1|mac2!*NOIP*") must still get exactly one Kea
    # reservation -- for the real NIC only.  The *NOIP* NIC intentionally has no
    # IP, so it must be skipped the same way the ISC path skips it.  Resolving
    # the literal "*NOIP*" as a host would otherwise emit a bogus second
    # reservation (or, on branches that treat an unresolved reservation as
    # fatal, abort makedhcp and leave the node with no reservation at all).
    my %noip_tables = (
        noderes  => DHCPKeaResTable->new( { cn01 => { netboot => 'xnba', tftpserver => '<xcatmaster>' } } ),
        chain    => DHCPKeaResTable->new( { cn01 => {} } ),
        nodetype => DHCPKeaResTable->new( { cn01 => { arch => 'x86_64', provmethod => 'install', os => 'rhels9' } } ),
        iscsi    => DHCPKeaResTable->new( {} ),
        vpd      => DHCPKeaResTable->new( {} ),
        mac      => DHCPKeaResTable->new(
            { cn01 => { mac => 'aa:bb:cc:dd:ee:01|aa:bb:cc:dd:ee:02!*NOIP*' } }
        ),
    );

    no warnings 'redefine';
    local *xCAT::Table::new = sub {
        my ( $class, $name ) = @_;
        return $noip_tables{$name};
    };

    # Resolve *every* hostname (including the literal *NOIP*) so the only thing
    # that can keep this to a single reservation is the explicit *NOIP* skip --
    # this makes the guard independent of how unresolved names are handled.
    my $noip_getipaddr = sub {
        my ( $host, %opt ) = @_;
        return '2001:db8::30' if $opt{OnlyV6};
        return '192.0.2.30';
    };
    local *xCAT::NetworkUtils::getipaddr = $noip_getipaddr;
    local *xCAT_plugin::dhcp::getipaddr  = $noip_getipaddr;
    local *xCAT_plugin::dhcp::ipIsDynamic = sub { return 0; };
    local *xCAT_plugin::dhcp::kea_next_server_for_node = sub { return ( '192.0.2.1', '192.0.2.1' ); };
    local *xCAT_plugin::dhcp::kea_boot_for_node = sub { return {}; };

    my @errors;
    local $xCAT_plugin::dhcp::callback = sub {
        my $resp = shift;
        push @errors, @{ $resp->{error} } if $resp->{error};
    };

    my $backend = bless {}, 'DHCPKeaResBackend';    # subnet_id_for_ip defined above

    my $res4 = xCAT_plugin::dhcp::kea_build_node_reservations( $backend, {}, ['cn01'] );
    is( scalar(@errors), 0, 'NOIP secondary NIC does not raise an error (v4)' );
    is( scalar( @{ $res4 || [] } ), 1, 'NOIP NIC skipped: exactly one IPv4 reservation' );
    is( ( $res4->[0] || {} )->{'hw-address'}, 'aa:bb:cc:dd:ee:01', 'IPv4 reservation is for the real NIC, not the *NOIP* NIC' );
    ok( !grep( { ( $_->{hostname} || '' ) eq '*NOIP*' } @{ $res4 || [] } ), 'no IPv4 reservation carries the *NOIP* sentinel as a hostname' );

    @errors = ();
    my $res6 = xCAT_plugin::dhcp::kea_build_node_reservations6( $backend, {}, ['cn01'] );
    is( scalar(@errors), 0, 'NOIP secondary NIC does not raise an error (v6)' );
    is( scalar( @{ $res6 || [] } ), 1, 'NOIP NIC skipped: exactly one IPv6 reservation' );
    is( ( $res6->[0] || {} )->{'hw-address'}, 'aa:bb:cc:dd:ee:01', 'IPv6 reservation is for the real NIC, not the *NOIP* NIC' );
    ok( !grep( { ( $_->{hostname} || '' ) eq '*NOIP*' } @{ $res6 || [] } ), 'no IPv6 reservation carries the *NOIP* sentinel as a hostname' );
}

done_testing();
