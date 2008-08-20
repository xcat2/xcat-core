# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle getpostscript command

=cut

#-------------------------------------------------------
package xCAT_plugin::getpostscript;
use xCAT::Postage;
use xCAT::Utils;
use xCAT::MsgUtils;
use xCAT::NodeRange;

1;

#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {'getpostscript' => "getpostscript"};
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
    my $rsp;
    my $i = 1;
    my @nodes=@$nodes; 
    # do your processing here
    # return info
    my $client;
    if ($request->{'_xcat_clienthost'}) {
      $client = $request->{'_xcat_clienthost'}->[0];
    }

    if ($client) { ($client) = noderange($client) };
    unless ($client) { #Not able to do identify the host in question
       xCAT::MsgUtils->message("S","Received getpostscript from $client, which couldn't be correlated to a node (domain mismatch?)");
      return;
    }
    my $state;
    if ($request->{scripttype}) { $state = $request->{scripttype}->[0];}

    my @scriptcontents = xCAT::Postage::makescript($client,$state,$callback);
    if (scalar(@scriptcontents)) {
       $rsp->{data} = \@scriptcontents;
    }
    $callback->($rsp);
}

