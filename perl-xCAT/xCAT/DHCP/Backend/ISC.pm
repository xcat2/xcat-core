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

# The backend auto-selection fell back to this backend because the preferred one
# was not installed (undef when no fallback happened). See issue #7710.
sub fallback_from {
    my $self = shift;
    return ref($self) ? $self->{selection}{fallback_from} : undef;
}

sub implemented {
    return 1;
}

1;
