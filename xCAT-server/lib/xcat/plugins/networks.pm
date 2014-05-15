# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::networks;
use xCAT::Table;
use Data::Dumper;
use Sys::Syslog;
use Socket;
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::NetworkUtils;
use xCAT::ServiceNodeUtils;
use Getopt::Long;

sub handled_commands
{
    return {makenetworks => "networks",};
}

sub preprocess_request
{
    my $req = shift;
    my $callback  = shift;

	# exit if preprocessed
	if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }
    
	my @requests = ({%$req}); #first element is local instance

	$::args = $req->{arg};
    if ( defined ($::args) && @{$::args} ) {
        @ARGV = @{$::args};
    } 

	Getopt::Long::Configure("no_pass_through");
    if (
        !GetOptions(
                    'help|h|?'    => \$::HELP,
					'display|d'	=> \$::DISPLAY,
					'verbose|V' => \$::VERBOSE,
                    'version|v' => \$::VERSION,
        )
      )
    {
    #    return 1;
    }

	# Option -h for Help
    if ($::HELP )
    {
        &makenetworks_usage($callback);
        return undef;
    }

	# Option -v for version - do we need this???
    if ($::VERSION)
    {
        my $rsp;
        my $version=xCAT::Utils->Version();
        $rsp->{data}->[0] = "makenetworks - $version";
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return undef;
    }

	# process the network interfaces on this system
    if (&donets($callback) != 0) {
        my $rsp;
        push @{$rsp->{data}}, "Could not get network information.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return undef;
    }

    my @sn = xCAT::ServiceNodeUtils->getSNList();
    foreach my $s (@sn)
    {
        my $reqcopy = {%$req};
        $reqcopy->{'_xcatdest'} = $s;
		$reqcopy->{_xcatpreprocessed}->[0] = 1;
        push @requests, $reqcopy;
    }

    return \@requests;
}

sub process_request
{
	my $request  = shift;
    my $callback = shift;

	$::args     = $request->{arg};

    if ( defined ($::args) && @{$::args} ) {
        @ARGV = @{$::args};
    }

    Getopt::Long::Configure("no_pass_through");
    if (
        !GetOptions(
                    'help|h|?'    => \$::HELP,
                    'display|d' => \$::DISPLAY,
                    'verbose|V' => \$::VERBOSE,
                    'version|v' => \$::VERSION,
        )
      )
    {
    #    return 1;
    }

	# process the network interfaces on this system
	#	- management node was already done
	if (!xCAT::Utils->isMN()) {
		if (&donets($callback) != 0) {
			my $rsp;
			push @{$rsp->{data}}, "Could not get network information.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}
	}
	return 0;
}

#----------------------------------------------------------------------------

=head3  donets
			Get network information and display or create xCAT network defs 

        Returns:
            0 - OK
            1 - error

        Usage:
			my $rc = &donets($callback);

=cut

#-----------------------------------------------------------------------------
sub donets
{
	my $callback = shift;

	my $host = `hostname`;
    chomp $host;

	# get all the existing xCAT network defs
    my @netlist;
    @netlist = xCAT::DBobjUtils->getObjectsOfType('network');

	my %nethash;
	if (scalar(@netlist)) {
		my %objtype;
    	foreach my $netn (@netlist) {
        	$objtype{$netn} = 'network';
    	}
	
    	%nethash = xCAT::DBobjUtils->getobjdefs(\%objtype, $callback);
    	if (!%nethash) {
        	my $rsp;
        	$rsp->{data}->[0] = "Could not get xCAT network definitions.\n";
        	xCAT::MsgUtils->message("E", $rsp, $::callback);
        	return 1;
    	}
	}

	my $nettab = xCAT::Table->new('networks', -create => 1, -autocommit => 0);

	if (xCAT::Utils->isAIX()) {

		# get list of interfaces "ifconfig -l"
		my $ifgcmd = "ifconfig -l";
		my @interfaces = split(/\s+/, xCAT::Utils->runcmd($ifgcmd, 0));
		if ($::RUNCMD_RC != 0) {
			my $rsp;
			push @{$rsp->{data}}, "Could not run \'$ifgcmd\'.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}

                my $master=xCAT::TableUtils->get_site_Master();
                my $masterip = xCAT::NetworkUtils->getipaddr($master);  
                if ($masterip =~ /:/) {
                    # do each ethernet interface for ipv6
	            foreach my $i (@interfaces) {

	               if ($i =~ /^en/) {
	    
                        # "ifconfig en0 |grep fe80" to get net and prefix length
                        my $cmd = "ifconfig $i |grep -i inet6";
                        my @netinfo = xCAT::Utils->runcmd($cmd, -1);
                        if ($::RUNCMD_RC != 0) {
                               # no ipv6 address configured 
                               next;
                        }

                        # only handle the ipv6 addr without %
                        foreach my $line (@netinfo)
                        {
                            next if ($line =~ /\%/);
                            
                            my $gateway;
                            my $netmask;
                            my @fields;

                            @fields = split(/ /, $line);
                            ($gateway, $netmask) = split(/\//, $fields[1]);

                            my $eip = Net::IP::ip_expand_address ($gateway,6);
                            my $bip = Net::IP::ip_iptobin($eip,6);
                            my $bmask = Net::IP::ip_get_mask($netmask,6);
                            my $bnet = $bip & $bmask;
                            my $ipnet = Net::IP::ip_bintoip($bnet,6);
                            my $net = Net::IP::ip_compress_address($ipnet,6);

                            my $netname = $net . "-" . $netmask;

                            # see if this network (or equivalent) is already defined
                            # - compare net and prefix_len values
                            my $foundmatch = 0;
                            foreach my $netn (@netlist) {
                                # get net and prefix_len
                                my $dnet = $nethash{$netn}{'net'};
                                my $dprefix_len = $nethash{$netn}{'mask'};

                                if (($net == $dnet) && ($netmask == $dprefix_len))
                                {
                                    $foundmatch = 1;
                                    last;
                                }
                            }

                            if ($::DISPLAY) {
                                    my $rsp;
                                    push @{$rsp->{data}}, "\n#From $host.";
                pus    h @{$rsp->{data}}, "$netname:";
                                    push @{$rsp->{data}}, "    objtype=network";
                                    push @{$rsp->{data}}, "    net=$net";
                                    push @{$rsp->{data}}, "    mask=$netmask";
                                    push @{$rsp->{data}}, "    mgtifname=$i";
                                    push @{$rsp->{data}}, "    gateway=$gateway\n";
                                    if ($foundmatch) {
                pus    h @{$rsp->{data}}, "# Note: An equivalent xCAT network definition already exists.\n";
                                    }
                xCA    T::MsgUtils->message("I", $rsp, $callback);
                            } else {

                                    if ($foundmatch) {
                                        next;
                                    }

                                    # add new network def
                                    $nettab->setAttribs({'net' => $net, 'mask' => $netmask}, {'netname' => $netname, 'gateway' => $gateway, 'mgtifname' => $i});
                            }
                        }
                }  
            }
        } else {
            # do each ethernet interface for ipv4
            foreach my $i (@interfaces) {
    
                if ($i =~ /^en/) {
    
            		# "mktcpip -S en0" to get nm & gw
            		my $mkcmd = "mktcpip -S $i";
            		my @netinfo = xCAT::Utils->runcmd($mkcmd, 0);
            		if ($::RUNCMD_RC != 0) {
            			my $rsp;
            			push @{$rsp->{data}}, "Could not run \'$mkcmd\'.\n";
            			xCAT::MsgUtils->message("E", $rsp, $callback);
            			return 1;
            		}
    
            		my $netmask;
            		my $ipaddr;
            		my @fields;
            		my $gateway;
            		foreach my $line (@netinfo) {
            			next if ($line =~ /^\s*#/);
    
            			@fields = split(/:/, $line);
            		}
            		$ipaddr = $fields[1];
            		$netmask = $fields[2];
                        if ($fields[6])
                        {
                            if(xCAT::NetworkUtils::isInSameSubnet($fields[6], $ipaddr, $netmask, 0))
                            {
                                $gateway = $fields[6]; 
                            }
                        }

                        # set gateway to keyword <xcatmaster>,
                        # to indicate to use the cluster-facing ip address 
                        # on this management node or service node
                        if (!$gateway)
                        {
                            $gateway = "<xcatmaster>";
                        }
                        
    
            		# split interface IP
                    my ($ip1, $ip2, $ip3, $ip4) = split('\.', $ipaddr);
    
            		# split mask
                    my ($m1, $m2, $m3, $m4) = split('\.', $netmask);
    
            		# AND nm and ip to get net attribute
            		my $n1 = ((int $ip1) & (int $m1));
                    my $n2 = ((int $ip2) & (int $m2));
                    my $n3 = ((int $ip3) & (int $m3));
                    my $n4 = ((int $ip4) & (int $m4));
    
            		my $net = "$n1.$n2.$n3.$n4";
    
            		# use convention for netname attr
            		my $netn;
            		my $maskn;
            		($netn = $net) =~ s/\./\_/g;
            		($maskn = $netmask) =~ s/\./\_/g;
            		#  ( 1_2_3_4-255_255_255_192 - ugh!)
            		my $netname = $netn . "-" . $maskn;
    
            		# see if this network (or equivalent) is already defined
            		# - compare net and mask values
                            my $foundmatch = 0;
            		foreach my $netn (@netlist) {
            			# split definition mask
            			my ($dm1, $dm2, $dm3, $dm4) = split('\.', $nethash{$netn}{'mask'});
    
            			# split definition net addr
            			my ($dn1, $dn2, $dn3, $dn4) = split('\.', $nethash{$netn}{'net'});
    
            			# check for the same netmask and network address
            			if ( ($n1 == $dn1) && ($n2 ==$dn2) && ($n3 == $dn3) && ($n4 == $dn4) ) {
            				if ( ($m1 == $dm1) && ($m2 ==$dm2) && ($m3 == $dm3) && ($m4== $dm4) ) {
            					$foundmatch=1;
                                                    last;
            				}
            			}
            		}
    
            		if ($::DISPLAY) {
            			my $rsp;
            			push @{$rsp->{data}}, "\n#From $host.";
                		push @{$rsp->{data}}, "$netname:";
            			push @{$rsp->{data}}, "    objtype=network";
            			push @{$rsp->{data}}, "    net=$net";
            			push @{$rsp->{data}}, "    mask=$netmask";
            		        push @{$rsp->{data}}, "    mgtifname=$i";	
            			push @{$rsp->{data}}, "    gateway=$gateway\n";
            			if ($foundmatch) {
                            push @{$rsp->{data}}, "# Note: An equivalent xCAT network definition already exists.\n";
            			}
                		xCAT::MsgUtils->message("I", $rsp, $callback);
            		} else {
    
            			if ($foundmatch) {
                            next;
                        }
    
            			# add new network def 
            			$nettab->setAttribs({'net' => $net, 'mask' => $netmask}, {'netname' => $netname, 'gateway' => $gateway, 'mgtifname' => $i});
            		}
    	        }
            } # end foreach
        } #end if ipv4

      } else { 

		# For Linux systems
        my @ip6table = split /\n/,`/sbin/ip -6 route`;
    	my @rtable = split /\n/, `/bin/netstat -rn`;

    	splice @rtable, 0, 2;

        my %netgw = ();
    	foreach my $rtent (@rtable)
        { 
            my @entarr = split /\s+/, $rtent;
            if ($entarr[3] eq 'UG')
            {
                $netgw{$entarr[0]}{$entarr[2]} = $entarr[1];
            }
        }
        #routers advertise their role completely outside of DHCPv6 scope, we don't need to
        #get ipv6 routes and in fact *cannot* dictate router via DHCPv6 at this specific moment.
        foreach (@ip6table)
        { 
            my @ent = split /\s+/, $_;
            if ($ent[0] eq 'fe80::/64' or $ent[0] eq 'unreachable' or $ent[1] eq 'via') {
                #Do not contemplate link-local, unreachable, or gatewayed networks further
                #DHCPv6 relay will be manually entered into networks as was the case for IPv4
                next;
            }
            my $net = shift @ent;
            my $dev = shift @ent;
            if ($dev eq 'dev') {
                $dev = shift @ent;
            } else {
                die "Unrecognized IPv6 routing entry $_";
            }
            my @myv6addrs=split /\n/,`ip -6 addr show dev $dev scope global`;
            #for v6, deprecating mask since the CIDR slash syntax is ubiquitous
            my $consideredaddr=$net;
            $consideredaddr=~ s!/(.*)!!;
            my $consideredbits=$1;
            #below may be redundant, but apply resolution in case ambiguous net, e.g. 2001:0db8:0::/64 is the same thing as 2001:0db8::/64
            $consideredaddr = xCAT::NetworkUtils->getipaddr($consideredaddr);
            my $netexists=0;
			foreach my $netn (@netlist) { #search for network that doesn't exist yet
                    my $curnet=$nethash{$netn}{'net'};
                    unless ($curnet =~ /:/) {  #only ipv6 here
                        next;
                    }
                    $curnet =~ s!/(.*)!!; #remove 
                    my $curnetbits=$1;
                    unless ($consideredbits==$curnetbits) { #only matches if netmask matches
                        next;
                    }
					$currnet = xCAT::NetworkUtils->getipaddr($currnet);
                    unless ($currnet eq  $consideredaddr) {
                        next;
                    }
                    $netexists=1;
            }
			if ($::DISPLAY) {
				push @{$rsp->{data}}, "\n#From $host.";
				push @{$rsp->{data}}, "$net:";
				push @{$rsp->{data}}, "    objtype=network";
                   push @{$rsp->{data}}, "    net=$net";
                   push @{$rsp->{data}}, "    mgtifname=$dev";
			} else {
				unless ($netexiss) {
				    	my $tmpmask = $net;
			            	$tmpmask =~ s!^.*/!/!;
					$nettab->setAttribs({'net' => $net, 'mask' => $tmpmask}, {'netname' => $net, 'mgtifname' => $dev});
				}
			}
            
        }
    	foreach (@rtable)
    	{ #should be the lines to think about, do something with U, and something else with UG

			my $foundmatch=0;
			my $rsp;
        	my $net;
        	my $mask;
        	my $mgtifname;
        	my $gw;
        	my @ent = split /\s+/, $_;
        	my $firstoctet = $ent[0];
        	$firstoctet =~ s/^(\d+)\..*/$1/;

        	if ($ent[0] eq "169.254.0.0" or ($firstoctet >= 224 and $firstoctet <= 239) or $ent[0] eq "127.0.0.0")
        	{
            	next;
        	}

        	if ($ent[3] eq 'U')
        	{
            	$net       = $ent[0];
            	$mask      = $ent[2];
				$mgtifname = $ent[7];
                if (defined($netgw{'0.0.0.0'}{'0.0.0.0'}))
                {
                    if(xCAT::NetworkUtils->ishostinsubnet($netgw{'0.0.0.0'}{'0.0.0.0'}, $mask, $net))
                    {
                        $gw =  $netgw{'0.0.0.0'}{'0.0.0.0'}; #default gatetway
                    }
                }
                # set gateway to keyword <xcatmaster>,
                # to indicate to use the cluster-facing ip address 
                # on this management node or service node
                if (!$gw)
                {
                    $gw = "<xcatmaster>";
                }

				# use convention for netname attr
                my $netn;
                my $maskn;
                ($netn = $net) =~ s/\./\_/g;
                ($maskn = $mask) =~ s/\./\_/g;
                #  ( 1_2_3_4-255_255_255_192 - ugh!)
                my $netname = $netn . "-" . $maskn;

				# see if this network (or equivalent) is already defined
                # - compare net and mask values

				# split mask
                my ($m1, $m2, $m3, $m4) = split('\.', $mask);

				# split net addr
				my ($n1, $n2, $n3, $n4) = split('\.', $net);

				foreach my $netn (@netlist) {

					# split definition mask
					my ($dm1, $dm2, $dm3, $dm4) = split('\.', $nethash{$netn}{'mask'});

					# split definition net addr
					my ($dn1, $dn2, $dn3, $dn4) = split('\.', $nethash{$netn}{'net'});

					# check for the same netmask and network address
					if ( ($n1 == $dn1) && ($n2 ==$dn2) && ($n3 == $dn3) && ($n4 == $dn4) ) {
						if ( ($m1 == $dm1) && ($m2 ==$dm2) && ($m3 == $dm3) && ($m4== $dm4) ) {
							$foundmatch=1;
						}
					}
				}

				if ($::DISPLAY) {
					push @{$rsp->{data}}, "\n#From $host.";
					push @{$rsp->{data}}, "$netname:";
					push @{$rsp->{data}}, "    objtype=network";
                    push @{$rsp->{data}}, "    net=$net";
                    push @{$rsp->{data}}, "    mask=$mask";
                    if ($gw)
                    {
                        push @{$rsp->{data}}, "    gateway=$gw";
                    }
                    push @{$rsp->{data}}, "    mgtifname=$mgtifname";
				} else {
					if (!$foundmatch) {
						$nettab->setAttribs({'net' => $net, 'mask' => $mask}, {'netname' => $netname, 'mgtifname' => $mgtifname, 'gateway' => $gw});
					}
				}
            	
            	unless ($tent and $tent->{tftpserver})
            	{
                	my $netdev = $ent[7];
                	my @netlines = split /\n/, `/sbin/ip addr show dev $netdev`;
                	foreach (grep /\s*inet\b/, @netlines)
                	{
                    	my @row = split(/\s+/, $_);
                    	my $ipaddr = $row[2];
                    	$ipaddr =~ s/\/.*//;
                    	my @maska = split(/\./, $mask);
                    	my @ipa   = split(/\./, $ipaddr);
                    	my @neta  = split(/\./, $net);
                    	my $isme  = 1;
                    	foreach (0 .. 3)
                    	{
                        	my $oct = (0 + $maska[$_]) & ($ipa[$_] + 0);
                        	unless ($oct == $neta[$_])
                        	{
                            	$isme = 0;
                            	last;
                        	}
                    	}
                    	if ($isme)
                    	{
							if ($::DISPLAY) {
                        		push @{$rsp->{data}}, "    tftpserver=$ipaddr";
                    		} else {
								if (!$foundmatch) {
                        			$nettab->setAttribs({'net' => $net, 'mask' => $mask}, {tftpserver => $ipaddr});
								}
							}
                        	last;
                    	}
                	}
            	}
            	#Nothing much sane to do for the other fields at the moment?
        	}
        	elsif ($ent[3] eq 'UG')
        	{

            	#TODO: networks through gateway. and how we might care..
        	}
        	else
        	{

            	#TODO: anything to do with such entries?
        	}

			if ($::DISPLAY) {

				if ($foundmatch) {
					push @{$rsp->{data}}, "# Note: An equivalent xCAT network definition already exists.\n";
				}
				xCAT::MsgUtils->message("I", $rsp, $callback);
			}
    	}
	}

	$nettab->commit;

	return 0;
}

#----------------------------------------------------------------------------

=head3  makenetworks_usage

=cut

#-----------------------------------------------------------------------------

sub makenetworks_usage
{
	my $callback = shift;

    my $rsp;
	push @{$rsp->{data}}, "\nUsage: makenetworks - Gather cluster network information and add it to the xCAT database.\n";
	push @{$rsp->{data}}, "  makenetworks [-h|--help ]\n";
	push @{$rsp->{data}}, "  makenetworks [-v|--version]\n";
	push @{$rsp->{data}}, "  makenetworks [-V|--verbose] [-d|--display]\n";
    xCAT::MsgUtils->message("I", $rsp, $callback);
    return 0;
}

1;
