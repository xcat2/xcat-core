#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );

sub slurp {
    my ($rel) = @_;
    my $path = File::Spec->catfile( $repo_root, $rel );
    return unless -r $path;
    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    my $c = do { local $/; <$fh> };
    close($fh);
    return $c;
}

# Report statements that sit after an unconditional return inside the same
# block. Those are unreachable, which is how the deprecated provisioning paths
# survived in the tree for years after they stopped running.
sub unreachable_after_return {
    my ($source) = @_;
    my @lines = split( /\n/, $source, -1 );
    my @found;
    for my $i ( 0 .. $#lines ) {
        my ($indent) = $lines[$i] =~ /^(\s*)(?:return\s*;|return\s+\d+\s*;)\s*$/;
        next unless defined $indent;
        my $depth = length($indent);
        for my $j ( $i + 1 .. $#lines ) {
            my $next = $lines[$j];
            next if $next =~ /^\s*$/ || $next =~ /^\s*#/;
            my ($ni) = $next =~ /^(\s*)/;
            last if length($ni) < $depth;
            last if $next =~ /^\s*[}\]\)]/;
            push @found, ( $j + 1 ) . ": $next";
            last;
        }
    }
    return @found;
}

my $destiny = slurp('xCAT-server/lib/xcat/plugins/destiny.pm');
my $packimage = slurp('xCAT-server/lib/xcat/plugins/packimage.pm');

plan skip_all => 'destiny.pm or packimage.pm not found'
  unless defined($destiny) && defined($packimage);

my @destiny_dead = unreachable_after_return($destiny);
is_deeply( \@destiny_dead, [], 'destiny.pm has no statements after an unconditional return' );

my @packimage_dead = unreachable_after_return($packimage);
is_deeply( \@packimage_dead, [], 'packimage.pm has no statements after an unconditional return' );

# The deprecated states must still be rejected. Removing the dead path below the
# rejection must not remove the rejection itself.
like(
    $destiny,
    qr/have been deprecated, use \\"osimage=/,
    'the deprecated nodeset states are still rejected'
);

# packimage rejects -o, -p and -a up front, so nothing after that point can ask
# for them again. The old no-imagename branch demanded -o, which could never be
# supplied, and reported that as the error.
unlike(
    $packimage,
    qr/Please specify a os version with the -o flag/,
    'packimage no longer asks for an option it rejects earlier'
);
like(
    $packimage,
    qr/-o, -p and -a options are obsoleted/,
    'packimage still rejects the deprecated options'
);
like(
    $packimage,
    qr/An image name is required/,
    'packimage reports the missing image name instead'
);

done_testing();
