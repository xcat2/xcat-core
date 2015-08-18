# IBM(c) 2014 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::petitboot;

use File::Path;
use Getopt::Long;
use xCAT::Table;
use Sys::Syslog;

my $globaltftpdir = xCAT::TableUtils->getTftpDir();

my %usage = (
    "nodeset" => "Usage: nodeset <noderange> osimage[=<imagename>]",
);

my $httpmethod="http";
my $httpport = "80";

sub handled_commands {
  return {
    nodeset => "noderes:netboot"
  }
}

sub check_dhcp {
  return 1;
  #TODO: omapi magic to do things right
  my $node = shift;
  my $dhcpfile;
  open ($dhcpfile,$dhcpconf);
  while (<$dhcpfile>) {
    if (/host $node\b/) {
      close $dhcpfile;
      return 1;
    }
  }
  close $dhcpfile;
  return 0;
}

sub _slow_get_tftpdir { #make up for paths where tftpdir is not passed in
    my $node=shift;
    my $nrtab = xCAT::Table->new('noderes',-create=>0); #in order to detect per-node tftp directories
    unless ($nrtab) { return $globaltftpdir; }
    my $ent = $nrtab->getNodeAttribs($node,["tftpdir"]);
    if ($ent and $ent->{tftpdir}) {
	return $ent->{tftpdir};
    } else {
        return $globaltftpdir;
    }
}

sub getstate {
  my $node = shift;
  my $tftpdir = shift;
  unless ($tftpdir) { $tftpdir = _slow_get_tftpdir($node); }
  if (check_dhcp($node)) {
    if (-r $tftpdir . "/petitboot/".$node) {
      my $fhand;
      open ($fhand,$tftpdir . "/petitboot/".$node);
      my $headline = <$fhand>;
      close $fhand;
      $headline =~ s/^#//;
      chomp($headline);
      return $headline;
    } else {
      return "boot";
    }
  } else {
    return "discover";
  }
}

sub setstate {
=pod

  This function will manipulate the yaboot structure to match what the noderes/chain tables indicate the node should be booting.

=cut
  my $node = shift;
  my %bphash = %{shift()};
  my %chainhash = %{shift()};
  my %machash = %{shift()};
  my $tftpdir = shift;
  my %nrhash = %{shift()};
  my $linuximghash = shift();
  my $kern = $bphash{$node}->[0]; #$bptab->getNodeAttribs($node,['kernel','initrd','kcmdline']);
   #my $nodereshash=$noderestab->getNodesAttribs(\@nodes,['tftpdir','xcatmaster','nfsserver', 'servicenode']);
  if ($kern->{kernel} !~ /^$tftpdir/) {
      my $nodereshash = $nrhash{$node}->[0];
      my $installsrv;
      if ($nodereshash and $nodereshash->{nfsserver} ) {
          $installsrv = $nodereshash->{nfsserver};
      } elsif ($nodereshash->{xcatmaster}) {
          $installsrv = $nodereshash->{xcatmaster};
      } else {
          $installsrv = '!myipfn!';
      }
      $kern->{kernel} = "$httpmethod://$installsrv:$httpport$tftpdir/".$kern->{kernel};
      $kern->{initrd} = "$httpmethod://$installsrv:$httpport$tftpdir/".$kern->{initrd};
  }
  if ($kern->{kcmdline} =~ /!myipfn!/ or $kern->{kernel} =~ /!myipfn!/) {
      my $ipfn = xCAT::NetworkUtils->my_ip_facing($node);
      unless ($ipfn) {
          my $servicenodes = $nrhash{$node}->[0];
          if ($servicenodes and $servicenodes->{servicenode}) {
              my @sns = split /,/, $servicenodes->{servicenode};
              foreach my $sn ( @sns ) {
                  # We are in the service node pools, print error if no facing ip.
                  if (xCAT::InstUtils->is_me($sn)) {
                      my @myself = xCAT::NetworkUtils->determinehostname();
                      my $myname = $myself[(scalar @myself)-1];
                      $::callback->(
                          {
                          error => [
                          "$myname: Unable to determine the image server for $node on service node $sn"
                          ],
                          errorcode => [1]
                          }
                      );
                      return;
                  }
              }
          } else {
              $::callback->(
                          {
                          error => [
                          "$myname: Unable to determine the image server for $node"
                          ],
                          errorcode => [1]
                          }
                      );
              return;
          }
      } else {
          $kern->{kernel} =~ s/!myipfn!/$ipfn/g;
          $kern->{initrd} =~ s/!myipfn!/$ipfn/g;
          $kern->{kcmdline} =~ s/!myipfn!/$ipfn/g;
      }
  }


  if ($kern->{addkcmdline}) {
      $kern->{kcmdline} .= " ".$kern->{addkcmdline};
  }
  
  if($linuximghash and $linuximghash->{'addkcmdline'})
  {
      unless($linuximghash->{'boottarget'}) 
      {
          $kern->{kcmdline} .= " ".$linuximghash->{'addkcmdline'};
      } 
  }
   
  my $pcfg;
  unless (-d "$tftpdir/petitboot") {
     mkpath("$tftpdir/petitboot");
  }
  my $nodemac;

  open($pcfg,'>',$tftpdir."/petitboot/".$node);
  my $cref=$chainhash{$node}->[0]; #$chaintab->getNodeAttribs($node,['currstate']);
  if ($cref->{currstate}) {
    print $pcfg "#".$cref->{currstate}."\n";
  }
  $normalnodes{$node}=1; #Assume a normal netboot (well, normal dhcp, 
                      #which is normally with a valid 'filename' field,
                      #but the typical ppc case will be 'special' makedhcp
                      #to clear the filename field, so the logic is a little
                      #opposite
  #  $sub_req->({command=>['makedhcp'], #This is currently batched elswhere
  #         node=>[$node]},$callback);  #It hopefully will perform correctly
  if ($cref and $cref->{currstate} eq "boot") {
    $breaknetbootnodes{$node}=1;
    delete $normalnodes{$node}; #Signify to omit this from one makedhcp command
    #$sub_req->({command=>['makedhcp'], #batched elsewhere, this code is stale, hopefully
    #       node=>[$node],
    #        arg=>['-s','filename = \"xcat/nonexistant_file_to_intentionally_break_netboot_for_localboot_to_work\";']},$callback);
    #print $pcfg "bye\n";
    close($pcfg);
  } elsif ($kern and $kern->{kernel}) {
    #It's time to set yaboot for this node to boot the kernel..
    print $pcfg "default xCAT\n";
    print $pcfg "label xCAT\n";
    print $pcfg "\tkernel $kern->{kernel}\n";
    if ($kern and $kern->{initrd}) {
      print $pcfg "\tinitrd ".$kern->{initrd}."\n";
    }
    if ($kern and $kern->{kcmdline}) {
      print $pcfg "\tappend \"".$kern->{kcmdline}."\"\n";
    }
    close($pcfg);
    my $inetn = xCAT::NetworkUtils->getipaddr($node);
    unless ($inetn) {
     syslog("local1|err","xCAT unable to resolve IP for $node in petitboot plugin");
     return;
    }
  } else { #TODO: actually, should possibly default to xCAT image?
    #print $pcfg "bye\n";
    close($pcfg);
  }
  my $ip = xCAT::NetworkUtils->getipaddr($node);
  unless ($ip) {
    syslog("local1|err","xCAT unable to resolve IP in petitboot plugin");
    return;
  }

      my @ipa=split(/\./,$ip);
      my $pname = sprintf("%02x%02x%02x%02x",@ipa);
      $pname = uc($pname);
      unlink($tftpdir."/".$pname);
      link($tftpdir."/petitboot/".$node,$tftpdir."/".$pname);
  return;      
}
  

    
my $errored = 0;
sub pass_along { 
    my $resp = shift;

#    print Dumper($resp);
    
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


sub preprocess_request {
    my $req = shift;
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }

    my $callback1 = shift;
    my $command  = $req->{command}->[0];
    my $sub_req = shift;
    my @args=();
    if (ref($req->{arg})) {
	@args=@{$req->{arg}};
    } else {
	@args=($req->{arg});
    }
    @ARGV = @args;
    my $nodes = $req->{node};
    #use Getopt::Long;
    my $HELP;
    my $VERSION;
    my $VERBOSE;
    Getopt::Long::Configure("bundling");
    Getopt::Long::Configure("pass_through");
    if (!GetOptions('h|?|help'  => \$HELP, 
	'v|version' => \$VERSION,
	'V'  => \$VERBOSE    #>>>>>>>used for trace log>>>>>>>
	) ) {
      if($usage{$command}) {
          my %rsp;
          $rsp{data}->[0]=$usage{$command};
          $callback1->(\%rsp);
      }
      return;
    }

    #>>>>>>>used for trace log start>>>>>>
    my $verbose_on_off=0;  
    if($VERBOSE){$verbose_on_off=1;}
    #>>>>>>>used for trace log end>>>>>>>
	
    if ($HELP) { 
	if($usage{$command}) {
	    my %rsp;
	    $rsp{data}->[0]=$usage{$command};
	    $callback1->(\%rsp);
	}
	return;
    }

    if ($VERSION) {
	my $ver = xCAT::Utils->Version();
	my %rsp;
	$rsp{data}->[0]="$ver";
	$callback1->(\%rsp);
	return; 
    }

    if (@ARGV==0) {
	if($usage{$command}) {
	    my %rsp;
	    $rsp{data}->[0]=$usage{$command};
	    $callback1->(\%rsp);
	}
	return;
    }


   #Assume shared tftp directory for boring people, but for cool people, help sync up tftpdirectory contents when 
   #if they specify no sharedtftp in site table
   my @entries =  xCAT::TableUtils->get_site_attribute("sharedtftp");
   my $t_entry = $entries[0];
   xCAT::MsgUtils->trace($verbose_on_off,"d","petitboot: sharedtftp = $t_entry");
   if ( defined($t_entry)  and ($t_entry == 0 or $t_entry =~ /no/i)) {
      # check for  computenodes and servicenodes from the noderange, if so error out
       my @SN;
       my @CN;
       xCAT::ServiceNodeUtils->getSNandCPnodes(\@$nodes, \@SN, \@CN);
       if ((@SN > 0) && (@CN >0 )) { # there are both SN and CN
            my $rsp;
            $rsp->{data}->[0] = 
              "Nodeset was run with a noderange containing both service nodes and compute nodes. This is not valid. You must submit with either compute nodes in the noderange or service nodes. \n";
            xCAT::MsgUtils->message("E", $rsp, $callback1);       
            return; 
           
       } 

      $req->{'_disparatetftp'}=[1];
      if ($req->{inittime}->[0]) {
          return [$req];
      }
      if (@CN >0 ) { # if compute nodes broadcast to all servicenodes
       return xCAT::Scope->get_broadcast_scope($req,@_);
      }
   }
   return [$req];
}


sub process_request {
  $request = shift;
  $callback = shift;
  $::callback=$callback;
  $sub_req = shift;
  my $command  = $request->{command}->[0];
  %breaknetbootnodes=();
  %normalnodes=();
  
  #>>>>>>>used for trace log start>>>>>>>
  my @args=();
  my %opt;
  my $verbose_on_off=0;
  if (ref($::request->{arg})) {
    @args=@{$::request->{arg}};
  } else {
    @args=($::request->{arg});
  }
  @ARGV = @args;
  GetOptions('V'  => \$opt{V});
  if($opt{V}){$verbose_on_off=1;}
  #>>>>>>>used for trace log end>>>>>>>
  
  if ($::XCATSITEVALS{"httpmethod"}) { $httpmethod = $::XCATSITEVALS{"httpmethod"}; }
  if ($::XCATSITEVALS{"httpport"}) { $httpport = $::XCATSITEVALS{"httpport"}; }

  my @nodes;
  my @rnodes;
  if (ref($request->{node})) {
    @rnodes = @{$request->{node}};
  } else {
    if ($request->{node}) { @rnodes = ($request->{node}); }
  }
  unless (@rnodes) {
      if ($usage{$request->{command}->[0]}) {
          $callback->({data=>$usage{$request->{command}->[0]}});
      }
      return;
  }

  #if not shared tftpdir, then filter, otherwise, set up everything
  if ($request->{'_disparatetftp'}->[0]) { #reading hint from preprocess_command
   @nodes = ();
   foreach (@rnodes) {
     if (xCAT::NetworkUtils->nodeonmynet($_)) {
        push @nodes,$_;
     } else {
        xCAT::MsgUtils->message("S", "$_: petitboot netboot: stop configuration because of none sharedtftp and not on same network with its xcatmaster.");
     }
   }
  } else {
     @nodes = @rnodes;
  }

  #>>>>>>>used for trace log>>>>>>>
  my $str_node = join(" ",@nodes);
  xCAT::MsgUtils->trace($verbose_on_off,"d","petitboot: nodes are $str_node");
  
  # return directly if no nodes in the same network
  unless (@nodes) {
     xCAT::MsgUtils->message("S", "xCAT: petitboot netboot: no valid nodes. Stop the operation on this server.");
     return;
  }

  if (ref($request->{arg})) {
    @args=@{$request->{arg}};
  } else {
    @args=($request->{arg});
  }
  
  #now run the begin part of the prescripts
  unless ($args[0] eq 'stat') { # or $args[0] eq 'enact') {
      $errored=0;
      if ($request->{'_disparatetftp'}->[0]) {  #the call is distrubuted to the service node already, so only need to handles my own children
	  xCAT::MsgUtils->trace($verbose_on_off,"d","petitboot: the call is distrubuted to the service node already, so only need to handles my own children");
	  xCAT::MsgUtils->trace($verbose_on_off,"d","petitboot: issue runbeginpre request");
	  $sub_req->({command=>['runbeginpre'],
		      node=>\@nodes,
		      arg=>[$args[0], '-l']},\&pass_along);
      } else { #nodeset did not distribute to the service node, here we need to let runednpre to distribute the nodes to their masters
          xCAT::MsgUtils->trace($verbose_on_off,"d","petitboot: nodeset did not distribute to the service node");
          xCAT::MsgUtils->trace($verbose_on_off,"d","petitboot: issue runbeginpre request");
	  $sub_req->({command=>['runbeginpre'],   
		      node=>\@rnodes,
		      arg=>[$args[0]]},\&pass_along);
      }
      if ($errored) {
	  my $rsp;
 	  $rsp->{errorcode}->[0]=1;
	  $rsp->{error}->[0]="Failed in running begin prescripts.\n";
	  $callback->($rsp);
	  return; 
      }
  } 

  #back to normal business
  my $inittime=0;
  if (exists($request->{inittime})) { $inittime= $request->{inittime}->[0];}
  if (!$inittime) { $inittime=0;}
  $errored=0;
  unless ($args[0] eq 'stat') { # or $args[0] eq 'enact') {
    xCAT::MsgUtils->trace($verbose_on_off,"d","petitboot: issue setdestiny request");
    $sub_req->({command=>['setdestiny'],
		node=>\@nodes,
		inittime=>[$inittime],
		arg=>\@args},\&pass_along);
  }
  if ($errored) { return; }

  # Fix the bug 4611: PowerNV stateful CN provision will hang at reboot stage#
  if ($args[0] eq 'next') {
    $sub_req->({command=>['rsetboot'],
                node=>\@nodes,
                arg=>['default']});
    xCAT::MsgUtils->message("S", "xCAT: petitboot netboot: clear node(s): @nodes boot device setting.");
  }
  my $bptab=xCAT::Table->new('bootparams',-create=>1);
  my $bphash = $bptab->getNodesAttribs(\@nodes,['kernel','initrd','kcmdline','addkcmdline']);
  my $chaintab=xCAT::Table->new('chain',-create=>1);
  my $chainhash=$chaintab->getNodesAttribs(\@nodes,['currstate']);
  my $noderestab=xCAT::Table->new('noderes',-create=>1);
  my $nodereshash=$noderestab->getNodesAttribs(\@nodes,['tftpdir','xcatmaster','nfsserver', 'servicenode']);
  my $mactab=xCAT::Table->new('mac',-create=>1);
  my $machash=$mactab->getNodesAttribs(\@nodes,['mac']);
  my $typetab=xCAT::Table->new('nodetype',-create=>1);
  my $typehash=$typetab->getNodesAttribs(\@nodes,['os','provmethod','arch','profile']);
  my $linuximgtab=xCAT::Table->new('linuximage',-create=>1);
  my $osimagetab=xCAT::Table->new('osimage',-create=>1);

  my $rc;
  my $errstr;

  my $tftpdir;
  foreach (@nodes) {
    my %response;
    if ($nodereshash->{$_} and $nodereshash->{$_}->[0] and $nodereshash->{$_}->[0]->{tftpdir}) {
       $tftpdir =  $nodereshash->{$_}->[0]->{tftpdir};
    } else {
       $tftpdir = $globaltftpdir;
    }
    $response{node}->[0]->{name}->[0]=$_;
    if ($args[0] eq 'stat') {
      $response{node}->[0]->{data}->[0]= getstate($_,$tftpdir);
      $callback->(\%response);
    } elsif ($args[0]) { #If anything else, send it on to the destiny plugin, then setstate
      my $ent = $typehash->{$_}->[0]; 
      my $osimgname = $ent->{'provmethod'};
      my $linuximghash = $linuximghash = $linuximgtab->getAttribs({imagename => $osimgname}, 'boottarget', 'addkcmdline');
     

      ($rc,$errstr) = setstate($_,$bphash,$chainhash,$machash,$tftpdir,$nodereshash,$linuximghash);
      if ($rc) {
        $response{node}->[0]->{errorcode}->[0]= $rc;
        $response{node}->[0]->{errorc}->[0]= $errstr;
        $callback->(\%response);
      }
    }
  }# end of foreach node    

  my @normalnodeset = keys %normalnodes;
  my @breaknetboot=keys %breaknetbootnodes;
  #print "yaboot:inittime=$inittime; normalnodeset=@normalnodeset; breaknetboot=@breaknetboot\n";
  my %osimagenodehash;
  for my $nn (@normalnodeset){
      #record the os version for node
      my $ent = $typehash->{$nn}->[0];
      my $osimage=$ent->{'provmethod'};
      push @{$osimagenodehash{$osimage}}, $nn;
  }
  
  #Don't bother to try dhcp binding changes if sub_req not passed, i.e. service node build time
  unless (($args[0] eq 'stat') || ($inittime) || ($args[0] eq 'offline')) {
      #dhcp stuff
      my $do_dhcpsetup=1;
      my @entries =  xCAT::TableUtils->get_site_attribute("dhcpsetup");
      my $t_entry = $entries[0];
      if (defined($t_entry) ) {
         if ($t_entry =~ /0|n|N/) { $do_dhcpsetup=0; }
      }
      if ($do_dhcpsetup) {
          foreach my $node (@normalnodeset) {
              if ($request->{'_disparatetftp'}->[0]) { #reading hint from preprocess_command
                  xCAT::MsgUtils->trace($verbose_on_off,"d","petitboot: issue makedhcp request");
                  $sub_req->({command=>['makedhcp'],
                              node=> [$node],
                              arg=>['-l']},$callback);
                              #arg=>['-l','-s','option conf-file \"'.$fpath.'\";']},$callback);
              } else {
                  xCAT::MsgUtils->trace($verbose_on_off,"d","petitboot: issue makedhcp request");                  
                  $sub_req->({command=>['makedhcp'],
                              node=> [$node]}, $callback);
                              #arg=>['-s','option conf-file \"'.$fpath.'\";']},$callback);
              }
          }
      }
  }
  
  #now run the end part of the prescripts
  unless ($args[0] eq 'stat') { # or $args[0] eq 'enact') 
      $errored=0;
      if ($request->{'_disparatetftp'}->[0]) {  #the call is distrubuted to the service node already, so only need to handles my own children
	  xCAT::MsgUtils->trace($verbose_on_off,"d","petitboot: issue runendpre request");
	  $sub_req->({command=>['runendpre'],
		      node=>\@nodes,
		      arg=>[$args[0], '-l']},\&pass_along);
      } else { #nodeset did not distribute to the service node, here we need to let runednpre to distribute the nodes to their masters
	  xCAT::MsgUtils->trace($verbose_on_off,"d","petitboot: issue runendpre request");
	  $sub_req->({command=>['runendpre'],   
		      node=>\@rnodes,
		      arg=>[$args[0]]},\&pass_along);
      }
      if ($errored) { 
	  my $rsp;
	  $rsp->{errorcode}->[0]=1;
	  $rsp->{error}->[0]="Failed in running end prescripts\n";
	  $callback->($rsp);
	  return; 
      }
  }
}

sub getstate {
  my $node = shift;
  my $tftpdir = shift;
  unless ($tftpdir) { $tftpdir = _slow_get_tftpdir($node); }
  if (check_dhcp($node)) {
    if (-r $tftpdir . "/petitboot/".$node) {
      my $fhand;
      open ($fhand,$tftpdir . "/petitboot/".$node);
      my $headline = <$fhand>;
      close $fhand;
      $headline =~ s/^#//;
      chomp($headline);
      return $headline;
    } else {
      return "boot";
    }
  } else {
    return "discover";
  }
}

#----------------------------------------------------------------------------
=head3  getNodesetStates
       returns the nodeset state for the given nodes. The possible nodeset
           states are: netboot, install, boot and discover.
    Arguments:
        nodes  --- a pointer to an array of nodes
        states -- a pointer to a hash table. This hash will be filled by this
             function.The key is the nodeset status and the value is a pointer
             to an array of nodes.
    Returns:
       (return code, error message)
=cut
#-----------------------------------------------------------------------------
sub getNodesetStates {
  my $noderef=shift;
  if ($noderef =~ /xCAT_plugin::petitboot/) {
    $noderef=shift;
  }
  my @nodes=@$noderef;
  my $hashref=shift;
  my $noderestab = xCAT::Table->new('noderes'); #in order to detect per-node tftp directories
  my %nrhash = %{$noderestab->getNodesAttribs(\@nodes,[qw(tftpdir)])};
 
  if (@nodes>0) {
    foreach my $node (@nodes) {
      my $tftpdir;
      if ($nrhash{$node}->[0] and $nrhash{$node}->[0]->{tftpdir}) {
        $tftpdir = $nrhash{$node}->[0]->{tftpdir};
      } else {
         $tftpdir = $globaltftpdir;
      }
      my $tmp=getstate($node, $tftpdir);
      my @a=split(' ', $tmp);
      my $stat = $a[0];
      if (exists($hashref->{$stat})) {
          my $pa=$hashref->{$stat};
          push(@$pa, $node);
      }
      else {
          $hashref->{$stat}=[$node];
      }
    }
  }
  return (0, "");
}

1;
