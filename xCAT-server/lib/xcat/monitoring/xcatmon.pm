#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_monitoring::xcatmon;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
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
      This function gets called by the monitorctrl module when monstart command 
     gets called and when xcatd starts.  

    Arguments:
       p_nodes -- a pointer to an arrays of nodes to be monitored. null means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only. 
                2 means both monservers and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
      (return code, message) 
      if the callback is set, use callback to display the status and error. 
     
=cut
#--------------------------------------------------------------------------------
sub start {
  print "xcatmon.start\n";

  return (0, "started");
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
  print "xcatmon.stop\n";
  
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
    This function is called by the monitorctrl module when monstart gets called and
    when xcatd starts. It starts monitoring the node status and feed them back
    to xCAT.  
    Arguments:
       p_nodes -- a pointer to an arrays of nodes to be monitored. null means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only.  
                2 means both monservers and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    note: p_nodes and scope are ignored by this plugin.
    Returns:
      (return code, message) 
      if the callback is set, use callback to display the status and error. 
=cut
#--------------------------------------------------------------------------------
sub startNodeStatusMon
{
  print "xcatmon.startNodeStatusMon\n";
  if (! -e "/etc/xCATMN") { return (0, ""); } #only run the cron job on mn

  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::xcatmon/) {
    $noderef=shift;
  }
  my $scope=shift;
  my $callback=shift;

  #run the command first to update the status, 
  #my $cmd="$::XCATROOT/sbin/xcatnodemon";
  my $cmd="$::XCATROOT/bin/nodestat all -m -u -q";
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
  my $reading;
  if (exists($settings{'ping-interval'})) { 
    $reading=$settings{'ping-interval'};
    if ($reading>0) { $value=$reading;}
  }
   
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
  my $localhostname=hostname(); 
  if ($code==0) { 
    if ($callback) {
      my $rsp={};
      $rsp->{data}->[0]="$localhostname: started. Refresh interval is $value minute(s).";
      $callback->($rsp);
    }
    return (0, "started"); }
  else {
    if ($callback) {
      my $rsp={};
      $rsp->{data}->[0]="$localhostname: $code  $msg";
      $callback->($rsp);
    }
    return ($code, $msg); 
  } 
}


#--------------------------------------------------------------------------------
=head3   stopNodeStatusMon
    This function is called by the monitorctrl module when monstop command is issued.
    It stops feeding the node status info back to xCAT. 
    Arguments:
       p_nodes -- a pointer to an arrays of nodes to stoped for monitoring. null means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only. 
                2 means both monservers and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    note: p_nodes and scope are ignored by this plugin.
    Returns:
      (return code, message) 
      if the callback is set, use callback to display the status and error. 
=cut
#--------------------------------------------------------------------------------
sub stopNodeStatusMon {
  print "xcatmon.stopNodeStatusMon\n";
  if (! -e "/etc/xCATMN") { return (0, ""); } #only run the cron job on mn

  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::xcatmon/) {
    $noderef=shift;
  }
  my $scope=shift;
  my $callback=shift;
  
  #my $job="$::XCATROOT/sbin/xcatnodemon";
  my $job="$::XCATROOT/bin/nodestat all -m -u -q";
  my ($code, $msg)=xCAT::Utils::remove_cron_job($job);
  my $localhostname=hostname(); 
  if ($code==0) { 
    if ($callback) {
      my $rsp={};
      $rsp->{data}->[0]="$localhostname: stopped.";
      $callback->($rsp);
    }
    return (0, "stopped"); }
  else {
    if ($callback) {
      my $rsp={};
      $rsp->{data}->[0]="$localhostname: $code  $msg";
      $callback->($rsp);
    }
    return ($code, $msg); 
  } 
}


#--------------------------------------------------------------------------------
=head3    config
      This function configures the cluster for the given nodes.  
      This function is called by when monconfig command is issued or when xcatd starts
     on the service node. It will configure the cluster to include the given nodes within
     the monitoring doamin. 
    Arguments:
       p_nodes -- a pointer to an arrays of nodes to be added for monitoring. none means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only. 
                2 means both monservers and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
       (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub config {

  print "xcatmon:config called\n";
 
  return (0, "ok");
}

#--------------------------------------------------------------------------------
=head3    deconfig
      This function de-configures the cluster for the given nodes.  
      This function is called by the monitorctrl module when nodes are removed 
      from the xCAT cluster. It should remove the nodes from the product for monitoring.
    Arguments:
       p_nodes -- a pointer to an arrays of nodes to be removed for monitoring. none means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only. 
                2 means both monservers and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
       (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub deconfig {

  print "xcatmon:deconfig called\n";

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
          {alive=>[node1, node3,...], unreachable=>[node4, node2...], unknown=>[node8, node101...]}
=cut
#--------------------------------------------------------------------------------
sub getMonNodesStatus {
  my %status=();
  my @inactive_nodes=();
  my @active_nodes=();
  my @unknown_nodes=();

  my $hierachy=xCAT_monitoring::monitorctrl->getMonHierarchy();
  if (ref($hierachy) eq 'ARRAY') {
      xCAT::MsgUtils->message('S', "[mon]: " . $hierachy->[1]);
      return %status;	
  }
 
  my @mon_servers=keys(%$hierachy); 
  my $isSV=xCAT::Utils->isServiceNode(); 
  
  #on a service node or on ms, get the nodes that has local host as the server node
  my @hostinfo=xCAT::Utils->determinehostname();
  my %iphash=();
  foreach(@hostinfo) {$iphash{$_}=1;}
  #if this is mn, include the ones that has no service nodes
  if (!$isSV) { $iphash{'noservicenode'}=1;}
  
  my %processed=();
  foreach(@mon_servers) {
    #service node come in pairs, the first one is the monserver adapter that facing the mn,
    # the second one is facing the cn. we use the first one here
    my @server_pair=split(':', $_); 
    my $sv=$server_pair[0];
    if (!$processed{$sv}) { $processed{$sv}=1;}
    else {  next; }

    if ($iphash{$sv}) {
      my $monnodes=$hierachy->{$_};
        
      foreach(@$monnodes) {
	  my $node=$_->[0];
	  my $status=$_->[2];
	  my $type=$_[1];
	  if (!$status) { $status=$::STATUS_DEFINED;} #default
	  
	  if ($status eq $::STATUS_ACTIVE) { push(@active_nodes, $node);}
	  elsif ($status eq $::STATUS_INACTIVE) { push(@inactive_nodes, $node);}
	  else {
	      my $need_active=0;
	      my $need_inactive=0;
	      if ($::NEXT_NODESTAT_VAL{$status}->{$::STATUS_ACTIVE}==1) { $need_active=1;}
	      if ($::NEXT_NODESTAT_VAL{$status}->{$::STATUS_INACTIVE}==1) { $need_inactive=1;}
	      if (($need_active==1) && ($need_inactive==0)) { push(@inactive_nodes, $node); } #put it into the inactive list so that the monitoring code can switch it to active.
	      elsif (($need_active==0) && ($need_inactive==1)) { push(@active_nodes, $node); } #put it into the active list so that the monitoring code can chane it to inactive.
	      elsif  (($need_active==1) && ($need_inactive==1)) { push(@unknown_nodes, $node);} #unknow list so that the monitoring code can change it to active or inactive
	      else {
		  #if it is non-osi node, check it anyway
		  if ($type !~ /osi/) {push(@unknown_nodes, $node);}
	      }
	  }
      }
    }
  }
 
  $status{$::STATUS_ACTIVE}=\@active_nodes;
  $status{$::STATUS_INACTIVE}=\@inactive_nodes;
  $status{unknown}=\@unknown_nodes;

  return %status;
}




#--------------------------------------------------------------------------------
=head3    setNodeStatusAttributes
      This function will update the status column of the nodelist table with the new node status.
    Arguments:
       status -- a hash pointer of the node status. A key is a status string. The value is 
                an array pointer of nodes that have the same status.
                for example: {alive=>["node1", "node1"], unreachable=>["node5","node100"]}
       force -- 1 force the input values to be set.
             -- 0 make sure if the input value is the next valid value.
    Returns:
        0 for successful.
        non-0 for not successful.
=cut
#--------------------------------------------------------------------------------
sub setNodeStatusAttributes {
  my $temp=shift;
  if ($temp =~ /xCAT_monitoring::xcatmon/) {
    $temp=shift;
  }
  my $force=shift;
  
  return xCAT_monitoring::monitorctrl->setNodeStatusAttributes($temp, $force);
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
  xCAT_monitoring::xcatmon->stopNodeStatusMon([], 0);
  xCAT_monitoring::xcatmon->startNodeStatusMon([], 0);  
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
    xcatmon provides node status monitoring using fping on AIX and nmap on Linux. 
    It also provides application status monitoring. The status and the appstatus 
    columns of the nodelist table will be  updated periodically  with the latest 
    status values for the nodes.   Use  command 'monadd xcatmon -n' and then 
    'monstart xcatmon'  to start monitoring. 
  Settings:
    ping-interval:  the number of minutes between each fping operation. 
        The default value is 3.
    apps: a list of comma separated application names whose status will be queried. 
        For how to get the status of each app, look for app name in the key filed 
        in a different row.
    port: the application daemon port number, if not specified, use internal list, 
        then /etc/services.
    group:  the name of a node group that needs to get the application status from.
         If not specified, assume all the nodes in the nodelist table. 
         To specify more than one groups, use group=a,group=b format.
    cmd: the command that will be run locally on mn or sn.
    lcmd: the command that will be run locally on the mn only.
    dcmd: the command that will be run distributed on the nodes using xdsh.

       For commands specified by 'cmd' and 'lcmd', the input of is a list of comma 
       separated node names, the output must be in the following format:
         node1:string1
         node2:string2
         ...
       For the command specified by 'dcmd', no input is needed, the output can be a 
       string.";

}
