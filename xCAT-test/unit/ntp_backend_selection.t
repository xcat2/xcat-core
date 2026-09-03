use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

use xCAT::NTP::Backend;

# --- normalize: aliases, trimming, case, validation --------------------------------------------
is( xCAT::NTP::Backend->normalize(undef),   'auto',   'undefined backend defaults to auto' );
is( xCAT::NTP::Backend->normalize(''),      'auto',   'empty backend defaults to auto' );
is( xCAT::NTP::Backend->normalize(' Chrony '), 'chrony', 'values are trimmed and lowercased' );
is( xCAT::NTP::Backend->normalize('chronyd'), 'chrony', 'chronyd aliases to chrony' );
is( xCAT::NTP::Backend->normalize('ntp'),     'ntpd',   'ntp aliases to ntpd' );
is( xCAT::NTP::Backend->normalize('ntpsec'),  'ntpd',   'ntpsec aliases to ntpd' );
is( xCAT::NTP::Backend->normalize('ntpd'),    'ntpd',   'ntpd is valid' );
is( xCAT::NTP::Backend->normalize('bogus'),   undef,    'invalid backend is rejected' );

# --- default_backend: per-distro table ---------------------------------------------------------
is( xCAT::NTP::Backend->default_backend( os_name => 'rhel',   version => 6 ),  'ntpd',   'EL6 defaults to ntpd' );
is( xCAT::NTP::Backend->default_backend( os_name => 'rhel',   version => 7 ),  'chrony', 'EL7 defaults to chrony' );
is( xCAT::NTP::Backend->default_backend( os_name => 'rhels',  version => 8 ),  'chrony', 'EL8 defaults to chrony' );
is( xCAT::NTP::Backend->default_backend( os_name => 'rocky',  version => 9 ),  'chrony', 'EL9 clones default to chrony' );
is( xCAT::NTP::Backend->default_backend( os_name => 'alma',   version => 10 ), 'chrony', 'EL10 clones default to chrony' );
is( xCAT::NTP::Backend->default_backend( os_name => 'sles',   version => 12 ), 'ntpd',   'SLES12 defaults to ntpd' );
is( xCAT::NTP::Backend->default_backend( os_name => 'sles',   version => 15 ), 'chrony', 'SLES15 defaults to chrony' );
is( xCAT::NTP::Backend->default_backend( os_name => 'sles',   version => 16 ), 'chrony', 'SLES16 defaults to chrony' );
is( xCAT::NTP::Backend->default_backend( os_name => 'leap',   version => '15.6' ), 'chrony', 'Leap 15.x defaults to chrony' );
is( xCAT::NTP::Backend->default_backend( os_name => 'ubuntu', version => '18.04' ), 'chrony', 'Ubuntu 18.04 defaults to chrony (timesyncd cannot serve)' );
is( xCAT::NTP::Backend->default_backend( os_name => 'ubuntu', version => '20.04' ), 'chrony', 'Ubuntu 20.04 defaults to chrony' );
is( xCAT::NTP::Backend->default_backend( os_name => 'ubuntu', version => '22.04' ), 'chrony', 'Ubuntu 22.04 defaults to chrony' );
is( xCAT::NTP::Backend->default_backend( os_name => 'ubuntu', version => '24.04' ), 'chrony', 'Ubuntu 24.04 defaults to chrony' );
is( xCAT::NTP::Backend->default_backend( os_name => 'ubuntu', version => '26.04' ), 'chrony', 'Ubuntu 26.04 defaults to chrony' );
is( xCAT::NTP::Backend->default_backend( os_name => 'debian', version => 12 ), 'chrony', 'Debian defaults to chrony' );

# --- choose: explicit override, auto, availability downgrade, install flag ----------------------
my $r;

$r = xCAT::NTP::Backend->choose( requested => 'ntpd', os_name => 'ubuntu', version => '24.04' );
is( $r->{name}, 'ntpd', 'explicit ntpd override is honored on Ubuntu' );

$r = xCAT::NTP::Backend->choose( requested => 'auto', os_name => 'ubuntu', version => '24.04' );
is( $r->{name}, 'chrony', 'auto resolves to the Ubuntu default (chrony)' );

$r = xCAT::NTP::Backend->choose( requested => 'bogus', os_name => 'ubuntu', version => '24.04' );
like( $r->{error}, qr/Invalid site\.ntpbackend/, 'invalid override returns an error' );

# chrony chosen but absent, ntpd present -> downgrade to ntpd (do not install a 2nd daemon)
$r = xCAT::NTP::Backend->choose(
    requested => 'auto', os_name => 'ubuntu', version => '24.04',
    check_available => 1, available => { chrony => 0, ntpd => 1 } );
is( $r->{name}, 'ntpd', 'chrony absent + ntpd present downgrades to ntpd' );
is( $r->{downgraded}, 'chrony', 'downgrade records the preferred backend' );
is( $r->{install}, 0, 'no install when a supported daemon is already present' );

# chrony chosen and present -> keep it, no install
$r = xCAT::NTP::Backend->choose(
    requested => 'auto', os_name => 'ubuntu', version => '24.04',
    check_available => 1, available => { chrony => 1, ntpd => 0 } );
is( $r->{name}, 'chrony', 'chrony present keeps chrony' );
is( $r->{install}, 0, 'chrony present needs no install' );

# neither present -> keep the preferred choice and flag install (stock Ubuntu MN)
$r = xCAT::NTP::Backend->choose(
    requested => 'auto', os_name => 'ubuntu', version => '24.04',
    check_available => 1, available => { chrony => 0, ntpd => 0 } );
is( $r->{name}, 'chrony', 'neither present keeps the preferred chrony' );
is( $r->{install}, 1, 'neither present flags install of the preferred daemon' );

# --- available: chrony needs systemd, not just chronyd -----------------------------------------
# makentp configures chrony only where systemctl is present, and setupntp hands over to ntpd
# without it. The selector has to call chrony usable on the same terms, or makentp silently takes
# the ntpd path for a backend the selector reported as available.
is( xCAT::NTP::Backend->available( 'chrony', commands => { chronyd => 1, systemctl => 1 } ), 1,
    'chrony is available where chronyd and systemctl are both present' );
is( xCAT::NTP::Backend->available( 'chrony', commands => { chronyd => 1, systemctl => 0 } ), 0,
    'chronyd without systemctl is not a usable chrony backend' );
is( xCAT::NTP::Backend->available( 'chrony', commands => { chronyd => 0, systemctl => 1 } ), 0,
    'systemctl without chronyd is not a usable chrony backend either' );
is( xCAT::NTP::Backend->available( 'ntpd', commands => { ntpd => 1 } ), 1,
    'ntpd needs only ntpd' );

$r = xCAT::NTP::Backend->choose(
    requested => 'chrony', check_available => 1,
    commands => { chronyd => 1, systemctl => 0, ntpd => 1 } );
is( $r->{name}, 'ntpd', 'chronyd without systemctl downgrades to the daemon that can be used' );
is( $r->{downgraded}, 'chrony', 'and the downgrade is reported rather than silent' );

$r = xCAT::NTP::Backend->choose(
    requested => 'chrony', check_available => 1,
    commands => { chronyd => 1, systemctl => 0, ntpd => 0 } );
is( $r->{install}, 1, 'chronyd without systemctl and no ntpd asks for an install' );

done_testing();
