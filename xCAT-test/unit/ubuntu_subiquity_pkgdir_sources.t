#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use File::Temp;
use FindBin;
use Test::More;

# ospkgs installs the pkglist from every pkgdir entry, the media first and the mirrors after it,
# and the Subiquity autoinstall now installs the pkglist too, so the installer must be given the
# same mirrors. The specs are derived from the pkgdir value alone, and the apt configuration is
# rendered for real with only the database readers stubbed.

my $repo = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..', '..' ) );
my @incs = ( "$repo/perl-xCAT", "$repo/xCAT-server/lib/perl" );
my $devnull = File::Spec->devnull();
my $probe = join( ' ', $^X, ( map { "-I$_" } @incs ), '-e', "'require xCAT::Template; 1'", ">$devnull", "2>&1" );
plan skip_all => 'xCAT::Template cannot be loaded here' if system($probe) != 0;
require lib;
lib->import(@incs);
require xCAT::Template;

{
    no warnings qw(redefine once);
    *xCAT::Template::ubuntu_subiquity_pkgdir_uri = sub { return "http://192.0.2.10$_[0]" };
}
my $flat = File::Temp->newdir();
open( my $pfh, '>', "$flat/Packages" ) or die $!; close $pfh;
open( my $rfh, '>', "$flat/Release" )  or die $!; close $rfh;
my @specs = xCAT::Template::ubuntu_subiquity_pkgdir_source_specs(
    "/install/ubuntu24.04.4/x86_64, http://mirror.example/ubuntu noble main universe ,http://repo.example/extra,ssh://host/path,http://mirror.example/ubuntu jammy,http://flat.example/pool ./,$flat"
);
is( scalar(@specs), 3, 'the media path, the bare URL, the ssh entry and a suite without components are no apt sources; the rest are' );
is_deeply( $specs[0], { uri => 'http://mirror.example/ubuntu', suites => 'noble', components => 'main universe', trusted => 0, signed_by => '',
        line => 'deb http://mirror.example/ubuntu noble main universe' },
    'an entry written as URL suite components is used as written, and is not marked trusted' );
is_deeply( $specs[1], { uri => 'http://flat.example/pool', suites => './', components => '', trusted => 0, signed_by => '',
        line => 'deb http://flat.example/pool ./' },
    'an exact-path suite needs no component' );
is_deeply( $specs[2], { uri => "http://192.0.2.10$flat", suites => './', components => '', trusted => 1, signed_by => '',
        line => "deb [trusted=yes] http://192.0.2.10$flat ./" },
    'a local flat repository is served by the management node and trusted, as an otherpkgdir is' );
is_deeply( [ xCAT::Template::ubuntu_subiquity_pkgdir_source_specs(undef) ], [], 'no pkgdir gives no sources' );
my @alias = xCAT::Template::ubuntu_subiquity_pkgdir_source_specs("$flat,http://192.0.2.10$flat/ ./");
is( scalar(@alias), 1, 'a local repository and its own URL in pkgdir are one source' );
is( $alias[0]{trusted}, 1, '... trusted, as the directory entry is' );
my $keyring = '/usr/share/keyrings/ubuntu-archive-keyring.gpg';
is_deeply(
    [ xCAT::Template::ubuntu_subiquity_pkgdir_source_specs( 'http://archive.example/ubuntu/ noble-proposed main,http://mirror.example/ubuntu noble main', $keyring, 'http://archive.example/ubuntu' ) ],
    [   { uri => 'http://archive.example/ubuntu/', suites => 'noble-proposed', components => 'main', trusted => 0, signed_by => $keyring,
            line => "deb [signed-by=$keyring] http://archive.example/ubuntu/ noble-proposed main" },
        { uri => 'http://mirror.example/ubuntu', suites => 'noble', components => 'main', trusted => 0, signed_by => '', line => 'deb http://mirror.example/ubuntu noble main' } ],
    'an entry that names the apt mirror, trailing slash or not, carries the key given for that mirror; another mirror gets none' );
is_deeply(
    [ xCAT::Template::ubuntu_subiquity_pkgdir_source_specs( 'http://archive.example/ubuntu jammy main', '', 'http://archive.example/ubuntu' ) ],
    [ { uri => 'http://archive.example/ubuntu', suites => 'jammy', components => 'main', trusted => 0, signed_by => '', line => 'deb http://archive.example/ubuntu jammy main' } ],
    'without a key for the mirror the entry is used as written' );

our ( $apt_mirror, @otherpkg_sources ) = ( '', () );
{
    no warnings qw(redefine once);
    *xCAT::Template::ubuntu_subiquity_apt_mirror       = sub { return $main::apt_mirror };
    *xCAT::Template::ubuntu_subiquity_otherpkg_sources = sub { return @main::otherpkg_sources };
}
# the value mkinstall hands over: the media first, then two mirrors
my $mirrors = '/install/ubuntu24.04.4/x86_64,http://mirror.example/ubuntu noble main,http://repo.example/extra';

sub apt_config_for {
    my ( $media_dir, %args ) = @_;
    local $apt_mirror       = $args{mirror} // '';
    local @otherpkg_sources = @{ $args{others} || [] };
    return xCAT::Template::ubuntu_subiquity_apt_config( $media_dir, undef, $args{pkgdirs} );
}

my $online = apt_config_for( 'ubuntu24.04', mirror => 'http://archive.example/ubuntu', pkgdirs => $mirrors );
like( $online, qr/^    sources:$/m, 'online: the pkgdir mirrors open the sources mapping' );
like( $online, qr{^      xcat-pkgdir-0\.sources:\n        source: \|\n          Types: deb\n          URIs: http://mirror\.example/ubuntu\n          Suites: noble\n          Components: main(?:\n|\z)}m,
    '... as a Deb822 stanza on a Deb822 release, with the suite and components as written' );
unlike( $online, qr{xcat-pkgdir-1|repo\.example}, '... and the bare URL is not offered as a repository' );

my $online_both = apt_config_for( 'ubuntu22.04', mirror => 'http://archive.example/ubuntu', others => ['http://mn/otherpkgs'], pkgdirs => $mirrors );
is( scalar( () = $online_both =~ /^    sources:$/mg ), 1, 'online with otherpkgs and pkgdir mirrors: one sources mapping' );
like( $online_both, qr/xcat-otherpkgs-0\.list:.*xcat-pkgdir-0\.list:/s, '... otherpkgs first, then the mirror' );

my $offline_deb822 = apt_config_for( 'ubuntu24.04', pkgdirs => $mirrors );
like( $offline_deb822, qr{^      URIs: http://mirror\.example/ubuntu\n      Suites: noble\n      Components: main(?:\n|\z)}m, 'offline Deb822: a stanza per mirror' );
unlike( $offline_deb822, qr{repo\.example|Trusted: yes\n(?:.*\n)*      URIs: http://mirror}, '... nothing trusted and no bare URL' );

my $offline_legacy = apt_config_for( 'ubuntu22.04', pkgdirs => $mirrors );
like( $offline_legacy, qr{^    sources:\n      xcat-pkgdir-0\.list:\n        source: "deb http://mirror\.example/ubuntu noble main"$}m, 'offline legacy: .list files under sources' );

my $same = apt_config_for( 'ubuntu24.04', mirror => 'http://mirror.example/ubuntu', pkgdirs => 'http://mirror.example/ubuntu noble-proposed main' );
like( $same, qr{^      xcat-pkgdir-0\.sources:\n        source: \|\n          Types: deb\n          URIs: http://mirror\.example/ubuntu\n          Suites: noble-proposed\n          Components: main\n          Signed-By: \Q$keyring\E(?:\n|\z)}m,
    'another suite of the apt mirror is added with the signing key the installer gives that mirror' );

# before Deb822 the archive sources are rendered here without a key, so a repeated mirror entry must carry none either
foreach my $release ( [ 'ubuntu20.04', 'focal' ], [ 'ubuntu22.04', 'jammy' ] ) {
    my ( $media, $suite ) = @$release;
    my $legacy_same = apt_config_for( $media, mirror => 'http://mirror.example/ubuntu', pkgdirs => "http://mirror.example/ubuntu $suite main" );
    like( $legacy_same, qr{^      xcat-pkgdir-0\.list:\n        source: "deb http://mirror\.example/ubuntu \Q$suite\E main"$}m,
        "$media: an entry that repeats the apt mirror carries no signing key, like the archive sources rendered next to it" );
    like( $legacy_same, qr{^      xcat-ubuntu-archive\.list:\n        source: "deb http://mirror\.example/ubuntu \$RELEASE main restricted universe multiverse"$}m,
        "$media: which stay as they were" );
}

# a repository named by otherpkgdir and by pkgdir is offered once, trusted, on both source forms
foreach my $media ( 'ubuntu24.04', 'ubuntu22.04' ) {
    my $overlap = apt_config_for( $media, mirror => 'http://archive.example/ubuntu', others => ['http://repo.example/ubuntu'],
        pkgdirs => '/install/ubuntu24.04.4/x86_64,http://repo.example/ubuntu/ ./' );
    like( $overlap, qr/xcat-otherpkgs-0\./, "$media: the repository the otherpkgdir names is offered as the trusted otherpkgs source" );
    unlike( $overlap, qr/xcat-pkgdir/, "$media: and not again as a pkgdir source with other options" );
}

# an otherpkgdir entry that names the apt mirror itself gets the options of the source the installer already has for it
my $archive_others = ['http://mirror.example/ubuntu noble universe'];
like( apt_config_for( 'ubuntu22.04', mirror => 'http://mirror.example/ubuntu', others => $archive_others ),
    qr{^      xcat-otherpkgs-0\.list:\n        source: "deb http://mirror\.example/ubuntu noble universe"$}m,
    'classic: an otherpkgdir entry for the apt mirror carries no option, like the archive sources next to it' );
like( apt_config_for( 'ubuntu24.04', mirror => 'http://mirror.example/ubuntu', others => $archive_others ),
    qr{^      xcat-otherpkgs-0\.sources:\n        source: \|\n          Types: deb\n          URIs: http://mirror\.example/ubuntu\n          Suites: noble\n          Components: universe\n          Signed-By: \Q$keyring\E(?:\n|\z)}m,
    'Deb822: and carries the archive keyring and no Trusted, as the primary source does' );

# the same repository and suite with other components: the pkgdir components join the otherpkgs source
my $union = apt_config_for( 'ubuntu24.04', mirror => 'http://archive.example/ubuntu', others => ['http://repo.example/team stable tools'],
    pkgdirs => '/install/ubuntu24.04.4/x86_64,http://repo.example/team/ stable compute tools' );
like( $union, qr{^      xcat-otherpkgs-0\.sources:\n        source: \|\n          Types: deb\n          URIs: http://repo\.example/team\n          Suites: stable\n          Components: tools compute\n          Trusted: yes(?:\n|\z)}m,
    'a pkgdir entry that repeats an otherpkgs repository adds its components to that source' );
unlike( $union, qr/xcat-pkgdir/, '... and is not a second source' );
my $union_legacy = apt_config_for( 'ubuntu22.04', mirror => 'http://archive.example/ubuntu', others => ['http://repo.example/team stable tools'],
    pkgdirs => '/install/ubuntu24.04.4/x86_64,http://repo.example/team stable compute' );
like( $union_legacy, qr{^      xcat-otherpkgs-0\.list:\n        source: "deb \[trusted=yes\] http://repo\.example/team stable tools compute"$}m,
    'in the one-line form as well' );

my $none = apt_config_for( 'ubuntu24.04', mirror => 'http://archive.example/ubuntu' );
unlike( $none, qr/sources:/, 'without otherpkgs or mirrors no sources mapping is rendered on a Deb822 release' );

done_testing();
