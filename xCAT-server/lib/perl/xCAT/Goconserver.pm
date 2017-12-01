#!/usr/bin/perl
## IBM(c) 2107 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::Goconserver;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use warnings "all";

use HTTP::Request;
use HTTP::Headers;
use LWP;
use JSON;
use IO::Socket::SSL qw( SSL_VERIFY_PEER );

sub http_request {
    my ($method, $url, $data) = @_;
    my @user          = getpwuid($>);
    my $homedir       = $user[7];
    my $rsp;
    my $brower = LWP::UserAgent->new( ssl_opts => {
            SSL_key_file    => xCAT::Utils->getHomeDir() . "/.xcat/client-cred.pem",
            SSL_cert_file   => xCAT::Utils->getHomeDir() . "/.xcat/client-cred.pem",
            SSL_ca_file     => xCAT::Utils->getHomeDir() . "/.xcat/ca.pem",
            SSL_use_cert    => 1,
            SSL_verify_mode => SSL_VERIFY_PEER,  }, );
    my $header = HTTP::Headers->new('Content-Type' => 'application/json');
    #    $data = encode_json $data if defined($data);
    $data = JSON->new->encode($data) if defined($data);
    my $request = HTTP::Request->new( $method, $url, $header, $data );
    my $response = $brower->request($request);
    if (!$response->is_success()) {
        xCAT::MsgUtils->message("S", "Failed to send request to $url, rc=".$response->status_line());
        return undef;
    }
    my $content = $response->content();
    if ($content) {
        return decode_json $content;
    }
    return "";
}

sub delete_nodes {
    my ($api_url, $node_map, $delmode, $callback) = @_;
    my $url = "$api_url/bulk/nodes";
    my @a = ();
    my ($data, $rsp, $ret);
    $data->{nodes} = \@a;
    foreach my $node (keys %{$node_map}) {
        my $temp;
        $temp->{name} = $node;
        push @a, $temp;
    }
    $ret = 0;
    my $response = http_request("DELETE", $url, $data);
    if (!defined($response)) {
        $rsp->{data}->[0] = "Failed to send delete request.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    } elsif ($delmode) {
        while (my ($k, $v) = each %{$response}) {
            if ($v ne "Deleted") {
                $rsp->{data}->[0] = "$k: Failed to delete entry in goconserver: $v";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                $ret = 1;
            } else {
                $rsp->{data}->[0] = "$k: $v";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }
        }
    }
    return $ret;
}

sub create_nodes {
    my ($api_url, $node_map, $callback) = @_;
    my $url = "$api_url/bulk/nodes";
    my ($data, $rsp, @a, $ret);
    $data->{nodes} = \@a;
    while (my ($k, $v) = each %{$node_map}) {
        push @a, $v;
    }
    $ret = 0;
    my $response = http_request("POST", $url, $data);
    if (!defined($response)) {
        $rsp->{data}->[0] = "Failed to send create request.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    } elsif ($response) {
        while (my ($k, $v) = each %{$response}) {
            if ($v ne "Created") {
                $rsp->{data}->[0] = "$k: Failed to create console entry in goconserver: $v";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                $ret = 1;
            } else {
                $rsp->{data}->[0] = "$k: $v";
                xCAT::MsgUtils->message("I", $rsp, $::callback);
            }
        }
    }
    return $ret;
}

1;