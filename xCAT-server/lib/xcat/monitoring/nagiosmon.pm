#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_monitoring::nagiosmon;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use File::Copy qw/copy cp mv move/;
use xCAT::NodeRange;
use Sys::Hostname;
use xCAT::Utils;
use xCAT::GlobalDef;
use xCAT_monitoring::monitorctrl;
use xCAT::MsgUtils;
use xCAT::DBobjUtils;
use xCAT::TableUtils;
use xCAT::NetworkUtils;
use Data::Dumper;
1;


#-------------------------------------------------------------------------------
=head1  xCAT_monitoring:nagiosmon  
=head2    Package Description
  xCAT monitoring plugin package to handle Nagios monitoring.
=cut
#-------------------------------------------------------------------------------

#--------------------------------------------------------------------------------
=head3    start
      This function gets called by the monitorctrl module
      when xcatd starts and when monstart command is issued by the user. 
      It starts the daemons and does necessary startup process for the Nagios monitoring.
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
    print "nagiosmon::start called\n";
    my $noderef=shift;
    if ($noderef =~ /xCAT_monitoring::nagiosmon/) {
	$noderef=shift;
    }
    my $scope=shift;
    my $callback=shift;
    my $grands=shift;
    
    my $localhostname=hostname();

    #only start once. this function will get called twice for mn, once for children and once for grand children. 
    if (($grands) && (keys(%$grands) > 0)) {
	return (0, "ok");
    }

    
    my $isSN=xCAT::Utils->isServiceNode();
    
    my $mychildren_cfg="/etc/nagios/objects/mychildren.cfg";
    if ($isSN) { #start nagios daemon only when mychildren exists on the sn
	if (-f $mychildren_cfg) {
	    #my $rc=`service nagios restart 2>&1`;
	    my $rc=xCAT::Utils->restartservice("nagios");
	    reportError("$localhostname: $rc", $callback);
	}
    }
    else { #always start nagios daemon on mn
	#my $rc=`service nagios restart 2>&1`;
	my $rc=xCAT::Utils->restartservice("nagios");
	reportError("$localhostname: $rc", $callback);
    }
    
    #go to nodes to start nrpe
    my $inactive_nodes=[];
    if (($scope) && ($noderef)) {
	my @mon_nodes=@$noderef;
	my %nodes_status=xCAT::NetworkUtils->pingNodeStatus(@mon_nodes); 
	$inactive_nodes=$nodes_status{$::STATUS_INACTIVE};
	if (@$inactive_nodes>0) { 
	    my $error="The following nodes cannot have nrpe started because they are inactive:\n  @$inactive_nodes.";
	    reportError("$localhostname: $error", $callback);
	}
	
	my $active_nodes=$nodes_status{$::STATUS_ACTIVE};
	if (@$active_nodes > 0) {
	    my $nodelist=join(',',@$active_nodes); 
	    my $result=`XCATBYPASS=Y $::XCATROOT/bin/xdsh $nodelist "service nrpe restart" 2>&1`;
	    if ($?) {
		reportError("$localhostname: $result", $callback);
		return (1, $result);
	    }     	   
	        
	}
    }
    
    return (0, "started");
}



#--------------------------------------------------------------------------------
=head3    stop
      This function gets called when monstop command is issued by the user. 
      It stops the monitoring on all nodes, stops the Nagios daemons.
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
    print "nagiosmon::stop called\n";
    my $noderef=shift;
    if ($noderef =~ /xCAT_monitoring::nagiosmon/) {
	$noderef=shift;
    }
    my $scope=shift;
    my $callback=shift;
    my $grands=shift;

    #only stop one. this function will get called twice for mn, once for children and once for grand children. 
    if (($grands) && (keys(%$grands) > 0)) {
	return (0, "ok");
    }


    my $localhostname=hostname();
    
    my $rc=`service nagios stop 2>&1`;
    reportError("$localhostname: $rc", $callback);
    
    #go to nodes to start nrpe
    if (($scope) && ($noderef)) {
	my @mon_nodes=@$noderef;
	my %nodes_status=xCAT::NetworkUtils->pingNodeStatus(@mon_nodes); 

	my $active_nodes=$nodes_status{$::STATUS_ACTIVE};
	if (@$active_nodes > 0) {
	    my $nodelist=join(',',@$active_nodes); 
	    my $result=`XCATBYPASS=Y $::XCATROOT/bin/xdsh $nodelist "service nrpe stop" 2>&1`;
	    if ($?) {
		reportError("$localhostname: $result", $callback);
		return (1, $result);
	    }     	   
	        
	}
    }

    return (0, "stopped");
}


#--------------------------------------------------------------------------------
=head3    config
      This function configures the cluster for the given nodes.  
      This function is called when moncfg command is issued or when xcatd starts
      on the service node. It will configure the cluster to include the given nodes within
      the monitoring doamin. 
    Arguments:
       p_nodes -- a pointer to an arrays of nodes to be added for monitoring. none means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only. 
                2 means localhost and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
       grands  -- a hash pointer to store the information of the grandchildren. key: "servicenode,xcatmaseter" for the grandchildren, value: a array pointer of grandchildren nodes. This one is only set when the current node is mn and handleGrandChildren returns 1 by the monitoring plugin.

    Returns:
       (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub config {
    print "nagiosmon:config called\n";
    my $noderef=shift;
    if ($noderef =~ /xCAT_monitoring::nagiosmon/) {
	$noderef=shift;
    }
    my $scope=shift;
    my $callback=shift;
    my $grands=shift;
    #print "*****nagiosmon::config: noderef:" . Dumper($noderef);
    #print "*****nagiosmon::config: grands:" . Dumper($grands);
    
    my $localhostname=hostname();
    
    #the identification of this node
    my @hostinfo=xCAT::NetworkUtils->determinehostname();
    my $isSN=xCAT::Utils->isServiceNode();
    my %iphash=();
    foreach(@hostinfo) {$iphash{$_}=1;}
    if (!$isSN) { $iphash{'noservicenode'}=1;}
    
    #set up the general settings in nagios.cfg file
    my $nagios_cfg="/etc/nagios/nagios.cfg";
    if (-f  $nagios_cfg) {
	#save the old version
	if (! -f "$nagios_cfg".".ORIG") {
	    copy($nagios_cfg, "$nagios_cfg".".ORIG");
	}
	copy($nagios_cfg, "$nagios_cfg".".save");
	
	if ($isSN) { 
	    #configuration for SN
	    my @ret=setup_nagios_cfg_sn($nagios_cfg);
	    if ((@ret > 0) && ($ret[0] != 0)) { return @ret; }
	} else {
	    #configuration for MN
	    my @ret=setup_nagios_cfg_mn($nagios_cfg);
	    if ((@ret > 0) && ($ret[0] != 0)) { return @ret; }
	}
    } else {
	return (1, "$nagios_cfg cannot be found. Please make sure Nagios is installed.");
    }


    
    #adding children nodes
    if (($noderef) && (@$noderef > 0)) {
	my $pPairHash=xCAT_monitoring::monitorctrl->getMonServer($noderef);
	if (ref($pPairHash) eq 'ARRAY') {
	    reportError($pPairHash->[1], $callback);
	    return (0, "");	
	}
	
	#print "noderef=" . Dumper($noderef);
	#print "iphash=" .  Dumper(%iphash);
	#print "pPairHash=" . Dumper($pPairHash);
	
	foreach my $key (keys (%$pPairHash)) {
	    my @key_a=split(':', $key);
	    if (! $iphash{$key_a[0]}) { next;} 
	    my $mon_nodes=$pPairHash->{$key};
	    
	    my $master=$key_a[1];
	    
	    #figure out what nodes to add
	    my @nodes_to_add=();
	    if ($mon_nodes) {
		foreach(@$mon_nodes) {
		    my $node=$_->[0];
		    my $nodetype=$_->[1];
		    if ($nodetype){ 
			if ($nodetype =~ /$::NODETYPE_OSI/) { push(@nodes_to_add, $node); }
		    } 
		}     
	    }
	    #print "nodestoadd=@nodes_to_add\n";
	    
	    #add new nodes to the Nagios cluster
	    if (@nodes_to_add> 0) {
		my @ret=addNodes(\@nodes_to_add, $master, $scope, $callback, 0);
		if ((@ret > 0) && ($ret[0] != 0)) { return @ret;}
	    }
	}
    }

    #for grand childdren
    if ((!$isSN) && ($grands) && (keys(%$grands) > 0)) {
	my @ret=addGrandNodes($grands, $scope, $callback, 0);
	if ((@ret > 0) && ($ret[0] != 0)) { return @ret;}
    }

    return (0, "configured");
}
 
sub setup_nagios_cfg_mn {
    my $nagios_cfg=shift;

    #set enable_notifications=1
    `grep "enable_notifications=" $nagios_cfg`;
    if ($? == 0) {
	my $rc=`sed -i 's/^[\#]*enable_notifications=.*\$/enable_notifications=1/' $nagios_cfg`;
	if ($?) {
	    `echo "$rc"`;
	}
    } else {
	`echo "enable_notifications=1" >> $nagios_cfg`;
    }
    
    #set execute_service_checks=1
    `grep "execute_service_checks=" $nagios_cfg`;
    if ($? == 0) {
	my $rc=`sed -i 's/^[\#]*execute_service_checks=.*\$/execute_service_checks=1/' $nagios_cfg`;
	if ($?) {
	    `echo "$rc"`;
	}
    } else {
	`echo "execute_service_checks=1" >> $nagios_cfg`;
    }
    
    #set check_external_commands=1
    `grep "check_external_commands=" $nagios_cfg`;
    if ($? == 0) {
	my $rc=`sed -i 's/^[\#]*check_external_commands=.*\$/check_external_commands=1/' $nagios_cfg`;
	if ($?) {
	    `echo "$rc"`;
	}
    } else {
	`echo "check_external_commands=1" >> $nagios_cfg`;
    }
    
    #set accept_passive_service_checks=1
    `grep "accept_passive_service_checks=" $nagios_cfg`;
    if ($? == 0) {
	my $rc=`sed -i 's/^[\#]*accept_passive_service_checks=.*\$/accept_passive_service_checks=1/' $nagios_cfg`;
	if ($?) {
	    `echo "$rc"`;
	}
    } else {
	`echo "accept_passive_service_checks=1" >> $nagios_cfg`;
    }
    return (0, "ok");
}   





sub setup_nagios_cfg_sn {
    my $nagios_cfg=shift;
    #set enable_notifications=0
    `grep "enable_notifications=" $nagios_cfg`;
    if ($? == 0) {
	my $rc=`sed -i 's/^[\#]*enable_notifications=.*\$/enable_notifications=0/' $nagios_cfg`;
	if ($?) {
	    `echo "$rc"`;
	}
    } else {
	`echo "enable_notifications=0" >> $nagios_cfg`;
    }
    
    #set obsess_over_services=1
    `grep "obsess_over_services=" $nagios_cfg`;
    if ($? == 0) {
	my $rc=`sed -i 's/^[\#]*obsess_over_services=.*\$/obsess_over_services=1/' $nagios_cfg`;
	if ($?) {
	    `echo "$rc"`;
	}
    } else {
	`echo "obsess_over_services=1" >> $nagios_cfg`;
    }
    
    #set ocsp_command=submit_service_check_result
    `grep "ocsp_command=" $nagios_cfg`;
    if ($? == 0) {
	my $rc=`sed -i 's/^[\#]*ocsp_command=.*\$/ocsp_command=submit_service_check_result/' $nagios_cfg`;
	if ($?) {
	    `echo "$rc"`;
	}
    } else {
	`echo "ocsp_command=submit_service_check_result" >> $nagios_cfg`;
    }
    
    #set obsess_over_hosts=1
    `grep "obsess_over_hosts=" $nagios_cfg`;
    if ($? == 0) {
	my $rc=`sed -i 's/^[\#]*obsess_over_hosts=.*\$/obsess_over_hosts=1/' $nagios_cfg`;
	if ($?) {
	    `echo "$rc"`;
	}
    } else {
	`echo "obsess_over_hosts=1" >> $nagios_cfg`;
    }
    
    my $local_cfg= "/etc/nagios/objects/localhost.cfg";
    if (-f $local_cfg) {
	mv($local_cfg, "$local_cfg.save");
    }
    my $rc=`grep "cfg_file=$local_cfg" $nagios_cfg`;
    #print "my rc=$rc\n";
    #print "grep \"cfg_file=$local_cfg\" $nagios_cfg\n";
    if ($rc && ($rc !~ /^(\s)*\#/)) {
	`sed -i 's/cfg_file=\\\/etc\\\/nagios\\\/objects\\\/localhost.cfg/\#cfg_cfg=\\\/etc\\\/nagios\\\/objects\\\/localhost.cfg/' $nagios_cfg`;
    }

    
    #set ochp_command=submit_host_check_result
    `grep "ochp_command=" $nagios_cfg`;
    if ($? == 0) {
	my $rc=`sed -i 's/^[\#]*ochp_command=.*\$/ochp_command=submit_host_check_result/' $nagios_cfg`;
	if ($?) {
	    `echo "$rc"`;
	}
    } else {
	`echo "ochp_command=submit_host_check_result" >> $nagios_cfg`;
    }

    #add commands in commands.cfg
    my $commands_cfg="/etc/nagios/objects/commands.cfg";
    if (-f  $commands_cfg) {
	#save the old version
	if (! -f "$commands_cfg".".ORIG") {
	    copy($commands_cfg, "$commands_cfg".".ORIG");
	}
	copy($commands_cfg, "$commands_cfg".".save");

	my $rc=`grep "submit_service_check_result" $commands_cfg |grep command_name`;
	if (!$rc || ($rc !~ /^(\s)*command_name(\s)+submit_service_check_result$/)) {
	    `echo "define command{
   command_name    submit_service_check_result
   command_line    /usr/lib/nagios/plugins/eventhandler/submit_service_check_result \\\$HOSTNAME\$ '\\\$SERVICEDESC\\\$' \\\$SERVICESTATE\$ '\\\$SERVICEOUTPUT\\\$'
}" >> $commands_cfg`;
	}
	my $rc=`grep "submit_host_check_result" $commands_cfg |grep command_name`;
	if (!$rc || ($rc !~ /^(\s)*command_name(\s)+submit_host_check_result$/)) {
	    `echo "define command{
        command_name    submit_host_check_result
        command_line    /usr/lib/nagios/plugins/eventhandler/submit_host_check_result \\\$HOSTNAME\$ \\\$HOSTSTATE\$ '\\\$HOSTOUTPUT\\\$'
}" >> $commands_cfg`;
	}
    } else {
	return (1, "$commands_cfg cannot be found. Please make sure Nagios is installed.");    
    }

    #create ncsa the commands
    my $ocsp_command="/usr/lib/nagios/plugins/eventhandler/submit_service_check_result";
    my $ochp_command="/usr/lib/nagios/plugins/eventhandler/submit_host_check_result";
    my $master=xCAT::TableUtils->get_site_Master();
    if (!$master) {
	my $rc=`grep XCATMASTER /opt/xcat/xcatinfo`;
	if ($rc && ($rc =~/^XCATMASTER=(.*)/)) {
	    $master=$1;
	}
    }
    
    my $master_ip="127.0.0.1";
    if ($master) {
	$master_ip=xCAT::NetworkUtils::getipaddr($master);
    }
    #print "master=$master, ip=$master_ip\n";

    if (-f $ocsp_command) {
	#save the old version
	if (! -f "$ocsp_command".".ORIG") {
	    copy($ocsp_command, "$ocsp_command".".ORIG");
	}
	copy($ocsp_command, "$ocsp_command".".save");
    }
    unlink($ocsp_command);

    if (-f $ochp_command) {
	#save the old version
	if (! -f "$ochp_command".".ORIG") {
	    copy($ochp_command, "$ochp_command".".ORIG");
	}
	copy($ochp_command, "$ochp_command".".save");
    }
    unlink($ochp_command);

    open(FILE1, ">$ocsp_command");
    print FILE1 "\#!/bin/sh
\# Arguments:
\#  \$1 = host_name (Short name of host that the service is
\#       associated with)
\#  \$2 = svc_description (Description of the service)
\#  \$3 = state_string (A string representing the status of
\#       the given service - \"OK\", \"WARNING\", \"CRITICAL\"
\#       or \"UNKNOWN\")
\#  \$4 = plugin_output (A text string that should be used
\#       as the plugin output for the service checks)
\#

\# Convert the state string to the corresponding return code
return_code=-1
case \"\$3\" in
    OK)
       return_code=0
        ;;
    WARNING)
       return_code=1
        ;;
   CRITICAL)
       return_code=2
        ;;
   UNKNOWN)
       return_code=-1
        ;;
esac

echo \"1=\$1, 2=\$2, 3=\$3, 4=\$4, return_code=\$return_code\" >> /tmp/6.txt
\# pipe the service check info into the send_nsca program, which
\# in turn transmits the data to the nsca daemon on the central
\# monitoring server
/usr/bin/printf \"%s\\t%s\\t%s\\t%s\\n\" \"\$1\" \"\$2\" \"\$return_code\" \"\$4\" | /usr/bin/send_nsca -H $master_ip -c /etc/nagios/send_nsca.cfg
";
    close FILE1;

    open(FILE2, ">$ochp_command");
    print FILE2 "\#!/bin/sh
\# Arguments:
\#  \$1 = host_name (Short name of host that the service is
\#       associated with)
\#  \$2 = state_string (A string representing the status of
\#       the given host - \"UP\", \"DOWN\")
\#  \$3 = plugin_output (A text string that should be used
\#       as the plugin output for the host checks)
\#

# Convert the state string to the corresponding return code
return_code=-1
case \"\$2\" in
    UP)
       return_code=0
        ;;
    DOWN)
       return_code=1
        ;;
    UNREACHABLE)
       return_code=1
        ;;
    UNKNOWN)
       return_code=-1
        ;;
esac
echo \"1=\$1, 2=\$2, 3=\$3, return_code=\$return_code\" >> /tmp/5.txt

\# pipe the service check info into the send_nsca program, which
\# in turn transmits the data to the nsca daemon on the central
\# monitoring server
/usr/bin/printf \"%s\\t%s\\t%s\\n\" \"\$1\" \"\$return_code\" \"\$3\" | /usr/bin/send_nsca -H $master_ip -c /etc/nagios/send_nsca.cfg
";
    close FILE2;
    
    chmod 0755, "$ocsp_command", "$ochp_command";
    return (0, "ok");
}

#--------------------------------------------------------------------------------
=head3    addNodes
      This function adds the nodes into the nagios cluster.
    Arguments:
       nodes --an array of nodes to be added. 
       master -- the monitoring master of the node.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only. 
                2 means localhost and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
       (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub addNodes {
    my $pmon_nodes=shift;
    if ($pmon_nodes =~ /xCAT_monitoring::nagiosmon/) {
	$pmon_nodes=shift;
    }
    
    my @mon_nodes = @$pmon_nodes;
    if (@mon_nodes==0) { return (0, "");}

    my $master=shift;
    my $scope=shift;
    my $callback=shift;
    print "nagiosmon.addNodes mon_nodes=@mon_nodes\n";
    
    my @hostinfo=xCAT::NetworkUtils->determinehostname();
    my %iphash=();
    foreach(@hostinfo) {$iphash{$_}=1;}
    my $localhostname=hostname();


    my $mychildren_cfg="/etc/nagios/objects/mychildren.cfg";
    my $nagios_cfg="/etc/nagios/nagios.cfg";
    
    if (-f  $mychildren_cfg) {
	#save the old version
	if (! -f "$mychildren_cfg".".ORIG") {
	    copy($mychildren_cfg, "$mychildren_cfg".".ORIG");
	}
	copy($mychildren_cfg, "$mychildren_cfg".".save");
    }

    #populate mychildren with new hosts
    #print "defining hosts in  $mychildren_cfg\n";
    foreach my $node (@mon_nodes) {
	my $rc=`grep host_name $mychildren_cfg |grep $node`;
        if (($rc) && ($rc =~ /host_name(\s)+$node(\s)*$/)) {
	    #if found, remove first
	    `sed -i "/#BEGIN HOST $node/,/#END HOST $node/ d" $mychildren_cfg`
	}  
	my $ip=xCAT::NetworkUtils->getipaddr($node);
	#print "ip=$ip\n";
        `echo "\#BEGIN HOST $node
define host\{\n    use             linux-server        
    host_name       $node                
    alias           $node    
    address         $ip              
    max_check_attempts  10
    contact_groups 	admins
\}
\#END HOST $node" >> $mychildren_cfg`;
    }

    #define host group for the nodes
    #print "defining host_group in  $mychildren_cfg\n";
    my $rc=`grep "hostgroup_name" $mychildren_cfg`;
    if (!$rc || ($rc !~ /^(\s)*hostgroup_name(\s)+mychildren/)) {
	`echo "define hostgroup{
        hostgroup_name  mychildren 
        alias           mychildren 
        members 
}
" >> $mychildren_cfg`;
    } 
    $rc=`grep "members" $mychildren_cfg`;
    if ($rc && ($rc =~ /members(\s)+(.*)/)) {
	my $oldnodes=$2;
	my %nodehash=();
	if ($oldnodes) {
	    my @a=split(',', $oldnodes);

	    foreach (@a) {
		$nodehash{$_}=1;
	    }
	}
	foreach my $node (@mon_nodes) {
	    if (!exists($nodehash{$node})) {
		$nodehash{$node}=1;
	    }
	}
        my $newnodes=join(',', keys(%nodehash));
	if ($newnodes) {
	    `sed -i 's/members.*\$/members $newnodes/'  $mychildren_cfg`;
	}
    }  

    #add nrpe command in mychildren.cfg file
    #print "defining nrpe command in  $mychildren_cfg\n";
    my $rc=`grep "command_name" $mychildren_cfg`;
    if (!$rc || ($rc !~ /^(\s)*command_name(\s)+check_nrpe/)) {
	`echo "\#check_nrpe command definition
define command{
command_name check_nrpe
command_line \\\$USER1\$/check_nrpe -H \\\$HOSTADDRESS\$ -t 30 -c \\\$ARG1\$
}
" >> $mychildren_cfg`;
    }

    #define services for the new hosts
    #print "defining services in  $mychildren_cfg\n";
    my $rc=`grep "service_description" $mychildren_cfg`;
    if (!$rc || ($rc !~ /(\s)*service_description(\s)+SSH/)) {
	`echo "define service{\n    use     generic-service
    hostgroups    mychildren
    service_description SSH
    check_command   check_ssh
}
" >> $mychildren_cfg`;
    }
    if (!$rc || ($rc !~ /(\s)*service_description(\s)+FTP/)) {
	`echo "define service{\n    use     generic-service
    hostgroups    mychildren
    service_description FTP
    check_command   check_ftp
}
" >> $mychildren_cfg`;
    }
    if (!$rc || ($rc !~ /(\s)*service_description(\s)+Load(\s)*/)) {
	`echo "define service{\n    use                             generic-service
    contact_groups                  admins
    hostgroups                      mychildren
    service_description             Load
    check_command                   check_nrpe!check_load
}
" >> $mychildren_cfg`;
    }
    if (!$rc || ($rc !~ /(\s)*service_description(\s)+Processes(\s)*/)) {
	`echo "define service{\n    use                             generic-service
    contact_groups                  admins
    hostgroups                      mychildren
    service_description             Processes
    check_command                   check_nrpe!check_total_procs
}
" >> $mychildren_cfg`;
    }
    if (!$rc || ($rc !~ /(\s)*service_description(\s)+Users(\s)*/)) {
	`echo "define service{\n    use                             generic-service
    contact_groups                  admins
    hostgroups                      mychildren
    service_description             Users
    check_command                   check_nrpe!check_users
}
" >> $mychildren_cfg`;
    }

    #add cfg_file=/etc/nagios/objects/mychildren.cfg to nagios.cfg file
    #print "adding $mychildren_cfg to $nagios_cfg file.\n";
    my $rc=`grep "mychildren.cfg" $nagios_cfg`;
    if (!$rc || ($rc !~ /^cfg_file=(.*)\/mychildren.cfg/)) {
	`echo "\#BEGIN xCAT configiration file mychildren
cfg_file=/etc/nagios/objects/mychildren.cfg
\#END xCAT configiration file mychildren
" >> $nagios_cfg`;
    }


    #go to nodes to configure nrpe
    my $inactive_nodes=[];
    if ($scope) { 
	#print "Configuring the nodes.\n";
	my %nodes_status=xCAT::NetworkUtils->pingNodeStatus(@mon_nodes); 
	$inactive_nodes=$nodes_status{$::STATUS_INACTIVE};
	if (@$inactive_nodes>0) { 
	    my $error="The following nodes cannot be configured because they are inactive:\n  @$inactive_nodes.";
	    reportError($error, $callback);
	}
	
	my $active_nodes=$nodes_status{$::STATUS_ACTIVE};
	if (@$active_nodes > 0) {
	    my $nodelist=join(',',@$active_nodes); 
	    my $result=`XCATBYPASS=Y $::XCATROOT/bin/updatenode $nodelist -P confNagios 2>&1`;
	    if ($?) {
		my $error= "$result";
		reportError($error, $callback);
		return (1, $error);
	    }     
	}
    }
 
    return (0, "ok"); 
}
 

#--------------------------------------------------------------------------------
=head3    removeNodes
      This function removes the nodes from the nagios cluster.
    Arguments:
       nodes --an array of nodes to be removed. 
       master -- the monitoring master of the node.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only. 
                2 means localhost and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
       (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub removeNodes {
    my $pmon_nodes=shift;
    if ($pmon_nodes =~ /xCAT_monitoring::nagiosmon/) {
	$pmon_nodes=shift;
    }
    
    my @mon_nodes = @$pmon_nodes;
    if (@mon_nodes==0) { return (0, "");}

    my $master=shift;
    my $scope=shift;
    my $callback=shift;
    print "nagiosmon.removeNodes mon_nodes=@mon_nodes\n";
    
    my @hostinfo=xCAT::NetworkUtils->determinehostname();
    my %iphash=();
    foreach(@hostinfo) {$iphash{$_}=1;}
    my $localhostname=hostname();


    my $mychildren_cfg="/etc/nagios/objects/mychildren.cfg";
    my $nagios_cfg="/etc/nagios/nagios.cfg";

    if (-f  $mychildren_cfg) {
	#save the old version
	if (! -f "$mychildren_cfg".".ORIG") {
	    copy($mychildren_cfg, "$mychildren_cfg".".ORIG");
	}
	copy($mychildren_cfg, "$mychildren_cfg".".save");
    }

    if (-f $mychildren_cfg) {
	
	#remove from the host group 
	my $rc=`grep "hostgroup_name" $mychildren_cfg`;
	if ($rc && ($rc =~ /^(\s)*hostgroup_name(\s)+mychildren/)) { 
	    $rc=`grep "members" $mychildren_cfg`;
	    if ($rc && ($rc =~ /members(\s)+(.*)/)) {
		my $oldnodes=$2;
		my %nodehash=();
		if ($oldnodes) {
		    my @a=split(',', $oldnodes);
		    
		    foreach (@a) {
			$nodehash{$_}=1;
		    }
		}
		foreach my $node (@mon_nodes) {
		    if (exists($nodehash{$node})) {
			delete($nodehash{$node});
		    }
		}
		my $newnodes=join(',', keys(%nodehash));
		if ($newnodes) {
		    `sed -i 's/members.*\$/members $newnodes/'  $mychildren_cfg`;

		    #remove the given hosts from mychildren.cfg
		    foreach my $node (@mon_nodes) {
			my $rc=`grep host_name $mychildren_cfg |grep $node`;
			if (($rc) && ($rc =~ /host_name(\s)+$node(\s)*$/)) {
			    #if found, remove it
			    `sed -i "/#BEGIN HOST $node/,/#END HOST $node/ d" $mychildren_cfg`
			}  
		    }
		} else { #no nodes in mychildren.cfg
		    #remove the file and remove it from nagios.cfg
		    unlink($mychildren_cfg);
		    my $rc=`grep "mychildren.cfg" $nagios_cfg`;
		    if ($rc && ($rc =~ /^cfg_file=(.*)\/mychildren.cfg/)) {
			`sed -i "/#BEGIN xCAT configiration file mychildren/,/#END xCAT configiration file mychildren/ d" $nagios_cfg`;
				    }		    
		}
	    }  
	}
	
    }

    return (0, "ok"); 
}


#--------------------------------------------------------------------------------
=head3    addGrandNodes
      This function adds the grand children nodes into the nagios cluster.
    Arguments:
       grands -- pointer to a hash. key: "servicenode, xcatmaster" for the nodes, 
                 value: an array pointer to the nodes.
       master -- the monitoring master of the node.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only. 
                2 means localhost and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
       (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub addGrandNodes {
    my $grands=shift;
    if ($grands =~ /xCAT_monitoring::nagiosmon/) {
	$grands=shift;
    }
    
    my $scope=shift;
    my $callback=shift;
    print "nagiosmon.addGrandNodes\n";
    
    my @hostinfo=xCAT::NetworkUtils->determinehostname();
    my %iphash=();
    foreach(@hostinfo) {$iphash{$_}=1;}
    my $localhostname=hostname();


    my $cn_template_cfg="/etc/nagios/objects/cn_template.cfg";
    my $nagios_cfg="/etc/nagios/nagios.cfg";

    #create cn_template.cfg
    if (-f  $cn_template_cfg) {
	#save the old version
	if (! -f "$cn_template_cfg".".ORIG") {
	    copy($cn_template_cfg, "$cn_template_cfg".".ORIG");
	}
	copy($cn_template_cfg, "$cn_template_cfg".".save");
    }
    #print "defining xCAT-node in  $cn_template_cfg\n";
    my $rc=`grep "xCAT-node" $cn_template_cfg`;
    if (!$rc || ($rc !~ /^(\s)*name(\s)+xCAT-node/)) {
	`echo "define host{
        name                            xCAT-node\n        use                             generic-host
        check_period                    24x7
        active_checks_enabled  0
        passive_checks_enabled 1
        check_interval                  5
        retry_interval                  1
        max_check_attempts              10
        check_command                   check-host-alive
        notification_period             workhours
        notification_interval           120
        notification_options            d,u,r
        contact_groups                  admins
        register                        0
        }
" >> $cn_template_cfg`;

    }


    foreach my $sv_pair (keys(%$grands)) {
        my @server_pair=split(',', $sv_pair); 
        my $sv=$server_pair[0];
        my $sv1;
	if (@server_pair>1) {
	    $sv1=$server_pair[1];
	}
        my $pnodes=$grands->{$sv_pair};
	my @mon_nodes;
        if ($pnodes) {
	    @mon_nodes=@$pnodes;
	}
        
        my $cn_cfg="/etc/nagios/objects/cn_$sv.cfg";
	
	#create compute node cfg file for a service node
	if (-f  $cn_cfg) {
	    copy($cn_cfg, "$cn_cfg".".save");
	}
	
    
	#populate cn cfg with new hosts
	#print "defining hosts in  $cn_cfg\n";
	foreach my $node (@mon_nodes) {
	my $rc=`grep host_name $cn_cfg |grep $node`;
        if (($rc) && ($rc =~ /host_name(\s)+$node(\s)*$/)) {
	    #if found, remove first
	    `sed -i "/#BEGIN HOST $node/,/#END HOST $node/ d" $cn_cfg`
	}  
	my $ip=xCAT::NetworkUtils->getipaddr($node);
	#print "ip=$ip\n";
        `echo "\#BEGIN HOST $node
define host\{\n    use         xCAT-node
    host_name   $node
    alias       $node
    address     $ip
    parents     $sv
\}
\#END HOST $node" >> $cn_cfg`;
    }

	#define host group for the nodes
	#print "defining host_group in  $cn_cfg\n";
	my $rc=`grep "hostgroup_name" $cn_cfg`;
	if (!$rc || ($rc !~ /^(\s)*hostgroup_name(\s)+cn_$sv/)) {
	    `echo "define hostgroup{
        hostgroup_name  cn_$sv 
        alias           cn_$sv 
        members 
}
" >> $cn_cfg`;
	} 
	$rc=`grep "members" $cn_cfg`;
	if ($rc && ($rc =~ /members(\s)+(.*)/)) {
	    my $oldnodes=$2;
	    my %nodehash=();
	    if ($oldnodes) {
		my @a=split(',', $oldnodes);
		
		foreach (@a) {
		    $nodehash{$_}=1;
		}
	    }
	    foreach my $node (@mon_nodes) {
		if (!exists($nodehash{$node})) {
		    $nodehash{$node}=1;
		}
	    }
	    my $newnodes=join(',', keys(%nodehash));
	    if ($newnodes) {
		`sed -i 's/members.*\$/members $newnodes/'  $cn_cfg`;
	    }
	}  


	#define services for the new hosts
	#print "defining services in  $cn_cfg\n";
	my $rc=`grep "service_description" $cn_cfg`;
	if (!$rc || ($rc !~ /(\s)*service_description(\s)+SSH/)) {
	    `echo "define service{\n    use     generic-service
    hostgroups  cn_$sv
    service_description  SSH
    check_command   check_ssh
    active_checks_enabled  0
    passive_checks_enabled 1
}
" >> $cn_cfg`;
	}
	if (!$rc || ($rc !~ /(\s)*service_description(\s)+FTP/)) {
	    `echo "define service{\n    use     generic-service
    hostgroups  cn_$sv
    service_description  FTP
    check_command   check_ssh
    active_checks_enabled  0
    passive_checks_enabled 1
}
" >> $cn_cfg`;
	}
	if (!$rc || ($rc !~ /(\s)*service_description(\s)+Load(\s)*/)) {
	    `echo "define service{\n    use     generic-service
    hostgroups  cn_$sv
    service_description Load
    check_command   check_ssh
    active_checks_enabled  0
    passive_checks_enabled 1
}
" >> $cn_cfg`;
	}
	if (!$rc || ($rc !~ /(\s)*service_description(\s)+Processes(\s)*/)) {
	    `echo "define service{\n    use     generic-service
    hostgroups  cn_$sv
    service_description  Processes
    check_command   check_ssh
    active_checks_enabled  0
    passive_checks_enabled 1
}
" >> $cn_cfg`;
	}
	
	#add cfg_file=/etc/nagios/objects/cn_$sv.cfg to nagios.cfg file
	#print "adding $cn_cfg to $nagios_cfg file.\n";
	my $rc=`grep "cn_$sv.cfg" $nagios_cfg`;
	if (!$rc || ($rc !~ /^cfg_file=(.*)\/cn_$sv.cfg/)) {
	    `echo "\#BEGIN xCAT configiration file cn_$sv
cfg_file=/etc/nagios/objects/cn_$sv.cfg
\#END xCAT configiration file cn_$sv
" >> $nagios_cfg`;
	}    
	#print "adding $cn_template_cfg to $nagios_cfg file.\n";
	my $rc=`grep "cn_template.cfg" $nagios_cfg`;
	if (!$rc || ($rc !~ /^cfg_file=(.*)\/cn_template.cfg/)) {
	    `echo "\#BEGIN xCAT configiration file for grandchildren template
cfg_file=$cn_template_cfg
\#END xCAT configiration file for grandchildren template
" >> $nagios_cfg`;
	}    
    }

    return (0, "ok"); 
}





#--------------------------------------------------------------------------------
=head3    removeGrandNodes
      This function removes the grand children nodes from the nagios cluster.
    Arguments:
       grands -- pointer to a hash. key: "servicenode, xcatmaster" for the nodes, 
                 value: an array pointer to the nodes.
       master -- the monitoring master of the node.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only. 
                2 means localhost and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
       (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub removeGrandNodes {
    my $grands=shift;
    if ($grands =~ /xCAT_monitoring::nagiosmon/) {
	$grands=shift;
    }
    
    my $scope=shift;
    my $callback=shift;
    print "nagiosmon.removeGrandNodes\n";
    
    my @hostinfo=xCAT::NetworkUtils->determinehostname();
    my %iphash=();
    foreach(@hostinfo) {$iphash{$_}=1;}
    my $localhostname=hostname();
    my $nagios_cfg="/etc/nagios/nagios.cfg";


    foreach my $sv_pair (keys(%$grands)) {
        my @server_pair=split(',', $sv_pair); 
        my $sv=$server_pair[0];
        my $sv1;
	if (@server_pair>1) {
	    $sv1=$server_pair[1];
	}
        my $pnodes=$grands->{$sv_pair};
	my @mon_nodes;
        if ($pnodes) {
	    @mon_nodes=@$pnodes;
	}
        
        my $cn_cfg="/etc/nagios/objects/cn_$sv.cfg";
	if (-f  $cn_cfg) {
	    #remove  hosts from the hostgroup
	    my $rc=`grep "hostgroup_name" $cn_cfg`;
	    if ($rc && ($rc =~ /^(\s)*hostgroup_name(\s)+cn_$sv/)) {
		
		$rc=`grep "members" $cn_cfg`;
		if ($rc && ($rc =~ /members(\s)+(.*)/)) {
		    my $oldnodes=$2;
		    my %nodehash=();
		    if ($oldnodes) {
			my @a=split(',', $oldnodes);
			
			foreach (@a) {
			    $nodehash{$_}=1;
			}
		    }
		    foreach my $node (@mon_nodes) {
			if (exists($nodehash{$node})) {
			    delete($nodehash{$node});
			}
		    }
		    my $newnodes=join(',', keys(%nodehash));
		    if ($newnodes) {
			`sed -i 's/members.*\$/members $newnodes/'  $cn_cfg`;
			#remove the hosts from cn cfg
			foreach my $node (@mon_nodes) {
			    my $rc=`grep host_name $cn_cfg |grep $node`;
			    if (($rc) && ($rc =~ /host_name(\s)+$node(\s)*$/)) {
				#if found, remove it
				`sed -i "/#BEGIN HOST $node/,/#END HOST $node/ d" $cn_cfg`
			    }  
			}
		    } else {
			unlink($cn_cfg);
			my $rc=`grep "$cn_cfg" $nagios_cfg`;
			if ($rc || ($rc =~ /^cfg_file=(.*)\/cn_$sv.cfg/)) {
			    `sed -i "/#BEGIN xCAT configiration file cn_$sv/,/#END xCAT configiration file cn_$sv/ d" $nagios_cfg`;
				    }		    
		    }
		   
		}
	    }
	}
    }

    return (0, "ok"); 
}



#--------------------------------------------------------------------------------
=head3    deconfig
      This function de-configures the cluster for the given nodes.  
      This function is called when mondecfg command is issued by the user. 
      It should remove the given nodes from the product for monitoring.
    Arguments:
       p_nodes -- a pointer to an arrays of nodes to be removed for monitoring. none means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means local host only. 
                2 means both local host and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
       (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub deconfig {
    print "nagiosmon:deconfig called\n";
    my $noderef=shift;
    if ($noderef =~ /xCAT_monitoring::nagiosmon/) {
	$noderef=shift;
    }
    my $scope=shift;
    my $callback=shift;
    my $grands=shift;
    my $localhostname=hostname();
    
    #the identification of this node
    my @hostinfo=xCAT::NetworkUtils->determinehostname();
    my $isSN=xCAT::Utils->isServiceNode();
    my %iphash=();
    foreach(@hostinfo) {$iphash{$_}=1;}
    if (!$isSN) { $iphash{'noservicenode'}=1;}
    
   
    #removinging children nodes
    if (($noderef) && (@$noderef > 0)) {
	my $pPairHash=xCAT_monitoring::monitorctrl->getMonServer($noderef);
	if (ref($pPairHash) eq 'ARRAY') {
	    reportError($pPairHash->[1], $callback);
	    return (0, "");	
	}
	
	#print "noderef=" . Dumper($noderef);
	#print "iphash=" .  Dumper(%iphash);
	#print "pPairHash=" . Dumper($pPairHash);
	
	foreach my $key (keys (%$pPairHash)) {
	    my @key_a=split(':', $key);
	    if (! $iphash{$key_a[0]}) { next;} 
	    my $mon_nodes=$pPairHash->{$key};
	    
	    my $master=$key_a[1];
	    
	    #figure out what nodes to remove
	    my @nodes_to_rm=();
	    if ($mon_nodes) {
		foreach(@$mon_nodes) {
		    my $node=$_->[0];
		    my $nodetype=$_->[1];
		    if ($nodetype){ 
			if ($nodetype =~ /$::NODETYPE_OSI/) { push(@nodes_to_rm, $node); }
		    } 
		}     
	    }
	    #print "nodes to rme=@nodes_to_rm\n";
	    
	    #remove new nodes to the Nagios cluster
	    if (@nodes_to_rm> 0) {
		my @ret=removeNodes(\@nodes_to_rm, $master, $scope, $callback, 0);
		if ((@ret > 0) && ($ret[0] != 0)) { return @ret;}
	    }
	}
    }
    

    #for grand childdren
    if ((!$isSN) && ($grands) && (keys(%$grands) > 0)) {
	my @ret=removeGrandNodes($grands, $scope, $callback, 0);
	if ((@ret > 0) && ($ret[0] != 0)) { return @ret;}
    }

    return (0, "deconfigured"); 
}

#--------------------------------------------------------------------------------
=head3    supportNodeStatusMon
    This function is called by the monitorctrl module to check
    if Nagios can help monitoring and returning the node status.
    
    Arguments:
        none
    Returns:
         1  
=cut
#--------------------------------------------------------------------------------
sub supportNodeStatusMon {
  print "nagiosmon::supportNodeStatusMon called\n";
  return 0;
}



#--------------------------------------------------------------------------------
=head3   startNodeStatusMon
    This function is called by the monitorctrl module to tell
    Nagios to start monitoring the node status and feed them back
    to xCAT. Nagios will start setting up the notification 
    to monitor the node status changes.  

    Arguments:
       p_nodes -- a pointer to an arrays of nodes for monitoring. none means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means local host only. 
                2 means both local host and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
       (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub startNodeStatusMon {
  print "nagiosmon::startNodeStatusMon\n";
  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::nagiosmon/) {
    $noderef=shift;
  }
  my $scope=shift;
  my $callback=shift;

  my $localhostname=hostname();
  my $retcode=0;
  my $retmsg="";


  my $isSN=xCAT::Utils->isServiceNode();

  #get all the nodes status from IBM.MngNode class of local host and 
  #the identification of this node
  my $pPairHash=xCAT_monitoring::monitorctrl->getMonServer($noderef);
  if (ref($pPairHash) eq 'ARRAY') {
      reportError($pPairHash->[1], $callback);
      return (1, "");	
  }

  my @hostinfo=xCAT::NetworkUtils->determinehostname();
  my %iphash=();
  foreach(@hostinfo) {$iphash{$_}=1;}
  if (!$isSN) { $iphash{'noservicenode'}=1;}


  return ($retcode, $retmsg);
}




#--------------------------------------------------------------------------------
=head3   stopNodeStatusMon
    This function is called by the monitorctrl module to tell
    Nagios to stop feeding the node status info back to xCAT. It will
    stop the notification that is monitoring the node status.

    Arguments:
       p_nodes -- a pointer to an arrays of nodes for monitoring. none means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means local host only. 
                2 means both local host and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
        (return code, message)
=cut
#--------------------------------------------------------------------------------
sub stopNodeStatusMon {
  print "nagiosmon::stopNodeStatusMon called\n";
  my $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::nagiosmon/) {
    $noderef=shift;
  }
  my $scope=shift;
  my $callback=shift;

  my $retcode=0;
  my $retmsg="";

  my $isSN=xCAT::Utils->isServiceNode();
  my $localhostname=hostname();
 

  return ($retcode, $retmsg);
}



#--------------------------------------------------------------------------------
=head3    reportError
      This function writes the error message to the callback, otherwise to syslog. 
    Arguments:
       error
       callback 
    Returns:
       none
=cut
#--------------------------------------------------------------------------------
sub reportError 
{
  my $error=shift;
  my $callback=shift;
  if ($callback) {
    my $rsp={};
    $rsp->{data}->[0]=$error;
    $callback->($rsp);
  } else { xCAT::MsgUtils->message('S', "[mon]: $error\n"); }
  return;
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
    nagiosmon is a monitoring plug-in for Nagios to monitor xCAT cluster. It defines hosts, host groups and services in the Nagios configuration files. The xCAT nodes and services will to be monitored by Nagios with its NRPE and NSCA add-ons. The following sequence of commands will do the configuration and monitoring.
    monadd nagiosmon
    moncfg nagiosmon service -r
    moncfg nagiosmon compute -r
    monstart nagiosmon service -r
    monstart nagiosmon compute -r
    where 'service' is the node group name for the service node, 'compute' is the node group name for the compute node.				  
";

}


#--------------------------------------------------------------------------------
=head3    getPostscripts
      This function returns the postscripts needed for the nodes and for the servicd
      nodes. 
     Arguments:
        none
    Returns:
     The the postscripts. It a pointer to an array with the node group names as the keys
    and the comma separated poscript names as the value. For example:
    {service=>"cmd1,cmd2", xcatdefaults=>"cmd3,cmd4"} where xcatdefults is a group
    of all nodes including the service nodes.
=cut
#--------------------------------------------------------------------------------
sub getPostscripts {
  my $ret={};
  $ret->{xcatdefaults}="confNagios";
  return $ret;
}



#--------------------------------------------------------------------------------
=head3    show
      This function shows the monitoring status.   
      This function is called when monshow command is issued.
    Arguments:
       p_nodes -- a pointer to an arrays of nodes to be added for monitoring. none means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only. 
                2 means localhost and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
       (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub show 
{
  print "nagiosmon:show called\n";
  no strict 'refs';
  my ($noderef, $sum, $time, $attrs, $pe, $where,$callback) = @_;

  return (0, "");
}


#--------------------------------------------------------------------------
=head3    handleGrandChildren
      This function tells if the mn shall handle the nodes that are managed by the service nodes.    
      
=cut
#---------------------------------------------------------------------------
sub handleGrandChildren {
    return 1;
}

