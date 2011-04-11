# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::fsp;
use strict;
use xCAT::PPC;
use xCAT::DBobjUtils;
use xCAT_plugin::hmc;

##########################################################################
# Command handler method from tables
##########################################################################
sub handled_commands {
  return {
      rpower    => 'nodehm:power,mgt',
      reventlog => 'nodehm:mgt',
      rspconfig => 'nodehm:mgt',
      mkhwconn  => 'nodehm:mgt',
      rmhwconn  => 'nodehm:mgt',
      lshwconn  => 'nodehm:mgt',
      renergy   => 'nodehm:mgt' ,
      rinv      => 'nodehm:mgt',
      rflash    => 'nodehm:mgt',
      getmacs   => 'nodehm:mgt',
      rnetboot  => 'nodehm:mgt',
      rbootseq  => 'nodehm:mgt',
      rvitals   => 'nodehm:mgt',
      mkvm      => 'nodehm:mgt',
      lsvm      => 'nodehm:mgt',
      chvm      => 'nodehm:mgt',
      rscan     => 'nodehm:mgt',
      getfspcon => 'nodehm:cons',
      getmulcon => 'fsp',

  };
}

##########################################################################
# Pre-process request from xCat daemon
##########################################################################
sub preprocess_request {

    #######################################################
    # IO::Socket::SSL apparently does not work with LWP.pm
    # When used, POST/GETs return immediately with:
    #     500 Can't connect to <nodename>:443 (Timeout)
    #
    # Net::HTTPS, which is used by LWP::Protocol::https::Socket,
    # uses either IO::Socket::SSL or Net::SSL. It chooses
    # by looking to see if $IO::Socket::SSL::VERSION
    # is defined (i.e. the module's already loaded) and
    # uses that if so. If not, it first tries Net::SSL,
    # then IO::Socket::SSL only if that cannot be loaded.
    # So we should invalidate  IO::Socket::SSL here and
    # load Net::SSL.
    #######################################################
    $IO::Socket::SSL::VERSION = undef;
    eval { require Net::SSL };
    if ( $@ ) {
        my $callback = $_[1];
        $callback->( {errorcode=>1,data=>[$@]} );
        return(1);
    }
    my ($arg1, $arg2, $arg3) = @_;
    if ($arg1->{command}->[0] eq "getfspcon") { #Can handle it here and now
        my $node = $arg1->{noderange}->[0];
		my $callback = $arg2;
        getfspcon($node,$callback);
        return [];
    }    
    if ($arg1->{command}->[0] eq "getmulcon") { #Can handle it here and now
        my $node = $arg1->{noderange}->[0];
        my $callback = $arg2;
        getmulcon($node,$callback);
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
sub getfspcon {
 
    my $node = shift;
	my $callback = shift;
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
    
    if ( !defined( $type ) or !($type =~ /lpar/) ) {
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
    
    my $fsp_name   = $att->{hcp};
    my $id = $att->{id};
	
    my $fsp_ip = xCAT::Utils::getNodeIPaddress( $fsp_name );
    if(!defined($fsp_ip)) {
        #return "Failed to get the $fsp_name\'s ip";
        $rsp->{node}->[0]->{error}=["Can't get node address"];
        $rsp->{node}->[0]->{errorcode}=[1];				
        $callback->($rsp); 
        return $rsp;        
    }	
	
	$rsp = {node=>[{name=>[$node]}]};
	$rsp->{node}->[0]->{fsp_ip}->[0]=$fsp_ip;
    $rsp->{node}->[0]->{id}->[0]=$id;	
    $callback->($rsp);	
    return $rsp	
}
	
##########################################################################
# get information for require of multiple sending
##########################################################################
sub getmulcon {
 
    my $node = shift;
    my $callback = shift;
    my @attribs = qw(id parent hcp);
    my %tabs    = ();
    my %hcphash;
    my $rsp;
	my $rsp2;
    
    ##################################
    # Open databases needed
    ##################################
    foreach ( qw(ppc nodetype) ) {
        $tabs{$_} = xCAT::Table->new($_);
    
        if ( !exists( $tabs{$_} )) {
            $rsp->{node}->[0]->{error}=["open table $_ error"];
            $rsp->{node}->[0]->{errorcode}=[1];    
        }
    }
    
    #################################
    # Get node type
    #################################
    my ($ent) = $tabs{nodetype}->getNodeAttribs($node, ["nodetype"] );
    if ( !defined( $ent )) {
        $rsp->{node}->[0]->{error}=["Not define nodetype"];
        $rsp->{node}->[0]->{errorcode}=[1];    
    }
    #################################
    # Check for type
    #################################
    if ( !exists( $ent->{nodetype} )) {
        $rsp->{node}->[0]->{error}=["Can't find nodetype"];
        $rsp->{node}->[0]->{errorcode}=[1];    
    }
    #################################
    # Check for valid "type"
    #################################
    my @types = split /,/, $ent->{nodetype};
    my ($type) = grep( /^(lpar|osi)$/, @types );
    
    if ( !defined( $type )) {
        $rsp->{node}->[0]->{error}=["nodetype is invalid"];
        $rsp->{node}->[0]->{errorcode}=[1];  
    }
    
    #################################
    # Get attributes
    #################################
    my ($att) = $tabs{ppc}->getAttribs({'node'=>$node}, @attribs );
    
    if ( !defined( $att )) {
        $rsp->{node}->[0]->{error}=["Node is not defined in ppc table"];
        $rsp->{node}->[0]->{errorcode}=[1];  
    }
    #################################
    # Verify required attributes
    #################################
    foreach my $at ( @attribs ) {
        if ( !exists( $att->{$at} )) {
            $rsp->{node}->[0]->{error}=["Can't find node attribute in ppc table"];
            $rsp->{node}->[0]->{errorcode}=[1];  
        }
    } 
    my $id       = $att->{id};
    my $parent   = $att->{parent};
    my $hcps     = $att->{hcp};
    my @hcp_list = split(",", $hcps);
    my $cmd = ();
    my $res;
    my $Rc;
    my $c = @hcp_list; 


    foreach my $thishcp ( @hcp_list ) {
        my $thishcp_type = xCAT::FSPUtils->getTypeOfNode($thishcp);
        if(!defined($thishcp_type)) {
            $rsp->{node}->[0]->{error}=["Can't get nodetype of $thishcp"];
            $rsp->{node}->[0]->{errorcode}=[1];   
            next;
        }
        $hcphash{$thishcp}{nodetype} = $thishcp_type;
        if($thishcp_type =~ /^(fsp)$/) { 
            $rsp = getfspcon($node,$callback);
            if ( $rsp->{node}->[0]->{errorcode} ) {
                return;
            }
            $hcphash{$thishcp}{fsp_ip} = $rsp->{node}->[0]->{fsp_ip}->[0];
            $hcphash{$thishcp}{id} = $rsp->{node}->[0]->{id}->[0];			
        } elsif ($thishcp_type =~ /^(hmc)$/) {
            $rsp = xCAT_plugin::hmc::gethmccon($node,$callback,$thishcp);
           if ( $rsp->{node}->[0]->{errorcode} ) {
               return;
           }
            $hcphash{$thishcp}{host} = $thishcp;
            $hcphash{$thishcp}{lparid} = $rsp->{node}->[0]->{lparid}->[0];
            $hcphash{$thishcp}{mtms} = $rsp->{node}->[0]->{mtms}->[0];
            $hcphash{$thishcp}{credencial} = $rsp->{node}->[0]->{cred}->[0];    
        }               
    }
    $rsp2->{node}->[0]->{hcp}->[0] = \%hcphash;
    $callback->($rsp2);  
}

1;
