# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::Directpower;
use strict;
#use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::Usage;
use xCAT::MsgUtils;
use Data::Dumper;
use xCAT::DBobjUtils;

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
    #		                                    0,
    #						    0,
    #						    '9110-51A*1075ECF',
    #						    'Server-9110-51A-SN1075ECF',
    #						    'fsp',
    #						    0
    #						     ]
    #            }
    foreach my $node_name ( keys %$hash)
    {
         
           my $d = $hash->{$node_name};
           my $stat = action ($node_name, $d, "state");
	   print "In boot, state\n";
	   print Dumper($stat);
    	   my $Rc = shift(@$stat);
    	   my $data = @$stat[0];
           my $type = @$d[4];
           my $id   = ($type=~/^(fsp|bpa)$/) ? $type : @$d[0];
        
	   ##################################
           # Output error
           ##################################
           if ( $Rc != SUCCESS ) {
              push @output, [$node_name,$data,$Rc];
              next;
           }
       	  my $t = $data->{$node_name}; 
	  print "boot: $t \n";
          ##################################
          # Convert state to on/off
          ##################################
          my $state = power_status($data->{$node_name});
	  print "boot:state:$state\n";
	  my $op    = ($state =~ /^off$/) ? "on" : "reset";
          $stat = action ($node_name, $d, $op);
	
          # @output  ...	
	  $Rc = shift(@$stat);
	  $data = @$stat[0];
	  if ( $Rc != SUCCESS ) {
		push @output, [$node_name,$data->{$node_name},$Rc];
		next;
	  }
	  push @output,[$node_name, "SUCCESS", 0];	  

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
           my $res = action ($node_name, $d, $request->{'op'});
	   print "In boot, state\n";
	   print Dumper($res);
    	   my $Rc = shift(@$res);
    	   my $data = @$res[0];
       	   my $t = $data->{$node_name}; 
           my $type = @$d[4];
           my $id   = ($type=~/^(fsp|bpa)$/) ? $type : @$d[0];
        
	   ##################################
           # Output error
           ##################################
           if ( $Rc != SUCCESS ) {
              push @output, [$node_name,$t,$Rc];
              next;
           }
             
	   push @output, [$node_name,$t,$Rc];
    }

    return( \@output );

}


##########################################################################
# Queries CEC/LPAR power status (On or Off)
##########################################################################
sub power_status {

    my @states = (
        "Operating|operating",
        "Running|running",
        "Open Firmware|open-firmware"
    );
    foreach ( @states ) { 
        if ( /^$_[0]$/ ) {
            return("on");
        }
    } 
    return("off");  
}

sub state {

    my $request = shift;
    my $hash    = shift;
#    my $prefix  = shift;
#    my $convert = shift;
    my @output  = ();
   
    #print "------in state--------\n"; 
    #print Dumper($request);	
    #print Dumper($hash); 
    ####################################
    # Power commands are grouped by hardware control point
    # In Direct attach support, the hcp is the related fsp.  
    ####################################
    
    # Example of $hash.    
    #VAR1 = {
    #	          '9110-51A*1075ECF' => {
    #                                   'Server-9110-51A-SN1075ECF' => [
    #    	                                                          0,
    #		                                                          0,
    #									  '9110-51A*1075ECF',
    #									  'fsp1_name',
    #									  'fsp',
    #									  0
    #									  ]
    #					 }
    # 	   };

    
    foreach my $cec_bpa ( keys %$hash)
    { 

        my $node_hash = $hash->{$cec_bpa};
        for my $node_name ( keys %$node_hash)
        {
            my $d = $node_hash->{$node_name};
            my $stat = action ($node_name, $d, "state");
            my $Rc = shift(@$stat);
    	    my $data = @$stat[0];
       	    my $t = $data->{$node_name}; 
            my $type = @$d[4];
            my $id   = ($type=~/^(fsp|bpa)$/) ? $type : @$d[0];
        
	    ##################################
            # Output error
            ##################################
            if ( $Rc != SUCCESS ) {
                push @output, [$node_name,$t,$Rc];
                next;
            }
	    push @output,[$node_name, $t, $Rc];
	}

    }
    return( \@output );
   
}


sub action {
    my $node_name  = shift;
    my $d          = shift;
    my $action     = shift;
#    my $user 	   = "HMC";
#    my $password   = "abc123";
    my $fsp_api    ="/home/fsp-api"; 
    my $id         = 1;
    my $fsp_name   = ();
    my $fsp_ip     = ();
    my $target_list=();
    my $type = (); # fsp|lpar -- 0. BPA -- 1
    my @result;
    my $Rc = 0 ;
    my %outhash = ();
        
    $id = $$d[0];
    $fsp_name = $$d[3]; 

    my %objhash = (); 
    $objhash{$fsp_name} = "node";
    my %myhash      = xCAT::DBobjUtils->getobjdefs(\%objhash);
    my $password    = $myhash{$fsp_name}{"passwd.HMC"};
    #print "fspname:$fsp_name password:$password\n";
    print Dumper(%myhash);
    if(!$password ) {
	$outhash{$node_name} = "The password.HMC of $fsp_name in ppcdirect table is empty";
	return ([-1, \%outhash]);
    }
#   my $user = "HMC";
    my $user = "hscroot";
#    my $cred = $request->{$fsp_name}{cred};
#    my $user = @$cred[0];
#    my $password = @$cred[1];
	    
            if($$d[4] =~ /^lpar$/) {
	    	$type = 0;
	    } elsif($$d[4] =~ /^fsp$/) { 
		$type = 0;
		if($action =~ /^state$/) {$action = "cec_state"; }
	   	if($action =~ /^on$/) { $action = "cec_on_autostart"; }
	   	if($action =~ /^off$/) { $action = "cec_off"; }
   	   	if($action =~ /^of$/ ) {
		    $outhash{$node_name} = "\'$action\' command not supported";
		    return ([-1, \%outhash]);
	        }
	    
	    } else {
		 $type = 1;
		 if($action =~ /^state$/) {
		      $action = "cec_state"; 
	         } else {
		      $outhash{$node_name} = "$node_name\'s type isn't fsp or lpar. Not allow doing this operation";
		      return ([-1, \%outhash]);
		 }
	    }

	    ############################
            # Get IP address
            ############################
            my $hosttab  = xCAT::Table->new( 'hosts' );
            if ( $hosttab)
            {
                my $node_ip_hash = $hosttab->getNodeAttribs( $fsp_name,[qw(ip)]);
                $fsp_ip = $node_ip_hash->{ip};
            }
            if (!$fsp_ip)
            {
                my $ip_tmp_res  = xCAT::Utils::toIP($fsp_name);
                ($Rc, $fsp_ip) = @$ip_tmp_res;
                if ( $Rc ) 
                {
		    $outhash{$node_name} = "Failed to get the $fsp_name\'s ip";
		    return ([-1, \%outhash]);
	    	}
            }

	
	   print "fsp name: $fsp_name\n";
	   print "fsp ip: $fsp_ip\n";

           my $cmd = "$fsp_api -a $action -u $user -p $password -t $type:$fsp_ip:$id:$node_name:";

           print "cmd: $cmd\n"; 
           $SIG{CHLD} = (); 
           my @res = xCAT::Utils->runcmd($cmd, -1);
	   if($::RUNCMD_RC != 0){
	   	$Rc = -1;	
	   } else {
	  	$Rc = SUCCESS;
		####################
		# on,off, of, reset, cec_onstandby,cec_off, if $? == 0, it will return sucess
		###################
		if(index($action,"state") == -1 ) {
		    $outhash{$node_name} = "Sucess";
		    return ([$Rc, \%outhash]);
		}
	   }
	   ##################
	   # state cec_state
	   #################
           my $r = ();
           foreach $r (@res) {
              chomp $r;
              print "jhhg:$r\n";
	      $outhash{ $node_name } = $r;
           }
     
	   return( [$Rc,\%outhash] ); 

}


1;

