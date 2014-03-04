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
require xCAT::Zone;
require xCAT::TableUtils;
require xCAT::ServiceNodeUtils;
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
    $::RUNCMD_RC     = 0;
    @::good_SN=();
    @::bad_SN = ();
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
            $::syncsnfile = $value;    # name of syncfile 
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
        if ($var eq "DSH_ENVIRONMENT")      # from xdsh -E flag
        {
            $::dshenvfile = $value;       # Name of file with env variables 
        }
    }
    # if xdcp need to make sure request has full path to input files 
    if ($command eq "xdcp") {
      $req = &parse_xdcp_cmd($req);
    }
    # if xdsh need to make sure request has full path to input files 
    # also process -K flag and use of zones
    if ($command eq "xdsh") {
     $req = &parse_xdsh_cmd($req,$cb,$sub_req);
    }

    # there are nodes in the xdsh command, not xdsh  to an image
    if ($nodes)
    {

        # find service nodes for requested nodes
        # build an individual request for each service node
        # find out the names for the Management Node
        my @MNnodeinfo   = xCAT::NetworkUtils->determinehostname;
        my $MNnodename   = pop @MNnodeinfo;                  # hostname
        my @MNnodeipaddr = @MNnodeinfo;                      # ipaddresses
        $::mnname = $MNnodeipaddr[0];
        $::SNpath;    # syncfile path on the service node
        $sn = xCAT::ServiceNodeUtils->get_ServiceNode($nodes, $service, "MN");
        my @snodes;
        my @snoderange;

        # check to see if service nodes and not just the MN
        # if just MN or I am on a Service Node, then no hierarchy to deal with

        if (! (xCAT::Utils->isServiceNode())) {  # not on a servicenode 
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
        }

        # if servicenodes and (if xdcp and not pull function or xdsh -e)
        # send command to service nodes first and process errors
        # return an array  of good service nodes
        #
        my $synfiledir;
        if (@snodes)    # service nodes
        {

            # if xdcp and not pull function or xdsh -e or xdsh -E
            if ((($command eq "xdcp") && ($::dcppull == 0)) or (($::dshexecute)
                        or ($::dshenvfile)))
            {

                # get the directory on the servicenode to put the  files in
                my @syndir = xCAT::TableUtils->get_site_attribute("SNsyncfiledir");
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
                } else {  # xdsh -e  or -E
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
                                         # process here on the MN  or I am on a service node
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
                    # split if a pool
                    # if one in the pool is good, send the command to the
                    # daemon
                    my @sn_list = split ',', $snkey;
                    my $goodsn=0;
                    foreach my $sn (@sn_list) {
                      if (grep(/$sn/, @::good_SN)) {
                         $goodsn=1;
                         last;
                      }
                    }
                    # found a good service node 
                    if ($goodsn == 1)
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

=head3 parse_xdcp_cmd 
  Check to see if full path on file(s) input to the command
  If not add currentpath to the file in the argument 
  Check to see if on a servicenode, if so then add the SNsynfiledir
  to the path
=cut

#-------------------------------------------------------
sub parse_xdcp_cmd 
{
   my $req=shift;
   my $args=$req->{arg};   # argument
   my $orgargarraySize = @{$args};  # get the size of the arg array
   my $currpath=$req->{cwd}->[0]; # current path when command was executed
   @ARGV = @{$args};    # get arguments

   my @SaveARGV=@ARGV;  # save the original argument list
   my %options = ();
   Getopt::Long::Configure("posix_default");
   Getopt::Long::Configure("no_gnu_compat");
   Getopt::Long::Configure("bundling");

   if (
       !GetOptions(
                   'f|fanout=i'       => \$options{'fanout'},
                   'F|File=s'         => \$options{'File'},
                   'h|help'           => \$options{'help'},
                   'i|rootimg=s'      => \$options{'rootimg'},
                   'l|user=s'         => \$options{'user'},
                   'n|nodes=s'        => \$options{'nodes'},
                   'o|node-options=s' => \$options{'node-options'},
                   'q|show-config'    => \$options{'show-config'},
                   'p|preserve'       => \$options{'preserve'},
                   'r|c|node-rcp=s'   => \$options{'node-rcp'},
                   's'                => \$options{'rsyncSN'},
                   't|timeout=i'      => \$options{'timeout'},
                   'v|verify'         => \$options{'verify'},
                   'B|bypass'         => \$options{'bypass'},
                   'Q|silent'         => \$options{'silent'},
                   'P|pull'           => \$options{'pull'},
                   'R|recursive'      => \$options{'recursive'},
                   'T|trace'          => \$options{'trace'},
                   'V|version'        => \$options{'version'},
                   'nodestatus|nodestatus' => \$options{'nodestatus'},
                   'sudo|sudo' => \$options{'sudo'},
                   'X:s'              => \$options{'ignore_env'}
       )
     )
   {
       xCAT::DSHCLI->usage_dcp;
       exit 1;
   }
   my $changedfile=0;
   # check to see if -F option and if there is, is the 
   # input file fully defined path
   my $newfile;
   if (defined($options{'File'})) { 
     if ($options{'File'} !~ /^\//) {  # not a full path
       $newfile = xCAT::Utils->full_path($options{'File'},$currpath);
       $changedfile=1;
     } else { # it is a full path
       $newfile =$options{'File'};
     }
     # if we are on a service node then we have to add the SNsyncfiledir path to the file name
     if  (xCAT::Utils->isServiceNode()) {  
         my  $synfiledir = "/var/xcat/syncfiles";    # default
         my @syndir = xCAT::TableUtils->get_site_attribute("SNsyncfiledir");
         if ($syndir[0])
         {
            $synfiledir = $syndir[0];
         }
         $newfile = $synfiledir . $newfile;
         $changedfile=1;
     }
     # now need to go through the original argument list and replace the file 
     # after the -F flag, if a file was changed
     my @newarg;
     my $updatefile=0;
     my $arglength =0;
     if ($changedfile == 1) {
      foreach my $arg (@SaveARGV) {
        if ($updatefile ==1) {  # found the file to change
          push @newarg,$newfile;
          $updatefile =0;
          next;   # skip the old entry
        }
        if ($arg !~ /^-F/) {
          push @newarg,$arg; 
        } else { 
          # if -F there are two format.  -Ffile in one element or -F file
          # in two elements of the array
          $arglength= length ($arg);   
          if ($arglength <=2) {  # this is the -F file format
            push @newarg,$arg;
            $updatefile=1;
          }  else {  # this is the -Ffile format
            my $n="-F";
            $n .=$newfile;
            push @newarg,$n;
            $updatefile =0;
          } 
        }
      }
      #put the new argument list on the request
      @{$req->{arg}}= @newarg;
     
     
     }
   } # end -F option


   # For xdcp ......   file1 file2 command 
   # what is left in the argument are the  files to copy
   # each from and to file needs to be checked if relative or expanded path
   # If not expanded, it needs to have current path added
   $changedfile =0;   # resetting this but there should be only -F or a list
                      # or files for xdcp, not both 
   my @newfiles;
   my $leftoverargsize=@ARGV;
   if (@ARGV > 0) {
    foreach my $file (@ARGV) {
      if ($file !~ /^\//) { # not full path
       $file = xCAT::Utils->full_path($file,$currpath);
       $changedfile=1;
      }
      push @newfiles,$file;      
    }
   }
   # if had to add the path to a file, then need to rebuild the 
   # request->{args} array 
   if ($changedfile == 1) {
     my $offset=$orgargarraySize  - $leftoverargsize ;
     # offset is where we start updating
     foreach my $file (@newfiles) {
        $req->{arg}->[$offset] = $file;
        $offset ++
     }
   }
   return $req;
}

#-------------------------------------------------------

=head3 parse_xdsh_cmd 
  Check to see if full path on file(s) input to the command
  If not add currentpath to the file in the argument 
=cut

#-------------------------------------------------------
sub parse_xdsh_cmd 
{
   my $req=shift;
   my $cb=shift;
   my $sub_req=shift;
   my $args=$req->{arg};   # argument
   my $nodes   = $req->{node};
   my $currpath=$req->{cwd}->[0]; # current path when command was executed
   my $orgargarraySize = @{$args};  # get the size of the arg array
   @ARGV = @{$args};    # get arguments

   my @SaveARGV=@ARGV;  # save the original argument list
   my %options = ();
   Getopt::Long::Configure("posix_default");
   Getopt::Long::Configure("no_gnu_compat");
   Getopt::Long::Configure("bundling");

   if (
        !GetOptions(
            'e|execute'                => \$options{'execute'},
            'f|fanout=i'               => \$options{'fanout'},
            'h|help'                   => \$options{'help'},
            'l|user=s'                 => \$options{'user'},
            'm|monitor'                => \$options{'monitor'},
            'o|node-options=s'         => \$options{'node-options'},
            'q|show-config'            => \$options{'show-config'},
            'r|node-rsh=s'             => \$options{'node-rsh'},
            'i|rootimg=s'              => \$options{'rootimg'},
            's|stream'                 => \$options{'streaming'},
            't|timeout=i'              => \$options{'timeout'},
            'v|verify'                 => \$options{'verify'},
            'z|exit-status'            => \$options{'exit-status'},
            'B|bypass'                 => \$options{'bypass'},
            'c|cleanup'                => \$options{'cleanup'},
            'E|environment=s'          => \$options{'environment'},
            'I|ignore-sig|ignoresig=s' => \$options{'ignore-signal'},
            'K|keysetup'               => \$options{'ssh-setup'},
            'L|no-locale'              => \$options{'no-locale'},
            'Q|silent'                 => \$options{'silent'},
            'S|syntax=s'               => \$options{'syntax'},
            'T|trace'                  => \$options{'trace'},
            'V|version'                => \$options{'version'},

            'devicetype=s'               => \$options{'devicetype'},
            'nodestatus|nodestatus' => \$options{'nodestatus'},
            'sudo|sudo' => \$options{'sudo'},
            'command-name|commandName=s' => \$options{'command-name'},
            'command-description|commandDescription=s' =>
              \$options{'command-description'},
            'X:s' => \$options{'ignore_env'}

       )
     )
   {
       xCAT::DSHCLI->usage_dsh;
       exit 1;
   }
   # elements left in the array after the parse
   # these are the script and it's arguments
   my $leftoverargsize=@ARGV;
   my $changedfile=0;
   # check to see if -e option
   # change  file to fully defined path
   my @executecmd = @ARGV;
   if (defined($options{'execute'})) { 
     # this can be the script name + parms
     if ($executecmd[0] !~ /^\//) {  # not a full path in the script name
       $executecmd[0] = xCAT::Utils->full_path($executecmd[0],$currpath);
       $changedfile=1;
     }
     # if had to add the path to the script, then need to rebuild the 
     # request->{args} array 
     if ($changedfile == 1) {
       my $offset=$orgargarraySize  - $leftoverargsize ;
       # offset is where we start updating
       foreach my $file (@executecmd) {
        $req->{arg}->[$offset] = $file;
        $offset ++
       }
     }
     
     
   } # end -e option
   
   # if -k options and there are zones and service nodes, we cannot allow
   #  servicenodes and compute nodes in the noderange.  The /etc/xcat/sshkeys directory must be sync'd 
   # to the service nodes first.  So they must run xdsh -K to the service nodes and then to the compute
   #  nodes. 
   
   if (defined($options{'ssh-setup'})) {
     if (xCAT::Zone->usingzones) { 
        # check to see if service nodes and compute nodes in node range
        my @SN;
        my @CN;
        xCAT::ServiceNodeUtils->getSNandCPnodes(\@$nodes, \@SN, \@CN);
        if ((@SN > 0) && (@CN >0 )) { # there are both SN and CN
           my $rsp;
           $rsp->{data}->[0] =
           "xdsh -K was run with a noderange containing both service nodes and compute nodes. This is not valid if using zones.  You must run xdsh -K to the service nodes first to setup the service node to be able to run xdsh -K to the compute nodes.  \n";
            xCAT::MsgUtils->message("E", $rsp, $cb);
            exit 1;
        }
        # if servicenodes for the node range this will  force the update of
        # the servicenode with /etc/xcat/sshkeys dir first
        # if servicenodes and xdsh -K and using zones and we are on the Management Node
        #  then we need to sync
        # /etc/xcat/sshkeys to the service nodes
        # get list of all servicenodes
        if (xCAT::Utils->isMN()) {  # on the MN
            my @snlist;
            foreach my $sn (xCAT::ServiceNodeUtils->getSNList()) {
               if (xCAT::NetworkUtils->thishostisnot($sn)) {  # if it is not me, the MN
                 push @snlist, $sn;
               }
            }
            if (@snlist) {   
                &syncSNZoneKeys($req, $cb, $sub_req, \@snlist);
            }
         }
 
      }  # not using zones
   }  # not -k flag

   return $req;
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
    $::RUNCMD_RC = 0;
    my $cmd = $req->{command}->[0];

    # if xdcp -F command (input $syncsnfile) and the original synclist need
    # to be rsync to the $synfiledir  directory on the service nodes first 
    if ($::syncsnfile)
    {
        if (!-f $::syncsnfile)
        {    # syncfile does not exist,  quit
            my $rsp = {};
            $rsp->{error}->[0] = "File:$::syncsnfile does not exist.";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            return (1);    # process no service nodes
        }

        # xdcp rsync each of the files contained in the -F syncfile and the
        # original synclist input on the -F flag to
        # the service node first to the site.SNsyncfiledir directory
        #change noderange to the service nodes
        # sync  and check for error

        my @sn = ();
        #build the array of all service nodes 
        foreach my $node (@snodes)
        {

            # handle multiple servicenodes for one node
            my @sn_list = split ',', $node;
            foreach my $snode (@sn_list) {
             push @sn, $snode;
            }
        }

        @::good_SN = @sn;  # initialize all good

        # run the command to the servicenodes
        # xdcp <sn> -s -F <syncfile>
        # don't use runxcmd, because can go straight to process_request,
        # these are all service nodes. Also servicenode is taken from
        # the noderes table and may not be the same name as in the nodelist
        # table, for example may be an ip address.
        # here on the MN
        my $addreq;
        $addreq->{'_xcatdest'}  = $::mnname;
        $addreq->{node}         = \@sn;
        $addreq->{noderange}    = \@sn;
        # check input request for --nodestatus
        my $args=$req->{arg};   # argument
        if (grep(/^--nodestatus$/, @$args)) {
          push (@{$addreq->{arg}},"--nodestatus"); # return nodestatus
        }
         push (@{$addreq->{arg}},"-v"); 
         push (@{$addreq->{arg}},"-s"); 
         push (@{$addreq->{arg}},"-F"); 
         push (@{$addreq->{arg}},$::syncsnfile); 
        $addreq->{command}->[0] = $cmd;
        $addreq->{cwd}->[0]     = $req->{cwd}->[0];
        $addreq->{env}          = $req->{env};
        &process_request($addreq, $callback, $sub_req);

        if ($::FAILED_NODES == 0)
        {
            @::good_SN = @sn;   # all servicenodes were sucessful
        }
        else
        {
          @::bad_SN = @::DCP_NODES_FAILED; 
          # remove all failing nodes from the good list
          my @tmpgoodnodes;
          foreach my $gnode (@::good_SN) {
            if (!grep(/$gnode/,@::bad_SN ))  # if not a bad node
            {   
               push @tmpgoodnodes, $gnode;
            }
          }
          @::good_SN = @tmpgoodnodes;
        }

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
     
        my @sn = ();
        # build list of servicenodes
        foreach my $node (@snodes)
        {
            # handle multiple servicenodes for one node
            my @sn_list = split ',', $node;
            foreach my $snode (@sn_list) {
             push @sn, $snode;
            }
        }
        @::good_SN = @sn;  # initialize all good

        # run the command to all servicenodes
        # to make the directory under the temporary
        # SNsyncfiledir to hold the files that will be
        # sent to the service nodes
        # xdsh <sn> mkdir -p <SNsyncfiledir>/$::SNpath
        my $addreq;
        $addreq->{'_xcatdest'}  = $::mnname;
        $addreq->{node}         = \@sn;
        $addreq->{noderange}    = \@sn;
        $addreq->{arg}->[0]     = "-v";
        $addreq->{arg}->[1]     = "mkdir ";
        $addreq->{arg}->[2]     = "-p ";
        $addreq->{arg}->[3]     = $SNdir;
        $addreq->{command}->[0] = 'xdsh';
        $addreq->{cwd}->[0]     = $req->{cwd}->[0];
        $addreq->{env}          = $req->{env};
        &process_request($addreq, $callback, $sub_req);
        if ($::FAILED_NODES == 0)
        {
                @::good_SN = @sn;
        }
        else
        {
          @::bad_SN = @::DCP_NODES_FAILED; 
          # remove all failing nodes from the good list
          my @tmpgoodnodes;
          foreach my $gnode (@::good_SN) {
            if (!grep(/$gnode/,@::bad_SN ))  # if not a bad node
            {   
               push @tmpgoodnodes, $gnode;
            }
          }
          @::good_SN = @tmpgoodnodes;
        }

        # now xdcp file to the service node to the new
        # tmp path

        # for all the service nodes that are still good
        my @sn = @::good_SN;
        
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
                 @::good_SN = @sn ;
        }
        else
        {
          @::bad_SN = @::DCP_NODES_FAILED; 
          # remove all failing nodes from the good list
          my @tmpgoodnodes;
          foreach my $gnode (@::good_SN) {
            if (!grep(/$gnode/,@::bad_SN ))  # if not a bad node
            {   
               push @tmpgoodnodes, $gnode;
            }
          }
          @::good_SN = @tmpgoodnodes;
        }

    }

    # report bad service nodes
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
  Build the xdsh command to sync the -e file or the -E file 
  to the servicenodes.
  The executable (-e) or the environment file (-E) 
  must be copied into /var/xcat/syncfiles (SNsyncfiledir attribute), and then
  the command modified so that the xdsh running on the SN will use the file
  from /var/xcat/syncfiles (default) for the compute nodes.
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

    # if xdsh -e <executable> command or xdsh -E <environment file>
    #   service nodes first need
    #   to be rsync with the executable or environment file to the $synfiledir
    if (($::dshexecute) or ($::dshenvfile)) 
    {
        if (defined($::dshexecute) && (!-f $::dshexecute))
        {    # -e file  does not exist,  quit
            my $rsp = {};
            $rsp->{error}->[0] = "File:$::dshexecute does not exist.";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            return (1);    # process no service nodes
        }
        if (defined($::dshenvfile) && (!-f $::dshenvfile))
        {    # -E file  does not exist,  quit
            my $rsp = {};
            $rsp->{error}->[0] = "File:$::dshenvfile does not exist.";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            return (1);    # process no service nodes
        }

        # xdcp (-F) the executable from the xdsh -e and/or 
        # xdcp (-F)  the environment file from the xdsh -E
        # to the service node 
        # change noderange to the service nodes
        # sync to each SN and check for error
        # if error do not add to good_SN array, add to bad_SN
        
        # /.../excutable -> $syncdir/..../executable
        # /.../envfile ->  $syncdir/...../envfile 
        # build a tmp syncfile with
        # $::dshexecute -> $synfiledir . $::dshexecute
        # $::dshenvfile -> $synfiledir . $::dshenvfile
        my $tmpsyncfile = POSIX::tmpnam . ".dsh";
        # if -E option
        my $envfile;
        my $execfile;
        open(TMPFILE, "> $tmpsyncfile")
                  or die "can not open file $tmpsyncfile";
        if (defined($::dshenvfile)) {
           $envfile=$synfiledir . $::dshenvfile;
           print TMPFILE "$::dshenvfile -> $envfile\n";
        } 
        if (defined($::dshexecute)) {
           $execfile=$synfiledir . $::dshexecute;
           print TMPFILE "$::dshexecute -> $execfile\n";
        } 
        close TMPFILE;
        chmod 0755, $tmpsyncfile;

        # build array of all service nodes , this is to cover pools where
        # an entry might actually be a comma separated list
        my @sn = ();
        foreach my $node (@snodes)
        {
            # handle multiple servicenodes for one node
            my @sn_list = split ',', $node;
            foreach my $snode (@sn_list) {
             push @sn, $snode;
            }

        }
        @::good_SN = @sn;  # initialize all good
        # sync the file to the SN /var/xcat/syncfiles directory
        # (site.SNsyncfiledir) 
        # xdcp <sn> -s -F <tmpsyncfile>
  
         
        # don't use runxcmd, because can go straight to process_request,
        # these are all service nodes. Also servicenode is taken from
        # the noderes table and may not be the same name as in the nodelist
        # table, for example may be an ip address.
        # here on the MN
        my $addreq;
        $addreq->{'_xcatdest'}  = $::mnname;
        $addreq->{node}         = \@sn;
        $addreq->{noderange}    = \@sn;
        $addreq->{arg}->[0]     = "-v";
        $addreq->{arg}->[1]     = "-s";
        $addreq->{arg}->[2]     = "-F";
        $addreq->{arg}->[3]     = $tmpsyncfile;
        $addreq->{command}->[0] = "xdcp";
        $addreq->{cwd}->[0]     = $req->{cwd}->[0];
        $addreq->{env}          = $req->{env};
        &process_request($addreq, $callback, $sub_req);

        if ($::FAILED_NODES == 0)
        {
          @::good_SN = @sn;   # all servicenodes were sucessful 
        }
        else
        {
          @::bad_SN = @::DCP_NODES_FAILED;
          # remove all failing nodes from the good list
          my @tmpgoodnodes;
          foreach my $gnode (@::good_SN) {
            if (!grep(/$gnode/,@::bad_SN ))  # if not a bad node
            {
               push @tmpgoodnodes, $gnode;
            }
          }
          @::good_SN = @tmpgoodnodes;
        }
        # remove the tmp syncfile
        `/bin/rm $tmpsyncfile`;

    }    # end  xdsh -e or -E

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
    # change the command to use the -F syncfiledir path to the synclist 
    # because that is where the file was put on the SN
    #
    my $newSNreq = dclone($req);
    my $newsyncfile = $synfiledir;
    $newsyncfile .=$::syncsnfile;
    if ($::syncsnfile)    # -F option
    {
        my $args = $newSNreq->{arg};

        my $i = 0;
        foreach my $argument (@$args)
        {

            # find the -F and change the name of the
            # file in the next array entry to the file that  
            # is in the site.SNsyncfiledir
            # 	directory on the service node
            if ($argument eq "-F")
            {
                $i++;
                $newSNreq->{arg}->[$i] = $newsyncfile;
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
            # have to change each file path and add the SNsynfiledir
            # except the last entry which is the destination on the computenode
            # skip flags 
            my $args = $newSNreq->{arg};
            my $arraysize = @$args;
            my $i = 0;
            foreach my $sarg (@$args) {
              if ($arraysize > 1) { 
                if ($sarg =~ /^-/) {  # just a flag, skip
                  $arraysize--; 
                  $i++;
                } else { 
                  my $tmpfile =$synfiledir ;
                  $tmpfile .=$newSNreq->{arg}->[$i] ;
                  $newSNreq->{arg}->[$i] = $tmpfile;
                  $arraysize--; 
                  $i++;
                }
              } else {
                 last;
              }    
            }
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

=head3 syncSNZoneKeys
  Build the xdcp command to send the zone keys to the service nodes 
  Return an array of servicenodes that do not have errors 
  Returns error code:
  if  = 0,  good return continue to process the
	  nodes.
  if  = 1,  global error need to quit

=cut

#-------------------------------------------------------
sub syncSNZoneKeys
{

    my $req        = shift;
    my $callback   = shift;
    my $sub_req    = shift;
    my $sn         = shift;
    my @snodes     = @$sn;
    $::RUNCMD_RC = 0;
    my $file="/tmp/xcatzonesynclist";
    # Run xdcp <servicenodes> -F /tmp/xcatzonesynclist 
    # can leave it , never changes and is built each time
    my $content= "\"/etc/xcat/sshkeys/* -> /etc/xcat/sshkeys/\"";
    `echo $content  > $file`;

    # xdcp rsync the file 

    my @sn = ();
    #build the array of all service nodes 
    foreach my $node (@snodes)
    {

            # handle multiple servicenodes for one node
            my @sn_list = split ',', $node;
            foreach my $snode (@sn_list) {
             push @sn, $snode;
            }
    }

    @::good_SN = @sn;  # initialize all good

    # run the command to the servicenodes
    # xdcp <sn>  -F <syncfile>
    my $addreq;
    $addreq->{'_xcatdest'}  = $::mnname;
    $addreq->{node}         = \@sn;
    $addreq->{noderange}    = \@sn;
    # check input request for --nodestatus
    my $args=$req->{arg};   # argument
    if (grep(/^--nodestatus$/, @$args)) {
       push (@{$addreq->{arg}},"--nodestatus"); # return nodestatus
    }
    push (@{$addreq->{arg}},"-v"); 
    push (@{$addreq->{arg}},"-F"); 
    push (@{$addreq->{arg}},$file); 
    $addreq->{command}->[0] = "xdcp";  # input command is xdsh, but we need to run xdcp -F
    $addreq->{cwd}->[0]     = $req->{cwd}->[0];
    $addreq->{env}          = $req->{env};
    &process_request($addreq, $callback, $sub_req);

    if ($::FAILED_NODES == 0)
    {
            @::good_SN = @sn;   # all servicenodes were sucessful
    }
    else
    {
          @::bad_SN = @::DCP_NODES_FAILED; 
          # remove all failing nodes from the good list
          my @tmpgoodnodes;
          foreach my $gnode (@::good_SN) {
            if (!grep(/$gnode/,@::bad_SN ))  # if not a bad node
            {   
               push @tmpgoodnodes, $gnode;
            }
          }
          @::good_SN = @tmpgoodnodes;
    }

    # report bad service nodes
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
    # if DSH_FROM_USERID does not exist, set for internal calls
    # if request->{username} exists,  set DSH_FROM_USERID to it
    # override input,  this is what was authenticated
    if (!($ENV{'DSH_FROM_USERID'})) {
      if (($request->{username}) && defined($request->{username}->[0])) {
         $ENV{DSH_FROM_USERID} = $request->{username}->[0];
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
            my $rsp = {};
            $rsp->{error}->[0] =
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

    
    # parse dsh input, will return
    $::FAILED_NODES = 0;  # this is the count
    # @::DSH_NODES_FAILED array of failing nodes. 
    
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
            if ($i >= $arraylen)
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


    # parse dcp input , run the command and return
    $::FAILED_NODES = 0;  # number of failing nodes
    # @::DCP_NODES_FAILED array of failing nodes 
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

    # set return code
    $rsp = {};
    $rsp->{errorcode} = $::FAILED_NODES;
    $callback->($rsp);
    return;
}

