package xCAT::VMCommon;
use strict;
#Functions common to virtualization management (KVM, Xen, VMware)
sub grab_table_data{ #grab table data relevent to VM guest nodes
  my $noderange=shift;
  my $cfghash = shift;
  my $callback=shift;
  my $vmtab = xCAT::Table->new("vm");
  my $hmtab = xCAT::Table->new("nodehm");
  my $nttab = xCAT::Table->new("nodetype");
  if ($hmtab) {
      $cfghash->{nodehm}  = $hmtab->getNodesAttribs($noderange,['serialspeed']);
  }
  if ($nttab) {
      $cfghash->{nodetype}  = $nttab->getNodesAttribs($noderange,['os']); #allow us to guess RTC config
  }
  unless ($vmtab) { 
    $callback->({data=>["Cannot open vm table"]});
    return;
  }
  $cfghash->{vm} = $vmtab->getNodesAttribs($noderange,['node','host','migrationdest','storage','memory','cpus','nics','bootorder','virtflags']);
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

1;
