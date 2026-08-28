package xCAT::DHCP::Range;

use strict;
use warnings;

use Math::BigInt;
use Socket;
use xCAT::NetworkUtils qw/getipaddr/;
use xCAT::StringUtils qw(trim);

sub parse_dynamic_ranges {
    my ( $class, $ranges ) = @_;

    return [] unless defined($ranges) && $ranges ne '';

    my @parsed;
    foreach my $range ( split /;/, $ranges ) {
        my $entry = $class->parse($range);
        push @parsed, $entry if $entry;
    }

    return \@parsed;
}

sub parse {
    my ( $class, $range ) = @_;

    return unless defined($range);
    $range = trim($range);
    return unless $range ne '';

    if ( $range =~ m{/} ) {
        return $class->_parse_cidr($range);
    }

    return $class->_parse_pair($range);
}

sub isc_ranges {
    my ( $class, $ranges ) = @_;

    return map { $class->isc_range($_) } @{ $class->parse_dynamic_ranges($ranges) };
}

sub kea_pools {
    my ( $class, $ranges ) = @_;

    return map { { pool => $class->kea_pool($_) } } @{ $class->parse_dynamic_ranges($ranges) };
}

sub isc_range {
    my ( $class, $entry ) = @_;

    return $entry->{cidr} if $entry->{family} == 6 && $entry->{cidr};
    return "$entry->{start} $entry->{end}";
}

sub kea_pool {
    my ( $class, $entry ) = @_;

    return $entry->{cidr} if $entry->{family} == 6 && $entry->{cidr};
    return "$entry->{start} - $entry->{end}";
}

sub bounds {
    my ( $class, $entry ) = @_;

    return ( $entry->{start_number}, $entry->{end_number} );
}

sub _parse_pair {
    my ( $class, $range ) = @_;

    my @parts = grep { $_ ne '' } split /[\s,-]+/, $range;
    return unless @parts >= 2;

    my ( $start, $end ) = @parts[ 0, 1 ];
    my $family = ( $start =~ /:/ || $end =~ /:/ ) ? 6 : 4;
    my $start_number = getipaddr( $start, GetNumber => 1 );
    my $end_number   = getipaddr( $end,   GetNumber => 1 );

    return unless defined($start_number) && defined($end_number);

    return {
        source       => $range,
        family       => $family,
        start        => $start,
        end          => $end,
        start_number => $start_number,
        end_number   => $end_number,
    };
}

sub _parse_cidr {
    my ( $class, $range ) = @_;

    my ( $prefix, $suffix ) = split /\//, $range, 2;
    return unless defined($prefix) && defined($suffix) && $suffix =~ /^\d+$/;

    my $family = $prefix =~ /:/ ? 6 : 4;
    my $numbits = $family == 6 ? 128 : 32;
    return if $suffix > $numbits;

    my $number = getipaddr( $prefix, GetNumber => 1 );
    return unless defined($number);

    my $highmask = Math::BigInt->new( "0b" . ( "1" x $suffix ) . ( "0" x ( $numbits - $suffix ) ) );
    my $lowmask  = Math::BigInt->new( "0b" . ( "1" x ( $numbits - $suffix ) ) );

    $number &= $highmask;
    my $start_number = $number->copy();
    $number |= $lowmask;
    my $end_number = $number->copy();

    if ( $family == 6 ) {
        return {
            source       => $range,
            family       => 6,
            cidr         => $range,
            start_number => $start_number,
            end_number   => $end_number,
        };
    }

    return {
        source       => $range,
        family       => 4,
        cidr         => $range,
        start        => inet_ntoa( pack( "N*", $start_number->numify() ) ),
        end          => inet_ntoa( pack( "N*", $end_number->numify() ) ),
        start_number => $start_number,
        end_number   => $end_number,
    };
}

1;
