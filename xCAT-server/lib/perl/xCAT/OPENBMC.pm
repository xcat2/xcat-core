#!/usr/bin/perl
## IBM(c) 2107 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::OPENBMC;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use warnings "all";

use HTTP::Async;
use HTTP::Request;
use HTTP::Headers;
use HTTP::Cookies;
use Data::Dumper;

my $header = HTTP::Headers->new('Content-Type' => 'application/json');

sub new {
    my $async = shift;
    $async = shift if (($async) && ($async =~ /OPENBMC/));
    my $url = shift;
    my $content = shift;
    my $method = 'POST';

    my $id = send_request( $async, $method, $url, $content );

    return $id;
}

sub send_request {
    my $async = shift;
    $async = shift if (($async) && ($async =~ /OPENBMC/));
    my $method = shift;
    my $url = shift;
    my $content = shift;

    my $request = HTTP::Request->new( $method, $url, $header, $content );
    my $id = $async->add_with_opts($request, {});
    return $id;
}

1;
