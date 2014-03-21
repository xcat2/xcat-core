#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::FSPUtils;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

# if AIX - make sure we include perl 5.8.2 in INC path.
#       Needed to find perl dependencies shipped in deps tarball.
if ($^O =~ /^aix/i) {
	unshift(@INC, qw(/usr/opt/perl5/lib/5.8.2/aix-thread-multi /usr/opt/perl5/lib/5.8.2 /usr/opt/perl5/lib/site_perl/5.8.2/aix-thread-multi /usr/opt/perl5/lib/site_perl/5.8.2));
}

use lib "$::XCATROOT/lib/perl";
require xCAT::Table;
use POSIX qw(ceil);
use File::Path;
use strict;
use Symbol;
require xCAT::InstUtils;
require xCAT::NetworkUtils;
require xCAT::Schema;
require xCAT::Utils;
require xCAT::TableUtils;
#use  Data::Dumper;
require xCAT::NodeRange;
use xCAT::MsgUtils qw(verbose_message);

        
 #-------------------------------------------------------------------------------

=head3   getHcpAttribs 
 Description:
     Build 2 Hashes from ppc/vpd table
     one hash is : CEC/Frame is the Key, FSPs/BPAs are the value. 
     the other is: fsp/bpa is the key, the side is the value.

 Arguments:
     $request: this hash will be usded to store the ppc hash and vpd hash
     $tabs: the hash store the new tables for ppc and bpd.
    Returns: 
    Globals:
        none
    Error:
        none
    Example:    xCAT::FSPUtils::getPPCAttribs($request, \%tabs);

=cut

#-------------------------------------------------------------------------------
       
sub getHcpAttribs 
{
    my $request = shift;
    my $tabs     = shift;
    my %ppchash ;
    my %vpd ;
    
    my @vs = $tabs->{vpd}->getAllNodeAttribs(['node', 'side']);
    for my $entry ( @vs ) {
        my $tmp_node = $entry->{node};
        my $tmp_side = $entry->{side};
	if(defined($tmp_node) && defined($tmp_side)) {
            $vpd{$tmp_node} = $tmp_side ;     	
	}
    }
    
    my @ps = $tabs->{ppc}->getAllNodeAttribs(['node','parent','nodetype','hcp','id']); 
    for my $entry ( @ps ) {
        my $tmp_parent = $entry->{parent};
        my $tmp_node = $entry->{node};
        my $tmp_type = $entry->{nodetype};
        if(defined($tmp_node) && defined($tmp_type) && ($tmp_type =~ /^(fsp|bpa)$/ && $tmp_parent) ) {
            push @{$ppchash{$tmp_parent}{children}}, $tmp_node;
	    #push @{$ppchash{$tmp_parent}}, $tmp_node;
        }
        if (defined($tmp_node) && defined($tmp_type) && ($tmp_type eq "blade") && defined($entry->{hcp})) {
            push @{$ppchash{$tmp_node}{children}}, $entry->{hcp};
        }
        if (defined($tmp_node) && defined($entry->{id}) && defined($tmp_parent) && defined($tmp_type) && ($tmp_type eq "lpar")) {
            $ppchash{$tmp_parent}{mapping}{$tmp_node} = $entry->{id};
        }

	#if(exists($ppchash{$tmp_node})) {
	#     if( defined($tmp_type) ) {
	#         #push @{$ppchash{$tmp_node}{type}}, $tmp_type;
	#     } else {
	#	 my %output;
	#	 my $msg = "no type for $tmp_type in the ppc table.";
	#         $output{errorcode} = 1;
	#         $output{data} = $msg;
	#	 $request->{callback}->( \%output );
	#     }
	#}
     }
     
     $request->{ppc}=\%ppchash ;
     $request->{vpd}=\%vpd ;
     
}
        
 #-------------------------------------------------------------------------------

=head3   getIPaddress 
 Description:    
        Used by DFM related functions. When getting the IPs for CECs' FSPs, or
        getting the IPs for Frames' BPAs. And the IPs order is A-0,A-1,B-0,B-1.
	When getting the IP for one FSP or one BPA, if the $nodetocheck it one IP,
	it will return the IP immediately; if not, it will get the IP of the FSP or BPA.
                         
 Arguments:
    $request: Because getIPaddress() is always used for one node after the process fork. Avoiding to 
              access the DB for each node in the subprocess, we should collect the attributs before
	      process fork, and put the attributes in the $request variable. For the getIpaddress().
              The $request parameter should include the ppc hash which mapping the CEC->FSPs and 
              Frames->BPAs, and vpd hash the fsp->side and the bpa->side.
    $type:    the type of the $nodetocheck
    $nodetocheck:  Node name,  only one node at a time.
    $port:   if the $nodetocheck is a fsp or bpa, it will be usde.
    Returns: ip address(s)
    Globals:
        none
    Error:
        none
    Example:   my $c1 = xCAT::FSPUtils::getIPaddress($request, $type, $nodetocheck);

=cut

#-------------------------------------------------------------------------------
       
sub getIPaddress 
{
#    require xCAT::Table;
    my $request     = shift;
    my $type       = shift;
    my $nodetocheck = shift;
    my $port        = shift;
    if (xCAT::NetworkUtils::isIpaddr($nodetocheck)) {
        return $nodetocheck;
    }
    my $side = "[A|B]";
    if (!defined($port)) {
        $port = "[0|1]";
    }
    
    my $ppc = $request->{ppc};
    my $vpd = $request->{vpd};
    
# only need to parse IP addresses for Frame/CEC/BPA/FSP

    #my $type = xCAT::DBobjUtils->getnodetype($nodetocheck);
    #my $type = $$attrs[4]; 
    if ($type) {
        my @children;
        my %node_side_pairs = ();
        my $children_num = 0;
        my $parent;
        if ($type eq "bpa" or $type eq "fsp") {
         
            push @children, $nodetocheck;
            
	    #my $tmp_s = $vpdtab->getNodeAttribs($nodetocheck, ['side']);
	    my $tmp_s = $vpd->{$nodetocheck};
            if ($tmp_s and $tmp_s =~ /(A|B)-\d/i) {
                $side = $1; # get side for the fsp
		
            } else {
                return -3;
            }
        } elsif ($type eq "frame" or $type eq "cec" or ($type =~ /lpar/i)) {
            #In DFM
	    #1. when the node type is frame, its hcp( $nodetocheck ) is frame, 
	    #and it will get the BPAs IPs for the Frame.
	    #2. when the node type is CEC, its hcp( $nodetocheck ) is CEC, 
	    #and it will get the FSPs IPs for the CEC.
	    #3. when the node type is lpar, its hcp is the CEC.
	    #the $nodetocheck is its' hcp. So set $nodetocheck to $parent variable. 
	    #And then get the FSPs IPs for the CEC. 
            $parent = $nodetocheck;
        } elsif ($type eq "blade") {
            return $ppc->{$nodetocheck}->{children}->[0];
        } else {
            return undef;
        }
        if( @children == 0 ) {	
            if( exists($ppc->{$parent} ) ) {
		#for cec/frame, get the FSPs/BPAs from the hash we built in getHcpAttribs() before. 
	        @children = @{$ppc->{$parent}->{children}}; 
            } else {
	        return undef;
	    }
	}
        foreach my $tmp_n( @children) {  
            my $tmp_s = $vpd->{$tmp_n};
            if ($tmp_s and $tmp_s =~ /^$side-$port$/i) {
                $tmp_s =~ s/a/A/;
                $tmp_s =~ s/b/B/;
                if (xCAT::NetworkUtils::isIpaddr($tmp_n)) {
                    $node_side_pairs{$tmp_s} = $tmp_n;           
                    $children_num++;
                } else {
                    my $tmpip = xCAT::NetworkUtils->getipaddr($tmp_n);
                    if (!$tmpip) {
			#my $hoststab = xCAT::Table->new( 'hosts' );
			#my $tmp = $hoststab->getNodeAttribs($tmp_n, ['ip']);
			#if ($tmp->{ip}) {
			#    $tmpip = $tmp->{ip};
			#}
                    }
                    if ($tmpip) {
                        $node_side_pairs{$tmp_s} = $tmpip;
                        $children_num++;
                    }
                } # end of parse IP address for a fsp/bpa
            } # end of parse a child's side
        } #end of loop for children
        if ($children_num == 0) {
            return undef; #no children or brothers for this node.
        }
        my @keys = qw(A-0 A-1 B-0 B-1);
        my $out_strings = undef;
        foreach my $tmp (@keys) {
            if (!$node_side_pairs{$tmp}) {
                $node_side_pairs{$tmp} = '';
            }
        }

        $out_strings = $node_side_pairs{"A-0"}.','.$node_side_pairs{"A-1"}.','.$node_side_pairs{"B-0"}.','.$node_side_pairs{"B-1"};

        return $out_strings;
    } else {
        return undef;
    }
}
 




#-------------------------------------------------------------------------------

=head3  fsp_api_action
    Description:
        invoke the fsp_api to perform the functions 

    Arguments:
        $node_name: 
        $attrs: an attributes hash 
	$action: the operations on the fsp, bpa or lpar
	$tooltype: 0 for HMC, 1 for HNM
    Returns:
        Return result of the operation
    Globals:
        none
    Error:
        none
    Example:
        my $res = xCAT::FSPUtils::fsp_api_action( $node_name, $d, "add_connection", $tooltype );
    Comments:

=cut

#-------------------------------------------------------------------------------
sub fsp_api_action {
    my $request  = shift;
    my $node_name  = shift;
    my $attrs      = shift;
    my $action     = shift;
    my $tooltype   = shift;
    my $parameter   = shift;
#    my $user 	   = "HMC";
#    my $password   = "abc123";
    my $fsp_api    = ($::XCATROOT) ? "$::XCATROOT/sbin/fsp-api" : "/opt/xcat/sbin/fsp-api"; 
    my $id         = 1;
    my $fsp_name   = ();
    my $fsp_ip     = ();
    my $target_list=();
    my $type = (); # fsp|lpar -- 0. BPA -- 1
    my @result;
    my $Rc = 0 ;
    my %outhash = ();
    my $res;    
    my $user;
    my $password;
    my $fsp_bpa_type;
    
    if( !defined($tooltype) ) {
        $tooltype = 0; 
    }
    $id = $$attrs[0];
    $fsp_name = $$attrs[3]; 
    xCAT::MsgUtils->verbose_message($request, "fsp_api_action START node:$node_name,type:$$attrs[4].");
    if($$attrs[4] =~ /^fsp$/ || $$attrs[4] =~ /^lpar$/ || $$attrs[4] =~ /^cec$/) {
        $type = 0;
	    $fsp_bpa_type="fsp";
    } elsif($$attrs[4] =~ /^bpa$/ || $$attrs[4] =~ /^frame$/) { 
	    $type = 1;
	    $fsp_bpa_type="bpa";
    } elsif($$attrs[4] =~ /^blade$/) { 
        $type = 0;
        $fsp_bpa_type = "blade";
    } else { 
        $res = "$fsp_name\'s type is $$attrs[4]. Not support for $$attrs[4]";
	    return ([$node_name, $res, -1]);
    } 
    if( $action =~ /^add_connection$/) { 
        ############################
        # Get IP address
        ############################
        $fsp_ip = getIPaddress($request, $$attrs[4], $fsp_name, $parameter );
	undef($parameter);
    } else {
        $fsp_ip = getIPaddress($request, $$attrs[4], $fsp_name );
    }
    xCAT::MsgUtils->verbose_message($request, "fsp_api_action getIPaddress:$fsp_ip.");
    if(!defined($fsp_ip)) {
        $res = "Failed to get IP address for $fsp_name or the related FSPs/BPAs.";
        return ([$node_name, $res, -1]);	
    }

    if($fsp_ip eq "-1") {
        $res = "Cannot open vpd table";
        return ([$node_name, $res, -1]);	
	} elsif( $fsp_ip eq "-3") {
        $res = "It doesn't have the  FSPs or BPAs whose side is the value as specified or by default.";
        return ([$node_name, $res, -1]);	
	}

    #print "fsp name: $fsp_name\n";
    #print "fsp ip: $fsp_ip\n";
  
    #In DFM, only the add_connection action need the userid/password to create the connection
    #between hdwr_svr and FSPs or BPAs. 
    if( $action =~ /^add_connection$/) {
        my $tmp_node; 
 	if( $$attrs[4] =~ /^cec$/ || $$attrs[4] =~ /^frame$/ ) {
	     $tmp_node = $node_name;
	} elsif ($$attrs[4] =~ /^blade$/) { 
                $tmp_node = $$attrs[5];
	} else {
	        $tmp_node = $fsp_name; 
	}
	
        my $cred = $request->{$tmp_node}{cred}; 
        ($user, $password) = @$cred ;
	#($user, $password) = xCAT::PPCdb::credentials( $tmp_node, $fsp_bpa_type,'HMC');        
	if ( !$password) {
	     $res = "Cannot get password of userid 'HMC'. Please check table 'passwd' or 'ppcdirect'.";
	     return ([$node_name, $res, -1]);
	}
        # The userid for creating connection only is "HMC".
        $user = 'HMC';
    }

    my $cmd;
    my $install_dir = xCAT::TableUtils->getInstallDir();
    if( $action =~ /^(code_update|get_compatible_version_from_rpm)$/) { 
        $cmd = "$fsp_api -a $action -T $tooltype -t $type:$fsp_ip:$id:$node_name:$parameter -d $install_dir/packages_fw/";
    } elsif($action =~ /^code_updateD$/) {
        $cmd = "$fsp_api -a code_update -D -T $tooltype -t $type:$fsp_ip:$id:$node_name:$parameter -d $install_dir/packages_fw/";
    } elsif($action =~ /^add_connection$/) {
    	$cmd = "$fsp_api -a $action -u $user -p $password -T $tooltype -t $type:$fsp_ip:$id:$node_name:";
    } elsif ($action =~ /^set_frame_number$/) { 
    	$cmd = "$fsp_api -a $action -T $tooltype -f $parameter -t $type:$fsp_ip:$id:$node_name:";
    } else {
        if( defined($parameter) ) {
            if ($action =~ /^set_(frame|cec|lpar)_name$/) {
                $cmd = "$fsp_api -a $action -n $parameter -T $tooltype -t $type:$fsp_ip:$id:$node_name:";
            } elsif( $parameter !=0 && $action =~ /^(on|reset)$/ ) {
                #powerinterval for lpars power on
                $cmd = "$fsp_api -a $action -i $parameter -T $tooltype -t $type:$fsp_ip:$id:$node_name:";
            } elsif ($action =~ /^part_set_lpar_def_state$/) {
                $cmd = "$fsp_api -a $action -T $tooltype -s $parameter -t $type:$fsp_ip:$id:$node_name:";
            } elsif (exists($request->{opt}->{vios})) {
                $cmd = "$fsp_api -a $action -T $tooltype -s 1 -t $type:$fsp_ip:$id:$node_name:$parameter";
            } else {
                $cmd = "$fsp_api -a $action -T $tooltype -t $type:$fsp_ip:$id:$node_name:$parameter";
            }
        } else {
            if (exists($request->{opt}->{vios})) {
                $cmd = "$fsp_api -a $action -T $tooltype -s 1 -t $type:$fsp_ip:$id:$node_name:";
            } else {
                $cmd = "$fsp_api -a $action -T $tooltype -t $type:$fsp_ip:$id:$node_name:";
            }
        }
    }
    xCAT::MsgUtils->verbose_message($request, "fsp_api_action cmd:$cmd.");
    #print "cmd: $cmd\n"; 
    $SIG{CHLD} = 'DEFAULT'; 
    # secure passwords in verbose mode
    my $tmpv = $::VERBOSE;
    if($action =~ /^add_connection$/)
    {
        # password involved
        $::VERBOSE = 0;
    }
    $res = xCAT::Utils->runcmd($cmd, -1);
    #$res = "good"; 
    $Rc = $::RUNCMD_RC;
    $::VERBOSE = $tmpv;
    
    ##################
    # output the prompt
    #################
    #$outhash{ $node_name } = $res;
    if(defined($res)) {
        $res =~ s/$node_name: //g;
    }
    xCAT::MsgUtils->verbose_message($request, "fsp_api_action return:$Rc.");
    return( [$node_name,$res, $Rc] ); 
}

#-------------------------------------------------------------------------------

=head3  fsp_state_action
    Description:
        invoke the fsp_api to perform the functions(all_lpars_state) 

    Arguments:
        $node_name: 
        $attrs: an attributes hash 
	$action: the operations on the fsp, bpa or lpar
	$tooltype: 0 for HMC, 1 for HNM
    Returns:
        Return result of the operation
    Globals:
        none
    Error:
        none
    Example:
        my $res = xCAT::FSPUtils::fsp_state_action( $cec_bpa, $type, $action, $tooltype );
    Comments:

=cut

#-------------------------------------------------------------------------------
sub fsp_state_action {
    my $request  = shift;
    my $node_name  = shift;
    my $attrs  = shift;
    my $action     = shift;
    my $tooltype   = shift;
    my $fsp_api    = ($::XCATROOT) ? "$::XCATROOT/sbin/fsp-api" : "/opt/xcat/sbin/fsp-api"; 
    my $id         = 0;
    my $fsp_name   = ();
    my $fsp_ip     = ();
    my $target_list=();
    my $type = (); # fsp|lpar -- 0. BPA -- 1
    my @result;
    my $Rc = 0 ;
    my %outhash = ();
    my @res;    
    
    if( !defined($tooltype) ) {
        $tooltype = 0; 
    }

    $fsp_name = $node_name; 

     
    xCAT::MsgUtils->verbose_message($request, "fsp_state_action START node:$node_name,type:$$attrs[4].");
    if( $$attrs[4] =~ /^(fsp|lpar|cec|blade)$/) {
        $type = 0;
    } else { 
	$type = 1;
    } 

    ############################
    # Get IP address
    ############################
    $fsp_ip = getIPaddress($request, $$attrs[4], $fsp_name );
    if(!defined($fsp_ip) or ($fsp_ip == -3)) {
        $res[0] = "Failed to get IP address for $fsp_name or the related FSPs/BPAs.";
        return ([-1, $res[0]]);	
    }
	
    xCAT::MsgUtils->verbose_message($request, "fsp_state_action getIPaddress:$fsp_ip.");
    #print "fsp name: $fsp_name\n";
    #print "fsp ip: $fsp_ip\n";
    my $cmd;
    #$cmd = "$fsp_api -a $action -u $user -p $password -T $tooltype -t $type:$fsp_ip:$id:$node_name:";
    $cmd = "$fsp_api -a $action -T $tooltype -t $type:$fsp_ip:$id:$node_name:";
    xCAT::MsgUtils->verbose_message($request, "fsp_state_action cmd:$cmd.");
    #print "cmd: $cmd\n"; 
    $SIG{CHLD} = 'DEFAULT'; 
    @res = xCAT::Utils->runcmd($cmd, -1);
    #$res = "good"; 
    $Rc = $::RUNCMD_RC;
    #$Rc = -1;
    ##################
    # output the prompt
    #################
    #$outhash{ $node_name } = $res;
    if( @res ) {
        $res[0] =~ s/$node_name: //g;
    }
    xCAT::MsgUtils->verbose_message($request, "fsp_state_action return:$Rc.");
    return( [$Rc,@res] ); 
}


#-------------------------------------------------------------------------------

=head3  fsp_api_create_partition
    Description:
        invoke the fsp_api to perform the functions 

    Arguments:
        $node_name: 
        $attrs: an attributes hash 
	$action: the operations on the fsp, bpa or lpar
	$tooltype: 0 for HMC, 1 for HNM
    Returns:
        Return result of the operation
    Globals:
        none
    Error:
        none
    Example:
        my $res = xCAT::FSPUtils::fsp_api_create_partition($request, ... );
    Comments:

=cut

#-------------------------------------------------------------------------------
sub fsp_api_create_partition {
    my $request   = shift;
    my $starting_lpar_id   = shift;
    my $octant_cfg = shift;
    my $node_number        = shift;
    my $attrs      = shift;
    my $action     = shift;
    my $tooltype   = shift;
#    my $user 	   = "HMC";
#    my $password   = "abc123";
    my $fsp_api    = ($::XCATROOT) ? "$::XCATROOT/sbin/fsp-api" : "/opt/xcat/sbin/fsp-api"; 
    my $id         = 0;
    my $fsp_name   = ();
    my $fsp_ip     = ();
    my $target_list=();
    my $type = (); # fsp|lpar -- 0. BPA -- 1
    my @result;
    my $Rc = 0 ;
    my %outhash = ();
    my $res;    
    my $number_of_lpars_per_octant;
    my $octant_num_needed;
    my $starting_octant_id;
    my $octant_conf_value;
    my $octant_cfg_value = $octant_cfg->{octant_cfg_value};
    my $new_pending_interleave_mode = $octant_cfg->{memory_interleave};
    
    if( !defined($tooltype) ) {
        $tooltype = 0; 
    }
   
    #use Data::Dumper; 
    #print Dumper($attrs);
    $fsp_name = $$attrs[3]; 
    $type = 0;

    ############################
    # Get IP address
    ############################
    $fsp_ip = getIPaddress($request, $$attrs[4], $fsp_name );
    if(!defined($fsp_ip) or ($fsp_ip == -3)) {
        $res = "Failed to get IP address for $fsp_name.";
        return ([$fsp_name, $res, -1]);	
    }
	
    #print "fsp name: $fsp_name\n";
    #print "fsp ip: $fsp_ip\n";
    $starting_octant_id = int($starting_lpar_id/4);
    my $lparnum_from_octant = 0;
    my $new_pending_pump_mode = $octant_cfg->{pendingpumpmode};
    my $parameters;
    #my $parameters = "$new_pending_pump_mode:$octant_num_needed";
    my $octant_id = $starting_octant_id ;
    my $i = 0;
    for($i=$starting_octant_id; $i < (keys %$octant_cfg_value) ; $i++) {
	if(! exists($octant_cfg_value->{$i})) {
	    $res = "starting LPAR id is $starting_lpar_id, starting octant id is $starting_octant_id, octant configuration value isn't provided. Wrong plan.";
	    return ([$fsp_name, $res, -1]);

        }
	my $octant_conf_value = $octant_cfg_value->{$i};
        #octant configuration values could be 1,2,3,4,5 ; AS following:
        #  1 - 1 partition with all cpus and memory of the octant
        #  2 - 2 partitions with a 50/50 split of cpus and memory
        #  3 - 3 partitions with a 25/25/50 split of cpus and memory
        #  4 - 4 partitions with a 25/25/25/25 split of cpus and memory
        #  5 - 2 partitions with a 25/75 split of cpus and memory
        if($octant_conf_value  ==  1)  {
	    $number_of_lpars_per_octant  = 1;
        } elsif($octant_conf_value  ==  2 ) {
            $number_of_lpars_per_octant  = 2;
        } elsif($octant_conf_value  ==  3 ) {
            $number_of_lpars_per_octant  = 3;
        } elsif($octant_conf_value  ==  4 ) {
            $number_of_lpars_per_octant  = 4;
        } elsif($octant_conf_value  ==  5 ) {
            $number_of_lpars_per_octant  = 2;
        } else {
            $res = "octant $i, configuration values: $octant_conf_value. Wrong octant configuration values!\n";
	    return ([$fsp_name, $res, -1]);
        }	   

    $lparnum_from_octant += $number_of_lpars_per_octant;
    $octant_num_needed++; 
    $parameters .= ":$octant_id:$octant_conf_value:$new_pending_interleave_mode";
     
        
    }  
    $parameters = "$new_pending_pump_mode:$octant_num_needed".$parameters;
    if($node_number != $lparnum_from_octant ) {
        $res =  "According to the partition split rule and the starting LPAR id, $lparnum_from_octant LPARs will be gotten. But the noderange has $node_number node.  Wrong plan.\n";
        return ([$fsp_name, $res, -1]);  
    }
   
    #my $new_pending_pump_mode = 1;
    #my $parameters = "$new_pending_pump_mode:$octant_num_needed";
    #my $octant_id = $starting_octant_id ;
    #my $new_pending_interleave_mode = 2;
    #my $i = 0;
    #for($i = 0; $i < $octant_num_needed; $i++  ) {
    #    $octant_id += $i;
    #	$parameters = $parameters.":$octant_id:$octant_conf_value:$new_pending_interleave_mode";
    #}

    my $cmd;
    $cmd = "$fsp_api -a $action -T $tooltype -t $type:$fsp_ip:0:$fsp_name:$parameters";
    #fsp-api -a set_octant_cfg -t 0:40.7.5.1:0:M019:1:1:7:4:2
    #print "cmd: $cmd\n"; 
    $SIG{CHLD} = 'DEFAULT'; 
    $res = xCAT::Utils->runcmd($cmd, -1);
    #$res = "good"; 
    $Rc = $::RUNCMD_RC;
    #$Rc = -1;
    ##################
    # output the prompt
    #################
    #$outhash{ $node_name } = $res;
    if( defined($res) ) {
        $res =~ s/$fsp_name: //;
    }
    return( [$fsp_name,$res, $Rc] ); 
}






1;
