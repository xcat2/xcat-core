#!/usr/bin/env perl
use strict;
use warnings;
use Carp qw(croak);
use FindBin;
use File::Temp qw(tempdir);
use IPC::Open3;
use Symbol qw(gensym);
use Test::More;

my $planner = "$FindBin::Bin/../../xCAT/postscripts/confignetwork-freebsd.awk";
my $directory = tempdir(CLEANUP => 1);

sub invoke {
    my ($environment, @arguments) = @_;
    local %ENV = (PATH => $ENV{PATH}, LC_ALL => 'C', %$environment);
    my $errors = gensym();
    my $pid = open3(my $input, my $output, $errors, 'awk', '-f', $planner, @arguments);
    close($input) or croak $!;
    my $stdout = do { local $/ = undef; <$output> } // '';
    my $stderr = do { local $/ = undef; <$errors> } // '';
    close($output) or croak $!;
    close($errors) or croak $!;
    waitpid($pid, 0) == $pid or croak $!;
    return ($?, $stdout, $stderr);
}

sub base {
    return {
        NICTYPES => 'vtnet1!ethernet',
        NICIPS => 'vtnet1!192.0.2.10|2001:db8:1::10',
        NICNETWORKS => 'vtnet1!data4|data6',
        NETWORKS_LINES => 2,
        NETWORKS_LINE1 => 'netname=data4||net=192.0.2.0||mask=255.255.255.0||gateway=||mtu=||disable=',
        NETWORKS_LINE2 => 'netname=data6||net=2001:db8:1::||mask=64||gateway=||mtu=||disable=',
        IPADDR => '198.51.100.10', MASTER_IP => '198.51.100.1',
    };
}

sub compile_plan {
    my ($environment, $configure_boot) = @_;
    return invoke($environment, '-v', 'bootnic=vtnet0', '-v', 'configure_boot=' . ($configure_boot || 0));
}

sub rejected {
    my ($name, $change, $message, $configure_boot) = @_;
    subtest $name => sub {
        my $environment = base();
        $change->($environment);
        my ($status, $output, $error) = compile_plan($environment, $configure_boot);
        isnt($status, 0, 'the invalid network is rejected');
        is($output, '', 'no partial application plan is emitted');
        like($error, $message, 'the rejection identifies the invalid input');
        done_testing();
    };
    return;
}

sub rows {
    my ($output, $kind) = @_;
    return [map { [split(/\t/x, $_, -1)] }
        grep { index($_, "$kind\t") == 0 } split(/\n/x, $output)];
}

sub value {
    my ($output, $kind, $key) = @_;
    my @matching = grep { $_->[1] eq $key } @{ rows($output, $kind) };
    return @matching == 1 ? $matching[0][2] : undef;
}

subtest 'physical interface with IPv4 and IPv6' => sub {
    my ($status, $output, $error) = compile_plan(base());
    is($status, 0, 'the standard postscript exports compile');
    is($error, '', 'no diagnostics');
    is_deeply(rows($output, 'I'), [['I', 'vtnet1', 'ethernet']], 'only the data interface changes');
    is(value($output, 'K', 'ifconfig_vtnet1'), 'inet 192.0.2.10/24 mtu 1500 up',
        'persistent IPv4 and netmask use native rc.conf syntax');
    is(value($output, 'K', 'ifconfig_vtnet1_ipv6'), 'inet6 2001:0db8:0001:0000:0000:0000:0000:0010 prefixlen 64',
        'persistent IPv6 uses the IPv6 rc.conf variable');
    is(value($output, 'I', 'vtnet0'), undef, 'the provisioning NIC is preserved');
    done_testing();
};

subtest 'multiple addresses and network MTU' => sub {
    my $environment = base();
    $environment->{NICIPS} = 'vtnet1!192.0.2.10|192.0.2.11|2001:db8:1::10|2001:db8:1::11';
    $environment->{NICNETWORKS} = 'vtnet1!data4|data4|data6|data6';
    $environment->{NETWORKS_LINE1} =~ s/mtu=/mtu=9000/x;
    $environment->{NETWORKS_LINE2} =~ s/mtu=/mtu=9000/x;
    my ($status, $output) = compile_plan($environment);
    is($status, 0, 'aliases compile');
    is(value($output, 'K', 'ifconfig_vtnet1_alias0'), 'inet 192.0.2.11/24', 'IPv4 alias has its own setting');
    is(value($output, 'K', 'ifconfig_vtnet1_alias1'), 'inet6 2001:0db8:0001:0000:0000:0000:0000:0011/64',
        'IPv6 aliases share the numbered alias sequence');
    is(value($output, 'T', 'vtnet1'), 9000, 'network MTU is effective');
    done_testing();
};

subtest 'network MTUs use numeric ordering' => sub {
    my $environment = base();
    $environment->{NETWORKS_LINE2} =~ s/mtu=/mtu=900/x;
    my ($status, $output, $error) = compile_plan($environment);
    isnt($status, 0, 'a three-digit network MTU cannot carry IPv6');
    is($output, '', 'no partial plan is emitted');
    like($error, qr/IPv6[ ]requires[ ]an[ ]MTU/x, 'the IPv6 minimum rejects the network MTU');
    $environment = base();
    $environment->{NICTYPES} .= ',vlan100!vlan';
    $environment->{NICDEVICES} = 'vlan100!vtnet1';
    $environment->{NICIPS} = 'vlan100!192.0.2.10';
    $environment->{NICNETWORKS} = 'vlan100!data4';
    $environment->{NETWORKS_LINE1} =~ s/mtu=/mtu=900/x;
    ($status, $output, $error) = compile_plan($environment);
    is($status, 0, 'a smaller IPv4 VLAN MTU fits the default parent') or diag($error);
    is(value($output, 'T', 'vlan100'), 900, 'the VLAN keeps the requested network MTU');
    is(value($output, 'T', 'vtnet1'), 1500, 'the parent retains its default MTU');
    done_testing();
};

subtest 'data gateways and xcatmaster preserve the installed IPv4 default' => sub {
    for my $gateway ('<xcatmaster>', '203.0.113.1') {
        my $environment = base();
        $environment->{NETWORKS_LINE1} =~ s/gateway=/gateway=$gateway/x;
        my ($status, $output, $error) = compile_plan($environment);
        is($status, 0, 'an unused data-network gateway does not reject the plan') or diag($error);
        is(value($output, 'K', 'defaultrouter'), undef, 'the data network does not replace the default');
    }
    my $environment = base();
    for my $attribute (qw(NICTYPES NICIPS NICNETWORKS)) {
        $environment->{$attribute} =~ s/vtnet1/vtnet0/gx;
    }
    $environment->{IPADDR} = '192.0.2.10';
    $environment->{MASTER_IP} = '192.0.2.1';
    $environment->{NETWORKS_LINE1} =~ s/gateway=/gateway=<xcatmaster>/x;
    my ($status, $output, $error) = compile_plan($environment, 1);
    is($status, 0, 'management adoption accepts the stock gateway token') or diag($error);
    is(value($output, 'K', 'defaultrouter'), undef, 'the token retains the default chosen during installation');
    $environment->{NETWORKS_LINE1} =~ s/<xcatmaster>/192.0.2.1/x;
    ($status, $output, $error) = compile_plan($environment, 1);
    is($status, 0, 'an explicit management gateway compiles') or diag($error);
    is(value($output, 'K', 'defaultrouter'), '192.0.2.1', 'an explicit gateway is persisted');
    done_testing();
};

subtest 'IPv6 CIDR network and slash-prefixed mask' => sub {
    my $environment = base();
    $environment->{NETWORKS_LINE2} =~ s{net=2001:db8:1::[|][|]mask=64}{net=2001:db8:1::/64||mask=/64}x;
    $environment->{NODEROUTENAMES} = 'storage6';
    $environment->{ROUTE_storage6} = '2001:db8:2::/64,/64,2001:db8:1::1,vtnet1';
    my ($status, $output, $error) = compile_plan($environment);
    is($status, 0, 'the existing xCAT IPv6 table notation compiles') or diag($error);
    is(value($output, 'K', 'ifconfig_vtnet1_ipv6'),
        'inet6 2001:0db8:0001:0000:0000:0000:0000:0010 prefixlen 64', 'the node prefix is retained');
    is(value($output, 'K', 'ipv6_route_xcat_net_storage6'),
        '-net 2001:0db8:0002:0000:0000:0000:0000:0000/64 2001:0db8:0001:0000:0000:0000:0000:0001',
        'the selected route retains its prefix and gateway');
    done_testing();
};

sub chain {
    my $environment = base();
    $environment->{NICTYPES} = 'bridge0!bridge,vlan100!vlan,lagg0!bond,vtnet2!ethernet,vtnet1!ethernet';
    $environment->{NICDEVICES} = 'bridge0!vlan100,vlan100!lagg0,lagg0!vtnet1|vtnet2';
    $environment->{NICIPS} =~ s/vtnet1/bridge0/x;
    $environment->{NICNETWORKS} =~ s/vtnet1/bridge0/x;
    $environment->{NICEXTRAPARAMS} = 'lagg0!LAGGPROTO=lacp';
    return $environment;
}

subtest 'aggregate VLAN and bridge dependencies' => sub {
    my $environment = chain();
    my ($status, $output, $error) = compile_plan($environment);
    is($status, 0, 'the composed topology compiles') or diag($error);
    is_deeply([ map { $_->[1] } @{ rows($output, 'I') } ], [qw(vtnet1 vtnet2 lagg0 vlan100 bridge0)],
        'application order follows dependencies regardless of attribute order');
    is_deeply(rows($output, 'C'), [['C', 'lagg0 vlan100 bridge0']], 'clones persist in dependency order');
    is(value($output, 'X', 'lagg0'), 'laggproto lacp laggport vtnet1 laggport vtnet2 mtu 1500 up',
        'bond attributes become native LAGG settings');
    is(value($output, 'X', 'vlan100'), 'vlan 100 vlandev lagg0 mtu 1500 up', 'VLAN keeps the selected parent and tag');
    is(value($output, 'X', 'bridge0'), 'addm vlan100 stp vlan100 mtu 1500 up', 'bridge enables STP by default');
    $environment->{NICTYPES} = join(',', reverse split(/,/x, $environment->{NICTYPES}));
    $environment->{NICDEVICES} = join(',', reverse split(/,/x, $environment->{NICDEVICES}));
    my ($second_status, $second_output) = compile_plan($environment);
    is($second_status, 0, 'reordered definitions compile');
    is($second_output, $output, 'the plan is deterministic');
    done_testing();
};

subtest 'selected native routes and IPv6 default gateway' => sub {
    my $environment = base();
    $environment->{NETWORKS_LINE2} =~ s/gateway=/gateway=fe80::1/x;
    $environment->{NODEROUTENAMES} = 'data,storage6';
    $environment->{ROUTE_data} = '203.0.113.0,255.255.255.0,192.0.2.1,vtnet1';
    $environment->{ROUTE_storage6} = '2001:db8:2::,64,fe80::1,vtnet1';
    my ($status, $output, $error) = compile_plan($environment);
    is($status, 0, 'routes compile') or diag($error);
    is(value($output, 'K', 'route_xcat_net_data'), '-net 203.0.113.0/24 192.0.2.1',
        'the selected IPv4 route persists');
    is(value($output, 'K', 'ipv6_route_xcat_net_storage6'),
        '-net 2001:0db8:0002:0000:0000:0000:0000:0000/64 fe80:0000:0000:0000:0000:0000:0000:0001%vtnet1',
        'link-local IPv6 gateway includes its interface scope');
    is(value($output, 'K', 'ipv6_defaultrouter'), 'fe80:0000:0000:0000:0000:0000:0000:0001%vtnet1',
        'IPv6 default gateway has a scope');
    is(value($output, 'K', 'defaultrouter'), undef, 'additional interfaces do not change the IPv4 default route');
    done_testing();
};

subtest 'a static address and clone MAC use separate native address families' => sub {
    my $environment = chain();
    $environment->{NICEXTRAPARAMS} .= ',bridge0!MACADDR=52:54:00:12:34:56';
    $environment->{NICIPS} = 'bridge0!192.0.2.10|192.0.2.11|2001:db8:1::10';
    $environment->{NICNETWORKS} = 'bridge0!data4|data4|data6';
    my ($status, $plan, $error) = compile_plan($environment);
    is($status, 0, 'the static clone compiles') or diag($error);
    is(value($plan, 'K', 'ifconfig_bridge0'),
        'ether 52:54:00:12:34:56 addm vlan100 stp vlan100 mtu 1500 up',
        'link configuration contains no IP address-family argument');
    is(value($plan, 'K', 'ifconfig_bridge0_alias0'), 'inet 192.0.2.10/24', 'the first IPv4 address persists separately');
    is(value($plan, 'K', 'ifconfig_bridge0_alias1'), 'inet 192.0.2.11/24', 'the second IPv4 address keeps a distinct alias');
    like(value($plan, 'K', 'ifconfig_bridge0_ipv6'), qr/^inet6[ ]/x, 'IPv6 retains its separate native command');
};

subtest 'management migration requires the existing IPv4 identity' => sub {
    my $environment = chain();
    $environment->{NICTYPES} =~ s/vtnet1/vtnet0/gx;
    $environment->{NICDEVICES} =~ s/vtnet1/vtnet0/gx;
    my ($denied, undef, $error) = compile_plan($environment);
    isnt($denied, 0, 'the default invocation cannot enslave the installation NIC');
    like($error, qr/confignetwork[ ]-s/x, 'the explicit management option is identified');
    my ($missing) = compile_plan($environment, 1);
    isnt($missing, 0, 'the management option cannot discard the node address');
    $environment->{IPADDR} = '192.0.2.10';
    my ($status, $output, $diagnostic) = compile_plan($environment, 1);
    is($status, 0, 'the declared topology retains the management address') or diag($diagnostic);
    is_deeply(rows($output, 'A')->[0], ['A', 'bridge0', 'inet', '192.0.2.10', '24'], 'the identity moves to the bridge');
    done_testing();
};

my @invalid = (
    ['duplicate interface', sub { $_[0]{NICTYPES} .= ',vtnet1!ethernet'; }, qr/Duplicate[ ]NICTYPES/x],
    ['missing type', sub { $_[0]{NICTYPES} = ''; }, qr/nictypes/x],
    ['unsafe interface', sub { $_[0]{NICTYPES} = 'vtnet1;id!ethernet'; }, qr/interface!value/x],
    ['unknown option', sub { $_[0]{NICEXTRAPARAMS} = 'vtnet1!ONBOOT=no'; }, qr/Unsupported[ ]FreeBSD[ ]option/x],
    ['option injection', sub { $_[0]{NICEXTRAPARAMS} = 'vtnet1!MTU=1500;id'; }, qr/Invalid[ ]MTU/x],
    ['duplicate option', sub { $_[0]{NICEXTRAPARAMS} = 'vtnet1!MTU=1500 MTU=9000'; }, qr/Duplicate[ ]option/x],
    ['custom script', sub { $_[0]{NICCUSTOMSCRIPTS} = 'vtnet1!configure'; }, qr/separate[ ]postscript/x],
    ['missing network', sub { $_[0]{NICNETWORKS} = 'vtnet1!missing'; }, qr/Missing,[ ]duplicate[ ]or[ ]disabled[ ]network/x],
    ['disabled network', sub { $_[0]{NETWORKS_LINE1} =~ s/disable=/disable=yes/x; }, qr/disabled[ ]network/x],
    ['duplicate network', sub { $_[0]{NETWORKS_LINES} = 3; $_[0]{NETWORKS_LINE3} = $_[0]{NETWORKS_LINE1}; }, qr/duplicate[ ]or[ ]disabled[ ]network/x],
    ['wrong subnet', sub { $_[0]{NICIPS} =~ s/192\.0\.2/192.0.3/x; }, qr/outside[ ]network/x],
    ['wrong address count', sub { $_[0]{NICNETWORKS} .= '|data4'; }, qr/same[ ]addresses/x],
    ['noncontiguous mask', sub { $_[0]{NETWORKS_LINE1} =~ s/255\.255\.255\.0/255.0.255.0/x; }, qr/Noncontiguous/x],
    ['invalid IPv6 prefix', sub { $_[0]{NETWORKS_LINE2} =~ s/mask=64/mask=129/x; }, qr/Invalid[ ]IPv6[ ]prefix/x],
    ['conflicting IPv6 prefix', sub { $_[0]{NETWORKS_LINE2} =~ s{net=2001:db8:1::}{net=2001:db8:1::/63}x; }, qr/Conflicting[ ]network[ ]prefix/x],
    ['network address', sub { $_[0]{NICIPS} =~ s/192\.0\.2\.10/192.0.2.0/x; }, qr/subnet[ ]or[ ]broadcast/x],
    ['broadcast address', sub { $_[0]{NICIPS} =~ s/192\.0\.2\.10/192.0.2.255/x; }, qr/subnet[ ]or[ ]broadcast/x],
    ['IPv4 leading zero', sub { $_[0]{NICIPS} =~ s/192\.0\.2\.10/192.0.2.010/x; }, qr/Invalid[ ]unicast[ ]IPv4/x],
    ['IPv4 multicast', sub { $_[0]{NICIPS} =~ s/192\.0\.2\.10/224.0.2.10/x; }, qr/Invalid[ ]unicast[ ]IPv4/x],
    ['IPv6 multicast', sub { $_[0]{NICIPS} =~ s/2001:db8:1::10/ff02::10/x; }, qr/Invalid[ ]unicast[ ]IPv6/x],
    ['IPv6 mapped IPv4', sub { $_[0]{NICIPS} =~ s/2001:db8:1::10/::ffff:c000:20a/x; }, qr/Invalid[ ]unicast[ ]IPv6/x],
    ['IPv6 malformed abbreviation', sub { $_[0]{NICIPS} =~ s/2001:db8:1::10/2001:::10/x; }, qr/Invalid[ ]unicast[ ]IPv6/x],
    ['IPv6 duplicate abbreviation', sub { $_[0]{NICIPS} =~ s/2001:db8:1::10/2001::1::10/x; }, qr/Invalid[ ]unicast[ ]IPv6/x],
    ['IPv6 link-local node address', sub { $_[0]{NICIPS} =~ s/2001:db8:1::10/fe80::10/x; }, qr/Link-local[ ]node/x],
    ['duplicate address', sub { $_[0]{NICIPS} = 'vtnet1!192.0.2.10|192.0.2.10'; $_[0]{NICNETWORKS} = 'vtnet1!data4'; }, qr/Duplicate[ ]node[ ]address/x],
    ['IPv6 MTU too small', sub { $_[0]{NICEXTRAPARAMS} = 'vtnet1!MTU=1000'; }, qr/MTU[ ]of[ ]at[ ]least[ ]1280/x],
    ['off-subnet gateway', sub { $_[0]{NETWORKS_LINE2} =~ s/gateway=/gateway=2001:db8:99::1/x; }, qr/Gateway[ ]is[ ]outside/x],
    ['missing route export', sub { $_[0]{NODEROUTENAMES} = 'missing'; }, qr/Missing[ ]or[ ]invalid[ ]selected[ ]route/x],
    ['route without interface', sub { $_[0]{NODEROUTENAMES} = 'data'; $_[0]{ROUTE_data} = '203.0.113.0,255.255.255.0,192.0.2.1,'; }, qr/configured[ ]ifname/x],
    ['off-link route gateway', sub { $_[0]{NODEROUTENAMES} = 'data'; $_[0]{ROUTE_data} = '203.0.113.0,255.255.255.0,198.51.100.1,vtnet1'; }, qr/not[ ]reachable/x],
    ['IPv6 route on disabled interface', sub {
        $_[0]{NICTYPES} .= ',vtnet2!ethernet';
        $_[0]{NODEROUTENAMES} = 'data';
        $_[0]{ROUTE_data} = '2001:db8:2::,64,fe80::1,vtnet2';
    }, qr/not[ ]reachable/x],
    ['network host bits', sub { $_[0]{NETWORKS_LINE2} =~ s/2001:db8:1::/2001:db8:1::1/x; }, qr/host[ ]bits/x],
    ['route host bits', sub { $_[0]{NODEROUTENAMES} = 'data'; $_[0]{ROUTE_data} = '2001:db8:2::1,64,2001:db8:1::1,vtnet1'; }, qr/route[ ]network/x],
    ['own gateway', sub { $_[0]{NETWORKS_LINE2} =~ s/gateway=/gateway=2001:db8:1::10/x; }, qr/own[ ]gateway/x],
    ['wrong gateway scope', sub { $_[0]{NETWORKS_LINE2} =~ s/gateway=/gateway=fe80::1%vtnet2/x; }, qr/scope[ ]differs/x],
    ['global gateway scope', sub { $_[0]{NETWORKS_LINE2} =~ s/gateway=/gateway=2001:db8:1::1%vtnet1/x; }, qr/Only[ ]link-local/x],
    ['overlapping interfaces', sub {
        $_[0]{NICTYPES} .= ',vtnet2!ethernet';
        $_[0]{NICIPS} .= ',vtnet2!192.0.2.11';
        $_[0]{NICNETWORKS} .= ',vtnet2!data4';
    }, qr/Overlapping[ ]subnets/x],
);
rejected(@$_) for @invalid;

for my $case (
    ['missing member', sub { $_[0]{NICDEVICES} =~ s/vtnet2/vtnet9/x; }, qr/Missing,[ ]duplicate[ ]or[ ]self-referencing/x],
    ['duplicate member', sub { $_[0]{NICDEVICES} =~ s/vtnet2/vtnet1/x; }, qr/Missing,[ ]duplicate[ ]or[ ]self-referencing/x],
    ['unselected protocol', sub { $_[0]{NICEXTRAPARAMS} = ''; }, qr/Set[ ]LAGGPROTO/x],
    ['unsupported protocol', sub { $_[0]{NICEXTRAPARAMS} = 'lagg0!LAGGPROTO=roundrobin'; }, qr/failover[ ]or[ ]lacp/x],
    ['member address', sub { $_[0]{NICIPS} .= ',vtnet1!192.0.2.11'; $_[0]{NICNETWORKS} .= ',vtnet1!data4'; }, qr/addresses[ ]on[ ]the[ ]aggregate/x],
    ['clone naming', sub {
        $_[0]{NICTYPES} =~ s/lagg0/bond0/x;
        $_[0]{NICDEVICES} =~ s/lagg0/bond0/gx;
        $_[0]{NICEXTRAPARAMS} =~ s/lagg0/bond0/x;
    }, qr/native[ ]lagg[ ]interface/x],
    ['invalid VLAN tag', sub { $_[0]{NICEXTRAPARAMS} .= ',vlan100!VLAN_TAG=4095'; }, qr/Invalid[ ]VLAN_TAG/x],
    ['incompatible MTU', sub { $_[0]{NICEXTRAPARAMS} .= ' MTU=9000'; }, qr/Incompatible[ ]member[ ]MTU/x],
    ['bridge changes member MTU', sub { $_[0]{NICEXTRAPARAMS} .= ',bridge0!MTU=1400'; }, qr/Incompatible[ ]member[ ]MTU/x],
    ['installation VLAN needs explicit selection', sub {
        $_[0]{NICTYPES} = 'vtnet0!ethernet,vlan100!vlan';
        $_[0]{NICDEVICES} = 'vlan100!vtnet0';
        $_[0]{NICIPS} = 'vlan100!192.0.2.10';
        $_[0]{NICNETWORKS} = 'vlan100!data4';
        $_[0]{NICEXTRAPARAMS} = '';
    }, qr/Use[ ]confignetwork[ ]-s/x],
) {
    subtest $case->[0] => sub {
        my $environment = chain();
        $case->[1]->($environment);
        my ($status, $output, $error) = compile_plan($environment);
        isnt($status, 0, 'invalid topology rejected');
        is($output, '', 'no partial plan');
        like($error, $case->[2], 'specific diagnostic');
        done_testing();
    };
}

my $fixture_number = 0;
sub inspect_state {
    my ($mode, $plan, $kernel, $environment, $configure_boot) = @_;
    my @paths;
    for my $contents ($plan, $kernel) {
        my $path = $directory . '/' . ++$fixture_number;
        open(my $file, '>', $path) or croak $!;
        print {$file} $contents or croak $!;
        close($file) or croak $!;
        push @paths, $path;
    }
    return invoke($environment || {}, '-v', "mode=$mode", '-v', 'configure_boot=' . ($configure_boot || 0), @paths);
}

sub persistent_configuration_tests {
    subtest 'persistent route names protect unmanaged configuration' => sub {
        my $environment = base();
        $environment->{NODEROUTENAMES} = 'data,storage6';
        $environment->{ROUTE_data} = '203.0.113.0,255.255.255.0,192.0.2.1,vtnet1';
        $environment->{ROUTE_storage6} = '2001:db8:2::,64,2001:db8:1::1,vtnet1';
        my ($compiled, $plan) = compile_plan($environment);
        is($compiled, 0, 'the selected routes compile');
        for my $family (
            ['static_routes', 'route_', 'data', '-net 198.51.100.0/24 127.0.0.1'],
            ['ipv6_static_routes', 'ipv6_route_', 'storage6', '-net 2001:db8:3::/64 ::1'],
        ) {
            my ($list, $prefix, $name, $route) = @{$family};
            my $variable = $prefix . 'xcat_net_' . $name;
            for my $existing (
                "$variable: $route\n",
                "$list: xcat_net_$name other\n",
                "$list: other xcat_net_$name another\n",
                "$list: other xcat_net_$name\n",
            ) {
                my ($status, $output, $error) = inspect_state('rcconflicts', $plan, $existing);
                isnt($status, 0, 'an existing route variable or list name is protected');
                is($output, '', 'no configuration is emitted');
                like($error, qr/route[ ]has[ ]configuration/x,
                    'the diagnostic identifies the unmanaged route');
            }
        }
        my $unrelated = <<'VARIABLES';
static_routes: other xcat_net_data_other xcat_net_storage6
ipv6_static_routes: other xcat_net_storage6_other xcat_net_data
route_xcat_net_data_other: -net 198.51.100.0/24 127.0.0.1
ipv6_route_xcat_net_storage6_other: -net 2001:db8:3::/64 ::1
route_xcat_net_storage6: -net 198.51.100.0/24 127.0.0.1
ipv6_route_xcat_net_data: -net 2001:db8:3::/64 ::1
VARIABLES
        for my $existing ('', $unrelated) {
            my ($status, undef, $error) = inspect_state('rcconflicts', $plan, $existing);
            is($status, 0, 'unrelated names and the other address family remain available') or diag($error);
        }
        done_testing();
    };

    subtest 'persistent clone settings require explicit ownership' => sub {
        my ($compiled, $plan) = compile_plan(chain());
        is($compiled, 0, 'the composed topology compiles');
        for my $variable (qw(ifconfig_bridge0 ifconfig_bridge0_ipv6 ifconfig_bridge0_alias0 create_args_lagg0 vlans_vlan100)) {
            my ($status, undef, $error) = inspect_state('rcconflicts', $plan, "$variable: existing\n");
            isnt($status, 0, 'unmanaged clone configuration is protected');
            like($error, qr/clone[ ]has[ ]configuration/x, 'the diagnostic identifies the clone');
        }
        my ($status, undef, $error) = inspect_state('rcconflicts', $plan,
            "ifconfig_vtnet1: inet 192.0.2.10/24\nifconfig_bridge00: up\ncreate_args_lagg10: laggproto failover\n");
        is($status, 0, 'physical adoption and unrelated clone names remain available') or diag($error);
        ($status, undef, $error) = inspect_state('rcconflicts', $plan, "cloned_interfaces: tap0 bridge0\n");
        isnt($status, 0, 'an unmanaged clone list entry requires integration');
        like($error, qr/clone[ ]has[ ]configuration/x, 'the list collision identifies the clone');
        done_testing();
    };

    subtest 'effective rc.conf lists retain additions outside the saved plan' => sub {
        my $environment = chain();
        $environment->{NODEROUTENAMES} = 'data,storage6';
        $environment->{ROUTE_data} = '203.0.113.0,255.255.255.0,192.0.2.1,bridge0';
        $environment->{ROUTE_storage6} = '2001:db8:2::,64,2001:db8:1::1,bridge0';
        my ($compiled, $plan) = compile_plan($environment);
        is($compiled, 0, 'the existing topology and selected routes compile');
        my $variables = "cloned_interfaces: tap0 lagg0 vlan100 bridge0 bridge7\n"
            . "static_routes: xcat_net_data management4\n"
            . "ipv6_static_routes: management6 xcat_net_storage6\n";
        my ($status, $retained, $error) = inspect_state('rclists', $plan, $variables);
        is($status, 0, 'effective list values are accepted') or diag($error);
        is($retained, "cloned_interfaces: tap0 bridge7\nstatic_routes: management4\nipv6_static_routes: management6\n",
            'only entries owned by the previous plan are removed before merging');
        ($status, $retained, $error) = inspect_state('rclists', '', $variables);
        is($status, 0, 'first adoption accepts an empty prior plan') or diag($error);
        is($retained, $variables, 'first adoption retains every existing list entry');
        ($status, $retained, $error) = inspect_state('rclists', $plan, "static_routes: manual;command\n");
        isnt($status, 0, 'unsafe list syntax is rejected');
        is($retained, '', 'an invalid list emits no partial result');
        like($error, qr/Invalid[ ]names[ ]in[ ]static_routes/x, 'the diagnostic identifies the invalid list');
        done_testing();
    };

    return;
}
persistent_configuration_tests();

subtest 'physical adoption protects existing interface options' => sub {
    my ($compiled, $plan) = compile_plan(base());
    is($compiled, 0, 'the desired physical interface compiles');
    for my $setting (
        'ifconfig_vtnet1: up -lro -tso',
        'ifconfig_vtnet1: media 10Gbase-T',
        'ifconfig_vtnet1: -vlanhwtag',
        'ifconfig_vtnet1: ether 52:54:00:12:34:56',
        'ifconfig_vtnet1: fib 1',
        'ifconfig_vtnet1_ipv6: inet6 2001:db8:1::10 prefixlen 64 -auto_linklocal',
        'ifconfig_vtnet1_alias0: inet 192.0.2.11/24 vhid 1',
        'ifconfig_vtnet1_aliases: inet 192.0.2.11/24 fib 1',
        'ifconfig_vtnet1_name: storage',
        'create_args_vtnet1: ether 52:54:00:12:34:56',
        'vlans_vtnet1: 100',
        'ipv6_prefix_vtnet1: 2001:db8:1::',
        'ipv6_ifconfig_vtnet1: 2001:db8:1::10 prefixlen 64',
        'ipv6_ifconfig_vtnet1_alias0: 2001:db8:1::11 prefixlen 64',
    ) {
        my ($status, undef, $error) = inspect_state('rcoptions', $plan, "$setting\n");
        isnt($status, 0, 'unsupported persistent options require integration');
        like($error, qr/Interface[ ]options[ ]require[ ]manual[ ]integration/x, 'the diagnostic identifies the adoption boundary');
    }
    my ($status, undef, $error) = inspect_state('rcoptions', $plan,
        "ifconfig_vtnet1: inet 192.0.2.10 netmask 255.255.255.0 broadcast 192.0.2.255 mtu 1500 up\n"
        . "ifconfig_vtnet1_ipv6: inet6 2001:db8:1::10 prefixlen 64\n"
        . "ifconfig_vtnet1_alias0: inet 192.0.2.11/24\n"
        . "ifconfig_vtnet1_aliases: inet6 2001:db8:1::11/64 alias\n"
        . "ifconfig_vtnet10: up -lro\nifconfig_vtnet0: up -tso\n");
    is($status, 0, 'static settings and unrelated interface options allow adoption') or diag($error);
    ($status, undef, $error) = inspect_state('rcoptions', $plan,
        "ifconfig_vtnet1_ipv6: DHCP NOAUTO SYNCDHCP nosyncdhcp WPA hostap\n");
    is($status, 0, 'IPv6 accepts the pseudo arguments removed by native ifconfig_getargs') or diag($error);
    done_testing();
};

subtest 'legacy IPv6 settings cannot configure a managed clone at boot' => sub {
    my ($compiled, $plan) = compile_plan(chain());
    is($compiled, 0, 'the composed topology compiles');
    for my $key (qw(ipv6_ifconfig_bridge0 ipv6_ifconfig_bridge0_alias0)) {
        my ($status, undef, $error) = inspect_state('rcoptions', $plan, "$key: 2001:db8:1::11 prefixlen 64\n");
        isnt($status, 0, 'the obsolete address setting requires integration');
        like($error, qr/Interface[ ]options[ ]require[ ]manual[ ]integration/x, 'the diagnostic identifies the boundary');
    }
    my ($status, undef, $error) = inspect_state('rcoptions', $plan,
        "ipv6_ifconfig_bridge0: \nipv6_ifconfig_bridge0_alias0: \nipv6_ifconfig_bridge7: 2001:db8:7::1\n");
    is($status, 0, 'empty settings and unrelated interfaces remain available') or diag($error);
    done_testing();
};

sub observed_state_tests {
    my $kernel = <<'IFCONFIG';
vtnet1: flags=1008843<UP,BROADCAST,RUNNING,SIMPLEX,MULTICAST,LOWER_UP> metric 0 mtu 1500
        ether 52:54:00:12:34:56
        inet 192.0.2.10 netmask 0xffffff00 broadcast 192.0.2.255
        inet6 fe80::5054:ff:fe12:3456%vtnet1 prefixlen 64 scopeid 0x2
        inet6 2001:db8:1::10 prefixlen 64
        media: Ethernet autoselect (10Gbase-T <full-duplex>)
        status: active
        nd6 options=21<PERFORMNUD,AUTO_LINKLOCAL>
IFCONFIG

    subtest 'native interface readback and rollback snapshot' => sub {
        my ($compile_status, $plan) = compile_plan(base());
        is($compile_status, 0, 'the desired configuration compiles');
        my ($status, undef, $error) = inspect_state('verify', $plan, $kernel);
        is($status, 0, 'native ifconfig output satisfies the plan') or diag($error);
        my ($snapshot_status, $snapshot) = inspect_state('snapshot', $plan, $kernel);
        is($snapshot_status, 0, 'the physical interface can be saved');
        is(value($snapshot, 'E', 'vtnet1'), '52:54:00:12:34:56', 'the current Ethernet address is retained');
        is(value($snapshot, 'V', 'vtnet1'), '-ifdisabled', 'the IPv6 state is retained');
        is_deeply([sort map { join(' ', @{$_}[2..4]) } @{ rows($snapshot, 'A') }], [
            'inet 192.0.2.10 24',
            'inet6 2001:0db8:0001:0000:0000:0000:0000:0010 64',
            'inet6 fe80:0000:0000:0000:5054:00ff:fe12:3456 64',
        ], 'rollback includes the link-local address');
        for my $readback_case (
            ['wrong MTU', sub { $_[0] =~ s/mtu[ ]1500/mtu 1400/x; }, 'Interface MTU differs'],
            ['wrong prefix', sub { $_[0] =~ s/prefixlen[ ]64/prefixlen 63/gx; }, 'A configured address or prefix is missing'],
            ['wrong address', sub { $_[0] =~ s/192[.]0[.]2[.]10/192.0.2.11/x; }, 'A configured address or prefix is missing'],
            ['missing interface', sub { $_[0] =~ s/vtnet1/vtnet2/gx; }, 'Interface did not become ready'],
            ['interface down', sub { $_[0] =~ s/<UP,/< /x; }, 'Interface did not become ready'],
            ['IPv6 disabled', sub { $_[0] =~ s/PERFORMNUD/PERFORMNUD,IFDISABLED/x; }, 'IPv6 interface state differs'],
            ['tentative link-local address', sub { $_[0] =~ s/prefixlen[ ]64/prefixlen 64 tentative/x; }, 'Interface did not become ready'],
            ['tentative global address', sub { $_[0] =~ s/(inet6[ ]2001:[^\n]+prefixlen[ ]64)/$1 tentative/x; }, 'Interface did not become ready'],
            ['duplicate address', sub { $_[0] =~ s/prefixlen[ ]64/prefixlen 64 duplicated/x; }, 'Interface did not become ready'],
            ['unexpected alias', sub { $_[0] .= "        inet 192.0.2.11 netmask 0xffffff00\n"; }, 'An unexpected address is configured'],
        ) {
            my $changed = $kernel;
            $readback_case->[1]->($changed);
            my ($rejected, undef, $readback_error) = inspect_state('verify', $plan, $changed);
            isnt($rejected, 0, $readback_case->[0] . ' is rejected');
            my $diagnostic = $readback_case->[2];
            like($readback_error, qr/\Q$diagnostic\E/x, 'the intended readback guard rejected it');
        }
        my ($clear) = inspect_state('conflicts', $plan, $kernel);
        is($clear, 0, 'the managed interface does not conflict with itself');
        my $slaac = $kernel;
        $slaac =~ s/PERFORMNUD/PERFORMNUD,ACCEPT_RTADV/x;
        my ($rejected, undef, $slaac_error) = inspect_state('conflicts', $plan, $slaac);
        isnt($rejected, 0, 'SLAAC must stop before static adoption');
        like($slaac_error, qr/Stop[ ]SLAAC[ ]configuration/x, 'SLAAC has a specific preflight diagnostic');
        ($rejected, undef, my $management_error) = inspect_state('conflicts', $plan, $kernel,
            { IPADDR => '192.0.2.10' });
        isnt($rejected, 0, 'the live management address requires explicit selection on any interface');
        like($management_error, qr/interface[ ]carrying[ ]the[ ]management[ ]address/x, 'the diagnostic identifies management protection');
        my ($selected) = inspect_state('conflicts', $plan, $kernel, { IPADDR => '192.0.2.10' }, 1);
        is($selected, 0, 'explicit management selection passes this ownership guard');
        for my $unmanaged (
            "management_0: flags=8843<UP,BROADCAST> mtu 1500\n    inet 192.0.2.1 netmask 0xffffff00\n",
            "bridge7: flags=8843<UP,BROADCAST> mtu 1500\n    member: vtnet1 flags=143<LEARNING,DISCOVER,AUTOEDGE,AUTOPTP>\n",
            "vlan7: flags=8843<UP,BROADCAST> mtu 1500\n    vlan: 7 vlanproto: 802.1q parent interface: vtnet1\n",
        ) {
            my ($conflict) = inspect_state('conflicts', $plan, $kernel . $unmanaged);
            isnt($conflict, 0, 'unmanaged addressing and topology are protected');
        }
        done_testing();
    };

    subtest 'rollback clears addresses before duplicate detection completes' => sub {
        my ($compiled, $plan) = compile_plan(base());
        is($compiled, 0, 'the desired configuration compiles');
        my (undef, $ready) = inspect_state('snapshot', $plan, $kernel);
        for my $state (qw(tentative duplicated)) {
            my $changed = $kernel;
            $changed =~ s/prefixlen[ ]64/prefixlen 64 $state/gx;
            my ($verified) = inspect_state('verify', $plan, $changed);
            isnt($verified, 0, "$state addresses do not satisfy readiness");
            my ($saved) = inspect_state('snapshot', $plan, $changed);
            isnt($saved, 0, "$state addresses cannot become the rollback baseline");
            for my $disabled (0, 1) {
                my $observed = $changed;
                $observed =~ s/PERFORMNUD/PERFORMNUD,IFDISABLED/x if $disabled;
                my ($cleared, $addresses, $error) = inspect_state('clear', $plan, $observed);
                is($cleared, 0, "$state addresses can be removed during rollback") or diag($error);
                is_deeply([sort map { join(' ', @$_) } @{ rows($addresses, 'A') }],
                    [sort map { join(' ', @$_) } @{ rows($ready, 'A') }],
                    'cleanup includes global and link-local addresses regardless of IPv6 state');
            }
        }
        my $malformed = $kernel;
        $malformed =~ s/prefixlen[ ]64/prefixlen -1/x;
        my ($status) = inspect_state('clear', $plan, $malformed);
        isnt($status, 0, 'cleanup still rejects an unparseable prefix');
        done_testing();
    };

    subtest 'disabled IPv6 ignores tentative link-local readiness' => sub {
        my $environment = base();
        $environment->{NICIPS} = 'vtnet1!192.0.2.10';
        $environment->{NICNETWORKS} = 'vtnet1!data4';
        my ($compiled, $plan) = compile_plan($environment);
        is($compiled, 0, 'IPv4-only configuration compiles');
        my $observed = $kernel;
        $observed =~ s/^.*inet6[ ]2001:[^\n]+\n//mx;
        $observed =~ s/prefixlen[ ]64/prefixlen 64 tentative/x;
        $observed =~ s/PERFORMNUD/PERFORMNUD,IFDISABLED/x;
        my ($status, undef, $error) = inspect_state('verify', $plan, $observed);
        is($status, 0, 'a disabled tentative link-local address does not block IPv4') or diag($error);
        ($status, my $snapshot, $error) = inspect_state('snapshot', $plan, $observed);
        is($status, 0, 'the rollback baseline can be saved') or diag($error);
        is(scalar(@{ rows($snapshot, 'A') }), 1, 'only the active IPv4 address is restored');
        done_testing();
    };

    subtest 'native route readback' => sub {
        my $environment = base();
        $environment->{NETWORKS_LINE2} =~ s/gateway=/gateway=fe80::1/x;
        $environment->{NODEROUTENAMES} = 'storage';
        $environment->{ROUTE_storage} = '203.0.113.0,255.255.255.0,192.0.2.1,vtnet1';
        my ($compiled, $plan) = compile_plan($environment);
        is($compiled, 0, 'desired routes compile');
        my $routes = <<'NETSTAT';
Routing tables
Internet:
Destination        Gateway            Flags   Nhop#    Mtu            Netif Expire
203.0.113.0/24     192.0.2.1           UGS         2   1500           vtnet1
Internet6:
Destination                       Gateway                       Flags   Nhop#    Mtu            Netif Expire
default                           fe80::1%vtnet1                UGS         3   1500           vtnet1
NETSTAT
        my ($status, undef, $error) = inspect_state('routes', $plan, $routes);
        is($status, 0, 'native routing table satisfies the plan') or diag($error);
        my $ownership = "I\tvtnet1\tethernet\n";
        my ($unowned) = inspect_state('routeconflicts', $ownership, $routes);
        isnt($unowned, 0, 'an existing manual route prevents interface replacement');
        $ownership .= "O\tinet\t203.0.113.0/24\t192.0.2.1\tvtnet1\n";
        my ($owned) = inspect_state('routeconflicts', $ownership, $routes);
        is($owned, 0, 'previously managed routes can be replaced');
        for my $route_case (
            ['wrong interface', sub { $_[0] =~ s/vtnet1/vtnet2/gx; }],
            ['wrong gateway', sub { $_[0] =~ s/192[.]0[.]2[.]1/192.0.2.2/x; }],
            ['wrong prefix', sub { $_[0] =~ s{/24}{/25}x; }],
            ['missing default', sub { $_[0] =~ s/^default.*\n//mx; }],
        ) {
            my $changed = $routes;
            $route_case->[1]->($changed);
            my ($rejected) = inspect_state('routes', $plan, $changed);
            isnt($rejected, 0, $route_case->[0] . ' is rejected');
        }
        done_testing();
    };
    return;
}
observed_state_tests();

sub dhcp_configuration_tests {
    subtest 'DHCP uses reserved addresses and native persistent configuration' => sub {
        for my $option ('BOOTPROTO=dhcp', 'dhcp4=true') {
            my $environment = base();
            $environment->{NICEXTRAPARAMS} = "vtnet1!$option";
            my ($status, $plan, $error) = compile_plan($environment);
            is($status, 0, "$option compiles") or diag($error);
            is(value($plan, 'K', 'ifconfig_vtnet1'), 'SYNCDHCP mtu 1500 up', 'boot uses the native DHCP client');
            is_deeply(rows($plan, 'H'), [['H', 'vtnet1', '192.0.2.10', '24', 'yes', 'no']],
                'the lease is bound to the reserved address, prefix and DNS policy');
            is(value($plan, 'K', 'dhclient_flags_vtnet1'), '-c /var/db/xcat/network/dhcp/vtnet1.conf',
                'the client uses its protected configuration');
            is(value($plan, 'K', 'ifconfig_vtnet1_ipv6'),
                'inet6 2001:0db8:0001:0000:0000:0000:0000:0010 prefixlen 64', 'IPv6 remains configured');
        }
        my $environment = base();
        $environment->{IPADDR} = '192.0.2.10';
        $environment->{NICTYPES} =~ s/vtnet1/vtnet0/gx;
        $environment->{NICIPS} =~ s/vtnet1/vtnet0/gx;
        $environment->{NICNETWORKS} =~ s/vtnet1/vtnet0/gx;
        $environment->{NETWORKS_LINE1} =~ s/gateway=/gateway=192.0.2.1/x;
        $environment->{NICEXTRAPARAMS} = 'vtnet0!BOOTPROTO=dhcp PEERDNS=no';
        my ($status, $plan, $error) = compile_plan($environment, 1);
        is($status, 0, 'the management reservation can use DHCP') or diag($error);
        is_deeply(rows($plan, 'H'), [['H', 'vtnet0', '192.0.2.10', '24', 'no', 'yes']],
            'the management interface owns the DHCP gateway');
        is(value($plan, 'K', 'defaultrouter'), 'NO', 'no static IPv4 gateway overrides DHCP at boot');
        is_deeply(rows($plan, 'D'), [], 'DHCP supplies the default route');
        done_testing();
    };

    for my $invalid ('BOOTPROTO=auto', 'dhcp4=yes', 'BOOTPROTO=dhcp dhcp4=false',
        'BOOTPROTO=static dhcp4=true', 'PEERDNS=no', 'DEFROUTE=yes', 'BOOTPROTO=dhcp PEERDNS=maybe') {
        rejected("invalid DHCP options: $invalid", sub {
            $_[0]->{NICEXTRAPARAMS} = "vtnet1!$invalid";
        }, qr/(BOOTPROTO|dhcp4|DHCP|PEERDNS|DEFROUTE)/x);
    }
    rejected('DHCP requires a reservation', sub {
        $_[0]->{NICEXTRAPARAMS} = 'vtnet1!BOOTPROTO=dhcp';
        $_[0]->{NICIPS} = 'vtnet1!2001:db8:1::10';
        $_[0]->{NICNETWORKS} = 'vtnet1!data6';
    }, qr/DHCP[ ]requires[ ]exactly[ ]one[ ]reserved/x);
    rejected('DHCP cannot choose among several IPv4 reservations', sub {
        $_[0]->{NICEXTRAPARAMS} = 'vtnet1!BOOTPROTO=dhcp';
        $_[0]->{NICIPS} = 'vtnet1!192.0.2.10|192.0.2.11';
        $_[0]->{NICNETWORKS} = 'vtnet1!data4';
    }, qr/DHCP[ ]requires[ ]exactly[ ]one[ ]reserved/x);

    subtest 'an expired DHCP address permits recovery without accepting a wrong lease' => sub {
        my $environment = base();
        $environment->{NICIPS} = 'vtnet1!192.0.2.10';
        $environment->{NICNETWORKS} = 'vtnet1!data4';
        $environment->{NICEXTRAPARAMS} = 'vtnet1!BOOTPROTO=dhcp';
        my ($status, $plan, $error) = compile_plan($environment);
        is($status, 0, 'the reserved DHCP interface compiles') or diag($error);
        my $state = "vtnet1: flags=1008843<UP,BROADCAST,RUNNING> metric 0 mtu 1500\n"
            . "        ether 52:54:00:12:34:56\n        nd6 options=29<PERFORMNUD,IFDISABLED,AUTO_LINKLOCAL>\n";
        is((inspect_state('verify-prior', $plan, $state))[0], 0, 'an expired lease allows a new configuration');
        isnt((inspect_state('verify', $plan, $state))[0], 0, 'completion still requires the reserved address');
        $state .= "        inet 192.0.2.11 netmask 0xffffff00 broadcast 192.0.2.255\n";
        isnt((inspect_state('verify-prior', $plan, $state))[0], 0, 'an unexpected IPv4 address remains a conflict');
        done_testing();
    };

    subtest 'DHCP bridge uses an explicit persistent MAC' => sub {
        my $environment = base();
        $environment->{NICTYPES} = 'vtnet1!ethernet,bridge0!bridge';
        $environment->{NICDEVICES} = 'bridge0!vtnet1';
        $environment->{NICIPS} =~ s/vtnet1/bridge0/gx;
        $environment->{NICNETWORKS} =~ s/vtnet1/bridge0/gx;
        $environment->{NICEXTRAPARAMS} = 'bridge0!BOOTPROTO=dhcp';
        my ($status, undef, $error) = compile_plan($environment);
        isnt($status, 0, 'a random bridge MAC cannot identify a DHCP reservation');
        like($error, qr/Set[ ]MACADDR[ ]for[ ]a[ ]bridge/x, 'the error identifies the missing reservation identity');
        $environment->{NICEXTRAPARAMS} .= ' MACADDR=52:54:00:12:34:56';
        my ($accepted, $plan, $diagnostic) = compile_plan($environment);
        is($accepted, 0, 'an explicit bridge MAC compiles') or diag($diagnostic);
        is(value($plan, 'K', 'ifconfig_bridge0'),
            'SYNCDHCP ether 52:54:00:12:34:56 addm vtnet1 stp vtnet1 mtu 1500 up',
            'the same bridge MAC is applied at boot');
        is(value($plan, 'E', 'bridge0'), '52:54:00:12:34:56', 'runtime readback checks the configured MAC');
        for my $bad ('ff:ff:ff:ff:ff:ff', '01:00:00:00:00:01', '00:00:00:00:00:00', 'invalid') {
            $environment->{NICEXTRAPARAMS} = "bridge0!BOOTPROTO=dhcp MACADDR=$bad";
            isnt((compile_plan($environment))[0], 0, 'invalid reservation MAC is rejected');
        }
        done_testing();
    };

    return;
}
dhcp_configuration_tests();

sub dhcp6_configuration_tests {
    subtest 'DHCPv6 uses the xCAT hardware UUID reservation identity' => sub {
        my ($status, $duid, $error) = invoke({}, '-v', 'mode=dhcp6-duid', '-v',
            'uuid=12345678-1234-ABCD-9876-1234567890AB');
        is($status, 0, 'a canonical hardware UUID is accepted') or diag($error);
        is($duid, "00:04:12:34:56:78:12:34:ab:cd:98:76:12:34:56:78:90:ab\n",
            'the identifier matches the DUID-UUID used by xCAT DHCP backends');
        for my $bad ('', '00000000-0000-0000-0000-000000000000',
            'ffffffff-ffff-ffff-ffff-ffffffffffff', '1234', '$(command)') {
            my ($rejected, $output) = invoke({}, '-v', 'mode=dhcp6-duid', '-v', "uuid=$bad");
            isnt($rejected, 0, 'an invalid hardware UUID cannot create a reservation identity');
            is($output, '', 'invalid identity emits no DUID');
        }
    };
    subtest 'DHCPv6 reservations use a separate persistent client' => sub {
        for my $option ('DHCPV6C=yes', 'dhcp6=true') {
            my $environment = base();
            $environment->{NICEXTRAPARAMS} = "vtnet1!$option PEERDNS=no IPV6_DEFROUTE=yes";
            my ($status, $plan, $error) = compile_plan($environment);
            is($status, 0, "$option compiles") or diag($error);
            is(value($plan, 'K', 'ifconfig_vtnet1'), 'inet 192.0.2.10/24 mtu 1500 up',
                'static IPv4 remains independent of DHCPv6');
            is(value($plan, 'K', 'ifconfig_vtnet1_ipv6'), 'inet6 -ifdisabled',
                'boot enables IPv6 without assigning the lease statically');
            is(value($plan, 'K', 'xcat_dhcp6_enable'), 'YES', 'boot enables the managed client');
            is(value($plan, 'K', 'ipv6_defaultrouter'), 'NO', 'router advertisements own the default');
            is_deeply(rows($plan, 'H6'), [['H6', 'vtnet1',
                '2001:0db8:0001:0000:0000:0000:0000:0010', '128', 'no', 'yes']],
                'the client receives the reservation, DNS and router policy');
            is_deeply(rows($plan, 'H'), [], 'DHCPv6 does not enable DHCPv4');
            $environment->{NICEXTRAPARAMS} .= ' BOOTPROTO=dhcp';
            ($status, $plan, $error) = compile_plan($environment);
            is($status, 0, 'both DHCP families can use the same interface') or diag($error);
            is(scalar(@{rows($plan, 'H')}), 1, 'IPv4 has its own lease policy');
            is(scalar(@{rows($plan, 'H6')}), 1, 'IPv6 retains its lease policy');
        }
    };

    for my $invalid ('dhcp6=yes', 'DHCPV6C=true', 'DHCPV6C=yes dhcp6=false',
        'DHCPV6C=no dhcp6=true', 'IPV6_DEFROUTE=yes', 'dhcp6=true IPV6_DEFROUTE=auto') {
        rejected("invalid DHCPv6 options: $invalid", sub {
            $_[0]->{NICEXTRAPARAMS} = "vtnet1!$invalid";
        }, qr/(dhcp6|DHCPV6C|DHCP|IPV6_DEFROUTE)/x);
    }
    rejected('DHCPv6 requires one reserved IPv6 address', sub {
        $_[0]->{NICEXTRAPARAMS} = 'vtnet1!dhcp6=true';
        $_[0]->{NICIPS} = 'vtnet1!192.0.2.10';
        $_[0]->{NICNETWORKS} = 'vtnet1!data4';
    }, qr/DHCPv6[ ]requires[ ]exactly[ ]one/x);
    rejected('DHCPv6 rejects ambiguous reservations', sub {
        $_[0]->{NICEXTRAPARAMS} = 'vtnet1!dhcp6=true';
        $_[0]->{NICIPS} .= '|2001:db8:1::11';
        $_[0]->{NICNETWORKS} .= '|data6';
    }, qr/DHCPv6[ ]requires[ ]exactly[ ]one/x);
    rejected('DHCPv6 and a static IPv6 default cannot compete', sub {
        $_[0]->{NICEXTRAPARAMS} = 'vtnet1!dhcp6=true IPV6_DEFROUTE=yes';
        $_[0]->{NETWORKS_LINE2} =~ s/gateway=/gateway=fe80::1/x;
    }, qr/one[ ]IPv6[ ]default[ ]route[ ]owner/x);

    subtest 'DHCPv6 lease validation precedes resolver output' => sub {
        my $environment = {
            interface => 'vtnet1', new_dhcp6_ia_na1_ia_addr1 => '2001:db8:1::10',
            new_dhcp6_name_servers => '2001:db8:1::1 fe80::1',
            new_dhcp6_domain_search => 'example.test storage.example.test',
        };
        my @args = ('-v', 'mode=dhcp6-options', '-v', 'expected=2001:db8:1::10', '-v', 'peerdns=yes');
        my ($status, $output, $error) = invoke($environment, @args);
        is($status, 0, 'a valid reserved lease compiles') or diag($error);
        is($output, "search example.test storage.example.test\n"
            . "nameserver 2001:0db8:0001:0000:0000:0000:0000:0001\n"
            . "nameserver fe80:0000:0000:0000:0000:0000:0000:0001%vtnet1\n",
            'DNS addresses are canonical and link-local servers have an interface scope');
        for my $bad (
            ['wrong address', {new_dhcp6_ia_na1_ia_addr1 => '2001:db8:1::11'}],
            ['missing address', {new_dhcp6_ia_na1_ia_addr1 => ''}],
            ['second address', {new_dhcp6_ia_na1_ia_addr2 => '2001:db8:1::11'}],
            ['invalid DNS', {new_dhcp6_name_servers => "2001:db8::1\noptions debug"}],
            ['invalid domain', {new_dhcp6_domain_search => 'example.test;command'}],
            ['excess DNS', {new_dhcp6_name_servers => join(' ', ('2001:db8::1') x 17)}],
        ) {
            ($status, $output, $error) = invoke({%$environment, %{$bad->[1]}}, @args);
            isnt($status, 0, "$bad->[0] is rejected");
            is($output, '', 'a rejected lease emits no resolver settings');
        }
        ($status, $output, $error) = invoke($environment, @args, '-v', 'peerdns=no');
        is($status, 0, 'DNS updates can be disabled') or diag($error);
        is($output, '', 'PEERDNS=no emits no resolver settings');
    };

    subtest 'DHCPv6 completion requires its router advertisement default' => sub {
        my $environment = base();
        $environment->{NICEXTRAPARAMS} = 'vtnet1!dhcp6=true IPV6_DEFROUTE=yes';
        my ($compiled, $plan) = compile_plan($environment);
        is($compiled, 0, 'the default route owner compiles');
        my $header = "Internet6:\nDestination Gateway Flags Netif Expire\n";
        my $route = "default fe80::1%vtnet1 UG vtnet1\n";
        is((inspect_state('routes', $plan, $header . $route))[0], 0,
            'the assigned interface has an IPv6 default');
        isnt((inspect_state('routes', $plan, $header))[0], 0,
            'a lease without the requested default is incomplete');
        $route =~ s/vtnet1/vtnet2/gx;
        isnt((inspect_state('routes', $plan, $header . $route))[0], 0,
            'a default through another interface is not accepted');
    };

    subtest 'expired DHCPv6 permits recovery while rejecting foreign addresses' => sub {
        my $environment = base();
        $environment->{NICEXTRAPARAMS} = 'vtnet1!dhcp6=true';
        my ($compiled, $plan, $diagnostic) = compile_plan($environment);
        is($compiled, 0, 'the reserved interface compiles') or diag($diagnostic);
        my $state = "vtnet1: flags=1008843<UP,BROADCAST,RUNNING> metric 0 mtu 1500\n"
            . "        ether 52:54:00:12:34:56\n"
            . "        inet 192.0.2.10 netmask 0xffffff00 broadcast 192.0.2.255\n"
            . "        inet6 fe80::5054:ff:fe12:3456%vtnet1 prefixlen 64 scopeid 0x2\n"
            . "        nd6 options=21<PERFORMNUD,AUTO_LINKLOCAL>\n";
        is((inspect_state('verify-prior', $plan, $state))[0], 0, 'an expired IPv6 lease permits repair');
        isnt((inspect_state('verify', $plan, $state))[0], 0, 'completion still requires the reservation');
        my $leased = $state . "        inet6 2001:db8:1::10 prefixlen 128\n";
        is((inspect_state('verify', $plan, $leased))[0], 0, 'the reserved lease satisfies native readback');
        $leased =~ s/::10/::11/x;
        isnt((inspect_state('verify-prior', $plan, $leased))[0], 0, 'a foreign lease blocks replacement');
    };
    return;
}
dhcp6_configuration_tests();

sub dhcp4_default_route_tests {
    subtest 'DHCPv4 default routes follow native lease precedence' => sub {
        my $path = "$directory/default.lease";
        my $header = "Internet:\nDestination Gateway Flags Netif Expire\n";
        for my $lease_case (
            ['routers', '192.0.2.1 192.0.2.254', '', "R\tinet\tdefault\t192.0.2.1\tvtnet1\n"],
            ['no router', '', '', ''],
            ['classless default', '192.0.2.254', '0 192 0 2 1', "R\tinet\tdefault\t192.0.2.1\tvtnet1\n"],
            ['classless without default', '192.0.2.254', '24 203 0 113 192 0 2 1', ''],
            ['partial prefix then default', '', '9 10 128 192 0 2 254 0 192 0 2 1', "R\tinet\tdefault\t192.0.2.1\tvtnet1\n"],
            ['on-link default', '', '0 0 0 0 0', "Q\tinet\tvtnet1\n"],
            ['own address as router', '192.0.2.10', '', "Q\tinet\tvtnet1\n"],
        ) {
            open(my $out, '>', $path) or croak $!;
            print {$out} "old_ip_address\t192.0.2.10\nold_routers\t$lease_case->[1]\nold_classless_routes\t$lease_case->[2]\n";
            close($out) or croak $!;
            my ($status, $plan, $error) = invoke({}, '-v', 'mode=dhcp4-default', '-v', 'nic=vtnet1', $path);
            is($status, 0, "$lease_case->[0] is understood") or diag($error);
            is($plan, $lease_case->[3], 'the default follows the lease options');
            if ($plan ne '') {
                my $gateway = $plan =~ /^Q/x ? 'link#2' : '192.0.2.1';
                is((inspect_state('routes', $plan, $header . "default $gateway UGS vtnet1\n"))[0], 0,
                    'the leased default passes kernel readback');
                isnt((inspect_state('routes', $plan, $header))[0], 0, 'a missing default is incomplete');
                isnt((inspect_state('routes', $plan, $header . "default $gateway UGS vtnet2\n"))[0], 0,
                    'a default on the former interface is rejected');
                if ($plan =~ /^R/x) {
                    isnt((inspect_state('routes', $plan, $header . "default 192.0.2.254 UGS vtnet1\n"))[0], 0,
                        'a wrong gateway on the right interface is rejected');
                }
            }
        }
        for my $bad ('0 192 0 2', '33 10 0 0 0 192 0 2 1', '0 256 0 2 1') {
            open(my $out, '>', $path) or croak $!;
            print {$out} "old_classless_routes\t$bad\n";
            close($out) or croak $!;
            my ($status, $plan) = invoke({}, '-v', 'mode=dhcp4-default', '-v', 'nic=vtnet1', $path);
            isnt($status, 0, 'a malformed classless route is rejected');
            is($plan, '', 'an invalid lease emits no expected route');
        }
    };
    return;
}
dhcp4_default_route_tests();

subtest 'early bootstrap graph uses the installed-node topology rules' => sub {
    my $environment = {
        NICTYPES => 'vtnet0!ethernet,vtnet1!ethernet,lagg0!bond,vlan100!vlan,bridge0!bridge,vtnet2!ethernet',
        NICDEVICES => 'lagg0!vtnet0|vtnet1,vlan100!lagg0,bridge0!vlan100',
        NICEXTRAPARAMS => 'lagg0!LAGGPROTO=lacp,bridge0!STP=no',
        NICMACS => 'vtnet0!52:54:00:00:00:01,vtnet1!52:54:00:00:00:02',
    };
    my @options = ('-v', 'mode=bootstrap', '-v', 'bootstrapnic=bridge0', '-v', 'bootmac=52:54:00:00:00:01');
    my ($status, $plan, $error) = invoke($environment, @options);
    is($status, 0, 'LACP, VLAN and bridge compose before the configuration download') or diag($error);
    is_deeply([map { $_->[1] } @{rows($plan, 'I')}], [qw(vtnet0 vtnet1 lagg0 vlan100 bridge0)],
        'dependencies are ordered and an unrelated physical NIC is omitted');
    is_deeply(rows($plan, 'M'), [['M', 'vtnet0', '52:54:00:00:00:01'], ['M', 'vtnet1', '52:54:00:00:00:02']],
        'physical identities are checked before application');
    like(value($plan, 'X', 'lagg0'), qr/laggproto[ ]lacp[ ]laggport[ ]vtnet0[ ]laggport[ ]vtnet1/x,
        'native LACP retains the boot member order');
    like(value($plan, 'X', 'bridge0'), qr/^ether[ ]52:54:00:00:00:01[ ]addm[ ]vlan100/x,
        'the provisioning MAC follows the virtual management interface');
    is_deeply(rows($plan, 'A'), [], 'bootstrap addressing is selected independently');
    for my $change (
        { NICMACS => 'vtnet0!52:54:00:00:00:01' },
        { NICMACS => 'vtnet0!52:54:00:00:00:01,vtnet1!52:54:00:00:00:01' },
        { NICMACS => 'vtnet0!52:54:00:00:00:01,vtnet1!ff:ff:ff:ff:ff:ff' },
        { NICDEVICES => 'lagg0!vtnet1|vtnet0,vlan100!lagg0,bridge0!vlan100' },
        { NICDEVICES => 'lagg0!vtnet0|bridge0,vlan100!lagg0,bridge0!vlan100' },
        { NICEXTRAPARAMS => 'lagg0!LAGGPROTO=balance-xor' },
        { NICEXTRAPARAMS => 'lagg0!LAGGPROTO=lacp,bridge0!MACADDR=52:54:00:00:00:99' },
    ) {
        my ($bad, $partial) = invoke({ %$environment, %$change }, @options);
        isnt($bad, 0, 'ambiguous identity, unsafe composition or conflicting MAC is rejected');
        is($partial, '', 'no partial bootstrap plan escapes');
    }
};

done_testing();
