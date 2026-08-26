#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path slurp_repo_file);

# EL10 riscv64 kickstart installs: the EL10 anaconda has no RISC-V EFI
# platform, so the riscv64 templates tolerate its x86 boot loader package
# request, pull grub2-efi-riscv64/efibootmgr in through the riscv64 package
# lists, and run a %post that points the UEFI boot entry at grubriscv64.efi
# and places the removable-media fallback loader.

my $install = File::Spec->catdir( 'xCAT-server', 'share', 'xcat', 'install' );

for my $family ( [ 'rocky', 'rocky10' ], [ 'rh', 'rhels10' ] ) {
    my ( $dir, $osbase ) = @$family;
    for my $profile (qw(compute service)) {
        my $tmpl    = File::Spec->catfile( $install, $dir, "$profile.$osbase.riscv64.tmpl" );
        my $pkglist = File::Spec->catfile( $install, $dir, "$profile.$osbase.riscv64.pkglist" );
        my $base    = File::Spec->catfile( $install, $dir, "$profile.$osbase.tmpl" );
        ok( -r repo_path($tmpl),    "$dir/$profile.$osbase.riscv64.tmpl exists" );
        ok( -r repo_path($pkglist), "$dir/$profile.$osbase.riscv64.pkglist exists" );
        my $t = slurp_repo_file($tmpl);
        like( $t, qr/^%packages --ignoremissing$/m, "$dir/$profile.$osbase riscv64 template tolerates anaconda's x86 boot loader package request" );
        like( $t, qr/^#INCLUDE_DEFAULT_PKGLIST#$/m, "$dir/$profile.$osbase riscv64 template still includes the default package list" );
        like( $t, qr{^#INCLUDE:#ENV:XCATROOT#/share/xcat/install/scripts/post\.rhels10\.riscv64#$}m, "$dir/$profile.$osbase riscv64 template runs the riscv64 UEFI boot entry fix-up" );
        like( $t, qr/^%addon com_redhat_kdump --disable\n%end$/m, "$dir/$profile.$osbase riscv64 template keeps the installer from writing a crash kernel reservation EL10 riscv64 cannot honour" );
        like( $t, qr/^%post --erroronfail --interpreter=\/bin\/bash$/m, "$dir/$profile.$osbase riscv64 template fails the install when no boot loader reached the ESP" );
        like( $t, qr{/boot/efi/EFI/BOOT/BOOTRISCV64\.EFI}, "$dir/$profile.$osbase riscv64 template checks the removable-media loader" );
        like( $t, qr{/boot/efi/EFI/\*/grubriscv64\.efi}, "$dir/$profile.$osbase riscv64 template also accepts a vendor directory loader" );
        like( $t, qr/^rootpw --iscrypted #CRYPT:passwd:key=system,username=root:password#$/m, "$dir/$profile.$osbase riscv64 template keeps the shared root password directive" );

        # the riscv64 template is the shared one plus the riscv64 changes
        my $b = slurp_repo_file($base);
        ( my $t_norm = $t ) =~ s/^# riscv64:.*\n(?:#.*\n)*%addon com_redhat_kdump --disable\n%end\n\n//m;
        $t_norm =~ s/^# riscv64:.*\n(?:#.*\n)*//m;
        $t_norm =~ s/^%packages --ignoremissing$/%packages/m;
        $t_norm =~ s{^#INCLUDE:#ENV:XCATROOT#/share/xcat/install/scripts/post\.rhels10\.riscv64#\n}{}m;
        $t_norm =~ s/\n# --ignoremissing above.*?\n%post --erroronfail.*?\n%end\n//s;
        is( $t_norm, $b, "$dir/$profile.$osbase riscv64 template only differs from the shared template in the riscv64 changes" );

        my $p = slurp_repo_file($pkglist);
        like( $p, qr/^grub2-efi-riscv64$/m, "$dir/$profile.$osbase riscv64 package list installs grub2-efi-riscv64" );
        like( $p, qr/^efibootmgr$/m,        "$dir/$profile.$osbase riscv64 package list installs efibootmgr" );
        unlike( $p, qr/shim|grub2-efi-x64|grub2-efi-aa64/, "$dir/$profile.$osbase riscv64 package list asks for no other architecture's boot loader" );
        my $shared = slurp_repo_file(
            File::Spec->catfile( $install, $dir, "$profile.$osbase.pkglist" )
        );
        ( my $p_norm = $p ) =~ s/^grub2-efi-riscv64\n//m;
        $p_norm =~ s/^efibootmgr\n//m;
        s/\s+\z/\n/ for ( $p_norm, $shared );
        is( $p_norm, $shared, "$dir/$profile.$osbase riscv64 package list is the shared list plus the boot loader packages" );
    }
}

my $post = File::Spec->catfile( $install, 'scripts', 'post.rhels10.riscv64' );
my $post_path = repo_path($post);
ok( -r $post_path, 'post.rhels10.riscv64 exists' );

is(system('sh', '-n', $post_path), 0, 'post.rhels10.riscv64 parses as POSIX shell');

my $tools = tempdir(CLEANUP => 1);
my $efi_log = File::Spec->catfile($tools, 'efibootmgr.log');

sub fake_command {
    my ($name, $body) = @_;
    my $path = File::Spec->catfile($tools, $name);
    write_text($path, "#!/bin/sh\n$body");
    chmod 0755, $path or die "Unable to make $path executable: $!";
    return $path;
}

my $uname = fake_command('uname', <<'SH');
printf '%s\n' "${XCAT_TEST_ARCH:-riscv64}"
SH
my $findmnt = fake_command('findmnt', <<'SH');
printf '/dev/vda1\n'
SH
my $lsblk = fake_command('lsblk', <<'SH');
case "$*" in
    *PKNAME*) printf "vda\n" ;;
    *PARTN*) printf "1\n" ;;
esac
SH
my $efibootmgr = fake_command('efibootmgr', <<'SH');
printf '%s\n' "$*" >> "$XCAT_EFI_LOG"
case "$*" in
    '') exit 0 ;;
    '-v')
        printf 'Boot0001* Rocky HD(1,GPT,...)/File(\\EFI\\rocky\\shimx64.efi)\n'
        printf 'Boot0002* OldRiscv HD(1,GPT,...)/File(\\EFI\\rocky\\grubriscv64.efi)\n'
        printf 'Boot0003* Network PXE\n'
        exit 0
        ;;
    *'-c'*) exit "${XCAT_EFI_CREATE_RC:-0}" ;;
esac
exit 0
SH

sub installed_root {
    my ($with_loader) = @_;
    my $root = tempdir(CLEANUP => 1);
    make_path(File::Spec->catdir($root, 'boot', 'efi', 'EFI', 'rocky'));
    make_path(File::Spec->catdir($root, 'etc'));
    write_text(File::Spec->catfile($root, 'etc', 'os-release'), "NAME=\"Rocky Linux\"\n");
    if ($with_loader) {
        write_text(
            File::Spec->catfile($root, 'boot', 'efi', 'EFI', 'rocky', 'grubriscv64.efi'),
            "riscv loader\n",
        );
    }
    return $root;
}

sub run_post {
    my ($root, %extra) = @_;
    local %ENV = (
        %ENV,
        XCAT_INSTALL_ROOT => $root,
        XCAT_UNAME         => $uname,
        XCAT_EFIBOOTMGR    => $efibootmgr,
        XCAT_FINDMNT       => $findmnt,
        XCAT_LSBLK         => $lsblk,
        XCAT_EFI_LOG       => $efi_log,
        XCAT_TEST_ARCH     => 'riscv64',
        %extra,
    );
    open(my $fh, '-|', 'sh', $post_path) or die "Unable to run $post_path: $!";
    my $output = do { local $/; <$fh> };
    close($fh);
    return ($? >> 8, $output);
}

my $root = installed_root(1);
my ($status, $output) = run_post($root);
is($status, 0, 'the RISC-V fix-up completes successfully');
is(
    read_text(File::Spec->catfile($root, 'boot', 'efi', 'EFI', 'BOOT', 'BOOTRISCV64.EFI')),
    "riscv loader\n",
    'the distro loader is copied to the removable-media fallback path',
);
like($output, qr/UEFI boot entry "Rocky Linux"/, 'the created UEFI entry is reported');
my $efi_calls = read_text($efi_log);
like($efi_calls, qr/^-q -b 0001 -B$/m, 'the invalid x86 boot entry is removed');
like($efi_calls, qr/^-q -b 0002 -B$/m, 'the prior RISC-V boot entry is removed');
unlike($efi_calls, qr/0003/, 'unrelated firmware entries are retained');
like(
    $efi_calls,
    qr/^-q -c -d \/dev\/vda -p 1 -L Rocky Linux -l \\EFI\\rocky\\grubriscv64\.efi$/m,
    'the new entry points at the distro RISC-V loader on the ESP disk',
);

unlink($efi_log);
my $x86_root = installed_root(1);
($status, $output) = run_post($x86_root, XCAT_TEST_ARCH => 'x86_64');
is($status, 0, 'the post-install script is a no-op on x86_64');
is($output, '', 'the x86_64 no-op reports nothing');
ok(!-e $efi_log, 'the x86_64 no-op never invokes efibootmgr');

my $bare_root = installed_root(0);
($status, $output) = run_post($bare_root);
is($status, 0, 'a missing distro loader remains nonfatal');
like($output, qr/no \\EFI\\\*\\grubriscv64\.efi/, 'a missing distro loader is diagnosed');

unlink($efi_log);
($status, $output) = run_post($root, XCAT_EFI_CREATE_RC => 1);
is($status, 0, 'an efibootmgr create failure remains nonfatal');
like($output, qr/firmware will use \\EFI\\BOOT\\BOOTRISCV64\.EFI/, 'the fallback path is reported after an efibootmgr failure');

done_testing();
