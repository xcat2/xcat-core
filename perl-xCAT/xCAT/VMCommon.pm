package xCAT::VMCommon;
use Socket;
use strict;
#Functions common to virtualization management (KVM, Xen, VMware)
sub grab_table_data{ #grab table data relevent to VM guest nodes
  my $noderange=shift;
  my $cfghash = shift;
  my $callback=shift;
  my $vmtab = xCAT::Table->new("vm");
  my $hmtab = xCAT::Table->new("nodehm");
  my $nttab = xCAT::Table->new("nodetype");
  my $sitetab = xCAT::Table->new("site");
  $cfghash->{site}->{genmacprefix} = xCAT::Utils->get_site_attribute('genmacprefix');
  if ($hmtab) {
      $cfghash->{nodehm}  = $hmtab->getNodesAttribs($noderange,['serialspeed']);
  }
  if ($nttab) {
      $cfghash->{nodetype}  = $nttab->getNodesAttribs($noderange,['os','arch']); #allow us to guess RTC config
  }
  unless ($vmtab) { 
    $callback->({data=>["Cannot open vm table"]});
    return;
  }
  $cfghash->{vm} = $vmtab->getNodesAttribs($noderange,['node','host','migrationdest','cfgstore','storage','memory','cpus','nics','bootorder','virtflags']);
  my $mactab = xCAT::Table->new("mac",-create=>1);
  my $nrtab= xCAT::Table->new("noderes",-create=>1);
  $cfghash->{mac} = $mactab->getAllNodeAttribs(['mac'],1);
  my $macs;
  my $mac;
  foreach (keys %{$cfghash->{mac}}) {
      $macs=$cfghash->{mac}->{$_}->[0]->{mac};
      foreach $mac (split /\|/,$macs) {
          $mac =~ s/\!.*//;
          $cfghash->{usedmacs}->{lc($mac)}=1;
      }
  }
}

sub getMacAddresses {
    my $tablecfg = shift;
    my $node = shift;
    my $count = shift;
    my $mactab = xCAT::Table->new("mac",-create=>1);
    my $macdata = $tablecfg->{mac}->{$node}->[0]->{mac};
    unless ($macdata) { $macdata ="" }
    my @macs;
    my $macaddr;
    foreach $macaddr (split /\|/,$macdata) {
         $macaddr =~ s/\!.*//;
         push @macs,lc($macaddr);
    }
    $count-=scalar(@macs);
    my $updatesneeded=0;
    if ($count > 0) {
        $updatesneeded = 1;
    }

    srand(); #Re-seed the rng.  This will make the mac address generation less deterministic
    while ($count > 0) { #still need more, autogen
        $macaddr = "";
        while (not $macaddr) {
            $macaddr = lc(genMac($node,$tablecfg->{site}->{genmacprefix}));
            if ($tablecfg->{usedmacs}->{$macaddr}) {
                $macaddr = "";
            }
        }
        $count--;
        $tablecfg->{usedmacs}->{$macaddr} = 1;
        if (not $macdata) {
            $macdata = $macaddr;
        } else {
            $macdata .= "|".$macaddr;
        }
        push @macs,$macaddr;
    }
    if ($updatesneeded) {
        my $mactab = xCAT::Table->new('mac',-create=>1);
        $mactab->setNodeAttribs($node,{mac=>$macdata});
        $tablecfg->{dhcpneeded}->{$node}=1; #at our leisure, this dhcp binding should be updated
    }
    return @macs;
#    $cfghash->{usedmacs}-{lc{$mac}};

}

sub genMac { #Generates a mac address for a node, does NOT assure uniqueness, calling code needs to do that
    my $node=shift;
    my $prefix = shift;
    if ($prefix) { #Specific prefix requested, honor it
        my $tail = int(rand(0xffffff)); #With only 24 bits of space, use random bits;
        $tail = sprintf("%06x",$tail);
        $tail =~ s/(..)(..)(..)/:$1:$2:$3/;
        return $prefix.$tail;
    }
    my $allbutmult = 0xfeff; # to & with a number to ensure multicast bit is *not* set
    my $locallyadministered = 0x200; # to | with the 16 MSBs to indicate a local mac
    my $leading = int(rand(0xffff));
    $leading = $leading & $allbutmult;
    $leading = $leading | $locallyadministered;
    #If this nodename is a resolvable name, we'll use that for the other 32 bits
    my $low32;
    my $n;
    if ($n = inet_aton($node)) {
        $low32= unpack("N",$n);
    }
    unless ($low32) { #If that failed, just do 32 psuedo-random bits
        $low32 = int(rand(0xffffffff));
    }
    my $mac;
    $mac = sprintf("%04x%08x",$leading,$low32);
    $mac =~s/(..)(..)(..)(..)(..)(..)/$1:$2:$3:$4:$5:$6/;
    return $mac;

}
1;
