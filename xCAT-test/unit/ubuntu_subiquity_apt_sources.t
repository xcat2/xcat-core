#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";

use Test::More;

# An online Subiquity install of a classic-sources release needs the online archive added, or
# in-target apt cannot find chrony and the install crashes. A Deb822 release must NOT get it,
# or the same suites are configured twice. See the comment in Template.pm.

require xCAT::Template;

my $MIRROR = 'http://br.archive.ubuntu.com/ubuntu';

sub apt_config_for {
    my (%opt) = @_;
    no warnings 'redefine';
    local *xCAT::Template::ubuntu_subiquity_apt_mirror         = sub { $opt{mirror} };
    local *xCAT::Template::ubuntu_subiquity_uses_deb822_sources = sub { $opt{deb822} };
    local *xCAT::Template::ubuntu_subiquity_otherpkg_sources    = sub { @{ $opt{others} || [] } };
    local *xCAT::Template::ubuntu_subiquity_uses_generated_cdrom_source = sub { 0 };
    return xCAT::Template::ubuntu_subiquity_apt_config('/some/media/dir');
}

# --- the otherpkgs repository: a one-line source before Deb822, a Deb822 stanza from 24.04 on, ---
# --- since curtin drops the options of a one-line source when it converts it there            ---
my $others = [ 'http://192.0.2.10/install/post/otherpkgs/ubuntu24.04/x86_64' ];
my $classic_others = apt_config_for( mirror => $MIRROR, deb822 => 0, others => $others );
like( $classic_others, qr{^      xcat-otherpkgs-0\.list:\n        source: "deb \[trusted=yes\] http://192\.0\.2\.10/install/post/otherpkgs/ubuntu24\.04/x86_64 \./"$}m,
    'classic: the otherpkgs repository is a one-line trusted source' );
my $deb822_others = apt_config_for( mirror => $MIRROR, deb822 => 1, others => $others );
like( $deb822_others,
    qr{^      xcat-otherpkgs-0\.sources:\n        source: \|\n          Types: deb\n          URIs: http://192\.0\.2\.10/install/post/otherpkgs/ubuntu24\.04/x86_64\n          Suites: \./\n          Components:\n          Trusted: yes(?:\n|\z)}m,
    'Deb822: the otherpkgs repository is a Deb822 stanza carrying Trusted: yes' );
unlike( $deb822_others, qr/xcat-otherpkgs-0\.list|trusted=yes/, 'Deb822: and no one-line form remains' );

# an otherpkgdir written as URL, suite and components is that source, trusted, not a flat repository at a URL with spaces
my $mirror_others = [ 'http://mirror.example/ubuntu noble main universe' ];
like( apt_config_for( mirror => $MIRROR, deb822 => 0, others => $mirror_others ),
    qr{^      xcat-otherpkgs-0\.list:\n        source: "deb \[trusted=yes\] http://mirror\.example/ubuntu noble main universe"$}m,
    'classic: an otherpkgdir mirror entry keeps its suite and components' );
like( apt_config_for( mirror => $MIRROR, deb822 => 1, others => $mirror_others ),
    qr{^      xcat-otherpkgs-0\.sources:\n        source: \|\n          Types: deb\n          URIs: http://mirror\.example/ubuntu\n          Suites: noble\n          Components: main universe\n          Trusted: yes(?:\n|\z)}m,
    'Deb822: and becomes a stanza with them as fields, so apt reads one URI' );

# --- online, classic sources (20.04 / 22.04): the archive must be added via sources: ---
my $classic = apt_config_for( mirror => $MIRROR, deb822 => 0 );

like( $classic, qr/^\s*mirror-selection:/m,
    'classic online install still sets the primary mirror' );
like( $classic, qr/^\s*sources:/m,
    'classic online install adds apt sources (sources_list is ignored by Subiquity)' );
like( $classic, qr/xcat-ubuntu-archive\.list:/,
    'classic online install writes an xCAT-owned archive source' );
like( $classic, qr/xcat-ubuntu-updates\.list:/,
    'classic online install writes an xCAT-owned updates source' );
like( $classic, qr/deb \Q$MIRROR\E \$RELEASE main restricted universe multiverse/,
    'the archive source uses the configured mirror and curtin\'s $RELEASE token' );

# --- online, Deb822 (24.04 / 26.04): no legacy .list files on top of ubuntu.sources ---
my $deb822 = apt_config_for( mirror => $MIRROR, deb822 => 1 );

like( $deb822, qr/^\s*mirror-selection:/m,
    'Deb822 online install still sets the primary mirror' );
unlike( $deb822, qr/xcat-ubuntu-archive\.list:/,
    'Deb822 online install does NOT add a legacy archive .list (it would duplicate ubuntu.sources)' );
unlike( $deb822, qr/xcat-ubuntu-updates\.list:/,
    'Deb822 online install does NOT add a legacy updates .list' );

# --- offline is untouched by any of this ---
my $offline = apt_config_for( mirror => '', deb822 => 0 );
like( $offline, qr/fallback: offline-install/,
    'the offline path is unchanged' );
unlike( $offline, qr/xcat-ubuntu-archive\.list:/,
    'the offline path adds no online archive source' );

done_testing();
