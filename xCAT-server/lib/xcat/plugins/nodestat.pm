package xCAT_plugin::nodestat;
use strict;
use warnings;

use Socket;
use IO::Handle;
use Getopt::Long;
my $stat;

sub handled_commands {
   return { 
      nodestat => 'nodestat',
   };
}

sub pinghost {
   my $node = shift;
   my $rc = system("ping -q -n -c 1 -w 1 $node > /dev/null");
   if ($rc == 0) {
      return 1;
   } else {
      return 0;
   }
}

sub nodesockopen {
   my $node = shift;
   my $port = shift;
   my $socket;
   my $addr = gethostbyname($node);
   my $sin = sockaddr_in($port,$addr);
   my $proto = getprotobyname('tcp');
   socket($socket,PF_INET,SOCK_STREAM,$proto) || return 0;
   connect($socket,$sin) || return 0;
   return 1;
}

sub installer_query {
   my $node = shift;
   my $destport = 3001;
   my $socket;
   my $text = "";
   my $proto = getprotobyname('tcp');
   socket($socket,PF_INET,SOCK_STREAM,$proto) || return 0;
   my $addr = gethostbyname($node);
   my $sin = sockaddr_in($destport,$addr);
   connect($socket,$sin) || return 0;
   print $socket "stat \n";
   $socket->flush;
   while (<$socket>) { 
      $text.=$_;
   }
   $text =~ s/\n.*//;
   return $text;
   close($socket);
}


sub getstat {
   my $response = shift;
   $stat = $response->{node}->[0]->{data}->[0];
}

#-------------------------------------------------------

=head3  preprocess_request

  Check and setup for hierarchy 

=cut

#-------------------------------------------------------
sub preprocess_request
{
    my $req = shift;
    my $cb  = shift;
    my %sn;
    if ($req->{_xcatdest}) { return [$req]; }    #exit if preprocessed
    my $nodes    = $req->{node};
    my $service  = "xcat";
    my @requests;
    if ($nodes){  
      # find service nodes for requested nodes
      # build an individual request for each service node
      my $sn = xCAT::Utils->get_ServiceNode($nodes, $service, "MN");

      # build each request for each service node
      foreach my $snkey (keys %$sn)
      {
            my $reqcopy = {%$req};
            $reqcopy->{node} = $sn->{$snkey};
            $reqcopy->{'_xcatdest'} = $snkey;
            push @requests, $reqcopy;

      }
    }
    else
    {    # non node options like -h 
         @ARGV=();
         my $args=$req->{arg};  
         if ($args) {
           @ARGV = @{$args};
         } else {
            &usage($cb);
            return(1);
         }
         # parse the options
          Getopt::Long::Configure("posix_default");
          Getopt::Long::Configure("no_gnu_compat");
          Getopt::Long::Configure("bundling");
         if (!GetOptions(
          'h|help'     => \$::HELP,
          'v|version'  => \$::VERSION))
         {
              &usage($cb);
              return(1);
         }
         if ($::HELP) {
              &usage($cb);
              return(0);
         } 
         if ($::VERSION) {
             my $version = xCAT::Utils->Version();
             my $rsp={};
             $rsp->{data}->[0] = "$version";
             xCAT::MsgUtils->message("I", $rsp, $cb);
             return(0);
         } 
    }
    return \@requests;
}

sub process_request {
   my $request = shift;
   my $callback = shift;
   my $doreq = shift;
   my @nodes = @{$request->{node}};
   my $node;
   foreach $node (@nodes) {
      my %rsp;
      my $text="";
      $rsp{name}=[$node];
      unless (pinghost($node)) {
         $rsp{data} = [ 'noping' ];
         $callback->({node=>[\%rsp]});
         next;
      }
      if (nodesockopen($node,15002)) {
         $rsp{data} = [ 'pbs' ];
         $callback->({node=>[\%rsp]});
         next;
      } elsif (nodesockopen($node,22)) {
         $rsp{data} = [ 'sshd' ];
         $callback->({node=>[\%rsp]});
         next;
      } elsif ($text = installer_query($node)) {
         $rsp{data} = [ $text ];
         $callback->({node=>[\%rsp]});
         next;
      } else {
         $doreq->({command=>['nodeset'],
                  node=>[$node],
                  arg=>['stat']},
                  \&getstat);
         $rsp{data} = [ 'ping '.$stat ];
         $callback->({node=>[\%rsp]});
         next;
      }
   }
}
sub usage
{
    my $cb=shift;
    my $rsp={};
    $rsp->{data}->[0]= "Usage:";
    $rsp->{data}->[1]= "  nodestat [noderange]";
    $rsp->{data}->[2]= "  nodestat [-h|--help|-v|--version]";
    xCAT::MsgUtils->message("I", $rsp, $cb);
}

1;
