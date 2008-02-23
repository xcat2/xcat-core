#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_monitoring::xcatmon;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::Utils;
use xCAT::GlobalDef;
use xCAT_monitoring::monitorctrl;
use Sys::Hostname;


1;
#-------------------------------------------------------------------------------
=head1  xCAT_monitoring:xcatmon  
=head2    Package Description
   This is a xCAT monitoring plugin. The only thing that this plug-in does is 
   the node monitoring. To activate it simply do the following command:
      chtab pname=xCAT monitoring.nodestatmon=Y
=cut
#-------------------------------------------------------------------------------

#--------------------------------------------------------------------------------
=head3    start
      This function gets called by the monitorctrl module
      when xcatd starts.  
    Arguments:
      monservers --A hash reference keyed by the monitoring server nodes 
         and each value is a ref to an array of [nodes, nodetype, status] arrays  
         monitored by the server. So the format is:
           {monserver1=>[['node1', 'osi', 'active'], ['node2', 'switch', 'booting']...], ...}
      settings -- ping-interval=x,   x is in number of minutes   
    Returns:
      (return code, message)      
=cut
#--------------------------------------------------------------------------------
sub start {
  #print "xcatmon.start\n";

  return (0, "started");
}



#--------------------------------------------------------------------------------
=head3    stop
      This function gets called by the monitorctrl module when
      xcatd stops. 
    Arguments:
       none
    Returns:
       (return code, message)
=cut
#--------------------------------------------------------------------------------
sub stop {
  
  return (0, "stopped");
}




#--------------------------------------------------------------------------------
=head3    supportNodeStatusMon
    This function is called by the monitorctrl module to check
    if this product can help monitoring and returning the node status.
    
    Arguments:
        none
    Returns:
        1
=cut
#--------------------------------------------------------------------------------
sub supportNodeStatusMon {
  
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
      settings -- ping-interval=x,   x is in number of minutes   
    Returns:
        (return code, message)

=cut
#--------------------------------------------------------------------------------
sub startNodeStatusMon {
  my $temp=shift;
  if ($temp =~ /xCAT_plugin::xcatmon/) {
    $temp=shift;
  }
  my $setting=shift;

  #print "xcatmon.startNodeStatusMon\n";

  #run the command first to update the status, 
  my $cmd="$::XCATROOT/sbin/xcatnodemon";
  #$output=`$cmd 2>&1`;
  #if ($?) {
  #  print "xcatmon: $output\n";
  #}
  
  #figure out the ping-intercal setting
  my $value=3;
  if ($setting) {
    if ($setting =~ /ping-interval=(\d+)/) { $value= ($1>0) ? $1 : 3; }
  }

 
  #create the cron job, it will run the command every 3 minutes.
  my $newentry="*/$value * * * * XCATROOT=$::XCATROOT $cmd";
  my ($code, $msg)=xCAT::Utils::add_cron_job($newentry);
  if ($code==0) { return (0, "started"); }
  else {  return ($code, $msg); } 
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
  
  my $job="$::XCATROOT/sbin/xcatnodemon";
  my ($code, $msg)=xCAT::Utils::remove_cron_job($job);
  if ($code==0) { return (0, "stopped"); }
  else {  return ($code, $msg); }

}


#--------------------------------------------------------------------------------
=head3    addNodes
      This function is called by the monitorctrl module when new nodes are added 
      to the xCAT cluster. It should add the nodes into the product for monitoring.
    Arguments:
      nodes --nodes to be added. It is a  hash reference keyed by the monitoring server 
        nodes and each value is a ref to an array of [nodes, nodetype, status] arrays  monitored 
        by the server. So the format is:
          {monserver1=>[['node1', 'osi', 'active'], ['node2', 'switch', 'booting']...], ...} 
    Returns:
       none
=cut
#--------------------------------------------------------------------------------
sub addNodes {

  #print "xcatmon:addNodes called\n";
 
  return;
}

#--------------------------------------------------------------------------------
=head3    removeNodes
      This function is called by the monitorctrl module when nodes are removed 
      from the xCAT cluster. It should remove the nodes from the product for monitoring.
    Arguments:
      nodes --nodes to be removed. It is a hash reference keyed by the monitoring server 
        nodes and each value is a ref to an array of [nodes, nodetype] arrays  monitored 
        by the server. So the format is:
        {monserver1=>[['node1', 'osi'], ['node2', 'switch']...], ...} 
    Returns:
       none
=cut
#--------------------------------------------------------------------------------
sub removeNodes {

  #print "xcatmon:removeNodes called\n";

  return;
}


#--------------------------------------------------------------------------------
=head3    getMonNodesStatus
      This function goes to the xCAT nodelist table to retrieve the saved node status
      for all the node that are managed by local nodes.
    Arguments:
       none.
    Returns:
       a hash that has the node status. The format is: 
          {active=>[node1, node3,...], unreachable=>[node4, node2...], unknown=>[node8, node101...]}
=cut
#--------------------------------------------------------------------------------
sub getMonNodesStatus {
  %status=();
  my @inactive_nodes=();
  my @active_nodes=();
  my @unknown_nodes=();

  my $monservers=xCAT_monitoring::monitorctrl->getMonHierarchy();

  my $host=hostname();
  my $monnodes=$monservers->{$host};
  if (($monnodes) && (@$monnodes >0)) {
    foreach(@$monnodes) {
      my $node=$_->[0];
      my $status=$_->[2];
      if ($status eq $::STATUS_ACTIVE) { push(@active_nodes, $node);}
      elsif ($status eq $::STATUS_INACTIVE) { push(@inactive_nodes, $node);}
      else { push(@unknown_nodes, $node);}
    }
  }

  $status{$::STATUS_ACTIVE}=\@active_nodes;
  $status{$::STATUS_INACTIVE}=\@inactive_nodes;
  $status{unknown}=\@unknown_nodes;

  return %status;
}


#--------------------------------------------------------------------------------
=head3    processNodeStatusChanges
      This function will update the status column of the
      nodelist table with the new node status.
    Arguments:
       status -- a hash pointer of the node status. A key is a status string. The value is 
                an array pointer of nodes that have the same status.
                for example: {active=>["node1", "node1"], inactive=>["node5","node100"]}
    Returns:
        0 for successful.
        non-0 for not successful.
=cut
#--------------------------------------------------------------------------------
sub processNodeStatusChanges {
  my $temp=shift;
  if ($temp =~ /xCAT_plugin::xcatmon/) {
    $temp=shift;
  }
  return xCAT_monitoring::monitorctrl->processNodeStatusChanges($temp);
}
