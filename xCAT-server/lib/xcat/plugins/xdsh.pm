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
    my $syncsn     = 0;
    my $syncsnfile = "NONE";
    foreach my $envar (@{$req->{env}})
    {
        my ($var, $value) = split(/=/, $envar, 2);
        if ($var eq "RSYNCSN")
        {    # syncing SN, will change noderange to list of SN
            $syncsn = 1;
        }
        if ($var eq "DSH_RSYNC_FILE")    # from -F flag
        {    # if hierarchy,need to copy file to the SN
            $syncsnfile = $value;    # in the new /tmp/xcatrf.tmp
        }
    }

    # find service nodes for requested nodes
    # build an individual request for each service node
    # find out the names for the Management Node
    my @MNnodeinfo   = xCAT::Utils->determinehostname;
    my $MNnodename   = pop @MNnodeinfo;                  # hostname
    my @MNnodeipaddr = @MNnodeinfo;                      # ipaddresses
    if ($nodes)
    {
        $sn = xCAT::Utils->get_ServiceNode($nodes, $service, "MN");
        if ($syncsn == 0)
        {    # not syncing the service node ( -s option) , do hierarchy
                # build each request for each service node
                # the file that will contain the sync request on the SN
            my $tmpsyncsnfile = "/tmp/xcatrf.tmp";

            # if -F command to rsync the SN and nodes
            # need to add to the commands to copy rsync file to the service node
            # to the /tmp/xcatrf.tmp file
            if ($syncsnfile ne "NONE")    # -F command
            {
                foreach my $snkey (keys %$sn)
                {
                    if (!grep(/$snkey/, @MNnodeipaddr))
                    {                     # not the MN
                        my $addreq;
                        $addreq->{node}->[0]      = $snkey;
                        $addreq->{noderange}->[0] = $snkey;
                        $addreq->{arg}->[0]       = $syncsnfile;
                        $addreq->{arg}->[1]       = $tmpsyncsnfile;
                        $addreq->{command}->[0]   = $req->{command}->[0];
                        $addreq->{cwd}->[0]       = $req->{cwd}->[0];
                        push @requests, $addreq;
                    }

                }
            }

            # now for each service node build the command
            foreach my $snkey (keys %$sn)
            {
                my $reqcopy = {%$req};
                if (!grep(/$snkey/, @MNnodeipaddr))    # not the MN
                {

                    # if the -F option to sync the nodes
                    # then for a Service Node
                    # change the command to use the -F /tmp/xcatrf.tmp
                    # because that is where the file was put on the SN
                    #
                    if ($syncsnfile ne "NONE")         # -F option
                    {
                        my $args = $reqcopy->{arg};
                        my $i    = 0;
                        foreach my $argument (@$args)
                        {

                            # find the -F and change the name of the
                            # file in the next array entry to the tmp file
                            if ($argument eq "-F")
                            {
                                $i++;
                                $reqcopy->{arg}->[$i] = $tmpsyncsnfile;
                                last;
                            }
                            $i++;
                        }
                    }
                }
                $reqcopy->{node}                   = $sn->{$snkey};
                $reqcopy->{'_xcatdest'}            = $snkey;
                $reqcopy->{_xcatpreprocessed}->[0] = 1;
                push @requests, $reqcopy;

            }
        }
        else
        {    # syncing SN, the file are being sent to the service nodes
                # of the noderange not to the noderange itself
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
    if ( -e "/tmp/xcatrf.tmp") { # used tmp file for -F option
      `rm /tmp/xcatrf.tmp`;
    }
    return;
}

