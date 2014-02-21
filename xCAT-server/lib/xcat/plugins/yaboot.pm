# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::yaboot;
use Data::Dumper;
use Sys::Syslog;
use xCAT::Scope;
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::ServiceNodeUtils;
use xCAT::NetworkUtils;
use xCAT::MsgUtils;
use File::Path;
use Socket;
use Getopt::Long;
use xCAT::Table;

my $request;
my %breaknetbootnodes;
our %normalnodes;
my $callback;
my $sub_req;
my $dhcpconf = "/etc/dhcpd.conf";
my $globaltftpdir = xCAT::TableUtils->getTftpDir();
#my $dhcpver = 3;

my %usage = (
    "nodeset" => "Usage: nodeset <noderange> [install|shell|boot|runcmd=bmcsetup|netboot|iscsiboot|osimage[=<imagename>]|offline]",
);
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
    if (-r $tftpdir . "/etc/".$node) {
      my $fhand;
      open ($fhand,$tftpdir . "/etc/".$node);
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
  if ($kern->{kcmdline} =~ /!myipfn!/) {
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
  unless (-d "$tftpdir/etc") {
     mkpath("$tftpdir/etc");
  }
  my $nodemac;
  my %client_nethash = xCAT::DBobjUtils->getNetwkInfo( [$node] );
  if ( $client_nethash{$node}{mgtifname} =~ /hf/ ) {
    my $mactab = xCAT::Table->new('mac');
    if ($mactab) {
      my $ment = $machash{$node}->[0]; #$mactab->getNodeAttribs($node,['mac']);
      if ($ment and $ment->{mac}) {
        my @macs = split(/\|/,$ment->{mac});
        my $count = 0;
        foreach my $mac (@macs) {
          if ( $mac !~ /!(.*)/) {
            my $hostname;
            if ( $node !~ /^(.*)-hf(.*)$/ ) {
                $hostname = $node . "-hf" . $count;
            } else {
                $hostname = $1 . "-hf" . $count;
            }
            open($pcfg,'>',$tftpdir."/etc/".$hostname);
            my $cref=$chainhash{$node}->[0]; #$chaintab->getNodeAttribs($node,['currstate']);
            if ($cref->{currstate}) {
              print $pcfg "#".$cref->{currstate}."\n";
            }

            print $pcfg "timeout=5\n";
            $normalnodes{$node}=1;
            if ($cref and $cref->{currstate} eq "boot") {
              $breaknetbootnodes{$node}=1;
              delete $normalnodes{$node}; #Signify to omit this from one makedhcp command
              #$sub_req->({command=>['makedhcp'], #batched elsewhere, this code is stale, hopefully
              #       node=>[$node],
              #        arg=>['-s','filename = \"xcat/nonexistant_file_to_intentionally_break_netboot_for_localboot_to_work\";']},$callback);
              print $pcfg "bye\n";
              close($pcfg);
            } elsif ($kern and $kern->{kernel}) {
              #It's time to set yaboot for this node to boot the kernel..
              print $pcfg "image=".$kern->{kernel}."\n\tlabel=xcat\n";
              if ($kern and $kern->{initrd}) {
                print $pcfg "\tinitrd=".$kern->{initrd}."\n";
              }
              if ($kern and $kern->{kcmdline}) {
                my $kcmdline = $kern->{kcmdline};
                $kcmdline =~ s/(.*ifname=.*):@macs[0].*( netdev.*)/$1:$mac$2/g;
                print $pcfg "\tappend=\"".$kcmdline."\"\n";
              }
              close($pcfg);
              my $inetn = xCAT::NetworkUtils->getipaddr($node);
              unless ($inetn) {
               syslog("local1|err","xCAT unable to resolve IP for $node in yaboot plugin");
               return;
              }
            } else { #TODO: actually, should possibly default to xCAT image?
              print $pcfg "bye\n";
              close($pcfg);
            }

            if ($mac =~ /:/) {
              $nodemac = $mac;
              my $tmp = $mac;
              $tmp =~ s/(..):(..):(..):(..):(..):(..)/$1-$2-$3-$4-$5-$6/g;
              my $pname = "25-" . $tmp;
              unlink($tftpdir."/etc/".$pname);
              link($tftpdir."/etc/".$hostname,$tftpdir."/etc/".$pname);
            }
          }
          $count = $count + 2;
        }
      }
    }


  } else {

    open($pcfg,'>',$tftpdir."/etc/".$node);
    my $cref=$chainhash{$node}->[0]; #$chaintab->getNodeAttribs($node,['currstate']);
    if ($cref->{currstate}) {
      print $pcfg "#".$cref->{currstate}."\n";
    }
    print $pcfg "timeout=5\n";
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
      print $pcfg "bye\n";
      close($pcfg);
    } elsif ($kern and $kern->{kernel}) {
      #It's time to set yaboot for this node to boot the kernel..
      print $pcfg "image=".$kern->{kernel}."\n\tlabel=xcat\n";
      if ($kern and $kern->{initrd}) {
        print $pcfg "\tinitrd=".$kern->{initrd}."\n";
      }
      if ($kern and $kern->{kcmdline}) {
        print $pcfg "\tappend=\"".$kern->{kcmdline}."\"\n";
      }
      close($pcfg);
      my $inetn = xCAT::NetworkUtils->getipaddr($node);
      unless ($inetn) {
       syslog("local1|err","xCAT unable to resolve IP for $node in yaboot plugin");
       return;
      }
    } else { #TODO: actually, should possibly default to xCAT image?
      print $pcfg "bye\n";
      close($pcfg);
    }
    my $ip = xCAT::NetworkUtils->getipaddr($node);
    unless ($ip) {
      syslog("local1|err","xCAT unable to resolve IP in yaboot plugin");
      return;
    }
    my $mactab = xCAT::Table->new('mac');
    my %ipaddrs;
    $ipaddrs{$ip} = 1;
    if ($mactab) {
      my $ment = $machash{$node}->[0]; #$mactab->getNodeAttribs($node,['mac']);
      if ($ment and $ment->{mac}) {
        my @macs = split(/\|/,$ment->{mac});
        foreach (@macs) {
           $nodemac = $_;
           if (/!(.*)/) {
              my $ipaddr = xCAT::NetworkUtils->getipaddr($1);
              if ($ipaddr) {
               $ipaddrs{$ipaddr} = 1;
              }
           }
        }
      }
    }
    # Do not use symbolic link, p5 does not support symbolic link in /tftpboot
    #  my $hassymlink = eval { symlink("",""); 1 };
    foreach $ip (keys %ipaddrs) {
      my @ipa=split(/\./,$ip);
      my $pname = sprintf("%02x%02x%02x%02x",@ipa);
      unlink($tftpdir."/etc/".$pname);
      link($tftpdir."/etc/".$node,$tftpdir."/etc/".$pname);
    }
  }
  if ($nodemac =~ /:/) {
      my $tmp = $nodemac;
      $tmp =~ s/(..):(..):(..):(..):(..):(..)/$1-$2-$3-$4-$5-$6/g;
      my $pname = "yaboot.conf-" . $tmp;
      unlink($tftpdir."/".$pname);
      link($tftpdir."/etc/".$node,$tftpdir."/".$pname); 
  }
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
    Getopt::Long::Configure("bundling");
    Getopt::Long::Configure("pass_through");
    if (!GetOptions('h|?|help'  => \$HELP, 'v|version' => \$VERSION) ) {
      if($usage{$command}) {
          my %rsp;
          $rsp{data}->[0]=$usage{$command};
          $callback1->(\%rsp);
      }
      return;
    }

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
   
   if ( defined($t_entry)  and ($t_entry eq "0" or $t_entry eq "no" or $t_entry eq "NO")) {
      # check for  computenodes and servicenodes from the noderange, if so error out
      my @SN;
      my @CN;
      xCAT::ServiceNodeUtils->getSNandCPnodes(\@$nodes, \@SN, \@CN);
      unless (($args[0] eq 'stat') or ($args[0] eq 'enact')) {
        if ((@SN > 0) && (@CN >0 )) { # there are both SN and CN
            my $rsp;
            $rsp->{data}->[0] = 
              "Nodeset was run with a noderange containing both service nodes and compute nodes. This is not valid. You must submit with either compute nodes in the noderange or service nodes. \n";
            xCAT::MsgUtils->message("E", $rsp, $callback1);       
            return; 
           
        } 
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

  my @args;
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
        xCAT::MsgUtils->message("S", "$_: yaboot netboot: stop configuration because of none sharedtftp and not on same network with its xcatmaster.");
     }
   }
  } else {
     @nodes = @rnodes;
  }

  # return directly if no nodes in the same network
  unless (@nodes) {
     xCAT::MsgUtils->message("S", "xCAT: yaboot netboot: no valid nodes. Stop the operation on this server.");
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
	  $sub_req->({command=>['runbeginpre'],
		      node=>\@nodes,
		      arg=>[$args[0], '-l']},\&pass_along);
      } else { #nodeset did not distribute to the service node, here we need to let runednpre to distribute the nodes to their masters
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
    $sub_req->({command=>['setdestiny'],
		node=>\@nodes,
		inittime=>[$inittime],
		arg=>\@args},\&pass_along);
  }
  if ($errored) { return; }

  my $bptab=xCAT::Table->new('bootparams',-create=>1);
  my $bphash = $bptab->getNodesAttribs(\@nodes,['kernel','initrd','kcmdline','addkcmdline']);
  my $chaintab=xCAT::Table->new('chain',-create=>1);
  my $chainhash=$chaintab->getNodesAttribs(\@nodes,['currstate']);
  my $noderestab=xCAT::Table->new('noderes',-create=>1);
  my $nodereshash=$noderestab->getNodesAttribs(\@nodes,['tftpdir']);
  my $mactab=xCAT::Table->new('mac',-create=>1);
  my $machash=$mactab->getNodesAttribs(\@nodes,['mac']);
  my $nrtab=xCAT::Table->new('noderes',-create=>1);
  my $nrhash=$nrtab->getNodesAttribs(\@nodes,['servicenode']);
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
      my $linuximghash=undef;
      unless($osimgname =~ /^(install|netboot|statelite)$/){
        $linuximghash = $linuximgtab->getAttribs({imagename => $osimgname}, 'boottarget', 'addkcmdline');
      }      

      ($rc,$errstr) = setstate($_,$bphash,$chainhash,$machash,$tftpdir,$nrhash,$linuximghash);
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
        if($osimage =~ /^(install|netboot|statelite)$/){
           $osimage=($ent->{'os'}).'-'.($ent->{'arch'}).'-'.($ent->{'provmethod'}).'-'.($ent->{'profile'});
        }
        push @{$osimagenodehash{$osimage}}, $nn;
        
    }

    foreach my $osimage (keys %osimagenodehash) {
        my $osimgent = $osimagetab->getAttribs({imagename => $osimage },'osvers');       
        my $os = $osimgent->{'osvers'};    

        my $osv;
        my $osn;
        my $osm;
        if ($os =~ /(\D+)(\d+)\.(\d+)/) {
            $osv = $1;
            $osn = $2;
            $osm = $3;
        
        } elsif ($os =~ /(\D+)(\d+)/){
            $osv = $1;
            $osn = $2;
            $osm = 0;   
        }
    
        if (($osv =~ /rh/ and int($osn) < 6) or 
            ($osv =~ /sles/ and int($osn) < 11)) {
            # check if yaboot-xcat installed
            my $yf = $tftpdir . "/yaboot";
            unless (-e $yf) {
                my $rsp;
                push @{$rsp->{data}},
                  "stop configuration because yaboot-xcat need to be installed for $os.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);       
                return; 
              }
        } elsif (($osv =~ /rh/ and int($osn) >= 6) or
                 ($osv =~ /sles/ and int($osn) >= 11)) {
            # copy yaboot from cn's repository
            my $cmd = '/usr/bin/rsync';
            if (!-f $cmd || !-x $cmd) {  
                my $rsp;
                push @{$rsp->{data}},
                  "stop configuration because rsync does not exist or is not executable.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);            
                return;
           }      
            my $yabootpath = $tftpdir."/yb/".$os;
            mkpath $yabootpath;     

            my $linuximgent = $linuximgtab->getAttribs({imagename => $osimage},'pkgdir');
            my @pkgdirlist = split  /,/, $linuximgent->{'pkgdir'};
            my $pkgdir = $pkgdirlist[0];
            $pkgdir =~ s/\/+$//;            
                   

            my $yabootfile;   
            if ($os =~ /sles/) {
                $yabootfile = $pkgdir."/1/suseboot/yaboot";
            } elsif ($os =~ /rh/){
                $yabootfile = $pkgdir."/ppc/chrp/yaboot";
            }  
            unless (-e "$yabootfile") {
                my $rsp;
                push @{$rsp->{data}},
                  "stop configuration because Unable to find the os shipped yaboot file.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return; 
              }          

            $cmd = $cmd." ".$yabootfile." ".$yabootpath; #???
            ($rc,$errstr) = xCAT::Utils->runcmd($cmd, 0);
            if ($rc)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "stop configuration because $synccmd failed.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
               return; 
            } 
        }
    } #end of foreach osimagenodehash
  
  #Don't bother to try dhcp binding changes if sub_req not passed, i.e. service node build time
  unless (($args[0] eq 'stat') || ($inittime) || ($args[0] eq 'offline')) {
      #dhcp stuff
      my $do_dhcpsetup=1;
      #my $sitetab = xCAT::Table->new('site');
      #if ($sitetab) {
          #(my $ref) = $sitetab->getAttribs({key => 'dhcpsetup'}, 'value');
          my @entries =  xCAT::TableUtils->get_site_attribute("dhcpsetup");
          my $t_entry = $entries[0];
          if (defined($t_entry) ) {
             if ($t_entry =~ /0|n|N/) { $do_dhcpsetup=0; }
          }
      #}

      if ($do_dhcpsetup) {
        if (%osimagenodehash) {
            foreach my $osimage (keys %osimagenodehash) {
                my $osimgent = $osimagetab->getAttribs({imagename => $osimage },'osvers');
                my $osentry = $osimgent->{'osvers'};

                my $osv;
                my $osn;
                my $osm;
                if ($osentry =~ /(\D+)(\d+)\.(\d+)/) {
                    $osv = $1;
                    $osn = $2;
                    $osm = $3;
                
                } elsif ($osentry =~ /(\D+)(\d+)/){
                    $osv = $1;
                    $osn = $2;
                    $osm = 0;   
                }
                if (($osv =~ /rh/ and int($osn) >= 6) or 
                    ($osv =~ /sles/ and int($osn) >= 11)) {
                    my $fpath = "/yb/". $osentry."/yaboot"; 
                    if ($request->{'_disparatetftp'}->[0]) { #reading hint from preprocess_command
                    $sub_req->({command=>['makedhcp'],
                         node=>\@{$osimagenodehash{$osimage}},
                         arg=>['-l','-s','filename = \"'.$fpath.'\";']},$callback);
                    } else {
                    $sub_req->({command=>['makedhcp'],
                         node=>\@{$osimagenodehash{$osimage}},
                         arg=>['-s','filename = \"'.$fpath.'\";']},$callback);
                    }
                } else {
                    if ($request->{'_disparatetftp'}->[0]) { #reading hint from preprocess_command, only change local settings if already farmed
                    $sub_req->({command=>['makedhcp'],arg=>['-l'],
                           node=>\@{$osimagenodehash{$osimage}}},$callback);
                    } else {
                    $sub_req->({command=>['makedhcp'],
                         node=>\@{$osimagenodehash{$osimage}}},$callback);
                    }
                }
            }
        } else {
            if ($request->{'_disparatetftp'}->[0]) { #reading hint from preprocess_command, only change local settings if already farmed
            $sub_req->({command=>['makedhcp'],arg=>['-l'],
                   node=>\@normalnodeset},$callback);
            } else {
            $sub_req->({command=>['makedhcp'],
                 node=>\@normalnodeset},$callback);
            }
        }
        if ($request->{'_disparatetftp'}->[0]) { #reading hint from preprocess_command
            $sub_req->({command=>['makedhcp'],
             node=>\@breaknetboot,
             arg=>['-l','-s','filename = \"xcat/nonexistant_file_to_intentionally_break_netboot_for_localboot_to_work\";']},$callback);
        } else {
            $sub_req->({command=>['makedhcp'],
             node=>\@breaknetboot,
             arg=>['-s','filename = \"xcat/nonexistant_file_to_intentionally_break_netboot_for_localboot_to_work\";']},$callback);
        }
     }
  }
  
  #now run the end part of the prescripts
  unless ($args[0] eq 'stat') { # or $args[0] eq 'enact') 
      $errored=0;
      if ($request->{'_disparatetftp'}->[0]) {  #the call is distrubuted to the service node already, so only need to handles my own children
	  $sub_req->({command=>['runendpre'],
		      node=>\@nodes,
		      arg=>[$args[0], '-l']},\&pass_along);
      } else { #nodeset did not distribute to the service node, here we need to let runednpre to distribute the nodes to their masters
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
  if ($noderef =~ /xCAT_plugin::yaboot/) {
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
      $stat = $a[0];
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
