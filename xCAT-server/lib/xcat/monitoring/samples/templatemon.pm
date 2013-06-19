#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_monitoring::templatemon;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use xCAT_monitoring::monitorctrl;
use xCAT::Utils;

1;
#-------------------------------------------------------------------------------
=head1  xCAT_monitoring:templatemon  
=head2    Package Description
   This is a xCAT monitoring plugin template. 
   To use it, copy it to /opt/xcat/lib/perl/xCAT_monitoring/ directory. 
   Note: 
     There are two ways to configure a node for monitoring. The preferred way is to  
     return the postscripts in the getPostScripts() function  and have the node 
     deployment/install process to call them locally on the nodes. 
     The other way is to run command 'moncfg templatemon -r'
     after the nodes are up and running. For the latter case, you need to, in the
     config() function, push the scripts down to the node and use xdsh to run it.
     We recommend you implement both to give user some freedom. 

   The following are the ways of configure and start monitoring:
   1. The preferred way:
      (define nodes in the xCAT db)
      monadd templatemon [-n]
      moncfg templatemon servicenode 
      (nodeset servicenode netboot)
      (rpower servicenodde on)
      moncfg templatemon conputenode 
      (nodeset conputenode netboot)
      (rpower conputenode on)
      monstart templatemon
   2. The other way: if the nodes has already up and running:
      monadd templatemon [-n]
      moncfg templatemon -r
      monstart templatemon -r
   3. To add more nodes for monitoring later without stoping monitoring:
      moncfg templatemon nodes -r

   Use monstop templatemon [noderange] [-r] to stop monitoring.
   Use mondecfg templatemon [noderange] [-r] to clean up.
   Use monrm templatemon [noderange] [-r] to remove it from the monitoring table. 

=cut
#-------------------------------------------------------------------------------

#--------------------------------------------------------------------------------
=head3    start
      This function gets called by the monitorctrl module
      when xcatd starts and when monstart command is issued by the user.
      It should start daemons and do the necessary start-up process 
      for the third party monitoring software. If the sope is 0, the operations 
      shoul only be applied on the local host. If it is 2, then it should be applied
      to the children that the local host is monitoring.
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
  print "templatemon::start called\n";
  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::templatemon/) {
    $noderef=shift;
  }
  my $scope=shift;  #2 when -r flag is specified for monstart command, otherwise 0. 
  my $callback=shift; #null when it is called by 'service xcatd start' command.
 

  #TODO: start up the monitoring on the local host

  #demo how to do output
  my $result="I am ok";
  if ($callback) { #this is the case when monstart is called, 
                   # the $result will be diplayed to STDIN
    my $rsp={};
    $rsp->{data}->[0]="$result";
    $callback->($rsp);
  } else {  #if this function is invoked by xcatd when xcatd starts, $callback is null
            #we have to store the result into syslog
    xCAT::MsgUtils->message('S', "[mon]: $result\n"); 
  } 

  if ($scope) {
    #demo how to get the children
    my @hostinfo=xCAT::NetworkUtils->determinehostname();
    my $isSV=xCAT::Utils->isServiceNode();
    my %iphash=();
    foreach(@hostinfo) {$iphash{$_}=1;}
    if (!$isSV) { $iphash{'noservicenode'}=1;}
    my $pPairHash=xCAT_monitoring::monitorctrl->getMonServer($noderef);
    if (ref($pPairHash) eq 'ARRAY') {
	if ($callback) {
	    my $resp={};
	    $resp->{data}->[0]=$pPairHash->[1];
	    $callback->($resp);
	} else {
	    xCAT::MsgUtils->message('S', "[mon]: " . $pPairHash->[1]);
	}
	return (1, "");	
    }

    foreach my $key (keys(%$pPairHash)) {
      my @key_a=split(':', $key);
      if (! $iphash{$key_a[0]}) {  next; }
      my $mon_nodes=$pPairHash->{$key};

      foreach(@$mon_nodes) {
        my $node_info=$_;
        print "    node=$node_info->[0], nodetype=$node_info->[1], status=$node_info->[2]\n";
        #TODO: use xdsh command to reach to the child to perform startup process.
      }
    }
  }
 
  return (0, "started");
}



#--------------------------------------------------------------------------------
=head3    stop
      This function gets called when monstop command is issued by the user.
      It should stop the daemons and do the necessary backup process 
      for the third party monitoring software. If the sope is 0, the operations 
      shoul only be applied on the local host. If it is 2, then it should be applied
      to the children that the local host is monitoring.
    Arguments:
       p_nodes -- a pointer to an arrays of nodes to be stoped. null means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only. 
                2 means both localhost and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
      (return code, message) 
      if the callback is set, use callback to display the status and error. 
=cut
#--------------------------------------------------------------------------------
sub stop {
  print "templatemon::stop called\n";
  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::templatemon/) {
    $noderef=shift;
  }
  my $scope=shift;
  my $callback=shift;
 

  #TODO: stop the monitoring on the local host


  if ($scope) {
    #demo how to get the children
    my @hostinfo=xCAT::NetworkUtils->determinehostname();
    my $isSV=xCAT::Utils->isServiceNode();
    my %iphash=();
    foreach(@hostinfo) {$iphash{$_}=1;}
    if (!$isSV) { $iphash{'noservicenode'}=1;}
    my $pPairHash=xCAT_monitoring::monitorctrl->getMonServer($noderef);
    if (ref($pPairHash) eq 'ARRAY') {
	if ($callback) {
	    my $resp={};
	    $resp->{data}->[0]=$pPairHash->[1];
	    $callback->($resp);
	} else {
	    xCAT::MsgUtils->message('S', "[mon]: " . $pPairHash->[1]);
	}
	return (1, "");	
    }

    foreach my $key (keys(%$pPairHash)) {
      my @key_a=split(':', $key); 
      if (! $iphash{$key_a[0]}) {  next; }
      my $mon_nodes=$pPairHash->{$key};

      foreach(@$mon_nodes) {
        my $node_info=$_;
        print "    node=$node_info->[0], nodetype=$node_info->[1], status=$node_info->[2]\n";
        #TODO: use xdsh command to reach to the child to perform the stop process.
      }
    }
  }
 
  
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
    This function is called by the monitorctrl module when monstart gets called and
    when xcatd starts. It starts monitoring the node status and feed them back
    to xCAT.  
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
sub startNodeStatusMon {
  print "templatemon::startNodeStatusMon called\n";
  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::templatemon/) {
    $noderef=shift;
  }
  my $scope=shift;
  my $callback=shift;
 
  #TODO: turn on the node status monitoring. use nodech command to feed the new status

  return (0, "");
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
  print "templatemon::stopNodeStatusMon called\n";
  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::templatemon/) {
    $noderef=shift;
  }
  my $scope=shift;
  my $callback=shift;
  #TODO: turn off the node status monitoring. 
  return (0, "");
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
  print "templatemon::config called\n";
  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::templatemon/) {
    $noderef=shift;
  }
  my $scope=shift;
  my $callback=shift;


  return (0, "");
}

#--------------------------------------------------------------------------------
=head3    deconfig
      This function is called by when mondeconfig command is issued.
      It will deconfigure the cluster to remove the given nodes from the monitoring doamin. 
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
  print "templatemon::deconfig called\n";
  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::templatemon/) {
    $noderef=shift;
  }
  my $scope=shift;
  my $callback=shift;

  return (0, "");
}


#--------------------------------------------------------------------------------
=head3    processSettingChanges
      This optional function gets called when the setting for this monitoring plugin 
      has been changed in the monsetting table.
    Arguments:
       none.
    Returns:
        0 for successful.
        non-0 for not successful.
=cut
#--------------------------------------------------------------------------------
sub processSettingChanges {
  #get latest settings for this plugin and do something about it
  my %settings=xCAT_monitoring::monitorctrl->getPluginSettings("templatemon");
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
    templatemon description goes here. 
  Settings:
    key:  explaination. default value etc.\n";
}


#--------------------------------------------------------------------------------
=head3    getNodesMonServers
      When monitoring commands get called, the default process is to dispatch the command
    to all the monserves of the given nodes. The monserver for a node is defined
    in noderes.monserver in the database. The monserver in the db is a comma separated
    pairs. The first one the monitoring server name/ip seen by the mn, the second one is 
    the same sever name/ip seen by the node. If it is not defined, noderes.servicenode and
    noderes.xcatmaster pairs are used. If not defined neither, the 'noservicenode' and 
    site.master pairs are used.
      This optional function overrides the default behavior.
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
      It returns a pointer to an array if there is an error. Format is [code, message].
=cut
#--------------------------------------------------------------------------------
sub getNodesMonServers
{
  print "templatemon.getNodesMonServer called\n";
  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::templatemon/) {
    $noderef=shift;
  }
  my $callback=shift;
}


#--------------------------------------------------------------------------------
=head3    getPostscripts
      This optional function returns the postscripts needed for configuring the the nodes
      for monitoring.  The postscripts get downloaded from mn to the nodes and
      called when the nodes are deployed/installed.
      Please put the postscripts to /install/postscripts directory. 
     Arguments:
        none
    Returns:
     The postscripts. It a pointer to an array with the node group names as the keys
    and the comma separated poscript names as the value. For example:
    {service=>"cmd1,cmd2", xcatdefaults=>"cmd3,cmd4"} where xcatdefults is a group
    of all nodes including the service nodes.
=cut
#--------------------------------------------------------------------------------
sub getPostscripts {
  #Sample
  my $ret={};
  $ret->{xcatdefaults}="cmd1";
  return $ret;
}


#--------------------------------------------------------------------------------
=head3    getNodeConfData
     This optional function gets called during the node deployment process before
     the postscripts are invoked. It gets a list of environmental variables for 
     the postscripts.  
    Arguments:
        pointet to a arry of nodes being deployed.
    Returns:
        ret: pointer to a 2-level hash like this:
        {
           'node1'=>{'env1'=>'value1',
                     'env2'=>'value2'},
           'node2'=>{'env1'=>'value3',
                     'env2'=>'value4'}
        }
                
=cut
#--------------------------------------------------------------------------------
sub getNodeConfData {
    my $noderef=shift;
    if ($noderef =~ /xCAT_monitoring::templatemon/) {
	$noderef=shift;
    }
    
    #sample
    my $ref_ret;
    foreach my $node (@$noderef) {  
	$ref_ret->{$node}->{MY_ENV1}="abcde";
	$ref_ret->{$node}->{MY_ENV2}="abcde2";
    }
    return $ref_ret;
}
