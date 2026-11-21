#!/usr/bin/env perl
#
# The AutoYaST networking section of an IPv6-only SUSE node.
#
# sles.pm has no static handoff on the kernel command line, so a static address in the AutoYaST
# profile is the only way an IPv6-only node reaches its installer: DHCPv6 would need the client
# to send the DUID that makedhcp put in the reservation. AutoYaST takes a prefix length for
# IPv6, not a netmask.
use strict;
use warnings;
no warnings 'once';

use File::Spec;
use FindBin;
use Test::More tests => 24;

my $repo_root = File::Spec->catdir($FindBin::Bin, '..', '..');
$ENV{XCATROOT} = File::Spec->catdir($repo_root, 'xCAT-server');
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";

use XML::Simple;
use xCAT::NetworkUtils;

my %cfg = (
    cn6     => [ '2001:db8:1::50', 'cn6',     '2001:db8:1::fe', 64 ],
    cn6nogw => [ '2001:db8:2::50', 'cn6nogw', '',               64 ],
    cn6bad  => [ undef,            undef,     undef,            undef ],
    cn6long => [ '2001:db8:3::50', 'cn6long', '2001:db8:3::fe',  129 ],
    cn6v4ns => [ '2001:db8:4::50', 'cn6v4ns', '2001:db8:4::fe', 64 ],
);
no warnings 'redefine';
*xCAT::NetworkUtils::getNodeNetworkCfg6   = sub { my $n = $_[-1]; return @{ $cfg{$n} || [] } };
# The management node, which runs named. It is deliberately not any node's gateway: a
# cluster whose gateway is a separate router would otherwise be handed a resolver that
# answers nothing, and the test could not tell the two apart.
our $master6 = '2001:db8:ff::1';
*xCAT::NetworkUtils::ipv6_server_for_node = sub {
    my $server = $_[-1];
    return $master6 if !defined($server) || $server eq '<xcatmaster>' || $server eq '!myipfn!';
    return $server;
};
*xCAT::NetworkUtils::getNodeDomains       = sub { return { map { $_ => 'xcat.lab' } @{ $_[-1] } } };
# site.nameservers holds one list for the cluster, so an IPv6-only node can be given the
# IPv4 resolver of an IPv4 network.
my %resolvers = ( cn6v4ns => '192.0.2.53,198.51.100.53' );
*xCAT::NetworkUtils::getNodeNameservers   = sub {
    return { map { $_ => ( $resolvers{$_} // '2001:db8:1::fe' ) } @{ $_[-1] } };
};
use warnings 'redefine';

my $template = File::Spec->catfile($repo_root, 'xCAT-server/lib/perl/xCAT/Template.pm');
require $template;

my $xml = xCAT::Template::_autoyast_network6('cn6');
ok(defined($xml), 'an IPv6-only node gets a networking section');
like($xml, qr{<bootproto>static</bootproto>}, 'the interface is static, not dhcp');
like($xml, qr{<ipaddr>\Q2001:db8:1::50\E</ipaddr>}, 'it carries the IPv6 address of the node');
like($xml, qr{<prefixlen>64</prefixlen>}, 'and a prefix length, which is what AutoYaST takes for IPv6');
unlike($xml, qr{<netmask>(?!-)}, 'no IPv4 netmask is emitted for the interface');
like($xml, qr{<gateway>\Q2001:db8:1::fe\E</gateway>}, 'the default route carries the IPv6 gateway');
like($xml, qr{<nameserver>\Q2001:db8:1::fe\E</nameserver>}, 'and the resolver is the IPv6 one');

# An IPv4 resolver cannot be reached from an IPv6-only node, and an unreachable server in
# resolv.conf makes every lookup wait for its timeout before the next one is tried.
my $v4ns = xCAT::Template::_autoyast_network6('cn6v4ns');
unlike($v4ns, qr{<nameserver>\Q192.0.2.53\E</nameserver>},
    'an IPv4 resolver is not given to an IPv6-only node');
like($v4ns, qr{<nameserver>\Q2001:db8:ff::1\E</nameserver>},
    'the management node stands in when the node has no IPv6 resolver');
unlike($v4ns, qr{<nameserver>\Q2001:db8:4::fe\E</nameserver>},
    'and the gateway does not, because a separate router need not serve DNS');

# dhcp_resolv says whether DHCP may overwrite resolv.conf. The AutoYaST schema of Leap 15.6
# does not accept it, and one invalid element makes YaST reject the whole profile: it reports
# "Extra element networking in interleave" and then that no profile could be retrieved. The
# section configures the node statically, so there is no DHCP to keep away from resolv.conf.
unlike($xml, qr{<dhcp_resolv}, 'no dhcp_resolv, which the Leap 15.6 schema refuses');
like($xml, qr{<dhcp_hostname}, 'dhcp_hostname stays, which the schema does accept');

# AutoYaST keeps the network the installer used unless the profile says otherwise, and the
# templates it replaces set keep_install_network to true. Without this the static interface
# below is ignored: the installed node came up with ifcfg-eth0 BOOTPROTO=dhcp, no address but
# a link-local one, and xcat.sh failed with "Network is unreachable".
like($xml, qr{<keep_install_network config:type="boolean">false</keep_install_network>},
    'the profile network replaces the one the installer used');

# A node with no gateway still installs; it simply gets no default route.
my $nogw = xCAT::Template::_autoyast_network6('cn6nogw');
ok(defined($nogw), 'a node with no gateway still gets a section');
unlike($nogw, qr{<routes}, 'and no default route, rather than an empty one');

# A node whose address cannot be resolved yields nothing rather than a profile with an empty
# address. The message goes to $tmplerr, which is a file-scoped lexical in Template.pm and so
# cannot be read from here; the caller reports it.
is(xCAT::Template::_autoyast_network6('cn6bad'), undef, 'an unresolvable node yields nothing');

# A prefix outside the IPv6 range is refused rather than written into the profile.
is(xCAT::Template::_autoyast_network6('cn6long'), undef, 'a prefix above 128 is refused');

# dhcp_hostname is false above, because an IPv6-only node has no DHCPv4 to take a hostname
# from. YaST then writes no hostname at all unless the profile carries one, and the installed
# node answers "localhost": y2log recorded Y2Network::Hostname with @static=nil.
like($xml, qr{<hostname>cn6</hostname>}, 'the profile names the node, so it does not boot as localhost');
like($xml, qr{<search>xcat.lab</search>}, 'and a search list, so the short name of the MN resolves');
# The AutoYaST schema gives searchlist the LIST type, as it does nameservers. Without the
# attribute the whole profile is refused with only "Element profile failed to validate
# content", and YaST then reports that no profile could be retrieved.
like($xml, qr{<searchlist config:type="list">}, 'the search list is a typed list, which the schema requires');

# ---- '<xcatmaster>' in site.nameservers is the management node, not the gateway --------
# The gateway can be a separate router that serves no DNS, and a cluster with no gateway
# would have been given no resolver at all.
{
    local $resolvers{cn6} = '<xcatmaster>';
    my $x = xCAT::Template::_autoyast_network6('cn6');
    like( $x, qr{<nameserver>\Q2001:db8:ff::1\E</nameserver>},
        'the placeholder resolves to the management node' );
    unlike( $x, qr{<nameserver>\Q2001:db8:1::fe\E</nameserver>},
        '... and not to the gateway of the node' );
}
{
    local $resolvers{cn6nogw} = '<xcatmaster>';
    my $x = xCAT::Template::_autoyast_network6('cn6nogw');
    like( $x, qr{<nameserver>\Q2001:db8:ff::1\E</nameserver>},
        'a node with no gateway still gets the management node as its resolver' );
}
{
    # Nothing that is not an address reaches the profile.
    local $resolvers{cn6} = '';
    local $master6 = '<xcatmaster>';
    my $x = xCAT::Template::_autoyast_network6('cn6');
    unlike( $x, qr{<nameserver>[^<]*xcatmaster}, 'an unresolved placeholder is not written' );
}
