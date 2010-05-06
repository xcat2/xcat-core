# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::yaboot;
use Data::Dumper;
use Sys::Syslog;
use xCAT::Scope;
use File::Path;
use Socket;
use Getopt::Long;

my $request;
my %breaknetbootnodes;
my %normalnodes;
my $callback;
my $sub_req;
my $dhcpconf = "/etc/dhcpd.conf";
my $tftpdir = "/tftpboot";
#my $dhcpver = 3;

my %usage = (
    "nodeset" => "Usage: nodeset <noderange> [install|shell|boot|runcmd=bmcsetup|netboot|iscsiboot|osimage=<imagename>]",
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

sub getstate {
  my $node = shift;
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
  my $kern = $bphash{$node}->[0]; #$bptab->getNodeAttribs($node,['kernel','initrd','kcmdline']);
  if ($kern->{kcmdline} =~ /!myipfn!/) {
      my $ipfn = xCAT::Utils->my_ip_facing($node);
      unless ($ipfn) {
        my @myself = xCAT::Utils->determinehostname();
        my $myname = $myself[(scalar @myself)-1];
         $callback->(
                {
                 error => [
                     "$myname: Unable to determine the image server for $node"
                 ],
                 errorcode => [1]
                }
                );
      }
      $kern->{kcmdline} =~ s/!myipfn!/$ipfn/;
  }
  if ($kern->{addkcmdline}) {
      $kern->{kcmdline} .= " ".$kern->{addkcmdline};
  }
  my $pcfg;
  unless (-d "$tftpdir/etc") {
     mkpath("$tftpdir/etc");
  }
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
    my $inetn = inet_aton($node);
    unless ($inetn) {
     syslog("local1|err","xCAT unable to resolve IP for $node in yaboot plugin");
     return;
    }
  } else { #TODO: actually, should possibly default to xCAT image?
    print $pcfg "bye\n";
    close($pcfg);
  }
  my $ip = inet_ntoa(inet_aton($node));;
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
              if (inet_aton($1)) {
               $ipaddrs{inet_ntoa(inet_aton($1))} = 1;
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
   #special case for sles 11
   my $mac = lc($machash{$node}->[0]->{mac});
   $mac =~ s/!.*//;
   $mac =~ s/|.*//;
   if (! (grep /\:/, $mac) ) {
      $mac =~ s/(..)(..)(..)(..)(..)(..)/$1:$2:$3:$4:$5:$6/;
   }
   my @mac_substr = split /\:/, $mac;
   my $sles_yaboot_link = sprintf("yaboot.conf-%s-%s-%s-%s-%s-%s", @mac_substr);
   unlink($tftpdir."/etc/".$pname);
   link($tftpdir."/etc/".$node,$tftpdir."/etc/".$pname);

   # Add the yaboot.conf-%s-%s-%s-%s-%s-%s for both the rh and sles
   unlink($tftpdir . "/" . $sles_yaboot_link);
   link($tftpdir."/etc/".$node, $tftpdir . '/' . $sles_yaboot_link);
  }
}
  

    
my $errored = 0;
sub pass_along { 
    print "pass_along\n";
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
     }
   }
  } else {
     @nodes = @rnodes;
  }
  #print "nodes=@nodes\nrnodes=@rnodes\n";

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
      if ($errored) { return; }
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
  my $mactab=xCAT::Table->new('mac',-create=>1);
  my $machash=$mactab->getNodesAttribs(\@nodes,['mac']);
  my $rc;
  my $errstr;

  foreach (@nodes) {
    my %response;
    $response{node}->[0]->{name}->[0]=$_;
    if ($args[0] eq 'stat') {
      $response{node}->[0]->{data}->[0]= getstate($_);
      $callback->(\%response);
    } elsif ($args[0]) { #If anything else, send it on to the destiny plugin, then setstate
      ($rc,$errstr) = setstate($_,$bphash,$chainhash,$machash);
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
      if ($errored) { return; }
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
  
  if (@nodes>0) {
    foreach my $node (@nodes) {
      my $tmp=getstate($node);
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
