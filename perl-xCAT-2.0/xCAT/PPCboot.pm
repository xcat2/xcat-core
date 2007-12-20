# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCboot;
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
            "rnetboot -h|--help",
            "rnetboot -v|--version",
            "rnetboot [-V|--verbose] noderange -S server -G gateway -C client -m MAC-address",
            "    -h   writes usage information to standard output",
            "    -v   displays command version",
            "    -C   IP of the partition to network boot",
            "    -G   Gateway IP of the partition specified",
            "    -S   IP of the machine to retrieve network boot image", 
            "    -m   MAC address of network adapter to use for network boot", 
            "    -V   verbose output" ]);
    };
    #############################################
    # Process command-line arguments
    #############################################
    if ( !defined( $args )) {
        return( usage() );
    }
    #############################################
    # Checks case in GetOptions, allows opts
    # to be grouped (e.g. -vx), and terminates
    # at the first unrecognized option.
    #############################################
    @ARGV = @$args;
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );

    if ( !GetOptions( \%opt, 
              qw(h|help V|Verbose v|version C=s G=s S=s m=s ))) { 
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
    # Option -m required
    ####################################
    if ( !exists($opt{m}) ) {
        return(usage( "Missing option: -m" ));    
    }
    ####################################
    # Options -C -G -S required 
    ####################################
    foreach ( qw(C G S) ) {
        if ( !exists($opt{$_}) ) {
            return(usage( "Missing option: -$_" ));    
        }
    }
    my $result = validate_ip( $opt{C}, $opt{G}, $opt{S} );
    if ( @$result[0] ) {
        return(usage( @$result[1] ));
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
            return( [1,"Invalid IP address: $ip"] );
        }
        foreach my $octet ( @octets ) {
            if (( $octet < 0 ) or ( $octet > 255 )) {
                return( [1,"Invalid IP address: $ip"] );
            }
        }
    }
    return([0]);
}


##########################################################################
# IVM rnetboot 
##########################################################################
sub ivm_rnetboot {

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
    my $cmd     = "/usr/sbin/lpar_netboot";
    my $result;

    #######################################
    # Disconnect Expect session
    #######################################
    xCAT::PPCcli::disconnect( $exp );

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
    # Network specified
    #######################################
    $cmd.= " -s auto -d auto -S $opt->{S} -G $opt->{G} -C $opt->{C}";
   
    #######################################
    # Add command options
    #######################################
    $cmd.= " -t ent -f \"$name\" \"$profile\" \"$fsp\" $id $hcp $fname";

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
    return( [SUCCESS,$result] );
}


##########################################################################
# Get LPAR MAC addresses
##########################################################################
sub rnetboot {

    my $request = shift;
    my $d       = shift;
    my $exp     = shift; 
    my $hwtype  = @$exp[2];
    my $opt     = $request->{opt};
    my $result;

    #####################################
    # Get node data 
    #####################################
    my $type = @$d[4];
    my $name = @$d[6];

    #####################################
    # Invalid target hardware 
    #####################################
    if ( $type !~ /^lpar$/ ) {
        return( [[$name,"Not supported"]] );
    }
    #########################################
    # IVM does not have lpar_netboot command
    # so we have to manually perform boot. 
    #########################################
    if ( $hwtype eq "ivm" ) {
        $result = ivm_rnetboot( $request, $d, $exp, $name );
    }
    else {
        $result = xCAT::PPCcli::lpar_netboot( 
                           $exp,
                           $request->{verbose}, 
                           $name,
                           $d,
                           $opt );
    }
    my $Rc = shift(@$result);

    ##################################
    # Form string from array results
    ##################################
    if ( exists($request->{verbose}) ) {
        return( [[$name,join( '', @$result )]] );
    }
    ##################################
    # Return error
    ##################################
    if ( $Rc != SUCCESS ) {
        return( [[$name,join( '', @$result )]] );
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
    #  # Connecting to p6vios
    #  # Connected
    #  # Checking for power off.
    #  # Power off complete.
    #  # Power on p6vios to Open Firmware.
    #  # Power on complete.
    #  # Network booting install adapter.
    # 
    #####################################
    my $values;
    foreach ( @$result ) {
        if ( /^[^#]/ ) {
            $values.= "$_\n";
        }
    }
    return( [[$name,$values]] );
}


1;

