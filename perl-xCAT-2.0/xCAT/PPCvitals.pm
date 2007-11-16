# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCvitals;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::PPCpower;


##########################################################################
# Parse the command line for options and operands
##########################################################################
sub parse_args {

    my $request = shift;
    my $args    = $request->{arg};
    my %opt     = ();
    my @rvitals = qw(temp voltage power state all);
    my @VERSION = qw( 2.0 );

    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        return( [ $_[0],
            "rvitals -h|--help",
            "rvitals -v|--version",
            "rvitals [-V|--verbose] noderange " . join( '|', @rvitals ),
            "    -h   writes usage information to standard output",
            "    -v   displays command version",
            "    -V   verbose output" ]);
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

    if ( !GetOptions( \%opt, qw(h|help V|Verbose v|version) )) {
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
    # Unsupported command
    ####################################
    my ($cmd) = grep(/^$ARGV[0]$/, @rvitals );
    if ( !defined( $cmd )) {
        return(usage( "Invalid command: $ARGV[0]" ));
    }
    ####################################
    # Check for an extra argument
    ####################################
    shift @ARGV;
    if ( defined( $ARGV[0] )) {
        return(usage( "Invalid Argument: $ARGV[0]" ));
    }
    ####################################
    # Set method to invoke
    ####################################
    $request->{method} = $cmd;
    return( \%opt );
}


##########################################################################
# Returns Frame voltages/currents
##########################################################################
sub enumerate_volt {

    my $exp = shift;
    my $d   = shift;

    my $mtms = @$d[2];
    my $volt = xCAT::PPCcli::lshwinfo( $exp, "frame", $mtms );
    my $Rc = shift(@$volt);

    ####################################
    # Return error
    ####################################
    if ( $Rc != SUCCESS ) {
        return( [RC_ERROR, @$volt[0]] );
    }
    ####################################
    # Success - return voltages 
    ####################################
    return( [SUCCESS, @$volt[0]] );
}


##########################################################################
# Returns cage temperatures 
##########################################################################
sub enumerate_temp {

    my $exp     = shift;
    my $frame   = shift;
    my %outhash = ();

    ####################################
    # Get cage information for frame
    ####################################
    my $filter = "type_model_serial_num,temperature";
    my $cages  = xCAT::PPCcli::lshwinfo( $exp, "sys", $frame, $filter ); 
    my $Rc = shift(@$cages);

    ####################################
    # Expect error
    ####################################
    if ( $Rc == EXPECT_ERROR ) {
        return( [$Rc,@$cages[0]] );
    }
    ####################################
    # Save frame by CEC MTMS in cage
    ####################################
    foreach ( @$cages ) {
        my ($mtms,$temp) = split /,/;
        $outhash{$mtms}  = $temp;
    }
    return( [SUCCESS,\%outhash] );
}



##########################################################################
# Returns voltages/currents 
##########################################################################
sub voltage {

    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $hwtype  = @$exp[2];
    my @result  = ();
    my $text    = "Frame Voltages: ";
    my @prefix  = ( 
        "Frame Voltage (Vab): %sV",
        "Frame Voltage (Vbc): %sV",
        "Frame Voltage (Vca): %sV",
        "Frame Current  (Ia): %sA",
        "Frame Current  (Ib): %sA",
        "Frame Current  (Ic): %sA",
    );

    while (my ($mtms,$h) = each(%$hash) ) {
        while (my ($name,$d) = each(%$h) ) {
            ################################# 
            # No frame command on IVM 
            #################################
            if ( $hwtype eq "ivm" ) {
                push @result, [$name,"$text Not available"];
                next;
            }
            ################################# 
            # Voltages available in frame
            ################################# 
            if ( @$d[4] ne "bpa" ) {
                push @result, [$name,"$text Only available for BPA"];
                next;
            }
            my $volt = enumerate_volt( $exp, $d );
            my $Rc = shift(@$volt);

            ################################# 
            # Output error 
            #################################
            if ( $Rc != SUCCESS ) { 
                push @result, [$name,"$text @$volt[0]"];
                next;
            }
            #################################
            # Output value
            #################################
            my @values = split /,/, @$volt[0];
            my $i = 0;

            foreach ( @prefix ) {
                my $value = sprintf($_, $values[$i++]);
                push @result, [$name,$value];
            } 
        }
    }
    return( \@result );
}


##########################################################################
# Returns temperatures for CEC
##########################################################################
sub temp {

    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $hwtype  = @$exp[2];
    my @result  = ();
    my %frame   = ();
    my $prefix  = "System Temperature:";

    ######################################### 
    # Group by frame
    ######################################### 
    while (my ($mtms,$h) = each(%$hash) ) {
        while (my ($name,$d) = each(%$h) ) {
            my $mtms = @$d[5];

            #################################
            # No frame commands for IVM 
            ################################# 
            if ( $hwtype eq "ivm" ) {
                push @result, [$name,"$prefix Not available (No BPA)"];
                next;
            }
            ################################# 
            # Temperatures not available 
            ################################# 
            if ( @$d[4] !~ /^fsp|lpar$/ ) {
                my $text = "$prefix Only available for CEC/LPAR";
                push @result, [$name,$text];
                next;
            }
            ################################# 
            # Error - No frame 
            #################################
            if ( $mtms eq "0" ) {
                push @result, [$name,"$prefix Not available (No BPA)"];
                next;
            }
            #################################
            # Save node 
            ################################# 
            $frame{$mtms}{$name} = $d;
        }
    }

    while (my ($mtms,$h) = each(%frame) ) {
        ################################# 
        # Get temperatures this frame 
        ################################# 
        my $temp = enumerate_temp( $exp, $mtms );
        my $Rc = shift(@$temp);
        my $data = @$temp[0];

        while (my ($name,$d) = each(%$h) ) {
            my $mtms = @$d[2];

            #############################
            # Output error
            #############################
            if ( $Rc != SUCCESS ) {
                push @result, [$name,"$prefix $data"];
                next;
            }
            #############################
            # CEC not in frame 
            #############################
            if ( !exists( $data->{$mtms} )) {
                push @result, [$name,"$prefix CEC '$mtms' not found"];
                next;
            }
            #############################
            # Output value
            #############################
            my $cel   = $data->{$mtms};
            my $fah   = ($cel * 1.8) + 32;
            my $value = "$prefix $cel C ($fah F)";
            push @result, [$name,$value];
        }
    }
    return( \@result );
}


##########################################################################
# Returns system power status (on or off) 
##########################################################################
sub power {
    return( xCAT::PPCpower::state(@_,"Current Power Status: ",1));
}

##########################################################################
# Returns system state 
##########################################################################
sub state {
    return( xCAT::PPCpower::state(@_,"System State: "));
}
 

##########################################################################
# Returns all vitals
##########################################################################
sub all {

    my @values = ( 
        @{temp(@_)}, 
        @{voltage(@_)}, 
        @{state(@_)},
        @{power(@_)} 
    ); 
    return( \@values );
}


1;
