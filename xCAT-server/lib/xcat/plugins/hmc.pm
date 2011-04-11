# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::hmc;
use strict;
use xCAT::PPC;
use xCAT::DBobjUtils;

##########################################################################
# Command handler method from tables
##########################################################################
sub handled_commands {
  return {
      rpower    => 'nodehm:power,mgt',
      rvitals   => 'nodehm:mgt',
      rinv      => 'nodehm:mgt',
      mkvm      => 'nodehm:mgt',
      rmvm      => 'nodehm:mgt',
      lsvm      => 'nodehm:mgt',
      chvm      => 'nodehm:mgt',
      rscan     => 'nodehm:mgt',
      getmacs   => 'nodehm:getmac,mgt',
      rnetboot  => 'nodehm:mgt',
      rspconfig => 'nodehm:mgt',
      rflash    => 'nodehm:mgt',
      mkhwconn    => 'nodehm:mgt',
      rmhwconn    => 'nodehm:mgt',
      lshwconn    => 'nodehm:mgt',
      renergy   => 'nodehm:mgt',
      gethmccon => 'nodehm:cons',
  };
}


##########################################################################
# Pre-process request from xCat daemon
##########################################################################
sub preprocess_request {
    my ($arg1, $arg2, $arg3) = @_;
    if ($arg1->{command}->[0] eq "gethmccon") { #Can handle it here and now
        my $node = $arg1->{noderange}->[0];
		my $callback = $arg2;
        gethmccon($node,$callback);
        return [];
    }	
    xCAT::PPC::preprocess_request(__PACKAGE__,@_);
}

##########################################################################
# Process request from xCat daemon
##########################################################################
sub process_request {
    xCAT::PPC::process_request(__PACKAGE__,@_);
}

##########################################################################
# get hcp and id for rcons with fsp
##########################################################################
sub gethmccon {
    
    my $node = shift;
	my $callback = shift;
	my $otherhcp = shift;
	my @attribs = qw(id parent hcp);
    my %tabs    = ();
	my $rsp;
    
    ##################################
    # Open databases needed
    ##################################
    foreach ( qw(ppc vpd nodetype) ) {
        $tabs{$_} = xCAT::Table->new($_);
    
        if ( !exists( $tabs{$_} )) {
            #return( sprintf( $errmsg{DB_UNDEF}, $_ ));
			$rsp->{node}->[0]->{error}=["open table $_ error"];
            $rsp->{node}->[0]->{errorcode}=[1];
            $callback->($rsp);		
            return $rsp;
        }
    }
    
    #################################
    # Get node type
    #################################
    my $type = xCAT::DBobjUtils->getnodetype($node);
    #my ($type) = grep( /^(lpar|osi)$/, @types );
    
    if ( !defined( $type ) or !($type =~/lpar/) ) {
        #return( "Invalid node type: $ent->{nodetype}" );
        $rsp->{node}->[0]->{error}=["Invalid node type: $type"];
        $rsp->{node}->[0]->{errorcode}=[1];		
        $callback->($rsp);	
        return $rsp;
    }
    #################################
    # Get attributes
    #################################
    my ($att) = $tabs{ppc}->getAttribs({'node'=>$node}, @attribs );
    
    if ( !defined( $att )) {
        #return( sprintf( $errmsg{NODE_UNDEF}, "ppc" ));
        $rsp->{node}->[0]->{error}=["node is not defined in ppc table"];
        $rsp->{node}->[0]->{errorcode}=[1];			
        $callback->($rsp);		
        return $rsp;
    }
    #################################
    # Verify required attributes
    #################################
    foreach my $at ( @attribs ) {
        if ( !exists( $att->{$at} )) {
            #return( sprintf( $errmsg{NO_ATTR}, $at, "ppc" ));
            $rsp->{node}->[0]->{error}=["Can't find node tarribute $at in ppc table"];
            $rsp->{node}->[0]->{errorcode}=[1];			   
            $callback->($rsp);			
            return $rsp;
        }
    }
    #################################
    # Find MTMS in vpd database
    #################################
    my @attrs = qw(mtm serial);
    my ($vpd) = $tabs{vpd}->getNodeAttribs($att->{parent}, \@attrs );
    
    if ( !defined( $vpd )) {
        #return( sprintf( $errmsg{NODE_UNDEF}, "vpd" ));
        $rsp->{node}->[0]->{error}=["Can't find node tarribute in vpd table"];
        $rsp->{node}->[0]->{errorcode}=[1];			   
        $callback->($rsp);					
        return $rsp;
    }
    ################################
    # Verify both vpd attributes
    ################################
    foreach ( @attrs ) {
        if ( !exists( $vpd->{$_} )) {
            #return( sprintf( $errmsg{NO_ATTR}, $_, "vpd" ));
            $rsp->{node}->[0]->{error}=["Can't find node tarribute in vpd table"];
            $rsp->{node}->[0]->{errorcode}=[1];			   
            $callback->($rsp);				
            return $rsp;
        }
    }
    ################################
    # Get username and passwd
    ################################
    my $hwtype   = "hmc";
	my $host;
	if ($otherhcp) {
	    $host = $otherhcp;
	} else {
	    $host = $att->{hcp};
	}
	my @cred = xCAT::PPCdb::credentials( $host, $hwtype );
	if ( !defined(@cred) )
	{
        $rsp->{node}->[0]->{error}=["Can't username and passwd for the hmc"];
        $rsp->{node}->[0]->{errorcode}=[1];			   
        $callback->($rsp);		
        return $rsp;
    }
	
	$rsp = {node=>[{name=>[$node]}]};
    $rsp->{node}->[0]->{mtms}->[0]   = "$vpd->{mtm}*$vpd->{serial}";
    $rsp->{node}->[0]->{host}->[0] = $host;
    $rsp->{node}->[0]->{lparid}->[0] = $att->{id};
	$rsp->{node}->[0]->{cred}->[0] =  join ',', @cred;   
    $callback->($rsp);	
	return $rsp;
}


1;
