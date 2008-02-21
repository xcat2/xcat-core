#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::Client;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::NodeRange;
use xCAT::Utils;
use xCAT::Table;

use IO::Socket::SSL;
if (xCAT::Utils->isLinux()) {
        eval { require Socket6 };
        eval { require IO::Socket::INET6 };
        eval { require IO::Socket::SSL::inet6 };
} else {

        eval { require Socket };
        eval { require IO::Socket::INET };
}

use XML::Simple;
use Data::Dumper;
use Storable qw(dclone);
my $xcathost='localhost:3001';
my $plugins_dir;
my %resps;
my $EXITCODE;     # save the bitmask of all exit codes returned by calls to handle_response()
1;


#################################
# submit_request will take an xCAT command and pass it to the xCAT
#   server for execution.
#
# If the XCATBYPASS env var is set, the connection to the server/daemon
#   will be bypassed and the plugin will be called directly.  If it is
#   set to one or more directories (separated by ":"), all perl modules
#   in those directories will be loaded in as plugins (for duplicate
#   commands, last one in wins). If it is set to any other value
#   (e.g. "yes", "default", whatever string you want) the default plugin
#   directory /opt/xcat/lib/perl/xCAT_plugin will be used.
#
# Input:
#    Request hash - A hash ref containing the input command and args to be
#       passed to the plugin.  The the xcatd daemon (or this routine when
#       XCATBYPASS) reads the {noderange} entry and builds a flattened array
#       of nodes that gets added as request->{node}
#       The format for the request hash is:
#          { command => [ 'xcatcmd' ],
#            noderange => [ 'noderange_string' ],
#            arg => [ 'arg1', 'arg2', '...', 'argn' ]
#          }
#    Callback - A subroutine ref that will be called to process the output
#       from the plugin.
#
# NOTE:  The request hash will get converted to XML when passed to the
#        xcatd daemon, and will get converted back to a hash before being
#        passed to the plugin.  The XMLin ForceArray option is used to
#        force all XML constructs to be arrays so that the plugin code
#        and callback routines can access the data consistently.
#        The input request and the response hash created by the plugin should
#        always create hashes with array values.
#################################
sub submit_request {
  my $request = shift;
  my $callback = shift;
  my $keyfile = shift;
  my $certfile = shift;
  my $cafile = shift;
  unless ($keyfile) { $keyfile = $ENV{HOME}."/.xcat/client-key.pem"; }
  unless ($certfile) { $certfile = $ENV{HOME}."/.xcat/client-cert.pem"; }
  unless ($cafile) { $cafile  = $ENV{HOME}."/.xcat/ca.pem"; }
  $xCAT::Client::EXITCODE = 0;    # clear out exit code before invoking the plugin


# If XCATBYPASS is set, invoke the plugin process_request method directly
# without going through the socket connection to the xcatd daemon
  if ($ENV{XCATBYPASS}) {
   # Load plugins from either specified or default dir
    my %cmd_handlers;
    my @plugins_dirs = split('\:',$ENV{XCATBYPASS});
    if (-d $plugins_dirs[0]) {
       foreach (@plugins_dirs) {
          $plugins_dir = $_;
          scan_plugins();
       }
    } else {
       # figure out default plugins dir
       my $sitetab=xCAT::Table->new('site');
       unless ($sitetab) {
         print ("ERROR: Unable to open basic site table for configuration\n");
       }
       $plugins_dir=$::XCATROOT.'/lib/perl/xCAT_plugin';
       scan_plugins();
    }

  #  don't do XML transformation -- assume request is well-formed
  #  my $xmlreq=XMLout($request,RootName=>xcatrequest,NoAttr=>1,KeyAttr=>[]);
  #  $request = XMLin($xmlreq,SuppressEmpty=>undef,ForceArray=>1) ;


    # Call the plugin directly
 #   ${"xCAT_plugin::".$modname."::"}{process_request}->($request,$callback);
    plugin_command($request,undef,$callback);
    return 0;
  }

# No XCATBYPASS, so establish a socket connection with the xcatd daemon
# and submit the request
  if ($ENV{XCATHOST}) {
    $xcathost=$ENV{XCATHOST};
  }
  my $client = IO::Socket::SSL->new(
    PeerAddr => $xcathost,
    SSL_key_file => $keyfile,
    SSL_cert_file => $certfile,
    SSL_ca_file => $cafile,
    SSL_use_cert => 1,
    );
  die "Connection failure: $@ (SSL Timeout may mean the credentials in ~/.xcat are incorrect)\n" unless ($client);
  my $msg=XMLout($request,RootName=>xcatrequest,NoAttr=>1,KeyAttr=>[]);
  print $client $msg;
  my $response;
  my $rsp;
  while (<$client>) {
    $response .= $_;
    if ($response =~ m/<\/xcatresponse>/) {
      $rsp = XMLin($response,SuppressEmpty=>undef,ForceArray=>1);
      $response='';
      $callback->($rsp);
      if ($rsp->{serverdone}) {
        last;
      }
    }
  }

###################################
# scan_plugins
#    will load all plugin perl modules and build a list of supported
#    commands
#
# NOTE:  This is copied from xcatd (last merge 10/3/07).
#        Will eventually move to using common source....
###################################
sub scan_plugins {
  my @plugins=glob($plugins_dir."/*.pm");
  foreach (@plugins) {
    /.*\/([^\/]*).pm$/;
    my $modname = $1;
    require "$_";
    no strict 'refs';
    my $cmd_adds=${"xCAT_plugin::".$modname."::"}{handled_commands}->();
    foreach (keys %$cmd_adds) {
      my $value = $_;
      if (defined($cmd_handlers{$_})) {
        my $add=1;
        #This next bit of code iterates through the handlers.
        #If the value doesn't contain an equal, and has an equivalent entry added by
        # another plugin already, don't add (otherwise would hit the DB multiple times)
        # a better idea, restructure the cmd_handlers as a multi-level hash
        # prove out this idea real quick before doing that
        foreach (@{$cmd_handlers{$_}}) {
          if (($_->[1] eq $cmd_adds->{$value}) and (($cmd_adds->{$value} !~ /=/) or ($_->[0] eq $modname))) {
            $add = 0;
          }
        }
        if ($add) { push @{$cmd_handlers{$_}},[$modname,$cmd_adds->{$_}]; }
        #die "Conflicting handler information from $modname";
      } else {
        $cmd_handlers{$_} = [ [$modname,$cmd_adds->{$_}] ];
      }
    }
  }
}



###################################
# plugin_command
#    will invoke the correct plugin
#
# NOTE:  This is copied from xcatd (last merge 10/3/07).
#        Will eventually move to using common source....
###################################
sub plugin_command {
  my $req = shift;
  my $sock = shift;
  my $callback = shift;
  my %handler_hash;
#  use xCAT::NodeRange;
  $Main::resps={};
  my @nodes;
  if ($req->{node}) {
    @nodes = @{$req->{node}};
  } elsif ($req->{noderange}) {
    @nodes = noderange($req->{noderange}->[0]);
    if (nodesmissed) {
#     my $rsp = {errorcode=>1,error=>"Invalid nodes in noderange:".join(',',nodesmissed)};
      print "Invalid nodes in noderange:".join(',',nodesmissed)."\n";
#     if ($sock) {
#       print $sock XMLout($rsp,RootName=>'xcatresponse' ,NoAttr=>1);
#     }
#     return ($rsp);
      return 1;
    }
  }
  if (@nodes) { $req->{node} = \@nodes; }
  if (defined($cmd_handlers{$req->{command}->[0]})) {
    my $hdlspec;
    foreach (@{$cmd_handlers{$req->{command}->[0]}}) {
      $hdlspec =$_->[1];
      my $ownmod = $_->[0];
      if ($hdlspec =~ /:/) { #Specificed a table lookup path for plugin name
        my $table;
        my $cols;
        ($table,$cols) = split(/:/,$hdlspec);
        my @colmns=split(/,/,$cols);
        my @columns;
        my $hdlrtable=xCAT::Table->new($table);
        unless ($hdlrtable) {
          #TODO: proper error handling
        }
        my $node;
        my $colvals = {};
        foreach my $colu (@colmns) {
          if ($colu =~ /=/) { #a value redirect to a pattern/specific name
            my $coln; my $colv;
            ($coln,$colv) = split(/=/,$colu,2);
            $colvals->{$coln} = $colv;
            push (@columns,$coln);
          } else {
            push (@columns,$colu);
          }
        }

        foreach $node (@nodes) {
          my $attribs = $hdlrtable->getNodeAttribs($node,\@columns);
          unless (defined($attribs)) { next; } #TODO: This really ought to craft an unsupported response for this request
          foreach (@columns) {
            my $col=$_;
            if (defined($attribs->{$col})) {
              if ($colvals->{$col}) { #A pattern match style request.
                if ($attribs->{$col} =~ /$colvals->{$col}/) {
                  $handler_hash{$ownmod}->{$node} = 1;
                  last;
                }
              } else {
                $handler_hash{$attribs->{$col}}->{$node} = 1;
                last;
              }
            }
          }
        }
      } else {
        unless (@nodes) {
          $handler_hash{$hdlspec} = 1;
        }
        foreach (@nodes) { #Specified a specific plugin, not a table lookup
          $handler_hash{$hdlspec}->{$_} = 1;
        }
      }
    }
  } else {
    print "$req->{command}->[0] xCAT command not found \n";
    return 1;  #TODO: error back that request has no known plugin for it
  }

## FOR NOW, DON'T FORK CHILD PROCESS TO MAKE BYPASS SIMPLER AND EASIER TO DEBUG
# my $children=0;
# $SIG{CHLD} = sub {while (waitpid(-1, WNOHANG) > 0) { $children--; } };
# my $check_fds;
# if ($sock) {
#   $check_fds = new IO::Select;
# }
  foreach (keys %handler_hash) {
    my $modname = $_;
    if (-r $plugins_dir."/".$modname.".pm") {
      require $plugins_dir."/".$modname.".pm";
#     $children++;
#     my $pfd; #will be referenced for inter-process messaging.
#     my $child;
#     if ($sock) { #If $sock not passed in, don't fork..
#       socketpair($pfd, $parent_fd,AF_UNIX,SOCK_STREAM,PF_UNSPEC) or die "socketpair: $!";
#       #pipe($pfd,$cfd);
#       $parent_fd->autoflush(1);
#       $pfd->autoflush(1);
#       $child = fork;
#     } else {
#       $child = 0;
#     }
#     unless (defined $child) { die "Fork failed"; }
#     if ($child == 0) {
#       if ($sock) { close $pfd; }
        unless ($handler_hash{$_} == 1) {
          my @nodes = sort {($a =~ /(\d+)/)[0] <=> ($b =~ /(\d+)/)[0] || $a cmp $b } (keys %{$handler_hash{$_}});
          $req->{node}=\@nodes;
        }
        no strict  "refs";
        ${"xCAT_plugin::".$modname."::"}{process_request}->($req,$callback,\&do_request);
#       if ($sock) {
#         close($parent_fd);
#         exit(0);
#       }
#     } else {
#       close $parent_fd;
#       $check_fds->add($pfd);
#     }
    }
  }
  unless ($sock) { return $Main::resps };
# while ($children > 0) {
#   relay_fds($check_fds,$sock);
# }
# #while (relay_fds($check_fds,$sock)) {}
# my %done;
# $done{serverdone} = {};
# if ($req->{transid}) {
#   $done{transid}=$req->{transid}->[0];
# }
# if ($sock) { print $sock XMLout(\%done,RootName => 'xcatresponse',NoAttr=>1); }
}



###################################
# do_request
#    called from a plugin to execute another xCAT plugin command internally
#
# NOTE:  This is copied from xcatd (last merge 10/3/07).
#        Will eventually move to using common source....
###################################
sub do_request {
  my $req = shift;
  my $second = shift;
  my $rsphandler = \&build_response;
  my $sock = undef;
  if ($second) {
    if (ref($second) eq "CODE") {
      $rsphandler = $second;
    } elsif (ref($second) eq "GLOB") {
      $sock = $second;
    }
  }

  #my $sock = shift; #If no sock, will return a response hash
  if ($cmd_handlers{$req->{command}->[0]}) {
     return plugin_command($req,$sock,$rsphandler);
  } elsif ($req->{command}->[0] eq "noderange" and $req->{noderange}) {
     my @nodes = noderange($req->{noderange}->[0]);
     my %resp;
     if (nodesmissed) {
       $resp{warning}="Invalid nodes in noderange:".join ',',nodesmissed ."\n";
     }
     $resp{serverdone} = {};
     @{$resp{node}}=@nodes;
     if ($req->{transid}) {
       $resp{transid}=$req->{transid}->[0];
     }
     if ($sock) {
       print $sock XMLout(\%resp,RootName => 'xcatresponse',NoAttr=>1);
     } else {
       return (\%resp);
     }
  } else {
     my %resp=(error=>"Unsupported request");
     $resp{serverdone} = {};
     if ($req->{transid}) {
       $resp{transid}=$req->{transid}->[0];
     }
     if ($sock) {
       print $sock XMLout(\%resp,RootName => 'xcatresponse',NoAttr=>1);
     } else {
       return (\%resp);
     }
  }
}


###################################
# build_response
#   This callback handles responses from nested level plugin calls.
#   It builds a merged hash of all responses that gets passed back
#   to the calling plugin.
#   Note:  Need to create a "deep clone" of this response to add to the
#     return, otherwise next time through the referenced data is overwritten
#
###################################
sub build_response {
  my $rsp = shift;
  foreach (keys %$rsp) {
    my $subresp = dclone($rsp->{$_});
    push (@{$Main::resps->{$_}}, @{$subresp});
  }
}



}    # end of submit_request()



##########################################
# handle_response is a default callback that can be passed into submit_response()
# It is invoked repeatedly by submit_response() to print out the data returned by
# the plugin.
#
# The normal flow is:
#	-> client cmd (e.g. nodels, which is just a link to xcatclient)
#		-> xcatclient
#			-> submit_request()
#				-> send xml request to xcatd
#					-> xcatd
#						-> process_request() of the plugin
#						<- plugin callback
#					<- xcatd
#				<- xcatd sends xml response to client
#			<- submit_request() read response
#		<- handle_response() prints responses and saves exit codes
#	<- xcatclient gets exit code and exits
#
# But in XCATBYPASS mode, the flow is:
#	-> client cmd (e.g. nodels, which is just a link to xcatclient)
#		-> xcatclient
#			-> submit_request()
#				-> process_request() of the plugin
#		<- handle_response() prints responses and saves exit codes
#	<- xcatclient gets exit code and exits
#
# Format of the response hash:
#  {data => [ 'data str1', 'data str2', '...' ] }
#
#    Results are printed as:
#       data str1
#       data str2
#
# or:
#  {data => [ {desc => [ 'desc1' ],
#              contents => [ 'contents1' ] },
#             {desc => [ 'desc2 ],
#              contents => [ 'contents2' ] }
#                :
#            ] }
#    NOTE:  In this format, only the data array can have more than one
#           element. All other arrays are assumed to be a single element.
#    Results are printed as:
#       desc1: contents1
#       desc2: contents2
#
# or:
#  {node => [ {name => ['node1'],
#              data => [ {desc => [ 'node1 desc' ],
#                         contents => [ 'node1 contents' ] } ] },
#             {name => ['node2'],
#              data => [ {desc => [ 'node2 desc' ],
#                         contents => [ 'node2 contents' ] } ] },
#                :
#             ] }
#    NOTE:  Only the node array can have more than one element.
#           All other arrays are assumed to be a single element.
#
#    This was generated from the corresponding XML:
#    <xcatrequest>
#      <node>
#        <name>node1</name>
#        <data>
#          <desc>node1 desc</desc>
#          <contents>node1 contents</contents>
#        </data>
#      </node>
#      <node>
#        <name>node2</name>
#        <data>
#          <desc>node2 desc</desc>
#          <contents>node2 contents</contents>
#        </data>
#      </node>
#    </xcatrequest>
#
#   Results are printed as:
#      node_name: desc: contents
##########################################
sub handle_response {
  my $rsp = shift;
#print "in handle_response\n";
  # Handle errors
  if ($rsp->{errorcode}) {
    if (ref($rsp->{errorcode}) eq 'ARRAY') { foreach my $ecode (@{$rsp->{errorcode}}) { $xCAT::Client::EXITCODE |= $ecode; } }
    else { $xCAT::Client::EXITCODE |= $rsp->{errorcode}; }   # assume it is a non-reference scalar
  }
  if ($rsp->{error}) {
#print "printing error\n";
  	if (ref($rsp->{error}) eq 'ARRAY') { foreach my $text (@{$rsp->{error}}) { print "Error: $text\n"; } }
  	else { print ("Error: ".$rsp->{error}."\n"); }
  }
  if ($rsp->{warning}) {
#print "printing warning\n";
  	if (ref($rsp->{warning}) eq 'ARRAY') { foreach my $text (@{$rsp->{warning}}) { print "Warning: $text\n"; } }
  	else { print ("Warning: ".$rsp->{warning}."\n"); }
  }
  if ($rsp->{info}) {
#print "printing info\n";
  	if (ref($rsp->{info}) eq 'ARRAY') { foreach my $text (@{$rsp->{info}}) { print "$text\n"; } }
  	else { print ($rsp->{info}."\n"); }
  }

  # Handle {node} structure
  if (scalar @{$rsp->{node}}) {
#print "printing node\n";
    my $nodes=($rsp->{node});
    my $node;
    foreach $node (@$nodes) {
      my $desc=$node->{name}->[0];
      if ($node->{errorcode}) {
        if (ref($node->{errorcode}) eq 'ARRAY') { foreach my $ecode (@{$node->{errorcode}}) { $xCAT::Client::EXITCODE |= $ecode; } }
    	else { $xCAT::Client::EXITCODE |= $node->{errorcode}; }   # assume it is a non-reference scalar
      }
      if ($node->{data}) {
         if (ref(\($node->{data}->[0])) eq 'SCALAR') {
            $desc=$desc.": ".$node->{data}->[0];
         } else {
            if ($node->{data}->[0]->{desc}) {
              $desc=$desc.": ".$node->{data}->[0]->{desc}->[0];
            }
            if ($node->{data}->[0]->{contents}) {
        $desc="$desc: ".$node->{data}->[0]->{contents}->[0];
            }
         }
      }
      if ($desc) {
         print "$desc\n";
      }
    }
  }

  # Handle {data} structure with no nodes
  if ($rsp->{data}) {
#print "printing data\n";
    my $data=($rsp->{data});
    my $data_entry;
    foreach $data_entry (@$data) {
      my $desc;
         if (ref(\($data_entry)) eq 'SCALAR') {
            $desc=$data_entry;
         } else {
            if ($data_entry->{desc}) {
              $desc=$data_entry->{desc}->[0];
            }
            if ($data_entry->{contents}) {
               if ($desc) {
           $desc="$desc: ".$data_entry->{contents}->[0];
               } else {
           $desc=$data_entry->{contents}->[0];
            }
         }
      }
      if ($desc) { print "$desc\n"; }
    }
  }
}      # end of handle_response






