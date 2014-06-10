# IBM(c) 2010 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle the snmove command

=cut

#-------------------------------------------------------
package xCAT_plugin::snmove;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use Sys::Hostname;
use File::Basename;
use File::Path;
use xCAT::Table;
use xCAT::Utils;
use xCAT::NetworkUtils;
use xCAT::MsgUtils;
use xCAT::SvrUtils;
use Getopt::Long;
use xCAT::NodeRange;

#use Data::Dumper;

1;

#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {snmove => "snmove",};
}

#-------------------------------------------------------

=head3  preprocess_request

  Preprocess the command

=cut

#-------------------------------------------------------
sub preprocess_request
{

    my $request  = shift;
    my $callback = shift;
    my $sub_req  = shift;
    my $command  = $request->{command}->[0];
    my $args     = $request->{arg};

    #if already preprocessed, go straight to process_request
    if (   (defined($request->{_xcatpreprocessed}))
        && ($request->{_xcatpreprocessed}->[0] == 1))
    {
        return [$request];
    }

    # let process_request handle it
    my $reqcopy = {%$request};
    $reqcopy->{_xcatpreprocessed}->[0] = 1;
    return [$reqcopy];

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

    my $command = $request->{command}->[0];
    my $args    = $request->{arg};
    my $error   = 0;

    # parse the options
    @ARGV = ();
    if ($args)
    {
        @ARGV = @{$args};
    }
    Getopt::Long::Configure("bundling");
    Getopt::Long::Configure("no_pass_through");

    if (
        !GetOptions(
                    'h|help'          => \$::HELP,
                    'v|version'       => \$::VERSION,
                    's|source=s'      => \$::SN1,       # source SN akb MN
                    'S|sourcen=s'     => \$::SN1N,      # source SN akb node
                    'd|dest=s'        => \$::SN2,       # dest SN akb MN
                    'D|destn=s'       => \$::SN2N,      # dest SN akb node
                    'l|liteonly'     => \$::SLonly,    # update statelite only!
					'n|noretarget'    => \$::NORETARGET,  # no dump retarget
                    'P|postscripts=s' => \$::POST,      # postscripts to be run
                    'i|ignorenodes'   => \$::IGNORE,
                    'V|verbose'       => \$::VERBOSE,
        )
      )
    {
        &usage($callback);
        return 1;
    }

    # display the usage if -h or --help is specified
    if ($::HELP)
    {
        &usage($callback);
        return 0;
    }

    # display the version statement if -v or --verison is specified
    if ($::VERSION)
    {
        my $rsp = {};
        $rsp->{data}->[0] = xCAT::Utils->Version();
        $callback->($rsp);
        return 0;
    }

    if (($::IGNORE) && ($::POST))
    {
        my $rsp = {};
        $rsp->{data}->[0] =
          "-P and -i flags cannot be specified at the same time.\n";
        $callback->($rsp);
        return 1;
    }

    if (@ARGV > 1)
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Too many paramters.\n";
        $callback->($rsp);
        &usage($callback);
        return 1;
    }

    if ((@ARGV == 0) && (!$::SN1))
    {
        my $rsp = {};
        $rsp->{data}->[0] =
          "A node range or the source service node must be specified.\n";
        $callback->($rsp);
        &usage($callback);
        return 1;
    }
	
	if (!$::SLonly) {
		my $rsp;
		push @{$rsp->{data}}, "Moving nodes to their backup service nodes.\n";
		xCAT::MsgUtils->message("I", $rsp, $callback);
	}

	my $nimprime = xCAT::InstUtils->getnimprime();
	chomp $nimprime;

    #
    #  get the list of nodes
    #     - either from the command line or by checking which nodes are
    #		managed by the servicenode (SN1)
    #
    my @nodes = ();
    if (@ARGV == 1)
    {
        my $nr = $ARGV[0];
        @nodes = noderange($nr);
        if (nodesmissed)
        {
            my $rsp = {};
            $rsp->{data}->[0] =
              "Invalid nodes in noderange:" . join(',', nodesmissed);
            $callback->($rsp);
            return 1;
        }
    }
    else
    {

        # get all the nodes that use SN1 as the primary service nodes
        my $pn_hash = xCAT::Utils->getSNandNodes();
        foreach my $snlist (keys %$pn_hash)
        {
            if (($snlist =~ /^$::SN1$/) || ($snlist =~ /^$::SN1\,/))
            {
                push(@nodes, @{$pn_hash->{$snlist}});
            }
        }
    }

    #
    # make sure all the nodes are resolvable
    #
    foreach my $n (@nodes)
    {
        my $packed_ip = xCAT::NetworkUtils->getipaddr($n);
        if (!$packed_ip)
        {
            my $rsp;
            $rsp->{data}->[0] = "Could not resolve node \'$n\'.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
    }

    #
    #  get the node object definitions
    #
    my %objtype;
    my %nodehash;
    foreach my $o (@nodes)
    {
        $objtype{$o} = 'node';
    }

    my %nhash = xCAT::DBobjUtils->getobjdefs(\%objtype, $callback);
    if (!(%nhash))
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get xCAT object definitions.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    # are we dealing with AIX or Linux ?
    #	 can't use isAIX since the MN could be Linux in mixed cluster
    $::islinux = 0;
    $::isaix   = 0;
    foreach my $node (@nodes)
    {
        if ($nhash{$node}{os} eq "AIX")
        {
            $::isaix++;
        }
        else
        {
            $::islinux++;
        }
    }
    if ($::islinux && $::isaix)
    {
        my $rsp;
        push @{$rsp->{data}},
          "This command does not support a mix of AIX and Linux nodes.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    if ($::SLonly && $::islinux)
    {
        my $rsp;
        push @{$rsp->{data}},
          "The '-l' option is not supported for Linux nodes.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    #
    # get the nimtype for AIX nodes  (diskless or standalone)
    #
    my %nimtype;
    if ($::isaix)
    {

        # need to check the nimimage table to find the nimtype
        my $nimtab = xCAT::Table->new('nimimage', -create => 1);
        if ($nimtab)
        {
            foreach my $node (@nodes)
            {
                my $provmethod = $nhash{$node}{'provmethod'};

                # get the nimtype
                my $ref =
                  $nimtab->getAttribs({imagename => $provmethod}, 'nimtype');
                if ($ref)
                {
                    $nimtype{$node} = $ref->{'nimtype'};
                }
            }
        }
    }

    #
    # get the backup sn for each node
    #
    my @servlist;    # list of new service nodes
    my %newsn;
    my $nodehash;
    if ($::SN2)
    {                # we have the backup for each node from cmd line
        foreach my $n (@nodes)
        {
            $newsn{$n} = $::SN2;
        }
        push(@servlist, $::SN2);
    }
    else
    {

        # check the 2nd value of the servicenode attr
        foreach my $node (@nodes)
        {
            if ($nhash{$node}{'servicenode'})
            {
                my @sn = split(',', $nhash{$node}{'servicenode'});

                #               if ((scalar(@sn) > 2) && (xCAT::Utils->isAIX()))
                if ((scalar(@sn) > 2) && ($::isaix))
                {
                    my $rsp = {};
                    $rsp->{error}->[0] =
                      "The service node attribute cannot have more than two values.";
                    $callback->($rsp);
                }

                if ($sn[1])
                {
                    $newsn{$node} = $sn[1];
                    if (!grep(/^$sn[1]$/, @servlist))
                    {
                        push(@servlist, $sn[1]);
                    }
                }
            }

            if (!$newsn{$node})
            {
                my $rsp = {};
                $rsp->{error}->[0] =
                  "Could not determine a backup service node for node $node.";
                $callback->($rsp);
                $error++;
            }
        }
    }

    if ($error)
    {
        return 1;
    }

    #
    # get the new xcatmaster for each node
    #
    my %newxcatmaster;
    if ($::SN2N)
    {    # we have the xcatmaster for each node from cmd line
        foreach my $n (@nodes)
        {
            $newxcatmaster{$n} = $::SN2N;
        }
    }
    else
    {

        # try to calculate the xcatmaster value for each node

        # get all the interfaces from each SN
        # $sni{$SN}= list of ip
        my $s = &getSNinterfaces(\@servlist, $callback, $sub_req);

        my %sni = %$s;

        # get the network info for each node
        # $nethash{nodename}{networks attr name} = value
        my %nethash = xCAT::DBobjUtils->getNetwkInfo(\@nodes);

        # determine the xcatmaster value for the new SN
        foreach my $node (@nodes)
        {

            # get the node ip
            # or use getNodeIPaddress
            my $nodeIP = xCAT::NetworkUtils->getipaddr($node);
            chomp $nodeIP;

            # get the new SN for the node
            my $mySN = $newsn{$node};

            # check each interface on the service node
            foreach my $IP (@{$sni{$mySN}})
            {

                # if IP is in nodes subnet then thats the xcatmaster
                if (
                    xCAT::NetworkUtils->ishostinsubnet(
                                                       $IP,
                                                       $nethash{$node}{mask},
                                                       $nethash{$node}{net}
                    )
                  )
                {
                    # add the value to the hash
                    $newxcatmaster{$node} = $IP;
                    last;
                }
            }
            if (!$newxcatmaster{$node})
            {
                my $rsp = {};
                $rsp->{error}->[0] =
                  "Could not determine an xcatmaster value for node $node.";
                $callback->($rsp);
                $error++;
            }
        }
    }

    if ($error)
    {
        return 1;
    }

    #
    #  determine the new node attribute values
    #
    my %sn_hash;
    my $old_node_hash = {};
    my $index         = 0;

    foreach my $node (@nodes)
    {
        my $sn1;
        my $sn1n;
        my $sn1n_ip;

        # get current xcatmaster
        if ($::SN1N)
        {    # use command line value
            $sn1n = $::SN1N;
        }
        elsif ($nhash{$node}{'xcatmaster'})
        {    # use xcatmaster attr
            $sn1n = $nhash{$node}{'xcatmaster'};
        }

        if ($sn1n)
        {
            my @ret = xCAT::Utils::toIP($sn1n);
            if ($ret[0]->[0] == 0)
            {
                $sn1n_ip = $ret[0]->[1];
            }
        }

        # get the servicenode values
        my @sn_a;
        my $snlist = $nhash{$node}{'servicenode'};
        @sn_a = split(',', $snlist);

        # get current servicenode
        if ($::SN1)
        {

            # current SN from the command line
            $sn1 = $::SN1;
        }
        else
        {

            # current SN from node attribute
            $sn1 = $sn_a[0];
        }

        # switch the servicenode attr list
        my @sn_temp = grep(!/^$newsn{$node}$/, @sn_a);
        unshift(@sn_temp, $newsn{$node});
        my $t = join(',', @sn_temp);

        $sn_hash{$node}{objtype} = 'node';

        # set servicenode and xcatmaster attr
        $sn_hash{$node}{'servicenode'}         = $t;
        $sn_hash{$node}{'xcatmaster'}          = $newxcatmaster{$node};
        $old_node_hash->{$node}->{'oldsn'}     = $sn1;
        $old_node_hash->{$node}->{'oldmaster'} = $sn1n;

        # set tftpserver
        my $tftp = $nhash{$node}{'tftpserver'};
        if ($tftp)
        {
            if ($sn1n && ($tftp eq $sn1n))
            {
                $sn_hash{$node}{'tftpserver'} = $newxcatmaster{$node};
            }
            elsif ($sn1n_ip && ($tftp eq $sn1n_ip))
            {
                $sn_hash{$node}{'tftpserver'} = $newxcatmaster{$node};
            }
        }

        # set nfsserver
        my $nfs = $nhash{$node}{'nfsserver'};

        if ($nfs)
        {
            if ($sn1n && ($nfs eq $sn1n))
            {
                $sn_hash{$node}{'nfsserver'} = $newxcatmaster{$node};
            }
            elsif ($sn1n_ip && ($nfs eq $sn1n_ip))
            {
                $sn_hash{$node}{'nfsserver'} = $newxcatmaster{$node};
            }
        }

        #set monserver  ( = "servicenode,xcatmaster" )
        my $mon = $nhash{$node}{'monserver'};
        if ($mon)    # if it is currently set
        {
            my @tmp_a = split(',', $mon);
            if (scalar(@tmp_a) < 2)    # it must have two values
            {
                my $rsp;
                push @{$rsp->{data}},
                  "The current value of the monserver attribute is not valid.  It will not be reset.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
            }
            else
            {

                # if the first value is the current service node then change it
                if ($tmp_a[0] eq $sn1)
                {
                    $sn_hash{$node}{'monserver'} =
                      "$newsn{$node},$newxcatmaster{$node}";
                }
            }
        }
    }    # end - foreach node

	# check the sharedinstall attr
	my $sharedinstall=xCAT::Utils->get_site_attribute('sharedinstall');
	chomp $sharedinstall;
	if (!$sharedinstall) {
        $sharedinstall="no";
    }

	# handle the statelite update for sharedinstall=no
	#  - not using a shared files system
	my %SLmodhash;
    my %LTmodhash;

	if ( ($::SLonly) && ($sharedinstall eq "sns") )
	{
		my $rsp;
		push @{$rsp->{data}}, "The liteonly option is not valaid when using a shared file system across service nodes.\n";
		xCAT::MsgUtils->message("I", $rsp, $callback);
		return 1;
	}
		
	
    if ( ($::isaix) && ($sharedinstall eq "no") )  
    {

        #
        # try to rsync statelite dirs from old SN to new SN
        #	- only if old SN is listed in the tables!
        #
        if ($::VERBOSE)
        {
            my $rsp;
            push @{$rsp->{data}},
              "Attempting the synchronization of statelite files.\n";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }

        #
        # handle statelite table
        #
        my $statetab = xCAT::Table->new('statelite', -create => 1);

        # get hash of entries???
        my $recs = $statetab->getAllEntries;

        my $statemnt;
        my $server;
        my $dir;
        my $item = 0;
        my $id   = 0;
        my %donehash;

        #  for each entry
        foreach my $line (@$recs)
        {
            $statemnt = $line->{statemnt};
            ($server, $dir) = split(/:/, $statemnt);

            # see what nodes this entry applies to
            my @nodeattr = &noderange($line->{node}, 0);

            chomp $server;
            my @donelist;    # list of indices of old/new SN pairs

            # the server and dir could potentially be different for each node
            foreach my $n (@nodes)
            {

                # if the node is not in the noderange for this 
				#		entry then skip it
                if (!grep(/$n/, @nodeattr))
                {
                    next;
                }

                # check for the server
                if (grep /\$/, $server)
                {
                    my $serv =
                      xCAT::SvrUtils->subVars($server, $n, 'server', $callback);
                    $server = $serv;

                    # note: if a variable is used in the entry then it
                    #	does not have to be updated.
                }
                else
                {

                    # if the $server value was the old SN hostname 
					#		then we need to
                    #	update the statelite table with the new SN name
                    $item++;
                    my $stmnt = "$sn_hash{$n}{'xcatmaster'}:$dir";
                    $SLmodhash{$item}{'statemnt'} = $stmnt;
					$SLmodhash{$item}{'node'}     = $n;
                }

                # check for the directory
                if (grep /\$|#CMD/, $dir)
                {
                    $dir = xCAT::SvrUtils->subVars($dir, $n, 'dir', $callback);
                    $dir =~ s/\/\//\//g;
                }

				# we only want to sync the subdir for this node
				# ex. if dir = /nodedata then we sync /nodedata/compute03
				my $dodir;
				my $shorthost;
				# just to be sure we have the short name
        		($shorthost = $n) =~ s/\..*$//;
				if ($dir =~ /\/$/)
				{
					$dodir = "$dir$shorthost";	
				} else {
					$dodir = "$dir/$shorthost";
				}

                # see if the server in the table matches the nodes SN
                if ($server eq $old_node_hash->{$n}->{'oldmaster'})
                {

                    # see if we did this sync already
                    my $foundit = 0;
                    foreach my $i (keys %donehash)
                    {

                        # if the server and dir are the same then 
						#		we already did it
                        if (
                               ($dodir eq $donehash{$i}{dir})
                            && ($server eq $donehash{$i}{oldXM})
                            && ($donehash{$i}{newXM} eq
                                $sn_hash{$n}{'xcatmaster'})
                          )
                        {
                            $foundit++;
                        }
                    }

                    # ok - just skip to the next node
                    if ($foundit)
                    {
                        next;
                    }

                   	if ($::VERBOSE)
                   	{
                       	my $rsp;
                       	push @{$rsp->{data}},
                          		"Synchronizing $dodir to $sn_hash{$n}{'xcatmaster'}\n";
                       	xCAT::MsgUtils->message("I", $rsp, $callback);
                   	}

                   	my $todir = dirname($dodir);

                  	# do rsync of file/dir
                   	my $synccmd =
                     		qq~/usr/bin/rsync -arlHpEAogDz $dodir $newsn{$n}:$todir 2>&1~;

					if ($::VERBOSE) {
						my $rsp;
						push @{$rsp->{data}}, "On $old_node_hash->{$n}->{'oldsn'}: Running: \'$synccmd\'\n";

						xCAT::MsgUtils->message("I", $rsp, $callback);
					}

                   	my $output =
                     		xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh",
                                           $old_node_hash->{$n}->{'oldsn'},
                                           $synccmd, 0);
	
                   	if ($::RUNCMD_RC != 0)
                   	{
                       	my $rsp;
                       	push @{$rsp->{data}},
                         		"Could not sync statelite \'$dodir\'.";
						push @{$rsp->{data}}, "$output\n";
                       	xCAT::MsgUtils->message("E", $rsp, $callback);
                       	$error++;
                   	}
                   	else
                   	{
                       	$id++;
                       	$donehash{$id}{oldXM} =
                         		$old_node_hash->{$n}->{'oldmaster'};
                       	$donehash{$id}{dir}   = $dodir;
                       	$donehash{$id}{newXM} = $sn_hash{$n}{'xcatmaster'};
                   	}
                }    # end if servers match
            }    # end - foreach node
        }    # end for each line in statelite table

        # done with statelite table
        $statetab->close();

        # if only statelite sync is required then return now
        if ($::SLonly)
        {
            return 0;
        }

    }    # end sync statelite

	my $rsp;
	push @{$rsp->{data}}, "Setting new values in the xCAT database.\n";
	xCAT::MsgUtils->message("I", $rsp, $callback);

	#
    # make updates to statelite table
	#

	if ( ($::isaix) && ($sharedinstall eq "no") ) 
    {

        my $statetab = xCAT::Table->new('statelite', -create => 1);

        # for each key in SLmodhash - update the statelite table
        foreach my $item (keys %SLmodhash)
        {

            my $node     = $SLmodhash{$item}{'node'};
            my $statemnt = $SLmodhash{$item}{'statemnt'};
            $statetab->setAttribs({'node' => $node}, {'statemnt' => $statemnt});
        }

        # done with statelite table
        $statetab->close();

    }

    # update the node definitions #1
    if (keys(%sn_hash) > 0)
    {

        # update the node definition
        if (xCAT::DBobjUtils->setobjdefs(\%sn_hash) != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not update xCAT node definitions.\n";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            $error++;
        }
    }

    #
    # handle conserver
    #
    my %sn_hash1;
    foreach my $node (@nodes)
    {
        if (    ($nhash{$node}{'conserver'})
            and
            ($nhash{$node}{'conserver'} eq $old_node_hash->{$node}->{'oldsn'}))
        {
            $sn_hash1{$node}{'conserver'} = $newsn{$node};
            $sn_hash1{$node}{objtype} = 'node';
        }
    }

    # update the node definition #2
    if (keys(%sn_hash1) > 0)
    {
        if (xCAT::DBobjUtils->setobjdefs(\%sn_hash1) != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not update xCAT node definitions.\n";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            $error++;
        }
    }

	#
    #  handle the statelite update for the sharedinstall=sns case
    #   - using a shared file system across all service nodes
	#	- must be done AFTER node def is updated!
    #
    if ( ($::isaix) && ($sharedinstall eq "sns") ){
        my $s = &sfsSLconfig(\@nodes, \%nhash, \%sn_hash, $old_node_hash, $nimprime, $callback, $sub_req);
    }

    # TBD - handle sharedinstall =all case ????



    # run makeconservercf
    my @nodes_con = keys(%sn_hash1);
    if (@nodes_con > 0)
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Running makeconservercf " . join(',', @nodes_con);
        $callback->($rsp);

        my $ret =
          xCAT::Utils->runxcmd(
                               {
                                command => ['makeconservercf'],
                                node    => \@nodes_con,
                               },
                               $sub_req, 0, 1
                               );
        $callback->({data => $ret});
	}

	# 
	# restore .client_data files on the new SN
	#

  	if ( ($::isaix) && ($sharedinstall eq "sns") ){

		# first get the shared_root locations for each SN and osimage 
		my $nimtab = xCAT::Table->new('nimimage');
		my %SRloc;
		foreach my $n (@nodes) {
			my $osimage = $nhash{$n}{'provmethod'};
			# get the new primary SN
			my ($sn, $junk) = split(/,/, $sn_hash{$n}{'servicenode'});

			# $sn is name of SN as known by management node
			if (!$SRloc{$sn}{$osimage})  {

				my $SRn = $nimtab->getAttribs({'imagename' => $osimage}, 'shared_root');
				my $SRname=$SRn->{shared_root};

				if ($SRname) {
					my $srloc = xCAT::InstUtils->get_nim_attr_val($SRname, 'location', $callback, $nimprime, $sub_req);
					$SRloc{$sn}{$osimage}=$srloc;
				}
			}
		}
		$nimtab->close();

		# need a list of nodes for each SN
    	#  - the nodes that have this SN as their primary SN
    	my %SNnodes;
    	my $nrtab = xCAT::Table->new('noderes');
    	my $nrhash;
    	if ($nrtab)
    	{
        	$nrhash = $nrtab->getNodesAttribs(\@nodes, ['xcatmaster', 'servicenode']);
    	}
		$nrtab->close();

    	foreach my $node (@nodes)
    	{
        	my ($snode, $junk) = (split /,/, $nrhash->{$node}->[0]->{'servicenode'});
        	push(@{$SNnodes{$snode}}, $node);
    	}

		# now try to restore any backup client data

		# for each service node
		foreach my $s (keys %SRloc) {

			# for each osimage on that SN
			foreach my $osi (keys %{$SRloc{$s}}) {

				# set the names of the .client_data and backup directories
				my $sloc = $SRloc{$s}{$osi};
				# ex. /install/nim/shared_root/71Bdskls_shared_root

				my $cdloc = "$sloc/etc/.client_data";
				my $snbk = "$s" . "_" . "$osi";
				my $bkloc = "$sloc/$snbk/.client_data";

				# get a list of files from the backup dir
				my $rcmd = qq~/usr/bin/ls $bkloc 2>/dev/null~;

				if ($::VERBOSE) {
					my $rsp;
					push @{$rsp->{data}}, "Running \'$rcmd\' on $s\n";
					xCAT::MsgUtils->message("I", $rsp, $callback);
				}

				my $rlist = xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $s, $rcmd, 0);

				if ($::RUNCMD_RC != 0)
				{
					my $rsp;
					push @{$rsp->{data}}, "Could not list contents of $bkloc.\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
					$error++;
				}

				# restore files on node by node basis
				#	we don't want all the files!
				# we need to process only the nodes that have this SN as
            	#   their primary
            	my @nodelist = @{$SNnodes{$s}};

				foreach my $nd (@nodelist) {
					$nd =~ s/\..*$//;
					# for each file in $bkloc
					my $filestring = "";
					foreach my $f ( split(/\n/, $rlist) ){
						my $junk;
						my $file;
						if ($f =~ /:/) {
							($junk, $file) = split(/:/, $f);
						}
						$file =~ s/\s*//g;    # remove blanks

						# if file contains node name then copy it
						if ($file =~ /$nd/) {
							$filestring .= "$bkloc/$file ";
						}
					}

                	if (!$filestring) {
						my $rsp;
						push @{$rsp->{data}}, "No backup client_data files for node $nd in $bkloc. Current client data files in $cdloc should be checked to avoid boot errors.\n";
						xCAT::MsgUtils->message("E", $rsp, $callback);
						$error++;
						next;
					}

					my $ccmd=qq~/usr/bin/cp -p $filestring $cdloc~;

					if ($::VERBOSE) {
						my $rsp;
						push @{$rsp->{data}}, "Running \'$ccmd\' on $s.\n";
						xCAT::MsgUtils->message("I", $rsp, $callback);
					}

					my $output = xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $s, $ccmd, 0);
					if ($::RUNCMD_RC != 0)
					{
						my $rsp;
						push @{$rsp->{data}}, "Could not copy\n$filestring\n\tto $cdloc.\n";
						push @{$rsp->{data}}, "Command output:\n$output\n";
						xCAT::MsgUtils->message("E", $rsp, $callback);
						$error++;
					}
				}
			}
		}
  	}

	#
	# - retarget the iscsi dump device to the new server for the nodes
	#
	if ((!$::IGNORE) && ($::isaix) && ($sharedinstall eq "sns")) {

		if (!$::NORETARGET) {
			if (&dump_retarget($callback, \@nodes, $sub_req) != 0)
			{
				my $rsp;
				push @{$rsp->{data}}, "One or more errors occured while attemping to re-target the dump device on cluster nodes.\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
				$error++;
			}
		}
	}

    #
    #   Run niminit on AIX diskful nodes
    #
    if (!$::IGNORE)    # unless the user does not want us to touch the node
    {

        if ($::isaix)
        {

            #if the node is aix and the type is standalone
            foreach my $node (@nodes)
            {

                # if this is a standalone node then run niminit
                if (($nimtype{$node}) && ($nimtype{$node} eq 'standalone'))
                {

					if ($::VERBOSE)
					{
						my $rsp;
						push @{$rsp->{data}},"Running niminit on $node.\n";
						xCAT::MsgUtils->message("I", $rsp, $callback);	
					}

                    my $nimcmd =
                      qq~/usr/sbin/niminit -a name=$node -a master=$newsn{$node} >/dev/null 2>&1~;

                    my $out =
                      xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $node,
                                            $nimcmd, 0);

                    if ($::RUNCMD_RC != 0)
                    {
                        my $rsp;
                        push @{$rsp->{data}},
                          "Could not run niminit on node $node.\n";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                        $error++;
                    }
                }
            }
        }
    }

    # for Linux system only
    if ($::islinux)
    {

        #tftp, dhcp and nfs (site.disjointdhcps should be set to 1)

        # get a list of nodes for each provmethod
        my %nodeset_hash;
        foreach my $node (@nodes)
        {
            my $provmethod = $nhash{$node}{'provmethod'};
            if ($provmethod)
            {
                if (!grep(/^$node$/, @{$nodeset_hash{$provmethod}}))
                {
                    push(@{$nodeset_hash{$provmethod}}, $node);
                }
            }
        }

        # run the nodeset command
        foreach my $provmethod (keys(%nodeset_hash))
        {

            # need a node list to send to nodeset
            my @nodeset_nodes = @{$nodeset_hash{$provmethod}};

            if (   ($provmethod eq 'netboot')
                || ($provmethod eq 'install')
                || ($provmethod eq 'statelite'))
            {
                my $ret =
                  xCAT::Utils->runxcmd(
                                       {
                                        command => ['nodeset'],
                                        node    => \@nodeset_nodes,
                                        arg     => [$provmethod],
                                       },
                                       $sub_req, 0, 1
                                       );
		my $rsp;
		$rsp->{data}=$ret;
                xCAT::MsgUtils->message("I", $rsp, $callback);
                if ($::RUNCMD_RC != 0)
                {
                    $error++;
                }
            }
            else
            {
                my $ret =
                  xCAT::Utils->runxcmd(
                                       {
                                        command => ['nodeset'],
                                        node    => \@nodeset_nodes,
                                        arg     => ["osimage=$provmethod"],
                                       },
                                       $sub_req, 0, 1
                                       );
		my $rsp;
		$rsp->{data}=$ret;
                xCAT::MsgUtils->message("I", $rsp, $callback);
                if ($::RUNCMD_RC != 0)
                {
                    $error++;
                }
            }
        }
    }    # end - for Linux system only

    #
    # update the /etc/xcatinfo files on the nodes
    #	switch to the new server name
    #
    if (!$::IGNORE)
    {
        if ($::isaix)
        {

			if ($::VERBOSE)
			{
				my $rsp;
				push @{$rsp->{data}}, "Updating the /etc/xcatinfo files.\n";
				xCAT::MsgUtils->message("I", $rsp, $callback);
			}

            foreach my $node (@nodes)
            {

                # may need to reorg this
                #   could organized into set of nodes for each new xcatmaster
                #	then run runxcmd for that set of nodes
                my $IP = xCAT::NetworkUtils->getipaddr($newxcatmaster{$node});
                chomp $IP;
                my $cmd = qq~echo "XCATSERVER=$IP" > /etc/xcatinfo~;
                my @nlist;
                push(@nlist, $node);

                my $ret =
                  xCAT::Utils->runxcmd(
                                       {
                                        command => ['xdsh'],
                                        node    => \@nlist,
                                        arg     => ["$cmd"],
                                       },
                                       $sub_req, 0, 1
                                       );

                if ($::RUNCMD_RC != 0)
                {
                    $error++;
                }
            }
        }    # end if isaix
    } # end of not ignore

    if (!$::IGNORE)
    {

        #
        # for both AIX and Linux systems
        # setup the default gateway if the network.gateway=xcatmaster 
		#	for the node
        #
        my %nethash;
        my %ipmap  = ();
        my %gwhash = ();
        my $nwtab  = xCAT::Table->new("networks");
        if ($nwtab)
        {
            my @tmp1 =
              $nwtab->getAllAttribs(('net', 'mask', 'gateway', 'mgtifname'));
            if (@tmp1 && (@tmp1 > 0))
            {
                foreach my $nwitem (@tmp1)
                {
                    my $gw = $nwitem->{'gateway'};
                    if (!$gw)
                    {
                        next;
                    }

                    chomp $gw;
                    if ($gw ne '<xcatmaster>')
                    {
                        next;
                    }

                    #now only handle the networks that has <xcatmaster> 
					#	as the gateway
                    my $NM     = $nwitem->{'mask'};
                    my $net    = $nwitem->{'net'};
                    my $ifname = $nwitem->{'mgtifname'};
                    chomp $NM;
                    chomp $net;
                    chomp $ifname;

                    # for each node - get the network info
                    foreach my $node (@nodes)
                    {

                        # get, check, split the node IP
                        my $IP = xCAT::NetworkUtils->getipaddr($node);
                        chomp $IP;

                        # check the entries of the networks table
                        # - if the bitwise AND of the IP and the netmask 
						#		gives you
                        #	the "net" name then that is the entry you want.
                        if (xCAT::NetworkUtils->ishostinsubnet($IP, $NM, $net))
                        {
                            my $newmaster = $newxcatmaster{$node};
                            my $newmasterIP;
                            if (exists($ipmap{$newmaster}))
                            {
                                $newmasterIP = $ipmap{$newmaster};
                            }
                            else
                            {
                                $newmasterIP =
                                  xCAT::NetworkUtils->getipaddr($newmaster);
                                chomp($newmasterIP);
                                $ipmap{$newmaster} = $newmasterIP;
                            }
                            $nethash{$node}{'gateway'}   = $newmasterIP;
                            $nethash{$node}{'net'}       = $net;
                            $nethash{$node}{'mask'}      = $NM;
                            $nethash{$node}{'mgtifname'} = $ifname;
                            if ($newmasterIP)
                            {
                                if (exists($gwhash{$newmasterIP}))
                                {
                                    my $pa = $gwhash{$newmasterIP};
                                    push(@$pa, $node);
                                }
                                else
                                {
                                    $gwhash{$newmasterIP} = [$node];
                                }
                            }
                        }
                    }
                }
            }
        }

        if (keys(%gwhash) > 0)
        {
            my $rsp;
            $rsp->{data}->[0] = "Checking the default routes on the nodes.";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }
		
		# for each new xcatmaster ip (gateway)
        foreach my $gw (keys %gwhash)
        {

			# for each node that is moved to this new gateway
			foreach my $nd ( @{$gwhash{$gw}} ) {

            	my $cmd = "route add default gw";  # for linux

            	if ($::isaix)
            	{

					# we need to make sure we have a default gateway set
					#  to the new SN - however we do not want to add 
					#	an additional default gateway and we don't
					# 	want to do anything to change what the user 
					#	may have set up
					# SO - just see if the old SN is the only default set 
					#	and if so then change it to the new gw (SN)

					my $oldgwip = xCAT::NetworkUtils->getipaddr($old_node_hash->{$nd}->{'oldmaster'});

					# get the ouptut of "netstat -rn"
					my $netcmd = qq~netstat -rn~;
					my $netout = xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $nd, $netcmd, 0);

					my $foundold;
                	my $foundnew;
					# see what default routes are set
					foreach my $l (split(/\n/, $netout)) {
						my $line;
						my $junk;
						if ($l =~ /:/) {
                			($junk, $line) = split(/:/, $l);
            			} else {
                			$line = $l;
						}

						my ($dest, $IP, $junk) = split(" ", $line);
						if ($dest eq 'default') {
							if ( $IP eq $oldgwip) {
								$foundold++;
							}
							if ( $IP eq $gw) {
								$foundnew++;
							}
						} else {
							next;
						}
					} # end foreach

					# decide if we need to change default gw
					if ($foundold && !$foundnew) {
						$cmd = "route change default";
					} else {
						$cmd = "";
					}
            	}

				if ($cmd ) 
				{
            		my $ret =
              			xCAT::Utils->runxcmd(
                                   {
                                    command => ['xdsh'],
                                    node    => $gwhash{$gw},
                                    arg     => ["-v", "$cmd $gw"],
                                   },
                                   $sub_req, -1, 1
                                   );

            		if (($::RUNCMD_RC != 0) &&
                            !grep(/ File exists/,@$ret) )  # ignore already set error 
            		{
						my $rsp;
                                                $rsp->{data} = $ret;
						push @{$rsp->{data}}, "Could not set default route.\n";
						xCAT::MsgUtils->message("E", $rsp, $callback);
						$error++;
            		}
				}

			} # end foreach node
        } # end for each new gw
    } # if not ignore nodes

	#  
	#  run the bootlist command
	#			
	if (!$::IGNORE)
    {
        if ($::isaix)
        {
        #    if ($::VERBOSE)
            {
                my $rsp;
                push @{$rsp->{data}}, "Updating the bootlist.\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }

			my %nethash = xCAT::DBobjUtils->getNetwkInfo(\@nodes);

            foreach my $nd (@nodes)
			{
				# get the device name to use with the bootlist cmd
				my $nimcmd = qq~netstat -in~;
				my $nimout = xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $nd, $nimcmd,0);
				my $myip = xCAT::NetworkUtils->getipaddr($nd);
				chomp $myip;
				my $intname;
				foreach my $l (split(/\n/,$nimout))

				{
					my $line;
					my $junk;
					if ($l =~ /:/) {
						($junk, $line) = split(/:/, $l);
					} else {
						$line = $l;
					}
					my ($name, $junk1, $junk, $IP, $junk3) = split(" ", $line);
					chomp $IP;

					if ($IP eq $myip) 
					{
						$intname =$name;
						last;
					}
				}

				my $devicename;
				if ($intname =~ /hf/) {
					$intname =~ s/hf/hfi/g;  
				} elsif ($intname =~ /en/) {
					$intname =~ s/en/ent/g;
				} elsif ($intname =~ /et/) {
					my $index = $intname =~ s/et//g;
					$intname =~ s/et/ent/g; 
				} 

				$devicename = $intname;

				# need node gateway
                my $gateway = $nethash{$nd}{'gateway'};

				# the boot server is the new xcatmaster value
				my $snIP = xCAT::NetworkUtils->getipaddr($newxcatmaster{$nd});

				# point to the new server
				my $blcmd = qq~/usr/bin/bootlist -m normal $devicename gateway=$gateway bserver=$snIP client=$myip ~;

				my $output = xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $nd, $blcmd, 0);
				if ($::RUNCMD_RC != 0)
				{
					my $rsp;
					push @{$rsp->{data}}, "Could not run \'$blcmd\' on node $nd.\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
					$error++;
					next;
				}
			}
		}
	}

    # run postscripts to take care of syslog, ntp, and mkresolvconf
    #	 - if they are included in the postscripts table
    if (!$::IGNORE)    # unless the user does not want us to touch the node
    {

        # get all the postscripts that should be run for the nodes
        my $pstab = xCAT::Table->new('postscripts', -create => 1);
        my $nodeposhash = {};
        if ($pstab)
        {
            $nodeposhash =
              $pstab->getNodesAttribs(\@nodes,
                                      ['postscripts', 'postbootscripts']);
        }
        else
        {
            my $rsp = {};
            $rsp->{error}->[0] = "Cannot open postscripts table.\n";
            $callback->($rsp);
            return 1;
        }

        my $et =
          $pstab->getAttribs({node => "xcatdefaults"},
                             'postscripts', 'postbootscripts');
        my $defscripts     = "";
        my $defbootscripts = "";
        if ($et)
        {
            $defscripts     = $et->{'postscripts'};
            $defbootscripts = $et->{'postbootscripts'};
        }

        my $user_posts;
        if ($::POST)
        {
            $user_posts = $::POST;
        }
        my $pos_hash = {};
        foreach my $node (@nodes)
        {

            foreach my $rec (@{$nodeposhash->{$node}})
            {
                my $scripts;
                if ($rec)
                {
                    $scripts = join(',',
                                    $defscripts, $rec->{'postscripts'},
                                    $defbootscripts, $rec->{'postbootscripts'});
                }
                else
                {
                    $scripts = join(',', $defscripts, $defbootscripts);
                }
                my @tmp_a = split(',', $scripts);

                # xCAT's default scripts to be run: syslog, 
				#			setupntp, and mkresolvconf

				my @valid_scripts;
				if ( ($::isaix) && ($sharedinstall eq "sns") ){
					@valid_scripts = ("syslog", "setupntp");
				} else {
					@valid_scripts = ("syslog", "setupntp", "mkresolvconf");
				}
                my $scripts1 = "";
                if (($user_posts) && ($user_posts eq "all"))
                {
                    $scripts1 = $scripts;
					#run all the postscripts defined in the postscripts table
                }
                else
                {
                    foreach my $s (@valid_scripts)
                    {

                        # if it was included in the original list then run it
                        if (grep(/^$s$/, @tmp_a))
                        {
                            if ($scripts1)
                            {
                                $scripts1 = "$scripts1,$s";
                            }
                            else
                            {
                                $scripts1 = $s;
                            }
                        }
                    }

                    #append the user given scripts
                    if ($user_posts)
                    {
                        if ($scripts1)
                        {
                            $scripts1 = "$scripts1,$user_posts";
                        }
                        else
                        {
                            $scripts1 = $user_posts;
                        }
                    }
                }

                if ($scripts1)
                {
                    if (exists($pos_hash->{$scripts1}))
                    {
                        my $pa = $pos_hash->{$scripts1};
                        push(@$pa, $node);
                    }
                    else
                    {
                        $pos_hash->{$scripts1} = [$node];
                    }
                }
            }
        }

        my $rsp;
        $rsp->{data}->[0] = "Running postscripts on the nodes.";
        xCAT::MsgUtils->message("I", $rsp, $callback);
        foreach my $scripts (keys(%$pos_hash))
        {

            my $pos_nodes = $pos_hash->{$scripts};

    # need to run updatenode -s first as a separate call
    # before running updatenode -P. The flags cannot be run together.
            my $ret =
              xCAT::Utils->runxcmd(
                                   {
                                    command => ['updatenode'],
                                    node    => $pos_nodes,
                                    arg     => ["-s"],
                                   },
                                   $sub_req, -1, 1
                                   );
            if ($::RUNCMD_RC != 0)
            {
                $error++;

            }
            my $rsp;
            $rsp->{data} = $ret;
            xCAT::MsgUtils->message("I", $rsp, $callback);

            $ret =
              xCAT::Utils->runxcmd(
                                   {
                                    command => ['updatenode'],
                                    node    => $pos_nodes,
                                    arg     => ["-P", "$scripts"],
                                   },
                                   $sub_req, -1, 1
                                   );
            if ($::RUNCMD_RC != 0)
            {
                $error++;

            }
            $rsp->{data} = $ret;
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }
    }    # end -for both AIX and Linux systems

    my $retcode = 0;
    if ($error)
    {

        #my $rsp;
        #push @{$rsp->{data}}, "One or more errors occurred while attempting to switch nodes to a new service node.\n";
        #xCAT::MsgUtils->message("E", $rsp, $callback);
        $retcode = 1;
    }

    #else
    #{
    #	my $rsp;
    #	push @{$rsp->{data}}, "The nodes were successfully moved to the new service node.\n";
    #	xCAT::MsgUtils->message("I", $rsp, $callback);
    #}

    return $retcode;

}

#----------------------------------------------------------------------------

=head3  getSNinterfaces

	Get a list of ip addresses for each service node in a list

	Arguments:
		list of servcie nodes
	Returns:
		1 -  could not get list of ips
		0 -  ok
	Globals:
		none
	Error:
		none
	Example:
		my $sni = xCAT::InstUtils->getSNinterfaces(\@servlist);

	Comments:
		none

=cut

#-----------------------------------------------------------------------------
sub getSNinterfaces
{

    my ($list, $callback, $sub_req) = @_;

    my @snlist = @$list;

    my %SNinterfaces;

    # get all the possible IPs for the node I'm running on
    my $ifcmd;

    #    if (xCAT::Utils->isAIX())
    if ($::isaix)
    {
        $ifcmd = "/usr/sbin/ifconfig -a ";
    }
    else
    {
        $ifcmd = "/sbin/ip addr ";
    }

    foreach my $sn (@snlist)
    {

        my $SNIP;

        my $result =
          xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $sn, $ifcmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp = {};
            $rsp->{data}->[0] =
              "Could not get IP addresses from service node $sn.\n";
            $callback->($rsp);
            next;
        }

        foreach my $int (split(/\n/, $result))
        {
            if (!grep(/inet/, $int))
            {

                # only want line with "inet"
                next;
            }
            $int =~ s/$sn:\s+//;    # skip hostname from xdsh output
            my @elems = split(/\s+/, $int);

            if (xCAT::Utils->isLinux())
            {
                if ($elems[0] eq 'inet6')
                {

                    #Linux IPv6 TODO, do not return IPv6 networks on
                    #	Linux for now
                    next;
                }

                ($SNIP, my $mask) = split /\//, $elems[1];
            }
            else
            {

                # for AIX
                if ($elems[0] eq 'inet6')
                {
                    $SNIP = $elems[1];
                    $SNIP =~ s/\/.*//;    # ipv6 address 4000::99/64
                    $SNIP =~ s/\%.*//;    # ipv6 address ::1%1/128
                }
                else
                {
                    $SNIP = $elems[1];
                }
            }

            chomp $SNIP;

            push(@{$SNinterfaces{$sn}}, $SNIP);
        }
    }

    return \%SNinterfaces;
}

#-----------------------------------------------------------------------------
sub usage
{
    my $cb  = shift;
    my $rsp = {};

    push @{$rsp->{data}},
      "\nsnmove - Move xCAT compute nodes from one xCAT service node to a \nbackup service node.";
    push @{$rsp->{data}}, "\nUsage: ";
    push @{$rsp->{data}}, "\tsnmove [-h | --help ]\n";
    push @{$rsp->{data}},
      "\tsnmove noderange [-V] [-l|--liteonly] [[-d|--dest]  sn2]\n\t\t[[-D|--destn]  sn2n] [-i|--ignorenodes] \n\t\t[[-P|--postscripts]  script1,script2...|all]\n";
    push @{$rsp->{data}},
      "\tsnmove [-V] [-l|--liteonly] -s|--source  sn1 [[-S|--sourcen]  sn1n]\n\t\t[[-d|--dest]  sn2] [[-D|--dest ]  sn2n]\n\t\t[-i|--ignorenodes][[-P|--postscripts] script1,script2...|all]";
    push @{$rsp->{data}}, "\n";
    push @{$rsp->{data}}, "\nWhere:";
    push @{$rsp->{data}},
      "\tsn1 is the hostname of the source service node as known by (facing) the management node.";
    push @{$rsp->{data}},
      "\tsn1n is the hostname of the source service node as known by (facing) the nodes.";
    push @{$rsp->{data}},
      "\tsn2 is the hostname of the destination service node as known by (facing) the management node.";
    push @{$rsp->{data}},
      "\tsn2n is the hostname of the destination service node as known by (facing) the nodes.";
    push @{$rsp->{data}},
      "\tscripts is a comma separated list of postscripts to be run on the nodes. 'all' means all the scripts defined in the postscripts table for each node are to be run.";
    $cb->($rsp);

    return 0;
}

#----------------------------------------------------------------------------

=head3   dump_retarget

			Switches the iscsi dump target of nodes to a backup service node.

        Arguments:
        Returns:
            0 - OK
            1 - error

        Usage:  $ret = &dump_retarget($callback, \@nodelist, $sub_req);

=cut

#-----------------------------------------------------------------------------
sub dump_retarget
{
	my $callback = shift;
	my $nodelist    = shift;
	my $sub_req   = shift;

	my @nodes = @$nodelist;

	my $error;

	my $rsp;
	push @{$rsp->{data}}, "Checking dump devices.\n";
	xCAT::MsgUtils->message("I", $rsp, $callback);

	# get provmethod and xcatmaster for each node
	my $nrtab = xCAT::Table->new('noderes');
	my $nttab = xCAT::Table->new('nodetype');
	my $nrhash;
	my $nthash;
	if ($nrtab)
	{
       	$nrhash = $nrtab->getNodesAttribs(\@nodes, ['xcatmaster', 'servicenode']);
   	}
   	else
   	{
       	my $rsp = {};
       	$rsp->{data}->[0] = "Can not open noderes table.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback, 1);
   	}
	if ($nttab)
   	{
       	$nthash = $nttab->getNodesAttribs(\@nodes, ['provmethod']);
   	}
   	else
   	{
       	my $rsp = {};
       	$rsp->{data}->[0] = "Can not open nodetype table.\n";
       	xCAT::MsgUtils->message("E", $rsp, $callback, 1);
   	}

	# get the network info for each node
	# $nethash{nodename}{networks attr name} = value
	my %nethash = xCAT::DBobjUtils->getNetwkInfo(\@nodes);


	# get a list of nodes for each SNs and osimage combo
	#		- also a list of osimages.
	my %SNosinodes;
	my @image_names;
	my %SNname;
	foreach my $node (@nodes)
	{

		my $xmast = $nrhash->{$node}->[0]->{'xcatmaster'};
		my ($snode, $junk) = (split /,/, $nrhash->{$node}->[0]->{'servicenode'});
		my $osimage = $nthash->{$node}->[0]->{'provmethod'};

		push(@{$SNosinodes{$xmast}{$osimage}}, $node);

		if (!grep(/^$osimage$/, @image_names) ) {
			push(@image_names, $osimage);
		}
		$SNname{$xmast}=$snode;      
	}

	#
	# get the image defs from the DB
	#
	my %imghash;
	my %objtype;
	# for each image
	foreach my $m (@image_names) 
	{
		$objtype{$m} = 'osimage';
	}
	my %imghash = xCAT::DBobjUtils->getobjdefs(\%objtype, $callback);
	if (!(%imghash))
	{
		my $rsp;
		push @{$rsp->{data}}, "Could not get xCAT osimage definitions.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
	}

	# set the default port - todo - user could have set differently???
	my $dump_port=32600;

	# for each SN
	foreach my $sn (keys %SNosinodes)
	{
		# get ip addr of SN as known by the node
		#  - sn is "xcatmaster"   
		chomp $sn;
		my $SNip = xCAT::NetworkUtils->getipaddr($sn);

		# this is "servicenode" value - get first in list
		my ($xcatSNname, $junk) = (split /,/, $SNname{$sn}); 

		# for each osimage needed for this SN
		foreach my $osi (keys %{$SNosinodes{$sn}})
		{
			if (!$imghash{$osi}{'dump'}) {
				next;
			}

			# get dump target and lun from nim dump res def
			my %nimattrs;
			my $dump_target;
			my $dump_lunid;
			my @attrs = ("dump_target", "dump_lunid");
			my $na = &getnimattr($imghash{$osi}{'dump'}, \@attrs, $callback, $xcatSNname, $sub_req);
			
			if ($na) {
				%nimattrs = %{$na};
				$dump_target = $nimattrs{dump_target};
				$dump_lunid = $nimattrs{dump_lunid};
			}
			my $configdump;
			if ($imghash{$osi}{'configdump'}) {
				$configdump = $imghash{$osi}{'configdump'};
			} else {
				$configdump = "selective";
			}
			
			if ($::VERBOSE) {
				# print values  ??
				# or cmd??
			}

			if (!$dump_target || !$dump_port || !$SNip || !$dump_lunid) {
				my $rsp;
				push @{$rsp->{data}}, "Could not re-target the dump device for the following nodes. \n@{$SNosinodes{$sn}{$osi}}\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
				$error++;
				next;
			}

			my @nodelist = @{$SNosinodes{$sn}{$osi}};
			foreach my $nd (@nodelist) {

				chomp $nd;
                my $Nodeip = xCAT::NetworkUtils->getipaddr($nd);

				# need node gateway
                my $gateway = $nethash{$nd}{'gateway'};

				#  This should configure the iscsi disc on the client
				my $tcmd = qq~/usr/lpp/bos.sysmgt/nim/methods/c_disc_target -a operation=discover -a target="$dump_target" -a dump_port="$dump_port" -a ipaddr="$SNip" -a lun_id="$dump_lunid"~;
				my $hd = xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $nd, $tcmd, 0);
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp;
                    push @{$rsp->{data}}, "Could not run \'$tcmd\' on node $nd.\
n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    $error++;
                    next;
                }
				chomp $hd;

				my $hdisk;
				foreach my $line ( split(/\n/, $hd )) {
					if ( $line =~ /hdisk/ ) {
						$hdisk = $line;
						if ($line =~ /:/) {
							my $node;
							($node, $hdisk) = split(': ', $line);
						}
					}
				}

				chomp $hdisk;
				$hdisk =~ s/\s*//g;

				if (!$hdisk) {
					my $rsp;
                    push @{$rsp->{data}}, "Could not determine dump device for node $nd.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    $error++;
                    next;
				}

				# define the disk on the client
				my $mkcmd = qq~/usr/sbin/mkdev -l $hdisk~;

				my $output = xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $nd, $mkcmd, 0);
				if ($::RUNCMD_RC != 0)
				{
					my $rsp;
					push @{$rsp->{data}}, "Could not run \'$mkcmd\' on node $nd.\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
					$error++;
					next;
				}

				# configure the dump device, select either selective or full
				# for the configdump attribute.
				my $ccmd = qq~/usr/lpp/bos.sysmgt/nim/methods/c_config_dump -a configdump=$configdump -a target=$dump_target -a dump_port=$dump_port -a ipaddr=$SNip -a lun_id=$dump_lunid~;

				$output = xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh",
$nd, $ccmd, 0);
				if ($::RUNCMD_RC != 0)
				{
					my $rsp;
					push @{$rsp->{data}}, "Could not run \'$ccmd\' on node $nd.\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
					$error++;
					next;
				}

				# set the dump disk:
				my $syscmd = qq~/usr/bin/sysdumpdev -p /dev/$hdisk~;
				$output = xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $nd, $syscmd, 0);
				if ($::RUNCMD_RC != 0)
				{
					my $rsp;
					push @{$rsp->{data}}, "Could not run \'$syscmd\' on node $nd.\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
					$error++;
					next;
				}

				my $rsp;
				push @{$rsp->{data}}, "Set the primary dump device for node \'$nd\' to \'/dev/$hdisk\' and changed the dump target to \'$sn\'.\n";
				xCAT::MsgUtils->message("I", $rsp, $callback);

			}
		}
	}

	if ($error) {
		return 1;
	}

	return 0;
}

#----------------------------------------------------------------------------

=head3	getnimattr

	Get the specified nim attrs form the named server

	Returns:
                undef - error
                hash ref - 

=cut

#-----------------------------------------------------------------------------
sub getnimattr	
{
	my $resname = shift;
	my $attr = shift;
    my $callback = shift;
    my $target   = shift;
    my $sub_req  = shift;

	my @attrs = @$attr;
	my %attrval;

	if (!$resname) {
		return undef;
	}

	if (!$target)
    {
        $target = xCAT::InstUtils->getnimprime();
    }
    chomp $target;

	my $ncmd  = "/usr/sbin/lsnim ";
	foreach my $a (@attrs) 
	{
		$ncmd .= "-a $a ";
	}

	$ncmd .= "$resname 2>/dev/null";

   	my $attrlist = xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $target, $ncmd, 0);
   	if ($::RUNCMD_RC != 0)
   	{
       	if ($::VERBOSE) {
           	my $rsp;
           	push @{$rsp->{data}}, "Could not run lsnim command: \'$ncmd\'.\n";
           	xCAT::MsgUtils->message("E", $rsp, $callback);
       	}
       	return undef;
   	}

	foreach my $line (split(/\n/, $attrlist) ){
		# look for attr name 
		foreach my $a (@attrs) {
			chomp $a;
			if ($line  =~ /$a/) {
				my ($stuff, $value) = split('=', $line);
				chomp $value;

				my ($val, $rest) = split(' ', $value);

				# add to hash
				$attrval{$a} = $val;
			}
		}
	}

	return \%attrval;
}

#----------------------------------------------------------------------------

=head3  sfsSLconfig

            Does statelite setup when using a shared file system

			The snmove cmd changes the xcatmaster value for the nodes
			This means, that since we won't be running mkdsklsnode again, 
			we need to take care of the ststelite file changes here
				- update statelite tables in DB
				- run dolitesetup to re-create the statelite files stored
					in the shared_root directories
				- copy the new statelite files to the shared_root directory
					on the target service node (only one since this is a
					shared filesystem
				- note: not copying the persistent directory on the MN

        Arguments:
        Returns:
            0 - OK
            1 - error

        Usage:  $ret = &sfsSLconfig(\@nodelist, \%nhash, \%sn_hash, $nimprime, 
							$callback, $sub_req);

=cut

#-----------------------------------------------------------------------------
sub sfsSLconfig
{
    my $nodelist    = shift;
	my $nh		= shift;
	my $n_h		= shift;
	my $old_node_hash = shift;
	my $nimprime = shift;                
	my $callback = shift;
    my $sub_req   = shift;

    my @nodes = @$nodelist;
	my %nhash = %{$nh};
	my %sn_hash = %{$n_h};
	my %imghash;  # osimage def

	my $statemnt;
    my $server;
    my $dir;
    my $item = 0;

	my %SLmodhash;   # changes for the statelite DB table

	#  gather some basic info
    my $targetsn;  # name of SN to copy files to
	my %objtype;  # need to pass to getobjdefs
	my %osinodes; # list of nodes for each osimage
	my @osimage;  # list of osimages
    foreach my $n (@nodes) {
        if (!grep(/$nhash{$n}{'provmethod'}/, @osimage) ){
            push (@osimage, $nhash{$n}{'provmethod'});

            $objtype{$nhash{$n}{'provmethod'}} = 'osimage';

			push (@{$osinodes{$nhash{$n}{'provmethod'}}}, $n);

			my ($sn, $snbak) = split(/,/, $sn_hash{$n}{servicenode});
            if (!$targetsn) {
                if (!xCAT::InstUtils->is_me($sn) ) {
                    $targetsn=$sn;
                }
            }
        }
    }

	my $statetab = xCAT::Table->new('statelite', -create => 1);
    my $recs = $statetab->getAllEntries;

	#
	# update the statelite DB tables
	#
	foreach my $line (@$recs)
    {
		$statemnt = $line->{statemnt};

        # if the statemnt is a variable then skip it
        if (grep /^\$/, $statemnt) {
            next;
        }

		($server, $dir) = split(/:/, $statemnt);
		chomp $server;

		# see what nodes this entry applies to
        my @nodeattr = &noderange($line->{node}, 0);

		foreach my $n (@nodes)
		{
			# if the node is not in the noderange for this
			#       entry then skip it
			if (!grep(/$n/, @nodeattr))
			{
				next;
			}

			# if the $server value was the old SN hostname
			#       then we need to
			#   update the statelite table with the new SN name
			if ( $server eq $old_node_hash->{$n}->{'oldmaster'} ) {	
				my $stmnt = "$sn_hash{$n}{'xcatmaster'}:$dir";
				$SLmodhash{$item}{'statemnt'} = $stmnt;
				$SLmodhash{$item}{'node'}     = $n;

				$statetab->setAttribs({'node' => $n}, {'statemnt' => $stmnt, 'mntopts' => $line->{mntopts}, 'comments' => $line->{comments}, 'disable' => $line->{disable}});
			}
		}
	} # end statelite DB update

	# done with statelite table
	$statetab->close();

	# get the osimage defs
	my %imghash = xCAT::DBobjUtils->getobjdefs(\%objtype, $callback);
	if (!(%imghash))
	{
		my $rsp;
		push @{$rsp->{data}}, "Could not get xCAT osimage definitions.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}

	# 
	# call dolitesetup() for each osimage needed for the nodes
	#	to re-do the statelite tables etc. in the shared_root dir
	#
	foreach my $i (@osimage)
    {

        #  dolitesetup to update the shared_root table files
		#  - updates files in the sopot and shared_root resour
        my $rc=xCAT::InstUtils->dolitesetup($i, \%imghash, \@{$osinodes{$i}}, $callback, $sub_req);
        if ($rc eq 1) { # error
            my $rsp;
            push @{$rsp->{data}}, "Could not complete the statelite setup.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
    } # end statelite setup

	#
    #  copy files to target SN
    #

	foreach my $i (@osimage)
	{
		my $SRname = $imghash{$i}{shared_root};

		if ($SRname) {
			my $srloc = xCAT::InstUtils->get_nim_attr_val( $imghash{$i}{shared_root}, "location", $callback, $nimprime, $sub_req);

			if ($srloc) {
				my $cpcmd = qq~$::XCATROOT/bin/xdcp $targetsn ~;
				my $output;
				if (-f "$srloc/statelite.table") {
					$cpcmd .= qq~$srloc/statelite.table ~;
				}

				if (-f "$srloc/litefile.table") {
					$cpcmd .= qq~$srloc/litefile.table ~;
				}

				if (-f "$srloc/litetree.table") {
					$cpcmd .= qq~$srloc/litetree.table ~;
				}

				if (-f "$srloc/aixlitesetup") {
					$cpcmd .= qq~$srloc/aixlitesetup ~;
				}
				$cpcmd .= qq~$srloc/ ~;

				$output=xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $nimprime, $cpcmd, 0);
				if ($::RUNCMD_RC != 0)
				{
					my $rsp;
					push @{$rsp->{data}}, "Could not copy new statelite file to $targetsn\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
				}

				my $ddir = "$srloc/.default";
				if (-d $ddir ) {
					$cpcmd = qq~$::XCATROOT/bin/xdcp $targetsn -R $srloc/.default $srloc/~;
				}

				$output=xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $nimprime, $cpcmd, 0);
				if ($::RUNCMD_RC != 0)
				{
					my $rsp;
					push @{$rsp->{data}}, "Could not copy new statelite information to $targetsn\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
				}
			}
		}
	}  # end copy files

	return 0;
}
