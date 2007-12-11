#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_monitoring::xcatmon;
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
#use xCAT::NodeRange;
#use Socket;
#use xCAT::Utils;
#use xCAT::GlobalDef;
use xCAT::Utils;


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
         and each value is a ref to an array of [nodes, nodetype] arrays  
         monitored by the server. So the format is:
           {monserver1=>[['node1', 'osi'], ['node2', 'switch']...], ...}   
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
         and each value is a ref to an array of [nodes, nodetype] arrays  
         monitored by the server. So the format is:
           {monserver1=>[['node1', 'osi'], ['node2', 'switch']...], ...}   
    Returns:
        (return code, message)

=cut
#--------------------------------------------------------------------------------
sub startNodeStatusMon {
  #print "xcatmon.startNodeStatusMon\n";
  my $newentry="*/3 * * * * $::XCATROOT/sbin/xcatnodemon";
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
        nodes and each value is a ref to an array of [nodes, nodetype] arrays  monitored 
        by the server. So the format is:
          {monserver1=>[['node1', 'osi'], ['node2', 'switch']...], ...} 
    Returns:
       none
=cut
#--------------------------------------------------------------------------------
sub addNodes {

  #print "xcatmon:addNodes called\n";
 
  #TODO: include the nodes into the product for monitoring. 
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

  #TODO: remove the nodes from the product for monitoring.
  return;
}


