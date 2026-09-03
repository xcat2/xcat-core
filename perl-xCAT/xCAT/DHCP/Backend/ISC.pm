package xCAT::DHCP::Backend::ISC;

use strict;
use warnings;

sub new {
    my ( $class, %args ) = @_;
    return bless \%args, $class;
}

sub name {
    return 'isc';
}

# The backend auto-selection preferred, and undef when it did not fall back. #7710
sub fallback_from {
    my $self = shift;
    return ref($self) ? $self->{selection}{fallback_from} : undef;
}

sub implemented {
    return 1;
}

1;
