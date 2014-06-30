# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::FSPvitals;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::FSPpower;
use xCAT::Usage;
use xCAT::PPCvitals;
use xCAT::FSPUtils;
#use Data::Dumper;


##########################################################################
# Parse the command line for options and operands
##########################################################################
sub parse_args {
    xCAT::PPCvitals::parse_args(@_);
}

##########################################################################
# Returns Frame voltages/currents
##########################################################################
sub enumerate_volt {

    my $exp = shift;
    my $d   = shift;

    my $mtms = @$d[2];
    #my $volt = xCAT::PPCcli::lshwinfo( $exp, "frame", $mtms );
    #my $Rc = shift(@$volt);
    my $value = "Not supported by FSPvitals";
    ####################################
    # Return error
    ####################################
    #if ( $Rc != SUCCESS ) {
    #    return( [RC_ERROR, $value] );
    #}
    ####################################
    # Success - return voltages 
    ####################################
    return( [SUCCESS, $value] );
}




##########################################################################
# Returns cage temperatures 
##########################################################################
sub enumerate_temp {

    my $exp     = shift;
    my $frame   = shift;
    my %outhash = ();
}

##########################################################################
# Returns refcode ; In DFM, it will get both the LCD value and the Current Power status Value
##########################################################################
sub enumerate_lcds {

    my $request= shift;
    my $name= shift;
    my $d = shift;
    my $action = shift; 
    my $only_lcds = shift; 
    my $prefix  = "Current LCD:";
    my $power_status_prefix = "Current Power Status:";
    my $Rc;
    my @refcode;
    my $c = 0;
 
    my $values = xCAT::FSPUtils::fsp_api_action ($request, $name, $d, $action); 
    $Rc =  @$values[2];
    my $data = @$values[1];
    my $t_n = @$values[0];
    if( $Rc != 0 ) {
        my @names = split(/,/, $t_n);
        my @t_data = split(/\n/, $data); 
        foreach my $n (@names) {
            if( $data =~ /$n/ ) {
                chomp $t_data[$c];
                #push @refcode,[$n, "$prefix $t_data[$c]", $Rc];
                if($t_data[$c] =~ /Error/ ) {
                    if( $only_lcds == 0) {
                        push @refcode,[$n, "$power_status_prefix $t_data[$c]", $Rc];
                    }
                    push @refcode,[$n, "$prefix $t_data[$c]", $Rc];
                } else {
                    if( $only_lcds == 0) {

                        # get power status
                        if( $data =~ /1\|/) {
                            push @refcode, [$n, "$power_status_prefix on", $Rc] ;
                        } else {
                            push @refcode, [$n, "$power_status_prefix off", $Rc];
                        }
                    }

                    # get lcd value
                    if( $t_data[$c] =~ /1\|(\w[\w\s]*)/) {
                        push @refcode, [$n, "$prefix $1", $Rc] ;
                    } else {
                        push @refcode, [$n, "$prefix blank", $Rc];
                    }
                } 
                $c++;
            } else {
                push @refcode, [$n, "$prefix $data", $Rc];
                if( $only_lcds == 0) {
                    push @refcode, [$n, "$power_status_prefix $data", $Rc];
                }
            }
        }
    } else {
       my @array =  split(/\n/, $data);
       foreach my $a (@array) {
            if ($a !~ /:\s?[^\s]*\s?[0|1]/) {
                next;
            }
            my @t = split(/:/, $a);
            my $name = $t[0];
            $data = $t[1];
            ## it will not parse the power status if only lcds.
            # $only_lcds = 0, it will get the power status
            # $only_lcds = 0, not get the power status.
            if( $only_lcds == 0) { 
                # get power status
                if( $data =~ /1\|/) {
                    push @refcode, [$name, "$power_status_prefix on", $Rc] ;
                } else {
                    push @refcode, [$name, "$power_status_prefix off", $Rc];
                }
            }

            # get lcd value
            if( $data =~ /1\|(\w[\w\s]*)/) {
               push @refcode, [$name, "$prefix $1", $Rc] ;
            } else {
               push @refcode, [$name, "$prefix blank", $Rc];
            }
        }
    }
    return \@refcode;
}

##########################################################################
# Returns rack environmentals 
##########################################################################
sub enumerate_rackenv {

    my $request= shift;
    my $name= shift;
    my $d = shift;
    #my $mtms = @$d[2];
    my $Rc;
    my $attr;
    my $value;
    my %outhash = ();
    my $action = "get_rack_env"; 
   
    my $values = xCAT::FSPUtils::fsp_api_action ($request, $name, $d, $action);
    $Rc =  @$values[2];
    my $data = @$values[1];
    if ( $Rc != 0 ) {
	 return( [$Rc,@$values[1]] );
    }
   
    my $i = 0;
    my @t = split(/\n/, $data); 
    foreach my $td ( @t ) {
       my ($attr,$value) = split (/:/, $td);
       $outhash{ $attr } = $value;
       $outhash{$i}{ $attr } = $value;
       $i++;
    }
    
    return ( [0,\%outhash] );
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
            # Voltages available in frame
            ################################# 
            #if ( @$d[4] ne "bpa" && @$d[4] ne "frame") {
            #    push @result, [$name,"$text Only available for BPA/Frame",1];
            #    next;
            #}
	    #my $volt = enumerate_volt( $exp, $d );
	    #my $Rc = shift(@$volt);

            ################################# 
            # Output error 
            #################################
            #if ( $Rc != SUCCESS ) { 
	    #    push @result, [$name,"$text @$volt[0]",$Rc];
	    #    next;
	    #}
            #################################
            # Output value
            #################################
	    #my @values = split /,/, @$volt[0];
	    #my $i = 0;

	    #foreach ( @prefix ) {
	    #    my $value = sprintf($_, $values[$i++]);
	    #    push @result, [$name,$value,$Rc];
	    #} 
	    push @result, [$name,"$text: Not supported in Direct FSP Management", 1];
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
            
            push @result, [$name,"System Temperature Not support in Direct FSP Management",-1];

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
            if ( @$d[4] !~ /^(fsp|lpar|cec)$/ ) {
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

    return( \@result );

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
# Returns rack environmentals
##########################################################################
sub rackenv {

    my $request = shift;
    my $hash    = shift;
    my @result  = ();
    my %frame   = ();
    my $prefix  = "Rack Environmentals:";

    ######################################### 
    # Group by frame
    ######################################### 
    while (my ($mtms,$h) = each(%$hash) ) {
        while (my ($name,$d) = each(%$h) ) {
            my $mtms = @$d[5];
            

            ################################# 
            # Temperatures not available 
            ################################# 
            if ( @$d[4] !~ /^(bpa|frame)$/ ) {
                my $text = "$prefix Only available for BPA/Frame";
                push @result, [$name,$text,0];
                next;
            }
            
            my $action = "get_rack_env";
            my $values = xCAT::FSPUtils::fsp_api_action ($request, $name, $d, $action);
            my $Rc =  @$values[2];
            my $data = @$values[1];
            if ( $Rc != 0 ) {
                push @result, [$name,$data, $Rc];
                next;
            }

            my @t = split(/\n/, $data);
            foreach my $td ( @t ) {
                push @result, [$name,$td, $Rc];
                if ( !exists($request->{verbose}) ) {
                    #if( $td =~ /^Rack altitude in meters/ ) {
                    if( $td =~ /^BPA-B total output in watts/ ) {
                        last;
                    }
                } 
            }
        }
    }


    return( \@result );
}






##########################################################################
# Returns system power status (on or off) 
# This subroutine will not be used in DFM
# And the power status will be returned with lcds
##########################################################################
sub power {
    return( xCAT::FSPpower::state(@_,"Current Power Status: ",1));
}

##########################################################################
# Returns system state 
##########################################################################
sub state {
    return( xCAT::FSPpower::state(@_,"System State: "));
}
###########################################################################
# Returns system LCD status and the power status
##########################################################################
sub lcds {
    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $result;
    my $newids;
    my $newnames;
    my $newd;
    my $action;
    my $type;
    my $only_lcds;
    if( $request->{method} =~ /^lcds$/ ) {
        $only_lcds = 1;
    }
    while (my ($mtms,$h) = each(%$hash) ) {
        while(my ($name, $d) = each(%$h) ){
            $newids .="$$d[0],";
            $newnames .="$name,";
            $newd = $d;
            if( defined( $type) && $type ne $$d[4] )  {
                push @$result,  [$name, "$name\'s type is $$d[4]. Please get the lcds for $type and $$d[4] seperately", -1 ];
                return $result;
            } 
            $type = $$d[4];
         }
    }
            
    if( $type eq "lpar" ) {
        $action = "query_lcds";
    } elsif ($type eq "blade") {
        $action = "pblade_query_lcds";
    } else {
        $action = "cec_query_lcds";
    } 
    
    $$newd[0] = $newids;
    $result = enumerate_lcds($request, $newnames, $newd, $action, $only_lcds);
    
    return $result;
}

sub lcds_orig {
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
            $refcodes = enumerate_lcds($request, $name, $d);
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
        @{rackenv(@_)}, 
        @{state(@_)},
        @{lcds(@_)}, 
    ); 

    my @sorted_values = sort {$a->[0] cmp $b->[0]} @values;
    return( \@sorted_values );
}


1;

