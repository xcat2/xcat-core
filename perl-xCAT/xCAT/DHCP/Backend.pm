package xCAT::DHCP::Backend;

use strict;
use warnings;

my %valid_backend = map { $_ => 1 } qw(auto isc kea);

sub normalize {
    my ( $class, $backend ) = @_;

    $backend = 'auto' unless defined($backend) && $backend ne '';
    $backend =~ s/^\s+|\s+$//g;
    $backend = lc($backend);

    return $backend if $valid_backend{$backend};
    return;
}

sub choose {
    my ( $class, %args ) = @_;

    my $requested = exists $args{requested} ? $args{requested} : $class->_site_backend();
    my $normalized = $class->normalize($requested);

    unless ($normalized) {
        return {
            error => "Invalid site.dhcpbackend value '$requested'. Valid values are auto, isc, and kea.",
        };
    }

    my $selected = $normalized eq 'auto' ? $class->default_backend(%args) : $normalized;

    if ( $args{check_available} && !$class->available( $selected, %args ) ) {
        return {
            requested => $normalized,
            name      => $selected,
            error     => "The selected DHCP backend '$selected' is not available on this system.",
        };
    }

    return {
        requested => $normalized,
        name      => $selected,
    };
}

sub default_backend {
    my ( $class, %args ) = @_;

    my $platform = exists $args{platform} ? $args{platform} : $class->_osver('platform');
    if ( defined($platform) && $platform =~ /^el(\d+)\b/i ) {
        return 'kea' if $1 >= 10;
    }

    my $os = exists $args{os} ? $args{os} : $class->_osver();
    if ( defined($os) && $os =~ /^(?:rhel|rhels|rocky|alma|centos|ol)(\d+)(?:\D|$)/i ) {
        return 'kea' if $1 >= 10;
    }

    my $os_name = exists $args{os_name} ? $args{os_name} : $class->_osver('os');
    my $version = exists $args{version} ? $args{version} : ( split /,/, $class->_osver('all'), 2 )[1];
    if ( defined($os_name) && $os_name =~ /^ubuntu$/i && defined($version) && $version =~ /^\d+\.\d+(?:\.\d+)*$/ ) {
        require xCAT::Utils;
        return 'kea' if xCAT::Utils->version_cmp( $version, '22.04' ) >= 0;
    }

    return 'isc';
}

sub available {
    my ( $class, $backend, %args ) = @_;

    if ( exists $args{available} && ref( $args{available} ) eq 'HASH' && exists $args{available}{$backend} ) {
        return $args{available}{$backend} ? 1 : 0;
    }

    if ( $backend eq 'isc' ) {
        return _command_exists('dhcpd');
    } elsif ( $backend eq 'kea' ) {
        return _command_exists('kea-dhcp4');
    }

    return 0;
}

sub backend_class {
    my ( $class, $backend ) = @_;

    return 'xCAT::DHCP::Backend::ISC' if $backend eq 'isc';
    return 'xCAT::DHCP::Backend::Kea' if $backend eq 'kea';
    return;
}

sub new_backend {
    my ( $class, %args ) = @_;

    my $selection = $class->choose(%args);
    return $selection if $selection->{error};

    my $backend_class = $class->backend_class( $selection->{name} );
    my $loaded = eval {
        if ( $selection->{name} eq 'isc' ) {
            require xCAT::DHCP::Backend::ISC;
        } elsif ( $selection->{name} eq 'kea' ) {
            require xCAT::DHCP::Backend::Kea;
        } else {
            die "Unknown DHCP backend '$selection->{name}'";
        }
        1;
    };
    if (!$loaded) {
        return {
            %$selection,
            error => "Unable to load DHCP backend '$selection->{name}': $@",
        };
    }

    return $backend_class->new( selection => $selection );
}

sub _site_backend {
    my $backend = eval {
        require xCAT::TableUtils;
        return xCAT::TableUtils->get_site_attribute('dhcpbackend', 'auto');
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
        my $path = "$dir/$command";
        return 1 if -x $path;
    }

    foreach my $path ( "/usr/sbin/$command", "/usr/bin/$command", "/sbin/$command", "/bin/$command" ) {
        return 1 if -x $path;
    }

    return 0;
}

1;
