#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

# archive.ubuntu.com publishes amd64 and i386 only. A ppc64el or riscv64 netboot image built
# against it finds no package at all, and debootstrap fails before it copies anything, so the
# default mirror has to follow the image architecture.
#
# Driven by the real selection code: the two statements are extracted from genimage and
# evaluated here, so this test tracks the script rather than a copy of it.

my $repo_root = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..', '..' ) );
my $genimage_path = File::Spec->catfile(
    $repo_root, 'xCAT-server', 'share', 'xcat', 'netboot', 'ubuntu', 'genimage'
);
plan skip_all => "genimage not found at $genimage_path" unless -f $genimage_path;

my $src = do { local $/; open my $fh, '<', $genimage_path or die $!; <$fh> };

my ($default) = $src =~ /^\s*(my \$default = \(\$uarch =~.*?;)\s*$/ms;
ok( defined $default, 'found the default mirror selection in genimage' )
  or done_testing(), exit;

my ($pick) = $src =~ /^\s*(my \$mirror = \(defined \$aptmirror\[0\].*?;)\s*$/ms;
ok( defined $pick, 'found the mirror override in genimage' )
  or done_testing(), exit;

sub choose {
    my ( $uarch, $site ) = @_;
    my $set = defined $site ? "('$site')" : "()";
    ## no critic (BuiltinFunctions::ProhibitStringyEval)
    my $mirror = eval "my \$uarch = '$uarch'; my \@aptmirror = $set; $default $pick \$mirror";
    ## use critic
    die "failed to evaluate the genimage mirror selection: $@" if $@;
    return $mirror;
}

is( choose('riscv64'), 'http://ports.ubuntu.com/ubuntu-ports',
    'a riscv64 image takes the ports archive' );
is( choose('ppc64el'), 'http://ports.ubuntu.com/ubuntu-ports',
    'a ppc64el image takes the ports archive' );
is( choose('amd64'), 'http://archive.ubuntu.com/ubuntu',
    'an amd64 image keeps the main archive' );
is( choose('i386'), 'http://archive.ubuntu.com/ubuntu',
    'an i386 image keeps the main archive' );

is( choose( 'riscv64', 'http://mirror.example.invalid/ubuntu' ),
    'http://mirror.example.invalid/ubuntu',
    'site.ubuntu_apt_mirror overrides the ports archive' );
is( choose( 'amd64', 'http://mirror.example.invalid/ubuntu' ),
    'http://mirror.example.invalid/ubuntu',
    'site.ubuntu_apt_mirror overrides the main archive' );
is( choose( 'riscv64', '' ), 'http://ports.ubuntu.com/ubuntu-ports',
    'an empty site.ubuntu_apt_mirror does not blank the mirror' );

done_testing();
