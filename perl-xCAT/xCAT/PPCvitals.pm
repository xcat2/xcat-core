# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::PPCvitals;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::PPCpower;
use xCAT::Usage;

##########################################################################
# Parse the command line for options and operands
##########################################################################
sub parse_args {

    my $request = shift;
    my $command = $request->{command};
    my $args    = $request->{arg};
    my %opt     = ();
    my @rvitals = qw(temp voltage power lcds state rackenv all);

    #############################################
    # Responds with usage statement
    #############################################
    local *usage = sub {
        my $usage_string = xCAT::Usage->getUsage($command);
        return( [ $_[0], $usage_string] );
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

    if ( !GetOptions( \%opt, qw(V|verbose) )) {
        return( usage() );
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
     
    if($ARGV[0] =~ /^rackenv$/) {
        if($request->{hwtype} =~ /^hmc$/) {
            return(usage( "Command $ARGV[0] is not valid when the nodes' hcp is hmc" ));
        }
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
    if ( $Rc == EXPECT_ERROR || $Rc == RC_ERROR ) {
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
# Returns refcode
##########################################################################
sub enumerate_lcds {

    my $exp = shift;
    my $d = shift;
    my $mtms = @$d[2];
    my $Rc = undef;
    my $value = undef;
    my $nodetype = @$d[4];
    my $lpar_id = @$d[0];
    my @refcode = ();
    
    my $values = xCAT::PPCcli::lsrefcode($exp, $nodetype, $mtms, $lpar_id);
    foreach $value (@$values){
        #Return error
        $Rc = shift @$value;
        if( @$value[0] =~ /refcode=(\w*)/){
            my $code = $1;
            if ( ! $code)
            {
                push @refcode, [$Rc, "blank"];
            }
            else
            {
                push @refcode, [$Rc, $code] ;
            }
	    } 
    }

    return \@refcode;
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
                push @result, [$name,"$text Not available",1];
                next;
            }
            ################################# 
            # Voltages available in frame
            ################################# 
            if ( @$d[4] ne "bpa" ) {
                push @result, [$name,"$text Only available for BPA",0];
                next;
            }
            my $volt = enumerate_volt( $exp, $d );
            my $Rc = shift(@$volt);

            ################################# 
            # Output error 
            #################################
            if ( $Rc != SUCCESS ) { 
                push @result, [$name,"$text @$volt[0]",$Rc];
                next;
            }
            #################################
            # Output value
            #################################
            my @values = split /,/, @$volt[0];
            my $i = 0;

            foreach ( @prefix ) {
                my $value = sprintf($_, $values[$i++]);
                push @result, [$name,$value,$Rc];
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
                push @result, [$name,"$prefix Not available (No BPA)",0];
                next;
            }
            ################################# 
            # Temperatures not available 
            ################################# 
            if ( @$d[4] !~ /^(fsp|cec|lpar)$/ ) {
                my $text = "$prefix Only available for CEC/LPAR";
                push @result, [$name,$text,0];
                next;
            }
            ################################# 
            # Error - No frame 
            #################################
            if ( $mtms eq "0" ) {
                push @result, [$name,"$prefix Not available (No BPA)",0];
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
                push @result, [$name,"$prefix $data",$Rc];
                next;
            }
            #############################
            # CEC not in frame 
            #############################
            if ( !exists( $data->{$mtms} )) {
                push @result, [$name,"$prefix CEC '$mtms' not found",1];
                next;
            }
            #############################
            # Output value
            #############################
            my $cel   = $data->{$mtms};
            my $fah   = ($cel * 1.8) + 32;
            my $value = "$prefix $cel C ($fah F)";
            push @result, [$name,$value,$Rc];
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
###########################################################################
# Returns system LCD status (LCD1, LCD2)
##########################################################################
sub lcds {
    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $hwtype  = @$exp[2];
    my @result  = ();
    my $text = "Current LCD:";
    my $prefix  = "Current LCD%d: %s";
    my $rcode = undef;
    my $refcodes = undef;
    my $Rc = undef;
    my $num = undef;
    my $value = undef;

    while (my ($mtms,$h) = each(%$hash) ) {
        while(my ($name, $d) = each(%$h) ){
            #Support HMC only
            if($hwtype ne 'hmc'){
                push @result, [$name, "$text Not available(NO HMC)", 1];
                next;
            }
            $refcodes = enumerate_lcds($exp, $d);
            $num = 1;
            foreach $rcode (@$refcodes){
                $Rc = shift(@$rcode);
                $value = sprintf($prefix, $num, @$rcode[0]);
                push @result, [$name, $value, $Rc];
                $num = $num + 1;
	    }
        }
    }
    return \@result;
}


##########################################################################
# Returns all vitals
##########################################################################
sub all {

    my @values = ( 
        @{temp(@_)}, 
        @{voltage(@_)}, 
        @{state(@_)},
        @{power(@_)},
        @{lcds(@_)}, 
    ); 

    my @sorted_values = sort {$a->[0] cmp $b->[0]} @values;
    return( \@sorted_values );
}


1;

