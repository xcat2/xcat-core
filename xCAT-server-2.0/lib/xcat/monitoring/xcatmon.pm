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
      None.
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
      None.
    Returns:
        (return code, message)

=cut
#--------------------------------------------------------------------------------
sub startNodeStatusMon {
  my $temp=shift;
  if ($temp =~ /xCAT_monitoring::xcatmon/) {
    $temp=shift;
  }

  #print "xcatmon.startNodeStatusMon\n";

  #run the command first to update the status, 
  my $cmd="$::XCATROOT/sbin/xcatnodemon";
  #$output=`$cmd 2>&1`;
  #if ($?) {
  #  print "xcatmon: $output\n";
  #}
  
  #figure out the ping-intercal setting
  my $value=3; #default
  my %settings=xCAT_monitoring::monitorctrl->getPluginSettings("xcatmon");

  #print "settings for xcatmon:\n";
  #foreach (keys(%settings)) {
  #  print "key=$_, value=$settings{$_}\n";
  #}
  my $reading=$settings{'ping-interval'};
  if ($reading>0) { $value=$reading;}
   
  #create the cron job, it will run the command every 3 minutes.
  my $newentry;
  if (xCAT::Utils->isAIX()) {
    #AIX does not support */value format, have to list them all.
    my $minutes;
    if ($value==1) { $minutes='*';}
    elsif ($value<=30) {
      my @temp_a=(0..59);
      foreach (@temp_a) {
        if (($_ % $value) == 0) { $minutes .= "$_,";}
      }
      chop($minutes);
    } else {
      $minutes="0";
    }
    $newentry="$minutes * * * * XCATROOT=$::XCATROOT PATH=$ENV{'PATH'} XCATCFG='$ENV{'XCATCFG'}' $cmd";
  } else {
    $newentry="*/$value * * * * XCATROOT=$::XCATROOT PATH=$ENV{'PATH'} XCATCFG='$ENV{'XCATCFG'}' $cmd";
  }
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
      nodes --nodes to be added. It is a pointer to an array with each element
        being a ref to an array of [nodes, nodetype, status]. For example: 
          [['node1', 'osi', 'active'], ['node2', 'switch', 'booting']..] 
    Returns:
       (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub addNodes {

  #print "xcatmon:addNodes called\n";
 
  return (0, "ok");
}

#--------------------------------------------------------------------------------
=head3    removeNodes
      This function is called by the monitorctrl module when nodes are removed 
      from the xCAT cluster. It should remove the nodes from the product for monitoring.
    Arguments:
      nodes --nodes to be removed. It is a pointer to an array with each element
        being a ref to an array of [nodes, nodetype, status]. For example: 
          [['node1', 'osi', 'active'], ['node2', 'switch', 'booting']..] 
    Returns:
       (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub removeNodes {

  #print "xcatmon:removeNodes called\n";

  return (0, "ok");
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

  my $hierachy=xCAT_monitoring::monitorctrl->getMonHierarchy();
  my @mon_servers=keys(%$hierachy); 
  my $isSV=xCAT::Utils->isServiceNode(); 
  
  #on a service node or on ms, get the nodes that has local host as the server node
  my $monnodes;
  my @hostinfo=xCAT::Utils->determinehostname();
  my %iphash=();
  foreach(@hostinfo) {$iphash{$_}=1;}
  #if this is mn, include the ones that has no service nodes
  if (!$isSV) { $iphash{'noservicenode'}=1;}
  

  foreach(@mon_servers) {
    #service node come in pairs, the first one is the monserver adapter that facing the mn,
    # the second one is facing the cn. we use the first one here
    my @server_pair=split(',', $_); 
    my $sv=$server_pair[0];
    if ($iphash{$sv}) {
      $monnodes=$hierachy->{$_};
    }
  }
     
  foreach(@$monnodes) {
    my $node=$_->[0];
    my $status=$_->[2];
    if ($status eq $::STATUS_ACTIVE) { push(@active_nodes, $node);}
    elsif ($status eq $::STATUS_INACTIVE) { push(@inactive_nodes, $node);}
    else { push(@unknown_nodes, $node);}
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
  if ($temp =~ /xCAT_monitoring::xcatmon/) {
    $temp=shift;
  }
  return xCAT_monitoring::monitorctrl->processNodeStatusChanges($temp);
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
  #restart the cron job
  xCAT_monitoring::xcatmon->stopNodeStatusMon();
  xCAT_monitoring::xcatmon->startNodeStatusMon();  
}

#--------------------------------------------------------------------------------
=head3    getDiscription
      This function returns the detailed description of the plugin inluding the
     valid values for its settings in the mon setting tabel. 
     Arguments:
        none
    Returns:
        The description.
=cut
#--------------------------------------------------------------------------------
sub getDescription {
  return 
"  Description:
    xcatmon uses fping to report the node liveness status and update the 
    nodelist.status column. Use command 'monstart xcatmon -n' to start 
    monitoring. 
  Settings:
    ping-interval:  the number of minutes between each fping operation. 
        The default value is 3.";
}
