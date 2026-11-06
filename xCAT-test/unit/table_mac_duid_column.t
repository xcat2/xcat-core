#!/usr/bin/env perl
#
# mac.duid names the DHCPv6 client identifier that a node's reservations match. It is a new
# column on an old table: a cluster that upgrades carries a mac table with no duid, and nothing
# recreates it.
#
# xcatd adds it. At startup it walks every table in the schema and calls updateschema, which
# compares the declared columns against the database and issues the ALTER. Table->new does NOT
# do this, so the column arrives when xcatd restarts and not when a plugin first opens the table.
use strict;
use warnings;
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Cwd qw(realpath);
use DBI;
use File::Temp qw(tempdir);
use Test::More tests => 9;

my $cfg = realpath( tempdir( CLEANUP => 1 ) );
$ENV{XCATCFG} = "SQLite:$cfg";

require xCAT::Schema;
require xCAT::Table;

# The schema is the contract makedhcp, chdef and lsdef read.
my $mac_cols = $xCAT::Schema::tabspec{mac}->{cols};
ok( scalar( grep { $_ eq 'duid' } @{$mac_cols} ),
    'the mac table declares a duid column' );

my ($duid_attr) =
  grep { ( $_->{tabentry} || '' ) eq 'mac.duid' }
  @{ $xCAT::Schema::defspec{node}->{attrs} };
ok( $duid_attr, 'a node attribute is mapped onto mac.duid, so chdef and lsdef reach it' );
is( $duid_attr->{attr_name}, 'duid',
    'and the attribute chdef and lsdef take is named duid' );

# The mac table of a cluster that predates the column: every other column, and no duid.
my @old_cols = grep { $_ ne 'duid' } @{$mac_cols};
my $dbfile = "$cfg/mac.sqlite";
{
    my $dbh = DBI->connect( "dbi:SQLite:dbname=$dbfile", '', '',
        { RaiseError => 1, PrintError => 0 } );
    $dbh->do( 'CREATE TABLE mac (' . join( ', ', map { "$_ TEXT" } @old_cols ) . ')' );
    $dbh->do( q{INSERT INTO mac (node, mac) VALUES ('node01', 'aa:bb:cc:dd:ee:ff')} );
    $dbh->disconnect;
}
ok( !column_present($dbfile, 'duid'), 'the old table starts without the column' );

# What xcatd runs at startup, for every table in the schema.
my $tab = xCAT::Table->new( 'mac', -create => 1 );
ok( $tab, 'the old mac table opens' );
$tab->updateschema();
ok( column_present($dbfile, 'duid'),
    'the schema update adds the duid column to a database that predates it' );

# Present is not the same as usable, and the row that was already there has to survive.
$tab->setAttribs( { node => 'node01' }, { duid => '00:04:0d:9e:4b:21' } );
my $row = $tab->getNodeAttribs( 'node01', [ 'mac', 'duid' ] );
is( $row->{duid}, '00:04:0d:9e:4b:21', 'a duid written to the upgraded table reads back' );
is( $row->{mac}, 'aa:bb:cc:dd:ee:ff',
    'and the MAC address the table already held is unchanged' );

# A second startup must not alter the table again, or every restart would rewrite it.
$tab->updateschema();
is( $tab->getNodeAttribs( 'node01', ['duid'] )->{duid}, '00:04:0d:9e:4b:21',
    'a second schema update leaves the duid alone' );

# column_present <dbfile> <column> -- read the columns from the database itself, not from the
# handle Table.pm holds, so the answer comes from what the ALTER did rather than from the schema.
sub column_present
{
    my ( $file, $column ) = @_;

    my $dbh = DBI->connect( "dbi:SQLite:dbname=$file", '', '',
        { RaiseError => 1, PrintError => 0 } );
    my $found = grep { $_->{name} eq $column } @{ $dbh->selectall_arrayref(
        'PRAGMA table_info(mac)', { Slice => {} } ) };
    $dbh->disconnect;
    return $found;
}
