#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use File::Temp qw(tempfile);
use Test::More;

my $libdir = "$FindBin::Bin/../../perl-xCAT";
plan skip_all => 'NodeRange.pm not found' unless -r "$libdir/xCAT/NodeRange.pm";

# Stub Table so NodeRange loads without a database. The ^ file path does not
# call a Table method.
BEGIN {
    $INC{'xCAT/Table.pm'} = 1;
    package xCAT::Table;
    sub new { return bless {}, shift }
    sub _set_use_cache { }
    sub _build_cache   { }
    our $AUTOLOAD;
    sub AUTOLOAD { return }
    sub DESTROY  { }
}
eval { require Text::Balanced; 1 } or plan skip_all => 'Text::Balanced is required';

push @INC, $libdir;
require xCAT::NodeRange;

my ($fh, $listfile) = tempfile('xcat_nrlist_XXXXXX', TMPDIR => 1, UNLINK => 1);
print {$fh} "n1uniqtoken\n";
close $fh;

eval { xCAT::NodeRange::noderange('^' . $listfile, 0, 0) };
is($@, '', 'a real ^file is processed without error');
ok(!xCAT::NodeRange::file_operator_rejected(), 'without nofile the ^file operator is not rejected');

my @nofile = eval { xCAT::NodeRange::noderange('^' . $listfile, 0, 0, nofile => 1) };
is($@, '', 'nofile: a ^file range is accepted without error');
is_deeply(\@nofile, [], 'nofile: the ^file operator yields no nodes');
ok(xCAT::NodeRange::file_operator_rejected(), 'nofile: the ^file operator is flagged as rejected');

xCAT::NodeRange::noderange('nodeX,^' . $listfile, 0, 0, nofile => 1);
ok(xCAT::NodeRange::file_operator_rejected(), 'nofile: a ^file mixed with a plain node is still flagged');

xCAT::NodeRange::noderange('nodeX', 0, 0, nofile => 1);
ok(!xCAT::NodeRange::file_operator_rejected(), 'nofile: a plain range is not flagged');

my $marker = File::Spec->catfile(File::Spec->tmpdir, "xcat_nr_nofile_marker_$$");
unlink $marker;
END { unlink $marker if defined $marker }
eval { xCAT::NodeRange::noderange('^touch ' . $marker . ' |', 0, 0, nofile => 1) };
ok(!-e $marker, 'nofile: the ^file operator opens and runs nothing');

$::XCATSITEVALS{excludenodes} = 'excludednode';
xCAT::NodeRange::noderange('nodeX,^' . $listfile, 0, 1, nofile => 1);
ok(xCAT::NodeRange::file_operator_rejected(),
    'site.excludenodes does not erase a rejected request ^file');

$::XCATSITEVALS{excludenodes} = '^' . $listfile;
xCAT::NodeRange::noderange('nodeX', 0, 1, nofile => 1);
ok(!xCAT::NodeRange::file_operator_rejected(),
    'a trusted site.excludenodes ^file is not attributed to the request');
ok((grep { $_ eq 'n1uniqtoken' } xCAT::NodeRange::nodesmissed()),
    'a trusted site.excludenodes ^file is read, not skipped');
$::XCATSITEVALS{excludenodes} = undef;

done_testing();
