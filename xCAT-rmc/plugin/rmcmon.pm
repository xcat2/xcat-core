#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_monitoring::rmcmon;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::NodeRange;
use Socket;
use xCAT::Utils;
use xCAT::GlobalDef;

print "xCAT_monitoring::rmcmon loaded\n";

1;
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
      monservers --A hash reference keyed by the monitoring server nodes 
         and each value is a ref to an array of [nodes, nodetype] arrays  
         monitored by the server. So the format is:
           {monserver1=>[['node1', 'osi'], ['node2', 'switch']...], ...}   
    Returns:
      (return code, message)      
=cut
#--------------------------------------------------------------------------------
sub start {
  print "rmcmon::start called\n";

  $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::rmcmon/) {
    $noderef=shift;
  }

  #TODO: get a list of monservers + nodes and compare them with RMC. remove/add 
  # if necessary. 
    
  #assume the server is the current node.
  #check if rsct is installed and running
  if (! -e "/usr/bin/lsrsrc") {
    return (1, "RSCT is not is not installed.\n");
  }
  my $result=`/usr/bin/lssrc -s ctrmc`;
  if ($result !~ /active/) {
    #restart rmc daemon
    $result=`startsrc -s ctrmc`;
    if ($?) {
      return (1, "rmc deamon cannot be started\n");
    }
  }
  
  #get a list of managed nodes
  $result=`/usr/bin/lsrsrc-api -s IBM.MngNode::::Name`;
  chomp($result);
  my @rmc_nodes=split(/\n/, $result);

  foreach (keys(%$noderef)) {
    my $server=$_;

    my $mon_nodes=$noderef->{$_};
    foreach(@$mon_nodes) {
      my $node_pair=$_;
      my $node=$node_pair->[0];
      my $nodetype=$node_pair->[1];
       
    }
  }

  

  #TODO: start condition-response assosciations 

  return (0, "started");
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
  print "rmcmon::stop called\n";

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
  print "rmcmon::supportNodeStatusMon called\n";
  return 1;
}



#--------------------------------------------------------------------------------
=head3   startNodeStatusMon
    This function is called by the monitorctrl module to tell
    RMC to start monitoring the node status and feed them back
    to xCAT. RMC will start setting up the condition/response 
    to monitor the node status changes.  

    Arguments:
      monservers --A hash reference keyed by the monitoring server nodes 
         and each value is a ref to an array of [nodes, nodetype] arrays  
         monitored by the server. So the format is:
           {monserver1=>[['node1', 'osi'], ['node2', 'switch']...], ...}   
    Returns:
        (return code, message)

=cut
#--------------------------------------------------------------------------------
sub startNodeStatusMon {
  print "rmcmon::startNodeStatusMon called\n";
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
  print "rmcmon::stopNodeStatusMon called\n";
  return (0, "stopped");
}


#--------------------------------------------------------------------------------
=head3    addNodes
      This function gdds the nodes into the RMC cluster.
    Arguments:
      nodes --nodes to be added. It is a  hash reference keyed by the monitoring server 
        nodes and each value is a ref to an array of [nodes, nodetype] arrays  monitored 
        by the server. So the format is:
          {monserver1=>[['node1', 'osi'], ['node2', 'switch']...], ...} 
      verbose -- verbose mode. 1 for yes, 0 for no.
    Returns:
       none
=cut
#--------------------------------------------------------------------------------
sub addNodes {
  $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::rmcmon/) {
    $noderef=shift;
  }
  my $VERBOSE=shift;

  if ($VERBOSE) { print "rmcmon::addNodes called $noderef=$noderef\n"};

  foreach (keys(%$noderef)) {
    my $server=$_;
    if ($VERBOSE) { print "  monitoring server: $server\n";}

    #check if rsct is installed and running
    if (! -e "/usr/bin/lsrsrc") {
      print "RSCT is not is not installed.\n";
      next;
    }
    my $result=`/usr/bin/lssrc -s ctrmc`;
    if ($result !~ /active/) {
      #restart rmc daemon
      $result=`startsrc -s ctrmc`;
      if ($?) {
        print "rmc deamon cannot be started\n";
        next;
      }
    }

    #enable remote client connection
    `/usr/bin/rmcctrl -p`;

    #get ms node id, hostname, ip etc
    #TODO: currently one server which is where xcatd is. later changes to use server for hierachy
    my $ms_node_id=`head -n 1 /var/ct/cfg/ct_node_id`;
    chomp($ms_node_id);
    my $ms_host_name=`hostname`;
    chomp($ms_host_name);
    my ($ms_name,$ms_aliases,$ms_addrtype,$ms_length,@ms_addrs) = gethostbyname($ms_host_name);
    chomp($ms_name);

    my $ms_ipaddresses="{";
    foreach (@ms_addrs) {
      $ms_ipaddresses .= '"' .inet_ntoa($_) . '",';
    }
    chop($ms_ipaddresses);
    $ms_ipaddresses .= "}";

    #if ($VERBOSE) {
    #  print "    ms_host_name=$ms_host_name, ms_nam=$ms_name, ms_aliases=$ms_aliases, ms_ip_addr=$ms_ipaddresses, ms_node_id=$ms_node_id\n";
    #}

    my $mon_nodes=$noderef->{$_};
    foreach(@$mon_nodes) {
      my $node_pair=$_;
      my $node=$node_pair->[0];
      my $nodetype=$node_pair->[1]; 
      if ((!$nodetype) || ($nodetype =~ /$::NODETYPE_OSI/)) {
        #RMC deals only with osi type. empty type is treated as osi type

        #TODO: check if the node is installed and ready for configuring monitor
        `fping -a $node 2> /dev/null`;
        if ($?) {
	  print "Cannot add the node $node into the RMC domian. The node is inactive.\n";
	  next;
        }

        #get info for the node
        $mn_node_id=`psh $node "head -n 1 /var/ct/cfg/ct_node_id" 2>&1`;
        $mn_node_id =~ s/.*([0-9 a-g]{16}).*/$1/s;

        my ($mn_name,$mn_aliases,$mn_addrtype,$mn_length,@mn_addrs) = gethostbyname($node);
        chomp($mn_name);
        my $mn_ipaddresses="{";
        foreach (@mn_addrs) {
          $mn_ipaddresses .= '"'.inet_ntoa($_) . '",';
        }
        chop($mn_ipaddresses);
        $mn_ipaddresses .= "}";
        #if ($VERBOSE) {
        #  print "    mn_name=$mn_name, mn_aliases=$mn_aliases,   mn_ipaddr=$mn_ipaddresses,  mn_node_id=$mn_node_id\n";          
        #}

        # define resource in IBM.MngNode class on server
        $result=`mkrsrc-api IBM.MngNode::Name::"$node"::KeyToken::"$node"::IPAddresses::"$mn_ipaddresses"::NodeID::0x$mn_node_id`;
        print "define resource in IBM.MngNode class result=$result\n"; 

        #copy the configuration script and run it locally
        $result=`scp $::XCATROOT/lib/perl/xCAT_monitoring/rmc/configrmcnode $node:/tmp`;
        if ($resul>0) {
          print "rmcmon:addNodes: cannot copy the file configrmcnode to node $node\n";
          next;
        }

        $result=`psh $node /tmp/configrmcnode -a $node $ms_host_name $ms_ipaddresses 0x$ms_node_id`;
        print "$result\n";
      } 
    }
  }


  return 0;
}

#--------------------------------------------------------------------------------
=head3    removeNodes
      This function removes the nodes from the RMC cluster.
    Arguments:
      nodes --nodes to be removed. It is a hash reference keyed by the monitoring server 
        nodes and each value is a ref to an array of [nodes, nodetype] arrays  monitored 
        by the server. So the format is:
        {monserver1=>[['node1', 'osi'], ['node2', 'switch']...], ...} 
      verbose -- verbose mode. 1 for yes, 0 for no.
    Returns:
       none
=cut
#--------------------------------------------------------------------------------
sub removeNodes {
  $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::rmcmon/) {
    $noderef=shift;
  }
  my $VERBOSE=shift;

  #if ($VERBOSE) { print "rmcmon::removeNodes called $noderef=$noderef\n"};

  foreach (keys(%$noderef)) {
    $server=$_;
    #print "  monitoring server: $server\n";

    my $mon_nodes=$noderef->{$_};
    foreach(@$mon_nodes) {
      my $node_pair=$_;
      my $node=$node_pair->[0];
      my $nodetype=$node_pair->[1]; 
      #if ($VERBOSE) { print "    node=$node, nodetype=$nodetype\n"; }
      if ((!$nodetype) || ($nodetype =~ /$::NODETYPE_OSI/)) {
        #RMC deals only with osi type. empty type is treated as osi type

        #TODO: check if the node is installed and ready for configuring monitor
        `fping -a $node 2> /dev/null`;
        if ($?) {
	  print "Cannot remove node $node from the RMC domian. The node is inactive.\n";
	  next;
        }

        #remove resource in IBM.MngNode class on server
        my $result=`rmrsrc-api -s IBM.MngNode::"Name=\\\"\"$node\\\"\""`;
	if ($VERBOSE) { print "remove resource in IBM.MngNode class result=$result\n"; }

        #copy the configuration script and run it locally
        $result=`scp $::XCATROOT/lib/perl/xCAT_monitoring/rmc/configrmcnode $node:/tmp`;
        if ($resul>0) {
          print "rmcmon:removeNodes: cannot copy the file configrmcnode to node $node\n";
          next;
        }

        $result=`psh --nonodecheck $node /tmp/configrmcnode -d $node`;
        print "$result\n";
      }           
    }
  }


  return 0;

}


