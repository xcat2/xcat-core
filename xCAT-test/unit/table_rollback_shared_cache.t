#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use File::Temp qw(tempdir);
use Test::More;

# A generic DBI database gives all tables of one autocommit mode one handle, as MySQL and PostgreSQL do.
my $fixture = tempdir(CLEANUP => 1);
$ENV{XCATCFG} = "dbi:SQLite:dbname=$fixture/xcatdb";
require xCAT::Table;

xCAT::Table->new('nodelist', -create => 1)->setAttribs({ node => 'cachenode' }, { groups => 'compute' });
my $scripts = xCAT::Table->new('postscripts', -create => 1, -autocommit => 0);
my $other   = xCAT::Table->new('site',        -create => 1, -autocommit => 0);
is($scripts->{dbh}, $other->{dbh}, 'the tables share one handle');
$scripts->setAttribs({ node => 'cachenode' }, { postscripts => 'committed script' });
$scripts->commit;

$scripts->setAttribsWhere(xCAT::Table::delimitcol('node') . " = 'cachenode'", { postscripts => 'rejected script' });
my ($entry) = $scripts->getNodeAttribs('cachenode', ['postscripts'], prefetchcache => 1);
is($entry && $entry->{postscripts}, 'rejected script', 'the cached reader sees the update before the rollback');

# A table that does not exist fails to open on the same handle.
ok(!xCAT::Table->new('networks', -create => 0, -autocommit => 0), 'a table that does not exist fails to open');
ok(eval { $other->rollback; 1 }, 'the rollback completes after a table failed to open') or diag($@);
($entry) = $scripts->getNodeAttribs('cachenode', ['postscripts'], prefetchcache => 1);
is($entry && $entry->{postscripts}, 'committed script', 'a rollback through another table of the handle refreshes the cache');

done_testing();
