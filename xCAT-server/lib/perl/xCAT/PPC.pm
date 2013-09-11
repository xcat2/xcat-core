# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPC;
use strict;
use lib "/opt/xcat/lib/perl";
use xCAT::Table;
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::ServiceNodeUtils;
use xCAT::SvrUtils;
use xCAT::FSPUtils;
use xCAT::Usage;
use POSIX "WNOHANG";
use Storable qw(freeze thaw);
use Time::HiRes qw(gettimeofday sleep);
use IO::Select;
use Socket;
use xCAT::PPCcli; 
use xCAT::GlobalDef;
use xCAT::DBobjUtils;
use xCAT_monitoring::monitorctrl;
use Thread qw(yield);
use xCAT::PPCdb;
#use Data::Dumper;

##########################################
# Globals
##########################################
my %modules = (
        rinv      => { hmc    => "xCAT::PPCinv",
                       ivm   => "xCAT::PPCinv",
                       fsp    => "xCAT::FSPinv",
                       bpa    => "xCAT::FSPinv",
                       cec    => "xCAT::FSPinv",
                       frame  => "xCAT::FSPinv",
                       },
        rpower    => { hmc    => "xCAT::PPCpower",
                       ivm   => "xCAT::PPCpower",
                       fsp    => "xCAT::FSPpower",
                       bpa    => "xCAT::FSPpower",
                       cec    => "xCAT::FSPpower",
                       frame  => "xCAT::FSPpower",
                       },
        rvitals   => { hmc    => "xCAT::PPCvitals",
                       fsp    => "xCAT::FSPvitals",
                       bpa    => "xCAT::FSPvitals",
                       cec    => "xCAT::FSPvitals",
                       frame  => "xCAT::FSPvitals",
                       },
        rscan     => { hmc    => "xCAT::PPCscan",
                       fsp    => "xCAT::FSPscan",
                       cec    => "xCAT::FSPscan",
                       ivm    => "xCAT::PPCscan",
                       },
        mkvm      => { hmc    => "xCAT::PPCvm",
                       fsp    => "xCAT::FSPvm",
                       cec    => "xCAT::FSPvm",
                      },
        rmvm      => { hmc    => "xCAT::PPCvm",
                       fsp    => "xCAT::FSPvm",
                      },
        lsvm      => { hmc    => "xCAT::PPCvm",
                       fsp    => "xCAT::FSPvm",
                       cec    => "xCAT::FSPvm",
                      },
        chvm      => { hmc    => "xCAT::PPCvm",
                       fsp    => "xCAT::FSPvm",
                       cec    => "xCAT::FSPvm",
                      },
        rnetboot  => { hmc    => "xCAT::PPCboot",
                       ivm    => "xCAT::PPCboot",
                       fsp    => "xCAT::FSPboot",
                       cec    => "xCAT::FSPboot",
                      },
        getmacs   => { hmc    => "xCAT::PPCmac",
                       ivm    => "xCAT::PPCmac",
                       fsp    => "xCAT::FSPmac",
                       cec    => "xCAT::FSPmac",
                      },
        reventlog => { hmc    => "xCAT::PPClog",
                      },
        rspconfig => { hmc    => "xCAT::PPCcfg",
                       fsp    => "xCAT::FSPcfg",
                       bpa    => "xCAT::FSPcfg",
                       cec    => "xCAT::FSPcfg",
                       blade    => "xCAT::FSPcfg",
                       frame  => "xCAT::FSPcfg",
                      },
        rflash    => { hmc    => "xCAT::PPCrflash",
                       fsp    => "xCAT::FSPflash",
                       bpa    => "xCAT::FSPflash",
                       cec    => "xCAT::FSPflash",
                       frame  => "xCAT::FSPflash",
                      },
        mkhwconn  => { hmc    => "xCAT::PPCconn",
                       fsp    => "xCAT::FSPconn",
                       cec    => "xCAT::FSPconn",
                       bpa    => "xCAT::FSPconn",
                       frame  => "xCAT::FSPconn",
                      },
        rmhwconn  => { hmc    => "xCAT::PPCconn",
                       fsp    => "xCAT::FSPconn",
                       cec    => "xCAT::FSPconn",
                       bpa    => "xCAT::FSPconn",
                       frame  => "xCAT::FSPconn",
                      },
        lshwconn  => { hmc    => "xCAT::PPCconn",
                       fsp    => "xCAT::FSPconn",
                       cec    => "xCAT::FSPconn",
                       bpa    => "xCAT::FSPconn",
                       frame  => "xCAT::FSPconn",
                      },
        renergy   => { hmc    => "xCAT::PPCenergy",
                       fsp    => "xCAT::PPCenergy",
                       cec    => "xCAT::PPCenergy",
                     },
        rbootseq  => { fsp    => "xCAT::FSPbootseq",
                       cec    => "xCAT::FSPbootseq",
             },
        );


##########################################
# Database errors
##########################################
my %errmsg = (
        NODE_UNDEF =>"Node not defined in '%s' database",
        NO_ATTR    =>"'%s' not defined in '%s' database",  
        NO_UNDEF   =>"'%s' not defined in '%s' database for '%s'",
        DB_UNDEF   =>"'%s' database not defined"
        );

##########################################################################
# Invokes the callback with the specified message                    
##########################################################################
sub send_msg {

    my $request = shift;
    my $ecode   = shift;
    my %output;

    #################################################
    # Called from child process - send to parent
    #################################################
    if ( exists( $request->{pipe} )) {
        my $out = $request->{pipe};

        $output{errorcode} = $ecode;
        $output{data} = \@_;
        print $out freeze( [\%output] );
        print $out "\nENDOFFREEZE6sK4ci\n";
    }
    #################################################
    # Called from parent - invoke callback directly
    #################################################
    elsif ( exists( $request->{callback} )) {
        my $callback = $request->{callback};

        $output{errorcode} = $ecode;
        $output{data} = \@_;
        $callback->( \%output );
    }
}


##########################################################################
# Fork child to execute remote commands
##########################################################################
sub process_command {

    my $request  = shift;
    my $hcps_will= shift;
    my $failed_nodes = shift;
    my $failed_msg = shift;
    my %nodes    = ();
    my $callback = $request->{callback};
    #my $sitetab  = xCAT::Table->new( 'site' );
    my @site     = qw(ppcmaxp ppctimeout maxssh ppcretry fsptimeout powerinterval syspowerinterval); 
    my $start;
    my $verbose = $request->{verbose};

    #######################################
    # Default site table attributes 
    #######################################
    $request->{ppcmaxp}    = 64;
    $request->{ppctimeout} = 0;
    $request->{fsptimeout} = 0;
    $request->{ppcretry}   = 3;
    $request->{maxssh}     = 8;
    $request->{powerinterval}     = 0;
    $request->{syspowerinterval}     = 0;

    #######################################
    # Get site table attributes 
    #######################################
    foreach ( @site ) {
        my @val = xCAT::TableUtils->get_site_attribute($_); 
        if ( defined($val[0]) ) { 
            $request->{$_} = $val[0]; 
        }
    } 
    if ( exists( $request->{verbose} )) {
        $start = Time::HiRes::gettimeofday();
    }

    #######################################
    # Group nodes based on command
    #######################################
    my $nodes;
    unless ($request->{command} =~ /^rspconfig$/&& exists( $request->{opt}->{resetnet})){

        $nodes = preprocess_nodes( $request, $hcps_will );
        if ( !defined( $nodes )) {
            return(1);
        }
    }
    
    #get new node status
    my %oldnodestatus=(); #saves the old node status
        my @allerrornodes=();
    my $check=0;
    my $global_check=1;
    my @val = xCAT::TableUtils->get_site_attribute("nodestatus");
    if (defined($val[0])) {
            if ($val[0] =~ /0|n|N/) { $global_check=0; }
        }

    my $command=$request->{command};
    if (($command eq 'rpower') || ($command eq 'rnetboot')) {
        my $subcommand="temp";
        if ($command eq 'rpower') {  $subcommand=$request->{op}; }
        if (($global_check) && ($subcommand ne 'stat') && ($subcommand ne 'status') && ($subcommand ne 'state')) { 
            $check=1; 
            my $noderange = $request->{node}; 
            my @allnodes=@$noderange;

            #save the old status
            my $nodelisttab = xCAT::Table->new('nodelist');
            if ($nodelisttab) {
                my $tabdata     = $nodelisttab->getNodesAttribs(\@allnodes, ['node', 'status']);
                foreach my $node (@allnodes)
                {
                    my $tmp1 = $tabdata->{$node}->[0];
                    if ($tmp1) { 
                        if ($tmp1->{status}) { $oldnodestatus{$node}=$tmp1->{status}; }
                        else { $oldnodestatus{$node}=""; }
                    }
                }
            }
            #print "oldstatus:" . Dumper(\%oldnodestatus);

            #set the new status to the nodelist.status
            my %newnodestatus=(); 
            my $newstat;
            if (($subcommand eq 'off') || ($subcommand eq 'softoff')) { 
                my $newstat=$::STATUS_POWERING_OFF; 
                $newnodestatus{$newstat}=\@allnodes;
            } else {
                #get the current nodeset stat
                if (@allnodes>0) {
                    my $nsh={};
                    my ($ret, $msg)=xCAT::SvrUtils->getNodesetStates(\@allnodes, $nsh);
                    if (!$ret) { 
                        foreach (keys %$nsh) {
                            my $newstat=xCAT_monitoring::monitorctrl->getNodeStatusFromNodesetState($_, $command);
                            $newnodestatus{$newstat}=$nsh->{$_};
                        }
                    } else {
                        trace( $request, $msg );
                    }
                }
            }
            #donot update node provision status (installing or netbooting) here
            xCAT::Utils->filter_nostatusupdate(\%newnodestatus);
            #print "newstatus" . Dumper(\%newnodestatus);
            xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%newnodestatus, 1);
        }
    }



    #######################################
    # Fork process
    #######################################
    my $children = 0;
    my $fds = new IO::Select;

    # For the commands getmacs and rnetboot, each time 
    # to fork process, pick out the HMC that has the 
    # least process number created to connect to the HMC.
    # After the process by preprocess_nodes, the $nodes 
    # variable has following structure:
    # $nodes
    #   |hcp
    #       |[[hcp,node1_attr], [hcp,node2_attr] ...]
    #       |count    //node number managed by the hcp
    #       |runprocess    //the process number connect to the hcp
    #       |index    //the index of node will be forked of the hcp
    if ( ($request->{command} =~ /^(getmacs)$/ && exists( $request->{opt}->{D} )) || ($request->{command} =~ /^(rnetboot)$/) || ($request->{command} =~ /^(rbootseq)$/) ) {
        my %pid_owner = ();

        $request->{maxssh} = int($request->{maxssh}/2);
        # Use the CHID signal to control the 
        #connection number of certain hcp    
        $SIG{CHLD} = sub { my $pid = 0; while (($pid = waitpid(-1, WNOHANG)) > 0) 
            { $nodes->{$pid_owner{$pid}}{'runprocess'}--; delete $pid_owner{$pid}; $children--; } };

        $SIG{INT} = $SIG{TERM} = sub { #prepare to process job termination and propogate it down
            foreach (keys %pid_owner) {
                kill 9, $_;
            }
            exit 0;
        };

        my $hasnode = 1;
        while ($hasnode) {
            while ( $children >= $request->{ppcmaxp} ) {
                my $handlednodes={};
                child_response( $callback, $fds, $handlednodes, $failed_nodes, $failed_msg, $verbose);

                #update the node status to the nodelist.status table
                if ($check) {
                    updateNodeStatus($handlednodes, \@allerrornodes);
                }

                Time::HiRes::sleep(0.1);
            }
            # Pick out the hcp which has least processes
            my $least_processes = $request->{maxssh};
            my $least_hcp;
            my $got_one = 0;
            while (!$got_one) {
                $hasnode = 0;
                foreach my $hcp (keys %$nodes) {
                    if ($nodes->{$hcp}{'index'} < $nodes->{$hcp}{'count'}) {
                        $hasnode = 1;
                        if ($nodes->{$hcp}{'runprocess'} < $least_processes) {
                            $least_processes = $nodes->{$hcp}{'runprocess'};
                            $least_hcp = $hcp;
                        }
                    }
                }

                if (!$hasnode) {
                    # There are no node in the $nodes
                    goto ENDOFFORK;
                }

                if ($least_processes < $request->{maxssh}) {
                    $got_one = 1;
                } else {
                    my $handlednodes={};
                    child_response( $callback, $fds, $handlednodes, $failed_nodes, $failed_msg, $verbose);

                    #update the node status to the nodelist.status table
                    if ($check) {
                        updateNodeStatus($handlednodes, \@allerrornodes);
                    }
                    Time::HiRes::sleep(0.1);
                }
            }

            Time::HiRes::sleep(0.1);
            my ($pipe, $pid) = fork_cmd( $nodes->{$least_hcp}{'nodegroup'}->[$nodes->{$least_hcp}{'index'}]->[0], 
                    $nodes->{$least_hcp}{'nodegroup'}->[$nodes->{$least_hcp}{'index'}]->[1], $request );

            if ($pid) {
                $pid_owner{$pid} = $least_hcp;
                $nodes->{$least_hcp}{'index'}++;
                $nodes->{$least_hcp}{'runprocess'}++;
            }

            if ( $pipe ) {
                $fds->add( $pipe );
                $children++;
            }
        }
    } elsif ( $request->{command} =~ /^(getmacs)$/ && exists( $request->{opt}->{arp} ) ) {
        my $display = "";
        if (defined($request->{opt}->{d})) {
            $display = "yes";
        }
        my $output = xCAT::SvrUtils->get_mac_by_arp($nodes, $display);
        
        my $rsp = ();
        foreach my $node (keys %{$output}) {
            push @{$rsp->{node}}, {name => [$node], data => [$output->{$node}]};
        }
        $rsp->{errorcode} = 0;
        $callback->($rsp);
    } elsif ( $request->{command} =~ /^rpower$/ ) {
        my $hw;
        my $sessions;
        my $pid_owner;
        my $remain_node = $nodes;
        my $num = 0;        

        while ( scalar($remain_node) ) {
            $remain_node = ();
            foreach my $hash ( @$nodes ) {
                $SIG{CHLD} = sub { my $pid = 0; while (($pid = waitpid(-1, WNOHANG)) > 0) { $hw->{$pid_owner->{$pid}}--; $children--; } };
                $SIG{INT} = $SIG{TERM} = $SIG{KILL} = sub { #prepare to process job termination and propogate it down
                    foreach my $pid (keys %{$pid_owner}) {
                        &kill_children_by_pid($pid);
                    }
                    exit 0;
                };
 
                while ( $children >= $request->{ppcmaxp} ) {
                    my $handlednodes={};
                    child_response( $callback, $fds, $handlednodes, $failed_nodes, $failed_msg, $verbose);

                    #update the node status to the nodelist.status table
                    if ($check) {
                        updateNodeStatus($handlednodes, \@allerrornodes);
                    }

                    Time::HiRes::sleep(0.1);
                }
                if ( $hw->{@$hash[0]} >= $request->{maxssh} ) {
                    my $handlednodes={};
                    child_response( $callback, $fds, $handlednodes, $failed_nodes, $failed_msg, $verbose);

                    #update the node status to the nodelist.status table
                    if ($check) {
                        updateNodeStatus($handlednodes, \@allerrornodes);
                    }

                    Time::HiRes::sleep(0.1);
                    push( @$remain_node, [@$hash[0], @$hash[1]] );
                    next;
                }
        
                if( $num > 0 && $request->{op} =~ /^on/ && $request->{fsp_api} == 1) {
		    my $t_hash = @$hash[1];
                    my $one_key_in_thash = (keys %$t_hash)[0];
                    my $one_d = $t_hash->{$one_key_in_thash};
                    #print Dumper($one_d);
                    if($$one_d[4]  =~ /^fsp$/ ||  $$one_d[4] =~ /^cec$/) {
                        if( $request->{syspowerinterval} > 0) {
                            no_interrupt_sleep($request->{syspowerinterval});
                        }
                    }
                }

                my ($pipe,$pid) = fork_cmd( @$hash[0], @$hash[1], $request );

                $num++;

                if ($pid) {
                    $pid_owner->{$pid} = @$hash[0];
                    $hw->{@$hash[0]}++;
                }

                if ( $pipe ) {
                    $fds->add( $pipe );
                    $children++;
                }
            }

            $nodes = $remain_node;
        }
    }  elsif ( $request->{command} =~ /^rspconfig$/&& exists( $request->{opt}->{resetnet} ) ) {
        runcmd( $request );
    } else {
        my %pid_owner = ();
        $SIG{CHLD} = sub { while (waitpid(-1, WNOHANG) > 0) { $children--; } };
        $SIG{INT} = $SIG{TERM} = $SIG{KILL} = sub { #prepare to process job termination and propogate it down
                foreach my $pid (keys %pid_owner) {
                    &kill_children_by_pid($pid);
                }
                exit 0;
        };
        my $hw;
        my $sessions;

        foreach ( @$nodes ) {
            while ( $children >= $request->{ppcmaxp} ) {
                my $handlednodes={};
                child_response( $callback, $fds, $handlednodes, $failed_nodes, $failed_msg, $verbose);

                #update the node status to the nodelist.status table
                if ($check) {
                    updateNodeStatus($handlednodes, \@allerrornodes);
                }

                Time::HiRes::sleep(0.1);
            }
            ###################################
            # sleep between connects to same
            # HMC/IVM so as not to overwelm it
            ###################################
            if ( $hw ne @$_[0] ) {
                $sessions = 1;
            } elsif ( $sessions++ >= $request->{maxssh} ) {
                sleep(1);
                $sessions = 1;
            }
            $hw = @$_[0];

            my ($pipe,$pid) = fork_cmd( @$_[0], @$_[1], $request );
            if ( $pipe ) {
                $pid_owner{$pid} = $pid;
                $fds->add( $pipe );
                $children++;
            }
        }
    }

ENDOFFORK:
    #######################################
    # Process responses from children
    #######################################
    while ( $fds->count > 0 or $children > 0 ) {
        my $handlednodes={};
        child_response( $callback, $fds, $handlednodes, $failed_nodes, $failed_msg, $verbose);

        #update the node status to the nodelist.status table
        if ($check) {
            updateNodeStatus($handlednodes, \@allerrornodes);
        }

        Time::HiRes::sleep(0.1);
    }

    #drain one more time
    my $rc=1;
    while ( $rc>0 ) {
        my $handlednodes={};
        $rc=child_response( $callback, $fds, $handlednodes, $failed_nodes, $failed_msg, $verbose);
        #update the node status to the nodelist.status table
        if ($check) {
            updateNodeStatus($handlednodes, \@allerrornodes);
        }
    }

    if ( exists( $request->{verbose} )) {
        my $elapsed = Time::HiRes::gettimeofday() - $start;
        my $msg     = sprintf( "Total Elapsed Time: %.3f sec\n", $elapsed );
        trace( $request, $msg );
    }

    if ($check) {
        #print "allerrornodes=@allerrornodes\n";
        #revert the status back for there is no-op for the nodes
        my %old=(); 
        foreach my $node (@allerrornodes) {
            my $stat=$oldnodestatus{$node};
            if (exists($old{$stat})) {
                my $pa=$old{$stat};
                push(@$pa, $node);
            }
            else {
                $old{$stat}=[$node];
            }
        } 
        xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%old, 1);
    }  


    return(0);
}

sub no_interrupt_sleep {
    my $sleep_time = shift;
    my $sleep_end = time + $sleep_time;
    while (1) {
        my $sleep_duration = $sleep_end - time;
        last if $sleep_duration <= 0;
        Time::HiRes::sleep($sleep_duration);
    }
}

sub kill_children_by_pid {
    my $pid = shift;
    my @pids = `ps -o pid,ppid -e`;
    for my $a_pid (@pids) {
        if( $a_pid =~ /\s*(\d*)\s*(\d*)/ ) {
            my $tmp_pid = $1;
            my $tmp_ppid = $2;
            if($tmp_ppid == $pid) {
                kill 9, $tmp_pid;
            }
        }
    }
}

##########################################################################
# updateNodeStatus
##########################################################################
sub updateNodeStatus {
    my $handlednodes=shift;
    my $allerrornodes=shift;
    foreach my $node (keys(%$handlednodes)) {
        if ($handlednodes->{$node} == -1) { push(@$allerrornodes, $node); }  
    }
}

##########################################################################
# Verbose mode (-V)
##########################################################################
sub trace {

    my $request = shift;
    my $msg   = shift;

    my ($sec,$min,$hour,$mday,$mon,$yr,$wday,$yday,$dst) = localtime(time);
    my $formatted = sprintf "%02d:%02d:%02d %5d %s", $hour,$min,$sec,$$,$msg;

    my $callback = $request->{callback};
    $callback->( {data=>[$formatted]} );
}


##########################################################################
# Send response from child process back to xCAT client
##########################################################################
sub child_response {

    my $callback = shift;
    my $fds = shift;
    my $errornodes=shift;
    my $failed_nodes=shift;
    my $failed_msg=shift;
    my $verbose=shift;
    my @ready_fds = $fds->can_read(1);
    my $rc = @ready_fds;
    my $mkvm_cec; 

    foreach my $rfh (@ready_fds) {
        my $data = <$rfh>;

        #################################
        # Read from child process
        #################################
        if ( defined( $data )) {
            while ($data !~ /ENDOFFREEZE6sK4ci/) {
                $data .= <$rfh>;
            }
            my $responses = thaw($data);
	    my @nodes;
	    foreach ( @$responses ) {
     	    	my $node = $_->{node}->[0]->{name}->[0];
		if (! grep /^$node$/, @nodes) {
     	    		push (@nodes, $node);
		}
	    }

	    foreach ( sort @nodes ) {
     		my $nodename = $_;
     		foreach ( @$responses ) {
	  		if ($nodename eq $_->{node}->[0]->{name}->[0]) {
                                # One special case for mkvm to output some messages 
                                if((exists($_->{errorcode})) && ($_->{errorcode} eq "mkvm" )) {
                                     $mkvm_cec = $nodename;
                                     next;    
                                }
                		#save the nodes that has errors for node status monitoring
          			if ((exists($_->{errorcode})) && ($_->{errorcode} != 0))  {
		        	    #if($$failed_nodes[0] !~ /^noloop$/) {
                                                #if (!grep /^$nodename$/, @$failed_nodes) {
				         	#     push(@$failed_nodes, $nodename);
				         	#}
					        #if( defined( $failed_msg->{$nodename} )) {
					        #    my $f = $failed_msg->{$nodename}; 
					        #    my $c = scalar(@$f);
					        #    $failed_msg->{$nodename}->[$c] = $_;
					        #} else {
					        #    $failed_msg->{$nodename}->[0] = $_;
					        #}
                                    #} else {
                                        #$callback->( $_ );
                                    #} 

                                if ($errornodes) { $errornodes->{$_->{node}->[0]->{name}->[0]}=-1; }
               			#if verbose, print all the message;
			     		#if not, print successful mesg for success, or all the failed mesg for failed.
				     	#if ( $verbose ) {
				        #    $callback->( $_ );
					#    }


                		} else {
                     	            if ($errornodes) { $errornodes->{$_->{node}->[0]->{name}->[0]}=1; }
                              #$callback->( $_ );
                		}
                        $callback->( $_ );
           		}
     		}
	    }
            if( defined($mkvm_cec)) {
                my $r;
                $r->{errorcode}=0;
                $r->{node}->[0]->{name}->[0] = $mkvm_cec;
                $r->{node}->[0]->{data}->[0]->{contents}->[0]="Please reboot the CEC $mkvm_cec firstly, and then use chvm to assign the I/O slots to the LPARs";
                $callback->($r);
            }

            next;
        }
        #################################
        # Done - close handle
        #################################
        $fds->remove($rfh);
        close($rfh);
    }
    yield; #Try to avoid useless iterations as much as possible
    return $rc;
} 


##########################################################################
# Finds attributes for given node is various databases
##########################################################################
sub resolve_hcp {
    my $request   = shift;
    my $noderange = shift;
    my @nodegroup = ();
    my $tab       = ($request->{hwtype} eq "fsp" or $request->{hwtype} eq "bpa") ? "ppcdirect" : "ppchcp";
    my $db        = xCAT::Table->new( $tab );

    ####################################
    # Database not defined 
    ####################################
    if ( !defined( $db )) {
        send_msg( $request, 1, sprintf( $errmsg{DB_UNDEF}, $tab ));
        return undef;
    }
    ####################################
    # Process each node
    ####################################
    foreach my $hcp ( @$noderange ) {
#        my ($ent) = $db->getAttribs( {hcp=>$hcp},"hcp" );
#        my ($ent) = $db->getNodeAttribs( $hcp, ["hcp"]);

#        if ( !defined( $ent )) {
#            my $msg = sprintf( "$hcp: $errmsg{NODE_UNDEF}", $tab );
#            send_msg( $request, 1, $msg );
#            next;
#        }
        ################################
        # Get userid and password
        ################################
        my @cred = xCAT::PPCdb::credentials( $hcp, $request->{hwtype} );
        $request->{$hcp}{cred} = \@cred;

        ################################
        # Save values
        ################################
        push @nodegroup,[$hcp];
    }
    return( \@nodegroup );

}


##########################################################################
# Group nodes depending on command
##########################################################################
sub preprocess_nodes {

    my $request   = shift;
    my $hcps_will = shift;
    my $noderange = $request->{node};
    my $method    = $request->{method};
    my %nodehash  = ();
    my @nodegroup = ();
    my %hcpgroup  = ();
    my %tabs      = ();
    my $netwk;

    ########################################
    # Special cases
    #   rscan - Nodes are hardware control pts 
    #   FSPpower, FSPinv and FSPrflash 
    ########################################
    if (( !$request->{hcp} && ($request->{hcp} ne "hmc" )) 
        and ($request->{command} !~ /^renergy$/)
        and (( $request->{command} =~ /^(rscan|rspconfig)$/ ) 
            or ($request->{hwtype} eq "fsp" or $request->{hwtype} eq "bpa" ) 
            or ($request->{command} eq 'lshwconn' and $request->{nodetype} eq 'hmc')) and ($request->{fsp_api} != 1)
       ) {
        my $result = resolve_hcp( $request, $noderange ); 
        return( $result );
    }
    ##########################################
    # Special processing - rnetboot 
    ##########################################
    if ( $request->{command} eq "rnetboot"  || $request->{command} eq "rbootseq"  ) { 
        $netwk = resolve_netwk( $request, $noderange );
        if ( !( %$netwk )) {
            return undef;
        }
    }
    ##########################################
    # Open databases needed
    ##########################################
    foreach ( qw(ppc vpd nodetype) ) {
        $tabs{$_} = xCAT::Table->new($_);

        if ( !exists( $tabs{$_} )) { 
            send_msg( $request, 1, sprintf( $errmsg{DB_UNDEF}, $_ )); 
            return undef;
        }
    }
   
    ##########################################################
    # For DFM actions, all the IPs of the FSPs/BPAs corresponding CECs/Frames will be used to do the 
    # comminucation with the hdwr_svr. So use the gethcpAttribs() to collect the CECs' FSPs, and Frames'
    # BPA here for process fork .
    # In the HMC hardware control environment, the mkhwconn/rmhwconn commands will use the FSPs' IPs or
    # the BPAs' IPs. So it also need to collect the CECs' FSPs, and Frames' BPA here.
    ##########################################################
    if ( $request->{fsp_api} == 1 || $request->{command} =~ /^(mkhwconn|rmhwconn|lshwconn)$/) {
         xCAT::FSPUtils::getHcpAttribs($request, \%tabs);
    }


    ##########################################
    # Group nodes. The first key is hcp, and the second kery is mtms.
    # All the attributs collected here will be used for the different commands Grcup Nodes later.
    ##########################################
    foreach my $node ( @$noderange ) {
        my $d = resolve( $request, $node, \%tabs );

        ######################################
        # Error locating node attributes
        ######################################
        if ( ref($d) ne 'ARRAY' ) {
            send_msg( $request, 1, "$node: $d");
            next;
        }
        ######################################
        # Get data values 
        ######################################
        my $hcp  = @$d[3];
        #my $hcp  = $hcps_will->{$node};
        #@$d[3] = $hcp;
        my $mtms = @$d[2];
       
        ######################################
        # Special case for mkhwconn with -p. The hcp in the command is specified by the users, 
	# not in the DB, and the hcp value is stored in  $request->{opt}->{p}.
	# So set the  $request->{opt}->{p} as the key the %nodehash directly.
        ######################################
        if ( $request->{command} eq "mkhwconn" and 
              exists $request->{opt}->{p})
        {
            $nodehash{ $request->{opt}->{p}}{$mtms}{$node} = $d;
        }
        ######################################
        #The common case
        ######################################
        else 
        {
            $nodehash{$hcp}{$mtms}{$node} = $d;
        }
    } 

    ##########################################
    # Get userid and password
    ##########################################
    while (my ($hcp,$hash) = each(%nodehash) ) {   
        my @cred; 
        if( $request->{fsp_api} != 1 ) {
            if ($request->{hcp} && ($request->{hcp} eq "hmc" )) {
                @cred = xCAT::PPCdb::credentials( $hcp, $request->{hcp} );
            } else {
                @cred = xCAT::PPCdb::credentials( $hcp, $request->{hwtype} );
            }
            $request->{$hcp}{cred} = \@cred;
         }
         
	 ######################################################
	 #In DFM suppport, only the mkhwconn command need the userid/password to
	 #create the connection between hdwr_svr and FSPs/BPAs
	 ###################################################### 
	 if( $request->{fsp_api} == 1 && $request->{command} eq "mkhwconn") {
             my $user;
	     while( my($mtms, $h) = each(%$hash) ) {
	         while(my($node, $tmp_d) = each(%$h) ) {
		     my $type = $$tmp_d[4];
		     ###############
		     #For NGP, get the passwd of the cmm's username USERID
		     ###############
		     if($type && $type =~ /^blade$/) {
	                 $user = "USERID";
			 my $cmm = $$tmp_d[5];
	                 @cred = xCAT::PPCdb::credentials( $cmm, $type, $user );
                         $request->{$cmm}{cred} = \@cred;
		     }
                     ############################
		     #For P7 IH DFM, get the password of the CEC's/Frame's username HMC
		     ###########################
		     if($type && $type =~ /^(fsp|bpa|cec|frame)$/) {
		         $user = "HMC"; 
	                 @cred = xCAT::PPCdb::credentials( $hcp, $type, $user );
                         $request->{$hcp}{cred} = \@cred;
		     }
                  }
	      }
	    
	 }
     
    } 
    ##########################################
    # Group the nodes - we will fork one 
    # process per nodegroup array element. 
    ##########################################

    ##########################################
    # These commands are grouped on an
    # LPAR-by-LPAR basis - fork one process
    # per LPAR.  
    ##########################################
    if ( ($method =~ /^(getmacs)$/ && exists( $request->{opt}->{D} )) || ($method =~ /^(rnetboot)$/) || $method =~ /^(rbootseq)$/ ) {
        while (my ($hcp,$hash) = each(%nodehash) ) {    
            @nodegroup = ();
            while (my ($mtms,$h) = each(%$hash) ) {
                while (my ($lpar,$d) = each(%$h)) {
                    push @$d, $lpar;

                    ##########################
                    # Save network info
                    ##########################
                    if ( $method =~ /^rnetboot$/ || $method =~ /^(rbootseq)$/  ) {
                        push @$d, $netwk->{$lpar}; 
                    }
                    push @nodegroup,[$hcp,$d]; 
                }
            }
            $hcpgroup{$hcp}{'nodegroup'} = [@nodegroup];
            $hcpgroup{$hcp}{'count'} = $#nodegroup + 1;
            $hcpgroup{$hcp}{'runprocess'} = 0;
            $hcpgroup{$hcp}{'index'} = 0;
        }
        return( \%hcpgroup );
    }

    elsif ( $method =~ /^(getmacs)$/ && exists( $request->{opt}->{arp} ) ) {
        return( $noderange );
    }

    ##########################################
    # Power control commands are grouped 
    # by CEC which is the smallest entity 
    # that commands can be sent to in parallel.  
    # If commands are sent in parallel to a
    # single CEC, the CEC itself will serialize 
    # them - fork one process per CEC.
    ##########################################
    elsif ( $method =~ /^powercmd/ || $method =~ /^renergy/ ) {
        while (my ($hcp,$hash) = each(%nodehash) ) {    
            while (my ($mtms,$h) = each(%$hash) ) {    
                push @nodegroup,[$hcp,$h]; 
            }
        }
        return( \@nodegroup );
    }
    ##########################################
    # All other commands are grouped by
    # hardware control point - fork one
    # process per hardware control point.
    ##########################################
    while (my ($hcp,$hash) = each(%nodehash) ) {    
        push @nodegroup,[$hcp,$hash];  
    } 
    return( \@nodegroup ); 
}


##########################################################################
# Finds attributes for given node is various databases 
##########################################################################
sub resolve_netwk {

    my $request   = shift;
    my $noderange = shift;
    my %nethash   = xCAT::DBobjUtils->getNetwkInfo( $noderange );
    my $tab       = xCAT::Table->new( 'mac' );
    my %result    = ();
    my $ip;

    #####################################
    # Network attributes undefined 
    #####################################
    if ( !%nethash ) {
        send_msg( $request,1,sprintf( $errmsg{NODE_UNDEF}, "networks" ));
        return undef;
    }
    #####################################
    # mac database undefined
    #####################################
    if ( !defined( $tab )) {
        send_msg( $request, 1, sprintf( $errmsg{DB_UNDEF}, "mac" ));
        return undef;
    }

    foreach ( @$noderange ) {
        #################################
        # Get gateway (-G)
        #################################
        if ( !exists( $nethash{$_} )) {
            my $msg = sprintf( "$_: $errmsg{NODE_UNDEF}", "networks");
            send_msg( $request, 1, $msg );
            next;
        }
        my $gateway = $nethash{$_}{gateway};
        my $gateway_ip;
        if ( defined( $gateway )) {
            $ip = xCAT::NetworkUtils::toIP( $gateway );
            if ( @$ip[0] != 0 ) {
                send_msg( $request, 1, "$_: Cannot resolve '$gateway'" );
                next;  
            }
            $gateway_ip = @$ip[1];
        }

        my $netmask = $nethash{$_}{mask};
        if ( !defined( $netmask )) {
            my $msg = sprintf("$_: $errmsg{NO_ATTR}","mask","networks");
            send_msg( $request, 1, $msg );
            next;
        }

        #################################
        # Get server (-S)
        #################################
        my $server = xCAT::TableUtils->GetMasterNodeName( $_ );
        if ( $server == 1 ) {
            send_msg( $request, 1, "$_: Unable to identify master" );
            next;
        }
        $ip = xCAT::NetworkUtils::toIP( $server );
        if ( @$ip[0] != 0 ) {
            send_msg( $request, 1, "$_: Cannot resolve '$server'" );
            next;  
        }
        my $server_ip = @$ip[1];

        #################################
        # Get client (-C)
        #################################
        $ip = xCAT::NetworkUtils::toIP( $_ ); 
        if ( @$ip[0] != 0 ) {
            send_msg( $request, 1, "$_: Cannot resolve '$_'" );
            next;  
        }
        my $client_ip = @$ip[1];

        #################################
        # Get mac-address (-m)
        #################################
        my ($ent) = $tab->getNodeAttribs( $_, ['mac'] );
        if ( !defined($ent) ) {
            my $msg = sprintf( "$_: $errmsg{NO_ATTR}","mac","mac");
            send_msg( $request, 1, $msg );
            next;
        }
        #################################
        # Save results 
        #################################
        $result{$_}{gateway} = $gateway_ip;
        $result{$_}{server}  = $server_ip;
        $result{$_}{client}  = $client_ip;
        $result{$_}{mac}     = $ent->{mac};
        $result{$_}{netmask} = $netmask;
    }
    return( \%result );
}


##########################################################################
# Finds attributes for given node is various databases 
##########################################################################
sub resolve {

    my $request = shift;
    my $node    = shift;
    my $tabs    = shift;
    my @attribs = qw(id pprofile parent hcp);
    my @values  = ();

    #################################
    # Get node type 
    #################################
    #my $ent = $tabs->{nodetype}->getNodeAttribs($node,[qw(nodetype node)]);
    #if ( !defined( $ent )) {
    #    return( sprintf( $errmsg{NODE_UNDEF}, "nodetype" ));
    #}
    #################################
    # Check for type
    #################################
    #if ( !exists( $ent->{nodetype} )) {
    #    return( sprintf( $errmsg{NO_ATTR}, "nodetype","nodetype" ));
    #}
    #################################
    # Check for valid "type"
    #################################
    my $ttype = xCAT::DBobjUtils->getnodetype($node, "ppc");
    my ($type) = grep( 
            /^$::NODETYPE_LPAR|$::NODETYPE_OSI|$::NODETYPE_BPA|$::NODETYPE_FSP|$::NODETYPE_CEC|$::NODETYPE_FRAME|$::NODETYPE_BLADE$/,
            #split /,/, $ent->{nodetype} );
            split /,/, $ttype);

    if ( !defined( $type )) {
        #return( "Invalid node type: $ent->{nodetype}" );
        return( "Invalid node type: $ttype" );
    }
    #################################
    # Get attributes 
    #################################
    my ($att) = $tabs->{ppc}->getNodeAttribs( $node, \@attribs );

    if ( !defined( $att )) { 
        return( sprintf( $errmsg{NODE_UNDEF}, "ppc" )); 
    }
    #################################
    # Special lpar processing 
    #################################
    if ( $type =~ /^$::NODETYPE_OSI|$::NODETYPE_LPAR$/ ) {
        $att->{bpa}  = 0;
        $att->{type} = "lpar";
        $att->{node} = $att->{parent};

        if ( !exists( $att->{parent} )) {
            return( sprintf( $errmsg{NO_ATTR}, "parent", "ppc" )); 
        }
        #############################
        # Get BPA (if any)
        #DFM doesn't support rvitals with temp, so add the if  fsp_api != 1
        #It will improve the performance of rvitals with all
        #############################
        if (( $request->{command} eq "rvitals" ) &&
                ( $request->{method}  =~ /^all|temp$/ ) && $request->{fsp_api} != 1 ) { 
            my ($ent) = $tabs->{ppc}->getNodeAttribs( $att->{parent},['parent']);

            #############################
            # Find MTMS in vpd database 
            #############################
            if (( defined( $ent )) && exists( $ent->{parent} )) {
                my @attrs = qw(mtm serial);
                my ($vpd) = $tabs->{vpd}->getNodeAttribs($ent->{parent},\@attrs);

                ########################
                # Verify attributes
                ########################
                foreach ( @attrs ) {
                    if ( !defined( $vpd ) || !exists( $vpd->{$_} )) {
                        return( sprintf( $errmsg{NO_UNDEF}, $_, "vpd", $ent->{parent} ));
                    }
                }
                $att->{bpa} = "$vpd->{mtm}*$vpd->{serial}";
            }
        }
    }
    #################################
    # Optional and N/A fields 
    #################################
    elsif ( $type =~ /^$::NODETYPE_FSP$/ ) {
        $att->{pprofile} = 0;
        $att->{id}       = 0;
        $att->{fsp}      = 0;
        $att->{node}     = $node;
        $att->{type}     = $type;
        $att->{parent}   = exists($att->{parent}) ? $att->{parent} : 0;
        $att->{bpa}      = $att->{parent};

        my $ntype;
        if ( exists( $att->{parent} )) {
            $ntype = xCAT::DBobjUtils->getnodetype($att->{parent}, "ppc");
        }
        if (( $request->{command} eq "rvitals" ) &&
                ( $request->{method}  =~ /^all|temp$/ && $ntype =~ /^cec$/ ) && $request->{fsp_api} != 1 ) {
            my ($ent) = $tabs->{ppc}->getNodeAttribs( $att->{parent},['parent']);

            #############################
            # Find MTMS in vpd database
            #############################
            if (( defined( $ent )) && exists( $ent->{parent} )) {
                my @attrs = qw(mtm serial);
                my ($vpd) = $tabs->{vpd}->getNodeAttribs($ent->{parent},\@attrs);

                ########################
                # Verify attributes
                ########################
                foreach ( @attrs ) {
                    if ( !defined( $vpd ) || !exists( $vpd->{$_} )) {
                        return( sprintf( $errmsg{NO_UNDEF}, $_, "vpd", $ent->{parent} ));
                    }
                }
                $att->{bpa} = "$vpd->{mtm}*$vpd->{serial}";
            }
        } elsif (( $request->{command} eq "rvitals" ) &&
                 ( $request->{method}  =~ /^all|temp$/ && $ntype =~ /^bpa$/ ) && $request->{fsp_api} != 1) {
            my @attrs = qw(mtm serial);
            my ($vpd) = $tabs->{vpd}->getNodeAttribs($att->{parent},\@attrs);
            ########################
            # Verify attributes
            ########################
            foreach my $attr ( @attrs ) {
                if ( !defined( $vpd ) || !exists( $vpd->{$attr} )) {
                    return( sprintf( $errmsg{NO_UNDEF}, $attr, "vpd", $att->{parent} ));
                }
            }
            $att->{bpa} = "$vpd->{mtm}*$vpd->{serial}";
        }
    }
    elsif ( $type =~ /^$::NODETYPE_BPA$/ ) {
        $att->{pprofile} = 0;
        $att->{id}       = 0;
        $att->{bpa}      = 0;
        $att->{parent}   = 0;
        $att->{fsp}      = 0;
        $att->{node}     = $node;
        $att->{type}     = $type;
    }
    elsif ( $type =~ /^$::NODETYPE_CEC|$::NODETYPE_BLADE$/ ) {
        $att->{pprofile} = 0;
        if( $type =~ /^$::NODETYPE_CEC$/) {
            $att->{id}       = 0;
        }
        $att->{fsp}      = 0;
        $att->{node}     = $node;
        $att->{type}     = $type;
        $att->{parent}   = exists($att->{parent}) ? $att->{parent} : 0;
        $att->{bpa}      = $att->{parent};

        if (( $request->{command} eq "rvitals" ) &&
                ( $request->{method}  =~ /^all|temp$/ ) && $request->{fsp_api} != 1) {

            #############################
            # Find MTMS in vpd database
            #############################
            if ( exists( $att->{parent} )) {
                my @attrs = qw(mtm serial);
                my ($vpd) = $tabs->{vpd}->getNodeAttribs($att->{parent},\@attrs);

                ########################
                # Verify attributes
                ########################
                foreach ( @attrs ) {
                    if ( !defined( $vpd ) || !exists( $vpd->{$_} )) {
                        return( sprintf( $errmsg{NO_UNDEF}, $_, "vpd", $att->{parent} ));
                    }
                }
                $att->{bpa} = "$vpd->{mtm}*$vpd->{serial}";
            }
        }
    }
    elsif ( $type =~ /^$::NODETYPE_FRAME$/ ) {
        $att->{pprofile} = 0;
        $att->{id}       = 0;
        $att->{bpa}      = 0;
        $att->{parent}   = 0;
        $att->{fsp}      = 0;
        $att->{node}     = $node;
        $att->{type}     = $type;
    }
    #################################
    # Find MTMS in vpd database 
    #################################
    my @attrs = qw(mtm serial);
    my ($vpd) = $tabs->{vpd}->getNodeAttribs($att->{node}, \@attrs );

    if ( !defined( $vpd )) {
        return( sprintf( $errmsg{NODE_UNDEF}, "vpd: ($att->{node})" )); 
    }
    ################################
    # Verify both vpd attributes
    ################################
    foreach ( @attrs ) {
        if ( !exists( $vpd->{$_} )) {
            return( sprintf( $errmsg{NO_ATTR}, $_, "vpd: ($att->{node})" ));
        }
    }
    $att->{fsp} = "$vpd->{mtm}*$vpd->{serial}";

    #################################
    # Verify required attributes
    #################################
    foreach my $at ( @attribs ) {
        if ( !exists( $att->{$at} )) {
                if( !($request->{fsp_api} == 1 && !exists($att->{pprofile}))) { #for p7 ih, there is no pprofile attribute
                    return( sprintf( $errmsg{NO_ATTR}, $at, "ppc" ));
                }
        } 
    }
   
    ############################
    #Specail case for mkhwconn/lshwconn/rmhwconn with -s . The sfp value( always the hmc) should
    #be set as the hcp. 
    ############################
    if( $request->{command} =~ /^(mkhwconn|lshwconn|rmhwconn)$/ && grep (/^-s$/, @{$request->{arg}})) {
        my $sfp;
        unless ( $request->{sfp} ) {
            my $ent = $tabs->{ppc}->getNodeAttribs( $node, [qw(sfp)]);
            if( $request->{command} =~ /^(lshwconn|rmhwconn)$/ && !defined($ent)) {
                return( "$node: No sfp defined in the ppc table.");
            
            }
            $sfp = $ent->{sfp};
            
        } else {
            $sfp = $request->{sfp};
        }
        if( $request->{command} =~ /^(mkhwconn)$/ && !defined($sfp)) {
            return("$node: Please specify the sfp in the commands or in the ppc table.");
        }
        $request->{fsp_api} = 0;
        $request->{hwtype} = "hmc";
        $att->{hcp} = $sfp;
    }


    #################################
    # Build array of data 
    #################################
    foreach ( qw(id pprofile fsp hcp type bpa) ) {
        push @values, $att->{$_};
    }
    return( \@values );
}



##########################################################################
# Forks a process to run the ssh command
##########################################################################
sub fork_cmd {

    my $host    = shift;
    my $nodes   = shift;
    my $request = shift;

    #######################################
    # Pipe childs output back to parent
    #######################################
    my $parent;
    my $child;
    pipe $parent, $child;
    my $pid = xCAT::Utils->xfork;

    if ( !defined($pid) ) {
        ###################################
        # Fork error
        ###################################
        send_msg( $request, 1, "Fork error: $!" );
        return undef;
    }
    elsif ( $pid == 0 ) {
        ###################################
        # Child process
        ###################################
        close( $parent );
        $request->{pipe} = $child;

        invoke_cmd( $host, $nodes, $request );
        exit(0);
    }
    else {
        ###################################
        # Parent process
        ###################################
        close( $child );
        return( $parent, $pid );
    }
    return(0);
}
sub handle_cmd {
    my $server = shift;
    my $host = shift;
    my $request = shift;
    my $verbose = $request->{verbose};
    eval { require xCAT::PPCfsp };
    if ( $@ ) {
       send_msg( $request, 1, $@ );
       return;
    }
    my @exp = xCAT::PPCfsp::connect( $request, $server );

####################################
# Error connecting 
####################################
    if ( ref($exp[0]) ne "LWP::UserAgent" ) {
#send_msg( $request, 1, $exp[0] );
        my @output_array;
        my $methods = $request->{method};
        foreach ( keys %$methods) {
            my %output;
            $output{node}->[0]->{name}->[0] = "$host";
            $output{node}->[0]->{data}->[0]->{contents}->[0] = "$server: $exp[0]";
            $output{node}->[0]->{cmd}->[0] = $_;
            $output{errorcode} = 128;
            push @output_array, \%output;
        }
        return \@output_array;
    }
    $request->{host} = $host;
    my $result = xCAT::PPCfsp::handler( $server, $request, \@exp);

####################################
# Output verbose Perl::LWP 
####################################
    if ( $verbose ) {
        my $verbose_log = $exp[3];
        my $output = shift @$result;
        $output->{data} = [$$verbose_log];
        unshift @$result, \%$output;
    }
    return $result;
}

sub handle_find_hw_children {
    my $host = shift;
    my $child_type = shift;
    my @children = ();
    my $vpdtab = xCAT::Table->new("vpd");
    if (!defined($vpdtab) or !defined($child_type)) {
        return undef;
    }
    my $mtms = $vpdtab->getNodeAttribs($host, qw(serial mtm));
    if (!defined($mtms))  {
        return undef;
    }
    my @nodearray = $vpdtab->getAttribs({serial=>$mtms->{serial}, mtm=>$mtms->{mtm}}, qw(node side)); # need regx
    if (!(@nodearray)) {
        return undef;
    }
    my @tempnodes;
    foreach (@nodearray) {
        push @tempnodes, $_->{node};
    }  
    my $typehash = xCAT::DBobjUtils->getnodetype(\@tempnodes, "ppc");
    foreach my $node (@nodearray) {
        my $n_type = $$typehash{$node->{node}};
        if ($n_type !~ /^$child_type$/ or !defined($node->{side})) {
            next;
        }  
        push @children, $node;
    }
    if (scalar(@children) eq '0') {
        return undef;
    }
    return \@children; 
}
sub print_res {
    my $request = shift;
    my $host = shift;
    my $res_array = shift;
    if (!defined($res_array) or ref($res_array) ne 'ARRAY') {
        return;
    }
    my $out = $request->{pipe};
    print $out freeze( $res_array );
    print $out "\nENDOFFREEZE6sK4ci\n";
    return ;
}

sub get_dirindex_from_side {
   my $side = shift;
   my $dir = undef;
   if ($side =~ /(a+)-\d*/i) {
       $dir = '0'; 
   } elsif ($side =~ /(b+)-\d*/i) {
       $dir = '1';
   } else {
       $dir = '2';
   }
   return $dir;
}
sub reorgnize_res_for_handle_cmd {
    my $request = shift;
    my $host = shift;
    my $output = shift;
    my $methods = $request->{method};
    my %re_output = ();
    my %succ_side = ();
    my $dir = undef;
    foreach my $side (keys %$output) {
        my $res = $output->{$side};
        foreach my $index (@$$res) {
            $dir = &get_dirindex_from_side($side);
            my $cmd = $index->{node}->[0]->{cmd}->[0];
            if (($index->{node}->[0]->{data}->[0]->{contents}->[0]) =~ /feature is not available/) {
                $dir = '0';
            }
            if (!defined($succ_side{$cmd}{$dir}{done})) {
                if (defined($re_output{$cmd}{$dir})) {
                    my $array = $re_output{$cmd}{$dir};
                    my $n = scalar(@$array);
                    $array->[$n] = $index;    
                } else {
                    $re_output{$cmd}{$dir}[0] = $index;
                }
            } else {
                next;
            }
            if ($index->{errorcode} eq '0') {
                @{$re_output{$cmd}{$dir}} = ();
                $re_output{$cmd}{$dir}[0] = $index;
                $succ_side{$cmd}{$dir}{done}++;
            }
        }
    }
    foreach my $method (keys %re_output) {
        my $value = $re_output{$method};
        foreach my $side (keys %$value) {
            my $res_array = $value->{$side};
            &print_res($request, $host, $res_array);
        }
    }
    return undef;
}

sub process_children {
    my $request = shift;
    my $host = shift;
    my $node_array = shift;
    my %output = ();
    my %conn_flag = ();
    foreach my $index (@$node_array) {
        my $side = $index->{side};
        my $dir = &get_dirindex_from_side($side);
        if (defined($conn_flag{$dir})) {
            next;
        }
        $request->{$index->{node}}{cred} = $request->{$host}{cred};
        my $res = &handle_cmd($index->{node}, $host, $request);
        $output{$side} = \$res;
        if ($res->[0]->{errorcode} ne '128') {
            $conn_flag{$dir} = 1;        
        }
    }
    &reorgnize_res_for_handle_cmd($request, $host, \%output);
    return undef;
}


my %children_type = (
        cec => "fsp",
        frame => "bpa"
        );

sub handle_redundance_fsps {
    my $host = shift;
    my $hwtype = shift;
    my $request = shift;
    my $res = undef;
    if ($hwtype =~ /^(bpa|fsp)$/) {
        $res = &handle_cmd($host, $host, $request);
        &print_res($request, $host, $res);
    } elsif ($hwtype =~ /^(cec|frame)$/){
        my $child_type = $children_type{$hwtype};
        my $children = &handle_find_hw_children($host, $child_type);
        if (!defined($children)) {
             send_msg($request, 1, "Not found any $child_type for $host");
        } else {
            &process_children($request, $host, $children);
        }
    } else {
        send_msg( $request, 1, "$hwtype not support!");
    }
    return undef;
}
sub check_node_info {
    my $hash = shift;
    my $if_lpar = undef;
    while (my ($mtms, $h) = each(%$hash)) {
        while (my($name, $d) = each(%$h)) {
            my $node_type = @$d[4];
            if ($node_type =~ /^lpar$/) {
                $if_lpar = $name;
                last; 
            }
        } 
    }
    return $if_lpar;
}


##########################################################################
# Run the command, process the response, and send to parent
##########################################################################
sub invoke_cmd {

    my $host    = shift;
    my $nodes   = shift;
    my $request = shift;
    my $hwtype  = $request->{hwtype};
    my $verbose = $request->{verbose};
    my $cmd     = $request->{command};
    my $power   = $request->{hcp};
    my @exp;
    my $verbose_log;
    my @outhash;

    ########################################
    # If the request command is renergy, just
    # uses the xCAT CIM Client to handle it
    ########################################
    if ( $request->{command} eq "renergy" ) {
        my $result = &runcmd($request, $host, $nodes);

        ########################################
        # Format and send back to parent
        ########################################
        foreach my $line ( @$result ) {
            my %output;
            $output{node}->[0]->{name}->[0] = @$line[0];
            $output{node}->[0]->{data}->[0]->{contents}->[0] = @$line[1];
            $output{errorcode} = @$line[2];
            push @outhash, \%output;
        }
        my $out = $request->{pipe};
        print $out freeze( [@outhash] );
        print $out "\nENDOFFREEZE6sK4ci\n";

        return;
    }

    ########################################
    # Direct-attached FSP handler 
    ########################################
    if ( ($power ne "hmc") && ( $hwtype =~ /^(fsp|bpa|cec|frame|blade)$/) && $request->{fsp_api} == 0) {

        if ($request->{command} eq 'rpower') {
            my $check = &check_node_info($nodes);
        if (defined($check)) {
           my %output;
           $output{node}->[0]->{name}->[0] = $check;
           $output{node}->[0]->{data}->[0]->{contents}->[0] = "Error: $request->{command} not support on lpar in ASMI mode";
           $output{node}->[0]->{cmd}->[0] = $request->{method};
           $output{errorcode} = 1;
           my $out = $request->{pipe};
          print $out freeze( [\%output] );
          print $out "\nENDOFFREEZE6sK4ci\n";
           return ;
           }

        if (ref($request->{method}) ne 'HASH') {
           my %method_hash = ();
           my $method = $request->{method};
           $method_hash{$method} = undef;
           $request->{method} = \%method_hash;
        }
        }
        &handle_redundance_fsps($host, $hwtype, $request);
        return;
    }

    ########################################
    # HMC and IVM-managed handler
    # Connect to list of remote servers
    ########################################
   if (  $request->{fsp_api} == 0 ) { 
       foreach ( split /,/, $host ) {
           if ( $power ne "hmc" ) {
               @exp = xCAT::PPCcli::connect( $request, $hwtype, $_ );
           } else {
               @exp = xCAT::PPCcli::connect( $request, $power, $_);
           }
           ####################################
           # Successfully connected 
           ####################################
           if ( ref($exp[0]) eq "Expect" ) {
              last;
           }
       }
    
       ########################################
       # Error connecting 
       ########################################
       if ( ref($exp[0]) ne "Expect" ) {
           send_msg( $request, 1, $exp[0] );
           return;
       }
    }

    ########################################
    # Process specific command 
    ########################################
    my $result = runcmd( $request, $nodes, \@exp );

    ########################################
    # Close connection to remote server
    ########################################
    if(  $request->{fsp_api} == 0 ) {
        xCAT::PPCcli::disconnect( \@exp );
    }

    ########################################
    # Get verbose Expect output
    ########################################
    if ( $verbose ) {
        $verbose_log = $exp[6];
    }
    ########################################
    # Return error
    ######################################## 
    if ( ref($result) ne 'ARRAY' ) {
        send_msg( $request, 1, $$verbose_log.$result );
        return;
    }
    ########################################
    # Prepend verbose output 
    ########################################
    if ( defined( $verbose_log )) {
        my %output;
        $output{data} = [$$verbose_log];
        push @outhash, \%output;
    }
    ########################################
    # Send result back to parent process
    ########################################
    if ( @$result[0] eq "FORMATDATA6sK4ci" ) {
        my $out = $request->{pipe};

        push @outhash, @$result[1];
        print $out freeze( [@outhash] );
        print $out "\nENDOFFREEZE6sK4ci\n";
        return;
    }
    ########################################
    # Format and send back to parent
    ########################################
    foreach ( @$result ) {
        my %output;
        $output{node}->[0]->{name}->[0] = @$_[0];
        #$output{node}->[0]->{data}->[0]->{contents}->[0] = @$_[1];
        $output{errorcode} = @$_[2];
    	if($output{errorcode} != 0) {
	        if($request->{fsp_api} == 1) {
                #$output{node}->[0]->{data}->[0]->{contents}->[0] = "(trying fsp-api)@$_[1]";
                $output{node}->[0]->{data}->[0]->{contents}->[0] = "@$_[1]";
	        } else {
                #$output{node}->[0]->{data}->[0]->{contents}->[0] = "(trying HMC    )@$_[1]"; 
	            $output{node}->[0]->{data}->[0]->{contents}->[0] = "@$_[1]"; 
	        }
	    } else {
                $output{node}->[0]->{data}->[0]->{contents}->[0] = @$_[1];	
	    }
        push @outhash, \%output;
    }
    my $out = $request->{pipe};
    print $out freeze( [@outhash] );
    print $out "\nENDOFFREEZE6sK4ci\n";
}


##########################################################################
# Run the command method specified
##########################################################################
sub runcmd {

    my $request = shift;
    my $cmd     = $request->{command};
    my $method  = $request->{method};
    my $hwtype  = $request->{hwtype};
    #my $modname = $modules{$cmd};
    my $modname = $modules{$cmd}{$hwtype};

    ######################################
    # Command not supported
    ######################################
    if ( !defined( $modname )) {
        return( ["$cmd not a supported command by $hwtype method"] );
    }   
    ######################################
    # Load specific module
    ######################################
    eval "require $modname";
    if ( $@ ) {
        return( [$@] );
    }
    ######################################
    # Invoke method 
    ######################################
    no strict 'refs';
    my $result = ${$modname."::"}{$method}->($request,@_);
    use strict;

    return( $result );

}

##########################################################################
# Pre-process request from xCat daemon. Send the request to the the service
# nodes of the HCPs.
##########################################################################
sub preprocess_request {

    my $package  = shift;
    my $req      = shift;
    #if ($req->{_xcatdest}) { return [$req]; }    #exit if preprocessed
    if ($req->{_xcatpreprocessed}->[0] == 1 ) { return [$req]; }
    my $callback = shift;
    my $subreq = shift;
    my @requests;

    #####################################
    # Parse arguments
    #####################################
    my $opt = parse_args($package, $req, $callback);
    if ( ref($opt) eq 'ARRAY' ) 
    {
        send_msg( $req, 1, @$opt );
        delete($req->{callback}); # if not, it will cause an error --  "Can't encode a value of type: CODE" in hierairchy.
        return(1);
    }
    delete($req->{callback}); # remove 'callback' => sub { "DUMMY" } in hierairchy.
    $req->{opt} = $opt;

    if ( exists( $req->{opt}->{V} )) {
        $req->{verbose} = 1;
    }

    ####################################
    # Get hwtype 
    ####################################
    $package =~ s/xCAT_plugin:://;

    my $deps;
    my $nodeseq;
    if (($req->{command}->[0] eq 'rpower') && (!grep(/^--nodeps$/, @{$req->{arg}}))
        && (($req->{op}->[0] eq 'on') || ($req->{op}->[0] eq 'off') 
        || ($req->{op}->[0] eq 'softoff') || ($req->{op}->[0] eq 'reset'))) {

        $deps = xCAT::SvrUtils->build_deps($req->{node}, $req->{op}->[0]);

        # no dependencies at all
        if (!defined($deps)) {
            foreach my $node (@{$req->{node}}) {
                $nodeseq->[0]->{$node} = 1;
            }
        } else {
            $nodeseq = xCAT::SvrUtils->handle_deps($deps, $req->{node}, $callback);
        }
    }

    if ($nodeseq == 1) {
        return undef;
    }
    # no dependency defined in deps table,
    # generate the $nodeseq hash
    if (!$nodeseq) {
        foreach my $node (@{$req->{node}}) {
            $nodeseq->[0]->{$node} = 1;
        }
    }

    my $i = 0;
    for ($i = 0; $i < scalar(@{$nodeseq}); $i++) { 
        #reset the @requests for this loop
        @requests = ();
        ####################################
        # Prompt for usage if needed and on MN
        ####################################
        my @dnodes = keys(%{$nodeseq->[$i]});
    
        if (scalar(@dnodes) == 0) {
             next;
        }
        if (scalar(@{$nodeseq}) > 1) {
            my %output;
            my $cnodes = join(',', @dnodes);
            $output{data} = ["Performing action against the following nodes: $cnodes"];
            $callback->( \%output );
        }
        my $noderange = \@dnodes;
        $req->{node} = \@dnodes; #Should be arrayref
        #$req->{noderange} = \@dnodes; #Should be arrayref
        my $command = $req->{command}->[0];
        my $extrargs = $req->{arg};
        my @exargs=($req->{arg});
        if (ref($extrargs)) {
            @exargs=@$extrargs;
        }
        if ($ENV{'XCATBYPASS'}){
            my $usage_string=xCAT::Usage->parseCommand($command, @exargs);
            if ($usage_string) {
                $callback->({data=>[$usage_string]});
                $req = {};
                return ;
            }
            if (!$noderange) {
                $usage_string="Missing noderange";
                $callback->({data=>[$usage_string]});
                $req = {};
                return ;
            }   
        }   
    
  
        ##################################################################
        # get the HCPs for the LPARs in order to figure out which service 
        # nodes to send the requests to
        ###################################################################
        #my $hcptab_name = ($package eq "fsp" or $package eq "bpa") ? "ppcdirect" : "ppchcp";
        #my $hcptab  = xCAT::Table->new( $hcptab_name );
        #unless ($hcptab ) {
        #    $callback->({data=>["Cannot open $hcptab_name table"]});
        #    $req = {};
        #    return;
        #}
        # Check if each node is hcp 
        my %hcp_hash=();
        my @missednodes=();
        my $support_hcp_type;
        # in the DFM model, cec/fsp/Frame/bpa can be hcp.
        if ($package eq "fsp" or $package eq "bpa") {
            $support_hcp_type = "(fsp|cec|bpa|frame|blade)";
        # in the HMC model, only hmc can be hcp.
        } elsif ($package eq "hmc") {
            $support_hcp_type = "hmc";
        # package equal 'ivm', only ivm can be hcp.
        } else {
            $support_hcp_type = "ivm";
        }
        my $typehash = xCAT::DBobjUtils->getnodetype(\@$noderange) ;
        foreach ( @$noderange ) {
            my $nodetype = $$typehash{$_};
            if ($nodetype and $nodetype =~ /$support_hcp_type/) {
                push @{$hcp_hash{$_}{nodes}}, $_;
            } else {
                push @missednodes, $_;
            }
        }
        #foreach ( @$noderange ) {
        #    my ($ent) = $hcptab->getNodeAttribs( $_,"hcp" );
        #    if ( !defined( $ent )) {
        #       push @missednodes, $_;
        #    next;
        #    }
        #    push @{$hcp_hash{$_}{nodes}}, $_;
        #}
   
        #check if the left-over nodes are lpars
        if (@missednodes > 0) {
            my $ppctab = xCAT::Table->new("ppc");
            unless ($ppctab) { 
                $callback->({data=>["Cannot open ppc table"]});
                $req = {};
                return;
            }
            foreach my $node (@missednodes) {

                my $ent=$ppctab->getNodeAttribs($node,['hcp']);
#if (defined($ent->{hcp})) { push @{$hcp_hash{$ent->{hcp}}{nodes}}, $node;}
                if (defined($ent->{hcp})) {
#for multiple hardware control points, the hcps should be split to nodes
                    my @h = split(",", $ent->{hcp}); 
                    foreach my $hcp (@h) {
                        push @{$hcp_hash{$hcp}{nodes}}, $node;
                    }  
                } else { 
                    $callback->({data=>["The node $node is neither a hcp nor an lpar"]});
                    $req = {};
                    return;
                }
            }
        }

        my @masters = xCAT::TableUtils->get_site_attribute("master");
       	#When run mkhwconn/lshwconn/rmhwconn with -T fnm for CNM, it will send the command to CEC/Frame direclty, 
     	#not through the service node if specified.
        if ($req->{command}->[0] =~ /^(mkhwconn|lshwconn|rmhwconn|rpower)$/
	        && ( $req->{opt}->{T} == 1) )  {
	        #for fnm
            my $reqcopy = {%$req};
            #my @masters = xCAT::TableUtils->get_site_attribute("master");
            if( $masters[0] ) {
                $reqcopy->{'_xcatdest'} = $masters[0];
                push @requests,$reqcopy;
            } else {
                $callback->({data=>["The value of the attribute master in the site table is NOT set"]});
                $req = {};
                return;
            }
        } else { 

        # find service nodes for the HCPs
        # build an individual request for each service node
        my $service  = "xcat";
        my @hcps=keys(%hcp_hash);
        my $sn;
        my @dfmdispatch = xCAT::TableUtils->get_site_attribute("hwctrldispatch");
        if (defined($dfmdispatch[0]) and ($dfmdispatch[0] =~ /0|n/i)) {
            if ($masters[0]) {
                push @{$sn->{$masters[0]}}, @hcps;
            } else {
                $callback->({data=>["The value of the attribute master in the site table is NOT set"]});
                $req = {};
                return;
            }
        } else {
            $sn = xCAT::ServiceNodeUtils->get_ServiceNode(\@hcps, $service, "MN");
        }
        # build each request for each service node
          foreach my $snkey (keys %$sn)
          {
            #$callback->({data=>["The service node $snkey "]});
            my $reqcopy = {%$req};
            $reqcopy->{'_xcatdest'} = $snkey;
            $reqcopy->{_xcatpreprocessed}->[0] = 1;
            my $hcps1=$sn->{$snkey};
            my @nodes=();
            foreach (@$hcps1) { 
                push @nodes, @{$hcp_hash{$_}{nodes}};
            }
    	    @nodes = sort @nodes;
            my %hash = map{$_=>1} @nodes; #remove the repeated node for multiple hardware control points
            @nodes =keys %hash;
            $reqcopy->{node} = \@nodes;
            #print "nodes=@nodes\n";
            push @requests, $reqcopy;
             
            if(($req->{command}->[0] eq "rflash") && ( exists( $req->{opt}->{activate} ) ) ) {
                my $linuxrequired = 0;
                if ( xCAT::Utils->isLinux() ) {
                    my @installloc = xCAT::TableUtils->get_site_attribute("installloc");
                    if (! ($installloc[0])) {
                        $linuxrequired = 1;       
                    }
                }
                
                if ( ($linuxrequired || xCAT::Utils->isAIX()) && ( $masters[0] ne $snkey )) {
                    my $install_dir = xCAT::TableUtils->getInstallDir();
                    my $cmd = "$::XCATROOT/bin/xdcp $snkey -R  $install_dir/packages_fw $install_dir/";
                    my $result = xCAT::Utils->runcmd("$cmd", -1); 
                    if ($::RUNCMD_RC != 0) {
                        $callback->({data=>["$result. Could not copy rpms in the $install_dir/packages_fw  to $snkey.\n"]});
                        $req = {};
                        return;
                    }
                }
                    
            }
          }
        }
        # No dependency, use the original logic
        if (scalar(@{$nodeseq}) == 1) {
            return \@requests;
        }

        # do all the new request entries in this loop
        my $j = 0;
        for ($j = 0; $j < scalar(@requests); $j++) {
            $subreq->(\%{$requests[$j]}, $callback);
        }

        # We can not afford waiting 'msdelay' for each node,
        # for performance considerations,
        # use the maximum msdelay for all nodes
        my $delay = 0;
        # do not need to calculate msdelay for the last loop
        if ($i < scalar(@{$nodeseq})) {
            foreach my $reqnode (@{$req->{node}}) {
                foreach my $depnode (keys %{$deps}) {
                    foreach my $depent (@{$deps->{$depnode}}) {
                        # search if the 'nodedep' includes the $reqnode
                        # do not use grep, performance problem!
                        foreach my $depentnode (split(/,/, $depent->{'nodedep'})) {
                            if ($depentnode eq $reqnode) {
                                if ($depent->{'msdelay'} > $delay) {
                                    $delay = $depent->{'msdelay'};
                                }
                            }
                        }
                    }
                }
            }
        }
        
        if ($ENV{'XCATDEBUG'}) {
            my %output;
            $output{data} = ["delay = $delay"];
            $callback->( \%output );
        }
        #convert from millisecond to second
        $delay /= 1000.0;
        if ($delay && ($i < scalar(@{$nodeseq}))) {
            my %output;
            $output{data} = ["Waiting $delay seconds for node dependencies\n"];
            $callback->( \%output );
            if ($ENV{'XCATDEBUG'}) {
                $output{data} = ["Before sleep $delay seconds"];
                $callback->( \%output );
            }
            Time::HiRes::sleep($delay);
            if ($ENV{'XCATDEBUG'}) {
                $output{data} = ["Wake up!"];
                $callback->( \%output );
            }
        }
    }
    return undef;
}
####################################
# Parse arguments
####################################
sub parse_args
{
    my $package = shift;
    my $req     = shift;
    my $callback= shift;
    $package =~ s/xCAT_plugin:://;
    #    if ( exists $req->{opt})
    #    {
    #        return $req->{opt};
    #    }

    #################################
    # To match the old logic
    ##################################
    my $command = $req->{command}->[0];
    my $stdin   = $req->{stdin}->[0];
    $req->{command}  = $command;
    $req->{stdin}    = $stdin; 
    $req->{hwtype}   = $package; 
    $req->{callback} = $callback; 
    $req->{method}   = "parse_args";

    my $opt = runcmd( $req);

    $req->{command} = [ $command];
    $req->{stdin}   = [ $stdin];
    $req->{method}  = [$req->{method}];
    $req->{op}  = [$req->{op}];
    return $opt;
}


##########################################################################
# Process request from xCat daemon
##########################################################################
sub process_request {

    my $package  = shift;
    my $req      = shift;
    my $callback = shift;
    my $subreq      = shift;

    ####################################
    # Get hwtype 
    ####################################
    $package =~ s/xCAT_plugin:://;

    ####################################
    # Build hash to pass around 
    ####################################
    my $request = {%$req};
    $request->{command} = $req->{command}->[0];
    $request->{stdin}   = $req->{stdin}->[0];
    $request->{method} = $req->{method}->[0];
    $request->{op}   = $req->{op}->[0];
    $request->{enableASMI} = $req->{enableASMI};
    #support more options in hierachy
    if( ref( $req->{opt}) eq 'ARRAY' ) {
        my $h = $req->{opt}->[0];
        my %t = ();
        foreach my $k(keys %$h){
            $t{$k} = $h->{$k}->[0];
        }
        $request->{opt} = \%t;
     }
    if (ref($req->{hwtype}) eq 'ARRAY') {
        $request->{hwtype} = $req->{hwtype}->[0];
    }
#   $request->{hwtype}  = $package;
    $request->{callback}= $callback;
    $request->{subreq}  = $subreq;
    #########################
    #This is a special case for rspconfig and mkhwconn, 
    #we shouldn't set hwtype as$package. and reserved for other commands.
    #probably for all HW ctrl commands it still true?
    #########################
    if($request->{command} ne "rspconfig" and 
        $request->{command} ne "mkhwconn") {
        $request->{hwtype}  = $package;
    }

    ####################################
    # Option -V for verbose output
    ####################################
    if ( exists( $request->{opt}->{V} )) {
        $request->{verbose} = 1;
    }

    #if( $request->{hwtype} ne 'hmc' ) {
    if( $request->{hwtype} !~ /hmc|ivm/ ) {
        $request->{fsp_api} = 1;
        #For using rspconfig to disable/enable dev/celogin1 through ASMI
        my $arg = $request->{arg};
        if($request->{command} eq "rspconfig" and grep(/^(dev|celogin1)/, @$arg)) {
           $request->{fsp_api} = 0;
        }
    } else {
        $request->{fsp_api} = 0; 
    }
    
    #print Dumper($request);
    process_command( $request );
    return;


    ####################################
    # Process remote command
    ####################################
    #process_command( $request );
    
    #The following code will not be used in xCAT 2.7

    #The following code supports for Multiple hardware control points.
    #use @failed_nodes to store the nodes which need to be run.
    #print "before process_command\n";
    #print Dumper($request);
    my %failed_msg = (); # store the error msgs
    my $t = $request->{node};
    my @failed_nodes = @$t;
    #print "-------failed nodes-------\n";
    #print Dumper(\@failed_nodes); 
    my $hcps = getHCPsOfNodes(\@failed_nodes, $callback, $request);
    if( !defined($hcps)) {
	#Not found the hcp for one node
        $request = {};	
        return;
    }
    #####################
    #print Dumper($hcps);
    #$VAR1 = {
    #          'lpar01' => {
    #                        'num' => 2,
    #                        'hcp' => [
    #                                   'Server-9110-51A-SN1075ECF',
    #                                   'c76v2hmc02'
    #                                 ]
    #                       }
    #         };
    ######################
    while(1)  {
       my $lasthcp_type;
       my %hcps_will = ();
       my @next = ();
       my $count; #to count the nodes who doesn't have hcp in the $hcps
       if( @failed_nodes == 0 ) {
           #all nodes succeeded --- no node in @$failed_nodes;
	       return ;
       }
       
       foreach my  $node (@failed_nodes)  {
	       #for multiple, get the first hcp in the $hcps{$node}.
	       my $hcp_list = $hcps->{$node}->{hcp};
	       #print Dumper($hcp_list);
	       my $thishcp=  shift( @$hcp_list );
	       if(!defined($thishcp) ) {
	          #if no hcp, count++; 
	          $count++;
	          if($count == @failed_nodes) {
		      # all the hcps of the nodes are tried. But still failed. so output the error msg and exit.
		      #print Dumper(\%failed_msg);
		      #prompt all the error msg.
		          foreach my $failed_node (@failed_nodes) {
		              my $msg = $failed_msg{$failed_node};
		              foreach my $item (@$msg) {
		      	          if($item) {
		                      #print Dumper($item);
		                      $callback->($item);
		                  } # end of if 
	                  } # end of foreach
		          }#end of foreach
		          #output all the msgs of the failed nodes, so return
	              return ;
	           }#end of if
	           #if $count != @failed_nodes, let's check next node
	           next;
	        }#end of if
	        #print "thishcp:$thishcp\n";
	        #get the nodetype of hcp:
	        #my $thishcp_type = xCAT::FSPUtils->getTypeOfNode($thishcp,$callback);
	        my  $thishcp_type = xCAT::DBobjUtils->getnodetype($thishcp, "ppc");
            if(!defined($thishcp_type)) {
                my %output = ();
                $output{node}->[0]->{name} = [$node];
                $output{node}->[0]->{data} = ["the type of $node\'s hcp is not defined in the 'ppc' table."];
                $output{errorcode} = '1';
                $callback-> (\%output);
	            next;
	         }
	         #print "lasthcp_type:$lasthcp_type ;thishcp_type:$thishcp_type\n";
	        if(defined($lasthcp_type)) { 
	        	if ( ($lasthcp_type =~ /^(hmc)$/ &&  $thishcp_type =~ /^(fsp|bpa|cec)$/) or (($lasthcp_type =~ /^(fsp|bpa|cec)$/ ) && ($thishcp_type =~ /^(hmc)$/ )) )  {
		            $callback->({data=>["the $node\'s hcp type is different from the other's in the specified noderange in the 'ppc' table."]}); 
	               return;
	             }
	       }
	  
	      $lasthcp_type = $thishcp_type; 
          $hcps_will{$node} = $thishcp;
	      push(@next, $node);
	  
       } #end of foreach
       my $request_new;
       %$request_new =%$request;
       $request_new->{node}  = \@next;
       $request_new->{fsp_api} = 0;
       if($lasthcp_type =~ /^(fsp|bpa|cec|frame)$/ ) {
#my $fsp_api = check_fsp_api($request);
#if($fsp_api == 0 ) {
    $request_new->{fsp_api} = 1; 
# }
       }
#For mkhwconn ....
       if( $request->{hwtype} ne 'hmc' ) {
           $request_new->{hwtype}  = $lasthcp_type;
       } else {
           $request_new->{fsp_api} = 0; 
       }
#print Dumper($request_new);
       @failed_nodes = () ;
       if( $hcps->{maxnum} == 1 && $request_new->{command} !~ /^(rspconfig|rpower|reventlog)$/ ) {
           push @failed_nodes, "noloop"; # if each node only has one hcp, it will return immediately.
       }
#For rspconfig to use ASMI
       if (defined($request->{enableASMI}) && ($request->{enableASMI} eq "1")) {
           $request_new->{fsp_api} = 0;
       }
       process_command( $request_new , \%hcps_will, \@failed_nodes, \%failed_msg);
#print "after result:\n";
#print Dumper(\@failed_nodes);
       if($lasthcp_type =~ /^(fsp|bpa|cec|frame)$/  && 
               $request->{hwtype} ne 'hmc' &&
               $request_new->{fsp_api} ne '0') {
           if ($request_new->{command} =~ /^(rspconfig|rpower|reventlog)$/){
               my @enableASMI = xCAT::TableUtils->get_site_attribute("enableASMI");
               if (defined($enableASMI[0])) {
                   if (($request_new->{command} !~ /^rspconfig$/) || 
                       (ref($request_new->{method} eq 'HASH'))) {
                       $enableASMI[0] =~ tr/a-z/A-Z/;    # convert to upper
                       if (($enableASMI[0] eq "1") || ($enableASMI[0] eq "YES")) {
                           #through asmi ......
                           $request_new->{fsp_api} = 0;
                           if(@failed_nodes != 0) {
                               my @temp = @failed_nodes;
                               @failed_nodes = (); 
                               $request_new->{node} = \@temp;
                               process_command( $request_new , \%hcps_will, \@failed_nodes, \%failed_msg);
                           } #end of if
                       } #end of if
                   } # end of if
               } #end of if  
           }
       } #end of if
    } #end of while(1)
}

##########################################################################
# connect hmc via ssh and execute remote command
##########################################################################
sub sshcmds_on_hmc
{
    my $ip = shift;
    my $user = shift;
    my $password = shift;
    my @cmds = @_;

    my %handled;
    my @data;
    my @exp;
    for my $cmd (@cmds)
    {
        if ( $cmd =~ /(.+?)=(.*)/)
        {
            my ($command,$value) = ($1,$2);
            $handled{$command} = $value;
        }
    }
    my %request = (
            ppcretry => 1,
            verbose  => 0,
            ppcmaxp    => 64,
            ppctimeout => 0,
            fsptimeout => 0,
            ppcretry   => 3,
            maxssh     => 8 

            );

    my $valid_ip;
    foreach my $individual_ip ( split /,/, $ip ) {
        ################################
        # Get userid and password 
        ################################
        my @cred = ($user, $password);
        $request{$individual_ip}{cred} = \@cred;

        @exp = xCAT::PPCcli::connect( \%request, 'hmc', $individual_ip);
        ####################################
        # Successfully connected 
        ####################################
        if ( ref($exp[0]) eq "Expect" ) {
            $valid_ip = $individual_ip;
            last;
        }
    }

    ########################################
    # Error connecting 
    ########################################
    if ( ref($exp[0]) ne "Expect" ) {
        return ([1,@cmds]);
    }
    ########################################
    # Process specific command 
    ########################################
    for my $cmd ( keys %handled)
    {
        my $result;
        if ($cmd eq 'network_reset')
        {
            $result = xCAT::PPCcli::network_reset( \@exp, $valid_ip, $handled{$cmd});
            my $RC = shift( @$result);
        }
        push @data, @$result[0]; 
    }
    ########################################
    # Close connection to remote server
    ########################################
    xCAT::PPCcli::disconnect( \@exp );

    return ([0, undef, \@data]);
}


sub check_fsp_api
{
    my $request = shift;
    
#    my $fsp_api = "/opt/xcat/sbin/fsp-api";
     my $fsp_api    = ($::XCATROOT) ? "$::XCATROOT/sbin/fsp-api" : "/opt/xcat/sbin/fsp-api";
    #my $libfsp  = "/usr/lib/libfsp.a";
     my $libfsp_aix   = ($::XCATROOT) ? "$::XCATROOT/lib/libfsp.so" : "/opt/xcat/lib/libfsp.so";
     my $libfsp_linux   = ($::XCATROOT) ? "$::XCATROOT/lib/libfsp.a" : "/opt/xcat/lib/libfsp.a";
#    my $libfsp  = "/opt/xcat/lib/libfsp.a";
#    my $libfsp    = ($::XCATROOT) ? "$::XCATROOT/lib/libfsp.a" : "/opt/xcat/lib/libfsp.a";
#    my $hw_svr  = "/opt/csm/csmbin/hdwr_svr";
    
    my $msg = ();
#    if((-e $fsp_api) && (-x $fsp_api)&& (-e $libfsp) && (-e $hw_svr)) {
    if((-e $fsp_api) && (-x $fsp_api)&& ((-e $libfsp_aix) || (-e $libfsp_linux) )) {
    	return 0;
    }
    
    return -1;
}

sub getHCPsOfNodes
{
    my $nodes    = shift;
    my $callback = shift;
    my $request  = shift;
    my %hcps;
    
    if ($request->{command} eq "mkhwconn" or $request->{command} eq "lshwconn" or $request->{command} eq "rmhwconn") {
        if ( grep (/^-s$/, @{$request->{arg}}) ) {

            my $ppctab = xCAT::Table->new('ppc');
            my %newhcp;
            if ( $ppctab ) {
                my $typeref = xCAT::DBobjUtils->getnodetype($nodes, "ppc");
                my $i = 0;
                unless ( $request->{sfp} ) {
                    for my $n (@$nodes) {
                        if ($$typeref{$n} =~ /^fsp|bpa$/) {
                            my $np = $ppctab->getNodeAttribs( $n, [qw(parent)]);
                            if ($np)  { # use parent(frame/cec)'s sfp attributes first,for high end machine with 2.5/2.6+ database
                                my $psfp = $ppctab->getNodeAttribs( $np->{parent}, [qw(sfp)]);
                                $newhcp{$n}{hcp} = [$psfp->{sfp}]  if ($psfp);
                            } else {    # if the node don't have a parent,for low end machine with 2.5 database
                                my $psfp = $ppctab->getNodeAttribs( $n, [qw(sfp)]);
                                $newhcp{$n}{hcp} = [$psfp->{sfp}] if ($psfp);
                            }
                        } else {
                             my $psfp = $ppctab->getNodeAttribs( $n, [qw(sfp)]);
                             $newhcp{$n}{hcp} = [$psfp->{sfp}] if($psfp); 
                        }
                        $newhcp{$n}{num} = 1;
                    } 
                    return \%newhcp;
                } else { 
                    my $sfp = $request->{sfp};
                    my %sfphash;
                    for my $n (@$nodes) {
                        # record hcp
                        $newhcp{$n}{hcp} = [$sfp];
                        $newhcp{$n}{num} = 1;  
                        # set the sfp attribute to the database
                        if ($$typeref{$n} =~ /^fsp|bpa$/) {
                            my $np = $ppctab->getNodeAttribs( $n, [qw(parent)]);
                            $sfphash{$np}{sfp} = $sfp if ( $np );                 
                        }
                        $sfphash{$n}{sfp} = $sfp;         
                    }
                    $ppctab->setNodesAttribs(\%sfphash);
                    return \%newhcp; 
                }            
            }else {
                $callback->({data=>["Could not open the ppc table"]});
                return undef;
            }
        }    
    }


    $hcps{maxnum} = 0; 
    #get hcp from ppc.
    foreach my $node( @$nodes) {
        #my $thishcp_type = xCAT::FSPUtils->getTypeOfNode($node, $callback);
        my $thishcp_type = xCAT::DBobjUtils->getnodetype($node, "ppc");
        if( $thishcp_type eq "hmc") {
            $hcps{$node}{hcp} = [$node];
            $hcps{$node}{num} = 1;
        } else {
            my $ppctab = xCAT::Table->new( 'ppc');
            unless($ppctab) {
                $callback->({data=>["Cannot open ppc table"]});	
	            return undef;
	        }	
	        #xCAT::MsgUtils->message('E', "Failed to open table 'ppc'.") if ( ! $ppctab);
            my $hcp_hash    = $ppctab->getNodeAttribs( $node,[qw(hcp)]);
            my $hcp    = $hcp_hash->{hcp};
            if ( !$hcp) {
	            #xCAT::MsgUtils->message('E', "Not found the hcp of $node");	
	            $callback->({data=>["Not found the hcp of $node"]});
	            return undef;
            }
	        #print "hcp:\n";
	        #print Dumper($hcp);
	        my @h = split(",", $hcp);
	       $hcps{$node}{hcp} = \@h;
	       $hcps{$node}{num} = @h;
       }
       if( $hcps{maxnum} < $hcps{$node}{num}) {
           $hcps{maxnum} = $hcps{$node}{num};
       }
    }
    #print "in getHCPsOfNodes\n";
    #print Dumper(\%hcps);
    return \%hcps;
}



1;

