# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCmac;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);



##########################################################################
# Parse the command line for options and operands 
##########################################################################
sub parse_args {

    my $request = shift;
    my %opt     = ();
    my $cmd     = $request->{command};
    my $args    = $request->{arg};
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

    if ( !GetOptions( \%opt,qw(h|help V|Verbose v|version C=s G=s S=s d f))) { 
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
    # If one specified, all required 
    ####################################
    my @network;
    foreach ( qw(C G S) ) {
        if ( exists($opt{$_}) ) {
            push @network, $_;
        }
    }
    if ( @network ) {
        if ( scalar(@network) != 3 ) {
            return( usage() );
        }
        my $result = validate_ip( $opt{C}, $opt{G}, $opt{S} );
        if ( @$result[0] ) {
            return(usage( @$result[1] ));
        }
    } 
    ####################################
    # Set method to invoke 
    ####################################
    $request->{method} = $cmd; 
    return( \%opt );
}



##########################################################################
# Validate list of IPs
##########################################################################
sub validate_ip {

    foreach (@_) {
        my $ip = $_;

        ###################################
        # Length is 4 for IPv4 addresses
        ###################################
        my (@octets) = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/;
        if ( scalar(@octets) != 4 ) {
            return( [1,"Invalid IP address1: $ip"] );
        }
        foreach my $octet ( @octets ) {
            if (( $octet < 0 ) or ( $octet > 255 )) {
                return( [1,"Invalid IP address2: $ip"] );
            }
        }
    }
    return([0]);
}



##########################################################################
# IVM get LPAR MAC addresses
##########################################################################
sub ivm_getmacs {

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
    }
    #######################################
    # Network specified (-D ping test)
    #######################################
    if ( exists( $opt->{S} )) { 
        $cmd.= " -D -s auto -d auto -S $opt->{S} -G $opt->{G} -C $opt->{C}";
    } 
    #######################################
    # Add command options 
    #######################################
    $cmd.= " -t ent -f -M -A -n \"$name\" \"$pprofile\" \"$fsp\" $id $hcp \"$node\"";

    #######################################
    # Execute command 
    #######################################
    if ( !open( OUTPUT, "$cmd 2>&1 |")) {
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
        if ( /^lpar_netboot: / ) {
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
    my $d       = shift;
    my $exp     = shift;
    my $opt     = $request->{opt};
    my $hwtype  = @$exp[2];
    my $result;
    my $name;

    #########################################
    # Get node data 
    #########################################
    my $lparid = @$d[0];
    my $mtms   = @$d[2];
    my $type   = @$d[4];
    my $node   = @$d[6];

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
    #########################################
    # Manually collect MAC addresses.
    #########################################
    $result = ivm_getmacs( $request, $d, $exp, $name, $node );
    $Rc = shift(@$result);
   
    ##################################
    # Form string from array results 
    ##################################
    if ( exists($request->{verbose}) ) {
        if ( $Rc == SUCCESS ) {
            if ( !exists( $opt->{d} )) { 
                writemac( $name, $result );
            }
        }
        return( [[$name,join( '', @$result ),$Rc]] );
    }
    ##################################
    # Return error
    ##################################
    if ( $Rc != SUCCESS ) {
        if ( @$result[0] =~ /lpar_netboot: (.*)/ ) {
            return( [[$name,$1,$Rc]] );
        }
        return( [[$name,join( '', @$result ),$Rc]] );
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
        } elsif ( /^ent\s+/ ) {
            $data.= format_mac( $_ );
        }
    }
    #####################################
    # Write first valid adapter MAC to database
    #####################################
    if ( !exists( $opt->{d} )) {
        writemac( $name, $result );
    }
    return( [[$name,$data,$Rc]] );
}


##########################################################################
# Insert colons in MAC addresses for Linux only
##########################################################################
sub format_mac {

    my $data = shift;

    if ( !xCAT::Utils->isAIX() ) {
        #####################################
        # Get adapter mac
        #####################################
        $data =~ /^(\S+\s+\S+\s+)(\S+)(\s+.*)$/;
        my $mac  = $2;
        my $save = $mac;

        #################################
        # Delineate MAC with colons 
        #################################
        $mac    =~ s/(\w{2})/$1:/g;
        $mac    =~ s/:$//;
        $data   =~ s/$save/$mac/;
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
    my @fields;

    #####################################
    # Find first valid adapter
    #####################################
    foreach ( @$data ) {
        if ( /^ent\s+/ ) {
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
                last;
            }
        }
    }

    #####################################
    # If no valid adapter, find the first one
    #####################################
    if ( $pingret ne "successful" ) {
        foreach ( @$data ) {
            if ( /^ent\s+/ ) {
            $value = $_;
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
    my $mac    = $fields[2];

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










