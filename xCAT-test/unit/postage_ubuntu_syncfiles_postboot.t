#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Test::More;

# On the Ubuntu/Debian DISKFUL install path a node's postscripts run inside the installer's
# in-target chroot, before the node has booted as itself. syncfiles asks the management node to
# scp files INTO the running node, which cannot work there -- no sshd yet -- so it times out and
# the node reports status=failed even though the OS installed fine. Postage defers it to the
# postbootscripts, which run on the booted node. Drive that decision directly.

my $repo = "$FindBin::Bin/../..";
plan skip_all => 'Postage.pm not found' unless -r "$repo/xCAT-server/lib/perl/xCAT/Postage.pm";

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
eval { require xCAT::Postage; 1 } or plan skip_all => "could not load xCAT::Postage: $@";

my $DEFERRED = "# ubuntu-deferred-postbootscripts-start-here\nsyncfiles\n"
             . "# ubuntu-deferred-postbootscripts-end-here\n";

sub defer { return xCAT::Postage::defer_syncfiles_to_postboot(@_) }

# --- the case the fix exists for -------------------------------------------
{
    my ($post, $postboot) =
      defer('ubuntu24.04', 'install', 'install', "syncfiles\notherpkgs\n", "setupntp\n");

    is($post, "otherpkgs\n", 'syncfiles is removed from the postscripts');
    is($postboot, $DEFERRED . "setupntp\n",
        'syncfiles is prepended to the postbootscripts, ahead of what consumes its files');
}

# The nodeset state is not always known; the osimage provmethod decides then.
{
    my ($post, $postboot) =
      defer('ubuntu24.04', 'install', undef, "syncfiles\n", "setupntp\n");
    is($post, '', 'provmethod=install defers when no nodeset state is given');
    is($postboot, $DEFERRED . "setupntp\n", 'and the postbootscripts receive it');
}

# --- paths that must NOT change --------------------------------------------
my @untouched = (
    [ 'netboot keeps its postscripts on the booted node already',
      'ubuntu24.04', 'netboot', 'netboot' ],
    [ 'statelite is unaffected',
      'ubuntu22.04', 'statelite', 'statelite' ],
    [ 'EL runs postscripts on the booted node, so nothing moves',
      'rhels9.4', 'install', 'install' ],
    [ 'SLES is unaffected',
      'sles15.6', 'install', 'install' ],
    [ 'an undefined os is left alone',
      undef, 'install', 'install' ],
);
foreach my $case (@untouched) {
    my ($name, $os, $provmethod, $state) = @$case;
    my ($post, $postboot) = defer($os, $provmethod, $state, "syncfiles\notherpkgs\n", "setupntp\n");
    is($post, "syncfiles\notherpkgs\n", "$name: the postscripts are unchanged");
    is($postboot, "setupntp\n",         "$name: the postbootscripts are unchanged");
}

# A node that does not run syncfiles must not gain an empty deferral block.
{
    my ($post, $postboot) = defer('ubuntu24.04', 'install', 'install', "otherpkgs\n", "setupntp\n");
    is($post, "otherpkgs\n",  'a node without syncfiles keeps its postscripts');
    is($postboot, "setupntp\n", 'and gains no deferral block');
}

# The name is matched whole: a postscript whose name merely contains "syncfiles" stays put.
{
    my ($post, $postboot) =
      defer('ubuntu24.04', 'install', 'install', "syncfiles2\nmysyncfiles\n", "setupntp\n");
    is($post, "syncfiles2\nmysyncfiles\n", 'a lookalike postscript name is not deferred');
    is($postboot, "setupntp\n", 'and nothing is added to the postbootscripts');
}

# Indented entries are still the syncfiles postscript.
{
    my ($post, $postboot) = defer('ubuntu24.04', 'install', 'install', "  syncfiles \nfoo\n", undef);
    is($post, "foo\n", 'an indented syncfiles entry is deferred');
    is($postboot, $DEFERRED, 'an undefined postbootscripts list becomes the deferral block');
}

# A node that already lists syncfiles as its own postbootscript keeps that entry, and does not
# gain a second one -- the install-time copy is still removed, since that is the one that cannot work.
{
    my ($post, $postboot) =
      defer('ubuntu24.04', 'install', 'install', "syncfiles\nfoo\n", "syncfiles\nsetupntp\n");
    is($post, "foo\n", 'the postscripts entry is still removed');
    is($postboot, "syncfiles\nsetupntp\n",
        "an admin's own syncfiles postbootscript is left as it was, not duplicated");
}

# Rendering the same node twice must not stack a second copy.
{
    my ($post, $postboot) =
      defer('ubuntu24.04', 'install', 'install', "syncfiles\nfoo\n", "setupntp\n");
    my ($post2, $postboot2) = defer('ubuntu24.04', 'install', 'install', $post, $postboot);
    is($post2, $post,         'a second pass leaves the postscripts alone');
    is($postboot2, $postboot, 'a second pass does not duplicate syncfiles');
}

done_testing();
