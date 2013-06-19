#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_monitoring::rmcmon;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use xCAT::NodeRange;
use Sys::Hostname;
use Socket;
use xCAT::Utils;
use xCAT::InstUtils;
use xCAT::NetworkUtils;
use xCAT::GlobalDef;
use xCAT_monitoring::monitorctrl;
use xCAT_monitoring::rmcmetrix;
use xCAT::MsgUtils;
use xCAT::DBobjUtils;
#print "xCAT_monitoring::rmcmon loaded\n";
1;


#TODO: script to define sensors on the nodes.
#TODO: how to push the sensor scripts to nodes?
#TODO: monitoring HMC with old RSCT and new RSCT

#-------------------------------------------------------------------------------
=head1  xCAT_monitoring:rmcmon  
=head2    Package Description
  xCAT monitoring plugin package to handle RMC monitoring.
=cut
#-------------------------------------------------------------------------------

#--------------------------------------------------------------------------------
=head3    start
      This function gets called by the monitorctrl module
      when xcatd starts and when monstart command is issued by the user. 
      It starts the daemons and does necessary startup process for the RMC monitoring.
      It also queries the RMC for its currently monitored
      nodes which will, in tern, compared with the nodes
      in the input parameter. It asks RMC to add or delete
      nodes according to the comparison so that the nodes
      monitored by RMC are in sync with the nodes currently
      in the xCAT cluster.
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
  print "rmcmon::start called\n";
  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::rmcmon/) {
    $noderef=shift;
  }
  my $scope=shift;
  my $callback=shift;

  my $localhostname=hostname();
    
  #assume the server is the current node.
  #check if rsct is installed and running
  if (! -e "/usr/bin/lsrsrc") {
    if ($callback) {
      my $rsp={};
      $rsp->{data}->[0]="$localhostname: RSCT is not installed.";
      $callback->($rsp);
    }
    return (1, "RSCT is not installed.\n");
  }

  my $result;
  chomp(my $pid= `/bin/ps -ef | /bin/grep rmcd | /bin/grep -v grep | /bin/awk '{print \$2}'`);
  unless($pid){
    #restart rmc daemon
    $result=`startsrc -s ctrmc`;
    if ($?) {
      if ($callback) {
        my $rsp={};
        $rsp->{data}->[0]="$localhostname: RMC deamon cannot be started.";
        $callback->($rsp);
      }
      return (1, "RMC deamon cannot be started\n");
    }
    `startsrc -s  IBM.MgmtDomainRM`;
  }

  #restore the association
  if ($callback) { #this is the case when monstart is called, not the xcatd starts
    #get all the current 
    my %assocHash=();
    my $result=`LANG=C /usr/bin/lscondresp -x -D:_:  2>&1`;
    if ($?==0) {
      chomp($result); 
      my @tmp=split('\n', $result);
      foreach my $line (@tmp) {
	my @tmp1=split(':_:', $line);
        if (@tmp1 < 4) { next; }
        my $cond=$tmp1[0];
        my $resp=$tmp1[1];
        if ($tmp1[3] =~ /Not|not/) { $assocHash{"$cond:_:$resp"}=0; } 
        else {$assocHash{"$cond:_:$resp"}=1;}
      }
    }

    #start the associations that are saved in /var/log/rmcmon
    my $isSV=xCAT::Utils->isServiceNode();
    my $fname="/var/log/rmcmon";
    if (! -f "$fname") { 
      if ($isSV) { $fname="$::XCATROOT/lib/perl/xCAT_monitoring/rmc/pred_assoc_sn"; }
      else { $fname="$::XCATROOT/lib/perl/xCAT_monitoring/rmc/pred_assoc_mn"; }
    }
    if (-f "$fname") {
      if (open(FILE, "<$fname")) {
        while (readline(FILE)) {
          chomp($_); 
	  my @tmp1=split(':_:', $_);
          if (@tmp1 < 4) { next; }
          my $cond=$tmp1[0];
          my $resp=$tmp1[1];
          if ($tmp1[3] !~ /Not|not/) { #active
	    if ((!exists($assocHash{"$cond:_:$resp"})) || ($assocHash{"$cond:_:$resp"}==0)) {
	      $result=`/usr/bin/startcondresp $cond $resp 2>&1`;
              if (($?) && ($result !~ /2618-244|2618-008/)) { #started
                my $rsp={};
                $rsp->{data}->[0]="$localhostname: $result";
                $callback->($rsp);
	      }
	    }
	  } else { #inactive
	    if (!exists($assocHash{"$cond:_:$resp"})) { 
              $result=`/usr/bin/mkcondresp $cond $resp  2>&1`; 
              if (($?) && ($result !~ /2618-201|2618-008/)) { #resource already defined
                my $rsp={};
                $rsp->{data}->[0]="$localhostname: $result";
                $callback->($rsp);
	      }
            } elsif ($assocHash{"$cond:_:$resp"}==1) { 
              $result=`/usr/bin/stopcondresp $cond $resp  2>&1`;
              if (($?) && ($result !~ /2618-264/)) { #stoped
                my $rsp={};
                $rsp->{data}->[0]="$localhostname: $result";
                $callback->($rsp);
	      }
            }
	  }
        }
        close(FILE);
      } 
    } 
  } #if ($callback)
  my $montype = 'event';
  my $entry = undef;
  my $conftable =  xCAT::Table->new('monsetting');
  $entry = $conftable->getAttribs({'name'=>'rmcmon','key'=>'montype'}, 'value');
  if($entry){
	  $montype = $entry->{value};
  }
  $conftable->close;

  my @metrixconf = xCAT_monitoring::rmcmetrix::get_metrix_conf();
  if($montype =~ /perf/){
    while(@metrixconf){
      my ($rsrc, $rname, $attrlist, $minute);
      $rsrc  = shift @metrixconf;
      $rname = shift @metrixconf;
      $attrlist = shift @metrixconf;
      $minute = shift @metrixconf;
      xCAT::Utils->runcmd("$::XCATROOT/sbin/rmcmon/rmcmetrixmon init $rsrc $rname $attrlist $minute", 0);
    }
  }
  if(xCAT::Utils->isServiceNode()){
    xCAT::Utils->runcmd("$::XCATROOT/sbin/rmcmon/rmcmetrixmon init rrdserver", 0);
  }
  if ($scope) {
    #get a list of managed nodes
    $result=`/usr/bin/lsrsrc-api -s IBM.MngNode::::Name 2>&1`;  
    if ($?) {
      if ($result !~ /2612-023/) {#2612-023 no resources found error
        reportError( $result, $callback); 
        return (1,$result);
      }
      $result='';
    }
    chomp($result);
    my @rmc_nodes=split(/\n/, $result);
    
    #start the rmc daemons for its children
    if (@rmc_nodes > 0) {
      my $nodestring=join(',', @rmc_nodes);
      $result=`XCATBYPASS=Y $::XCATROOT/bin/xdsh $nodestring startsrc -s ctrmc 2>&1`;
      if (($result) && ($result !~ /0513-029/)) { #0513-029 multiple instance not supported.
        reportError( $result, $callback); 
      }
    }
  }
  if ($callback) {
    my $rsp={};
    $rsp->{data}->[0]="$localhostname: done.";
    $callback->($rsp);
  }

  return (0, "started");
}





#--------------------------------------------------------------------------------
=head3    stop
      This function gets called when monstop command is issued by the user. 
      It stops the monitoring on all nodes, stops the RMC daemons.
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
  print "rmcmon::stop called\n";
  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::rmcmon/) {
    $noderef=shift;
  }
  my $scope=shift;
  my $callback=shift;

  my $localhostname=hostname();

  
  xCAT::Utils->runcmd("$::XCATROOT/sbin/rmcmon/rmcmetrixmon clean", 0);
  if(xCAT::Utils->isServiceNode()){
    xCAT::Utils->runcmd("$::XCATROOT/sbin/rmcmon/rmcmetrixmon clean rrdserver", 0);
  } 
  my $result;
  chomp(my $pid= `/bin/ps -ef | /bin/grep rmcd | /bin/grep -v grep | /bin/awk '{print \$2}'`);
  if ($pid){
    #save all the association in to /var/log/rmcmon
    `rm -f /var/log/rmcmon`;
    my $result=`LANG=C /usr/bin/lscondresp -x -D:_:  2>&1`;
    if ($?==0) {
      if (open(FILE, ">/var/log/rmcmon")) {
        print FILE $result;
        close(FILE);
      }

      #stop condition-response associtations
      chomp($result); 
      my @tmp=split('\n', $result);
      foreach my $line (@tmp) {
	my @tmp1=split(':_:', $line);
        if (@tmp1 < 4) { next; }
        if ($tmp1[3] !~ /Not|not/) {
	  my $result=`/usr/bin/stopcondresp $tmp1[0] $tmp1[1]  2>&1`;
          if (($?) && ($result !~ /2618-264/)) { #stoped
	    if ($callback) {
              my $rsp={};
              $rsp->{data}->[0]="$localhostname: $result";
              $callback->($rsp);
	    }
	  }
        }
      } #foreach
    } # if ($pid)
  
    #restop the rmc daemon
    #$result=`stopsrc -s ctrmc`;
    #if ($?) {
    #  if ($callback) {
    #    my $rsp={};
    #    $rsp->{data}->[0]="$localhostname: RMC deamon cannot be stopped.";
    #    $callback->($rsp);
    #  }
    #  return (1, "RMC deamon cannot be stopped\n");
    #}
  }

  if ($scope) {
    my $pPairHash=xCAT_monitoring::monitorctrl->getMonServer($noderef);
    if (ref($pPairHash) eq 'ARRAY') {
	reportError($pPairHash->[1], $callback);
	return (1, "");	
    }

 
    #the identification of this node
    my @hostinfo=xCAT::NetworkUtils->determinehostname();
    my $isSV=xCAT::Utils->isServiceNode();

    my %iphash=();
    foreach(@hostinfo) {$iphash{$_}=1;}
    if (!$isSV) { $iphash{'noservicenode'}=1;}

    foreach my $key (keys (%$pPairHash)) {
      my @key_a=split(':', $key);
      if (! $iphash{$key_a[0]}) { next;}  
      my $mon_nodes=$pPairHash->{$key};
      
      #figure out what nodes to stop
      my @nodes_to_stop=();
      if ($mon_nodes) {
        foreach(@$mon_nodes) {
          my $node=$_->[0];
          my $nodetype=$_->[1];
          if (($nodetype) && ($nodetype =~ /$::NODETYPE_OSI/)) { 
	    push(@nodes_to_stop, $node);
          }  
        }     
      }

      if (@nodes_to_stop > 0) {
        my $nodestring=join(',', @nodes_to_stop);
        $result=`XCATBYPASS=Y $::XCATROOT/bin/xdsh $nodestring "/bin/ps -ef | /bin/grep rmcd | /bin/grep -v grep | /bin/awk '{if (\\\$2>0) system(\\\"stopsrc -s ctrmc\\\")}' 2>&1"`;

        if (($result) && ($result !~ /0513-044/)){ #0513-0544 is normal value
	  reportError($result, $callback);
        }
      }
    }
  }

  return (0, "stopped");
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
  #print "rmcmon:config called\n";
  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::rmcmon/) {
    $noderef=shift;
  }
  my $scope=shift;
  my $callback=shift;

  my $localhostname=hostname();
    
  #assume the server is the current node.
  #check if rsct is installed and running
  if (! -e "/usr/bin/lsrsrc") {
    if ($callback) {
      my $rsp={};
      $rsp->{data}->[0]="$localhostname: RSCT is not installed.";
      $callback->($rsp);
    }
    return (1, "RSCT is not installed.\n");
  }

  my $result;
  chomp(my $pid= `/bin/ps -ef | /bin/grep rmcd | /bin/grep -v grep | /bin/awk '{print \$2}'`);
  unless($pid){
    #restart rmc daemon
    $result=`startsrc -s ctrmc`;
    if ($?) {
     if ($callback) {
       my $rsp={};
       $rsp->{data}->[0]="$localhostname: RMC deamon cannot be started.";
       $callback->($rsp);
     }
     return (1, "RMC deamon cannot be started\n");
    }
  }

  #enable remote client connection
  `/usr/bin/rmcctrl -p`;
  
 
  #the identification of this node
  my @hostinfo=xCAT::NetworkUtils->determinehostname();
  my $isSV=xCAT::Utils->isServiceNode();
  my %iphash=();
  foreach(@hostinfo) {$iphash{$_}=1;}
  if (!$isSV) { $iphash{'noservicenode'}=1;}

  #create conditions/responses/sensors on the service node or mn
  my $result=`/usr/sbin/rsct/install/bin/ctversion`;
  my $rsct_ver;
  if (!$?) {
      chomp($result);
      my @tempa=split(/ /, $result); 
      if (@tempa>1) {
          $rsct_ver=$tempa[1]; 
      }
  }
  my $version_string;
  if ($rsct_ver) {$version_string="RSCT_VER=$rsct_ver"; } 

  my $result;
  if ($isSV) {
      $result=`$version_string $::XCATROOT/sbin/rmcmon/mkrmcresources $::XCATROOT/lib/perl/xCAT_monitoring/rmc/resources/sn 2>&1`;  } else  {
	  $result=`$version_string $::XCATROOT/sbin/rmcmon/mkrmcresources $::XCATROOT/lib/perl/xCAT_monitoring/rmc/resources/mn 2>&1`;
  }      
  if ($?) {
    my $error= "Error when creating predefined resources on $localhostname:\n$result";
    reportError($error, $callback);
  }
  if(!$isSV){
    xCAT::Utils->runcmd("chtab key='rmetrics_IBM.Host' monsetting.name=rmcmon monsetting.value='PctTotalTimeIdle,PctTotalTimeWait,PctTotalTimeUser,PctTotalTimeKernel,PctRealMemFree:1'", 0);
    xCAT::Utils->runcmd("chtab key='rmetrics_IBM.EthernetDevice' monsetting.name=rmcmon monsetting.value='RecByteRate,RecPacketRate,XmitByteRate,XmitPacketRate:1'", 0);
  }

  my $pPairHash=xCAT_monitoring::monitorctrl->getMonServer($noderef);
  if (ref($pPairHash) eq 'ARRAY') {
      reportError($pPairHash->[1], $callback);
      return (1, "");	
  }

  foreach my $key (keys (%$pPairHash)) {
    my @key_a=split(':', $key);
    if (! $iphash{$key_a[0]}) { next;} 
    my $mon_nodes=$pPairHash->{$key};

    my $master=$key_a[1];

    #figure out what nodes to add
    my @nodes_to_add=();
    my @hmc_nodes=();
    if ($mon_nodes) {
      foreach(@$mon_nodes) {
        my $node=$_->[0];
        my $nodetype=$_->[1];
        if ($nodetype){ 
	  if ($nodetype =~ /$::NODETYPE_OSI/) { push(@nodes_to_add, $node); }
	  elsif (xCAT::DBobjUtils->getnodetype($node) =~ /$::NODETYPE_HMC/) { push(@hmc_nodes, $node); }
        } 
      }     
    }

    #add new nodes to the RMC cluster
    if (@nodes_to_add> 0) {
      addNodes(\@nodes_to_add, $master, $scope, $callback, 0);
    }

    #add new HMC nodes to the RMC cluster
    if (@hmc_nodes > 0) {
      addNodes(\@hmc_nodes, $master, $scope, $callback, 1);
    }
  }

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
  print "rmcmon:deconfig called\n";
  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::rmcmon/) {
    $noderef=shift;
  }
  my $scope=shift;
  my $callback=shift;
  my $localhostname=hostname();
  my $pPairHash=xCAT_monitoring::monitorctrl->getMonServer($noderef);
  if (ref($pPairHash) eq 'ARRAY') {
      reportError($pPairHash->[1], $callback);
      return (1, "");	
  }
 
  #the identification of this node
  my @hostinfo=xCAT::NetworkUtils->determinehostname();
  my $isSV=xCAT::Utils->isServiceNode();
  my %iphash=();
  foreach(@hostinfo) {$iphash{$_}=1;}
  if (!$isSV) { $iphash{'noservicenode'}=1;}
  if(!$isSV){
    xCAT::Utils->runcmd("chtab -d key='rmetrics_IBM.Host' monsetting", 0);
    xCAT::Utils->runcmd("chtab -d key='rmetrics_IBM.EthernetDevice' monsetting", 0);
  }

  foreach my $key (keys (%$pPairHash)) {
    my @key_a=split(':', $key);
    if (! $iphash{$key_a[0]}) { next;}  
    my $mon_nodes=$pPairHash->{$key};

    my $master=$key_a[1];

    #figure out what nodes to remove
    my @nodes_to_rm=();
    my @hmc_nodes=();
    if ($mon_nodes) {
      foreach(@$mon_nodes) {
        my $node=$_->[0];
        my $nodetype=$_->[1];
        if ($nodetype) {
          if ($nodetype =~ /$::NODETYPE_OSI/) { push(@nodes_to_rm, $node);}
	  elsif (xCAT::DBobjUtils->getnodetype($node) =~ /$::NODETYPE_HMC/) { push(@hmc_nodes, $node); }
        }  
      }     
    }

    #remove nodes from the RMC cluster
    if (@nodes_to_rm > 0) {
      removeNodes(\@nodes_to_rm, $master, $scope, $callback, 0);
    }

    #remove HMC nodes from the RMC cluster
    if (@hmc_nodes > 0) {
      removeNodes(\@hmc_nodes, $master, $scope, $callback, 1);
    }
  } 
}

#--------------------------------------------------------------------------------
=head3    supportNodeStatusMon
    This function is called by the monitorctrl module to check
    if RMC can help monitoring and returning the node status.
    
    Arguments:
        none
    Returns:
         1  
=cut
#--------------------------------------------------------------------------------
sub supportNodeStatusMon {
  #print "rmcmon::supportNodeStatusMon called\n";
  return 1;
}



#--------------------------------------------------------------------------------
=head3   startNodeStatusMon
    This function is called by the monitorctrl module to tell
    RMC to start monitoring the node status and feed them back
    to xCAT. RMC will start setting up the condition/response 
    to monitor the node status changes.  

    Arguments:
       p_nodes -- a pointer to an arrays of nodes for monitoring. none means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means local host only. 
                2 means both local host and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
       (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub startNodeStatusMon {
  print "rmcmon::startNodeStatusMon\n";
  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::rmcmon/) {
    $noderef=shift;
  }
  my $scope=shift;
  my $callback=shift;

  my $localhostname=hostname();
  my $retcode=0;
  my $retmsg="";


  my $isSV=xCAT::Utils->isServiceNode();

  #get all the nodes status from IBM.MngNode class of local host and 
  #the identification of this node
  my $pPairHash=xCAT_monitoring::monitorctrl->getMonServer($noderef);
  if (ref($pPairHash) eq 'ARRAY') {
      reportError($pPairHash->[1], $callback);
      return (1, "");	
  }

  my @hostinfo=xCAT::NetworkUtils->determinehostname();
  my %iphash=();
  foreach(@hostinfo) {$iphash{$_}=1;}
  if (!$isSV) { $iphash{'noservicenode'}=1;}

  my @servicenodes=();
  my %status_hash=();
  foreach my $key (keys (%$pPairHash)) {
    my @key_a=split(':', $key);
    if (! $iphash{$key_a[0]}) { next;}
    my $mon_nodes=$pPairHash->{$key};

    foreach my $nn(@$mon_nodes) {
      my $nodetype=$nn->[1];
      if ($nodetype) {
	if (($nodetype =~ /$::NODETYPE_OSI/)|| (xCAT::DBobjUtils->getnodetype($nn->[0]) =~ /$::NODETYPE_HMC/)) {
          $status_hash{$nn->[0]}=$nn->[2];
        }
      }  
    }
  }

  #get nodestatus from RMC and update the xCAT DB
  ($retcode, $retmsg) = saveRMCNodeStatusToxCAT(\%status_hash);
  if ($retcode != 0) {
    reportError($retmsg, $callback);
  }

 #get rsct version
  my $result=`/usr/sbin/rsct/install/bin/ctversion`;
  my $rsct_ver="0.0.0";
  if (!$?) {
      chomp($result);
      my @tempa=split(/ /, $result); 
      if (@tempa>1) {
          $rsct_ver=$tempa[1]; 
      }
  }
 
  #get setting from the monsetting table
  my $batch=0;
  if (xCAT::Utils->CheckVersion($rsct_ver, "2.3.5.0") >= 0) {
    my %settings=xCAT_monitoring::monitorctrl->getPluginSettings("rmcmon");

    my $batch_string=$settings{'nodeusebatch'};
    if ($batch_string  =~ /1|Yes|yes|YES|Y|y/ ) { $batch=1;}   
  }

  if ($batch) {
      my $result=`startcondresp NodeReachability_B UpdatexCATNodeStatus_B 2>&1`;
      if (($?) && ($result !~ /2618-244|2618-008/)) { #started
	  $retcode=$?;
	  $retmsg="Error start node status monitoring: $result";
	  reportError($retmsg, $callback);
      }
  } else {
    if (!$isSV) {
	#start monitoring the status of mn's immediate children
	my $result=`startcondresp NodeReachability UpdatexCATNodeStatus 2>&1`;
	if (($?) && ($result !~ /2618-244|2618-008/)) { #started
	    $retcode=$?;
	    $retmsg="Error start node status monitoring: $result";
	    reportError($retmsg, $callback);
	}
	
	#start monitoring the status of mn's grandchildren via their service nodes
	$result=`startcondresp NodeReachability_H UpdatexCATNodeStatus 2>&1`;
	if (($?) && ($result !~ /2618-244|2618-008/)) { #started
	    $retcode=$?;
	    $retmsg="Error start node status monitoring: $result";
	    reportError($retmsg, $callback);
	}
    }
  }
  return ($retcode, $retmsg);
}


#--------------------------------------------------------------------------------
=head3   saveRMCNodeStatusToxCAT
    This function gets RMC node status and save them to xCAT database

    Arguments:
        $oldstatus a pointer to a hash table that has the current node status
        $node  the name of the service node to run RMC command from. If null, get from local host. 
    Returns:
        (return code, message)
=cut
#--------------------------------------------------------------------------------
sub saveRMCNodeStatusToxCAT {
  #print "rmcmon::saveRMCNodeStatusToxCAT called\n";
  my $retcode=0;
  my $retmsg="";
  my $statusref=shift;
  if ($statusref =~ /xCAT_monitoring::rmcmon/) {
    $statusref=shift;
  }
  my $node=shift;

  my %status_hash=%$statusref;

  #get all the node status from mn's children
  my $result;
  my @active_nodes=();
  my @inactive_nodes=();
  if ($node) {
    $result=`CT_MANAGEMENT_SCOPE=4 LANG=C /usr/bin/lsrsrc-api -o IBM.MngNode::::$node::Name::Status 2>&1`;
  } else {
    $result=`CT_MANAGEMENT_SCOPE=1 LANG=C /usr/bin/lsrsrc-api -s IBM.MngNode::::Name::Status 2>&1`;
  }

  
  if ($result) {
    my @lines=split('\n', $result);
    #only save the ones that needs to change
    foreach (@lines) {
	my @pairs=split('::', $_);
        if ($pairs[0] eq "ERROR") {
	  $retmsg .= "$_\n";
        }
        else {
          if ($pairs[1]==1) { 
            if ($status_hash{$pairs[0]} ne $::STATUS_ACTIVE) { push @active_nodes,$pairs[0];} 
          }
          else { 
            if ($status_hash{$pairs[0]} ne $::STATUS_INACTIVE) { push @inactive_nodes, $pairs[0];}
          }
        }   
      } 
  }
  

  my %new_node_status=();
  if (@active_nodes>0) {
    $new_node_status{$::STATUS_ACTIVE}=\@active_nodes;
  } 
  if (@inactive_nodes>0) {
    $new_node_status{$::STATUS_INACTIVE}=\@inactive_nodes;
  }
  #only set the node status for the changed ones
  if (keys(%new_node_status) > 0) {
    xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%new_node_status);
  }  

  if ($retmsg) {$retcode=1;}
  else {$retmsg="started";}
 
  return ($retcode, $retmsg);
}




#--------------------------------------------------------------------------------
=head3   stopNodeStatusMon
    This function is called by the monitorctrl module to tell
    RMC to stop feeding the node status info back to xCAT. It will
    stop the condition/response that is monitoring the node status.

    Arguments:
       p_nodes -- a pointer to an arrays of nodes for monitoring. none means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means local host only. 
                2 means both local host and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
        (return code, message)
=cut
#--------------------------------------------------------------------------------
sub stopNodeStatusMon {
  print "rmcmon::stopNodeStatusMon called\n";
  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::rmcmon/) {
    $noderef=shift;
  }
  my $scope=shift;
  my $callback=shift;

  my $retcode=0;
  my $retmsg="";

  my $isSV=xCAT::Utils->isServiceNode();
  my $localhostname=hostname();
 
 #get rsct version
  my $result=`/usr/sbin/rsct/install/bin/ctversion`;
  my $rsct_ver="0.0.0";
  if (!$?) {
      chomp($result);
      my @tempa=split(/ /, $result); 
      if (@tempa>1) {
          $rsct_ver=$tempa[1]; 
      }
  }
 
  #get setting from the monsetting table
  my $batch=0;
  if (xCAT::Utils->CheckVersion($rsct_ver, "2.3.5.0") >= 0) {
    my %settings=xCAT_monitoring::monitorctrl->getPluginSettings("rmcmon");

    my $batch_string=$settings{'nodeusebatch'};
    if ($batch_string  =~ /1|Yes|yes|YES|Y|y/ ) { $batch=1;}   
  }
  if ($batch) {
      my $result=`stopcondresp NodeReachability_Batch UpdatexCATNodeStatus_Batch 2>&1`;
      if (($?) && ($result !~ /2618-264/)) { #stoped
	  $retcode=$?;
	  $retmsg="Error stop node status monitoring: $result";
	  reportError($retmsg, $callback);
      }
      
  } else {
      if ($isSV) { return  ($retcode, $retmsg); }

      #stop monitoring the status of mn's immediate children
      my $result=`stopcondresp NodeReachability UpdatexCATNodeStatus 2>&1`;
      if (($?) && ($result !~ /2618-264/)) { #stoped
	  $retcode=$?;
	  $retmsg="Error stop node status monitoring: $result";
	  reportError($retmsg, $callback);
      }
      #stop monitoring the status of mn's grandchildren via their service nodes
      $result=`stopcondresp NodeReachability_H UpdatexCATNodeStatus 2>&1`;
      if (($?) && ($result !~ /2618-264/)) { #stoped
	  $retcode=$?;
	  $retmsg="Error stop node status monitoring: $result";
	  reportError($retmsg, $callback);
      }
  }

  return ($retcode, $retmsg);
}


#--------------------------------------------------------------------------------
=head3   getNodeID
    This function gets the nodeif for the given node.

    Arguments:
        node
    Returns:
        node id for the given node
=cut
#--------------------------------------------------------------------------------
sub getNodeID {
  my $node=shift;
  if ($node =~ /xCAT_monitoring::rmcmon/) {
    $node=shift;
  }
  my $tab=xCAT::Table->new("mac", -create =>0);
  my $tmp=$tab->getNodeAttribs($node, ['mac']);
  if (defined($tmp) && ($tmp)) {
    my $mac=$tmp->{mac};
    $mac =~ s/\|.*//g; #use the first mac
    $mac =~ s/\!.*//g; #remove the hostname
    $mac =~ s/://g;    #remove :
    $mac = "EA" . $mac . "EA";
    $tab->close();
    return $mac;  
  }
  $tab->close();
  return undef;
}



#--------------------------------------------------------------------------------
=head3   getLocalNodeID
    This function goes to RMC and gets the nodeid for the local host.

    Arguments:
        node
    Returns:
        node id for the local host.
=cut
#--------------------------------------------------------------------------------
sub getLocalNodeID {
  my $node_id=`/usr/sbin/rsct/bin/lsnodeid`;
  if ($?==0) {
    chomp($node_id);
    return $node_id;
  } else {
    return undef;
  }
}

#--------------------------------------------------------------------------------
=head3    getNodeInfo
      This function gets the nodeid, node ip addresses for the given node 
    Arguments:
       node
       flag --- if 0 means normal nodes, if 1 means HMC.  
    Returns:
       (nodeid, nodeip) if error, nodeid=-1 and nodeip is the error message
=cut
#--------------------------------------------------------------------------------
sub getNodeInfo 
{
  my $node=shift;
  my $flag=shift;

  my @hostinfo=xCAT::NetworkUtils->determinehostname();
  my %iphash=();
  foreach(@hostinfo) {$iphash{$_}=1;}

  my $node_id;
  if($iphash{$node}) {
    $node_id=getLocalNodeID();
  } else { 
    if ($flag) { 
      my $result=`XCATBYPASS=Y $::XCATROOT/bin/xdsh $node -l hscroot lsnodeid`;
      if ($?) {
	return (-1, $result);
      } else {
	chomp($result);
        my @a=split(' ', $result);
        $node_id=$a[1];
      }
    }
    else { $node_id=getNodeID($node);} 
  }

  my ($name,$aliases,$addrtype,$length,@addrs) = gethostbyname($node);
  chomp($name);
  my $ipaddresses="{";
  foreach (@addrs) { $ipaddresses .= '"'.inet_ntoa($_) . '",'; }
  chop($ipaddresses);
  $ipaddresses .= "}";

  return ($node_id, $ipaddresses);
}

#--------------------------------------------------------------------------------
=head3    reportError
      This function writes the error message to the callback, otherwise to syslog. 
    Arguments:
       error
       callback 
    Returns:
       none
=cut
#--------------------------------------------------------------------------------
sub reportError 
{
  my $error=shift;
  my $callback=shift;
  if ($callback) {
    my $rsp={};
    $rsp->{data}->[0]=$error;
    $callback->($rsp);
  } else { xCAT::MsgUtils->message('S', "[mon]: $error\n"); }
  return;
}

#--------------------------------------------------------------------------------
=head3    addNodes
      This function adds the nodes into the RMC cluster, it does not check the OSI type and
      if the node has already defined. 
    Arguments:
       nodes --an array of nodes to be added. 
       master -- the monitoring master of the node.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only. 
                2 means localhost and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
       flag  -- 0 means normal node. 1 means HMC.
    Returns:
       (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub addNodes {
  my $pmon_nodes=shift;
  if ($pmon_nodes =~ /xCAT_monitoring::rmcmon/) {
    $pmon_nodes=shift;
  }

  my @mon_nodes = @$pmon_nodes;
  if (@mon_nodes==0) { return (0, "");}

  my $master=shift;
  my $scope=shift;
  my $callback=shift;
  my $flag=shift;
  print "rmcmon.addNodes mon_nodes=@mon_nodes, flag=$flag\n";

  my @hostinfo=xCAT::NetworkUtils->determinehostname();
  my %iphash=();
  foreach(@hostinfo) {$iphash{$_}=1;}
  my $localhostname=hostname();

  #find in active nodes
  my $inactive_nodes=[];
  if ($scope) { 
    my %nodes_status=xCAT::NetworkUtils->pingNodeStatus(@mon_nodes); 
    $inactive_nodes=$nodes_status{$::STATUS_INACTIVE};
    #print "active nodes to add:@$active_nodes\ninactive nodes to add: @$inactive_nodes\n";
    if (@$inactive_nodes>0) { 
      my $error="The following nodes cannot be added to the RMC cluster because they are inactive:\n  @$inactive_nodes.";
      reportError($error, $callback);
    }
  }
  my %inactiveHash=();
  foreach(@$inactive_nodes) { $inactiveHash{$_}=1;} 

  #get a list of managed nodes
  my $result=`/usr/bin/lsrsrc-api -s IBM.MngNode::::Name 2>&1`;  
  if ($?) {
    if ($result !~ /2612-023/) {#2612-023 no resources found error
      reportError($result, $callback);
      return (1,$result);
    }
    $result='';
  }
  chomp($result);
  my @rmc_nodes=split(/\n/, $result);
  my %rmcHash=();
  foreach (@rmc_nodes) { $rmcHash{$_}=1;}


  my $ms_host_name=$localhostname;
  my $ms_node_id;
  my $mn_node_id;
  my $ms_ipaddresses;
  my $mn_ipaddresses;
  my $result;
  my $first_time=1;
  my @normal_nodes=();

  foreach my $node(@mon_nodes) {
    my $mn_node_id_found=0;
    my $hmc_ssh_enabled=0;
    #get mn info
    if ($first_time) {
      $first_time=0;
      $ms_node_id=getLocalNodeID();
      if ($ms_node_id == -1) {
        reportError("Cannot get nodeid for $ms_host_name", $callback);
        return (1, "Cannot get nodeid for $ms_host_name"); 
      }
     
      $result= xCAT::NetworkUtils::toIP( $master );
      if ( @$result[0] != 0 ) {
        reportError("Cannot resolve $master", $callback);
        return (1, "Cannot resolve $master"); 
      }
      $ms_ipaddresses="{" . @$result[1] . "}";
    }

    if (!$rmcHash{$node}) {
      #enable ssh for HMC
      if ($flag) {
        my $result=`XCATBYPASS=Y $::XCATROOT/bin/rspconfig $node sshcfg=enable 2>&1`;
        if ($?) {
          my $error= "$result";
          reportError($error, $callback);
          next;
        }     
        $hmc_ssh_enabled=1;
      }

      #get info for the node
      ($mn_node_id, $mn_ipaddresses)=getNodeInfo($node, $flag);
      if ($mn_node_id == -1) {
        reportError($mn_ipaddresses, $callback);
        next; 
      }
      $mn_node_id_found=1;

      # define resource in IBM.MngNode class on server
      $result=`mkrsrc-api IBM.MngNode::Name::"$node"::KeyToken::"$node"::IPAddresses::"$mn_ipaddresses"::NodeID::0x$mn_node_id 2>&1`;
      if ($?) {
        reportError("define resource in IBM.MngNode class result=$result.", $callback);
        next; 
      }
    }

    if ($inactiveHash{$node}) { next;}

    push(@normal_nodes, $node);
    if ($scope==0) { next; }

    #copy the configuration script and run it locally
    if($iphash{$node}) {
      pop(@normal_nodes);
      $result=`/usr/bin/mkrsrc-api IBM.MCP::MNName::"$node"::KeyToken::"$master"::IPAddresses::"$ms_ipaddresses"::NodeID::0x$ms_node_id`;      
      if ($?) {
        reportError($result, $callback);
        next;
      }
    } else {
      if ($flag) { #define MCP on HMC
        pop(@normal_nodes);
	if (!$hmc_ssh_enabled) {
          my $result=`XCATBYPASS=Y $::XCATROOT/bin/rspconfig $node sshcfg=enable 2>&1`;
          if ($?) {
            my $error= "$result";
            reportError($error, $callback);
            next;
          }
        }    
        
	#print "hmccmd=XCATBYPASS=Y $::XCATROOT/bin/xdsh $node -l hscroot \"lsrsrc-api -s IBM.MCP::\\\"NodeID=0x$ms_node_id\\\" 2>&1\"\n";
        $result=`XCATBYPASS=Y $::XCATROOT/bin/xdsh $node -l hscroot "lsrsrc-api -s IBM.MCP::\\\"NodeID=0x$ms_node_id\\\" 2>&1"`;
        if ($?) {
          if ($result !~ /2612-023/) {#2612-023 no resources found error
            reportError($result, $callback);
            next;
	  }  else {
            #print "hmccmd2=XCATBYPASS=Y $::XCATROOT/bin/xdsh $node -l hscroot \"mkrsrc-api IBM.MCP::MNName::\\\"$node\\\"::KeyToken::\\\"$master\\\"::IPAddresses::\\\"$ms_ipaddresses\\\"::NodeID::0x$ms_node_id 2>&1\"\n";
            reportError("Configuring $node", $callback); 
            $result=`XCATBYPASS=Y $::XCATROOT/bin/xdsh $node -l hscroot "mkrsrc-api IBM.MCP::MNName::\\\"$node\\\"::KeyToken::\\\"$master\\\"::IPAddresses::\\\"$ms_ipaddresses\\\"::NodeID::0x$ms_node_id 2>&1"`;
            if ($?) { reportError($result, $callback); }
	  }
        }

        #check if hmc node added to management domain successfully
        my $n = 6;
        while($n > 0){
           $result = `/usr/sbin/rsct/bin/rmcdomainstatus -s ctrmc | grep $node`;
           if ($result =~ /\s$node\s/){
               last;
           } else {
               sleep 10;
               $n = $n - 1;
           }
        }

        #define AllServiceableEvents_B condition on the HMC
	$result=`CT_MANAGEMENT_SCOPE=3 /usr/bin/mkrsrc-api IBM.Condition::Name::"AllServiceableEvents_B"::ResourceClass::"IBM.Sensor"::EventExpression::"String=?\\\"LSSVCEVENTS_ALL%\\\""::SelectionString::"Name=\\\"CSMServiceableEventSensor\\\""::NodeNameList::{\\\"$node\\\"}::EventBatchingInterval::1::BatchedEventRetentionPeriod::72 2>&1`;
	if (($?) && ($result !~ /2618-201|2618-008|2636-050/)){ 
	    reportError($result, $callback); 
	}
	
      }
    }
  } 

  #let updatenode command to handle the normal nodes as a bulk
  if (@normal_nodes>0) {
    my $nr=join(',',@normal_nodes);
    my $install_root = xCAT::TableUtils->getInstallDir();

    #get the fanout value
    my %settings=xCAT_monitoring::monitorctrl->getPluginSettings("rmcmon");

    my $fanout_string="";
    my $fanout_value=$settings{'rfanout'};
    if ($fanout_value) { $fanout_string="DSH_FANOUT=$fanout_value";}

    #for local mode, need to referesh the IBM.MCP class to initialize the hb
    if ($scope==0) {
      #$result=`XCATBYPASS=Y $fanout_string $::XCATROOT/bin/xdsh $nr /usr/bin/refrsrc-api -c IBM.MCP 2>&1"`;
      if ($?) { reportError($result, $callback); }
      return (0, "ok"); 
    }

    #this is remore case
    reportError("Configuring the following nodes. It may take a while.\n$nr", $callback);
    my $cmd;
    my %servernodes = %{xCAT::InstUtils->get_server_nodes($callback, \@normal_nodes)};
    # it's possible that the nodes could have diff server names
    # do all the nodes for a particular server at once
    foreach my $snkey (keys %servernodes) {
	my $nr = join(',', @{$servernodes{$snkey}});
	my $cmd;
	if (xCAT::Utils->isLinux()) {
	    $cmd="XCATBYPASS=Y $fanout_string $::XCATROOT/bin/xdsh $nr -s -e $install_root/postscripts/xcatdsklspost 2 -m $snkey configrmcnode 2>&1";
	    print "$cmd\n";
	}
	else {
	    #use -c 2 here to tell xcataixpost that there is only one postscript, download only it. It applies to AIX only     
	    $cmd="XCATBYPASS=Y $fanout_string $::XCATROOT/bin/xdsh $nr -s -e $install_root/postscripts/xcataixpost -m $snkey -c 2 configrmcnode 2>&1";
	}
	if (! open (CMD, "$cmd |")) {
	    reportError("Cannot run command $cmd", $callback);
	} else {
	    while (<CMD>) {
		chomp;
		my $rsp={};
		$rsp->{data}->[0]="$_";
		$callback->($rsp);
	    }
	    close(CMD);
	}
    }
  }

  return (0, "ok"); 
}


#--------------------------------------------------------------------------------
=head3    removeNodes
      This function removes the nodes from the RMC cluster.
    Arguments:
      nodes --a pointer to a array of node names to be removed. 
      master -- the master of the nodes.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only. 
                2 means localhost and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
       flag  -- 0 means normal node. 1 means HMC.
    Returns:
      (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub removeNodes {
  my $pmon_nodes=shift;
  if ($pmon_nodes =~ /xCAT_monitoring::rmcmon/) {
    $pmon_nodes=shift;
  }
  my @mon_nodes = @$pmon_nodes;
  if (@mon_nodes==0) { return (0, "");}

  my $master=shift;
  my $scope=shift;
  my $callback=shift;
  my $flag=shift;

  print "rmcmon.removeNodes mon_nodes=@mon_nodes, flag=$flag\n";

  my $localhostname=hostname();
  my $ms_host_name=$localhostname;
  my $ms_node_id;
  my $result;
  my $first_time=1;
  my @normal_nodes=();
 
  #find in active nodes
  my $inactive_nodes=[];
  if ($scope) { 
    my %nodes_status=xCAT::NetworkUtils->pingNodeStatus(@mon_nodes); 
    $inactive_nodes=$nodes_status{$::STATUS_INACTIVE};
    #print "active nodes to add:@$active_nodes\ninactive nodes to add: @$inactive_nodes\n";
    if (@$inactive_nodes>0) { 
      my $error="The following nodes cannot be removed from the RMC cluster because they are inactive:\n  @$inactive_nodes.";
      reportError($error, $callback);
    }
  }
  my %inactiveHash=();
  foreach(@$inactive_nodes) { $inactiveHash{$_}=1;} 

  #get a list of managed nodes
  my $result=`/usr/bin/lsrsrc-api -s IBM.MngNode::::Name 2>&1`;  
  if ($?) {
    if ($result !~ /2612-023/) {#2612-023 no resources found error
      reportError($result, $callback);
      return (1,$result);
    }
    $result='';
  }
  chomp($result);
  my @rmc_nodes=split(/\n/, $result);
  my %rmcHash=();
  foreach (@rmc_nodes) { $rmcHash{$_}=1;}

  #print "rmcmon::removeNodes_noChecking get called with @mon_nodes\n";

  foreach my $node (@mon_nodes) {
    if ($rmcHash{$node}) {
	my $result=0;
	if ($flag && $scope && (!$inactiveHash{$node})) {  #remove AllServiceableEvents_B condition for HMC
	    $result=`XCATBYPASS=Y $::XCATROOT/bin/xdsh $node -l hscroot "lsrsrc-api -s IBM.Condition::\\\"Name='AllServiceableEvents_B'\\\" 2>&1"`;
	    if ($?) {
		if ($result !~ /2612-023/) {#2612-023 no resources found error
		    reportError($result, $callback); 
		} 
	    }
	    $result=`/usr/bin/rmcondition -f AllServiceableEvents_B:$node 2>&1`;
	    if ($?) { reportError($result, $callback); }
	}
    

      #remove resource in IBM.MngNode class on server
      $result=`rmrsrc-api -s IBM.MngNode::"Name=\\\"\"$node\\\"\"" 2>&1`;
      if ($?) {  
        if ($result =~ m/2612-023/) { #resource not found
         next;
        }
        reportError("Remove resource in IBM.MngNode class result=$result.", $callback);
      }
    }

    if ($scope==0) { next; }
    if ($inactiveHash{$node}) { next;}

    if ($ms_host_name eq $node) {
      $result= `/usr/bin/rmrsrc-api -s IBM.MCP::"MNName=\\\"\"$node\\\"\"" 2>&1`;
      if ($?) { reportError($result, $callback); }
    } else {
      #get mn info
      if ($first_time) {
        $ms_node_id=getLocalNodeID();
        if ($ms_node_id == -1) {
          reportError("Cannot get nodeid for $ms_host_name", $callback);
          return (1, "Cannot get nodeid for $ms_host_name"); 
        }
        $first_time=0;
      }

      if ($flag) { #hmc nodes
	#remove the MCP
        $result=`XCATBYPASS=Y $::XCATROOT/bin/xdsh $node -l hscroot "lsrsrc-api -s IBM.MCP::\\\"NodeID=0x$ms_node_id\\\" 2>&1"`;
        if ($?) {
          if ($result !~ /2612-023/) {#2612-023 no resources found error
            reportError($result, $callback); 
	  } 
	  next;
        }
        $result=`XCATBYPASS=Y $::XCATROOT/bin/xdsh $node -l hscroot "rmrsrc-api -s IBM.MCP::\\\"NodeID=0x$ms_node_id\\\" 2>&1"`;
        if ($?) { reportError($result, $callback); }

      } else { #normal nodes
        push(@normal_nodes, $node);
      }
    }
  }   

  #let updatenode command to handle the normal nodes as a bulk
  if (@normal_nodes>0) {
    my $nr=join(',',@normal_nodes); 

    my %settings=xCAT_monitoring::monitorctrl->getPluginSettings("rmcmon");

    my $fanout_string="";
    my $fanout_value=$settings{'rfanout'};
    if ($fanout_value) { $fanout_string="DSH_FANOUT=$fanout_value";}

    #copy the configuration script and run it locally
    $result=`XCATBYPASS=Y $fanout_string $::XCATROOT/bin/xdcp $nr $::XCATROOT/sbin/rmcmon/configrmcnode /tmp 2>&1 `;
    if ($?) {
      reportError("$result", $callback);
    }

    reportError("De-configuring the following nodes. It may take a while.\n$nr", $callback); 
    my $cmd="XCATBYPASS=Y $fanout_string $::XCATROOT/bin/xdsh $nr -s MS_NODEID=$ms_node_id /tmp/configrmcnode -1 2>&1";
    if (! open (CMD1, "$cmd |")) {
      reportError("Cannot run command $cmd", $callback);
    } else {
      while (<CMD1>) {
	chomp;
        my $rsp={};
        $rsp->{data}->[0]="$_";
        $callback->($rsp);
      }
      close(CMD1);
    }

    #$result=`XCATBYPASS=Y $::XCATROOT/bin/xdsh $nr MS_NODEID=$ms_node_id /tmp/configrmcnode -1 2>&1`;
    #if ($?) { reportError($result, $callback);  }
  }    

  return (0, "ok");
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
    rmcmon uses IBM's Resource Monitoring and Control (RMC) component 
    of Reliable Scalable Cluster Technology (RSCT) to monitor the 
    xCAT cluster. RMC has built-in resources such as CPU, memory, 
    process, network, file system etc for monitoring. RMC can also be 
    used to provide node liveness status monitoring and performance monitoring for xCAT. 
    RMC is good for threadhold monitoring. xCAT automatically sets up the 
    monitoring domain for RMC during node deployment time. And if performance
    monitoring is enabled, xCAT monitoring will collect and consolidate performance
    data based on montype&rmetrics setting, and then store to RRD database. 
  Settings:
    rfanout -- indicating the fanout number for configuring or deconfiguring 
        remote nodes.
    nodeusebatch -- use RMC event batching function when doing node status monitoring.
    montype -- indicating type of performance monitoring, the value could be 
               \"event\" : event monitoring (default),
	       \"perf\" : performance monitoring,
               \"event,perf\" or \"perf,event\" : both.
    rmetrics -- defines resource class,resouce names, attributes and sample interval for 
                performance monitoring. 
		Syntax of key: rmetrics_resource class For example: rmetrics_IBM.Processor
		Syntax of value: [resource names]attribute names:sample interval
		The unit of sample interval is minute.
		For example:
		  [proc0,proc1]PctTimeIdle,PctTimeWait,PctTimeKernel,PctTimeUser:5
				  
";
}

#--------------------------------------------------------------------------------
=head3    getNodeConfData
      This function gets a list of configuration data that is needed by setting up
    node monitoring.  These data-value pairs will be used as environmental variables 
    on the given node.
    Arguments:
        pointet to a arry of nodes 
    Returns:
        pointer to a 2-level hash. For format will as following:
        {
           'node1'=>{'NODEID'=>'123',
                     'MS_NODEID'=>'456'},
           'node2'=>{'NODEID'=>'789',
                     ''MS_NODEID'=>'0AB'}
        }

=cut
#--------------------------------------------------------------------------------
sub getNodeConfData {
  my $ref_ret;
  #check if rsct is installed or not
  if (! -e "/usr/bin/lsrsrc") {
    return $ref_ret;
  }

  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::rmcmon/) {
    $noderef=shift;
  }
  my $tab=xCAT::Table->new("mac", -create =>0);
  my $machash=$tab->getNodesAttribs($noderef, ['mac']);
  $tab->close();

  my $ms_nodeid=xCAT_monitoring::rmcmon->getLocalNodeID();

  foreach my $node (@$noderef) {
      #get node ids for RMC monitoring
      if ($machash && defined($machash->{$node}) && defined($machash->{$node}->[0])) {
	  my $mac=$machash->{$node}->[0]->{'mac'};
	  if ($mac) {
	      $mac =~ s/\|.*//g; #use the first mac
	      $mac =~ s/\!.*//g; #remove the hostname
	      $mac =~ s/://g;    #remove :
	      $mac = "EA" . $mac . "EA";
	      $ref_ret->{$node}->{NODEID}=$mac;
	  }
      }

      if (defined($ms_nodeid)) {
	  $ref_ret->{$node}->{MS_NODEID}=$ms_nodeid;
      }
  }
  return $ref_ret;
}

#--------------------------------------------------------------------------------
=head3    getPostscripts
      This function returns the postscripts needed for the nodes and for the servicd
      nodes. 
     Arguments:
        none
    Returns:
     The the postscripts. It a pointer to an array with the node group names as the keys
    and the comma separated poscript names as the value. For example:
    {service=>"cmd1,cmd2", xcatdefaults=>"cmd3,cmd4"} where xcatdefults is a group
    of all nodes including the service nodes.
=cut
#--------------------------------------------------------------------------------
sub getPostscripts {
  my $ret={};
  $ret->{xcatdefaults}="configrmcnode";
  return $ret;
}

sub showmetrix($rrddir, $attrs, $start_time, $end_time)
{
	my($rrddir, $attrs, $start_time, $end_time) = @_;
	my $result = [];
	my $output = undef;
	my @files = ();
	my $file = undef;
	my @attrlist = split /,/,$attrs;
	my $attr = undef;
	my $line = undef;
	my @namelist = ();
	my @timelist = ();
	my %hash = {};
	my $name = undef;
	my $timestamp = undef;
	my $sum = undef;
	my $num = undef;
	my $remote = undef;

	if($rrddir =~ /:/){
		($remote,$rrddir) = split /:/,$rrddir;
	}
	
	foreach $attr (@attrlist) {
		@namelist = ();
		@timelist = ();
		%hash = {};
		if($remote){
			$output = xCAT::Utils->runcmd("xdsh $remote 'ls -A /var/rrd/$rrddir/$attr*'", 0);
			if($::RUNCMD_RC != 0){
				return $result;
			}
			$output =~ s/(\S+): \/var\/rrd\//''/;
		} else {
			$output = xCAT::Utils->runcmd("ls -A $rrddir/$attr*", 0);
		}
		@files = split /\n/, $output;
		foreach $file (@files) {
			if($file =~ /$attr\.rrd$/){
				$name = "$attr";
			} elsif ($file =~ /${attr}_(\S+)\.rrd$/) {
				$name = $1;
			}
			push @namelist, $name;
			if($remote){
				$output = xCAT_monitoring::rrdutil::RRD_fetch($file, $start_time, $end_time, $remote);
			} else {
				$output = xCAT_monitoring::rrdutil::RRD_fetch($file, $start_time, $end_time);
			}
			$line = pop(@$output);
			if($line =~ /ERROR/){
				push @$result, $line;
				next;
			} else {
				push @$output, $line;
			}
			foreach $line (@$output){
				if($line =~ /[NaNQ|nan]/){
					next;
				} elsif ($line =~ /^(\d+): (\S+) (\S+)/){
					$timestamp = $1;
					$sum = $2;
					$num = $3;
					if(! grep {/$timestamp/} @timelist){
						push @timelist, $timestamp;
					}
					$hash{$name}{$timestamp} = sprintf "%.4f", $sum;
				} elsif ($line =~ /^(\d+): (\S+)/){
					$timestamp = $1;
					$sum = $2;
					if(! grep {/$timestamp/} @timelist){
						push @timelist, $timestamp;
					}
					$hash{$name}{$timestamp} = sprintf "%.4f", $sum;
				}
			}
		}
		$line = join "\t", (@namelist);
		$line = "                          ".$line;
		push @$result, $line;
		@timelist = sort @timelist;
		foreach $timestamp (@timelist){
			$line = localtime($timestamp)."  ";
			foreach $name (@namelist){
				if(exists $hash{$name}{$timestamp}){
					$line =$line."$hash{$name}{$timestamp}\t";
				} else {
					$line = $line."-\t";
				}
			}
			push @$result, $line;
		}
	}
	
	return $result;

}

sub showeventlog
{
  my @result = ();
  my ($table, $node,$attrs,$start_time,$end_time,$where) = @_;

  my $need_filter = 0;  #need second search to sql
  my @attr = ();
  my @attrkey = ();
  my @severity = ('Informational', 'Warning', 'Critical');

  if(!$attrs){
    @attrkey = ('eventtype','monitor','monnode','application',
               'component','id','severity','message','rawdata','comments');
  } else {
    @attrkey = split /,/, $attrs;
  }
  
  #node 
  push @attr, "node==$node";
  #plugin
  push @attr, "application==RMC";
  #where
  if(defined($where)){
    foreach my $a (@$where){
      if($a =~ /severity([!=><]+)(\w+)/){
        my $op = $1;
        my $sev = $2;
        if(($op eq '==')||($op eq '!=')){
          push @attr, $a;
        } elsif($op eq '>=') {
          foreach my $s (@severity){
            if($sev =~ /^$s$/i){
              last; 
            }
            push @attr, "severity!=$s"; 
          }
        } elsif($op eq '<=') {
          my $s = pop @severity;
          while($s !~ /^$sev$/i){
            push @attr, "severity!=$s";
            $s = pop @severity;
          }
        } elsif($op eq '>') {
          foreach my $s (@severity){
            if($sev =~ /^$s$/i){
              push @attr, "severity!=$s";
              last;
            }
          }
        } elsif($op eq '<') {
          my $s = pop @severity;
          while($sev !~ /^$s$/i){
            push @attr, "severity!=$s";
            $s = pop @severity;
          }
          push @attr, "severity!=$s";
        } 
      } else {
        push @attr, $a;
      }
    } 
  }
  #eventtime
  my ($s_sec,$s_min,$s_hour,$s_mday,$s_mon,$s_year) = localtime($start_time);
  my ($e_sec,$e_min,$e_hour,$e_mday,$e_mon,$e_year) = localtime($end_time);
  my $tmp = sprintf("eventtime>=%04d-%02d-%02d %02d:%02d:%02d",$s_year+1900,$s_mon+1,$s_mday,$s_hour,$s_min,$s_sec);
  push @attr, $tmp;
  $tmp = sprintf("eventtime<=%04d-%02d-%02d %02d:%02d:%02d",$e_year+1900,$e_mon+1,$e_mday,$e_hour,$e_min,$e_sec);
  push @attr, $tmp;

  my @r = $table->getAllAttribsWhere(\@attr, 'eventtime', @attrkey);

  push @result, (join ",", @attrkey);
  $result[0] = "eventtime,$result[0]";
  foreach my $entry (@r){
    my $str = "\'$entry->{eventtime}\'";
    foreach my $a (@attrkey){
      $str = $str. ",\'$entry->{$a}\'";
    }
    push @result, $str;
  }
  return \@result;
  
}

#--------------------------------------------------------------------------------
=head3    show
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
sub show 
{
  print "rmcmon:show called\n";
  no strict 'refs';
  my ($noderef, $sum, $time, $attrs, $pe, $where,$callback) = @_;
  my @monnodes = ();
  my $rsp = {};
  my $localhostname=hostname();
  my $start_time = undef;
  my $end_time = undef;
  my $node = undef;
  my $output = undef;
  my $rrddir = undef;

  $end_time = `date +%s`;
  if($time =~ /(\d+)-(\d+)/){
    $start_time = $end_time - $1 * 60;
    $end_time = $end_time - $2 * 60;
  } else {
    $start_time = $end_time - $time * 60;
  }
  
  foreach $node (@$noderef){
    my $table = xCAT::Table->new('nodetype');
    my $entry = $table->getNodeAttribs($node, ['nodetype']);
    if($entry && ($entry->{nodetype} =~ /$::NODETYPE_OSI/)){
      push @monnodes, $node;
    }
  }
  
  #the identification of this node
  my $isSV=xCAT::Utils->isServiceNode();

  if(!$isSV && ($sum&0x2)){
    push @monnodes, $localhostname;
  }
  $sum &= 0x1;

  if($pe =~ /p/){
  if($sum){
    foreach $node (@monnodes){
      if($node eq $localhostname){
	$rrddir = "/var/rrd/cluster";
	my @metrixconf = xCAT_monitoring::rmcmetrix::get_metrix_conf();
	my $rmetrixcmd = undef;
  	while(@metrixconf){
	  my ($rsrc, $rname, $attrlist, $minute);
	  $rsrc  = shift @metrixconf;
	  $rname = shift @metrixconf;
	  $attrlist = shift @metrixconf;
	  $minute = shift @metrixconf;
	  $rmetrixcmd = "/opt/xcat/sbin/rmcmon/rmcmetrixmon sum $rsrc $attrlist $minute";
	  xCAT::Utils->runcmd($rmetrixcmd, 0);
        }
      }	elsif(xCAT::Utils->isSN($node)){
	$rrddir = "$node:summary";
      } else {
        $rrddir = "/var/rrd/$node";
      }
      $output = &showmetrix($rrddir, $attrs, $start_time, $end_time);
      push @{$rsp->{data}}, "\n$node-summary:";
      push @{$rsp->{data}}, @$output;
    }
  } else {
    foreach $node (@monnodes){
      $rrddir = "/var/rrd/$node";
      $output = &showmetrix($rrddir, $attrs, $start_time, $end_time);
      push @{$rsp->{data}}, "\n$node:";
      push @{$rsp->{data}}, @$output;
    }
  }
  } elsif($pe =~ /e/){
    my $eventtable =xCAT::Table->new("eventlog", -create =>0);
    if (!$eventtable) {
      push @{$rsp->{data}}, "Error:Can't open table eventlog!";
      return -1;
    }
    foreach $node (@monnodes){
      push @{$rsp->{data}}, "\n$node:";
      $output = showeventlog($eventtable,$node,$attrs,$start_time,$end_time,$where);
      push @{$rsp->{data}}, @$output;
    }
    $eventtable->close();
  }
  $callback->($rsp);
  return (0, "");
}

