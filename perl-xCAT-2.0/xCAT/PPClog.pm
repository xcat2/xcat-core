# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPClog;
use strict;
use Getopt::Long;


##########################################################################
# Parse the command line for options and operands
##########################################################################
sub parse_args {

    my $request   = shift;
    my $args      = $request->{arg};
    my %opt       = ();
    my @reventlog = qw(clear all all_clear);
    my @VERSION   = qw( 2.0 );
    my $cmd;

    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        return( [ $_[0],
            "reventlog -h|--help",
            "reventlog -v|--version",
            "reventlog [-V|--verbose] noderange " . join( '|', @reventlog ),
            "    -h   writes usage information to standard output",
            "    -v   displays command version",
            "    -V   verbose output",
            "    -e   Reads number of entries specified, starting with first"])
    };
    #############################################
    # Process command-line arguments
    #############################################
    if ( !defined( $args )) {
        return(usage( "No command specified" ));
    }
    #############################################
    # Checks case in GetOptions, allows opts
    # to be grouped (e.g. -vx), and terminates
    # at the first unrecognized option.
    #############################################
    @ARGV = @$args;
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure( "bundling" );

    if ( !GetOptions( \%opt, qw(h|help V|Verbose v|version e=s) )) {
        return( usage() );
    }
    ####################################
    # Option -v for version
    ####################################
    if ( exists( $opt{v} )) {
        return( \@VERSION );
    }
    ####################################
    # Option -h for Help
    ####################################
    if ( exists( $opt{h} )) {
        return( usage() );
    }
    ####################################
    # Check for "-" with no option
    ####################################
    if ( grep(/^-$/, @ARGV )) {
        return(usage( "Missing option: -" ));
    }
    ####################################
    # Check for non-zero integer 
    ####################################
    if ( exists( $opt{e} )) {
        if ( $opt{e} !~ /^[1-9]{1}$|^[1-9]{1}[0-9]+$/ ) {
            return(usage( "Invalid entry: $opt{e}" ));
        } 
        $cmd = "entries";
    }
    else { 
        ################################
        # Unsupported commands
        ################################
        ($cmd) = grep(/^$ARGV[0]$/, @reventlog );
        if ( !defined( $cmd )) {
            return(usage( "Invalid command: $ARGV[0]" ));
        }
        shift @ARGV;
    }
    ####################################
    # Check for an extra argument
    ####################################
    if ( defined( $ARGV[0] )) {
        return(usage( "Invalid Argument: $ARGV[0]" ));
    }
    ####################################
    # Set method to invoke 
    ####################################
    $request->{method} = $cmd;
    return( \%opt );
}



1;
