#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_monitoring::templatemon;

#use xCAT::NodeRange;
#use Socket;
#use xCAT::Utils;


1;
#-------------------------------------------------------------------------------
=head1  xCAT_monitoring:templatemon  
=head2    Package Description
   This is a xCAT monitoring plugin template. To use it, first register the plug-in
   name to the monitoring table use chtab command. For example:
      chtab name=xxxmon monitoring.nodestatmon=1 (0r 0). 
   Then change the package name from xCAT_monitoring::templatemon to xCAT_monitoring::xxxmon.
   Change the file name to xxxmon.pm and copy the file to /opt/xcat/lib/perl/xCAT_monitoring/
   directory.  
=cut
#-------------------------------------------------------------------------------

#--------------------------------------------------------------------------------
=head3    start
      This function gets called by the monitorctrl module
      when xcatd starts. It should perform all the necessary 
      startup process for a monitoring product.
      It also queries the product for its currently monitored
      nodes which will, in tern, compared with the nodes
      in the input parameter. It asks the product to add or delete
      nodes according to the comparison so that the nodes
      monitored by the product are in sync with the nodes currently
      in the xCAT cluster.
    Arguments:
      monservers --A hash reference keyed by the monitoring server nodes 
         and each value is a ref to an array of [nodes, nodetype, status] arrays  
         monitored by the server. So the format is:
           {monserver1=>[['node1', 'osi', 'active'], ['node2', 'switch', 'booting']...], ...}   
    Returns:
      (return code, message)      
=cut
#--------------------------------------------------------------------------------
sub start {
  my $monservers=shift;
  if ($monservers =~ /xCAT_monitoring::templatemon/) {
    $monservers=shift;
  }

  #demo how you can parse the input. you may commnet it out.
  my $monservers=shift;
  foreach (keys(%$monservers)) {
    print "  monitoring server: $_\n";
    my $mon_nodes=$monservers->{$_};
    foreach(@$mon_nodes) {
      my $node_info=$_;
      print "    node=$node_info->[0], nodetype=$node_info->[1], status=$node_info->[2]\n";
    }
  }

  #TODO: add code here to start the product for monitoring. 
  #TODO: compare the nodes with input and add/delete nodes to/from the product if needed.
  return (0, "started");
}



#--------------------------------------------------------------------------------
=head3    stop
      This function gets called by the monitorctrl module when
      xcatd stops. It stops the monitoring on all nodes, 
      and does necessary cleanup process for the product.
    Arguments:
       none
    Returns:
       (return code, message)
=cut
#--------------------------------------------------------------------------------
sub stop {

  #TODO: stop the product from monitoring the xCAT cluster
  
  return (0, "stopped");
}




#--------------------------------------------------------------------------------
=head3    supportNodeStatusMon
    This function is called by the monitorctrl module to check
    if this product can help monitoring and returning the node status.
    
    Arguments:
        none
    Returns:
           0 means not support. 
           1 means yes.
=cut
#--------------------------------------------------------------------------------
sub supportNodeStatusMon {
  #TODO: change the return value here.
  return 1;
}



#--------------------------------------------------------------------------------
=head3   startNodeStatusMon
    This function is called by the monitorctrl module to tell
    the product to start monitoring the node status and feed them back
    to xCAT.  
    Arguments:
      monservers --A hash reference keyed by the monitoring server nodes 
         and each value is a ref to an array of [nodes, nodetype, status] arrays  
         monitored by the server. So the format is:
           {monserver1=>[['node1', 'osi', 'active'], ['node2', 'switch', 'booting']...], ...}   
    Returns:
        (return code, message)

=cut
#--------------------------------------------------------------------------------
sub startNodeStatusMon {
  my $monservers=shift;
  if ($monservers =~ /xCAT_monitoring::templatemon/) {
    $monservers=shift;
  }

  #demo how you can parse the input. you may commnet it out.
  my $monservers=shift;
  foreach (keys(%$monservers)) {
    print "  monitoring server: $_\n";
    my $mon_nodes=$monservers->{$_};
    foreach(@$mon_nodes) {
      my $node_info=$_;
      print "    node=$node_info->[0], nodetype=$node_info->[1], status=$node_info->[2]\n";
    }
  }
 
  #TODO: turn on the node status monitoring. use nodech command to feed the new
  return (0, "started");
}


#--------------------------------------------------------------------------------
=head3   stopNodeStatusMon
    This function is called by the monitorctrl module to tell
    the product to stop feeding the node status info back to xCAT. 

    Arguments:
        none
    Returns:
        (return code, message)
=cut
#--------------------------------------------------------------------------------
sub stopNodeStatusMon {
  #TODO: turn off the node status monitoring. 
  return (0, "stopped");
}


#--------------------------------------------------------------------------------
=head3    addNodes
      This function is called by the monitorctrl module when new nodes are added 
      to the xCAT cluster. It should add the nodes into the product for monitoring.
    Arguments:
      nodes --nodes to be added. It is a  hash reference keyed by the monitoring server 
        nodes and each value is a ref to an array of [nodes, nodetype, status] arrays  monitored 
        by the server. So the format is:
          {monserver1=>[['node1', 'osi', 'active'], ['node2', 'switch', 'bboting']...], ...} 
    Returns:
       none
=cut
#--------------------------------------------------------------------------------
sub addNodes {
  $noderef=shit;
  if ($noderef =~ /xCAT_monitoring::templatemon/) {
    $noderef=shift;
  }

  #demo how you can parse the input. you may commnet it out.
  foreach (keys(%$noderef)) {
    print "  monitoring server: $_\n";
    my $mon_nodes=$noderef->{$_};
    foreach(@$mon_nodes) {
      my $node_info=$_;
      print "    node=$node_info->[0], nodetype=$node_info->[1], status=$node_info->[2]\n";
    }
  }
 
  #TODO: include the nodes into the product for monitoring. 
  return;
}

#--------------------------------------------------------------------------------
=head3    removeNodes
      This function is called by the monitorctrl module when nodes are removed 
      from the xCAT cluster. It should remove the nodes from the product for monitoring.
    Arguments:
      nodes --nodes to be removed. It is a hash reference keyed by the monitoring server 
        nodes and each value is a ref to an array of [nodes, nodetype, status] arrays  monitored 
        by the server. So the format is:
        {monserver1=>[['node1', 'osi', 'active'], ['node2', 'switch', 'booting']...], ...} 
    Returns:
       none
=cut
#--------------------------------------------------------------------------------
sub removeNodes {
  $noderef=shit;
  if ($noderef =~ /xCAT_monitoring::templatemon/) {
    $noderef=shift;
  }

  #demo how you can parse the input. you may commnet it out.
  foreach (keys(%$noderef)) {
    print "  monitoring server: $_\n";
    my $mon_nodes=$noderef->{$_};
    foreach(@$mon_nodes) {
      my $node_info=$_;
      print "    node=$node_info->[0], nodetype=$node_info->[1], status=$node_info->[2]\n";
    }
  }

  #TODO: remove the nodes from the product for monitoring.
  return;
}


