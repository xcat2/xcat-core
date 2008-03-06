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
    my @VERSION = qw( 2.0 );

    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        return( [ $_[0],
            "getmacs -h|--help",
            "getmacs -v|--version",
            "getmacs [-V|--verbose] noderange [-c][-S server -G gateway -C client]",
            "    -h   writes usage information to standard output",
            "    -v   displays command version",
            "    -c   colon seperated output",
            "    -C   IP of the partition",
            "    -G   Gateway IP of the partition specified",
            "    -S   Server IP to ping", 
            "    -V   verbose output" ]);
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

    if ( !GetOptions( \%opt, qw(h|help V|Verbose v|version C=s G=s S=s c) )) { 
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

    my $request = shift;
    my $d       = shift;
    my $exp     = shift; 
    my $name    = shift;
    my $opt     = $request->{opt};
    my $id      = @$d[0];
    my $profile = @$d[1];
    my $fsp     = @$d[2];
    my $hcp     = @$d[3];
    my $ssh     = @$exp[0];
    my $userid  = @$exp[4];
    my $pw      = @$exp[5];
    my $cmd;
    my $result;

    #######################################
    # Disconnect Expect session 
    #######################################
    xCAT::PPCcli::disconnect( $exp );

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
    # Create random temporary userid/pw 
    # file between 1000000 and 2000000
    #######################################
    my $random = int( rand(1000001)) + 1000000;
    my $fname = "/tmp/xCAT-$hcp-$random";

    unless ( open( CRED, ">$fname" )) {
        return( [RC_ERROR,"Error creating temporary password file '$fname'"]);
    }
    print CRED "$userid $pw\n";
    close( CRED );

    #######################################
    # Turn on verbose and debugging 
    #######################################
    if ( exists($request->{verbose}) ) {
        $cmd.= " -v -x";
    }
    #######################################
    # Colon seperated output 
    #######################################
    if ( exists($opt->{c}) ) {
        $cmd.= " -c";
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
    $cmd.= " -t ent -f -M -A -n \"$name\" \"$profile\" \"$fsp\" $id $hcp $fname";

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
    # If command did not, remove file  
    #######################################
    if ( -r $fname ) {
        unlink( $fname );
    }
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
    return( [$Rc,$result] );
 
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
    my $node;

    #########################################
    # Get node data 
    #########################################
    my $lparid = @$d[0];
    my $mtms   = @$d[2];
    my $type   = @$d[4];
    my $name   = @$d[6];

    #########################################
    # Invalid target hardware 
    #########################################
    if ( $type ne "lpar" ) {
        return( [[$name,"Node must be LPAR",RC_ERROR]] );
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
        return( [[$name,@$values[0],$Rc]] );
    }
    #########################################
    # Find LPARs by lpar_id
    #########################################
    foreach ( @$values ) {
        if ( /^(.*),$lparid$/ ) {
            $node = $1;
            last;
        }
    }
    #########################################
    # Node not found by lpar_id 
    #########################################
    if ( !defined( $node )) {
        return( [[$name,"Node not found, lparid=$lparid",RC_ERROR]] );
    }
    #########################################
    # IVM does not have lpar_netboot command
    # so we have to manually collect MAC 
    # addresses. 
    #########################################
    if ( $hwtype eq "ivm" ) {
        $result = ivm_getmacs( $request, $d, $exp, $node );
    }
    else {
        $result = xCAT::PPCcli::lpar_netboot( 
                           $exp,
                           $request->{verbose},
                           $node,
                           $d,
                           $opt );
    }
    my $Rc = shift(@$result);
   
    ##################################
    # Form string from array results 
    ##################################
    if ( exists($request->{verbose}) ) {
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
    ##################################
    # Split results into array
    ##################################
    if ( $hwtype eq "ivm" ) {
        my $data = @$result[0];
        @$result = split /\n/, $data;    
    }
    ##################################
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
    my $values;
    foreach ( @$result ) {
        if ( /^#\s?Type/ ) {
            $values.= "\n$_\n";
        } elsif ( /^ent:?/ ) {
            $values.= "$_\n";
        }
    }
    return( [[$name,$values,$Rc]] );
}


1;




