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
use Storable qw(dclone);
use File::Basename;
use File::Path;
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
    my $command = $req->{command}->[0];    # xdsh vs xdcp

    #if already preprocessed, go straight to request
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }
    my $nodes   = $req->{node};
    my $service = "xcat";
    my @requests;
    my $syncsn = 0;
    my $syncsnfile;
    my $dcppull = 0;

    # read the environment variables for rsync setup
    foreach my $envar (@{$req->{env}})
    {
        my ($var, $value) = split(/=/, $envar, 2);
        if ($var eq "RSYNCSNONLY")
        {    # syncing SN, will change noderange to list of SN
                # we are only syncing the service node ( -s flag)
            $syncsn = 1;
        }
        if ($var eq "DSH_RSYNC_FILE")    # from -F flag
        {    # if hierarchy,need to copy file to the SN
            $syncsnfile = $value;    # in the new /tmp/xcatrf.tmp
        }
        if ($var eq "DCP_PULL")    # from -P flag
        {   
            $dcppull = 1;    # TBD  handle pull hierarchy  
        }
    }

    # find service nodes for requested nodes
    # build an individual request for each service node
    # find out the names for the Management Node
    my @MNnodeinfo    = xCAT::Utils->determinehostname;
    my $MNnodename    = pop @MNnodeinfo;                  # hostname
    my @MNnodeipaddr  = @MNnodeinfo;                      # ipaddresses
    my $mnname        = $MNnodeipaddr[0];
    my $tmpsyncsnfile = "/tmp/xcatrf.tmp";
    my $SNpath;

    my $synfiledir = "/var/xcat/syncfiles";               # default
    if ($nodes)
    {
        $sn = xCAT::Utils->get_ServiceNode($nodes, $service, "MN");
        my @snodes;
        my @snoderange;

        # check to see if service nodes and not just the MN
        if ($sn)
        {
            foreach my $snkey (keys %$sn)
            {
                if (!grep(/$snkey/, @MNnodeipaddr))
                {    # if not the MN
                    push @snodes, $snkey;
                    $snoderange[0] .= "$snkey,";

                }
            }

            if (@snodes)
            {

                # get the directory on the servicenode to put the  files in
                my @syndir = xCAT::Utils->get_site_attribute("SNsyncfiledir");
                if ($syndir[0])
                {
                    $synfiledir = $syndir[0];
                }

                # if -F command and service nodes first need to rsync the SN
                if ($syncsnfile)
                {

                    #change noderange to the service nodes
                    my $addreq;
                    chop $snoderange[0];
                    $addreq->{'_xcatdest'}  = $mnname;
                    $addreq->{node}         = \@snodes;
                    $addreq->{noderange}    = \@snoderange;
                    $addreq->{arg}->[0]     = "-s";
                    $addreq->{arg}->[1]     = "-F";
                    $addreq->{arg}->[2]     = $syncsnfile;
                    $addreq->{command}->[0] = $req->{command}->[0];
                    $addreq->{cwd}->[0]     = $req->{cwd}->[0];
                    push @requests, $addreq;

                    # need to add to the queue to copy rsync file( -F input)
                    # to the service node  to the /tmp/xcatrf.tmp file
                    my $addreq;
                    $addreq->{'_xcatdest'}  = $mnname;
                    $addreq->{node}         = \@snodes;
                    $addreq->{noderange}    = \@snoderange;
                    $addreq->{arg}->[0]     = $syncsnfile;
                    $addreq->{arg}->[1]     = $tmpsyncsnfile;
                    $addreq->{command}->[0] = $req->{command}->[0];
                    $addreq->{cwd}->[0]     = $req->{cwd}->[0];
                    push @requests, $addreq;
                }
                else
                {

                    # if other xdcp command
                    # mk the diretory on the SN to hold the files
                    # to be sent to the CN.
                    # build a command to update the service nodes
                    # change the destination to the tmp location on
                    # the service node, if not pull function 
                    if (($command eq "xdcp") && ($dcppull == 0))
                    {

                        #make the needed directory on the service node
                        # create new directory for path on Service Node
                        my $frompath = $req->{arg}->[-2];
                        $SNpath = $synfiledir;
                        $SNpath .= $frompath;
                        my $SNdir;
                        $SNdir = dirname($SNpath); # get directory
                        my $addreq= dclone($req);
                        $addreq->{'_xcatdest'}  = $mnname;
                        $addreq->{node}         = \@snodes;
                        $addreq->{noderange}    = \@snoderange;
                        $addreq->{arg}->[0]     = "mkdir ";
                        $addreq->{arg}->[1]     = "-p ";
                        $addreq->{arg}->[2]     = $SNdir;
                        $addreq->{command}->[0] = "xdsh";
                        $addreq->{cwd}->[0]     = $req->{cwd}->[0];
                        push @requests, $addreq;

                        # now sync file to the service node to the new
                        # tmp path
                        my $addreq = dclone($req);
                        $addreq->{'_xcatdest'} = $mnname;
                        chop $snoderange[0];
                        $addreq->{node}      = \@snodes;
                        $addreq->{noderange} = \@snoderange;
                        $addreq->{arg}->[-1] = $SNdir;
                        push @requests, $addreq;

                    }
                }
            }
        }    # end if SN

        # if not only syncing the service nodes ( -s flag)
        # for each node build the
        # the command, to sync from the service node
        if ($syncsn == 0)
        {    #syncing nodes ( no -s flag)
            foreach my $snkey (keys %$sn)
            {

                if (!grep(/$snkey/, @MNnodeipaddr))
                {    # entries run from the Service Node

                    # if the -F option to sync the nodes
                    # then for a Service Node
                    # change the command to use the -F /tmp/xcatrf.tmp
                    # because that is where the file was put on the SN
                    #
                    my $newSNreq = dclone($req);
                    if ($syncsnfile)    # -F option
                    {
                        my $args = $newSNreq->{arg};

                        my $i = 0;
                        foreach my $argument (@$args)
                        {

                            # find the -F and change the name of the
                            # file in the next array entry to the tmp file
                            if ($argument eq "-F")
                            {
                                $i++;
                                $newSNreq->{arg}->[$i] = $tmpsyncsnfile;
                                last;
                            }
                            $i++;
                        }
                    }
                    else
                    {    # if other dcp command, change from directory
                            # to be the tmp directory on the service node
                         # if not pull (-P) funcion
                        if (($command eq "xdcp") && ($dcppull == 0))
                        {
                            $newSNreq->{arg}->[-2] = $SNpath;
                        }
                    }
                    $newSNreq->{node}                   = $sn->{$snkey};
                    $newSNreq->{'_xcatdest'}            = $snkey;
                    $newSNreq->{_xcatpreprocessed}->[0] = 1;
                    push @requests, $newSNreq;
                }
                else
                {           # just run normal dsh dcp
                    my $reqcopy = {%$req};
                    $reqcopy->{node}                   = $sn->{$snkey};
                    $reqcopy->{'_xcatdest'}            = $snkey;
                    $reqcopy->{_xcatpreprocessed}->[0] = 1;
                    push @requests, $reqcopy;

                }
            }    # end foreach
        }    # end syncing only service nodes

    }
    else
    {        # running local on image
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

    xCAT::MsgUtils->message("D", $rsp, $callback);

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

    xCAT::MsgUtils->message("D", $rsp, $callback);
    if (-e "/tmp/xcatrf.tmp")
    {    # used tmp file for -F option
            #`rm /tmp/xcatrf.tmp`;
    }
    return;
}

