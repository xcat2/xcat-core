#!/usr/bin/env perl
use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage)

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Spec;
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use Test::More;

use XCAT::Test::File qw(repo_path slurp_repo_file);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);
plan skip_all => 'postinstall execution requires Linux' unless $^O eq 'linux';
my $database = tempdir(CLEANUP => 1);
$ENV{XCATROOT} = repo_path('xCAT-server');
$ENV{XCATCFG} = "SQLite:$database";
require xCAT::SvrUtils;

my $share_relative = File::Spec->catdir( 'xCAT-server', 'share', 'xcat' );
my $share = repo_path($share_relative);
my $imgutils_relative = File::Spec->catfile(
    $share_relative, 'netboot', 'imgutils', 'imgutils.pm'
);
my $imgutils = repo_path($imgutils_relative);
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

        my $postinstall = imgutils::get_profile_def_filename($osver, $profile, 'riscv64', $base, 'postinstall');
        for my $mode (qw(enforcing disabled absent)) {
            subtest "$osver $profile SELinux $mode" => sub {
                my $root = sandbox_root();
                my $image = "$root/target";
                make_path("$image/etc/selinux", "$root/etc/selinux");
                write_text("$root/etc/fstab", "host fstab\n");
                write_text("$root/etc/selinux/config", "SELINUX=enforcing\n# host policy\n");
                write_text("$image/etc/fstab", "obsolete\n");
                write_text("$image/etc/selinux/config", "SELINUX=$mode\nSELINUXTYPE=targeted\n")
                    unless $mode eq 'absent';
                for my $pass (1, 2) {
                    my ($status, $output) = sandbox_run($root,
                        {read_only => {repo_path('.') => repo_path('.')}},
                        $postinstall, '/target', $osver, 'riscv64', $profile, $base);
                    is($status, 0, "pass $pass executes the selected script") or diag($output);
                    is(read_text("$root/etc/fstab"), "host fstab\n", "pass $pass leaves the host fstab unchanged");
                    is(read_text("$root/etc/selinux/config"), "SELINUX=enforcing\n# host policy\n", "pass $pass leaves host SELinux unchanged");
                    if ($mode eq 'absent') {
                        ok(!-e "$image/etc/selinux/config", "pass $pass leaves absent SELinux configuration absent");
                    } else {
                        is(read_text("$image/etc/selinux/config"), "SELINUX=disabled\nSELINUXTYPE=targeted\n",
                            "pass $pass disables SELinux without changing the policy type");
                    }
                    my @mounts = map { [split /\s+/] } grep { /\S/ } split /\n/, read_text("$image/etc/fstab");
                    is_deeply(\@mounts, [
                        [qw(proc /proc proc rw 0 0)],
                        [qw(sysfs /sys sysfs rw 0 0)],
                        ['devpts', '/dev/pts', 'devpts', 'rw,gid=5,mode=620', 0, 0],
                    ], "pass $pass writes the diskless virtual filesystems once");
                }
            };
        }
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
