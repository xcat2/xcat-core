#!/usr/bin/env perl
use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage)

use FindBin;
use File::Spec;
use Cwd qw(realpath);
use Test::More;

# EL10 riscv64 diskless and service profiles are plain data files resolved by
# imgutils::get_profile_def_filename (osver.arch first, then osbase.arch, then
# the arch-less fallbacks). Pin that the riscv64 files exist, win the lookup
# for rocky10/rhels10 point releases, and carry the right content.

BEGIN {
    # imgutils pulls in xCAT::SvrUtils only for the OS search list; emulate
    # the point-release walk (rocky10.2 -> rocky10.2, rocky10.1, ..., rocky10,
    # rocky) without the database-backed module.
    package xCAT::SvrUtils;
    sub get_os_search_list {
        my ($os) = @_;
        my @word = split( /\./, $os );
        my @list;
        while ( @word && $word[-1] =~ /^[0-9]+$/ ) {
            my $last = pop @word;
            while ( $last >= 0 ) {
                push @list, join( '.', @word, $last );
                $last--;
            }
        }
        push @list, join( '.', @word );
        return @list;
    }
    $INC{'xCAT/SvrUtils.pm'} = __FILE__;
}

my $repo_root = realpath( File::Spec->catdir( $FindBin::Bin, '..', '..' ) );
my $share     = File::Spec->catdir( $repo_root, 'xCAT-server', 'share', 'xcat' );
my $imgutils  = File::Spec->catfile( $share, 'netboot', 'imgutils', 'imgutils.pm' );
plan skip_all => "$imgutils not found" unless -r $imgutils;
require $imgutils;

sub slurp {
    my ($path) = @_;
    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    my $content = do { local $/; <$fh> };
    close($fh);
    return $content;
}

my @families = (
    [ 'rocky', 'rocky10', 'rocky10.2' ],
    [ 'rh',    'rhels10', 'rhels10.2' ],
);

for my $family (@families) {
    my ( $dir, $osbase, $osver ) = @$family;
    my $base = File::Spec->catdir( $share, 'netboot', $dir );

    for my $profile (qw(compute service)) {
        for my $ext (qw(pkglist exlist postinstall)) {
            my $expected = File::Spec->catfile( $base, "$profile.$osbase.riscv64.$ext" );
            ok( -r $expected, "$dir/$profile.$osbase.riscv64.$ext exists" );
            is(
                imgutils::get_profile_def_filename( $osver, $profile, 'riscv64', $base, $ext ),
                $expected,
                "$osver riscv64 $profile $ext resolves to the riscv64 file",
            );
        }
        my $x86 = slurp( File::Spec->catfile( $base, "$profile.$osbase.x86_64.pkglist" ) );
        my $rv  = slurp( File::Spec->catfile( $base, "$profile.$osbase.riscv64.pkglist" ) );
        s/\s+\z/\n/ for ( $x86, $rv );
        is( $rv, $x86, "$dir/$profile.$osbase riscv64 pkglist matches the x86_64 list (no arch-specific packages)" );
        unlike( $rv, qr/^(?:microcode_ctl|grub2-efi-x64|shim-x64|syslinux|xnba)/m, "$dir/$profile.$osbase riscv64 pkglist has no x86-only packages" );

        my $exlist = slurp( File::Spec->catfile( $base, "$profile.$osbase.riscv64.exlist" ) );
        like( $exlist, qr{^\./lib/kbd/keymaps/include\*$}m, "$dir/$profile.$osbase riscv64 exlist excludes the kbd keymap includes" );
        unlike( $exlist, qr{^\./lib/kdb/}m, "$dir/$profile.$osbase riscv64 exlist has no kdb typo" );
        is( scalar( () = $exlist =~ m{^\./usr/share/man\*$}mg ), 1, "$dir/$profile.$osbase riscv64 exlist lists usr/share/man once" );

        my $postinstall = slurp( File::Spec->catfile( $base, "$profile.$osbase.riscv64.postinstall" ) );
        like( $postinstall, qr/^#!\/bin\/sh/, "$dir/$profile.$osbase riscv64 postinstall is a shell script" );
        like( $postinstall, qr/SELINUX=disabled/, "$dir/$profile.$osbase riscv64 postinstall disables SELinux in the image" );
    }

    my $otherpkgs = File::Spec->catfile( $base, "service.$osbase.riscv64.otherpkgs.pkglist" );
    is(
        imgutils::get_profile_def_filename( $osver, 'service', 'riscv64', $base, 'otherpkgs.pkglist' ),
        $otherpkgs,
        "$osver riscv64 service otherpkgs resolves to the riscv64 file",
    );
    like( slurp($otherpkgs), qr{^xcat/xcat-dep/rh10/riscv64/goconserver$}m, "$dir netboot service otherpkgs pulls goconserver from the riscv64 EL10 dep repo" );

    my $install_otherpkgs = File::Spec->catfile( $share, 'install', $dir, "service.$osbase.riscv64.otherpkgs.pkglist" );
    ok( -r $install_otherpkgs, "install/$dir/service.$osbase.riscv64.otherpkgs.pkglist exists" );
    like( slurp($install_otherpkgs), qr{^xcat/xcat-dep/rh10/riscv64/goconserver$}m, "$dir install service otherpkgs pulls goconserver from the riscv64 EL10 dep repo" );
    like( slurp($install_otherpkgs), qr{^xcat/xcat-core/xCATsn$}m, "$dir install service otherpkgs installs xCATsn" );
}

# an architecture without its own files still falls back to the arch-less ones
my $rocky_base = File::Spec->catdir( $share, 'netboot', 'rocky' );
is(
    imgutils::get_profile_def_filename( 'rocky10.2', 'compute', 'riscv32', $rocky_base, 'pkglist' ),
    File::Spec->catfile( $rocky_base, 'compute.pkglist' ),
    'an unknown architecture falls back to the arch-less compute pkglist',
);

done_testing();
