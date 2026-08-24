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
    my ($source) = @_;
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
        ],
    };

    no warnings 'redefine';
    local *xCAT::DBobjUtils::getobjdefs = sub {
        my ($class, $objects) = @_;

        return (node01 => { selector => 'axb' })
          if $source eq 'database' && exists $objects->{node01};
        return (literalgroup => { selector => 'axb' })
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
    $attrs{selector} = 'axb'          if $source eq 'explicit';
    $attrs{groups}   = 'literalgroup' if $source eq 'group';

    my %objects = (node01 => \%attrs);
    my $rc = xCAT::DBobjUtils->setobjdefs(\%objects);

    is($rc, 0, "$source source passes only_if validation");
    my @payload_tables = sort map { $_->{table} }
      grep { exists $_->{updates}{payload} } @writes;
    is_deeply(
        \@payload_tables,
        ['route_expected'],
        "$source source routes through only the literal-matching only_if entry",
    );
}

check_literal_only_if_routing($_) for qw(explicit database group);

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
