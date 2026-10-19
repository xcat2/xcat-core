#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Storable qw(dclone);
use Test::More;
use XML::Simple;
use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Temp qw(tempdir);

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
        my ($self, $key, @attributes) = @_;
        @attributes = @{ $attributes[0] } if ref($attributes[0]);
        my ($name) = values %$key;
        my $row = $rows{$self->{table}}{$name};
        return undef unless $row;
        return {map { $_ => $row->{$_} } grep { exists($row->{$_}) } @attributes};
    }
    sub getNodesAttribs {
        my ($self, $nodes, $attributes) = @_;
        return {map { $_ => [$self->getAttribs({node => $_}, $attributes) || {}] } @$nodes};
    }
    package xCAT::TableUtils;
    our (%site, $tftpdir);
    sub getTftpDir { return $tftpdir; }
    sub get_site_attribute { return $site{$_[1]}; }
    package xCAT::MsgUtils;
    sub trace { return; }
    sub message { return; }
    package xCAT::BootUtils;
    sub volatile_addkcmdline { return $_[0]; }
    package xCAT::Usage;
    sub validateArgs { return [0]; }
    package xCAT::ServiceNodeUtils;
    sub getSNList { return ('sn1', 'sn2'); }
    sub getSNandCPnodes { push @{ $_[3] }, @{ $_[1] }; return; }
    sub getSNformattedhash { return {manager => $_[1]}; }
    package xCAT::NetworkUtils;
    our ($local, %addresses, @lookups, @facing, %off_subnet);
    sub getipaddr {
        my ($class, $name, %options) = @_;
        push @lookups, [$name, $options{OnlyV4}];
        return $addresses{$name};
    }
    sub thishostisnot { return $_[1] ne $local; }
    sub my_ip_facing { return (0, @facing); }
    sub determinehostname { return 'manager'; }
    sub checkNodeIPaddress { return {ip => $_[1] eq 'node1' ? '198.51.100.10' : '192.0.2.10'}; }
    sub nodeonmynet { return !$off_subnet{$_[1]}; }
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
my $temporary = abs_path(tempdir(CLEANUP => 1));
$xCAT::TableUtils::tftpdir = "$temporary/tftp";
my $sequence = 0;
my $pool_dispatch;
{
    no warnings 'redefine';
    *xCAT::Utils::isMN = sub { return $is_mn; };
    *xCAT::Utils::isServiceNode = sub { return !$is_mn; };
}
my $plugin = $ENV{XCAT_XNBA_SCOPE_FILE} || "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/xnba.pm";
require $plugin;

sub fixture {
    $pool_dispatch = undef;
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
    @xCAT::NetworkUtils::facing = ('192.0.2.1');
    %xCAT::NetworkUtils::off_subnet = ();
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
        sub { push @errors, @{ $_[0]{error} || [] }; }, $pool_dispatch || sub { die 'Unexpected execution during preprocessing'; });
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

for my $bad_owner ('sn1,sn2', 'sn1 sn2', '2001:db8::1', '../sn1', [], 'unresolved') {
    subtest 'invalid or ambiguous service-node owner fails closed' => sub {
        fixture();
        $xCAT::Table::rows{noderes}{node2}{xcatmaster} = $bad_owner;
        my ($requests, $errors) = scope('osimage', 'node1', 'node2');
        is_deeply($requests, [], 'no selected request is dispatched');
        ok(@$errors, 'invalid owner produces an error');
        is_deeply(\@xCAT::Scope::calls, [], 'owner validation precedes all scope execution');
    };
}

subtest 'a pool coordinator failure preserves fixed-owner work' => sub {
    for my $unset (undef, '') {
        fixture();
        $xCAT::Table::rows{noderes}{node2}{xcatmaster} = $unset;
        my ($requests, $errors) = scope('osimage', 'node1', 'node2');
        is(scalar(@$requests), 1, 'fixed owner retains one scoped request');
        is_deeply($requests->[0]{node}, ['node1'], 'unavailable pool is excluded from the fixed owner request');
        like(join('', @$errors), qr/node2:.*Unexpected[ ]execution/sx, 'coordinator failure names the pool node');
    }
};

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

for my $facing ([], ['192.0.2.1', '192.0.2.2']) {
    subtest 'MN default owner requires one node-facing address' => sub {
        fixture();
        delete $xCAT::Table::rows{noderes}{node1}{$_} for qw(xcatmaster servicenode);
        delete $xCAT::TableUtils::site{master};
        @xCAT::NetworkUtils::facing = @$facing;
        my ($requests, $errors) = scope('osimage=freebsd', 'node1');
        is_deeply($requests, [], 'ambiguous or missing facing address dispatches no request');
        like(join('', @$errors), qr/management-node address/, 'owner selection failure is explicit');
        is_deeply(\@xCAT::Scope::calls, [], 'no owner is selected from partial address results');
    };
}

sub process_scoped {
    my ($request) = @_;
    my $tftp = "$temporary/request-" . ++$sequence;
    for my $node (@{ $request->{node} }) {
        $xCAT::Table::rows{noderes}{$node}{tftpdir} = $tftp;
        make_path("$tftp/xcat/freebsd/$node/boot", "$tftp/xcat/xnba/nodes");
        for my $loader ('pxeboot', 'loader.efi') {
            open(my $file, '>', "$tftp/xcat/freebsd/$node/boot/$loader") or die $!;
            print {$file} 'native loader fixture';
            close($file) or die $!;
        }
    }
    my (@responses, @commands);
    xCAT_plugin::xnba::process_request($request, sub { push @responses, dclone($_[0]); }, sub {
        my ($req) = @_;
        push @commands, dclone($req);
        if ($req->{command}[0] eq 'setdestiny') {
            for my $node (@{ $req->{node} }) {
                my $image = $xCAT::Table::rows{osimage}{ $xCAT::Table::rows{nodetype}{$node}{provmethod} };
                $xCAT::Table::rows{nodetype}{$node}{os} = $image->{osvers};
                $xCAT::Table::rows{nodetype}{$node}{arch} = $image->{osarch};
                $xCAT::Table::rows{chain}{$node}{currstate} = 'install freebsd15.1-x86_64-compute';
                $req->{bootparams}{$node} = [{kernel => "xcat/freebsd/$node/boot/pxeboot", initrd => '', kcmdline => '', addkcmdline => ''}];
            }
        }
    });
    return (\@responses, \@commands, $tftp);
}

sub read_file {
    my ($path) = @_;
    return unless -f $path;
    open(my $file, '<', $path) or die $!;
    my $text = do { local $/; <$file> };
    close($file) or die $!;
    return $text;
}

subtest 'selected FreeBSD owner generates routed-node configuration through both request handlers' => sub {
    fixture();
    $xCAT::NetworkUtils::off_subnet{'198.51.100.10'} = 1;
    my ($requests, $errors) = scope('osimage=freebsd', 'node1');
    is_deeply($errors, [], 'native request selects its explicit owner');
    $xCAT::NetworkUtils::local = '192.0.2.2';
    my ($responses, $commands, $tftp) = process_scoped($requests->[0]);
    is_deeply($responses, [], 'routed native node is not dropped by the legacy subnet filter');
    like(read_file("$tftp/xcat/xnba/nodes/node1"), qr{chain tftp://\$\{next-server\}/xcat/freebsd/node1/boot/pxeboot}, 'owner publishes the BIOS native loader script');
    like(read_file("$tftp/xcat/xnba/nodes/node1.uefi"), qr{chain tftp://\$\{next-server\}/xcat/freebsd/node1/boot/loader.efi}, 'owner publishes the UEFI native loader script');
    is_deeply([map { $_->{command}[0] } @$commands], [qw(runbeginpre setdestiny makedhcp runendpre)], 'routed native request completes all existing stages');
    is_deeply([map { $_->{node} } @$commands], [map { ['node1'] } 1 .. 4], 'all stages retain the selected node');
    is_deeply([map { $_->{arg} } grep { $_->{command}[0] ne 'setdestiny' } @$commands],
        [['osimage=freebsd', '-l'], ['-l'], ['osimage=freebsd', '-l']], 'prescripts and DHCP remain local to the selected owner');
};

subtest 'wrong host rejects a forwarded native request before processing nodes' => sub {
    fixture();
    my ($requests) = scope('osimage=freebsd', 'node1');
    my ($responses, $commands, $tftp) = process_scoped($requests->[0]);
    like(join('', map { @{ $_->{error} || [] } } @$responses), qr/FreeBSD.*owner/, 'misdirected native request reports an ownership error');
    is_deeply($commands, [], 'wrong owner invokes no prescripts, installer or DHCP update');
    ok(!-e "$tftp/xcat/xnba/nodes/node1", 'wrong owner publishes no script');
};

subtest 'routed native nodes remain in a batch with directly connected nodes' => sub {
    fixture();
    $xCAT::NetworkUtils::off_subnet{'198.51.100.10'} = 1;
    my ($requests) = scope('osimage', 'node1', 'node2');
    $xCAT::NetworkUtils::local = '192.0.2.2';
    my ($responses, $commands, $tftp) = process_scoped($requests->[0]);
    is_deeply($responses, [], 'native batch reports no error');
    for my $node ('node1', 'node2') {
        like(read_file("$tftp/xcat/xnba/nodes/$node"), qr{chain tftp://\$\{next-server\}/xcat/freebsd/$node/boot/pxeboot}, "$node receives its own boot script");
    }
    is_deeply([map { [sort @{ $_->{node} }] } @$commands], [map { ['node1', 'node2'] } 1 .. 4],
        'routed and directly connected native nodes remain in every stage');
};

for my $invalid ('192.0.2.2', [], [undef], ['sn1'], ['192.0.2.2', '192.0.2.1']) {
    subtest 'malformed native-owner routing metadata cannot enable processing' => sub {
        fixture();
        my ($requests) = scope('osimage=freebsd', 'node1');
        $requests->[0]{_freebsd_owner} = $invalid;
        $xCAT::NetworkUtils::local = '192.0.2.2';
        my ($responses, $commands, $tftp) = process_scoped($requests->[0]);
        like(join('', map { @{ $_->{error} || [] } } @$responses), qr/FreeBSD.*owner/, 'malformed owner metadata is rejected');
        is_deeply($commands, [], 'malformed owner invokes no request stages');
        ok(!-e "$tftp/xcat/xnba/nodes/node1", 'malformed owner publishes no script');
    };
}

subtest 'off-subnet Linux nodes retain legacy filtering' => sub {
    fixture();
    $xCAT::Table::rows{nodetype}{node1}{provmethod} = 'linux';
    $xCAT::NetworkUtils::off_subnet{'198.51.100.10'} = 1;
    my ($requests, $errors) = scope('osimage', 'node1');
    is_deeply($errors, [], 'legacy request still preprocesses');
    my ($responses, $commands, $tftp) = process_scoped($requests->[0]);
    is_deeply($commands, [], 'legacy off-subnet node does not reach its installer');
    ok(!-e "$tftp/xcat/xnba/nodes/node1", 'legacy filtering creates no node script');
};

subtest 'mixed OS preprocessing never grants native routing to legacy nodes' => sub {
    fixture();
    $xCAT::Table::rows{nodetype}{node1}{provmethod} = 'linux';
    $xCAT::NetworkUtils::off_subnet{'198.51.100.10'} = 1;
    my ($requests, $errors) = scope('osimage', 'node1', 'node2');
    is_deeply($errors, [], 'mixed batch preprocesses');
    my ($legacy) = grep { $_->{node}[0] eq 'node1' && !$_->{_xcatdest} } @$requests;
    my ($responses, $commands, $tftp) = process_scoped($legacy);
    is_deeply($commands, [], 'legacy off-subnet node still does not run any stage');
    ok(!-e "$tftp/xcat/xnba/nodes/node1", 'mixed batch does not publish a legacy off-subnet script');
};

subtest 'pool prepares both servers with one shared epoch' => sub {
    fixture();
    delete $xCAT::Table::rows{noderes}{node1}{xcatmaster};
    my @coordinator;
    $pool_dispatch = sub {
        my $request = shift;
        push @coordinator, dclone($request);
        return {data => [JSON->new->encode({format => 'xcat-freebsd-pool-1', node => 'node1',
            operation => $request->{arg}[0], result => {epoch => 'd' x 32, phase => 'prepared'}})]};
    };
    my ($requests, $errors) = scope('osimage=freebsd', 'node1');
    is_deeply($errors, [], 'pool preprocessing succeeds');
    is(scalar(@coordinator), 1, 'one coordinator preparation covers both service nodes');
    is($coordinator[0]{arg}[0], 'prepare', 'preprocessing arms the coordinator');
    is_deeply([map { $_->{_xcatdest} } @$requests], ['192.0.2.2', '192.0.2.3'], 'each eligible server gets a scoped request');
    for my $request (@$requests) {
        my $wire = XML::Simple::XMLout($request, RootName => 'xcatrequest', NoAttr => 1);
        $request = XML::Simple::XMLin($wire, SuppressEmpty => undef, ForceArray => qr/.*/x);
        ok(ref($request->{_freebsd_pool}) eq 'ARRAY' && @{$request->{_freebsd_pool}} == 1
            && !ref($request->{_freebsd_pool}[0]), 'pool metadata survives XML as one scalar field') or next;
        my $metadata = JSON->new->decode($request->{_freebsd_pool}[0])->{node1};
        my $destination = $request->{_xcatdest}[0];
        is_deeply($metadata, {epoch => 'd' x 32, coordinator => '192.0.2.1', server => $destination},
            'metadata binds the shared epoch to the receiving server');
        $xCAT::NetworkUtils::local = $destination;
        is_deeply(xCAT::FreeBSDPool::local_preparation('node1', $request->{_freebsd_pool},
            {coordinator => '192.0.2.1', servers => ['192.0.2.2', '192.0.2.3']}), $metadata,
            'the production consumer accepts metadata after the daemon XML round trip');
        my ($responses, $commands) = process_scoped($request);
        is_deeply($responses, [], 'each owner can publish its local loader');
        my ($destiny) = grep { $_->{command}[0] eq 'setdestiny' } @$commands;
        is_deeply($destiny->{_freebsd_pool}, $request->{_freebsd_pool}, 'setdestiny receives unchanged pool metadata');
    }
};

subtest 'service-node startup refreshes only local FreeBSD entries without parallel dispatch' => sub {
    fixture();
    delete $xCAT::Table::rows{noderes}{node1}{xcatmaster};
    $xCAT::Table::rows{noderes}{node2}{xcatmaster} = 'sn2';
    $xCAT::Table::rows{nodetype}{$_}{os} = 'freebsd15.1' for qw(node1 node2);
    for my $local ('192.0.2.2', '192.0.2.1') {
        $xCAT::NetworkUtils::local = $local;
        $is_mn = 0;
        my (@errors, @operations);
        @xCAT::Scope::calls = ();
        my $requests = xCAT_plugin::xnba::preprocess_request(
            {command => ['nodeset'], arg => ['enact'], node => [qw(node1 node2)], inittime => [1]},
            sub { push @errors, @{ $_[0]{error} || [] }; }, sub {
                my $request = shift;
                push @operations, $request->{arg}[0];
                return {data => [JSON->new->encode({format => 'xcat-freebsd-pool-1', node => 'node1',
                    operation => $request->{arg}[0], result => {epoch => 'd' x 32, phase => 'prepared'}})]};
            });
        is_deeply(\@errors, [], 'startup scope succeeds');
        is_deeply(\@xCAT::Scope::calls, [], 'startup does not fork parallel or broadcast requests');
        if ($local eq '192.0.2.1') {
            is_deeply($requests, [], 'nonmember startup does not contact another installation owner');
            is_deeply(\@operations, [], 'nonmember startup does not query another pool');
            next;
        }
        is(scalar(@$requests), 1, 'only the local pool member is refreshed');
        is_deeply($requests->[0]{node}, ['node1'], 'remote explicit owner is excluded');
        ok(!exists($requests->[0]{_xcatdest}), 'startup work stays local');
        is_deeply(\@operations, ['inspect'], 'startup reuses the prepared epoch without rearming');
        my $metadata = eval { JSON->new->decode($requests->[0]{_freebsd_pool}[0]); };
        is($metadata && $metadata->{node1}{server}, $local, 'local preparation retains its server identity');
    }
};

subtest 'invalid owner in a mixed batch cannot rearm an earlier pool node' => sub {
    fixture();
    delete $xCAT::Table::rows{noderes}{node1}{xcatmaster};
    $xCAT::Table::rows{noderes}{node2}{xcatmaster} = 'sn1,sn2';
    my $operations = 0;
    $pool_dispatch = sub { ++$operations; return {}; };
    my ($requests, $errors) = scope('osimage=freebsd', 'node1', 'node2');
    is_deeply($requests, [], 'invalid batch creates no worker requests');
    ok(@$errors, 'invalid owner is reported');
    is($operations, 0, 'static validation precedes coordinator mutations');
};

subtest 'one coordinator error does not suppress other pools or Linux work' => sub {
    for my $startup (0, 1) {
        fixture();
        for my $node (qw(node1 node2)) {
            delete $xCAT::Table::rows{noderes}{$node}{xcatmaster};
            $xCAT::Table::rows{nodetype}{$node}{os} = 'freebsd15.1';
        }
        $xCAT::Table::rows{nodetype}{node3} = {os => 'rhels9', provmethod => 'linux'};
        $xCAT::NetworkUtils::local = '192.0.2.2' if $startup;
        $is_mn = !$startup;
        my (@errors, @operations);
        my $action = $startup ? 'enact' : 'osimage';
        my $request = {command => ['nodeset'], arg => [$action], node => [qw(node1 node2 node3)],
            $startup ? (inittime => [1]) : ()};
        my $legacy = xCAT_plugin::xnba::preprocess_request({%$request, node => ['node3']}, sub { die 'Legacy control failed'; });
        @xCAT::Scope::calls = ();
        my $requests = xCAT_plugin::xnba::preprocess_request($request,
            sub { push @errors, @{$_[0]{error} || []}; }, sub {
                my $operation = shift;
                push @operations, dclone($operation);
                return {error => ['Coordinator cannot prepare this node']} if $operation->{node}[0] eq 'node2';
                return {data => [JSON->new->encode({format => 'xcat-freebsd-pool-1', node => 'node1',
                    operation => $operation->{arg}[0], result => {epoch => 'd' x 32, phase => 'prepared'}})]};
            });
        like(join('', @errors), qr/node2:.*Coordinator/sx, 'failure identifies only the rejected pool node');
        is_deeply([map { $_->{node}[0] } @operations], [qw(node1 node2)], 'both coordinator operations were attempted');
        my @native = grep { $_->{_freebsd_owner} } @$requests;
        is(scalar(@native), $startup ? 1 : 2, 'the earlier prepared pool still receives its worker requests');
        is_deeply($_->{node}, ['node1'], 'failed pool node is excluded from each worker') for @native;
        is_deeply([grep { !$_->{_freebsd_owner} } @$requests], $legacy,
            'Linux requests retain their independently computed scope');
        ok(!grep($_->[0] eq 'parallel' || $_->[0] eq 'broadcast', @xCAT::Scope::calls),
            'startup remains local and serial') if $startup;
    }
    return;
};

subtest 'a rejected Linux scope preserves prepared pool and fixed-owner work' => sub {
    fixture();
    delete $xCAT::Table::rows{noderes}{node1}{xcatmaster};
    $xCAT::Table::rows{nodetype}{$_}{os} = 'freebsd15.1' for qw(node1 node2);
    $xCAT::Table::rows{nodetype}{$_} = {os => 'rhels9', provmethod => 'linux'} for qw(node3 sn3);
    no warnings 'redefine';
    local *xCAT::ServiceNodeUtils::getSNandCPnodes = sub {
        my (undef, $nodes, $servers, $computes) = @_;
        push @{$_ eq 'sn3' ? $servers : $computes}, $_ for @$nodes;
        return;
    };
    my ($legacy, $legacy_errors) = scope('osimage', qw(node3 sn3));
    ok(!$legacy, 'Linux-only mixed server and compute scope remains rejected');
    like(join('', @$legacy_errors), qr/both[ ]service[ ]nodes[ ]and[ ]compute[ ]nodes/x,
        'the legacy error identifies its invalid range');
    my @operations;
    $pool_dispatch = sub {
        my $request = shift;
        push @operations, dclone($request);
        return {data => [JSON->new->encode({format => 'xcat-freebsd-pool-1', node => 'node1',
            operation => $request->{arg}[0], result => {epoch => 'e' x 32, phase => 'prepared'}})]};
    };
    my ($requests, $errors) = scope('osimage', qw(node1 node2 node3 sn3));
    is_deeply($errors, $legacy_errors, 'mixed processing retains the Linux scope error');
    is_deeply([map { $_->{node}[0] } @operations], ['node1'], 'the pool epoch was prepared');
    my %destinations;
    for my $request (@$requests) {
        push @{$destinations{$_}}, $request->{_freebsd_owner}[0] for @{$request->{node}};
    }
    is_deeply(\%destinations, {node1 => ['192.0.2.2', '192.0.2.3'], node2 => ['192.0.2.2']},
        'both pool members and the fixed owner retain their worker requests');
    return;
};

subtest 'offline fences the pool before contacting either server' => sub {
    fixture();
    delete $xCAT::Table::rows{noderes}{node1}{xcatmaster};
    $xCAT::Table::rows{nodetype}{node1}{os} = 'freebsd15.1';
    my @operations;
    $pool_dispatch = sub {
        my $request = shift;
        push @operations, $request->{arg}[0];
        is_deeply(\@xCAT::Scope::calls, [], 'coordinator cancellation precedes worker dispatch');
        return {data => [JSON->new->encode({format => 'xcat-freebsd-pool-1', node => 'node1',
            operation => 'cancel', result => {phase => 'cancelled'}})]};
    };
    my ($requests, $errors) = scope('offline', 'node1');
    is_deeply($errors, [], 'offline cancellation is acknowledged');
    is_deeply(\@operations, ['cancel'], 'one cancellation covers all stale generations');
    is(scalar(@$requests), 2, 'offline publication is sent to both servers');
};

done_testing();
