#!/usr/bin/env perl
use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage)

use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Spec;
use Test::More;

use XCAT::Test::File qw(repo_path slurp_repo_file);

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

my $share_relative = File::Spec->catdir( 'xCAT-server', 'share', 'xcat' );
my $share = repo_path($share_relative);
my $imgutils_relative = File::Spec->catfile(
    $share_relative, 'netboot', 'imgutils', 'imgutils.pm'
);
my $imgutils = repo_path($imgutils_relative);
plan skip_all => "$imgutils not found" unless -r $imgutils;
require $imgutils;

my @families = (
    [ 'rocky', 'rocky10', 'rocky10.2' ],
    [ 'rh',    'rhels10', 'rhels10.2' ],
);

for my $family (@families) {
    my ( $dir, $osbase, $osver ) = @$family;
    my $base_relative = File::Spec->catdir( $share_relative, 'netboot', $dir );
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
        my $x86 = slurp_repo_file(
            File::Spec->catfile( $base_relative, "$profile.$osbase.x86_64.pkglist" )
        );
        my $rv = slurp_repo_file(
            File::Spec->catfile( $base_relative, "$profile.$osbase.riscv64.pkglist" )
        );
        s/\s+\z/\n/ for ( $x86, $rv );
        is( $rv, $x86, "$dir/$profile.$osbase riscv64 pkglist matches the x86_64 list (no arch-specific packages)" );
        unlike( $rv, qr/^(?:microcode_ctl|grub2-efi-x64|shim-x64|syslinux|xnba)/m, "$dir/$profile.$osbase riscv64 pkglist has no x86-only packages" );

        my $exlist = slurp_repo_file(
            File::Spec->catfile( $base_relative, "$profile.$osbase.riscv64.exlist" )
        );
        like( $exlist, qr{^\./lib/kbd/keymaps/include\*$}m, "$dir/$profile.$osbase riscv64 exlist excludes the kbd keymap includes" );
        unlike( $exlist, qr{^\./lib/kdb/}m, "$dir/$profile.$osbase riscv64 exlist has no kdb typo" );
        is( scalar( () = $exlist =~ m{^\./usr/share/man\*$}mg ), 1, "$dir/$profile.$osbase riscv64 exlist lists usr/share/man once" );

        my $postinstall = slurp_repo_file(
            File::Spec->catfile( $base_relative, "$profile.$osbase.riscv64.postinstall" )
        );
        like( $postinstall, qr/^#!\/bin\/sh/, "$dir/$profile.$osbase riscv64 postinstall is a shell script" );
        like( $postinstall, qr/SELINUX=disabled/, "$dir/$profile.$osbase riscv64 postinstall disables SELinux in the image" );
    }

    my $otherpkgs = File::Spec->catfile( $base, "service.$osbase.riscv64.otherpkgs.pkglist" );
    my $otherpkgs_relative = File::Spec->catfile(
        $base_relative, "service.$osbase.riscv64.otherpkgs.pkglist"
    );
    is(
        imgutils::get_profile_def_filename( $osver, 'service', 'riscv64', $base, 'otherpkgs.pkglist' ),
        $otherpkgs,
        "$osver riscv64 service otherpkgs resolves to the riscv64 file",
    );
    like( slurp_repo_file($otherpkgs_relative), qr{^xcat/xcat-dep/rh10/riscv64/goconserver$}m, "$dir netboot service otherpkgs pulls goconserver from the riscv64 EL10 dep repo" );

    my $install_otherpkgs_relative = File::Spec->catfile(
        $share_relative, 'install', $dir,
        "service.$osbase.riscv64.otherpkgs.pkglist"
    );
    my $install_otherpkgs = repo_path($install_otherpkgs_relative);
    ok( -r $install_otherpkgs, "install/$dir/service.$osbase.riscv64.otherpkgs.pkglist exists" );
    like( slurp_repo_file($install_otherpkgs_relative), qr{^xcat/xcat-dep/rh10/riscv64/goconserver$}m, "$dir install service otherpkgs pulls goconserver from the riscv64 EL10 dep repo" );
    like( slurp_repo_file($install_otherpkgs_relative), qr{^xcat/xcat-core/xCATsn$}m, "$dir install service otherpkgs installs xCATsn" );
}

# an architecture without its own files still falls back to the arch-less ones
my $rocky_base = File::Spec->catdir( $share, 'netboot', 'rocky' );
is(
    imgutils::get_profile_def_filename( 'rocky10.2', 'compute', 'riscv32', $rocky_base, 'pkglist' ),
    File::Spec->catfile( $rocky_base, 'compute.pkglist' ),
    'an unknown architecture falls back to the arch-less compute pkglist',
);

done_testing();
