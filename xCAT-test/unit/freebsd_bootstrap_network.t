#!/usr/bin/env perl
use strict;
use warnings;
use Carp qw(croak);
use File::Temp qw(tempdir);
use FindBin;
use MIME::Base64 qw(encode_base64);
use Test::More;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use xCAT::FreeBSDNetwork;
use xCAT::FreeBSDConfig;

my $planner = "$FindBin::Bin/../../xCAT/postscripts/confignetwork-freebsd.awk";
my $mac = '52:54:00:00:00:01';
my $nics = { nictypes => 'vtnet0!ethernet,vtnet1!ethernet,lagg0!lagg,vlan100!vlan,bridge0!bridge',
    nicdevices => 'lagg0!vtnet0|vtnet1,vlan100!lagg0,bridge0!vlan100',
    nicextraparams => 'lagg0!LAGGPROTO=failover,bridge0!STP=no',
    nicsadapter => "vtnet0!mac=$mac linkstate=UP,vtnet1!mac=52:54:00:00:00:02,vtnet9!mac=52:54:00:00:00:09" };
my $encoded = xCAT::FreeBSDNetwork::encode('bridge0', $mac, $nics, $planner, 9000);
my $description = xCAT::FreeBSDNetwork::decode($encoded);
is($description->{mtu}, 9000, 'the provisioning network MTU travels with the topology');
my $plan = xCAT::FreeBSDNetwork::compile($encoded, $planner);
like($plan, qr/^X\tlagg0\t.*laggproto[ ]failover[ ]laggport[ ]vtnet0[ ]laggport[ ]vtnet1/mx,
    'the producer calls the shared topology compiler');
like($plan, qr/^T\tbridge0\t9000$/mx, 'the virtual address owner inherits the network MTU');
my $loader = xCAT::FreeBSDNetwork::loader($encoded);
my @chunks = $loader =~ /^xcat_network_[0-9]+="([A-Za-z0-9+\/=]+)"$/mgx;
is(join('', @chunks), $encoded, 'loader chunks retain every network byte');
ok(!grep({ length($_) > 120 } @chunks), 'each chunk fits the native kernel environment value bound');
like($loader, qr/^xcat_network_chunks="@{[scalar @chunks]}"$/mx, 'the count describes all chunks');
my $media = { install_contract => 'xcat-freebsd-install-6', network_contract => 'xcat-freebsd-bootstrap-1' };
my $settings = xCAT::FreeBSDConfig::boot_settings({bootstrap_network_base64 => $encoded}, '', {}, $media);
like(xCAT::FreeBSDConfig::render_loader_settings($settings, {}), qr/\Q$loader\E/x,
    'normal boot publication includes the topology before HTTP is available');
for my $bad_media ({}, { install_contract => 'xcat-freebsd-install-6' },
    { install_contract => 'xcat-freebsd-install-6', network_contract => 'unknown' }) {
    my $ok = eval { xCAT::FreeBSDConfig::boot_settings({bootstrap_network_base64 => $encoded}, '', {}, $bad_media); 1 };
    ok(!$ok, 'unqualified media cannot silently ignore early virtual networking');
}
for my $bad ('', 'A' x 8193, $encoded . '\n', encode_base64("interface=bridge0\n", ''),
    encode_base64("interface=bridge0\nmac=$mac\nmtu=9000\nNICTYPES=vtnet0!ethernet\nNICDEVICES=\nNICEXTRAPARAMS=\nNICMACS=vtnet0!$mac", '')) {
    my $ok = eval { xCAT::FreeBSDNetwork::decode($bad); 1 };
    ok(!$ok, 'malformed, oversized or incomplete descriptions are rejected');
}
for my $change ({nicdevices => 'lagg0!vtnet1|vtnet0,vlan100!lagg0,bridge0!vlan100'},
    {nicextraparams => 'lagg0!LAGGPROTO=lacp,bridge0!STP=no MACADDR=52:54:00:00:00:99'},
    {nicsadapter => "vtnet0!mac=$mac"},
    {nicsadapter => "vtnet0!mac=$mac mac=$mac,vtnet1!mac=52:54:00:00:00:02"},
    {nicsadapter => "vtnet0!mac=$mac,vtnet0!mac=$mac,vtnet1!mac=52:54:00:00:00:02"}) {
    my $ok = eval { xCAT::FreeBSDNetwork::encode('bridge0', $mac, { %$nics, %$change }, $planner); 1 };
    ok(!$ok, 'invalid topology fails before loader publication');
}
my $changed = xCAT::FreeBSDNetwork::encode('bridge0', $mac,
    { %$nics, nicextraparams => 'lagg0!LAGGPROTO=lacp,bridge0!STP=no' }, $planner, 9000);
isnt($changed, $encoded, 'a topology change changes the generation-bound configuration bytes');

subtest 'installed IB policy does not change the boot-image input' => sub {
    my $with_data = xCAT::FreeBSDNetwork::encode('bridge0', $mac, {
        %$nics,
        nictypes => $nics->{nictypes} . ',ib0!Infiniband,ib1!Infiniband,lagg1!bond-infiniband,vtnet2!ethernet',
        nicdevices => $nics->{nicdevices} . ',lagg1!ib0|ib1',
        nicextraparams => $nics->{nicextraparams} . ',lagg1!LAGGPROTO=failover,ib0!IB_DRIVER=mlx5ib,vtnet2!MTU=1500',
        nicsadapter => $nics->{nicsadapter} . ',vtnet2!mac=52:54:00:00:00:03',
    }, $planner, 9000);
    is($with_data, $encoded, 'an older boot planner receives the identical supported Ethernet policy');
    is(xCAT::FreeBSDNetwork::compile($with_data, $planner), $plan,
        'the filtered description reproduces the validated bootstrap plan');
};

subtest 'installer networking becomes managed installed-node configuration' => sub {
    my $directory = tempdir(CLEANUP => 1);
    open(my $input, '>', "$directory/bootstrap.plan") or croak $!;
    print {$input} $plan;
    close($input) or croak $!;
    local %ENV = (%ENV, XCAT_WORK => $directory, FIXTURE_PLAN => "$directory/bootstrap.plan",
        XCAT_BOOTSTRAP_NETWORK_BASE64 => $encoded, XCAT_MAC => $mac,
        XCAT_IPV4 => '192.0.2.10', XCAT_NETMASK => '255.255.255.0', XCAT_GATEWAY => '192.0.2.1');
    my $helper = "$FindBin::Bin/../../xCAT-server/share/xcat/install/freebsd/xcat-network.sh";
    # Supply the real producer output at the native compiler seam. This part
    # of the test exercises the installed configuration handoff on Linux too.
    my $script = '. "$1"; xcat_network_plan() { cp "$FIXTURE_PLAN" "$3"; }; xcat_network_rc';
    open(my $pipe, '-|', 'sh', '-eu', '-c', $script, 'sh', $helper) or croak $!;
    my $rc = do { local $/ = undef; <$pipe> };
    close($pipe);
    is($? >> 8, 0, 'the native helper renders the installed configuration');
    like($rc, qr/\A[#][ ]BEGIN[ ]xCAT[ ]FreeBSD[ ]network\n/x, 'the regular network manager owns the block');
    like($rc, qr/^ifconfig_bridge0_alias0="inet[ ]192\.0\.2\.10\/24"$/mx, 'the management address remains on the virtual leaf');
    like($rc, qr/^ifconfig_bridge0="ether[ ]52:54:00:00:00:01[ ]/mx, 'the link address has its own native address-family command');
    like($rc, qr/^defaultrouter="192\.0\.2\.1"$/mx, 'the configured gateway is retained');
    like($rc, qr/^static_routes=""$/mx, 'IPv4 route-list ownership is explicit before the first normal update');
    like($rc, qr/^ipv6_static_routes=""$/mx, 'IPv6 route-list ownership is explicit before the first normal update');
    open(my $saved, '<', "$directory/target-network.plan") or croak $!;
    my $state = do { local $/ = undef; <$saved> };
    close($saved) or croak $!;
    like($state, qr/\AF\txcat-freebsd-network-1\n/x, 'saved ownership uses the installed network contract');
    like($state, qr/^A\tbridge0\tinet\t192\.0\.2\.10\t24$/mx, 'saved state contains the installed address');
    like($state, qr/^D\tinet\t192\.0\.2\.1$/mx, 'saved state retains default-route ownership');
    unlike($state, qr/^[BM]\t/mx, 'bootstrap-only identity records do not enter installed state');
    local %ENV = (%ENV, NICTYPES => $nics->{nictypes}, NICDEVICES => $nics->{nicdevices},
        NICEXTRAPARAMS => $nics->{nicextraparams}, NICIPS => 'bridge0!192.0.2.10',
        NICNETWORKS => 'bridge0!provision', IPADDR => '192.0.2.10', NETWORKS_LINES => 1,
        NETWORKS_LINE1 => 'netname=provision||net=192.0.2.0||mask=255.255.255.0||gateway=192.0.2.1||mtu=9000||disable=');
    my @compile = ('awk', '-v', 'bootnic=vtnet0', '-v', "bootmac=$mac", '-v', 'configure_boot=1', '-f', $planner);
    open(my $normal, '-|', @compile) or croak $!;
    my $managed = do { local $/ = undef; <$normal> };
    close($normal);
    is($? >> 8, 0, 'the unchanged inventory compiles without explicit member MTUs or clone MACs');
    is($managed, $state, 'normal adoption reproduces the exact installer ownership plan');

    $ENV{NETWORKS_LINE1} =~ s/gateway=192[.]0[.]2[.]1/gateway=<xcatmaster>/x;
    my ($owned_gateway) = $state =~ /^D\tinet\t([^\n]+)$/mx;
    my @retained = (@compile, '-v', "owned_ipv4_gateway=$owned_gateway");
    open(my $token, '-|', @retained) or croak $!;
    my $preserved = do { local $/ = undef; <$token> };
    close($token);
    is($? >> 8, 0, 'the controller token accepts the default owned by the installer');
    is($preserved, $state, 'the token preserves the exact installed plan and default-route ownership');

    $ENV{NICEXTRAPARAMS} .= ' BOOTPROTO=dhcp';
    open(my $dhcp, '-|', @retained) or croak $!;
    my $leased = do { local $/ = undef; <$dhcp> };
    close($dhcp);
    is($? >> 8, 0, 'the management DHCP bridge inherits the provisioning identity');
    like($leased, qr/^K\tifconfig_bridge0\tSYNCDHCP[ ]ether[ ]\Q$mac\E[ ]/mx,
        'DHCP retains the inherited MAC at boot');
    unlike($leased, qr/^K\tifconfig_bridge0_alias[0-9]+\tinet[ ]/mx,
        'DHCP owns the management IPv4 address exclusively');
    unlike($leased, qr/^D\tinet\t/mx, 'DHCP replaces the previously owned static default');
};
subtest 'a physical bootstrap interface retains the normal address command' => sub {
    my $directory = tempdir(CLEANUP => 1);
    my $inventory = { nictypes => 'vtnet0!ethernet', nicsadapter => "vtnet0!mac=$mac" };
    my $physical = xCAT::FreeBSDNetwork::encode('vtnet0', $mac, $inventory, $planner);
    open(my $input, '>', "$directory/bootstrap.plan") or croak $!;
    print {$input} xCAT::FreeBSDNetwork::compile($physical, $planner);
    close($input) or croak $!;
    local %ENV = (%ENV, XCAT_WORK => $directory, FIXTURE_PLAN => "$directory/bootstrap.plan",
        XCAT_BOOTSTRAP_NETWORK_BASE64 => $physical, XCAT_MAC => $mac,
        XCAT_IPV4 => '192.0.2.10', XCAT_NETMASK => '255.255.255.0', XCAT_GATEWAY => '');
    my $helper = "$FindBin::Bin/../../xCAT-server/share/xcat/install/freebsd/xcat-network.sh";
    my $script = '. "$1"; xcat_network_plan() { cp "$FIXTURE_PLAN" "$3"; }; xcat_network_rc';
    open(my $pipe, '-|', 'sh', '-eu', '-c', $script, 'sh', $helper) or croak $!;
    my $rc = do { local $/ = undef; <$pipe> };
    close($pipe);
    is($? >> 8, 0, 'the physical interface handoff succeeds');
    like($rc, qr/^ifconfig_vtnet0="inet[ ]192\.0\.2\.10\/24[ ]mtu[ ]1500[ ]up"$/mx,
        'an interface without a link-address command retains its primary IPv4 address');
    unlike($rc, qr/^ifconfig_vtnet0_alias/mx, 'the primary address needs no extra alias');
};
done_testing();
