#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

# A riscv64 management node has no legacy Genesis: the image ships as the OpenEmbedded package
# xcat-genesis-openembedded-riscv64, which mknb consumes. xCAT.spec already says so for the rpm
# side and gives riscv64 its own dependency block.
#
# The deb side named xcat-genesis-scripts-amd64 in a plain Depends, and that package is
# Architecture: all, so apt installed the x86 Genesis scripts (and, through them, the x86 Genesis
# base) on every management node that is not amd64. Name one scripts package per architecture that
# has a legacy Genesis, so riscv64 gets none and ppc64el gets its own.

my $repo_root = File::Spec->rel2abs(
    File::Spec->catdir( $FindBin::Bin, '..', '..' )
);

sub read_file {
    my ($filename) = @_;
    open( my $fh, '<', $filename ) or die "Unable to read $filename: $!";
    my $content = do { local $/; <$fh> };
    close($fh);
    return $content;
}

my $have_dpkg_deps = eval { require Dpkg::Deps; 1 } ? 1 : 0;

foreach my $pkg ( [ 'xCAT', 'xcat' ], [ 'xCATsn', 'xcatsn' ] ) {
    my ( $dir, $name ) = @$pkg;
    my $control = read_file( File::Spec->catfile( $repo_root, $dir, 'debian', 'control' ) );
    my ($depends) = $control =~ /^Depends:\s*(.*)$/m;
    ok( defined $depends, "$name debian/control has a Depends line" );
    my ($recommends) = $control =~ /^Recommends:\s*(.*)$/m;
    ok( defined $recommends, "$name debian/control has a Recommends line" );

    my @entries = grep { /xcat-genesis-scripts/ } split( /\s*,\s*/, $depends );
    ok( scalar(@entries), "$name depends on a legacy Genesis scripts package" );
    my @unqualified = grep { !/\[(?:amd64|ppc64el)\]\s*$/ } @entries;
    is_deeply( \@unqualified, [],
        "$name asks for the legacy Genesis scripts of an architecture that has them" )
        or diag( "unqualified: @unqualified" );

  SKIP: {
        skip( "Dpkg::Deps is not available", 7 ) unless $have_dpkg_deps;

        # Dpkg::Deps cannot parse a substvar, which dpkg-gencontrol expands before it gets here.
        ( my $parsable = $depends ) =~ s/\$\{[^}]*\}\s*,?\s*//g;
        my %reduced = map {
            my $d = Dpkg::Deps::deps_parse( $parsable, reduce_arch => 1, host_arch => $_ );
            $_ => ( defined $d ? $d->output() : '' )
        } qw(riscv64 amd64 ppc64el);

        unlike( $reduced{riscv64}, qr/xcat-genesis-scripts/,
            "$name on riscv64 does not pull the legacy Genesis scripts" );
        like( $reduced{amd64}, qr/xcat-genesis-scripts-amd64/,
            "$name on amd64 still pulls them" );
        like( $reduced{ppc64el}, qr/xcat-genesis-scripts-ppc64el/,
            "$name on ppc64el pulls the ppc64el ones" );

        # The restriction must not take anything else with it: every other dependency of the
        # amd64 package must survive on riscv64.
        my @lost = grep { $reduced{riscv64} !~ /\Q$_\E/ }
                   grep { !/xcat-genesis-scripts/ }
                   map  { my $d = $_; $d =~ s/\s*\(.*//; $d =~ s/\s*\[.*//; $d }
                   split( /\s*,\s*/, $reduced{amd64} );
        is_deeply( \@lost, [],
            "$name on riscv64 keeps every other dependency" )
            or diag( "dropped: @lost" );

        # A management node of any architecture can provision nodes of another, so what it SERVES
        # to those nodes -- the x86 boot payload and the Genesis images of the other architectures
        # -- stays recommended everywhere. Only the legacy Genesis of this node is architecture
        # specific, and that one is a dependency, not a recommendation.
        my %reduced_recommends = map {
            my $d = Dpkg::Deps::deps_parse( $recommends, reduce_arch => 1, host_arch => $_ );
            $_ => ( defined $d ? $d->output() : '' )
        } qw(riscv64 amd64);

        like( $reduced_recommends{riscv64}, qr/\bsyslinux-xcat\b/,
            "$name on riscv64 still recommends the x86 boot payload it serves" );
        like( $reduced_recommends{riscv64}, qr/xcat-genesis-openembedded-x86-64/,
            "$name on riscv64 still recommends the Genesis image of the other architectures" );
        like( $reduced_recommends{amd64}, qr/\bsyslinux-xcat\b/,
            "$name on amd64 is unchanged" );
    }
}

done_testing();
