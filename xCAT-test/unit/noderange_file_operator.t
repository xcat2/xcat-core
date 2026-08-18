#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use File::Temp qw(tempfile);
use Test::More;

my $libdir = "$FindBin::Bin/../../perl-xCAT";
plan skip_all => 'NodeRange.pm not found' unless -r "$libdir/xCAT/NodeRange.pm";

# NodeRange requires xCAT::Table at load and creates a nodelist handle once, on
# entry. Stub Table so the module loads and that init succeeds without a
# database. The ^file path under test never calls a Table method.
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

# The command an injected ^file range would run. The marker must never appear.
my $marker = File::Spec->catfile(File::Spec->tmpdir, "xcat_nr_marker_$$");
unlink $marker;
END { unlink $marker if defined $marker }

# The ^ operator reads node names from a file. A two-argument open would treat
# the value as a shell pipe and run the command; assert it does not.
my $evil = '^touch ' . $marker . ' |';
eval { xCAT::NodeRange::noderange($evil, 0, 0) };
ok(!-e $marker, 'a piped ^file range does not execute a command');

# A real file that holds only comment and blank lines is opened and read
# without error and yields no nodes.
my ($fh, $listfile) = tempfile('xcat_nrlist_XXXXXX', TMPDIR => 1, UNLINK => 1);
print {$fh} "# a comment line\n\n";
close $fh;
my @res = eval { xCAT::NodeRange::noderange('^' . $listfile, 0, 0) };
is($@, '', 'a real ^file is read without error');
is_deeply(\@res, [], 'a comment-only ^file yields no nodes');

done_testing();
