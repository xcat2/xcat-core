#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';

use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
BEGIN { $ENV{XCATROOT} = "$FindBin::Bin/../../xCAT-server"; }
use Test::More;

my $repo_root = File::Spec->catdir($FindBin::Bin, '..', '..');

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use xCAT::Template;

my %addresses = (
    nodev4                 => { 4 => '192.0.2.50' },
    nodev6                 => { 6 => '2001:db8:1::50' },
    # A node whose gateway is a literal router address, not the management node. The two must
    # differ, or a resolver test cannot tell the management node from the gateway.
    nodev6lit              => { 6 => '2001:db8:1::51' },
    nodedual               => { 4 => '192.0.2.60', 6 => '2001:db8:1::60' },
    'master4.example.test' => { 4 => '192.0.2.1' },
    'master6.example.test' => { 6 => '2001:db8::1' },
    'dns6.example.test'    => { 6 => '2001:db8::53' },
);
my @facing_calls;

no warnings 'redefine';
local *xCAT::NetworkUtils::getipaddr = sub {
    my $host = shift;
    $host = shift if defined($host) && $host eq 'xCAT::NetworkUtils';
    my %opts = @_;
    my $entry = $addresses{$host} || {};
    return $entry->{6} if $opts{OnlyV6};
    return $entry->{4} if $opts{OnlyV4};
    return $entry->{4} || $entry->{6};
};
# The address of the management node on the network of the node. An MN with none is the
# control of the resolver fallback below: it must yield no resolver rather than a guess.
our $master_facing6 = '2001:db8::1';
local *xCAT::NetworkUtils::my_ip_facing_family = sub {
    my $node = shift;
    $node = shift if defined($node) && $node eq 'xCAT::NetworkUtils';
    my $family = shift;
    push @facing_calls, [$node, $family];
    return (1, undef) unless defined($master_facing6);
    return (0, $master_facing6);
};
local *xCAT::NetworkUtils::getNodeNetworkCfg6 = sub {
    my $candidate = shift;
    $candidate = shift if defined($candidate) && $candidate eq 'xCAT::NetworkUtils';
    return ('2001:db8:1::51', $candidate, '2001:db8:1::fe', 64)
      if $candidate eq 'nodev6lit';
    return ('2001:db8:1::50', $candidate, '<xcatmaster>', 64);
};
# site.nameservers holds one list for the whole cluster, so it can name resolvers the node
# cannot reach.
our $site_nameservers = 'dns6.example.test,192.0.2.53';
local *xCAT::NetworkUtils::getNodeNameservers = sub {
    my $nodes = shift;
    $nodes = shift if defined($nodes) && $nodes eq 'xCAT::NetworkUtils';
    return { $nodes->[0] => $site_nameservers };
};

is(
    xCAT::Template::_dynamic_kickstart_network('02:00:00:00:00:41', 0),
    'dhcp --device=02:00:00:00:00:41',
    'IPv4 dynamic Kickstart network fragment remains unchanged'
);
is(
    xCAT::Template::_dynamic_kickstart_network('02:00:00:00:00:61', 1),
    'dhcp --device=02:00:00:00:00:61 --noipv4 --ipv6=dhcp',
    'IPv6-only Kickstart network fragment disables IPv4 and enables DHCPv6'
);
# The media_url of an autoyast add-on product. The table substitution writes the address of
# the management node as it stands, so an IPv6-only node was told to install from
# "http://2001:db8::1//install/leap15.6/x86_64", which is not a URL YaST can read.
is(
    xCAT::Template::_sles_media_url(1, '[2001:db8::1]', '', '/install/leap15.6/x86_64'),
    'http://[2001:db8::1]//install/leap15.6/x86_64',
    'an IPv6-only node gets a bracketed media_url'
);
is(
    xCAT::Template::_sles_media_url(1, '[2001:db8::1]', ':8080', '/install/leap15.6/x86_64'),
    'http://[2001:db8::1]:8080//install/leap15.6/x86_64',
    'a custom port follows the bracketed address'
);
is(
    xCAT::Template::_sles_media_url(0, '[2001:db8::1]', '', '/install/leap15.6/x86_64'),
    'http://#TABLE:noderes:$NODE:nfsserver#//install/leap15.6/x86_64',
    'a node with IPv4 keeps the table substitution'
);
unlike(
    xCAT::Template::_sles_media_url(1, '[2001:db8::1]', '', '/install/leap15.6/x86_64'),
    qr{http://2001:db8::1},
    'no unbracketed IPv6 authority reaches the media_url'
);

{
    package TemplateIPv6MacTable;
    sub new { return bless {}, shift; }
    sub getNodeAttribs {
        my ($self, $node) = @_;
        my $mac = $node eq 'nodev6' ? '02:00:00:00:00:61' : '02:00:00:00:00:41';
        return { mac => $mac };
    }
}

local *xCAT::Template::getPersistentKcmdline = sub { return ''; };
local *xCAT::Table::new = sub {
    my ($class, $name) = @_;
    return TemplateIPv6MacTable->new() if $name eq 'mac';
    return;
};
local *xCAT::TableUtils::get_site_attribute = sub {
    my ($class, $attribute) = @_;
    return 8080 if $attribute eq 'httpport';
    return '/install' if $attribute eq 'installdir';
    return;
};
local *xCAT::Utils::parseMacTabEntry = sub {
    my ($class, $mac) = @_;
    return lc($mac);
};
local $::XCATSITEVALS{managedaddressmode} = 'dhcp';
local $::XCATSITEVALS{xcatdebugmode} = '0';

sub render_minimal_template {
    my ($node, $master, $body, $os) = @_;
    $body //= "#KICKSTARTNET#\n#INSTALL_SOURCES_IN_PRE#\n";
    $os //= 'alma10.1';
    my $tmpdir = tempdir(CLEANUP => 1);
    my $input = "$tmpdir/input.tmpl";
    my $output = "$tmpdir/output";
    open(my $template, '>', $input) or die "Unable to write template: $!";
    print {$template} $body;
    close($template);

    my $error = xCAT::Template->subvars(
        $input,
        $output,
        $node,
        undef,
        '/install/rhels10/x86_64',
        'rh',
        undef,
        { xcatmaster => $master },
        os => $os,
    );
    is($error, 0, "$node minimal $os template renders without error");

    open(my $rendered, '<', $output) or die "Unable to read rendered template: $!";
    local $/;
    my $content = <$rendered>;
    close($rendered);
    return $content;
}

my $v6_rendered = render_minimal_template('nodev6', 'master6.example.test');
like(
    $v6_rendered,
    qr/^network --onboot=yes --bootproto=static --device=02:00:00:00:00:61 --activate --noipv4 --ipv6=2001:db8:1::50\/64 --ipv6gateway=2001:db8::1 --hostname=nodev6 --nameserver=2001:db8::53$/m,
    'rendered EL10 IPv6-only Kickstart uses the node address and IPv6-only static configuration'
);
like(
    $v6_rendered,
    qr/^nextserver_uri_host="\[\$nextserver\]"$/m,
    'IPv6-only repository renderer brackets the raw NEXTSERVER value'
);
like(
    $v6_rendered,
    qr{http://\'\$nextserver_uri_host\':8080/},
    'IPv6-only repository URL uses the bracketed NEXTSERVER authority'
);
is($ENV{MASTER_IP}, '2001:db8::1', 'IPv6-only template resolves the explicit master as IPv6');

{
    local $::XCATSITEVALS{managedaddressmode} = 'static';
    my $v6_static_rendered =
      render_minimal_template('nodev6', 'master6.example.test');
    like(
        $v6_static_rendered,
        qr/^network --onboot=yes --bootproto=static --device=02:00:00:00:00:61 --activate --noipv4 --ipv6=2001:db8:1::50\/64 --ipv6gateway=2001:db8::1 --hostname=nodev6 --nameserver=2001:db8::53$/m,
        'site static mode keeps an EL10 IPv6-only node on the native IPv6 path'
    );
    unlike(
        $v6_static_rendered,
        qr/--ip=|--netmask=/,
        'site static mode does not fall through to legacy IPv4 Kickstart options'
    );
}

# EL 8 and EL 9 render the same static network line as EL 10, by operator decision of
# 2026-11-05. They rendered "dhcp --noipv4 --ipv6=dhcp" before, and anaconda then solicited
# DHCPv6 with an identifier that no makedhcp reservation holds.
foreach my $el_os (qw(alma8.10 rhels9.6)) {
    my $el_rendered =
      render_minimal_template('nodev6', 'master6.example.test', undef, $el_os);
    like(
        $el_rendered,
        qr/^network --onboot=yes --bootproto=static --device=02:00:00:00:00:61 --activate --noipv4 --ipv6=2001:db8:1::50\/64 --ipv6gateway=2001:db8::1 --hostname=nodev6 --nameserver=2001:db8::53$/m,
        "$el_os renders the static IPv6 network line"
    );
    unlike($el_rendered, qr/--ipv6=dhcp/,
        "$el_os does not ask DHCPv6 from the installer");
}

# The resolver of a statically configured IPv6-only node. site.nameservers names the IPv4
# resolver of the cluster on a normal lab, so no resolver reached the node and it installed
# with no /etc/resolv.conf.
{
    local $site_nameservers = '192.168.177.1';
    my $v4ns = render_minimal_template('nodev6lit', 'master6.example.test', undef, 'alma9.6');
    like($v4ns, qr/^network .* --nameserver=2001:db8::1$/m,
        'an IPv4 site resolver is replaced by the IPv6 address of the management node');
    unlike($v4ns, qr/--nameserver=[^ ]*192\.168\.177\.1/,
        'and the IPv4 resolver itself does not reach the node');
    unlike($v4ns, qr/--nameserver=[^ ]*2001:db8:1::fe/,
        'and not by the gateway, which can be a router that serves no DNS');
}
{
    local $site_nameservers = '2001:db8:aa::53';
    my $v6ns = render_minimal_template('nodev6lit', 'master6.example.test', undef, 'alma9.6');
    like($v6ns, qr/^network .* --nameserver=2001:db8:aa::53$/m,
        'a configured IPv6 resolver is kept as it stands');
}
{
    # The control: an MN with no address on the network of the node has no resolver to offer.
    local $site_nameservers = '192.168.177.1';
    local $master_facing6 = undef;
    my $none = render_minimal_template('nodev6lit', 'master6.example.test', undef, 'alma9.6');
    unlike($none, qr/--nameserver/,
        'a management node with no address on the network yields no resolver at all');
}

my $v4_rendered = render_minimal_template('nodev4', 'master4.example.test');
like(
    $v4_rendered,
    qr/^network --onboot=yes --bootproto=dhcp --device=02:00:00:00:00:41$/m,
    'rendered IPv4 Kickstart network command remains unchanged'
);
unlike($v4_rendered, qr/nextserver_uri_host/, 'IPv4 repository rendering adds no IPv6 helper variable');
like(
    $v4_rendered,
    qr{http://\'\$nextserver\':8080/},
    'IPv4 repository URL retains the original NEXTSERVER expression'
);
is($ENV{MASTER_IP}, '192.0.2.1', 'IPv4 template keeps legacy master resolution');

# post.sles.common rewrites the interface configuration with BOOTPROTO=dhcp unless
# MANAGEDADDRESSMODE reads static, which undoes the static IPv6 configuration the
# AutoYaST profile carries for an IPv6-only node. The site attribute describes the
# cluster, so it cannot answer for a node that has no IPv4 address to ask for.
{
    my $v6_mode =
      render_minimal_template('nodev6', 'master6.example.test', "#MANAGEDADDRESSMODE#\n");
    like($v6_mode, qr/^static$/m,
        'an IPv6-only node reports the static address mode whatever the site says');

    my $v4_mode =
      render_minimal_template('nodev4', 'master4.example.test', "#MANAGEDADDRESSMODE#\n");
    like($v4_mode, qr/^dhcp$/m, 'an IPv4 node keeps the site address mode');

    my $dual_mode =
      render_minimal_template('nodedual', 'master4.example.test', "#MANAGEDADDRESSMODE#\n");
    like($dual_mode, qr/^dhcp$/m,
        'a dual-stack node keeps the site address mode, since it can still use DHCP');
}

done_testing();
