#!/usr/bin/env perl
# A diskless node brings its interface up from the dracut ip= parameter, and xCAT's Ubuntu
# diskless path emits none: debian.pm appends ifname, netdev and BOOTIF only. With no ip=
# at all, dracut configures the interface it needs with DHCPv4, so an IPv6-only node gets
# no address, cannot fetch imgurl and never mounts a root.
#
# dracut takes either6 for the IPv6 case: it asks for DHCPv6 and falls back to router
# advertisement. gen_net_boot_params already derives the interface in xCAT's own order, so
# the IPv6 spelling of the parameter belongs beside the IPv4 one it already returns.
#
# The IPv4 ip= is asserted unchanged. anaconda.pm is its only caller, and an IPv6-only
# Ubuntu node must not change what an EL node is told.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;
use xCAT::NetworkUtils;

my $MAC = 'aa:bb:cc:dd:ee:01';

my @cases = (
    {
        name       => 'installnic names an interface',
        installnic => 'eth0',
        primarynic => undef,
        ipv4       => 'ip=eth0:dhcp',
        ipv6       => 'ip=eth0:either6',
    },
    {
        name       => 'primarynic names an interface when installnic is unset',
        installnic => undef,
        primarynic => 'ens4',
        ipv4       => 'ip=ens4:dhcp',
        ipv6       => 'ip=ens4:either6',
    },
    {
        name       => 'neither attribute names an interface, so the MAC decides',
        installnic => undef,
        primarynic => undef,
        ipv4       => 'ip=dhcp',
        ipv6       => 'ip=either6',
    },
    {
        name       => 'installnic reads "mac", so the MAC decides',
        installnic => 'mac',
        primarynic => 'ens4',
        ipv4       => 'ip=dhcp',
        ipv6       => 'ip=either6',
    },
);

foreach my $case (@cases) {
    my $params = xCAT::NetworkUtils->gen_net_boot_params(
        $case->{installnic}, $case->{primarynic}, $MAC, undef);

    is($params->{ip}, $case->{ipv4},
        "$case->{name}: the IPv4 parameter is unchanged");
    is($params->{ip6}, $case->{ipv6},
        "$case->{name}: the IPv6 parameter asks dracut for either6");
}

# An installnic holding a MAC sets setmac and names no interface, so the parameter applies
# to every interface, the same way the IPv4 one in that branch already does.
my $by_mac = xCAT::NetworkUtils->gen_net_boot_params($MAC, undef, $MAC, undef);
is($by_mac->{setmac}, $MAC, 'an installnic holding a MAC sets setmac');
is($by_mac->{ip}, 'ip=dhcp', 'the setmac branch names no interface in the IPv4 parameter');
is($by_mac->{ip6}, 'ip=either6', 'the setmac branch names no interface in the IPv6 parameter');

# nodebootif from the image definition names the interface when noderes does not.
my $from_image = xCAT::NetworkUtils->gen_net_boot_params(undef, undef, $MAC, 'enp0s3');
is($from_image->{ip6}, 'ip=enp0s3:either6',
    'the image definition interface reaches the IPv6 parameter');

done_testing();
