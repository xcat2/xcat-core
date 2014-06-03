# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::yaboot;
use Data::Dumper;
use Sys::Syslog;
use xCAT::Scope;
use xCAT::NetworkUtils;
use xCAT::MsgUtils;
use File::Path;
use Socket;
use Getopt::Long;

my $request;
my %breaknetbootnodes;
my %normalnodes;
my $callback;
my $sub_req;
my $dhcpconf = "/etc/dhcpd.conf";
my $globaltftpdir = xCAT::Utils->getTftpDir();
#my $dhcpver = 3;

my %usage = (
    "nodeset" => "Usage: nodeset <noderange> [install|shell|boot|runcmd=bmcsetup|netboot|iscsiboot|osimage=<imagename>|offline]",
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
    my $node = shift;
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
  my $kern = $bphash{$node}->[0]; #$bptab->getNodeAttribs($node,['kernel','initrd','kcmdline']);
  if ($kern->{kcmdline} =~ /!myipfn!/) {
      my $ipfn = xCAT::Utils->my_ip_facing($node);
      unless ($ipfn) {
          my $servicenodes = $nrhash{$node}->[0];
          if ($servicenodes and $servicenodes->{servicenode}) {
              my @sns = split /,/, $servicenodes->{servicenode};
              foreach my $sn ( @sns ) {
                  # We are in the service node pools, print error if no facing ip.
                  if (xCAT::InstUtils->is_me($sn)) {
                      my @myself = xCAT::Utils->determinehostname();
                      my $myname = $myself[(scalar @myself)-1];
                      $callback->(
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
              $callback->(
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
  my $pcfg;
  unless (-d "$tftpdir/etc") {
     mkpath("$tftpdir/etc");
  }

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
                $kcmdline =~ s/(.*ifname=.*):@macs->[0].*( netdev.*)/$1:$mac$2/g;
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
   #they specify no sharedtftp in site table
   my $stab = xCAT::Table->new('site');
  
   my $sent = $stab->getAttribs({key=>'sharedtftp'},'value');
   if ($sent and ($sent->{value} == 0 or $sent->{value} =~ /no/i)) {
      $req->{'_disparatetftp'}=[1];
      if ($req->{inittime}->[0]) {
          return [$req];
      }
      return xCAT::Scope->get_broadcast_scope($req,@_);
   }
   return [$req];
}
#sub preprocess_request {
#   my $req = shift;
#   my $callback = shift;
#  my %localnodehash;
#  my %dispatchhash;
#  my $nrtab = xCAT::Table->new('noderes');
#  foreach my $node (@{$req->{node}}) {
#     my $nodeserver;
#     my $tent = $nrtab->getNodeAttribs($node,['tftpserver']);
#     if ($tent) { $nodeserver = $tent->{tftpserver} }
#     unless ($tent and $tent->{tftpserver}) {
#        $tent = $nrtab->getNodeAttribs($node,['servicenode']);
#        if ($tent) { $nodeserver = $tent->{servicenode} }
#     }
#     if ($nodeserver) {
#        $dispatchhash{$nodeserver}->{$node} = 1;
#     } else {
#        $localnodehash{$node} = 1;
#     }
#  }
#  my @requests;
#  my $reqc = {%$req};
#  $reqc->{node} = [ keys %localnodehash ];
#  if (scalar(@{$reqc->{node}})) { push @requests,$reqc }
#
#  foreach my $dtarg (keys %dispatchhash) { #iterate dispatch targets
#     my $reqcopy = {%$req}; #deep copy
#     $reqcopy->{'_xcatdest'} = $dtarg;
#     $reqcopy->{node} = [ keys %{$dispatchhash{$dtarg}}];
#     push @requests,$reqcopy;
#  }
#  return \@requests;
#}
#


sub process_request {
  $request = shift;
  $callback = shift;
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
     if (xCAT::Utils->nodeonmynet($_)) {
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
	  $rsp->{error}->[0]="Failed in running begin prescripts.  Processing will still continue.\n";
	  $callback->($rsp);
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
		arg=>[$args[0]]},\&pass_along);
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
  my $rc;
  my $errstr;

  foreach (@nodes) {
    my %response;
    my $tftpdir;
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
      ($rc,$errstr) = setstate($_,$bphash,$chainhash,$machash,$tftpdir,$nrhash);
      if ($rc) {
        $response{node}->[0]->{errorcode}->[0]= $rc;
        $response{node}->[0]->{errorc}->[0]= $errstr;
        $callback->(\%response);
      }
    }
  }

  my @normalnodeset = keys %normalnodes;
  my @breaknetboot=keys %breaknetbootnodes;
  #print "yaboot:inittime=$inittime; normalnodeset=@normalnodeset; breaknetboot=@breaknetboot\n";

  #Don't bother to try dhcp binding changes if sub_req not passed, i.e. service node build time
  unless (($args[0] eq 'stat') || ($inittime) || ($args[0] eq 'offline')) {
      #dhcp stuff
      my $do_dhcpsetup=1;
      my $sitetab = xCAT::Table->new('site');
      if ($sitetab) {
          (my $ref) = $sitetab->getAttribs({key => 'dhcpsetup'}, 'value');
          if ($ref) {
             if ($ref->{value} =~ /0|n|N/) { $do_dhcpsetup=0; }
          }
      }

      if ($do_dhcpsetup) {
         if ($request->{'_disparatetftp'}->[0]) { #reading hint from preprocess_command, only change local settings if already farmed
	     $sub_req->({command=>['makedhcp'],arg=>['-l'],
		        node=>\@normalnodeset},$callback);
         } else {
	     $sub_req->({command=>['makedhcp'],
		      node=>\@normalnodeset},$callback);
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
	  $rsp->{error}->[0]="Failed in running end prescripts.  Processing will still continue.\n";
	  $callback->($rsp);
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
