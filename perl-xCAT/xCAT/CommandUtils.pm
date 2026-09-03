package xCAT::CommandUtils;

use strict;
use warnings;

our @SYSTEM_FALLBACK_DIRS = qw(
  /usr/sbin
  /usr/bin
  /sbin
  /bin
);

=head1 NAME

xCAT::CommandUtils - dependency-light command lookup helpers

=head1 FUNCTIONS

=head2 find_executable

Find an executable by searching PATH in order, followed by the standard system
directories. Pass C<path =E<gt> $value> to search that value instead of the
process PATH. Like the callers this function replaces, empty entries and an
entry named C<0> are ignored. Pass C<fallback_dirs =E<gt> []> to disable the
standard fallbacks, or supply an array reference to replace them. The matching
candidate path is returned, or undef when none is found.

=cut

sub find_executable {
    my ( $command, %args ) = @_;

    return unless defined($command) && length($command);

    my $path = exists( $args{path} ) ? $args{path} : $ENV{PATH};
    foreach my $dir ( split /:/, $path || '' ) {
        next unless $dir;
        my $candidate = "$dir/$command";
        return $candidate if -x $candidate;
    }

    my $fallback_dirs = exists( $args{fallback_dirs} )
      ? $args{fallback_dirs}
      : \@SYSTEM_FALLBACK_DIRS;
    foreach my $dir ( @{ $fallback_dirs || [] } ) {
        next unless defined($dir) && length($dir);
        my $candidate = "$dir/$command";
        return $candidate if -x $candidate;
    }

    return;
}

1;
