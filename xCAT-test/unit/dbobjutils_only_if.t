#!/usr/bin/env perl
use strict;
use warnings;

BEGIN {
    $ENV{XCATCFG} ||= 'SQLite:/tmp';
}

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Scalar::Util qw(refaddr);
use Test::More;

use xCAT::DBobjUtils;

my %missing_mgt = (
    objtype => 'node',
    groups  => 'test',
    bmc     => '10.0.0.1',
);
my @failures = xCAT::DBobjUtils->validate_only_if_attrs('node01', 'node', \%missing_mgt, {});
is(scalar @failures, 1, 'bmc without mgt fails only_if validation');
like($failures[0]->{message}, qr/mgt value is .*openbmc/, 'failure explains accepted mgt values');

my %substring_openbmc = (
    objtype => 'node',
    groups  => 'test',
    mgt     => 'openbmc-redfish',
    bmc     => '10.0.0.1',
);
@failures = xCAT::DBobjUtils->validate_only_if_attrs('node01', 'node', \%substring_openbmc, {});
is(scalar @failures, 1, 'substring-only mgt value fails bmc only_if validation');
like($failures[0]->{message}, qr/mgt value is .*openbmc/, 'substring rejection explains accepted mgt values');

my %explicit_openbmc = (
    objtype => 'node',
    groups  => 'test',
    mgt     => 'openbmc',
    bmc     => '10.0.0.1',
);
@failures = xCAT::DBobjUtils->validate_only_if_attrs('node01', 'node', \%explicit_openbmc, {});
is(scalar @failures, 0, 'explicit mgt=openbmc satisfies bmc only_if validation');

my %existing_openbmc = (
    objtype => 'node',
    groups  => 'test',
    bmc     => '10.0.0.1',
);
my %dbattrs = (mgt => 'openbmc');
@failures = xCAT::DBobjUtils->validate_only_if_attrs('node01', 'node', \%existing_openbmc, \%dbattrs);
is(scalar @failures, 0, 'existing mgt=openbmc satisfies bmc only_if validation');

my %group_openbmc = (
    objtype => 'node',
    groups  => 'openbmcgrp',
    bmc     => '10.0.0.1',
);
my %groupattrs = (openbmcgrp => { mgt => 'openbmc' });
@failures = xCAT::DBobjUtils->validate_only_if_attrs('node01', 'node', \%group_openbmc, {}, \%groupattrs);
is(scalar @failures, 0, 'group mgt=openbmc satisfies bmc only_if validation');

sub check_exact_only_if_value {
    my ($source, $actual, $required, $matches, $description) = @_;
    my (%attrs, %dbattrs, %groupattrs);

    $attrs{selector} = $actual if $source eq 'explicit';
    $dbattrs{selector} = $actual if $source eq 'database';
    $groupattrs{exactgroup}{selector} = $actual if $source eq 'group';

    is(
        xCAT::DBobjUtils::_only_if_value_matches(
            \%attrs,
            \%dbattrs,
            \%groupattrs,
            'selector',
            $required,
        ),
        $matches,
        "$source source $description",
    );
}

my @exact_match_cases = (
    ['pdu',                 'pdu', 1, 'matches a single value'],
    ['openbmc,pdu',         'pdu', 1, 'matches an exact list element'],
    [' openbmc , pdu ',     'pdu', 1, 'matches a whitespace-padded list element'],
    [0,                     '0',   1, 'matches a defined zero'],
    ['not-pdu',             'pdu', 0, 'rejects a hyphenated prefix'],
    ['pdu-extra',           'pdu', 0, 'rejects a hyphenated suffix'],
    ['pdu.extra',           'pdu', 0, 'rejects a dotted suffix'],
    ['.pdu',                'pdu', 0, 'rejects a punctuated prefix'],
    ['pdu.',                'pdu', 0, 'rejects a punctuated suffix'],
    ['.pdu',                '.pdu', 1, 'matches a leading-punctuation value exactly'],
    ['pdu.',                'pdu.', 1, 'matches a trailing-punctuation value exactly'],
    ['',                    'pdu', 0, 'rejects an empty value'],
    [undef,                 'pdu', 0, 'rejects an undefined value'],
);

foreach my $source (qw(explicit database group)) {
    check_exact_only_if_value($source, @$_) for @exact_match_cases;
}

is(
    xCAT::DBobjUtils::_only_if_value_matches(
        { selector => 'not-pdu' },
        { selector => 'pdu.extra' },
        { exactgroup => { selector => ' openbmc , pdu ' } },
        'selector',
        'pdu',
    ),
    1,
    'later exact source match preserves source OR semantics',
);

sub check_literal_only_if_read {
    my ($selector, $expected_payload, $description) = @_;

    local $xCAT::Schema::defspec{node} = {
        objkey => 'name',
        attrs  => [
            {
                attr_name       => 'selector',
                tabentry        => 'route_source.selector',
                access_tabentry => 'route_source.node=attr:name',
            },
            {
                attr_name       => 'payload',
                only_if         => 'selector=axb',
                tabentry        => 'route_expected.payload',
                access_tabentry => 'route_expected.node=attr:name',
            },
            {
                attr_name       => 'payload',
                only_if         => 'selector=a.b',
                tabentry        => 'route_wrong.payload',
                access_tabentry => 'route_wrong.node=attr:name',
            },
            {
                attr_name       => 'payload',
                only_if         => 'selector=not-pdu',
                tabentry        => 'route_not_pdu.payload',
                access_tabentry => 'route_not_pdu.node=attr:name',
            },
            {
                attr_name       => 'payload',
                only_if         => 'selector=pdu.extra',
                tabentry        => 'route_pdu_extra.payload',
                access_tabentry => 'route_pdu_extra.node=attr:name',
            },
            {
                attr_name       => 'payload',
                only_if         => 'selector=pdu',
                tabentry        => 'route_pdu.payload',
                access_tabentry => 'route_pdu.node=attr:name',
            },
        ],
    };

    my @tables = qw(
      route_source route_expected route_wrong route_not_pdu
      route_pdu_extra route_pdu
    );
    local @xCAT::Schema::tabspec{@tables};
    @xCAT::Schema::tabspec{@tables} = map { { nodecol => 'node' } } @tables;

    no warnings 'redefine';
    local *xCAT::DBobjUtils::getobjattrs = sub {
        return (
            route_source => { node01 => { selector => $selector } },
            route_expected => { node01 => { payload => 'literal axb' } },
            route_wrong => { node01 => { payload => 'literal a.b' } },
            route_not_pdu => { node01 => { payload => 'literal not-pdu' } },
            route_pdu_extra => { node01 => { payload => 'literal pdu.extra' } },
            route_pdu => { node01 => { payload => 'literal pdu' } },
        );
    };

    local $::ATTRLIST = '';
    my %objects = (node01 => 'node');
    my %defs = xCAT::DBobjUtils->getobjdefs(
        \%objects,
        0,
        ['selector', 'payload'],
    );

    is($defs{node01}{payload}, $expected_payload, $description);
}

check_literal_only_if_read('axb',       'literal axb',       'read routing treats regex punctuation literally');
check_literal_only_if_read('not-pdu',   'literal not-pdu',   'read routing rejects a hyphenated substring match');
check_literal_only_if_read('pdu.extra', 'literal pdu.extra', 'read routing rejects a dotted substring match');
check_literal_only_if_read('other,pdu', 'literal pdu',       'read routing accepts an exact comma-list element');

{
    package DBobjUtilsOnlyIf::TableRecorder;

    sub setAttribs {
        my ($self, $keys, $updates) = @_;
        push @{ $self->{writes} }, {
            table   => $self->{table},
            keys    => { %$keys },
            updates => { %$updates },
        };
        return (1, undef);
    }

    sub commit { return 1; }
}

sub check_literal_only_if_routing {
    my ($source, $selector, $expected_table, $description) = @_;
    my @writes;

    local $xCAT::Schema::defspec{routing_fixture} = {
        objkey  => 'name',
        attrhash => {},
        attrs   => [
            {
                attr_name       => 'groups',
                tabentry        => 'route_source.groups',
                access_tabentry => 'route_source.node=attr:name',
            },
            {
                attr_name       => 'selector',
                tabentry        => 'route_source.selector',
                access_tabentry => 'route_source.node=attr:name',
            },
            {
                attr_name       => 'payload',
                only_if         => 'selector=a.b',
                tabentry        => 'route_wrong.payload',
                access_tabentry => 'route_wrong.node=attr:name',
            },
            {
                attr_name       => 'payload',
                only_if         => 'selector=axb',
                tabentry        => 'route_expected.payload',
                access_tabentry => 'route_expected.node=attr:name',
            },
            {
                attr_name       => 'payload',
                only_if         => 'selector=pdu',
                tabentry        => 'route_pdu.payload',
                access_tabentry => 'route_pdu.node=attr:name',
            },
            {
                attr_name       => 'payload',
                only_if         => 'selector=not-pdu',
                tabentry        => 'route_not_pdu.payload',
                access_tabentry => 'route_not_pdu.node=attr:name',
            },
            {
                attr_name       => 'payload',
                only_if         => 'selector=pdu.extra',
                tabentry        => 'route_pdu_extra.payload',
                access_tabentry => 'route_pdu_extra.node=attr:name',
            },
        ],
    };

    no warnings 'redefine';
    local *xCAT::DBobjUtils::getobjdefs = sub {
        my ($class, $objects) = @_;

        return (node01 => { selector => $selector })
          if $source eq 'database' && exists $objects->{node01};
        return (literalgroup => { selector => $selector })
          if $source eq 'group' && exists $objects->{literalgroup};
        return ();
    };
    local *xCAT::Table::getTableSchema = sub {
        return { keys => ['node'] };
    };
    local *xCAT::Table::new = sub {
        my ($class, $table) = @_;
        return bless {
            table  => $table,
            writes => \@writes,
        }, 'DBobjUtilsOnlyIf::TableRecorder';
    };

    my %attrs = (
        objtype => 'routing_fixture',
        payload => 'stored',
    );
    $attrs{selector} = $selector      if $source eq 'explicit';
    $attrs{groups}   = 'literalgroup' if $source eq 'group';

    my %objects = (node01 => \%attrs);
    my $rc = xCAT::DBobjUtils->setobjdefs(\%objects);

    is($rc, 0, "$source source $description passes only_if validation");
    my @payload_tables = sort map { $_->{table} }
      grep { exists $_->{updates}{payload} } @writes;
    is_deeply(
        \@payload_tables,
        [$expected_table],
        "$source source $description routes through only the exact only_if entry",
    );
}

foreach my $source (qw(explicit database group)) {
    check_literal_only_if_routing($source, 'axb',       'route_expected',  'literal value');
    check_literal_only_if_routing($source, 'not-pdu',   'route_not_pdu',   'hyphenated value');
    check_literal_only_if_routing($source, 'pdu.extra', 'route_pdu_extra', 'dotted value');
    check_literal_only_if_routing($source, 'other,pdu', 'route_pdu',       'comma-list value');
}

my %external_entries;
foreach my $type (keys %xCAT::ExtTab::ext_defspec) {
    foreach my $entry (@{ $xCAT::ExtTab::ext_defspec{$type}{attrs} || [] }) {
        $external_entries{refaddr($entry)} = 1;
    }
}

my @inconsistent_only_if;
my @falsey_only_if;
my $checked_only_if = 0;
foreach my $type (sort keys %xCAT::Schema::defspec) {
    foreach my $entry (@{ $xCAT::Schema::defspec{$type}{attrs} || [] }) {
        next if $external_entries{refaddr($entry)};
        next unless exists($entry->{only_if});
        my $condition = $entry->{only_if};
        $checked_only_if++;
        if ($condition !~ /^([^!=]+)=(.+)$/) {
            push @inconsistent_only_if, "$type.$entry->{attr_name}:$condition";
            next;
        }
        my ($validator_key, $validator_value) = ($1, $2);
        my ($router_key, $router_value) = split(/=/, $condition);
        if ($validator_key ne $router_key || $validator_value ne $router_value) {
            push @inconsistent_only_if, "$type.$entry->{attr_name}:$condition";
            next;
        }
        push @falsey_only_if, "$type.$entry->{attr_name}:$condition" unless $validator_value;
    }
}

cmp_ok($checked_only_if, '>', 0, 'core only_if schema conditions are examined');
is_deeply(\@inconsistent_only_if, [], 'validator and router parse core only_if conditions consistently');
is_deeply(\@falsey_only_if, [], 'core only_if schema values are truthy for routing');

done_testing();
