#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_monitoring::rmcmon;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::NodeRange;
use Sys::Hostname;
use Socket;
use xCAT::Utils;
use xCAT::GlobalDef;
use xCAT_monitoring::monitorctrl;
use xCAT_monitoring::xcatmon;
use xCAT::MsgUtils;

#print "xCAT_monitoring::rmcmon loaded\n";
1;


#TODO: script to define sensors on the nodes.
#TODO: how to push the sensor scripts to nodes?
#TODO: what to do when stop is called? stop all the associations or just the ones that were predefined? or leve them there?
#TODO: do we need to stop all the RMC daemons when stop is called?
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
      when xcatd starts. It starts the daemons and does
      necessary startup process for the RMC monitoring.
      It also queries the RMC for its currently monitored
      nodes which will, in tern, compared with the nodes
      in the input parameter. It asks RMC to add or delete
      nodes according to the comparison so that the nodes
      monitored by RMC are in sync with the nodes currently
      in the xCAT cluster.
    Arguments:
      None.
    Returns:
      (return code, message)      
=cut
#--------------------------------------------------------------------------------
sub start {
  #print "rmcmon::start called\n";

  my $noderef=xCAT_monitoring::monitorctrl->getMonHierarchy();
    
  #assume the server is the current node.
  #check if rsct is installed and running
  if (! -e "/usr/bin/lsrsrc") {
    return (1, "RSCT is not installed.\n");
  }

  chomp(my $pid= `/bin/ps -ef | /bin/grep rmcd | /bin/grep -v grep | /bin/awk '{print \$2}'`);
  unless($pid){
    #restart rmc daemon
    $result=`startsrc -s ctrmc`;
    if ($?) {
      return (1, "RMC deamon cannot be started\n");
    }
  }

  #enable remote client connection
  `/usr/bin/rmcctrl -p`;
  
  #get a list of managed nodes
  $result=`/usr/bin/lsrsrc-api -s IBM.MngNode::::Name 2>&1`;  
  if ($?) {
    if ($result !~ /2612-023/) {#2612-023 no resources found error
      xCAT::MsgUtils->message('SI', "[mon]: $result\n");
      return (1,$result);
    }
    $result='';
  }
  chomp($result);
  my @rmc_nodes=split(/\n/, $result);
  #print "RMC defined nodes=@rmc_nodes\n";

  
  #the identification of this node
  my @hostinfo=xCAT::Utils->determinehostname();
  my $isSV=xCAT::Utils->isServiceNode();
  %iphash=();
  foreach(@hostinfo) {$iphash{$_}=1;}
  if (!$isSV) { $iphash{'noservicenode'}=1;}

  foreach my $key (keys (%$noderef)) {
    my @key_a=split(',', $key);
    if (! $iphash{$key_a[0]}) { next;}   
    my $mon_nodes=$noderef->{$key};
    my $master=$key_a[1];

    #check what has changed 
    my %summary;
    foreach (@rmc_nodes) { $summary{$_}=-1;}
    if ($mon_nodes) {
      foreach(@$mon_nodes) {
        my $node=$_->[0];
        my $nodetype=$_->[1];
        if ((!$nodetype) || ($nodetype =~ /$::NODETYPE_OSI/)) { 
          $summary{$node}++;
        }  
      }     
    }

    my @nodes_to_add=();
    my @nodes_to_remove=();
    foreach(keys(%summary)) {
      if ($summary{$_}==1) {push(@nodes_to_add, $_);}  
      elsif ($summary{$_}==-1) {push(@nodes_to_remove, $_);}      
    }
 
    #add new nodes to the RMC cluster
    #print "all nodes to add: @nodes_to_add\nall nodes to remove: @nodes_to_remove\n";  
    if (@nodes_to_add>0) { 
      my %nodes_status=xCAT_monitoring::rmcmon->pingNodeStatus(@nodes_to_add); 
      my $active_nodes=$nodes_status{$::STATUS_ACTIVE};
      my $inactive_nodes=$nodes_status{$::STATUS_INACTIVE};
      #print "active nodes to add:@$active_nodes\ninactive nodes to add: @$inactive_nodes\n";
      if (@$inactive_nodes>0) { 
        xCAT::MsgUtils->message('SI', "[mon]: The following nodes cannot be added to the RMC cluster because they are inactive:\n  @$inactive_nodes\n");
      }
      if (@$active_nodes>0) {
        addNodes_noChecking($active_nodes, $master);
      }
    }  

    #remove unwanted nodes to the RMC cluster
    if (@nodes_to_remove>0) {
      #print "nodes to remove @nodes_to_remove\n"; 
      removeNodes_noChecking(\@nodes_to_remove, $master);
    }  

    #create conditions/responses/sensors on the service node or mn
    my $result=`$::XCATROOT/sbin/rmcmon/mkrmcresources $::XCATROOT/lib/perl/xCAT_monitoring/rmc/resources/sn 2>&1`;
    if ($?) {
      xCAT::MsgUtils->message('SI', "[mon]: Error when creating predefined resources on $localhostname:\n$result\n");
    }   
    if ($isSV) {
      $result=`$::XCATROOT/sbin/rmcmon/mkrmcresources $::XCATROOT/lib/perl/xCAT_monitoring/rmc/resources/node 2>&1`; 
    } else  {
      $result=`$::XCATROOT/sbin/rmcmon/mkrmcresources $::XCATROOT/lib/perl/xCAT_monitoring/rmc/resources/mn 2>&1`; 
    }      
    if ($?) {
      xCAT::MsgUtils->message('SI', "[mon]: Error when creating predefined resources on $localhostname:\n$result\n");
    }
  }

  return (0, "started");
}


#--------------------------------------------------------------------------------
=head3    pingNodeStatus
      This function takes an array of nodes and returns their status using fping.
    Arguments:
       nodes-- an array of nodes.
    Returns:
       a hash that has the node status. The format is: 
          {active=>[node1, node3,...], unreachable=>[node4, node2...]}
=cut
#--------------------------------------------------------------------------------
sub pingNodeStatus {
  my ($class, @mon_nodes)=@_;
  %status=();
  my @active_nodes=();
  my @inactive_nodes=();
  if ((@mon_nodes)&& (@mon_nodes > 0)) {
    #get all the active nodes
    my $nodes= join(' ', @mon_nodes);
    my $temp=`fping -a $nodes 2> /dev/null`;
    chomp($temp);
    @active_nodes=split(/\n/, $temp);

    #get all the inactive nodes by substracting the active nodes from all.
    my %temp2;
    if ((@active_nodes) && ( @active_nodes > 0)) {
      foreach(@active_nodes) { $temp2{$_}=1};
        foreach(@mon_nodes) {
          if (!$temp2{$_}) { push(@inactive_nodes, $_);}
        }
    }
    else {@inactive_nodes=@mon_nodes;}     
  }

  $status{$::STATUS_ACTIVE}=\@active_nodes;
  $status{$::STATUS_INACTIVE}=\@inactive_nodes;
 
  return %status;
}



#--------------------------------------------------------------------------------
=head3    stop
      This function gets called by the monitorctrl module when
      xcatd stops. It stops the monitoring on all nodes, stops
      the daemons and does necessary cleanup process for the
      RMC monitoring.
    Arguments:
       none
    Returns:
       (return code, message)
=cut
#--------------------------------------------------------------------------------
sub stop {
  #print "rmcmon::stop called\n";

  #TODO: stop condition-response associtations. 
  return (0, "stopped");
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
       None.
    Returns:
        (return code, message)

=cut
#--------------------------------------------------------------------------------
sub startNodeStatusMon {
  #print "rmcmon::startNodeStatusMon called\n";
  my $retcode=0;
  my $retmsg="started";
  my $isSV=xCAT::Utils->isServiceNode();
  if ($isSV) { return  ($retcode, $retmsg); } 

  #get all the nodes status from IBM.MngNode class of local host and 
  #the identification of this node
  my $noderef=xCAT_monitoring::monitorctrl->getMonHierarchy();
  my @hostinfo=xCAT::Utils->determinehostname();
  %iphash=();
  foreach(@hostinfo) {$iphash{$_}=1;}
  if (!$isSV) { $iphash{'noservicenode'}=1;}

  my @servicenodes=();
  my %status_hash=();
  foreach my $key (keys (%$noderef)) {
    my @key_a=split(',', $key);
    if (! $iphash{$key_a[0]}) { push @servicenodes, $key_a[0]; } 
    my $mon_nodes=$monservers->{$key};
    foreach(@$mon_nodes) {
      my $node_info=$_;
      $status_hash{$node_info->[0]}=$node_info->[2];
    }
  }

  #get nodestatus from RMC and update the xCAT DB
  ($retcode, $retmsg) = saveRMCNodeStatusToxCAT(\%status_hash);
  if ($retcode != 0) {
    $retmsg="Error occurred while updating xCAT node status from RMC data.:$retmsg";
    xCAT::MsgUtils->message('SI', "[mon]: $retmsg\n");
  }
  foreach (@servicenodes) {
    ($retcode, $retmsg) = saveRMCNodeStatusToxCAT(\%status_hash, $_);
    if ($retcode != 0) {
      $retmsg="Error occurred while updating xCAT node status from RMC data from $_.:$retmsg";
      xCAT::MsgUtils->message('SI', "[mon]: $retmsg\n");
    }
  }

  #start monitoring the status of mn's immediate children
  my $result=`startcondresp NodeReachability UpdatexCATNodeStatus 2>&1`;
  if ($?) {
    $retcode=$?;
    $retmsg="Error start node status monitoring: $result";
    xCAT::MsgUtils->message('SI', "[mon]: $retmsg\n");
  }

  #start monitoring the status of mn's grandchildren via their service nodes
  $result=`startcondresp NodeReachability_H UpdatexCATNodeStatus 2>&1`;
  if ($?) {
    $retcode=$?;
    $retmsg="Error start node status monitoring: $result";
    xCAT::MsgUtils->message('SI', "[mon]: $retmsg\n");
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
  my $retmsg="started";
  my $statusref=shift;
  if ($statusref =~ /xCAT_monitoring::rmcmon/) {
    $statusref=shift;
  }
  my $node=shift;

  %status_hash=%$statusref;

  #get all the node status from mn's children
  my $result;
  if ($node) {
    $result=`CT_MANAGEMENT_SCOPE=4 /usr/bin/lsrsrc-api -o IBM.MngNode::::$node::Name::Status 2>&1`;
  } else {
    $result=`CT_MANAGEMENT_SCOPE=1 /usr/bin/lsrsrc-api -s IBM.MngNode::::Name::Status 2>&1`;
  }
  if ($?) {
    $retcode=$?;
    $retmsg=$result;
    xCAT::MsgUtils->message('SI', "[mon]: Error getting node status from RMC: $result\n");
    return ($retcode, $retmsg);
  } else {
    my @active_nodes=();
    my @inactive_nodes=();
    if ($result) {
      my @lines=split('\n', $result);
      #only save the ones that needs to change
      foreach (@lines) {
	@pairs=split('::', $_);
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
    xCAT_monitoring::xcatmon::processNodeStatusChanges(\%new_node_status);
  }  
  return ($retcode, $retmsg);
}




#--------------------------------------------------------------------------------
=head3   stopNodeStatusMon
    This function is called by the monitorctrl module to tell
    RMC to stop feeding the node status info back to xCAT. It will
    stop the condition/response that is monitoring the node status.

    Arguments:
        none
    Returns:
        (return code, message)
=cut
#--------------------------------------------------------------------------------
sub stopNodeStatusMon {
  #print "rmcmon::stopNodeStatusMon called\n";
  my $retcode=0;
  my $retmsg="stopped";
  my $isSV=xCAT::Utils->isServiceNode();
  if ($isSV) { return  ($retcode, $retmsg); }
 
  #stop monitoring the status of mn's immediate children
  my $result=`stopcondresp NodeReachability UpdatexCATNodeStatus 2>&1`;
  if ($?) {
    $retcode=$?;
    $retmsg="Error stop node status monitoring: $result";
    xCAT::MsgUtils->message('SI', "[mon]: $retmsg\n");
  }

  #stop monitoring the status of mn's grandchildren via their service nodes
  $result=`stopcondresp NodeReachability_H UpdatexCATNodeStatus 2>&1`;
  if ($?) {
    $retcode=$?;
    $retmsg="Error stop node status monitoring: $result";
    xCAT::MsgUtils->message('SI', "[mon]: $retmsg\n");
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
    $mac =~ s/://g;
    $mac .= "0000";
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
=head3    addNodes
      This function adds the nodes into the RMC cluster.
    Arguments:
      nodes --nodes to be added. It is a pointer to an array. If the next argument is
       1, each element is a ref to an array of [nodes, status]. For example: 
          [['node1', 'active'], ['node2', 'booting']..]. 
       if the next argument is 0, each element is a node name to be added.
      boolean -- 1, or 0. 
    Returns:
       (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub addNodes {
  return (0, "ok"); #not handle it now, wait when nodelist.status work is done

}


#--------------------------------------------------------------------------------
=head3    addNodes_noChecking
      This function gdds the nodes into the RMC cluster, it does not check the OSI type and
      if the node has already defined. 
    Arguments:
      nodes --an array of nodes to be added. 
    Returns:
       (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub addNodes_noChecking {
  
  my $pmon_nodes=shift;
  if ($pmon_nodes =~ /xCAT_monitoring::rmcmon/) {
    $pmon_nodes=shift;
  }

  my @mon_nodes = @$pmon_nodes;
  my $master=shift;

  #print "rmcmon::addNodes_noChecking get called with @mon_nodes\n";
  my @hostinfo=xCAT::Utils->determinehostname();
  %iphash=();
  foreach(@hostinfo) {$iphash{$_}=1;}

  my $ms_host_name=hostname();

  my $ms_node_id;
  my $mn_node_id;
  my $ms_name,$ms_aliases,$ms_addrtype,$ms_length,@ms_addrs;
  my $ms_ipaddresses;

  my $first_time=1;
  foreach(@mon_nodes) {
      
    my $node=$_;

    if ($first_time) {
      $first_time=0;
      #get ms node id, hostname, ip etc
      $ms_node_id=`/usr/sbin/rsct/bin/lsnodeid`;
      chomp($ms_node_id);
      ($ms_name,$ms_aliases,$ms_addrtype,$ms_length,@ms_addrs) = gethostbyname($ms_host_name);
      chomp($ms_name);

      $ms_ipaddresses="{";
      foreach (@ms_addrs) {
        $ms_ipaddresses .= '"' .inet_ntoa($_) . '",';
      }
      chop($ms_ipaddresses);
      $ms_ipaddresses .= "}";
    }

    #get info for the node
    if($iphash{$node}) {
      $mn_node_id=$ms_node_id;
    } else { 
      $mn_node_id=`$::XCATROOT/bin/psh --nonodecheck $node /usr/sbin/rsct/bin/lsnodeid 2>&1`;
      if ($?) {
	xCAT::MsgUtils->message('SI',  "[mon]: Cannot get NodeID for $node. $mn_node_id\n");
        next;
      }
      if ($mn_node_id =~ s/.*([0-9 a-g]{16}).*/$1/s) {;}
      else { xCAT::MsgUtils->message('SI', "[mon]: No node id found for $node:\n$mn_node_id\n"); next;}
    }

    my ($mn_name,$mn_aliases,$mn_addrtype,$mn_length,@mn_addrs) = gethostbyname($node);
    chomp($mn_name);
    my $mn_ipaddresses="{";
    foreach (@mn_addrs) {
      $mn_ipaddresses .= '"'.inet_ntoa($_) . '",';
    }
    chop($mn_ipaddresses);
    $mn_ipaddresses .= "}";
    #  print "    mn_name=$mn_name, mn_aliases=$mn_aliases,   mn_ipaddr=$mn_ipaddresses,  mn_node_id=$mn_node_id\n";          

    # define resource in IBM.MngNode class on server
    $result=`mkrsrc-api IBM.MngNode::Name::"$node"::KeyToken::"$node"::IPAddresses::"$mn_ipaddresses"::NodeID::0x$mn_node_id 2>&1`;
    if ($?) {
      xCAT::MsgUtils->message('SI', "[mon]: define resource in IBM.MngNode class result=$result\n");
      next; 
    }

    #copy the configuration script and run it locally
    if($iphash{$node}) {
      $result=`/usr/bin/mkrsrc-api IBM.MCP::MNName::"$node"::KeyToken::"$master"::IPAddresses::"$ms_ipaddresses"::NodeID::0x$ms_node_id`;      
      if ($?) {
        xCAT::MsgUtils->message('SI', "[mon]: $result\n");
        next;
      }
    } else {
      $result=`scp $::XCATROOT/sbin/rmcmon/configrmcnode $node:/tmp 2>&1`;
      if ($?) {
        xCAT::MsgUtils->message('SI', "[mon]: rmcmon:addNodes: cannot copy the file configrmcnode to node $node\n");
        next;
      }

      $result=`$::XCATROOT/bin/psh --nonodecheck $node NODE=$node MONSERVER=$master MS_NODEID=$ms_node_id /tmp/configrmcnode 1 2>&1`;
      if ($?) {
        xCAT::MsgUtils->message('SI',  "[mon]: $result\n");
      }
    }
  } 

  return (0, "ok"); 
}

#--------------------------------------------------------------------------------
=head3    removeNodes
      This function removes the nodes from the RMC cluster.
    Arguments:
      nodes --nodes to be added. It is a pointer to an array. If the next argument is
       1, each element is a ref to an array of [nodes, nodetype, status]. For example: 
          [['node1', 'active'], ['node2', 'booting']..]. 
       if the next argument is 0, each element is a node name to be added.
      boolean -- 1, or 0. 
    Returns:
       (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub removeNodes {
  return (0, "ok"); #not handle it now, wait when nodelist.status work is done

}


#--------------------------------------------------------------------------------
=head3    removeNodes_noChecking
      This function removes the nodes from the RMC cluster.
    Arguments:
      nodes --a pointer to a array of node names to be removed. 
     
    Returns:
      (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub removeNodes_noChecking {
  my $pmon_nodes=shift;
  if ($pmon_nodes =~ /xCAT_monitoring::rmcmon/) {
    $pmon_nodes=shift;
  }
  my @mon_nodes = @$pmon_nodes;

  my $ms_host_name=hostname();
 

  #print "rmcmon::removeNodes_noChecking get called with @mon_nodes\n";

  foreach(@mon_nodes) {
    my $node=$_;

    #remove resource in IBM.MngNode class on server
    my $result=`rmrsrc-api -s IBM.MngNode::"Name=\\\"\"$node\\\"\"" 2>&1`;
    if ($?) {  
      if ($result =~ m/2612-023/) { #resource not found
       next;
      }
      xCAT::MsgUtils->message('SI', "[mon]: Remove resource in IBM.MngNode class result=$result\n");
    }

    # TODO: check all the nodes together or use the 'status' value
    #if the node is inactive, forget it
    if ($ms_host_name ne $node) {
      `fping -a $node 2> /dev/null`;
      if ($?) {
       next;
      }
    }

    if ($ms_host_name eq $node) {
      $result= `/usr/bin/rmrsrc-api -s IBM.MCP::"MNName=\\\"\"$node\\\"\"" 2>&1`;
      if ($?) {
        xCAT::MsgUtils->message('SI', "[mon]: $result\n");
      }
    } else {
      #copy the configuration script and run it locally
      $result=`scp $::XCATROOT/sbin/rmcmon/configrmcnode $node:/tmp 2>&1 `;
      if ($?) {
        xCAT::MsgUtils->message('SI', "[mon]: rmcmon:removeNodes: cannot copy the file configrmcnode to node $node\n");
        next;
      }

      $result=`$::XCATROOT/bin/psh --nonodecheck $node NODE=$node /tmp/configrmcnode -1 2>&1`;
      if ($?) {
        xCAT::MsgUtils->message('SI', "[mon]: $result\n");
      }
    }
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
    used to provide node liveness status monitoring for xCAT. RMC is 
    good for threadhold monitoring. xCAT automatically sets up the 
    monitoring domain for RMC during node deployment time. To start 
    RMC monitoring, use
      monstart rmcmon
    or 
      monstart rmcmon -n   (to include node status monitoring).
  Settings:
    none.\n";
}

#--------------------------------------------------------------------------------
=head3    getNodeConfData
      This function gets a list of configuration data that is needed by setting up
    node monitoring.  These data-value pairs will be used as environmental variables 
    on the given node.
    Arguments:
        node  
        pointer to a hash that will take the data.
    Returns:
        none
=cut
#--------------------------------------------------------------------------------
sub getNodeConfData {
  #check if rsct is installed or not
  if (! -e "/usr/bin/lsrsrc") {
    return;
  }

  my $node=shift;
  if ($node =~ /xCAT_monitoring::rmcmon/) {
    $node=shift;
  }
  my $ref_ret=shift;

  #get node ids for RMC monitoring
  my $nodeid=xCAT_monitoring::rmcmon->getNodeID($node);
  if (defined($nodeid)) {
    $ref_ret->{NODEID}=$nodeid;
  }
  my $ms_nodeid=xCAT_monitoring::rmcmon->getLocalNodeID();
  if (defined($ms_nodeid)) {
    $ref_ret->{MS_NODEID}=$ms_nodeid;
  }
  return;
}

