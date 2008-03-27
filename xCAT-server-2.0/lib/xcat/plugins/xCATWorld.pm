# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle xCATWorld

   Supported command:
         xCATWorld->xCATWorld

=cut

#-------------------------------------------------------
package xCAT_plugin::xCATWorld;
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
    my $i = 0;
    my @nodes=@$nodes; 
    # do your processing here
    # return info
    foreach $node (@nodes)
    {
        $rsp->{data}->[$i] = "Hello $node\n";
        $i++;
    }
    xCAT::MsgUtils->message("I", $rsp, $callback, 0);
    return;

}

