# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::FSPinv;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::Usage;
use xCAT::PPCinv;
use Data::Dumper;

##########################################
# Maps fsp-api attributes to text
##########################################
my @licmap = (
    ["ecnumber",               "Release Level  "],
    ["activated_level",        "Active Level   "],
    ["installed_level",        "Installed Level"],
    ["accepted_level",         "Accepted Level "],
    ["curr_ecnumber_a",        "Release Level A"],
    ["curr_level_a",           "Level A        "],
    ["curr_ecnumber_b",        "Release Level B"],
    ["curr_level_b",           "Level B        "],
    ["curr_ecnumber_primary",  "Release Level Primary"],
    ["curr_level_primary",     "Level Primary  "],
    ["curr_ecnumber_secondary","Release Level Secondary"],
    ["curr_level_secondary",   "Level Secondary"]
);

##########################################################################
# Parse the command line for options and operands 
##########################################################################
sub parse_args {
    xCAT::PPCinv::parse_args(@_);
}




##########################################################################
# Returns FSP/BPA firmware information
##########################################################################
sub firmware {

    my $request = shift;
    my $hash    = shift;
    my @result;
 
    # print "in FSPinv \n";
    #print Dumper($request);
    #print Dumper($hash);

    ####################################
    # FSPinv with firm command is grouped by hardware control point
    # In FSPinv, the hcp is the related fsp.  
    ####################################
    
    # Example of $hash.    
    #VAR1 = {
    #	          '9110-51A*1075ECF' => {
    #                                   'Server-9110-51A-SN1075ECF' => [
    #    	                                                          0,
    #		                                                          0,
    #                           									  '9110-51A*1075ECF',
    #							                            		  'fsp1_name',
    #				                            					  'fsp',
    #									                               0
    #									                               ]
    #					                }
    # 	   };

    while (my ($mtms,$h) = each(%$hash) ) {
        while (my ($name,$d) = each(%$h) ) {

            #####################################
            # Command only supported on FSP/BPA/LPARs 
            #####################################
            if ( @$d[4] !~ /^(fsp|bpa|lpar)$/ ) {
                push @result, 
                    [$name,"Information only available for CEC/BPA/LPAR",RC_ERROR];
                next; 
            }
	       #################
	       #For support on  Lpars, the flag need to be changed.
	       ##########
	       if(@$d[4] eq "lpar")	{
		        @$d[4] = "fsp";
	       }
           my $values = action( $name, $d, "list_firmware_level");
           my $Rc = shift(@$values);
   	       my $data = @$values[0];
           #print "values";
           #print Dumper($values); 
            #####################################
            # Return error
            #####################################
            if ( $Rc != SUCCESS ) {
                push @result, [$name,$data->{$name},$Rc];
                next; 
            }
            
	        #####################################
            # Format fsp-api results
            #####################################
            my $val;
            foreach $val ( @licmap ) {  
                if ( $data->{$name} =~ /@$val[0]=(\w+)/ ) {
                    push @result, [$name,"@$val[1]: $1",$Rc];
                }
            }
        }
    }
    return( \@result );
}

##########################################################################
# invoke the fsp-api command
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
    #print Dumper(%myhash);
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
		$id = 1;
	} elsif($$attrs[4] =~ /^fsp$/) { 
		$type = 0;
	} else {
		 $type = 1;
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
	if($::RUNCMD_RC != 0){
	   	$Rc = -1;	
	} else {
	  	$Rc = SUCCESS;
	}
     
	$outhash{ $node_name } = $res;
     
	return( [$Rc,\%outhash] ); 

}



##########################################################################
# Returns firmware version 
##########################################################################
sub firm {
    return( firmware(@_) );
}

##########################################################################
# Returns serial-number
##########################################################################
sub serial {
}

sub vpd {
}

sub bus {
}

sub config {
}

##########################################################################
# Returns machine-type-model
##########################################################################
sub model {
}

##########################################################################
# Returns all inventory information
##########################################################################
sub all {

    my @result = ( 
        @{vpd(@_)}, 
        @{bus(@_)}, 
        @{config(@_)},
        @{firmware(@_)} 
    );       
    return( \@result );
}


1;


