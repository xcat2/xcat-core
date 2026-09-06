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
use lib "$FindBin::Bin/../../perl-xCAT";
require xCAT::Utils;
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

# genimage does not read osimage.osarch directly: it converts it first, so the value the selection
# sees is whatever xCAT::Utils::debian_arch returns. Driving the xCAT token through that conversion
# is what catches a token the map does not know.
sub choose_osarch {
    my ( $osarch, $site ) = @_;
    return choose( xCAT::Utils->debian_arch($osarch), $site );
}

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

# The architecture reaches the selection as an xCAT osarch value, not as a Debian one.
is( choose_osarch('x86_64'), 'http://archive.ubuntu.com/ubuntu',
    'osarch x86_64 reaches the archive' );
is( choose_osarch('x86'), 'http://archive.ubuntu.com/ubuntu',
    'osarch x86 reaches the archive, which is where i386 lives' );
is( choose_osarch('riscv64'), 'http://ports.ubuntu.com/ubuntu-ports',
    'osarch riscv64 reaches the ports archive' );
is( choose_osarch('ppc64el'), 'http://ports.ubuntu.com/ubuntu-ports',
    'osarch ppc64el reaches the ports archive' );

done_testing();
