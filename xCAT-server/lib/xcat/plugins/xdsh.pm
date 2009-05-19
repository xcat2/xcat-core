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
use strict;
require xCAT::Table;

require xCAT::Utils;

require xCAT::MsgUtils;
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

=head3  preprocess_request

  Check and setup for hierarchy 

=cut

#-------------------------------------------------------
sub preprocess_request
{
    my $req = shift;
    my $cb  = shift;
    my %sn;
    my $sn;

    #if already preprocessed, go straight to request
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }
    my $nodes   = $req->{node};
    my $service = "xcat";
    my @requests;
    my $syncsn = 0;
    foreach my $envar (@{$req->{env}})
    {
        my ($var, $value) = split(/=/, $envar, 2);
        if ($var eq "RSYNCSN")
        {    # syncing SN, will change
            $syncsn = 1;    # nodelist to the list of SN
            last;           # for those nodes
        }
    }

    # find service nodes for requested nodes
    # build an individual request for each service node
    if ($nodes)
    {
        $sn = xCAT::Utils->get_ServiceNode($nodes, $service, "MN");
        if ($syncsn == 0)
        {                   # not syncing sn, do hierarchy
                            # build each request for each service node

            foreach my $snkey (keys %$sn)
            {
                my $reqcopy = {%$req};
                $reqcopy->{node}                   = $sn->{$snkey};
                $reqcopy->{'_xcatdest'}            = $snkey;
                $reqcopy->{_xcatpreprocessed}->[0] = 1;
                push @requests, $reqcopy;

            }
        }
        else
        {    # syncing SN
                # rebuild nodelist and noderange with service nodes
            my @snodes;
            my @snoderange;
            foreach my $snkey (keys %$sn)
            {
                push @snodes, $snkey;
                $snoderange[0] .= "$snkey,";

            }
            chop $snoderange[0];
            $req->{node}      = \@snodes;
            $req->{noderange} = \@snoderange;
            return [$req];
        }
    }
    else
    {    # running local on image
        return [$req];
    }
    return \@requests;
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
    my $rsp      = {};

    # get the Environment Variables and set them in the current environment
    foreach my $envar (@{$request->{env}})
    {
        my ($var, $value) = split(/=/, $envar, 2);
        $ENV{$var} = $value;
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
            my $rsp = {};
            $rsp->{data}->[0] =
              "Unknown command $command.  Cannot process the command.";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            return;
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

    my $rsp = {};

    # parse dsh input
    my @local_results =
      xCAT::DSHCLI->parse_and_run_dsh($nodes,   $args, $callback,
                                      $command, $noderange);
    push @{$rsp->{data}}, @local_results;

    xCAT::MsgUtils->message("I", $rsp, $callback);

    return;
}

#-------------------------------------------------------

=head3  xdcp

   Parses, Builds and runs the dcp command


=cut

#-------------------------------------------------------
sub xdcp
{
    my ($nodes, $args, $callback, $command, $noderange) = @_;

    #`touch /tmp/lissadebug`;
    # parse dcp input
    my @local_results =
      xCAT::DSHCLI->parse_and_run_dcp($nodes,   $args, $callback,
                                      $command, $noderange);
    my $rsp = {};
    my $i   = 0;
    ##  process return data
    foreach my $line (@local_results)
    {
        $rsp->{data}->[$i] = $line;
        $i++;
    }

    xCAT::MsgUtils->message("I", $rsp, $callback);

    return;
}

