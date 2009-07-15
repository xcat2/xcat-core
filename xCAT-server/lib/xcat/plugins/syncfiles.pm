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
    xCAT::Postage->syncfiles($client,$callback,$subreq);
}

