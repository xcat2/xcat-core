#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::CmdLog;

use strict;
use warnings;

use xCAT::xcatd;

sub response_is_sensitive {
    my ($req, $req_redacted) = @_;
    return 1 if defined $req->{command}->[0]
      and ($req->{command}->[0] eq 'getcredentials' or $req->{command}->[0] eq 'lsvm');
    return 1 if join(' ', @{ $req->{arg} || [] }) =~ /passw/i;
    return 1 if xCAT::xcatd->secret_in_request($req->{command}->[0], $req->{arg});
    return 1 if $req_redacted;
    return 0;
}

sub finalize_response {
    my ($buffer, $sensitive) = @_;
    return "*REDACTED*\n"
      if $sensitive or xCAT::xcatd->secret_in_response($buffer);
    return $buffer;
}

sub format_response {
    my ($response, $local_server) = @_;
    my $response_log = "";

    if (exists($response->{xcatresponse}->[0]->{serverdone})
        && !exists($response->{xcatresponse}->[0]->{error})) {
        return $response_log;
    }

    my $responses;
    if (exists($response->{xcatresponse})) {
        $responses = $response->{xcatresponse};
    } else {
        push @{$responses}, $response;
    }
    return $response_log if ref($responses) ne 'ARRAY' or scalar(@$responses) == 0;

    foreach my $item (@{$responses}) {
        my $rsp = $item;
        my $msgsource = "";
        $msgsource = $rsp->{xcatdsource}->[0] if $rsp->{xcatdsource};
        $msgsource = "" if $local_server eq $msgsource;

        if ($rsp->{error}) {
            if (ref($rsp->{error}) eq 'ARRAY') {
                foreach my $text (@{ $rsp->{error} }) {
                    my $desc = "$text";
                    $desc = "[$msgsource]: $desc" if $desc && $msgsource;
                    $desc = "Error: $desc" unless $rsp->{NoErrorPrefix};
                    $response_log .= "$desc\n";
                }
            } elsif (defined($rsp->{error})) {
                my $desc = $rsp->{error};
                $desc = "[$msgsource]: $desc" if $desc && $msgsource;
                $desc = "Error: $desc" unless $rsp->{NoErrorPrefix};
                $response_log .= "$desc\n";
            }
        }

        if ($rsp->{warning}) {
            if (ref($rsp->{warning}) eq 'ARRAY') {
                foreach my $text (@{ $rsp->{warning} }) {
                    my $desc = "$text";
                    $desc = "[$msgsource]: $desc" if $desc && $msgsource;
                    $desc = "Warning: $desc" unless $rsp->{NoWarnPrefix};
                    $response_log .= "$desc\n";
                }
            } elsif (defined($rsp->{warning})) {
                my $desc = $rsp->{warning};
                $desc = "[$msgsource]: $desc" if $desc && $msgsource;
                $desc = "Warning: $desc" unless $rsp->{NoWarnPrefix};
                $response_log .= "$desc\n";
            }
        }

        if ($rsp->{info}) {
            if (ref($rsp->{info}) eq 'ARRAY') {
                foreach my $text (@{ $rsp->{info} }) {
                    my $desc = "$text";
                    $desc = "[$msgsource]: $desc" if $desc && $msgsource;
                    $response_log .= "$desc\n";
                }
            } else {
                my $desc = $rsp->{info};
                $desc = "[$msgsource]: $desc" if $desc && $msgsource;
                $response_log .= "$desc\n";
            }
        }

        if ($rsp->{sinfo}) {
            if (ref($rsp->{sinfo}) eq 'ARRAY') {
                foreach my $text (@{ $rsp->{sinfo} }) {
                    $response_log .= "$text " if defined $text;
                }
            } elsif (defined($rsp->{sinfo})) {
                $response_log .= $rsp->{sinfo} . " ";
            }
        }

        my $nodes = $rsp->{node};
        $nodes = [$nodes] unless ref $nodes eq 'ARRAY';
        if (scalar @{$nodes}) {
            foreach my $node (@$nodes) {
                my $desc;
                if (ref($node->{name}) eq 'ARRAY') {
                    $desc = $node->{name}->[0];
                } else {
                    $desc = $node->{name};
                }
                if ($node->{error} && defined($node->{error}->[0])) {
                    if ($desc) {
                        $desc = "$desc: [$msgsource]" if $msgsource;
                    } else {
                        $desc = "[$msgsource]" if $msgsource;
                    }
                    $desc .= ": Error: " . $node->{error}->[0];
                }
                if ($node->{warning} && defined($node->{warning}->[0])) {
                    if ($desc) {
                        $desc = "$desc: [$msgsource]" if $msgsource;
                    } else {
                        $desc = "[$msgsource]" if $msgsource;
                    }
                    $desc .= ": Warning: " . $node->{warning}->[0];
                }
                if ($node->{data}) {
                    if ($desc) {
                        $desc = "$desc: [$msgsource]" if $msgsource;
                    } else {
                        $desc = "[$msgsource]" if $msgsource;
                    }
                    if (ref(\($node->{data})) eq 'SCALAR') {
                        $desc = $desc . ": " . $node->{data} if defined $node->{data};
                    } elsif (ref($node->{data}) eq 'HASH') {
                        if ($node->{data}->{desc}) {
                            if (ref($node->{data}->{desc}) eq 'ARRAY') {
                                $desc = $desc . ": " . $node->{data}->{desc}->[0]
                                    if defined $node->{data}->{desc}->[0];
                            } else {
                                $desc = $desc . ": " . $node->{data}->{desc}
                                    if defined $node->{data}->{desc};
                            }
                        }
                        if ($node->{data}->{contents}) {
                            if (ref($node->{data}->{contents}) eq 'ARRAY') {
                                $desc = "$desc: " . $node->{data}->{contents}->[0]
                                    if defined $node->{data}->{contents}->[0];
                            } else {
                                $desc = "$desc: " . $node->{data}->{contents}
                                    if defined $node->{data}->{contents};
                            }
                        }
                    } elsif (ref(\($node->{data}->[0])) eq 'SCALAR') {
                        $desc = $desc . ": " . $node->{data}->[0]
                            if defined $node->{data}->[0];
                    } else {
                        if ($node->{data}->[0]->{desc}
                            && defined($node->{data}->[0]->{desc}->[0])) {
                            $desc = $desc . ": " . $node->{data}->[0]->{desc}->[0];
                        }
                        if ($node->{data}->[0]->{contents}
                            && defined($node->{data}->[0]->{contents}->[0])) {
                            $desc = "$desc: " . $node->{data}->[0]->{contents}->[0];
                        }
                    }
                }
                $response_log .= "$desc\n" if $desc;
            }
        }

        foreach my $key (keys %{$rsp}) {
            next if $key ne 'data';
            if ($rsp->{data}) {
                if (ref($rsp->{data}) eq 'ARRAY') {
                    foreach my $data_entry (@{ $rsp->{data} }) {
                        my $desc;
                        if (ref(\($data_entry)) eq 'SCALAR') {
                            $desc = $data_entry;
                        } else {
                            $desc = $data_entry->{desc}->[0] if $data_entry->{desc};
                            if ($data_entry->{contents}) {
                                if ($desc) {
                                    $desc = "$desc: " . $data_entry->{contents}->[0]
                                        if defined $data_entry->{contents}->[0];
                                } else {
                                    $desc = $data_entry->{contents}->[0];
                                }
                            }
                        }
                        $response_log .= "$desc\n" if $desc;
                    }
                } else {
                    $response_log .= $rsp->{data} . "\n";
                }
            }
        }
    }

    return $response_log;
}

1;
