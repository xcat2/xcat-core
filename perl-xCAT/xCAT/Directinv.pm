# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::Directinv;
use strict;
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::Usage;
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
# Returns FSP/BPA firmware information
##########################################################################
sub firmware {

    my $request = shift;
    my $hash    = shift;
    my @result;
 
    # print "in Directinv \n";
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
                push @result, [$name,@$values[0],$Rc];
                next; 
            }
            
	        #####################################
            # Format fsp-api results
            #####################################
            foreach ( @licmap ) {  
                if ( $data->{$name} =~ /@$_[0]=(\w+)/ ) {
                    push @result, [$name,"@$_[1]: $1",$Rc];
                }
            }
        }
    }
    return( \@result );
}

sub action {
    my $node_name  = shift;
    my $d          = shift;
    my $action     = shift;
#    my $user 	   = "HMC";
#    my $password   = "abc123";
    my $fsp_api    ="/opt/xcat/sbin/fsp-api"; 
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
    #print Dumper(%myhash);
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
		$id = 1;
	} elsif($$d[4] =~ /^fsp$/) { 
		$type = 0;
	} else {
		 $type = 1;
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
	}
     
    my $r = ();
    foreach $r (@res) {
        chomp $r;
        print "r:$r\n";
	    $outhash{ $node_name } = $r;
    }
     
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


