#!/usr/bin/perl
package xCAT_plugin::vlan::CiscoSwitch;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use xCAT::MacMap;
use Data::Dumper;
use xCAT::SwitchHandler;
use SNMP;

#IF-MIB
my $ifName='.1.3.6.1.2.1.31.1.1.1.1';
my $ifDescr='.1.3.6.1.2.1.2.2.1.2';
my $ifOperStatus='.1.3.6.1.2.1.2.2.1.8';

#CISCO-VTP-MIB
my $vtpVlanEditTable='.1.3.6.1.4.1.9.9.46.1.4.2';
my $vtpVlanEditOperation='.1.3.6.1.4.1.9.9.46.1.4.1.1.1';
my $vtpVlanEditBufferOwner='.1.3.6.1.4.1.9.9.46.1.4.1.1.3';
my $vtpVlanEditRowStatus='.1.3.6.1.4.1.9.9.46.1.4.2.1.11.1';
my $vtpVlanEditType='.1.3.6.1.4.1.9.9.46.1.4.2.1.3.1';
my $vtpVlanEditName='.1.3.6.1.4.1.9.9.46.1.4.2.1.4.1';
my $vtpVlanEditDot10Said='.1.3.6.1.4.1.9.9.46.1.4.2.1.6.1';
my $vtpVlanState='.1.3.6.1.4.1.9.9.46.1.3.1.1.2';
my $vlanTrunkPortDynamicStatus='.1.3.6.1.4.1.9.9.46.1.6.1.1.14';
my $vlanTrunkPortDynamicState='.1.3.6.1.4.1.9.9.46.1.6.1.1.13';
my $vlanTrunkPortNativeVlan=  '.1.3.6.1.4.1.9.9.46.1.6.1.1.5';
my $vlanTrunkPortVlansEnabled='.1.3.6.1.4.1.9.9.46.1.6.1.1.4';
my $vlanTrunkPortEncapsulationType='.1.3.6.1.4.1.9.9.46.1.6.1.1.3';

#CISCO-VLAN-MEMBERSHIP-MIB
my $vmVlan='.1.3.6.1.4.1.9.9.68.1.2.2.1.2';
my $vmVlanType='.1.3.6.1.4.1.9.9.68.1.2.2.1.1'; #1:static 2:dynamic 3:trunk

#CISCI-STP-EXTENSION-MIB
my $stpxRootGuardConfigEnabled='1.3.6.1.4.1.9.9.82.1.5.1.1.2'; #1:enable 2:disable
my $stpxFastStartPortBpduGuardMode='1.3.6.1.4.1.9.9.82.1.9.3.1.4'; #1:enable 2:disable 3:default


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
    return "Cisco ";
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

  my $vlanmap = xCAT::MacMap::walkoid($session, "$vtpVlanState.1", silentfail=>1); 
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

    It returns a hash pointer that contains the vlan ids for each given port.
    The kay is the port, the vlaue is a pointer to an array.
=cut
#-------------------------------------------------------------
sub get_vlanids_for_ports {
  my $session=shift;
  my @ports=@_;

  my $namemap = xCAT::MacMap::walkoid($session, $ifName);
    #namemap is the mapping of ifIndex->(human readable name)
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
  unless ($namemap) { #Failback to ifDescr.  ifDescr is close, but not perfect on some switches
     $namemap = xCAT::MacMap::walkoid($session,$ifDescr);
  }
  unless ($namemap) {
    return;
  }
  #print "namemap=" . Dumper($namemap) . "\n";

  my $iftovlanmap = xCAT::MacMap::walkoid($session, $vmVlan, silentfail=>1); 
  #print "iftovlanmap=" . Dumper($iftovlanmap) . "\n";

  my $trunktovlanmap = xCAT::MacMap::walkoid($session, $vlanTrunkPortNativeVlan, silentfail=>1); #for trunk ports, we are interested in the native vlan
  #print "trunktovlanmap=" . Dumper($trunktovlanmap) . "\n";

  my %ret=();
  if (defined($iftovlanmap) or defined($trunktovlanmap)) { 
      foreach my $portid (keys %{$namemap}) {
	  my $switchport = $namemap->{$portid};
	  foreach my $portname (@ports) { 
	      unless (xCAT::MacMap::namesmatch($portname,$switchport)) {
		  next;
	      }
        
	      if (defined  $iftovlanmap->{$portid}) {
		  $ret{$portname}=[$iftovlanmap->{$portid}];
	      } elsif (defined  $trunktovlanmap->{$portid}){ 
		  $ret{$portname}=[$trunktovlanmap->{$portid}];
	      } else {
		  $ret{$portname}=['NA'];
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
   
    print "Cisco\n";
    #Verify if the edition is in use by another NMS station or device. 
    #The edition is not in use if you see this message: no MIB objects contained under subtree:
    my $tmp = xCAT::MacMap::walkoid($session,$vtpVlanEditTable); 
    #print "tmp=" . Dumper($tmp) . "\n";
    
    #Set the vtpVlanEditOperation to the copy state(2). This allows to create the VLAN.
    my @ret= xCAT::SwitchHandler::setoid($session, $vtpVlanEditOperation, 1, 2, 'INTEGER'); 
    #if ($ret[0] != 0) { return @ret; }
    
    #set vtpVlanEditBufferOwner in order to makethe current owner of the edit permission visible 
    my $username="xcat";
    my @ret=xCAT::SwitchHandler::setoid($session,$vtpVlanEditBufferOwner, 1, $username, 'OCTET');
    if ($ret[0] != 0) { 
	$ret[1]="Set vtpVlanEditBufferOwner $vtpVlanEditBufferOwner.1 to $username.\n" .$ret[1];
	return @ret;
    }
    
    #my $tmp = xCAT::MacMap::walkoid($session, $vtpVlanEditOperation);
    #print "tmp=" . Dumper($tmp) . "\n";
    
    #my $tmp = xCAT::MacMap::walkoid($session, $vtpVlanEditBufferOwner);
    #print "tmp=" . Dumper($tmp) . "\n";
    
    #set vtpVlanEditRowStatus to createAndGo(4)
    my @ret= xCAT::SwitchHandler::setoid($session, $vtpVlanEditRowStatus, $vlan_id, 4, 'INTEGER'); 
    if ($ret[0] != 0) { 
	$ret[1]="Set vtpVlanEditRowStatus $vtpVlanEditRowStatus.$vlan_id to 4.\n" . $ret[1];
	return @ret;
    }
    
    #set vtpVlanEditType to ethernet (1)
    my @ret= xCAT::SwitchHandler::setoid($session,$vtpVlanEditType, $vlan_id, 1, 'INTEGER'); 
    if ($ret[0] != 0) { 
	$ret[1]="Set vtpVlanEditType $vtpVlanEditType.$vlan_id to 1.\n" . $ret[1];
	return @ret;
    }
    
    #set vtpVlanEditName to xcat_vlan_#
    my @ret= xCAT::SwitchHandler::setoid($session,$vtpVlanEditName, $vlan_id, $vlan_name, 'OCTET'); 
    if ($ret[0] != 0) { 
	$ret[1]="Set vtpVlanEditName $vtpVlanEditName.$vlan_id to $vlan_name.\n" . $ret[1];
	return @ret;
    }
    
    #Set the vtpVlanEditDot10Said. This is the VLAN number + 100000 translated to hexadecimal. 
    my $num=100000 + $vlan_id;
    my $hex_num=sprintf("%x", $num);
    my @ret= xCAT::SwitchHandler::setoid($session,$vtpVlanEditDot10Said, $vlan_id, $hex_num, 'OCTETHEX'); 
    #if ($ret[0] != 0) { 
    #	$ret[1]="Set vtpVlanEditDot10Said $vtpVlanEditDot10Said.$vlan_id to $hex_num.\n" . $ret[1];
    	#return @ret;
    #}
    
    #apply the changes, set vtpVlanEditOperation.1 to apply (3)
    my @ret= xCAT::SwitchHandler::setoid($session, $vtpVlanEditOperation, 1, 3, 'INTEGER'); 
    if ($ret[0] != 0) { 
	$ret[1]="Set vtpVlanEditOperation $vtpVlanEditOperation.1 to 3.\n" . $ret[1];
	return @ret;
    }
    
    #release the edition buffer, set vtpVlanEditOperation.1 to release (4)
    my @ret= xCAT::SwitchHandler::setoid($session, $vtpVlanEditOperation, 1, 4, 'INTEGER'); 
    if ($ret[0] != 0) { 
	$ret[1]="Set vtpVlanEditOperation $vtpVlanEditOperation.1 to 4.\n" . $ret[1];
	return @ret;
    }


    return (0, "");
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
    my @ports=@_;
    
    #print "Add ports @ports to vla $vlan_id.\n";

    #add ports to the vlan.  
    if (@ports > 0) {
	  my $namemap = xCAT::MacMap::walkoid($session,$ifName);
	  #namemap is the mapping of ifIndex->(human readable name)
	  if ($namemap) {
	      my $ifnamesupport=0; #Assume broken ifnamesupport until proven good... (Nortel switch)
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
	  unless ($namemap) { #Failback to ifDescr.  ifDescr is close, but not perfect on some switches
	      $namemap = xCAT::MacMap::walkoid($session, $ifDescr);
	  }
	  unless ($namemap) {
	      return;
	  }
	  #print "namemap=" . Dumper($namemap) . "\n";
	  
	  my $trunkportstate = xCAT::MacMap::walkoid($session,$vlanTrunkPortDynamicState);
	  #print "trunkportstate=" . Dumper($trunkportstate) . "\n";
 
	  my $iftovlanmap = xCAT::MacMap::walkoid($session, $vmVlan, silentfail=>1); 
	  #print "iftovlanmap=" . Dumper($iftovlanmap) . "\n";
	  my $trunktovlanmap = xCAT::MacMap::walkoid($session, $vlanTrunkPortNativeVlan, silentfail=>1); 
	  #print "trunktovlanmap=" . Dumper($trunktovlanmap) . "\n";

	  #get current vlan type (static, dynamic or trunk)
	  my $vlantypemap = xCAT::MacMap::walkoid($session, $vmVlanType, silentfail=>1);  
	  #print "vlantypemap=" . Dumper($vlantypemap) . "\n";
 
                 
	  foreach my $portid (keys %{$namemap}) {
	      my $switchport = $namemap->{$portid};
	      foreach my $portname (@ports) { 
	  	  unless (xCAT::MacMap::namesmatch($portname,$switchport)) {
		      next;
		  }


                  ### set the port to trunk mode
                  print "portid=$portid\n";
                  # TODO: need testing in cisco's env for how to set a port as access mode through snmpset? 
                  # Can setting vlanTrunkPortDot1qTunnel or cltcDot1qTunnelMode helps?
		  if ($trunkportstate->{$portid} != 1) {
		      my @ret = xCAT::SwitchHandler::setoid($session, $vlanTrunkPortEncapsulationType, $portid, 4, 'INTEGER');
		      if ($ret[0] != 0) { 
		  	  $ret[1]="Set vlanTrunkPortEncapsulationType $vlanTrunkPortEncapsulationType.$portid to 4(dot1Q).\n" . $ret[1];
		  	  return @ret;
		      }
		      my @ret = xCAT::SwitchHandler::setoid($session, $vlanTrunkPortDynamicState, $portid, 1, 'INTEGER');
		      if ($ret[0] != 0) { 
		  	  $ret[1]="Set vlanTrunkPortDynamicState $vlanTrunkPortDynamicState.$portid to 1.\n" . $ret[1];
		  	  return @ret;
		      }
		  }

		  ### set trunk native vlan id
		  my $native_vlanid=1;
                  if ((exists($vlantypemap->{$portid})) && ($vlantypemap->{$portid} < 3)) { #the port was set to access mode before
		      if ((exists($iftovlanmap->{$portid})) && ($iftovlanmap->{$portid} > 0)) {
			  $native_vlanid=$iftovlanmap->{$portid};
		      }
		  } else { #the port is originally set to trunk mode
		      if ((exists($trunktovlanmap->{$portid})) && ($trunktovlanmap->{$portid} > 0)) {
			  $native_vlanid=$trunktovlanmap->{$portid};
		      } elsif ((exists($iftovlanmap->{$portid})) && ($iftovlanmap->{$portid} > 0)) {
			  $native_vlanid=$iftovlanmap->{$portid};
		      }
		  }
                  print "*** native_vlanid=$native_vlanid\n";
		  my @ret = xCAT::SwitchHandler::setoid($session, $vlanTrunkPortNativeVlan, $portid, $native_vlanid, 'INTEGER');
		  if ($ret[0] != 0) { 
		      $ret[1]="Set native vlan for port $portid to $native_vlanid ($vlanTrunkPortNativeVlan.$portid to $native_vlanid).\n" . $ret[1];
		      return @ret;
		  }


		  ### allow this vlan on the port 
		  my $data = $session->get([$vlanTrunkPortVlansEnabled, $portid]);
		  my @a = split(//, $data);
		  foreach (@a) {
		      my $num=unpack("C*", $_);
		      $_= sprintf ("%02x",$num);
		  }
		  if ((exists($vlantypemap->{$portid})) && ($vlantypemap->{$portid} < 3)) {
		      #if originally this port was in access or dynamic mode, only enable original vlan and this tagged vlan
		      #reset the matrix
                      #print "***was access mode\n";
		      foreach (@a) {
		        $_="00";
		      } 
                      #add native vlan id in the matrix
		      my $index  = int($native_vlanid / 8);
                      my $offset = $native_vlanid % 8;
                      my $num = hex($a[$index]) | $HexConv{$offset};
		      $a[$index] = sprintf("%02x", $num);
                      #print "index=$index, offset=$offset\n";

                      #add current vlan id in the matrix
		      $index  = int($vlan_id / 8);
                      $offset  = $vlan_id % 8;
                      $num = hex($a[$index]) | $HexConv{$offset};
		      $a[$index] = sprintf("%02x", $num);
		  } else { 
                      #if this port was trunk mode before, add this tagged vlan in the matrix
                     # print "***was trunk mode\n";
		      my $index  = int($vlan_id / 8);
		      my $offset  = $vlan_id % 8;
		      my $num = hex($a[$index]) | $HexConv{$offset};
		      $a[$index] = sprintf("%02x", $num);
		  }
		  #print "a=@a\n";
		  foreach (@a) {
		      $_=hex($_);
		      $_=pack("C*", $_);
		  } 
		  my $s = join(//, @a);
		  my @ret = xCAT::SwitchHandler::setoid($session, $vlanTrunkPortVlansEnabled, $portid, $s, 'OCTET');
		  #print "**** ret=@ret\n";
		  if ($ret[0] != 0) { 
		      $ret[1]="Allow vlan on port $portid ($vlanTrunkPortVlansEnabled.$portid=$s).\n" . $ret[1];
		      return @ret;
		  }
	      
		  
                  ### security feature
		  if ($::XCATSITEVALS{vlansecurity} eq '1') {
		      #set root guard on the port
		      my @ret = xCAT::SwitchHandler::setoid($session, $stpxRootGuardConfigEnabled, $portname, 1, 'INTEGER');
		      if ($ret[0] != 0) { 
			  $ret[1]="Set root guard for port $portname to enable ($stpxRootGuardConfigEnabled.$portname=1).\n" . $ret[1];
			  return @ret;
		      }
		      #set bpdu guard on the port
		      my @ret = xCAT::SwitchHandler::setoid($session, $stpxFastStartPortBpduGuardMode, $portname, 1, 'INTEGER');
		      if ($ret[0] != 0) { 
			  $ret[1]="Set bpdu guard for port $portname to enalbe ($stpxFastStartPortBpduGuardMode.$portname=1).\n" . $ret[1];
			  return @ret;
		      }
		  }
                  last;
	      }
	  }
    }

    return (0, "");
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
        
    #Verify if the edition is in use by another NMS station or device. 
    #The edition is not in use if you see this message: no MIB objects contained under subtree:
    my $tmp = xCAT::MacMap::walkoid($session,$vtpVlanEditTable); 
    #print "tmp=" . Dumper($tmp) . "\n";
    
    #Set the vtpVlanEditOperation to the copy state(2). This allows to delete the VLAN.
    my @ret= xCAT::SwitchHandler::setoid($session, $vtpVlanEditOperation, 1, 2, 'INTEGER'); 
    if ($ret[0] != 0) { 
	$ret[1]="Set vtpVlanEditOperation $vtpVlanEditOperation.1 to 3 (copy state).\n" . $ret[1];
	return @ret;
    }
    
    #set vtpVlanEditBufferOwner in order to makethe current owner of the edit permission visible 
    my $username="xcat";
    my @ret=xCAT::SwitchHandler::setoid($session,$vtpVlanEditBufferOwner, 1, $username, 'OCTET');
    if ($ret[0] != 0) { 
	$ret[1]="Set vtpVlanEditBufferOwner $vtpVlanEditBufferOwner.1 to $username.\n" . $ret[1];
	return @ret;
    }
    
    #set vtpVlanEditRowStatus to destroy(6)
    my @ret= xCAT::SwitchHandler::setoid($session, $vtpVlanEditRowStatus, $vlan_id, 6, 'INTEGER'); 
    if ($ret[0] != 0) { 
	$ret[1]="Set vtpVlanEditRowStatus $vtpVlanEditRowStatus.$vlan_id to 6 (destroy).\n" . $ret[1];
	return @ret;
    }
 
    #apply the changes, set vtpVlanEditOperation.1 to apply (3)
    my @ret= xCAT::SwitchHandler::setoid($session, $vtpVlanEditOperation, 1, 3, 'INTEGER'); 
    if ($ret[0] != 0) { 
	$ret[1]="Set $vtpVlanEditOperation.1 to 3 (apply).\n" . $ret[1];
	return @ret;
    }
   
    #release the edition buffer, set vtpVlanEditOperation.1 to release (4)
    my @ret= xCAT::SwitchHandler::setoid($session, $vtpVlanEditOperation, 1, 4, 'INTEGER'); 
    if ($ret[0] != 0) { 
	$ret[1]="Set vtpVlanEditOperation $vtpVlanEditOperation.1 to 4 (release).\n" . $ret[1];
	return @ret;
    }

    #my $iftovlanmap = xCAT::MacMap::walkoid($session, $vmVlan, silentfail=>1); 
    #print "iftovlanmap=" . Dumper($iftovlanmap) . "\n";
    #foreach (keys(%$iftovlanmap)) {
    #	if($iftovlanmap->{$_} == $vlan_id) { 
	    #my @ret= xCAT::SwitchHandler::setoid($session, $vmVlan, $_, 1, 'INTEGER'); 
	    #if ($ret[0] != 0) { 
            #	$ret[1]="Set $vmVlan.$_ to 1.\n" . $ret[1];
	    #   return @ret;
	    #}
    #	}
    #}
    #my $trunktovlanmap = xCAT::MacMap::walkoid($session, $vlanTrunkPortNativeVlan, silentfail=>1); #for trunk ports, we are interested in the native vlan
    #print "trunktovlanmap=" . Dumper($trunktovlanmap) . "\n";
    #foreach (keys(%$trunktovlanmap)) {
    #	if($trunktovlanmap->{$_} == $vlan_id) { 
	   # my @ret= xCAT::SwitchHandler::setoid($session, $vlanTrunkPortNativeVlan, $_, 1, 'INTEGER'); 
	   # if ($ret[0] != 0) { 
	   #	$ret[1]="Set $vlanTrunkPortNativeVlan.$_ to 1.\n" . $ret[1];
	   #	return @ret;
	   # }
    #	}
    #}


    return (0, "");;
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
    my @ports = @_;
    

    if (@ports > 0) {
	my $namemap = xCAT::MacMap::walkoid($session,$ifName);
	#namemap is the mapping of ifIndex->(human readable name)
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
	unless ($namemap) { #Failback to ifDescr.  ifDescr is close, but not perfect on some switches
	    $namemap = xCAT::MacMap::walkoid($session, $ifDescr);
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
		
                #remove the vlan id from the vlanTrunkPortVlansEnabled.port  matrix		  
		my $data = $session->get([$vlanTrunkPortVlansEnabled, $portid]);
		my @a = split(//, $data);
		foreach (@a) {
		    my $num=unpack("C*", $_);
		    $_= sprintf ("%02x",$num);
		}
		#print "a=@a\n";
		my $index  = int($vlan_id / 8);
		my $offset  = $vlan_id % 8;
		my $num = hex($a[$index]) & (~$HexConv{$offset});
		$a[$index] = sprintf("%02x", $num);
		
		#print "a=@a\n";
		
		foreach (@a) {
		    $_=hex($_);
		    $_=pack("C*", $_);
		} 
		
		my $s = join(//, @a);
		my @ret = xCAT::SwitchHandler::setoid($session, $vlanTrunkPortVlansEnabled, $portid, $s, 'OCTET');
		if ($ret[0] != 0) { 
		    $ret[1]="Set vlanTrunkPortVlansEnabled $vlanTrunkPortVlansEnabled.$portid to $s.\n" . $ret[1];
		    return @ret;
		}

		last;
	    }
	}
    }

    return (0, "");;
}



1;
