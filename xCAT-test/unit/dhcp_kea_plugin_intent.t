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
    sub my_ip_facing_family { return ( 0, '2001:db8::1' ); }
    sub node_is_ipv6_only {
        my $node = $_[-1];
        return 0 if getipaddr($node, OnlyV4 => 1);
        return getipaddr($node, OnlyV6 => 1) ? 1 : 0;
    }
    sub ipv6_server_for_node {
        my ( $class, $node, $server ) = @_;
        ( $node, $server ) = ( $class, $node ) if $class ne __PACKAGE__;
        if (!defined($server) || $server eq '!myipfn!' || $server eq '<xcatmaster>') {
            my @facing = my_ip_facing_family(__PACKAGE__, $node, 6);
            return unless @facing && !$facing[0];
            return $facing[1];
        }
        return $server if $server =~ /:/ && isValidIp(__PACKAGE__, $server);
        return getipaddr($server, OnlyV6 => 1);
    }
    sub isIpv6addr {
        my $addr = $_[-1];
        return 0 unless defined($addr) && length($addr);
        return 0 if $addr =~ /%/;
        return 0 unless $addr =~ /:/;
        return $addr =~ /^[0-9a-fA-F:.]+$/ ? 1 : 0;
    }
    sub isValidIp {
        my $addr = $_[-1];
        return 0 unless defined($addr) && length($addr);
        return 1 if $addr =~ /^\d{1,3}(?:\.\d{1,3}){3}$/;
        return 1 if $addr =~ /^[0-9a-fA-F:]+$/ && $addr =~ /:/;
        return 0;
    }
    sub getIPv6PrefixLength {
        my ( $class, $network, $mask ) = @_;
        ( $network, $mask ) = ( $class, $network ) if $class ne __PACKAGE__;
        return $1 if defined($network) && $network =~ m{/([0-9]+)$} && $1 <= 128;
        return $1 if defined($mask) && $mask =~ m{^/?([0-9]+)$} && $1 <= 128;
        return;
    }
    sub getIPv6ReverseZone {
        my ( $class, $network, $mask ) = @_;
        ( $network, $mask ) = ( $class, $network ) if $class ne __PACKAGE__;
        my $prefix = getIPv6PrefixLength(__PACKAGE__, $network, $mask);
        return unless defined($prefix);
        return '0.0.0.0.9.0.3.7.8.b.d.0.1.0.0.2.ip6.arpa.'
          if $network =~ /^2001:db8:7309::/ && $prefix == 64;
        return;
    }
    sub format_uri_host {
        my ($host) = @_;
        $host = $_[1] if defined($host) && $host eq __PACKAGE__;
        return "[$host]" if defined($host) && $host =~ /:/;
        return $host;
    }
    sub thishostisnot { return 0; }
    sub ishostinsubnet { return 0; }
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
    our $service_nodes = {};
    our $dhcp_servers = [];
    sub getSNList {
        return @{ $dhcp_servers || [] } if $_[-1] eq 'dhcpserver';
        return;
    }
    sub get_ServiceNode { return $service_nodes; }
    sub getSNformattedhash { return $service_nodes; }
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

    package DHCPKeaIntentFilteredNetTable;
    our @ISA = ('DHCPKeaIntentNetTable');
    sub getAllAttribs {
        my ( $self, @attrs ) = @_;
        return {
            map { $_ => $self->{entry}{$_} }
              grep { exists $self->{entry}{$_} } @attrs
        };
    }
}

{
    # Answered per net and mask, so a test can tell one subnet from another.
    package DHCPKeaIntentMultiNetTable;
    sub new {
        my ( $class, @entries ) = @_;
        return bless { entries => [@entries] }, $class;
    }
    sub getAllAttribs {
        my ($self) = @_;
        return map { { %{$_} } } @{ $self->{entries} };
    }
    sub getAttribs {
        my ( $self, $criteria ) = @_;
        foreach my $entry ( @{ $self->{entries} } ) {
            next unless $entry->{net} eq $criteria->{net};
            next unless $entry->{mask} eq $criteria->{mask};
            return { %{$entry} };
        }
        return;
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
    # The local TFTP directory has no upstream loader, so the subnet offers no network script.
    is_deeply( [ grep { /^xcat-ipxe-net-/ } @{ $subnet->{additional_client_classes} } ], [],
        'without the upstream loader on this server, the Kea subnet names no network script' );

    local *xCAT_plugin::dhcp::kea_ipxe_loader_flags = sub { return ( ipxe_bios => 1, ipxe_uefi => 1 ); };
    $subnet = xCAT_plugin::dhcp::kea_subnet4_intent( $nettab, '10.0.0.0', '255.255.255.0', 'eth0', 0, 1, 80 );
    %classes = map { $_->{name} => $_ } @{ $subnet->{client_classes} };
    is_deeply(
        [ grep { /^xcat-ipxe-net-/ } @{ $subnet->{additional_client_classes} } ],
        [ 'xcat-ipxe-net-10.0.0.0_24-bios', 'xcat-ipxe-net-10.0.0.0_24-uefi' ],
        'with it, the Kea subnet gives unknown x86 clients the network scripts of the upstream loader',
    );
    like( $classes{'xcat-ipxe-net-10.0.0.0_24-bios'}{'boot-file-name'}, qr{/tftpboot/xcat/ipxe/nets/10\.0\.0\.0_24$},
        'from xcat/ipxe/nets' );
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
    # Regression: makenetworks stores some IPv6 networks as a literal in
    # networks.net and a numeric prefix in networks.mask. Reverse-zone
    # generation must consume that representation without looping.
    no warnings 'redefine';
    local *xCAT_plugin::dhcp::getipaddr = sub {
        my ( $address, %options ) = @_;
        return Math::BigInt->new('0x20010db8730900000000000000000000')
          if $address eq '2001:db8:7309::' && $options{GetNumber};
        return;
    };

    my ($zone, $error);
    {
        local $SIG{ALRM} = sub { die "IPv6 reverse-zone generation timed out\n" };
        eval {
            alarm 2;
            $zone = xCAT_plugin::dhcp::getzonesfornet(
                '2001:db8:7309::', '64'
            );
            alarm 0;
            1;
        } or $error = $@;
        alarm 0;
    }
    is($error, undef, 'Kea DDNS reverse-zone generation terminates');
    is(
        $zone,
        '0.0.0.0.9.0.3.7.8.b.d.0.1.0.0.2.ip6.arpa.',
        'Kea DDNS accepts an IPv6 network with a separate numeric prefix mask'
    );
    is_deeply(
        [ xCAT_plugin::dhcp::getzonesfornet('2001:db8:7309::', undef) ],
        [],
        'Kea DDNS rejects a missing IPv6 prefix without looping'
    );
    is_deeply(
        [ xCAT_plugin::dhcp::getzonesfornet('2001:db8:7309::', '129') ],
        [],
        'Kea DDNS rejects an out-of-range IPv6 prefix without looping'
    );
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
    package DHCPKeaControlSocketBackend;
    sub control_socket_path {
        my ( $self, $name ) = @_;
        return "shared-$name";
    }
    sub host_cmds_hook_path { return '/usr/lib64/kea/hooks/libdhcp_host_cmds.so'; }
    sub bootp_hook_path     { return '/usr/lib64/kea/hooks/libdhcp_bootp.so'; }

    package main;
    no warnings 'redefine';
    local *xCAT_plugin::dhcp::kea_ipv4_routes = sub {
        return ([ '10.0.0.0', 'eth0', '255.255.255.0', '' ]);
    };
    local *xCAT_plugin::dhcp::kea_boot_client_classes = sub { return []; };
    local *xCAT_plugin::dhcp::kea_option_defs = sub { return []; };
    local *xCAT_plugin::dhcp::kea_global_option_data = sub { return []; };
    local *xCAT_plugin::dhcp::kea_dhcp_lease_time = sub { return 43200; };
    local *xCAT_plugin::dhcp::kea_control_agent_enabled = sub { return 1; };

    my $backend = bless {}, 'DHCPKeaControlSocketBackend';
    local $xCAT::Table::networks = DHCPKeaIntentNetTable->new( \%network_entry );
    my $intent4 = xCAT_plugin::dhcp::kea_build_dhcp4_intent($backend, { eth0 => 1 });
    is(
        $intent4->{'control-socket'}{'socket-name'},
        'shared-kea4-ctrl-socket',
        'DHCPv4 and Control Agent use the shared Kea socket-name policy'
    );

    local $xCAT::Table::networks = DHCPKeaIntentNetTable->new(
        {
            net       => '2001:db8:7309::',
            mask      => '64',
            mgtifname => 'eth0',
            domain    => 'cluster.test',
        }
    );
    my $intent6 = xCAT_plugin::dhcp::kea_build_dhcp6_intent($backend, { eth0 => 1 });
    is(
        $intent6->{'control-socket'}{'socket-name'},
        'shared-kea6-ctrl-socket',
        'DHCPv6 and Control Agent use the shared Kea socket-name policy'
    );
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
    no warnings 'redefine';
    local *xCAT_plugin::dhcp::kea_dhcp_lease_time = sub { return 43200; };
    local *xCAT_plugin::dhcp::kea_control_agent_enabled = sub { return 0; };

    my %network6_entry = (
        net          => '2001:db8:7309::',
        mask         => '64',
        mgtifname    => 'eth0',
        dynamicrange => '2001:db8:7309::100/120',
        domain       => 'cluster.test',
        dhcpserver   => 'service-node-a',
    );
    my $backend = bless {}, 'DHCPKeaIntentBackend';

    {
        local *xCAT::NetworkUtils::thishostisnot = sub { return 1; };
        local $xCAT::Table::networks = DHCPKeaIntentFilteredNetTable->new( \%network6_entry );

        my $intent = xCAT_plugin::dhcp::kea_build_dhcp6_intent( $backend, { eth0 => 1 } );
        ok( !defined( $intent->{subnets}[0]{dynamicrange} ), 'non-owning Kea DHCPv6 server does not render dynamic pool' );
    }

    {
        local *xCAT::NetworkUtils::thishostisnot = sub { return 0; };
        local $xCAT::Table::networks = DHCPKeaIntentFilteredNetTable->new( \%network6_entry );

        my $intent = xCAT_plugin::dhcp::kea_build_dhcp6_intent( $backend, { eth0 => 1 } );
        is( $intent->{subnets}[0]{dynamicrange}, $network6_entry{dynamicrange}, 'owning Kea DHCPv6 server renders dynamic pool' );
    }

    {
        local *xCAT::NetworkUtils::my_ip_facing_family = sub {
            return ( 0, '2001:db8:7309::1' );
        };
        my $v6_getipaddr = sub {
            my ( $host, %options ) = @_;
            return unless $options{OnlyV6};
            return '2001:db8::53' if $host eq 'dns6.example.test';
            return;
        };
        local *xCAT::NetworkUtils::getipaddr = $v6_getipaddr;
        local *xCAT_plugin::dhcp::getipaddr = $v6_getipaddr;

        is(
            xCAT_plugin::dhcp::kea_ipv6_nameservers(
                '2001:db8:7309::/64',
                '<xcatmaster>, 192.0.2.53, dns6.example.test'
            ),
            '2001:db8:7309::1, 2001:db8::53',
            'DHCPv6 resolves the local xCAT server and filters IPv4 DNS fallbacks'
        );

        my %dns_network6 = (
            %network6_entry,
            nameservers => '<xcatmaster>, 192.0.2.53',
        );
        my $subnet = xCAT_plugin::dhcp::kea_subnet6_intent(
            \%dns_network6, 'eth0', 0, 10001
        );
        my ($dns_option) = grep { $_->{name} eq 'dns-servers' }
          @{ $subnet->{option_data} || [] };
        is(
            $dns_option->{data},
            '2001:db8:7309::1',
            'service-node DHCPv6 advertises its compute-facing IPv6 DNS address'
        );

        # The networks table carries an IPv6 mask as a prefix length, and
        # makenetworks and the osimage templates write it with the leading
        # slash. Both forms name the same prefix and both have to be accepted,
        # or makedhcp refuses the network it was given.
        foreach my $mask ( '64', '/64' ) {
            my %network6_mask = ( %network6_entry, mask => $mask );
            my $masked = xCAT_plugin::dhcp::kea_subnet6_intent(
                \%network6_mask, 'eth0', 0, 10002
            );
            ok( !$masked->{error}, "mask '$mask' is accepted" )
              or diag( $masked->{error} );
            is( $masked->{subnet}, '2001:db8:7309::/64',
                "mask '$mask' yields the /64 subnet" );
        }

        my %network6_noprefix = ( %network6_entry, mask => '' );
        my $noprefix = xCAT_plugin::dhcp::kea_subnet6_intent(
            \%network6_noprefix, 'eth0', 0, 10003
        );
        like( ( $noprefix->{error} || '' ), qr/must include a prefix length/,
            'a network with no prefix length is refused by name' );
    }
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
    # The same placeholder resolution and reverse-zone path must work when an
    # IPv6 network stores its prefix in networks.mask instead of CIDR notation.
    no warnings 'redefine';
    local *xCAT_plugin::dhcp::kea_ddns_enabled = sub { 1 };
    local *xCAT_plugin::dhcp::kea_ddns_key     = sub { ( 'HMAC-SHA256', 'YWJjMTIz' ); };
    local *xCAT_plugin::dhcp::getipaddr = sub {
        my ( $address, %options ) = @_;
        return Math::BigInt->new('0x20010db8730900000000000000000000')
          if $address eq '2001:db8:7309::' && $options{GetNumber};
        return;
    };
    local $xCAT::Table::networks = DHCPKeaIntentNetTable->new(
        {
            net         => '2001:db8:7309::',
            mask        => '64',
            nameservers => '<xcatmaster>',
            domain      => 'cluster.test',
        }
    );

    my ($ddns_intent, $error);
    {
        local $SIG{ALRM} = sub { die "IPv6 Kea DDNS intent timed out\n" };
        eval {
            alarm 2;
            $ddns_intent = xCAT_plugin::dhcp::kea_build_ddns_intent();
            alarm 0;
            1;
        } or $error = $@;
        alarm 0;
    }

    is($error, undef, 'IPv6 Kea DDNS intent generation terminates');
    ok(
        $ddns_intent && !$ddns_intent->{error},
        'IPv6 Kea DDNS intent accepts a separate numeric prefix mask'
    );
    is(
        $ddns_intent->{reverse_domains}[0]{name},
        '0.0.0.0.9.0.3.7.8.b.d.0.1.0.0.2.ip6.arpa.',
        'IPv6 Kea DDNS intent renders the expected reverse zone'
    );
    is(
        $ddns_intent->{reverse_domains}[0]{'dns-servers'}[0]{'ip-address'},
        '2001:db8::1',
        'IPv6 Kea DDNS resolves <xcatmaster> to the IPv6-facing management address'
    );
}

{
    # Kea D2 on a service node must update the authoritative management-node
    # DNS server, not the service node's local forwarding cache or slave.
    no warnings 'redefine';
    local *xCAT::Utils::isServiceNode = sub { return 1; };

    is(
        xCAT_plugin::dhcp::kea_ddns_update_target(
            '10.0.0.0', '<xcatmaster>, 192.0.2.53'
        ),
        '192.0.2.53',
        'service-node D2 uses the documented IPv4 management-node fallback'
    );
    is(
        xCAT_plugin::dhcp::kea_ddns_update_target(
            '2001:db8:7309::', '<xcatmaster>, 2001:db8::53'
        ),
        '2001:db8::53',
        'service-node D2 uses the documented IPv6 management-node fallback'
    );
    is(
        xCAT_plugin::dhcp::kea_ddns_update_target(
            '10.0.0.0', '192.0.2.54, 192.0.2.53'
        ),
        '192.0.2.54',
        'service-node D2 preserves an explicit first IPv4 DNS target'
    );
    is(
        xCAT_plugin::dhcp::kea_ddns_update_target(
            '2001:db8:7309::', '2001:db8::54, 2001:db8::53'
        ),
        '2001:db8::54',
        'service-node D2 preserves an explicit first IPv6 DNS target'
    );

    {
        local *xCAT::TableUtils::get_site_attribute = sub {
            return $_[-1] eq 'master' ? ('mn.example.test') : ();
        };
        local *xCAT_plugin::dhcp::getipaddr = sub {
            return '192.0.2.55' if $_[0] eq 'mn.example.test';
            return '2001:db8::56' if $_[0] eq 'dns.example.test';
            return;
        };
        is(
            xCAT_plugin::dhcp::kea_ddns_update_target(
                '2001:db8:7309::', '<xcatmaster>'
            ),
            '192.0.2.55',
            'service-node D2 resolves site.master when no explicit fallback is configured'
        );
        is(
            xCAT_plugin::dhcp::kea_ddns_update_target(
                '2001:db8:7309::', 'dns.example.test'
            ),
            '2001:db8::56',
            'service-node D2 resolves an explicit DNS hostname to an address literal'
        );
        is(
            xCAT_plugin::dhcp::kea_ddns_update_target(
                '2001:db8:7309::', '<xcatmaster>, <xcatmaster>'
            ),
            '192.0.2.55',
            'duplicate placeholders fall back to the resolvable site.master address'
        );
    }

    {
        local *xCAT_plugin::dhcp::getipaddr = sub { return; };
        is(
            xCAT_plugin::dhcp::kea_ddns_update_target(
                '10.0.0.0', 'not-an-address.invalid'
            ),
            undef,
            'unresolvable explicit D2 targets are omitted instead of breaking Kea validation'
        );
    }

    local *xCAT_plugin::dhcp::kea_ddns_enabled = sub { 1 };
    local *xCAT_plugin::dhcp::kea_ddns_key = sub {
        return ( 'HMAC-SHA256', 'YWJjMTIz' );
    };
    local $xCAT::Table::networks = DHCPKeaIntentNetTable->new(
        {
            %network_entry,
            nameservers => '<xcatmaster>, 192.0.2.53',
        }
    );

    my $ddns_intent = xCAT_plugin::dhcp::kea_build_ddns_intent();
    my @dns_ips =
      map { $_->{'ip-address'} }
      map { @{ $_->{'dns-servers'} || [] } }
      ( @{ $ddns_intent->{forward_domains} || [] }, @{ $ddns_intent->{reverse_domains} || [] } );

    ok( scalar(@dns_ips), 'service-node DDNS intent renders forward and reverse DNS targets' );
    is_deeply(
        [ grep { $_ ne '192.0.2.53' } @dns_ips ],
        [],
        'service-node DDNS intent sends every update to the authoritative management node'
    );
}

{
    no warnings 'redefine';
    local *xCAT::Utils::isServiceNode = sub { return 0; };

    is(
        xCAT_plugin::dhcp::kea_ddns_update_target(
            '10.0.0.0', '<xcatmaster>, 192.0.2.53'
        ),
        '10.0.0.1',
        'management-node D2 keeps the local IPv4-facing target when a fallback is present'
    );
    is(
        xCAT_plugin::dhcp::kea_ddns_update_target(
            '2001:db8:7309::', '<xcatmaster>, 2001:db8::53'
        ),
        '2001:db8::1',
        'management-node D2 keeps the local IPv6-facing target when a fallback is present'
    );
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
        foreach my $node (@$nodes) {
            my $row = $self->{rows}{$node} || {};
            $out{$node} = [ { map { exists($row->{$_}) ? ($_ => $row->{$_}) : () } @$attrs } ];
        }
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
    # S-74. The reservation names the node in two places and both are needed.
    # The "hostname" field is the only name a client cannot displace: with the
    # field absent, Kea 2.4.1 wrote the name the client advertised into the
    # lease and into the DDNS update, and sent it back in option 12 as well, so
    # a node calling itself anything took over the node's DNS record. The
    # host-name option carries the unqualified name for a server that sends it
    # verbatim.
    is( $r->{hostname}, 'svc01',
        'service node reservation carries the hostname field' );
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

    # An IPv6 tftpserver or xcatmaster is not a DHCPv4 next-server. inet_aton
    # cannot read it, and reporting that as an error makes makedhcp fail for a
    # node whose boot server is named in the DHCPv6 reservation instead.
    @errors = ();
    my @v6_tftp = xCAT_plugin::dhcp::next_server_for_node(
        'n1', { tftpserver => '2001:db8:7309::1' } );
    is( scalar(@v6_tftp), 0, 'an IPv6 tftpserver yields no DHCPv4 next-server' );
    is_deeply( \@errors, [],
        'and reports no error, because a DHCPv4 answer was never due' );

    @errors = ();
    my @v6_master = xCAT_plugin::dhcp::next_server_for_node(
        'n1', { xcatmaster => '2001:db8:7309::1' } );
    is( scalar(@v6_master), 0, 'an IPv6 xcatmaster yields no DHCPv4 next-server' );
    is_deeply( \@errors, [], 'and reports no error either' );

    # A name that genuinely does not resolve still has to be reported, or the
    # check above would be satisfied by removing the error path altogether.
    @errors = ();
    my @broken = xCAT_plugin::dhcp::next_server_for_node(
        'n1', { tftpserver => 'no.such.host.invalid' } );
    is( scalar(@broken), 0, 'an unresolvable tftpserver yields no next-server' );
    like( ( $errors[0] || '' ), qr/tftpserver/,
        'and says which attribute to look at' );

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
    # The xNBA and iPXE node classes depend on the netboot method of each node and on whether it
    # boots from SAN, so each record their builder gets carries both.
    my %tables = (
        noderes => DHCPKeaResTable->new( {
            ipxe01  => { netboot => 'ipxe' },
            san01   => { netboot => 'ipxe' },
            san02   => { netboot => 'ipxe' },
            xnba01  => { netboot => 'xnba' },
            grub01  => { netboot => 'grub2' },
        } ),
        mac => DHCPKeaResTable->new( {
            ipxe01 => { mac => '52:54:00:00:20:01' },
            san01  => { mac => '52:54:00:00:20:02' },
            san02  => { mac => '52:54:00:00:20:03' },
            xnba01 => { mac => '52:54:00:00:20:04' },
            grub01 => { mac => '52:54:00:00:20:05' },
        } ),
        iscsi => DHCPKeaResTable->new( { san01 => { server => '192.0.2.5', target => 'iqn.2026-01.test:disk1' }, san02 => { server => '192.0.2.5' } } ),
    );

    no warnings 'redefine';
    local *xCAT::Table::new = sub {
        my ( $class, $name ) = @_;
        return $tables{$name};
    };
    local *xCAT_plugin::dhcp::next_server_for_node = sub { return ( '192.0.2.1', '192.0.2.1' ); };
    my $records;
    local *xCAT::DHCP::BootPolicy::kea_xnba_node_classes = sub {
        my ( $class, %opts ) = @_;
        $records = $opts{nodes};
        return [];
    };

    xCAT_plugin::dhcp::kea_node_client_classes_for_nodes( [qw(ipxe01 san01 san02 xnba01 grub01)] );
    is_deeply(
        { map { $_->{node} => [ $_->{netboot}, $_->{iscsi} ] } @{ $records || [] } },
        { ipxe01 => [ 'ipxe', 0 ], san01 => [ 'ipxe', 1 ], san02 => [ 'ipxe', 0 ], xnba01 => [ 'xnba', 0 ] },
        'ipxe and xnba nodes get node classes with their method, and an iscsi entry without a target is no SAN disk'
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
    # Two netboot methods the Kea path used to answer differently from ISC.
    #
    # nimol: ISC supersedes server.filename with /vios/nodes/<node>; Kea named no
    # boot file, so a VIOS install got nothing to fetch.
    #
    # petitboot: ISC sends the conf-file option and nothing else. Kea also set
    # boot-file-name, and petitboot acts on one when it sees it, sending the
    # machine after a file that was never put there.
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
    # A ScaleMP hypervisor and an ISAN iSCSI initiator both need a different
    # answer from the machine next to them, and on ISC both are an if/else in the
    # node's host block. A Kea reservation outranks every class, so neither the
    # pxe boot file nor an ISAN node's root path is reserved: what the
    # reservation does not name, a class can decide.
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

    # The empty container comes first: an encapsulated space travels only inside
    # the option that encapsulates it, and option 43 carries no data of its own,
    # so without it Kea sends neither sub-option. ISC builds the container from
    # the sub-option declarations.
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
    # A NIC marked *NOIP* is meant to be answered with nothing. ISC writes
    # "deny booting;"; Kea discards a packet assigned to the class named DROP,
    # and nothing else will do -- skipping the reservation still leaves the
    # architecture classes handing the interface a boot file.
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
    # A node that has an operating system, and a Windows UEFI install waiting on
    # proxyDHCP, both get no boot file. ISC writes filename = "" into the host
    # block, which outranks the subnet chain.
    #
    # On Kea the empty boot-file-name below is necessary and not sufficient: Kea
    # reads it as "not specified" and falls through to the classes. What stops
    # them is the xcat-localboot class, asserted further down.
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

{
    # spec.md S-31. Withholding the node's classes and writing an empty
    # boot-file-name does not stop an installed node being netbooted: Kea reads
    # the empty string as "not specified" and the shared classes hand it a loader
    # on architecture alone. It then returns as an xNBA second stage and is
    # answered with the network's script, reinstalling on every power cycle.
    #
    # So the MACs go into one class that every boot-naming class excludes.
    my %tables = (
        noderes => DHCPKeaResTable->new(
            {
                booted => { netboot => 'xnba' },
                bootpx => { netboot => 'pxe' },
            }
        ),
        mac => DHCPKeaResTable->new(
            {
                booted => { mac => 'aa:bb:cc:dd:ee:05' },
                bootpx => { mac => 'aa:bb:cc:dd:ee:06' },
            }
        ),
        chain => DHCPKeaResTable->new(
            {
                booted => { currstate => 'boot' },
                bootpx => { currstate => 'boot' },
            }
        ),
    );

    no warnings 'redefine';
    local *xCAT::Table::new = sub {
        my ( $class, $name ) = @_;
        return $tables{$name};
    };
    local *xCAT_plugin::dhcp::next_server_for_node = sub { return ( '192.0.2.1', '192.0.2.1' ); };

    # A class of the shape the architecture classes have: it names a boot file
    # and so must learn to exclude these nodes.
    my $config = {
        Dhcp4 => {
            'client-classes' => [
                { name => 'xcat-bios', test => 'option[93].hex == 0x0000', 'boot-file-name' => 'xcat/xnba.kpxe' },
                { name => 'xcat-opal', test => "option[93].hex == 0x000e", 'option-data' => [] },
            ],
        },
    };

    ok( xCAT_plugin::dhcp::kea_sync_node_client_classes( $config, [ 'booted', 'bootpx' ] ),
        'a node that is to boot from its disk changes the configuration' );

    my @names = map { $_->{name} } @{ $config->{Dhcp4}{'client-classes'} };
    my ($localboot) = grep { $_->{name} eq 'xcat-localboot' } @{ $config->{Dhcp4}{'client-classes'} };
    ok( $localboot, 'the installed nodes land in a class of their own' );
    is( $localboot->{test},
        'pkt4.mac == 0xaabbccddee05 or pkt4.mac == 0xaabbccddee06',
        'both netboot methods are in it' );
    is( $names[0], 'xcat-localboot',
        'and it is defined first, because Kea rejects a member() test naming a class below it' );

    my %by_name = map { $_->{name} => $_ } @{ $config->{Dhcp4}{'client-classes'} };
    is( $by_name{'xcat-bios'}{test},
        "(option[93].hex == 0x0000) and not member('xcat-localboot')",
        'a class that names a boot file stops matching them' );
    is( $by_name{'xcat-opal'}{test}, 'option[93].hex == 0x000e',
        'a class that names none is left alone' );

    # Regenerating must not wrap the test one layer deeper every time.
    xCAT_plugin::dhcp::kea_sync_node_client_classes( $config, ['booted'] );
    %by_name = map { $_->{name} => $_ } @{ $config->{Dhcp4}{'client-classes'} };
    is( $by_name{'xcat-bios'}{test},
        "(option[93].hex == 0x0000) and not member('xcat-localboot')",
        'and running makedhcp again writes the same test, not a nested one' );
    is( $by_name{'xcat-localboot'}{test},
        'pkt4.mac == 0xaabbccddee05 or pkt4.mac == 0xaabbccddee06',
        'a makedhcp for one node leaves the rest of the cluster in the class' );

    # With the last of them gone the guard has to come off: a member() test
    # naming a class that no longer exists is a configuration Kea refuses.
    xCAT_plugin::dhcp::kea_remove_node_client_classes( $config, [ 'booted', 'bootpx' ] );
    %by_name = map { $_->{name} => $_ } @{ $config->{Dhcp4}{'client-classes'} };
    ok( !exists $by_name{'xcat-localboot'}, 'with no installed node left the class goes' );
    is( $by_name{'xcat-bios'}{test}, 'option[93].hex == 0x0000',
        'and the guard naming it goes with it' );
}

{
    # An installed node that boots from SAN: its own classes give the loader of its method to a
    # client without iSCSI, and the local-boot class keeps every boot file from a client with iSCSI.
    my %tables = (
        noderes => DHCPKeaResTable->new( { san01 => { netboot => 'ipxe' }, booted => { netboot => 'xnba' } } ),
        mac     => DHCPKeaResTable->new( { san01 => { mac => 'aa:bb:cc:dd:ee:07' }, booted => { mac => 'aa:bb:cc:dd:ee:05' } } ),
        chain   => DHCPKeaResTable->new( { san01 => { currstate => 'iscsiboot' }, booted => { currstate => 'boot' } } ),
        iscsi   => DHCPKeaResTable->new( { san01 => { server => '192.0.2.9', target => 'iqn.2024-01.test:san01', lun => 0 } } ),
    );

    no warnings 'redefine';
    local *xCAT::Table::new = sub {
        my ( $class, $name ) = @_;
        return $tables{$name};
    };
    local *xCAT_plugin::dhcp::next_server_for_node = sub { return ( '192.0.2.1', '192.0.2.1' ); };

    my $config = {
        Dhcp4 => {
            'client-classes' => [
                { name => 'xcat-bios', test => 'option[93].hex == 0x0000', 'boot-file-name' => 'xcat/ipxe/i386/undionly.kpxe' },
            ],
        },
    };
    xCAT_plugin::dhcp::kea_sync_node_client_classes( $config, [ 'san01', 'booted' ] );
    my %by_name = map { $_->{name} => $_ } @{ $config->{Dhcp4}{'client-classes'} };
    is( $by_name{'xcat-localboot'}{test},
        'pkt4.mac == 0xaabbccddee05 or (pkt4.mac == 0xaabbccddee07 and option[175].option[17].exists)',
        'an installed SAN node is in the local-boot class for a client with iSCSI only' );
    is( $by_name{'xcat-ipxe-san01-aabbccddee07-bios-san'}{'boot-file-name'}, 'xcat/ipxe/i386/undionly.kpxe',
        'and gets the upstream loader on a BIOS client without iSCSI' );
    like( $by_name{'xcat-ipxe-san01-aabbccddee07-bios-san'}{test}, qr/\Qand not member('xcat-localboot')\E$/,
        'under the guard that every boot-file class carries' );
    is( $by_name{'xcat-ipxe-san01-aabbccddee07-uefi-san'}{'boot-file-name'}, 'xcat/ipxe/x86_64-sb/snponly-shim.efi',
        'and the upstream UEFI loader on a UEFI client without iSCSI' );

    xCAT_plugin::dhcp::kea_remove_node_client_classes( $config, ['san01'] );
    %by_name = map { $_->{name} => $_ } @{ $config->{Dhcp4}{'client-classes'} };
    is( $by_name{'xcat-localboot'}{test}, 'pkt4.mac == 0xaabbccddee05',
        'removing the SAN node takes it out of the local-boot class' );
    ok( !grep( { /-san$/ } keys %by_name ), 'and removes its classes' );
}

{
    # A Windows UEFI install deferred to proxyDHCP gets an empty boot-file-name
    # in its reservation, and Kea reads that as "not specified". So its MAC
    # must be excluded from every class that names a boot file, or
    # xcat-uefi-x64 hands it xcat/xnba.efi.
    my %tables = (
        noderes => DHCPKeaResTable->new(
            {
                win01 => { netboot => 'xnba' },
                cn01  => { netboot => 'xnba' },
            }
        ),
        mac => DHCPKeaResTable->new(
            {
                win01 => { mac => 'aa:bb:cc:dd:ee:08' },
                cn01  => { mac => 'aa:bb:cc:dd:ee:09' },
            }
        ),
        chain => DHCPKeaResTable->new(
            { win01 => { currstate => 'install' }, cn01 => { currstate => 'install' } }
        ),
        nodetype => DHCPKeaResTable->new(
            { win01 => { os => 'win2022' }, cn01 => { os => 'rhels9' } }
        ),
    );

    no warnings 'redefine';
    local *xCAT::Table::new = sub {
        my ( $class, $name ) = @_;
        return $tables{$name};
    };
    local *xCAT_plugin::dhcp::next_server_for_node = sub { return ( '192.0.2.1', '192.0.2.1' ); };
    local *xCAT_plugin::dhcp::proxydhcp = sub { return 1; };

    my $config = {
        Dhcp4 => {
            'client-classes' => xCAT::DHCP::BootPolicy->kea_client_classes( ipxe_bios => 1, ipxe_uefi => 1 ),
        },
    };
    xCAT_plugin::dhcp::kea_sync_node_client_classes( $config, [ 'win01', 'cn01' ] );
    my %by_name = map { $_->{name} => $_ } @{ $config->{Dhcp4}{'client-classes'} };

    my $excluded = $by_name{'xcat-localboot'};
    ok( $excluded, 'a proxyDHCP node puts its MAC in the class the boot-file classes exclude' );
    is( $excluded ? $excluded->{test} : undef, 'pkt4.mac == 0xaabbccddee08',
        'the proxyDHCP node is in it, and the node that netboots is not' );

    my @unguarded = sort map { $_->{name} }
      grep { defined $_->{'boot-file-name'} and $_->{test} !~ /\Qnot member('xcat-localboot')\E$/ }
      @{ $config->{Dhcp4}{'client-classes'} };
    is_deeply( \@unguarded, [], 'no class that names a boot file can match the proxyDHCP node' );

    is( $by_name{'xcat-uefi-x64'}{'boot-file-name'}, 'xcat/ipxe/x86_64-sb/snponly-shim.efi',
        'the UEFI class still names the upstream UEFI loader for every other client' );

    ok( $by_name{'xcat-proxydhcp-win01-aabbccddee08'},
        'the proxyDHCP node keeps the class that tags its reply PXEClient' );
    unlike( $by_name{'xcat-proxydhcp-win01-aabbccddee08'}{test} // '', qr/xcat-localboot/,
        'and that class, which names no boot file, is not excluded from it' );
}

{
    # makedhcp <node> writes the loaded config back through encode_config, not
    # through the renderer. Kea rejects an option flag written as the number 1.
    my %tables = (
        noderes  => DHCPKeaResTable->new( { win01 => { netboot => 'xnba' } } ),
        mac      => DHCPKeaResTable->new( { win01 => { mac => 'aa:bb:cc:dd:ee:0a' } } ),
        chain    => DHCPKeaResTable->new( { win01 => { currstate => 'install' } } ),
        nodetype => DHCPKeaResTable->new( { win01 => { os => 'win2022' } } ),
    );

    no warnings 'redefine';
    local *xCAT::Table::new = sub {
        my ( $class, $name ) = @_;
        return $tables{$name};
    };
    local *xCAT_plugin::dhcp::next_server_for_node = sub { return ( '192.0.2.1', '192.0.2.1' ); };
    local *xCAT_plugin::dhcp::proxydhcp = sub { return 1; };

    my $config = { Dhcp4 => { 'client-classes' => [] } };
    xCAT_plugin::dhcp::kea_sync_node_client_classes( $config, ['win01'] );
    my $written = JSON::decode_json( xCAT::DHCP::Backend::Kea->new()->encode_config($config) );
    my ($deferral) = grep { $_->{name} eq 'xcat-proxydhcp-win01-aabbccddee0a' }
      @{ $written->{Dhcp4}{'client-classes'} };
    ok( $deferral, 'the proxyDHCP class is written by a makedhcp for one node' );
    is( ref( $deferral ? $deferral->{'option-data'}[0]{'always-send'} : undef ), 'JSON::PP::Boolean',
        'and its always-send flag is written as a boolean, which is what Kea parses' );
}

# Without the noderes or mac table there are no node classes. kea_sync_node_client_classes reads
# all three lists of the answer, so each one must be present, empty.
{
    no warnings 'redefine';
    local *xCAT::Table::new = sub { return; };
    is_deeply( xCAT_plugin::dhcp::kea_node_client_classes_for_nodes(['cn01']),
        { classes => [], noip => [], localboot => [] },
        'with no noderes or mac table there are no classes, no NOIP MACs and no localboot MACs' );
    my $config = { Dhcp4 => { 'client-classes' => [] } };
    ok( eval { xCAT_plugin::dhcp::kea_sync_node_client_classes( $config, ['cn01'] ); 1 },
        'syncing the node client classes with no noderes or mac table does not die' ) or diag($@);
}

{
    # A "!remote!<nic>" mgtifname is reached through a relay, so %activenics never holds it.
    my %local_net = (
        net          => '10.0.0.0',
        mask         => '255.255.255.0',
        mgtifname    => 'eth0',
        dynamicrange => '10.0.0.100-10.0.0.150',
        domain       => 'cluster.test',
        tftpserver   => '<xcatmaster>',
    );
    my %relayed_net = (
        net        => '100.100.100.0',
        mask       => '255.255.255.0',
        mgtifname  => '!remote!eth0',
        domain     => 'cluster.test',
        tftpserver => '<xcatmaster>',
    );

    no warnings 'redefine';
    local *xCAT::NetworkUtils::thishostisnot = sub { return 0; };
    local *xCAT_plugin::dhcp::kea_ipv4_routes = sub {
        return (
            [ '10.0.0.0',      'eth0',         '255.255.255.0', '' ],
            [ '100.100.100.0', '!remote!eth0', '255.255.255.0', '' ],
        );
    };
    local *xCAT_plugin::dhcp::kea_boot_client_classes   = sub { return []; };
    local *xCAT_plugin::dhcp::kea_option_defs           = sub { return []; };
    local *xCAT_plugin::dhcp::kea_global_option_data    = sub { return []; };
    local *xCAT_plugin::dhcp::kea_dhcp_lease_time       = sub { return 43200; };
    local *xCAT_plugin::dhcp::kea_control_agent_enabled = sub { return 0; };

    local $xCAT::Table::networks =
      DHCPKeaIntentMultiNetTable->new( \%local_net, \%relayed_net );

    my $intent = xCAT_plugin::dhcp::kea_build_dhcp4_intent(
        bless( {}, 'DHCPKeaIntentBackend' ), { eth0 => 1 }
    );

    is_deeply(
        [
            map { [ $_->{subnet}, exists $_->{interface} ? $_->{interface} : undef ] }
            sort { $a->{subnet} cmp $b->{subnet} } @{ $intent->{subnets} }
        ],
        [ [ '10.0.0.0/24', 'eth0' ], [ '100.100.100.0/24', undef ] ],
        'the relayed network gets a subnet, and it names no local interface'
    );
    is_deeply(
        $intent->{interfaces}, ['eth0'],
        'the relay marker is not served as an interface'
    );
}

for my $case ([undef, ''], ['', ''], [0, ''], ['0', ''], ['80', ''], ['080', ':080'], ['8080', ':8080']) {
    my ($port, $suffix) = @$case;
    no warnings 'redefine';
    local *xCAT::TableUtils::get_site_attribute = sub {
        return ($port) if $_[-1] eq 'httpport' && defined($port);
        return;
    };
    for my $method (qw(onie petitboot)) {
        my $boot = xCAT_plugin::dhcp::kea_boot_for_node('cn1', {netboot => $method},
            {currstate => 'install'}, {}, {}, '192.0.2.1');
        my $path = $method eq 'onie' ? '/install/onie/onie-installer' : '/tftpboot/petitboot/cn1';
        is($boot->{'option-data'}[0]{data}, "http://192.0.2.1$suffix$path",
            "$method reservation preserves site port defaulting");
    }
}
for my $case (['80', ''], ['080', ':080'], ['8080', ':8080']) {
    my ($port, $suffix) = @$case;
    my $opal = xCAT_plugin::dhcp::kea_opal_client_class('192.0.2.0', 24, '192.0.2.1', $port);
    is($opal->{'option-data'}[0]{data}, "http://192.0.2.1$suffix/tftpboot/pxelinux.cfg/p/192.0.2.0_24",
        'OPAL preserves the supplied port');
    my $subnet = xCAT_plugin::dhcp::kea_subnet4_intent(
        DHCPKeaIntentNetTable->new(\%network_entry), '10.0.0.0', '255.255.255.0', 'eth0', 0, 1, $port,
    );
    my ($onie) = grep { $_->{name} eq 'xcat-onie-10.0.0.0_24' } @{$subnet->{client_classes}};
    is($onie->{'option-data'}[0]{data}, "http://10.0.0.1$suffix/install/onie/onie-installer",
        'subnet generation preserves the supplied port');
}

{
    my %res_tables = (
        noderes => DHCPKeaResTable->new(
            {
                'nodev6'     => { netboot => 'grub2',      tftpserver => '<xcatmaster>', servicenode => 'sn01' },
                'nodev6http' => { netboot => 'grub2-http', tftpserver => 'boot6.example.test' },
                'nodev6tftp' => { netboot => 'grub2-tftp', tftpserver => 'boot6.example.test' },
                'nodev6xnba' => { netboot => 'xnba',       tftpserver => 'boot6.example.test' },
                'nodev6aliasv4' => { netboot => 'xnba',    tftpserver => '<xcatmaster>' },
                'nodev4aliasv6' => { netboot => 'xnba',    tftpserver => '<xcatmaster>' },
            }
        ),
        mac => DHCPKeaResTable->new(
            {
                'nodev6'     => { mac => '02:00:00:00:00:61' },
                'nodev6http' => { mac => '02:00:00:00:00:62' },
                'nodev6tftp' => { mac => '02:00:00:00:00:64' },
                'nodev6xnba' => { mac => '02:00:00:00:00:63' },
                'nodev6aliasv4' => { mac => '02:00:00:00:00:65!aliasv4' },
                'nodev4aliasv6' => { mac => '02:00:00:00:00:66!aliasv6' },
            }
        ),
        vpd => DHCPKeaResTable->new(
            {
                'nodev6'     => { uuid => '00112233-4455-6677-8899-aabbccddeeff' },
                'nodev6http' => {},
                'nodev6tftp' => {},
                'nodev6xnba' => {},
            }
        ),
    );

    no warnings 'redefine';
    local *xCAT::Table::new = sub {
        my ( $class, $name ) = @_;
        return $res_tables{$name};
    };
    my %node_addresses = (
        nodev6             => '2001:db8:61::50',
        nodev6http         => '2001:db8:62::50',
        nodev6tftp         => '2001:db8:64::50',
        nodev6xnba         => '2001:db8:63::50',
        'boot6.example.test' => '2001:db8::10',
        aliasv6            => '2001:db8:66::50',
        nodev6aliasv4      => '2001:db8:65::50',
    );
    my %node_v4_addresses = (
        aliasv4       => '192.0.2.65',
        nodev4aliasv6 => '192.0.2.66',
    );
    my $v6_getipaddr = sub {
        my ( $host, %opt ) = @_;
        return $node_v4_addresses{$host} if $opt{OnlyV4};
        return $node_addresses{$host} if $opt{OnlyV6};
        return;
    };
    local *xCAT::NetworkUtils::getipaddr = $v6_getipaddr;
    local *xCAT_plugin::dhcp::getipaddr = $v6_getipaddr;
    local *xCAT::NetworkUtils::my_ip_facing_family = sub {
        my ( $class, $peer, $family ) = @_;
        return ( 1, 'unexpected address family' ) unless $family == 6;
        return ( 0, '2001:db8::1' );
    };
    local *xCAT_plugin::dhcp::ipIsDynamic = sub { return 0; };

    my @errors;
    local $xCAT_plugin::dhcp::callback = sub {
        my $resp = shift;
        push @errors, @{ $resp->{error} } if $resp->{error};
    };

    my $backend = bless {}, 'DHCPKeaRes6Backend';
    {
        package DHCPKeaRes6Backend;
        sub subnet_id_for_ip { return 61; }
    }

    my $reservations = xCAT_plugin::dhcp::kea_build_node_reservations6(
        $backend,
        {},
        [qw(nodev6 nodev6http nodev6tftp nodev6xnba)]
    );

    is( scalar(@errors), 0, 'DHCPv6 reservations build without errors' );
    is( scalar(@$reservations), 4, 'all known IPv6 nodes receive reservations' );

    my %by_hostname = map { $_->{hostname} => $_ } @$reservations;
    my $grub2 = $by_hostname{nodev6};
    is( $grub2->{duid}, '00:04:00:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff', 'DHCPv6 reservation retains DUID-UUID matching' );
    is( $grub2->{'option-data'}[0]{name}, 'bootfile-url', 'grub2 reservation carries RFC 5970 bootfile-url' );
    is( $grub2->{'option-data'}[0]{data}, 'tftp://[2001:db8::1]/boot/grub2/grub2-nodev6', 'grub2 bootfile URL uses the IPv6-facing xCAT server and bracketed authority' );
    ok( $grub2->{'option-data'}[0]{'always-send'}, 'grub2 bootfile URL is always sent' );

    my $grub2_http = $by_hostname{nodev6http};
    is( $grub2_http->{'hw-address'}, '02:00:00:00:00:62', 'DHCPv6 reservation retains hardware-address fallback' );
    is( $grub2_http->{'option-data'}[0]{data}, 'tftp://[2001:db8::10]/boot/grub2/grub2-nodev6http', 'grub2-http firmware handoff still loads GRUB over TFTP from the configured IPv6 server' );

    my $grub2_tftp = $by_hostname{nodev6tftp};
    is( $grub2_tftp->{'option-data'}[0]{data}, 'tftp://[2001:db8::10]/boot/grub2/grub2-nodev6tftp', 'grub2-tftp receives the DHCPv6 bootfile URL advertised as supported on x86_64' );

    ok( !exists($by_hostname{nodev6xnba}{'option-data'}), 'unsupported IPv6 netboot modes do not receive a GRUB bootfile URL' );

    @errors = ();
    my $v4_reservations = xCAT_plugin::dhcp::kea_build_node_reservations(
        $backend,
        {},
        [qw(nodev6 nodev6http nodev6tftp nodev6xnba)]
    );
    is( scalar(@errors), 0, 'IPv6-only nodes do not enter the IPv4 TFTP resolver' );
    is( scalar(@$v4_reservations), 0, 'IPv6-only nodes do not create DHCPv4 reservations' );

    {
        my $next_server_calls = 0;
        local *xCAT_plugin::dhcp::kea_next_server_for_node = sub {
            $next_server_calls++;
            return ('192.0.2.1', '192.0.2.1');
        };
        my $config = { Dhcp4 => { 'client-classes' => [] } };
        my $saved_mac = $res_tables{mac};
        $res_tables{mac} = DHCPKeaResTable->new(
            { 'nodev6xnba' => { mac => '02:00:00:00:00:63!*NOIP*' } }
        );

        xCAT_plugin::dhcp::kea_sync_node_client_classes(
            $config, ['nodev6xnba']
        );
        $res_tables{mac} = $saved_mac;

        is( scalar(@{ $config->{Dhcp4}{'client-classes'} }), 0, 'xNBA does not create a DHCPv4 client class for an explicit *NOIP* MAC alias' );
        is( $next_server_calls, 0, 'IPv6-only xNBA node does not enter the IPv4 TFTP resolver' );
    }

    {
        local *xCAT::NetworkUtils::my_ip_facing = sub {
            return ( 0, '192.0.2.1' );
        };
        my $config = { Dhcp4 => { 'client-classes' => [] } };

        xCAT_plugin::dhcp::kea_sync_node_client_classes(
            $config, [qw(nodev6aliasv4 nodev4aliasv6)]
        );

        my @owners = map {
            $_->{'user-context'}{'xcat-node'}
        } @{ $config->{Dhcp4}{'client-classes'} };
        ok(
            scalar(grep { $_ eq 'nodev6aliasv4' } @owners),
            'IPv6 base node retains xNBA when its per-MAC alias is IPv4'
        );
        ok(
            !scalar(grep { $_ eq 'nodev4aliasv6' } @owners),
            'IPv4 base node omits xNBA when its per-MAC alias is IPv6-only'
        );
    }

    {
        local *xCAT::TableUtils::get_site_attribute = sub {
            return $_[-1] eq 'disjointdhcps' ? ('1') : ();
        };
        local $xCAT::ServiceNodeUtils::dhcp_servers = ['configured-dhcp-service'];
        local $xCAT::ServiceNodeUtils::service_nodes = {
            'sn01' => ['nodev6'],
        };
        local *xCAT::NetworkUtils::thishostisnot = sub { return 1; };
        @errors = ();
        my $remote = xCAT_plugin::dhcp::kea_build_node_reservations6(
            $backend, {}, ['nodev6']
        );
        is( scalar(@$remote), 0, 'disjoint DHCPv6 omits a node owned by another service node' );
        is( scalar(@errors), 0, 'non-owning DHCPv6 server skips the node without an error' );
    }

    {
        local *xCAT::TableUtils::get_site_attribute = sub {
            return $_[-1] eq 'disjointdhcps' ? ('1') : ();
        };
        local $xCAT::ServiceNodeUtils::dhcp_servers = ['configured-dhcp-service'];
        local $xCAT::ServiceNodeUtils::service_nodes = {
            'remote-service-node' => ['nodev6'],
        };
        local *xCAT::NetworkUtils::thishostisnot = sub {
            return $_[-1] eq 'dynamic-dhcp6-owner' ? 0 : 1;
        };
        $res_tables{networks} = DHCPKeaIntentNetTable->new(
            {
                net          => '2001:db8:99::/64',
                dynamicrange => '2001:db8:99::100/120',
                dhcpserver   => 'dynamic-dhcp6-owner',
            }
        );

        my $owned = xCAT_plugin::dhcp::kea_build_node_reservations6(
            $backend, {}, ['nodev6']
        );
        delete $res_tables{networks};

        is( scalar(@$owned), 1, 'global dynamic-range DHCP owner retains an unrelated IPv6 reservation like legacy dispatch' );
    }
}

done_testing();
