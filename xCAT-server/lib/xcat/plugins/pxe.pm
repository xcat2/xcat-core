# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::pxe;
use Data::Dumper;
use Sys::Syslog;
use Socket;
use File::Copy;

my $request;
my $callback;
my $dhcpconf = "/etc/dhcpd.conf";
my $tftpdir = "/tftpboot";
#my $dhcpver = 3;

my %usage = (
    "nodeset" => "Usage: nodeset <noderange> [install|shell|boot|runcmd=bmcsetup|netboot|iscsiboot]",
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
  my %bphash = %{shift()};
  my %chainhash = %{shift()};
  my %machash = %{shift()};
  my $kern = $bphash{$node}->[0]; #$bptab->getNodeAttribs($node,['kernel','initrd','kcmdline']);
  if ($kern->{kcmdline} =~ /!myipfn!/) {
      my $ipfn = xCAT::Utils->my_ip_facing($node);
      unless ($ipfn) { return (1,"Unable to identify IP facing client node"); }
      $kern->{kcmdline} =~ s/!myipfn!/$ipfn/;
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
    my $inetn = inet_aton($node);
    unless ($inetn) {
     syslog("local1|err","xCAT unable to resolve IP for $node in pxe plugin");
     return;
    }
  } else { #TODO: actually, should possibly default to xCAT image?
    print $pcfg "LOCALBOOT 0\n";
    close($pcfg);
  }
  my $mactab = xCAT::Table->new('mac'); #to get all the hostnames
  my %ipaddrs;
  unless (inet_aton($node)) {
    syslog("local1|err","xCAT unable to resolve IP in pxe plugin");
    return;
  }
  my $ip = inet_ntoa(inet_aton($node));;
  unless ($ip) {
    syslog("local1|err","xCAT unable to resolve IP in pxe plugin");
    return;
  }
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
   #Assume shared tftp directory for boring people, but for cool people, help sync up tftpdirectory contents when 
   #they specify no sharedtftp in site table
   my $stab = xCAT::Table->new('site');
   my $req = shift;
   my $sent = $stab->getAttribs({key=>'sharedtftp'},'value');
   if ($sent and ($sent->{value} == 0 or $sent->{value} =~ /no/i)) {
      $req->{'_disparatetftp'}=[1];
      return xCAT::Scope->get_broadcast_scope($req,@_);
   }
   return [$req];
}
#sub preprocess_request {
#   my $req = shift;
#   $callback = shift;
#   if ($req->{_xcatdest}) { return [$req]; } #Exit if the packet has been preprocessed in its history
#   my @requests = ({%$req}); #Start with a straight copy to reflect local instance
#   my $sitetab = xCAT::Table->new('site');
#   (my $ent) = $sitetab->getAttribs({key=>'xcatservers'},'value');
#   $sitetab->close;
#   if ($ent and $ent->{value}) {
#      foreach (split /,/,$ent->{value}) {
#         if (xCAT::Utils->thishostisnot($_)) {
#            my $reqcopy = {%$req};
#            $reqcopy->{'_xcatdest'} = $_;
#            push @requests,$reqcopy;
#         }
#      }
#   }
#   return \@requests;
#}
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

sub process_request {
  $request = shift;
  $callback = shift;
  my $sub_req = shift;
  my @args;
  my @nodes;
  my @rnodes;
  if (ref($request->{node})) {
    @rnodes = @{$request->{node}};
  } else {
    if ($request->{node}) { @rnodes = ($request->{node}); }
  }

  my $args_ref = $request->{arg};
  if(scalar grep(/^--version$|^-v$/, @$args_ref)) {
      my $ver = xCAT::Utils->Version();
      my %rsp;
      $rsp{data}->[0]="$ver";
      $callback->(\%rsp);
      return;
  }

  unless (@rnodes) {
      if ($usage{$request->{command}->[0]}) {
          $callback->({data=>$usage{$request->{command}->[0]}});
      }
      return;
  }

  #if not shared, then help sync up
  if ($req->{_disparatetftp}) { #reading hint from preprocess_command
   @nodes = ();
   foreach (@rnodes) {
     if (xCAT::Utils->nodeonmynet($_)) {
        push @nodes,$_;
     }
   }
  } else {
     @nodes = @rnodes;
  }
  
  if (! -r "$tftpdir/pxelinux.0") {
    unless (-r "/usr/lib/syslinux/pxelinux.0" or -r "/usr/share/syslinux/pxelinux.0") {
       $callback->({error=>["Unable to find pxelinux.0 "],errorcode=>[1]});
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
     $callback->({errror=>["Unable to find pxelinux.0 from syslinux"],errorcode=>[1]});
     return;
  }

      
  if (ref($request->{arg})) {
    @args=@{$request->{arg}};
  } else {
    @args=($request->{arg});
  }
  unless ($args[0] eq 'stat' or $args[0] eq 'enact') {
    $sub_req->({command=>['setdestiny'],
           node=>\@nodes,
         arg=>[$args[0]]},\&pass_along);
  }
  if ($errored) { return; }
  #Time to actually configure the nodes, first extract database data with the scalable calls
  my $bptab = xCAT::Table->new('bootparams',-create=>1);
  my $chaintab = xCAT::Table->new('chain');
  my $mactab = xCAT::Table->new('mac'); #to get all the hostnames
  my %bphash = %{$bptab->getNodesAttribs(\@nodes,[qw(kernel initrd kcmdline)])};
  my %chainhash = %{$chaintab->getNodesAttribs(\@nodes,[qw(currstate)])};
  my %machash = %{$mactab->getNodesAttribs(\@nodes,[qw(mac)])};
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
  if ($args[0] ne 'stat') {
    $sub_req->({command=>['makedhcp'],
           node=>\@nodes},$callback);
   }

}


#----------------------------------------------------------------------------
=head3  getNodesetStates
       returns the nodeset state for the given nodes. The possible nodeset
           states are: netboot, install, boot and discover.
    Arguments:
        nodes  --- a pointer to an array of nodes
        states -- a pointer to a hash table. This hash will be filled by this
             function node and key and the nodeset stat as the value. 
    Returns:
       (return code, error message)
=cut
#-----------------------------------------------------------------------------
sub getNodesetStates {
  my $noderef=shift;
  if ($noderef =~ /xCAT_plugin::pxe/) {
    $noderef=shift;
  }
  my @nodes=@$noderef;
  my $hashref=shift; 
  
  if (@nodes>0) {
    foreach my $node (@nodes) {
      my $tmp=getstate($node);
      my @a=split(' ', $tmp);
      $stat = $a[0];
      $hashref->{$node}=$stat;
    }
  }
  return (0, "");
}

1;
