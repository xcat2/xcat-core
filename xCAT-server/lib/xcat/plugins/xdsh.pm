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
use POSIX;
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
    my $req     = shift;
    my $cb      = shift;
    my $sub_req = shift;
    my %sn;
    my $sn;
    my $rc = 0;

    #if already preprocessed, go straight to request
    if (   (defined($req->{_xcatpreprocessed}))
        && ($req->{_xcatpreprocessed}->[0] == 1))
    {
        return [$req];
    }
    my $command = $req->{command}->[0];    # xdsh vs xdcp
    my $nodes   = $req->{node};
    my $service = "xcat";
    my @requests;
    $::tmpsyncsnfile = "/tmp/xcatrf.tmp";
    $::RUNCMD_RC     = 0;
    @::good_SN;
    @::bad_SN;
    my $syncsn = 0;                        # sync service node only if 1

    # read the environment variables for rsync setup
    # and xdsh -e command
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
            $::syncsnfile = $value;    # in the new /tmp/xcatrf.tmp
        }
        if ($var eq "DCP_PULL")        # from -P flag
        {
            $::dcppull = 1;            # TBD  handle pull hierarchy
        }
        if ($var eq "DSHEXECUTE")      # from xdsh -e flag
        {
            $::dshexecutecmd = $value;   # Handle hierarchy 
            my @cmd = split(/ /, $value); # split off args, if any
            $::dshexecute = $cmd[0];      # This is the executable file 
        }
    }

    # there are nodes in the xdsh command, not xdsh  to an image
    if ($nodes)
    {

        # find service nodes for requested nodes
        # build an individual request for each service node
        # find out the names for the Management Node
        my @MNnodeinfo   = xCAT::Utils->determinehostname;
        my $MNnodename   = pop @MNnodeinfo;                  # hostname
        my @MNnodeipaddr = @MNnodeinfo;                      # ipaddresses
        $::mnname = $MNnodeipaddr[0];
        $::SNpath;    # syncfile path on the service node
        $sn = xCAT::Utils->get_ServiceNode($nodes, $service, "MN");
        my @snodes;
        my @snoderange;

        # check to see if service nodes and not just the MN
        # if just MN, then no hierarchy to deal with
        if ($sn)
        {
            foreach my $snkey (keys %$sn)
            {
                if (!grep(/$snkey/, @MNnodeipaddr))
                {     # if not the MN
                    push @snodes, $snkey;
                    $snoderange[0] .= "$snkey,";
                    chop $snoderange[0];

                }
            }
        }

        # if servicenodes and (if xdcp and not pull function or xdsh -e)
        # send command to service nodes first and process errors
        # return an array  of good service nodes
        #
        my $synfiledir;
        if (@snodes)    # service nodes
        {

            # if xdcp and not pull function or xdsh -e
            if ((($command eq "xdcp") && ($::dcppull == 0)) or ($::dshexecute))
            {

                # get the directory on the servicenode to put the  files in
                my @syndir = xCAT::Utils->get_site_attribute("SNsyncfiledir");
                if ($syndir[0])
                {
                    $synfiledir = $syndir[0];
                }
                else
                {
                    $synfiledir = "/var/xcat/syncfiles";    # default
                }

                # setup the service node with the files to xdcp to the
                # compute nodes
                if ($command eq "xdcp"){
                  $rc =
                    &process_servicenodes_xdcp($req, $cb, $sub_req, \@snodes,
                                        \@snoderange, $synfiledir);

                  # fatal error need to stop
                  if ($rc != 0)
                  {
                     return;
                  }
                } else {  # xdsh -e
                   $rc =
                    &process_servicenodes_xdsh($req, $cb, $sub_req, \@snodes,
                                        \@snoderange, $synfiledir);

                   # fatal error need to stop
                   if ($rc != 0)
                   {
                      return;
                   }
                }
            }
            else
            {    # command is xdsh ( not -e)  or xdcp pull
                @::good_SN = @snodes;    # all good service nodes for now
            }

        }
        else
        {                                # no servicenodes, no hierarchy
                                         # process here on the MN
            &process_request($req, $cb, $sub_req);
            return;

        }

        # if  hierarchical work still to do
        # Note there may still be a mix of nodes that are service from
        # the MN and nodes that are serviced from the SN, for example
        # a dsh to a list of servicenodes and nodes in the noderange.

        if ($syncsn == 0)    # not just syncing (-s) the service nodes
                             # taken care of in process_servicenodes

        {
            foreach my $snkey (keys %$sn)
            {

                # if it is not being service by the MN
                if (!grep(/$snkey/, @MNnodeipaddr))
                {

                    # if it is a good SN, one ready to service the nodes
                    if (grep(/$snkey/, @::good_SN))
                    {
                        my $noderequests =
                            &process_nodes($req, $sn, $snkey,$synfiledir);
                        push @requests, $noderequests;    # build request queue

                    }
                }
                else    # serviced by the MN, then
                {       # just run normal dsh dcp
                    my $reqcopy = {%$req};
                    $reqcopy->{node}                   = $sn->{$snkey};
                    $reqcopy->{'_xcatdest'}            = $snkey;
                    $reqcopy->{_xcatpreprocessed}->[0] = 1;
                    push @requests, $reqcopy;

                }
            }    # end foreach
        }    # end syncing  nodes
    }
    else     # no nodes on the command
    {        # running on local image
        return [$req];
    }
    return \@requests;
}

#-------------------------------------------------------

=head3  process_servicenodes_xdcp
  Build the xdcp command to send to the service nodes first 
  Return an array of servicenodes that do not have errors 
  Returns error code:
  if  = 0,  good return continue to process the
	  nodes.
  if  = 1,  global error need to quit

=cut

#-------------------------------------------------------
sub process_servicenodes_xdcp
{

    my $req        = shift;
    my $callback   = shift;
    my $sub_req    = shift;
    my $sn         = shift;
    my $snrange    = shift;
    my $synfiledir = shift;
    my @snodes     = @$sn;
    my @snoderange = @$snrange;
    my $args;
    $::RUNCMD_RC = 0;
    my $cmd = $req->{command}->[0];

    # if xdcp -F command (input $syncsnfile) and service nodes first need
    #   to be rsync to the
    #  $synfiledir  directory
    if ($::syncsnfile)
    {
        if (!-f $::syncsnfile)
        {    # syncfile does not exist,  quit
            my $rsp = {};
            $rsp->{data}->[0] = "File:$::syncsnfile does not exist.";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            return (1);    # process no service nodes
        }

        # xdcp rsync each of the files contained in the -F syncfile to
        # the service node first to the site.SNsyncfiledir directory
        #change noderange to the service nodes
        # sync each one and check for error
        # if error do not add to good_SN array, add to bad_SN
        foreach my $node (@snodes)
        {

            # run the command to each servicenode
            # xdcp <sn> -s -F <syncfile>
            my @sn = ();
            # handle multiple servicenodes for one node
            my @sn_list = split ',', $node;
            foreach my $snode (@sn_list) {
             push @sn, $snode;
            }
            # don't use runxcmd, because can go straight to process_request,
            # these are all service nodes. Also servicenode is taken from
            # the noderes table and may not be the same name as in the nodelist
            # table, for example may be an ip address.
            # here on the MN
            my $addreq;
            $addreq->{'_xcatdest'}  = $::mnname;
            $addreq->{node}         = \@sn;
            $addreq->{noderange}    = \@sn;
            $addreq->{arg}->[0]     = "-s";
            $addreq->{arg}->[1]     = "-F";
            $addreq->{arg}->[2]     = $::syncsnfile;
            $addreq->{command}->[0] = $cmd;
            $addreq->{cwd}->[0]     = $req->{cwd}->[0];
            $addreq->{env}          = $req->{env};
            &process_request($addreq, $callback, $sub_req);

            if ($::FAILED_NODES == 0)
            {
                push @::good_SN, $node;
            }
            else
            {
                push @::bad_SN, $node;
            }
        }    # end foreach good servicenode

        # for all the service nodes that are still good
        # need to xdcp rsync file( -F input)
        # to the service node  to the /tmp/xcatrf.tmp file
        my @good_SN2 = @::good_SN;
        @::good_SN = ();
        foreach my $node (@good_SN2)
        {
            my @sn = ();
            push @sn, $node;

            # run the command to each good servicenode
            # xdcp <sn> <syncfile> <tmp/xcatrf.tmp>
            my $addreq;
            $addreq->{'_xcatdest'}  = $::mnname;
            $addreq->{node}         = \@sn;
            $addreq->{noderange}    = \@sn;
            $addreq->{arg}->[0]     = "$::syncsnfile";
            $addreq->{arg}->[1]     = "$::tmpsyncsnfile";
            $addreq->{command}->[0] = $cmd;
            $addreq->{cwd}->[0]     = $req->{cwd}->[0];
            $addreq->{env}          = $req->{env};
            &process_request($addreq, $callback, $sub_req);

            if ($::FAILED_NODES == 0)
            {
                push @::good_SN, $node;
            }
            else
            {
                push @::bad_SN, $node;
            }

        }    # end foreach good service node
    }    # end  xdcp -F
    else
    {

        # if other xdcp commands, and not pull function
        # mk the directory on the SN to hold the files
        # to be sent to the SN.
        # build a command to update the service nodes
        # change the destination to the tmp location on
        # the service node
        # hierarchical support for pull (TBD)

        #make the needed directory on the service node
        # create new directory for path on Service Node
        # xdsh  <sn> mkdir -p $SNdir
        my $frompath = $req->{arg}->[-2];
        $::SNpath = $synfiledir;
        $::SNpath .= $frompath;
        my $SNdir;
        $SNdir = dirname($::SNpath);    # get directory

        foreach my $node (@snodes)
        {
            my @sn = ();
            # handle multiple servicenodes for one node
            my @sn_list = split ',', $node;
            foreach my $snode (@sn_list) {
             push @sn, $snode;
            }

            # run the command to each servicenode
            # to make the directory under the temporary
            # SNsyncfiledir to hold the files that will be
            # sent to the service nodes
            # xdsh <sn> mkdir -p <SNsyncfiledir>/$::SNpath
            my $addreq;
            $addreq->{'_xcatdest'}  = $::mnname;
            $addreq->{node}         = \@sn;
            $addreq->{noderange}    = \@sn;
            $addreq->{arg}->[0]     = "mkdir ";
            $addreq->{arg}->[1]     = "-p ";
            $addreq->{arg}->[2]     = $SNdir;
            $addreq->{command}->[0] = 'xdsh';
            $addreq->{cwd}->[0]     = $req->{cwd}->[0];
            $addreq->{env}          = $req->{env};
            &process_request($addreq, $callback, $sub_req);

            if ($::FAILED_NODES == 0)
            {
                push @::good_SN, $node;
            }
            else
            {
                push @::bad_SN, $node;
            }
        }    # end foreach good servicenode

        # now xdcp file to the service node to the new
        # tmp path

        # for all the service nodes that are still good
        my @good_SN2 = @::good_SN;
        @::good_SN = ();
        foreach my $node (@good_SN2)
        {
            my @sn;
            push @sn, $node;

            # copy the file to each good servicenode
            # xdcp <sn> <file> <SNsyncfiledir/../file>
            my $addreq = dclone($req);    # get original request
            $addreq->{arg}->[-1] = $SNdir;    # change to tmppath on servicenode
            $addreq->{'_xcatdest'} = $::mnname;
            $addreq->{node}        = \@sn;
            $addreq->{noderange}   = \@sn;
            &process_request($addreq, $callback, $sub_req);

            if ($::FAILED_NODES == 0)
            {
                push @::good_SN, $node;
            }
            else
            {
                push @::bad_SN, $node;
            }

        }    # end foreach good service node
    }

    # report bad service nodes]
    if (@::bad_SN)
    {
        my $rsp = {};
        my $badnodes;
        foreach my $badnode (@::bad_SN)
        {
            $badnodes .= $badnode;
            $badnodes .= ", ";
        }
        chop $badnodes;
        my $msg =
          "\nThe following servicenodes: $badnodes have errors and cannot be updated\n Until the error is fixed, xdcp will not work to nodes serviced by these service nodes.";
        $rsp->{data}->[0] = $msg;
        xCAT::MsgUtils->message("D", $rsp, $callback);
    }
    return (0);
}
#-------------------------------------------------------

=head3  process_servicenodes_xdsh
  Build the xdsh command to send the -e file 
  The executable must be copied into /var/xcat/syncfiles, and then
  the command modified so that the xdsh running on the SN will cp the file
  from /var/xcat/syncfiles to the compute node /tmp directory and run it.
  Return an array of servicenodes that do not have errors 
  Returns error code:
  if  = 0,  good return continue to process the
	  nodes.
  if  = 1,  global error need to quit

=cut

#-------------------------------------------------------
sub process_servicenodes_xdsh
{

    my $req        = shift;
    my $callback   = shift;
    my $sub_req    = shift;
    my $sn         = shift;
    my $snrange    = shift;
    my $synfiledir = shift;
    my @snodes     = @$sn;
    my @snoderange = @$snrange;
    my $args;
    $::RUNCMD_RC = 0;
    my $cmd = $req->{command}->[0];

    # if xdsh -e <executable> command, service nodes first need
    #   to be rsync with the executable file to the $synfiledir
    if ($::dshexecute)
    {
        if (!-f $::dshexecute)
        {    # -e file  does not exist,  quit
            my $rsp = {};
            $rsp->{data}->[0] = "File:$::dshexecute does not exist.";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            return (1);    # process no service nodes
        }

        # xdcp the executable from the xdsh -e to the service node first
        # change noderange to the service nodes
        # sync to each SN and check for error
        # if error do not add to good_SN array, add to bad_SN

        # build a tmp syncfile with
        # $::dshexecute -> $synfiledir . $::dshexecute
        my $tmpsyncfile = POSIX::tmpnam . ".dsh";
        my $destination=$synfiledir . $::dshexecute;
        open(TMPFILE, "> $tmpsyncfile")
                  or die "can not open file $tmpsyncfile";
                print TMPFILE "$::dshexecute -> $destination\n";
        close TMPFILE;
        chmod 0755, $tmpsyncfile;
        foreach my $node (@snodes)
        {

            # sync the file to the SN /var/xcat/syncfiles directory
            # (site.SNsyncfiledir) 
            # xdcp <sn> -s -F <tmpsyncfile>
  
            my @sn = ();
            # handle multiple servicenodes for one node
            my @sn_list = split ',', $node;
            foreach my $snode (@sn_list) {
             push @sn, $snode;
            }

            # don't use runxcmd, because can go straight to process_request,
            # these are all service nodes. Also servicenode is taken from
            # the noderes table and may not be the same name as in the nodelist
            # table, for example may be an ip address.
            # here on the MN
            my $addreq;
            $addreq->{'_xcatdest'}  = $::mnname;
            $addreq->{node}         = \@sn;
            $addreq->{noderange}    = \@sn;
            $addreq->{arg}->[0]     = "-s";
            $addreq->{arg}->[1]     = "-F";
            $addreq->{arg}->[2]     = $tmpsyncfile;
            $addreq->{command}->[0] = "xdcp";
            $addreq->{cwd}->[0]     = $req->{cwd}->[0];
            $addreq->{env}          = $req->{env};
            &process_request($addreq, $callback, $sub_req);

            if ($::FAILED_NODES == 0)
            {
                push @::good_SN, $node;
            }
            else
            {
                push @::bad_SN, $node;
            }
        }    # end foreach good servicenode
        # remove the tmp syncfile
        `/bin/rm $tmpsyncfile`;

    }    # end  xdsh -E

    # report bad service nodes]
    if (@::bad_SN)
    {
        my $rsp = {};
        my $badnodes;
        foreach my $badnode (@::bad_SN)
        {
            $badnodes .= $badnode;
            $badnodes .= ", ";
        }
        chop $badnodes;
        my $msg =
          "\nThe following servicenodes: $badnodes have errors and cannot be updated\n Until the error is fixed, xdsh -e  will not work to nodes serviced by these service nodes. Run xdsh <servicenode,...> -c ,  to clean up the xdcp servicenode directory, and run the command again.";
        $rsp->{data}->[0] = $msg;
        xCAT::MsgUtils->message("D", $rsp, $callback);
    }
    return (0);
}

#-------------------------------------------------------

=head3  process_nodes

  Build the  request to send to the nodes, serviced by SN 
  Return the request 

=cut

#-------------------------------------------------------
sub process_nodes
{

    my $req     = shift;
    my $sn      = shift;
    my $snkey   = shift;
    my $synfiledir   = shift;
    my $command = $req->{command}->[0];
    my @requests;

    # if the xdcp -F option to sync the nodes
    # then for a Node
    # change the command to use the -F /tmp/xcatrf.tmp
    # because that is where the file was put on the SN
    #
    my $newSNreq = dclone($req);
    if ($::syncsnfile)    # -F option
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
                $newSNreq->{arg}->[$i] = $::tmpsyncsnfile;
                last;
            }
            $i++;
        }
    }
      
    else
    {    # if other dcp command, change from directory
            # to be the site.SNsyncfiledir
            #	directory on the service node
            # if not pull (-P) pullfunction
            # xdsh and xdcp pull just use the input request
        if (($command eq "xdcp") && ($::dcppull == 0))
        {
            $newSNreq->{arg}->[-2] = $::SNpath;
        } else { # if xdsh -e
          if ($::dshexecute) { # put in new path from SN directory
            my $destination=$synfiledir . $::dshexecute;
            my $args = $newSNreq->{arg};
            my $i = 0;
            foreach my $argument (@$args)
            {
               # find the -e and change the name of the
               # file in the next array entry to SN offset 
               if ($argument eq "-e")
               {
                   $i++;
                   $newSNreq->{arg}->[$i] = $destination;
                   last;
                }
                $i++;
                 
            }
          } # end if dshexecute
        } 
    }
    $newSNreq->{node}                   = $sn->{$snkey};
    $newSNreq->{'_xcatdest'}            = $snkey;
    $newSNreq->{_xcatpreprocessed}->[0] = 1;

    #push @requests, $newSNreq;

    return $newSNreq;
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
    my $sub_req  = shift;
    $::SUBREQ = $sub_req;

    my $nodes   = $request->{node};
    my $command = $request->{command}->[0];
    my $args    = $request->{arg};
    my $envs    = $request->{env};
    my $rsp     = {};

    # get the Environment Variables and set them in the current environment
    foreach my $envar (@{$request->{env}})
    {
        my ($var, $value) = split(/=/, $envar, 2);
        $ENV{$var} = $value;
    }
    # if request->{username} exists,  set DSH_FROM_USERID to it
    # override input,  this is what was authenticated
    if (($request->{username}) && defined($request->{username}->[0])) {
       $ENV{DSH_FROM_USERID} = $request->{username}->[0];
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

    $::FAILED_NODES = 0;

    # parse dsh input, will return $::NUMBER_NODES_FAILED
    my @local_results =
      xCAT::DSHCLI->parse_and_run_dsh($nodes,   $args, $callback,
                                      $command, $noderange);

    my $maxlines = 10000;
    my $arraylen = @local_results;
    my $rsp      = {};
    my $i        = 0;
    my $j;
    while ($i < $arraylen)
    {

        for ($j = 0 ; $j < $maxlines ; $j++)
        {
            if ($i > $arraylen)
            {
                last;
            }
            else
            {
                $rsp->{data}->[$j] = $local_results[$i];    # send  max lines
            }
            $i++;
        }
        xCAT::MsgUtils->message("D", $rsp, $callback);
    }

    # set return code
    $rsp = {};
    $rsp->{errorcode} = $::FAILED_NODES;
    $callback->($rsp);
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

    $::FAILED_NODES = 0;

    #`touch /tmp/lissadebug`;
    # parse dcp input
    my @local_results =
      xCAT::DSHCLI->parse_and_run_dcp($nodes,   $args, $callback,
                                      $command, $noderange);
    my $rsp = {};
    my $i   = 0;
    ##  process return data
    if (@local_results)
    {
        foreach my $line (@local_results)
        {
            $rsp->{data}->[$i] = $line;
            $i++;
        }

        xCAT::MsgUtils->message("D", $rsp, $callback);
    }
    if (-e "/tmp/xcatrf.tmp")
    {    # used tmp file for -F option
            #`rm /tmp/xcatrf.tmp`;
    }

    # set return code
    $rsp = {};
    $rsp->{errorcode} = $::FAILED_NODES;
    $callback->($rsp);
    return;
}

