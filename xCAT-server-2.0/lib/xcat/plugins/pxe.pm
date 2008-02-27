# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::pxe;
use Data::Dumper;
use Sys::Syslog;
use Socket;

my $request;
my $callback;
my $dhcpconf = "/etc/dhcpd.conf";
my $tftpdir = "/tftpboot";
#my $dhcpver = 3;

my %usage = (
    "nodeset" => "Usage: nodeset <noderange> [install|shell|boot|runcmd=bmcsetup]",
);
sub handled_commands {
  return {
    nodeset => "noderes:netboot"
  }
}

sub check_dhcp {
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
  my $restab = xCAT::Table->new('noderes');
  my $kern = $restab->getNodeAttribs($node,['kernel','initrd','kcmdline']);
  my $pcfg;
  open($pcfg,'>',$tftpdir."/pxelinux.cfg/".$node);
  my $chaintab = xCAT::Table->new('chain');
  my $cref=$chaintab->getNodeAttribs($node,['currstate']);
  if ($cref->{currstate}) {
    print $pcfg "#".$cref->{currstate}."\n";
  }
  print $pcfg "DEFAULT xCAT\n";
  print $pcfg "LABEL xCAT\n";
  $chaintab = xCAT::Table->new('chain');
  my $stref = $chaintab->getNodeAttribs($node,['currstate']);
  if ($stref and $stref->{currstate} eq "boot") {
    print $pcfg "LOCALBOOT 0\n";
    close($pcfg);
  } elsif ($kern and $kern->{kernel}) {
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
  my $ip = inet_ntoa(inet_aton($node));;
  unless ($ip) {
    syslog("local1|err","xCAT unable to resolve IP in pxe plugin");
    return;
  }
  my @ipa=split(/\./,$ip);
  my $pname = sprintf("%02X%02X%02X%02X",@ipa);
  unlink($tftpdir."/pxelinux.cfg/".$pname);
  link($tftpdir."/pxelinux.cfg/".$node,$tftpdir."/pxelinux.cfg/".$pname);
}
  

    
my $errored = 0;
sub pass_along { 
    my $resp = shift;
    $callback->($resp);
    if ($resp and $resp->{errorcode} and $resp->{errorcode}->[0]) {
        $errored=1;
    }
}




sub preprocess_request {
   my $req = shift;
   $callback = shift;
   if ($req->{_xcatdest}) { return [$req]; } #Exit if the packet has been preprocessed in its history
   my @requests = ({%$req}); #Start with a straight copy to reflect local instance
   my $sitetab = xCAT::Table->new('site');
   (my $ent) = $sitetab->getAttribs({key=>'xcatservers'},'value');
   $sitetab->close;
   if ($ent and $ent->{value}) {
      foreach (split /,/,$ent->{value}) {
         if (xCAT::Utils->thishostisnot($_)) {
            my $reqcopy = {%$req};
            $reqcopy->{'_xcatdest'} = $_;
            push @requests,$reqcopy;
         }
      }
   }
   return \@requests;
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
  unless (@rnodes) {
      if ($usage{$request->{command}->[0]}) {
          $callback->({data=>$usage{$request->{command}->[0]}});
      }
      return;
  }
  @nodes = ();
  foreach (@rnodes) {
     if (xCAT::Utils->nodeonmynet($_)) {
        push @nodes,$_;
     }
  }
  if (! -r "$tftpdir/pxelinux.0") {
     unless (-r "/usr/lib/syslinux/pxelinux.0") {
       $callback->({error=>["Unable to find pxelinux.0 "],errorcode=>[1]});
       return;
     }
     copy("/usr/lib/syslinux/pxelinux.0","$tftpdir/pxelinux.0");
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
  foreach (@nodes) {
    my %response;
    $response{node}->[0]->{name}->[0]=$_;
    if ($args[0] eq 'stat') {
      $response{node}->[0]->{data}->[0]= getstate($_);
      $callback->(\%response);
    } elsif ($args[0] eq 'enact') {
      setstate($_);
    } elsif ($args[0]) { #If anything else, send it on to the destiny plugin, then setstate
      setstate($_);
    }
  }
}


1;
