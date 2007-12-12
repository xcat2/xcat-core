# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1 
  xCAT plugin package to handle xdsh

   Supported command:
         xdsh-> dsh
         xdcp-> dcp

=cut

#-------------------------------------------------------
package xCAT_plugin::xdsh;
use xCAT::Table;

use xCAT::Utils;

use xCAT::MsgUtils;
use Getopt::Long;
require xCAT::DSHCLI;
1;

#-------------------------------------------------------

=head3  handled_commands 

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {
            xdsh => "xdsh",
            xdcp => "xdsh"
            };
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

    # get Environment Variables
    my $outref = [];
    foreach my $envar (@{$request->{env}})
    {
        my $cmd = "export ";
        $cmd .= $envar;
        $cmd .= ";";
        @$outref = `$cmd`;
        if ($? > 0)
        {
            my %rsp;
            $rsp->{data}->[0] = "Error running command: $cmd\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;

        }
    }
    if ($command eq "xdsh")
    {
        xdsh($nodes, $args, $callback, $command, $request->{noderange}->[0]);
    }
    else
    {
        if ($command eq "xdcp")
        {
            xdcp($nodes, $args, $callback, $command,
                 $request->{noderange}->[0]);
        }
        else
        {
            my %rsp;
            $rsp->{data}->[0] =
              "Unknown command $command.  Cannot process the command\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
    }
}

#-------------------------------------------------------

=head3  xdsh 

   Parses Builds and runs the dsh  


=cut

#-------------------------------------------------------
sub xdsh
{
    my ($nodes, $args, $callback, $command, $noderange) = @_;

    # parse dsh input
    @local_results =
      xCAT::DSHCLI->parse_and_run_dsh($nodes,   $args, $callback,
                                      $command, $noderange);
    my %rsp;
    my $i = 0;
    ##  process return data
    foreach my $line (@local_results)
    {
        $rsp->{data}->[$i] = $line;
        $i++;
    }

    xCAT::MsgUtils->message("I", $rsp, $callback);

    return 0;
}

#-------------------------------------------------------

=head3  xdcp 

   Parses, Builds and runs the dcp command 


=cut

#-------------------------------------------------------
sub xdcp
{
    my ($nodes, $args, $callback, $command, $noderange) = @_;

    # parse dcp input
    @local_results =
      xCAT::DSHCLI->parse_and_run_dcp($nodes,   $args, $callback,
                                      $command, $noderange);
    my %rsp;
    my $i = 0;
    ##  process return data
    foreach my $line (@local_results)
    {
        $rsp->{data}->[$i] = $line;
        $i++;
    }

    xCAT::MsgUtils->message("I", $rsp, $callback);

    return 0;
}

