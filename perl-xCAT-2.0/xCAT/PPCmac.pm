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
            "getmacs [-V|--verbose] noderange [-S server -G gateway -C client]",
            "    -h   writes usage information to standard output",
            "    -v   displays command version",
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

    if ( !GetOptions( \%opt, qw(h|help V|Verbose v|version C=s G=s S=s) )) { 
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

    foreach my $ip (@_) {
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
# IVM get LPAR MAC addresses
##########################################################################
sub ivm_getmacs {

    my $request = shift;
    my $d       = shift;
    my $exp     = shift; 
    my $name    = shift;

    return( [[RC_ERROR,"Not Implemented"]] );
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
    my @output;

    #########################################
    # Get node data 
    #########################################
    my $type = @$d[4];
    my $name = @$d[6];

    #########################################
    # Invalid target hardware 
    #########################################
    if ( $type ne "lpar" ) {
        return( [[$name,"Node must be LPAR"]] );
    }
    #########################################
    # IVM does not have lpar_netboot command
    # so we have to manually collect MAC 
    # addresses. 
    #########################################
    if ( $hwtype eq "ivm" ) {
        return( ivm_getmacs( $request, $d, $exp, $name ));
    }
    my $result = xCAT::PPCcli::lpar_netboot( 
                           $exp, 
                           $name,
                           $d,
                           $opt->{S},
                           $opt->{G},
                           $opt->{C} );

    my $Rc = shift(@$result);
    
    ##################################
    # Return error
    ##################################
    if ( $Rc != SUCCESS ) {
        return( [[$name,@$result]] );
    }
    ##################################
    # Success - verbose output 
    ##################################
    my $data = join( '',@$result );

    if ( exists($request->{verbose}) ) {
        return( [[$name,$data]] );
    }
    ##################################
    # lpar_netboot returns:
    #
    # Connecting to lpar4\r\n
    # Connected\r\n
    # Checking for power off.\r\n
    # Power off complete.\r\n
    # Power on lpar4 to Open Firmware.\r\n
    # Power on complete.\r\n
    # Getting adapter location codes.\r\n
    # Type\t Location Code\t MAC Address\t Full Path Name\t
    # Ping Result\t Device Type\r\nent U9117.MMA.10F6F3D-V5-C3-T1
    # 1e0e122a930d /vdevice/l-lan@30000003  virtual\r\n
    #####################################
    $data =~ /Device Type(.*)/;
    my $values;
       
    foreach ( split /\r\n/, $1 ) {
        if ( /ent ([^\s]+) ([^\s]+)/ ) {
            $values.= "$1:".uc($2);
        }
    }
    return( [[$name,$values]] );
}


1;
