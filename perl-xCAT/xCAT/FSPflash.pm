# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::FSPflash;
use strict;
use lib "/opt/xcat/lib/perl";
use Getopt::Long;
use xCAT::PPCcli qw(SUCCESS EXPECT_ERROR RC_ERROR NR_ERROR);
use xCAT::Usage;
use xCAT::PPCinv;
use xCAT::DSHCLI;
use xCAT::Table;
use Getopt::Long;
use File::Spec;
use xCAT::PPCrflash;
#use Data::Dumper;
use xCAT::FSPUtils;

my $packages_dir= ();
my $activate	= ();
my $verbose	= 0;
my $release_level;
my $active_level;
my @dirlist;

#######################################
# This flag tracks the operation to be performed.  If set, it means we need
# to commit a previously applied update or else recover from one.
#######################################
my $housekeeping = undef;

#####################################
#For -V|--verbose,put the $msg into @value
###################################
sub dpush {
	my $value = shift;
	my $msg = shift;

	if($verbose == 1) {
		push(@$value,$msg);
	}
}

##########################################################################
# Parse the command line for options and operands 
##########################################################################
sub parse_args {
    xCAT::PPCrflash::parse_args(@_);
}

##########################################################################
# Invokes the callback with the specified message                    
##########################################################################
sub send_msg {

    my $request = shift;
    my $ecode   = shift;
    my %output;

    #################################################
    # Called from child process - send to parent
    #################################################
    if ( exists( $request->{pipe} )) {
        my $out = $request->{pipe};

        $output{errorcode} = $ecode;
        $output{data} = \@_;
        print $out freeze( [\%output] );
        print $out "\nENDOFFREEZE6sK4ci\n";
    }
    #################################################
    # Called from parent - invoke callback directly
    #################################################
    elsif ( exists( $request->{callback} )) {
        my $callback = $request->{callback};

        $output{errorcode} = $ecode;
        $output{data} = \@_;
        $callback->( \%output );
    }
}


#-------------------------------------------------------------------------#
# get_lic_filenames - construct and validate the lup filenames for each   #
# each node                                                               #
#-------------------------------------------------------------------------#
#
sub get_lic_filenames {
	my $mtms = shift;
	my $upgrade_required = 0;	
	my $msg = undef;
	my $filename;

	if(! -d $packages_dir) {
              $msg = "The directory $packages_dir doesn't exist!";
              return ("","","", $msg, -1);
        }
        
	#print "opening directory and reading names\n";
        opendir DIRHANDLE, $packages_dir;
        @dirlist= readdir DIRHANDLE;
        closedir DIRHANDLE;

        @dirlist = File::Spec->no_upwards( @dirlist );

        # Make sure we have some files to process
        #
        if( !scalar( @dirlist ) ) {
        	$msg = "directory $packages_dir is empty";
                return ("","","",$msg, -1);
        }

        $release_level =~/(\w{4})(\d{3})/;
        my $pns = $1;
	my $fff = $2;
		
	#Find the latest version lic file
        @dirlist = grep /\.rpm$/, @dirlist;
        @dirlist = grep /$1/, @dirlist;
        if( !scalar( @dirlist ) ) {
		$msg = "There isn't a package suitable for $mtms";
                return ("","","",$msg, -1);
	}
        if( scalar(@dirlist) > 1) {
         # Need to find the latest version package.
        	@dirlist =reverse sort(@dirlist);
                my $t = "\n";
                foreach $t(@dirlist) {
                       $msg =$msg."$t\t";
                }
         }

         $filename = File::Spec->catfile( $packages_dir, $dirlist[0] );
         $dirlist[0] =~ /(\w{4})(\d{3})_(\w{3})_(\d{3}).rpm$/;
    	##############
    	#If the release levels are different, it will be upgrade_required.
    	#############
    	if($fff ne $2) {
	    	$upgrade_required = 1;
    	} else {

       	 if(($pns eq $1) && ($4 <= $active_level)) {
    		$msg = $msg. "Upgrade $mtms $activate!";
	#	if($activate ne "concurrent") {
	#		$msg = "Option --actviate's value should be disruptive";
	#		return ("", "","", $msg, -1);
	#	}
	  } else {
		$msg = $msg . "Upgrade $mtms disruptively!";
           if($activate ne "disruptive") {
	    		$msg = "Option --activate's value shouldn't be concurrent, and it must be disruptive";
			return ("", "","", $msg, -1);
		}
       	 } 
	}
        #print "filename is $filename\n";
	my $xml_file_name = $filename;
	$xml_file_name =~ s/(.+\.)rpm/\1xml/;
	#print "check_licdd_update: source xml file is $xml_file_name\n";

	if( ( -z $filename)|| ( -z $xml_file_name) ) {
		$msg = "The package $filename or xml $xml_file_name is empty" ;
		return ("", "", "", $msg, -1);
	}
		
	return ($filename, $xml_file_name ,$upgrade_required, $msg, 0);

}



##########################
#Performs Licensed Internal Code (LIC) update support for HMC-attached POWER5 and POWER6 Systems
###########################
sub rflash {

    my $request = shift;
    my $hash    = shift;
    my $exp     = shift;
    my $subreq  = $request->{subreq};
    my $hwtype  = @$exp[2];
    my @result;
    my $timeout    = $request->{ppctimeout};
    my $housekeeping = $request->{housekeeping};
    $packages_dir = $request->{opt}->{p};
    $activate = $request->{opt}->{activate};	
    print "housekeeping:$housekeeping\n";
    my $mtms;
    my $h;
    my $user;
    my $action;

    my $tmp_file; #the file handle of the stanza
    my $rpm_file;
    my $xml_file;
    my @rpm_files;
    my @xml_files;
    my $upgrade_required;
    my $stanza = undef;
    my $mtms_t;	
    my @value;
    my %infor;
    my $role ; #0x01: BPC A, BPC B; 0x01: Primary or only FSP, 0x02: Backup FSP
 
    #print "in Directflash \n";
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
    #									  'Server-9110-51A-SN1075ECF',
    #									  'fsp',
    #									  0
    #									  ]
    #					 }
    # 	   };
    my $flag = 0;
    my $flag2 = 0;
    while (my ($mtms,$h) = each(%$hash) ) {
	#
	#For one mtms, it just needs to do the operation one time.
	#
        $flag += 1;
	if($flag > 1) {
	    last;	
	}	
	
	$mtms =~ /(\w+)-(\w+)\*(\w+)/;
	my $mtm    = "$1-$2";
	my $serial = $3;
		
	
        while (my ($name,$d) = each(%$h) ) {
       	    $flag2 += 1;
	    if($flag2 > 1) {
	        last;	
 	    }

            if( !defined($housekeeping) && ($$d[4] =~ /^fsp$/ || $$d[4] =~ /^lpar$/ || $$d[4] =~ /^cec$/)) {
                $action  =  "get_compatible_version_from_rpm";
	        my $values = xCAT::FSPUtils::fsp_api_action( $name, $d, $action, 0, $request->{opt}->{d} );
		my $Rc =  @$values[2];
		my $v = @$values[1];
		if ($Rc != 0) {
                    push @value, [$name, $v, -1];
		    return (\@value);
		}
                            
                #if( $v !~ "nocheckversion") {
		my @levels = split(/,/, $v);
	       	
	        my $frame = $$d[5];
                if ( $frame ne $name ) {
                    
                    my @frame_d = (0, 0, 0, $frame, "frame", 0);
	            $action = "list_firmware_level";
	            $values = xCAT::FSPUtils::fsp_api_action( $frame, \@frame_d, $action );	
	            $Rc =  @$values[2];
	            my $frame_firmware_level = @$values[1];
		    if ($Rc != 0) {
                        push @value, [$frame, $frame_firmware_level, -1];
		        return (\@value);
		    }
                
	            my $level_a;
		    my $level_b;
		    if( $frame_firmware_level =~ /curr_level_a=(\d{3}),curr_ecnumber_a=02(\w{5})/) {
		        $level_a = "$2_$1";
		    }
	
                   if( $frame_firmware_level =~ /curr_level_b=(\d{3}),curr_ecnumber_b=02(\w{5})/) {
   		       $level_b = "$2_$1";
		   }
		   
                   #print "frame_firmware_level=$frame_firmware_level,level_a=$level_a,level_b=$level_b\n";
	           foreach my $l (@levels) {
	                #print "rpm requires: $l\n"	;
	                if( (defined($level_a) && (  $l gt $level_a )) ||  (defined($level_b) && (  $l gt $level_b )) ) {
		            my $res = "New Managed System level for $name is not compatible with current Power Subsystem level 02$level_a on $frame.\nPower Subsystem level 02$l or later is required.";
		       	
                            push @value, [$name, $res, -1];
		            return (\@value);
		        }	
		
		   }
                 }
               #} 
	    
            }

	   if(!defined($housekeeping)) {	   
               my $values  = xCAT::FSPUtils::fsp_api_action( $name, $d, "list_firmware_level"); 
               my $Rc = @$values[2];
	       my $level = @$values[1];
	       #####################################
	       # Return error
      	       #####################################
               if ( $Rc != SUCCESS ) {
                   push @value, [$name,$level,$Rc];
                   next;
               }
            
	       if ( $level =~ /ecnumber=(\w+)/ ) {
                   $release_level = $1;
                   &dpush( \@value, [$name,"$mtms :release level:$1"]);
	       }
				
               if ( $level =~ /activated_level=(\w+)/ ) {
                   $active_level = $1;
                   &dpush( \@value, [$name,"$mtms :activated level:$1"]);
	        }	

	   } 
	    
	    
    	  
           if($housekeeping =~ /^commit$/) { $action = "code_commit"}
           if($housekeeping =~ /^recover$/) { $action = "code_reject"}
           if($activate =~ /^disruptive$/) { 
               $action = "code_update";
           }
           if($activate =~ /^concurrent$/) {
               my $res = "\'concurrent\' option not supported in FSPflash.Please use disruptive mode";
               push @value, [$name, $res, -1];
	       next;
          }
	   
	   my $msg;	
	   if(!defined($housekeeping)) {	   
	       my $flag = 0;	
	       ($rpm_file, $xml_file, $upgrade_required,$msg, $flag) = &get_lic_filenames($mtms);
	        if( $flag == -1) {
		    push (@value, [$name,"$mtms: $msg"]);
	            push (@value, [$name,"Failed to upgrade the firmware of $name"]);
		    return (\@value);
	        }
	       dpush ( \@value, [$name, $msg]);
	   }

           my $res = xCAT::FSPUtils::fsp_api_action( $name, $d, $action, 0, $request->{opt}->{d} );
           push(@value,[$name, @$res[1], @$res[2]]);
           return (\@value);
	         
        }
    }
    push(@value, @result);
    return (\@value);	


}

1;


