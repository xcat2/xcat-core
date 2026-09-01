#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

# Regression: nodes whose noderes.xcatmaster is unset stopped getting a boot config at all.
#
# When xcatmaster is unset, debian.pm sets $instserver to the literal '!myipfn!'. That is a
# placeholder, not a hostname: pxe.pm:176 and grub2.pm:129 substitute it with
# my_ip_facing($node) -- an address -- when they write the boot config. Resolving it as a name
# returns undef, so the subiquity path reported "Could not resolve the install server" and
# `next`ed past the node, where before it had produced exactly the numeric nfsroot the fix
# wants. anaconda.pm and sles.pm both guard the same placeholder with
# `unless ($instserver eq '!myipfn!')`; the Ubuntu path did not.
#
# noderes.5.rst:125 documents an unset xcatmaster as supported, and the CI confs all set it
# (reg_linux_diskfull_installation_flat chdefs xcatmaster=$$MN), which is why no pipeline
# would catch this.
#
# The decision lives in its own routine so it can be driven with an injected resolver instead
# of a management node.

my $repo_root = File::Spec->rel2abs(
    File::Spec->catdir( $FindBin::Bin, '..', '..' )
);
my $plugin = File::Spec->catfile(
    $repo_root, 'xCAT-server', 'lib', 'xcat', 'plugins', 'debian.pm'
);
plan skip_all => "debian.pm not found" unless -f $plugin;

my $src = do { local $/; open my $fh, '<', $plugin or die $!; <$fh> };

# Lift the routine into a scratch package: debian.pm itself needs a management node to load.
# BAIL_OUT rather than skip, so a rename fails loudly instead of silently covering nothing.
my ($body) = $src =~ /\n(sub subiquity_nfsroot_server \{.*?\n\})\n/s;
BAIL_OUT('could not extract subiquity_nfsroot_server from debian.pm')
  unless defined $body;

{
    package T;
    eval "$body; 1" or main::BAIL_OUT("could not eval subiquity_nfsroot_server: $@");
}

# A resolver that records what it was asked, so "never asked" is checkable.
my @asked;
my $resolver = sub { push @asked, $_[0]; return $_[0] eq 'mn.cluster' ? '10.0.0.1' : undef };

# The bug: the placeholder must survive to the boot config, not be resolved.
@asked = ();
is( T::subiquity_nfsroot_server( '!myipfn!', $resolver ), '!myipfn!',
    'the !myipfn! placeholder is passed through untouched' );
is_deeply( \@asked, [],
    'and the resolver is never asked to resolve it' );

# A name that resolves still resolves.
@asked = ();
is( T::subiquity_nfsroot_server( 'mn.cluster', $resolver ), '10.0.0.1',
    'a resolvable install server name becomes its address' );
is_deeply( \@asked, ['mn.cluster'], 'by asking the resolver' );

# An address passes through the resolver unchanged, as getipaddr does.
is( T::subiquity_nfsroot_server( '10.0.0.1', sub { $_[0] } ), '10.0.0.1',
    'an address is returned as itself' );

# The guard that motivated the original commit must survive: a name that does not resolve is
# still a failure, because klibc's nfsmount cannot resolve it either.
@asked = ();
ok( !defined T::subiquity_nfsroot_server( 'nosuchhost', $resolver ),
    'a name that does not resolve is still rejected' );
is_deeply( \@asked, ['nosuchhost'], 'after actually trying to resolve it' );

# Degenerate inputs are rejected rather than passed to the resolver.
ok( !defined T::subiquity_nfsroot_server( undef, $resolver ),
    'an undefined install server is rejected' );
ok( !defined T::subiquity_nfsroot_server( '', $resolver ),
    'an empty install server is rejected' );

done_testing();
