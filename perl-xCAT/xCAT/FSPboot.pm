# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::FSPboot;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::Usage;
use xCAT::Utils;
use xCAT::MsgUtils;
use xCAT::PPCboot;

##########################################################################
# Parse the command line for options and operands 
##########################################################################
sub parse_args {
    xCAT::PPCboot::parse_args(@_);
}


##########################################################################
# Netboot the lpar 
##########################################################################
sub do_rnetboot {

    my $request = shift;
    my $d       = shift;
    my $exp     = shift;
    my $name    = shift;
    my $node    = shift;
    my $opt     = shift;
    my $ssh     = @$exp[0];
    my $userid  = @$exp[4];
    my $pw      = @$exp[5];
    my $result  = "";
    my $Rc      = SUCCESS;
    my $cmd;
    
    #######################################
    # Disconnect Expect session
    #######################################
    #xCAT::PPCcli::disconnect( $exp );
 
    #######################################
    # Get node data 
    #######################################
    my $id       = @$d[0];
    my $pprofile = @$d[1];
    my $fsp      = @$d[2];
    my $hcp      = @$d[3];

    #######################################
    # Find Expect script 
    #######################################
    $cmd = ($::XCATROOT) ? "$::XCATROOT/sbin/" : "/opt/xcat/sbin/";
    $cmd .= "lpar_netboot.expect"; 

    #######################################
    # Check command installed
    #######################################
    if ( !-x $cmd ) {
        return( [RC_ERROR,"Command not installed: $cmd"] );
    }
    #######################################
    # Save user name and passwd of hcp to
    # environment variables.
    # lpar_netboot.expect depends on it 
    #######################################
    $ENV{HCP_USERID} = $userid;
    $ENV{HCP_PASSWD} = $pw;

    #######################################
    # Turn on verbose and debugging
    #######################################
    if ( exists($request->{verbose}) ) {
        $cmd.= " -v -x";
    }
    #######################################
    # Force LPAR shutdown
    #######################################
    if ( exists( $opt->{f} ) || !xCAT::Utils->isAIX() ) {
        $cmd.= " -i";
    } 

    #######################################
    # Write boot order
    #######################################
    if (  exists( $opt->{s} )) {
        foreach ($opt->{s}) {
            if ( /^net$/ ) {
                $cmd.= " -w 1";
            } elsif ( /^net,hd$/ ) {
                $cmd.= " -w 2";
            } elsif ( /^hd,net$/ ) {
                $cmd.= " -w 3";
            } elsif ( /^hd$/ ) {
                $cmd.= " -w 4";
            }
        }
    }

    my @macs = split /\|/, $opt->{m};
    foreach my $mac ( @macs ) {
        $mac = lc($mac);
        #######################################
        # Network specified
        #######################################
        $cmd.= " -s auto -d auto -m \"$mac\" -S $opt->{S} -G $opt->{G} -C $opt->{C}";
        if (  exists( $opt->{o} )) {
            $cmd.= " -o";
        }

        my %client_nethash = xCAT::DBobjUtils->getNetwkInfo( [$node] );
        if ( grep /hf/, $client_nethash{$node}{mgtifname} ) {
            $cmd.= " -t hfi-ent";
        } else {
            $cmd.= " -t ent";
        }
    
        $pprofile = "not_use"; #lpar_netboot.expect need pprofile for p5 & p6, but for p7 ih, we don't use this attribute.

        #######################################
        # Add command options
        #######################################
        $cmd.= " -f \"$name\" \"$pprofile\" \"$fsp\" $id $hcp \"$node\"";
        print "cmd: $cmd\n";
        my $done = 0;
        while ( $done < 2 ) {
            $result = "";
            $Rc = SUCCESS;
            #######################################
            # Execute command
            #######################################
	    print "cmd:$cmd\n";
            my $pid = open( OUTPUT, "$cmd 2>&1 |");
            $SIG{INT} = $SIG{TERM} = sub { #prepare to process job termination and propogate it down
                kill 9, $pid;
                return( [RC_ERROR,"Received INT or TERM signal"] );
            };
            if ( !$pid ) {
                return( [RC_ERROR,"$cmd fork error: $!"] );
            }
            #######################################
            # Get command output
            #######################################
            while ( <OUTPUT> ) {
                $result.=$_;
            }
            close OUTPUT;
    
            #######################################
            # Get command exit code
            #######################################

            foreach ( split /\n/, $result ) {
                if ( /^lpar_netboot / ) {
                    $Rc = RC_ERROR;
                    last;
                }
            }

            if ( $Rc == SUCCESS ) {
                $done = 2;
            } else {
                $done = $done + 1;
                sleep 1;
            }
        }

        if ( $Rc == SUCCESS ) {
            last;
        }
    }
    return( [$Rc,$result] );
}


##########################################################################
# Get LPAR MAC addresses
##########################################################################
sub rnetboot {

    my $request = shift;
    my $d       = shift;
    my $exp     = shift;
    my $options = $request->{opt};
    my $hwtype  = @$exp[2];
    my $result;
    my $name;
    my $callback = $request->{callback};
    #####################################
    # Get node data 
    #####################################
    my $lparid = @$d[0];
    my $mtms   = @$d[2];
    my $type   = @$d[4];
    my $node   = @$d[6];
    my $o      = @$d[7]; 

    #####################################
    # Gateway (-G) 
    # Server  (-S) 
    # Client  (-C)
    # mac     (-m)
    #####################################
    my %opt = (
        G => $o->{gateway},
        S => $o->{server},
        C => $o->{client},
        m => $o->{mac}
    );
    #####################################
    # Strip colons from mac address 
    #####################################
    $opt{m} =~ s/://g;

    #####################################
    # Force LPAR shutdown 
    #####################################
    if ( exists( $options->{f} )) { 
        $opt{f} = 1;
    }
    #####################################
    # Write boot device order
    #####################################
    if ( exists( $options->{s} )) {
        $opt{s} = $options->{s};
    }
    if ( exists( $options->{o} )) {
        $opt{o} = $options->{o};
    }

    #####################################
    # Invalid target hardware 
    #####################################
    if ( $type !~ /^lpar$/ ) {
        return( [[$name,"Not supported",RC_ERROR]] );
    }
    #########################################
    # Get name known by HCP
    #########################################
    #my $filter = "name,lpar_id";
    #my $values = xCAT::PPCcli::lssyscfg( $exp, $type, $mtms, $filter );
    #my $Rc = shift(@$values);

    #########################################
    # Return error
    #########################################
    #if ( $Rc != SUCCESS ) {
    # return( [[$node,@$values[0],$Rc]] );
    #}
    #########################################
    # Find LPARs by lpar_id
    #########################################
    #foreach ( @$values ) {
    #    if ( /^(.*),$lparid$/ ) {
    #        $name = $1;
    #        last;
    #    }
    #}
    #########################################
    # Node not found by lpar_id
    #########################################
    #if ( !defined( $name )) {
    #    return( [[$node,"Node not found, lparid=$lparid",RC_ERROR]] );
    #}
    my $Rc;
    #########################################
    # Check current node state.
    # It is not allowed to rinitialize node
    # if it is in boot state
    #########################################
    if ( !exists( $options->{F} ) && !xCAT::Utils->isAIX() ) {
        my $chaintab = xCAT::Table->new('chain');
        my $vcon = $chaintab->getAttribs({ node => "$node"}, 'currstate');
        if ( $vcon and $vcon->{"currstate"} and $vcon->{"currstate"} eq "boot" ) {
            return( [[$node,"Node is in boot state. Use nodeset command before rnetboot or use -F option with rnetboot",RC_ERROR]] );
        }
    }

    #my $sitetab  = xCAT::Table->new('site');
    #my $vcon = $sitetab->getAttribs({key => "conserverondemand"}, 'value');
    #if ($vcon and $vcon->{"value"} and $vcon->{"value"} eq "yes" ) {
	    #   $result = xCAT::PPCcli::lpar_netboot(
	    #                $exp,
	    #                $request->{verbose},
	    #                $name,
	    #                $d,
	    #                \%opt );
    #    return( [[$node,"Not support conserverondemand's value is yes",RC_ERROR]] );
    #} else {
        #########################################
        # Manually perform boot. 
        #########################################
        $result = do_rnetboot( $request, $d, $exp, $name, $node, \%opt );
    #}
    #$sitetab->close;

    if (defined($request->{opt}->{m})) {
    
        my $retries = 0;
        my @monnodes = ($name);
        my $monsettings = xCAT::Utils->generate_monsettings($request, \@monnodes);
        xCAT::Utils->monitor_installation($request, $monsettings);;
        while ($retries++ < $monsettings->{'retrycount'} && scalar(keys %{$monsettings->{'nodes'}}) > 0) {
            ####lparnetboot can not support multiple nodes in one invocation
            ####for now, does not know how the $d and \%opt will be changed if
            ####support mulitiple nodes in one invocation,
            ####so just use the original node name and node attribute array and hash
             
             my $rsp={};
             $rsp->{data}->[0] = "$node: Reinitializing the installation: $retries retry";
             xCAT::MsgUtils->message("I", $rsp, $callback);
             #if ($vcon and $vcon->{"value"} and $vcon->{"value"} eq "yes" ) {
		    #    $result = xCAT::PPCcli::lpar_netboot(
		    #                $exp,
		    #                $request->{verbose},
		    #                $name,
		    #                $d,
		    #                \%opt );
            #return( [[$node,"Not support conserverondemand's value is yes",RC_ERROR]] );
            #} else {
                $result = do_rnetboot( $request, $d, $exp, $name, $node, \%opt );
            #}
            xCAT::Utils->monitor_installation($request, $monsettings);
                
        }
        #failed after retries
        if (scalar(keys %{$monsettings->{'nodes'}}) > 0) {
            foreach my $node (keys %{$monsettings->{'nodes'}}) {
                my $rsp={};
                $rsp->{data}->[0] = "The node \"$node\" can not reach the expected status after $monsettings->{'retrycount'} retries, the installation for this done failed";
                xCAT::MsgUtils->message("E", $rsp, $callback);
            }
         }
    }
    $Rc = shift(@$result);
    

    ##################################
    # Form string from array results
    ##################################
    if ( exists($request->{verbose}) ) {
        return( [[$node,join( '', @$result ),$Rc]] );
    }
    ##################################
    # Return error
    # lpar_netboot returns (for example):
    #  # Connecting to lpar1
    #  # Connected
    #  # Checking for power off.
    #  # Power off the node
    #  # Wait for power off.
    #  # Power off complete.
    #  # Power on lpar1 to Open Firmware.
    #  # Power on complete.
    #    lpar_netboot: can not find mac address 42DAB.
    #
    ##################################
    if ( $Rc != SUCCESS ) {
        if ( @$result[0] =~ /lpar_netboot (.*)/ ) {
            return( [[$node,$1,$Rc]] );
        }
        return( [[$node,join( '', @$result ),$Rc]] );
    }
    ##################################
    # Split array into string
    ##################################
    my $data = @$result[0];
    if ( $hwtype eq "hmc" ) {
        $data = join( '', @$result );
    }
    ##################################
    # lpar_netboot returns:
    #
    #  # Connecting to lpar1
    #  # Connected
    #    ...
    #  lpar_netboot Status: network boot initiated
    #  # bootp sent over network.
    #  lpar_netboot Status: waiting for the boot image to boot up.
    #  # Network boot proceeding, lpar_netboot is exiting.
    #  # Finished.
    #
    #####################################
    if ( $data =~ /Finished/) {
        return( [[$node,"Success",$Rc]] );
    }
    #####################################
    # Can still be error w/ Rc=0:
    #
    #  # Connecting to lpar1
    #  # Connected
    #    ...
    #  lpar_netboot Status: network boot initiated
    #  # bootp sent over network.
    #  lpar_netboot Status: waiting for the boot image to boot up.
    #  lpar_netboot: bootp operation failed.
    #
    #####################################
    if ( $data =~ /lpar_netboot (.*)/ ) {
        return( [[$node,$1,RC_ERROR]] );
    }
    return( [[$node,$data,RC_ERROR]] );
}
 

1;







