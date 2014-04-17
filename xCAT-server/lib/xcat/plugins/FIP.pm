#!/usr/bin/env perl -w
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#####################################################
#
#  xCAT plugin package to handle commands that manage the xCAT object
#     definitions
#
#####################################################

package xCAT_plugin::FIP;

use lib ("/opt/xcat/lib/perl");
use Data::Dumper;
use Getopt::Long;
use xCAT::MsgUtils;
use strict;
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::ServiceNodeUtils;
# options can be bundled up like -vV
Getopt::Long::Configure("bundling");
$Getopt::Long::ignorecase = 0;


#----------------------------------------------------------------------------

=head3  handled_commands

        Return a list of commands handled by this plugin

=cut

#-----------------------------------------------------------------------------

sub handled_commands
{
    return {
            swapnodes => "FIP"
            };
}


##########################################################################
# Pre-process request from xCat daemon. Send the request to the the service
# nodes of the HCPs.
##########################################################################
sub preprocess_request {

    my $req      = shift;
    #if ($req->{_xcatdest}) { return [$req]; }    #exit if preprocessed
    if ($req->{_xcatpreprocessed}->[0] == 1 ) { return [$req]; }
    my $callback = shift;
    my $subreq = shift;
    my @requests;

    # process the command line
    my $rc = &parse_args($req);
    if ($rc != 0)
    {
	&swapnodes_usage($callback);
	return -1;
    }
    
    #####################################
    # Parse arguments
    #####################################
    #my $opt = parse_args( $req, $callback);
    #if ( ref($opt) eq 'ARRAY' ) 
    #{
    #    send_msg( $req, 1, @$opt );
    #    delete($req->{callback}); # if not, it will cause an error --  "Can't encode a value of type: CODE" in hierairchy.
    #    return(1);
    #}
    #delete($req->{callback}); # remove 'callback' => sub { "DUMMY" } in hierairchy.
    #$req->{opt} = $opt;

    #if ( exists( $req->{opt}->{V} )) {
    #    $req->{verbose} = 1;
    #}
    my $opt = $req->{opt};
    
    my $current_node = $opt->{c};
    my $fip_node = $opt->{f};
   
    my @ppcattribs = ('hcp', 'id', 'pprofile', 'parent', 'supernode', 'comments', 'disable');
    my $ppctab  = xCAT::Table->new( 'ppc', -create=>1, -autocommit=>0);
    unless ($ppctab ) {
	my $rsp->{data}->[0] = "Cannot open ppc table";
	xCAT::MsgUtils->message("E", $rsp, $callback);
	return 1;
    }

    
    my ($current_ppc_ent) = $ppctab->getNodeAttribs($current_node,@ppcattribs);
    my ($fip_ppc_ent) = $ppctab->getNodeAttribs($fip_node,@ppcattribs);
    my @current_attrs;
    my @fip_attrs;
    if( $current_ppc_ent->{'parent'} ne $fip_ppc_ent->{'parent'} ) {
        my $reqcopy = {%$req};
        push @requests, $reqcopy;
        return \@requests;
    } else {
    
        if($current_ppc_ent->{'hcp'} ne $fip_ppc_ent->{'hcp'} ) {
            $callback->({data=>["The two nodes are on the same CEC, but don't have the same hcp"]});
	    $req = {};
	    return;
        }

        # find service nodes for the HCPs
        # build an individual request for each service node
        my $service  = "xcat";
        my @hcps=[$current_ppc_ent->{'hcp'}];
        my $sn = xCAT::ServiceNodeUtils->get_ServiceNode(\@hcps, $service, "MN");
        #print Dumper($sn);
        if( keys(%$sn) == 0 )     {
            my $reqcopy = {%$req};
            push @requests, $reqcopy;
        } 
      
 
        # build each request for each service node
        foreach my $snkey (keys %$sn)
        { 
            #$callback->({data=>["The service node $snkey "]});
            my $reqcopy = {%$req};
            $reqcopy->{'_xcatdest'} = $snkey;
            $reqcopy->{_xcatpreprocessed}->[0] = 1;
            #my $hcps1=$sn->{$snkey};
	    #my @nodes=();
	    #foreach (@$hcps1) { 
	    #    push @nodes, @{$hcp_hash{$_}{nodes}};
	    #}
	    #@nodes = sort @nodes;
	    #my %hash = map{$_=>1} @nodes; #remove the repeated node for multiple hardware control points
	    #@nodes =keys %hash;
	    #$reqcopy->{node} = \@nodes;
            #print "nodes=@nodes\n";
            push @requests, $reqcopy;
        }
    
    }
    #print Dumper(\@requests);
    return \@requests;
}





#----------------------------------------------------------------------------

=head3   process_request

        Check for xCAT command and call the appropriate subroutine.

        Arguments:

        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub process_request
{

    my $request  = shift;
    my $callback = shift;

    my $ret;
    my $msg;

    my $command  = $request->{command}->[0];
    my $args     = $request->{arg};
    my $filedata = $request->{stdin}->[0];

    # figure out which cmd and call the subroutine to process
    if ($command eq "swapnodes")
    {
        ($ret, $msg) = &swapnodes($request, $callback, $args);
    }
     
    my $rsp;
    if ($msg)
    {
        $rsp->{data}->[0] = $msg;
        $callback->($rsp);
    }

    if ($ret > 0) {
	$rsp->{errorcode}->[0] = $ret;
    }
}

#----------------------------------------------------------------------------

=head3   processArgs

        Process the command line. Covers all four commands.

		Also - Process any input files provided on cmd line.

        Arguments:

        Returns:
                0 - OK
                1 - just print usage
		2 - error
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub parse_args
{
    my $request = shift;
    my $args = $request->{arg}; 
    my $gotattrs = 0;
    my %opt      =();
    if ( defined ($args) && @{$args}) { 
        @ARGV = @{$args};
    } else {
            return 2;
    }

    if (scalar(@ARGV) <= 0) {
        return 2;
    }

    # parse the options - include any option from all 4 cmds
    Getopt::Long::Configure("no_pass_through");
    if ( !GetOptions( \%opt, qw(h|help v|version V|verbose c=s f=s o ) )) {
         return 2;
    }

    if ( exists( $opt{v} )) {
         return( \$::VERSION );
    }

    if ( exists( $opt{h}) || $opt{help}) {
         return 2;
    }

    if ( (!exists( $opt{c})) ||(!exists( $opt{f})) ) {
         return 2; 
    }
   
    $request->{opt} = \%opt;    
    
    return 0;
}

#----------------------------------------------------------------------------

=head3  swapnodes

        Support for the xCAT chdef command.

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Comments:

=cut

#-----------------------------------------------------------------------------

sub swapnodes
{
    my $request = shift;
    my $callback = shift;
    my $args    = shift;
	
    my $Rc    = 0;
    my $error = 0;
	
    my $rsp;
    my $action;
    my $values;
    my $vals;
    

    my $opt = $request->{opt};
    #print Dumper($opt);
    
    my $current_node = $opt->{c};
    my $fip_node = $opt->{f};
   
    #check the current_node and fip_node state, they should be in Not Activated state
    
    
    # get the ppc attributes for the two nodes
    #swap
    #update it
    my @ppcattribs = ('hcp', 'id', 'pprofile', 'parent', 'supernode', 'comments', 'disable');
    my $ppctab  = xCAT::Table->new( 'ppc', -create=>1, -autocommit=>0);
    unless ($ppctab ) {
	$rsp->{data}->[0] = "Cannot open ppc table";
	xCAT::MsgUtils->message("E", $rsp, $callback);
	return 1;
    }
   
    my ($current_ppc_ent) = $ppctab->getNodeAttribs( $current_node,@ppcattribs);
    my ($fip_ppc_ent) = $ppctab->getNodeAttribs( $fip_node,@ppcattribs);
    my @current_attrs;
    my @fip_attrs;
    my $cec;
    if( $current_ppc_ent->{'parent'} eq $fip_ppc_ent->{'parent'} ) {

        my %tabs;
	$tabs{ppc}=$ppctab;
	$tabs{vpd}= xCAT::Table->new( 'vpd', -create=>1, -autocommit=>0);
        unless (  !exists( $tabs{vpd} )  ) {
	    $rsp->{data}->[0] = "Cannot open vpd table";
	    xCAT::MsgUtils->message("E", $rsp, $callback);
	    return 1;
        }

	xCAT::FSPUtils::getHcpAttribs($request, \%tabs);
	#the attributes of the current LPAR will be used for fsp_api_action
        push @current_attrs, $current_ppc_ent->{'id'};
        push @current_attrs, "0";
        push @current_attrs, $current_ppc_ent->{'parent'};
        push @current_attrs, $current_ppc_ent->{'hcp'};	
        push @current_attrs, "lpar";	
        push @current_attrs, "0";
        
        #the attributes of the current LPAR will be used for fsp_api_action
	push @fip_attrs, $fip_ppc_ent->{'id'};	
	push @fip_attrs, "0";	
	push @fip_attrs, $fip_ppc_ent->{'parent'};	
	push @fip_attrs, $fip_ppc_ent->{'hcp'};	
	push @fip_attrs, "lpar";	
	push @fip_attrs, "0";	
       
        #For the LPARs on the same CEC, we should swap the nodes' attributes and then assign the IO which are assigned to the current LPAR to the FIP LPAR.	
	$cec = $current_ppc_ent->{'parent'};
        my $type = "lpar";
	$action = "all_lpars_state";
	
        my $values =  xCAT::FSPUtils::fsp_state_action ($request, $cec, \@current_attrs, $action);
        my $Rc = shift(@$values);
	if ( $Rc != 0 ) {
	     $rsp->{data}->[0] = $$values[0];
	     xCAT::MsgUtils->message("E", $rsp, $callback);
	     return -1;
	}
	
	foreach ( @$values ) {
            my ($state,$lparid) = split /,/;
	    if( $lparid eq $current_ppc_ent->{'id'}) {
	         if($state ne "Not Activated") {
		     $rsp->{data}->[0] = "The two LPARs in one same CEC. Please make sure the two LPARs are in Not Activated state before swapping their location information";
	             xCAT::MsgUtils->message("E", $rsp, $callback);
	             return -1;
		 }   
	    }

	    if( $lparid eq $fip_ppc_ent->{'id'}) {
	         if($state ne "Not Activated") {
		     $rsp->{data}->[0] = "The two LPARs in one same CEC. Please make sure the two LPARs are in Not Activated state before swapping their location information";
	             xCAT::MsgUtils->message("E", $rsp, $callback);
	             return -1;
		 }   
	    }
        }
      	 

    }
    
    my %keyhash = ();
    # swap the current ent and the fip ent 
    $keyhash{'node'}    = $current_node; 
    $ppctab->setAttribs( \%keyhash,$fip_ppc_ent );

    if( ! (exists($opt->{o}))) {
        $keyhash{'node'}    = $fip_node;
        $ppctab->setAttribs( \%keyhash,$current_ppc_ent );
    }

    $ppctab->commit;
    $ppctab->close();
    
    #set the variables to be  empty
    #$current_ent = ();
    #$fip_ent     = ();
    %keyhash     =();   
    
    # get the nodepos attributes for the two nodes
    #swap
    #update it
    my @nodeposattribs =('rack','u','chassis','slot','room','comments','disable'); 
    my $nodepostab  = xCAT::Table->new( 'nodepos', -create=>1, -autocommit=>0);
    unless ($nodepostab ) {
	$rsp->{data}->[0] = "Cannot open nodepos table";
	xCAT::MsgUtils->message("E", $rsp, $callback);
	return 1;
    }

    my $current_ent = $nodepostab->getNodeAttribs( $current_node,@nodeposattribs);
    my $fip_ent     = $nodepostab->getNodeAttribs( $fip_node,@nodeposattribs);

    # swap the current ent and the fip ent 
    $keyhash{'node'}    = $current_node; 
    $nodepostab->setAttribs( \%keyhash,$fip_ent );

    if( ! (exists($opt->{o}))) {
        $keyhash{'node'}    = $fip_node;
        $nodepostab->setAttribs( \%keyhash,$current_ent );
    }

    $nodepostab->commit;
    $nodepostab->close();
   
    # get the slots information from fsp, swap them, and then assign them to the others.
    #....
    if( $current_ppc_ent->{'parent'} eq $fip_ppc_ent->{'parent'} ) {
	
	$action = "get_io_slot_info";
	$values =  xCAT::FSPUtils::fsp_api_action ($request,$cec, \@current_attrs, $action);
	#$Rc = shift(@$values);
	$Rc = pop(@$values);
	if ( $Rc != 0 ) {
	     $rsp->{data}->[0] = $$values[1];
	     xCAT::MsgUtils->message("E", $rsp, $callback);
	     return 1;
	}	
       
	$action = "set_io_slot_owner";
	my $tooltype = 0;
        my @data = split(/\n/, $$values[1]);
	foreach my $v (@data) {
	    my ($lpar_id, $busid, $location, $drc_index, $owner_type, $owner, $descr) = split(/,/, $v);
	    if( $lpar_id eq $current_ppc_ent->{'id'} ) {
	        $vals =  xCAT::FSPUtils::fsp_api_action ($request, $fip_node, \@fip_attrs, $action, $tooltype, $drc_index); 
	        $Rc = pop(@$vals);
	        if ( $Rc != 0 ) {
	             $rsp->{data}->[0] = $$vals[1];
		     xCAT::MsgUtils->message("E", $rsp, $callback);
		     return -1;
		}	
	    }  
	}
    } 

    return ;

    
}

#----------------------------------------------------------------------------

=head3  swapnodes_usage 

        Arguments:
        Returns:
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub swapnodes_usage
{
    my $callback = shift;
    my $rsp;
    $rsp->{data}->[0] =
      "\nUsage: swapnodes - swap the location info in the db between 2 nodes. If swapping within a cec, it will assign the IO adapters that were assigned to the defective node to the available node\n";
    $rsp->{data}->[1] = "  swapnodes [-h | --help ] \n";
    $rsp->{data}->[2] = "  swapnodes -c current_node -f fip_node [-o]";
    xCAT::MsgUtils->message("I", $rsp, $callback);
    return 0;
}



1;

