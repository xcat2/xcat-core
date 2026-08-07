#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my $plugin = File::Spec->catfile( $repo_root, 'xCAT-server/lib/xcat/plugins/destiny.pm' );

plan skip_all => "$plugin not found" unless -r $plugin;

open( my $fh, '<', $plugin ) or die "Unable to read $plugin: $!";
my $source = do { local $/; <$fh> };
close($fh);

# Extract the chain-advance block out of nextdestiny() and run it directly, so
# that this exercises the shipped logic instead of a copy that can drift away
# from it. The block only touches $ref and $callnodeset, so it can be evaluated
# without a database or a running xcatd.
my ($block) = $source =~ m{
    ( unless \s* \(\$ref->\{currchain\}\) .*?
      \#If \s we've \s gone \s off \s the \s end \s of \s the \s chain .*?
      \n \s* \} \n )
}sx;

ok( $block, 'the chain-advance block was located in nextdestiny()' )
  or BAIL_OUT('destiny.pm no longer matches the expected chain-advance shape');

sub advance {
    my (%chain) = @_;
    my $ref = { %chain };
    my $callnodeset = 1;
    my $code = "sub { my (\$ref, \$callnodeset) = \@_;\n$block\n return (\$ref, \$callnodeset); }";
    my $sub = eval $code;
    die "Unable to evaluate the extracted block: $@" if $@;
    my ( $out, $cns ) = $sub->( $ref, $callnodeset );
    return $out;
}

# A completed provision leaves chain.currchain set to 'boot' (setdestiny does
# this once the install or netboot destiny is applied). Some installers advance
# the destiny more than once, and that extra advance must leave the node on a
# destiny that still boots it.
my $repeat = advance( currchain => 'boot', currstate => 'boot', chain => 'osimage=rhels9-x86_64-install-compute' );
is( $repeat->{currstate}, 'boot', 'advancing again from boot keeps the node booting' );
is( $repeat->{currchain}, 'boot', 'advancing again from boot leaves boot as the next destiny' );

# Advancing repeatedly has to stay idempotent, not drift one state per call.
my $twice = advance( currchain => $repeat->{currchain}, currstate => $repeat->{currstate}, chain => 'osimage=rhels9-x86_64-install-compute' );
is( $twice->{currstate}, 'boot', 'a third advance still leaves the node booting' );
is( $twice->{currchain}, 'boot', 'repeated advances from boot are idempotent' );

# An exhausted non-boot chain must still fall to standby, so that a finished
# install does not simply reinstall the node on its next boot.
my $exhausted = advance(
    currchain => 'osimage=rhels9-x86_64-install-compute',
    currstate => 'osimage=rhels9-x86_64-install-compute',
    chain     => 'osimage=rhels9-x86_64-install-compute'
);
is( $exhausted->{currstate}, 'standby', 'an exhausted install chain still falls to standby' );

# A chain with steps left is untouched by the guard and advances normally.
my $remaining = advance(
    currchain => 'osimage=rhels9-x86_64-install-compute,boot',
    currstate => 'osimage=rhels9-x86_64-install-compute',
    chain     => 'osimage=rhels9-x86_64-install-compute,boot'
);
is( $remaining->{currstate}, 'osimage=rhels9-x86_64-install-compute', 'a chain with steps left advances to its next step' );
is( $remaining->{currchain}, 'boot', 'a chain with steps left keeps the rest of the chain' );

# With no current chain the default chain is still copied in.
my $fresh = advance( currchain => '', currstate => '', chain => 'osimage=rhels9-x86_64-install-compute,boot' );
is( $fresh->{currstate}, 'osimage=rhels9-x86_64-install-compute', 'an empty currchain still starts from the default chain' );

done_testing();
