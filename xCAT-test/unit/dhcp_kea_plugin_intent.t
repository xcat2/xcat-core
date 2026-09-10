use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage, TestingAndDebugging::ProhibitNoStrict, TestingAndDebugging::ProhibitNoWarnings)
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";

use File::Temp qw(tempdir);
use Socket ();
use Test::More;
use XCAT::Test::File qw(repo_path);

BEGIN {
    package xCAT::Table;
    our $networks;
    sub new {
        my ( $class, $name ) = @_;
        return $name eq 'networks' ? $networks : undef;
    }
    $INC{'xCAT/Table.pm'} = __FILE__;

    package xCAT::TableUtils;
    our $tftpdir;
    sub getTftpDir { return $tftpdir; }
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

$xCAT::TableUtils::tftpdir = '/srv/tftp';
my $source_dhcp_plugin = repo_path('xCAT-server/lib/xcat/plugins/dhcp.pm');
require $source_dhcp_plugin;
require xCAT::DHCP::Backend::Kea;

{
    package DHCPKeaIntentBackend;
    our @ISA = ('xCAT::DHCP::Backend::Kea');
    sub host_cmds_hook_path { return '/test/libdhcp_host_cmds.so'; }
    sub bootp_hook_path     { return '/test/libdhcp_bootp.so'; }
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

{
    no warnings 'redefine';
    local *xCAT::NetworkUtils::thishostisnot = sub { return 0; };
    my $nettab = DHCPKeaIntentNetTable->new(\%network_entry);
    my $subnet = xCAT_plugin::dhcp::kea_subnet4_intent(
        $nettab, '10.0.0.0', '255.255.255.0', 'eth0', 0, 1, 80
    );
    my %classes = map { $_->{name} => $_ } @{ $subnet->{client_classes} };
    ok($classes{'xcat-s390x-qemu-10.0.0.0_24'}, 'the Kea subnet includes QEMU s390x boot policy');
    is(
        $classes{'xcat-s390x-qemu-10.0.0.0_24'}{'option-data'}[0]{data},
        's390x/10.0.0.0_24',
        'the Kea subnet sends the s390x configuration name',
    );
    is_deeply(
        [ grep { /^xcat-s390x-/ } @{ $subnet->{additional_client_classes} } ],
        ['xcat-s390x-qemu-10.0.0.0_24'],
        'the s390x policy is evaluated only for its subnet',
    );

    # ONIE is answered per network for the same reason as s390x: the answer is
    # a URL naming the management node on this network. The ISC path sends the
    # same URL from its onie_vendor branch.
    ok( $classes{'xcat-onie-10.0.0.0_24'}, 'the Kea subnet answers ONIE switches' );
    is(
        $classes{'xcat-onie-10.0.0.0_24'}{'option-data'}[0]{data},
        'http://10.0.0.1/install/onie/onie-installer',
        'the ONIE switch is pointed at the installer on this network',
    );
    is_deeply(
        [ grep { /^xcat-onie-/ } @{ $subnet->{additional_client_classes} } ],
        ['xcat-onie-10.0.0.0_24'],
        'the ONIE policy is evaluated only for its subnet',
    );
}

my @sysconfig_policy_cases = (
    [ 'sles10',                  0, 'SLES 10' ],
    [ 'sles11',                  1, 'SLES 11' ],
    [ 'sles15.10',               1, 'SLES 15.10' ],
    [ 'sles-sap15.6',            1, 'SLES for SAP 15.6' ],
    [ 'opensuse-leap15.6',       1, 'openSUSE Leap 15.6' ],
    [ 'opensuse_leap15.6',       1, 'underscored openSUSE Leap 15.6' ],
    [ 'leap15.6',                1, 'short Leap 15.6' ],
    [ 'rhel6',                    0, 'RHEL 6' ],
    [ 'rhel6.10',                 0, 'RHEL 6.10' ],
    [ 'rhel7',                    1, 'RHEL 7' ],
    [ 'rhels7.0',                 1, 'RHEL Server 7.0' ],
    [ 'rhel10',                   1, 'RHEL 10' ],
    [ 'RHEL7',                    1, 'uppercase RHEL 7' ],
    [ 'ubuntu24.04',              0, 'Ubuntu release' ],
    [ 'debian12',                 0, 'Debian release' ],
    [ 'opensuse-tumbleweed',      0, 'openSUSE Tumbleweed release' ],
    [ 'unknown',                  0, 'unknown release' ],
    [ undef,                      0, 'undefined release' ],
);

foreach my $case (@sysconfig_policy_cases) {
    my ( $os, $expected, $description ) = @{$case};
    my $actual = xCAT_plugin::dhcp::dhcpd_sysconfig_uses_interface_key($os);
    is( $actual, $expected, "$description keeps the dhcpd sysconfig policy" );
}

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

    {
        local $ENV{PATH} = $tmpdir;
        is(
            xCAT_plugin::dhcp::kea_command_path('ip'),
            $fake_ip,
            'DHCP route command lookup retains the first executable PATH match'
        );
    }

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
    # ip/mac/hostname reservation for it.
    #
    # This node names no server of its own -- its tftpserver is the
    # <xcatmaster> placeholder and it has no xcatmaster -- so the address it is
    # sent to is the subnet's, which a reservation states by saying nothing.
    # Kea used to fall back to my_ip_facing here, which is a different answer
    # from the one ISC gives the same node whenever networks.tftpserver names
    # some third machine.
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
    # The name travels as the reservation's own host-name option and the
    # "hostname" field is left out entirely. Kea builds option 12 out of that
    # field and appends ddns-qualifying-suffix to it, so a node asking who it
    # was got an FQDN while ISC, which writes option 12 and the DDNS name as
    # separate statements, sent the node's own name. S-35 asks for the node's
    # own name on both.
    ok( !exists $r->{hostname},
        'a reservation carries no hostname field for Kea to qualify' );
    is_deeply(
        [ grep { $_->{name} eq 'host-name' } @{ $r->{'option-data'} || [] } ],
        [ { name => 'host-name', data => 'svc01' } ],
        'service node reservation carries its name as the host-name option'
    );
    ok( !exists $r->{'next-server'},
        'a node that names no server of its own leaves next-server to the subnet' );
}

{
    # Where a node is sent, in the order noderes states it. Both backends read
    # this one answer; they used to have a copy each and the copies disagreed
    # about every row but the first.
    no warnings 'redefine';
    local *xCAT::NetworkUtils::my_ip_facing = sub { return ( 0, '10.0.0.1' ); };
    my @errors;
    local $xCAT_plugin::dhcp::callback = sub {
        my $resp = shift;
        push @errors, @{ $resp->{error} || [] };
    };

    my @cases = (
        [   { tftpserver => '192.0.2.10', xcatmaster => '192.0.2.20' },
            [ '192.0.2.10', '192.0.2.10' ],
            'the node\'s own tftpserver outranks its xcatmaster',
        ],
        [   { tftpserver => '<xcatmaster>', xcatmaster => '192.0.2.20' },
            [ '192.0.2.20', '192.0.2.20' ],
            'the <xcatmaster> placeholder defers to the xcatmaster attribute',
        ],
        [   { netboot => 'xnba', xcatmaster => '192.0.2.20' },
            [ '192.0.2.20', '192.0.2.20' ],
            'xcatmaster is honoured for every netboot method, not only petitboot and onie',
        ],
        [   { netboot => 'xnba' },
            [ '${next-server}', undef ],
            'a node naming neither inherits the subnet\'s value',
        ],
        [   {},
            [ '${next-server}', undef ],
            'and so does a node with no noderes entry to speak of',
        ],
        [   { netboot => 'petitboot' },
            [ '10.0.0.1', '10.0.0.1' ],
            'petitboot needs an address to build its URL with, so it falls back to the facing interface',
        ],
        [   { netboot => 'onie' },
            [ '10.0.0.1', '10.0.0.1' ],
            'and so does onie',
        ],
    );

    foreach my $case (@cases) {
        my ( $nrent, $want, $why ) = @{$case};
        is_deeply( [ xCAT_plugin::dhcp::next_server_for_node( 'n1', $nrent ) ], $want, $why );
    }

    is_deeply( [ xCAT_plugin::dhcp::next_server_for_node( 'n1', undef ) ],
        [ '${next-server}', undef ], 'a node with no noderes row at all inherits the subnet too' );

    is( scalar(@errors), 0, 'none of those are an error the operator has to read about' );

    # An xcatmaster nobody can resolve is a misconfiguration, and silently
    # sending the node somewhere else hides it.
    @errors = ();
    my @unresolvable = xCAT_plugin::dhcp::next_server_for_node( 'n1', { xcatmaster => 'no.such.host.invalid' } );
    is( scalar(@unresolvable), 0, 'an unresolvable xcatmaster yields no address' );
    like( ( $errors[0] || '' ), qr/xcatmaster/, 'and says which attribute to look at' );
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
    local *xCAT_plugin::dhcp::next_server_for_node = sub { return ( '192.0.2.1', '192.0.2.1' ); };
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
    local *xCAT_plugin::dhcp::next_server_for_node = sub { return ( '192.0.2.1', '192.0.2.1' ); };
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
        [ map { $_->{'ip-address'} } @$reservations ],
        ['192.0.2.30'],
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
    local *xCAT_plugin::dhcp::next_server_for_node = sub { return ( '192.0.2.1', '192.0.2.1' ); };

    my $classes = xCAT_plugin::dhcp::kea_node_client_classes_for_nodes(['xnba01'])->{classes};
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
    local *xCAT_plugin::dhcp::next_server_for_node = sub { return ( '192.0.2.1', '192.0.2.1' ); };
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

{
    my %range_tables = (
        noderes  => DHCPKeaResTable->new( { range01 => {} } ),
        chain    => DHCPKeaResTable->new( { range01 => {} } ),
        nodetype => DHCPKeaResTable->new( { range01 => {} } ),
        iscsi    => DHCPKeaResTable->new( {} ),
        vpd      => DHCPKeaResTable->new( {} ),
        mac      => DHCPKeaResTable->new(
            {
                range01 => {
                    mac => '00:11:22:33:44:55!dynamic-host|00:11:22:33:44:66!static-host',
                },
            }
        ),
    );

    no warnings 'redefine';
    local *xCAT::Table::new = sub {
        my ( $class, $name ) = @_;
        return $range_tables{$name};
    };
    my $use_ipv4_v6_fallback = 0;
    local *xCAT_plugin::dhcp::getipaddr = sub {
        my ( $host, %opt ) = @_;
        if ( $opt{OnlyV6} ) {
            return '192.0.2.150' if $use_ipv4_v6_fallback && $host eq 'dynamic-host';
            return $host eq 'dynamic-host' ? '2001:db8::150' : '2001:db8::25';
        }
        return $host eq 'dynamic-host' ? '192.0.2.150' : '192.0.2.25';
    };
    local *xCAT_plugin::dhcp::ipIsDynamic = sub {
        my ($ip) = @_;
        return $ip eq '192.0.2.150' || $ip eq '2001:db8::150';
    };
    local *xCAT_plugin::dhcp::next_server_for_node = sub { return; };
    local *xCAT_plugin::dhcp::kea_boot_for_node = sub { return {}; };
    local *xCAT::MsgUtils::message = sub { return; };
    local *xCAT::MsgUtils::trace = sub { return; };

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

    my $backend = bless {}, 'DHCPKeaResBackend';
    my $reservations4 = xCAT_plugin::dhcp::kea_build_node_reservations( $backend, {}, ['range01'] );
    is_deeply(
        [ map { $_->{'ip-address'} } @$reservations4 ],
        ['192.0.2.25'],
        'Kea IPv4 omits a reservation whose address is in a dynamic range'
    );
    is_deeply(
        \@errors,
        [
            'Node range01 has IP 192.0.2.150 which is inside the DHCP dynamic range. '
              . 'Move the node IP outside the dynamic range or adjust the range in the networks table.'
        ],
        'Kea IPv4 reports the dynamic-range conflict and continues with later interfaces'
    );

    @errors = ();
    my $reservations6 = xCAT_plugin::dhcp::kea_build_node_reservations6( $backend, {}, ['range01'] );
    is_deeply(
        [ map { $_->{'ip-addresses'}->[0] } @$reservations6 ],
        ['2001:db8::25'],
        'Kea IPv6 omits a reservation whose address is in a dynamic range'
    );
    is_deeply(
        \@errors,
        [
            'Node range01 has IPv6 address 2001:db8::150 which is inside the DHCP dynamic range. '
              . 'Move the node IP outside the dynamic range or adjust the range in the networks table.'
        ],
        'Kea IPv6 reports the dynamic-range conflict and continues with later interfaces'
    );

    $use_ipv4_v6_fallback = 1;
    @errors = ();
    $reservations6 = xCAT_plugin::dhcp::kea_build_node_reservations6( $backend, {}, ['range01'] );
    is_deeply(
        [ map { $_->{'ip-addresses'}->[0] } @$reservations6 ],
        ['2001:db8::25'],
        'Kea IPv6 still omits a dynamic IPv4 fallback result'
    );
    is_deeply(
        \@errors,
        [
            'Node range01 has IPv6 address 192.0.2.150 which is inside the DHCP dynamic range. '
              . 'Move the node IP outside the dynamic range or adjust the range in the networks table.'
        ],
        'Kea IPv6 preserves dynamic-range checking when OnlyV6 falls back to IPv4'
    );
}

{
    no warnings 'redefine';
    my ( @checked, @responses );
    local *xCAT_plugin::dhcp::ipIsDynamic = sub {
        my ($ip) = @_;
        push @checked, $ip;
        return $ip eq '192.0.2.150' || $ip eq '2001:db8::150';
    };
    my $capture_response = sub { push @responses, shift; };

    ok(
        !xCAT_plugin::dhcp::_reject_dynamic_node_ip( 'range01', '192.0.2.25', 'IPv4', $capture_response ),
        'an IPv4 address outside the dynamic range is accepted'
    );
    ok(
        xCAT_plugin::dhcp::_reject_dynamic_node_ip( 'range01', '192.0.2.150', 'IPv4', $capture_response ),
        'an IPv4 address inside the dynamic range is rejected'
    );
    ok(
        xCAT_plugin::dhcp::_reject_dynamic_node_ip( 'range01', '2001:db8::150', 'IPv6', $capture_response ),
        'an IPv6 address inside the dynamic range is rejected'
    );
    is_deeply(
        \@checked,
        [ '192.0.2.25', '192.0.2.150', '2001:db8::150' ],
        'the shared helper checks each caller-approved address'
    );
    is_deeply(
        \@responses,
        [
            {
                error => [
                    'Node range01 has IP 192.0.2.150 which is inside the DHCP dynamic range. '
                      . 'Move the node IP outside the dynamic range or adjust the range in the networks table.'
                ],
                errorcode => [1],
            },
            {
                error => [
                    'Node range01 has IPv6 address 2001:db8::150 which is inside the DHCP dynamic range. '
                      . 'Move the node IP outside the dynamic range or adjust the range in the networks table.'
                ],
                errorcode => [1],
            },
        ],
        'dynamic IPv4 and IPv6 addresses keep the existing callback payloads'
    );
}

{
    # A client that speaks BOOTP and not DHCP. ISC serves it from
    # "range dynamic-bootp"; Kea answers it only with the bootp hook loaded,
    # and without the hook such a machine times out for ever with nothing on
    # the wire to say why.
    no warnings 'redefine';
    local *xCAT::NetworkUtils::thishostisnot = sub { return 0; };
    local *xCAT_plugin::dhcp::kea_boot_client_classes = sub { return []; };
    local *xCAT_plugin::dhcp::kea_option_defs = sub { return []; };
    local *xCAT_plugin::dhcp::kea_global_option_data = sub { return []; };
    local *xCAT_plugin::dhcp::kea_dhcp_lease_time = sub { return 43200; };
    local *xCAT_plugin::dhcp::kea_control_agent_enabled = sub { return 0; };
    local $xCAT::Table::networks = DHCPKeaIntentNetTable->new( \%network_entry );

    my @warnings;
    local $xCAT_plugin::dhcp::callback = sub {
        my $resp = shift;
        push @warnings, @{ $resp->{warning} } if $resp->{warning};
    };

    my $served = xCAT_plugin::dhcp::kea_build_dhcp4_intent(
        DHCPKeaIntentBackend->new(), { eth0 => 1 } );
    is_deeply(
        $served->{'hooks-libraries'},
        [ { library => '/test/libdhcp_bootp.so' } ],
        'the bootp hook is loaded so a BOOTP-only client is answered',
    );
    is_deeply( \@warnings, [], 'and nothing is reported when it is there' );

    # The Control Agent hook and the BOOTP hook are separate decisions, and
    # both belong in the list rather than one replacing the other.
    {
        local *xCAT_plugin::dhcp::kea_control_agent_enabled = sub { return 1; };
        my $both = xCAT_plugin::dhcp::kea_build_dhcp4_intent(
            DHCPKeaIntentBackend->new( kea_socket_dir => '/run/kea-xcat-test' ),
            { eth0 => 1 } );
        is_deeply(
            [ map { $_->{library} } @{ $both->{'hooks-libraries'} } ],
            [ '/test/libdhcp_host_cmds.so', '/test/libdhcp_bootp.so' ],
            'loading one hook does not drop the other',
        );
    }

    {
        package DHCPKeaNoBootpBackend;
        our @ISA = ('DHCPKeaIntentBackend');
        sub bootp_hook_path { return; }
    }
    @warnings = ();
    my $unserved = xCAT_plugin::dhcp::kea_build_dhcp4_intent(
        DHCPKeaNoBootpBackend->new(), { eth0 => 1 } );
    ok( !$unserved->{'hooks-libraries'},
        'a hook that is not installed is not named in the configuration' );
    is_deeply(
        \@warnings,
        ['libdhcp_bootp.so was not found, so BOOTP-only clients will not be answered. Install the Kea hooks package to serve them.'],
        'and the operator is told which clients that leaves unanswered',
    );
}

{
    # Two netboot methods the Kea path used to answer differently from the ISC
    # one, so the same node booted on one backend and not on the other.
    #
    # nimol: ISC supersedes server.filename with /vios/nodes/<node>; Kea named
    # no boot file at all, so a VIOS install got nothing to fetch.
    #
    # petitboot: ISC sends the conf-file option and nothing else.  Kea also set
    # boot-file-name, and petitboot acts on a boot file name when it sees one,
    # sending the machine after a TFTP fetch of a file that was never put there.
    my $nimol = xCAT_plugin::dhcp::kea_boot_for_node(
        'vios01', { netboot => 'nimol' }, undef, undef, undef, '192.0.2.1'
    );
    is( $nimol->{'boot-file-name'}, '/vios/nodes/vios01',
        'a nimol node is given the boot file the ISC path supersedes' );

    my $petitboot = xCAT_plugin::dhcp::kea_boot_for_node(
        'pb01', { netboot => 'petitboot' }, undef, undef, undef, '192.0.2.1'
    );
    ok( !exists $petitboot->{'boot-file-name'},
        'a petitboot node is named no boot file: the conf-file is the whole answer' );
    my ($conf_file) = grep { $_->{name} eq 'conf-file' } @{ $petitboot->{'option-data'} };
    is(
        $conf_file ? $conf_file->{data} : undef,
        'http://192.0.2.1/tftpboot/petitboot/pb01',
        'the petitboot conf-file URL matches the ISC statement',
    );

    # Without a next server there is no URL to build, and a boot file name is
    # still not an answer petitboot can use.
    my $unserved = xCAT_plugin::dhcp::kea_boot_for_node(
        'pb02', { netboot => 'petitboot' }, undef, undef, undef, undef
    );
    ok( !exists $unserved->{'boot-file-name'},
        'a petitboot node with no next server is left alone rather than sent to TFTP' );
    is_deeply(
        [ grep { $_->{name} eq 'conf-file' } @{ $unserved->{'option-data'} } ],
        [],
        'no conf-file is invented without a next server',
    );
}

{
    # A ScaleMP hypervisor and an ISAN iSCSI initiator both need to be answered
    # differently from the machine next to them, and on ISC both are an
    # if/else inside the node's own host block. A Kea reservation outranks
    # every class, so anything the reservation names cannot be overridden --
    # which is why neither the pxe boot file nor an ISAN node's root path is
    # reserved. What the reservation does not name, a class can decide.
    my $pxe = xCAT_plugin::dhcp::kea_boot_for_node(
        'cn01', { netboot => 'pxe' }, undef, undef, undef, '192.0.2.1'
    );
    ok( !exists $pxe->{'boot-file-name'},
        'a pxe node reserves no boot file, so the ScaleMP class can win' );

    my $iscsi = { server => '192.0.2.9', target => 'iqn.2024-01.test:cn01', lun => 0 };
    my $plain = xCAT_plugin::dhcp::kea_boot_for_node(
        'cn02', {}, undef, undef, $iscsi, '192.0.2.1'
    );
    my ($root_path) = grep { $_->{name} eq 'root-path' } @{ $plain->{'option-data'} };
    is(
        $root_path ? $root_path->{data} : undef,
        'iscsi:192.0.2.9:6:3260:0:iqn.2024-01.test:cn01',
        'without an initiator name there is no choice to make, so the root path is reserved',
    );

    my $named = xCAT_plugin::dhcp::kea_boot_for_node(
        'cn03', {}, undef, undef, { %$iscsi, iname => 'iqn.2024-01.test:init' },
        '192.0.2.1'
    );
    is_deeply(
        [ grep { $_->{name} =~ /^(root-path|iscsi-initiator-iqn)$/ } @{ $named->{'option-data'} } ],
        [],
        'with one, nothing is reserved: an ISAN initiator must not be sent option 17',
    );
}

{
    # ...and the classes that carry what the reservation gave up.
    my %tables = (
        noderes => DHCPKeaResTable->new(
            { smp01 => { netboot => 'pxe' }, san01 => { netboot => 'pxe' } }
        ),
        mac => DHCPKeaResTable->new(
            {
                smp01 => { mac => 'aa:bb:cc:dd:ee:01' },
                san01 => { mac => 'aa:bb:cc:dd:ee:02' },
            }
        ),
        iscsi => DHCPKeaResTable->new(
            {
                san01 => {
                    server => '192.0.2.9',
                    target => 'iqn.2024-01.test:san01',
                    lun    => 0,
                    iname  => 'iqn.2024-01.test:init',
                },
            }
        ),
    );

    no warnings 'redefine';
    local *xCAT::Table::new = sub {
        my ( $class, $name ) = @_;
        return $tables{$name};
    };
    local *xCAT_plugin::dhcp::next_server_for_node = sub { return ( '192.0.2.1', '192.0.2.1' ); };

    my $classes = xCAT_plugin::dhcp::kea_node_client_classes_for_nodes( [ 'smp01', 'san01' ] )->{classes};
    my %by_name = map { $_->{name} => $_ } @$classes;

    is( $by_name{'xcat-pxe-smp01-aabbccddee01-scalemp'}{'boot-file-name'},
        'vsmp/pxelinux.0',
        'a ScaleMP machine is handed the binary built for it' );
    is( $by_name{'xcat-pxe-smp01-aabbccddee01'}{'boot-file-name'},
        'pxelinux.0',
        'and every other machine on that reservation keeps pxelinux.0' );
    like( $by_name{'xcat-pxe-smp01-aabbccddee01'}{test}, qr/\Qnot (option[60].text == 'ScaleMP')\E/,
        'the two are mutually exclusive: Kea has no else to fall into' );

    # The empty container comes first because without it Kea has nowhere to put
    # the two sub-options and sends neither: an encapsulated space travels only
    # inside the option that encapsulates it, and option 43 carries no data of
    # its own. ISC builds the container from the sub-option declarations.
    is_deeply(
        $by_name{'xcat-iscsi-san01-aabbccddee02-isan'}{'option-data'},
        [
            { name => 'isan-encap-opts' },
            { space => 'isan', name => 'iqn',       data => 'iqn.2024-01.test:init' },
            { space => 'isan', name => 'root-path', data => 'iscsi:192.0.2.9:6:3260:0:iqn.2024-01.test:san01' },
        ],
        'an ISAN initiator reads both values out of the vendor space',
    );
    is_deeply(
        $by_name{'xcat-iscsi-san01-aabbccddee02'}{'option-data'},
        [
            { name => 'root-path',           data => 'iscsi:192.0.2.9:6:3260:0:iqn.2024-01.test:san01' },
            { name => 'iscsi-initiator-iqn', data => 'iqn.2024-01.test:init' },
        ],
        'everything else gets the standard form ISC emits',
    );

    ok( !exists $by_name{'xcat-iscsi-smp01-aabbccddee01'},
        'a node with no iscsi entry is given no iSCSI classes' );

    # The option 43 space those two names live in has to be declared, or Kea
    # rejects the configuration outright.
    my %defs = map { ( $_->{space} . '/' . $_->{name} ) => $_ } @{ xCAT_plugin::dhcp::kea_option_defs() };
    is( $defs{'dhcp4/isan-encap-opts'}{code}, 43, 'option 43 encapsulates the isan space' );
    is( $defs{'dhcp4/isan-encap-opts'}{encapsulate}, 'isan', 'and says which space that is' );
    is( $defs{'isan/iqn'}{code},       203, 'the initiator name is sub-option 203' );
    is( $defs{'isan/root-path'}{code}, 201, 'the root path is sub-option 201' );
}

{
    # A NIC marked *NOIP* in the mac table is meant to be answered with
    # nothing. ISC writes "deny booting;" into its host block; Kea discards a
    # packet assigned to the class named DROP, and nothing else will do --
    # skipping the reservation still leaves the subnet-wide architecture
    # classes handing the interface a boot file.
    my %tables = (
        noderes => DHCPKeaResTable->new(
            { cn01 => { netboot => 'xnba' }, cn02 => { netboot => 'pxe' } }
        ),
        mac => DHCPKeaResTable->new(
            {
                cn01 => { mac => 'aa:bb:cc:dd:ee:01|aa:bb:cc:dd:ee:11!*NOIP*' },
                cn02 => { mac => 'aa:bb:cc:dd:ee:02!*NOIP*' },
            }
        ),
    );

    no warnings 'redefine';
    local *xCAT::Table::new = sub {
        my ( $class, $name ) = @_;
        return $tables{$name};
    };
    local *xCAT_plugin::dhcp::next_server_for_node = sub { return ( '192.0.2.1', '192.0.2.1' ); };

    my $config = { Dhcp4 => { 'client-classes' => [] } };
    ok( xCAT_plugin::dhcp::kea_sync_node_client_classes( $config, [ 'cn01', 'cn02' ] ),
        'marking an interface *NOIP* changes the configuration' );

    my ($drop) = grep { $_->{name} eq 'DROP' } @{ $config->{Dhcp4}{'client-classes'} };
    ok( $drop, 'the MACs land in the one class Kea treats as a discard' );
    is( $drop->{test},
        'pkt4.mac == 0xaabbccddee11 or pkt4.mac == 0xaabbccddee02',
        'every marked MAC in the range is named, and only those' );

    # cn01's real NIC is untouched: the marking is per interface, not per node.
    ok( ( grep { $_->{name} =~ /aabbccddee01/ } @{ $config->{Dhcp4}{'client-classes'} } ),
        'the node\'s addressed NIC still gets its boot classes' );

    # Re-running makedhcp for one node must not take the other node's
    # interfaces out of the class they share.
    xCAT_plugin::dhcp::kea_sync_node_client_classes( $config, ['cn01'] );
    ($drop) = grep { $_->{name} eq 'DROP' } @{ $config->{Dhcp4}{'client-classes'} };
    is( $drop->{test},
        'pkt4.mac == 0xaabbccddee11 or pkt4.mac == 0xaabbccddee02',
        'a makedhcp for one node leaves the rest of the cluster in the DROP class' );

    # ...and makedhcp -d for a node takes only that node's out.
    ok( xCAT_plugin::dhcp::kea_remove_node_client_classes( $config, ['cn02'] ),
        'removing a node with a marked interface changes the configuration' );
    ($drop) = grep { $_->{name} eq 'DROP' } @{ $config->{Dhcp4}{'client-classes'} };
    is( $drop->{test}, 'pkt4.mac == 0xaabbccddee11',
        'and leaves the other node still dropped' );

    xCAT_plugin::dhcp::kea_remove_node_client_classes( $config, ['cn01'] );
    is_deeply(
        [ grep { $_->{name} eq 'DROP' } @{ $config->{Dhcp4}{'client-classes'} } ],
        [],
        'with nothing left to drop the class goes rather than matching nothing',
    );
}

{
    # A node that has an operating system now, and a Windows UEFI install
    # waiting on the proxyDHCP daemon, both have to be handed no boot file.
    # ISC writes filename = "" into the node's host block, which outranks the
    # subnet chain. On Kea only a reservation outranks a class, so if the
    # reservation stays silent the subnet's architecture classes answer instead
    # and an installed node netboots forever.
    no warnings 'redefine';
    local *xCAT_plugin::dhcp::proxydhcp = sub { return 1; };

    foreach my $state (qw(boot iscsiboot)) {
        my $booted = xCAT_plugin::dhcp::kea_boot_for_node(
            'cn01', { netboot => 'xnba' }, { currstate => $state }, undef, undef, '192.0.2.1'
        );
        is( $booted->{'boot-file-name'}, '',
            "a node in state $state is handed no boot file rather than left to the subnet" );
    }

    my $installing = xCAT_plugin::dhcp::kea_boot_for_node(
        'win01', { netboot => 'xnba' }, { currstate => 'install' },
        { os => 'win2022' }, undef, '192.0.2.1'
    );
    is( $installing->{'boot-file-name'}, '',
        'a Windows UEFI install names no boot file, which is what defers it to proxyDHCP' );

    # ...and the same node on a Linux install is not deferred to anything.
    my $linux = xCAT_plugin::dhcp::kea_boot_for_node(
        'cn02', { netboot => 'pxe' }, { currstate => 'install' },
        { os => 'rhels9' }, undef, '192.0.2.1'
    );
    ok( !exists $linux->{'boot-file-name'},
        'a Linux install is left to its classes as before' );

    # An iSCSI node told to boot from disk still needs its root path: it is
    # what the disk is.
    my $iscsi = xCAT_plugin::dhcp::kea_boot_for_node(
        'cn03', {}, { currstate => 'iscsiboot' }, undef,
        { server => '192.0.2.9', target => 'iqn.2024-01.test:cn03', lun => 0 },
        '192.0.2.1'
    );
    is( $iscsi->{'boot-file-name'}, '', 'an iscsiboot node is handed no boot file' );
    ok( ( grep { $_->{name} eq 'root-path' } @{ $iscsi->{'option-data'} } ),
        'but it keeps the root path that says where its disk is' );
}

{
    my %tables = (
        noderes => DHCPKeaResTable->new(
            {
                booted => { netboot => 'xnba' },
                win01  => { netboot => 'xnba' },
            }
        ),
        mac => DHCPKeaResTable->new(
            {
                booted => { mac => 'aa:bb:cc:dd:ee:03' },
                win01  => { mac => 'aa:bb:cc:dd:ee:04' },
            }
        ),
        chain => DHCPKeaResTable->new(
            { booted => { currstate => 'boot' }, win01 => { currstate => 'install' } }
        ),
        nodetype => DHCPKeaResTable->new(
            { booted => { os => 'rhels9' }, win01 => { os => 'win2022' } }
        ),
    );

    no warnings 'redefine';
    local *xCAT::Table::new = sub {
        my ( $class, $name ) = @_;
        return $tables{$name};
    };
    local *xCAT_plugin::dhcp::next_server_for_node = sub { return ( '192.0.2.1', '192.0.2.1' ); };
    local *xCAT_plugin::dhcp::proxydhcp = sub { return 1; };

    my $classes = xCAT_plugin::dhcp::kea_node_client_classes_for_nodes( [ 'booted', 'win01' ] )->{classes};
    my %by_name = map { $_->{name} => $_ } @$classes;

    is_deeply(
        [ grep { /booted/ } keys %by_name ],
        [],
        'a node booting from disk is given no second stage to chainload',
    );

    my $deferral = $by_name{'xcat-proxydhcp-win01-aabbccddee04'};
    ok( $deferral, 'the Windows UEFI node gets the class that tags its reply' );
    is_deeply(
        $deferral->{'option-data'},
        [ { name => 'vendor-class-identifier', data => 'PXEClient', 'always-send' => 1 } ],
        'the tag is what sends the firmware to the daemon on 4011',
    );
    like( $deferral->{test}, qr/option\[93\]\.hex == 0x0000 or option\[93\]\.hex == 0x0007 or option\[93\]\.hex == 0x0009/,
        'and only the architectures ISC tags are tagged' );
    ok( !exists $by_name{'xcat-xnba-win01-aabbccddee04-bios'},
        'the node gets no xNBA class that would pre-empt the deferral' );
}

done_testing();
