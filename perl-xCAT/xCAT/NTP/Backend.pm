package xCAT::NTP::Backend;

# Selector for the NTP daemon xCAT configures on a node (chrony vs. ntpd), in the same spirit as
# xCAT::DHCP::Backend (ISC vs. Kea). makentp/setupntp support chronyd and ntpd only -- there is no
# systemd-timesyncd path (timesyncd is an SNTP client and cannot serve time to compute nodes), so an
# xCAT MN always needs chrony or ntpd. This module centralizes and unit-tests the choice.

use strict;
use warnings;

my %valid_backend = map { $_ => 1 } qw(auto chrony ntpd);

# Accept common aliases so site.ntpbackend / callers can say chronyd or ntp.
my %alias = (
    chronyd => 'chrony',
    ntp     => 'ntpd',
    ntpsec  => 'ntpd',
);

sub normalize {
    my ( $class, $backend ) = @_;

    $backend = 'auto' unless defined($backend) && $backend ne '';
    $backend =~ s/^\s+|\s+$//g;
    $backend = lc($backend);
    $backend = $alias{$backend} if exists $alias{$backend};

    return $backend if $valid_backend{$backend};
    return;
}

# choose: resolve the effective backend for this node.
#   requested       -- override (default: site.ntpbackend, else 'auto')
#   os_name/version -- OS identity (default: detected)
#   available       -- optional { chrony => 0/1, ntpd => 0/1 } to bypass command detection (tests)
#   check_available -- when true, downgrade chrony->ntpd (or ntpd->chrony) if the chosen one is
#                      absent but the other is present, and flag install=1 when neither is present.
sub choose {
    my ( $class, %args ) = @_;

    my $requested = exists $args{requested} ? $args{requested} : $class->_site_backend();
    my $normalized = $class->normalize($requested);
    unless ($normalized) {
        return { error => "Invalid site.ntpbackend value '$requested'. Valid values are auto, chrony, and ntpd." };
    }

    my $selected = $normalized eq 'auto' ? $class->default_backend(%args) : $normalized;
    my $result = { requested => $normalized, name => $selected, install => 0 };

    return $result unless $args{check_available};

    my $other = $selected eq 'chrony' ? 'ntpd' : 'chrony';
    if ( $class->available( $selected, %args ) ) {
        return $result;
    } elsif ( $class->available( $other, %args ) ) {
        # respect what is actually installed rather than installing a second daemon
        $result->{name}       = $other;
        $result->{downgraded} = $selected;
        return $result;
    }

    # neither present: keep the preferred choice and tell the caller to install it
    $result->{install} = 1;
    return $result;
}

# default_backend: table-driven per distro family.
#   EL/RHEL & clones: >= 7 -> chrony, 6 -> ntpd
#   SLES/SUSE:        >= 15 -> chrony, 12 -> ntpd
#   Ubuntu/Debian:    chrony (timesyncd is the OOB client but cannot serve; chrony from 18.04+)
sub default_backend {
    my ( $class, %args ) = @_;

    my $os_name = exists $args{os_name} ? $args{os_name} : $class->_osver('os');
    my $version = exists $args{version} ? $args{version} : ( split /,/, $class->_osver('all'), 2 )[1];
    my ($major) = ( defined($version) ? $version : '' ) =~ /^(\d+)/;

    if ( defined($os_name) && $os_name =~ /^(?:rhel|rhels|rocky|alma|centos|ol|fedora)$/i ) {
        return 'ntpd' if defined($major) && $major <= 6;
        return 'chrony';
    }
    if ( defined($os_name) && $os_name =~ /^(?:sles|sled|suse|opensuse|leap)$/i ) {
        return 'ntpd' if defined($major) && $major <= 12;
        return 'chrony';
    }
    if ( defined($os_name) && $os_name =~ /^(?:ubuntu|debian)$/i ) {
        return 'chrony';
    }

    return 'chrony';
}

sub available {
    my ( $class, $backend, %args ) = @_;

    if ( exists $args{available} && ref( $args{available} ) eq 'HASH' && exists $args{available}{$backend} ) {
        return $args{available}{$backend} ? 1 : 0;
    }

    return _command_exists('chronyd') if $backend eq 'chrony';
    return _command_exists('ntpd')    if $backend eq 'ntpd';
    return 0;
}

sub _site_backend {
    my $backend = eval {
        require xCAT::TableUtils;
        return xCAT::TableUtils->get_site_attribute( 'ntpbackend', 'auto' );
    };

    return $backend || 'auto';
}

sub _osver {
    my ( $class, $type ) = @_;

    my $osver = eval {
        require xCAT::Utils;
        return defined($type) ? xCAT::Utils->osver($type) : xCAT::Utils->osver();
    };

    return $osver || 'unknown';
}

sub _command_exists {
    my ($command) = @_;

    foreach my $dir ( split /:/, $ENV{PATH} || '' ) {
        next unless $dir;
        return 1 if -x "$dir/$command";
    }
    foreach my $path ( "/usr/sbin/$command", "/usr/bin/$command", "/sbin/$command", "/bin/$command" ) {
        return 1 if -x $path;
    }
    return 0;
}

1;
