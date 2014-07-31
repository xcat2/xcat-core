# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCboot;
use lib "/opt/xcat/lib/perl";
use Data::Dumper;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::Usage;
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::MsgUtils;
use xCAT::LparNetbootExp;

##########################################################################
# Parse the command line for options and operands 
##########################################################################
sub parse_args {

    my $request = shift;
    my %opt     = ();
    my $cmd     = $request->{command};
    my $args    = $request->{arg};

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

    if ( !GetOptions( \%opt, qw(h|help V T v|version I|iscsiboot F f o s=s m:s@ r=s t=s) )) { 
        return( usage() );
    }

    ####################################
    # Option -h for Help
    ####################################
    if ( exists( $opt{h} )) {
        return( usage() );
    }
    ####################################
    # Option -v for version
    ####################################
    if ( exists( $opt{v} )) {
        my $version = xCAT::Utils->Version();
        return ([$version]);
    }

    if ( exists( $opt{s} ) ){
        my @boot_devices = split(/,/, $opt{s});
        foreach (@boot_devices) {
            if ( (!/^net$/) && (!/^hd$/) ) {
                return(usage( "boot device $_ is not supported" ));
            }
         }
    }

    if (exists( $opt{m} ) ){
        my $res = xCAT::Utils->check_deployment_monitoring_settings($request, \%opt);
        if ($res != SUCCESS) {
             return(usage());
        } 
    }
    #############################################
    # T is used for trace, V is used for debug
    #############################################
    if (exists($opt{T})) {
        $opt{V} = 1;
        delete $opt{T};

    }elsif(exists($opt{V})) {
        $opt{T} = 1;
        delete $opt{V};
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
    $request->{method} = $cmd; 
    return( \%opt );
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
    my $subreq  = $request->{subreq};
    my $Rc      = SUCCESS;
    my $result  = "";
    my $cmd;
    my %optarg;

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
    #if (!-x "/usr/bin/expect" ) {
    #    return( [RC_ERROR,"Command not installed: /usr/bin/expect"] );
    #}
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
    if ( ${$request->{arg}}[0] eq '-V' ) {
        #$cmd.= " -v -x";
        $optarg{'v'} = 1; #for verbose
        $optarg{'x'} = 1; #for debug
    }
    #######################################
    # Force LPAR shutdown
    #######################################
    if ( exists( $opt->{f} ) || !xCAT::Utils->isAIX() ) {
        #$cmd.= " -i";
        $optarg{'i'} = 1;
    } 

    #######################################
    # Write boot order
    #######################################
    if (  exists( $opt->{s} )) {
        foreach ($opt->{s}) {
            if ( /^net$/ ) {
                #$cmd.= " -w 1";
                $optarg{'w'} = 1;
            } elsif ( /^net,hd$/ ) {
                #$cmd.= " -w 2";
                $optarg{'w'} = 2;
            } elsif ( /^hd,net$/ ) {
                #$cmd.= " -w 3";
                $optarg{'w'} = 3;
            } elsif ( /^hd$/ ) {
                #$cmd.= " -w 4";
                $optarg{'w'} = 4;
            }
        }
    }

    if (  exists( $opt->{o} )) {
        #$cmd.= " -o";
        $optarg{'o'} = 1;
    }

    my @macs = split /\|/, $opt->{m};
    foreach my $mac ( @macs ) {
        #######################################
        # Network specified
        #######################################
        my $mac_a = lc($mac);
        #$cmd.= " -s auto -d auto -m $mac_a -S $opt->{S} -C $opt->{C} -N $opt->{N}";

        $optarg{'s'} = 'auto';
        $optarg{'d'} = 'auto';
        $optarg{'m'} = $mac_a;
        $optarg{'S'} = $opt->{S};
        $optarg{'C'} = $opt->{C};
        $optarg{'N'} = $opt->{N};
        if (defined($opt->{G}))
        {
            #$cmd.= " -G $opt->{G}";
            $optarg{'G'} = $opt->{G};
        }
  

        #######################################
        # Get required attributes from master
        # of the node if -I|--iscsiboot is
        # specified
        #######################################
        if (  exists( $opt->{I} )) {
            my $ret;
            my $dump_target;
            my $dump_lun;
            my $dump_port;
            my $noderestab = xCAT::Table->new('noderes');
            unless ($noderestab)
            {
                xCAT::MsgUtils->message('S',
                                "Unable to open noderes table.\n");
                return 1;
            }
            my $et = $noderestab->getNodeAttribs($node, ['xcatmaster']);
            if ($et and $et->{'xcatmaster'})
            {
                $ret = xCAT::Utils->runxcmd(
                {
                    command => ['xdsh'],
                    node    => [$et->{'xcatmaster'}],
                    arg     => [ 'cat /tftpboot/$node.info' ]
                },
                $subreq, 0, 0 );
            } else {
                $ret = `cat /tftpboot/$node.info`;
            }
            chomp($ret);
            my @attrs = split /\n/, $ret;
            foreach (@attrs)
            {
                if (/DUMP_TARGET=(.*)$/) {
                    $dump_target = $1;
                } elsif (/DUMP_LUN=(.*)$/) {
                    $dump_lun = $1;
                    $dump_lun =~ s/^0x(.*)$/$1/g;
                } elsif (/DUMP_PORT=(.*)$/) {
                    $dump_port =$1;
                }
            }
            if ( defined($dump_target) and defined($dump_lun) and defined($dump_port) ) {
                #$cmd.= " -T \"$dump_target\" -L \"$dump_lun\" -p \"$dump_port\"";
                $optarg{'T'} = $dump_target;
                $optarg{'L'} = $dump_lun;
                $optarg{'p'} = $dump_port;
            } else {
                return( [RC_ERROR,"Unable to find DUMP_TARGET, DUMP_LUN, DUMP_PORT for iscsi dump"] );
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
        # Add command options
        #######################################
        #$cmd.= " -f \"$name\" \"$pprofile\" \"$fsp\" $id $hcp \"$node\"";
        $optarg{'f'} = 1;
        $optarg{'name'} = $name;
        $optarg{'pprofile'} = $pprofile;
        $optarg{'fsp'} = $fsp;
        $optarg{'id'} = $id;
        $optarg{'hcp'} = $hcp;
        $optarg{'node'} = $node;

        my $done = 0;
        while ( $done < 2 ) {
            $result = "";
            $Rc = SUCCESS;
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

            #######################################
            # Invoke the lpar_netbootexp
            #######################################
            $result = xCAT::LparNetbootExp->lparnetbootexp(\%optarg, $request);
            $Rc = @$result[0];
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

    # Set the boot mode to norm from 'of' (open firmware)
    # NOW, only necessary for IVM
    my $hwtype = @$exp[2];
    if ($hwtype eq "ivm") {
        my $server = @$exp[3];

        # creat connection first
        my @newexp = xCAT::PPCcli::connect( $request, $hwtype, $server );
        if (ref($newexp[0]) eq "Expect" ) {
            my $cfg = "lpar_id=@$d[0],boot_mode=norm";
            # change the boot mode to 'norm'
            xCAT::PPCcli::chsyscfg(\@newexp, "prof", $d, $cfg);
            xCAT::PPCcli::disconnect(\@newexp);
        } else {
            my $rsp;
            $rsp->{data} = ["Failed to set the boot mode to normal. For rnetboot command, you have to rpower off and then on the node after finishing the OS deployment."];
            xCAT::MsgUtils->message("E", $rsp, $request->{callback});
        }
    }

    return  $result;
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
        N => $o->{netmask},
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
    # Do iscsi boot
    #####################################
    if ( exists( $options->{I} )) {
        $opt{I} = 1; 
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
    my @vcons = xCAT::TableUtils->get_site_attribute("conserverondemand");
    my $vcon = $vcons[0]; 
    #if ($vcon and $vcon->{"value"} and $vcon->{"value"} eq "yes" ) {
    if ( defined($vcon) and $vcon eq "yes" ) {
        $result = xCAT::PPCcli::lpar_netboot(
                            $exp,
                            $request->{verbose},
                            $name,
                            $d,
                            \%opt );
    } else {
        #########################################
        # Manually perform boot. 
        #########################################
        $result = do_rnetboot( $request, $d, $exp, $name, $node, \%opt );
    }
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
            if ($vcon and $vcon->{"value"} and $vcon->{"value"} eq "yes" ) {
                $result = xCAT::PPCcli::lpar_netboot(
                                    $exp,
                                    $request->{verbose},
                                    $name,
                                    $d,
                                    \%opt );
            } else {
                $result = do_rnetboot( $request, $d, $exp, $name, $node, \%opt );
            }
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







