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
        use lib "/usr/opt/perl5/lib/5.8.2/aix-thread-multi";
        use lib "/usr/opt/perl5/lib/5.8.2";
        use lib "/usr/opt/perl5/lib/site_perl/5.8.2/aix-thread-multi";
        use lib "/usr/opt/perl5/lib/site_perl/5.8.2";
}

use lib "$::XCATROOT/lib/perl";
require xCAT::Table;
use POSIX qw(ceil);
use File::Path;
use Socket;
use strict;
use Symbol;
use IPC::Open3;
use warnings "all";
require xCAT::InstUtils;
require xCAT::NetworkUtils;
require xCAT::Schema;
require xCAT::Utils;
use  Data::Dumper;
require xCAT::NodeRange;
require DBI;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(genpassword runcmd3);

my $utildata; #data to persist locally


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
        my $res = xCAT::Utils::fsp_api_action( $node_name, $d, "add_connection", $tooltype );
    Comments:

=cut

#-------------------------------------------------------------------------------
sub fsp_api_action {
    my $node_name  = shift;
    my $attrs      = shift;
    my $action     = shift;
    my $tooltype   = shift;
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
    
    if( !defined($tooltype) ) {
        $tooltype = 0; 
    }

    $id = $$attrs[0];
    $fsp_name = $$attrs[3]; 

    my %objhash = (); 
    $objhash{$fsp_name} = "node";
    my %myhash      = xCAT::DBobjUtils->getobjdefs(\%objhash);
#    my $password    = $myhash{$fsp_name}{"passwd.hscroot"};
    my $password    = $myhash{$fsp_name}{"passwd.HMC"};
    #print "fspname:$fsp_name password:$password\n";
    if(!$password ) {
	   $res = "The password.HMC of $fsp_name in ppcdirect table is empty";
	   return ([$node_name, $res, -1]);
    }
    my $user = "HMC";
    #my $user = "hscroot";
#    my $cred = $request->{$fsp_name}{cred};
#    my $user = @$cred[0];
#    my $password = @$cred[1];
     
    if($$attrs[4] =~ /^fsp$/ || $$attrs[4] =~ /^lpar$/) {
        $type = 0;
    } else { 
	$type = 1;
    } 

    ############################
    # Get IP address
    ############################
    #$fsp_ip = xCAT::Utils::get_hdwr_ip($fsp_name);
    #if($fsp_ip == 0) {
    #    $res = "Failed to get the $fsp_name\'s ip";
    #    return ([$node_name, $res, -1]);	
    #}
    $fsp_ip = getNodeIPaddress( $fsp_name );
    if(!defined($fsp_ip)) {
        $res = "Failed to get the $fsp_name\'s ip";
        return ([$node_name, $res, -1]);	
    }
    unless ($fsp_ip =~ /\d+\.\d+\.\d+\.\d+/) {
	    $res = "Not supporting IPv6 here"; #Not supporting IPv6 here IPV6TODO
        return ([$node_name, $res, -1]);	
    }
	
    #print "fsp name: $fsp_name\n";
    #print "fsp ip: $fsp_ip\n";
    
    my $cmd;
    if( $action =~ /^code_update$/) { 
        $cmd = "$fsp_api -a $action -u $user -p $password -T $tooltype -t $type:$fsp_ip:$id:$node_name: -d /install/packages_fw/";
    } else {
        $cmd = "$fsp_api -a $action -u $user -p $password -T $tooltype -t $type:$fsp_ip:$id:$node_name:";
    }

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
    $res =~ s/$node_name: //;
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
        my $res = xCAT::Utils::fsp_state_action( $cec_bpa, $type, $action, $tooltype );
    Comments:

=cut

#-------------------------------------------------------------------------------
sub fsp_state_action {
    my $node_name  = shift;
    my $type_name  = shift;
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
    my @res;    
    
    if( !defined($tooltype) ) {
        $tooltype = 0; 
    }

    $fsp_name = $node_name; 

    #my %objhash = (); 
    #$objhash{$fsp_name} = "node";
    #my %myhash      = xCAT::DBobjUtils->getobjdefs(\%objhash);
    #my $password    = $myhash{$fsp_name}{"passwd.HMC"};
    #if(!$password ) { 
    #   $res = "The password.HMC of $fsp_name in ppcdirect table is empty";
    #	   return ([$node_name, $res, -1]);
    #}
    #my $user = "HMC";
     
    if($type_name =~ /^fsp$/ || $type_name =~ /^lpar$/) {
        $type = 0;
    } else { 
	$type = 1;
    } 

    ############################
    # Get IP address
    ############################
    #$fsp_ip = xCAT::Utils::get_hdwr_ip($fsp_name);
    #if($fsp_ip == 0) {
    #    $res = "Failed to get the $fsp_name\'s ip";
    #    return ([$node_name, $res, -1]);	
    #}
    $fsp_ip = xCAT::Utils::getNodeIPaddress( $fsp_name );
    if(!defined($fsp_ip)) {
        $res[0] = ["Failed to get the $fsp_name\'s ip"];
        return ([-1, @res]);	
    }
	
    #print "fsp name: $fsp_name\n";
    #print "fsp ip: $fsp_ip\n";
    my $cmd;
    #$cmd = "$fsp_api -a $action -u $user -p $password -T $tooltype -t $type:$fsp_ip:$id:$node_name:";
    $cmd = "$fsp_api -a $action -T $tooltype -t $type:$fsp_ip:$id:$node_name:";
    $SIG{CHLD} = 'DEFAULT'; 
    @res = xCAT::Utils->runcmd($cmd, -1);
    #$res = "good"; 
    $Rc = $::RUNCMD_RC;
    #$Rc = -1;
    ##################
    # output the prompt
    #################
    #$outhash{ $node_name } = $res;
    $res[0] =~ s/$node_name: //;
    return( [$Rc,@res] ); 
}



1;
