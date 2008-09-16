# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle sinv 

   Supported command:
         sinv 

=cut

#-------------------------------------------------------
package xCAT_plugin::sinv;
use strict;

require xCAT::Utils;

require xCAT::MsgUtils;
require xCAT::SINV;
use Getopt::Long;
1;

#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {sinv => "sinv",};
}

#-------------------------------------------------------

=head3  preprocess_request


=cut

#-------------------------------------------------------
#sub preprocess_request
#{
#    my $req = shift;
#    my $cb  = shift;
#    my %sn;
#    my $sn;
#    if ($req->{_xcatdest}) { return [$req]; }    #exit if preprocessed
#    my $nodes   = $req->{node};
#    my $service = "xcat";
#    my @requests;
#
# find service nodes for requested nodes
# build an individual request for each service node
#    $sn = xCAT::Utils->get_ServiceNode($nodes, $service, "MN");

# build each request for each service node

#    foreach my $snkey (keys %$sn)
#    {
#        my $reqcopy = {%$req};
#        $reqcopy->{node} = $sn->{$snkey};
#        $reqcopy->{'_xcatdest'} = $snkey;
#        push @requests, $reqcopy;

#    }
#    return \@requests;
#}

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
    my $rsp      = {};

    sinv($nodes, $args, $callback, $command, $request->{noderange}->[0]);
}

#-------------------------------------------------------

=head3  sinv 

   Parses Builds and runs the sinv 


=cut

#-------------------------------------------------------
sub sinv
{
    my ($nodes, $args, $callback, $command, $noderange) = @_;

    my $rsp = {};

    # parse  input
    my @local_results =
      xCAT::SINV->parse_and_run_sinv($nodes,   $args, $callback,
                                     $command, $noderange);
    push @{$rsp->{data}}, @local_results;

    xCAT::MsgUtils->message("I", $rsp, $callback);

    return;
}
