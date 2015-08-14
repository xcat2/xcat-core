# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle docker
=cut

#-------------------------------------------------------

package xCAT_plugin::docker;

BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use strict;
use POSIX qw(WNOHANG nice);
use POSIX qw(WNOHANG setsid :errno_h);
use IO::Select;
require IO::Socket::SSL; IO::Socket::SSL->import('inet4');
use Time::HiRes qw(gettimeofday sleep);
use Fcntl qw/:DEFAULT :flock/;
use File::Path;
use File::Copy;
use Getopt::Long;
Getopt::Long::Configure("bundling");
use HTTP::Headers;
use HTTP::Request;
use XML::LibXML;
use xCAT::Utils;
use xCAT::MsgUtils;
use Getopt::Long;
use File::Basename;
use Cwd;
use IO::Select;
use xCAT::Usage;

my %globalopt;
my @filternodes;
my $verbose;
my $global_callback;

#-------------------------------------------------------

=head3  send_msg

  Invokes the callback with the specified message

=cut

#-------------------------------------------------------
sub send_msg {

    my $request = shift;
    my $ecode   = shift;
    my $msg     = shift;
    my %output;

    #################################################
    # Called from child process - send to parent
    #################################################
    if ( exists( $request->{pipe} )) {
        my $out = $request->{pipe};

        $output{errorcode} = $ecode;
        $output{data} = \@_;
        print $out freeze( [\%output] );
        print $out "\nENDOFFREEZE6sK4ci\n";
    }
    #################################################
    # Called from parent - invoke callback directly
    #################################################
    elsif ( exists( $request->{callback} )) {
        my $callback = $request->{callback};
        $output{errorcode} = $ecode;
        $output{data} = $msg;
        $callback->( \%output );
    }
}

#-------------------------------------------------------

=head3  handled_commands

  Return list of commands handled by this plugin

=cut

#-------------------------------------------------------
sub handled_commands {
    return( {docker=>"docker"} );
}


#-------------------------------------------------------

=head3  parse_args

  Parse the command line options and operands

=cut

#-------------------------------------------------------
sub parse_args {

    my $request  = shift;
    my $args     = $request->{arg};
    my $cmd      = $request->{command};
    my %opt;

    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage($cmd);
        return( [$_[0], $usage_string] );
    };
    #############################################
    # No command-line arguments - use defaults
    #############################################
    if ( !defined( $args )) {
        return(0);
    }
    #############################################
    # Checks case in GetOptions, allows opts
    # to be grouped (e.g. -vx), and terminates
    # at the first unrecognized option.
    #############################################
    @ARGV = @$args;
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );

    #############################################
    # Process command-line flags
    #############################################
    if (!GetOptions( \%opt,
            qw(h|help V|Verbose v|version))) {
        return( usage() );
    }

    #############################################
    # Option -V for verbose output
    #############################################
    if ( exists( $opt{V} )) {
        $globalopt{verbose} = 1;
    }

    return;
}


#-------------------------------------------------------

=head3  preprocess_request

  preprocess the command

=cut

#-------------------------------------------------------
sub preprocess_request {
    my $req = shift;
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }
    my $callback=shift;
    my $command = $req->{command}->[0];
    my $extrargs = $req->{arg};
    my @exargs=($req->{arg});
    if (ref($extrargs)) {
        @exargs=@$extrargs;
    }
    my $usage_string=xCAT::Usage->parseCommand($command, @exargs);
    if ($usage_string) {
        $callback->({data=>[$usage_string]});
        $req = {};
        return;
    }

    my @result = ();
    my $mncopy = {%$req};
    push @result, $mncopy;
    return \@result;
}

#-------------------------------------------------------

=head3  process_request

  Process the command

=cut

#-------------------------------------------------------
sub process_request {
    my $req      = shift;
    my $callback = shift;
  
    ###########################################
    # Build hash to pass around
    ###########################################
    my %request;
    $request{arg}      = $req->{arg};
    $request{callback} = $callback;
    $request{command}  = $req->{command}->[0];

    ####################################
    # Process command-specific options
    ####################################
    my $result = parse_args( \%request );

    ####################################
    # Return error
    ####################################
    if ( ref($result) eq 'ARRAY' ) {
        send_msg( \%request, 1, @$result );
        return(1);
    }

    return;

}

#-------------------------------------------------------

=head3  genreq

  Generate the docker REST API http request
  Input:
        $dochost: hash, keys: name, port, user, pw
        $method: GET, PUT, POST, DELETE
        $api: the url of rest api
        $content: an xml section which including the data to perform the rest api
  Return:
        The REST API http request
  Usage example:
         my $api = "/images/json";
         my $method = "GET";
         my %dockerhost = ( name => "bybc0604", port => "2375", );
         my $request = genreq(\%dockerhost, $method,$api, "");

=cut

#-------------------------------------------------------
sub genreq {
    my $dochost = shift;
    my $method = shift;
    my $api = shift;
    my $content = shift;

    if (! defined($content)) { $content = ""; }
    my $header = HTTP::Headers->new('content-type' => 'application/xml',
                             'Accept' => 'application/xml',
                             #'Connection' => 'keep-alive',
                             'Host' => $dochost->{name});
    $header->authorization_basic($dochost->{user}.'@internal', $dochost->{pw});

    my $ctlen = length($content);
    $header->push_header('Content-Length' => $ctlen);

    my $url = "https://".$dochost->{name}.":".$dochost->{port}.$api;
    my $request = HTTP::Request->new($method, $url, $header, $content);
    $request->protocol('HTTP/1.1');

    return $request;
}

#-------------------------------------------------------

=head3  send_req

  Make connection to docker daemon
  Send REST api request to docker daemon
  Receive the response from docker daemon
  Handle the error cases

  Input: $dochost: hash, keys: name, port, user, pw
         $ssl_file: hash, keys: ssl_ca_file, ssl_cert_file, ssl_key_file
         $request: the REST API http request


  return: 1-ssl connection error;
          2-http response error;
          3-return a http error message;
          5-operation failed
          $response is the output of docker REST API. 
  Usage example:
          my ($rc, $response) = send_req(\%dockerhost,\%ssl_file,$request->as_string());

=cut

#-------------------------------------------------------
sub send_req {
    my $dochost = shift;
    my $ssl_file = shift;
    my $request = shift;

    my $ssl_ca_file = $ssl_file->{ssl_ca_file};
    my $ssl_cert_file = $ssl_file->{ssl_cert_file};
    my $key_file = $ssl_file->{ssl_key_file};
    my $doc_hostname = $dochost->{name};
    my $port = $dochost->{port};
    my $rc = 0;
    my $response;
    my $connect;
    my $socket = IO::Socket::INET->new( PeerAddr => $doc_hostname,
                                                              PeerPort => $port,
                                                              Timeout => 2,
                                                              Blocking => 0
                                      );
    if ($socket) {
        $connect = IO::Socket::SSL->start_SSL( $socket,
                                                   SSL_verify_mode => SSL_VERIFY_PEER,
                                                   SSL_ca_file => $ssl_ca_file,
                                                   SSL_cert_file =>$ssl_cert_file,
                                                   SSL_key_file => $key_file,
                                                   Timeout => 0
                                      );


        if ($connect) {
            my $flags=fcntl($connect,F_GETFL,0);
            $flags |= O_NONBLOCK;
            fcntl($connect,F_SETFL,$flags);
        } else {
            $rc = 1;
            $response = "Could not make ssl connection to $doc_hostname:$port.";
        }
    } else {
        $rc = 1;
        $response = "Could not create socket to $doc_hostname:$port.";
    }

    if ($rc) {
        return ($rc, $response);
    }

    my $IOsel = new IO::Select;
    $IOsel->add($connect);

    if ($verbose) {
        my $rsp;
        push @{$rsp->{data}}, "\n===================================================\n$request----------------";
        xCAT::MsgUtils->message("I", $rsp, $global_callback);
    }
    print $connect $request;
    $response = "";
    my $retry;
    my $ischunked;
    my $firstnum;
    while ($retry++ < 10) {
        unless ($IOsel->can_read(2)) {
            next;
        }
        my $readbytes;
        my $res = "";
        do { $readbytes=sysread($connect,$res,65535,length($res)); } while ($readbytes);
        if ($res) {
            my @part = split (/\r\n/, $res);
            for my $data (@part) {
              # for chunk formated data, check the last chunk to finish
              if ($data =~ /Transfer-Encoding: (\S+)/) {
                if ($1 eq "chunked") {
                  $ischunked = 1;
                }
              }
              if ($ischunked && $data =~ /^([\dabcdefABCDEF]+)$/) {
                if ($1 eq 0) {
                  # last chunk
                  goto FINISH;
                }else {
                  # continue to get the rest chunks
                  $retry = 0;
                  next;
                }
              } else {
                # put all data together
                $response .= $data;
              }
           }
        }
        unless ($ischunked) {
            # for non chunk data, just read once
            if ($response) {
                last;
            } else {
                if (not defined $readbytes and $! == EAGAIN) { next; }
                $rc = 2;
                last;
            }
        }
    }
FINISH:
    if ($retry >= 10 ) {$rc = 3;}

    if ($verbose) {
        my $rsp;
        push @{$rsp->{data}}, "$response===================================================\n";
        xCAT::MsgUtils->message("I", $rsp, $global_callback);
    }

    $IOsel->remove($connect);
    close($connect);

    if ($response) {
        if (grep (/<html>/, $response)) { # get a error message in the html
            $rc = 3;
        }  elsif (grep (/<\?xml/, $response)) {
            $response =~ s/.*?</</ms;
            my $parser = XML::LibXML->new();
            my $doc = $parser->parse_string($response);
            if ($doc ) {
                my $attr;
                if ($attr = getAttr($doc, "/fault/detail")) {
                    $response = $attr;
                    $rc = 5;
                } elsif ($attr = getAttr($doc, "/action/fault/detail")) {
                    if ($attr eq "[]") {
                        if ($attr = getAttr($doc, "/action/fault/reason")) {
                            $response = $attr;
                        } else {
                            $response = "failed";
                        }
                    } else {
                        $response = $attr;
                    }
                    $rc = 5;
                }
            }
        }
   }

    return ($rc, $response);
}

1;

