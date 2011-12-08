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
                    'l|statelite'     => \$::SLonly,    # update statelite only!
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

        #print Dumper(%nethash);

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

                    # get the short hostname
                    my $xcatmaster = xCAT::NetworkUtils->gethostname($IP);
                    $xcatmaster =~ s/\..*//;

                    # add the value to the hash
                    $newxcatmaster{$node} = $xcatmaster;
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

        #print "nfs=$nfs, sn1n=$sn1n, sn1n_ip=$sn1n_ip\n";
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

    #
    # do the rsync of statelite files form the primary SN to the backup
    #	SN if appropriate
    #
    my %SLmodhash;
    my %LTmodhash;

    if ($::isaix)
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
                    $SLmodhash{$item}{'node'}     = $line->{node};
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
                          "Synchronizing $old_node_hash->{$n}->{'oldmaster'}:$dir to $sn_hash{$n}{'xcatmaster'}\n";
                        xCAT::MsgUtils->message("I", $rsp, $callback);
                    }

                    my $todir = dirname($dodir);

                    # do rsync of file/dir
                    my $synccmd =
                      qq~$::XCATROOT/bin/prsync -o "rlHpEAogDz" $dodir $newsn{$n}:$todir 2>/dev/null~;

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

        if ($error)
        {
            return 1;
        }

        # if only statelite sync is required then return now
        if ($::SLonly)
        {
            return 0;
        }

    }    # end sync statelite and litetree entries

    if ($::VERBOSE)
    {
        my $rsp;
        push @{$rsp->{data}}, "Setting new values in the xCAT database.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }

	#
    # make updates to statelite table
	#
    if ($::isaix)
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
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "Could not run the nodeset command.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
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
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "Could not run the nodeset command.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    $error++;
                }
            }
        }
    }    # end - for Linux system only

    #
    # update the /etc/xcatinfo files on the nodes
    #	switch to the new server name
    #
if (0) {  # save this for later - not needed yet
    if (!$::IGNORE)
    {
        if ($::isaix)
        {

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
}  # end of not needed

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
            $rsp->{data}->[0] = "Setting up the default routes on the nodes.";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }
        foreach my $gw (keys %gwhash)
        {
            my $cmd =
              "route add default gw"
              ;    #this is temporary,TODO, set perminant route on the nodes.

            #            if (xCAT::Utils->isAIX())
            if ($::isaix)
            {
                $cmd = "route add default";
            }
            my $ret =
              xCAT::Utils->runxcmd(
                                   {
                                    command => ['xdsh'],
                                    node    => $gwhash{$gw},
                                    arg     => ["-v", "$cmd $gw"],
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
                my @valid_scripts = ("syslog", "setupntp", "mkresolvconf");
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

            my $ret =
              xCAT::Utils->runxcmd(
                                   {
                                    command => ['updatenode'],
                                    node    => $pos_nodes,
                                    arg     => ["-P", "$scripts", "-s"],
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

    #my ($class, $list, $callback, $subreq) = @_;
    my ($list, $callback, $subreq) = @_;

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
          xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $sn, $ifcmd, 0);
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

