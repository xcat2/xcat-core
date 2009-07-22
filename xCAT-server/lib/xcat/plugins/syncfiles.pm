# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle syncfiles command

=cut

#-------------------------------------------------------
package xCAT_plugin::syncfiles;
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
    return {'syncfiles' => "syncfiles"};
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
    my $subreq   = shift;

    my $client;
    if ($request->{'_xcat_clienthost'}) {
      $client = $request->{'_xcat_clienthost'}->[0];
    }

    if ($client) { ($client) = noderange($client) };
    unless ($client) { #Not able to do identify the host in question
       xCAT::MsgUtils->message("S","Received syncfiles from $client, which couldn't be correlated to a node (domain mismatch?)");
      return;
    }

    require xCAT::Postage;
    &syncfiles($client,$callback,$subreq);
}


#----------------------------------------------------------------------------

=head3  syncfiles

        Use the xdcp command to sync files from Management node/Service node t
o the Compute node

        Arguments:
        Returns: 0 - failed; 1 - succeeded;
        Example:
                syncfiles($node, $callback);

        Comments:

=cut

#-----------------------------------------------------------------------------

sub syncfiles {
  my $node = shift;
  if ($node =~ /xCAT::Postage/) {
    $node = shift;
  }
  my $callback = shift;
  my $subreq = shift;

  #get the sync file base on the node type
  my $synclist = xCAT::SvrUtils->getsynclistfile([$node]);
  if (!$synclist) {
    xCAT::MsgUtils->message("S", "Cannot find synclist file for the $node");
    return 0;
  }

  # call the xdcp plugin to handle the syncfile operation
  my $args = ["-F", "$$synclist{$node}"];
  my $env = ["DSH_RSYNC_FILE=$$synclist{$node}"];
  $subreq->({command=>['xdcp'], node=>[$node], arg=>$args, env=>$env}, $callback);

  return 1;
}

1;
