#!/usr/bin/env perl
use strict;
use warnings;

use Digest::MD5 qw(md5_hex);
use File::Spec;
use FindBin;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );

sub read_file {
    my ($path) = @_;
    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    binmode($fh);
    my $contents = do { local $/; <$fh> };
    close($fh);
    return $contents;
}

my $deb_install = read_file(
    File::Spec->catfile( $repo_root, 'xCAT-server', 'debian', 'install' )
);
my $dpkg_managed =
  $deb_install =~ qr{^etc/init\.d/xcatd etc/init\.d$}m;
my $ucf_managed =
  $deb_install =~ qr{^etc/init\.d/xcatd opt/xcat/share/xcat/scripts$}m;

ok( $dpkg_managed || $ucf_managed,
    'Debian selects a configuration-aware legacy init backend' );

if ($dpkg_managed) {
    pass('dpkg owns the directly packaged legacy init conffile');
    done_testing();
    exit;
}

my $deb_control = read_file(
    File::Spec->catfile( $repo_root, 'xCAT-server', 'debian', 'control' )
);
like( $deb_control, qr{^Depends:.*(?:,\s+|^)ucf(?:,|$)}m,
    'the generated-conffile backend depends on ucf' );
like( $deb_install,
    qr{^debian/xcatd\.md5sum opt/xcat/share/xcat/scripts$}m,
    'historical template checksums are installed beside the template' );

my $sum_path = File::Spec->catfile(
    $repo_root, 'xCAT-server', 'debian', 'xcatd.md5sum'
);
ok( -f $sum_path, 'the Debian package carries historical template checksums' );
my $sums = -f $sum_path ? read_file($sum_path) : '';
like( $sums, qr{^0b1eea60994ff79faa9a8d0bcd53c558\s+2\.17\.0$}m,
    'the last pre-transition release is recognized as unmodified' );

my $template = read_file(
    File::Spec->catfile(
        $repo_root, 'xCAT-server', 'etc', 'init.d', 'xcatd'
    )
);
like( $sums, qr{^\Q@{[ md5_hex($template) ]}\E\s+2\.18\.0$}m,
    'the current released template is recognized as unmodified' );

my $postinst = read_file(
    File::Spec->catfile( $repo_root, 'xCAT-server', 'debian', 'postinst' )
);
like( $postinst,
    qr{"\$xcatd_init_state" configure-legacy "\$xcatd_transition_context"},
    'postinst delegates legacy conffile transitions to the state helper' );

my $state_helper = read_file(
    File::Spec->catfile( $repo_root, 'xCAT-server', 'debian', 'xcatd-init-state' )
);
like( $state_helper, qr{ucf "\$legacy_template" "\$legacy_init"},
    'legacy configuration delegates updates to ucf' );
like( $state_helper, qr{ucfr xcat-server "\$legacy_init"},
    'legacy configuration registers ucf ownership' );
like( $state_helper, qr{state_content=stashed.*?stash_candidate}s,
    'a present legacy script is represented by an exact stash' );
like( $state_helper, qr{state_content=deleted},
    'administrator deletion has a distinct persistent state' );
like( $state_helper,
    qr{package-default\).*?UCF_FORCE_CONFFMISS=1 ucf}s,
    'only known package omission forces recreation of a missing script' );
like( $state_helper,
    qr{state_content=unknown.*?preserving its absence}s,
    'ambiguous markerless upgrades preserve absence instead of guessing' );

my $postrm = read_file(
    File::Spec->catfile( $repo_root, 'xCAT-server', 'debian', 'postrm' )
);
like( $postrm,
    qr{xcatd\.ucf-old.*?xcatd\.ucf-new.*?xcatd\.ucf-dist}s,
    'purge removes ucf backup artifacts' );
like( $postrm, qr{ucf --purge /etc/init\.d/xcatd},
    'purge removes ucf checksum state' );
like( $postrm, qr{ucfr --purge xcat-server /etc/init\.d/xcatd},
    'purge removes the ucf ownership registration' );
like( $postrm,
    qr{xcatd_state_dir=/var/lib/xcat/xcatd-init-state.*?(?:/var/lib/xcat/xcatd-init-state/state|"\$xcatd_state_dir/state")}s,
    'purge removes the persistent init transition state' );

done_testing();
