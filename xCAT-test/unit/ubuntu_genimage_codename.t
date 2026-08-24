#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

# Regression: the Ubuntu netboot genimage derives a debootstrap suite from the osimage's
# osvers. It reduced "ubuntu24.04.4" to "24.04" with a bare s/\.\d+$//, which ALSO strips the
# minor from a two-part osvers -- an initial release with no point-release ISO, e.g.
# "ubuntu26.04" -> "26". "26" is not in the codename map and is not a debootstrap suite, so
# the rootimg build dies with:
#
#     E: No such script: /usr/share/debootstrap/scripts/26
#
# Only a trailing THIRD component may be stripped, so 24.04.4 -> 24.04 while 26.04 (and 18.04,
# 20.04, 22.04 from an initial-release ISO) survive intact and reach the codename map.
#
# Driven by the real derivation code: the substitution and the codename map are extracted from
# genimage and evaluated here, so this test tracks the script rather than a copy of it.

my $repo_root = File::Spec->rel2abs(
    File::Spec->catdir( $FindBin::Bin, '..', '..' )
);

my $genimage_path = File::Spec->catfile(
    $repo_root, 'xCAT-server', 'share', 'xcat', 'netboot', 'ubuntu', 'genimage'
);
plan skip_all => "genimage not found at $genimage_path" unless -f $genimage_path;

my $src = do { local $/; open my $fh, '<', $genimage_path or die $!; <$fh> };

my ($strip) = $src =~ /^\s*(\$codename\s*=~\s*s\/.*?;)\s*(?:#.*)?$/m;
ok( defined $strip, 'found the codename point-release substitution in genimage' )
  or done_testing(), exit;

my ($map) = $src =~ /^\s*(my\s+%cn\s*=\s*\(.*?\);)\s*$/ms;
ok( defined $map, 'found the codename map in genimage' )
  or done_testing(), exit;

sub derive {
    my ($osver) = @_;
    my $codename = $osver;
    $codename =~ s/^ubuntu//;
    ## no critic
    eval "$strip $map \$codename = \$cn{\$codename} if exists \$cn{\$codename}; 1"
      or die "failed to evaluate genimage codename derivation: $@";
    ## use critic
    return $codename;
}

is( derive('ubuntu24.04.4'), 'noble',
    'a point release still reduces to its MAJOR.MINOR codename (24.04.4 -> noble)' );
is( derive('ubuntu26.04'), 'resolute',
    'an initial release keeps its minor and maps to a codename (26.04 -> resolute, not "26")' );
is( derive('ubuntu20.04'), 'focal',
    'an initial 20.04 osvers is not over-stripped to "20"' );
is( derive('ubuntu22.04'), 'jammy',
    'an initial 22.04 osvers is not over-stripped to "22"' );
is( derive('ubuntu18.04'), 'bionic',
    'an initial 18.04 osvers is not over-stripped to "18"' );

done_testing();
