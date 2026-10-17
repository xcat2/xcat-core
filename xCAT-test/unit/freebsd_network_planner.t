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

done_testing();
