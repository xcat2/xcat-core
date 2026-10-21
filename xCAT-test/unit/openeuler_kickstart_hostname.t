#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $dir = tempdir(CLEANUP => 1);
make_path("$dir/db", "$dir/install");
$ENV{XCATROOT} = repo_path('xCAT-server');
$ENV{XCATCFG} = "SQLite:$dir/db";
require xCAT::Table;
my $source = $ENV{XCAT_TEST_TEMPLATE_SOURCE}
  || repo_path('xCAT-server/lib/perl/xCAT/Template.pm');
require $source;

my %site_values = (
    installdir => "$dir/install", master => '192.0.2.1', httpport => 80,
    domain => 'example.invalid', autoulaprefix => 'fd00::',
);
my $site = xCAT::Table->new('site', -create => 1);
for my $key (keys %site_values) {
    $site->setAttribs({ key => $key }, { value => $site_values{$key} });
}
$site->close();
%::XCATSITEVALS = (%site_values, managedaddressmode => 'dhcp');
write_text("$dir/network.tmpl", "#KICKSTARTNET#\n");

my $sequence = 0;
sub render {
    my (%args) = @_;
    my $node = $args{node} || 'cn-' . ++$sequence;
    for my $entry (
        ['nodelist', { groups => 'all' }],
        ['noderes', {
            xcatmaster => '192.0.2.1', nfsserver => '192.0.2.1',
            installnic => $args{installnic} || '', primarynic => $args{primarynic} || '',
        }],
        ['mac', { mac => $args{mac} || '52:54:00:12:34:56' }],
    ) {
        my ($name, $values) = @$entry;
        my $table = xCAT::Table->new($name, -create => 1);
        $table->setAttribs({ node => $node }, $values);
        $table->close();
    }
    local $::XCATSITEVALS{managedaddressmode} = exists($args{mode}) ? $args{mode} : 'dhcp';
    my $output = "$dir/$node.ks";
    my $error = xCAT::Template->subvars("$dir/network.tmpl", $output, $node,
        undef, undef, $args{platform}, undef, { xcatmaster => '192.0.2.1' });
    ok(!$error, "$args{label} renders successfully") or diag($error);
    return (read_text($output), $node);
}

for my $case (
    { label => 'native DHCP by MAC', node => 'native-short', device => '52:54:00:12:34:56' },
    { label => 'native DHCP preserves FQDN', node => 'native.example.invalid', installnic => 'enP1p12s0f0', device => 'enP1p12s0f0' },
    { label => 'native DHCP by primary interface', primarynic => 'eth2', device => 'eth2' },
    { label => 'native DHCP with explicit MAC', installnic => '52:54:AA:12:34:99', device => '52:54:aa:12:34:99' },
    { label => 'native DHCP with absent address mode', mode => undef, installnic => 'eth0', device => 'eth0' },
) {
    my ($output, $node) = render(%$case, platform => 'openeuler');
    is($output, "network --onboot=yes --bootproto=dhcp --device=$case->{device} --hostname=$node\n",
        "$case->{label} persists the existing node identity");
}

for my $platform (undef, qw(rh SL centos alma ol fedora rocky)) {
    my $label = defined($platform) ? "$platform DHCP" : 'unspecified platform DHCP';
    my ($output) = render(label => $label, platform => $platform, installnic => 'eth0');
    is($output, "network --onboot=yes --bootproto=dhcp --device=eth0\n",
        "$label retains its exact previous output");
}

{
    no warnings 'redefine';
    local *xCAT::NetworkUtils::getNodeNetworkCfg = sub {
        my (undef, $node) = @_;
        return ('192.0.2.20', $node, '192.0.2.1', '255.255.255.0');
    };
    local *xCAT::NetworkUtils::getNodeNameservers = sub {
        my (undef, $nodes) = @_;
        return { map { $_ => '192.0.2.1' } @$nodes };
    };
    for my $platform (qw(openeuler rh)) {
        my ($output, $node) = render(label => "$platform static", platform => $platform,
            mode => 'static', installnic => 'eth0');
        is($output, "network --onboot=yes --bootproto=static  --device=eth0 --ip=192.0.2.20 --netmask=255.255.255.0 --gateway=192.0.2.1 --hostname=$node  --nameserver=192.0.2.1\n",
            "$platform static retains one hostname and its previous addressing options");
    }
}

for my $platform (qw(openeuler rh)) {
    my ($output) = render(label => "$platform autoula", platform => $platform,
        mode => 'autoula', installnic => 'eth0');
    is($output, "network --onboot=yes --bootproto=static --device=eth0 --noipv4 --ipv6=fd00::5054:00ff:fe12:3456\n",
        "$platform autoula retains its previous output");
}

done_testing();
