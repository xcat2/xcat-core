# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::RespawnUtils;

use strict;
use warnings;

sub policy {
    my (%opt) = @_;

    my $min     = defined($opt{min_interval}) ? $opt{min_interval} : 5;
    my $max     = defined($opt{max_interval}) ? $opt{max_interval} : 300;
    my $healthy = defined($opt{healthy})      ? $opt{healthy}      : 60;

    $min = 1    if $min < 1;
    $max = $min if $max < $min;

    return {
        min_interval => $min,
        max_interval => $max,
        healthy      => $healthy,
        delay        => $min,
        next_at      => 0,
        started_at   => undef,
        streak       => 0,
        reported     => 0,
    };
}

sub due {
    my ($state, $now) = @_;
    return $now >= $state->{next_at} ? 1 : 0;
}

sub forked {
    my ($state, $now) = @_;
    return { %$state, started_at => $now };
}

sub exited {
    my ($state, $now) = @_;

    my %next = (%$state, started_at => undef);

    if (defined($state->{started_at})
        and ($now - $state->{started_at}) >= $state->{healthy}) {

        $next{delay}    = $state->{min_interval};
        $next{next_at}  = $now;
        $next{streak}   = 0;
        $next{reported} = 0;
    } else {
        $next{streak}  = $state->{streak} + 1;
        $next{next_at} = $now + $state->{delay};
        $next{delay}   = ($state->{delay} * 2 > $state->{max_interval})
          ? $state->{max_interval}
          : $state->{delay} * 2;
    }

    return \%next;
}

sub should_report {
    my ($state) = @_;
    return 0 if $state->{reported};
    return 0 if $state->{streak} < 1;
    return $state->{delay} >= $state->{max_interval} ? 1 : 0;
}

sub reported {
    my ($state) = @_;
    return { %$state, reported => 1 };
}

1;
