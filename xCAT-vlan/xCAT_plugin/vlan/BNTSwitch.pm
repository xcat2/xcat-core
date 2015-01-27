#!/usr/bin/perl
package xCAT_plugin::vlan::BNTSwitch;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use xCAT::MacMap;
use xCAT::Table;
use Data::Dumper;
use xCAT::SwitchHandler;
use SNMP;

my $sysDescr='.1.3.6.1.2.1.1.1';

#BNT uses different OIDs for different switch module and versions. The following 
#assumes that the FW versions are v6.x.
#G8100 is not supported yet because it uses different method. No hw to test. 
my $BNTOID={
    'EN4093'=>{
        'vlanInfoId'=>'.1.3.6.1.4.1.20301.2.5.2.3.5.1.1.1',
        'vlanInfoPorts'=>'.1.3.6.1.4.1.20301.2.5.2.3.5.1.1.7',
        'portInfoPhyIfDescr'=>'.1.3.6.1.4.1.20301.2.5.1.3.2.1.1.6',
        'vlanNewCfgVlanName'=>'.1.3.6.1.4.1.20301.2.5.2.1.1.3.1.2',
        'vlanNewCfgState'=>'.1.3.6.1.4.1.20301.2.5.2.1.1.3.1.4', #2:enable 3:disable
        'vlanNewCfgAddPort'=>'.1.3.6.1.4.1.20301.2.5.2.1.1.3.1.5',
        'vlanNewCfgRemovePort'=>'.1.3.6.1.4.1.20301.2.5.2.1.1.3.1.6',
        'vlanNewCfgDelete'=>'.1.3.6.1.4.1.20301.2.5.2.1.1.3.1.7', #1:other 2:delete
        'agPortNewCfgVlanTag'=>'.1.3.6.1.4.1.20301.2.5.1.1.2.3.1.3', #2:tagged 3:untagged
        'agPortNewCfgBpduGuard'=>'.1.3.6.1.4.1.20301.2.5.1.1.2.3.1.41', #1:enable 2:disable
        'agPortNewCfgStpExtGuard'=>'.1.3.6.1.4.1.20301.2.5.1.1.2.3.1.52',#1:loop, 2:root, 3:none, 0:default
        'agApplyConfig'=>'.1.3.6.1.4.1.20301.2.5.1.1.8.2',
        'agSaveConfiguration'=> '.1.3.6.1.4.1.20301.2.5.1.1.1.4',	#saveActive(2), notSaveActive(3)
        'arpInfoDestIp'=>'.1.3.6.1.4.1.20301.2.5.3.3.2.1.1.1',
        'arpInfoSrcPort'=>'.1.3.6.1.4.1.20301.2.5.3.3.2.1.1.4',
    },

    'G8000'=>{
	'vlanInfoId'=>'.1.3.6.1.4.1.26543.2.7.1.2.3.5.1.1.1',
	'vlanInfoPorts'=>'.1.3.6.1.4.1.26543.2.7.1.2.3.5.1.1.7',
	'portInfoPhyIfDescr'=>'.1.3.6.1.4.1.26543.2.7.1.1.3.2.1.1.6',
	'vlanNewCfgVlanName'=>'.1.3.6.1.4.1.26543.2.7.1.2.1.1.3.1.2',
	'vlanNewCfgState'=>'.1.3.6.1.4.1.26543.2.7.1.2.1.1.3.1.4', #2:enable 3:disable
	'vlanNewCfgAddPort'=>'.1.3.6.1.4.1.26543.2.7.1.2.1.1.3.1.5',
	'vlanNewCfgRemovePort'=>'.1.3.6.1.4.1.26543.2.7.1.2.1.1.3.1.6',
	'vlanNewCfgDelete'=>'.1.3.6.1.4.1.26543.2.7.1.2.1.1.3.1.7', #1:other 2:delete
	'agPortNewCfgVlanTag'=>'.1.3.6.1.4.1.26543.2.7.1.1.1.2.3.1.3', #2:tagged 3:untagged
	'agPortNewCfgBpduGuard'=>'.1.3.6.1.4.1.26543.2.7.1.1.1.2.3.1.41', #1:enable 2:disable
	'agPortNewCfgStpExtGuard'=>'.1.3.6.1.4.1.26543.2.7.1.1.1.2.3.1.52',#1:loop, 2:root, 3:none, 0:default
	'agApplyConfig'=>'.1.3.6.1.4.1.26543.2.7.1.1.1.8.2',
    'agSaveConfiguration'=> '.1.3.6.1.4.1.26543.2.7.1.1.1.1.4',	#saveActive(2), notSaveActive(3)
	'arpInfoDestIp'=>'.1.3.6.1.4.1.26543.2.7.1.3.3.2.1.1.1',
	'arpInfoSrcPort'=>'.1.3.6.1.4.1.26543.2.7.1.3.3.2.1.1.4',
    },

    'G8052'=>{
	'vlanInfoId'=>'.1.3.6.1.4.1.26543.2.7.7.2.3.5.1.1.1',
	'vlanInfoPorts'=>'.1.3.6.1.4.1.26543.2.7.7.2.3.5.1.1.7',
	'portInfoPhyIfDescr'=>'.1.3.6.1.4.1.26543.2.7.7.1.3.2.1.1.6',
	'vlanNewCfgVlanName'=>'.1.3.6.1.4.1.26543.2.7.7.2.1.1.3.1.2',
	'vlanNewCfgState'=>'.1.3.6.1.4.1.26543.2.7.7.2.1.1.3.1.4', 
	'vlanNewCfgAddPort'=>'.1.3.6.1.4.1.26543.2.7.7.2.1.1.3.1.5',
	'vlanNewCfgRemovePort'=>'.1.3.6.1.4.1.26543.2.7.7.2.1.1.3.1.6',
	'vlanNewCfgDelete'=>'.1.3.6.1.4.1.26543.2.7.7.2.1.1.3.1.7', 
	'agPortNewCfgVlanTag'=>'.1.3.6.1.4.1.26543.2.7.7.1.1.2.3.1.3', 
	'agPortNewCfgBpduGuard'=>'.1.3.6.1.4.1.26543.2.7.7.1.1.2.3.1.41', 
	'agPortNewCfgStpExtGuard'=>'.1.3.6.1.4.1.26543.2.7.7.1.1.2.3.1.52',
	'agApplyConfig'=>'.1.3.6.1.4.1.26543.2.7.7.1.1.8.2',		      
    'agSaveConfiguration'=> '.1.3.6.1.4.1.26543.2.7.7.1.1.1.4',	#saveActive(2), notSaveActive(3)
	'arpInfoDestIp'=>'.1.3.6.1.4.1.26543.2.7.7.3.3.2.1.1.1',
	'arpInfoSrcPort'=>'.1.3.6.1.4.1.26543.2.7.7.3.3.2.1.1.4',
    },

    'G8124'=>{
	'vlanInfoId'=>'.1.3.6.1.4.1.26543.2.7.4.2.3.5.1.1.1',
	'vlanInfoPorts'=>'.1.3.6.1.4.1.26543.2.7.4.2.3.5.1.1.7',
	'portInfoPhyIfDescr'=>'.1.3.6.1.4.1.26543.2.7.4.1.3.2.1.1.6',
	'vlanNewCfgVlanName'=>'.1.3.6.1.4.1.26543.2.7.4.2.1.1.3.1.2',
	'vlanNewCfgState'=>'.1.3.6.1.4.1.26543.2.7.4.2.1.1.3.1.4', 
	'vlanNewCfgAddPort'=>'.1.3.6.1.4.1.26543.2.7.4.2.1.1.3.1.5',
	'vlanNewCfgRemovePort'=>'.1.3.6.1.4.1.26543.2.7.4.2.1.1.3.1.6',
	'vlanNewCfgDelete'=>'.1.3.6.1.4.1.26543.2.7.4.2.1.1.3.1.7',
	'agPortNewCfgVlanTag'=>'.1.3.6.1.4.1.26543.2.7.4.1.1.2.3.1.3', 
	'agPortNewCfgBpduGuard'=>'.1.3.6.1.4.1.26543.2.7.4.1.1.2.3.1.41', 
	'agPortNewCfgStpExtGuard'=>'.1.3.6.1.4.1.26543.2.7.4.1.1.2.3.1.52',
	'agApplyConfig'=>'.1.3.6.1.4.1.26543.2.7.4.1.1.8.2',		      
    'agSaveConfiguration'=> '.1.3.6.1.4.1.26543.2.7.4.1.1.1.4',	 #saveActive(2), notSaveActive(3)
	'arpInfoDestIp'=>'.1.3.6.1.4.1.26543.2.7.4.3.3.2.1.1.1',
	'arpInfoSrcPort'=>'.1.3.6.1.4.1.26543.2.7.4.3.3.2.1.1.4',
    },
    
    #this is for G8264 and 8264E
    'G8264'=>{
	'vlanInfoId'=>'.1.3.6.1.4.1.26543.2.7.6.2.3.5.1.1.1',
	'vlanInfoPorts'=>'.1.3.6.1.4.1.26543.2.7.6.2.3.5.1.1.7',
	'portInfoPhyIfDescr'=>'.1.3.6.1.4.1.26543.2.7.6.1.3.2.1.1.6',
	'vlanNewCfgVlanName'=>'.1.3.6.1.4.1.26543.2.7.6.2.1.1.3.1.2',
	'vlanNewCfgState'=>'.1.3.6.1.4.1.26543.2.7.6.2.1.1.3.1.4', 
	'vlanNewCfgAddPort'=>'.1.3.6.1.4.1.26543.2.7.6.2.1.1.3.1.5',
	'vlanNewCfgRemovePort'=>'.1.3.6.1.4.1.26543.2.7.6.2.1.1.3.1.6',
	'vlanNewCfgDelete'=>'.1.3.6.1.4.1.26543.2.7.6.2.1.1.3.1.7',
	'agPortNewCfgVlanTag'=>'.1.3.6.1.4.1.26543.2.7.6.1.1.2.3.1.3', 
	'agPortNewCfgBpduGuard'=>'.1.3.6.1.4.1.26543.2.7.6.1.1.2.3.1.41', 
	'agPortNewCfgStpExtGuard'=>'.1.3.6.1.4.1.26543.2.7.6.1.1.2.3.1.52',
	'agApplyConfig'=>'.1.3.6.1.4.1.26543.2.7.6.1.1.8.2',		      
    'agSaveConfiguration'=> '.1.3.6.1.4.1.26543.2.7.6.1.1.1.4',	  #saveActive(2), notSaveActive(3)
	'arpInfoDestIp'=>'.1.3.6.1.4.1.26543.2.7.6.3.3.2.1.1.1',
	'arpInfoSrcPort'=>'.1.3.6.1.4.1.26543.2.7.6.3.3.2.1.1.4',
    },
};


my %HexConv=( 0=>0x80, 1=>0x40, 2=>0x20, 3=>0x10,
              4=>0x08, 5=>0x04, 6=>0x02, 7=>0x01);


#--------------------------------------------------------------
=head3 filter_string 
  
    Every switch plugin must implement this subroutine.

    The return value will be used comare against the string 
    from sysDescr value from snmpget. If the latter contains
    this string, then this mudule will be used to handle the 
    requests for vlan configuration.

=cut
#-------------------------------------------------------------
sub filter_string {
    return "BNT |Blade Network Technologies|IBM Networking Operating System|EN4093";
}

              
#--------------------------------------------------------------
=head3 get_vlan_ids  
  
  Every switch plugin must implement this subroutine.

  It gets the existing vlan IDs for the switch.
  Returns:  an array containing all the vlan ids for the switch
=cut
#-------------------------------------------------------------
sub get_vlan_ids {
  my $session=shift;

  my $swmod=getSwitchModule($session);
  if (!$swmod) { return ();}

  my $vlanmap = xCAT::MacMap::walkoid($session, $BNTOID->{$swmod}->{vlanInfoId}, silentfail=>1); 

  my %vlanids=();
  foreach(keys(%$vlanmap)) {
      $vlanids{$_}=1;
  }

  my @ret=(sort keys(%vlanids));
  print "ids=@ret\n";
  return @ret; 
}

#--------------------------------------------------------------
=head3 get_vlanids_for_ports 
  
    Every switch plugin must implement this subroutine.

    It returns a hash pointer that contains the vlan id for each given port.
    The kay is the port, the vlaue is a pointer to an array.
=cut
#-------------------------------------------------------------
sub get_vlanids_for_ports {
  my $session=shift;
  my @ports=@_;

  my $swmod=getSwitchModule($session);
  if (!$swmod) { return;}


  my $namemap = xCAT::MacMap::walkoid($session, $BNTOID->{$swmod}->{portInfoPhyIfDescr});
  if ($namemap) {
     my $ifnamesupport=0; 
     foreach (keys %{$namemap}) {
        if ($namemap->{$_}) {
           $ifnamesupport=1;
           last;
        }
     }
     unless ($ifnamesupport) {
        $namemap=0;
     }
  }
  unless ($namemap) {
    return;
  }
  #print "namemap=" . Dumper($namemap) . "\n";

  my $portsvlanmap = xCAT::MacMap::walkoid($session, $BNTOID->{$swmod}->{vlanInfoPorts}, silentfail=>1); 
  #print "portsvlanmap=" . Dumper($portsvlanmap) . "\n";
  foreach my $vid (keys (%$portsvlanmap)) {
      my $data=$portsvlanmap->{$vid};
      my @a = split(//, $data);
      foreach (@a) {
	  my $num=unpack("C*", $_);
	  $_= sprintf ("%02x",$num);
      }
      $portsvlanmap->{$vid}=\@a;
  }
  
  my %ret=();
  if (defined($portsvlanmap)) { 
      foreach my $portid (keys %{$namemap}) {
	  my $switchport = $namemap->{$portid};
	  foreach my $portname (@ports) { 
	      unless (xCAT::MacMap::namesmatch($portname,$switchport)) {
		  next;
	      }

	      foreach  my $vid (keys (%$portsvlanmap)) {
		  my $data=$portsvlanmap->{$vid};
		  my $index  = int($portid / 8);
		  my $offset  = $portid % 8;
		  my $num = hex($data->[$index]) & ($HexConv{$offset});
		  if ($num != 0) {
		      if (exists($ret{$portname})) {
			  my $pa=$ret{$portname};
			  push (@$pa, $vid);
		      } else {
			  $ret{$portname}=[$vid];
		      }
		  }
	      }
	  }
      }
  }

  return \%ret;
}


#--------------------------------------------------------------
=head3 create_vlan
  
    Every switch plugin must implement this subroutine.
 
    Creates a new vlan on the switch
    Returns an array. (erorcode, errormsg). When errorcode=0, means no error.
=cut
#-------------------------------------------------------------
sub  create_vlan {
    my $session=shift;
    my $vlan_id=shift;
    my $vlan_name="xcat_vlan_" . $vlan_id;
      
    my $swmod=getSwitchModule($session);
    if (!$swmod) { return (1, "This BNT switch modeule is not supported.");}

    print "BNT $swmod\n";
    #name
    my @ret= xCAT::SwitchHandler::setoid($session, $BNTOID->{$swmod}->{vlanNewCfgVlanName}, $vlan_id, $vlan_name, 'OCTET'); 
    if ($ret[0] != 0) { 
	$ret[1]="Set vlanNewCfgVlanName " . $BNTOID->{$swmod}->{vlanNewCfgVlanName} . ".$vlan_id to $vlan_name.\n" . $ret[1];
	return @ret;
    }

    my $tmp = xCAT::MacMap::walkoid($session, $BNTOID->{$swmod}->{vlanNewCfgVlanName});
    #print "tmp=" . Dumper($tmp) . "\n";

    #change to enable state
    my @ret= xCAT::SwitchHandler::setoid($session, $BNTOID->{$swmod}->{vlanNewCfgState}, $vlan_id, 2, 'INTEGER'); 
    if ($ret[0] != 0) { 
    	$ret[1]="Set vlanNewCfgState " . $BNTOID->{$swmod}->{vlanNewCfgState} . ".$vlan_id to 2(enable).\n" . $ret[1];
    	return @ret;
    }

    @ret=apply_changes($session, $swmod);
   
   
    return @ret;
}

#--------------------------------------------------------------
=head3 add_ports_to_vlan   

    Every switch plugin must implement this subroutine.

    Adds the given ports to the existing vlan
    Returns an array. (erorcode, errormsg). When errorcode=0, means no error.
=cut
#-------------------------------------------------------------
sub  add_ports_to_vlan {
    my $session=shift;
    my $vlan_id=shift;
    # If portmode is set, we'll set the switchport to untagged(access) mode.
    my $portmode=shift;
    my @ports1=@_;

    my $swmod=getSwitchModule($session);
    if (!$swmod) { return (1, "This BNT switch modeule is not supported.");}

    my $port_vlan_hash=get_vlanids_for_ports($session,@ports1);
    #print "port_vlan_hash=" . Dumper($port_vlan_hash) . "\n";
    my @ports=();
    foreach my $port (keys(%$port_vlan_hash)) {
	my $val=$port_vlan_hash->{$port};
	my $found=0;
	foreach my $tmp_vid (@$val) {
	    if ($tmp_vid == $vlan_id) {
		$found=1;
		last;
	    }
	}
	if (!$found) {
	    push(@ports, $port);
	}
    }

    if (@ports==0) {  return (0, ""); }
    
    #print "vlan=$vlan_id, ports=@ports\n";
    my $namemap = xCAT::MacMap::walkoid($session, $BNTOID->{$swmod}->{portInfoPhyIfDescr});
    if ($namemap) {
	my $ifnamesupport=0; 
	foreach (keys %{$namemap}) {
	    if ($namemap->{$_}) {
		$ifnamesupport=1;
		last;
	    }
	}
	unless ($ifnamesupport) {
	    $namemap=0;
	}
    }
    unless ($namemap) {
	return;
    }
    #print "namemap=" . Dumper($namemap) . "\n";
    
  
    foreach my $portid (keys %{$namemap}) {
	my $switchport = $namemap->{$portid};
	foreach my $portname (@ports) { 
	    unless (xCAT::MacMap::namesmatch($portname,$switchport)) {
		next;
	    }
            
	    print "portid=$portid, vlan_id=$vlan_id\n";
        if ($portmode){
            #change this port to untagged
             my @ret= xCAT::SwitchHandler::setoid($session, $BNTOID->{$swmod}->{agPortNewCfgVlanTag}, $portid, 3, 'INTEGER'); 
             if ($ret[0] != 0) { 
                 $ret[1]="Set agPortNewCfgVlanTag " . $BNTOID->{$swmod}->{agPortNewCfgVlanTag} . ".$portid to 3(untagged).\n" . $ret[1];
                 return @ret;
            }	                        
        } else{
            #change this port to tagged
            my @ret= xCAT::SwitchHandler::setoid($session, $BNTOID->{$swmod}->{agPortNewCfgVlanTag}, $portid, 2, 'INTEGER'); 
            if ($ret[0] != 0) { 
                $ret[1]="Set agPortNewCfgVlanTag " . $BNTOID->{$swmod}->{agPortNewCfgVlanTag} . ".$portid to 2(tagged).\n" . $ret[1];
                return @ret;
            }
        }
            
	    #security feature:
	    if ($::XCATSITEVALS{vlansecurity} eq '1') {
		#enable bpdu guard on this port
		my @ret= xCAT::SwitchHandler::setoid($session, $BNTOID->{$swmod}->{agPortNewCfgBpduGuard}, $portid, 1, 'INTEGER'); 
		if ($ret[0] != 0) { 
		    $ret[1]="Enable bpdu guard for port $portid. (Set " . $BNTOID->{$swmod}->{agPortNewCfgBpduGuard} . ".$portid to 1.)\n" . $ret[1];
		    return @ret;
		}	                
		#enable root guard on this port
		my @ret= xCAT::SwitchHandler::setoid($session, $BNTOID->{$swmod}->{agPortNewCfgStpExtGuard}, $portid, 2, 'INTEGER'); 
		if ($ret[0] != 0) { 
		    $ret[1]="Enable root guard for port $portid. (Set  " . $BNTOID->{$swmod}->{agPortNewCfgStpExtGuard} . ".$portid to 2.\n" . $ret[1];
		    #	return @ret; #do not return because it is not supported for some switches yet. A defect will be fixed in BNT.
		}	                
	    }

            #add port in one by one
	    my @ret= xCAT::SwitchHandler::setoid($session, $BNTOID->{$swmod}->{vlanNewCfgAddPort}, $vlan_id, $portid, 'GAUGE'); 
	    if ($ret[0] != 0) { 
		$ret[1]="Set vlanNewCfgAddPort" . $BNTOID->{$swmod}->{vlanNewCfgAddPort} . ".$vlan_id to $portid.\n" . $ret[1];
		return @ret;
	    }	                
	}
    }

    my @ret=apply_changes($session, $swmod);

    return @ret;
}

#-------------------------------------------------------
=head3  add_crossover_ports_to_vlan
  It enables the vlan on the cross-over links.
    Returns an array. (erorcode, errormsg). When errorcode=0, means no error.
=cut
#-------------------------------------------------------
sub add_crossover_ports_to_vlan {
    my $session=shift;
    my $vlan_id=shift;
    my $switch=shift;
    my @switches=@_;
    my @ret=(0, "");
    my $msg;

    if (@switches == 0 ) { return (0, ""); }

#    my $swmod=getSwitchModule($session);
#    if (!$swmod) { return (1, "This BNT switch modeule is not supported.");}

    #figure out the port numbers that are connecting to the given switches
#    my @ips=();
    #get the ip address for each switch
#    foreach my $switch (@switches) {
#	my $ip=xCAT::NetworkUtils->getipaddr($switch);
#	if (!$ip) {
#	    $msg .= "Cannot resolve ip address for switch $switch\n";
#	} else {
#	   push(@ips, $ip); 
#	}
#    }

#    my @ports=();
#    my $tmp = xCAT::MacMap::walkoid($session, $BNTOID->{$swmod}->{arpInfoDestIp});
#    my $tmp1 = xCAT::MacMap::walkoid($session, $BNTOID->{$swmod}->{arpInfoSrcPort});
#    print Dumper($tmp);
#    print Dumper($tmp1);
#    foreach my $tmp_id (keys %{$tmp}) {
#	my $tmp_ip=$tmp->{$tmp_id};
#	if (grep /^$tmp_ip$/, @ips) {
#	    my $port=$tmp1->{$tmp_id};
#	    if ($port) { push(@ports, $port); }
#	}
#    }

    #get the ports that are connects to the switches
    my $switchestab=xCAT::Table->new('switches',-create=>0);
    my $ent = $switchestab->getNodeAttribs($switch, [qw(switch linkports)]);
    if ((!$ent) || (! $ent->{linkports}))  { return (0, $msg); }

    my %linkports=();
    foreach my $item (split(',',$ent->{linkports})) {
	my @a=split(':', $item);
	if (@a>1) {
	    $linkports{$a[1]}=$a[0];
	}
    }
    #print Dumper(%linkports);
    
    my @ports=();
    foreach my $sw (@switches) {
	if (exists($linkports{$sw})) {
	    push(@ports, $linkports{$sw}); 
	}
    }
    #print "ports=@ports\n";

    #now add the ports to the vlan
    if (@ports > 0) {
	my ($code, $msg1) = add_ports_to_vlan($session, $vlan_id, @ports);
	if ($msg) {
	    $msg1 = $msg . $msg1;
	}
	
	return ($code, $msg1);
    }

    return (0, $msg);
}

#--------------------------------------------------------------
=head3 remove_vlan   

    Every switch plugin must implement this subroutine.

    Remove a vlan from the switch
    Returns an array. (erorcode, errormsg). When errorcode=0, means no error.
=cut
#-------------------------------------------------------------
sub  remove_vlan {
    my $session=shift;
    my $vlan_id=shift;
    
    my $swmod=getSwitchModule($session);
    if (!$swmod) { return (1, "This BNT switch modeule is not supported.");}

    #set to delete state
    my @ret= xCAT::SwitchHandler::setoid($session, $BNTOID->{$swmod}->{vlanNewCfgDelete}, $vlan_id, 2, 'INTEGER'); 
    if ($ret[0] != 0) { 
    	$ret[1]="Set vlanNewCfgDelete " . $BNTOID->{$swmod}->{vlanNewCfgDelete} . ".$vlan_id to 2(delete).\n" . $ret[1];
    	return @ret;
    }

    @ret=apply_changes($session, $swmod);
   
    return @ret;
}


#--------------------------------------------------------------
=head3 remove_ports_from_vlan  

    Every switch plugin must implement this subroutine.

    Remove ports from a vlan
    Returns an array. (erorcode, errormsg). When errorcode=0, means no error.
=cut
#-------------------------------------------------------------
sub  remove_ports_from_vlan {
    my $session=shift;
    my $vlan_id=shift;
    my @ports=@_;
    
    my $swmod=getSwitchModule($session);
    if (!$swmod) { return (1, "This BNT switch modeule is not supported.");}

    #print "vlan=$vlan_id, ports=@ports\n";
    my $namemap = xCAT::MacMap::walkoid($session, $BNTOID->{$swmod}->{portInfoPhyIfDescr});
    if ($namemap) {
	my $ifnamesupport=0; 
	foreach (keys %{$namemap}) {
	    if ($namemap->{$_}) {
		$ifnamesupport=1;
		last;
	    }
	}
	unless ($ifnamesupport) {
	    $namemap=0;
	}
    }
    unless ($namemap) {
	return;
    }
    #print "namemap=" . Dumper($namemap) . "\n";
    
  
    foreach my $portid (keys %{$namemap}) {
	my $switchport = $namemap->{$portid};
	foreach my $portname (@ports) { 
	    unless (xCAT::MacMap::namesmatch($portname,$switchport)) {
		next;
	    }
            
	    print "portid=$portid, vlan_id=$vlan_id\n";
           
            #remove port in one by one
	    my @ret= xCAT::SwitchHandler::setoid($session, $BNTOID->{$swmod}->{vlanNewCfgRemovePort}, $vlan_id, $portid, 'GAUGE'); 
	    if ($ret[0] != 0) { 
		$ret[1]="Set vlanNewCfgRemovePort " . $BNTOID->{$swmod}->{vlanNewCfgRemovePort} . ".$vlan_id to $portid.\n" . $ret[1];
		return @ret;
	    }	                
	}
    }

    my @ret=apply_changes($session, $swmod);

    return @ret;

}


sub apply_changes {
    my $session=shift;
    my $swmod=shift;
    #apply 
    my @ret= xCAT::SwitchHandler::setoid($session, $BNTOID->{$swmod}->{agApplyConfig}, 0, 1, 'INTEGER'); 
    if ($ret[0] != 0) { 
	$ret[1]="Set agApplyConfig " . $BNTOID->{$swmod}->{agApplyConfig} . ".0 to 1(apply).\n" . $ret[1];
	return @ret;
    }

    my $state=3; 
    while ($state == 3) {
	my $tmp = xCAT::MacMap::walkoid($session, $BNTOID->{$swmod}->{agApplyConfig});
	#print "tmp=" . Dumper($tmp) . "\n";
	if ($tmp) {
	    $state=$tmp->{0};
	}
        sleep(3);
    }

    #set apply to idle state
    my @ret= xCAT::SwitchHandler::setoid($session, $BNTOID->{$swmod}->{agApplyConfig}, 0, 2, 'INTEGER'); 
    if ($ret[0] != 0) { 
	$ret[1]="Set agApplyConfig " . $BNTOID->{$swmod}->{agApplyConfig} . ".0 to 2(idle).\n" . $ret[1];
	return @ret;
    }

    if ($state == 5) {
	return (1, "Apply configuration failed.\n");
    }
    
    #save configurations.
    my @ret= xCAT::SwitchHandler::setoid($session, $BNTOID->{$swmod}->{agSaveConfiguration}, 0, 2, 'INTEGER'); 
    if ($ret[0] != 0) { 
        $ret[1]="Set agSaveConfiguration " . $BNTOID->{$swmod}->{agSaveConfiguration} . ".0 to 2(saveActive).\n" . $ret[1];
        return @ret;
    }
    return @ret;
}

sub getSwitchModule {
    my $session=shift;
    
    #get the the switch brand name
    my $tmp = xCAT::MacMap::walkoid($session, "$sysDescr", silentfail=>1);
    my $swmod;
    my $descr=$tmp->{0};
    if ($descr) {
	if ($descr =~ /G8000/) { return "G8000"; }
	if ($descr =~ /G8052/) { return "G8052"; }
	if ($descr =~ /G8124/) { return "G8124"; }
	if ($descr =~ /G8264/) { return "G8264"; }
	if ($descr =~ /EN4093/) { return "EN4093"; }
    }
    return 0;
}

1;
