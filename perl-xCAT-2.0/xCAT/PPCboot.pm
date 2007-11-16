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
# Get LPAR MAC addresses
##########################################################################
sub rnetboot {

    my $request = shift;
    my $d       = shift;
    my $exp     = shift; 
    my $hwtype  = @$exp[2];
    my $opt     = $request->{opt};
    my @output;

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
    my $result = xCAT::PPCcli::lpar_netboot( 
                           $exp, 
                           $name,
                           $d,
                           $opt->{S},
                           $opt->{G},
                           $opt->{C},
                           $opt->{m} );

    my $Rc = shift(@$result);
    return( [[$name,@$result[0]]] );
}


1;
