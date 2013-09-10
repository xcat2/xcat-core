#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_monitoring::snmpmon;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use IO::File;
use xCAT::Utils;
use xCAT::MsgUtils;
use xCAT::TableUtils;
use xCAT::NodeRange;
use xCAT_monitoring::monitorctrl;
use Sys::Hostname;
use File::Path qw/mkpath/;

#print "xCAT_monitoring::snmpmon loaded\n";
1;


my $confdir;
if(xCAT::Utils->isAIX()){
  $::snmpconfdir = "/opt/freeware/etc";
} else {
  $::snmpconfdir = "/usr/share/snmp";
}



#-------------------------------------------------------------------------------
=head1  xCAT_monitoring:snmpmon  
=head2    Package Description
  xCAT monitoring plugin package to handle SNMP monitoring. 

=cut
#-------------------------------------------------------------------------------

#--------------------------------------------------------------------------------
=head3    start
      This function gets called by the monitorctrl module when monstart command 
     gets called and when xcatd starts.  
    Arguments:
       p_nodes -- a pointer to an arrays of nodes to be monitored. null means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only. 
                2 means both localhost and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
      (return code, message) 
      if the callback is set, use callback to display the status and error. 
=cut
#--------------------------------------------------------------------------------
sub start {
  print "snmpmon:start called\n";
  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::snmpmon/) {
    $noderef=shift;
  }
  my $scope=shift;
  my $callback=shift;

  my $localhostname=hostname();

  # get the PID of the currently running snmptrapd if it is running.
  # then stop it and restart it again so that it reads our new
  # snmptrapd.conf configuration file. Then the process
  my $pid;
  chomp($pid= `/bin/ps -ef | /bin/grep snmptrapd | /bin/grep -v grep | /bin/awk '{print \$2}'`);
  if($pid){
    `/bin/kill -9 $pid`;
  }
  # start it up again!
  if(xCAT::Utils->isAIX()){
    system("/opt/freeware/sbin/snmptrapd -m ALL");
  } else {
    system("/usr/sbin/snmptrapd -m ALL");
  }

  # get the PID of the currently running snmpd if it is running.
  # if it's running then we just leave.  Otherwise, if we don't get A PID, then we
  # assume that it isn't running, and start it up again!
  chomp($pid= `/bin/ps -ef | /bin/grep snmpd | /bin/grep -v grep | /bin/awk '{print \$2}'`);
  unless($pid){
    # start it up!
    system("/usr/sbin/snmpd");         
  }

  if ($scope) {
    #enable alerts on the nodes
    if ($callback) {
      my $rsp={};
      $rsp->{data}->[0]="$localhostname: enabling SNMP alert...";
      $callback->($rsp);
    }
    #enable bmcs if any
    configBMC(1, $noderef, $callback);

    #enable MMAs if any
    configMPA(1, $noderef, $callback);

    #enable MMAs if any
    configSwitch(1, $noderef, $callback);
  }
  
  if ($callback) {
    my $rsp={};
    $rsp->{data}->[0]="$localhostname: done.";
    $callback->($rsp);
  }
  
  return (0, "started")
}



#--------------------------------------------------------------------------------
=head3    stop
      This function gets called by the monitorctrl module when monstop command gets called. 
    Arguments:
       p_nodes -- a pointer to an arrays of nodes to be stoped for monitoring. null means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only. 
                2 means both monservers and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
      (return code, message) 
      if the callback is set, use callback to display the status and error. 
=cut
#--------------------------------------------------------------------------------
sub stop {
  print "snmpmon:stop called\n";
  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::snmpmon/) {
    $noderef=shift;
  }
  my $scope=shift;
  my $callback=shift;

  my $localhostname=hostname();

  if ($scope) {
    if ($callback) {
      my $rsp={};
      $rsp->{data}->[0]="$localhostname: disabling SNMP alert...";
      $callback->($rsp);
    }
    #disable MMAs if any
    configMPA(0, $noderef, $callback);

    #disable BMC so that it stop senging alerts (PETs) to this node
    configBMC(0, $noderef, $callback);

    #disable switches so that it stop senging alerts (PETs) to this node
    configSwitch(0, $noderef, $callback);
  }
 

  # now check to see if the daemon is running.  If it is then we need to resart or stop?
  # it with the new snmptrapd.conf file that will not forward events to RMC.
  chomp(my $pid= `/bin/ps -ef | /bin/grep snmptrapd | /bin/grep -v grep | /bin/awk '{print \$2}'`);
  if($pid){
    `/bin/kill -9 $pid`;
    # start it up again!
    #system("/usr/sbin/snmptrapd");
  }

  if ($callback) {
    my $rsp={};
    $rsp->{data}->[0]="$localhostname: done.";
    $callback->($rsp);
  }

  return (0, "stopped");
}


#--------------------------------------------------------------------------------
=head3    supportNodeStatusMon
    This function is called by the monitorctrl module to check
    if SNMP can help monitoring and returning the node status.
    SNMP does not support this function.
    
    Arguments:
        none
    Returns:
         0  
=cut
#--------------------------------------------------------------------------------
sub supportNodeStatusMon {
  return 0;
}



#--------------------------------------------------------------------------------
=head3   startNodeStatusMon
    This function is called by the monitorctrl module when monstart gets called and
    when xcatd starts. It starts monitoring the node status and feed them back
    to xCAT.  
    Arguments:
       p_nodes -- a pointer to an arrays of nodes to be monitored. null means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means loca lhost only.  
                2 means both localhost and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    note: p_nodes and scope are ignored by this plugin.
    Returns:
      (return code, message) 
      if the callback is set, use callback to display the status and error. 
    This function is called by the monitorctrl module to tell
=cut
#--------------------------------------------------------------------------------
sub startNodeStatusMon {
  return (1, "This function is not supported.");
}


#--------------------------------------------------------------------------------
=head3   stopNodeStatusMon
    This function is called by the monitorctrl module when monstop command is issued.
    It stops feeding the node status info back to xCAT. 
    Arguments:
       p_nodes -- a pointer to an arrays of nodes to stoped for monitoring. null means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means local host only. 
                2 means both local host and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    note: p_nodes and scope are ignored by this plugin.
    Returns:
      (return code, message) 
      if the callback is set, use callback to display the status and error. 
=cut
#--------------------------------------------------------------------------------
sub stopNodeStatusMon {
  return (1, "This function is not supported.");
}



#--------------------------------------------------------------------------------
=head3    config
      This function configures the cluster for the given nodes.  
      This function is called when moncfg command is issued or when xcatd starts
      on the service node. It will configure the cluster to include the given nodes within
      the monitoring doamin. 
    Arguments:
       p_nodes -- a pointer to an arrays of nodes to be added for monitoring. none means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only. 
                2 means localhost and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
       (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub config {
  print "snmpmon:config called\n";
  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::snmpmon/) {
    $noderef=shift;
  }
  my $scope=shift;
  my $callback=shift;

  my $localhostname=hostname();

  # check supported snmp package
  my $cmd;
  my @snmpPkg = `/bin/rpm -qa | grep snmp`;
  my $pkginstalled = grep(/net-snmp/, @snmpPkg);

  if (!$pkginstalled) {
    if ($callback) {
      my $rsp={};
      $rsp->{data}->[0]="$localhostname: net-snmp is not installed.";
      $callback->($rsp);
    }
    return (1, "net-snmp is not installed")
  } else {
    my ($ret, $err)=configSNMP(2, $noderef, $callback);
    if ($ret != 0) { return ($ret, $err);}
  }

  #configure mail to enabling receiving mails from trap handler
  configMail();


  if ($scope) {
    if ($callback) {
      my $rsp={};
      $rsp->{data}->[0]="$localhostname: setting up SNMP alert destination....";
      $callback->($rsp);
    }
    #enable bmcs if any
    configBMC(2, $noderef, $callback);

    #enable MMAs if any
    configMPA(2, $noderef, $callback);

    #enable switches if any
    configSwitch(2, $noderef, $callback);
  }

  if ($callback) {
    my $rsp={};
    $rsp->{data}->[0]="$localhostname: done.";
    $callback->($rsp);
  }

  return (0, "")
}

#--------------------------------------------------------------------------------
=head3    deconfig
      This function de-configures the cluster for the given nodes.  
      This function is called when mondecfg command is issued by the user. 
      It should remove the given nodes from the product for monitoring.
    Arguments:
       p_nodes -- a pointer to an arrays of nodes to be removed for monitoring. none means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means local host only. 
                2 means both local host and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
       (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub deconfig {
  print "snmpmon:deconfig called\n";
  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::snmpmon/) {
    $noderef=shift;
  }
  my $scope=shift;
  my $callback=shift;
  my $localhostname=hostname();

  if (-f "$::snmpconfdir/snmptrapd.conf.orig"){
    # copy back the old one
    `mv -f $::snmpconfdir/snmptrapd.conf.orig $::snmpconfdir/snmptrapd.conf`;
  } else {
    if (-f "$::snmpconfdir/snmptrapd.conf"){

      # if the file exists, delete all entries that have xcat_traphandler
      my $cmd = "grep -v  xcat_traphandler $::snmpconfdir/snmptrapd.conf ";
      $cmd .= "> $::snmpconfdir/snmptrapd.conf.unconfig ";
      `$cmd`;

      # move it back to the snmptrapd.conf file.                     
      `mv -f $::snmpconfdir/snmptrapd.conf.unconfig $::snmpconfdir/snmptrapd.conf`;
    }
  }

  deconfigSNMP(2,$noderef,$callback);


  if ($scope) {
    if ($callback) {
      my $rsp={};
      $rsp->{data}->[0]="$localhostname: removing SNMP destination....";
      $callback->($rsp);
    }
    #remove snmp destination for switches
    configSwitch(3, $noderef, $callback);
  }

  if ($callback) {
    my $rsp={};
    $rsp->{data}->[0]="$localhostname: done.";
    $callback->($rsp);
  }

  return (0, "");
}

#--------------------------------------------------------------------------------
=head3    deconfigSNMP
      This function remove xcat_traphanlder from the snmptrapd.conf file,
      remove the node configurations from snmptrapd.conf, and
      restarts the snmptrapd with the new configuration.
    Arguments:
      none.
    Returns:
      (return code, message)      
=cut
=cut
#--------------------------------------------------------------------------------
sub deconfigSNMP {
   return (0, ""); 
}

#--------------------------------------------------------------------------------
=head3    configBMC
      This function configures BMC to setup the snmp destination, enable/disable
    PEF policy table entry number 1. 
    Arguments:
      actioon -- 0 disable alert. 1 enable alert. 2 setup snmp destination
            
      p_nodes -- a pointer to an arrays of nodes to be monitored. null means all.
      callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
      (return code, message)      
=cut
#--------------------------------------------------------------------------------
sub configBMC {
  my $action=shift;
  my $noderef=shift;
  my $callback=shift;

  my $ret_text="";
  my $ret_val=0;

  #the identification of this node
  my @hostinfo=xCAT::NetworkUtils->determinehostname();
  my $isSV=xCAT::Utils->isServiceNode();
  my  %iphash=();
  foreach(@hostinfo) {$iphash{$_}=1;}
  if (!$isSV) { $iphash{'noservicenode'}=1;}
 
  my $pPairHash=xCAT_monitoring::monitorctrl->getNodeMonServerPair($noderef, 0);
  if (ref($pPairHash) eq 'ARRAY') { 
      if ($callback) {
	  my $rsp={};
	  if ($ret_val) {
	      $rsp->{data}->[0]=$pPairHash->[1];
	  } 
	  $callback->($rsp);
      } else {
	  xCAT::MsgUtils->message('S', "[mon]: " . $pPairHash->[1]);
      } 
      return (0, "");
  }

    
  my %masterhash=();
  my @node_a=();
  my $table=xCAT::Table->new("ipmi");
  if ($table) {
    my @tmp1=$table->getAllNodeAttribs(['node','bmc']);
    if (@tmp1 > 0) {
      foreach(@tmp1) {
        my $node=$_->{node};
        my $bmc=$_->{bmc};
        if (! exists($pPairHash->{$node})) {next;}
        
        my $pairs=$pPairHash->{$node};
        my @a_temp=split(':',$pairs); 
        my $monserver=$a_temp[0];
        my $master=$a_temp[1];

        if ($monserver) { 
          if (!$iphash{$monserver}) { next;} #skip if has sn but not localhost
        } else { 
          if ($isSV) { next; } #skip if does not have sn but localhost is a sn
        }
        
        push(@node_a, $node);

        # find the master node and add the node in the hash
        if(exists($masterhash{$master})) {
	  my $ref=$masterhash{$master};
          push(@$ref, $node); 
	} else { $masterhash{$master}=[$node]; } 
      } #foreach
    }
    $table->close();
  }

  if (@node_a==0){ return ($ret_val, $ret_text);} #nothing to handle
  #print "configBMC: node_a=@node_a\n";

  #now doing the real thing: enable PEF alert policy table
  my $noderange=join(',',@node_a );
  if ($action==0) {
    print "XCATBYPASS=Y rspconfig $noderange alert=dis\n";
    my $result = `XCATBYPASS=Y rspconfig $noderange alert=dis 2>&1`;
    if ($?) {
	$ret_val=1;
	xCAT::MsgUtils->message('S', "[mon]: Changeing SNMP PEF policy for IPMI nodes $noderange:\n  $result\n");
	$ret_text .= "Changeing SNMP PEF policy for IPMI nodes $noderange:\n  $result\n";
    } 
  } elsif ($action==1) {
    print "XCATBYPASS=Y rspconfig $noderange alert=en\n";
    my $result = `XCATBYPASS=Y rspconfig $noderange alert=en 2>&1`;
    if ($?) {
	$ret_val=1;
	xCAT::MsgUtils->message('S', "[mon]: Changeing SNMP PEF policy for IPMI nodes $noderange:\n  $result\n");
	$ret_text .= "Changeing SNMP PEF policy for IPMI nodes $noderange:\n  $result\n";
    } 
  } else {
    #setup the snmp destination
    foreach (keys(%masterhash)) {
      my $ref2=$masterhash{$_};
      if (@$ref2==0) { next;}
      my $nr2=join(',', @$ref2);
      my @tmp_a=xCAT::NetworkUtils::toIP($_);
      my $ptmp=$tmp_a[0];
      if ($ptmp->[0]>0) {
         xCAT::MsgUtils->message('S', "[mon]: Converting to IP: $ptmp->[1]\n"); 
	 $ret_val=1;
         $ret_text .= "Converting to IP: $ptmp->[1]\n";
      } else {
        print "XCATBYPASS=Y rspconfig $nr2 snmpdest=$ptmp->[1]\n";
        my $result2 = `XCATBYPASS=Y rspconfig $nr2 snmpdest=$ptmp->[1] 2>&1`;
        if ($?) {
	    $ret_val=1;
	    xCAT::MsgUtils->message('S', "[mon]: Changing SNMP destination for IPMI nodes $nr2:\n  $result2\n");
	    $ret_text .= "Changing SNMP destination for IPMI nodes $nr2:\n  $result2\n";
        }
      }
    }
  }

  if ($callback) {
    my $rsp={};
    if ($ret_val) {
      $rsp->{data}->[0]="$ret_text";
    } 
    $callback->($rsp);
  } 

  return ($ret_val, $ret_text);
  
}


#--------------------------------------------------------------------------------
=head3    configMPA
      This function configures Blade Center Management Module to setup the snmp destination, 
      enable/disable remote alert notification. 
    Arguments:
      actioon -- 1 enable remote alert notification. 0 disable remote alert notification. 
                 2 setting up snmp destination.
      p_nodes -- a pointer to an arrays of nodes to be monitored. null means all.
      callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
      (return code, message)      
=cut
#--------------------------------------------------------------------------------
sub configMPA {
  my $action=shift;
  my $noderef=shift;
  my $callback=shift;

  my $ret_val=0;
  my $ret_text="";

  #the identification of this node
  my @hostinfo=xCAT::NetworkUtils->determinehostname();
  my $isSV=xCAT::Utils->isServiceNode();
  my %iphash=();
  foreach(@hostinfo) {$iphash{$_}=1;}
  if (!$isSV) { $iphash{'noservicenode'}=1;}

  my $all=0;
  my %nodehash=();
  if ((!$noderef) || (@$noderef==0)) {$all=1;}
  else {
    foreach(@$noderef) { $nodehash{$_}=1;}
  }

  my %mpa_hash=();
  my %masterhash=();
  my @node_a=();
  my $table=xCAT::Table->new("mp");
  if ($table) {
    my @tmp1=$table->getAllNodeAttribs(['node','mpa']);
    if (@tmp1 > 0) {
      foreach(@tmp1) {
        my $node=$_->{node};
        my $mpa=$_->{mpa};
        if ((!$all) && (!exists($nodehash{$node})) && (!exists($nodehash{$mpa}))) {next;}
        
        if ($mpa_hash{$mpa}) { next;} #already handled

        $mpa_hash{$mpa}=1;
        
        my $pHash=xCAT_monitoring::monitorctrl->getNodeMonServerPair([$mpa], 0);
	if (ref($pHash) eq 'ARRAY') { 
	    if ($callback) {
		my $rsp={};
		if ($ret_val) {
		    $rsp->{data}->[0]=$pHash->[1];
		} 
		$callback->($rsp);
	    } else {
		xCAT::MsgUtils->message('S', "[mon]: " . $pHash->[1]);
	    } 
	    return (0, "");
	}

        my $pairs=$pHash->{$mpa}; 
        my @a_temp=split(':',$pairs); 
        my $monserver=$a_temp[0];
        my $master=$a_temp[1];

        if ($monserver) { 
          if (!$iphash{$monserver}) { next;} #skip if has sn but not localhost
        } else { 
          if ($isSV) { next; } #skip if does not have sn but localhost is a sn
        }
        
        push(@node_a, $mpa);

        # find the master node and add the node in the hash
        if(exists($masterhash{$master})) {
	  my $ref=$masterhash{$master};
          push(@$ref, $mpa); 
	} else { $masterhash{$master}=[$mpa]; } 
      } #foreach
    }
    $table->close();
  }

  if (@node_a==0){ return ($ret_val, $ret_text);} #nothing to handle
  #print "configMPA: node_a=@node_a\n";


  #now doing the real thing: enable PEF alert policy table
  my $noderange=join(',',@node_a );
  if ($action==0) {
    print "XCATBYPASS=Y rspconfig $noderange alert=dis\n";
    my $result = `XCATBYPASS=Y rspconfig $noderange alert=dis 2>&1`;
    if ($?) {
	$ret_val=1;
	xCAT::MsgUtils->message('S', "[mon]: Changeing SNMP remote alert profile for Blade Center MM $noderange:\n  $result\n");
	$ret_text .= "Changeing SNMP remote alert profile for Blade Center MM $noderange:\n  $result\n";
    }
  } elsif ($action==1)  {
    print "XCATBYPASS=Y rspconfig $noderange alert=en\n";
    my $result = `XCATBYPASS=Y rspconfig $noderange alert=en 2>&1`;
    if ($?) {
	$ret_val=1;
	xCAT::MsgUtils->message('S', "[mon]: Changeing SNMP remote alert profile for Blade Center MM $noderange:\n  $result\n");
	$ret_text .= "Changeing SNMP remote alert profile for Blade Center MM $noderange:\n  $result\n";
    }
  } else {
    #setup the snmp destination
    foreach (keys(%masterhash)) {
      my $ref2=$masterhash{$_};
      if (@$ref2==0) { next;}
      my $nr2=join(',', @$ref2);
      my @tmp_a=xCAT::NetworkUtils::toIP($_);
      my $ptmp=$tmp_a[0];
      if ($ptmp->[0]>0) {
         xCAT::MsgUtils->message('S', "[mon]: Converting to IP: $ptmp->[1]\n"); 
	 $ret_val=1;
         $ret_text .= "Converting to IP: $ptmp->[1]\n";
      } else {
        print "XCATBYPASS=Y rspconfig $nr2 snmpdest=$ptmp->[1]\n";
        my $result2 = `XCATBYPASS=Y rspconfig $nr2 snmpdest=$ptmp->[1] 2>&1`;
        if ($?) {
	    $ret_val=1;
	    xCAT::MsgUtils->message('S', "[mon]: Changing SNMP destination for Blade Center MM $nr2:\n  $result2\n");
	    $ret_text .= "Changing SNMP destination for Blade Center MM $nr2:\n  $result2\n";  
        }
      }
    }
  }

  if ($callback) {
    my $rsp={};
    if ($ret_val) {
      $rsp->{data}->[0]="$ret_text";
    }
    $callback->($rsp);
  } 

  return ($ret_val, $ret_text);
}


#--------------------------------------------------------------------------------
=head3    configSwitch
      This function configures switches to setup the snmp destination, enable/disable
    alerts. 
    Arguments:
      actioon -- 0 disable alert (called mon monstop). 
                 1 enable alert. (called by monstart)
                 2 setup snmp destination (called by moncfg)
                 3 remove the snmp destination (called by mondecfg)
    p_nodes -- a pointer to an arrays of nodes to be monitored. null means all.
      callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
      (return code, message)      
=cut
#--------------------------------------------------------------------------------
sub configSwitch {
  my $action=shift;
  my $noderef=shift;
  my $callback=shift;

  my $ret_text="";
  my $ret_val=0;

  #the identification of this node
  my @hostinfo=xCAT::NetworkUtils->determinehostname();
  my $isSV=xCAT::Utils->isServiceNode();
  my  %iphash=();
  foreach(@hostinfo) {$iphash{$_}=1;}
  if (!$isSV) { $iphash{'noservicenode'}=1;}
 
  my $pPairHash=xCAT_monitoring::monitorctrl->getNodeMonServerPair($noderef, 0);
  if (ref($pPairHash) eq 'ARRAY') { 
      if ($callback) {
	  my $rsp={};
	  if ($ret_val) {
	      $rsp->{data}->[0]=$pPairHash->[1];
	  } 
	  $callback->($rsp);
      } else {
	  xCAT::MsgUtils->message('S', "[mon]: " . $pPairHash->[1]);
      } 
      return (0, "");
  }

    
  my @node_a=();
  my $table=xCAT::Table->new('switches',-create=>0);
  if ($table) {
      my @tmp1=$table->getAllAttribs(('switch'));
      if (defined(@tmp1) && (@tmp1 > 0)) {
	  foreach(@tmp1) {
	      my @switches_tmp=noderange($_->{switch});
	      if (@switches_tmp==0) { push @switches_tmp, $_->{switch}; } 
	      foreach my $node (@switches_tmp) {
		  if (! exists($pPairHash->{$node})) {next;}
		  my $pairs=$pPairHash->{$node};
		  my @a_temp=split(':',$pairs); 
		  my $monserver=$a_temp[0];
		  my $master=$a_temp[1];
		  
		  if ($monserver) { 
		      if (!$iphash{$monserver}) { next;} #skip if has sn but not localhost
		  } else { 
		      if ($isSV) { next; } #skip if does not have sn but localhost is a sn
		  }
		  
		  push(@node_a, $node);
	      } #foreach
	  }
	  $table->close();
      }
  }

  if (@node_a==0){ return ($ret_val, $ret_text);} #nothing to handle
  print "configSwitch: node_a=@node_a\n";

  #now doing the real thing: enable PEF alert policy table
  foreach my $noderange (@node_a) {
      $ret_val=0;
      $ret_text = "";
      if ($action==0) {
	  print "XCATBYPASS=Y rspconfig $noderange alert=dis\n";
	  my $result = `XCATBYPASS=Y rspconfig $noderange alert=dis 2>&1`;
	  if (($result =~ /Error:/) || ($?)) {
	      $ret_val=1;
	      xCAT::MsgUtils->message('S', "[mon]: Disabling SNMP alert for switches $noderange:\n  $result\n");
	      $ret_text .= "Disabling SNMP alert.\n  $result\n";
	  } 
      } elsif ($action==1) {
	  print "XCATBYPASS=Y rspconfig $noderange alert=en\n";
	  my $result = `XCATBYPASS=Y rspconfig $noderange alert=en 2>&1`;
	  if (($result =~ /Error:/) || ($?)) {
	      $ret_val=1;
	      xCAT::MsgUtils->message('S', "[mon]: Enabling SNMP alert for switches $noderange:\n  $result\n");
	      $ret_text .= "Enabling SNMP alert.\n  $result\n";
	  } 
      } elsif ($action==2) {
	  print "XCATBYPASS=Y rspconfig $noderange sshcfg\n";
	  my $result = `XCATBYPASS=Y rspconfig $noderange sshcfg 2>&1`;
	  if ($result !~ /enabled/) {
	      print "XCATBYPASS=Y rspconfig $noderange sshcfg=en\n";
	      my $result = `XCATBYPASS=Y rspconfig $noderange sshcfg=en 2>&1`;
	      if (($result =~ /Error:/) || ($?)) {
		  $ret_val=1;
		  xCAT::MsgUtils->message('S', "[mon]: Setting up SSH for switches $noderange:\n  $result\n");
		  $ret_text .= "Setting up SSH.\n  $result\n";
	      }
	  } else {
	      print "XCATBYPASS=Y rspconfig $noderange snmpcfg\n";
	      my $result = `XCATBYPASS=Y rspconfig $noderange snmpcfg 2>&1`;
	      if ($result !~ /enabled/) {
		  print "XCATBYPASS=Y rspconfig $noderange snmpcfg=en\n";
		  my $result = `XCATBYPASS=Y rspconfig $noderange snmpcfg=en 2>&1`;
		  if (($result =~ /Error:/) || ($?)) {
		      $ret_val=1;
		      xCAT::MsgUtils->message('S', "[mon]: Enabling SNMP for switches $noderange:\n  $result\n");
		      $ret_text .= "Enabling SNMP.\n  $result\n";
		  }
	      } else {
		  #setup the snmp destination
		  my $pairs=$pPairHash->{$noderange};
		  my @a_temp=split(':',$pairs); 
		  my $monserver=$a_temp[0];
		  my $master=$a_temp[1];
		  my @tmp_a=xCAT::NetworkUtils::toIP($master);
		  my $ptmp=$tmp_a[0];
		  if ($ptmp->[0]>0) {
		      xCAT::MsgUtils->message('S', "[mon]: Converting to IP: $ptmp->[1]\n"); 
		      $ret_val=1;
		      $ret_text .= "Converting to IP: $ptmp->[1]\n";
		  } else {
		      print "XCATBYPASS=Y rspconfig $noderange snmpdest=$ptmp->[1]\n";
		      my $result = `XCATBYPASS=Y rspconfig $noderange snmpdest=$ptmp->[1] 2>&1`;
		      if (($result =~ /Error:/) || ($?)) {
			  $ret_val=1;
			  xCAT::MsgUtils->message('S', "[mon]: Changing SNMP destination for switches $noderange:\n  $result\n");
			  $ret_text .= "Changing SNMP destination\n  $result\n";
		      }
		  }
	      }
	  }
	  
      } elsif ($action==3) {
	  #remove the snmp destination
	  my $pairs=$pPairHash->{$noderange};
	  my @a_temp=split(':',$pairs); 
	  my $monserver=$a_temp[0];
	  my $master=$a_temp[1];
	  my @tmp_a=xCAT::NetworkUtils::toIP($master);
	  my $ptmp=$tmp_a[0];
	  if ($ptmp->[0]>0) {
	      xCAT::MsgUtils->message('S', "[mon]: Converting to IP: $ptmp->[1]\n"); 
	      $ret_val=1;
	      $ret_text .= "Converting to IP: $ptmp->[1]\n";
	  } else {
	      print "XCATBYPASS=Y rspconfig $noderange snmpdest=$ptmp->[1] remove\n";
	      my $result = `XCATBYPASS=Y rspconfig $noderange snmpdest=$ptmp->[1] remove 2>&1`;
	      if (($result =~ /Error:/) || ($?)) {
		  $ret_val=1;
		  xCAT::MsgUtils->message('S', "[mon]: Removing SNMP destination for switches $noderange:\n  $result\n");
		  $ret_text .= "Removing SNMP destination\n  $result\n";
	      }
	  }
      }      

      if ($callback) {
	  my $rsp={};
	  if ($ret_val) {
	      $rsp->{data}->[0]="$noderange: $ret_text";
	  } else {
	      $rsp->{data}->[0]="$noderange: done.\n $ret_text" 
	  }
	  $callback->($rsp);
      } 
  }

 

  return ($ret_val, $ret_text);
  
}




#--------------------------------------------------------------------------------
=head3    configSNMP
      This function puts xcat_traphanlder into the snmptrapd.conf file and
      restarts the snmptrapd with the new configuration.
    Arguments:
      none.
    Returns:
      (return code, message)      
=cut
#--------------------------------------------------------------------------------
sub configSNMP {
  my $action=shift;
  my $noderef=shift;
  my $callback=shift;

  my $ret_val=0;
  my $ret_text="";

    print "configSNMP called \n";
  my $isSN=xCAT::Utils->isServiceNode();
  my $master=xCAT::TableUtils->get_site_Master();
  my $cmd;

  # now move $::snmpconfdir/snmptrapd.conf to $::snmpconfdir/snmptrapd.conf.orig
  # if it exists.
  mkpath("$::snmpconfdir");
  if (-f "$::snmpconfdir/snmptrapd.conf"){

    # if the file exists and has references to xcat_traphandler in mn or 'forward' in sn
    # then there is nothing that needs to be done.
    if ($isSN) {
      `/bin/grep "forward default $master" $::snmpconfdir/snmptrapd.conf > /dev/null`;
    } else {
      `/bin/grep  xcat_traphandler $::snmpconfdir/snmptrapd.conf > /dev/null`;
    }

    # if the return code is 1, then there is no xcat_traphandler, or 'forward'
    # references and we need to put them in.
    if($? >> 8){     
      # back up the original file.
      `/bin/cp -f $::snmpconfdir/snmptrapd.conf $::snmpconfdir/snmptrapd.conf.orig`;

      # if the file exists and does not have  "authCommunity execute,net public" then add it.
      open(FILE1, "<$::snmpconfdir/snmptrapd.conf");
      open(FILE, ">$::snmpconfdir/snmptrapd.conf.tmp");
      my $found=0;
      my $forward_handled=0;
      while (readline(FILE1)) {
        if (/\s*authCommunity.*public/) {
          $found=1;
          if (!/\s*authCommunity\s*.*execute.*public/) {
            s/authCommunity\s*(.*)\s* public/authCommunity $1,execute public/;  #modify it to have 'execute' if found
          }
          if (!/\s*authCommunity\s*.*net.*public/) {
            s/authCommunity\s*(.*)\s* public/authCommunity $1,net public/;  #modify it to have 'net' if found
          }
        } elsif (/\s*forward\s*default/) {
          if (($isSN) && (!/$master/)) {
            s/\s*forward/\#forward/; #comment out the old one
            if (!$forward_handled) {
              print FILE "forward default $master\n"; 
              $forward_handled=1;
            }
          }
        }

        print FILE $_;
      } 
      


      if (!$found) { #add new one if not found
        print FILE "authCommunity log,execute,net public\n"; 
      }

      # now add the new traphandle commands:
      if (!$isSN) {
        print FILE "traphandle default $::XCATROOT/sbin/xcat_traphandler\n";
      }

      close(FILE1);
      close(FILE);
      `mv -f $::snmpconfdir/snmptrapd.conf.tmp $::snmpconfdir/snmptrapd.conf`;
    }
  }
  else {     # The snmptrapd.conf file does not exists
    # create the file:
    my $handle = new IO::File;
    open($handle, ">$::snmpconfdir/snmptrapd.conf");
    print $handle "authCommunity log,execute,net public\n";
    if ($isSN) {
      print $handle "forward default $master\n"; #forward the trap from sn to mn
    } else {
      print $handle "traphandle default $::XCATROOT/sbin/xcat_traphandler\n";
    }
    close($handle);
  }


  # Configure SNMPv3 on AIX
#  if(xCAT::Utils->isAIX()){
    #the identification of this node
    my @hostinfo=xCAT::NetworkUtils->determinehostname();
    my $isSV=xCAT::Utils->isServiceNode();
    my %iphash=();
    foreach(@hostinfo) {$iphash{$_}=1;}
    if (!$isSV) { $iphash{'noservicenode'}=1;}

    my $all=0;
    my %nodehash=();
    if ((!$noderef) || (@$noderef==0)) {$all=1;}
    else {
      foreach(@$noderef) { $nodehash{$_}=1;}
    }

    my %mpa_hash=();
    my %masterhash=();
    my @node_a=();
    my $table=xCAT::Table->new("mp");
    if ($table) {
      my @tmp1=$table->getAllNodeAttribs(['node','mpa']);
      if (@tmp1 > 0) {
        foreach(@tmp1) {
          my $node=$_->{node};
          my $mpa=$_->{mpa};
          if ((!$all) && (!exists($nodehash{$node})) && (!exists($nodehash{$mpa}))) {next;}
  
          if ($mpa_hash{$mpa}) { next;} #already handled

          $mpa_hash{$mpa}=1;

          my $pHash=xCAT_monitoring::monitorctrl->getNodeMonServerPair([$mpa], 0);
          if (ref($pHash) eq 'ARRAY') {
            if ($callback) {
                my $rsp={};
                if ($ret_val) {
                    $rsp->{data}->[0]=$pHash->[1];
                }
                $callback->($rsp);
            } else {
                xCAT::MsgUtils->message('S', "[mon]: " . $pHash->[1]);
            }
            return (0, "");
          }

          my $pairs=$pHash->{$mpa};
          my @a_temp=split(':',$pairs);
          my $monserver=$a_temp[0];
          my $master=$a_temp[1];
  
          if ($monserver) {
            if (!$iphash{$monserver}) { next;} #skip if has sn but not localhost
          } else {
            if ($isSV) { next; } #skip if does not have sn but localhost is a sn
          }

          push(@node_a, $mpa);

          # find the master node and add the node in the hash
          if(exists($masterhash{$master})) {
            my $ref=$masterhash{$master};
            push(@$ref, $mpa);
          } else { $masterhash{$master}=[$mpa]; }
        } #foreach
      }
      $table->close();
    }

    if (@node_a==0){ return ($ret_val, $ret_text);} #nothing to handle

    # Read username, password, and mac from DB.
    foreach my $mpa ( @node_a ) {
      my $mac;
      my $user;
      my $password;

      my $mpatable=xCAT::Table->new("mpa");
      if ($mpatable) {
        my $mpa_a = $mpatable->getAttribs({mpa => $mpa}, 'username', 'password');
        if ( $mpa_a and $mpa_a->{username} and $mpa_a->{password} ) {
          $user = $mpa_a->{username};
          $password = $mpa_a->{password};
        } else {
          xCAT::MsgUtils->message('E', "No username or password found for $mpa");
        }
      }

      my $mactable=xCAT::Table->new("mac");
      if ( $mactable ) {
        my $mac_a = $mactable->getAttribs({node=> $mpa}, 'mac');
        if ( $mac_a and $mac_a->{mac} ) {
          $mac = $mac_a->{mac};
        } else {
          xCAT::MsgUtils->message('E', "No mac found for $mpa");
        }
      }

      my $found1=0;
      my $found2=0;
      if ( $mac and $user and $password ) {
        #write configuration file
        open(FILE1, "<$::snmpconfdir/snmptrapd.conf");
        open(FILE, ">$::snmpconfdir/snmptrapd.conf.tmp");
        while (readline(FILE1)) {
          if (/\s*authUser.*$user/) {
            $found1=1;
            if (!/\s*authUser\s*.*execute.*$user/) {
              s/authUser\s*(.*)\s* $user/authUser $1,execute $user/;  #modify it to have 'execute' if found
            }
          }
          if (!/\s*authUser\s*.*net.*$user/) {
            s/authUser\s*(.*)\s* $user/authUser $1,net $user/;  #modify it to have 'net' if found
          }

          if (/\s*createUser.*$mac.*$user.*$password/) {
            $found2=1;
          }

          print FILE $_;
        }

      }
     
      if (!$found1) { #add new one if not found
        print FILE "authUser log,execute,net $user\n";
      }

      if (!$found2) {
        print FILE "createUser -e 0x8000045001$mac $user SHA $password DES\n";
      }
      
      close(FILE1);
      close(FILE);
      `mv -f $::snmpconfdir/snmptrapd.conf.tmp $::snmpconfdir/snmptrapd.conf`;
    }
#  }


  # TODO: put the mib files to /usr/share/snmp/mibs
  return (0, "");
}

#--------------------------------------------------------------------------------
=head3    configMail
      This function adds a "alerts" mail aliase so that the mail notification 
      from the trap handler can be received. It the alerts already exists, this 
      function does nothing. 
      TODO: configure mail servers on MS to forward mails to MS 
    Arguments:
      none
    Returns:
      (return code, message)      
=cut
#--------------------------------------------------------------------------------
sub configMail {
  #check if "alerts" is in the /etc/aliases file
  if (-f "/etc/aliases"){ 
    # if the file exists, check if alerts is in
    `/bin/grep -e ^alerts /etc/aliases > /dev/null`;
    if ($? ==0) { return (0, "") };
  }
  
  #make a alerts aliase, forwarding the mail to the root of local host.
  `echo "alerts:  root" >> /etc/aliases`; 

  #make it effective
  `newaliases`;

  return (0, "");
}




#--------------------------------------------------------------------------------
=head3    processSettingChanges
      This function gets called when the setting for this monitoring plugin 
      has been changed in the monsetting table.
    Arguments:
       none.
    Returns:
        0 for successful.
        non-0 for not successful.
=cut
#--------------------------------------------------------------------------------
sub processSettingChanges {
  return 0;
}

#--------------------------------------------------------------------------------
=head3    getDiscription
      This function returns the detailed description of the plugin inluding the
     valid values for its settings in the monsetting tabel. 
     Arguments:
        none
    Returns:
        The description.
=cut
#--------------------------------------------------------------------------------
sub getDescription {
  return 
"  Description:
    snmpmon sets up the snmptrapd on the management server to receive SNMP
    traps for different nodes. It also sets the trap destination for Blade 
    Center Management Module, RSA II, IPMIs that are managed by the xCAT cluster. 
    xCAT has categorized some events into different event priorities (critical, 
    warning and informational) based on the MIBs we know such as MM, RSA II and 
    IPMI. All the unknown events are categorized as 'warning'. By default, 
    the xCAT trap handler will log all events into the syslog and only
    email the critical and the warning events to the mail alias called 'alerts'. 
    You can use the settings to override the default behavior.
    Use command 'monstart snmpmon' to star monitoring and 'monstop snmpmon' 
    to stop it. 
  Settings:
    ignore:  specifies the events that will be ignored. It's a comma separated 
        pairs of oid=value. For example, 
        spTrapAppType=4,spTrapMsgText=~power,spTrapMsgText=Hello there.
    email:  specifies the events that will get email notification.
    log:    specifies the events that will get logged.
    runcmd#:specifies the events that will be passed to the user defined scripts.
    cmds#:  specifies the command names that will be invoked for the events 
            specified in the runcmd# row. '#' is a number.
    db:     specifies the events that will be logged into the eventlog table
            in xCAT database.
    
    Special keywords for specifying events:
      All -- all events.
      None -- none of the events.
      Critical -- all critical events.
      Warning -- all warning events.
      Informational -- all informational events.

    For example, you can have the following setting:
      email  Critical,spTrapMsgText=~Test this,spTrapMsgText=Hello there
      This means send email for all the critical events and events with spTrapMsgText
      contains the phrase 'Test this' or equals 'Hello there'.\n"  
}

#--------------------------------------------------------------------------------
=head3    getNodesMonServers
      This function checks the given nodes, if they are bmc/ipmi nodes, the monserver pairs of
     the nodes will be returned. If the nodes are managed by MM, the monserver pairs of their
     mpa will be returned.  
     Arguments:
       p_nodes -- a pointer to an arrays of nodes to be added for monitoring. none means all.
       callback -- the callback pointer for error and status displaying. It can be null.
   Returns: 
      A pointer to a hash table with monserver pairs as the key and an array
                     pointer of nodes as the value. 
                     For example: { "sv1,ma1"=>[node1,node2], "sv2,ma2"=>node3...}
         The pair is in the format of "monserver,monmaser". First one is the monitoring service 
      node ip/hostname that faces the mn and the second one is the monitoring service 
      node ip/hostname that faces the cn. 
      The value of the first one can be "noservicenode" meaning that there is no service node 
      for that node. In this case the second one is the site master. 
      It retuens a pointer to an array if there is an error. Format is [code, message].
=cut
#--------------------------------------------------------------------------------
sub getNodesMonServers
{
  print "snmpmon:getNodesMonServer called\n";
  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::snmpmon/) {
    $noderef=shift;
  }
  my $callback=shift;

  my $ret={};
  my $localhostname=hostname();
  my $pPairHash=xCAT_monitoring::monitorctrl->getNodeMonServerPair($noderef, 0);

  if (ref($pPairHash) eq 'ARRAY') { 
      return $pPairHash;               
  } 


  #check for blades, only returns the MPAs and their monservers
  my %mpa_hash=();
  my $table=xCAT::Table->new("mp");
  if ($table) {
    my @tmp1=$table->getAllNodeAttribs(['node','mpa']);
    if (@tmp1 > 0) {
      foreach(@tmp1) {
        my $node=$_->{node};
        my $mpa=$_->{mpa};
        if ((!exists($pPairHash->{$node})) && (!exists($pPairHash->{$mpa}))) {next;} #not in input
        
        #if  (exists($pPairHash->{$node})) { delete($pPairHash->{$node}); }
        if ($mpa_hash{$mpa}) { next;} #already handled

        $mpa_hash{$mpa}=1;
        
        my $pairs;
        if (exists($pPairHash->{$mpa})) { 
          $pairs=$pPairHash->{$mpa}; 
        } else {
          my $pHash=xCAT_monitoring::monitorctrl->getNodeMonServerPair([$mpa], 0);
	  if (ref($pHash) eq 'ARRAY') { 
	      return $pHash;               
	  } 

          $pairs=$pHash->{$mpa};
        }

        if (exists($ret->{$pairs})) {
          my $pa=$ret->{$pairs};
          push(@$pa, $mpa);
        }
        else {
          $ret->{$pairs}=[$mpa];
        }

        #if (exists($pPairHash->{$mpa}))) { delete($pPairHash->{$mpa}); } 
      } #foreach
    }
    $table->close();
  }


  #check BMC/IPMI nodes   
  $table=xCAT::Table->new("ipmi");
  if ($table) {
    my @tmp1=$table->getAllNodeAttribs(['node','bmc']);
    if (@tmp1 > 0) {
      foreach(@tmp1) {
        my $node=$_->{node};
        my $bmc=$_->{bmc};
        if (! exists($pPairHash->{$node})) {next;}
        my $pairs=$pPairHash->{$node};

        if (exists($ret->{$pairs})) {
          my $pa=$ret->{$pairs};
          push(@$pa, $node);
        }
        else {
          $ret->{$pairs}=[$node];
        }

        #delete($pPairHash->{$node});
      } #foreach
    }
    $table->close();
  }

  #check swithes
  my $table=xCAT::Table->new('switches',-create=>0);
  if ($table) {
      my @tmp1=$table->getAllAttribs(('switch'));
      if (defined(@tmp1) && (@tmp1 > 0)) {
	  foreach(@tmp1) {
	      my @switches_tmp=noderange($_->{switch});
	      if (@switches_tmp==0) { push @switches_tmp, $_->{switch}; } 
	      foreach my $node (@switches_tmp) {
		  if (! exists($pPairHash->{$node})) {next;}
		  my $pairs=$pPairHash->{$node};
		  
		  if (exists($ret->{$pairs})) {
		      my $pa=$ret->{$pairs};
		      push(@$pa, $node);
		  }
		  else {
		      $ret->{$pairs}=[$node];
		  }
	      }
	  }
      }
      $table->close();
  }


  return $ret;
}
