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
local *xCAT::NetworkUtils::my_ip_facing_family = sub {
    my $node = shift;
    $node = shift if defined($node) && $node eq 'xCAT::NetworkUtils';
    my $family = shift;
    push @facing_calls, [$node, $family];
    return (0, '2001:db8::1');
};
local *xCAT::NetworkUtils::getNodeNetworkCfg6 = sub {
    my $candidate = shift;
    $candidate = shift if defined($candidate) && $candidate eq 'xCAT::NetworkUtils';
    return ('2001:db8:1::50', $candidate, '<xcatmaster>', 64);
};
local *xCAT::NetworkUtils::getNodeNameservers = sub {
    my $nodes = shift;
    $nodes = shift if defined($nodes) && $nodes eq 'xCAT::NetworkUtils';
    return { $nodes->[0] => 'dns6.example.test,192.0.2.53' };
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
    my ($node, $master, $body) = @_;
    $body //= "#KICKSTARTNET#\n#INSTALL_SOURCES_IN_PRE#\n";
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
        os => 'alma10.1',
    );
    is($error, 0, "$node minimal EL10 template renders without error");

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
