#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Temp qw(tempdir);
use Storable qw(dclone);
use Test::More;

BEGIN {
    $INC{'xCAT/Table.pm'} = 1;
    $INC{'xCAT/TableUtils.pm'} = 1;
    $INC{'xCAT/Postage.pm'} = 1;
    $INC{'xCAT/MsgUtils.pm'} = 1;
    $INC{'xCAT_monitoring/monitorctrl.pm'} = 1;
}

my $utils = $ENV{XCAT_UTILS_FILE} || "$FindBin::Bin/../../perl-xCAT/xCAT/Utils.pm";
$INC{'xCAT/Utils.pm'} = $utils;
require $utils;

{
    package xCAT::Table;
    our (%rows, @writes);
    sub new {
        my ($class, $table, %options) = @_;
        return if exists($options{'-create'}) && !$options{'-create'} && !exists($rows{$table});
        $rows{$table} ||= {};
        return bless { table => $table }, $class;
    }
    sub getAttribs {
        my ($self, $key, @attributes) = @_;
        @attributes = @{ $attributes[0] } if ref($attributes[0]);
        my ($name) = values %$key;
        my $row = $rows{$self->{table}}{$name};
        return undef unless $row;
        return {map { $_ => $row->{$_} } grep { exists($row->{$_}) } @attributes};
    }
    sub getNodesAttribs {
        my ($self, $nodes, @attributes) = @_;
        return {map { $_ => [$self->getAttribs({node => $_}, @attributes) || {}] } @$nodes};
    }
    sub getNodeAttribs {
        my ($self, $node, @attributes) = @_;
        return $self->getAttribs({node => $node}, @attributes);
    }
    sub setNodesAttribs {
        my ($self, $nodes, $values) = @_;
        my $updates = ref($nodes) eq 'ARRAY' ? {map { $_ => $values } @$nodes} : ($nodes || {});
        push @writes, [$self->{table}, Storable::dclone($updates)];
        for my $node (keys %$updates) {
            $rows{$self->{table}}{$node} = {%{ $rows{$self->{table}}{$node} || {} }, %{ $updates->{$node} }};
        }
        return 0;
    }
    sub close { return; }
    package xCAT::TableUtils;
    our $installroot;
    sub get_site_attribute { return '192.0.2.1' if $_[1] eq 'master'; return; }
    sub getInstallDir { return $installroot; }
    package xCAT::Postage;
    our $calls = 0;
    sub create_mypostscript_or_not { ++$calls; return; }
    package xCAT::MsgUtils;
    sub trace { return; }
    sub report_node_error {
        my ($class, $callback, $node, $message) = @_;
        $callback->({node => [{name => [$node], error => [$message], errorcode => [1]}]});
    }
    package xCAT_monitoring::monitorctrl;
    sub getNodeStatusFromNodesetState { return 'installing'; }
    sub setNodeStatusAttributes { return; }
}

my $plugin = $ENV{XCAT_DESTINY_FILE} || "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/destiny.pm";
require $plugin;
my $temporary = tempdir(CLEANUP => 1);
$xCAT::TableUtils::installroot = $temporary;
my $image = {imagetype => 'freebsd', osname => 'FreeBSD', osvers => 'freebsd15.1',
    osarch => 'x86_64', provmethod => 'install', profile => 'compute'};

sub fixture {
    %xCAT::Table::rows = (
        osimage => {image1 => dclone($image)},
        nodetype => {map { $_ => {os => 'rhels9', arch => 'x86_64', profile => 'old', provmethod => 'image1'} } qw(node1 node2)},
        noderes => {map { $_ => {netboot => 'xnba', xcatmaster => '192.0.2.1'} } qw(node1 node2)},
        bootparams => {map { $_ => {kernel => 'old', addkcmdline => 'preserve-old'} } qw(node1 node2)},
        chain => {map { $_ => {currstate => 'boot', currchain => 'boot'} } qw(node1 node2)},
        mac => {map { $_ => {mac => '02:00:00:00:00:01'} } qw(node1 node2)},
    );
    @xCAT::Table::writes = ();
    $xCAT::Postage::calls = 0;
}

sub request {
    my ($action, @nodes) = @_;
    my (@responses, @commands, %boots);
    local $::XCATSITEVALS{disablecredfilecheck} = 1;
    eval { xCAT_plugin::destiny::process_request({command => ['setdestiny'], node => \@nodes,
        arg => [$action], bootparams => \%boots}, sub { push @responses, dclone($_[0]); }, sub {
        my ($req) = @_;
        push @commands, $req->{command}[0];
        if ($req->{command}[0] eq 'mkinstall') {
            my $params = ${ $req->{bootparams} };
            $params->{$_} = [{kernel => "xcat/freebsd/$_/boot/pxeboot", initrd => '', kcmdline => '', addkcmdline => ''}]
              for @{ $req->{node} };
        }
    }); 1; } or push @responses, {error => ["Unhandled plugin exception: $@"]};
    return (\@responses, \@commands, \%boots);
}

sub errors {
    my $responses = shift;
    my @errors;
    for my $response (@$responses) {
        push @errors, ref($response->{error}) ? @{ $response->{error} } : $response->{error} if $response->{error};
        push @errors, map { @{ $_->{error} || [] } } @{ $response->{node} || [] };
    }
    return join('\n', @errors);
}

is(xCAT::Utils->lookupNetboot('freebsd15.1', 'x86_64', 'freebsd'), 'xnba', 'FreeBSD uses only xNBA');
for my $unsupported (['freebsd15.0', 'x86_64'], ['freebsd16', 'x86_64'], ['freebsd15.1-extra', 'x86_64'], ['freebsd15.1', 'amd64'], ['freebsd15.1', 'aarch64']) {
    is(xCAT::Utils->lookupNetboot(@$unsupported, 'freebsd'), '', 'unsupported FreeBSD release or architecture has no route');
}
is(xCAT::Utils->lookupNetboot('rhels9', 'x86_64', 'Linux'), 'xnba,pxe,grub2', 'Linux lookup is unchanged');
is(xCAT::Utils->lookupNetboot('aix7', 'ppc64', 'NIM'), 'nimol', 'NIM lookup is unchanged');

for my $action ('osimage=image1', 'osimage', 'osimage:reboot4deploy') {
    subtest "$action supported FreeBSD installation" => sub {
        fixture();
        my ($responses, $commands, $boots) = request($action, 'node1', 'node2');
        is(errors($responses), '', 'supported request succeeds');
        is_deeply($commands, ['mkinstall'], 'actual destiny selects the install plugin command');
        is($xCAT::Table::rows{nodetype}{node1}{os}, 'freebsd15.1', 'node OS changes only after validation');
        like($xCAT::Table::rows{chain}{node1}{currstate}, qr/^install freebsd15\.1-x86_64-compute$/, 'chain records the FreeBSD installation');
        is($boots->{node1}[0]{kernel}, 'xcat/freebsd/node1/boot/pxeboot', 'installer bootparams return through destiny');
    };
    for my $invalid (
        ['osarch', 'aarch64'], ['osarch', 'amd64'], ['osarch', undef],
        ['osvers', 'freebsd16'], ['osvers', 'freebsd15.0'], ['osvers', 'freebsd15.1-extra'],
        ['imagetype', 'linux'], ['imagetype', undef],
        ['provmethod', 'netboot'], ['provmethod', 'statelite'], ['provmethod', 'sysclone'], ['provmethod', undef],
    ) {
        subtest "$action rejects invalid $invalid->[0] " . ($invalid->[1] || 'missing') => sub {
            fixture();
            $xCAT::Table::rows{osimage}{image1}{$invalid->[0]} = $invalid->[1];
            my $before = dclone(\%xCAT::Table::rows);
            my ($responses, $commands, $boots) = request($action, 'node1', 'node2');
            like(errors($responses), qr/FreeBSD/, 'unsupported FreeBSD configuration is an error');
            is_deeply(\%xCAT::Table::rows, $before, 'all database state is unchanged');
            is_deeply(\@xCAT::Table::writes, [], 'no state write occurs');
            is_deeply($boots, {}, 'boot arguments are not copied before validation');
            is_deeply($commands, [], 'no installer command is dispatched');
            is($xCAT::Postage::calls, 0, 'no postscript generation occurs');
        };
    }
    for my $netboot ('pxe', 'grub2', 'xnba,pxe', 'XNBA', 'xn', [], 'xnba ' ) {
        subtest "$action rejects explicit incompatible netboot" => sub {
            fixture();
            $xCAT::Table::rows{noderes}{node2}{netboot} = $netboot;
            my $before = dclone(\%xCAT::Table::rows);
            my ($responses, $commands, $boots) = request($action, 'node1', 'node2');
            like(errors($responses), qr/node2: FreeBSD requires noderes.netboot=xnba/, 'each node is checked, including the second node');
            is_deeply(\%xCAT::Table::rows, $before, 'mixed backend rejection is mutation-free');
            is_deeply($boots, {}, 'rejected backend leaves bootparams unchanged');
            is_deeply($commands, [], 'rejected backend dispatches no installer');
        };
    }
}

subtest 'per-node images validate before any image group changes state' => sub {
    fixture();
    $xCAT::Table::rows{osimage}{bad} = {%$image, provmethod => 'netboot'};
    $xCAT::Table::rows{nodetype}{node2}{provmethod} = 'bad';
    my $before = dclone(\%xCAT::Table::rows);
    my ($responses, $commands) = request('osimage', 'node1', 'node2');
    like(errors($responses), qr/node2: FreeBSD supports only provmethod=install/, 'second image group fails in preflight');
    is_deeply(\%xCAT::Table::rows, $before, 'earlier valid image group has not been written');
    is_deeply($commands, [], 'no image group is dispatched');
};

subtest 'unspecified netboot is not an explicit incompatibility' => sub {
    fixture();
    delete $xCAT::Table::rows{noderes}{node1}{netboot};
    my ($responses, $commands) = request('osimage=image1', 'node1');
    is(errors($responses), '', 'unspecified backend is accepted');
    is_deeply($commands, ['mkinstall'], 'normal install dispatch remains available');
};

subtest 'Linux explicit incompatible backend retains its warning behavior' => sub {
    fixture();
    $xCAT::Table::rows{osimage}{image1} = {%$image, imagetype => 'linux', osname => 'Linux', osvers => 'rhels9'};
    $xCAT::Table::rows{noderes}{node1}{netboot} = 'yaboot';
    my ($responses, $commands) = request('osimage=image1', 'node1');
    is(errors($responses), '', 'Linux compatibility warning is not promoted to an error');
    ok(grep($_->{warning}, @$responses), 'existing Linux warning is emitted');
    is_deeply($commands, ['mkinstall'], 'Linux still dispatches its existing installer');
};

for my $missing ('nodetype', 'noderes') {
    subtest "explicit Linux image tolerates absent $missing table" => sub {
        fixture();
        $xCAT::Table::rows{osimage}{image1} = {%$image, imagetype => 'linux', osname => 'Linux', osvers => 'rhels9'};
        delete $xCAT::Table::rows{$missing};
        my ($responses, $commands) = request('osimage=image1', 'node1');
        is(errors($responses), '', 'optional routing table does not add a FreeBSD error');
        is_deeply($commands, ['mkinstall'], 'Linux retains its existing installer dispatch');
        is($xCAT::Table::rows{nodetype}{node1}{os}, 'rhels9', 'Linux nodetype is updated normally');
        like($xCAT::Table::rows{chain}{node1}{currstate}, qr/^install rhels9-x86_64-compute$/, 'Linux chain is armed normally');
    };
}

subtest 'implicit Linux image tolerates absent optional resources' => sub {
    fixture();
    $xCAT::Table::rows{osimage}{image1} = {%$image, imagetype => 'linux', osname => 'Linux', osvers => 'rhels9'};
    delete $xCAT::Table::rows{noderes};
    my ($responses, $commands) = request('osimage', 'node1');
    is(errors($responses), '', 'implicit Linux routing retains the default resource behavior');
    ok(exists($xCAT::Table::rows{noderes}), 'legacy routing creates its optional resource table');
    ok(!grep($_->{errorabort}, @$responses), 'native preflight does not abort legacy routing');
};

subtest 'identified FreeBSD image requires resources before updating a mixed range' => sub {
    fixture();
    $xCAT::Table::rows{osimage}{linux} = {%$image, imagetype => 'linux', osname => 'Linux', osvers => 'rhels9'};
    $xCAT::Table::rows{nodetype}{node1}{provmethod} = 'linux';
    delete $xCAT::Table::rows{noderes};
    my $before = dclone(\%xCAT::Table::rows);
    my ($responses, $commands, $boots) = request('osimage', 'node1', 'node2');
    like(errors($responses), qr/(?:routing tables|FreeBSD.*noderes)/, 'missing FreeBSD resources is an explicit error');
    is_deeply(\%xCAT::Table::rows, $before, 'neither image group is updated before native validation');
    is_deeply($commands, [], 'mixed request dispatches no installer');
    is_deeply($boots, {}, 'mixed rejection copies no bootparams');
};

subtest 'invalid FreeBSD image rejects a mixed range before Linux state changes' => sub {
    fixture();
    $xCAT::Table::rows{osimage}{linux} = {%$image, imagetype => 'linux', osname => 'Linux', osvers => 'rhels9'};
    $xCAT::Table::rows{nodetype}{node1}{provmethod} = 'linux';
    $xCAT::Table::rows{osimage}{image1}{osarch} = 'aarch64';
    my $before = dclone(\%xCAT::Table::rows);
    my ($responses, $commands) = request('osimage', 'node1', 'node2');
    like(errors($responses), qr/node2: FreeBSD/, 'native image error names its node');
    is_deeply(\%xCAT::Table::rows, $before, 'mixed range remains unchanged');
    is_deeply($commands, [], 'no earlier Linux image group is dispatched');
};

done_testing();
