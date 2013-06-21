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
use Storable qw(dclone);
use xCAT::TableUtils;
use xCAT::ServiceNodeUtils;
use xCAT::NetworkUtils;
use xCAT::InstUtils;
use xCAT::CFMUtils;
use xCAT::Postage;
use Getopt::Long;
use xCAT::GlobalDef;
use Sys::Hostname;
use File::Basename;
use xCAT::GlobalDef;
use xCAT_monitoring::monitorctrl;
use Socket;

use strict;
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
            updatenode           => "updatenode",
            updatenodestat       => "updatenode",
            updatemynodestat     => "updatenode",
            updatenodeappstat    => "updatenode",
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
    elsif ($command eq "updatemynodestat")
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
        return;
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
    elsif ($command eq "updatemynodestat")
    {
        delete $request
          ->{node}; #the restricted form of this command must be forbidden from specifying other nodes, only can set it's own value
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

    my $installdir = xCAT::TableUtils->getInstallDir();

    # subroutine to display the usage
    sub updatenode_usage
    {
        my $cb           = shift;
        my $rsp          = {};
        my $usage_string = xCAT::Usage->getUsage("updatenode");
        push @{$rsp->{data}}, $usage_string;

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
                    'A|updateallsw' => \$::ALLSW,
                    'c|cmdlineonly' => \$::CMDLINE,
                    'd=s'           => \$::ALTSRC,
                    'h|help'        => \$::HELP,
                    'v|version'     => \$::VERSION,
                    'V|verbose'     => \$::VERBOSE,
                    'F|sync'        => \$::FILESYNC,
                    'l|user:s'      => \$::USER,
                    'f|snsync'      => \$::SNFILESYNC,
                    'S|sw'          => \$::SWMAINTENANCE,
                    's|sn'          => \$::SETSERVER,
                    'P|scripts:s'   => \$::RERUNPS,
                    'k|security'    => \$::SECURITY,
                    'o|os:s'        => \$::OS,
                    'fanout=i'      => \$::fanout,

        )
      )
    {
        &updatenode_usage($callback);
        return;
    }

    # display the usage if -h or --help is specified
    if ($::HELP)
    {
        &updatenode_usage($callback);
        return;
    }

    # display the version statement if -v or --verison is specified
    if ($::VERSION)
    {
        my $rsp = {};
        $rsp->{data}->[0] = xCAT::Utils->Version();
        $callback->($rsp);
        return;
    }

    # -c must work with -S for AIX node
    if ($::CMDLINE && !$::SWMAINTENANCE)
    {
        my $rsp = {};
        $rsp->{data}->[0] =
          "If you specify the -c flag you must specify the -S flag";
        $callback->($rsp);
        return;
    }

    # -s must work with -P or -S or --security
    if ($::SETSERVER && !($::SWMAINTENANCE || $::RERUNPS || $::SECURITY))
    {
        my $rsp = {};
        $rsp->{data}->[0] =
          "If you specify the -s flag you must specify either the -S or -k or -P
 flags";
        $callback->($rsp);
        return;
    }

    # -f or -F not both
    if (($::FILESYNC) && ($::SNFILESYNC))
    {
        my $rsp = {};
        $rsp->{data}->[0] = "You can not specify both the -f and -F flags.";
        $callback->($rsp);
        return;
    }

    # --security cannot work with -S -P -F
    if ($::SECURITY
        && ($::SWMAINTENANCE || $::RERUNPS || defined($::RERUNPS)))
    {
        my $rsp = {};
        $rsp->{data}->[0] =
          "If you use the -k flag, you cannot specify the -S,-P or -F flags.";
        $callback->($rsp);
        return;
    }

    # the -P flag is omitted when only postscripts are specified,
    # so if there are parameters without any flags, it may mean
    # to re-run the postscripts. Except for the -k flag
    if (@ARGV)
    {

        # we have one or more operands on the cmd line
        if (
            $#ARGV == 0
            && !(
                    $::FILESYNC
                 || $::SNFILESYNC
                 || $::SWMAINTENANCE
                 || defined($::RERUNPS)
                 || $::SECURITY
            )
          )
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
        if (!($::SNFILESYNC))
        {

            # no flags and no operands, set defaults
            if (
                !(
                      $::FILESYNC
                   || $::SWMAINTENANCE
                   || defined($::RERUNPS)
                   || $::SECURITY
                )
              )
            {
                $::FILESYNC      = 1;
                $::SWMAINTENANCE = 1;
                $::RERUNPS       = "";
            }
        }
    }

    my $nodes = $request->{node};

    if (!$nodes)
    {
        my $rsp = {};
        $rsp->{data}->[0] =
          "A noderange is required for the updatenode command.";
        $callback->($rsp);
        return;
    }
    if ($::SECURITY)
    {

        # check to see if the Management Node is in the noderange and
        # if it is abort
        my $mname = xCAT::Utils->noderangecontainsMn(@$nodes);
        if ($mname)
        {    # MN in the nodelist
            my $rsp = {};
            $rsp->{error}->[0] =
              "You must not run -k option against the Management Node:$mname.";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            return;
        }

        # now build a list of all service nodes that are either in the
        # noderange or a service node of a node in the noderange
        # and update there ssh keys and credentials
        # get computenodes and servicenodes from the noderange
        my @SN;
        my @CN;
        xCAT::ServiceNodeUtils->getSNandCPnodes(\@$nodes, \@SN, \@CN);
        $::NODEOUT = ();
        &update_SN_security($request, $callback, $subreq, \@SN);

        # are there compute nodes, then we want to change the request to
        # just update the compute nodes
        if (scalar(@CN))
        {
            $request->{node}      = \@CN;
            $request->{noderange} = \@CN;
            $::RERUNPS            = "remoteshell";
        }
        else
        {    # no more nodes
            return;
        }

    }

    #
    # process @ARGV
    #

    # the first arg should be a noderange - the other should be attr=val
    #  - put attr=val operands in %attrvals hash

    my %attrvals;
    if ($::SWMAINTENANCE)
    {
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
                $attrvals{$attr} = $value;
            }
        }
    }

    my @nodes = @$nodes;
    my $postscripts;

    # Handle updating operating system
    if (defined($::OS))
    {
        my $reqcopy = {%$request};
        $reqcopy->{os}->[0] = "yes";
        push @requests, $reqcopy;

        return \@requests;
    }

    # handle the validity of postscripts
    # check to see if they exist except for the internal xCAT
    # postscripts-start-here,postbootscripts-start-here,
    # defaults-postbootscripts-start-here, osimage-postbootscripts-start-here,
    # etc
    if (defined($::RERUNPS))
    {
        if ($::RERUNPS eq "")
        {
            $postscripts = "";
        }
        else
        {
            $postscripts = $::RERUNPS;
            my @posts = split(',', $postscripts);
            if (!grep(/start-here/, @posts))
            {
                foreach (@posts)
                {
                    my @aa = split(' ', $_);
                    if (!-e "$installdir/postscripts/$aa[0]")
                    {
                        my $rsp = {};
                        $rsp->{data}->[0] =
                          "The postscript $installdir/postscripts/$aa[0] does not exist.";
                        $callback->($rsp);
                        return;
                    }
                }
            }
            else
            {

                # can only input one internal postscript  on call
                # updatenode -P defaults-postscripts-start-here
                my $arraySize = @posts;
                if ($arraySize > 1)
                {    # invalid
                    my $rsp = {};
                    $rsp->{data}->[0] =
                      "Only one internal postscript can be used with -P. Postscripts input were as follows:$postscripts";
                    $callback->($rsp);
                    return;
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
    if ($::SNFILESYNC)    # either sync service node
    {
        my $reqcopy = {%$request};
        $reqcopy->{SNFileSyncing}->[0] = "yes";
        push @requests, $reqcopy;
    }

    # If -F  or -f then,  call CFMUtils  to check if any PCM CFM data is to be
    # built for the node.   This will also create the synclists attribute in
    # the osimage for each node in the noderange
    if (($::FILESYNC) || ($::SNFILESYNC))
    {

        # determine the list of osimages names in the noderange to pass into
        # the CFMUtils
        my @imagenames = xCAT::TableUtils->getimagenames(\@nodes);

        # Now here we will call CFMUtils
        $::CALLBACK = $callback;
        my $rc = 0;
        $rc = xCAT::CFMUtils->updateCFMSynclistFile(\@imagenames);
        if ($rc != 0)
        {
            my $rsp = {};
            $rsp->{data}->[0] =
              "The call to CFMUtils to build synclist returned an errorcode=$rc.";
            $callback->($rsp);
            return;

        }
    }

    # if  not -S or -P or --security
    unless (defined($::SWMAINTENANCE) || defined($::RERUNPS) || $::SECURITY)
    {
        return \@requests;
    }

    #  - need to consider the mixed cluster case
    #		- can't depend on the os of the MN - need to split out the AIX nodes
    my ($rc, $AIXnodes, $Linuxnodes) = xCAT::InstUtils->getOSnodes($nodes);
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

    my $sn = xCAT::ServiceNodeUtils->get_ServiceNode(\@nodes, "xcat", "MN");
    if ($::ERROR_RC)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get list of xCAT service nodes.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return;

    }

    # Get the MN names
    my @MNip = xCAT::NetworkUtils->determinehostname;
    my @sns  = ();
    foreach my $s (keys %$sn)
    {
        my @tmp_a = split(',', $s);
        foreach my $s1 (@tmp_a)
        {
            if (!grep (/^$s1$/, @MNip))
            {
                push @sns, $s1;
            }
        }
    }

    # build each request for each node
    foreach my $snkey (keys %$sn)
    {


        # build request

        my $reqcopy = {%$request};
        $reqcopy->{node}                   = $sn->{$snkey};
        $reqcopy->{'_xcatdest'}            = $snkey;
        $reqcopy->{_xcatpreprocessed}->[0] = 1;

        if (defined($::SWMAINTENANCE))
        {
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
        if (defined($::RERUNPS))
        {
            $reqcopy->{rerunps}->[0] = "yes";
            $reqcopy->{postscripts} = [$postscripts];
            if (defined($::SECURITY))
            {
                $reqcopy->{rerunps4security}->[0] = "yes";
            }
        }

        if (defined($::SECURITY))
        {
            $reqcopy->{security}->[0] = "yes";
        }

        #
        # Handle updating OS
        #
        if (defined($::OS))
        {
            $reqcopy->{os}->[0] = "yes";
        }

        push @requests, $reqcopy;

    }
    return \@requests;
}

#-------------------------------------------------------------------------------

=head3  update_SN_security 

    process updatenode -k command 
    determine all the service nodes that must be processed from the
    input noderange and then update the ssh keys and credentials 

=cut

#-----------------------------------------------------------------------------
sub update_SN_security

{
    my $request      = shift;
    my $callback     = shift;
    my $subreq       = shift;
    my $servicenodes = shift;
    my @SN           = @$servicenodes;
    my $nodes        = $request->{node};
    my @nodes        = @$nodes;
    my $sn = xCAT::ServiceNodeUtils->get_ServiceNode(\@nodes, "xcat", "MN");

    if ($::ERROR_RC)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get list of xCAT service nodes.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return;

    }

    # take out the Management Node
    my @MNip = xCAT::NetworkUtils->determinehostname;
    my @sns  = ();
    foreach my $s (keys %$sn)
    {
        my @tmp_a = split(',', $s);
        foreach my $s1 (@tmp_a)
        {
            if (!grep (/^$s1$/, @MNip))
            {
                push @sns, $s1;
            }
        }
    }

    # now add any service nodes in the input noderange, we missed
    foreach my $sn (@SN)
    {
        if (!grep (/^$sn$/, @sns))
        {
            push @sns, $sn;
        }
    }

    # if we  have any service nodes to process
    if (scalar(@sns))
    {

        # setup the ssh keys on the service nodes
        # run the postscripts: remoteshell, servicenode
        # These are all servicenodes
        $::RERUNPS = "remoteshell,servicenode";

        my $req_rs = {%$request};
        my $ps;
        $ps                              = $::RERUNPS;
        $req_rs->{rerunps}->[0]          = "yes";
        $req_rs->{security}->[0]         = "yes";
        $req_rs->{rerunps4security}->[0] = "yes";
        $req_rs->{node}                  = \@sns;
        $req_rs->{noderange}             = \@sns;
        $req_rs->{postscripts}           = [$ps];
        updatenode($req_rs, $callback, $subreq);

        # parse the output of update security for sns
        foreach my $sn (keys %{$::NODEOUT})
        {
            if (!grep /^$sn$/, @sns)
            {
                next;
            }
            if (   (grep /ps ok/, @{$::NODEOUT->{$sn}})
                && (grep /ssh ok/, @{$::NODEOUT->{$sn}}))
            {
                push @::good_sns, $sn;
            }
        }

        if ($::VERBOSE)
        {
            my $rsp;
            push @{$rsp->{data}},
              "Update security for following service nodes: @sns.";
            push @{$rsp->{data}},
              "  Following service nodes have been updated successfully: @::good_sns";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }

    }
    return;
}

#-------------------------------------------------------------------------------

=head3  security_update_sshkeys 

    process updatenode -k command 
    the ssh keys on  the service nodes  and nodes
    by calling xdsh -K

=cut

#-----------------------------------------------------------------------------
sub security_update_sshkeys

{
    my $request       = shift;
    my $callback      = shift;
    my $subreq        = shift;
    my $nodes         = shift;
    my @nodes         = @$nodes;
    my $localhostname = hostname();

    # remove the host key from known_hosts
    xCAT::Utils->runxcmd(
                         {
                          command => ['makeknownhosts'],
                          node    => \@$nodes,
                          arg     => ['-r'],
                         },
                         $subreq, 0, 1
                         );

    if ($::VERBOSE)
    {
        my $rsp = {};
        $rsp->{data}->[0] =
          "  $localhostname: run makeknownhosts to clean known_hosts file for nodes: @$nodes";
        $callback->($rsp);
    }

    # call the xdsh -K to set up the ssh keys
    my @envs = @{$request->{environment}};
    my @args = ("-K");
    my $res  =
      xCAT::Utils->runxcmd(
                           {
                            command => ['xdsh'],
                            node    => \@$nodes,
                            arg     => \@args,
                            env     => \@envs,
                           },
                           $subreq, 0, 1
                           );

    if ($::VERBOSE)
    {
        my $rsp = {};
        # not display password in verbose mode.
        $rsp->{data}->[0] =
          "  $localhostname: Internal call command: xdsh -K. nodes = @$nodes, arguments = @args, env = xxxxxx";
        $rsp->{data}->[1] =
          "  $localhostname: return messages of last command: @$res";
        $callback->($rsp);
    }

    # parse the output of xdsh -K
    my @failednodes = @$nodes;
    foreach my $line (@$res)
    {
        chomp($line);
        if ($line =~ /SSH setup failed for the following nodes: (.*)\./)
        {
            @failednodes = split(/,/, $1);
        }
        elsif ($line =~ /setup is complete/)
        {
            @failednodes = ();
        }
    }

    my $rsp = {};
    foreach my $node (@$nodes)
    {
        if (grep /^$node$/, @failednodes)
        {
            push @{$rsp->{data}}, "$node: Setup ssh keys failed.";
        }
        else
        {
            push @{$rsp->{data}}, "$node: Setup ssh keys has completed.";
        }
    }
    $callback->($rsp);
    return;
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
    @::SUCCESSFULLNODES=();
    @::FAILEDNODES=();
    #print Dumper($request);
    my $nodes         = $request->{node};
    # $request->{status}= "yes";  for testing
    my $requeststatus;
    if (defined($request->{status})) {
       $requeststatus         = $request->{status};
    }
    my $localhostname = hostname();
    
    # if status return requested
    my $numberofnodes;
    # This is an internal call from another plugin requesting status
    # currently this is not displayed is only returned and not displayed
    # by updatenode. 
    if (defined($requeststatus) && ($requeststatus eq "yes")) {  
      $numberofnodes = @$nodes;
      my $rsp = {};
      $rsp->{status}->[0] = "TOTAL NODES: $numberofnodes";
      $callback->($rsp); 
    }
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
    my $installdir = xCAT::TableUtils->getInstallDir();

    #if the postscripts directory exists then make sure it is
    # world readable and executable by root
    my $postscripts = "$installdir/postscripts";
    if (-e $postscripts)
    {
        my $cmd = "chmod -R u+x,a+r $postscripts";
        xCAT::Utils->runcmd($cmd, 0);
        my $rsp = {};
        if ($::RUNCMD_RC != 0)
        {
            $rsp->{data}->[0] = "$cmd failed.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);

        }

    }

    #create each /tftpboot/mypostscript/mypostscript.<nodename> for each node
    # This first removes the old one if precreatemypostscripts =0 or undefined
    # call create files but no tmp files
    my $notmpfiles=1;
    my $nofiles=0;
    #my $nofiles=1;
    xCAT::Postage::create_mypostscript_or_not($request, $callback, $subreq,$notmpfiles,$nofiles);

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
                    'A|updateallsw' => \$::ALLSW,
                    'c|cmdlineonly' => \$::CMDLINE,
                    'd=s'           => \$::ALTSRC,
                    'h|help'        => \$::HELP,
                    'v|version'     => \$::VERSION,
                    'V|verbose'     => \$::VERBOSE,
                    'F|sync'        => \$::FILESYNC,
                    'l|user:s'      => \$::USER,
                    'f|snsync'      => \$::SNFILESYNC,
                    'S|sw'          => \$::SWMAINTENANCE,
                    's|sn'          => \$::SETSERVER,
                    'P|scripts:s'   => \$::RERUNPS,
                    'k|security'    => \$::SECURITY,
                    'o|os:s'        => \$::OS,
                    'fanout=i'      => \$::fanout,
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
    # if not just using the -k flag, then set all nodes to syncing in 
    # nodelist updatestatus  for the other updatenode options
    if (!($::SECURITY)) {
     my $stat="syncing";
     xCAT::TableUtils->setUpdateStatus(\@$nodes, $stat);
    }

    #
    #  handle file synchronization
    #
    if (($request->{FileSyncing} && $request->{FileSyncing}->[0] eq "yes")
        || (
            (   $request->{SNFileSyncing}
             && $request->{SNFileSyncing}->[0] eq "yes")))
    {
        &updatenodesyncfiles($request, $subreq, $callback);
    }

    if (scalar(@$AIXnodes))
    {
        if (xCAT::Utils->isLinux())
        {

            # mixed cluster enviornment, Linux MN=>AIX node
            # linux nfs client can not mount AIX nfs directory with default settings.
            # settting nfs_use_reserved_ports=1 could solve the problem
            my $cmd    = qq~nfso -o nfs_use_reserved_ports=1~;
            my $output =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $AIXnodes, $cmd,
                                    0);
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
        &updatenodesoftware($request, $subreq, $callback, $imgdefs, $updates);
    }

    #
    # handle of setting up ssh keys
    #

    if ($request->{security} && $request->{security}->[0] eq "yes")
    {

        # check to see if the Management Node is in the noderange and
        # if it is abort
        my $mname = xCAT::Utils->noderangecontainsMn(@$nodes);
        if ($mname)
        {    # MN in the nodelist
            my $rsp = {};
            $rsp->{error}->[0] =
              "You must not run -k option against the Management Node:$mname.";
            xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 1);
            return;
        }

        # setup the root ssh keys ( runs xdsh -k)

        &security_update_sshkeys($request, $callback, $subreq, \@$nodes);

    }

    #
    # handle the running of cust scripts
    #

    if ($request->{rerunps} && $request->{rerunps}->[0] eq "yes")
    {
        &updatenoderunps($request, $subreq, $callback);
    }

    #
    # Handle updating OS
    #
    if ($request->{os} && $request->{os}->[0] eq "yes")
    {
        my $os = $::OS;

        # Process ID for xfork()
        my $pid;

        # Child process IDs
        my @children;

        # Go through each node
        foreach my $node (@$nodes)
        {
            $pid = xCAT::Utils->xfork();

            # Parent process
            if ($pid)
            {
                push(@children, $pid);
            }

            # Child process
            elsif ($pid == 0)
            {

                # Update OS
                updateOS($callback, $node, $os);

                # Exit process
                exit(0);
            }
            else
            {

                # Ran out of resources
                die "Error: Could not fork\n";
            }
        }    # End of foreach

        # Wait for all processes to end
        foreach (@children)
        {
            waitpid($_, 0);
        }
    }

    # update the node status, this is done when -F -S -P are run
    # make sure the nodes only appear in one array good or bad 
    &cleanstatusarrays;  
	 if(@::SUCCESSFULLNODES)
	 {
	     
            my $stat="synced";
            xCAT::TableUtils->setUpdateStatus(\@::SUCCESSFULLNODES, $stat);
                      
	 }
	 if(@::FAILEDNODES)
	 {
	     
            my $stat="failed";
            xCAT::TableUtils->setUpdateStatus(\@::FAILEDNODES, $stat);
                      
	 }
    # internal call request for status, not output to CLI
    if (defined($requeststatus) && ($requeststatus eq "yes")) {  
       foreach my $n (@::SUCCESSFULLNODES) {
        my $rsp = {};
        $rsp->{status}->[0] = "$n: SUCCEEDED";
        $callback->($rsp); 
       }
       foreach my $n (@::FAILEDNODES) {
        my $rsp = {};
        $rsp->{status}->[0] = "$n: FAILED";
        $callback->($rsp); 
       }
      
       my $numberofgoodnodes = 0;
       my $numberofbadnodes = 0;
       $numberofgoodnodes = @::SUCCESSFULLNODES;
       $numberofbadnodes = @::FAILEDNODES;
       my $rsp = {};
        $rsp->{status}->[0] = "TOTAL NODES: $numberofnodes, SUCCEEDED: $numberofgoodnodes, FAILED: $numberofbadnodes";
        $callback->($rsp); 
    
    }
    #  if site.precreatemypostscripts = not 1 or yes or undefined,
    # remove all the
    # node files in the noderange in  /tftpboot/mypostscripts
     my $removeentries=0;
     my @entries = 
         xCAT::TableUtils->get_site_attribute("precreatemypostscripts");
     if ($entries[0] ) {  # not 1 or yes and defined
       $entries[0] =~ tr/a-z/A-Z/;
       if ($entries[0] !~ /^(1|YES)$/ ) {
         $removeentries=1; 
       }
     } else {  # or not defined
         $removeentries=1; 
     }
 
     if ($removeentries ==1) { 
         my $tftpdir = xCAT::TableUtils::getTftpDir();
         foreach my $n (@$nodes ) {
               unlink("$tftpdir/mypostscripts/mypostscript.$n");
         }
     }

    return 0;
}

#-------------------------------------------------------------------------------

=head3  updatenoderunps  - run postscripts or the updatenode -P option 

    Arguments: request
    Returns:
        0 - for success.
        1 - for error.

=cut

#-----------------------------------------------------------------------------
sub updatenoderunps

{
    my $request       = shift;
    my $subreq        = shift;
    my $callback      = shift;
    my $nodes         = $request->{node};
    my $localhostname = hostname();
    my $installdir    = xCAT::TableUtils->getInstallDir();
    my $tftpdir       = xCAT::TableUtils->getTftpDir();
    my $postscripts      = "";
    my $orig_postscripts = "";
    # For AIX nodes check NFS
    my $nfsv4;
    my @nfsv4 =
      xCAT::TableUtils->get_site_attribute("useNFSv4onAIX");
      if ($nfsv4[0] && ($nfsv4[0] =~ /1|Yes|yes|YES|Y|y/)) {
         $nfsv4 = "yes";
      } else {
         $nfsv4 = "no";
      }
        

      if (($request->{postscripts}) && ($request->{postscripts}->[0]))
      {
        $orig_postscripts = $request->{postscripts}->[0];
      }
        $postscripts = $orig_postscripts;

        my $cmd;

        # get server names as known by the nodes
        my %servernodes =
          %{xCAT::InstUtils->get_server_nodes($callback, \@$nodes)};

        # it's possible that the nodes could have diff server names
        # do all the nodes for a particular server at once

        foreach my $snkey (keys %servernodes)
        {
            my $nodestring = join(',', @{$servernodes{$snkey}});
            my $args;
            my $mode;

            #now build the actual updatenode command
           
            if (   $request->{rerunps4security}
                && $request->{rerunps4security}->[0] eq "yes")
            {

                # for updatenode --security
                $mode = "5";
            }
            else
            {

                # for updatenode -P
                $mode = "1";
            }
            my $args1;
            # Note order of parameters to xcatdsklspost 
            #is important and cannot be changed
            my $runpscmd;
            if ($::SETSERVER){
               $runpscmd  =
                    "$installdir/postscripts/xcatdsklspost $mode -M $snkey '$postscripts' --tftp $tftpdir --installdir $installdir --nfsv4 $nfsv4 -c";
            } else {
               $runpscmd  =
                    "$installdir/postscripts/xcatdsklspost $mode -m $snkey '$postscripts' --tftp $tftpdir --installdir $installdir --nfsv4 $nfsv4 -c"
            }
            push @$args1,"--nodestatus"; # return nodestatus
            if (defined($::fanout))  {  # fanout
             push @$args1,"-f" ;
             push @$args1,$::fanout;
            }
            if (defined($::USER))  {  # -l contains sudo user
             push @$args1,"--sudo" ;
             push @$args1,"-l" ;
             push @$args1,"$::USER" ;
            }
            push @$args1,"-s";  # streaming
            push @$args1,"-v";  # streaming
            push @$args1,"-e";  # execute 
            push @$args1,"$runpscmd"; # the command 


            if ($::VERBOSE)
            {
                my $rsp = {};
                $rsp->{data}->[0] =
                  "  $localhostname: Internal call command: xdsh $nodestring "
                  . join(' ', @$args1);
                $callback->($rsp);
            }

            $CALLBACK = $callback;
            if ($request->{rerunps4security})
            {
                $RERUNPS4SECURITY = $request->{rerunps4security}->[0];
            }
            else
            {
                $RERUNPS4SECURITY = "";
            }
            $subreq->(
                      {
                       command           => ["xdsh"],
                       node              => $servernodes{$snkey},
                       arg               => $args1,
                       _xcatpreprocessed => [1]
                      },
                      \&getdata
                      );
        }


    if (   $request->{rerunps4security}
        && $request->{rerunps4security}->[0] eq "yes")
    {

        # clean the know_hosts
        xCAT::Utils->runxcmd(
                             {
                              command => ['makeknownhosts'],
                              node    => \@$nodes,
                              arg     => ['-r'],
                             },
                             $subreq, 0, 1
                             );
    }

    return;
}

#-------------------------------------------------------------------------------

=head3  updatenodesyncfiles  - performs node rsync  updatenode -F

    Arguments: request
    Returns:
        0 - for success.
        1 - for error.

=cut

#-----------------------------------------------------------------------------
sub updatenodesyncfiles
{
    my $request            = shift;
    my $subreq             = shift;
    my $callback           = shift;
    my $nodes              = $request->{node};
    my $localhostname      = hostname();
    my %syncfile_node      = ();
    my %syncfile_rootimage = ();
    my $node_syncfile      = xCAT::SvrUtils->getsynclistfile($nodes);
    foreach my $node (@$nodes)
    {
        my $synclist = $$node_syncfile{$node};

        if ($synclist)
        {
        
            # this can be a comma separated list of multiple
            # syncfiles
            my @sl = split(',', $synclist);
            foreach my $s (@sl)
            {
                push @{$syncfile_node{$s}}, $node;
            }
        }
    }

    my $numberofsynclists=0; 
    # Check the existence of the synclist file
    if (%syncfile_node)
    {    # there are files to sync defined
        foreach my $synclist (keys %syncfile_node)
        {
            if (!(-r $synclist))
            {
                my $rsp = {};
                $rsp->{data}->[0] =
                  "The Synclist file $synclist which specified for certain node does NOT existed.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
        }

        # Sync files to the target nodes
        my $output; 
        foreach my $synclist (keys %syncfile_node)
        {
            $numberofsynclists++; 
            my $args;
            my $env;
            if ($request->{FileSyncing}->[0] ne "yes") {  # sync SN only
              push @$args,"-s" ;
              $env = ["DSH_RSYNC_FILE=$synclist", "RSYNCSNONLY=1"];
            } else {
              $env = ["DSH_RSYNC_FILE=$synclist"];
            }
            push @$args,"--nodestatus" ;
            if (defined($::fanout))  {  # fanout
             push @$args,"-f" ;
             push @$args,$::fanout;
            }
            if (defined($::USER))  {  # -l must sudo
             push @$args,"--sudo" ;
             push @$args,"-l" ;
             push @$args,"$::USER" ;
            }
            push @$args,"-F" ;
            push @$args,"$synclist" ;
            my $nodestring = join(',', @{$syncfile_node{$synclist}});

            if ($::VERBOSE)
            {
                my $rsp = {};
                $rsp->{data}->[0] =
                  "  $localhostname: Internal call command: xdcp $nodestring " . join(' ', @$args);
                $callback->($rsp);
            }

            $CALLBACK = $callback;


           $output =
             xCAT::Utils->runxcmd(
                   {
                     command => ["xdcp"],
                     node    => $syncfile_node{$synclist},
                     arg     => $args,
                     env     => $env
                   },
                   $subreq, -1,1);

           # build the list of good and bad nodes
           &buildnodestatus(\@$output,$callback);
	     }
   	
       my $rsp = {};
       $rsp->{data}->[0] = "File synchronization has completed.";
       $callback->($rsp);
    }
    else
    {    # no syncfiles defined
        my $rsp = {};
        $rsp->{data}->[0] =
          "There were no syncfiles defined to process. File synchronization has completed.";
        $callback->($rsp);
        my $stat="synced";
        xCAT::TableUtils->setUpdateStatus(\@$nodes, $stat);

    }

    return;
}
#-------------------------------------------------------------------------------
=head3  buildnodestatus - Takes the output of the updatenode run
        and builds a global array of successfull nodes  and one of failed nodes
        and then outputs the remaining user info

    Arguments: output,callback
    Globals @::SUCCESSFULLNODES,  @::FAILEDNODES

=cut


#-----------------------------------------------------------------------------
sub buildnodestatus
{
    my $output       = shift;
    my $callback      = shift;
    my @userinfo=();
    # determine if the sync was successful or not
	 foreach my $line (@$output) {
	   if($line =~ /^\s*(\S+)\s*:\s*Remote_command_successful/)
	   {
         my ($node,$info) = split (/:/, $line);
		   push(@::SUCCESSFULLNODES,$node);
	   }
      elsif($line =~ /^\s*(\S+)\s*:\s*Remote_command_failed/)
	   {
         my ($node,$info)= split (/:/, $line);
	      push(@::FAILEDNODES,$node);
	   }	
      else  
	   {
	      push(@userinfo,$line);   # user data
	   }	
	 }
    # output user data 
    if (@userinfo) {
        foreach my $line (@userinfo) {
           my $rsp = {};
           $rsp->{data}->[0] = $line;
           $callback->($rsp);
	     }
	 }

  return;
}
#-------------------------------------------------------------------------------
=head3  cleanstatusarrays
    Makes sure no Failed nodes are in the successfull nodes list
    Removes dups
    Globals @::SUCCESSFULLNODES,  @::FAILEDNODES

=cut


#-----------------------------------------------------------------------------
sub cleanstatusarrays 
{
    my %m=();
    my %n=();

    for(@::FAILEDNODES)
    {
       $m{$_}++;
    }
    for(@::SUCCESSFULLNODES)
    {
        $m{$_}++ || $n{$_}++;
    }
    @::SUCCESSFULLNODES=keys %n;
  return;
}
#-------------------------------------------------------------------------------

=head3  updatenodesoftware  - software updates  updatenode -S

    Arguments: request, subreq,callback,imgdefs,updates
    Returns:
        0 - for success.
        1 - for error.

=cut

#-----------------------------------------------------------------------------
sub updatenodesoftware
{
    my $request       = shift;
    my $subreq        = shift;
    my $callback      = shift;
    my $imgdefs       = shift;
    my $updates       = shift;
    my $nodes         = $request->{node};
    my $installdir    = xCAT::TableUtils->getInstallDir();
    my $tftpdir       = xCAT::TableUtils->getTftpDir();
    my $localhostname = hostname();
    my $rsp;
    $CALLBACK = $callback;
    push @{$rsp->{data}},
      "Performing software maintenance operations. This could take a while, if there are packages to install.\n";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    my ($rc, $AIXnodes_nd, $Linuxnodes_nd) =
      xCAT::InstUtils->getOSnodes($nodes);

    #
    #   do linux nodes
    #
    if (scalar(@$Linuxnodes_nd))
    {    # we have a list of linux nodes
        my $cmd;

        # get server names as known by the nodes
        my %servernodes =
          %{xCAT::InstUtils->get_server_nodes($callback, \@$Linuxnodes_nd)};

        # it's possible that the nodes could have diff server names
        # do all the nodes for a particular server at once
        foreach my $snkey (keys %servernodes)
        {
            my $nodestring = join(',', @{$servernodes{$snkey}});
            my $cmd;
            my $args1;
            if ($::SETSERVER)
            {
               $cmd =
                  "$installdir/postscripts/xcatdsklspost 2 -M $snkey 'ospkgs,otherpkgs' --tftp $tftpdir" ;



            }
            else
            {
                $cmd =
                  "$installdir/postscripts/xcatdsklspost 2 -m $snkey 'ospkgs,otherpkgs' --tftp $tftpdir";
            }
    
            # build xdsh command
            push @$args1,"--nodestatus"; # return nodestatus
            if (defined($::fanout))  {  # fanout
             push @$args1,"-f" ;
             push @$args1,$::fanout;
            }
            if (defined($::USER))  {  # -l contains sudo user
             push @$args1,"--sudo" ;
             push @$args1,"-l" ;
             push @$args1,"$::USER" ;
            }
            push @$args1,"-s";  # streaming
            push @$args1,"-v";  # streaming
            push @$args1,"-e";  # execute 
            push @$args1,"$cmd"; # the command 



            if ($::VERBOSE)
            {
                my $rsp = {};
                $rsp->{data}->[0] =
                  "  $localhostname: Internal call command: xdsh $nodestring "
                  . join(' ', @$args1);
                $callback->($rsp);
            }
            $subreq->(
                      {
                       command           => ["xdsh"],
                       node              => $servernodes{$snkey},
                       arg               => $args1,
                       _xcatpreprocessed => [1]
                      },
                      \&getdata2
                      );


        }

    }

    #
    #   do AIX nodes
    #

    if (scalar(@$AIXnodes_nd))
    {

        # update the software on an AIX node
        if (
            &updateAIXsoftware(
                               $callback, \%::attrres,  $imgdefs,
                               $updates,  $AIXnodes_nd, $subreq
            ) != 0
          )
        {

            #		my $rsp;
            #		push @{$rsp->{data}},  "Could not update software for AIX nodes \'@$AIXnodes\'.";
            #		xCAT::MsgUtils->message("E", $rsp, $callback);;
            return 1;
        }
    }

    return;
}
#-------------------------------------------------------------------------------

=head3  getdata  - This is the local callback that handles the response from
        the xdsh streaming calls when running postscripts

=cut
#-------------------------------------------------------------------------------
sub getdata
{
    no strict;
    my $response = shift;
    my $rsp;
    foreach my $type (keys %$response)
    {
        foreach my $output (@{$response->{$type}})
        {
            chomp($output);
            $output =~ s/\\cM//;
            if($output =~ /^\s*(\S+)\s*:\s*Remote_command_successful/)
            {
              my ($node,$info) = split (/:/, $output);
              push(@::SUCCESSFULLNODES,$node);
            }
            if($output =~ /^\s*(\S+)\s*:\s*Remote_command_failed/)
            {
              my ($node,$info) = split (/:/, $output);
              push(@::FAILEDNODES,$node);
            }


            if ($output =~ /returned from postscript/)
            {
                $output =~
                  s/returned from postscript/Running of postscripts has completed./;
            }
            if ($RERUNPS4SECURITY && $RERUNPS4SECURITY eq "yes")
            {
                if ($output =~ /Running of postscripts has completed/)
                {
                    $output =~
                      s/Running of postscripts has completed/Redeliver security files has completed/;
                    push @{$rsp->{$type}}, $output;
                }
                elsif ($output !~ /Running postscript|Error loading module/)
                {
                    push @{$rsp->{$type}}, "$output";
                }
            } else{  # for non -k option then get the rest of the output
              if (($output !~ (/Error loading module/)) && ($output !~ /^\s*(\S+)\s*:\s*Remote_command_successful/) && ($output !~ /^\s*(\S+)\s*:\s*Remote_command_failed/))
              {
                push @{$rsp->{$type}}, "$output";
              }
            }
        }
    }
    $CALLBACK->($rsp);
}
#-------------------------------------------------------------------------------

=head3  getdata2  - This is the local callback that handles the response from
        the xdsh streaming calls when running software updates 

=cut
#-------------------------------------------------------------------------------
sub getdata2
{
    no strict;
    my $response = shift;
    my $rsp;
    foreach my $type (keys %$response)
    {
        my $alreadyinstalled=0;
        foreach my $output (@{$response->{$type}})
        {
            chomp($output);
            $output =~ s/\\cM//;
            if($output =~ /^\s*(\S+)\s*:\s*Remote_command_successful/)
            {
              my ($node,$info) = split (/:/, $output);
              push(@::SUCCESSFULLNODES,$node);
            }
            # check for already installed, this is not an error
            if($output =~ /^\s*(\S+)\s*:\s*already installed/)
            {
              $alreadyinstalled = 1; 
            }
            if($output =~ /^\s*(\S+)\s*:\s*Remote_command_failed/)
            {
              if ($alreadyinstalled == 0) { # not an already install error 
                my ($node,$info) = split (/:/, $output);
                push(@::FAILEDNODES,$node);
              } 
            }


            if ($output =~ /returned from postscript/)
            {
                $output =~
                   s/returned from postscript/Running of Software Maintenance has completed./;

            }
            if (($output !~ /^\s*(\S+)\s*:\s*Remote_command_successful/) && ($output !~ /^\s*(\S+)\s*:\s*Remote_command_failed/))
            {
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
        else
        {    #client asking to update its own status...
            unless (ref $request->{username})
            {
                return;
            }    #TODO: log an attempt without credentials?
            @nodes = @{$request->{username}};
        }
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
        unless ($::VALID_STATUS_VALUES{$stat})
        {
            return;
        }    #don't accept just any string, see GlobalDef for updates
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
    if (defined($::USER)){ # not supported on AIX
     		my $rsp;
         $rsp->{error}->[0] = " The -l option is not supported on AIX";
     		xCAT::MsgUtils->message("E", $rsp, $callback);;
         return 1;
    } 

    # get the NIM primary server name
    my $nimprime = xCAT::InstUtils->getnimprime();
    chomp $nimprime;

    my %nodeupdateinfo;

    #
    # do we have to copy files to any SNs????
    #

    # get a list of service nodes for this node list
    my $sn = xCAT::ServiceNodeUtils->get_ServiceNode(\@nodelist, "xcat", "MN");
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

        if (!$imgname)
        {
            push @noimage, $node;
        }
        elsif (!grep(/^$imgname$/, @imagenames))
        {
            push @imagenames, $imgname;
        }
        $nodeupdateinfo{$node}{imagename} = $imgname;
    }
    $nodetab->close;

    if (@noimage)
    {
        my $rsp;
        my $allnodes = join(',', @noimage);
        push @{$rsp->{data}},
          "No osimage specified for the following nodes: $allnodes. You can try to run the nimnodeset command or set the profile|provmethod attributes manually.";
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
        if ($::ALTSRC)
        {
            $imagedef{$img}{alt_loc} = $::ALTSRC;
        }
        else
        {
            if ($imagedef{$img}{lpp_source})
            {
                $imagedef{$img}{lpp_loc} =
                  xCAT::InstUtils->get_nim_attr_val($imagedef{$img}{lpp_source},
                                     'location', $callback, $nimprime, $subreq);
            }
            else
            {
                $imagedef{$img}{lpp_loc} = "";
                next;
            }
        }

        if ($::ALLSW)
        {

            # get a list of all the files in the location
            # if its an alternate loc than just check that dir
            # if it's an lpp_source than check both RPM and installp
            my $rpmloc;
            my $instploc;
            my $emgrloc;
            if ($::ALTSRC)
            {

                # use same loc for everything
                $rpmloc = $instploc = $imagedef{$img}{alt_loc};
            }
            else
            {

                # use specific lpp_source loc
                $rpmloc   = "$imagedef{$img}{lpp_loc}/RPMS/ppc";
                $instploc = "$imagedef{$img}{lpp_loc}/installp/ppc";
                $emgrloc  = "$imagedef{$img}{lpp_loc}/emgr/ppc";
            }

            # get installp filesets in this dir
            my $icmd =
              qq~installp -L -d $instploc | /usr/bin/cut -f1 -d':' 2>/dev/null~;
            my @ilist = xCAT::Utils->runcmd("$icmd", -1);
            foreach my $f (@ilist)
            {
                if (!grep(/^$f$/, @pkglist))
                {
                    push(@pkglist, $f);
                }
            }

            # get epkg files
            my $ecmd = qq~/usr/bin/ls $emgrloc 2>/dev/null~;
            my @elist = xCAT::Utils->runcmd("$ecmd", -1);
            foreach my $f (@elist)
            {
                if (($f =~ /epkg\.Z/))
                {
                    push(@pkglist, $f);
                }
            }

            # get rpm packages
            my $rcmd = qq~/usr/bin/ls $rpmloc 2>/dev/null~;
            my @rlist = xCAT::Utils->runcmd("$rcmd", -1);
            foreach my $f (@rlist)
            {
                if ($f =~ /\.rpm/)
                {
                    push(@pkglist, $f);
                }
            }
        }
        else
        {

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
                    my ($rc, $list, $loc) =
                      xCAT::InstUtils->readBNDfile($callback, $bnd, $nimprime,
                                                   $subreq);
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
            if (!$::ALTSRC)
            {

                # if lpp_source is not defined on SN then next
                my $scmd =
                  qq~/usr/sbin/lsnim -l $imagedef{$img}{lpp_source} 2>/dev/null~;
                my $out =
                  xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $snkey,
                                        $scmd, 0);

                if ($::RUNCMD_RC != 0)
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "The NIM lpp_source resource named $imagedef{$img}{lpp_source} is not defined on $snkey. Cannot copy software to $snkey.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                }
            }

            # get the dir names to copy to
            my $srcdir;
            if ($::ALTSRC)
            {
                $srcdir = "$imagedef{$img}{alt_loc}";
            }
            else
            {
                $srcdir = "$imagedef{$img}{lpp_loc}";
            }
            my $dir = dirname($srcdir);

            if ($::VERBOSE)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Copying $srcdir to $dir on service node $snkey.\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }

            # make sure the dir exists on the service node
            #  also make sure it's writeable by all
            my $mkcmd  = qq~/usr/bin/mkdir -p $dir~;
            my $output =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $snkey, $mkcmd,
                                    0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not create directories on $snkey.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$output\n";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                next;
            }

            # sync source files to SN
            my $cpcmd =
              qq~$::XCATROOT/bin/prsync -o "rlHpEAogDz" $srcdir $snkey:$dir 2>/dev/null~;
            $output =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime,
                                    $cpcmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not copy $srcdir to $dir for service node $snkey.\n";
                push @{$rsp->{data}}, "Output from command: \n\n$output\n\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return (1);
            }

            # run inutoc in remote installp dir
            my $installpsrcdir;
            if ($::ALTSRC)
            {
                $installpsrcdir = $srcdir;
            }
            else
            {
                $installpsrcdir = "$srcdir/installp/ppc";
            }
            my $icmd   = qq~cd $installpsrcdir; /usr/sbin/inutoc .~;
            my $output =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $snkey, $icmd,
                                    0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not run inutoc for $installpsrcdir on $snkey\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
            }
        }    # end for each osimage
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

    # get the server name for each node - as known by the node
    my $noderestab  = xCAT::Table->new('noderes');
    my $xcatmasters =
      $noderestab->getNodesAttribs(\@noderange, ['node', 'xcatmaster']);

    # get the NIM primary server name
    my $nimprime = xCAT::InstUtils->getnimprime();
    chomp $nimprime;

	#
	# get a list of servers and a hash of the servers name for each node
	#
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
			# if it's not the xcatmaster then default to the NIM primary
            $server{$node} = $nimprime;
        }

        if (!grep($server{$node}, @servers))
        {
            push(@servers, $server{$node});
        }
    }
    $noderestab->close;

	#  need to sort nodes by osimage AND server 
	#	- each aixswupdate call should go to all nodes with the same server
	#		and osimage

	my %nodeoslist;
	foreach my $node (@noderange) {
		my $server = $server{$node};
		my $osimage = $nodeupdateinfo{$node}{imagename};
		push(@{$nodeoslist{$server}{$osimage}}, $node);
	}

    my $error = 0;

	# process nodes - all that have same serv and osimage go at once
	foreach my $serv (keys %nodeoslist) {   # for each server

		foreach my $img (keys %{$nodeoslist{$serv}} ) { # for each osimage

			my @nodes = @{$nodeoslist{$serv}{$img}};
			if ( !scalar(@nodes)){
                next;
            }

        	# set the location of the software
        	my $pkgdir = "";
        	if ($::ALTSRC)
        	{
            	$pkgdir = $::ALTSRC;
        	}
        	else
        	{
            	$pkgdir = $imagedefs{$img}{lpp_loc};
        	}

			# check for pkg dir
			if ( ! -d $pkgdir ) {
				my $rsp;
				push @{$rsp->{data}}, "The source directory $pkgdir does not exist.\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
				$error++;
				next;
			}

			# create a file in the pkgdir and add the pkg list to it
			#  the pkgdir is mounted and the pkglist file will be available 
			#	on the node.
			#
			# create a unique name
			my $thisdate = `date +%s`;
			my $pkglist_file_name = qq~pkglist_file.$thisdate~;			
           	chomp $pkglist_file_name;

			@pkglist = split(/,/, $imagedefs{$img}{pkglist});

           	if (!scalar(@pkglist))
           	{
				my $rsp;
				push @{$rsp->{data}}, "There is no list of packages for nodes: @nodes.\n";		
				xCAT::MsgUtils->message("E", $rsp, $callback);
				$error++;
				next;
			}
			
            #  make sure the permissions are correct on pkgdir
            # - we are running on MN
            my $chmcmd = qq~/bin/chmod -R +r $pkgdir~;
            my @result = xCAT::Utils->runcmd("$chmcmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}},
                    "Could not set permissions for $pkgdir.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
				$error++;
				next;
            }

			# create a pkglist file in the pkgdir on MN
			my $pkglist_file= qq~$pkgdir/$pkglist_file_name~;

           	if (!open(PKGLISTFILE, ">$pkglist_file"))
           	{
               	my $rsp;
               	push @{$rsp->{data}}, "Could not open $pkglist_file_name.\n";
               	xCAT::MsgUtils->message("E", $rsp, $callback);
				$error++;
				next;
			}
			else
           	{
               	foreach (@pkglist)
               	{
                   	print PKGLISTFILE $_ . "\n";
               	}
               	close(PKGLISTFILE);
			}

# ndebug
# ??? has the whole pkgdir been copied to the SN yet???

			if (!xCAT::InstUtils->is_me($serv)) {
				# cp file to SN 
				# has pkgdir already been copied.             
				my $rcpcmd = "$::XCATROOT/bin/xdcp $serv $pkglist_file $pkgdir ";
				my $output = xCAT::Utils->runcmd("$rcpcmd", -1);
				if ($::RUNCMD_RC != 0)
				{
					my $rsp;
					push @{$rsp->{data}}, "Could not copy $pkglist_file to $serv.\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
					$error++;
					next;
				}
			}

			# export the pkgdir on the server
			my $ecmd;
			my @nfsv4 = xCAT::TableUtils->get_site_attribute("useNFSv4onAIX");
			if ($nfsv4[0] && ($nfsv4[0] =~ /1|Yes|yes|YES|Y|y/))
			{
				$ecmd = qq~exportfs -i -o vers=4 $pkgdir~;
			}
			else
			{
				$ecmd = qq~exportfs -i $pkgdir~;
			}

			if (!xCAT::InstUtils->is_me($serv)) {
				my $output = xCAT::Utils->runxcmd(
					{
						command => ["xdsh"],
						node    => [$serv],	
						arg     => [$ecmd]
					},
					$subreq, -1, 1
					);
				if ($::RUNCMD_RC != 0)
				{
					my $rsp;
					push @{$rsp->{data}}, "Could not export $pkgdir on $serv.\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
					$error++;
                    next;
				}
			} else {
				my $output = xCAT::Utils->runcmd("$ecmd", -1);
				if ($::RUNCMD_RC != 0)
				{
					my $rsp;
					push @{$rsp->{data}}, "Could not export $pkgdir on $serv.\n";
					push @{$rsp->{data}}, "$output\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
					$error++;
					next;
				}
			}

			#
           	# call aixswupdate to install sw on the nodes
           	#

			# put together the cmd string
           	my $installcmd = qq~/install/postscripts/aixswupdate -f $pkglist_file ~;

			# $serv is the name of the nodes server as known by the node
			$installcmd .= qq~ -s $serv ~;
		
			if ($::ALLSW) {
				$installcmd .= qq~ -a ~;
			}

			if ($::ALTSRC) {
				$installcmd .= qq~ -d ~;
			}

			if ($::NFSV4) {
				$installcmd .= qq~ -n ~;
			}

			# add installp flags
			if ( $imagedefs{$img}{installp_flags} ) {
				$installcmd .= qq~ -i $imagedefs{$img}{installp_flags} ~;
			}
			# add rpm flags
			if ( $imagedefs{$img}{rpm_flags} ) {
               	$installcmd .= qq~ -r $imagedefs{$img}{rpm_flags} ~;
           	}
			# add emgr flags
           	if ( $imagedefs{$img}{emgr_flags} ) {
               	$installcmd .= qq~ -e $imagedefs{$img}{emgr_flags} ~;
           	}

			my $args1;
			push @$args1,"--nodestatus";
			push @$args1,"-s";
			push @$args1,"-v";
			push @$args1,"-e";
			if (defined($::fanout))  {  # fanout input
				push @$args1,"-f" ;
				push @$args1,$::fanout;
			}
			push @$args1,"$installcmd";

			$subreq->(
				{
					command           => ["xdsh"],
					node              => \@nodes,
					arg               => $args1,
					_xcatpreprocessed => [1]
				},
				\&getdata2
				);

			# remove pkglist_file from MN - local
			my $rcmd = qq~/bin/rm -f $pkglist_file~;
            my $output = xCAT::Utils->runcmd("$rcmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not remove $pkglist_file.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
            }


			# if not $serv then remove pkglist_file from $serv
			if (!xCAT::InstUtils->is_me($serv)) {
				my $output = xCAT::Utils->runxcmd(
                      	{
                       		command => ["xdsh"],
                       		node    => [$serv],
                          	arg     => [$rcmd]
                       	},
                       	$subreq, -1, 1
                        );
				if ($::RUNCMD_RC != 0)
				{
					my $rsp;
					push @{$rsp->{data}}, "Could not remove $pkglist_file on $serv.\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
					$error++;
				}
			}

			# unexport pkgdir
			my $ucmd = qq~exportfs -u -F $pkgdir~;
			if (xCAT::InstUtils->is_me($serv)) {
                my $ucmd = qq~exportfs -u -F $pkgdir~;
                my $output = xCAT::Utils->runcmd("$ucmd", -1);
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp;
                    push @{$rsp->{data}}, "Could not unexport $pkgdir.\n";
                    if ($::VERBOSE)
                    {
                        push @{$rsp->{data}}, "$output\n";
                	}
                	xCAT::MsgUtils->message("E", $rsp, $callback);
					$error++;
				}
			} else {
				# unexport dirs on SNs
				my $output = xCAT::Utils->runxcmd(
                        {
                            command => ["xdsh"],
                            node    => [$serv],
                            arg     => [$ucmd]
                        },
                        $subreq, -1, 1
                        );
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp;
                    push @{$rsp->{data}}, "Could not unexport $pkgdir on $serv.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
					$error++;
                }
			}
		} # for each osimage
	} # for each server 

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
          "Cluster node software update commands have completed.\n";
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
sub updateOS
{

    # Get inputs
    my ($callback, $node, $os) = @_;
    my $rsp;

    # Get install directory
    my $installDIR = xCAT::TableUtils->getInstallDir();

    # Get HTTP server
    my $http = xCAT::NetworkUtils->my_ip_facing($node);
    if (!$http)
    {
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
    if (
        `ssh -o ConnectTimeout=5 $node "test -f /etc/redhat-release && echo 'redhat'"`
      )
    {
        $installOS = "rh";
        chomp($version =
              `ssh $node "tr -d '.' < /etc/redhat-release" | head -n 1`);
        $version =~ s/[^0-9]*([0-9]+).*/$1/;
    }

    # SUSE Linux
    elsif (
        `ssh -o ConnectTimeout=5 $node "test -f /etc/SuSE-release && echo 'SuSE'"`
      )
    {
        $installOS = "sles";
        chomp($version =
              `ssh $node "tr -d '.' < /etc/SuSE-release" | head -n 1`);
        $version =~ s/[^0-9]*([0-9]+).*/$1/;
    }

    # Everything else
    else
    {
        $installOS = "Unknown";

        push @{$rsp->{data}}, "$node: (Error) Linux distribution not supported";
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return;
    }

    # Is the installed OS and the update to OS of the same distributor
    if (!($update2os =~ m/$installOS/i))
    {
        push @{$rsp->{data}},
          "$node: (Error) Cannot not update $installOS$version to $os.  Linux distribution does not match";
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return;
    }

    # Setup the repository for the node
    my $path;
    my $out;
    if ("$installOS$version" =~ m/sles10/i)
    {

        # SUSE repository path - http://10.1.100.1/install/sles10.3/s390x/1/
        $path = "http://$http$installDIR/$os/$arch/1/";
        if (!(-e "$installDIR/$os/$arch/1/"))
        {
            push @{$rsp->{data}},
              "$node: (Error) Missing install directory $installDIR/$os/$arch/1/";
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

    elsif ("$installOS$version" =~ m/sles11/i)
    {

        # SUSE repository path - http://10.1.100.1/install/sles10.3/s390x/1/
        $path = "http://$http$installDIR/$os/$arch/1/";
        if (!(-e "$installDIR/$os/$arch/1/"))
        {
            push @{$rsp->{data}},
              "$node: (Error) Missing install directory $installDIR/$os/$arch/1/";
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
        $out =
          `ssh $node "zypper --non-interactive update --auto-agree-with-licenses"`;
        push @{$rsp->{data}}, "$node: $out";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }

    elsif ("$installOS$version" =~ m/rh/i)
    {

        # Red Hat repository path - http://10.0.0.1/install/rhel5.4/s390x/Server/
        $path = "http://$http$installDIR/$os/$arch/Server/";
        if (!(-e "$installDIR/$os/$arch/Server/"))
        {
            push @{$rsp->{data}},
              "$node: (Error) Missing install directory $installDIR/$os/$arch/Server/";
            xCAT::MsgUtils->message("I", $rsp, $callback);
            return;
        }

        # Create a yum repository file
        my $exist =
          `ssh $node "test -e /etc/yum.repos.d/$os.repo && echo 'File exists'"`;
        if (!$exist)
        {
            $out = `ssh $node "echo [$os] >> /etc/yum.repos.d/$os.repo"`;
            $out =
              `ssh $node "echo baseurl=$path >> /etc/yum.repos.d/$os.repo"`;
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

    else
    {
        push @{$rsp->{data}},
          "$node: (Error) Could not update operating system";
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
        my ($apps, $newstatus) = split(/=/, $appstat);

        xCAT::TableUtils->setAppStatus(\@nodes, $apps, $newstatus);

    }

    return 0;
}

