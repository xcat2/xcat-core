# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::destiny;
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use xCAT::NodeRange;
use Data::Dumper;
use xCAT::Utils;
use xCAT::TableUtils;
use Sys::Syslog;
use xCAT::GlobalDef;
use xCAT::Table;
use xCAT_monitoring::monitorctrl;
use Getopt::Long;
use strict;

my $request;
my $callback;
my $subreq;
my $errored = 0;

#DESTINY SCOPED GLOBALS
my $chaintab;
my $iscsitab;
my $bptab;
my $typetab;
my $restab;
#my $sitetab;
my $hmtab;
my $tftpdir="/tftpboot";


my $nonodestatus=0;
#my $sitetab = xCAT::Table->new('site');
#if ($sitetab) {
    #(my $ref1) = $sitetab->getAttribs({key => 'nodestatus'}, 'value');
    my @entries =  xCAT::TableUtils->get_site_attribute("nodestatus");
    my $site_entry = $entries[0];
    if ( defined($site_entry) ) {
	if ($site_entry =~ /0|n|N/) { $nonodestatus=1; }
    }
#}


sub handled_commands {
  return {
    setdestiny => "destiny",
    getdestiny => "destiny",
    nextdestiny => "destiny"
  }
}
sub process_request {
  $request = shift;
  $callback = shift;
  $subreq = shift;
  if (not $::XCATSITEVALS{disablecredfilecheck} and xCAT::Utils->isMN()) {
      my $result= xCAT::TableUtils->checkCredFiles($callback);
  }
  if ($request->{command}->[0] eq 'getdestiny') {
    getdestiny(0);
  }
  if ($request->{command}->[0] eq 'nextdestiny') {
    nextdestiny(0,1);  #it is called within dodestiny
  }
  if ($request->{command}->[0] eq 'setdestiny') {
    setdestiny($request, 0); 
  }
}

sub relay_response {
    my $resp = shift;
    $callback->($resp);
    if ($resp and ($resp->{errorcode} and $resp->{errorcode}->[0]) or ($resp->{error} and $resp->{error}->[0])) {
        $errored=1;
    }
    foreach (@{$resp->{node}}) {
       if ($_->{error} or $_->{errorcode}) {
          $errored=1;
       }
    }
}

sub setdestiny {
    my $req=shift;
    my $flag=shift;
    my $noupdate=shift;
    
    $chaintab = xCAT::Table->new('chain',-create=>1);
    my @nodes=@{$req->{node}};

    @ARGV = @{$req->{arg}};
    my $noupdateinitrd;
    my $ignorekernelchk;
    GetOptions('noupdateinitrd' => \$noupdateinitrd,
               'ignorekernelchk' => \$ignorekernelchk,);
    
    my $state = $ARGV[0];
    my $reststates;

    # to support the case that the state could be runimage=xxx,runimage=yyy,osimage=xxx
    ($state, $reststates) = split (/,/, $state, 2);
    my %nstates;
    if ($state eq "enact") {
	my $nodetypetab = xCAT::Table->new('nodetype',-create=>1);
	my %nodestates;
	my %stents = %{$chaintab->getNodesAttribs($req->{node},"currstate")};
	my %ntents = %{$nodetypetab->getNodesAttribs($req->{node},"provmethod")};
	my $state;
	my $sninit=0;
	if (exists($req->{inittime})) { # this is called in AAsn.pm
	    $sninit=$req->{inittime}->[0];
	}
	
	foreach (@{$req->{node}}) { #First, build a hash of all of the states to attempt to keep things as aggregated as possible
	    if ($stents{$_}->[0]->{currstate}) {
		$state = $stents{$_}->[0]->{currstate};
		$state =~ s/ .*//;
		#get the osimagename if nodetype.provmethod has osimage specified
		#use it for both sninit and genesis operating
		if (($state eq 'install') || ($state eq 'netboot') || ($state eq 'statelite')) {
		    my $osimage=$ntents{$_}->[0]->{provmethod};
		    if (($osimage) && ($osimage ne 'install') && ($osimage ne 'netboot') && ($osimage ne 'statelite')) {
			$state="osimage=$osimage"; 
		    }
		}
		push @{$nodestates{$state}},$_;
	    }
	}
	foreach (keys %nodestates) {
	    $req->{arg}->[0]=$_;
	    $req->{node} = $nodestates{$_};
	    setdestiny($req,30,1); #ludicrous flag to denote no table updates can be inferred.
	}
	return;
    } elsif ($state eq "next") {
	return nextdestiny($flag + 1);  #this is special case where updateflag is called
    } elsif ($state eq "iscsiboot") {
	my $iscsitab=xCAT::Table->new('iscsi');
	unless ($iscsitab) {
	    $callback->({error=>"Unable to open iscsi table to get iscsiboot parameters",errorcode=>[1]});
	}
	my $bptab = xCAT::Table->new('bootparams',-create=>1);
	my $nodetype = xCAT::Table->new('nodetype');
	my $ntents = $nodetype->getNodesAttribs($req->{node},[qw(os arch profile)]);
	my $ients = $iscsitab->getNodesAttribs($req->{node},[qw(kernel kcmdline initrd)]);
	foreach (@{$req->{node}}) {
	    my $ient = $ients->{$_}->[0]; #$iscsitab->getNodeAttribs($_,[qw(kernel kcmdline initrd)]);
	    my $ntent = $ntents->{$_}->[0];
	    unless ($ient and $ient->{kernel}) {
		unless ($ntent and $ntent->{arch} =~ /x86/ and -f ("$tftpdir/undionly.kpxe" or -f "$tftpdir/xcat/xnba.kpxe")) { $callback->({error=>"$_: No iscsi boot data available",errorcode=>[1]}); } #If x86 node and undionly.kpxe exists, presume they know what they are doing
		next;
	    }
	    my $hash;
	    $hash->{kernel} = $ient->{kernel};
	    if ($ient->{initrd}) { $hash->{initrd} = $ient->{initrd} }
	    if ($ient->{kcmdline}) { $hash->{kcmdline} = $ient->{kcmdline} }
	    $bptab->setNodeAttribs($_,$hash);
	}
    } elsif ($state =~ /^install[=\$]/ or $state eq 'install' or $state =~ /^netboot[=\$]/ or $state eq 'netboot' or $state eq "image" or $state eq "winshell" or $state =~ /^osimage/ or $state =~ /^statelite/) {
	my %state_hash;
	chomp($state);
	my $target;
	my $action;
	if ($state =~ /=/) {
	    ($state,$target) = split '=',$state,2;
	    if ($target =~ /:/) {
		($target, $action) = split ':',$target,2;
	    }
	} else {
	    if ($state =~ /:/) {
		($state, $action) = split ':',$state,2;
	    }
	}

        foreach my $tmpnode (@{$req->{node}}) {
	    $state_hash{$tmpnode}=$state;
	}

	my $nodetypetable = xCAT::Table->new('nodetype', -create=>1);
	if ($state ne 'osimage') {
	    my $updateattribs;
	    if ($target) {
		my $archentries = $nodetypetable->getNodesAttribs($req->{node},['supportedarchs']);
		if ($target =~ /^([^-]*)-([^-]*)-(.*)/) {
		    $updateattribs->{os}=$1;
		    $updateattribs->{arch}=$2;
		    $updateattribs->{profile}=$3;
		    my $nodearch=$2;
		    foreach (@{$req->{node}}) {
			if ($archentries->{$_}->[0]->{supportedarchs} and $archentries->{$_}->[0]->{supportedarchs} !~ /(^|,)$nodearch(\z|,)/) {
			    $callback->({errorcode=>1,error=>"Requested architecture ".$nodearch." is not one of the architectures supported by $_  (per nodetype.supportedarchs, it supports ".$archentries->{$_}->[0]->{supportedarchs}.")"});
			    return;
			}
		    } #end foreach
		} else {
		    $updateattribs->{profile}=$target;
		}
	    } #end if($target) 
	    $updateattribs->{provmethod}=$state;
	    my @tmpnodelist = @{$req->{node}};
	    $nodetypetable->setNodesAttribs(\@tmpnodelist, $updateattribs);
	} else { #state is osimage
	    if (@{$req->{node}} == 0) { return;}
	    if ($target) {
		my $osimagetable=xCAT::Table->new('osimage');
		(my $ref) = $osimagetable->getAttribs({imagename => $target}, 'provmethod', 'osvers', 'profile', 'osarch');
		if ($ref) {
		    if ($ref->{provmethod}) {
			$state=$ref->{provmethod};
		    } else {
			$errored =1; $callback->({error=>"osimage.provmethod for $target must be set."});
			return;
		    }
		} else {
		    $errored =1; $callback->({error=>"Cannot find the OS image $target on the osimage table."});
		    return;
		}
		my $updateattribs;
		$updateattribs->{provmethod}=$target;
		$updateattribs->{profile}=$ref->{profile};
		$updateattribs->{os}=$ref->{osvers};
		$updateattribs->{arch}=$ref->{osarch};
		my @tmpnodelist = @{$req->{node}};
		$nodetypetable->setNodesAttribs(\@tmpnodelist,$updateattribs);

		foreach my $tmpnode (@{$req->{node}}) {
		    $state_hash{$tmpnode}=$state;
		}
		
	    } else { 
		my @errornodes=();
		my $updatestuff;
		my $nodetypetable = xCAT::Table->new('nodetype', -create=>1);
		my %ntents = %{$nodetypetable->getNodesAttribs($req->{node},"provmethod")};
		foreach my $tmpnode (@{$req->{node}}) { 
		    my $osimage=$ntents{$tmpnode}->[0]->{provmethod};
		    if (($osimage) && ($osimage ne 'install') && ($osimage ne 'netboot') && ($osimage ne 'statelite')) {
			if (!exists($updatestuff->{$osimage})) {
			    my $osimagetable=xCAT::Table->new('osimage');
			    (my $ref) = $osimagetable->getAttribs({imagename => $osimage}, 'provmethod', 'osvers', 'profile', 'osarch');
			    if ($ref) {
				if ($ref->{provmethod}) {
				    $state=$ref->{provmethod};
				    $state_hash{$tmpnode}=$state;

				    $updatestuff->{$osimage}->{state}=$state;
				    $updatestuff->{$osimage}->{nodes}=[$tmpnode];
				    $updatestuff->{$osimage}->{profile}=$ref->{profile};
				    $updatestuff->{$osimage}->{os}=$ref->{osvers};
				    $updatestuff->{$osimage}->{arch}=$ref->{osarch};
				} else {
				    $errored =1; $callback->({error=>"osimage.provmethod for $osimage must be set."});
				    return;
				}
			    } else {
				$errored =1; $callback->({error=>"Cannot find the OS image $osimage on the osimage table."});
				return;
			    }
			} else {
			    my $nodes= $updatestuff->{$osimage}->{nodes};
			    push (@$nodes, $tmpnode);
			    $state_hash{$tmpnode}=$updatestuff->{$osimage}->{state};
			}
			
		    } else {
			push(@errornodes, $tmpnode);
		    }
		}
		
		if (@errornodes) {
		    $errored =1; $callback->({error=>"OS image name must be specified in nodetype.provmethod for nodes: @errornodes."});
		    return;
		} else {
		    foreach my $tmpimage (keys %$updatestuff) {
			my $updateattribs=$updatestuff->{$tmpimage};
			my @tmpnodelist = @{$updateattribs->{nodes}};
			delete $updateattribs->{nodes}; #not needed for nodetype table
			delete $updateattribs->{state}; #node needed for nodetype table
			$nodetypetable->setNodesAttribs(\@tmpnodelist,$updateattribs);
		    } 
		}
	    }
	}
        #if the postscripts directory exists then make sure it is
        # world readable and executable by root; otherwise wget fails
        my $installdir = xCAT::TableUtils->getInstallDir();
        my $postscripts = "$installdir/postscripts";
        if (-e $postscripts)
        {
           my $cmd = "chmod -R a+r $postscripts";
           xCAT::Utils->runcmd($cmd, 0);
           my $rsp = {};
           if ($::RUNCMD_RC != 0)
           {
              $callback->({info=>"$cmd failed"});

           }

        }
	#print Dumper($req);
	# if precreatemypostscripts=1, create each mypostscript for each node
	# otherwise, create it during installation /updatenode
        my $notmpfiles=0; # create tmp files if precreate=0
        my $nofiles=0; # create files, do not return array
	require xCAT::Postage;
	xCAT::Postage::create_mypostscript_or_not($request, $callback, $subreq,$notmpfiles,$nofiles); 
       
        my %state_hash1; 
	foreach my $tmpnode (keys(%state_hash)) {
	    push @{$state_hash1{$state_hash{$tmpnode}}},$tmpnode;
	}
	#print Dumper(%state_hash);
	#print Dumper(%state_hash1);
	foreach my $tempstate (keys %state_hash1) {
	    my $samestatenodes=$state_hash1{$tempstate};
	    #print "state=$tempstate nodes=@$samestatenodes\n";	
	    $errored=0;
	    $subreq->({command=>["mk$tempstate"],
		       node=>$samestatenodes, 
		       noupdateinitrd=>$noupdateinitrd,
                       ignorekernelchk=>$ignorekernelchk,}, \&relay_response);
	    if ($errored) { 
                my @myself = xCAT::NetworkUtils->determinehostname();
                my $myname = $myself[(scalar @myself)-1];
		$callback->({error=>"Some nodes failed to set up $state resources on server $myname, aborting"});
		return; 
	    }
	
	
	    my $ntents = $nodetypetable->getNodesAttribs($samestatenodes,[qw(os arch profile)]);
	    foreach (@{$samestatenodes}) {
		$nstates{$_} = $tempstate; #local copy of state variable for mod
		my $ntent = $ntents->{$_}->[0]; #$nodetype->getNodeAttribs($_,[qw(os arch profile)]);
		if ($tempstate ne "winshell") {
		    if ($ntent and $ntent->{os}) {
			$nstates{$_} .= " ".$ntent->{os};
		    } else { $errored =1; $callback->({error=>"nodetype.os not defined for $_"}); }
		} else {
		    $nstates{$_} .= " winpe";
		}
		if ($ntent and $ntent->{arch}) {
		    $nstates{$_} .= "-".$ntent->{arch};
		} else { $errored =1; $callback->({error=>"nodetype.arch not defined for $_"}); }
		if (($tempstate ne "winshell") && ($tempstate ne "sysclone")) {
		    if ($ntent and $ntent->{profile}) {
			$nstates{$_} .= "-".$ntent->{profile};
		    } else { $errored =1; $callback->({error=>"nodetype.profile not defined for $_"}); }
		}
		if ($errored) {return;}
		#statelite
		unless ($tempstate =~ /^netboot|^statelite/) { $chaintab->setNodeAttribs($_,{currchain=>"boot"}); };
	    }
	    
	    if ($action eq "reboot4deploy") {
		# this action is used in the discovery process for deployment of the node
		# e.g. set chain.chain to 'osimage=rhels6.2-x86_64-netboot-compute:reboot4deploy'
		# Set the status of the node to be 'installing' or 'netbooting'
		my %newnodestatus;
		my $newstat=xCAT_monitoring::monitorctrl->getNodeStatusFromNodesetState($tempstate, "rpower");
		$newnodestatus{$newstat}=$samestatenodes;
		xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%newnodestatus, 1);
	    }
	}
    } elsif ($state eq "shell" or $state eq "standby" or $state =~ /^runcmd/ or $state =~ /^runimage/) {
	$restab=xCAT::Table->new('noderes',-create=>1);
	my $bootparms=xCAT::Table->new('bootparams',-create=>1);
	my $nodetype = xCAT::Table->new('nodetype');
	#my $sitetab = xCAT::Table->new('site');
	my $nodehm = xCAT::Table->new('nodehm');
	my $hments = $nodehm->getNodesAttribs(\@nodes,['serialport','serialspeed','serialflow']);
	#(my $portent) = $sitetab->getAttribs({key=>'xcatdport'},'value');
	my @entries =  xCAT::TableUtils->get_site_attribute("xcatdport");
	my $port_entry = $entries[0];
	#(my $mastent) = $sitetab->getAttribs({key=>'master'},'value');
	my @entries =  xCAT::TableUtils->get_site_attribute("master");
	my $master_entry = $entries[0];
	my $enthash = $nodetype->getNodesAttribs(\@nodes,[qw(arch)]);
	my $resents = $restab->getNodesAttribs(\@nodes,[qw(xcatmaster)]);
	foreach (@nodes) {
	    my $ent = $enthash->{$_}->[0]; #$nodetype->getNodeAttribs($_,[qw(arch)]);
	    unless ($ent and $ent->{arch}) {
		$callback->({error=>["No archictecture defined in nodetype table for $_"],errorcode=>[1]});
		return;
	    }
	    my $arch = $ent->{arch};
	    my $ent = $resents->{$_}->[0]; #$restab->getNodeAttribs($_,[qw(xcatmaster)]);
	    my $master;
	    my $kcmdline = "quiet ";
	    if ( defined($master_entry) ) {
		$master = $master_entry;
	    }
	    if ($ent and $ent->{xcatmaster}) {
		$master = $ent->{xcatmaster};
	    }
	    $ent = $hments->{$_}->[0]; #$nodehm->getNodeAttribs($_,['serialport','serialspeed','serialflow']);
	    if ($ent and defined($ent->{serialport})) {
		$kcmdline .= "console=tty0 console=ttyS".$ent->{serialport};
		#$ent = $nodehm->getNodeAttribs($_,['serialspeed']);
		unless ($ent and defined($ent->{serialspeed})) {
		    $callback->({error=>["Serial port defined in noderes, but no nodehm.serialspeed set for $_"],errorcode=>[1]});
		    return;
		}
		$kcmdline .= ",".$ent->{serialspeed};
		#$ent = $nodehm->getNodeAttribs($_,['serialflow']);
		$kcmdline .= " ";
	    }
	    
	    unless ($master) {
		$callback->({error=>["No master in site table nor noderes table for $_"],errorcode=>[1]});
		return;
	    }
	    my $xcatdport="3001";
	    if ( defined($port_entry)) {
		$xcatdport = $port_entry;
	    }
	    if (-r "$tftpdir/xcat/genesis.kernel.$arch") {
		my $bestsuffix="lzma";
		my $othersuffix="gz";
		if (-r "$tftpdir/xcat/genesis.fs.$arch.lzma" and -r "$tftpdir/xcat/genesis.fs.$arch.gz") {
			if (-C "$tftpdir/xcat/genesis.fs.$arch.lzma" > -C "$tftpdir/xcat/genesis.fs.$arch.gz") { #here, lzma is older for whatever reason
				$bestsuffix="gz";
				$othersuffix="lzma";
			}
		}
		if (-r "$tftpdir/xcat/genesis.fs.$arch.$bestsuffix") {
		    $bootparms->setNodeAttribs($_,{kernel => "xcat/genesis.kernel.$arch",
						   initrd => "xcat/genesis.fs.$arch.$bestsuffix",
						   kcmdline => $kcmdline."xcatd=$master:$xcatdport destiny=$state"});
		} else {
		    $bootparms->setNodeAttribs($_,{kernel => "xcat/genesis.kernel.$arch",
						   initrd => "xcat/genesis.fs.$arch.$othersuffix",
						   kcmdline => $kcmdline."xcatd=$master:$xcatdport destiny=$state"});
		}
	    } else {  #'legacy' environment
		$bootparms->setNodeAttribs($_,{kernel => "xcat/nbk.$arch",
					       initrd => "xcat/nbfs.$arch.gz",
					       kcmdline => $kcmdline."xcatd=$master:$xcatdport"});
	    }
	}
        # try to check the existence of the image for runimage
        my @runimgcmds;
        if ($state =~ /^runimage/) {
            push @runimgcmds, $state;
        }
        if ($reststates) {
            my @rstates = split (/,/, $reststates);
            foreach (@rstates) {
                if (/^runimage/) {
                    push @runimgcmds, $_;
                }
            }
        }

        foreach (@runimgcmds) {
            my (undef, $path) = split (/=/, $_);
            if ($path) {
                if ($path =~ /\$/) {next;} # Ignore the path with including variable like $xcatmaster
                my $cmd = "wget --spider --timeout 3 --tries=1 $path";
                my @output = xCAT::Utils->runcmd("$cmd", -1);
                unless (grep /^Remote file exists/, @output) {
                    $callback->({error=>["Cannot get $path with wget. Could you confirm it's downloadable by wget?"],errorcode=>[1]});
                    return;
                }
            } else {
                $callback->({error=>"An image path should be specified to runnimage.",errorcode=>[1]});
                return;
            }
        }
    } elsif ($state eq "offline" || $state eq "shutdown") {
	1;
    } elsif (!($state eq "boot")) { 
	$callback->({error=>["Unknown state $state requested"],errorcode=>[1]});
	return;
    }
    
    #blank out the nodetype.provmethod if the previous provisioning method is not 'install'
    if ($state eq "iscsiboot" or $state eq "boot") {
	my $nodetype = xCAT::Table->new('nodetype',-create=>1);
	my $osimagetab = xCAT::Table->new('osimage', -create=>1);
	my $ntents = $nodetype->getNodesAttribs($req->{node},[qw(os arch profile provmethod)]);
	my @nodestoblank=();
	my %osimage_hash=();
	foreach (@{$req->{node}}) {
	    my $ntent = $ntents->{$_}->[0];
	    
	    #if the previous nodeset staute is not install, then blank nodetype.provmethod
	    if ($ntent and $ntent->{provmethod}){
		my $provmethod=$ntent->{provmethod};
		if (($provmethod ne 'install') && ($provmethod ne 'netboot') && ($provmethod ne 'statelite')) {
		    if (exists($osimage_hash{$provmethod})) {
			$provmethod= $osimage_hash{$provmethod};
		    } else {
			(my $ref) = $osimagetab->getAttribs({imagename => $provmethod}, 'provmethod');
			if (($ref) && $ref->{provmethod}) {
			    $osimage_hash{$provmethod}=$ref->{provmethod};
			    $provmethod=$ref->{provmethod};
			} 
		    }
		}
		if ($provmethod ne 'install') {
		    push(@nodestoblank, $_);
		}
	    }
	} #end foreach
	
	#now blank out the nodetype.provmethod
	#print "nodestoblank=@nodestoblank\n";
	if (@nodestoblank > 0) {
	    my $newhash;
	    $newhash->{provmethod}="";
	    $nodetype->setNodesAttribs(\@nodestoblank, $newhash);
	}
    }
    
    if ($noupdate) { return; } #skip table manipulation if just doing 'enact'
    foreach (@nodes) {
	my $lstate = $state;
	if ($nstates{$_}) {
	    $lstate = $nstates{$_};
	} 
	$chaintab->setNodeAttribs($_,{currstate=>$lstate});
        # if there are multiple actions in the state argument, set the rest of states (shift out the first one)
        # to chain.currchain so that the rest ones could be used by nextdestiny command
        if ($reststates) {
           $chaintab->setNodeAttribs($_,{currchain=>$reststates});
        }
    }
    return getdestiny($flag + 1);
}


sub nextdestiny {
  my $flag=shift;
  my $callnodeset=0;
  if (scalar(@_)) {
     $callnodeset=1;
  }
  my @nodes;
  if ($request and $request->{node}) {
    if (ref($request->{node})) {
      @nodes = @{$request->{node}};
    } else {
      @nodes = ($request->{node});
    }
    #TODO: service third party getdestiny..
  } else { #client asking to move along its own chain
    #TODO: SECURITY with this, any one on a node could advance the chain, for node, need to think of some strategy to deal with...
    my $node;
    if ($::XCATSITEVALS{nodeauthentication}) { #if requiring node authentication, this request will have a certificate associated with it, use it instead of name resolution
	unless (ref $request->{username}) { return; } #TODO: log an attempt without credentials? 
	$node = $request->{username}->[0];
    } else {
	    unless ($request->{'_xcat_clienthost'}->[0]) {
	      #ERROR? malformed request
	      return; #nothing to do here...
	    }
	    $node = $request->{'_xcat_clienthost'}->[0];
    }
   ($node) = noderange($node);
   unless ($node) {
      #not a node, don't trust it
      return;
   }
   @nodes=($node);
  }

  my $node;
  my $noupdate_flag = 0;
  $chaintab = xCAT::Table->new('chain');
  my $chainents = $chaintab->getNodesAttribs(\@nodes,[qw(currstate currchain chain)]);
  foreach $node (@nodes) {
    unless($chaintab) {
      syslog("local4|err","ERROR: $node requested destiny update, no chain table");
      return; #nothing to do...
    }
    my $ref =  $chainents->{$node}->[0]; #$chaintab->getNodeAttribs($node,[qw(currstate currchain chain)]);
    unless ($ref->{chain} or $ref->{currchain}) {
      syslog ("local4|err","ERROR: node requested destiny update, no path in chain.currchain");
      return; #Can't possibly do anything intelligent..
    }
    unless ($ref->{currchain}) { #If no current chain, copy the default
      $ref->{currchain} = $ref->{chain};
    }
    my @chain = split /[,;]/,$ref->{currchain};

    $ref->{currstate} = shift @chain;
    $ref->{currchain}=join(',',@chain);
    unless ($ref->{currchain}) { #If we've gone off the end of the chain, have currchain stick
      $ref->{currchain} = $ref->{currstate};
    }
    $chaintab->setNodeAttribs($node,$ref); #$ref is in a state to commit back to db

    my %requ;
    $requ{node}=[$node];
    $requ{arg}=[$ref->{currstate}];
    if($ref->{currstate} =~ /noupdateinitrd$/)
    {
        my @items = split /[:]/,$ref->{currstate};
        $requ{arg}= \@items;
        $noupdate_flag = 1;
    }
    setdestiny(\%requ, $flag+1);
  }
  
  if ($callnodeset) {
     my $args;
     if($noupdate_flag)
     {
	     $args = ['enact', '--noupdateinitrd'];
     } 
     else
     {
	     $args = ['enact'];
     }
     $subreq->({command=>['nodeset'],
               node=> \@nodes,
               arg=>$args});
  }

}


sub getdestiny {
  my $flag=shift;
  # flag value:
  # 0--getdestiny is called by dodestiny
  # 1--called by nextdestiny in dodestiny. The node calls nextdestiny before boot and runcmd.
  # 2--called by nodeset command
  # 3--called by updateflag after the node finished installation and before booting
  my @args;
  my @nodes;
  if ($request->{node}) {
    if (ref($request->{node})) {
      @nodes = @{$request->{node}};
    } else {
      @nodes = ($request->{node});
    }
  } else { # a client asking for it's own destiny.
    unless ($request->{'_xcat_clienthost'}->[0]) {
      $callback->({destiny=>[ 'discover' ]});
      return;
    }
    my ($node) = noderange($request->{'_xcat_clienthost'}->[0]);
    unless ($node) { # it had a valid hostname, but isn't a node
      $callback->({destiny=>[ 'discover' ]}); 
      return;
    }
    @nodes=($node);
  }
  my $node;
  $restab = xCAT::Table->new('noderes');
  my $chaintab = xCAT::Table->new('chain');
  my $chainents = $chaintab->getNodesAttribs(\@nodes,[qw(currstate chain)]);
  my $nrents = $restab->getNodesAttribs(\@nodes,[qw(tftpserver xcatmaster)]);
  $bptab = xCAT::Table->new('bootparams',-create=>1);
  my $bpents = $bptab->getNodesAttribs(\@nodes,[qw(kernel initrd kcmdline xcatmaster)]);
  #my $sitetab= xCAT::Table->new('site');
  #(my $sent) = $sitetab->getAttribs({key=>'master'},'value');
  my @entries =  xCAT::TableUtils->get_site_attribute("master");
  my $master_value = $entries[0];

  my %node_status=();
  foreach $node (@nodes) {
    unless ($chaintab) { #Without destiny, have the node wait with ssh hopefully open at least
      $callback->({node=>[{name=>[$node],data=>['standby'],destiny=>[ 'standby' ]}]});
      return;
    }
    my $ref = $chainents->{$node}->[0]; #$chaintab->getNodeAttribs($node,[qw(currstate chain)]);
    unless ($ref) {
      #collect node status for certain states
      if (($nonodestatus==0) && (($flag==0) || ($flag==3))) { 
        my $stat=xCAT_monitoring::monitorctrl->getNodeStatusFromNodesetState("standby", "getdestiny");
	#print "node=$node, stat=$stat\n";
        if ($stat) {
          if (exists($node_status{$stat})) {
            my $pa=$node_status{$stat};
            push(@$pa, $node);
          }
          else { $node_status{$stat}=[$node]; }
        }    
      }

      $callback->({node=>[{name=>[$node],data=>['standby'],destiny=>[ 'standby' ]}]});
      next;
    }
    unless ($ref->{currstate}) { #Has a record, but not yet in a state...
      # we set a 1 here so that it does the nodeset to create tftpboot files
      return nextdestiny(0,1); #Becomes a nextdestiny...
#      my @chain = split /,/,$ref->{chain};
#      $ref->{currstate} = shift @chain;
#      $chaintab->setNodeAttribs($node,{currstate=>$ref->{currstate}});
    }
    my %response;
    $response{name}=[$node];
    $response{data}=[$ref->{currstate}];
    $response{destiny}=[$ref->{currstate}];
    my $nrent = $nrents->{$node}->[0]; #$noderestab->getNodeAttribs($node,[qw(tftpserver xcatmaster)]);
    my $bpent = $bpents->{$node}->[0]; #$bptab->getNodeAttribs($node,[qw(kernel initrd kcmdline xcatmaster)]);
    if (defined $bpent->{kernel}) {
        $response{kernel}=$bpent->{kernel};
    }
    if (defined $bpent->{initrd}) {
        $response{initrd}=$bpent->{initrd};
    }
    if (defined $bpent->{kcmdline}) {
        $response{kcmdline}=$bpent->{kcmdline};
    }
    if (defined $nrent->{tftpserver}) {
        $response{imgserver}=$nrent->{tftpserver};
    } elsif (defined $nrent->{xcatmaster}) {
        $response{imgserver}=$nrent->{xcatmaster};
    } elsif (defined( $master_value )) {
        $response{imgserver}=$master_value;
    } else {
       $response{imgserver} = xCAT::NetworkUtils->my_ip_facing($node);
    }
    
    #collect node status for certain states
    if (($flag==0) || ($flag==3)) {
      my $stat=xCAT_monitoring::monitorctrl->getNodeStatusFromNodesetState($response{destiny}->[0], "getdestiny");
	#print  "node=$node, stat=$stat\n";
      if ($stat) {
        if (exists($node_status{$stat})) {
          my $pa=$node_status{$stat};
          push(@$pa, $node);
        }
        else { $node_status{$stat}=[$node]; }
      }    
    }

    $callback->({node=>[\%response]});
  }  

  #setup the nodelist.status
  if (($nonodestatus==0) && (($flag==0) || ($flag==3))) {
      #print "save status\n";
    if (keys(%node_status) > 0) { xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%node_status, 1); }
  }
}


1;
