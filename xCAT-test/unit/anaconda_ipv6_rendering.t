#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';

use File::Spec;
use FindBin;
use Test::More;

my $repo_root = File::Spec->catdir($FindBin::Bin, '..', '..');
$ENV{XCATROOT} = File::Spec->catdir($repo_root, 'xCAT-server');

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";

my $anaconda = File::Spec->catfile(
    $repo_root,
    'xCAT-server/lib/xcat/plugins/anaconda.pm'
);
do $anaconda or die $@ || "Unable to load $anaconda: $!";
open(my $anaconda_fh, '<', $anaconda) or die "Unable to read $anaconda: $!";
my $anaconda_source = do { local $/; <$anaconda_fh> };
close($anaconda_fh);

my %addresses = (
    nodev4                => { 4 => '192.0.2.50' },
    nodev6                => { 6 => '2001:db8:1::50' },
    nodedual              => { 4 => '192.0.2.60', 6 => '2001:db8:1::60' },
    'boot6.example.test'  => { 6 => '2001:db8::10' },
);
my @facing_calls;
my %network_cfg = (
    nodev6 => [ '2001:db8:1::50', 'nodev6', '2001:db8:1::fe', 64 ],
    nodev6mastergw => [ '2001:db8:2::50', 'nodev6mastergw', '<xcatmaster>', 64 ],
    nodev6nogw => [ '2001:db8:3::50', 'nodev6nogw', '', 64 ],
);

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
    my $node = shift;
    $node = shift if defined($node) && $node eq 'xCAT::NetworkUtils';
    return @{ $network_cfg{$node} || [] };
};

ok(xCAT::SvrUtils->is_el10_os('rhels10.0'), 'RHEL 10 is recognized as EL10');
ok(xCAT::SvrUtils->is_el10_os('rocky10'), 'Rocky 10 is recognized as EL10');
ok(!xCAT::SvrUtils->is_el10_os('rhels9.6'), 'EL9 is outside the EL10 IPv6 rendering path');

ok(xCAT::NetworkUtils->node_is_ipv6_only('nodev6'), 'AAAA-only node is detected as IPv6-only');
ok(!xCAT::NetworkUtils->node_is_ipv6_only('nodev4'), 'IPv4-only node stays on the IPv4 path');
ok(!xCAT::NetworkUtils->node_is_ipv6_only('nodedual'), 'dual-stack node retains IPv4 preference');

is(
    xCAT::NetworkUtils->ipv6_server_for_node('nodev6', 'boot6.example.test'),
    '2001:db8::10',
    'explicit image server resolves in the node IPv6 family'
);
is(
    xCAT::NetworkUtils->ipv6_server_for_node('nodev6', '!myipfn!'),
    '2001:db8::1',
    'dynamic xCAT master resolves to the IPv6-facing local address'
);
is_deeply($facing_calls[-1], ['nodev6', 6], 'dynamic master uses the shared family helper');

is(
    xCAT_plugin::anaconda::_server_authority('192.0.2.1', 8080, 0),
    '192.0.2.1:8080',
    'IPv4 authority remains byte-for-byte unchanged'
);
is(
    xCAT_plugin::anaconda::_server_authority('2001:db8::1', 8080, 1),
    '[2001:db8::1]:8080',
    'IPv6 URL authority is bracketed before its port'
);

is(
    xCAT_plugin::anaconda::_syslog_server_arg('192.0.2.1'),
    '192.0.2.1',
    'IPv4 syslog kernel arguments remain unchanged'
);
is(
    xCAT_plugin::anaconda::_syslog_server_arg('2001:db8::1'),
    '[2001:db8::1]',
    'IPv6 syslog kernel arguments use a bracketed server literal'
);
is(
    xCAT_plugin::anaconda::_syslog_server_arg('!myipfn!'),
    '!myipfn!',
    'deferred xCAT master token remains available for late bootloader replacement'
);
is(
    xCAT_plugin::anaconda::_syslog_server_arg('mgmt.example.test'),
    'mgmt.example.test',
    'hostname syslog kernel arguments remain unchanged'
);
is(
    xCAT_plugin::anaconda::_syslog_server_arg('[2001:db8::1]'),
    '[2001:db8::1]',
    'already-bracketed IPv6 syslog kernel arguments remain unchanged'
);
ok(
    !defined(xCAT_plugin::anaconda::_syslog_server_arg('bad host')),
    'malformed syslog server arguments remain rejected'
);
like(
    $anaconda_source,
    qr/syslog\.server=\$syslog_server syslog\.type=rsyslogd/,
    'stateless debug boot uses the family-safe syslog argument'
);
like(
    $anaconda_source,
    qr/inst\.syslog=\$syslog_server/,
    'stateful EL10 debug install uses the family-safe syslog argument'
);

is(
    xCAT_plugin::anaconda::_el10_install_url_args(
        'http', '192.0.2.1:8080', '/install/rhels10/x86_64', 'nodev4'
    ),
    'inst.repo=http://192.0.2.1:8080/install/rhels10/x86_64 inst.ks=http://192.0.2.1:8080/install/autoinst/nodev4',
    'EL10 IPv4 install URL arguments remain unchanged'
);
is(
    xCAT_plugin::anaconda::_el10_install_url_args(
        'http', '[2001:db8::1]:8080', '/install/rhels10/x86_64', 'nodev6'
    ),
    'inst.repo=http://[2001:db8::1]:8080/install/rhels10/x86_64 inst.ks=http://[2001:db8::1]:8080/install/autoinst/nodev6',
    'EL10 IPv6 install URL arguments use bracketed authorities'
);

is(
    xCAT_plugin::anaconda::_el10_static_ipv6_boot_args(
        'nodev6', { nicname => 'eno1', mac => '02:00:00:00:00:61' }
    ),
    'rd.neednet=1 ip=[2001:db8:1::50]::[2001:db8:1::fe]:64:nodev6:eno1:none',
    'named install interface receives the configured static IPv6 boot address'
);
is(
    xCAT_plugin::anaconda::_el10_static_ipv6_boot_args(
        'nodev6nogw', { mac => '02-00-00-00-00-63' }
    ),
    'ifname=xcatboot0:02:00:00:00:00:63 rd.neednet=1 ip=[2001:db8:3::50]:::64:nodev6nogw:xcatboot0:none',
    'unspecified install interface is deterministically named and bound to its MAC'
);
is(
    xCAT_plugin::anaconda::_el10_static_ipv6_boot_args(
        'nodev6mastergw', { nicname => 'ens3' }
    ),
    'rd.neednet=1 ip=[2001:db8:2::50]::[2001:db8::1]:64:nodev6mastergw:ens3:none',
    'xcatmaster gateway resolves to the IPv6-facing address and is bracketed'
);
is_deeply(
    $facing_calls[-1],
    ['nodev6mastergw', 6],
    'static IPv6 xcatmaster gateway lookup is constrained to IPv6'
);
ok(
    !defined(xCAT_plugin::anaconda::_el10_static_ipv6_boot_args('nodev6nogw', {})),
    'static IPv6 boot rendering refuses an unbound interface when no NIC name or MAC exists'
);

done_testing();
