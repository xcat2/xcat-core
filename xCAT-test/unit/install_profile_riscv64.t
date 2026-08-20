#!/usr/bin/env perl
use strict;
use warnings;

use Cwd qw(realpath);
use File::Spec;
use FindBin;
use Test::More;

# EL10 riscv64 kickstart installs: the EL10 anaconda has no RISC-V EFI
# platform, so the riscv64 templates tolerate its x86 boot loader package
# request, pull grub2-efi-riscv64/efibootmgr in through the riscv64 package
# lists, and run a %post that points the UEFI boot entry at grubriscv64.efi
# and places the removable-media fallback loader.

my $repo_root = realpath( File::Spec->catdir( $FindBin::Bin, '..', '..' ) );
my $install   = File::Spec->catdir( $repo_root, 'xCAT-server', 'share', 'xcat', 'install' );

sub slurp {
    my ($path) = @_;
    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    my $content = do { local $/; <$fh> };
    close($fh);
    return $content;
}

for my $family ( [ 'rocky', 'rocky10' ], [ 'rh', 'rhels10' ] ) {
    my ( $dir, $osbase ) = @$family;
    for my $profile (qw(compute service)) {
        my $tmpl    = File::Spec->catfile( $install, $dir, "$profile.$osbase.riscv64.tmpl" );
        my $pkglist = File::Spec->catfile( $install, $dir, "$profile.$osbase.riscv64.pkglist" );
        my $base    = File::Spec->catfile( $install, $dir, "$profile.$osbase.tmpl" );
        ok( -r $tmpl,    "$dir/$profile.$osbase.riscv64.tmpl exists" );
        ok( -r $pkglist, "$dir/$profile.$osbase.riscv64.pkglist exists" );
        my $t = slurp($tmpl);
        like( $t, qr/^%packages --ignoremissing$/m, "$dir/$profile.$osbase riscv64 template tolerates anaconda's x86 boot loader package request" );
        like( $t, qr/^#INCLUDE_DEFAULT_PKGLIST#$/m, "$dir/$profile.$osbase riscv64 template still includes the default package list" );
        like( $t, qr{^#INCLUDE:#ENV:XCATROOT#/share/xcat/install/scripts/post\.rhels10\.riscv64#$}m, "$dir/$profile.$osbase riscv64 template runs the riscv64 UEFI boot entry fix-up" );
        like( $t, qr/^%post --erroronfail --interpreter=\/bin\/bash$/m, "$dir/$profile.$osbase riscv64 template fails the install when no boot loader reached the ESP" );
        like( $t, qr{/boot/efi/EFI/BOOT/BOOTRISCV64\.EFI}, "$dir/$profile.$osbase riscv64 template checks the removable-media loader" );
        like( $t, qr{/boot/efi/EFI/\*/grubriscv64\.efi}, "$dir/$profile.$osbase riscv64 template also accepts a vendor directory loader" );
        like( $t, qr/^rootpw --iscrypted #CRYPT:passwd:key=system,username=root:password#$/m, "$dir/$profile.$osbase riscv64 template keeps the shared root password directive" );

        # the riscv64 template is the shared one plus the riscv64 changes
        my $b = slurp($base);
        ( my $t_norm = $t ) =~ s/^# riscv64:.*\n(?:#.*\n)*//m;
        $t_norm =~ s/^%packages --ignoremissing$/%packages/m;
        $t_norm =~ s{^#INCLUDE:#ENV:XCATROOT#/share/xcat/install/scripts/post\.rhels10\.riscv64#\n}{}m;
        $t_norm =~ s/\n# --ignoremissing above.*?\n%post --erroronfail.*?\n%end\n//s;
        is( $t_norm, $b, "$dir/$profile.$osbase riscv64 template only differs from the shared template in the riscv64 changes" );

        my $p = slurp($pkglist);
        like( $p, qr/^grub2-efi-riscv64$/m, "$dir/$profile.$osbase riscv64 package list installs grub2-efi-riscv64" );
        like( $p, qr/^efibootmgr$/m,        "$dir/$profile.$osbase riscv64 package list installs efibootmgr" );
        unlike( $p, qr/shim|grub2-efi-x64|grub2-efi-aa64/, "$dir/$profile.$osbase riscv64 package list asks for no other architecture's boot loader" );
        my $shared = slurp( File::Spec->catfile( $install, $dir, "$profile.$osbase.pkglist" ) );
        ( my $p_norm = $p ) =~ s/^grub2-efi-riscv64\n//m;
        $p_norm =~ s/^efibootmgr\n//m;
        s/\s+\z/\n/ for ( $p_norm, $shared );
        is( $p_norm, $shared, "$dir/$profile.$osbase riscv64 package list is the shared list plus the boot loader packages" );
    }
}

# The kickstart %post is a single shell script: xCAT splices every #INCLUDE: inline, so a
# top-level "exit" in an earlier included script ends the whole section. The riscv64 boot
# entry fix-up must run, so it has to come before any script that exits.
for my $family ( [ 'rocky', 'rocky10' ], [ 'rh', 'rhels10' ] ) {
    my ( $dir, $osbase ) = @$family;
    for my $profile (qw(compute service)) {
        my $t = slurp( File::Spec->catfile( $install, $dir, "$profile.$osbase.riscv64.tmpl" ) );
        my ($section) = $t =~ /^(%post\b.*?)^%end/ms;
        ok( $section, "$dir/$profile.$osbase riscv64 template has a %post section" )
          or next;
        my @scripts = $section =~ m{^#INCLUDE:\#ENV:XCATROOT\#/share/xcat/install/scripts/(\S+?)\#$}mg;
        my ($index) = grep { $scripts[$_] eq 'post.rhels10.riscv64' } 0 .. $#scripts;
        ok( defined $index, "$dir/$profile.$osbase riscv64 template includes the fix-up in the %post section" )
          or next;
        for my $earlier ( @scripts[ 0 .. $index - 1 ] ) {
            my $body = slurp( File::Spec->catfile( $install, 'scripts', $earlier ) );
            unlike( $body, qr/^\s*exit\b/m,
                "$dir/$profile.$osbase runs $earlier before the riscv64 fix-up, and $earlier does not end the %post" );
        }
    }
}

my $post = File::Spec->catfile( $install, 'scripts', 'post.rhels10.riscv64' );
ok( -r $post, 'post.rhels10.riscv64 exists' );
my $bash = `bash -n $post 2>&1`;
is( $bash, '', 'post.rhels10.riscv64 parses as bash' );
my $s = slurp($post);
like( $s, qr/\[ "\$\(uname -m\)" = "riscv64" \]/, 'the fix-up only acts on riscv64' );
like( $s, qr{/boot/efi/EFI/\*/grubriscv64\.efi}, 'the fix-up locates the distro grub2 UEFI image on the ESP' );
like( $s, qr{cp -f "\$grubefi" /boot/efi/EFI/BOOT/BOOTRISCV64\.EFI}, 'the fix-up installs the removable-media fallback loader' );
like( $s, qr/shimx64\|grubx64\|grubriscv64/, 'the fix-up removes the x86 boot entries anaconda registered and the riscv64 entry of an earlier install' );
like( $s, qr/efibootmgr -q -c -d "\/dev\/\$disk" -p "\$part" -L "\$label" -l "\\\\EFI\\\\\$vendordir\\\\grubriscv64\.efi"/, 'the fix-up registers grubriscv64.efi as the boot entry' );
unlike( $s, qr/set -e/, 'the fix-up never aborts the kickstart %post' );

done_testing();
