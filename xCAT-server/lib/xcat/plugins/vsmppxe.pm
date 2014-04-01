# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::vsmppxe;
use Data::Dumper;
use Sys::Syslog;
use xCAT::Scope;
use xCAT::Utils;
use xCAT::NetworkUtils;
use Socket;
use File::Copy;
use Getopt::Long;
use xCAT::MsgUtils;
use xCAT::ServiceNodeUtils;
use xCAT::TableUtils;
my $dhcpconf = "/etc/dhcpd.conf";
my $tftpdir = "/tftpboot/vsmp";
#my $dhcpver = 3;

my %usage = (
    "nodeset" => "Usage: nodeset <noderange> [install|shell|boot|runcmd=bmcsetup|netboot|iscsiboot|osimage[=<imagename>]]",
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
    if (-r $tftpdir . "/pxelinux.cfg/".$node) {
      my $fhand;
      open ($fhand,$tftpdir . "/pxelinux.cfg/".$node);
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

  This function will manipulate the pxelinux.cfg structure to match what the noderes/chain tables indicate the node should be booting.

=cut
  my $node = shift;
  my $primarynode = $node;
  $primarynode =~ s/-vsmp$//gm;
  my %bphash = %{shift()};
  my %chainhash = %{shift()};
  my %machash = %{shift()};
  my $kern = $bphash{$node}->[0]; #$bptab->getNodeAttribs($node,['kernel','initrd','kcmdline']);
  if (not $::VSMPPXE_addkcmdlinehandled->{$node} and $kern->{addkcmdline}) {  #Implement the kcmdline append here for
                               #most generic, least code duplication
        $kern->{kcmdline} .= " ".$kern->{addkcmdline};
  }
  if ($kern->{kcmdline} =~ /!myipfn!/) {
      my $ipfn = xCAT::NetworkUtils->my_ip_facing($node);
      unless ($ipfn) {
        my @myself = xCAT::NetworkUtils->determinehostname();
        my $myname = $myself[(scalar @myself)-1];
         $::VSMPPXE_callback->(
                {
                 error => [
                     "$myname: Unable to determine or reasonably guess the image server for $node"
                 ],
                 errorcode => [1]
                }
                );
      }
      $kern->{kcmdline} =~ s/!myipfn!/$ipfn/g;
  }
  my $pcfg;
  open($pcfg,'>',$tftpdir."/pxelinux.cfg/".$node);
  my $cref=$chainhash{$node}->[0]; #$chaintab->getNodeAttribs($node,['currstate']);
  if ($cref->{currstate}) {
    print $pcfg "#".$cref->{currstate}."\n";
  }
  print $pcfg "DEFAULT xCAT\n";
  print $pcfg "LABEL xCAT\n";
  if ($cref and $cref->{currstate} eq "boot") {
    print $pcfg "LOCALBOOT 0\n";
    close($pcfg);
  } elsif ($kern and $kern->{kernel}) {
    if ($kern->{kernel} =~ /!/) {
	my $hypervisor;
	my $kernel;
	($kernel,$hypervisor) = split /!/,$kern->{kernel};
    	print $pcfg " KERNEL mboot.c32\n";
	print $pcfg " APPEND $hypervisor --- $kernel ".$kern->{kcmdline}." --- ".$kern->{initrd}."\n";
    } else {
    #It's time to set pxelinux for this node to boot the kernel..
    print $pcfg " KERNEL ".$kern->{kernel}."\n";
    if ($kern->{initrd} or $kern->{kcmdline}) {
      print $pcfg " APPEND ";
    }
    if ($kern and $kern->{initrd}) {
      print $pcfg "initrd=".$kern->{initrd}." ";
    }
    if ($kern and $kern->{kcmdline}) {
      print $pcfg $kern->{kcmdline}."\n";
    } else {
      print $pcfg "\n";
    }
    }
    close($pcfg);
    my $inetn = inet_aton($primarynode);
    unless ($inetn) {
     syslog("local4|err","xCAT unable to resolve IP for $node in pxe plugin");
     return;
    }
  } else { #TODO: actually, should possibly default to xCAT image?
    print $pcfg "LOCALBOOT 0\n";
    close($pcfg);
  }
  my $mactab = xCAT::Table->new('mac'); #to get all the hostnames
  my %ipaddrs;
  unless (inet_aton($primarynode)) {
    syslog("local4|err","xCAT unable to resolve IP in pxe plugin");
    return;
  }
  my $ip = inet_ntoa(inet_aton($primarynode));;
  unless ($ip) {
    syslog("local4|err","xCAT unable to resolve IP in pxe plugin");
    return;
  }
  $ipaddrs{$ip} = 1;
  if ($mactab) {
     my $ment = $machash{$primarynode}->[0]; #$mactab->getNodeAttribs($node,['mac']);
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
  my $hassymlink = eval { symlink("",""); 1 };
  foreach $ip (keys %ipaddrs) {
   my @ipa=split(/\./,$ip);
   my $pname = sprintf("%02X%02X%02X%02X",@ipa);
   unlink($tftpdir."/pxelinux.cfg/".$pname);
   if ($hassymlink) { 
    symlink($node,$tftpdir."/pxelinux.cfg/".$pname);
   } else {
    link($tftpdir."/pxelinux.cfg/".$node,$tftpdir."/pxelinux.cfg/".$pname);
   }
  }
}
  

    
my $errored = 0;
sub pass_along { 
    my $resp = shift;
    if ($resp and ($resp->{errorcode} and $resp->{errorcode}->[0]) or ($resp->{error} and $resp->{error}->[0])) {
        $errored=1;
    }
    foreach (@{$resp->{node}}) {
       if ($_->{error} or $_->{errorcode}) {
          $errored=1;
       }
       if ($_->{_addkcmdlinehandled}) {
           $::VSMPPXE_addkcmdlinehandled->{$_->{name}->[0]}=1;
           return; #Don't send back to client this internal hint
       }
    }
    $::VSMPPXE_callback->($resp);
}



sub preprocess_request {
   #Assume shared tftp directory for boring people, but for cool people, help sync up tftpdirectory contents when 
   #they specify no sharedtftp in site table
   
   #my $stab = xCAT::Table->new('site');
   my $req = shift;
   if (   (defined($req->{_xcatpreprocessed}))
        && ($req->{_xcatpreprocessed}->[0] == 1))
   {
       return [$req];
   }
 
   my $callback1 = shift;
   my $command = $req->{command}->[0];
   my $sub_req = shift;
   my $nodes = $req->{node};
   my @args=();
   if (ref($req->{arg})) {
       @args=@{$req->{arg}};
    } else { 
        @args=($req->{arg});
    }
    @ARGV = @args;
    Getopt::Long::Configure("bundling");
    Getopt::Long::Configure("pass_through");
    if (!GetOptions('h|?|help' => \$HELP, 'v|version' => \$VERSION) ) {
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

   my @entries =  xCAT::TableUtils->get_site_attribute("sharedtftp");
   my $t_entry = $entries[0];
   if ( defined($t_entry)  and ($t_entry eq "0" or $t_entry eq "no" or $t_entry eq "NO")) {
      # check for  computenodes and servicenodes from the noderange, if so error out
      my @SN;
      my @CN;
      xCAT::ServiceNodeUtils->getSNandCPnodes(\@$nodes, \@SN, \@CN);
      unless (($args[0] eq 'stat') or ($args[0] eq 'enact')) { # mix is ok for these options
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
      if (@CN >0 ) { # if there are compute nodes then broadcast to any servicenodes 
        return xCAT::Scope->get_broadcast_scope($req,@_);
      }
   }
   return [$req];
}

sub process_request {
  $::VSMPPXE_request = shift;
  $::VSMPPXE_callback = shift;
  my $sub_req = shift;
  undef $::VSMPPXE_addkcmdlinehandled;
  my @args;
  my @nodes;
  my @rnodes;
  if (ref($::VSMPPXE_request->{node})) {
    @rnodes = @{$::VSMPPXE_request->{node}};
  } else {
    if ($::VSMPPXE_request->{node}) { 
    	@rnodes = ($::VSMPPXE_request->{node}); 
    }
  }

  unless (@rnodes) {
      if ($usage{$::VSMPPXE_request->{command}->[0]}) {
          $::VSMPPXE_callback->({data=>$usage{$::VSMPPXE_request->{command}->[0]}});
      }
      return;
  }

  #if not shared, then help sync up
  if ($::VSMPPXE_request->{'_disparatetftp'}->[0]) { #reading hint from preprocess_command
   @nodes = ();
   foreach (@rnodes) {
     if (xCAT::NetworkUtils->nodeonmynet($_)) {
        push @nodes,$_;
      } else {
        xCAT::MsgUtils->message("S", "$_: vsmppxe netboot: stop configuration because of none sharedtftp and not on same network with its xcatmaster.");
     }
   }
  } else {
     @nodes = @rnodes;
  }

  # return directly if no nodes in the same network
  unless (@nodes) {
     xCAT::MsgUtils->message("S", "xCAT: vsmppxe netboot: no valid nodes. Stop the operation on this server.");
     return;
  }

  if (ref($::VSMPPXE_request->{arg})) {
      @args=@{$::VSMPPXE_request->{arg}};
  } else {
      @args=($::VSMPPXE_request->{arg});
  }

   #now run the begin part of the prescripts

   unless ($args[0] eq 'stat') { # or $args[0] eq 'enact') {
       $errored=0;
       if ($::VSMPPXE_request->{'_disparatetftp'}->[0]) {  #the call is distrubuted to the service node already, so only need to handles my own children
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
	  $rsp->{error}->[0]="Failed in running begin prescripts\n";
	  $::VSMPPXE_callback->($rsp);
	  return; 
       }
   }
  
#end prescripts code
  # Need to make sure the $tftpdir is actually there ! :)
  if (! -d "$tftpdir") {
    mkdir("$tftpdir",0755);
  }
  # Same for pxelinux.cfg dir
  if (! -d "$tftpdir/pxelinux.cfg") {
    mkdir("$tftpdir/pxelinux.cfg",0755);
  }
  # Since our pxe root is /tftpboot/vsmp we need a way to reference the
  # netboot images.  We do that here by placing a symlink back to the xcat
  # dir in /tftpboot
  if (! -l "$tftpdir/xcat") {
    symlink("/tftpboot/xcat",$tftpdir."/xcat");
  }

  if (! -r "$tftpdir/pxelinux.0") {
    unless (-r "/usr/lib/syslinux/pxelinux.0" or -r "/usr/share/syslinux/pxelinux.0") {
       $::VSMPPXE_callback->({error=>["Unable to find pxelinux.0 "],errorcode=>[1]});
       return;
    }
    if (-r "/usr/lib/syslinux/pxelinux.0") {
       copy("/usr/lib/syslinux/pxelinux.0","$tftpdir/pxelinux.0");
    } else {
       copy("/usr/share/syslinux/pxelinux.0","$tftpdir/pxelinux.0");
     }
     chmod(0644,"$tftpdir/pxelinux.0");
  }
  unless ( -r "$tftpdir/pxelinux.0" ) {
     $::VSMPPXE_callback->({errror=>["Unable to find pxelinux.0 from syslinux"],errorcode=>[1]});
     return;
  }

      
  $errored=0;
  my $inittime=0;
  if (exists($::VSMPPXE_request->{inittime})) { $inittime= $::VSMPPXE_request->{inittime}->[0];}
  if (!$inittime) { $inittime=0;}
  unless ($args[0] eq 'stat') { # or $args[0] eq 'enact') {
    $sub_req->({command=>['setdestiny'],
               node=>\@nodes,
               inittime=>[$inittime],
               arg=>[$args[0]]},\&pass_along);
  }
  if ($errored) { return; }
  #Time to actually configure the nodes, first extract database data with the scalable calls
  my $bptab = xCAT::Table->new('bootparams',-create=>1);
  my $chaintab = xCAT::Table->new('chain');
  my $mactab = xCAT::Table->new('mac'); #to get all the hostnames
  my %bphash = %{$bptab->getNodesAttribs(\@nodes,[qw(kernel initrd kcmdline addkcmdline)])};
  my %chainhash = %{$chaintab->getNodesAttribs(\@nodes,[qw(currstate)])};
  my %machash = %{$mactab->getNodesAttribs(\@nodes,[qw(mac)])};
  foreach (@nodes) {
    my %response;
    $response{node}->[0]->{name}->[0]=$_;
    if ($args[0] eq 'stat') {
      $response{node}->[0]->{data}->[0]= getstate($_);
      $::VSMPPXE_callback->(\%response);
    } elsif ($args[0]) { #If anything else, send it on to the destiny plugin, then setstate
      ($rc,$errstr) = setstate($_,\%bphash,\%chainhash,\%machash);
      if ($rc) {
        $response{node}->[0]->{errorcode}->[0]= $rc;
        $response{node}->[0]->{errorc}->[0]= $errstr;
        $::VSMPPXE_callback->(\%response);
      }
    }
  }

  my $inittime=0;
  if (exists($::VSMPPXE_request->{inittime})) { $inittime= $::VSMPPXE_request->{inittime}->[0];} 
  if (!$inittime) { $inittime=0;}

  #dhcp stuff -- inittime is set when xcatd on sn is started
  unless (($args[0] eq 'stat') || ($inittime)) {
      my $do_dhcpsetup=1;
      #my $sitetab = xCAT::Table->new('site');
      #if ($sitetab) {
          #(my $ref) = $sitetab->getAttribs({key => 'dhcpsetup'}, 'value');
          my @entries =  xCAT::TableUtils->get_site_attribute("dhcpsetup");
          my $t_entry = $entries[0];
          if (defined($t_entry)) {
             if ($t_entry =~ /0|n|N/) { $do_dhcpsetup=0; }
          }
      #}
      
      if ($do_dhcpsetup) {
        if ($::VSMPPXE_request->{'_disparatetftp'}->[0]) { #reading hint from preprocess_command
            $sub_req->({command=>['makedhcp'],arg=>['-l'],
                        node=>\@nodes},$::VSMPPXE_callback);
        } else {
            $sub_req->({command=>['makedhcp'],
                       node=>\@nodes},$::VSMPPXE_callback);
        }
     }  

  }
  #now run the end part of the prescripts
  unless ($args[0] eq 'stat') { # or $args[0] eq 'enact') 
      $errored=0;
      if ($::VSMPPXE_request->{'_disparatetftp'}->[0]) {  #the call is distrubuted to the service node already, so only need to handles my own children
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
	  $::VSMPPXE_callback->($rsp);
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
             function. The key is the nodeset status and the value is a pointer
             to an array of nodes. 
    Returns:
       (return code, error message)
=cut
#-----------------------------------------------------------------------------
sub getNodesetStates {
  my $noderef=shift;
  if ($noderef =~ /xCAT_plugin::vsmppxe/) {
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
