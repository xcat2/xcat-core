package xCAT_plugin::nodestat;

use Socket;
use IO::Handle;
use Storable qw/freeze thaw/;
my $stat;
my $children;

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


sub process_request {
   my $request = shift;
   my $callback = shift;
   my $doreq = shift;
   my @nodes = @{$request->{node}};
   my $node;
   my $child_handles = new IO::Select;
   $children=0;
   $SIG{CHLD} = sub {while (waitpid(-1, WNOHANG) > 0) { $children--; }};
   foreach $node (@nodes) {
      my $parent;
      my $childfd;
      undef ($parent);
      undef ($childfd);
      socketpair($childfd,$parent,AF_UNIX,SOCK_STREAM,PF_UNSPEC) or die "socketpair: $!";
      my $child;
      $child = xCAT::Utils->xfork;
      unless (defined $child) { die "Fork failure"; }
      if ($child==0) { #This is the child
         close($childfd);
         undef $SIG{CHLD};
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
            print $parent freeze({node=>[\%rsp]})
         } elsif (nodesockopen($node,22)) {
            $rsp{data} = [ 'sshd' ];
            print "$node is sshd\n";
            print $parent freeze({node=>[\%rsp]});
         } elsif ($text = installer_query($node)) {
            $rsp{data} = [ $text ];
            print $parent freeze({node=>[\%rsp]});
         } else {
            $doreq->({command=>['nodeset'],
                     node=>[$node],
                     arg=>['stat']},
                     \&getstat);
            $rsp{data} = [ 'ping '.$stat ];
            print $parent freeze({node=>[\%rsp]});
         }
         print $parent "\nENDOFFREEZEx3a93\n";
         $parent->flush;
         print "Wait for $node ack...\n";
         <$parent>;
         print "$node acked...\n";
         close($parent);
         exit 0;
      }
      close($parent);
      $children++;
      $child_handles->add($childfd);
   }
   print "wait for kids\n";
   while ($children) {
      relay_responses($child_handles,$callback);
   }
   print "kids gone\n";
   while (relay_responses($child_handles,$callback)) {}
   print "out i go\n";
}

sub relay_responses {
   my $fhs = shift;
   my $callback = shift;
   my @handles = $fhs->can_read(0.2);
   foreach my $input (@handles) {
      print "I can haz input\n";
      my $data;
      $data = "";
      print "here\n";
      if ($data = <$input>) {
         print $data;
         while ($data !~ /ENDOFFREEZEx3a93/) { #<$input>) {
            $data .= <$input>;
         }
         my $response = thaw($data);
         print "fin issued\n";
         print $input "fin\n";
         $input->flush;
         $callback->($response);
      } else { 
         print "not here....\n";
         $fhs->remove($input);
         close($input);
      }
   }
   return scalar(@handles);
}

      



1;
