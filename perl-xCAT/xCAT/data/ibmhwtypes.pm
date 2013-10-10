#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::data::ibmhwtypes;
require Exporter;
@EXPORT_OK=qw(parse_group mt2group);
use Data::Dumper;
my %groups2mtm = (
    "x3250" => ["2583","4251","4252"],
    "x3550" => ["7914","7944","7946"],
    "x3650" => ["7915","7945"],
    "dx360" => [],
    "x220"  => ["7906"],
    "x240"  => ["8737","7863"],
    "x440"  => ["7917"],
    "p260"  => ["7895"], #789522X, 789523X
    "p460"  => [],       #789542X
    "p470"  => ["7954"],
);

%mt2group = ();
foreach my $group (keys %groups2mtm) {
    foreach my $mtm (@{$groups2mtm{$group}}) {
        $mt2group{$mtm} = $group;
    }
}

sub parse_group {
    my $mtm = shift;
    if ($mtm =~ /xCAT::data/) {
        $mtm = shift;
    }
    if ($mtm =~ /^(\w{4})/) {
        $mt = $1;
        if ($mt eq "7895" and $mtm =~ /789542X/i) {
            return "p460";
        }
        return $mt2group{$mt};
    }
    return undef;
}

1;
