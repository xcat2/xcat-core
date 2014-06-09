#!/usr/bin/env perl
# IBM(c) 2014 EPL license http://www.eclipse.org/legal/epl-v10.html
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

use strict;
use warnings;

package Confluent::TLV;

use JSON;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};
    $self->{handle} = shift;
    $self->{json} = JSON->new;
    bless($self, $class);
    return $self;
}

sub recv {
    my $self = shift;
    my $data;
    my $tl = '';
    do {
        sysread($self->{handle}, $data, 4 - length($tl));
        $tl .= $data;
    } while (length($tl) < 4);
    $tl = unpack("N", $tl);
    if ($tl & (1 << 31)) {
        die "Reserved bit used, protocol violated";
    }
    my $length = $tl & 16777215;  # lower 24 bits only
    my $datatype = ($tl >> 24);
    my $bytedata = '';
    while (length($bytedata) < $length) {
        sysread($self->{handle}, $data, $length - length($bytedata));
        $bytedata .= $data;
    }
    if ($datatype == 0) {
        return $bytedata;
    } elsif ($datatype == 1) {
        return $self->{json}->utf8->decode($bytedata);
    } else {
        die "Unexpected data type $datatype";
    }
}

sub send {
    my $self = shift;
    my $data = shift;
    if (ref $data eq 'HASH') {  # Need to do JSON
        my $json = $self->{json}->utf8->encode($data);
        my $typelength = length($json);
        if ($typelength > 16777215) {
            die "Data too large";
        }
        $typelength |= 16777216;
        my $handle = $self->{handle};
        print $handle pack("N", $typelength) . $json;
        $self->{handle}->flush();
    } elsif (not ref $data) {  # text data
        my $typelength = length($data);
        if ($typelength > 16777215) {
            die "Data too large";
        }
        my $handle = $self->{handle};
        print $handle pack("N", $typelength) . $data;
        $self->{handle}->flush();
    }
}

1;
