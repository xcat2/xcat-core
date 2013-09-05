# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::fsp;
use strict;
use xCAT::PPC;
use xCAT::DBobjUtils;
use xCAT::Utils;
use xCAT_plugin::hmc;

##########################################################################
# Command handler method from tables
##########################################################################
sub handled_commands {
  return {
      rpower    => 'nodehm:power,mgt',
      #reventlog => 'nodehm:mgt',
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
      rmvm      => 'nodehm:mgt',
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
    if ($arg1->{command}->[0] =~ /rspconfig|rvitals|getmacs|renergy/) { 
        # All the nodes with mgt=blade or mgt=fsp will get here
        # filter out the nodes for fsp.pm
        my (@fspnodes, @nohandle);
        xCAT::Utils->filter_nodes($arg1, undef, \@fspnodes, undef, \@nohandle);
        if (@fspnodes) {
            $arg1->{noderange} = \@fspnodes;
        } else {
            return [];
        }
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
    my $type = xCAT::DBobjUtils->getnodetype($node, "ppc");
    #my ($type) = grep( /^(lpar|osi)$/, @types );
    
    if ( !defined( $type ) or !($type =~ /lpar|blade/) ) {
        #return( "Invalid node type: $ent->{nodetype}" );
        $rsp->{node}->[0]->{error}=["Invalid node type: $type"];
        $rsp->{node}->[0]->{errorcode}=[1];		
        $callback->($rsp); 
        return $rsp;           
    }
    #################################
    # Get attributes
    #################################
    my ($att) = $tabs{ppc}->getNodeAttribs($node, @attribs );
    
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
   
    my %request; 
    xCAT::FSPUtils::getHcpAttribs(\%request, \%tabs); 
    #my $fsp_ip = xCAT::NetworkUtils::getNodeIPaddress( $fsp_name );
    my $fsp_ip = xCAT::FSPUtils::getIPaddress(\%request, $type, $fsp_name );
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
    $rsp->{node}->[0]->{type}->[0]=$type; 
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
    my $ntype = xCAT::DBobjUtils->getnodetype($node, "ppc");
    my @types = split /,/, $ntype;
    my ($type) = grep( /^(lpar|osi)$/, @types );
    
    if ( !defined( $type )) {
        $rsp->{node}->[0]->{error}=["nodetype is invalid"];
        $rsp->{node}->[0]->{errorcode}=[1];  
    }
    
    #################################
    # Get attributes
    #################################
    my ($att) = $tabs{ppc}->getNodeAttribs($node, @attribs );
    
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

    my $hashtype = xCAT::DBobjUtils->getnodetype(\@hcp_list, "ppc");
    foreach my $thishcp ( @hcp_list ) {
        my $thishcp_type = $$hashtype{$thishcp};
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

##########################################################################
# generate hardware tree, called from lstree.
##########################################################################
sub genhwtree
{
    my $nodelist = shift;  # array ref
	my $callback = shift;
	my %hwtree;

    # read ppc table
    my $ppctab = xCAT::Table->new('ppc');
    unless ($ppctab)
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Can not open ppc table.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
    }

    my @entries = $ppctab->getAllNodeAttribs(['node','parent','hcp']);

##################################################################
####################refine the loop after getnodetype updated!!!!!
##################################################################
    my $typehash = xCAT::DBobjUtils->getnodetype(\@$nodelist, "ppc");
    # only handle physical hardware objects here.
    foreach my $node (@$nodelist)
    {
        # will build a hash like sfp->frame->cec
        my $ntype = $$typehash{$node};
        if ($ntype =~ /^frame$/)
        {
            # assume frame always available in DFM.
            # try to see if sfp available.
            my $frment = $ppctab->getNodeAttribs($node, ['sfp']);

            foreach my $ent (@entries)
            {
                # get all cecs by this frame
                if ($ent->{parent} =~ /$node/)
                {
                    if ($frment->{sfp})
                    {
                        unless (grep(/$ent->{node}/, @{$hwtree{$frment->{sfp}}{$node}}))
                        {
                            push @{$hwtree{$frment->{sfp}}{$node}}, $ent->{node};
                        }
                    }
                    else
                    {
                        unless (grep(/$ent->{node}/, @{$hwtree{0}{$node}}))
                        {
                            push @{$hwtree{0}{$node}}, $ent->{node};
                        }
                    }
                }
            }
        }
        elsif ($ntype =~ /^cec$/)
        {
            # get cec's parent
            my $cent = $ppctab->getNodeAttribs($node, ['parent']);
            if ($cent->{parent}) # assume frame always available for DFM
            {
                # try to see if sfp available.
                my $frment = $ppctab->getNodeAttribs($cent->{parent}, ['sfp']);
                if ($frment->{sfp})
                {
                    unless (grep(/$node/, @{$hwtree{$frment->{sfp}}{$cent->{parent}}}))
                    {
                        push @{$hwtree{$frment->{sfp}}{$cent->{parent}}}, $node;
                    }
                }
                else
                {
                    unless (grep(/$node/, @{$hwtree{0}{$cent->{parent}}}))
                    {
                        push @{$hwtree{0}{$cent->{parent}}}, $node;
                    }
                }
            }
        }
        else
        {
            # may add new support later?
            next;
        }    
    }

    return \%hwtree;
}




1;
