package xCAT::BladeUtils;

use strict;
use warnings;

sub findme_request_for_handler {
    my ($request) = @_;

    return unless ref $request eq 'HASH';
    return unless ref $request->{command} eq 'ARRAY';
    return unless defined $request->{command}->[0];
    return unless $request->{command}->[0] eq 'findme';
    return [$request];
}

sub blade_nodes_from_mp {
    my @entries = @_;
    my %hwtype;
    my %ownmpa;

    foreach my $entry (@entries) {
        next unless ref $entry eq 'HASH' and defined $entry->{node};
        $hwtype{ $entry->{node} } =
          defined $entry->{nodetype} ? lc( $entry->{nodetype} ) : q{};
        $hwtype{ $entry->{node} } =~ s/^\s+|\s+$//gx;
        $ownmpa{ $entry->{node} } = $entry->{mpa}
          if defined $entry->{mpa};
    }

    my @blades;
    foreach my $entry (@entries) {
        next unless ref $entry eq 'HASH';
        my $node = $entry->{node};
        next unless defined $node;
        if ($hwtype{$node} eq 'blade') {
            push @blades, $node;
            next;
        }
        next if $hwtype{$node} ne q{};
        my $chassis = $ownmpa{$node};
        next if not defined $chassis or $chassis eq $node;
        my $chassis_type =
          defined $hwtype{$chassis} ? $hwtype{$chassis} : q{};
        next if $chassis_type ne 'mm'
          and $chassis_type ne 'cmm'
          and not(
            defined $ownmpa{$chassis}
            and $ownmpa{$chassis} eq $chassis
          );
        push @blades, $node;
    }

    return @blades;
}

1;
