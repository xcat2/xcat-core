# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::pxe;
use Data::Dumper;
use Sys::Syslog;
use xCAT::Scope;
use xCAT::MsgUtils;
use Socket;
use File::Copy;
use File::Path;
use Getopt::Long;
require xCAT::Utils;
require xCAT::TableUtils;
use xCAT::ServiceNodeUtils;
my $dhcpconf = "/etc/dhcpd.conf";
my $globaltftpdir = xCAT::TableUtils->getTftpDir();
#my $dhcpver = 3;

my %usage = (
    "nodeset" => "Usage: nodeset <noderange> [shell|boot|runcmd=bmcsetup|iscsiboot|osimage[=<imagename>]|offline]",
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
  my %nthash = %{shift()};
  my $tftpdir = shift;
  my %linuximghash = ();
  my $linuximghashref = shift;
  if (ref $linuximghashref) { %linuximghash = %{$linuximghashref}; }
  my $imgaddkcmdline=($linuximghash{'boottarget'})? undef:$linuximghash{'addkcmdline'};

  my $kern = $bphash{$node}->[0]; #$bptab->getNodeAttribs($node,['kernel','initrd','kcmdline']);
  if (not $::PXE_addkcmdlinehandled->{$node} and ($kern->{addkcmdline} or  ($imgaddkcmdline))) {

#Implement the kcmdline append here for
#most generic, least code duplication

###hack start
# This is my comment. There are many others like it, but this one is mine.
# My comment is my best friend. It is my life. I must master it as I must master my life.
# Without me, my comment is useless. Without my comment, I am useless.

# Jarrod to clean up.  It really should be in Table.pm and support
# the new statelite $table notation.

#I dislike spaces, tabs are cleaner, I'm too tired to change all the xCAT code.
#I give in.

    my $kcmdlinehack = ($imgaddkcmdline)?$kern->{addkcmdline}." ".$imgaddkcmdline : $kern->{addkcmdline};

    my $cmdhashref;
    if($kcmdlinehack){
       $cmdhashref=xCAT::Utils->splitkcmdline($kcmdlinehack);
    }

    if($cmdhashref and $cmdhashref->{volatile})
    {
       $kcmdlinehack=$cmdhashref->{volatile};
    }    


    while ($kcmdlinehack =~ /#NODEATTRIB:([^:#]+):([^:#]+)#/) {
        my $natab = xCAT::Table->new($1);
        my $naent = $natab->getNodeAttribs($node,[$2]);
        my $naval = $naent->{$2};
        $kcmdlinehack =~ s/#NODEATTRIB:([^:#]+):([^:#]+)#/$naval/;
    }
    while ($kcmdlinehack =~ /#TABLE:([^:#]+):([^:#]+):([^:#]+)#/) {
        my $tabname = $1;
        my $keyname = $2;
        my $colname = $3;
        if ($2 =~ /THISNODE/ or $2 =~ /\$NODE/) {
            my $natab = xCAT::Table->new($tabname);
            my $naent = $natab->getNodeAttribs($node,[$colname]);
            my $naval = $naent->{$colname};
            $kcmdlinehack =~ s/#TABLE:([^:#]+):([^:#]+):([^:#]+)#/$naval/;
        } else {
            my $msg =  "Table key of $2 not yet supported by boottarget mini-template";
            $::PXE_callback->({
                error => ["$msg"],
                errorcode => [1]
            });
        }
    }

    #$kern->{kcmdline} .= " ".$kern->{addkcmdline};

    $kern->{kcmdline} .= " ".$kcmdlinehack;

###hack end

  }
  if ($kern->{kcmdline} =~ /!myipfn!/) {
      my $ipfn;
      my @ipfnd = xCAT::NetworkUtils->my_ip_facing($node);
      unless ($ipfnd[0]) { $ipfn = $ipfnd[1];}
      unless ($ipfn) {
        my @myself = xCAT::NetworkUtils->determinehostname();
        my $myname = $myself[(scalar @myself)-1];
         $::PXE_callback->(
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
  unless (-d $tftpdir."/pxelinux.cfg/") {
      mkpath($tftpdir."/pxelinux.cfg/");
  }

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
    
    # add the IPAPPEND flag
    my $os = $nthash{$node}->[0]->{os};
    if ($os !~ /fedora12|fedora13/) {
        print $pcfg "  IPAPPEND 2\n";
    }
    }
    close($pcfg);
    my $inetn = inet_aton($node);
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
  unless (inet_aton($node)) {
    syslog("local4|err","xCAT unable to resolve IP in pxe plugin");
    return;
  }
  my $ip = inet_ntoa(inet_aton($node));;
  unless ($ip) {
    syslog("local4|err","xCAT unable to resolve IP in pxe plugin");
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
    if ($resp and ($resp->{errorcode} and $resp->{errorcode}->[0]) or ($resp->{error} and $resp->{error}->[0])) {
        $errored=1;
    }
    foreach (@{$resp->{node}}) {
       if ($_->{error} or $_->{errorcode}) {
          $errored=1;
       }
       if ($_->{_addkcmdlinehandled}) {
           $::PXE_addkcmdlinehandled->{$_->{name}->[0]}=1;
           return; #Don't send back to client this internal hint
       }
    }
    $::PXE_callback->($resp);
}



sub preprocess_request {
   #Assume shared tftp directory for boring people, but for cool people, help sync up tftpdirectory contents when 
   #they specify no sharedtftp in site table
   #my $stab = xCAT::Table->new('site');
   my $req = shift;
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
    my $HELP;
    my $VERSION;
    my $VERBOSE;	
    Getopt::Long::Configure("bundling");
    Getopt::Long::Configure("pass_through");
    if (!GetOptions('h|?|help' => \$HELP, 
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

   #my $sent = $stab->getAttribs({key=>'sharedtftp'},'value');
   my @entries =  xCAT::TableUtils->get_site_attribute("sharedtftp");
   my $t_entry = $entries[0];
   xCAT::MsgUtils->trace($verbose_on_off,"d","pxe: sharedtftp=$t_entry");
   if ( defined($t_entry)  and ($t_entry eq "0" or $t_entry eq "no" or $t_entry eq "NO")) {
      # check for  computenodes and servicenodes from the noderange, if so error out
      my @SN;
      my @CN;
      xCAT::ServiceNodeUtils->getSNandCPnodes(\@$nodes, \@SN, \@CN);
      unless (($args[0] eq 'stat') or ($args[0] eq 'enact')) { # ok for these options 
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
  $::PXE_request = shift;
  $::PXE_callback = shift;
  my $sub_req = shift;
  undef $::PXE_addkcmdlinehandled;
  my @args;
  my @nodes;
  my @rnodes;
  
  #>>>>>>>used for trace log start>>>>>>>
  my %opt;
  my $verbose_on_off=0;
  if (ref($::PXE_request->{arg})) {
    @args=@{$::PXE_request->{arg}};
  } else {
    @args=($::PXE_request->{arg});
  }
  @ARGV = @args;
  GetOptions('V'  => \$opt{V});
  if($opt{V}){$verbose_on_off=1;}
  #>>>>>>>used for trace log end>>>>>>>
  
  if (ref($::PXE_request->{node})) {
    @rnodes = @{$::PXE_request->{node}};
  } else {
    if ($::PXE_request->{node}) { @rnodes = ($::PXE_request->{node}); }
  }

  unless (@rnodes) {
      if ($usage{$::PXE_request->{command}->[0]}) {
          $::PXE_callback->({data=>$usage{$::PXE_request->{command}->[0]}});
      }
      return;
  }

  #if not shared, then help sync up
  if ($::PXE_request->{'_disparatetftp'}->[0]) { #reading hint from preprocess_command
   @nodes = ();
   foreach (@rnodes) {
     if (xCAT::NetworkUtils->nodeonmynet($_)) {
        push @nodes,$_;
      } else {
        xCAT::MsgUtils->message("S", "$_: pxe netboot: stop configuration because of none sharedtftp and not on same network with its xcatmaster.");
     }
   }
  } else {
     @nodes = @rnodes;
  }

  #>>>>>>>used for trace log>>>>>>>
  my $str_node = join(" ",@nodes);
  xCAT::MsgUtils->trace($verbose_on_off,"d","pxe: nodes are $str_node");
  
  # return directly if no nodes in the same network
  unless (@nodes) {
     xCAT::MsgUtils->message("S", "xCAT: pxe netboot: no valid nodes. Stop the operation on this server.");
     return;
  }

  if (ref($::PXE_request->{arg})) {
      @args=@{$::PXE_request->{arg}};
  } else {
      @args=($::PXE_request->{arg});
  }

   #now run the begin part of the prescripts
   unless ($args[0] eq 'stat') { # or $args[0] eq 'enact') {
       $errored=0;
       if ($::PXE_request->{'_disparatetftp'}->[0]) {  #the call is distrubuted to the service node already, so only need to handles my own children
           xCAT::MsgUtils->trace($verbose_on_off,"d","pxe: the call is distrubuted to the service node already, so only need to handles my own children");
           xCAT::MsgUtils->trace($verbose_on_off,"d","pxe: issue runbeginpre request");
           $sub_req->({command=>['runbeginpre'],
           node=>\@nodes,
           arg=>[$args[0], '-l']},\&pass_along);
       } else { #nodeset did not distribute to the service node, here we need to let runednpre to distribute the nodes to their masters
            xCAT::MsgUtils->trace($verbose_on_off,"d","pxe: nodeset did not distribute to the service node");
            xCAT::MsgUtils->trace($verbose_on_off,"d","pxe: issue runbeginpre request");
            $sub_req->({command=>['runbeginpre'],   
                    node=>\@rnodes,
                    arg=>[$args[0]]},\&pass_along);
       }
       if ($errored) { 
	  my $rsp;
	  $rsp->{errorcode}->[0]=1;
	  $rsp->{error}->[0]="Failed in running begin prescripts.  Processing will still continue.\n";
	  $::PXE_callback->($rsp);
       }
   }
  
#end prescripts code
  if (! -r "$tftpdir/pxelinux.0") {
    unless (-r "/usr/lib/syslinux/pxelinux.0" or -r "/usr/share/syslinux/pxelinux.0") {
       $::PXE_callback->({error=>["Unable to find pxelinux.0 "],errorcode=>[1]});
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
     $::PXE_callback->({errror=>["Unable to find pxelinux.0 from syslinux"],errorcode=>[1]});
     return;
  }

      
  $errored=0;
  my $inittime=0;
  if (exists($::PXE_request->{inittime})) { $inittime= $::PXE_request->{inittime}->[0];}
  if (!$inittime) { $inittime=0;}
  unless ($args[0] eq 'stat') { # or $args[0] eq 'enact') {
    xCAT::MsgUtils->trace($verbose_on_off,"d","pxe: issue setdestiny request");
    $sub_req->({command=>['setdestiny'],
               node=>\@nodes,
               inittime=>[$inittime],
               arg=>\@args},\&pass_along);
  }
  if ($errored) { return; }
  #Time to actually configure the nodes, first extract database data with the scalable calls
  my $bptab = xCAT::Table->new('bootparams',-create=>1);
  my $chaintab = xCAT::Table->new('chain');
  my $mactab = xCAT::Table->new('mac'); #to get all the hostnames
  my $typetab = xCAT::Table->new('nodetype');
  my $restab = xCAT::Table->new('noderes');
  my $linuximgtab=xCAT::Table->new('linuximage',-create=>1);
  my %nrhash =  %{$restab->getNodesAttribs(\@nodes,[qw(tftpdir)])};
  my %bphash = %{$bptab->getNodesAttribs(\@nodes,[qw(kernel initrd kcmdline addkcmdline)])};
  my %chainhash = %{$chaintab->getNodesAttribs(\@nodes,[qw(currstate)])};
  my %machash = %{$mactab->getNodesAttribs(\@nodes,[qw(mac)])};
  my %nthash = %{$typetab->getNodesAttribs(\@nodes,[qw(os provmethod)])};
  foreach (@nodes) {
    my %response;
    my $tftpdir;
    if ($nrhash{$_} and $nrhash{$_}->[0] and $nrhash{$_}->[0]->{tftpdir}) {
       $tftpdir = $nrhash{$_}->[0]->{tftpdir};
    } else {
       $tftpdir = $globaltftpdir;
    }
    $response{node}->[0]->{name}->[0]=$_;
    if ($args[0] eq 'stat') {
      $response{node}->[0]->{data}->[0]= getstate($_,$tftpdir);
      $::PXE_callback->(\%response);
    } elsif ($args[0]) { #If anything else, send it on to the destiny plugin, then setstate
      my $ent = $nthash{$_}->[0];
      my $osimgname = $ent->{'provmethod'};
      my $linuximghash=undef;
      unless($osimgname =~ /^(install|netboot|statelite)$/){
        $linuximghash = $linuximgtab->getAttribs({imagename => $osimgname}, 'boottarget', 'addkcmdline');
      }
      ($rc,$errstr) = setstate($_,\%bphash,\%chainhash,\%machash,\%nthash,$tftpdir,$linuximghash);
      if ($rc) {
        $response{node}->[0]->{errorcode}->[0]= $rc;
        $response{node}->[0]->{errorc}->[0]= $errstr;
        $::PXE_callback->(\%response);
      }
    }
  }

  my $inittime=0;
  if (exists($::PXE_request->{inittime})) { $inittime= $::PXE_request->{inittime}->[0];} 
  if (!$inittime) { $inittime=0;}

  #dhcp stuff -- inittime is set when xcatd on sn is started
  unless (($args[0] eq 'stat') || ($inittime) || ($args[0] eq 'offline')) {
      my $do_dhcpsetup=1;
      #my $sitetab = xCAT::Table->new('site');
      #if ($sitetab) {
          #(my $ref) = $sitetab->getAttribs({key => 'dhcpsetup'}, 'value');
          my @entries =  xCAT::TableUtils->get_site_attribute("dhcpsetup");
          my $t_entry = $entries[0];  
          if ( defined($t_entry) ) {
             if ($t_entry =~ /0|n|N/) { $do_dhcpsetup=0; }
          }
      #}
      
      if ($do_dhcpsetup) {
        if ($::PXE_request->{'_disparatetftp'}->[0]) { #reading hint from preprocess_command
            xCAT::MsgUtils->trace($verbose_on_off,"d","pxe: issue makedhcp request");
            $sub_req->({command=>['makedhcp'],arg=>['-l'],
                        node=>\@nodes},$::PXE_callback);
        } else {
            xCAT::MsgUtils->trace($verbose_on_off,"d","pxe: issue makedhcp request");
            $sub_req->({command=>['makedhcp'],
                       node=>\@nodes},$::PXE_callback);
        }
     }  

  }
  #unlink the files for 'offline' command
  if($args[0] eq 'offline') {
    foreach my $node (@nodes) {
      my %ipaddrs;
      unless (inet_aton($node)) {
        syslog("local4|err","xCAT unable to resolve IP in pxe plugin");
        return;
      }
      my $ip = inet_ntoa(inet_aton($node));;
      unless ($ip) {
        syslog("local4|err","xCAT unable to resolve IP in pxe plugin");
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

      unlink($tftpdir."/pxelinux.cfg/".$node);

      foreach $ip (keys %ipaddrs) {
        my @ipa=split(/\./,$ip);
        my $pname = sprintf("%02X%02X%02X%02X",@ipa);
        unlink($tftpdir."/pxelinux.cfg/".$pname);
        #if ($hassymlink) {
          #symlink($node,$tftpdir."/pxelinux.cfg/".$pname);
        #} else {
          #link($tftpdir."/pxelinux.cfg/".$node,$tftpdir."/pxelinux.cfg/".$pname);
        #}
      }
    }
  }

  #now run the end part of the prescripts
  unless ($args[0] eq 'stat') { # or $args[0] eq 'enact') 
      $errored=0;
      if ($::PXE_request->{'_disparatetftp'}->[0]) {  #the call is distrubuted to the service node already, so only need to handles my own children
         xCAT::MsgUtils->trace($verbose_on_off,"d","pxe: issue runendpre request");
         $sub_req->({command=>['runendpre'],
                     node=>\@nodes,
                     arg=>[$args[0], '-l']},\&pass_along);
      } else { #nodeset did not distribute to the service node, here we need to let runednpre to distribute the nodes to their masters
         xCAT::MsgUtils->trace($verbose_on_off,"d","pxe: issue runendpre request");
         $sub_req->({command=>['runendpre'],   
                     node=>\@rnodes,
                     arg=>[$args[0]]},\&pass_along);
      }
      if ($errored) { 
	  my $rsp;
	  $rsp->{errorcode}->[0]=1;
	  $rsp->{error}->[0]="Failed in running end prescripts.  Processing will still continue.\n";
	  $::PXE_callback->($rsp);
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
  if ($noderef =~ /xCAT_plugin::pxe/) {
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
