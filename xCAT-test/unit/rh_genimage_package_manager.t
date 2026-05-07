#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );

sub read_file {
    my ($file) = @_;
    my $path = File::Spec->catfile( $repo_root, $file );

    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh);

    return $contents;
}

my $genimage = read_file('xCAT-server/share/xcat/netboot/rh/genimage');

like( $genimage, qr/sub el_major_version/, 'RH genimage has an EL major-version helper' );
like( $genimage, qr/sub rpm_installroot_command/, 'RH genimage builds RPM installroot commands through one helper' );
like( $genimage, qr/-x "\/usr\/bin\/dnf".*?\$pkgmgr = "dnf"/s, 'EL8+ genimage prefers dnf when it is available' );
like( $genimage, qr/--releasever=.*?--setopt=module_platform_id=platform:el/s, 'EL8+ installroot commands keep releasever and module platform options' );
like( $genimage, qr/my \$yumcmd = rpm_installroot_command\(\$non_interactive\);/, 'base package pass uses shared installroot command builder' );
like( $genimage, qr/my \$yumcmd_base = rpm_installroot_command\(\$non_interactive\);/, 'otherpkgs pass uses shared installroot command builder' );
unlike( $genimage, qr/my \$yumcmd(?:_base)? = "yum /, 'RH genimage no longer hardcodes yum in installroot command builders' );

done_testing();
