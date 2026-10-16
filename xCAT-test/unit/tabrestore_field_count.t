#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

my $fixture = tempdir(CLEANUP => 1);
make_path("$fixture/db");
local $ENV{XCATCFG} = "SQLite:$fixture/db";
require xCAT::Table;
require(repo_path('xCAT-server/lib/xcat/plugins/tabutils.pm'));

# Restores the rows into the site table, which has 4 columns, over a row that was there before.
sub restore {
    my @rows = @_;
    my $site = xCAT::Table->new('site', -create => 1);
    $site->delEntries();
    $site->setAttribs({ key => 'before' }, { value => 'kept' });
    my @errors;
    xCAT_plugin::tabutils::process_request({ command => ['tabrestore'], table => ['site'], data => [ '#key,value,comments,disable', @rows ] },
        sub { push @errors, map { ref($_) ? @$_ : $_ } grep { defined } $_[0]{error} });
    my %rows = map { ($_->{key} => join('|', map { $_ // '' } @{$_}{qw(value comments)})) } xCAT::Table->new('site')->getAllAttribs('key', 'value', 'comments');
    return (join("\n", @errors), \%rows);
}

for my $case (
    [ 'one field for each column',          '"k1","v1",,' ],
    [ 'fewer fields than columns',          '"k1","v1"' ],
    [ 'a quoted field that holds a comma',  '"k1","v1","a,b",', 'v1|a,b' ],
    [ 'a quoted comment before the last field', '"k1","v1","note",', 'v1|note' ])
{
    my ($label, $row, $want) = @$case;
    my ($errors, $rows) = restore($row);
    is($errors, '', "$label: the row is restored without an error");
    is_deeply($rows, { k1 => $want // 'v1|' }, "$label: the restore replaces the table with the row");
}

for my $case (
    [ 'an empty field after the last column',         '"k1","v1",,,' ],
    [ 'a field of 0 after the last column',           '"k1","v1",,,0' ],
    [ 'an empty field after a quoted last column',    '"k1","v1",,"yes",' ],
    [ 'an empty field after an unquoted last column', '"k1","v1",,yes,' ],
    [ 'a text field after the last column',           '"k1","v1",,,extra' ])
{
    my ($label, $row) = @$case;
    my ($errors, $rows) = restore('"k0","v0",,', $row);
    like($errors, qr/Too many fields on line \d+: \Q$row\E/, "$label: the row is refused");
    is_deeply($rows, { before => 'kept|' }, "$label: the restore is rolled back");
}

done_testing();
