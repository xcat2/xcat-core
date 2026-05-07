package xCAT::DHCP::OmapiPolicy;

use strict;
use warnings;

my %ALGORITHMS = (
    'hmac-md5'    => 157,
    'hmac-sha1'   => 161,
    'hmac-sha224' => 162,
    'hmac-sha256' => 163,
    'hmac-sha384' => 164,
    'hmac-sha512' => 165,
);

sub settings {
    my ( $class, %args ) = @_;

    my $raw_algorithm      = _site_value( 'dhcpomapialgorithm', %args );
    my $algorithm_explicit = defined($raw_algorithm) && $raw_algorithm ne '';
    my $algorithm          = $class->normalize_algorithm($raw_algorithm);
    unless ($algorithm) {
        return {
            error => "Invalid site.dhcpomapialgorithm value '$raw_algorithm'. Valid values are: "
              . join( ', ', sort keys %ALGORITHMS )
              . ".",
        };
    }

    my $raw_key_name = _site_value( 'dhcpomapikeyname', %args );
    my $key_name     = $class->normalize_key_name($raw_key_name);
    unless ($key_name) {
        return {
            error => "Invalid site.dhcpomapikeyname value '$raw_key_name'. Use letters, digits, underscore, dot, or dash.",
        };
    }

    my $raw_omshell_path = _site_value( 'dhcpomshellpath', %args );
    my $omshell_path     = $class->normalize_omshell_path($raw_omshell_path);
    unless ($omshell_path) {
        return {
            error => "Invalid site.dhcpomshellpath value '$raw_omshell_path'. Use an absolute path without whitespace.",
        };
    }

    return {
        algorithm                   => $algorithm,
        algorithm_explicit          => $algorithm_explicit,
        key_name                    => $key_name,
        key_name_for_regex          => quotemeta($key_name),
        key_rr_type                 => $ALGORITHMS{$algorithm},
        omshell_path                => $omshell_path,
        needs_omshell_key_algorithm => $algorithm ne 'hmac-md5',
    };
}

sub normalize_algorithm {
    my ( $class, $algorithm ) = @_;

    $algorithm = 'hmac-md5' unless defined($algorithm) && $algorithm ne '';
    $algorithm =~ s/^\s+|\s+$//g;
    $algorithm = lc($algorithm);

    return $algorithm if $ALGORITHMS{$algorithm};
    return;
}

sub normalize_key_name {
    my ( $class, $key_name ) = @_;

    $key_name = 'xcat_key' unless defined($key_name) && $key_name ne '';
    $key_name =~ s/^\s+|\s+$//g;

    return $key_name if $key_name =~ /\A[A-Za-z0-9_][A-Za-z0-9_.-]*\z/;
    return;
}

sub normalize_omshell_path {
    my ( $class, $path ) = @_;

    $path = '/usr/bin/omshell' unless defined($path) && $path ne '';
    $path =~ s/^\s+|\s+$//g;

    return $path if $path =~ m{\A/[A-Za-z0-9_.:/%+=@-]+\z};
    return;
}

sub key_owner {
    my ( $class, $settings ) = @_;

    my $owner = $settings->{key_name};
    $owner .= '.' unless $owner =~ /\.\z/;
    return $owner;
}

sub omshell_preamble {
    my ( $class, $settings, %args ) = @_;

    my $secret   = $args{secret};
    my $commands = '';
    $commands .= "port $args{port}\n" if defined $args{port};

    # Stock legacy omshell accepts the implicit MD5 default but rejects an
    # explicit key-algorithm command, so emit it only when needed.
    $commands .= "key-algorithm $settings->{algorithm}\n"
      if $settings->{needs_omshell_key_algorithm};
    $commands .= "key $settings->{key_name} \"$secret\"\n";
    $commands .= "server $args{server}\n"
      if defined( $args{server} ) && $args{server} ne '';
    return $commands;
}

sub _site_value {
    my ( $key, %args ) = @_;

    if ( ref( $args{site_values} ) eq 'HASH'
        && exists $args{site_values}{$key} )
    {
        return $args{site_values}{$key};
    }

    return $::XCATSITEVALS{$key} if exists $::XCATSITEVALS{$key};

    my $value = eval {
        require xCAT::TableUtils;
        my @entries = xCAT::TableUtils->get_site_attribute($key);
        return $entries[0];
    };

    return $value;
}

1;
