# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCmac;
use Socket;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::NetworkUtils;


##########################################################################
# Parse the command line for options and operands 
##########################################################################
sub parse_args {

    my $request = shift;
    my %opt     = ();
    my $cmd     = $request->{command};
    my $args    = $request->{arg};
    my $node    = $request->{node};
    my $vers = 
    my @VERSION = qw( 2.1 );

    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage($cmd);
        return( [ $_[0], $usage_string] );
    };
    #############################################
    # Process command-line arguments
    #############################################
    if ( !defined( $args )) {
        $request->{method} = $cmd;
        return( \%opt );
    }
    #############################################
    # Checks case in GetOptions, allows opts
    # to be grouped (e.g. -vx), and terminates
    # at the first unrecognized option.
    #############################################
    @ARGV = @$args;
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );

    if ( !GetOptions( \%opt,qw(h|help V|Verbose v|version C=s G=s S=s D d f o F=s arp))) { 
        return( usage() );
    }
    ####################################
    # Option -h for Help
    ####################################
    #if ( exists( $opt{h} )) {
    #    return( usage() );
    #}
    ####################################
    # Option -v for version
    ####################################
    if ( exists( $opt{v} )) {
        return( \@VERSION );
    }
    ####################################
    # Check for "-" with no option
    ####################################
    if ( grep(/^-$/, @ARGV )) {
        return(usage( "Missing option: -" ));
    }
    ####################################
    # Check for an extra argument
    ####################################
    if ( defined( $ARGV[0] )) {
        return(usage( "Invalid Argument: $ARGV[0]" ));
    }
    ####################################
    # Check argument for ping test
    ####################################
    if ( exists($opt{D}) ) {
        my @network;
        my $client_ip;
        my $gateway;
        my $server;
        my $server_ip;
        my %server_nethash;

        ####################################
        # Set server IP
        ####################################
        if ( exists($opt{S}) ) {
            push @network, $_;
        } else {
			$server = xCAT::Utils->getSNformattedhash( $node, "xcat", "node", "primary" );
            foreach my $key ( keys %$server ) {
                my $valid_ip = xCAT::Utils->validate_ip( $key );
                if ( $valid_ip ) {
                    ###################################################
                    # Service node is returned as hostname, Convert 
                    # hostname to IP  
                    ####################################
                    $server_ip = xCAT::NetworkUtils->getipaddr($key);
                    chomp $server_ip;
                } else {
                    ####################################
                    # Service node is returned as an IP
                    # set the IP as server 
                    ####################################
                    $server_ip = $key;
                }

                if ( $server_ip ) {
                    $opt{S} = $server_ip; 
                    push @network, $server_ip;
                }
                last;
            }
        }
        ####################################################################
        # Fulfill in the server network information for gateway resolving
        ####################################################################
        if ( exists($opt{S}) ) {
            # why convert to hostname??
            #$server = gethostbyaddr( inet_aton($opt{S}), AF_INET );
            $server = $opt{S};
            if ( $server ) {
                %server_nethash = xCAT::DBobjUtils->getNetwkInfo( [$server] );
            }
        }

        my %client_nethash = xCAT::DBobjUtils->getNetwkInfo( $node );
        #####################################
        # Network attributes undefined
        #####################################
        if ( !%client_nethash ) {
            # IPv6, the client ip address may not be available,
            # if the link local address is being used,
            # the link local address is calculated from mac address
            if ($opt{S} =~ /:/) {
                #get the network "fe80::"
                my $tmpll = "fe80::1";
                %client_nethash = xCAT::DBobjUtils->getNetwkInfo( [$tmpll] );
                if (defined $client_nethash{$tmpll})
                {
                    $client_nethash{@$node[0]} = $client_nethash{$tmpll};
                }
            } else {
                return( [RC_ERROR,"Cannot get network information for node"] );
            }
        }

        if ( exists($opt{C}) ) {
            if ( scalar(@$node) > 1 ) {
                return( [RC_ERROR,"Option '-C' doesn't work with noderange\n"] );
            }
            push @network, $_;
        } else {
            # get, check the node IP
            $client_ip = xCAT::NetworkUtils->getipaddr(@$node[0]);
            chomp $client_ip;
            if ( $client_ip ) {
                $opt{C} = $client_ip;
                push @network, $client_ip;
            } else {
                if ($opt{S} =~ /:/) {
                    # set the IPv6 loopback address, lpar_netboot will handle it
                    $opt{C} = "::1";
                    push @network, "::1";
                }
            }
        }


        if ( exists($opt{G}) ) {
            push @network, $_;
        } elsif ( $client_nethash{@$node[0]}{net} eq $server_nethash{$server}{net} ) {
            ####################################
            # Set gateway to service node if 
            # service node and client node are 
            # in the same net
            ####################################
            $gateway = $opt{S};
            $opt{G} = $gateway;
            push @network, $gateway;
        } else {
            ####################################
            # Set gateway in networks table
            ####################################
            $gateway = $client_nethash{@$node[0]}{gateway};
            if ( $gateway ) {
                $opt{G} = $gateway;
                push @network, $gateway;
            }
        }

        if ( @network ) {
            if ( scalar(@network) != 3 ) {
                return( usage() );
            }
            my $result = xCAT::Utils->validate_ip( $opt{C}, $opt{G}, $opt{S} );
            if ( @$result[0] ) {
                return(usage( @$result[1] ));
            }
        }
    } elsif ( exists($opt{S}) || exists($opt{G}) || exists($opt{C}) ) {
        return( [RC_ERROR,"Option '-D' is required for ping test\n"] );
    }

    ####################################
    # Check -F options's format 
    ####################################
    if ( exists($opt{F}) ) {
        my @filters = split /,/,$opt{F};
        foreach ( @filters ) {
            my @value = split /=/,$_;
            if ( !@value[1] ) {
                return( usage("Option '-F' contains wrong filter format") );
            }
        }
    }

    ####################################
    # Set method to invoke 
    ####################################
    $request->{method} = $cmd; 
    return( \%opt );
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
    my $cmd;
    my $result;

    #######################################
    # Disconnect Expect session 
    #######################################
    xCAT::PPCcli::disconnect( $exp );

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
    # lpar_netboot.expect depends on this
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
    if ( exists( $opt->{f} )) {
        $cmd.= " -i";
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
                        $cmd.= " -i";
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
            $cmd.= " -i";
        }
    }

    my %client_nethash = xCAT::DBobjUtils->getNetwkInfo( [$node] );
    if ( grep /hf/, $client_nethash{$node}{mgtifname} ) {
        $cmd.= " -t hfi-ent";
    } else {
        $cmd.= " -t ent";
    }

    #######################################
    # Network specified (-D ping test)
    #######################################
    if ( exists( $opt->{S} )) {
        if ( exists( $opt->{o} )) {
            $cmd .=" -o";
        }
        $cmd.= " -D -s auto -d auto -S $opt->{S} -G $opt->{G} -C $opt->{C}";
    } 
    #######################################
    # Add command options 
    #######################################
    $cmd.= " -f -M -A -n \"$name\" \"$pprofile\" \"$fsp\" $id $hcp \"$node\"";

    #######################################
    # Execute command 
    #######################################
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
    my $Rc = SUCCESS;

    foreach ( split /\n/, $result ) {
        if ( /^lpar_netboot / ) {
            $Rc = RC_ERROR;
            last;
        }
    }
    ######################################
    # Split results into array
    ######################################
    return( [$Rc, split( /\n/, $result)] ); 
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

    if ( $par =~ /^HASH/ ) {
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

            #########################################
            # Achieve virtual ethernet MAC address
            #########################################
            @$cmd[0] = ["lpar","virtualio","","eth"];
            @$cmd[1] = ["port","hea","","logical"];
            @$cmd[2] = ["port","hea","","phys"];

            #########################################
            # Parse the output of lshwres command
            #########################################
            for ( my $stat = 0; $stat < 3; $stat++ ) {
                my $output = xCAT::PPCcli::lshwres( $exp, @$cmd[$stat], $hcp);
                my $macs; 

                foreach my $line ( @$output ) {
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
                push @$value,"\n#Type  Phys_Port_Loc  MAC_Address  Adapter  Port_Group  Phys_Port  Logical_Port  VLan  VSwitch  Curr_Conn_Speed";

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
                        $type = "hea      ";          
                    } else {
                        $type = "virtualio";
                    }

                    my %att = ();
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
                        my $matched = 1;
                        foreach ( keys %$filter ) {
                            if ( $att{$_} ne $filter->{$_} ) {
                                $matched = 0;
                                last;
                            }
                        }
                        if ( $matched == 1 ) {
                            push @$value,"$att{'Type'}  $att{'Phys_Port_Loc'}  $att{'MAC_Address'}  $att{'Adapter'}  $att{'Port_Group'}  $att{'Phys_Port'}  $att{'Logical_Port'}  $att{'VLan'}  $att{'VSwitch'}  $att{'Curr_Conn_Speed'}";
                        }
                    } else {
                        push @$value,"$att{'Type'}  $att{'Phys_Port_Loc'}  $att{'MAC_Address'}  $att{'Adapter'}  $att{'Port_Group'}  $att{'Phys_Port'}  $att{'Logical_Port'}  $att{'VLan'}  $att{'VSwitch'}  $att{'Curr_Conn_Speed'}";
                    }
                }
                #########################################
                # Write MAC address to database
                #########################################
                if ( !exists( $opt->{d} )) {
                    writemac( $node, $value );
                }


                if ( scalar(@$value) < 2 ) {
                    my $filter = "lpar_id,curr_profile";
                    my $prof   = xCAT::PPCcli::lssyscfg( $exp, "node", $mtms, $filter, $id );
                    my $Rc = shift(@$prof);

                    #########################################
                    # Return error
                    #########################################
                    if ( $Rc != SUCCESS ) {
                        return( [[$node,@$prof[0],$Rc]] );
                    }

                    foreach my $val ( @$prof ) {
                        my ($lpar_id,$curr_profile) = split  /,/, $val;
			if ( (!length($curr_profile)) || ($curr_profile =~ /^none$/) ) {
                            push @emptynode,$node;
                        }
                    }
                }
                foreach ( @$value ) {
                    if ( /^#\s?Type/ ) {
                        $data.= "\n$_\n";
                    } else {
                        $data.= format_mac( $_ );
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
        my $values = xCAT::PPCcli::lssyscfg( $exp, $type, $mtms, $filter );
        my $Rc = shift(@$values);

        #########################################
        # Return error
        #########################################
        if ( $Rc != SUCCESS ) {
            return( [[$node,@$values[0],$Rc]] );
        }
        #########################################
        # Find LPARs by lpar_id
        #########################################
        foreach ( @$values ) {
            if ( /^(.*),$lparid$/ ) {
                $name = $1;
                last;
            }
        }
        #########################################
        # Node not found by lpar_id 
        #########################################
        if ( !defined( $name )) {
            return( [[$node,"Node not found, lparid=$lparid",RC_ERROR]] );
        }

        my $sitetab  = xCAT::Table->new('site');
        my $vcon = $sitetab->getAttribs({key => "conserverondemand"}, 'value');
        if ($vcon and $vcon->{"value"} and $vcon->{"value"} eq "yes" ) {
            $result = xCAT::PPCcli::lpar_netboot(
                            $exp,
                            $request->{verbose},
                            $name,
                            $d,
                            $opt );
        } else {
            #########################################
            # Manually collect MAC addresses.
            #########################################
            $result = do_getmacs( $request, $d, $exp, $name, $node );
        }
        $sitetab->close;
        $Rc = shift(@$result);
   
        ##################################
        # Form string from array results 
        ##################################
        if ( exists($request->{verbose}) ) {
            if ( $Rc == SUCCESS ) {
                if ( !exists( $opt->{d} )) { 
                    writemac( $node, $result );
                }
            }
            return( [[$node,join( '', @$result ),$Rc]] );
        }
        ##################################
        # Return error
        ##################################
        if ( $Rc != SUCCESS ) {
            if ( @$result[0] =~ /lpar_netboot Status: (.*)/ ) {
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
        my $data;

        foreach ( @$result ) {
            if ( /^#\s?Type/ ) {
                $data.= "\n$_\n";
            } elsif ( /^ent\s+/ or /^hfi-ent\s+/ ) {
                $data.= format_mac( $_ );
            }
        }
        #####################################
        # Write first valid adapter MAC to database
        #####################################
        if ( !exists( $opt->{d} )) {
            writemac( $node, $result );
        }
        return( [[$node,$data,$Rc]] );
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

    my $data = shift;

    $data =~ /^(\S+\s+\S+\s+)(\S+)(\s+.*)$/;
    my $mac = $2;
    #####################################
    # Get adapter mac
    #####################################
    my @newmacs;
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
        my $newmac = join("|",@newmacs);
        $data   =~ s/$mac/$newmac/;
    }

    return( "$data\n" );

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
            if ( /^ent\s+/ or /^hfi-ent\s+/ ) {
                $value = $_;
                $ping_test = 0;
                last;
            } elsif ( /^hea\s+/ || /^virtualio\s+/ ) {
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
    $value = format_mac( $value ); 
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










