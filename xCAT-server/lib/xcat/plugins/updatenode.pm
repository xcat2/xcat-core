#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::updatenode;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use xCAT::Table;
use xCAT::Schema;
use Data::Dumper;
use xCAT::Utils;
use xCAT::SvrUtils;
use xCAT::Usage;
use xCAT::NetworkUtils;
use xCAT::InstUtils;
use Getopt::Long;
use xCAT::GlobalDef;
use Sys::Hostname;
use File::Basename;
use xCAT::GlobalDef;
use xCAT_monitoring::monitorctrl;
use Socket;
#use strict;
my $CALLBACK;
my $RERUNPS4SECURITY;
1;

#-------------------------------------------------------------------------------

=head1  xCAT_plugin:updatenode
=head2    Package Description
  xCAT plug-in module. It handles the updatenode command.
=cut

#------------------------------------------------------------------------------

#--------------------------------------------------------------------------------

=head3   handled_commands
      It returns a list of commands handled by this plugin.
    Arguments:
        none
    Returns:
        a list of commands.
=cut

#------------------------------------------------------------------------------
sub handled_commands
{
    return {
            updatenode     => "updatenode",
            updatenodestat => "updatenode",
            updatenodeappstat => "updatenode"
            };
}

#-------------------------------------------------------

=head3  preprocess_request
  Check and setup for hierarchy 
=cut

#-------------------------------------------------------
sub preprocess_request
{
    my $request  = shift;
    my $callback = shift;
    $::subreq = shift;

    # needed for runcmd output
    $::CALLBACK = $callback;

    my $command = $request->{command}->[0];
    if ($request->{_xcatpreprocessed}->[0] == 1) { return [$request]; }

    my @requests = ();

    if ($command eq "updatenode")
    {
        return &preprocess_updatenode($request, $callback, $::subreq);
    }
    elsif ($command eq "updatenodestat")
    {
        return [$request];
    }
    elsif ($command eq "updatenodeappstat")
    {
        return [$request];
    }
    else
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Unsupported command: $command.";
        $callback->($rsp);
        return \@requests;
    }
}

#-----------------------------------------------------------------------------

=head3   process_request
      It processes the updatenode command.
    Arguments:
      request -- a hash table which contains the command name and the arguments.
      callback -- a callback pointer to return the response to.
    Returns:
        0 - for success. The output is returned through the callback pointer.
        1 -  for error. The error messages are returns through the 
							callback pointer.
=cut

#------------------------------------------------------------------------------
sub process_request
{
    my $request  = shift;
    my $callback = shift;
    $::subreq = shift;

    # needed for runcmd output
    $::CALLBACK = $callback;

    my $command       = $request->{command}->[0];
    my $localhostname = hostname();

    if ($command eq "updatenode")
    {
        return updatenode($request, $callback, $::subreq);
    }
    elsif ($command eq "updatenodestat")
    {
        return updatenodestat($request, $callback);
    }
    elsif ($command eq "updatenodeappstat")
    {
        return updatenodeappstat($request, $callback);
    }
    else
    {
        my $rsp = {};
        $rsp->{data}->[0] = "$localhostname: Unsupported command: $command.";
        $callback->($rsp);
        return 1;
    }
    return 0;
}

#-----------------------------------------------------------------------------

=head3   preprocess_updatenode
        This function checks for the syntax of the updatenode command
     		and distributes the command to the right server. 
    Arguments:
      request - the request. 
      callback - the pointer to the callback function.
	  subreq - the sub request
    Returns:
      A pointer to an array of requests.
=cut

#------------------------------------------------------------------------------
sub preprocess_updatenode
{
    my $request  = shift;
    my $callback = shift;
    my $subreq   = shift;
    my $args     = $request->{arg};
    my @requests = ();

    my $installdir = xCAT::Utils->getInstallDir();

    # subroutine to display the usage
    sub updatenode_usage
    {
        my $cb  = shift;
        my $rsp = {};
        my $usage_string = xCAT::Usage->getUsage("updatenode");
        push @{$rsp->{data}},$usage_string;

        $cb->($rsp);
    }

    @ARGV = ();
    if ($args)
    {
        @ARGV = @{$args};
    }

    # parse the options
    Getopt::Long::Configure("bundling");
    Getopt::Long::Configure("no_pass_through");
    if (
        !GetOptions(
					'A|updateallsw'    => \$::ALLSW,
                    'c|cmdlineonly'    => \$::CMDLINE,
					'd=s'              => \$::ALTSRC,
                    'h|help'           => \$::HELP,
                    'v|version'        => \$::VERSION,
                    'V|verbose'        => \$::VERBOSE,
                    'F|sync'           => \$::FILESYNC,
                    'f|snsync'         => \$::SNFILESYNC,
                    'S|sw'             => \$::SWMAINTENANCE,
                    's|sn'             => \$::SETSERVER,
                    'P|scripts:s'      => \$::RERUNPS,
                    'k|security'       => \$::SECURITY,
                    'o|os:s'           => \$::OS,
                    'user=s'           => \$::USER,
                    'devicetype=s'     => \$::DEVICETYPE,
        )
      )
    {
        &updatenode_usage($callback);
        return \@requests;
    }

    # display the usage if -h or --help is specified
    if ($::HELP)
    {
        &updatenode_usage($callback);
        return \@requests;
    }

    # display the version statement if -v or --verison is specified
    if ($::VERSION)
    {
        my $rsp = {};
        $rsp->{data}->[0] = xCAT::Utils->Version();
        $callback->($rsp);
        return \@requests;
    }

    # -c must work with -S for AIX node
    if ($::CMDLINE && !$::SWMAINTENANCE) {
        &updatenode_usage($callback);
        return \@requests;
    }
    
    # -s must work with -P or -S or --security
    if ($::SETSERVER && !($::SWMAINTENANCE || $::RERUNPS || $::SECURITY)) {
        &updatenode_usage($callback);
        return \@requests;
    }
    # -f or -F not both
    if (($::FILESYNC) && ($::SNFILESYNC)) {
        &updatenode_usage($callback);
        return \@requests;
    }


    # --user and --devicetype must work with --security
    if (($::USER || $::DEVICETYPE) && !($::SECURITY && $::USER && $::DEVICETYPE)) {
        &updatenode_usage($callback);
        return \@requests;
    }

    # --security cannot work with -S -P -F
    if ($::SECURITY && ($::SWMAINTENANCE || $::RERUNPS || defined($::RERUNPS))) {
        &updatenode_usage($callback);
        return \@requests;
    }

    # the -P flag is omitted when only postscritps are specified,
    # so if there are parameters without any flags, it may mean
    # to re-run the postscripts.
    if (@ARGV)
    {

        # we have one or more operands on the cmd line
        if ($#ARGV == 0
            && !($::FILESYNC || $::SNFILESYNC || $::SWMAINTENANCE || defined($::RERUNPS) || $::SECURITY))
        {

            # there is only one operand
            # if it doesn't contain an = sign then it must be postscripts
            if (!($ARGV[0] =~ /=/))
            {
                $::RERUNPS = $ARGV[0];
                $ARGV[0] = "";
            }

        }
    }
    else
    {
        # if not syncing Service Node
        if (!($::SNFILESYNC)) {
          # no flags and no operands, set defaults
          if (!($::FILESYNC  || $::SWMAINTENANCE || defined($::RERUNPS) ||$::SECURITY))
          {
            $::FILESYNC      = 1;
            $::SWMAINTENANCE = 1;
            $::RERUNPS       = "";
          }
        }
    }

    if ($::SECURITY && !($::USER || $::DEVICETYPE)) {
        $::RERUNPS = "allkeys44444444security";
    }

    my $nodes = $request->{node};
    if (!$nodes)
    {
        &updatenode_usage($callback);
        return \@requests;
    }

	#
    # process @ARGV
    #

    # the first arg should be a noderange - the other should be attr=val
    #  - put attr=val operands in %attrvals hash

    my %attrvals;
    if ($::SWMAINTENANCE) {
        while (my $a = shift(@ARGV))
        {
            if ($a =~ /=/)
            {
    
                # if it has an "=" sign its an attr=val - we hope
                my ($attr, $value) = $a =~ /^\s*(\S+?)\s*=\s*(\S*.*)$/;
    
                if (!defined($attr) || !defined($value))
                {
                    my $rsp;
                    $rsp->{data}->[0] = "Incorrect \'attr=val\' pair - $a\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback,3);
                    return ;
                }
    
                # put attr=val in hash
                $attrvals{$attr} = $value;
            }
        }
    }

    my @nodes = @$nodes;
    my $postscripts;

	# Handle updating operating system
	if (defined($::OS)) {
    	my $reqcopy = {%$request};
        $reqcopy->{os}->[0] = "yes";
        push @requests, $reqcopy;
        
		return \@requests;
    }
    
    # handle the validity of postscripts 
    if (defined($::RERUNPS))
    {
        if ($::RERUNPS eq "")
        {
            $postscripts = "";
        }
        else
        {
            $postscripts = $::RERUNPS;
            my @posts = ();
            if ($postscripts eq "allkeys44444444security") {
                @posts = ("remoteshell", "aixremoteshell", "servicenode");
            } else {
                @posts = split(',', $postscripts);
            }

            foreach (@posts)
            {
                my @aa=split(' ', $_);
                if (!-e "$installdir/postscripts/$aa[0]")
                {
                    my $rsp = {};
                    $rsp->{data}->[0] =
                      "The postcript $installdir/postscripts/$aa[0] does not exist.";
                    $callback->($rsp);
                    return \@requests;
                }
            }
        }
    }

    # If -F or -f  option specified, sync files to the noderange or their 
    # service nodes.
    # Note: This action only happens on MN, since xdcp, xdsh handles the
    #	hierarchical scenario inside
    if ($::FILESYNC)
    {
        my $reqcopy = {%$request};
        $reqcopy->{FileSyncing}->[0] = "yes";
        push @requests, $reqcopy;
    }
    if ($::SNFILESYNC)   # either sync service node
    {
        my $reqcopy = {%$request};
        $reqcopy->{SNFileSyncing}->[0] = "yes";
        push @requests, $reqcopy;
    }

    # when specified -S or -P or --security
    # find service nodes for requested nodes
    # build an individual request for each service node
    unless (defined($::SWMAINTENANCE) || defined($::RERUNPS) || $::SECURITY)
    {
        return \@requests;
    }


    my %insttype_node = ();
    # get the nodes installation type
    xCAT::SvrUtils->getNodesetStates($nodes, \%insttype_node);

    
    # figure out the diskless nodes list and non-diskless nodes
    my @dsklsnodes;
    my @notdsklsnodes;
    foreach my $type (keys %insttype_node) {
        if ($type eq "netboot" || $type eq "statelite" || $type eq "diskless") {
            push @dsklsnodes, @{$insttype_node{$type}};
        } else {
            push @notdsklsnodes, @{$insttype_node{$type}};
        }
    }

    if (defined($::SWMAINTENANCE) && scalar(@dsklsnodes) > 0) {
        my $rsp;
        my $outdsklsnodes = join (',', @dsklsnodes);
        push @{$rsp->{data}}, "The updatenode command does not support software maintenance on diskless nodes. The following diskless nodes will be skipped:\n$outdsklsnodes";
        xCAT::MsgUtils->message("E", $rsp, $callback);
    }

    #  - need to consider the mixed cluster case
    #		- can't depend on the os of the MN - need to split out the AIX
    #		nodes from the node list which are not diskless 
    my ($rc, $AIXnodes, $Linuxnodes) = xCAT::InstUtils->getOSnodes(\@notdsklsnodes);
    my @aixnodes = @$AIXnodes;
    
    # for AIX nodes we need to copy software to SNs first - if needed
    my ($imagedef, $updateinfo);
    if (defined($::SWMAINTENANCE) && scalar(@aixnodes))
    {
        ($rc, $imagedef, $updateinfo) =
          &doAIXcopy($callback, \%attrvals, $AIXnodes, $subreq);
        if ($rc != 0)
        {
            # Do nothing when doAIXcopy failed
            return undef;
        }
    }

    my $sn = xCAT::Utils->get_ServiceNode(\@nodes, "xcat", "MN");
    if ($::ERROR_RC)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get list of xCAT service nodes.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return \@requests;

        # return undef; ???
    }


    # for security update, we need to handle the service node first
    my @good_sns = ();
    my @MNip   = xCAT::Utils->determinehostname;
    my @sns = ();
    foreach my $s (keys %$sn) {
	my @tmp_a=split(',',$s);
	foreach my $s1 (@tmp_a) {
	    if (!grep (/^$s1$/, @MNip)) {
		push @sns, $s1;
	    }
	}
    }
    
    if (scalar(@sns) && $::SECURITY) {
       # cannot use updatenode  -k to compute nodes, whose master is a service node
       my $rsp;
       push @{$rsp->{data}}, "updatenode -k is not supported to compute nodes in a hierarchical cluster.";
       push @{$rsp->{data}}, " To update ssh keys on compute nodes , use xdsh -K";
       xCAT::MsgUtils->message("E", $rsp, $callback,1);
       return 1;
    }
    
    # build each request for each service node
    foreach my $snkey (keys %$sn)
    {

	my @tmp_a=split(',',$snkey);
	foreach my $s1 (@tmp_a) {
	    if ($::SECURITY
		&& !(grep /^$s1$/, @good_sns)
		&& !(grep /^$s1$/, @MNip)) {
		my $rsp;
		push @{$rsp->{data}}, "The security update for service node $snkey encountered error, update security for following nodes will be skipped: @{$sn->{$snkey}}";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		next;
	    }

	    # remove the service node which have been handled before
	    if ($::SECURITY && (grep /^$s1$/, @MNip)) {
		delete @{$sn->{$snkey}}[@sns];
		if (scalar(@{$sn->{$snkey}}) == 0) {
		    next;
		}
	    }
	}

        
        my $reqcopy = {%$request};
        $reqcopy->{node}                   = $sn->{$snkey};
        $reqcopy->{'_xcatdest'}            = $snkey;
        $reqcopy->{_xcatpreprocessed}->[0] = 1;

        if (defined($::SWMAINTENANCE))
        {
            # skip the diskless nodes
            my @validnode = ();
            foreach my $node (@{$sn->{$snkey}}) {
                if (! grep /^$node$/, @dsklsnodes) {
                    push @validnode, $node;
                }
            }
            if (scalar (@validnode) > 0) {
                $reqcopy->{nondsklsnode} = \@validnode;
                $reqcopy->{swmaintenance}->[0] = "yes";
    
                # send along the update info and osimage defs
                if ($imagedef)
                {
                    xCAT::InstUtils->taghash($imagedef);
                    $reqcopy->{imagedef} = [$imagedef];
                }
                if ($updateinfo)
                {
                    xCAT::InstUtils->taghash($updateinfo);
                    $reqcopy->{updateinfo} = [$updateinfo];
                }
            }
        }

        if (defined($::RERUNPS))
        {
            $reqcopy->{rerunps}->[0] = "yes";
            $reqcopy->{postscripts} = [$postscripts];
            if (defined($::SECURITY)) {
                $reqcopy->{rerunps4security}->[0] = "yes";
            }
        }

        if (defined($::SECURITY)) {
            $reqcopy->{security}->[0] = "yes";
            if ($::USER) {
                $reqcopy->{user}->[0] = $::USER;
            }
            if ($::DEVICETYPE) {
                $reqcopy->{devicetype}->[0] = $::DEVICETYPE;
            }
        }
        
        #
        # Handle updating OS
        #
		if (defined($::OS)) {
			$reqcopy->{os}->[0] = "yes";
		}

        push @requests, $reqcopy;

    }
    return \@requests;
}


#--------------------------------------------------------------------------------

=head3   updatenode_cb

    A callback function which is used to handle the output of updatenode function
    when run updatenode --secruity for service node inside 

=cut

#-----------------------------------------------------------------------------
sub updatenode_cb
{
    my $resp = shift;

    # call the original callback function
    $::CALLBACK->($resp);

    foreach my $line (@{$resp->{data}}) {
        my $node;
        my $msg;
        if ($line =~ /(.*):(.*)/) {
            $node = $1;
            $msg = $2;
        }
        if ($msg =~ /Redeliver certificates has completed/) {
            push @{$::NODEOUT->{$node}}, "ps ok";
        } elsif ($msg =~ /Setup ssh keys has completed/) {
            push @{$::NODEOUT->{$node}}, "ssh ok";
        }
    }
}


#--------------------------------------------------------------------------------

=head3   updatenode
        This function implements the updatenode command. 
    Arguments:
      request - the request.        
      callback - the pointer to the callback function.
	  subreq - the sub request
    Returns:
        0 - for success. The output is returned through the callback pointer.
        1 - for error. The error messages are returned through the 
				callback pointer.
=cut

#-----------------------------------------------------------------------------
sub updatenode
{
    my $request  = shift;
    my $callback = shift;
    my $subreq   = shift;

    #print Dumper($request);
    my $nodes         = $request->{node};
    my $nondsklsnodes = $request->{nondsklsnode};
    my $localhostname = hostname();

    # in a mixed cluster we could potentially have both AIX and Linux
    #	nodes provided on the command line ????
    my ($rc, $AIXnodes, $Linuxnodes) = xCAT::InstUtils->getOSnodes($nodes);

    my $args = $request->{arg};
    @ARGV = ();
    if ($args)
    {
        @ARGV = @{$args};
    }

    # Lookup Install dir location at this Mangment Node.
    # XXX: Suppose that compute nodes has the same Install dir location.
    my $installdir = xCAT::Utils->getInstallDir();

    #if the postscripts directory exists then make sure it is 
    # world readable and executable by root 
    my $postscripts = "$installdir/postscripts";
    if (-e $postscripts) {
      my $cmd="chmod -R u+x,a+r $postscripts";
      xCAT::Utils->runcmd($cmd, 0);
      my $rsp = {};
      if ($::RUNCMD_RC != 0)
      {
         $rsp->{data}->[0] = "$cmd failed.\n";
         xCAT::MsgUtils->message("E", $rsp, $callback);

       }
    }


    # convert the hashes back to the way they were passed in
    my $flatreq = xCAT::InstUtils->restore_request($request, $callback);
    my $imgdefs;
    my $updates;
    if ($flatreq->{imagedef})
    {
        $imgdefs = $flatreq->{imagedef};
    }
    if ($flatreq->{updateinfo})
    {
        $updates = $flatreq->{updateinfo};
    }

    # get the NIM primary server name
    my $nimprime = xCAT::InstUtils->getnimprime();
    chomp $nimprime;

    # parse the options 
    Getopt::Long::Configure("bundling");
    Getopt::Long::Configure("no_pass_through");
    if (
        !GetOptions(
					'A|updateallsw'    => \$::ALLSW,
                    'c|cmdlineonly'    => \$::CMDLINE,
					'd=s'              => \$::ALTSRC,
                    'h|help'           => \$::HELP,
                    'v|version'        => \$::VERSION,
                    'V|verbose'        => \$::VERBOSE,
                    'F|sync'           => \$::FILESYNC,
                    'f|snsync'         => \$::SNFILESYNC,
                    'S|sw'             => \$::SWMAINTENANCE,
                    's|sn'             => \$::SETSERVER,
                    'P|scripts:s'      => \$::RERUNPS,
                    'k|security'       => \$::SECURITY,
                    'o|os:s'      	   => \$::OS,
                    'user=s'           => \$::USER,
                    'devicetype=s'     => \$::DEVICETYPE,
        )
      )
    {
    }

    #
    # process @ARGV
    #
	#  - put attr=val operands in %::attrres hash
    while (my $a = shift(@ARGV))
    {
        if ($a =~ /=/)
        {

            # if it has an "=" sign its an attr=val - we hope
            my ($attr, $value) = $a =~ /^\s*(\S+?)\s*=\s*(\S*.*)$/;

            if (!defined($attr) || !defined($value))
            {
                my $rsp;
                $rsp->{data}->[0] = "Incorrect \'attr=val\' pair - $a\n";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                return 3;
            }
			# put attr=val in hash
            $::attrres{$attr} = $value;
        }
    }

    #
    #  handle file synchronization
    #

    if (($request->{FileSyncing} && $request->{FileSyncing}->[0] eq "yes")
      || (($request->{SNFileSyncing} && $request->{SNFileSyncing}->[0] eq "yes")))
    {
        my %syncfile_node      = ();
        my %syncfile_rootimage = ();
        my $node_syncfile      = xCAT::SvrUtils->getsynclistfile($nodes);
        foreach my $node (@$nodes)
        {
            my $synclist = $$node_syncfile{$node};

            if ($synclist)
            {
                push @{$syncfile_node{$synclist}}, $node;
            }
         }

         if (%syncfile_node) { # there are files to sync defined
          # Check the existence of the synclist file
          foreach my $synclist (keys %syncfile_node)
          {
            if (!(-r $synclist))
            {
                my $rsp = {};
                $rsp->{data}->[0] =
                  "The Synclist file $synclist which was specified for the nodes does NOT existed.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
          }
          #Sync files to the target nodes
          foreach my $synclist (keys %syncfile_node)
          {
            if ($::VERBOSE)
            {
                my $rsp = {};
                if ($request->{FileSyncing}->[0] eq "yes") { # sync nodes
                  $rsp->{data}->[0] =
                   "  $localhostname: Internal call command: xdcp -F $synclist";
                } else { # sync SN
                  $rsp->{data}->[0] =
                   "  $localhostname: Internal call command: xdcp -s -F $synclist";
                }
                $callback->($rsp);
            }
            my $args;
            my $env;
            if ($request->{FileSyncing}->[0] eq "yes") { # sync nodes
              $args = ["-F", "$synclist"];
              $env = ["DSH_RSYNC_FILE=$synclist"];
            } else { # sync SN only
              $args = ["-s", "-F", "$synclist"];
              $env = ["DSH_RSYNC_FILE=$synclist","RSYNCSNONLY=1"];
            }
            $subreq->(
                      {
                       command => ['xdcp'],
                       node    => $syncfile_node{$synclist},
                       arg     => $args,
                       env     => $env
                      },
                      $callback
                      );
         }
         my $rsp = {};
         $rsp->{data}->[0] = "File synchronization has completed.";
         $callback->($rsp);
       } else { # no syncfiles defined
         my $rsp = {};
         $rsp->{data}->[0] = "There were no syncfiles defined to process. File synchronization has completed.";
         $callback->($rsp);
       }
    }

    if (scalar(@$AIXnodes))
    {
        if (xCAT::Utils->isLinux())
        {
            # mixed cluster enviornment, Linux MN=>AIX node
            # linux nfs client can not mount AIX nfs directory with default settings.
            # settting nfs_use_reserved_ports=1 could solve the problem
            my $cmd   = qq~nfso -o nfs_use_reserved_ports=1~;
            my $output =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $AIXnodes, $cmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not set nfs_use_reserved_ports=1 on nodes. Error message is:\n";
                push @{$rsp->{data}}, "$output\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
        }
    }

    #
    #  handle software updates
    #
    if ($request->{swmaintenance} && $request->{swmaintenance}->[0] eq "yes")
    {
        my $rsp;
        push @{$rsp->{data}},
          "Performing software maintenance operations. This could take a while.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);

        my ($rc, $AIXnodes_nd, $Linuxnodes_nd) = xCAT::InstUtils->getOSnodes($nondsklsnodes);

		#
        #   do linux nodes
        #
        if (scalar(@$Linuxnodes_nd))
        {    # we have a list of linux nodes
            my $cmd;
 	    # get server names as known by the nodes
	    my %servernodes = %{xCAT::InstUtils->get_server_nodes($callback, \@$Linuxnodes_nd)};
	    # it's possible that the nodes could have diff server names
	    # do all the nodes for a particular server at once
	    foreach my $snkey (keys %servernodes) {
		my $nodestring = join(',', @{$servernodes{$snkey}});
       	my $cmd;
		if ($::SETSERVER) {
		    $cmd =
		    "XCATBYPASS=Y $::XCATROOT/bin/xdsh $nodestring -s -v -e $installdir/postscripts/xcatdsklspost 2 -M $snkey ospkgs,otherpkgs 2>&1";

		} else {
		    
		    $cmd =
		    "XCATBYPASS=Y $::XCATROOT/bin/xdsh $nodestring -s -v -e $installdir/postscripts/xcatdsklspost 2 -m $snkey ospkgs,otherpkgs 2>&1";
		}

		if ($::VERBOSE)
		{
		    my $rsp = {};
		    $rsp->{data}->[0] = "  $localhostname: Internal call command: $cmd";
		    $callback->($rsp);
		}
		
		if ($cmd && !open(CMD, "$cmd |"))
		{
		    my $rsp = {};
		    $rsp->{data}->[0] = "$localhostname: Cannot run command $cmd";
		    $callback->($rsp);
		}
		else
		{
		    while (<CMD>)
		    {
			my $rsp    = {};
			my $output = $_;
			chomp($output);
			$output =~ s/\\cM//;
			if ($output =~ /returned from postscript/)
			{
			    $output =~
				s/returned from postscript/Running of Software Maintenance has completed./;
			}
			$rsp->{data}->[0] = "$output";
			$callback->($rsp);
		    }
		    close(CMD);
		}
	    }

        }

		#
        #   do AIX nodes
        #

        if (scalar(@$AIXnodes_nd))
        {   
            # update the software on an AIX node
			if ( &updateAIXsoftware($callback, \%::attrres, $imgdefs, $updates,
$AIXnodes_nd, $subreq  ) != 0 ) {
                #		my $rsp;
                #		push @{$rsp->{data}},  "Could not update software for AIX nodes \'@$AIXnodes\'.";
                #		xCAT::MsgUtils->message("E", $rsp, $callback);;
                return 1;
            }
        }
    }    # end sw maint section

    #
    # handle of setting up ssh keys
    #

    if ($request->{security} && $request->{security}->[0] eq "yes") {
         
        # generate the arguments
        my @args = ("-K");
        if ($request->{user}->[0]) {
            push @args, "--user";
            push @args, $request->{user}->[0];
        }
        if ($request->{devicetype}->[0]) {
            push @args, "--devicetype";
            push @args, $request->{devicetype}->[0];
        }

        # remove the host key from known_hosts
        xCAT::Utils->runxcmd(  {
            command => ['makeknownhosts'],
            node    => \@$nodes,
            arg     => ['-r'],
            }, $subreq, 0, 1);

        if ($::VERBOSE)
        {
            my $rsp = {};
            $rsp->{data}->[0] =
              "  $localhostname: run makeknownhosts to clean known_hosts file for nodes: @$nodes";
            $callback->($rsp);
        }

        # call the xdsh -K to set up the ssh keys
        my @envs = @{$request->{environment}};
        my $res = xCAT::Utils->runxcmd(  {
            command => ['xdsh'],
            node    => \@$nodes,
            arg     => \@args,
            env     => \@envs,
            }, $subreq, 0, 1);
            
        if ($::VERBOSE)
        {
            my $rsp = {};
            $rsp->{data}->[0] =
              "  $localhostname: Internal call command: xdsh -K. nodes = @$nodes, arguments = @args, env = @envs";
            $rsp->{data}->[1] = 
              "  $localhostname: return messages of last command: @$res";
            $callback->($rsp);
        }

        # parse the output of xdsh -K
        my @failednodes = @$nodes;
        foreach my $line (@$res) {
            chomp($line);
            if ($line =~ /SSH setup failed for the following nodes: (.*)\./) {
                @failednodes = split(/,/, $1);
            } elsif ($line =~ /setup is complete/) {
                @failednodes = ();
            }
        }


        my $rsp = {};
        foreach my $node (@$nodes) {
            if (grep /^$node$/, @failednodes) {
                push @{$rsp->{data}}, "$node: Setup ssh keys failed.";
            } else {
                push @{$rsp->{data}}, "$node: Setup ssh keys has completed.";
            }
        }
        $callback->($rsp);
    }

    #
    # handle the running of cust scripts
    #

    if ($request->{rerunps} && $request->{rerunps}->[0] eq "yes")
    {
        my $postscripts = "";
        my $orig_postscripts = "";
        if (($request->{postscripts}) && ($request->{postscripts}->[0]))
        {
            $orig_postscripts = $request->{postscripts}->[0];
        }

        if (scalar(@$Linuxnodes))
        {    
           my $DBname = xCAT::Utils->get_DBName;
           if ($orig_postscripts eq "allkeys44444444security") {
               $postscripts = "remoteshell,servicenode";
           } else {
               $postscripts = $orig_postscripts;
           }
           
           # we have Linux nodes
           my $cmd;
	    # get server names as known by the nodes
	    my %servernodes = %{xCAT::InstUtils->get_server_nodes($callback, \@$Linuxnodes)};
	    # it's possible that the nodes could have diff server names
	    # do all the nodes for a particular server at once
	    foreach my $snkey (keys %servernodes) {
		my $nodestring = join(',', @{$servernodes{$snkey}});
            	my $args;
                my $mode;
                if ($request->{rerunps4security} && $request->{rerunps4security}->[0] eq "yes") {
                    # for updatenode --security
                    $mode = "5";
                } else {
                    # for updatenode -P
                    $mode = "1"; 
                }
                my $args1;
		if ($::SETSERVER) {
		    $args1 = ["-s", "-v", "-e", "$installdir/postscripts/xcatdsklspost $mode -M $snkey '$postscripts'"];

		} else {
		    
		    $args1 = ["-s", "-v", "-e", "$installdir/postscripts/xcatdsklspost $mode -m $snkey '$postscripts'"];
		}
		

		if ($::VERBOSE)
		{
		    my $rsp = {};
		    $rsp->{data}->[0] = "  $localhostname: Internal call command: xdsh $nodestring ".join(' ',@$args1);
		    $callback->($rsp);
		}
               
		#my  $output1 = xCAT::Utils->runxcmd({command => ["xdsh"], 
		#				    node => $servernodes{$snkey}, 
		#				    arg => $args1, 
		#				    _xcatpreprocessed =>[1]}, 
		#				   $subreq, 0, 1);
		#

                #if ($::RUNCMD_RC != 0)
                #{
                #    my $rsp;
                #    push @{$rsp->{data}}, "Could not run postscripts $postscripts on nodes $nodestring \n";
                #    xCAT::MsgUtils->message("E", $rsp, $callback);
                #} 
                $CALLBACK=$callback;
		if ($request->{rerunps4security}) {
		    $RERUNPS4SECURITY=$request->{rerunps4security}->[0];
		} else {
		    $RERUNPS4SECURITY="";
		}
		$subreq->({command => ["xdsh"], 
			   node => $servernodes{$snkey}, 
			   arg => $args1, 
			   _xcatpreprocessed =>[1]},
			  \&getdata);

	    }
	}
    


        if (scalar(@$AIXnodes))
        {
           # we have AIX nodes
           if ($orig_postscripts eq "allkeys44444444security") {
               $postscripts = "aixremoteshell,servicenode";
           } else {
               $postscripts = $orig_postscripts;
           }
           
	    # need to pass the name of the server on the xcataixpost cmd line
	    
	    # get server names as known by the nodes
	    my %servernodes = %{xCAT::InstUtils->get_server_nodes($callback, \@$AIXnodes)};
	    # it's possible that the nodes could have diff server names
	    # do all the nodes for a particular server at once
	    foreach my $snkey (keys %servernodes) {
		my $nodestring = join(',', @{$servernodes{$snkey}});
            	my $cmd;
                my $mode;
                if ($request->{rerunps4security} && $request->{rerunps4security}->[0] eq "yes") {
                    # for updatenode --security
                    $mode = "5";
                } else {
                    # for updatenode -P
                    $mode = "1";
                }

		if ($::SETSERVER) {
		    $cmd = "XCATBYPASS=Y $::XCATROOT/bin/xdsh $nodestring -s -v -e $installdir/postscripts/xcataixpost -M $snkey -c $mode '$postscripts' 2>&1";
		} else {
		    $cmd = "XCATBYPASS=Y $::XCATROOT/bin/xdsh $nodestring -s -v -e $installdir/postscripts/xcataixpost -m $snkey -c $mode '$postscripts' 2>&1";
		}
		
            	if ($::VERBOSE)
            	{
		    my $rsp = {};
		    $rsp->{data}->[0] = "  $localhostname: Internal call command: $cmd";
		    $callback->($rsp);
            	}
		
            	if (!open(CMD, "$cmd |"))
            	{
		    my $rsp = {};
		    $rsp->{data}->[0] = "$localhostname: Cannot run command $cmd";
		    $callback->($rsp);
            	}
            	else
            	{
                    my $rsp = {};
		    while (<CMD>)
		    {
                    	my $output = $_;
                    	chomp($output);
                    	$output =~ s/\\cM//;
                    	if ($output =~ /returned from postscript/)
                    	{
			    $output =~
				s/returned from postscript/Running of postscripts has completed./;
                    	}
                        if ($request->{rerunps4security} && $request->{rerunps4security}->[0] eq "yes") {
                            if ($output =~ /Running of postscripts has completed/) {
                                $output =~ s/Running of postscripts has completed/Redeliver certificates has completed/;
                                push @{$rsp->{data}}, $output;
                            } elsif ($output !~ /Running postscript|Error loading module/) {
                                push @{$rsp->{data}}, $output;
                            }
                        } elsif ($output !~ /Error loading module/) {
			    push @{$rsp->{data}}, "$output";
                        }
		    }
		    close(CMD);
                    $callback->($rsp);
            	}
	    }
        }
        if ($request->{rerunps4security} && $request->{rerunps4security}->[0] eq "yes") {
            # clean the know_hosts
            xCAT::Utils->runxcmd(  {
                command => ['makeknownhosts'],
                node    => \@$nodes,
                arg     => ['-r'],
                }, $subreq, 0, 1);
        }
    }


	#
	# Handle updating OS
	#
	if ($request->{os} && $request->{os}->[0] eq "yes") {
		my $os = $::OS;
		
		# Process ID for xfork()
		my $pid;

		# Child process IDs
		my @children;
	
		# Go through each node
		foreach my $node (@$nodes) {
			$pid = xCAT::Utils->xfork();

			# Parent process
			if ($pid) {
				push( @children, $pid );
			}

			# Child process
			elsif ( $pid == 0 ) {
				# Update OS
				updateOS($callback, $node, $os);

				# Exit process
				exit(0);
			}
			else {

				# Ran out of resources
				die "Error: Could not fork\n";
			}
		} # End of foreach
		
		# Wait for all processes to end
		foreach (@children) {
			waitpid( $_, 0 );
		}
	}

    return 0;
}

sub getdata {
   my $response = shift;
   my $rsp;
   foreach my $type (keys %$response) {
       foreach my $output (@{$response->{$type}}) {
	   chomp($output);
	   $output =~ s/\\cM//;
	   if ($output =~ /returned from postscript/)
	   {
	       $output =~
		   s/returned from postscript/Running of postscripts has completed./;
	   }
	   if ($RERUNPS4SECURITY && $RERUNPS4SECURITY eq "yes") {
	       if ($output =~ /Running of postscripts has completed/) {
		   $output =~ s/Running of postscripts has completed/Redeliver certificates has completed/;
		   push @{$rsp->{$type}}, $output;
	       } elsif ($output !~ /Running postscript|Error loading module/) {
		   push @{$rsp->{$type}}, "$output";
	       }
	   } elsif ($output !~ /Error loading module/) {
	       push @{$rsp->{$type}}, "$output";
	   }
       }
   }
   $CALLBACK->($rsp);
}

#-------------------------------------------------------------------------------

=head3   updatenodestat

    Arguments:
    Returns:
        0 - for success.
        1 - for error.

=cut

#-----------------------------------------------------------------------------
sub updatenodestat
{
    my $request  = shift;
    my $callback = shift;
    my @nodes    = ();
    my @args     = ();
    if (ref($request->{node}))
    {
        @nodes = @{$request->{node}};
    }
    else
    {
        if ($request->{node}) { @nodes = ($request->{node}); }
    }
    if (ref($request->{arg}))
    {
        @args = @{$request->{arg}};
    }
    else
    {
        @args = ($request->{arg});
    }

    if ((@nodes > 0) && (@args > 0))
    {
        my %node_status = ();
        my $stat        = $args[0];
        $node_status{$stat} = [];
        foreach my $node (@nodes)
        {
            my $pa = $node_status{$stat};
            push(@$pa, $node);
        }
        xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%node_status, 1);
    }

    return 0;
}

#-------------------------------------------------------------------------------

=head3   doAIXcopy

    Copy software update files to SNs - if needed.

    Arguments:

    Returns:
		errors:
      		0 - OK
      		1 - error
		hash refs:
			- osimage definitions
			- node update information

    Example
	 my ($rc, $imagedef, $updateinfo) = &doAIXcopy($callback, \%attrvals, 
			$nodes, $subreq);

    Comments:
        - running on MN

=cut

#------------------------------------------------------------------------------
sub doAIXcopy
{
    my $callback = shift;
    my $av       = shift;
    my $nodes    = shift;
    my $subreq   = shift;

    my @nodelist;    # node list
    my %attrvals;    # cmd line attr=val pairs

    if ($nodes)
    {
        @nodelist = @$nodes;
    }

    if ($av)
    {
        %attrvals = %{$av};
    }

    # get the NIM primary server name
    my $nimprime = xCAT::InstUtils->getnimprime();
    chomp $nimprime;

    my %nodeupdateinfo;

    #
    # do we have to copy files to any SNs????
    #

    # get a list of service nodes for this node list
    my $sn = xCAT::Utils->get_ServiceNode(\@nodelist, "xcat", "MN");
    if ($::ERROR_RC)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get list of xCAT service nodes.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    # want list of remote service nodes - to copy files to

    # get the ip of the NIM primary (normally the management node)
    my $ip = xCAT::NetworkUtils->getipaddr($nimprime);
    chomp $ip;
    my ($p1, $p2, $p3, $p4) = split /\./, $ip;

    my @SNlist;
    foreach my $snkey (keys %$sn)
    {

        my $sip = xCAT::NetworkUtils->getipaddr($snkey);
        chomp $sip;
        if ($ip eq $sip)
        {
            next;
        }
        else
        {
            if (!grep(/^$snkey$/, @SNlist))
            {
                push(@SNlist, $snkey);
            }
        }
    }

    # get a list of osimage names needed for the nodes
    my $nodetab = xCAT::Table->new('nodetype');
    my $images  =
      $nodetab->getNodesAttribs(\@nodelist, ['node', 'provmethod', 'profile']);
    my @imagenames;
    my @noimage;
    foreach my $node (@nodelist)
    {
        my $imgname;
        if ($images->{$node}->[0]->{provmethod})
        {
            $imgname = $images->{$node}->[0]->{provmethod};
        }
        elsif ($images->{$node}->[0]->{profile})
        {
            $imgname = $images->{$node}->[0]->{profile};
        }

        if(!$imgname) {
            push @noimage, $node;
        } elsif (!grep(/^$imgname$/, @imagenames))
        {
            push @imagenames, $imgname;
        }
        $nodeupdateinfo{$node}{imagename} = $imgname;
    }
    $nodetab->close;

    if (@noimage) {
        my $rsp;
        my $allnodes = join(',', @noimage);
        push @{$rsp->{data}}, "No osimage specified for the following nodes: $allnodes. You can try to run the nimnodeset command or set the profile|provmethod attributes manually.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    my $osimageonly = 0;
    if ((!$attrvals{installp_bundle} && !$attrvals{otherpkgs}) && !$::CMDLINE)
    {

        # if nothing is provided on the cmd line and we don't set CMDLINE
        #	then we just use the osimage def - used for permanent updates
        $osimageonly = 1;
    }

    #
    #  get the osimage defs
    #
    my %imagedef;
    my @pkglist;    # list of all software to go to SNs
    my %bndloc;

    foreach my $img (@imagenames)
    {
        my %objtype;
        $objtype{$img} = 'osimage';
        %imagedef = xCAT::DBobjUtils->getobjdefs(\%objtype, $callback);
        if (!(%imagedef))
        {
            my $rsp;
            push @{$rsp->{data}},
              "Could not get the xCAT osimage definition for \'$img\'.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }

        #
        #  if this is not a "standalone" type image then this is an error
        #
        if ($imagedef{$img}{nimtype} ne "standalone")
        {
            my $rsp;
            push @{$rsp->{data}},
              "The osimage \'$img\' is not a standalone type.  \nThe software maintenance function of updatenode command can only be used for standalone (diskfull) type nodes. \nUse the mknimimage comamand to update diskless osimages.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }

		# if we're not using the os image 
        if ($osimageonly != 1)
        {
			# set the imagedef to the cmd line values
            if ($attrvals{installp_bundle})
            {
                $imagedef{$img}{installp_bundle} = $attrvals{installp_bundle};
            }
            else
            {
                $imagedef{$img}{installp_bundle} = "";
            }
            if ($attrvals{otherpkgs})
            {
                $imagedef{$img}{otherpkgs} = $attrvals{otherpkgs};
            }
            else
            {
                $imagedef{$img}{otherpkgs} = "";
            }
        }

        if ($attrvals{installp_flags})
        {
            $imagedef{$img}{installp_flags} = $attrvals{installp_flags};
        }

        if ($attrvals{rpm_flags})
        {
            $imagedef{$img}{rpm_flags} = $attrvals{rpm_flags};
        }

		if ($attrvals{emgr_flags})
		{
			$imagedef{$img}{emgr_flags} = $attrvals{emgr_flags};
		}

        # get loc of software for node
		if ($::ALTSRC) {
			$imagedef{$img}{alt_loc} = $::ALTSRC;
		} else {
			if ($imagedef{$img}{lpp_source} ) {
        		$imagedef{$img}{lpp_loc} = xCAT::InstUtils->get_nim_attr_val($imagedef{$img}{lpp_source}, 'location', $callback, $nimprime, $subreq);
			} else {
				$imagedef{$img}{lpp_loc} = "";
				next;
			}
		}

		if ($::ALLSW) {
			# get a list of all the files in the location
			# if its an alternate loc than just check that dir
			# if it's an lpp_source than check both RPM and installp
			my $rpmloc;
			my $instploc;
			my $emgrloc;
			if ($::ALTSRC) {
				# use same loc for everything
				$rpmloc = $instploc = $imagedef{$img}{alt_loc};
			} else {
				# use specific lpp_source loc
				$rpmloc = "$imagedef{$img}{lpp_loc}/RPMS/ppc";
				$instploc = "$imagedef{$img}{lpp_loc}/installp/ppc";
				$emgrloc = "$imagedef{$img}{lpp_loc}/emgr/ppc";
			}

			# get installp filesets in this dir
			my $icmd = qq~installp -L -d $instploc | /usr/bin/cut -f1 -d':' 2>/dev/null~;
			my @ilist = xCAT::Utils->runcmd("$icmd", -1);
			foreach my $f (@ilist) {
				if (!grep(/^$f$/, @pkglist)) {
					push (@pkglist, $f);
				}
			}

			# get epkg files
			my $ecmd = qq~/usr/bin/ls $emgrloc 2>/dev/null~;
			my @elist = xCAT::Utils->runcmd("$ecmd", -1);
			foreach my $f (@elist) {
				if (($f =~ /epkg\.Z/)) {
					push (@pkglist, $f);
                }
			}

			# get rpm packages
			my $rcmd = qq~/usr/bin/ls $rpmloc 2>/dev/null~;
			my @rlist = xCAT::Utils->runcmd("$rcmd", -1);
			foreach my $f (@rlist) {
				if ($f =~ /\.rpm/) {
					 push (@pkglist, $f);
                }
			}
		} else {
			# use otherpkgs and or installp_bundle

        	# keep a list of packages from otherpkgs and bndls
        	if ($imagedef{$img}{otherpkgs})
        	{
            	foreach my $pkg (split(/,/, $imagedef{$img}{otherpkgs}))
            	{
					my ($junk, $pname);
					$pname = $pkg;
					if (!grep(/^$pname$/, @pkglist))
                	{
                          push(@pkglist, $pname);
                	}
            	}
        	}
        	if ($imagedef{$img}{installp_bundle})
        	{
            	my @bndlist = split(/,/, $imagedef{$img}{installp_bundle});
            	foreach my $bnd (@bndlist)
            	{
                	my ($rc, $list, $loc) = xCAT::InstUtils->readBNDfile($callback, $bnd, $nimprime, $subreq);
                	foreach my $pkg (@$list)
                	{
                    	chomp $pkg;
                    	if (!grep(/^$pkg$/, @pkglist))
                    	{
                        	push(@pkglist, $pkg);
                    	}
                	}
                	$bndloc{$bnd} = $loc;
            	}
        	}
		}

        # put array in string to pass along to SN
        $imagedef{$img}{pkglist} = join(',', @pkglist);
    }

    # if there are no SNs to update then return
    if (scalar(@SNlist) == 0)
    {
        return (0, \%imagedef, \%nodeupdateinfo);
    }

    # copy pkgs from location on nim prime to same loc on SN
    foreach my $snkey (@SNlist)
    {
        # copy files to SN from nimprime!!
        # for now - assume nimprime is management node

        foreach my $img (@imagenames)
        {
			if (!$::ALTSRC) {
            	# if lpp_source is not defined on SN then next
            	my $scmd = qq~/usr/sbin/lsnim -l $imagedef{$img}{lpp_source} 2>/dev/null~;
            	my $out = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $snkey, $scmd, 0);

            	if ($::RUNCMD_RC != 0)
            	{
					my $rsp;
					push @{$rsp->{data}}, "The NIM lpp_source resource named $imagedef{$img}{lpp_source} is not defined on $snkey. Cannot copy software to $snkey.\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
                	next;
            	}
			}

			# get the dir names to copy to
			my $srcdir;
			if ($::ALTSRC) {
				$srcdir = "$imagedef{$img}{alt_loc}";
			} else {
				$srcdir = "$imagedef{$img}{lpp_loc}";
			}
			my $dir = dirname($srcdir);

			if ($::VERBOSE)
			{
				my $rsp;
				push @{$rsp->{data}}, "Copying $srcdir to $dir on service node $snkey.\n";
				xCAT::MsgUtils->message("I", $rsp, $callback);
			}

			# make sure the dir exists on the service node
			#  also make sure it's writeable by all
			my $mkcmd = qq~/usr/bin/mkdir -p $dir~;
			my $output = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $snkey, $mkcmd, 0);
			if ($::RUNCMD_RC  != 0) {
				my $rsp;
				push @{$rsp->{data}}, "Could not create directories on $snkey.\n";
				if ($::VERBOSE) {
					push @{$rsp->{data}}, "$output\n";
				}
				xCAT::MsgUtils->message("E", $rsp, $callback);
				next;
			}

			# sync source files to SN
			my $cpcmd = qq~$::XCATROOT/bin/prsync -o "rlHpEAogDz" $srcdir $snkey:$dir 2>/dev/null~;
			$output=xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cpcmd, 0);
			if ($::RUNCMD_RC != 0)
			{
				my $rsp;
				push @{$rsp->{data}}, "Could not copy $srcdir to $dir for service node $snkey.\n";
				push @{$rsp->{data}}, "Output from command: \n\n$output\n\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
				return (1);
			}

			# run inutoc in remote installp dir
			my $installpsrcdir;
			if ($::ALTSRC) {
				$installpsrcdir = $srcdir;
			} else {
				$installpsrcdir = "$srcdir/installp/ppc";
			}
			my $icmd = qq~cd $installpsrcdir; /usr/sbin/inutoc .~;
			my $output = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $snkey, $icmd, 0);
			if ($::RUNCMD_RC != 0)
			{
				my $rsp;
				push @{$rsp->{data}}, "Could not run inutoc for $installpsrcdir on $snkey\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
			}
        } # end for each osimage
    }    # end - for each service node
    return (0, \%imagedef, \%nodeupdateinfo);
}

#-------------------------------------------------------------------------------

=head3   updateAIXsoftware

    Update the software on an xCAT AIX cluster node. 

    Arguments:

    Returns:
      0 - OK
      1 - error

	Example
		if (&updateAIXsoftware($callback, \%attrres, $imgdefs, $updates, $nodes, $subreq)!= 0) 

    Comments:

=cut

#-------------------------------------------------------------------------------

sub updateAIXsoftware
{
    my $callback = shift;
	my $attrs    = shift;
    my $imgdefs  = shift;
    my $updates  = shift;
    my $nodes    = shift;
    my $subreq   = shift;

    my @noderange = @$nodes;
    my %attrvals;    # cmd line attr=val pairs
    my %imagedefs;
    my %nodeupdateinfo;
    my @pkglist;     # list of ALL software to install

    # att=val - bndls, otherpakgs, flags
    if ($attrs)
    {
        %attrvals = %{$attrs};
    }
    if ($imgdefs)
    {
        %imagedefs = %{$imgdefs};
    }
    if ($updates)
    {
        %nodeupdateinfo = %{$updates};
    }

    my %bndloc;

    # get the server name for each node - as known by node
    my $noderestab  = xCAT::Table->new('noderes');
    my $xcatmasters =
      $noderestab->getNodesAttribs(\@noderange, ['node', 'xcatmaster']);

    # get the NIM primary server name
    my $nimprime = xCAT::InstUtils->getnimprime();
    chomp $nimprime;

    # if it's not the xcatmaster then default to the NIM primary
    my %server;
    my @servers;
    foreach my $node (@noderange)
    {
        if ($xcatmasters->{$node}->[0]->{xcatmaster})
        {
            $server{$node} = $xcatmasters->{$node}->[0]->{xcatmaster};
        }
        else
        {
            $server{$node} = $nimprime;
        }

        if (!grep($server{$node}, @servers))
        {
            push(@servers, $server{$node});
        }
    }
    $noderestab->close;

    # sort nodes by image name so we can do bunch at a time
    my %nodeoslist;
    foreach my $node (@noderange)
    {
		push(@{$nodeoslist{$nodeupdateinfo{$node}{imagename}}}, $node);
    }

    my $error = 0;
    my @installp_files;    # list of tmp installp files created
	my @emgr_files;        # list of tmp emgr file created

    foreach my $img (keys %imagedefs)
    {
		# set the location of the software 
		my $pkgdir="";
		if ($::ALTSRC) {
			$pkgdir = $::ALTSRC;
		} else {
			$pkgdir = $imagedefs{$img}{lpp_loc};
		}

		my $noinstp=0;
		my $noemgr=0;

        chomp $img;
        if ($img)
        {
            my @nodes = @{$nodeoslist{$img}};

            # process the package list
            #   - split into rpm, emgr, and installp
            #   - remove leading prefix - if any
            my @rpm_pkgs;
			my @emgr_pkgs;
            my @installp_pkgs;
            @pkglist = split(/,/, $imagedefs{$img}{pkglist});

            if (scalar(@pkglist))
            {
                foreach my $p (@pkglist)
                {
					if (($p =~ /\.rpm/) || ($p =~ /^R:/))
                    {
						my ($junk, $pname);
						if ($p =~ /:/) {
                        	($junk, $pname) = split(/:/, $p);
						} else {
							$pname = $p;
						}
                        push @rpm_pkgs, $pname;
                    } elsif (($p =~ /epkg\.Z/) || ($p =~ /^E:/)) {

						my ($junk, $pname);
                        if ($p =~ /:/) {
                            ($junk, $pname) = split(/:/, $p);
                        } else {
                            $pname = $p;
                        }
                        push @emgr_pkgs, $pname;

					} else {
						my ($junk, $pname);
                        if ($p =~ /:/) {
                            ($junk, $pname) = split(/:/, $p);
                        } else {
                            $pname = $p;
                        }
                        push @installp_pkgs, $pname;
                    }
                }
            }

			my $thisdate           = `date +%s`;

            #
            # create tmp file for installp filesets
            #
            my $installp_file_name = "installp_file-" . $thisdate;
            chomp $installp_file_name;

			my $noinstallp=0;
            if (scalar(@installp_pkgs))
            {
			  	if ($pkgdir) {
                	if (!open(INSTPFILE, ">/tmp/$installp_file_name"))
                	{
                    	my $rsp;
                    	push @{$rsp->{data}},
                      		"Could not open $installp_file_name.\n";
                    	xCAT::MsgUtils->message("E", $rsp, $callback);
						$error++;
						$noinstp=1;
                	} else {

            			foreach (@installp_pkgs)
            			{
                			print INSTPFILE $_ . "\n";
            			}
            			close(INSTPFILE);

            			# add new file to list so it can be removed later
            			push @installp_files, $installp_file_name;

            			# copy file to each lpp_source, make sure it's 
            			#	 all readable and export the dir

            			if ((-e "/tmp/$installp_file_name"))
            			{
                			my $icmd =
                  				qq~cp /tmp/$installp_file_name $pkgdir; chmod 444 /$pkgdir/$installp_file_name~;
                			my $output = xCAT::Utils->runcmd("$icmd", -1);
                			if ($::RUNCMD_RC != 0)
                			{
                    			my $rsp;
                    			push @{$rsp->{data}},
                      				"Could not copy /tmp/$installp_file_name.\n";
                    			push @{$rsp->{data}}, "$output\n";
                    			xCAT::MsgUtils->message("E", $rsp, $callback);
								$error++;
								$noinstp=1;
                			}
						}
            		}
			  	}
			} # end installp tmp file

            #
            # create tmp file for interim fix packages
            #
            my $emgr_file_name = "emgr_file-" . $thisdate;
            chomp $emgr_file_name;
            if (scalar(@emgr_pkgs))
            {
			  	if ($pkgdir) {
                	if (!open(EMGRFILE, ">/tmp/$emgr_file_name"))
                	{
                    	my $rsp;
                    	push @{$rsp->{data}},
                      		"Could not open $emgr_file_name.\n";
                    	xCAT::MsgUtils->message("E", $rsp, $callback);
						$error++;
						$noemgr=1;
                	} else {

            			foreach (@emgr_pkgs)
            			{
                			print EMGRFILE "./$_" . "\n";
            			}
            			close(EMGRFILE);

            			# add new file to list so it can be removed later
            			push @emgr_files, $emgr_file_name;

            			# copy file to each package directory, make sure it's 
						#	all readable and export ed
            			if ((-e "/tmp/$emgr_file_name"))
            			{
                			my $icmd =
                  			qq~cp /tmp/$emgr_file_name $pkgdir; chmod 444 $pkgdir/$emgr_file_name~;
                			my $output = xCAT::Utils->runcmd("$icmd", -1);
                			if ($::RUNCMD_RC != 0)
                			{
                    			my $rsp;
                    			push @{$rsp->{data}},
                      				"Could not copy /tmp/$emgr_file_name.\n";
                    			push @{$rsp->{data}}, "$output\n";
                    			xCAT::MsgUtils->message("E", $rsp, $callback);
								$error++;
								$noemgr=1;
							}
                		}
            		}
			  	}
			} # end emgr tmp file

			# make sure pkg dir is exported
            if (scalar(@pkglist)) {
				my $ecmd;
                my @nfsv4 = xCAT::Utils->get_site_attribute("useNFSv4onAIX");
                if ($nfsv4[0] && ($nfsv4[0] =~ /1|Yes|yes|YES|Y|y/))
                {
                    $ecmd = qq~exportfs -i -o vers=4 $pkgdir~;
                }
                else
                {
                    $ecmd = qq~exportfs -i $pkgdir~;
                }
                my $output = xCAT::Utils->runcmd("$ecmd", -1);
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp;
                    push @{$rsp->{data}}, "Could not export $pkgdir.\n";
                    push @{$rsp->{data}}, "$output\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    $error++;
                    next;
                }
            }

            #
            # install sw on nodes
            #
			# $serv is the name of the nodes server as known by the node

		  	if (scalar(@pkglist)) {
            	foreach my $serv (@servers)
            	{

					# make sure the permissions are correct in the lpp_source
					my $chmcmd = qq~/bin/chmod -R +r $pkgdir~;

					# if server is me then just do chmod
					if (xCAT::InstUtils->is_me($serv)) {
						my @result = xCAT::Utils->runcmd("$chmcmd", -1);
						if ($::RUNCMD_RC != 0)
						{
							my $rsp;
							push @{$rsp->{data}}, "Could not set permissions for $pkgdir.\n";
							xCAT::MsgUtils->message("E", $rsp, $callback);
							return 1;
						}

					} else {  # if server is remote then use xdsh
						my $output = xCAT::Utils->runxcmd({command => ["xdsh"], node => [$serv], arg => [$chmcmd]}, $subreq, -1, 1);
						if ($::RUNCMD_RC != 0)
						{
							my $rsp;
							push @{$rsp->{data}}, "Could not set permissions for $pkgdir.\n";
							xCAT::MsgUtils->message("E", $rsp, $callback);
						 	return 1;
						}
					}

                	# mount source dir to node
					my $mcmd;
					my @nfsv4 = xCAT::Utils->get_site_attribute("useNFSv4onAIX");
					if ($nfsv4[0] && ($nfsv4[0] =~ /1|Yes|yes|YES|Y|y/))
					{
						$mcmd   = qq~mkdir -m 644 -p /xcatmnt; mount -o vers=4 $serv:$pkgdir /xcatmnt~;
					}
					else
					{
						$mcmd   = qq~mkdir -m 644 -p /xcatmnt; mount $serv:$pkgdir /xcatmnt~;
					}

					if ($::VERBOSE)
                	{
                    	my $rsp;
                    	push @{$rsp->{data}}, "Running command: $mcmd\n";
                    	xCAT::MsgUtils->message("I", $rsp, $callback);
                	}

					my $output = xCAT::Utils->runxcmd({command => ["xdsh"], node => \@nodes, arg => [$mcmd]}, $subreq, -1, 1);

                	if ($::RUNCMD_RC != 0)
                	{
                    	my $rsp;
                    	push @{$rsp->{data}},
                      		"Could not mount $pkgdir on nodes.\n";
						foreach my $o (@$output)
                        {
                            push @{$rsp->{data}}, "$o";
                        }
                    	xCAT::MsgUtils->message("E", $rsp, $callback);
                    	$error++;
                    	next;
                	}
            	}
			}

            # do installp first
            # if we have installp filesets or other installp flags
			# we may just get flags!
            if ( ((scalar(@installp_pkgs)) || $::ALLSW || ($imagedefs{$img}{installp_flags})) && !$noinstp) {

                # - use installp with file
                # set flags
                my $flags;
                if ($imagedefs{$img}{installp_flags})
                {
                    $flags = " " . $imagedefs{$img}{installp_flags};
                }
                else
                {
                    $flags = " -agQX ";
                }

                # put together the installp command
                my $inpcmd = qq~/usr/sbin/installp ~;

                # these installp flags can be used with -d
                if ($flags =~ /l|L|i|A|a/)
                {
					# if a specific dir was provided then use it
					# otherwise use the installp dir in the lpp src
					if ($::ALTSRC) {
						$inpcmd .= qq~-d /xcatmnt ~;
					} else {
                    	$inpcmd .= qq~-d /xcatmnt/installp/ppc ~;
					}
                }

                $inpcmd .= qq~$flags ~;

                # don't provide a list of filesets with these flags
                if ($flags !~ /C|L|l/) {

					if ($::ALLSW) {
                        # we want all sw installed
                        $inpcmd .= qq~ all~;
                    } elsif ( scalar(@installp_pkgs) == 0  ) {
                        # there is no sw to install
                        $noinstallp=1;
                    } else {
                        # install what is in installp_pkgs
                        $inpcmd .= qq~-f /xcatmnt/$installp_file_name~;
                    }
                }

				#  - could just have installp flags by mistake -ugh!
				#	- but don't have fileset to install - so don't run
				#		installp - UNLESS the flags don't need filesets
			  	if ($noinstallp == 0 ) {

                	if ($::VERBOSE)
                	{
                    	my $rsp;
                    	push @{$rsp->{data}}, "Running: \'$inpcmd\'.\n";
                    	xCAT::MsgUtils->message("I", $rsp, $callback);
                	}

					my $output = xCAT::Utils->runxcmd({command => ["xdsh"], node => \@nodes, arg => [$inpcmd]}, $subreq, -1, 1);

                	if ($::RUNCMD_RC != 0)
                 	{
                    	my $rsp;
                    	push @{$rsp->{data}}, "Could not run installp command.\n";
						foreach my $o (@$output)
                        {
                            push @{$rsp->{data}}, "$o";
                        }
                    	xCAT::MsgUtils->message("I", $rsp, $callback);
                    	$error++;

                	} elsif ($::VERBOSE)
                	{
                    	my $rsp;
						foreach my $o (@$output)
                        {
                            push @{$rsp->{data}}, "$o";
                        }
                    	xCAT::MsgUtils->message("I", $rsp, $callback);
                	}
			  	}

				#
				# - run updtvpkg to make sure installp software
				#       is registered with rpm
				#
				my $upcmd   = qq~/usr/sbin/updtvpkg~;
				if ($::VERBOSE)
				{
					my $rsp;
					push @{$rsp->{data}}, "Running command: $upcmd\n";
					xCAT::MsgUtils->message("I", $rsp, $callback);
				}

				my $output = xCAT::Utils->runxcmd({command => ["xdsh"], node => \@nodes, arg => [$upcmd]}, $subreq, -1, 1);

				if ($::RUNCMD_RC != 0)
				{
					my $rsp;
					push @{$rsp->{data}}, "Could not run updtvpkg.\n";
					foreach my $o (@$output)
                    {
                        push @{$rsp->{data}}, "$o";
                    }
					xCAT::MsgUtils->message("E", $rsp, $callback);
					$error++;
				}
            }

			#
			# do any interim fixes using emgr
			#

			# if we have epkgs or emgr flags
			# we may just get flags!
			if ( ((scalar(@emgr_pkgs)) || $::ALLSW || ($imagedefs{$img}{emgr_flags})) && !$noemgr) {


				# if a specific dir was provided then use it
                # otherwise use the rpm dir in the lpp src
                my $dir;
                if ($::ALTSRC) {
                    $dir = "/xcatmnt";
                } else {
                    $dir = "/xcatmnt/emgr/ppc";
                }

				my $emgrcmd = qq~cd $dir; /usr/sbin/emgr~;

				if ($imagedefs{$img}{emgr_flags}) {
                    $emgrcmd .= qq~ $imagedefs{$img}{emgr_flags}~;
                }

				if ( (scalar(@emgr_pkgs)) || $::ALLSW ) {
					# call emgr with -f filename
					$emgrcmd .= qq~ -f /xcatmnt/$emgr_file_name~; 
				}

               	if ($::VERBOSE)
               	{
               		my $rsp;
               		push @{$rsp->{data}}, "Running: \'$emgrcmd\'.\n";
               		xCAT::MsgUtils->message("I", $rsp, $callback);
               	}

				my $output = xCAT::Utils->runxcmd({command => ["xdsh"], node => \@nodes, arg => [$emgrcmd]}, $subreq, -1, 1);

               	if ($::RUNCMD_RC != 0)
               	{
               		my $rsp;
               		push @{$rsp->{data}}, "Could not run emgr command.\n";
					foreach my $o (@$output)
                   	{
                       	push @{$rsp->{data}}, "$o";
                   	}
               		xCAT::MsgUtils->message("I", $rsp, $callback);
               		$error++;
               	} elsif ($::VERBOSE)
               	{
               		my $rsp;
					foreach my $o (@$output)
                   	{
                       	push @{$rsp->{data}}, "$o";
                   	}
               		xCAT::MsgUtils->message("I", $rsp, $callback);
            	}
			}

			#
			# do RPMs
			#

            if (scalar(@rpm_pkgs) || $::ALLSW || ($imagedefs{$img}{rpm_flags}))
            {

                # don't do rpms if these installp flags were specified
				# check this ??????!!!!! - this check doesn't seem necessary?
                #if ($imagedefs{$img}{installp_flags} !~ /C|L|l/)
				if (1) 
                {

                    # set flags
                    my $flags;
                    if ($imagedefs{$img}{rpm_flags})
                    {
                        $flags = " " . $imagedefs{$img}{rpm_flags};
                    }
                    else
                    {
						# use --replacepkgs so cmd won't fail if one is 
						#	already installed
                        $flags = " -Uvh --replacepkgs ";
                    }

					# if a specific dir was provided then use it
                    # otherwise use the rpm dir in the lpp src
					my $dir;
                    if ($::ALTSRC) {
                        $dir = "/xcatmnt";
                    } else {
                        $dir = "/xcatmnt/RPMS/ppc";
                    }
                    my $pkg_string = "";
					if ($::ALLSW) {
						$pkg_string = " *.rpm	"
					} else {
                    	foreach my $pkg (@rpm_pkgs)
                    	{
                        	$pkg_string .= " $pkg";
                    	}
					}

					my $rcmd;
					if (scalar(@rpm_pkgs)) {
						$rcmd = qq~cd $dir; /usr/bin/rpm $flags $pkg_string ~;
					} else {
						$rcmd = qq~/usr/bin/rpm $flags ~;
					}

                    if ($::VERBOSE)
                    {
                        my $rsp;
                        push @{$rsp->{data}}, "Running: \'$rcmd\'.\n";
                        xCAT::MsgUtils->message("I", $rsp, $callback);
                    }

					my $output = xCAT::Utils->runxcmd({command => ["xdsh"], node => \@nodes, arg => [$rcmd]}, $subreq, -1, 1);

                    if ( ($::RUNCMD_RC != 0) && (!$::ALLSW)) {
                        my $rsp;
                        push @{$rsp->{data}}, "Could not install RPMs.\n";
						foreach my $o (@$output)
                        {
                            push @{$rsp->{data}}, "$o";
                        }
                        xCAT::MsgUtils->message("I", $rsp, $callback);
                        $error++;
                    } elsif ($::VERBOSE) {
						# should we always give output??
						#   could get gobs of unwanted output in some cases
                        my $rsp;
						push @{$rsp->{data}}, "Command output:\n";
						foreach my $o (@$output)
                        {
                            push @{$rsp->{data}}, "$o";
                        }
                        xCAT::MsgUtils->message("I", $rsp, $callback);
                    }
                }
            }

			# unmount the src dir -
			if (scalar(@pkglist)) {
            	my $ucmd   = qq~umount -f /xcatmnt~;
				if ($::VERBOSE)
				{
					my $rsp;
					push @{$rsp->{data}}, "Running command: $ucmd\n";
					xCAT::MsgUtils->message("I", $rsp, $callback);
				}
					
				my $output = xCAT::Utils->runxcmd({command => ["xdsh"], node => \@nodes, arg => [$ucmd]}, $subreq, -1, 1);

            	if ($::RUNCMD_RC != 0)
            	{
                	my $rsp;
                	push @{$rsp->{data}}, "Could not umount.\n";
					foreach my $o (@$output)
                    {
                        push @{$rsp->{data}}, "$o";
                    }
                	xCAT::MsgUtils->message("E", $rsp, $callback);
                	next;
            	}
			}
        }
    }

    # clean up files copied to lpp_source locations and
    #	unexport the lpp locations
    foreach my $img (keys %imagedefs)
    {

        chomp $img;

		my $pkgdir;
		if ($::ALTSRC) {
			$pkgdir = $::ALTSRC;
		} else {
			$pkgdir = $imagedefs{$img}{lpp_loc};
		}

		if (scalar(@pkglist)) {
	
			# remove tmp installp files
       	 	foreach my $file (@installp_files)
        	{
				my $rcmd;
				$rcmd = qq~rm -f $pkgdir/$file; rm -f /tmp/$file~;
            	my $output = xCAT::Utils->runcmd("$rcmd", -1);

            	if ($::RUNCMD_RC != 0)
            	{
                	my $rsp;
                	push @{$rsp->{data}},
                  		"Could not remove $imagedefs{$img}{lpp_loc}/$file.\n";
                	if ($::VERBOSE)
                	{
                    	push @{$rsp->{data}}, "$output\n";
                	}
                	xCAT::MsgUtils->message("E", $rsp, $callback);
                	next;
            	}
        	}

			# remove tmp emgr files
        	foreach my $file (@emgr_files)
        	{
				my $rcmd;
				$rcmd = qq~rm -f $pkgdir/$file; rm -f /tmp/$file~;
            	my $output = xCAT::Utils->runcmd("$rcmd", -1);

            	if ($::RUNCMD_RC != 0)
            	{
                	my $rsp;
                	push @{$rsp->{data}},
                  	"Could not remove $imagedefs{$img}{lpp_loc}/$file.\n";
                	if ($::VERBOSE)
                	{
                    	push @{$rsp->{data}}, "$output\n";
                	}
                	xCAT::MsgUtils->message("E", $rsp, $callback);
                	next;
            	}
        	}

        	# unexport lpp dirs
        	my $ucmd = qq~exportfs -u -F $pkgdir~;
        	my $output = xCAT::Utils->runcmd("$ucmd", -1);
        	if ($::RUNCMD_RC != 0)
        	{
            	my $rsp;
            	push @{$rsp->{data}},
              		"Could not unexport $pkgdir.\n";
            	if ($::VERBOSE)
            	{
                	push @{$rsp->{data}}, "$output\n";
            	}
            	xCAT::MsgUtils->message("E", $rsp, $callback);
				$error++;
            	next;
        	}
    	}
	}

    if ($error)
    {
        my $rsp;
        push @{$rsp->{data}},
          "One or more errors occured while updating node software.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }
    else
    {
        my $rsp;
        push @{$rsp->{data}},
          "Cluster node software update commands have completed successfully.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }
    return 0;
}


#-------------------------------------------------------

=head3   updateOS

	Description	: Update the node operating system
    Arguments	: 
    Returns		: Nothing
    Example		: updateOS($callback, $nodes, $os);
    
=cut

#-------------------------------------------------------
sub updateOS {

	# Get inputs
	my ( $callback, $node, $os ) = @_;
	my $rsp; 
	
	# Get install directory
	my $installDIR = xCAT::Utils->getInstallDir();
		
	# Get HTTP server
	my $http = xCAT::Utils->my_ip_facing($node);
	if ( !$http ) {
		push @{$rsp->{data}}, "$node: (Error) Missing HTTP server";
		xCAT::MsgUtils->message("I", $rsp, $callback);
		return;
	}
		
	# Get OS to update to
	my $update2os = $os;
		
	push @{$rsp->{data}}, "$node: Upgrading $node to $os";
	xCAT::MsgUtils->message("I", $rsp, $callback);
	
	# Get the OS that is installed on the node
	my $arch = `ssh -o ConnectTimeout=5 $node "uname -m"`;
	chomp($arch);
	my $installOS;
	my $version;
	
	# Red Hat Linux
	if (`ssh -o ConnectTimeout=5 $node "test -f /etc/redhat-release && echo 'redhat'"`) {
		$installOS = "rh";
		chomp($version = `ssh $node "tr -d '.' < /etc/redhat-release" | head -n 1`);
		$version =~ s/[^0-9]*([0-9]+).*/$1/;
	}
	
	# SUSE Linux
	elsif (`ssh -o ConnectTimeout=5 $node "test -f /etc/SuSE-release && echo 'SuSE'"`) {
		$installOS = "sles";
		chomp($version = `ssh $node "tr -d '.' < /etc/SuSE-release" | head -n 1`);
		$version =~ s/[^0-9]*([0-9]+).*/$1/;
	} 
	
	# Everything else
	else {
		$installOS = "Unknown";
		
		push @{$rsp->{data}}, "$node: (Error) Linux distribution not supported";
		xCAT::MsgUtils->message("I", $rsp, $callback);
		return;
	}
			
	# Is the installed OS and the update to OS of the same distributor
	if (!($update2os =~ m/$installOS/i)) {
		push @{$rsp->{data}}, "$node: (Error) Cannot not update $installOS$version to $os.  Linux distribution does not match";
		xCAT::MsgUtils->message("I", $rsp, $callback);
		return;
	}
			
	# Setup the repository for the node
	my $path;
	my $out;
	if ( "$installOS$version" =~ m/sles10/i ) {		
		# SUSE repository path - http://10.1.100.1/install/sles10.3/s390x/1/
		$path = "http://$http$installDIR/$os/$arch/1/";
		if (!(-e "$installDIR/$os/$arch/1/")) {
			push @{$rsp->{data}}, "$node: (Error) Missing install directory $installDIR/$os/$arch/1/";
			xCAT::MsgUtils->message("I", $rsp, $callback);
			return;
		}

		# Add installation source using rug
		$out = `ssh $node "rug sa -t zypp $path $os"`;
		push @{$rsp->{data}}, "$node: $out";
		xCAT::MsgUtils->message("I", $rsp, $callback);

		# Subscribe to catalog
		$out = `ssh $node "rug sub $os"`;
		push @{$rsp->{data}}, "$node: $out";
		xCAT::MsgUtils->message("I", $rsp, $callback);

		# Refresh services
		$out = `ssh $node "rug ref"`;
		push @{$rsp->{data}}, "$node: $out";
		xCAT::MsgUtils->message("I", $rsp, $callback);

		# Update
		$out = `ssh $node "rug up -y"`;
		push @{$rsp->{data}}, "$node: $out";
		xCAT::MsgUtils->message("I", $rsp, $callback);
	}
	
	elsif ( "$installOS$version" =~ m/sles11/i ) {		
		# SUSE repository path - http://10.1.100.1/install/sles10.3/s390x/1/
		$path = "http://$http$installDIR/$os/$arch/1/";
		if (!(-e "$installDIR/$os/$arch/1/")) {
			push @{$rsp->{data}}, "$node: (Error) Missing install directory $installDIR/$os/$arch/1/";
			xCAT::MsgUtils->message("I", $rsp, $callback);
			return;
		}
		
		# Add installation source using zypper
		$out = `ssh $node "zypper ar $path $installOS$version"`;
		push @{$rsp->{data}}, "$node: $out";
		xCAT::MsgUtils->message("I", $rsp, $callback);
		
		# Refresh services
		$out = `ssh $node "zypper ref"`;
		push @{$rsp->{data}}, "$node: $out";
		xCAT::MsgUtils->message("I", $rsp, $callback);
		
		# Update
		$out = `ssh $node "zypper --non-interactive update --auto-agree-with-licenses"`;
		push @{$rsp->{data}}, "$node: $out";
		xCAT::MsgUtils->message("I", $rsp, $callback);
	}
	
	elsif ( "$installOS$version" =~ m/rh/i ) {		
		# Red Hat repository path - http://10.0.0.1/install/rhel5.4/s390x/Server/
		$path = "http://$http$installDIR/$os/$arch/Server/";
		if (!(-e "$installDIR/$os/$arch/Server/")) {
			push @{$rsp->{data}}, "$node: (Error) Missing install directory $installDIR/$os/$arch/Server/";
			xCAT::MsgUtils->message("I", $rsp, $callback);
			return;
		}
		
		# Create a yum repository file
		my $exist = `ssh $node "test -e /etc/yum.repos.d/$os.repo && echo 'File exists'"`;
		if (!$exist) {
			$out = `ssh $node "echo [$os] >> /etc/yum.repos.d/$os.repo"`;
			$out = `ssh $node "echo baseurl=$path >> /etc/yum.repos.d/$os.repo"`;
			$out = `ssh $node "echo enabled=1 >> /etc/yum.repos.d/$os.repo"`;
		}

		# Send over release key
		my $key = "$installDIR/$os/$arch/RPM-GPG-KEY-redhat-release";
		my $tmp = "/tmp/RPM-GPG-KEY-redhat-release";
		my $tgt = "root@" . $node;
		$out = `scp $key $tgt:$tmp`;

		# Import key
		$out = `ssh $node "rpm --import $tmp"`;

		# Upgrade
		$out = `ssh $node "yum -y upgrade"`;
		push @{$rsp->{data}}, "$node: $out";
		xCAT::MsgUtils->message("I", $rsp, $callback);
	}
	
	else {
		push @{$rsp->{data}}, "$node: (Error) Could not update operating system";
		xCAT::MsgUtils->message("I", $rsp, $callback);
	}

	return;
}

#-------------------------------------------------------------------------------

=head3   updatenodeappstat
    This subroutine is used to handle the messages reported by 
    HPCbootstatus postscript. Update appstatus node attribute.

    Arguments:
    Returns:
        0 - for success.
        1 - for error.

=cut

#-----------------------------------------------------------------------------
sub updatenodeappstat
{
    my $request  = shift;
    my $callback = shift;
    my @nodes    = ();
    my @args     = ();
    if (ref($request->{node}))
    {
        @nodes = @{$request->{node}};
    }
    else
    {
        if ($request->{node}) { @nodes = ($request->{node}); }
    }
    if (ref($request->{arg}))
    {
        @args = @{$request->{arg}};
    }
    else
    {
        @args = ($request->{arg});
    }

    if ((@nodes > 0) && (@args > 0))
    {
        # format: apps=status
        my $appstat = $args[0];
        my ($apps, $newstatus) = split(/=/,$appstat);

        xCAT::Utils->setAppStatus(\@nodes, $apps, $newstatus);

    }   
    
    return 0;
}

