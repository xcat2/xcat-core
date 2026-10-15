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
$ENV{XCATCFG} = "SQLite:$fixture/db";
require xCAT::Table;

# A reader builds the cache of the table, and a conditional update then changes a row.
xCAT::Table->new('nodelist', -create => 1)->setAttribs({ node => 'cachenode' }, { groups => 'compute' });
my $tab = xCAT::Table->new('postscripts', -create => 1, -autocommit => 0);
$tab->setAttribs({ node => 'cachenode' }, { postscripts => 'script before the update' });
$tab->commit;
my ($entry) = $tab->getNodeAttribs('cachenode', ['postscripts'], prefetchcache => 1);
is($entry && $entry->{postscripts}, 'script before the update', 'the cached reader sees the row');

my ($rc, $error) = $tab->setAttribsWhere(xCAT::Table::delimitcol('node') . " = 'cachenode'", { postscripts => 'script after the update' });
$tab->commit;
is($rc, 0, 'the conditional update succeeds');
($entry) = $tab->getNodeAttribs('cachenode', ['postscripts'], prefetchcache => 1);
is($entry && $entry->{postscripts}, 'script after the update', 'the cached reader sees the conditional update at once');

{
    # A cached read sees a conditional update before the rollback rejects it.
    $tab->setAttribsWhere(xCAT::Table::delimitcol('node') . " = 'cachenode'", { postscripts => 'script that the rollback rejects' });
    ($entry) = $tab->getNodeAttribs('cachenode', ['postscripts'], prefetchcache => 1);
    is($entry && $entry->{postscripts}, 'script that the rollback rejects', 'the cached reader sees the update before the rollback');
    $tab->rollback;
    ($entry) = $tab->getNodeAttribs('cachenode', ['postscripts'], prefetchcache => 1);
    is($entry && $entry->{postscripts}, 'script after the update', 'the cached reader sees the committed value after the rollback');
}

done_testing();
