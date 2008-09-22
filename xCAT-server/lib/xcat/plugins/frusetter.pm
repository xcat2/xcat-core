package xCAT_plugin::frusetter;
use Data::Dumper;

sub handled_commands {
    return {
          rewritemyfru => 'frusetter',
    }
}

sub ok_with_node {
   my $node = shift;
   #Here we connect to the node on a privileged port (in the clear) and ask the
   #node if it just asked us for credential.  It's convoluted, but it is 
   #a convenient way to see if root on the ip has approved requests for
   #credential retrieval.  Given the nature of the situation, it is only ok
   #to assent to such requests before users can log in.  During postscripts
   #stage in stateful nodes and during the rc scripts of stateless boot
   my $select = new IO::Select;
   #sleep 0.5; # gawk script race condition might exist, try to lose just in case
   my $sock = new IO::Socket::INET(PeerAddr=>$node,
                                     Proto => "tcp",
                                     PeerPort => shift);
   my $rsp;
   unless ($sock) {return 0};
   $select->add($sock);
   print $sock "CREDOKBYYOU?\n";
   unless ($select->can_read(5)) { #wait for data for up to five seconds
      return 0;
   }
   my $response = <$sock>;
   chomp($response);
   if ($response eq "CREDOKBYME") {
      return 1;
   }
   return 0;
}
sub process_request {
    my $request = shift;
    my $callback = shift;
    my $doreq = shift;
    my $node = $request->{_xcat_clienthost}->[0];
    unless (ok_with_node($node,300)) {
        $callback->({error=>["Unable to prove root on your IP approves of this request"],errorcode=>[1]});
        return;
    }
    $doreq->({command=>['rfrurewrite'],
              noderange=>[$node],
             });   
    return;
}

1;
