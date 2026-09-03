#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/lib/xcat";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $plugin = repo_path('xCAT-server/lib/xcat/plugins/confluent.pm');
plan skip_all => 'confluent.pm not found' unless -r $plugin;

# Every collaborator this plugin reaches for is stood in below: the tables, the
# transport, and the few helpers it calls. Stand the modules in as well, so the
# file needs neither DBI, which xCAT::Table loads, nor DB_File, which the
# transport loads and which the packaging makes optional because riscv64 on
# EL10 has no libdb. Nothing here touches a database or a socket.
BEGIN {
    $INC{$_} = 1 for qw(
        Confluent/Client.pm
        xCAT/Table.pm
        xCAT/Utils.pm
        xCAT/TableUtils.pm
        xCAT/PasswordUtils.pm
        xCAT/SvrUtils.pm
        xCAT/MsgUtils.pm
        xCAT/NetworkUtils.pm
    );
}
{ package Confluent::Client;   our $INSTANCE; sub new { return $INSTANCE } }
{ package xCAT::Table;         sub new { return } }
{ package xCAT::Utils;         sub Version { return 'unit-test' }
                               sub isServiceNode { return 0 } }
{ package xCAT::TableUtils;    sub get_site_Master { return 'mn' } }
{ package xCAT::PasswordUtils; sub getIPMIAuth { return {} } }
{ package xCAT::SvrUtils;      sub sendmsg { return } }
{ package xCAT::MsgUtils;      sub message { return } }
{ package xCAT::NetworkUtils;  sub determinehostname { return ('mn') } }

# With every collaborator stood in, a plugin that still will not load is a
# broken command rather than an unsupported environment, so fail loudly.
eval { require $plugin; 1 } or BAIL_OUT("confluent.pm did not load: $@");

# A table that answers the two calls the command makes of it. Rows are given
# per node exactly as xCAT::Table returns them, a list of hashes per node.
{
    package TestTable;
    sub new { my ($class, %rows) = @_; return bless { rows => {%rows} }, $class }
    # A table that answers any node with the same row, for the columns the
    # command reads but this file is not exercising.
    sub new_uniform { my ($class, $row) = @_; return bless { rows => {}, any => $row }, $class }
    # xCAT::Table returns only the attributes the caller asked for. Project the
    # fixture the same way, so a command that stops asking for a column loses
    # it here too instead of being handed it anyway.
    sub _project {
        my ($row, $attrs, %extra) = @_;
        my %out = %extra;
        foreach my $a (@{ $attrs || [] }) {
            $out{$a} = $row->{$a} if exists $row->{$a};
        }
        return \%out;
    }
    sub getNodesAttribs {
        my ($self, $nodes, $attrs) = @_;
        my %out;
        foreach my $n (@{ $nodes || [] }) {
            my $rows = exists $self->{rows}{$n} ? $self->{rows}{$n}
                     : $self->{any}             ? [ $self->{any} ]
                     :                            [ undef ];
            $out{$n} = [ map { defined($_) ? _project($_, $attrs) : undef } @$rows ];
        }
        return \%out;
    }
    sub getAllNodeAttribs {
        my ($self, $attrs) = @_;
        my @flat;
        foreach my $n (sort keys %{ $self->{rows} }) {
            foreach my $r (@{ $self->{rows}{$n} }) {
                push @flat, _project($r, $attrs, node => $n);
            }
        }
        return @flat;
    }
    sub close { return }
}

# A confluent client that records what the command sends it.
{
    package TestConfluent;
    sub new { my ($class, @existing) = @_;
        return bless { existing => [@existing], queue => [], sent => [] }, $class }
    sub read {
        my ($self, $path) = @_;
        $self->{queue} = [];
        if ($path eq '/nodes/') {
            push @{ $self->{queue} }, { item => { href => "$_/" } } for @{ $self->{existing} };
        }
        return;
    }
    sub next_result { my ($self) = @_; return shift @{ $self->{queue} } }
    sub create { my ($self, $path, %a) = @_;
        push @{ $self->{sent} }, { op => 'create', path => $path, parameters => $a{parameters} };
        return }
    sub update { my ($self, $path, %a) = @_;
        push @{ $self->{sent} }, { op => 'update', path => $path, parameters => $a{parameters} };
        return }
    sub delete { my ($self, $path) = @_;
        push @{ $self->{sent} }, { op => 'delete', path => $path }; return }
    sub sent_for {
        my ($self, $node) = @_;
        foreach my $s (@{ $self->{sent} }) {
            next unless defined $s->{parameters};
            my $name = $s->{parameters}{name};
            return $s if defined($name) && $name eq $node;
            return $s if defined($s->{path}) && $s->{path} =~ m{/nodes/\Q$node\E/};
        }
        return;
    }
}

# Run plugin code with table, host, and message collaborators at the boundary.
sub with_tables {
    my ($tables, $code) = @_;
    no warnings qw(redefine once);
    my $empty    = TestTable->new();
    my $nodelist = TestTable->new_uniform({ groups => 'all' });
    local *xCAT::Table::new = sub {
        my ($class, $name, @rest) = @_;
        return $tables->{$name} if exists $tables->{$name};
        return $nodelist if $name eq 'nodelist';
        return $empty;
    };
    return $code->();
}

# Drive the real command. %tables maps a table name to its rows; @existing are
# the nodes confluent already holds, which selects create versus update.
sub run_command {
    my (%opt) = @_;
    my $client = TestConfluent->new(@{ $opt{existing} || [] });
    my %tables = %{ $opt{tables} || {} };

    no warnings qw(once);
    local $Confluent::Client::INSTANCE = $client;
    with_tables(\%tables, sub {
        my $req = { command => ['makeconfluentcfg'], arg => [] };
        $req->{node} = $opt{nodes} if $opt{nodes};
        xCAT_plugin::confluent::makeconfluentcfg($req, sub { return });
    });
    return $client;
}

sub run_preprocess {
    my (%opt) = @_;
    my %tables = %{ $opt{tables} || {} };

    no warnings qw(once);
    local $::CONSERVER;
    local $::LOCAL;
    local $::HELP;
    local $::VERSION;
    local $::VERBOSE;
    local $::DEBUG;
    return with_tables(\%tables, sub {
        my $args = $opt{confluent_only} ? ['-c'] : [];
        my $req = {
            command           => ['makeconfluentcfg'],
            arg               => $args,
            _xcatpreprocessed => [0],
        };
        $req->{node} = $opt{nodes} if exists $opt{nodes};
        return xCAT_plugin::confluent::preprocess_request($req, sub { return });
    });
}

sub params_for {
    my ($client, $node) = @_;
    my $s = $client->sent_for($node);
    return (undef, undef) unless $s;
    return ($s->{parameters}, $s->{op});
}

# Explicit nodes remain in the request even without console attributes or a
# nodehm row, and conserver routing still uses the configured destination.
{
    my $nodehm = TestTable->new(
        withcons   => [ { node => 'withcons', cons => 'ipmi' } ],
        nocons     => [ { node => 'nocons' } ],
        withserver => [ { node => 'withserver', cons => 'ipmi', conserver => 'sn1' } ],
    );
    my $requests = run_preprocess(
        nodes  => [ 'withcons', 'nocons', 'neverdefined', 'withserver' ],
        tables => { nodehm => $nodehm },
    );
    my ($management) = grep { $_->{_xcatdest} eq 'mn' } @{$requests};
    my ($conserver)  = grep { $_->{_xcatdest} eq 'sn1' } @{$requests};
    is_deeply(
        [ sort @{ $management->{node} } ],
        [qw(neverdefined nocons withcons withserver)],
        'an explicit noderange keeps console and console-less nodes',
    );
    is_deeply($conserver->{node}, ['withserver'],
        'a node keeps its explicit conserver');
}

# A full-scan preprocess request keeps the legacy dispatch filter: only nodes
# with a console method or a serial port are assigned to a destination.
{
    my $nodehm = TestTable->new(
        withcons   => [ { cons => 'ipmi' } ],
        withserial => [ { serialport => 0 } ],
        nocons     => [ {} ],
        withserver => [ { cons => 'ipmi', conserver => 'sn1' } ],
    );
    my $requests = run_preprocess(
        confluent_only => 1,
        tables         => { nodehm => $nodehm },
    );
    my %nodes_by_destination = map {
        $_->{_xcatdest} => [ sort @{ $_->{node} } ]
    } @{$requests};
    is_deeply($nodes_by_destination{mn}, [qw(withcons withserial)],
        'full-scan dispatch excludes a console-less node');
    is_deeply($nodes_by_destination{sn1}, ['withserver'],
        'full-scan dispatch keeps explicit conserver routing');
}

# The second nodehm lookup must carry the requested name even when no row is
# defined, so the create request never receives an empty node name.
{
    my $client = run_command(
        nodes  => ['neverdefined'],
        tables => { nodehm => TestTable->new() },
    );
    my ($p) = params_for($client, 'neverdefined');
    ok(defined($p), 'a named node with no nodehm row reaches confluent');
    is($p->{name}, 'neverdefined', 'the create request carries the requested node name');
}

# A node cabled on two interfaces. Both must survive: keeping only one loses
# the port of the other, which is what this export exists to carry.
{
    my $client = run_command(
        nodes  => ['n1'],
        tables => {
            nodehm => TestTable->new(n1 => [ { node => 'n1', cons => 'ipmi' } ]),
            switch => TestTable->new(n1 => [
                { switch => 'sw1', port => '1', interface => 'eth0' },
                { switch => 'sw2', port => '9', interface => 'ib0' },
            ]),
        },
    );
    my ($p) = params_for($client, 'n1');
    ok(defined($p), 'a node with switch rows is sent to confluent');
    is($p->{'net.eth0.switch'},     'sw1', 'the first interface carries its switch');
    is($p->{'net.eth0.switchport'}, '1',   'the first interface carries its port');
    is($p->{'net.ib0.switch'},      'sw2', 'the second interface carries its switch');
    is($p->{'net.ib0.switchport'},  '9',   'the second interface carries its port');
}

# A row that names no interface carries the plain names.
{
    my $client = run_command(
        nodes  => ['n2'],
        tables => {
            nodehm => TestTable->new(n2 => [ { node => 'n2', cons => 'ipmi' } ]),
            switch => TestTable->new(n2 => [ { switch => 'sw3', port => '4' } ]),
        },
    );
    my ($p) = params_for($client, 'n2');
    is($p->{'net.switch'},     'sw3', 'a row with no interface carries the plain switch');
    is($p->{'net.switchport'}, '4',   'a row with no interface carries the plain port');
}

# A node known only through the switch table still reaches confluent.
{
    my $client = run_command(
        nodes  => ['n3'],
        tables => {
            switch => TestTable->new(n3 => [ { switch => 'sw4', port => '7', interface => 'eth1' } ]),
        },
    );
    my ($p) = params_for($client, 'n3');
    ok(defined($p), 'a node known only by its interfaces is still exported');
    is($p->{'net.eth1.switch'}, 'sw4', 'its interface topology is carried');
}

# An empty switch table must leave the configuration untouched.
{
    my $client = run_command(
        nodes  => ['n4'],
        tables => {
            nodehm => TestTable->new(n4 => [ { node => 'n4', cons => 'ipmi' } ]),
            switch => TestTable->new(),
        },
    );
    my ($p) = params_for($client, 'n4');
    ok(defined($p), 'a node with no switch row is still configured');
    is($p->{'net.switch'},     undef, 'no plain switch is carried');
    is($p->{'net.eth0.switch'}, undef, 'no interface switch is carried');
}

# Retraction. For a node confluent already holds, the request must name the
# topology that xCAT no longer holds so that confluent removes it.
{
    my $client = run_command(
        nodes    => ['n5'],
        existing => ['n5'],
        tables   => {
            nodehm => TestTable->new(n5 => [ { node => 'n5', cons => 'ipmi' } ]),
            switch => TestTable->new(),
        },
    );
    my ($p, $op) = params_for($client, 'n5');
    is($op, 'update', 'a node confluent holds is updated');
    ok(exists $p->{'net.switch'},       'the plain switch is named');
    is($p->{'net.switch'},     undef,   'the plain switch carries no value');
    ok(exists $p->{'net.switchport'},   'the plain port is named');
    is($p->{'net.switchport'}, undef,   'the plain port carries no value');
    ok(exists $p->{'net.*.switch'},     'every interface switch is named');
    is($p->{'net.*.switch'},     undef, 'every interface switch carries no value');
    ok(exists $p->{'net.*.switchport'}, 'every interface port is named');
    is($p->{'net.*.switchport'}, undef, 'every interface port carries no value');

    # Those clears are undefined values in a Perl hash. Only a JSON null asks
    # confluent to remove an attribute, so put the payload the command actually
    # produced through the real transport and read the bytes.
    # Those clears are undefined values in a Perl hash. Only a JSON null asks
    # confluent to remove an attribute, so put the payload the command actually
    # produced through the real transport and read the bytes. Confluent::TLV is
    # in the checkout and JSON is a hard dependency of the server package, so a
    # failure to load either is a broken transport, not an absent environment.
    my $tlvpm = repo_path('xCAT-server/lib/xcat/Confluent/TLV.pm');
    require $tlvpm;
    require JSON;

    my $wire = '';
    open(my $sink, '>', \$wire) or die "in-memory handle: $!";
    Confluent::TLV->new($sink)->send({ operation => 'update', parameters => $p });
    close($sink);

    ok(length($wire) > 4, 'the transport wrote a framed payload');
    my $json = substr($wire, 4);
    like($json, qr/"net\.switch"\s*:\s*null/,
        'the plain switch reaches the wire as a null, which is what removes it');
    like($json, qr/"net\.\*\.switch"\s*:\s*null/,
        'the interface wildcard reaches the wire as a null');
}

# A held value is never replaced by a clear.
{
    my $client = run_command(
        nodes    => ['n6'],
        existing => ['n6'],
        tables   => {
            nodehm => TestTable->new(n6 => [ { node => 'n6', cons => 'ipmi' } ]),
            switch => TestTable->new(n6 => [
                { switch => 'sw5', port => '2' },
                { switch => 'sw6', port => '8', interface => 'ib1' },
            ]),
        },
    );
    my ($p) = params_for($client, 'n6');
    is($p->{'net.switch'},      'sw5', 'a held plain switch keeps its value');
    is($p->{'net.switchport'},  '2',   'a held plain port keeps its value');
    is($p->{'net.ib1.switch'},  'sw6', 'a held interface switch keeps its value');
    ok(exists $p->{'net.*.switch'}, 'the interface wildcard is still named');
    is($p->{'net.*.switch'}, undef, 'the interface wildcard still clears');
}

# The request that creates a node has nothing to remove.
{
    my $client = run_command(
        nodes  => ['n7'],
        tables => {
            nodehm => TestTable->new(n7 => [ { node => 'n7', cons => 'ipmi' } ]),
            switch => TestTable->new(n7 => [ { switch => 'sw7', port => '3' } ]),
        },
    );
    my ($p, $op) = params_for($client, 'n7');
    is($op, 'create', 'a node confluent does not hold is created');
    ok(!exists $p->{'net.*.switch'}, 'the request that creates a node sends no clear');
    is($p->{'net.switch'}, 'sw7', 'it still carries the topology xCAT holds');
}

# With no node range the command reads every table in full. The enclosure of a
# node comes from the mp table; nodepos does not have those columns.
{
    my $client = run_command(
        tables => {
            nodehm  => TestTable->new(n8 => [ { cons => 'ipmi' } ]),
            nodepos => TestTable->new(n8 => [ { rack => 'r1', u => '12' } ]),
            mp      => TestTable->new(n8 => [ { mpa => 'chassis1', id => '5' } ]),
            switch  => TestTable->new(n8 => [ { switch => 'sw8', port => '6', interface => 'eth2' } ]),
        },
    );
    my ($p) = params_for($client, 'n8');
    ok(defined($p), 'a full scan sends the node');
    is($p->{'enclosure.manager'}, 'chassis1', 'the enclosure manager comes from the mp table');
    is($p->{'enclosure.bay'},     '5',        'the enclosure bay comes from the mp table');
    is($p->{'location.rack'},     'r1',       'the rack still comes from nodepos');
    is($p->{'net.eth2.switch'},   'sw8',      'a full scan carries the switch topology');
}

# The noderange path reshapes nodepos and mp lookups before preparing the
# confluent request. Exercise both tables through that path.
{
    my $client = run_command(
        nodes  => ['n9'],
        tables => {
            nodehm  => TestTable->new(n9 => [ { node => 'n9', cons => 'ipmi' } ]),
            nodepos => TestTable->new(n9 => [
                { node => 'n9', rack => 'r2', u => '21', room => 'west' },
            ]),
            mp => TestTable->new(n9 => [
                { node => 'n9', mpa => 'chassis2', id => '6' },
            ]),
        },
    );
    my ($p) = params_for($client, 'n9');
    ok(defined($p), 'an explicit node with location rows is sent to confluent');
    is($p->{'location.rack'},     'r2',       'the nodepos row supplies the rack');
    is($p->{'location.u'},        '21',       'the nodepos row supplies the rack unit');
    is($p->{'location.room'},     'west',     'the nodepos row supplies the room');
    is($p->{'enclosure.manager'}, 'chassis2', 'the mp row supplies the enclosure manager');
    is($p->{'enclosure.bay'},     '6',        'the mp row supplies the enclosure bay');
}

done_testing();
