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
use xCAT::MsgUtils;

#print "xCAT_monitoring::rmcmon loaded\n";
1;

#now the RMC domain can automatically setup when xCAT starts. predefined conditions and sensor are defined on ms.
#TODO: predefined responses
#TODO: node status monitoring for xCAT.
#TODO: script to define sensors on the nodes.
#TODO: how to push the sensor scripts to nodes?
#TODO: what to do when stop is called? stop all the associations or just the ones that were predefined? or leve them there?
#TODO: do we need to stop all the RMC daemons when stop is called?
#I will come back to work on these once I have SNMP stuff done. 

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
  print "rmcmon::start called\n";

  my $noderef=xCAT_monitoring::monitorctrl->getMonHierarchy();
    
  #assume the server is the current node.
  #check if rsct is installed and running
  if (! -e "/usr/bin/lsrsrc") {
    return (1, "RSCT is not installed.\n");
  }
  my $result=`/usr/bin/lssrc -s ctrmc`;   #TODO: change this
  if ($result !~ /active/) {
    #restart rmc daemon
    $result=`startsrc -s ctrmc`;
    if ($?) {
      return (1, "rmc deamon cannot be started\n");
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
  print "RMC defined nodes=@rmc_nodes\n";

  
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
      print "active nodes to add:@$active_nodes\ninactive nodes to add: @$inactive_nodes\n";
      if (@$inactive_nodes>0) { 
        xCAT::MsgUtils->message('SI', "[mon]: The following nodes cannot be added to the RMC cluster because they are inactive:\n  @$inactive_nodes\n");
      }
      if (@$active_nodes>0) {
        addNodes_noChecking(@$active_nodes);
      }
    }  

    #remove unwanted nodes to the RMC cluster
    if (@nodes_to_remove>0) {
      print "nodes to remove @nodes_to_remove\n"; 
      removeNodes_noChecking(@nodes_to_remove);
    }  

    #start condition-response assosciations 
    my $result=`$::XCATROOT/sbin/rmcmon/mkrmcresources $::XCATROOT/lib/perl/xCAT_monitoring/rmc/resources/mn 2>&1`;
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
  return (0, "started");
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
  return (0, "stopped");
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


  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::rmcmon/) {
    $noderef=shift;
  }
  my $bWithInfo=shift;
  #print "rmcmon::addNodes get called\n";
  my $mon_nodes=$noderef;
  

  my @hostinfo=xCAT::Utils->determinehostname();
  %iphash=();
  foreach(@hostinfo) {$iphash{$_}=1;}

  my @nodes_to_add=();
  my $table3=xCAT::Table->new("nodetype", -create =>0);
  foreach(@$mon_nodes) {
    my $node_pair=$_;
    my $node=$node_pair->[0];
    my $status=$node_pair->[1];

    #get node type
    my $tmp3=$table3->getNodeAttribs($node, ['nodetype']);
    my $nodetype="osi"; #default
    if (defined($tmp3) && ($tmp3)) {
      if ($tmp3->{nodetype}) { $nodetype=$tmp3->{nodetype}; }
    }

    if ($nodetype =~ /$::NODETYPE_OSI/) {
      #RMC deals only with osi type. empty type is treated as osi type
      #check if the node has already defined
      $result=`lsrsrc-api -s IBM.MngNode::"Name=\\\"\"$node\\\"\"" 2>&1`;
      if (($?) && ($result !~ /2612-023/)) { #2612-023 no resources found error
	xCAT::MsgUtils->message('SI', "[mon]: $result\n");
        next;
      } 

      #check if the node is active
      my $active=0;
      if (exists($iphash{$node})) { $active=1;} 
      elsif ($status && ($status eq $::STATUS_ACTIVE)) { $active=1; }
      else {
        `fping -a $node 2> /dev/null`;
	 if ($?==0) {$active=1; }
      }
      if (!$active) {
        xCAT::MsgUtils->message('SI', "[mon]: Cannot add the node $node into the RMC domian. The node is inactive.\n");
        next;
      }

      push(@nodes_to_add, $node); 
    } 
  }
  $table3->close();

  if (@nodes_to_add>0) {
    return addNodes_noChecking(@nodes_to_add);
  }
   
  return (0, "ok");
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
 
  @mon_nodes = @_;
  #print "rmcmon::addNodes_noChecking get called with @mon_nodes\n";
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
    if($ms_host_name eq $node) {
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
    if($ms_host_name eq $node) {
      $result=`/usr/bin/mkrsrc-api IBM.MCP::MNName::"$node"::KeyToken::"$ms_host_name"::IPAddresses::"$ms_ipaddresses"::NodeID::0x$ms_node_id`;      
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

      $result=`$::XCATROOT/bin/psh --nonodecheck $node /tmp/configrmcnode -a $node $ms_host_name $ms_ipaddresses 0x$ms_node_id 2>&1`;
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

  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::rmcmon/) {
    $noderef=shift;
  }
  my $bWithInfo=shift;
  my $mon_nodes=$noderef;

  #print "rmcmon::removeNodes called\n";

  my @nodes_to_remove=();

  my $table3=xCAT::Table->new("nodetype", -create =>0);
  foreach(@$mon_nodes) {
    my $node_pair=$_;
    my $node=$node_pair->[0]; 
    my $status=$node_pair->[1]; 

    #get node type
    my $tmp3=$table3->getNodeAttribs($node, ['nodetype']);
    my $nodetype="osi"; #default
    if (defined($tmp3) && ($tmp3)) {
      if ($tmp3->{nodetype}) { $nodetype=$tmp3->{nodetype}; }
    }

    if ((!$nodetype) || ($nodetype =~ /$::NODETYPE_OSI/)) {
      #RMC deals only with osi type. empty type is treated as osi type
      push(@nodes_to_remove, $node);
    }
  }
  $table3->close();

  if (@nodes_to_remove>0) {
    return removeNodes_noChecking(@nodes_to_remove);
  }

  return (0, "ok");
}


#--------------------------------------------------------------------------------
=head3    removeNodes_noChecking
      This function removes the nodes from the RMC cluster.
    Arguments:
      nodes --an array of node names to be removed. 
    Returns:
      (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub removeNodes_noChecking {
  my @mon_nodes = @_;
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

      $result=`$::XCATROOT/bin/psh --nonodecheck $node /tmp/configrmcnode -d $node 2>&1`;
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
    rmcmon ..... 
  Settings:
    key:  value.\n";
}
