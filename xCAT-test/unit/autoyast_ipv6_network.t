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
use Test::More tests => 13;

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
);
no warnings 'redefine';
*xCAT::NetworkUtils::getNodeNetworkCfg6   = sub { my $n = $_[-1]; return @{ $cfg{$n} || [] } };
*xCAT::NetworkUtils::ipv6_server_for_node = sub { return $_[-1] };
*xCAT::NetworkUtils::getNodeDomains       = sub { return { map { $_ => 'xcat.lab' } @{ $_[-1] } } };
*xCAT::NetworkUtils::getNodeNameservers   = sub { return { map { $_ => '2001:db8:1::fe' } @{ $_[-1] } } };
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

# dhcp_resolv says whether DHCP may overwrite resolv.conf. The AutoYaST schema of Leap 15.6
# does not accept it, and one invalid element makes YaST reject the whole profile: it reports
# "Extra element networking in interleave" and then that no profile could be retrieved. The
# section configures the node statically, so there is no DHCP to keep away from resolv.conf.
unlike($xml, qr{<dhcp_resolv}, 'no dhcp_resolv, which the Leap 15.6 schema refuses');
like($xml, qr{<dhcp_hostname}, 'dhcp_hostname stays, which the schema does accept');

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
