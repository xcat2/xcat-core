# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::FSPvitals;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::FSPpower;
use xCAT::Usage;
use xCAT::PPCvitals;

##########################################################################
# Parse the command line for options and operands
##########################################################################
sub parse_args {
    xCAT::PPCvitals::parse_args(@_);
}

##########################################################################
# invoke the fsp-api command.
##########################################################################
sub action {
    my $node_name  = shift;
    my $attrs          = shift;
    my $action     = shift;
#    my $fsp_api    ="/opt/xcat/sbin/fsp-api"; 
    my $fsp_api    = ($::XCATROOT) ? "$::XCATROOT/sbin/fsp-api" : "/opt/xcat/sbin/fsp-api";
    my $id         = 1;
    my $fsp_name   = ();
    my $fsp_ip     = ();
    my $target_list=();
    my $type = (); # fsp|lpar -- 0. BPA -- 1
    my @result;
    my $Rc = 0 ;
    my %outhash = ();
        
    $id = $$attrs[0];
    $fsp_name = $$attrs[3]; 

    my %objhash = (); 
    $objhash{$fsp_name} = "node";
    my %myhash      = xCAT::DBobjUtils->getobjdefs(\%objhash);
    my $password    = $myhash{$fsp_name}{"passwd.hscroot"};
    #print "fspname:$fsp_name password:$password\n";
#    print Dumper(%myhash);
    if(!$password ) {
	$outhash{$node_name} = "The password.hscroot of $fsp_name in ppcdirect table is empty";
	return ([-1, \%outhash]);
    }
#   my $user = "HMC";
    my $user = "hscroot";
#    my $cred = $request->{$fsp_name}{cred};
#    my $user = @$cred[0];
#    my $password = @$cred[1];
	    
    if($$attrs[4] =~ /^lpar$/) {
        $type = 0;
	if($action =~ /^lcds$/) {$action = "query_lcds"; }
	
    } elsif($$attrs[4] =~ /^fsp$/) { 
	$type = 0;
	if($action =~ /^lcds$/) {$action = "cec_query_lcds";} 
    } else {
	$type = 1;
	if($action =~ /^lcds$/) {$action = "cec_query_lcds"; }
    }

    ############################
    # Get IP address
    ############################
    $fsp_ip = xCAT::Utils::get_hdwr_ip($fsp_name);
    if($fsp_ip == -1) {
        $outhash{$node_name} = "Failed to get the $fsp_name\'s ip";
        return ([-1, \%outhash]);	
    }
	
    print "fsp name: $fsp_name\n";
    print "fsp ip: $fsp_ip\n";

    my $cmd = "$fsp_api -a $action -u $user -p $password -t $type:$fsp_ip:$id:$node_name:";

    print "cmd: $cmd\n"; 
    $SIG{CHLD} = (); 
    my $res = xCAT::Utils->runcmd($cmd, -1);
    $Rc = $::RUNCMD_RC;
    ##################
     
    return( [$Rc, $res] ); 

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
# Returns refcode
##########################################################################
sub enumerate_lcds {

    my $name= shift;
    my $d = shift;
    my $mtms = @$d[2];
    my $Rc = undef;
    my $value = undef;
    my $nodetype = @$d[4];
    my $lpar_id = @$d[0];
    my @refcode = ();
   
    my $values = action ($name, $d, "lcds" );
    $Rc =  shift(@$values);
    my $data = @$values[0];
    $data =~ /\|(\w*)/ ;
       my $code = $1;
       if ( ! $code) {
          push @refcode, [$Rc, "blank"];
       } else {
          push @refcode, [$Rc, $code] ;
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
            # Voltages available in frame
            ################################# 
            if ( @$d[4] ne "bpa" ) {
                push @result, [$name,"$text Only available for BPA",1];
                next;
            }
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
	    push @result, [$name,"$text: Not supported by FSPvitals", 1];
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
                push @result, [$name,"$prefix Not available (No BPA)",1];
                next;
            }
            ################################# 
            # Temperatures not available 
            ################################# 
            if ( @$d[4] !~ /^(fsp|lpar)$/ ) {
                my $text = "$prefix Only available for CEC/LPAR";
                push @result, [$name,$text,1];
                next;
            }
            ################################# 
            # Error - No frame 
            #################################
            if ( $mtms eq "0" ) {
                push @result, [$name,"$prefix Not available (No BPA)",1];
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
    return( xCAT::FSPpower::state(@_,"Current Power Status: ",1));
}

##########################################################################
# Returns system state 
##########################################################################
sub state {
    return( xCAT::FSPpower::state(@_,"System State: "));
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
	    #if($hwtype ne 'hmc'){
	    #    push @result, [$name, "$text Not available(NO HMC)", 1];
	    #    next;
	    #}
            $refcodes = enumerate_lcds($name, $d);
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

