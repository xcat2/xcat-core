package xCAT_plugin::nodestat;
use strict;
use warnings;

use Socket;
use IO::Handle;
use Getopt::Long;
my $stat;
my %portservices;

sub handled_commands {
   return { 
      nodestat => 'nodestat',
   };
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
    return 0;
}

sub process_request {
   my $request = shift;
   my $callback = shift;
   my $doreq = shift;
   %portservices = (
        '22' => 'ssh',
        '15002' => 'pbs',
        '8002' => 'xend',
   );
   my @livenodes;
   my @nodes = @{$request->{node}};
   my %unknownnodes;
   foreach (@nodes) {
	$unknownnodes{$_}=1;
	my $packed_ip = undef;
        $packed_ip = gethostbyname($_);
        if( !defined $packed_ip) {
                my %rsp;
                $rsp{name}=[$_];
                $rsp{data} = [ "Please make sure $_ exists in /etc/hosts or DNS" ];
                $callback->({node=>[\%rsp]});
        }
   }

   my $node;
   my $fping;
   my $ports = join ',',keys %portservices;
   my %deadnodes;
   foreach (@nodes) {
       $deadnodes{$_}=1;
   }
   open($fping,"nmap -p $ports ".join(' ',@nodes). " 2> /dev/null|") or die("Can't start nmap: $!");
   my $currnode='';
   my $port;
   my $state;
   my %states;
   my %rsp;
   while (<$fping>) {
      if (/Interesting ports on ([^ ]*) /) {
          $currnode=$1;
          unless ($deadnodes{$1}) {
              foreach (keys %deadnodes) {
                  if ($currnode =~ /^$_\./) {
                      $currnode = $_;
                      last;
                  }
              }
          }
          delete $deadnodes{$currnode};
      } elsif ($currnode) {
          if (/^MAC/) {
              $rsp{name}=[$currnode];
              my $status = join ',',sort keys %states ;
              unless ($status or $status = installer_query($currnode)) { #pingable, but no *clue* as to what the state may be
                 $doreq->({command=>['nodeset'],
                      node=>[$currnode],
                      arg=>['stat']},
                      \&getstat);
                 $status= 'ping '.$stat;
              }

              $rsp{data} = [ $status ];
              $callback->({node=>[\%rsp]});
              $currnode="";
              %states=();
              next;
          }
          if (/^PORT/) { next; }
          ($port,$state) = split;
          if ($port =~ /^(\d*)\// and $state eq 'open') {
              $states{$portservices{$1}}=1;
          }
      } 
    }
    foreach $currnode (sort keys %deadnodes) {
         $rsp{name}=[$currnode];
         $rsp{data} = [ 'noping' ];
         $callback->({node=>[\%rsp]});
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
