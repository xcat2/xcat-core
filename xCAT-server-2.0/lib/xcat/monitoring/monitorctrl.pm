#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_monitoring::monitorctrl;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use Sys::Hostname;
use xCAT::NodeRange;
use xCAT::Table;
use xCAT::MsgUtils;
use xCAT::Utils;
use xCAT::Client;
use xCAT_plugin::notification;
use xCAT_monitoring::montbhandler;

#the list store the names of the monitoring plug-in and the file name and module names.
#the names are stored in the "name" column of the monitoring table. 
#the format is: (name=>[filename, modulename], ...)
%PRODUCT_LIST;

#stores the module name and the method that is used for the node status monitoring
#for xCAT.
$NODESTAT_MON_NAME; 
$masterpid;

1;

#-------------------------------------------------------------------------------
=head1  xCAT_monitoring:monitorctrl
=head2    Package Description
  xCAT monitoring control  module. This module is the center for the xCAT
  monitoring support. It interacts with xctad and the monitoring plug-in modules
  for the 3rd party monitoring products. 
=cut
#-------------------------------------------------------------------------------




#--------------------------------------------------------------------------------
=head3    start
      It is called by the xcatd when xcatd gets started.
      It gets a list of monitoring plugin module names from the "monitoring" 
      table. It gets a list of nodes in the xcat cluster and,
      in tern, calls the start() function of all the monitoring
      plug-in modules. It registers for nodelist
      tble changes. It queries each monitoring plug-in modules
      to see whether they can feed node status info to xcat or not.
      If some of them can, this function will set up the necessary
      timers (for pull mode) or callback mechanism (for callback mode)
      in order to get the node status from them.
    Arguments:
        none
    Returns:
        0 for successful.
        non-0 for not successful.
=cut
#--------------------------------------------------------------------------------
sub start {
  #print "\nmonitorctrl::start called\n";
  $masterpid=shift;
  if ($masterpid =~ /xCAT_monitoring::monitorctrl/) {
    $masterpid=shift;
  }
  
  #print "masterpid=$masterpid\n";
  # get the plug-in list from the monitoring table
  refreshProductList();

  #setup signal 
  $SIG{USR2}=\&handleMonSignal;

  xCAT_monitoring::montbhandler->regMonitoringNotif();


  #start monitoring for all the registered plug-ins in the monitoring table.
  #better span a process so that it will not block the xcatd.
  my $pid;
  if ($pid=xCAT::Utils->xfork()) {#parent process 
    #print "parent done\n";
    return 0;
  }
  elsif (defined($pid)) { #child process
    my %ret = startMonitoring(());
    if ($NODESTAT_MON_NAME) {
      my @ret2 = startNodeStatusMonitoring($NODESTAT_MON_NAME);
      $ret{"Node status monitoring with $NODESTAT_MON_NAME"}=\@ret2;
    }
    # TODO: somehow, we should log the return status here
    if (%ret) {
      foreach(keys(%ret)) {
        my $retstat=$ret{$_}; 
        print "$_: @$retstat\n";
      }
    }
    
    if (keys(%PRODUCT_LIST) > 0) {
      regNodelistNotif();
    }
    else {
      unregNodelistNotif();
    }

    #print "child done\n";
    exit 0;
  }
}


#--------------------------------------------------------------------------------
=head3    regNodelistNotif
      It registers this module in the notification table to watch for changes in 
      the nodelist table.
    Arguments:
        none
    Returns:
        0 for successful.
        non-0 for not successful.
=cut
#--------------------------------------------------------------------------------
sub regNodelistNotif {

  #register for nodelist table changes if not already registered
  my $tab = xCAT::Table->new('notification');
  my $regged=0;
  if ($tab) {
    (my $ref) = $tab->getAttribs({filename => qw(monitorctrl.pm)}, tables);
    if ($ref and $ref->{tables}) {
       $regged=1;
    }
    $tab->close();
  }

  if (!$regged) {
    xCAT_plugin::notification::regNotification([qw(monitorctrl.pm nodelist -o a,d)]);
  }
}

#--------------------------------------------------------------------------------
=head3    unregNodelistNotif
      It un-registers this module in the notification table.
    Arguments:
        none
    Returns:
        0 for successful.
        non-0 for not successful.
=cut
#--------------------------------------------------------------------------------
sub unregNodelistNotif {
  my $tab = xCAT::Table->new('notification');
  my $regged=0;
  if ($tab) {
    (my $ref) = $tab->getAttribs({filename => qw(monitorctrl.pm)}, tables);
    if ($ref and $ref->{tables}) {
       $regged=1;
    }
    $tab->close();
  }

  if ($regged) {
    xCAT_plugin::notification::unregNotification([qw(monitorctrl.pm)]);
  }
}

#-------------------------------------------------------------------------------

=head3  handleSignal
      It is called the signal is received. It then update the cache with the
      latest data in the monitoring table and start/stop the plug-ins for monitoring
      accordingly.
    Arguments:
      none.
    Returns:
      none
=cut
#-------------------------------------------------------------------------------
sub handleMonSignal {
  #print "handleMonSignal called masterpid=$masterpid\n";
  #save the old cache values
  my @old_products=keys(%PRODUCT_LIST);
  my $old_nodestatmon=$NODESTAT_MON_NAME;
  
  #print "old_products=@old_products.\n";
  #print "old_nodestatmon=$old_nodestatmon.\n";
  #get new cache values, it also loads the newly added modules
  refreshProductList();

  #my @new_products=keys(%PRODUCT_LIST);
  #my $new_nodestatmon=$NODESTAT_MON_NAME;
  #print "new_products=@new_products.\n";
  #print "new_nodestatmon=$new_nodestatmon.\n";


  #check what have changed 
  my %summary;
  foreach (@old_products) { $summary{$_}=-1;}
  foreach (keys %PRODUCT_LIST) { $summary{$_}++;}

  #start/stop plug-ins accordingly
  my %ret=();
  foreach (keys %summary) {
    if ($summary{$_}==-1) { #plug-in deleted
	#print "got here stop $_.\n";
      %ret=stopMonitoring(($_));
    } elsif ($summary{$_}==1) { #plug-in added
      #print "got here start $_.\n";
      my %ret1=startMonitoring(($_));
      %ret=(%ret, %ret1);
    }
  }

  #handle node status monitoring changes
  if ($old_nodestatmon ne $NODESTAT_MON_NAME) {
    if ($old_nodestatmon) {
      my @ret3=stopNodeStatusMonitoring($old_nodestatmon);
      $ret{"Stop node status monitoring with $old_nodestatmon"}=\@ret3;
    }
    if ($NODESTAT_MON_NAME) {
      my @ret4=startNodeStatusMonitoring($NODESTAT_MON_NAME);
      $ret{"Start node status monitoring with $NODESTAT_MON_NAME"}=\@ret4;
    }
  }

  #registers or unregusters this module in the notification table for changes in
  # the nodelist and monitoring tables. 
  if (keys(%PRODUCT_LIST) > 0) {
    regNodelistNotif();
  } 
  else {
    unregNodelistNotif();
  }


  #setup the signal again  
  $SIG{USR2}=\&handleMonSignal;

  #TODO: log status
  foreach(keys(%ret)) {
    my $retstat=$ret{$_}; 
    print "$_: @$retstat\n";
  }
}


#-------------------------------------------------------------------------------

=head3  sendMonSignal
      It is called by any module that has made changes to the monitoring table.
    Arguments:
      none.
    Returns:
      none
=cut
#-------------------------------------------------------------------------------
sub sendMonSignal {
  #print "sendMonSignal masterpid=$masterpid\n";
  if ($masterpid) {
    kill('USR2', $masterpid);
  } else {
    sub handle_response {return;}
    my $cmdref;
    $cmdref->{command}->[0]="updatemon";
    xCAT::Client::submit_request($cmdref,\&handle_response);
  }
}



#--------------------------------------------------------------------------------
=head3    stop
      It is called by the xcatd when xcatd stops. It 
      in tern calls the stop() function of each monitoring
      plug-in modules, stops all the timers for pulling the
      node status and unregisters for the nodelist  
      tables changes. 
    Arguments:
        none
    Returns:
        0 for successful.
        non-0 for not successful.
=cut
#--------------------------------------------------------------------------------
sub stop {
  #print "\nmonitorctrl::stop called\n";

  %ret=stopMonitoring(());
  if ($NODESTAT_MON_NAME) {
    my @ret2 = stopNodeStatusMonitoring($NODESTAT_MON_NAME);
    $ret{"Stop node status monitoring with $NODESTAT_MON_NAME"}=\@ret2;
  }

  xCAT_monitoring::montbhandler->unregMonitoringNotif();
  unregNodelistNotif();

  if (%ret) {
    foreach(keys(%ret)) {
      $retstat=$ret{$_};
      print "$_: @$retstat\n";
    }
  }

  return 0;
}

#--------------------------------------------------------------------------------
=head3    startMonitoring
      It takes a list of monitoring plug-in names as an input and start
      the monitoring process for them.
    Arguments:
       names -- an array of monitoring plug-in module names to be started. If non is specified, 
         all the plug-in modules registered in the monitoring table will be used.  
    Returns:
        A hash table keyed by the plug-in names. The value is an array pointer 
        pointer to a return code and  message pair. For example:
        {rmcmon=>[0, ""], gangliamin=>[1, "something is wrong"]}

=cut
#--------------------------------------------------------------------------------
sub startMonitoring {
  @product_names=@_;
  #print "\nmonitorctrl::startMonitoring called with @product_names\n";

  if (@product_names == 0) {
     @product_names=keys(%PRODUCT_LIST);    
  }

  my $monservers;
  if (@product_names > 0) {
    #get a list of monitoring servers and the nodes they are responsible for monitoring. 
    $monservers=getMonHierarchy();
    #foreach (keys(%$monservers)) {
    #  print "  monitoring server: $_\n";
    #  my $mon_nodes=$monservers->{$_};
    #  print "    nodes: @$mon_nodes\n";
    #}
  }

  my %ret=();
  foreach(@product_names) {
    my $aRef=$PRODUCT_LIST{$_};
    if ($aRef) {
      my $module_name=$aRef->[1];

      undef $SIG{CHLD};
      #initialize and start monitoring
      my @ret1 = ${$module_name."::"}{start}->($monservers);
      $ret{$_}=\@ret1;
    } else {
       $ret{$_}=[1, "Monitoring plug-in module $_ is not registered."];
    }
  }


  return %ret;
}


#--------------------------------------------------------------------------------
=head3    startNodeStatusMonitoring
      It starts the given plug-in for node status monitoring. 
      If no product is specified, use the one in the monitoring table.
    Arguments:
       name -- name of the mornitoring plug-in module to be started for node status monitoring.
        If none is specified, use the one in the monitoring table that has the
        "nodestatmon" column set to be "1", or "Yes".
    Returns:
        (return_code, error_message)

=cut
#--------------------------------------------------------------------------------
sub startNodeStatusMonitoring {
  my $pname=shift;
  if ($pname =~ /xCAT_monitoring::monitorctrl/) {
    $pname=shift;
  }

  if (!$pname) {$pname=$NODESTAT_MON_NAME;}

  if ($pname) {
    my $aRef=$PRODUCT_LIST{$pname};
    if ($aRef) {
      my $module_name=$aRef->[1];
      undef $SIG{CHLD};
      my $method = ${$module_name."::"}{supportNodeStatusMon}->();
      # return value 0 means not support. 1 means yes. 
      if ($method > 0) {
        #start nodes tatus monitoring
        my @ret2 = ${$module_name."::"}{startNodeStatusMon}->(getMonHierarchy()); 
        return @ret2;
      }         
      else {
	return (1, "$pname does not support node status monitoring.");
      }
    }
    else {
      return (1, "The monitoring plug-in module $pname is not registered.");
    }
  }
  else {
    return (0, "No plug-in is specified for node status monitoring.");
  }
}



#--------------------------------------------------------------------------------
=head3    stopMonitoring
      It takes a list of monitoring plug-in names as an input and stop
      the monitoring process for them.
    Arguments:
       names -- an array of monitoring plug-in names to be stopped. If non is specified,
         all the plug-ins registered in the monitoring table will be stopped.
    Returns:
        A hash table keyed by the plug-in names. The value is ann array pointer
        pointer to a return code and  message pair. For example:
        {rmcmon=>[0, ""], gangliamon=>[1, "something is wrong"]}

=cut
#--------------------------------------------------------------------------------
sub stopMonitoring {
  @product_names=@_;
  #print "\nmonitorctrl::stopMonitoring called with @product_names\n";

  if (@product_names == 0) {
     @product_names=keys(%PRODUCT_LIST);
  }

  my %ret=();

  #stop each plug-in from monitoring the xcat cluster
  my $count=0;
  foreach(@product_names) {
    my $aRef=$PRODUCT_LIST{$_};

    if ($aRef) {
      $module_name=$aRef->[1];
    }
    else {
      my $file_name="$::XCATROOT/lib/perl/xCAT_monitoring/$_.pm";
      $module_name="xCAT_monitoring::$_";
      #load the module in memory
      eval {require($file_name)};
      if ($@) {   
        my @ret3=(1, "The file $file_name cannot be located or has compiling errors.\n"); 
        $ret{$_}=\@ret3;
        next;
      }
      #else {
      #  my @a=($file_name, $module_name);
      #  $PRODUCT_LIST{$pname}=\@a;
      #}
    }      
    #stop monitoring
    my @ret2 = ${$module_name."::"}{stop}->();
    $ret{$_}=\@ret2;
  }

  return %ret;
}



#--------------------------------------------------------------------------------
=head3    stopNodeStatusMonitoring
      It stops the given plug-in for node status monitoring. 
      If no plug-in is specified, use the one in the monitoring table.
    Arguments:
       name -- name of the monitoring plu-in module to be stoped for node status monitoring.
        If none is specified, use the one in the monitoring table that has the
        "nodestatmon" column set to be "1", or "Yes".
    Returns:
        (return_code, error_message)

=cut
#--------------------------------------------------------------------------------
sub stopNodeStatusMonitoring {
  my $pname=shift;
  if ($pname =~ /xCAT_monitoring::monitorctrl/) {
    $pname=shift;
  }

  if (!$pname) {$pname=$NODESTAT_MON_NAME;}

  if ($pname) {
    my $module_name;
    if (exists($PRODUCT_LIST{$pname})) {
      my $aRef = $PRODUCT_LIST{$pname};
      $module_name=$aRef->[1];
    } else {
      my $file_name="$::XCATROOT/lib/perl/xCAT_monitoring/$pname.pm";
      $module_name="xCAT_monitoring::$pname";
      #load the module in memory
      eval {require($file_name)};
      if ($@) {   
        return (1, "The file $file_name cannot be located or has compiling errors.\n"); 
      }
      #else {
      #  my @a=($file_name, $module_name);
      #  $PRODUCT_LIST{$pname}=\@a;
      #}
    }
    
    my @ret2 = ${$module_name."::"}{stopNodeStatusMon}->(); 
    return @ret2;
  }
}



#--------------------------------------------------------------------------------
=head3    processTableChanges
      It is called by the NotifHander module
      when the nodelist or the monitoring tables get changed. If a
      node is added or removed from the nodelist table, this
      function will inform all the monitoring plug-in modules. If a plug-in
      is added or removed from the monitoring table. this function will start
      or stop the plug-in for monitoing the xCAT cluster.  
    Arguments:
      action - table action. It can be d for rows deleted, a for rows added
                    or u for rows updated.
      tablename - string. The name of the DB table whose data has been changed.
      old_data - an array reference of the old row data that has been changed.
           The first element is an array reference that contains the column names.
           The rest of the elelments are also array references each contains
           attribute values of a row.
           It is set when the action is u or d.
      new_data - a hash refernce of new row data; only changed values are present
           in the hash.  It is keyed by column names.
           It is set when the action is u or a.
    Returns:
        0 for successful.
        non-0 for not successful.
=cut
#--------------------------------------------------------------------------------
sub processTableChanges {
  my $action=shift;
  if ($action =~ /xCAT_monitoring::monitorctrl/) {
    $action=shift;
  }
  my $tablename=shift;
  my $old_data=shift;
  my $new_data=shift;

  processNodelistTableChanges($action, $tablename, $old_data, $new_data);

}

 
#--------------------------------------------------------------------------------
=head3    processNodelistTableChanges
      It is called when the nodelist table gets changed. 
      When node is added or removed from the nodelist table, this 
      function will inform all the monitoring plug-in modules.
    Arguments:
      See processTableChanges.  
    Returns:
        0 for successful.
        non-0 for not successful.
=cut
#--------------------------------------------------------------------------------
sub processNodelistTableChanges {
  my $action=shift;
  if ($action =~ /xCAT_monitoring::monitorctrl/) {
    $action=shift;
  }
  #print "monitorctrl::processNodelistTableChanges action=$action\n";

  if ($action eq "u") {   
    return 0;
  }

  if (!$masterpid) { refreshProductList();}
  if (keys(%PRODUCT_LIST) ==0) { return 0; }

  my $tablename=shift;
  my $old_data=shift;
  my $new_data=shift;
  
  #foreach (keys %$new_data) {
  #  print "new_data{$_}=$new_data->{$_}\n";
  #}

  #for (my $j=0; $j<@$old_data; ++$j) {
  #  my $tmp=$old_data->[$j];
  #  print "old_data[". $j . "]= @$tmp \n";
  #}

  my @nodenames=();
  if ($action eq "a") {
    if ($new_data) {
      my $nodetype='';
      my $status='';
      if (exists($new_data->{nodetype})) {$nodetype=$new_data->{nodetype};}
      if (exists($new_data->{status})) {$status=$new_data->{status};}      
      push(@nodenames, [$new_data->{node}, $nodetype, $status]);
      my $hierarchy=getMonServerWithInfo(\@nodenames);

      #call each plug-in to add the nodes into the monitoring domain
      foreach(keys(%PRODUCT_LIST)) {
        my $aRef=$PRODUCT_LIST{$_};
        my $module_name=$aRef->[1];
        #print "moduel_name=$module_name\n";
        ${$module_name."::"}{addNodes}->($hierarchy, 1);
      }
    }
  }
  elsif ($action eq "d") {
    #find out the index of "node" column
    if ($old_data->[0]) {
      $colnames=$old_data->[0];
      my $node_i=-1;
      my $nodetype_i=-1;
      my $status_i=-1;
      for ($i=0; $i<@$colnames; ++$i) {
        if ($colnames->[$i] eq "node") {
          $node_i=$i;
        } elsif ($colnames->[$i] eq "nodetype") {
          $nodetype_i=$i;
        }  elsif ($colnames->[$i] eq "status") {
          $status_i=$i;
        }  
      }
      
      for (my $j=1; $j<@$old_data; ++$j) {
        push(@nodenames, [$old_data->[$j]->[$node_i], $old_data->[$j]->[$nodetype_i], $old_data->[$j]->[$status_i]]);
      }

      if (@nodenames > 0) {
        #print "monitorctrl:  nodenames=@nodenames\n";
        my $hierarchy=getMonServerWithInfo(\@nodenames);        

        #call each plug-in to remove the nodes into the monitoring domain
        foreach(keys(%PRODUCT_LIST)) {
          my $aRef=$PRODUCT_LIST{$_};
          my $module_name=$aRef->[1];
          ${$module_name."::"}{removeNodes}->($hierarchy, 1); 
        }
      }
    }
  } 
  
  return 0;
} 


#--------------------------------------------------------------------------------
=head3    processMonitoringTableChanges
      It is called when the monitoring table gets changed.
      When a plug-in is added to or removed from the monitoring table, this
      function will start the plug-in to monitor the xCAT cluster or stop the plug-in
      from monitoring the xCAT cluster accordingly. 
    Arguments:
      See processTableChanges.
    Returns:
        0 for successful.
        non-0 for not successful.
=cut
#--------------------------------------------------------------------------------
sub processMonitoringTableChanges {

  #print "monitorctrl::procesMonitoringTableChanges \n";

  sendMonSignal();
  return 0;
}


#--------------------------------------------------------------------------------
=head3    processNodeStatusChanges
      This routine will be called by 
      monitoring plug-in modules to feed the node status back to xcat.
      (callback mode). This function will update the status column of the
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
  #print "monitorctrl::processNodeStatusChanges called\n";
  my $temp=shift;
  if ($temp =~ /xCAT_monitoring::monitorctrl/) {
    $temp=shift;
  }

  my %status_hash=%$temp;

  my $tab = xCAT::Table->new('nodelist',-create=>0,-autocommit=>1);
  my %updates;
  if ($tab) {
    foreach (keys %status_hash) {
      my $nodes=$status_hash{$_};
      if (@$nodes > 0) {
        $updates{'status'} = $_;
        my $where_clause="node in ('" . join("','", @$nodes) . "')";
        $tab->setAttribsWhere($where_clause, \%updates );
      }
    }
  } 
  else {
    xCAT::MsgUtils->message("E", "Could not read the nodelist table\n");
  }

  $tab->close;
  return 0;
}

#--------------------------------------------------------------------------------
=head3    getNodeStatus
      This function goes to the xCAT nodelist table to retrieve the saved node status.
    Arguments:
       none.
    Returns:
       a hash that has the node status. The format is: 
          {active=>[node1, node3,...], unreachable=>[node4, node2...], unknown=>[node8, node101...]}
=cut
#--------------------------------------------------------------------------------
sub getNodeStatus {
  %status=();
  my @inactive_nodes=();
  my @active_nodes=();
  my @unknown_nodes=();
  my $table=xCAT::Table->new("nodelist", -create =>0);
  if ($table) {
    my @tmp1=$table->getAllAttribs(('node','status'));
    if (defined(@tmp1) && (@tmp1 > 0)) {
      foreach(@tmp1) {
        my $node=$_->{node};
        my $status=$_->{status};
        if ($status eq $::STATUS_ACTIVE) { push(@active_nodes, $node);}
        elsif ($status eq $::STATUS_INACTIVE) { push(@inactive_nodes, $node);}
        else { push(@unknown_nodes, $node);}
      }
    }
  }

  $status{$::STATUS_ACTIVE}=\@active_nodes;
  $status{$::STATUS_INACTIVE}=\@inactive_nodes;
  $status{unknown}=\@unknown_nodes;
  return %status;
}



#--------------------------------------------------------------------------------
=head3    refreshProductList
      This function goes to the monitoring table to get the plug-in names 
      and stores the value into the PRODUCT_LIST cache. The cache also stores
      the monitoring plugin module name and file name for each plug-in. This function
      also load the modules in. 
 
    Arguments:
        none
    Returns:
        0 for successful.
        non-0 for not successful.
=cut
#--------------------------------------------------------------------------------
sub refreshProductList {
  #print "monitorctrl::refreshProductList called\n";
  #flush the cache
  %PRODUCT_LIST=();
  $NODESTAT_MON_NAME="";

  #get the monitoring plug-in list from the monitoring table
  my $table=xCAT::Table->new("monitoring", -create =>1);
  if ($table) {
    my @tmp1=$table->getAllAttribs(('name','nodestatmon'));
    if (defined(@tmp1) && (@tmp1 > 0)) {
      foreach(@tmp1) {
        my $pname=$_->{name};

        #get the node status monitoring plug-in name
        my $nodestatmon=$_->{nodestatmon};
        if ((!$NODESTAT_MON_NAME) && ($nodestatmon =~ /1|Yes|yes|YES|Y|y/)) {
           $NODESTAT_MON_NAME=$pname;
        }

        #find out the monitoring plugin file and module name for the product
        $file_name="$::XCATROOT/lib/perl/xCAT_monitoring/$pname.pm";
        $module_name="xCAT_monitoring::$pname";
        #load the module in memory
        eval {require($file_name)};
        if ($@) {   
          print "The file $file_name cannot be located or has compiling errors.\n"; 
        }
        else {
          my @a=($file_name, $module_name);
          $PRODUCT_LIST{$pname}=\@a;
        }
      } 
    }
  }

  #print "Monitoring PRODUCT_LIST:\n";
  foreach (keys(%PRODUCT_LIST)) {
    my $aRef=$PRODUCT_LIST{$_};
    #print "  $_:@$aRef\n"; 
  }
  #print "NODESTAT_MON_NAME=$NODESTAT_MON_NAME\n";
  return 0;
}



#--------------------------------------------------------------------------------
=head3    getMonHierarchy
      It gets the monnitoring server node for all the nodes within nodelist table.
      The "monserver" attribute is used from the noderes table. If "monserver" is not defined
      for a node, "servicenode" is used. If none is defined, use the local host.
    Arguments:
      None.
    Returns:
      A hash reference keyed by the monitoring server nodes and each value is a ref to
      an array of [nodes, nodetype, status] arrays  monitored by the server. So the format is:
      {monserver1=>[['node1', 'osi', 'active'], ['node2', 'switch', 'booting']...], ...}     
=cut
#--------------------------------------------------------------------------------
sub getMonHierarchy {
  my $ret={};
  
  #get all from nodelist table and noderes table
  my $table=xCAT::Table->new("nodelist", -create =>0);
  my @tmp1=$table->getAllAttribs(('node','nodetype', 'status'));

  my $table2=xCAT::Table->new("noderes", -create =>0);  
  
  #get monserver for each node. use "monserver" attribute from noderes table, if not
  #defined, use "servicenode". otherwise, use loca lhost. 
  my $host=hostname();
  if (defined(@tmp1) && (@tmp1 > 0)) {
    foreach(@tmp1) {
      my $node=$_->{node};
      my $status=$_->{status};
      my $nodetype=$_->{nodetype};
      my $monserver=$host;
      my $tmp2=$table2->getNodeAttribs($node, ['monserver', 'servicenode']);
      if (defined($tmp2) && ($tmp2)) {
	if ($tmp2->{monserver}) {  $monserver=$tmp2->{monserver}; }
        elsif ($tmp2->{servicenode})  {  $monserver=$tmp2->{servicenode}; }
      }

      if (exists($ret->{$monserver})) {
        my $pa=$ret->{$monserver};
        push(@$pa, [$node, $nodetype, $status]);
      }
      else {
        $ret->{$monserver}=[[$node, $nodetype, $status]];
      }
    }
  }
  $table->close();
  $table2->close();
  return $ret;
}

#--------------------------------------------------------------------------------
=head3    getMonServerWithInfo
      It gets the monnitoring server node for each of the nodes from the input. 
      The "monserver" attribute is used from the noderes table. If "monserver" is not defined
      for a node, "servicenode" is used. If none is defined, use the local host as the
      the monitoring server. The difference of this function from the getMonServer function
      is that the input of the nodes have 'node', 'nodetype' and 'status' info. 
      The other one just has  'node'. The
      names. 
    Arguments:
      nodes: An array ref. Each element is of the format: [node, nodetype, status]
    Returns:
      A hash reference keyed by the monitoring server nodes and each value is a ref to
      an array of [nodes, nodetype, status] arrays  monitored by the server. So the format is:
      {monserver1=>[['node1', 'osi', 'active'], ['node2', 'switch', 'booting']...], ...}
=cut
#--------------------------------------------------------------------------------
sub getMonServerWithInfo {
  my $p_input=shift;
  my @in_nodes=@$p_input;

  my $ret={};

  #print "getMonServerWithInfo called with @in_nodes\n";
  #get all from the noderes table
  my $table2=xCAT::Table->new("noderes", -create =>0);
  my $host=hostname();
  
  foreach (@in_nodes) {
    my $node=$_->[0];
    my $nodetype=$_->[1];
    my $status=$_->[2];

    my $monserver=$host;
    my $tmp2=$table2->getNodeAttribs($node, ['monserver', 'servicenode']);
    if (defined($tmp2) && ($tmp2)) {
      if ($tmp2->{monserver}) {  $monserver=$tmp2->{monserver}; }
      elsif ($tmp2->{servicenode})  {  $monserver=$tmp2->{servicenode}; }
    }


    if (exists($ret->{$monserver})) {
      my $pa=$ret->{$monserver};
      push(@$pa, [$node, $nodetype]);
    }
    else {
      $ret->{$monserver}=[[$node, $nodetype]];
    }
  }    
  
  $table2->close();
  return $ret;
}


#--------------------------------------------------------------------------------
=head3    getMonServer
      It gets the monnitoring server node for each of the nodes from the input.
      The "monserver" attribute is used from the noderes table. If "monserver" is not defined
      for a node, "servicenode" is used. If none is defined, use the local host as the
      the monitoring server.
    Arguments:
      nodes: An array ref of nodes.
    Returns:
      A hash reference keyed by the monitoring server nodes and each value is a ref to
      an array of [nodes, nodetype, status] arrays  monitored by the server. So the format is:
      {monserver1=>[['node1', 'osi', active'], ['node2', 'switch', booting']...], ...}
=cut
#--------------------------------------------------------------------------------
sub getMonServer {
  my $p_input=shift;
  my @in_nodes=@$p_input;

  my $ret={};
  #get all from nodelist table and noderes table
  my $table=xCAT::Table->new("nodelist", -create =>0);
  my $table2=xCAT::Table->new("noderes", -create =>0);
  my $host=hostname();
  
  foreach (@in_nodes) {
    my @tmp1=$table->getAttribs({'node'=>$_}, ('node', 'nodetype', 'status'));

    if (defined(@tmp1) && (@tmp1 > 0)) {
      my $node=$_;
      my $status=$tmp1[0]->{status};
      my $nodetype=$tmp1[0]->{nodetype};

      my $monserver=$host;
      my $tmp2=$table2->getNodeAttribs($node, ['monserver', 'servicenode']);
      if (defined($tmp2) && ($tmp2)) {
        if ($tmp2->{monserver}) {  $monserver=$tmp2->{monserver}; }
        elsif ($tmp2->{servicenode})  {  $monserver=$tmp2->{servicenode}; }
      }

      if (exists($ret->{$monserver})) {
        my $pa=$ret->{$monserver};
        push(@$pa, [$node, $nodetype, $status]);
      }
      else {
        $ret->{$monserver}=[ [$node,$nodetype, $status] ];
      }
    }    
  }
  $table->close();
  $table2->close();
  return $ret;
}




#--------------------------------------------------------------------------------
=head3    nodeStatMonName
      This function returns the current monitoring plug-in name that is assigned for monitroing
      the node status for xCAT cluster.  
     Arguments:
        none
    Returns:
        plug-in name.
=cut
#--------------------------------------------------------------------------------
sub nodeStatMonName {
  return $NODESTAT_MON_NAME;
}









