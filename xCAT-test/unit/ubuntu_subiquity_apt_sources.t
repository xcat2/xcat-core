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
    local *xCAT::Template::ubuntu_subiquity_otherpkg_sources    = sub { () };
    local *xCAT::Template::ubuntu_subiquity_uses_generated_cdrom_source = sub { 0 };
    return xCAT::Template::ubuntu_subiquity_apt_config('/some/media/dir');
}

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
