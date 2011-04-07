# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::fsp;
use strict;
use xCAT::PPC;
use xCAT::DBobjUtils;

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
        }
    }
    #################################
    # Get node type
    #################################
    my $type = xCAT::DBobjUtils->getnodetype($node);
    #my ($type) = grep( /^(lpar|osi)$/, @types );
    
    if ( !defined( $type ) or !($type =~/^(lpar|osi)$/) ) {
        #return( "Invalid node type: $ent->{nodetype}" );
        $rsp->{node}->[0]->{error}=["Invalid node type: $type"];
        $rsp->{node}->[0]->{errorcode}=[1];		
    }
    #################################
    # Get attributes
    #################################
    my ($att) = $tabs{ppc}->getAttribs({'node'=>$node}, @attribs );
    
    if ( !defined( $att )) {
        #return( sprintf( $errmsg{NODE_UNDEF}, "ppc" ));
        $rsp->{node}->[0]->{error}=["node is not defined in ppc table"];
        $rsp->{node}->[0]->{errorcode}=[1];			
    }
    #################################
    # Verify required attributes
    #################################
    foreach my $at ( @attribs ) {
        if ( !exists( $att->{$at} )) {
            #return( sprintf( $errmsg{NO_ATTR}, $at, "ppc" ));
            $rsp->{node}->[0]->{error}=["Can't find node tarribute $at in ppc table"];
            $rsp->{node}->[0]->{errorcode}=[1];			   
        }
    }
    
    my $fsp_name   = $att->{hcp};
    my $id = $att->{id};
	
    my $fsp_ip = xCAT::Utils::getNodeIPaddress( $fsp_name );
    if(!defined($fsp_ip)) {
        #return "Failed to get the $fsp_name\'s ip";
        $rsp->{node}->[0]->{error}=["Can't get node address"];
        $rsp->{node}->[0]->{errorcode}=[1];				
    }	
	
	$rsp = {node=>[{name=>[$node]}]};
	$rsp->{node}->[0]->{fsp_ip}->[0]=$fsp_ip;
    $rsp->{node}->[0]->{id}->[0]=$id;	
    $callback->($rsp);	
	
}



1;
