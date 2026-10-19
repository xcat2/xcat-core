#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;

my $fixture = tempdir(CLEANUP => 1);
make_path("$fixture/db");
local $ENV{XCATCFG} = "SQLite:$fixture/db";
require xCAT::Table;
require xCAT::TableUtils;

for my $table (qw(nodehm noderes)) {
    xCAT::Table->new($table, -create => 1)->setAttribs({ node => $_ }, { comments => "row of $_" }) for qw(n1 n2 n3);
}

sub nodes {
    my ($table) = @_;
    return join(',', sort map { $_->{node} } xCAT::Table->new($table)->getAllAttribs('node'));
}

sub delete_rows {
    my @args = @_;
    my $missing = eval { xCAT::TableUtils->delete_rows(@args) };
    return ($missing, $@);
}

my ($missing, $error) = delete_rows({ node => 'n1' }, 'nodehm', 'noderes');
is($error,   '',    'rows are deleted from tables that open');
is($missing, undef, 'no table is reported when every table opens');
is(nodes('nodehm'),  'n2,n3', 'the row of the key is deleted from the first table');
is(nodes('noderes'), 'n2,n3', 'the row of the key is deleted from the last table');

for my $case ([ 'between two tables', 'nodehm', 'notatable', 'noderes' ], [ 'first', 'notatable', 'nodehm', 'noderes' ],
    [ 'last', 'nodehm', 'noderes', 'notatable' ]) {
    my ($label, @tables) = @$case;
    ($missing, $error) = delete_rows({ node => 'n2' }, @tables);
    is($error,   '',          "a missing table named $label does not die");
    is($missing, 'notatable', "a missing table named $label is returned");
    is(nodes('nodehm'),  'n2,n3', "nodehm keeps its rows when a missing table is named $label");
    is(nodes('noderes'), 'n2,n3', "noderes keeps its rows when a missing table is named $label");
}

done_testing();
