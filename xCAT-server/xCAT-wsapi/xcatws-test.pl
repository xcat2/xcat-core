#!/usr/bin/env perl
# IBM(c) 2014 EPL license http://www.eclipse.org/legal/epl-v10.html

# This is a command which can be used to access the rest api of xCAT

use strict;
use Getopt::Long;
use LWP;
use JSON;
require HTTP::Request;

# set the usage message
my $usage_string = "Usage:
    restapi -u url -m GET|PUT|POST|DELETE [-f html|json|xml] [-V]
      -u The url of the action. .e.g to get the power status of node \'nodename\' https://httpserver/xcatws/nodes/nodename/power 
      -m The method of the request
      -h The hostname of the xCAT web server
      -o Target object
      -f The output format of the requested action
      -V Display the verbose message\n";

#todo: make the code below into functions so that this file can be used for 2 purposes:
#       1. contain all the test cases that can all be run at once
#       2. if arguments are passed in, run the one api call passed in

# Parse the argument
$Getopt::Long::ignorecase = 0;
Getopt::Long::Configure( "bundling" );
if (!GetOptions( 'u=s'   => \$::URL,
                       'f=s'   => \$::FORMAT,
                      'h=s'   => \$::HOST,
                      'o=s'   => \$::OBJ,
	              'm=s'  => \$::METHOD,
                       'V'     => \$::VERBOSE )) {
    print $usage_string;
    exit 1;
}

if (defined($::FORMAT)) {
    if ($::FORMAT eq "") {
      $::FORMAT = "html";
    } elsif ($::FORMAT !~ /^(html|json|xml)$/) {
      print $usage_string;
      exit 1;
    }
}
else{
    $::FORMAT = "html";
}

if (defined($::METHOD)){
    if ($::METHOD !~/^(GET|PUT|POST|DELETE)$/){
	print $usage_string;
	exit 1;
    }
}
else{
    print $usage_string;
    exit 1;
}

if (!$::URL) {
    if ($::HOST && $::OBJ) {
        $::URL = "https://$::HOST/xcatws/$::OBJ?format=$::FORMAT";
    } else {
        print $usage_string;
        exit 1;
    }
} else {
    if ($::URL =~ /\?/){
	$::URL .= "&format=$::FORMAT";
    }
    else{
	$::URL .= "?format=$::FORMAT";
    }
}

my @updatearray;
my $fieldname;
my $fieldvalue;
if (scalar(@ARGV) > 0){
    foreach my $tempstr (@ARGV){
        push @updatearray, $tempstr;
    }
}

my $request;

my $ua = LWP::UserAgent->new();
my $response;
if (($::METHOD eq 'PUT') || ($::METHOD eq 'POST')){
    my $tempstr = encode_json \@updatearray;
    $request = HTTP::Request->new($::METHOD => $::URL);
    $request->header('content-type' => 'text/plain');
    $request->header('content-length' => length($tempstr));
    $request->content($tempstr);
}
elsif(($::METHOD eq 'GET'|| ($::METHOD eq 'DELETE'))){
    $request = HTTP::Request->new($::METHOD=>$::URL);
}

my $response = $ua->request($request);

print $response->content . "\n";
print $response->code . "\n";
print $response->message . "\n";

