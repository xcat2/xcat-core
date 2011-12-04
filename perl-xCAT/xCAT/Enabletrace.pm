#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::Enabletrace;
use Filter::Util::Call;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(loadtrace filter);

sub loadtrace{
  my (undef, $filename) = caller();
  my (%args) = (
      filename => $filename,
      inside => 0,
      lineno => 0,
  );

  filter_add(bless \%args);
}

sub filter {
  my ($self) = @_;
  my $line= filter_read();
  $self->{lineno}++;
  # deal with EOF/error first
  if ($line<= 0) {
    if ($self->{inside}) {
      die "Do not find the END of the trace block. [$self->{filename}:$self->{lineno}]";
    }
    return $line;
  }
  if ($self->{inside}) {
    if (/^\s*##\s*TRACE_BEGIN/ ) {
      die "The trace block is nested. [$self->{filename}:$self->{lineno}]";
    } elsif (/^\s*##\s*TRACE_END/) {
      $self->{inside} = 0;
    } else {
      # remove the #.. at the begin of the line
      s/^\s*#+//;
    }
  } elsif ( /^\s*##\s*TRACE_BEGIN/ ) {
    $self->{inside} = 1;
  } elsif ( /^\s*##\s*TRACE_END/ ) {
    die "Do not see the BEGIN of the trace block. [$self->{filename}:$self->{lineno}]";
  } elsif ( /^\s*##\s*TRACE_LINE/ ) {
     s/^\s*##\s*TRACE_LINE//;
  }

    return $line;
  }


1;
