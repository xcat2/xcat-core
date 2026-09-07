#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Storable qw(dclone);
use Test::More;

BEGIN {
    for my $module (qw(Scope MsgUtils BootUtils TableUtils ServiceNodeUtils Usage Table NetworkUtils)) {
        $INC{"xCAT/$module.pm"} = 1;
    }
}

use xCAT::Utils;

{
    package xCAT::Table;
    our %rows;
    sub new { return bless { table => $_[1] }, $_[0]; }
    sub getAttribs {
        my ($self, $key, $attributes) = @_;
        my ($name) = values %$key;
        my $row = $rows{$self->{table}}{$name};
        return undef unless $row;
        return {map { $_ => $row->{$_} } grep { exists($row->{$_}) } @$attributes};
    }
    sub getNodesAttribs {
        my ($self, $nodes, $attributes) = @_;
        return {map { $_ => [$self->getAttribs({node => $_}, $attributes) || {}] } @$nodes};
    }
    package xCAT::TableUtils;
    our %site;
    sub getTftpDir { return '/tftpboot'; }
    sub get_site_attribute { return $site{$_[1]}; }
    package xCAT::MsgUtils;
    sub trace { return; }
    package xCAT::Usage;
    sub validateArgs { return [0]; }
    package xCAT::ServiceNodeUtils;
    sub getSNList { return ('sn1', 'sn2'); }
    sub getSNandCPnodes { push @{ $_[3] }, @{ $_[1] }; return; }
    package xCAT::NetworkUtils;
    our ($local, %addresses, @lookups);
    sub getipaddr {
        my ($class, $name, %options) = @_;
        push @lookups, [$name, $options{OnlyV4}];
        return $addresses{$name};
    }
    sub thishostisnot { return $_[1] ne $local; }
    sub my_ip_facing { return (0, $local); }
    package xCAT::Scope;
    our @calls;
    sub get_parallel_scope {
        push @calls, ['parallel', Storable::dclone($_[1]{node})];
        return [$_[1]];
    }
    sub get_broadcast_scope_with_parallel {
        my ($class, $request, $servers) = @_;
        push @calls, ['broadcast', Storable::dclone($request->{node})];
        return [{%$request}, map { {%$request, _xcatdest => $_} } @$servers];
    }
}

my $is_mn = 1;
{
    no warnings 'redefine';
    *xCAT::Utils::isMN = sub { return $is_mn; };
    *xCAT::Utils::isServiceNode = sub { return !$is_mn; };
}
my $plugin = $ENV{XCAT_XNBA_SCOPE_FILE} || "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/xnba.pm";
require $plugin;

sub fixture {
    %xCAT::Table::rows = (
        osimage => {
            freebsd => {imagetype => 'freebsd', osname => 'FreeBSD', osvers => 'freebsd15.1', osarch => 'x86_64', provmethod => 'install'},
            linux => {imagetype => 'linux', osname => 'Linux', osvers => 'rhels9', osarch => 'x86_64', provmethod => 'install'},
        },
        nodetype => {map { $_ => {os => 'rhels9', provmethod => 'freebsd'} } qw(node1 node2)},
        noderes => {map { $_ => {xcatmaster => 'sn1', servicenode => 'sn1,sn2', netboot => 'xnba'} } qw(node1 node2)},
    );
    %xCAT::TableUtils::site = (master => 'manager', sharedtftp => 'no', disjointdhcps => 0);
    %xCAT::NetworkUtils::addresses = (
        manager => '192.0.2.1', sn1 => '192.0.2.2', alias1 => '192.0.2.2', sn2 => '192.0.2.3',
        '192.0.2.1' => '192.0.2.1', '192.0.2.2' => '192.0.2.2', '192.0.2.3' => '192.0.2.3',
    );
    $xCAT::NetworkUtils::local = '192.0.2.1';
    $is_mn = 1;
    @xCAT::NetworkUtils::lookups = ();
    @xCAT::Scope::calls = ();
}

sub scope {
    my ($action, @nodes) = @_;
    my @errors;
    my $request = {command => ['nodeset'], arg => [$action], node => \@nodes};
    my $before = dclone($request);
    my $requests = xCAT_plugin::xnba::preprocess_request($request,
        sub { push @errors, @{ $_[0]{error} || [] }; }, sub { die 'Unexpected execution during preprocessing'; });
    return ($requests, \@errors, $request, $before);
}

for my $action ('osimage=freebsd', 'osimage', 'osimage:reboot4deploy') {
    for my $shared ('yes', 'no') {
        subtest "$action routes to one SN with sharedtftp=$shared" => sub {
            fixture();
            $xCAT::TableUtils::site{sharedtftp} = $shared;
            my ($requests, $errors) = scope($action, 'node1', 'node2');
            is_deeply($errors, [], 'owner routing succeeds');
            is(scalar(@$requests), 1, 'request is not broadcast');
            is($requests->[0]{_xcatdest}, '192.0.2.2', 'request targets the configured owner');
            is_deeply($requests->[0]{node}, [qw(node1 node2)], 'owner receives exactly its nodes');
            is_deeply($requests->[0]{_xcatpreprocessed}, [1], 'forwarded request does not redispatch');
            is_deeply($requests->[0]{_disparatetftp}, [1], 'prescripts and DHCP remain local to the owner');
            ok(!grep($_->[0] eq 'broadcast', @xCAT::Scope::calls), 'ordinary broadcast helper is not called');
            ok(!grep(!$_->[1], @xCAT::NetworkUtils::lookups), 'owner resolution requests IPv4 only');
        };
    }
}

for my $control ('boot', 'offline', 'enact') {
    subtest "$control uses nodetype to reach the owner" => sub {
        fixture();
        $xCAT::Table::rows{nodetype}{node1}{os} = 'freebsd15.1';
        $xCAT::NetworkUtils::local = '192.0.2.3';
        $is_mn = 0;
        my ($requests, $errors) = scope($control, 'node1');
        is_deeply($errors, [], 'control request succeeds');
        is(scalar(@$requests), 1, 'control request has one owner');
        is($requests->[0]{_xcatdest}, '192.0.2.2', 'wrong SN forwards to the owner');
        $xCAT::NetworkUtils::local = '192.0.2.2';
        ($requests, $errors) = scope($control, 'node1');
        is_deeply($errors, [], 'owner accepts its own control request');
        ok(!exists($requests->[0]{_xcatdest}), 'completion does not forward away from its local owner');
    };
}

subtest 'unassigned nodes default to the MN, not the current SN' => sub {
    fixture();
    delete $xCAT::Table::rows{noderes}{node1}{$_} for qw(xcatmaster servicenode);
    my ($requests, $errors) = scope('osimage=freebsd', 'node1');
    is_deeply($errors, [], 'MN default is valid');
    ok(!exists($requests->[0]{_xcatdest}), 'MN owns the local request');
    $xCAT::NetworkUtils::local = '192.0.2.3';
    $is_mn = 0;
    ($requests, $errors) = scope('osimage=freebsd', 'node1');
    is_deeply($errors, [], 'SN resolves the MN default');
    is($requests->[0]{_xcatdest}, '192.0.2.1', 'SN forwards unassigned node to MN');
    delete $xCAT::TableUtils::site{master};
    ($requests, $errors) = scope('osimage=freebsd', 'node1');
    is_deeply($requests, [], 'SN cannot silently become owner without an MN');
    like(join('', @$errors), qr/management-node owner/, 'missing MN owner is explicit');
};

subtest 'owner aliases group once and distinct owners split' => sub {
    fixture();
    $xCAT::Table::rows{noderes}{node2}{xcatmaster} = 'alias1';
    my ($requests, $errors) = scope('osimage', 'node1', 'node2');
    is(scalar(@$requests), 1, 'aliases for one IPv4 owner are grouped once');
    $xCAT::Table::rows{noderes}{node2}{xcatmaster} = 'sn2';
    ($requests, $errors) = scope('osimage', 'node1', 'node2');
    is_deeply($errors, [], 'distinct owner routing succeeds');
    is_deeply([map { [$_->{_xcatdest}, $_->{node}] } @$requests],
        [['192.0.2.2', ['node1']], ['192.0.2.3', ['node2']]], 'each node reaches only its owner');
};

subtest 'MN without site.master uses its node-facing address' => sub {
    fixture();
    delete $xCAT::Table::rows{noderes}{node1}{$_} for qw(xcatmaster servicenode);
    delete $xCAT::TableUtils::site{master};
    my ($requests, $errors) = scope('osimage=freebsd', 'node1');
    is_deeply($errors, [], 'MN facing-address fallback succeeds');
    is(scalar(@$requests), 1, 'MN fallback has one owner');
    ok(!exists($requests->[0]{_xcatdest}), 'node-facing MN address remains local');
};

for my $shared ('yes', 'no') {
    subtest "Linux-only preprocessing remains unchanged with sharedtftp=$shared" => sub {
        fixture();
        $xCAT::TableUtils::site{sharedtftp} = $shared;
        $xCAT::Table::rows{nodetype}{$_}{provmethod} = 'linux' for qw(node1 node2);
        my ($requests, $errors) = scope('osimage', 'node1', 'node2');
        is_deeply($errors, [], 'Linux preprocessing succeeds');
        is(scalar(@$requests), $shared eq 'yes' ? 1 : 3, 'original request fan-out is unchanged');
        is_deeply([map { $_->{node} } @$requests], [map { ['node1', 'node2'] } @$requests], 'Linux node grouping is unchanged');
        is_deeply(\@xCAT::NetworkUtils::lookups, [], 'FreeBSD owner resolution does not run');
    };
}

for my $bad_owner (undef, '', 'sn1,sn2', 'sn1 sn2', '2001:db8::1', '../sn1', [], 'unresolved') {
    subtest 'invalid or ambiguous service-node owner fails closed' => sub {
        fixture();
        $xCAT::Table::rows{noderes}{node2}{xcatmaster} = $bad_owner;
        my ($requests, $errors) = scope('osimage', 'node1', 'node2');
        is_deeply($requests, [], 'no selected request is dispatched');
        ok(@$errors, 'invalid owner produces an error');
        is_deeply(\@xCAT::Scope::calls, [], 'owner validation precedes all scope execution');
    };
}

subtest 'mixed Linux requests retain the existing broadcast path' => sub {
    fixture();
    $xCAT::Table::rows{nodetype}{node2}{provmethod} = 'linux';
    my ($requests, $errors) = scope('osimage', 'node1', 'node2');
    is_deeply($errors, [], 'mixed request scopes successfully');
    my @native = grep { $_->{node}[0] eq 'node1' } @$requests;
    my @linux = grep { $_->{node}[0] eq 'node2' } @$requests;
    is(scalar(@native), 1, 'FreeBSD remains single-owner');
    is($native[0]{_xcatdest}, '192.0.2.2', 'FreeBSD targets its explicit owner');
    is(scalar(@linux), 3, 'Linux retains local plus two-SN broadcast');
    is_deeply([map { $_->[1] } grep { $_->[0] eq 'broadcast' } @xCAT::Scope::calls], [['node2']], 'only Linux enters broadcast helper');
};

subtest 'incompatible FreeBSD backend is rejected before owner dispatch' => sub {
    fixture();
    $xCAT::Table::rows{noderes}{node1}{netboot} = 'pxe';
    my ($requests, $errors) = scope('osimage=freebsd', 'node1');
    is_deeply($requests, [], 'incompatible backend is not dispatched');
    like(join('', @$errors), qr/netboot=xnba/, 'backend error is explicit');
};

done_testing();
