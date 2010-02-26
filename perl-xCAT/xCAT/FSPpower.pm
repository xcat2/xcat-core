# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::FSPpower;
use strict;
#use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::Usage;
use xCAT::MsgUtils;
use Data::Dumper;
use xCAT::DBobjUtils;
use xCAT::PPCpower;

##########################################################################
# Parse the command line for options and operands
##########################################################################
sub parse_args {
	xCAT::PPCpower::parse_args(@_);	
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
       
       my $res = xCAT::Utils::fsp_api_action ($node_name, $d, "state");
	   print "In boot, state\n";
	   print Dumper($res);
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
	   print "boot:state:$state\n";
       my $op    = ($state =~ /^off$/) ? "on" : "reset";
       $res = xCAT::Utils::fsp_api_action ($node_name, $d, $op);
	
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
    
    print "++++in powercmd++++\n";   
    print Dumper($hash);
    
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
	    } elsif ($$d[4] =~ /^fsp$/) {
	        if($action =~ /^on$/) { $action = "cec_on_autostart"; }
	        if($action =~ /^off$/) { $action = "cec_off"; }
	        if($action =~ /^of$/ ) {
	            push @output, [$node_name, "\'$action\' command not supported for CEC", -1 ];
	            #return (\@output);
		        next;
	         }		    
        } else {
             if($action =~ /^state$/) {
	         $action = "cec_state";
	     } else {
	         push @output, [$node_name, "$node_name\'s type isn't fsp or lpar. Not allow doing this operation", -1 ];
		     #return (\@output);
             next;
	     }
        }		
        my $res = xCAT::Utils::fsp_api_action($node_name, $d, $action );
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

    my @states = (
        "Operating|operating",
        "Running|running",
        "Open Firmware|open-firmware"
    );
    foreach ( @states ) { 
        if ( /$_[0]/ ) {
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
            my $stat = xCAT::Utils::fsp_api_action ($node_name, $d, $action);
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

