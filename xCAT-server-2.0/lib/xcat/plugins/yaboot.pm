# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::yaboot;
use Data::Dumper;
use Sys::Syslog;
use Socket;

my $request;
my $callback;
my $sub_req;
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
  my $restab = xCAT::Table->new('noderes');
  my $kern = $restab->getNodeAttribs($node,['kernel','initrd','kcmdline']);
  my $pcfg;
  open($pcfg,'>',$tftpdir."/etc/".$node);
  my $chaintab = xCAT::Table->new('chain');
  my $cref=$chaintab->getNodeAttribs($node,['currstate']);
  if ($cref->{currstate}) {
    print $pcfg "#".$cref->{currstate}."\n";
  }
  print $pcfg "timeout=5\n";
  #print $pcfg "LABEL xCAT\n";
  my $chaintab = xCAT::Table->new('chain');
  my $stref = $chaintab->getNodeAttribs($node,['currstate']);
    $sub_req->({command=>['makedhcp'],
           node=>[$node]},$callback);
  if ($stref and $stref->{currstate} eq "boot") {
    #TODO use omapi to set the filename so no netboot is attempted?
    $sub_req->({command=>['makedhcp'],
           node=>[$node],
            arg=>['-s','filename = \"xcat/nonexistant_file_to_intentionally_break_netboot_for_localboot_to_work\";']},$callback);
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
  my @ipa=split(/\./,$ip);
  my $pname = sprintf("%02x%02x%02x%02x",@ipa);
  unlink($tftpdir."/etc/".$pname);
  link($tftpdir."/etc/".$node,$tftpdir."/etc/".$pname);
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
   my $callback = shift;
  my %localnodehash;
  my %dispatchhash;
  my $nrtab = xCAT::Table->new('noderes');
  foreach my $node (@{$req->{node}}) {
     my $nodeserver;
     my $tent = $nrtab->getNodeAttribs($node,['tftpserver']);
     if ($tent) { $nodeserver = $tent->{tftpserver} }
     unless ($tent and $tent->{tftpserver}) {
        $tent = $nrtab->getNodeAttribs($node,['servicenode']);
        if ($tent) { $nodeserver = $tent->{servicenode} }
     }
     if ($nodeserver) {
        $dispatchhash{$nodeserver}->{$node} = 1;
     } else {
        $localnodehash{$node} = 1;
     }
  }
  my @requests;
  my $reqc = {%$req};
  $reqc->{node} = [ keys %localnodehash ];
  if (scalar(@{$reqc->{node}})) { push @requests,$reqc }

  foreach my $dtarg (keys %dispatchhash) { #iterate dispatch targets
     my $reqcopy = {%$req}; #deep copy
     $reqcopy->{'_xcatdest'} = $dtarg;
     $reqcopy->{node} = [ keys %{$dispatchhash{$dtarg}}];
     push @requests,$reqcopy;
  }
  return \@requests;
}



sub process_request {
  $request = shift;
  $callback = shift;
  $sub_req = shift;
  my @args;
  my @nodes;
  if (ref($request->{node})) {
    @nodes = @{$request->{node}};
  } else {
    if ($request->{node}) { @nodes = ($request->{node}); }
  }
  unless (@nodes) {
      if ($usage{$request->{command}->[0]}) {
          $callback->({data=>$usage{$request->{command}->[0]}});
      }
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
