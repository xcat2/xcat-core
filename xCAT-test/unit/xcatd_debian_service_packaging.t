#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );

sub read_file {
    my ($path) = @_;
    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh);
    return $contents;
}

my $deb_install = read_file(
    File::Spec->catfile( $repo_root, 'xCAT-server', 'debian', 'install' )
);
like( $deb_install, qr{^etc/init\.d/xcatd opt/xcat/share/xcat/scripts$}m,
    'Debian stages the legacy script as a compatibility template' );
unlike( $deb_install, qr{^etc/init\.d/xcatd etc/init\.d$}m,
    'Debian does not install the legacy script directly' );

my $deb_dirs = read_file(
    File::Spec->catfile( $repo_root, 'xCAT-server', 'debian', 'dirs' )
);
unlike( $deb_dirs, qr{^etc/init\.d/?$}m,
    'Debian does not package an empty legacy init directory' );

foreach my $maintainer_script (qw(preinst postinst postrm)) {
    my $script = read_file(
        File::Spec->catfile(
            $repo_root, 'xCAT-server', 'debian', $maintainer_script
        )
    );
    like( $script,
        qr{dpkg-maintscript-helper rm_conffile /etc/init\.d/xcatd -- "\$\@"},
        "Debian $maintainer_script participates in graceful conffile removal" );
}

my $deb_postinst = read_file(
    File::Spec->catfile( $repo_root, 'xCAT-server', 'debian', 'postinst' )
);
like( $deb_postinst,
    qr{if "\$xcatd_init_compat" uses-systemd(?: --explicit-target)?; then},
    'Debian postinst delegates target init detection to the packaged helper' );
unlike( $deb_postinst, qr{sub xcat_target_uses_systemd|xcat_target_uses_systemd\(\)},
    'Debian postinst does not carry weaker duplicate init detection' );
like( $deb_postinst,
    qr{\[ -x /etc/init\.d/xcatd \].*?update-rc\.d xcatd defaults}s,
    'Debian postinst registers SysV only after materializing an executable script' );

foreach my $fallback_script (qw(preinst postrm)) {
    my $script = read_file(
        File::Spec->catfile( $repo_root, 'xCAT-server', 'debian', $fallback_script )
    );
    like( $script, qr{VERSION_ID.*?ubuntu.*?-ge 15.*?debian.*?-ge 8}s,
        "Debian $fallback_script recognizes stripped modern targets" );
    like( $script, qr{\[ "\$os_id" = "debian" \].*?\[ -z "\$os_version" \]}s,
        "Debian $fallback_script recognizes testing and sid without VERSION_ID" );
    like( $script, qr{value=\$\{value#\\'\}\s+value=\$\{value%\\'\}}s,
        "Debian $fallback_script strips single-quoted os-release values" );
}

my $deb_prerm = read_file(
    File::Spec->catfile( $repo_root, 'xCAT-server', 'debian', 'prerm' )
);
like( $deb_prerm,
    qr{if "\$xcatd_init_compat" uses-systemd(?: --explicit-target)?; then.*?update-rc\.d -f xcatd remove}s,
    'Debian prerm removes registration through the detected init implementation' );

done_testing();
