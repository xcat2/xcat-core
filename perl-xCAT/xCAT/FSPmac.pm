# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::FSPmac;
use Socket;
use strict;
use Getopt::Long;
use xCAT::PPCmac;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::MsgUtils qw(verbose_message);
use xCAT::LparNetbootExp;
##########################################################################
# Parse the command line for options and operands 
##########################################################################
sub parse_args {
    xCAT::PPCmac::parse_args(@_);
}


##########################################################################
# Get LPAR MAC addresses
##########################################################################
sub do_getmacs {

    my $request  = shift;
    my $d        = shift;
    my $exp      = shift; 
    my $name     = shift;
    my $node     = shift;
    my $opt      = $request->{opt};
    my $ssh      = @$exp[0];
    my $userid   = @$exp[4];
    my $pw       = @$exp[5];
    my %optarg;
    my $cmd;
    my $result;

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

    ########################################
    ## Find Expect script
    ########################################
    #$cmd = ($::XCATROOT) ? "$::XCATROOT/sbin/" : "/opt/xcat/sbin/";
    #$cmd .= "lpar_netboot.expect";
    #
    ########################################
    ## Check command installed
    ########################################
    #if ( !-x $cmd ) {
    #    return( [RC_ERROR,"Command not installed: $cmd"] );
    #}
    #######################################
    # Save user name and passwd of hcp to 
    # environment variables.
    # lpar_netboot.expect depends on this
    #######################################
    $ENV{HCP_USERID} = $userid;
    $ENV{HCP_PASSWD} = $pw;

    #######################################
    # Turn on verbose and debugging 
    #######################################
    if ( exists($request->{verbose}) ) {
        #$cmd.= " -v -x";
        $optarg{'v'} = 1; #for verbose
        $optarg{'x'} = 1; #for debug
    }
    #######################################
    # Force LPAR shutdown
    #######################################
    if ( exists( $opt->{f} )) {
        #$cmd.= " -i";
        $optarg{'i'} = 1;
    } else {
        #################################
        # Force LPAR shutdown if LPAR is
        # running Linux
        #################################
        my $table = "nodetype";
        my $intable = 0;
        my @TableRowArray = xCAT::DBobjUtils->getDBtable($table);
        if ( @TableRowArray ) {
            foreach ( @TableRowArray ) {
                my @nodelist = split(',', $_->{'node'});
                my @oslist = split(',', $_->{'os'});
                my $osname = "AIX";
                if ( grep(/^$node$/, @nodelist) ) {
                    if ( !grep(/^$osname$/, @oslist) ) {
                        #$cmd.= " -i";
                        $optarg{'i'} = 1;
                    }
                    $intable = 1;
                    last;
                }
            }
        }
        #################################
        # Force LPAR shutdown if LPAR OS
        # type is not assigned in table
        # but mnt node is running Linux
        #################################
        if ( xCAT::Utils->isLinux() && $intable == 0 ) {
               #$cmd.= " -i";
               $optarg{'i'} = 1;
        }
    }

    my %client_nethash = xCAT::DBobjUtils->getNetwkInfo( [$node] );
    if ( grep /hf/, $client_nethash{$node}{mgtifname} ) {
        #$cmd.= " -t hfi-ent";
        $optarg{'t'} = "hfi-ent";
    } else {
        #$cmd.= " -t ent";
        $optarg{'t'} = "ent";
    }

    #######################################
    # Network specified (-D ping test)
    #######################################
    if ( exists( $opt->{noping} )) {
        $optarg{'D'} = 1;
        $optarg{'noping'} = 1;
        $optarg{'pprofile'} = "not_use"; #lpar_netboot.expect need pprofile for p5 & p6, but for p7 ih, we don't use this attribute.
    }

    if ( exists( $opt->{S} )) { 
        if ( exists( $opt->{o} )) {
            #$cmd .=" -o";
           $optarg{'o'} = 1;
        }
        #$cmd.= " -D -s auto -d auto -S $opt->{S} -G $opt->{G} -C $opt->{C}";
        $optarg{'D'} = 1;
        $optarg{'s'} = 'auto';
        $optarg{'d'} = 'auto';
        $optarg{'S'} = $opt->{S};
        $optarg{'C'} = $opt->{C};
        $optarg{'G'} = $opt->{G};
        $optarg{'pprofile'} = "not_use"; #lpar_netboot.expect need pprofile for p5 & p6, but for p7 ih, we don't use this attribute.
    } 
    #######################################
    # Add command options 
    #######################################
    #$cmd.= " -f -M -A -n \"$name\" \"$pprofile\" \"$fsp\" $id $hcp \"$node\"";
    $optarg{'f'} = 1;
    $optarg{'M'} = 1;
    $optarg{'A'} = 1;
    $optarg{'n'} = $name;
    #$optarg{'pprofile'} = $pprofile;
    $optarg{'fsp'} = $fsp;
    $optarg{'id'} = $id;
    $optarg{'hcp'} = $hcp;
    $optarg{'node'} = $node;

    ########################################
    ## Execute command
    ########################################
    #my $pid = open( OUTPUT, "$cmd 2>&1 |");
    #$SIG{INT} = $SIG{TERM} = sub { #prepare to process job termination and propogate it down
    #    kill 9, $pid;
    #    return( [RC_ERROR,"Received INT or TERM signal"] );
    #};
    #if ( !$pid ) {
    #    return( [RC_ERROR,"$cmd fork error: $!"] );
    #}
    ########################################
    ## Get command output
    ########################################
    #while ( <OUTPUT> ) {
    #    $result.=$_;
    #}
    #close OUTPUT;
    #
    ########################################
    ## Get command exit code
    ########################################
    #
    #foreach ( split /\n/, $result ) {
    #    if ( /^lpar_netboot / ) {
    #        $Rc = RC_ERROR;
    #        last;
    #    }
    #}
    xCAT::MsgUtils->verbose_message($request, "getmacs :lparnetbootexp for node:$node.");
    my $Rc = xCAT::LparNetbootExp->lparnetbootexp(\%optarg, $request);
    ######################################
    # Split results into array
    ######################################
    return $Rc;
}


##########################################################################
# Get LPAR MAC addresses
##########################################################################
sub getmacs {

    my $request = shift;
    my $par     = shift;
    my $exp     = shift;
    my $opt     = $request->{opt};
    my $hwtype  = @$exp[2];
    my $result;
    my $name;
    my @emptynode;
    my $res;
    
    if ( $par =~ /^HASH/ ) {
	#my $t = $request->{node};
	#foreach my $n (@$t) {
	#        return( [[$n,"Please use -D -f options to getmacs through FSP directly",RC_ERROR]] );
	#    }

        #########################################
        # Parse the filters specified by user
        #########################################
        my $filter;
        if ( $opt->{F} ) {
            my @filters = split /,/,$opt->{F};
            foreach ( @filters ) {
                my @value = split /=/,$_;
                $filter->{@value[0]} = @value[1];
            }
        }

        ######################################### 
        # A hash to save lpar attributes
        ######################################### 
        my %nodeatt = ();

        #########################################
        # Cleanup old data
        #########################################
        my $result  = ();

        #########################################
        # No ping test performed, call lshwres
        # to achieve the MAC address
        #########################################
        foreach my $hcp ( keys %$par ) {
            my $hash = $par->{$hcp};
            my $cmd; 
            my @lpar_name = keys(%$hash);
	    $name = $lpar_name[0];
	    my $d = $$hash{$name};
            #########################################
            # Achieve virtual ethernet MAC address
            #########################################
	    #@$cmd[0] = ["lpar","virtualio","","eth"];
	    #@$cmd[1] = ["port","hea","","logical"];
	    #@$cmd[2] = ["port","hea","","phys"];
            my @cmd = ("lpar_veth_mac","lpar_lhea_mac","lpar_hfi_mac");
            #########################################
            # Parse the output of lshwres command
            #########################################
            for ( my $stat = 0; $stat < 3; $stat++ ) {
		#my $output = xCAT::PPCcli::lshwres( $exp, @$cmd[$stat], $hcp);
                my $output  = xCAT::FSPUtils::fsp_api_action($request, $name, $d, $cmd[$stat]);
		my $macs; 
                my $res = $$output[1];
		chomp($res);
		my @op  = split("\n", $res);
		#print Dumper(\@op);
                foreach my $line ( @op ) {
                    if ( $line =~ /^.*lpar\_id=(\d+),.*$/ ) {
                        #########################################
                        # For the first two commands
                        #########################################
                        my $lparid = $1;
                        $nodeatt{$hcp}{$lparid}{'num'}++;
                        $macs      = $nodeatt{$hcp}{$lparid}{'num'};
                        my @attrs  = split /,/, $line;
                        foreach ( @attrs ) {
                            my @attr = split /=/, $_;
                            $nodeatt{$hcp}{$lparid}{$macs}{@attr[0]} = @attr[1];
                        }

                    } elsif ( ($line =~ /^(.*)port\_group=(\d+),(.*),"log\_port\_ids=(.*)"/) || ($line =~ /^(.*)port\_group=(\d+),(.*),log\_port\_ids=(.*)/) ) {
                        #########################################
                        # For the third command
                        #########################################
                        my $port_group = $2;
                        if ( $4 !~ /^none$/ ) {
                            my @ids        = split /,/, $4;
                            my @attrs      = split /,/, $1;
                            foreach (@attrs) {
                                my @attr   = split /=/,$_;
                                foreach (@ids) {
                                    $nodeatt{$hcp}{$port_group}{$_}{@attr[0]} = @attr[1];
                                }
                            } 
                            my @attrs      = split /,/, $3;
                            foreach (@attrs) {
                                my @attr   = split /=/,$_;
                                foreach (@ids) {
                                    $nodeatt{$hcp}{$port_group}{$_}{@attr[0]} = @attr[1];
                                }
                            }
                        }    
                    }
                }
            }
                            
            foreach ( keys %$hash ) {
                my $node       = $_;
                my $d          = $hash->{$_};
                my $mtms       = @$d[2];
                my $id         = @$d[0];
                my $nodetype       = @$d[4];

                my $mac_count  = $nodeatt{$mtms}{$id}{'num'};               
                my $value      = ();
                my $data    = ();
                my $type;

                #########################################
                # Invalid target hardware
                #########################################
                if ( $nodetype ne "lpar" ) {
                    return( [[$node,"Node must be LPAR",RC_ERROR]] );
                }

                #########################################
                # Put all the attributes required
                # together
                #########################################
                push @$value,"\n#Type  Phys_Port_Loc  MAC_Address  Adapter  Port_Group  Phys_Port  Logical_Port  VLan  VSwitch  Curr_Conn_Speed\n";

                for ( my $num = 1; $num <= $mac_count; $num++ ) {
                    my $mac_addr        = $nodeatt{$mtms}{$id}{$num}{'mac_addr'};
                    my $adapter_id      = $nodeatt{$mtms}{$id}{$num}{'adapter_id'};
                    my $port_group      = $nodeatt{$mtms}{$id}{$num}{'port_group'};
                    my $phys_port_id    = $nodeatt{$mtms}{$id}{$num}{'phys_port_id'};
                    my $logical_port_id = $nodeatt{$mtms}{$id}{$num}{'logical_port_id'};
                    my $vlan_id         = $nodeatt{$mtms}{$id}{$num}{'port_vlan_id'};
                    my $vswitch         = $nodeatt{$mtms}{$id}{$num}{'vswitch'};
                    my $phys_port_loc   = $nodeatt{$mtms}{$port_group}{$logical_port_id}{'phys_port_loc'};
                    my $curr_conn_speed = $nodeatt{$mtms}{$port_group}{$logical_port_id}{'curr_conn_speed'};

                    if ( $phys_port_loc ) {
                        $type = "hea";          
                    } else {
                        $type = "virtualio";
                    }
                    my $type        = $nodeatt{$mtms}{$id}{$num}{'type'};
                    my %att = ();
		    if( $mac_addr ) {
		        $mac_addr = format_mac($mac_addr);
	            }
                    if ( !exists( $opt->{M} )) {
                        my @mac_addrs = split /\|/, $mac_addr;
                        $mac_addr = @mac_addrs[0];
                    }
                    $att{'MAC_Address'}        = ($mac_addr) ? $mac_addr : "N/A";
                    $att{'Adapter'}            = ($adapter_id) ? $adapter_id : "N/A";
                    $att{'Port_Group'}         = ($port_group) ? $port_group : "N/A"; 
                    $att{'Phys_Port'}          = ($phys_port_id) ? $phys_port_id : "N/A"; 
                    $att{'Logical_Port'}       = ($logical_port_id) ? $logical_port_id : "N/A";
                    $att{'VLan'}               = ($vlan_id) ? $vlan_id : "N/A";
                    $att{'VSwitch'}            = ($vswitch) ? $vswitch : "N/A";
                    $att{'Phys_Port_Loc'}      = ($phys_port_loc) ? $phys_port_loc : "N/A";
                    $att{'Curr_Conn_Speed'}    = ($curr_conn_speed) ? $curr_conn_speed : "N/A";
                    $att{'Type'}               = $type;

                    #########################################
                    # Parse the adapter with the filters
                    # specified
                    #########################################
                    if ( defined($filter) ) {
                        my $matched = 0;
                        foreach my $key ( keys %$filter ) {
                            if ( $key eq "MAC_Address" ) {
                                my $mac = lc($att{$key});
                                my $filter_mac = lc($filter->{$key});

                                $mac =~ s/://g;
                                $filter_mac =~ s/://g;

                                if ( grep(/$filter_mac/, $mac) ) {
                                    $matched = 1;
                                    last;
                                }
                            } elsif ( grep(/$filter->{$key}/, $att{$key}) ) {
                                $matched = 1;
                                last;
                            }
                        }
                        if ( $matched ) {
                            push @$value,"$att{'Type'}  $att{'Phys_Port_Loc'}  $att{'MAC_Address'}  $att{'Adapter'}  $att{'Port_Group'}  $att{'Phys_Port'}  $att{'Logical_Port'}  $att{'VLan'}  $att{'VSwitch'}  $att{'Curr_Conn_Speed'}\n";
                        }
                    } else {
                        push @$value,"$att{'Type'}  $att{'Phys_Port_Loc'}  $att{'MAC_Address'}  $att{'Adapter'}  $att{'Port_Group'}  $att{'Phys_Port'}  $att{'Logical_Port'}  $att{'VLan'}  $att{'VSwitch'}  $att{'Curr_Conn_Speed'}\n";
                    }
                }
                #########################################
                # Write MAC address to database
                #########################################
                if ( !exists( $opt->{d} )) {
                    writemac( $node, $value );
                }


                if ( scalar(@$value) < 2 ) {
		    #my $filter = "lpar_id,curr_profile";
		    #my $prof   = xCAT::PPCcli::lssyscfg( $exp, "node", $mtms, $filter, $id );
		    #my $Rc = shift(@$prof);

                    #########################################
                    # Return error
                    #########################################
		    #if ( $Rc != SUCCESS ) {
		    #    return( [[$node,@$prof[0],$Rc]] );
		    #}

		    #foreach my $val ( @$prof ) {
		    #    my ($lpar_id,$curr_profile) = split  /,/, $val;
		    #    if ( !length($curr_profile) || ($curr_profile =~ /^none$/) ) {
		    #        push @emptynode,$node;
		    #    }
		    #}
		    return( [[$node,"get NO mac address from PHYP for $node",-1]]);
                }
                foreach ( @$value ) {
                    if ( /^#\s?Type/ ) {
                        $data.= "\n$_\n";
                    } else {
			#$data.= format_mac( $_ );
			$data .= $_;
                    }
                }

                push @$result,[$node,$data,0];
            }
        }
        if ( scalar(@emptynode) > 0 ) {
            return([[join(",", @emptynode),"\nThese nodes have no active profiles.  Please active the nodes to enable the default profiles",RC_ERROR]]);
        } 
        return([@$result]);
    } else {
        #########################################
        # Connect to fsp to achieve MAC address
        #########################################
        xCAT::MsgUtils->verbose_message($request, "getmacs START.");
        my $d = $par;

        #########################################
        # Get node data 
        #########################################
        my $lparid  = @$d[0];
        my $mtms    = @$d[2];
        my $type    = @$d[4];
        my $node    = @$d[6];

        #########################################
        # Invalid target hardware 
        #########################################
        if ( $type ne "lpar" ) {
            return( [[$node,"Node must be LPAR",RC_ERROR]] );
        }
        #########################################
        # Get name known by HCP
        #########################################
        my $filter = "name,lpar_id";
	# my $values = xCAT::PPCcli::lssyscfg( $exp, $type, $mtms, $filter );
	#my $Rc = shift(@$values);

        #########################################
        # Return error
        #########################################
	#if ( $Rc != SUCCESS ) {
	# return( [[$node,@$values[0],$Rc]] );
	    # }
        #########################################
        # Find LPARs by lpar_id
        #########################################
	# foreach ( @$values ) {
	#    if ( /^(.*),$lparid$/ ) {
	#        $name = $1;
	#        last;
	#    }
	# }
        #########################################
        # Node not found by lpar_id 
        #########################################
	# if ( !defined( $name )) {
	#    return( [[$node,"Node not found, lparid=$lparid",RC_ERROR]] );
        # }
        my $Rc;
        #my $sitetab  = xCAT::Table->new('site');
        #my $vcon = $sitetab->getAttribs({key => "conserverondemand"}, 'value');
        #if ($vcon and $vcon->{"value"} and $vcon->{"value"} eq "yes" ) {
		#    $result = xCAT::PPCcli::lpar_netboot(
		#            $exp,
		#            $request->{verbose},
		#            $name,
		#            $d,
		#            $opt );
        #   return( [[$node,"Not support conserverondemand's value is yes",RC_ERROR]] );
        #} else {
            #########################################
            # Manually collect MAC addresses.
            #########################################
            xCAT::MsgUtils->verbose_message($request, "getmacs :do_getmacs for node:$node.");
            $result = do_getmacs( $request, $d, $exp, $name, $node );
        #}
        #$sitetab->close;
        $Rc = shift(@$result);
  
        my $data;
        my $value;	
        if ( $Rc == SUCCESS ) {
	   foreach ( @$result ) {
	      if ( /^#\s?Type/ ) {
	         $data.= "\n$_\n";
	         push @$value, "\n$_\n";
	      } elsif ( /^ent\s+/ ||  /^hfi-ent\s+/ ) {
	         #my @fields = split /\s+/, $_;
	         #my $mac    = $fields[2];
	         #$mac    = format_mac( $mac );
	         #$fields[2] = $mac;
	         #$data  .= join(" ",@fields)."\n";
	         #push @$value, join(" ",@fields)."\n";
                 $data .= "$_\n";
                 push @$value, "$_\n";
	      }
	   }
	   push @$res,[$node,$data,0];
       }
        
        ##################################
        # Form string from array results 
        ##################################
        if ( exists($request->{verbose}) ) {
            if ( $Rc == SUCCESS ) {
                if ( !exists( $opt->{d} )) { 
                    writemac( $node, $value );
                }
            }
            return( [[$node,join( '', @$result ),$Rc]] );
        }
        ##################################
        # Return error
        ##################################
        if ( $Rc != SUCCESS ) {
            if ( @$result[0] =~ /lpar_netboot (.*)/ ) {
                return( [[$node,$1,$Rc]] );
            }
            return( [[$node,join( '', @$result ),$Rc]] );
        }
        #####################################
        # lpar_netboot returns:
        #
        #  # Connecting to lpar4\n
        #  # Connected\n
        #  # Checking for power off.\n
        #  # Power off complete.\n
        #  # Power on lpar4 to Open Firmware.\n
        #  # Power on complete.\n
        #  # Getting adapter location codes.\n
        #  # Type\t Location Code\t MAC Address\t Full Path Name\tPing Result\n
        #    ent U9117.MMA.10F6F3D-V5-C3-T1 1e0e122a930d /vdevice/l-lan@30000003
        #
        #####################################
	#my $data;

	#foreach ( @$result ) {
	#    if ( /^#\s?Type/ ) {
	#        $data.= "\n$_\n";
	#    } elsif ( /^ent\s+/ or /^hfi-ent\s+/) {
	#        $data.= format_mac( $_ );
	#    }
	#}
        #####################################
        # Write first valid adapter MAC to database
        #####################################
        if ( !exists( $opt->{d} )) {
            writemac( $node, $value );
        }
	#return( [[$node,$data,$Rc]] );
        xCAT::MsgUtils->verbose_message($request, "getmacs END.");
	return $res;
    }
}

##########################################################################
# Calculate secondary 1 and secondary 2 MAC address based on primary MAC
# for HFI devices
##########################################################################
sub cal_mac {

    my $mac = shift;

    $mac =~ s/://g;
    $mac =~ /(.........)(.)(..)/; 
    my ($basemac, $mac_h, $mac_l) = ($1,$2, $3);
    my $macnum_l = hex($mac_l);
    my $macnum_h = hex($mac_h);
    $macnum_l += 1; 
    if ($macnum_l > 0xFF) {
        $macnum_h += 1;
    }
    my $newmac_l = sprintf("%02X", $macnum_l);
    $newmac_l =~ /(..)$/;
    $newmac_l = $1;
    my $newmac_h = sprintf("%01X", $macnum_h);
    my $newmac = $basemac.$newmac_h.$newmac_l;

    return( $newmac );
}

##########################################################################
# Insert colons in MAC addresses for Linux only
##########################################################################
sub format_mac {

    my $mac = shift;
    #my $data = shift;

    #####################################
    # Get adapter mac
    #####################################
    my @newmacs;
    my $newmac = $mac;
    my @macs = split /\|/, $mac;

    if ( !xCAT::Utils->isAIX() ) {
        foreach my $mac_a ( @macs ) {
            #################################
            # Delineate MAC with colons
            #################################
            $mac_a = lc($mac_a);
            $mac_a =~ s/(\w{2})/$1:/g;
            $mac_a =~ s/:$//;
            push @newmacs, $mac_a;
        }
        $newmac = join("|",@newmacs);
    }


    return( "$newmac" );

}

##########################################################################
# checkmac format
##########################################################################

sub checkmac {
    my $mac = shift;
    if ( !xCAT::Utils->isAIX()) {
        if ($mac =~ /\w{2}:\w{2}:\w{2}:\w{2}:\w{2}:\w{2}/) {
            return 1;
        } else {
            return 0;
        }
    } else {
        return 1;
    }
}

##########################################################################
# Write first valid adapter MAC to database 
##########################################################################
sub writemac {

    my $name  = shift;
    my $data  = shift;
    my $value;
    my $pingret;
    my $ping_test;
    my $mac;
    my @fields;

    #####################################
    # Find first valid adapter
    #####################################
    foreach ( @$data ) {
        if ( /^ent\s+/ or /^hfi-ent\s+/ ) {
            $value = $_;
            #####################################
            # MAC not found in output
            #####################################
            if ( !defined( $value )) {
                return;
            }
            @fields = split /\s+/, $value;
            $pingret = $fields[4];
            if ( $pingret eq "successful" ) {
                $ping_test = 0;
                last;
            }
        }
    }

    #####################################
    # If no valid adapter, find the first one
    #####################################
    if ( $pingret ne "successful" ) {
        foreach ( @$data ) {
            unless (&checkmac($_)) {
                next;
            }
            if ( /^ent\s+/ or /^hfi-ent\s+/ ) {
                $value = $_;
                $ping_test = 0;
                last;
            } elsif ( /^hea\s+/ || /^virtualio\s+/ ||  /^HFI\s+/ ) {
                $value = $_;
                $ping_test = 1;
                last;
            }
        }
    }

    #####################################
    # MAC not found in output
    #####################################
    if ( !defined( $value )) {
        return;
    }
    #####################################
    # Get adapter mac
    #####################################
    #$value = format_mac( $value ); 
    @fields = split /\s+/, $value;
    $mac    = $fields[2];

    #####################################
    # Write adapter mac to database
    #####################################
    my $mactab = xCAT::Table->new( "mac", -create=>1, -autocommit=>1 );
    if ( !$mactab ) {
        return( [[$name,"Error opening 'mac'",RC_ERROR]] );
    }
    $mactab->setNodeAttribs( $name,{mac=>$mac} );
    $mactab->close();
}

1;










