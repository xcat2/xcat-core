# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::FSPflash;
use strict;
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
use xCAT::FSPinv;
use POSIX "WNOHANG";
use Storable qw(freeze thaw);
use Thread qw(yield);

my $packages_dir= ();
my $activate	= ();
my $verbose	= 0;
$::POWER_DEST_DIR               = "/tmp";
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


sub get_one_mtms {
	my $exp = shift;
        my $bpa = shift;
        my $cmd = "lssyscfg -r cage -e $bpa";
        my $mtms;
        my $msg;

        my $values = xCAT::PPCcli::send_cmd( $exp, $cmd );
        my $Rc = shift(@$values);

        #####################################
        # Return error
        #####################################
        if ( $Rc != SUCCESS ) {
                $msg = "ERROR: Failed to find a CEC managed by $bpa on the HMC";
                return ("", $msg);
        }

        foreach (@$values) {
                if( $_ =~ /cage_num=(\w*),contents=sys,type_model_serial_num=(\w+)-(\w+)\*(\w+),loc_code=(\w+).(\w+).(\w+)/) {
                        $mtms = "$2-$3*$4";
                        last;
                }
        }

	
	#print "the managed system is $mtms!\n";
	return ($mtms, $msg);	
}

sub process_node {
	my $req = shift;
	my $node    = shift;

	my $tab = xCAT::Table->new("vpd");
	my $msg;
	unless ($tab) {
		$msg = "ERROR: Unable to open basic ppc table for configuration";
		return ("", $msg);
	}
       
	print "in process_node1, node $node\n";
    #print Dumper($node);
	my $ent = $tab->getNodeAttribs($node, ['serial', 'mtm']);	
	#print "in process_node\n";
    #print Dumper($ent);

	my $serial = $ent->{'serial'};
	my $mtm	   = $ent->{'mtm'};
	#################################
	#Get node
	#################################
    #print "in get_related_fsp_bpa(), serial = $serial, mtm= $mtm\n";
	my @ents = $tab->getAllAttribsWhere("serial=\"$serial\" and mtm=\"$mtm\"", 'node');
	if (@ents < 0) {
		$msg = "failed to get the FSPs or BPAs whose mtm is $mtm, serial is $serial!";
		return ("", $msg);
	}
	my $e;
	#print Dumper(@ents);
	foreach $e (@ents) {
		if($e->{node} ne $node) {
#			push @{$req->{node}},$e->{node};
			push @{$req->{noderange}},$e->{node};
		}
	}
}

sub get_related_fsp_bpa {
	my $mtm    = shift;
	my $serial = shift;
	my $tab = xCAT::Table->new("vpd");
	my $msg;
	unless ($tab) {
		$msg = "ERROR: Unable to open basic ppc table for configuration";
		return ("", $msg);
	}
	#################################
	#Get node
	#################################
	print "in get_related_fsp_bpa(), serial = $serial, mtm= $mtm\n";
	my @ent = $tab->getAllAttribsWhere("serial=\"$serial\" and mtm=\"$mtm\"", 'node');
	if (@ent < 0) {
		$msg = "failed to get the FSPs or BPAs whose mtm is $mtm, serial is $serial!";
		return ("", $msg);
	}
	return(\@ent);

}

sub get_hcp_id {
	my $node = shift;
	
	my $tab = xCAT::Table->new("ppc");
	my $msg;
	unless ($tab) {
		$msg = "ERROR: Unable to open basic ppc table for configuration";
		return ("", $msg);
	}
	#################################
	#Get node
	#################################
	my @ent = $tab->getNodeAttribs($node, ['hcp', 'id']);	
	if (@ent < 0) {
		$msg = "failed to get the hcp and id of $node!";
		return ("", $msg);
	}
	return($ent[0]->{hcp}, $ent[0]->{id});

}





##########################################################################
# Forks a process to run the action command
##########################################################################
sub fork_cmd {

    my $node_name    = shift;
    my $attrs  	     = shift;
    my $action       = shift;
    my $pipe ;
    
    #######################################
    # Pipe childs output back to parent
    #######################################
    my $parent;
    my $child;
    pipe $parent, $child;
    my $pid = xCAT::Utils->xfork;
    my $res;

    if ( !defined($pid) ) {
        ###################################
        # Fork error
        ###################################
        print "Fork error:!";
        return undef;
    }
    elsif ( $pid == 0 ) {
        ###################################
        # Child process
        ###################################
        close( $parent );
        $pipe = $child;

        $res = xCAT::FSPUtils::fsp_api_action( $node_name, $attrs, $action );
        #print "res\n";
    #print Dumper($res);
	my %output;
	$output{node} = $node_name;
	$output{ret} = @$res[2];
	$output{contents} = @$res[1];
#	print $pipe %output;
#	print $pipe freeze(\%output);
	my @outhash;
	push @outhash,\%output;
	print $pipe freeze([@outhash]);
#	print $pipe "good";	
	print $pipe "\nENDOFFREEZE6sK4ci\n";
	exit(0);
    }
    else {
        ###################################
        # Parent process
        ###################################
        close( $child );
        return( $parent, $pid );
    }
    return(0);
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
            my $values  = xCAT::FSPUtils::fsp_api_action( $name, $d, "list_firmware_level"); 
	    # my $level = xCAT::PPCcli::lslic( $exp, $d, $timeout );
            my $Rc = @$values[2];
	    my $level = @$values[1];
	    #####################################
	    # Return error
      	    #####################################
           if ( $Rc != SUCCESS ) {
                push @value, [$name,$level,$Rc];
                next;
           }
            
	   if (( $level =~ /curr_level_primary/ ) || ( $level =~ /curr_level_a/ )) {
                $role = 0x01;
	   } else {
	  	$role = 0x02; 
	   }
	   	   
	   if ( $level =~ /ecnumber=(\w+)/ ) {
                $release_level = $1;
                &dpush( \@value, [$name,"$mtms :release level:$1"]);
	   }
				
	   if ( $level =~ /activated_level=(\w+)/ ) {
                $active_level = $1;
                &dpush( \@value, [$name,"$mtms :activated level:$1"]);
	   }	
	  
       if($housekeeping =~ /^commit$/) { $action = "code_commit"}
       if($housekeeping =~ /^recover$/) { $action = "code_reject"}
       if($activate =~ /^disruptive$/) { $action = "code_update"}
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
	   my $nodes = get_related_fsp_bpa( $mtm, $serial);
       #print Dumper($nodes); 
	   my $i     = 0;
	   my $flag  = 0;
	   my $c = @$nodes;
	   my $name2 = undef;
	   if ($c == 1 && $role == 0x01 ) {
			
	   }
	   if ($c == 1 && $role == 0x02 ) {
	   
                push(@result,[$name, "$name\'s role is  Backup FSP or BPC side B). Please configure the Primary FSP or BPC side A.", -1]); 
	   }
	   if($c == 2 && $role == 0x01 ) {
	   	if($$nodes[0]->{node} eq $name) {
			$i = 0;
			$name2 = $$nodes[1]->{node};  #Secondary FSP or BPC side B.
		} else {
			$name2 = $name;          #Secondary FSP or BPC side B.
			$name  = $$nodes[1]->{node}; #the Primary FSP or BPC side A.
		}
	   }

	   if($c ==2 && $role == 0x02) {
	  	if($$nodes[0]->{node} eq $name) {
			$name2 = $name; # Secondary FSP or BPC side B.
			$name  = $$nodes[1]->{node};#the Primary FSP or BPC side A.
		} else {
			$name2 = $$nodes[1]->{node};  #Secondary FSP or BPC side B.
		} 
	   }
	   print "name: $name, name2: $name2\n";
	  
	   my $children = 0; 
	   $SIG{CHLD} = sub { while (waitpid(-1, WNOHANG) > 0) {print "child exit\n";$children--;} }; 
	   my $fds = new IO::Select;
 	   my $pipe;
	   if(defined($name2) ) {
		my($hcp, $id) = get_hcp_id($name2);
		my @dt = ($id, @$d[1], $mtms, $hcp, @$d[4], 0);
	   
                ($pipe) = fork_cmd( $name2, \@dt, $action );
	       	
                if ( $pipe ) {
	            $fds->add( $pipe );
		    $children++;
	        }
	        sleep(5); 
           }
	   $pipe = undef;  
	   ($pipe) = fork_cmd( $name, $d, $action );
	       	
           if ( $pipe ) {
	        $fds->add( $pipe );
		$children++;
	   }
	   print "count:\n";
	   print $fds->count;
	   print "children:$children\n";
	   while ( $fds->count > 0 or $children > 0 ) {
	        my @ready_fds = $fds->can_read(1);
		foreach my $rfh (@ready_fds) {
		     my $val = <$rfh>;
		     if( defined($val)) {
		         while($val !~ /ENDOFFREEZE6sK4ci/) {
		             $val .=  <$rfh>;
			 } 
			 my $resp = thaw($val);
			 foreach my $t( @$resp ) {
                #print Dumper($t);
			    push @result, [$t->{node}, $t->{contents}, $t->{ret}];
		         }
			 next;
		    }
		    $fds->remove($rfh);
		    close($rfh);
	        }
       	   }		   
	         
        }
    }
    push(@value, @result);
    return (\@value);	



}

1;


