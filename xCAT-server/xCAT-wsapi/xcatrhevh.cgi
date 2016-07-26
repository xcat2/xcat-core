#!/usr/bin/perl

# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

use strict;
use CGI qw/:standard/;
use Socket;
use IO::Socket::INET;
use IO::Socket::SSL; IO::Socket::SSL->import('inet4');


my $q        = CGI->new;
my $url      = $q->url;
my $pathInfo = $q->path_info;
my $peerAdd  = $q->remote_addr;

my $iaddr = inet_aton($peerAdd);
my $peerhost = gethostbyaddr($iaddr, AF_INET);
$peerhost =~ s/\..*//;

if ($pathInfo =~ /^\/rhevh_finish_install\/(.*)$/) {
    if ($1 eq $peerhost) {
        &rhevhupdateflag($peerhost);
        my $cmd = "rhevhupdateflag";
    }
}

# check mapping of the IP and hostname

sub rhevhupdateflag {
    my $node = shift;


    my $socket = IO::Socket::INET->new(
        PeerAddr => "127.0.0.1",
        PeerPort => '3001',
        Timeout  => 15,);
    my $client;
    if ($socket) {
        $client = IO::Socket::SSL->start_SSL($socket,
            Timeout => 0,
        );
    }

    my $req1 = "<xcatrequest><command>rhevhupdateflag</command><noderange>";
    my $req2 = "</noderange></xcatrequest>";
    my $req  = $req1 . $node . $req2;

    print $client $req;
}

