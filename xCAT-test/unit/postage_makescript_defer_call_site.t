#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

# Regression: makescript's call to defer_syncfiles_to_postboot was covered by nothing.
#
# The helper itself has tests, but deleting the whole block out of makescript -- the
# provmethod override AND the call -- left the entire unit suite green. That is how a wrong
# deletion shipped once already: the override was removed on the mistaken grounds that
# %image_hash never carries a provmethod, and no test noticed.
#
# makescript needs a management node and a database, so the block is lifted out and eval'd into
# a scratch package, driven with the hash makescript actually builds. What is under test is the
# resolution -- an osimage NAME becoming the osimage's real provmethod -- and that the result is
# what reaches the helper.

my $repo_root = File::Spec->rel2abs(
    File::Spec->catdir( $FindBin::Bin, '..', '..' )
);
my $postage = File::Spec->catfile(
    $repo_root, 'xCAT-server', 'lib', 'perl', 'xCAT', 'Postage.pm'
);
plan skip_all => "Postage.pm not found" unless -f $postage;

my $src = do { local $/; open my $fh, '<', $postage or die $!; <$fh> };

# The helper, and the block in makescript that calls it. BAIL_OUT rather than skip, so a rename
# fails loudly instead of silently covering nothing.
my ($helper) = $src =~ /\n(sub defer_syncfiles_to_postboot \{.*?\n\})\n/s;
BAIL_OUT('could not extract defer_syncfiles_to_postboot from Postage.pm') unless defined $helper;

my ($block) = $src =~ /\n([ ]+my \$effective_provmethod = \$provmethod;\n.*?defer_syncfiles_to_postboot\(\n.*?\);)\n/s;
BAIL_OUT('could not extract the makescript call site from Postage.pm') unless defined $block;
BAIL_OUT('the extracted call site does not consult the image hash')
  unless $block =~ /\$image_hash\{\$osimgname\}\{'provmethod'\}/;

my $driver = <<"CODE";
$helper

sub drive {
    my (\%a) = \@_;
    my \$provmethod   = \$a{provmethod};
    my \$osimgname    = \$a{osimgname};
    my \$os           = \$a{os};
    my \$nodesetstate = \$a{nodesetstate};
    my \$postscripts     = \$a{postscripts};
    my \$postbootscripts = \$a{postbootscripts};
    my \%image_hash = \%{ \$a{image_hash} || {} };
$block
    return (\$postscripts, \$postbootscripts, \$effective_provmethod);
}
CODE

{
    package T;
    eval "$driver; 1" or main::BAIL_OUT("could not eval the makescript call site: $@");
}

my $POST = "otherpkgs\nsyncfiles\nremoteshell\n";

# nodetype.provmethod naming an osimage: getScripts() fills %image_hash from the osimage table,
# so the override is what turns that name into the real provmethod.
{
    my ($post, $postboot, $eff) = T::drive(
        os => 'ubuntu24.04', nodesetstate => undef,
        provmethod => 'ubuntu24.04-x86_64-install-compute',
        osimgname  => 'ubuntu24.04-x86_64-install-compute',
        image_hash => { 'ubuntu24.04-x86_64-install-compute' => { provmethod => 'install' } },
        postscripts => $POST, postbootscripts => '' );
    is( $eff, 'install', 'an osimage name resolves to the osimage provmethod' );
    unlike( $post, qr/^syncfiles$/m, 'so syncfiles leaves the in-target postscripts' );
    like( $postboot, qr/^syncfiles$/m, 'and is deferred to the postboot scripts' );
}

# Without the resolution there is nothing to key off when nodesetstate is absent.
{
    my ($post, $postboot, $eff) = T::drive(
        os => 'ubuntu24.04', nodesetstate => undef,
        provmethod => 'ubuntu24.04-x86_64-install-compute',
        osimgname  => 'ubuntu24.04-x86_64-install-compute',
        image_hash => {},
        postscripts => $POST, postbootscripts => '' );
    is( $eff, 'ubuntu24.04-x86_64-install-compute',
        'an osimage with no row in the hash leaves the provmethod alone' );
    like( $post, qr/^syncfiles$/m, 'and nothing is deferred' );
}

# A literal provmethod is passed straight through -- $osimgname is undef in that case.
{
    my ($post, $postboot, $eff) = T::drive(
        os => 'ubuntu24.04', nodesetstate => undef, provmethod => 'install',
        osimgname => undef, image_hash => {},
        postscripts => $POST, postbootscripts => '' );
    is( $eff, 'install', 'a literal provmethod is used as-is' );
    unlike( $post, qr/^syncfiles$/m, 'and still defers' );
}

# nodesetstate wins when it is set, which is the ordinary nodeset path.
{
    my ($post, $postboot) = T::drive(
        os => 'ubuntu24.04', nodesetstate => 'install',
        provmethod => 'ubuntu24.04-x86_64-install-compute',
        osimgname  => 'ubuntu24.04-x86_64-install-compute',
        image_hash => {}, postscripts => $POST, postbootscripts => '' );
    unlike( $post, qr/^syncfiles$/m, 'nodesetstate install defers regardless of provmethod' );
    like( $postboot, qr/^syncfiles$/m, 'and syncfiles lands in the postboot scripts' );
}

# Not Ubuntu: the block must not touch anything.
{
    my ($post, $postboot) = T::drive(
        os => 'rhels9', nodesetstate => 'install', provmethod => 'install',
        osimgname => undef, image_hash => {}, postscripts => $POST, postbootscripts => '' );
    like( $post, qr/^syncfiles$/m, 'a non-Debian OS keeps syncfiles where it was' );
    is( $postboot, '', 'and gains no postboot scripts' );
}

done_testing();
