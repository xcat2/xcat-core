# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::FSPpower;
use strict;
#use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::PPCpower;
use xCAT::FSPUtils;
#use Data::Dumper;
##########################################################################
# Parse the command line for options and operands
##########################################################################
sub parse_args {
	xCAT::PPCpower::parse_args(@_);	
}


##########################################################################
# Builds a hash of CEC/LPAR information returned from FSP
##########################################################################
sub enumerate {

    my $h    = shift;
    my $mtms    = shift;
    my %outhash = ();
    my %cmds    = (); 
    my $type    = ();
    my $cec_bpa = ();
    ######################################
    # Check for CEC/LPAR/BPAs in list
    ######################################
    while (my ($name,$d) = each(%$h) ) {
        $cec_bpa = @$d[3];
        $type = @$d[4];
        #$cmds{$type} = ($type=~/^lpar$/) ? "all_lpars_state" : "cec_state";
        if( $type=~/^lpar$/ ) {
            $cmds{$type} = "all_lpars_state";
        } elsif ($type=~/^(fsp|cec)$/) {
            $cmds{$type} =  "cec_state";
        } else {
            $cmds{$type} = "bpa_state";
        }
    }
    foreach my $type ( keys %cmds ) {
        my $action = $cmds{$type};
        my $values =  xCAT::FSPUtils::fsp_state_action ($cec_bpa, $type, $action);;
        my $Rc = shift(@$values);
        ##################################
        # Return error 
        ##################################
        if ( $Rc != 0 ) {
            return( [$Rc,@$values[0]] );
        }
        ##################################
        # Save LPARs by id 
        ##################################
        foreach ( @$values ) {
            my ($state,$lparid) = split /,/;

            ##############################
            # No lparid for fsp/bpa     
            ##############################
            if ( $type =~ /^(fsp|bpa|cec|frame)$/ ) {
                $lparid = $type;
            }
            $outhash{ $lparid } = $state;
        }
    }
    return( [0,\%outhash] );
}






##########################################################################
# Performs boot operation (Off->On, On->Reset)
##########################################################################
sub powercmd_boot {

    my $request = shift;
    my $hash    = shift;
    my @output  = (); 
    
    
    ######################################
    # Power commands are grouped by CEC 
    # not Hardware Control Point
    ######################################
    
    #Example of $hash
    #    $VAR1 = {
    #	              'Server-9110-51A-SN1075ECF' => [
    #		                                        0,
    #						                        0,
    #						                       '9110-51A*1075ECF',
    #			                    			    'Server-9110-51A-SN1075ECF',
    #		                    				    'fsp',
    #						                        0
    #						                        ]
    #            }
    foreach my $node_name ( keys %$hash)
    {
         
       my $d = $hash->{$node_name};
       if (!($$d[4] =~ /^lpar$/)) { 
           push @output, [$node_name, "\'boot\' command not supported for CEC or BPA", -1 ];
	       #return (\@output);
	       next;
       }
       
       my $res = xCAT::FSPUtils::fsp_api_action ($node_name, $d, "state");
       #print "In boot, state\n";
       #print Dumper($res);
       my $Rc = @$res[2];
       my $data = @$res[1];
       #my $type = @$d[4];
       #my $id   = ($type=~/^(fsp|bpa)$/) ? $type : @$d[0];
        
       ##################################
       # Output error
       ##################################
       if ( $Rc != SUCCESS ) {
           push @output, [$node_name,$data,$Rc];
           next;
       }
       
       ##################################
       # Convert state to on/off
       ##################################
       my $state = power_status($data);
       #print "boot:state:$state\n";
       my $op    = ($state =~ /^off$/) ? "on" : "reset";

       # Attribute powerinterval in site table,
       # to control the rpower speed
       if(defined($request->{'powerinterval'}) && ($request->{'powerinterval'} ne '')) {
           Time::HiRes::sleep($request->{'powerinterval'});
       }


       $res = xCAT::FSPUtils::fsp_api_action ($node_name, $d, $op);
	
       # @output  ...	
       $Rc = @$res[2];
       $data = @$res[1];
       if ( $Rc != SUCCESS ) {
	       push @output, [$node_name,$data,$Rc];
	       next;
	   }
	   push @output,[$node_name, "Success", 0];	  

    }
    return( \@output );
}



##########################################################################
# Performs power control operations (on,off,reboot,etc)
##########################################################################
sub powercmd {

    my $request = shift;
    my $hash    = shift;
    my @result  = ();
    my @output;
    my $action  =  $request->{'op'}; 
    
    #print "++++in powercmd++++\n";   
    #print Dumper($hash);
    
    ####################################
    # Power commands are grouped by cec or lpar 
    # not Hardware Control Point
    ####################################
    
    #Example of $hash.    
    #$VAR1 = {
    #              'lpar01' => [
    #                             '1',
    #     			  'lpar01_normal',
    #				  '9110-51A*1075ECF',
    #				  'Server-9110-51A-SN1075ECF',
    #				  'lpar',
    #				  0
    #				  ]
    # };
																						      
    foreach my $node_name ( keys %$hash)
    {
        my $d = $hash->{$node_name};
	if ($$d[4] =~ /^lpar$/) {
	    if( !($action =~ /^(on|off|of|reset|sms)$/)) {
	        push @output, [$node_name, "\'$action\' command not supported for LPAR", -1 ];
	        return (\@output);
	    }
	} elsif ($$d[4] =~ /^(fsp|cec)$/) {
	    if($action =~ /^on$/) { $action = "cec_on_autostart"; }
	    if($action =~ /^off$/) { $action = "cec_off"; }
	    if($action =~ /^resetsp$/) { $action = "reboot_service_processor"; }
	    if($action =~ /^lowpower$/) { $action = "cec_on_low_power"; }
	    if($action !~ /^cec_on_autostart$/ && $action !~ /^cec_off$/ &&  $action !~ /^cec_on_low_power$/ && $action !~ /^onstandby$/ && $action !~ /^reboot_service_processor$/ ) {
	        push @output, [$node_name, "\'$action\' command not supported for CEC", -1 ];
	        #return (\@output);
	        next;
	    }		    
        } else {
	     if ( $action =~ /^rackstandby$/) {
	         $action = "enter_rack_standby";
	     } elsif ( $action=~/^exit_rackstandby$/) {
	         $action = "exit_rack_standby";
	     } else {
	         push @output, [$node_name, "$node_name\'s type isn't fsp or lpar. Not allow doing this operation", -1 ];
		 #return (\@output);
                 next;
	     }
        }		

        # Attribute powerinterval in site table,
        # to control the rpower speed
        if (($action ne 'enter_rack_standby') && ($action ne 'exit_rack_standby') && ($action ne 'stat') && ($action ne 'status')
           && ($action ne 'state') && ($action ne 'off') && ($action ne 'softoff')) {
            if(defined($request->{'powerinterval'}) && ($request->{'powerinterval'} ne '')) {
                Time::HiRes::sleep($request->{'powerinterval'});
            }
        }

        my $res = xCAT::FSPUtils::fsp_api_action($node_name, $d, $action );
	#    print "In boot, state\n";
	#    print Dumper($res);
    	my $Rc = @$res[2];
    	my $data = @$res[1];
	#my $type = @$d[4];
	#my $id   = ($type=~/^(fsp|bpa)$/) ? $type : @$d[0];
        
	##################################
        # Output error
        ##################################
        if ( $Rc != SUCCESS ) {
            push @output, [$node_name,$data,$Rc];
	    #    next;
        } else {
	    push @output, [$node_name,"Success",$Rc];
	}
    }

    return( \@output );

}


##########################################################################
# Queries CEC/LPAR power status (On or Off) for powercmd_boot
##########################################################################
sub power_status {
    my $value = shift;
    my @states = (
        "Operating|operating",
        "Running|running",
        "standby",
        "Open Firmware|open-firmware"
    );
    foreach my $s ( @states ) { 
        if ($value =~ /$s/ ) {
            return("on");
        }
    } 
    return("off");  
}

##########################################################################
# Queries CEC/LPAR power status 
##########################################################################
sub state {

    my $request = shift;
    my $hash    = shift;
    my $exp     = shift; # NOt use
    my $prefix  = shift;
    my $convert = shift;
    my @output  = ();
			
    
    #print "------in state--------\n"; 
    #print Dumper($request);	
    #print Dumper($hash); 
    ####################################
    # Power commands are grouped by hardware control point
    # In FSPpower, the hcp is the related fsp.  
    ####################################
    
    # Example of $hash.    
    #VAR1 = {
    #	          '9110-51A*1075ECF' => {
    #                                   'Server-9110-51A-SN1075ECF' => [
    #    	                                                          0,
    #		                                                          0,
    #	                      						  '9110-51A*1075ECF',
    #	                     						  'fsp1_name',
    #   							          'fsp',
    #							                  0
    #									]
    #					                 }          
    # 	   };

    my @result  = ();


    if ( !defined( $prefix )) {
        $prefix = "";
    }
    while (my ($mtms,$h) = each(%$hash) ) {
        ######################################
        # Build CEC/LPAR information hash
        ######################################
        my $stat = enumerate( $h, $mtms );
        my $Rc = shift(@$stat);
        my $data = @$stat[0];
        #if($Rc != 0) {
        #    push @result,[$mtms ,$$data[0],$Rc];
        #    return(\@result);
        #}
        while (my ($name,$d) = each(%$h) ) {
            ##################################
            # Look up by lparid 
            ##################################
            my $type = @$d[4];
            my $id   = ($type=~/^(fsp|bpa|cec|frame)$/) ? $type : @$d[0];
            
            ##################################
            # Output error
            ##################################
            if ( $Rc != SUCCESS ) {
                push @result, [$name, "$prefix$data",$Rc];
                next;
            }
            #print Dumper($data); 
            my @k = keys(%$data); 
            if( grep(/all/, @k) == 1 ) {
                 $data->{$id} = $data->{all};
            }
            ##################################
            # Node not found 
            ##################################
            if ( !exists( $data->{$id} )) {
                push @result, [$name, $prefix."Node not found",1];
                next;
            }
            ##################################
            # Output value
            ##################################
            my $value = $data->{$id};

            ##############################
            # Convert state to on/off 
            ##############################
            if ( defined( $convert )) {
                $value = power_status( $value );
            }
            push @result, [$name,"$prefix$value",$Rc];
        }
    }
    return( \@result );
 
   
}





##########################################################################
# Queries CEC/LPAR power status 
##########################################################################
sub state1 {

    my $request = shift;
    my $hash    = shift;
    my $exp     = shift; # NOt use
    my $prefix  = shift;
    my $convert = shift;
    my @output  = ();
    my $action  = "state"; 
			
    
    #print "------in state--------\n"; 
    #print Dumper($request);	
    #print Dumper($hash); 
    ####################################
    # Power commands are grouped by hardware control point
    # In FSPpower, the hcp is the related fsp.  
    ####################################
    
    # Example of $hash.    
    #VAR1 = {
    #	          '9110-51A*1075ECF' => {
    #                                   'Server-9110-51A-SN1075ECF' => [
    #    	                                                          0,
    #		                                                          0,
    #	                      						  '9110-51A*1075ECF',
    #	                     						  'fsp1_name',
    #   							          'fsp',
    #							                  0
    #									]
    #					                 }          
    # 	   };

    
    foreach my $cec_bpa ( keys %$hash)
    {
       

        my $node_hash = $hash->{$cec_bpa};
        for my $node_name ( keys %$node_hash)
        {
            my $d = $node_hash->{$node_name};
	    if($$d[4] =~ /^fsp$/ || $$d[4] =~ /^bpa$/) {
	        $action = "cec_state";		  
            } 
            my $stat = xCAT::FSPUtils::fsp_api_action ($node_name, $d, $action);
            my $Rc = @$stat[2];
    	    my $data = @$stat[1];
            my $type = @$d[4];
	    #my $id   = ($type=~/^(fsp|bpa)$/) ? $type : @$d[0];
	    ##################################
            # Output error
            ##################################
            if ( $Rc != SUCCESS ) {
                push @output, [$node_name,$data,$Rc];
                next;
            }
	    ##############################
            # Convert state to on/off 
            ##############################
            if ( defined( $convert )) {
                $data = power_status( $data );
            }

            #print Dumper($prefix); 
            ##################
	    # state cec_state
	    #################
	    if ( defined($prefix) ) {
                $data = "$prefix $data";
            }

	    
	    push @output,[$node_name, $data, $Rc];
	}

    }
    return( \@output );
   
}


1;

