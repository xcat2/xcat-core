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

my $debian_pm = read_file('xCAT-server/lib/xcat/plugins/debian.pm');
like( $debian_pm, qr/sub is_ubuntu_live_media/, 'copycds can detect Ubuntu live media' );
like( $debian_pm, qr/casper\/install-sources\.yaml/, 'copycds recognizes Subiquity install source metadata' );
like( $debian_pm, qr/casper\/\*\.squashfs/, 'copycds recognizes live squashfs media' );
like( $debian_pm, qr/not a complete Ubuntu apt package mirror/, 'copycds warns that Ubuntu live media is not a complete apt mirror' );
like( $debian_pm, qr/linuximage\.pkgdir.*linuximage\.otherpkgdir.*HTTP\/HTTPS Ubuntu apt repository/s, 'copycds warning points to explicit package source attributes' );

my $genimage = read_file('xCAT-server/share/xcat/netboot/ubuntu/genimage');
unlike( $genimage, qr{http://archive\.ubuntu\.com/ubuntu/}, 'Ubuntu genimage does not implicitly use the public amd64 archive' );
unlike( $genimage, qr{http://ports\.ubuntu\.com/ubuntu-ports/}, 'Ubuntu genimage does not implicitly use the public ports archive' );
like( $genimage, qr{\$aptcmd2 = "--verbose --arch \$uarch \$dist \$rootimg_dir file://\$srcdir"}, 'Ubuntu genimage uses copied local media when no explicit mirror is configured' );
like( $genimage, qr/copied Ubuntu media.*complete local Ubuntu apt mirror.*HTTP\/HTTPS Ubuntu apt repository/s, 'Ubuntu genimage gives an actionable package source error' );
like( $genimage, qr{\@pkgdir_internet.*?\$aptcmd2 = "--verbose --arch \$uarch \$dist \$rootimg_dir \$mirrorurl"}s, 'Ubuntu genimage still honors an explicit mirror configured in pkgdir' );

my $copycds_doc = read_file('docs/source/guides/admin-guides/references/man8/copycds.8.rst');
like( $copycds_doc, qr/Ubuntu live-server media.*not a complete Ubuntu apt package mirror/s, 'copycds documentation explains Ubuntu live media package limits' );

my $linuximage_doc = read_file('docs/source/guides/admin-guides/references/man5/linuximage.5.rst');
like( $linuximage_doc, qr/Ubuntu live-server media copied by copycds is not a complete apt package mirror.*HTTP\/HTTPS Ubuntu apt repository/, 'linuximage documentation explains Ubuntu live media package limits' );

my $osimage_doc = read_file('docs/source/guides/admin-guides/references/man7/osimage.7.rst');
like( $osimage_doc, qr/Ubuntu live-server media copied by copycds is not a complete apt package mirror.*HTTP\/HTTPS Ubuntu apt repository/, 'osimage documentation explains Ubuntu live media package limits' );

done_testing();
