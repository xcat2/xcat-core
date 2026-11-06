#!/usr/bin/env perl
# Every xcatroot xCAT ships must carry the execute bit.
#
# dracut dispatches the network root through 45net-lib/netroot.sh, which does
# handler=$(command -v "${netroot%%:*}root"). command -v skips a file without
# the execute bit, so a non-executable xcatroot makes netroot.sh print
# "No handler for netroot type 'xcat'" and the node powers off in its
# initramfs. genimage copies the file with the mode it finds in the share tree
# (chmod($perm & 07777)), and dracut's inst_script keeps that mode, so the mode
# in the repository is what reaches the initramfs.
use strict;
use warnings;

use File::Basename qw(dirname);
use File::Find qw(find);
use File::Spec;
use Test::More;

my $root = File::Spec->rel2abs(File::Spec->catdir(dirname(__FILE__), '..', '..'));

my @trees = grep { -d } map { File::Spec->catdir($root, $_) }
  ('xCAT-server/share/xcat/netboot', 'xCAT-genesis-base');

die "no netboot tree under $root" unless @trees;

my @handlers;
find(sub { push @handlers, $File::Find::name if $_ eq 'xcatroot' && -f $_ }, @trees);

# A positive control: an empty list would pass every assertion below.
cmp_ok(scalar(@handlers), '>=', 5, scalar(@handlers) . ' xcatroot handlers found');

for my $handler (sort @handlers) {
    ok(-x $handler, File::Spec->abs2rel($handler, $root) . ' is executable');
}

done_testing();
