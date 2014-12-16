#! /usr/bin/env perl
# IBM(c) 2014 EPL license http://www.eclipse.org/legal/epl-v10.html

# This package offers subroutines to access CIM server

package xCAT::CIMUtils;

use strict;
use warnings;

use HTTP::Headers;
use HTTP::Request;
use LWP::UserAgent;

use XML::LibXML;

=head1 HTTP_PARAMS

    A hash which includes all the parameters for accessing HTTP server. The valid parameter:
        ip:        The IP address of the HTTP server
        user:      The user to access HTTP server. 
        password:  The password for the user. 
        method:    The http method. (GET, PUT, POST, DELETE). Default is GET
        protocol:  The protocol which will be used to access HTTP server.  (http/https). Default is https
        format:    The format of payload. Default is xml
        payload:   The payload of http
        
    Example:
        my %http_params = ( ip       => '192.168.1.1',
                            port     => '5989',
                            user     => 'HMC',
                            password => 'admin',
                            method   => 'POST',
                            protocol => 'https');
        
=cut

=head1 enum_instance ()
    Description:
        Enumerate CIM instances.

    Arguments:
        http_params: A reference to HTTP_PARAMS
        cim_params:  The CIM parameters

    Return:
        A hash reference. The valid key includes:
            rc     - The return code. 0 - success. > 0 - fail.
            msg    - Output message
            value  - ??
=cut


sub enum_instance
{
    my $http_params = shift;
    unless (ref($http_params)) {
        $http_params = shift;
    }
    
    my $cim_params = shift;
    
    # prepare the CIM payload
    my $tmpnode;

    # create a new doc
    my $doc = XML::LibXML->createDocument('1.0','UTF-8');
    
    # create and add the root element
    my $root = $doc->createElement("CIM");
    $root->setAttribute("CIMVERSION", "2.0");
    $root->setAttribute("DTDVERSION", "2.0");
    
    $doc->setDocumentElement($root);
    
    # create and add the MESSAGE element
    my $message = $doc->createElement("MESSAGE");
    $message->setAttribute("ID", "1000");
    $message->setAttribute("PROTOCOLVERSION", "1.0");
    
    $root->addChild($message);
    
    # add a SIMPLE REQUEST
    my $simple_request = $doc->createElement("SIMPLEREQ");
    $message->addChild($simple_request);
    
    # add an IMETHOD CALL
    my $imethod_call = $doc->createElement("IMETHODCALL");
    $imethod_call->setAttribute("NAME", "EnumerateInstances");
    
    $simple_request->addChild($imethod_call);
    
    # add the local name space path
    my $localnamespacepath = $doc->createElement("LOCALNAMESPACEPATH");
    $tmpnode = $doc->createElement("NAMESPACE");
    $tmpnode->setAttribute("NAME", "root");
    $localnamespacepath->addChild($tmpnode);
    
    $tmpnode = $doc->createElement("NAMESPACE");
    $tmpnode->setAttribute("NAME", "ibmsd");
    $localnamespacepath->addChild($tmpnode);
    
    $imethod_call->addChild($localnamespacepath);
    
    # add the target class name
    my $param_classname = $doc->createElement("IPARAMVALUE");
    $param_classname->setAttribute("NAME", "ClassName");
    $imethod_call->addChild($param_classname);
    
    my $classname = $doc->createElement("CLASSNAME");
    $classname->setAttribute("NAME", "IBM_HWCtrlPoint");
    $param_classname->addChild($classname);
    
    # add several common parameters
    $imethod_call->appendWellBalancedChunk('<IPARAMVALUE NAME="DeepInheritance"><VALUE>TRUE</VALUE></IPARAMVALUE><IPARAMVALUE NAME="LocalOnly"><VALUE>FALSE</VALUE></IPARAMVALUE><IPARAMVALUE NAME="IncludeQualifiers"><VALUE>FALSE</VALUE></IPARAMVALUE><IPARAMVALUE NAME="IncludeClassOrigin"><VALUE>TRUE</VALUE></IPARAMVALUE>');
    
    my $payload = $doc->toString();
    

    # generate http request
    my $ret = gen_http_request($http_params, $payload);

    if ($ret->{rc}) {
        return $ret;
    }

    # send request to http server
    $ret = send_http_request($http_params, $ret->{request});
    if ($ret->{rc}) {
        return $ret;
    }

    
    # parse the http response
    print $ret->{payload};
}


=head1 gen_http_request ()
    Description:
        Generate a http request.

    Arguments: 
        http_params: A reference to HTTP_PARAMS
        payload:     The payload for the http request. It can be null if the payload has been set in http_params.

    Return:
        A hash reference. The valid key includes:
            rc      - The return code. 0 - success. > 0 - fail.
            msg     - Output message 
            request - The generated HTTP::Request object
=cut

sub gen_http_request
{
    my $http_params = shift;
    my $http_payload = shift;
    
    # check the mandatory parameters
    unless (defined ($http_params->{ip}) && defined ($http_params->{port}) && defined($http_params->{user}) && defined($http_params->{password})) {
        return ({rc => 1, msg => "Miss the mandatory parameters: ip, port, user or password"});
    }

    # set the default value for parameters
    unless (defined ($http_params->{protocol})) {
        $http_params->{protocol} = 'https';
    }
    unless (defined ($http_params->{format})) {
        $http_params->{format} = 'xml';
    }
    unless (defined ($http_params->{method})) {
        $http_params->{method} = 'GET';
    }

    my $payload = '';
    if (defined ($http_params->{payload})) {
        $payload = $http_params->{payload};
    }
    if (defined ($http_payload)) {
        unless (ref($http_payload)) { #Todo: support payloasd to be a hash
            $payload = $http_payload;
        }
    }

    # create the http head
    my $header = HTTP::Headers->new('content-type' => "application/$http_params->{format}",
                                    'Accept' => "application/$http_params->{format}",
                                    'User-Agent' => "xCAT/2",
                                    'Host' => "$http_params->{ip}:$http_params->{port}");

    # set the user & password
    $header->authorization_basic($http_params->{user}, $http_params->{password});

    # set the length of payload
    my $plen = length($payload);
    $header->push_header('Content-Length' => $plen);

    # create the URL
    my $url = "$http_params->{protocol}://$http_params->{ip}:$http_params->{port}";
    my $request = HTTP::Request->new($http_params->{method}, $url, $header, $payload);

    # set the http version
    $request->protocol('HTTP/1.1');

    return ({rc => 0, request => $request});
}


=head1 send_http_request ()
    Description:
        Send http request to http server and waiting for the response.

    Arguments:
        http_params:  A reference to HTTP_PARAMS
        http_request: A HTTP::Request object

    Return:
        A hash reference. The valid key includes:
            rc      - The return code. 0 - success. > 0 - fail.
            http_rc - The return code of http. 200, 400 ...
            msg     - Output message
            payload - The http response from http server
=cut

sub send_http_request
{
    my $http_params = shift;
    my $http_request = shift;

    # Load the library LWP::Protocol::https for https support
    if ($http_params->{protocol} eq 'https') {
        eval { require LWP::Protocol::https};
        if ($@) {
            return ({rc => 1, msg => "Failed to load perl library LWP::Protocol::https"});
        }
    }

    # create a new HTTP User Agent Object
    my $ua = LWP::UserAgent->new(ssl_opts => { verify_hostname => 0 });
    $ua->timeout(10);

    # send request and receive the response
    my $response = $ua->request($http_request);

    # check the http response
    if (defined ($response) && defined ($response->{_rc}) && defined ($response->{_msg})) {
        if ($response->{_rc} eq "200" && $response->{_msg} eq "OK") {
            return ({rc => 0, http_rc => $response->{_rc}, payload => $response->{_content}});
        }
    }
    
    return ({rc => 1, http_rc => $response->{_rc}, msg => $response->{_msg}});
}



1;
