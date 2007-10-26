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
    my %rsp;
    $::DSH = "/opt/csm/bin/dsh";
    $::DCP = "/opt/csm/bin/dcp";

    # check that dsh is installed
    if (!-e $::DSH)
    {
        $rsp->{data}->[0] =
          "dsh is not installed. Cannot process the command\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);

    }
    else
    {

        if (($command eq "xdsh") || ($command eq "xdcp"))
        {
            return
              xdsh($nodes, $args, $callback, $command,
                   $request->{noderange}->[0]);
        }
        else
        {    # error
            $rsp->{data}->[0] =
              "Unknown command $command.  Cannot process the command\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
        }
    }
}

#-------------------------------------------------------

=head3  xdsh 

   Builds and runs the dsh or dcp command 


=cut

#-------------------------------------------------------
sub xdsh
{
    my $nodes     = shift;
    my $args      = shift;
    my $callback  = shift;
    my $command   = shift;
    my $noderange = shift;

    #
    # set XCAT Context
    #
    $ENV{DSH_CONTEXT} = "XCAT";

    #
    #  if nodes, Put nodes in a file so we do
    #  not risk hitting a command line
    #  limit
    my $node_file;
    if ($nodes)
    {
        $node_file = xCAT::Utils->make_node_list_file($nodes);
        $ENV{'DSH_LIST'} = $node_file;    # export the file for dsh
    }

    #
    # call dsh or dcp
    #

    my $dsh_dcp_command = "";
    my %rsp;
    if ($command eq "xdsh")
    {
        $dsh_dcp_command = $::DSH;
    }
    else
    {
        $dsh_dcp_command = $::DCP;
    }
    $dsh_dcp_command .= " ";

    foreach my $arg (@$args)
    {    # add arguments
        $dsh_dcp_command .= $arg;    # last argument must be command to run
        $dsh_dcp_command .= " ";
    }
    $dsh_dcp_command .= "2>&1";
    my @local_results = `$dsh_dcp_command`;    #  run the dsh command
    my $rc            = $? >> 8;
    my $i             = 0;
    chop @local_results;
    foreach my $line (@local_results)
    {
        $rsp->{data}->[$i] = $line;
        $i++;
    }

    #$rsp->{data}->[$i] = "Return Code = $rc\n";
    xCAT::Utils->close_delete_file($::NODE_LIST_FILE, $node_file);
    xCAT::MsgUtils->message("I", $rsp, $callback);

    #xCAT::MsgUtils->message("I", $rsp);
    #$callback->($rsp);
    return 0;
}

