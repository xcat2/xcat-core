#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(mkpath);
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

use lib "$FindBin::Bin/../../perl-xCAT";
use xCAT::ProfiledNodeUtils;

# nodepurge deletes the autoinstall configuration of each node it removes. mkinstall writes that
# configuration as a directory for a Subiquity node and as a plain file for preseed and kickstart,
# so the cleanup must remove both shapes.

my $dir = tempdir(CLEANUP => 1);

# A Subiquity node: cloud-init files in a directory named after the node.
mkpath("$dir/subiquitynode");
write_text("$dir/subiquitynode/$_", "x\n") for qw(meta-data user-data vendor-data);

# A preseed node: a plain file, with its .pre and .post scripts.
write_text("$dir/$_", "x\n") for qw(preseednode preseednode.pre preseednode.post);

# othernode is not in the node list, so the routine must leave it alone.
write_text("$dir/othernode", "x\n");

# neverinstalled has no configuration at all, so the routine must not die on it.
xCAT::ProfiledNodeUtils->remove_node_config_files(
    $dir, ['subiquitynode', 'preseednode', 'neverinstalled']);

ok(!-e "$dir/subiquitynode",    'the autoinstall directory of a Subiquity node is removed');
ok(!-e "$dir/preseednode",      'the autoinstall file of a preseed node is removed');
ok(!-e "$dir/preseednode.pre",  'the .pre script of a preseed node is removed');
ok(!-e "$dir/preseednode.post", 'the .post script of a preseed node is removed');
ok(-e "$dir/othernode",         'a node outside the node list keeps its configuration');

done_testing();
