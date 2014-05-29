#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::Client;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}

# if AIX - make sure we include perl 5.8.2 in INC path.
#       Needed to find perl dependencies shipped in deps tarball.
use Storable qw/nstore_fd fd_retrieve/;
if ($^O =~ /^aix/i) {
	unshift(@INC, qw(/usr/opt/perl5/lib/5.8.2/aix-thread-multi /usr/opt/perl5/lib/5.8.2 /usr/opt/perl5/lib/site_perl/5.8.2/aix-thread-multi /usr/opt/perl5/lib/site_perl/5.8.2));
}
use IO::Handle;

my $inet6support;
if ($^O =~ /^aix/i) {  # disable AIX IPV6  TODO fix
 $inet6support = 0;
} else {
  $inet6support=eval { require Socket6; 1; };
}
if ($inet6support) {
   $inet6support = eval { require IO::Socket::INET6; 1; };
}
if ($inet6support) {
   $inet6support = eval { require IO::Socket::SSL; IO::Socket::SSL->import('inet6'); 1;};
}

if ($^O =~ /^linux/i) {
    # Is IPv6 enabled on the MN or xcat client node at all?
    my $ipv6enabled = `ip addr 2> /dev/null | grep inet6`;
    if (!$ipv6enabled) {
        $inet6support = 0;
    }
}

unless ($inet6support) {
  eval { require Socket };
  eval { require IO::Socket::INET };
  eval { require IO::Socket::SSL; IO::Socket::SSL->import('inet4') };
}


use XML::Simple; #smaller than libxml....
use Fcntl;
use POSIX qw/:errno_h/;
use IO::Select;
$XML::Simple::PREFERRED_PARSER='XML::Parser';
#require Data::Dumper;
my $xcathost='localhost:3001';
my $plugins_dir;
my %resps;
my $EXITCODE;     # save the bitmask of all exit codes returned by calls to handle_response()
1;


sub rspclean {
      my $response = shift;
      my $callback = shift;
      my $rsps = XMLin($response,SuppressEmpty=>undef,ForceArray=>1);
	foreach my $rsp (@{$rsps->{xcatresponse}}) {
      #add ESC back
      foreach my $key (keys %$rsp) {
	  if (ref($rsp->{$key}) eq 'ARRAY') { 
              foreach my $text (@{$rsp->{$key}}) {
                  next unless defined $text;
                  $text =~ s/xxxxESCxxxx/\e/g;
              }
          }
	  else {
              $rsp->{$key} =~ s/xxxxESCxxxx/\e/g;
          }
      }
      $callback->($rsp);
      if ($rsp->{serverdone}) {
         return 1;
      }
	}
	return 0;
}
sub send_request {
    my $request = shift;
    my $sock = shift;
    my $encode = shift;
    if ($encode eq "xml") {
        my $msg=XMLout($request,RootName=>'xcatrequest',NoAttr=>1,KeyAttr=>[]);
        if ($ENV{XCATXMLTRACE}) { print $msg; }
        if($ENV{XCATXMLWARNING}) {
            validateXML($msg);
        }
        print $sock $msg;
        $sock->flush();
    } else {
        nstore_fd($request,$sock);
        $sock->flush();
    }
}
#################################
# submit_request will take an xCAT command and pass it to the xCAT
#   server for execution.
#  Note must not put a require or use for Utils.pm in the non-bypass path
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
  # get home directory
  my  @user = getpwuid($>);
  my $homedir=$user[7];
  unless ($keyfile) { $keyfile = $homedir."/.xcat/client-cred.pem"; }
  unless ($certfile) { $certfile = $homedir."/.xcat/client-cred.pem"; }
  unless ($cafile) { $cafile  = $homedir."/.xcat/ca.pem"; }
  $xCAT::Client::EXITCODE = 0;    # clear out exit code before invoking the plugin
if (ref($request) eq 'HASH') { # the request is an array, not pure XML
 $request->{clienttype}->[0] = "cli";   # setup clienttype for auditlog
}
# If XCATBYPASS is set, invoke the plugin process_request method directly
# without going through the socket connection to the xcatd daemon
  if ($ENV{XCATBYPASS}) {
     #add current userid to the request
     if (ref($request) eq 'HASH') { # the request is an array, not pure XML
       if (!(defined($request->{username}))) {
         $request->{username}->[0] = getpwuid($>);
       }

       # only allow root to run
       unless ($request->{username}->[0] =~ /root/) {
         print ("WARNING: Only allow root to run XCATBYPASS mode, your current user ID is $request->{username}->[0].\n");
         return 0;
       }
     }
   # Load plugins from either specified or default dir
    require xCAT::Table;
    my %cmd_handlers;
    my @plugins_dirs = split('\:',$ENV{XCATBYPASS});
    if (-d $plugins_dirs[0]) {
       foreach (@plugins_dirs) {
          $plugins_dir = $_;
          scan_plugins();
       }
    } else {
       # figure out default plugins dir
       #my $sitetab=xCAT::Table->new('site');
       #unless ($sitetab) {
       #  print ("ERROR: Unable to open basic site table for configuration\n");
       #}
       $plugins_dir=$::XCATROOT.'/lib/perl/xCAT_plugin';
       scan_plugins();
    }

    populate_site_hash();

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
  my %connargs=();
  if ($xcathost =~ s/%([^\]|:]*)//) {
      $connargs{PeerScope} = $1;
  }
  $connargs{PeerAddr} = $xcathost;
  $connargs{Timeout} = 15;
  if ($connargs{PeerScope} and $connargs{PeerScope} =~ /[a-zA-Z]/) { #non-numeric, need to translate...
	my @ipdata = `ip link`;
	@ipdata = grep(/[^@]$connargs{PeerScope}(:|@)/,@ipdata);
	if (scalar(@ipdata) != 1) {
		print STDERR "Unable to identify scope ".$connargs{PeerScope}."\n";
		exit(1);
	}
	$connargs{PeerScope} = $ipdata[0];
	$connargs{PeerScope} =~ s/:.*//;
   }
		
	
  my $pclient;
  if ($inet6support) {
     $pclient = IO::Socket::INET6->new(
	%connargs,
    );
  } else {
     $pclient = IO::Socket::INET->new(
      PeerAddr => $xcathost,
      Timeout => 15,
     );
   }
  unless ($pclient) {
     print "Unable to open socket connection to xcatd daemon on $xcathost.\n";
     print "Verify that the xcatd daemon is running and that your SSL setup is correct.\n";
     if ($@ =~ /SSL Timeout/) {
        die "Connection failure: SSL Timeout or incorrect certificates in ~/.xcat";
     } else {
        die "Connection failure: $@"
     }
  }
  my $client;
  if (-r $keyfile and -r $certfile and -r $cafile) {
    $client = IO::Socket::SSL->start_SSL($pclient,
    SSL_key_file => $keyfile,
    SSL_cert_file => $certfile,
    SSL_ca_file => $cafile,
    SSL_verify_mode => SSL_VERIFY_PEER,
    SSL_use_cert => 1,
    Timeout => 0,
   );
  } else {
    $client =  IO::Socket::SSL->start_SSL($pclient,
		 Timeout => 0,
		);
  }
  unless ($client) {
     print "Unable to open socket connection to xcatd daemon on $xcathost.\n";
     print "Verify that the xcatd daemon is running and that your SSL setup is correct.\n";
     if ($@ =~ /SSL Timeout/) {
        die "Connection failure: SSL Timeout or incorrect certificates in ~/.xcat";
     } else {
        die "Connection failure: $@"
     }
  }

  my $msg;
  my $encode = "xml";
  #storable encoding is unsafe, carry on with the unsafe xml scheme
  #perhaps one day will support faster schemes
  #my $encode = "storable";
  #my $straightprint=0;
  #if ($ENV{XCATXMLTRACE} or $ENV{XCATXMLWARNING}) { $encode="xml"; }
  if (ref($request) eq 'HASH') { # the request is an array, not pure XML
    #print $client "xcatencoding: $encode\n";
    #my $encok=<$client>;
    send_request($request,$client,$encode);
  } else { #XML
    $straightprint=1;
    $msg=$request;
    print $client $msg;
  }
  $SIG{TERM} =  $SIG{INT} = sub { send_request({abortcommand=>[1]},$client,$encode); exit 0; };
  my $response;
  my $rsp;
  my $cleanexit=0;
  if ($encode eq 'xml') {
  my $massresponse="<massresponse>";
  my $nextcoalescetime=time()+1;
  my $coalescenow=0;
  my $flags=fcntl($client,F_GETFL,0);
  $flags |= O_NONBLOCK; #select can be a bit.. fickle, make sysread work more easily...
  fcntl($client,F_SETFL,$flags);
  my $clientsel = new IO::Select;
  $clientsel->add($client);
  my $line;
  my $newdata=0;
  while (1) {
      my $shouldexit;
      if ($newdata and ($coalescenow or time() > $nextcoalescetime)) {
        $coalescenow=0;
        $newdata=0;
        $nextcoalescetime=time()+1;
	$massresponse .= "</massresponse>";
         $shouldexit = rspclean($massresponse,$callback);
	$massresponse="<massresponse>";
      }

      if ($shouldexit) {
         $cleanexit=1;
        last;
      }
    $line = "";
    $clientsel->can_read(0.5);
    my $readbytes;
    do { $readbytes=sysread($client,$line,65535,length($line)); } while ($readbytes);
    unless (length($line)) {
	if (not defined $readbytes and $! == EAGAIN) { next; }
        last;
    }
    $newdata=1;
    $response .= $line;
    if ($line =~ m/<\/xcatresponse>\s*\z/) {
      if ($line =~ /serverdone/) { $coalescenow=1; } #if serverdone was detected, hint at coalesce code to flush things out now
	#this means that coalesce can be triggered by stray words in the output prematurely, but that's harmless
      #replace ESC with xxxxESCxxx because XMLin cannot handle it
      $response =~ s/\e/xxxxESCxxxx/g;

      if ($ENV{XCATXMLTRACE}) { print $response; }
      $massresponse.=$response;
      $response='';
      if($ENV{XCATXMLWARNING}) {
        validateXML($response);
      }
    }
  }
  if (not $cleanexit and $massresponse ne "<massresponse>") {
	$massresponse .= "</massresponse>";
         $cleanexit = rspclean($massresponse,$callback);
  }
  } else { #storable encode
    my $rsp;
    eval { $rsp = fd_retrieve($client); };
    SERVERINPUT: while ($rsp) {
     my @rsps;
     if (ref $rsp eq 'ARRAY') {
        @rsps = @$rsp;
     } else {
        @rsps = ($rsp);
    }
    foreach (@rsps) {
     $callback->($_);
     if ($_->{serverdone}) {
         $cleanexit=1;
         last SERVERINPUT;
      }
     }
     $rsp = undef;
     eval { $rsp = fd_retrieve($client); };
    }
  }
  $massresponse="";
  unless ($cleanexit) {
     print STDERR "ERROR/WARNING: communication with the xCAT server seems to have been ended prematurely\n";
     $xCAT::Client::EXITCODE = 1;
  }

sub validateXML {
  my $xml = shift;
  my @lines = split /\n/, $xml;
  my $invalidNewline = 0;
  my $contentsColon = 0;
  my $contentsLine;

  foreach (@lines) {
    if(!$invalidNewline) {
      if( ($_ =~ /<contents>/ && $_ !~ /<\/contents>/) ||
          ($_ =~ /<desc>/ && $_ !~ /<\/desc>/)) {
        $invalidNewline = 1;
        print "Possible invalid XML using newlines found:  \n$xml\n";
      }
    }
    if($_ =~ /<contents>.+:.+<\/contents>/) {
      $contentsColon = 1;
      $contentsLine = $_;
    }
    if($_ =~ /<desc>.+<\/desc>/) {
      $contentsColon = 0;
    }
    if($contentsColon && $_ =~ /<desc><\/desc>/) {
      print "Possible invalid XML found(data contents using colon and blank description):  \n$contentsLine\n$_\n";
      $contentsColon = 0;
    }
  }
}

###################################
# scan_plugins
#    will load all plugin perl modules and build a list of supported
#    commands
#
# NOTE:  This is copied from xcatd (last merge 11/23/09).
# TODO:  Will eventually move to using common source....
###################################
sub scan_plugins {
  my @plugins=glob($plugins_dir."/*.pm");
  foreach (@plugins) {
    /.*\/([^\/]*).pm$/;
    my $modname = $1;
    unless ( eval { require "$_" }) {
#       xCAT::MsgUtils->message("S","Error loading module ".$_."  ...skipping");
        print "Error loading module $_  ...skipping\n"; 
        next;
    }
    no strict 'refs';
    my $cmd_adds=${"xCAT_plugin::".$modname."::"}{handled_commands}->();
    foreach (keys %$cmd_adds) {
      my $value = $_;
      if (defined($cmd_handlers{$_})) {
        push @{$cmd_handlers{$_}},[$modname,$cmd_adds->{$_}]; 
      } else {
        $cmd_handlers{$_} = [ [$modname,$cmd_adds->{$_}] ];
      }
    }
  }
  foreach (@plugins) {
    no strict 'refs';
    /.*\/([^\/]*).pm$/;
    my $modname = $1;
    unless (defined(${"xCAT_plugin::".$modname."::"}{init_plugin})) {
        next;
    }
    ${"xCAT_plugin::".$modname."::"}{init_plugin}->(\&do_request);
  }
}




###################################
# plugin_command
#    will invoke the correct plugin
#
# NOTE:  This is copied from xcatd (last merge 11/23/09).
# TODO:  Will eventually move to using common source....
###################################
sub plugin_command {
  my $req = shift;
  my $sock = shift;
  my $callback = shift;
  my %handler_hash;
  my $usesiteglobal = 0;
  # We require these only in bypass mode to reduce start up time for the normal case
  #use lib "$::XCATROOT/lib/perl";
  #use xCAT::NodeRange;
  require lib;
  lib->import("$::XCATROOT/lib/perl");
  require xCAT::NodeRange;
  require xCAT::Table;

  $Main::resps={};
  my $xmlreq;
  if (ref($req) ne 'HASH') { # the request XML, get an array
    $xmlreq=$req;   # save the original XML
    $req = XMLin($xmlreq,SuppressEmpty=>undef,ForceArray=>1) ;

  }
  my @nodes;
  if ($req->{node}) {
    @nodes = @{$req->{node}};
  } elsif ($req->{noderange} and $req->{noderange}->[0]) {
    @nodes = xCAT::NodeRange::noderange($req->{noderange}->[0]);
    if (xCAT::NodeRange::nodesmissed()) {
#     my $rsp = {errorcode=>1,error=>"Invalid nodes in noderange:".join(',',xCAT::NodeRange::nodesmissed)};
#     my $rsp->{serverdone} = {};
      print "Invalid nodes in noderange:".join(',',xCAT::NodeRange::nodesmissed())."\n";
#     if ($sock) {
#       print $sock XMLout($rsp,RootName=>'xcatresponse' ,NoAttr=>1);
#     }
#     return ($rsp);
      return 1;
    }
    unless (@nodes) {
       $req->{emptynoderange} = [1];
    }
  }
  if (@nodes) { $req->{node} = \@nodes; }
  my %unhandled_nodes;
  foreach (@nodes) {
      $unhandled_nodes{$_}=1;
  }
  my $useunhandled=0;
  if (defined($cmd_handlers{$req->{command}->[0]})) {
    my $hdlspec;
    my @globalhandlers=();
    my $useglobals=1; #If it stays 1, then use globals normally, if 0, use only for 'unhandled_nodes, if -1, don't do at all
    foreach (@{$cmd_handlers{$req->{command}->[0]}}) {
      $hdlspec =$_->[1];
      my $ownmod = $_->[0];
      if ($hdlspec =~ /^site:/) { #A site entry specifies a plugin
          my $sitekey = $hdlspec;
          $sitekey =~ s/^site://;
          #$sitetab = xCAT::Table->new('site');
          #my $sent = $sitetab->getAttribs({key=>$sitekey},['value']);
          #if ($sent and $sent->{value}) { #A site style plugin specification is just like
          if ($::XCATSITEVALS{$sitekey}) { #A site style plugin specification is just like
                                          #a static global, it grabs all nodes rather than some
            $useglobals = -1; #If they tried to specify anything, don't use the default global handlers at all
            unless (@nodes) {
              $handler_hash{$::XCATSITEVALS{$sitekey}} = 1;
              $usesiteglobal = 1;
            }
            foreach (@nodes) { #Specified a specific plugin, not a table lookup
              $handler_hash{$::XCATSITEVALS{$sitekey}}->{$_} = 1;
            }
          }
      } elsif ($hdlspec =~ /:/) { #Specificed a table lookup path for plugin name
        if (@nodes) { # only use table lookup plugin if nodelist exists
                      # Usage will be handled in common AAAhelp plugin

          $useglobals = 0; #Only contemplate nodes that aren't caught through searching below in the global handler
          $useunhandled=1;
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


          unless (@nodes) { #register the plugin in the event of usage
            $handler_hash{$ownmod} = 1;
            $useglobals = 1;
          }
          my $hdlrcache;
          if ($hdlrtable) {
                  $hdlrcache = $hdlrtable->getNodesAttribs(\@nodes,\@columns);
          }
          foreach $node (@nodes) {
            unless ($hdlrcache) { next; }
            my $attribs = $hdlrcache->{$node}->[0]; #$hdlrtable->getNodeAttribs($node,\@columns);
            unless (defined($attribs)) { next; }
            foreach (@columns) {
              my $col=$_;
              if (defined($attribs->{$col})) {
                if ($colvals->{$col}) { #A pattern match style request.
                  if ($attribs->{$col} =~ /$colvals->{$col}/) {
                    $handler_hash{$ownmod}->{$node} = 1;
                    delete $unhandled_nodes{$node};
                    last;
                  }
                } else {
                  # call the plugin that matches the table value for that node
                  if ($attribs->{$col} =~ /$ownmod/) {
                    $handler_hash{$attribs->{$col}}->{$node} = 1;
                    delete $unhandled_nodes{$node};
                    last;
                  }
                }
              }
            }
          }
          $hdlrtable->close;
        }  # end if (@nodes)

      } else {
          push @globalhandlers,$hdlspec;
      }
    }
      if ($useglobals == 1) {  #Behavior when globals have not been overriden
          my $hdlspec;
          foreach $hdlspec (@globalhandlers) {
            unless (@nodes) {
              $handler_hash{$hdlspec} = 1;
            }
            foreach (@nodes) { #Specified a specific plugin, not a table lookup
              $handler_hash{$hdlspec}->{$_} = 1;
            }
          }
      } elsif ($useglobals == 0) {
          unless (@nodes or $usesiteglobal) { #if something like 'makedhcp -n',
              foreach (keys %handler_hash) {
                  if ($handler_hash{$_} == 1) {
                      delete ($handler_hash{$_})
                  }
              }
          }
          foreach $hdlspec (@globalhandlers) {
            unless (@nodes or $usesiteglobal) {
              $handler_hash{$hdlspec} = 1;
            }
            foreach (keys %unhandled_nodes) { #Specified a specific plugin, not a table lookup
              $handler_hash{$hdlspec}->{$_} = 1;
            }
          }
      } #Otherwise, global handler is implicitly disabled
  } else {
     print "Error request: $req->{command}->[0]  has no known plugin for it.\n"; 
    return 1;  
  }
  if ($useunhandled) {
   my $queuelist;
   foreach (@{$cmd_handlers{$req->{command}->[0]}}) {
       my $queueitem = $_->[1];
       if (($queueitem =~ /:/) and !($queuelist =~ /($queueitem)/)) {
         $queuelist .= "$_->[1];";
       } 
   }
   $queuelist =~ s/;$//;
   $queuelist =~ s/:/./g;
   foreach (keys %unhandled_nodes) {
#      if ($sock) {
#         print $sock XMLout({node=>[{name=>[$_],data=>["Unable to identify plugin for this command, check relevant tables: $queuelist"],errorcode=>[1]}]},NoAttr=>1,RootName=>'xcatresponse');
#      } else {
         my $tabdesc = $queuelist;
         $tabdesc =~ s/=.*$//;
         $callback->({node=>[{name=>[$_],error=>['Unable to identify plugin for this command, check relevant tables: '.$tabdesc],errorcode=>[1]}]});
#      }
     }
  }

## FOR NOW, DON'T FORK CHILD PROCESS TO MAKE BYPASS SIMPLER AND EASIER TO DEBUG
#  $plugin_numchildren=0;
#  %plugin_children=();
#  $SIG{CHLD} = \&plugin_reaper; #sub {my $plugpid; while (($plugpid = waitpid(-1, WNOHANG)) > 0) { if ($plugin_children{$plugpid}) { delete $plugin_children{$plugpid}; $plugin_numchildren--; } } };
# my $check_fds;
# if ($sock) {
#   $check_fds = new IO::Select;
# }
  foreach (keys %handler_hash) {
    my $modname = $_;
#   my $shouldbealivepid=$$;
    if (-r $plugins_dir."/".$modname.".pm") {
      require $plugins_dir."/".$modname.".pm";
#     $plugin_numchildren++;
#     my $pfd; #will be referenced for inter-process messaging.
#     my $parfd; #not causing a problem that I discern yet, but theoretically
#     my $child;
#     if ($sock) { #If $sock not passed in, don't fork..
#       socketpair($pfd, $parfd,AF_UNIX,SOCK_STREAM,PF_UNSPEC) or die "socketpair: $!";
#       #pipe($pfd,$cfd);
#       $parfd->autoflush(1);
#       $pfd->autoflush(1);
#       $child = xCAT::Utils->xfork;
#     } else {
#       $child = 0;
#     }
#     unless (defined $child) { die "Fork failed"; }
#     if ($child == 0) {
#       if ($parfd) {  #If xCAT is doing multiple requests in same communication PID, things would get unfortunate otherwise
#           $parent_fd = $parfd;
#       }
        my $oldprogname=$$progname;
        $$progname=$oldprogname.": $modname instance";
#       if ($sock) { close $pfd; }
        unless ($handler_hash{$_} == 1) {
          my @nodes = sort {($a =~ /(\d+)/)[0] <=> ($b =~ /(\d+)/)[0] || $a cmp $b } (keys %{$handler_hash{$_}});
          $req->{node}=\@nodes;
        }
        no strict  "refs";
#       eval { #REMOVEEVALFORDEBUG
#       if ($dispatch_requests) {
        # backup the original req and recover it after the a run
        my $org_req = {%$req};
        dispatch_request($req,$callback,$modname);
        $req = {%$org_req};
#       } else {
#          $SIG{CHLD}='DEFAULT';
#          ${"xCAT_plugin::".$modname."::"}{process_request}->($req,$callback,\&do_request);
#       }
        $$progname=$oldprogname;
#       if ($sock) {
#         close($parent_fd);
#         xexit(0);
#       }
#       }; #REMOVEEVALFORDEBUG
#       if ($sock or $shouldbealivepid != $$) { #We shouldn't still be alive, try to send as much detail to parent as possible as to why
#           my $error= "$modname plugin bug, pid $$, process description: '$$progname'";
#           if ($@) {
#               $error .= " with error '$@'";
#           } else { #Sys::Virt and perhaps Net::SNMP sometimes crashes in a way $@ won't catch..
#               $error .= " with missing eval error, probably due to special manipulation of $@ or strange circumstances in an XS library, remove evals in xcatd marked 'REMOVEEVALFORDEBUG and run xcatd -f for more info";
#           }
#           if (scalar (@nodes)) { #Don't know which of the nodes, so one error message warning about the possibliity..
#               $error .= " while trying to fulfill request for the following nodes: ".join(",",@nodes);
#           }
#           xCAT::MsgUtils->message("S","xcatd: $error");
#           $callback->({error=>[$error],errorcode=>[1]});
#           xexit(0); #Die like we should have done
#       } elsif ($@) { #We are still alive, should be alive, but yet we have an error.  This means we are in the case of 'do_request' or something similar.  Forward up the death since our communication channel is intact..
#           die $@;
#       }
#     } else {
#       $plugin_children{$child}=1;
#       close $parfd;
#       $check_fds->add($pfd);
#     }
    } else {
      my $pm_name = $plugins_dir."/".$modname.".pm";
      foreach my $node (keys %{$handler_hash{$_}}) {
        if ($sock) {
         print $sock XMLout({node=>[{name=>[$node],data=>["Cannot find the perl module to complete the operation: $pm_name"],errorcode=>[1]}]},NoAttr=>1,RootName=>'xcatresponse');
        } else {
         $callback->({node=>[{name=>[$node],data=>["Cannot find the perl module to complete the operation: $pm_name"],errorcode=>[1]}]});
        }
      }
    }
  }
  unless ($sock) { return $Main::resps };
# while (($plugin_numchildren > 0) and ($check_fds->count > 0)) { #this tracks end of useful data from children much more closely
#   relay_fds($check_fds,$sock);
# }
# #while (relay_fds($check_fds,$sock)) {}
# my %done;
# $done{serverdone} = {};
# if ($req->{transid}) {
#   $done{transid}=$req->{transid}->[0];
# }
# if ($sock) {
#     my $clientpresence = new IO::Select; #The client may have gone away without confirmation, don't PIPE over this trivial thing
#     $clientpresence->add($sock);
#     if ($clientpresence->can_write(5)) {
#         print $sock XMLout(\%done,RootName => 'xcatresponse',NoAttr=>1);
#     }
# }
}




###################################
# dispatch_request
#    dispatch the requested command
#
# NOTE:  This is copied from xcatd (last merge 11/23/09).
#        All we really need from this subroutine is to call preprocess_request
#        and to only run the command for nodes handled by the local server
#        Will eventually move to using common source....
###################################
sub dispatch_request {
#  %dispatched_children=();
   require xCAT::Utils;
   my $req = shift;
   $dispatch_cb = shift;

   my $modname = shift;
   my $reqs = [];
#  my $child_fdset = new IO::Select;
   no strict  "refs";

   #Hierarchy support.  Originally, the default scope for noderange commands was
   #going to be the servicenode associated unless overriden.
   #However, assume for example that you have blades and a blade is the service node
   #rpower being executed by the servicenode for one of its subnodes would have to
   #reach it's own management module.  This has the potential to be non-trivial for some quite possible network configurations.
   #Since plugins may commonly experience this, a preprocess_request implementation
   #will for now be required for a command to be scaled through service nodes
   #If the plugin offers a preprocess method, use it to set the request array
   if (defined(${"xCAT_plugin::".$modname."::"}{preprocess_request})) {
   $SIG{CHLD}='DEFAULT';
    $reqs = ${"xCAT_plugin::".$modname."::"}{preprocess_request}->($req,$dispatch_cb,\&do_request);
   } else { #otherwise, pass it in without hierarchy support
    $reqs = [$req];
   }

# $dispatch_children=0;
# $SIG{CHLD} = \&dispatch_reaper; #sub {my $cpid; while (($cpid =waitpid(-1, WNOHANG)) > 0) { if ($dispatched_children{$cpid}) { delete $dispatched_children{$cpid}; $dispatch_children--; } } };
  my $onlyone=0;
  if (defined $reqs and (scalar(@{$reqs}) == 1)) {
      $onlyone=1;
  }

   foreach (@{$reqs}) {
#   my $pfd;
#   my $parfd; #use a private variable so it won't trounce itself recursively
#   my $child;
    delete $_->{noderange};
#----- added to Client.pm -----#
    if ($_->{node}) {
       $_->{noderange}->[0]=join(',',@{$_->{node}});
    }
#----- end added to Client.pm -----#

    if (ref $_->{'_xcatdest'} and (ref $_->{'_xcatdest'}) eq 'ARRAY') {
        _->{'_xcatdest'} =  $_->{'_xcatdest'}->[0];
    }
    if ($onlyone and not ($_->{'_xcatdest'} and xCAT::NetworkUtils->thishostisnot($_->{'_xcatdest'}))) {
       $SIG{CHLD}='DEFAULT';
       ${"xCAT_plugin::".$modname."::"}{process_request}->($_,$dispatch_cb,\&do_request);
        return;
    }

#   socketpair($pfd, $parfd,AF_UNIX,SOCK_STREAM,PF_UNSPEC) or die "socketpair: $!";
#   $parfd->autoflush(1);
#   $pfd->autoflush(1);
#   $child = xCAT::Utils->xfork;
#   if ($child) {
#      $dispatch_children++;
#      $dispatched_children{$child}=1;
#      $child_fdset->add($pfd);
#      next;
#   }
#   unless (defined $child) {
#      $dispatch_cb->({error=>['Fork failure dispatching request'],errorcode=>[1]});
#   }
#   undef $SIG{CHLD};
#     $dispatch_parentfd = $parfd;
      my @prexcatdests=();
      my @xcatdests=();
     if (ref($_->{'_xcatdest'}) eq 'ARRAY') { #If array, consider it an 'anycast' operation, broadcast done through dupe
                                              #requests, or an alternative join '&' maybe?
         @prexcatdests=@{$_->{'_xcatdest'}};
     } else {
         @prexcatdests=($_->{'_xcatdest'});
     }
     foreach (@prexcatdests) {
         if ($_ and /,/) {
             push @xcatdests,split /,/,$_;
         } else {
             push @xcatdests,$_;
         }
     }
     my $xcatdest;
     my $numdests=scalar(@xcatdests);
     my $request_satisfied=0;
     foreach $xcatdest (@xcatdests) {
        my $dlock;
        if ($xcatdest and xCAT::NetworkUtils->thishostisnot($xcatdest)) {
#----- added to Client.pm -----#
       $dispatch_cb->({warning=>['XCATBYPASS is set, skipping hierarchy call to '.$_->{'_xcatdest'}.'']});
#----- end added to Client.pm -----#

#           #mkpath("/var/lock/xcat/"); #For now, limit intra-xCAT requests to one at a time, to mitigate DB handle usage
#           #open($dlock,">","/var/lock/xcat/dispatchto_$xcatdest");
#           #flock($dlock,LOCK_EX);
#           $ENV{XCATHOST} =  ($xcatdest =~ /:/ ? $xcatdest : $xcatdest.":3001" );
#           $$progname.=": connection to ".$ENV{XCATHOST};
#           my $errstr;
#           eval {
#           undef $_->{'_xcatdest'};
#           xCAT::Client::submit_request($_,\&dispatch_callback,$xcatdir."/cert/server-cred.pem",$xcatdir."/cert/server-cred.pem",$xcatdir."/cert/ca.pem");
#           };
#           if ($@) {
#            $errstr=$@;
#           }
#           #unlink("/var/lock/xcat/dispatchto_$xcatdest");
#           #flock($dlock,LOCK_UN);
#           if ($errstr) {
#                   if ($numdests == 1) {
#                   dispatch_callback({error=>["Unable to dispatch command to ".$ENV{XCATHOST}.", command will not make changes to that server ($errstr)"],errorcode=>[1]});
#                       xCAT::MsgUtils->message("S","Error dispatching request to ".$ENV{XCATHOST}.": ".$errstr);
#               } else {
#                       xCAT::MsgUtils->message("S","Error dispatching request to ".$ENV{XCATHOST}.", trying other service nodes: ".$errstr);
#               }
#               next;
#               } else {
#               $request_satisfied=1;
#               last;
#           }
         } else {
            $$progname.=": locally executing";
            $SIG{CHLD}='DEFAULT';
#           ${"xCAT_plugin::".$modname."::"}{process_request}->($_,\&dispatch_callback,\&do_request);
#----- changed in Client.pm -----#
            ${"xCAT_plugin::".$modname."::"}{process_request}->($_,$dispatch_cb,\&do_request);
#----- end changed in Client.pm -----#
            last;
        }
     }
#    if ($numdests > 1 and not $request_satisfied) {
#           xCAT::MsgUtils->message("S","Error dispatching a request to all possible service nodes for request");
#       dispatch_callback({error=>["Failed to dispatch command to any of the following service nodes: ".join(",",@xcatdests)],errorcode=>[1]});
#    }

#    xexit;
  }
#while (($dispatch_children > 0) and ($child_fdset->count > 0)) { relay_dispatch($child_fdset) }
#while (relay_dispatch($child_fdset)) { } #Potentially useless drain.
}



###################################
# do_request
#    called from a plugin to execute another xCAT plugin command internally
#
# NOTE:  This is copied from xcatd (last merge 11/23/09).
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
     my @nodes = xCAT::NodeRange::noderange($req->{noderange}->[0]);
     my %resp;
     if (xCAT::NodeRange::nodesmissed()) {
       $resp{warning}="Invalid nodes in noderange:".join ',',xCAT::NodeRange::nodesmissed() ."\n";
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
  require Storable;
  foreach (keys %$rsp) {
    my $subresp = Storable::dclone($rsp->{$_});
    push (@{$Main::resps->{$_}}, @{$subresp});
  }
}



}    # end of submit_request()

####################################
# populates all the site attributes into %::XCATSITEVALS
# This is used with XCATBYPASS=1
###################################
sub populate_site_hash {
    %::XCATSITEVALS=();
    my $sitetab = xCAT::Table->new('site',-create=>0);
    unless ($sitetab) { 
       print ("ERROR: Unable to open basic site table for configuration\n");
       return; 
    }
    my @records = $sitetab->getAllAttribs(qw/key value/);
    foreach (@records) {
        $::XCATSITEVALS{$_->{key}}=$_->{value};
    }
}



##########################################
# handle_response is a default callback that can be passed into submit_request()
# It is invoked repeatedly by submit_request() to print out the data returned by
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
  if ($ENV{'XCATSHOWXML'}) {
    my  $xmlrec=XMLout($rsp,RootName=>'xcatresponse',NoAttr=>1,KeyAttr=>[]);
    print "$xmlrec\n";
   return;
  }
#print "in handle_response\n";
  # Handle errors
  if (defined($rsp->{errorcode})) {
    if (ref($rsp->{errorcode}) eq 'ARRAY') {
      foreach my $ecode (@{$rsp->{errorcode}}) { 
        $xCAT::Client::EXITCODE |= $ecode;
      }
    }
    else {
      $xCAT::Client::EXITCODE |= $rsp->{errorcode};
    }   # assume it is a non-reference scalar
  }
  if ($rsp->{error}) {
#print "printing error\n";
    if (ref($rsp->{error}) eq 'ARRAY') {
      foreach my $text (@{$rsp->{error}}) {
        if ($rsp->{NoErrorPrefix}) {
          print STDERR "$text\n";
        } else {
          print STDERR "Error: $text\n";
        }
      }
    }
    else {
      if ($rsp->{NoErrorPrefix}) {
           print STDERR ($rsp->{error}."\n");
      } else {
          print STDERR ("Error: ".$rsp->{error}."\n");
      }
    }
  }
  if ($rsp->{warning}) {
#print "printing warning\n";
    if (ref($rsp->{warning}) eq 'ARRAY') {
      foreach my $text (@{$rsp->{warning}}) {
        if ($rsp->{NoWarnPrefix}) {
          print STDERR "$text\n";
        } else {
          print STDERR "Warning: $text\n";
        }
      }
    }
    else {
        if ($rsp->{NoWarnPrefix}) {
           print STDERR ($rsp->{warning}."\n");
        } else {
           print STDERR ("Warning: ".$rsp->{warning}."\n");
        }
    }
  }
  if ($rsp->{info}) {
#print "printing info\n";
    if (ref($rsp->{info}) eq 'ARRAY') {
      foreach my $text (@{$rsp->{info}}) {
        print "$text\n";
      }
    }
    else {
      print ($rsp->{info}."\n");
    }
  }

  if ($rsp->{sinfo}) {
    if (ref($rsp->{sinfo}) eq 'ARRAY') {
      foreach my $text (@{$rsp->{sinfo}}) {
        print "$text\r"; $|++;
      }
    }
    else {
      print ($rsp->{sinfo}."\r"); $|++;
    }
  }



  # Handle {node} structure
  my $errflg=0;
    my $nodes=($rsp->{node});
    unless (ref $nodes eq 'ARRAY') {
	$nodes = [$nodes];
    }
  if (scalar @{$nodes}) {
#print "printing node\n";
    my $node;
    foreach $node (@$nodes) {
      my $desc;
      if (ref($node->{name}) eq 'ARRAY') {
      $desc=$node->{name}->[0];
      } else {
      $desc=$node->{name};
      }
      if ($node->{errorcode}) {
        if (ref($node->{errorcode}) eq 'ARRAY') {
          foreach my $ecode (@{$node->{errorcode}}) {
            $xCAT::Client::EXITCODE |= $ecode;
          }
        }
    	else {
          $xCAT::Client::EXITCODE |= $node->{errorcode};
        }   # assume it is a non-reference scalar
      }
      if ($node->{error}) {
         $desc.=": Error: ".$node->{error}->[0];
		 $errflg=1;
      }
      if ($node->{warning}) {
         $desc.=": Warning: ".$node->{warning}->[0];
		 $errflg=1;
      }
      if ($node->{data}) {
         if (ref(\($node->{data})) eq 'SCALAR') {
            $desc=$desc.": ".$node->{data};
         } elsif (ref($node->{data}) eq 'HASH') {
            if ($node->{data}->{desc}) {
             if (ref($node->{data}->{desc}) eq 'ARRAY') {
              $desc=$desc.": ".$node->{data}->{desc}->[0];
              } else {
              $desc=$desc.": ".$node->{data}->{desc};
              }
            }
            if ($node->{data}->{contents}) {
                if (ref($node->{data}->{contents}) eq 'ARRAY') {
        $desc="$desc: ".$node->{data}->{contents}->[0];
                } else {
        $desc="$desc: ".$node->{data}->{contents};
                }
            }
         } elsif (ref(\($node->{data}->[0])) eq 'SCALAR') {
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
		if ($errflg == 1) {
		  print STDERR ("$desc\n");
		} else {
          print "$desc\n";
        }
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






