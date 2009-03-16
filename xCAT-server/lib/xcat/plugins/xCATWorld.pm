# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle xCATWorld

   Supported command:
         xCATWorld->xCATWorld

=cut

#-------------------------------------------------------
package xCAT_plugin::xCATWorld;
use Sys::Hostname;
use xCAT::Table;

use xCAT::Utils;

use xCAT::MsgUtils;
use Getopt::Long;
1;

#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {xCATWorld => "xCATWorld"};
}

#-------------------------------------------------------

=head3  preprocess_request

  Check and setup for hierarchy 

=cut

#-------------------------------------------------------
sub preprocess_request
{
    my $req = shift;
    my $callback  = shift;
    my %sn;
    #if already preprocessed, go straight to request
    if ($req->{_xcatpreprocessed}->[0] == 1 ) { return [$req]; }
    my $nodes    = $req->{node};
    my $service  = "xcat";

    # find service nodes for requested nodes
    # build an individual request for each service node
    if ($nodes) {
     $sn = xCAT::Utils->get_ServiceNode($nodes, $service, "MN");

      # build each request for each service node

      foreach my $snkey (keys %$sn)
      {
	my $n=$sn->{$snkey};
	print "snkey=$snkey, nodes=@$n\n";
            my $reqcopy = {%$req};
            $reqcopy->{node} = $sn->{$snkey};
            $reqcopy->{'_xcatdest'} = $snkey;
            $reqcopy->{_xcatpreprocessed}->[0] = 1;
            push @requests, $reqcopy;

      }
      return \@requests;
    } else { # input error
       my %rsp;
       $rsp->{data}->[0] = "Input noderange missing. Useage: xCATWorld <noderange> \n";
      xCAT::MsgUtils->message("I", $rsp, $callback, 0);
      return 1;
    }
}

#-------------------------------------------------------

=head3  process_request

  Process the command

=cut

#-------------------------------------------------------
sub process_request
{

    my $request  = shift;
    my $callback = shift;
    my $nodes    = $request->{node};
    my $command  = $request->{command}->[0];
    my $args     = $request->{arg};
    my $envs     = $request->{env};
    my %rsp;
    my $i = 1;
    my @nodes=@$nodes; 
    # do your processing here
    # return info
    my $host=hostname();

    $rsp->{data}->[0] = "Hello World from $host! I can process the following nodes:";
    xCAT::MsgUtils->message("I", $rsp, $callback, 0);
    foreach $node (@nodes)
    {
        $rsp->{data}->[$i] = "$node";
        $i++;
    }
    xCAT::MsgUtils->message("I", $rsp, $callback, 0);
    return;

}

