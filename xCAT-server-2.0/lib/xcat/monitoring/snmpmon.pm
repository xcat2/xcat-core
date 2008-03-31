#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_monitoring::snmpmon;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use IO::File;
use xCAT::Utils;
use xCAT::MsgUtils;


#print "xCAT_monitoring::snmpmon loaded\n";
1;



#-------------------------------------------------------------------------------
=head1  xCAT_monitoring:snmpmon  
=head2    Package Description
  xCAT monitoring plugin package to handle SNMP monitoring. 

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
  #print "snmpmon::start called\n";

  $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::snmpmon/) {
    $noderef=shift;
  }

  # do not turn it on on the service node
  #if (xCAT::Utils->isServiceNode()) { return (0, "");}

  # unless we are running on linux, exit.
  #unless($^O eq "linux"){      
  #  exit;
  # }

  # check supported snmp package
  my $cmd;
  my @snmpPkg = `/bin/rpm -qa | grep snmp`;
  my $pkginstalled = grep(/net-snmp/, @snmpPkg);

  if ($pkginstalled) {
    my ($ret, $err)=configSNMP();
    if ($ret != 0) { return ($ret, $err);}
  } else {
    return (1, "net-snmp is not installed")
  }

  #enable bmcs if any
  configBMC(1);

  #enable MMAs if any
  configMPA(1);

  #configure mail to enabling receiving mails from trap handler
  configMail();

  return (0, "started")
}

#--------------------------------------------------------------------------------
=head3    configBMC
      This function configures BMC to setup the snmp destination, enable/disable
    PEF policy table entry number 1. 
    Arguments:
      actioon -- 1 enable PEF policy table. 0 disable PEF policy table.
    Returns:
      (return code, message)      
=cut
#--------------------------------------------------------------------------------
sub configBMC {
  my $action=shift;

  my $ret_text="";
  my $ret_val=0;

  #the identification of this node
  my @hostinfo=xCAT::Utils->determinehostname();
  %iphash=();
  foreach(@hostinfo) {$iphash{$_}=1;}
  my $isSV=xCAT::Utils->isServiceNode();

  
  my %masterhash=();
  my @node_a=();
  my $nrtab = xCAT::Table->new('noderes');
  my $table=xCAT::Table->new("ipmi");
  if ($table) {
    my @tmp1=$table->getAllNodeAttribs(['node','bmc']);
    if (defined(@tmp1) && (@tmp1 > 0)) {
      foreach(@tmp1) {
        my $node=$_->{node};
        my $bmc=$_->{bmc};
        
        my $monserver;
        my $tent  = $nrtab->getNodeAttribs($node,['monserver', 'servicenode']);
        if ($tent) {
	  if ($tent->{monserver}) {  $monserver=$tent->{monserver}; }
          elsif ($tent->{servicenode})  {  $monserver=$tent->{servicenode}; }
        } 

        if ($monserver) { 
          if (!$iphash{$monserver}) { next;} #skip if has sn but not localhost
        } else { 
          if ($isSV) { next; } #skip if does not have sn but localhost is a sn
        }
        
        push(@node_a, $node);

        # find the master node and add the node in the hash
        $master=xCAT::Utils->GetMasterNodeName($node); #should we use $bmc?
        if(exists($masterhash{$master})) {
	  my $ref=$masterhash{$master};
          push(@$ref, $node); 
	} else { $masterhash{$master}=[$node]; } 
      } #foreach
    }
    $table->close();
  }
  $nrtab->close();       

  if (@node_a==0){ return ($ret_val, $ret_text);} #nothing to handle

  #now doing the real thing: enable PEF alert policy table
  my $noderange=join(',',@node_a );
  my $actionstring="en";
  if ($action==0) {$actionstring="dis";}
  my $result = `XCATBYPASS=Y rspconfig $noderange alert=$actionstring 2>&1`;
  if ($?) {
     xCAT::MsgUtils->message('S', "[mon]: Changeing SNMP PEF policy for IPMI nodes $noderange:\n  $result\n");
     $ret_tex .= "Changeing SNMP PEF policy for IPMI nodes $noderange:\n  $result\n";
  } 

  #setup the snmp destination
  if ($action==1) {
    foreach (keys(%masterhash)) {
      my $ref2=$masterhash{$_};
      if (@$ref2==0) { next;}
      my $nr2=join(',', @$ref2);
      my $result2 = `XCATBYPASS=Y rspconfig $nr2 snmpdest=$_ 2>&1`;
      if ($?) {
         xCAT::MsgUtils->message('S', "[mon]: Changing SNMP destination for IPMI nodes $nr2:\n  $result2\n");
	 $ret_tex .= "Changing SNMP destination for IPMI nodes $nr2:\n  $result2\n";
      }
    }
  }

  return ($ret_val, $ret_text);
  
}


#--------------------------------------------------------------------------------
=head3    configMPA
      This function configures Blade Center Management Module to setup the snmp destination, 
      enable/disable remote alert notification. 
    Arguments:
      actioon -- 1 enable remote alert notification. 0 disable remote alert notification.
    Returns:
      (return code, message)      
=cut
#--------------------------------------------------------------------------------
sub configMPA {
  my $action=shift;

  my $ret_val=0;
  my $ret_text="";

  #the identification of this node
  my @hostinfo=xCAT::Utils->determinehostname();
  %iphash=();
  foreach(@hostinfo) {$iphash{$_}=1;}
  my $isSV=xCAT::Utils->isServiceNode();

  my %mpa_hash=();
  my %masterhash=();
  my @node_a=();
  my $nrtab = xCAT::Table->new('noderes');
  my $table=xCAT::Table->new("mp");
  if ($table) {
    my @tmp1=$table->getAllNodeAttribs(['mpa']);
    if (defined(@tmp1) && (@tmp1 > 0)) {
      foreach(@tmp1) {
        my $mpa=$_->{mpa};
        
        if ($mpa_hash{$mpa}) { next;} #already handled

        $mpa_hash{$mpa}=1;
        
        my $monserver;
        my $tent  = $nrtab->getNodeAttribs($mpa,['monserver', 'servicenode']);
        if ($tent) {
	  if ($tent->{monserver}) {  $monserver=$tent->{monserver}; }
          elsif ($tent->{servicenode})  {  $monserver=$tent->{servicenode}; }
        } 

        if ($monserver) { 
          if (!$iphash{$monserver}) { next;} #skip if has sn but not localhost
        } else { 
          if ($isSV) { next; } #skip if does not have sn but localhost is a sn
        }
        
        push(@node_a, $mpa);

        # find the master node and add the node in the hash
        $master=xCAT::Utils->GetMasterNodeName($mpa); #should we use $bmc?
        if(exists($masterhash{$master})) {
	  my $ref=$masterhash{$master};
          push(@$ref, $mpa); 
	} else { $masterhash{$master}=[$mpa]; } 
      } #foreach
    }
    $table->close();
  }
  $nrtab->close();       

  if (@node_a==0){ return ($ret_val, $ret_text);} #nothing to handle

  #now doing the real thing: enable PEF alert policy table
  my $noderange=join(',',@node_a );
  #print "noderange=@noderange\n";
  my $actionstring="en";
  if ($action==0) {$actionstring="dis";}
  my $result = `XCATBYPASS=Y rspconfig $noderange alert=$actionstring 2>&1`;
  if ($?) {
     xCAT::MsgUtils->message('S', "[mon]: Changeing SNMP remote alert profile for Blade Center MM $noderange:\n  $result\n");
     $ret_text .= "Changeing SNMP remote alert profile for Blade Center MM $noderange:\n  $result\n";
  } 

  #setup the snmp destination
  if ($action==1) {
    foreach (keys(%masterhash)) {
      my $ref2=$masterhash{$_};
      if (@$ref2==0) { next;}
      my $nr2=join(',', @$ref2);
      my $result2 = `XCATBYPASS=Y rspconfig $nr2 snmpdest=$_ 2>&1`;
      if ($?) {
         xCAT::MsgUtils->message('S', "[mon]: Changing SNMP destination for Blade Center MM $nr2:\n  $result2\n");
         $ret_text .= "Changing SNMP destination for Blade Center MM $nr2:\n  $result2\n";  
      }
    }
  }

  return ($ret_val, $ret_text);
}


#--------------------------------------------------------------------------------
=head3    configSNMP
      This function puts xcat_traphanlder into the snmptrapd.conf file and
      restarts the snmptrapd with the new configuration.
    Arguments:
      none.
    Returns:
      (return code, message)      
=cut
#--------------------------------------------------------------------------------
sub configSNMP {
  my $cmd;
  # now move /usr/share/snmptrapd.conf to /usr/share/snmptrapd.conf.orig
  # if it exists.
  if (-f "/usr/share/snmp/snmptrapd.conf"){
  
    # if the file exists and has references to xcat_traphandler then
    # there is nothing that needs to be done.
    `/bin/grep  xcat_traphandler /usr/share/snmp/snmptrapd.conf > /dev/null`;

    # if the return code is 1, then there is no xcat_traphandler
    # references and we need to put them in.
    if($? >> 8){     
      # back up the original file.
      `/bin/cp -f /usr/share/snmp/snmptrapd.conf /usr/share/snmp/snmptrapd.conf.orig`;

      # if the file exists and does not have  "authCommunity execute public" then add it.
      open(FILE1, "</usr/share/snmp/snmptrapd.conf");
      open(FILE, ">/usr/share/snmp/snmptrapd.conf.tmp");
      my $found=0;
      while (readline(FILE1)) {
	 if (/\s*authCommunity.*public/) {
	   $found=1;
           if (!/\s*authCommunity\s*.*execute.*public/) {
             s/authCommunity\s*(.*)\s* public/authCommunity $1,execute public/;  #modify it to have execute if found
	   }
	 }
	 print FILE $_;
      }

      if (!$found) {
        print FILE "authCommunity execute public\n"; #add new one if not found
      }
 
      # now add the new traphandle commands:
      print FILE "traphandle default $::XCATROOT/sbin/xcat_traphandler\n";

      close($handle);
      close(FILE);
      `mv -f /usr/share/snmp/snmptrapd.conf.tmp /usr/share/snmp/snmptrapd.conf`;
    }
  }
  else {     # The snmptrapd.conf file does not exists
    # create the file:
    open($handle, ">/usr/share/snmp/snmptrapd.conf");
    print $handle "authCommunity execute public\n";
    print $handle "traphandle default $::XCATROOT/sbin/xcat_traphandler\n";
    close($handle);
  }

  # TODO: put the mib files to /usr/share/snmp/mibs

  # get the PID of the currently running snmptrapd if it is running.
  # then stop it and restart it again so that it reads our new
  # snmptrapd.conf configuration file. Then the process
  chomp(my $pid= `/bin/ps -ef | /bin/grep snmptrapd | /bin/grep -v grep | /bin/awk '{print \$2}'`);
  if($pid){
    `/bin/kill -9 $pid`;
  }
  # start it up again!
  system("/usr/sbin/snmptrapd -m ALL");

  # get the PID of the currently running snmpd if it is running.
  # if it's running then we just leave.  Otherwise, if we don't get A PID, then we
  # assume that it isn't running, and start it up again!
  chomp(my $pid= `/bin/ps -ef | /bin/grep snmpd | /bin/grep -v grep | /bin/awk '{print \$2}'`);
  unless($pid){
    # start it up again!
    system("/usr/sbin/snmpd");         
  }

  return (0, "started");
}

#--------------------------------------------------------------------------------
=head3    configMail
      This function adds a "alerts" mail aliase so that the mail notification 
      from the trap handler can be received. It the alerts already exists, this 
      function does nothing. 
      TODO: configure mail servers on MS to forward mails to MS 
    Arguments:
      none
    Returns:
      (return code, message)      
=cut
#--------------------------------------------------------------------------------
sub configMail {
  #check if "alerts" is in the /etc/aliases file
  if (-f "/etc/aliases"){ 
    # if the file exists, check if alerts is in
    `/bin/grep -e ^alerts /etc/aliases > /dev/null`;
    if ($? ==0) { return (0, "") };
  }
  
  #make a alerts aliase, forwarding the mail to the root of local host.
  `echo "alerts:  root" >> /etc/aliases`; 

  #make it effective
  `newaliases`;

  return (0, "");
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
  #print "snmpmon::stop called\n";

  # do not turn it on on the service node
  #if (xCAT::Utils->isServiceNode()) { return (0, "");}

  #disable MMAs if any
  configMPA(0);

  #disable BMC so that it stop senging alerts (PETs) to this node
  configBMC(0);
 
  if (-f "/usr/share/snmp/snmptrapd.conf.orig"){
    # copy back the old one
    `mv -f /usr/share/snmp/snmptrapd.conf.orig /usr/share/snmp/snmptrapd.conf`;
  } else {
    if (-f "/usr/share/snmp/snmptrapd.conf"){ 

      # if the file exists, delete all entries that have xcat_traphandler
      my $cmd = "grep -v  xcat_traphandler /usr/share/snmp/snmptrapd.conf "; 
      $cmd .= "> /usr/share/snmp/snmptrapd.conf.unconfig ";         
      `$cmd`;     

      # move it back to the snmptrapd.conf file.                     
      `mv -f /usr/share/snmp/snmptrapd.conf.unconfig /usr/share/snmp/snmptrapd.conf`; 
    }
  }

  # now check to see if the daemon is running.  If it is then we need to resart or stop?
  # it with the new snmptrapd.conf file that will not forward events to RMC.
  chomp(my $pid= `/bin/ps -ef | /bin/grep snmptrapd | /bin/grep -v grep | /bin/awk '{print \$2}'`);
  if($pid){
    `/bin/kill -9 $pid`;
    # start it up again!
    #system("/usr/sbin/snmptrapd");
  }

  return (0, "stopped");
}




#--------------------------------------------------------------------------------
=head3    supportNodeStatusMon
    This function is called by the monitorctrl module to check
    if SNMP can help monitoring and returning the node status.
    SNMP does not support this function.
    
    Arguments:
        none
    Returns:
         1  
=cut
#--------------------------------------------------------------------------------
sub supportNodeStatusMon {
  return 0;
}



#--------------------------------------------------------------------------------
=head3   startNodeStatusMon
    This function is called by the monitorctrl module to tell
    SNMP to start monitoring the node status and feed them back
    to xCAT. SNMP does not have this support.

    Arguments:
       None.
    Returns:
        (return code, message)

=cut
#--------------------------------------------------------------------------------
sub startNodeStatusMon {
  return (1, "This function is not supported.");
}


#--------------------------------------------------------------------------------
=head3   stopNodeStatusMon
    This function is called by the monitorctrl module to tell
    SNMP to stop feeding the node status info back to xCAT. 
    SNMP does not support this function.

    Arguments:
        none
    Returns:
        (return code, message)
=cut
#--------------------------------------------------------------------------------
sub stopNodeStatusMon {
  return (1, "This function is not supported.");
}


#--------------------------------------------------------------------------------
=head3    addNodes
      This function adds the nodes into the  SNMP domain.
    Arguments:
      nodes --nodes to be added. It is a pointer to an array with each element
        being a ref to an array of [nodes, nodetype, status]. For example: 
          [['node1', 'osi', 'active'], ['node2', 'switch', 'booting']..] 
    Returns:
       (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub addNodes {
  print "snmpmon::addNodes\n";
  $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::snmpmon/) {
    $noderef=shift;
  }

  foreach(@$noderef) {
    my $node_info=$_;
    print "    node=$node_info->[0], nodetype=$node_info->[1], status=$node_info->[2]\n";
  }
    
  return (0, "ok");
}

#--------------------------------------------------------------------------------
=head3    removeNodes
      This function removes the nodes from the SNMP domain.
    Arguments:
      nodes --nodes to be removed. It is a pointer to an array with each element
        being a ref to an array of [nodes, nodetype, status]. For example: 
          [['node1', 'osi', 'active'], ['node2', 'switch', 'booting']..] 
    Returns:
       (error code, error message)
=cut
#--------------------------------------------------------------------------------
sub removeNodes {
    print "snmpmon::removeNodes\n";
  $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::snmpmon/) {
    $noderef=shift;
  }

  foreach(@$noderef) {
    my $node_info=$_;
    print "    node=$node_info->[0], nodetype=$node_info->[1], status=$node_info->[2]\n";
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
    snmpmon sets up the snmptrapd on the management server to receive SNMP
    traps for different nodes. It also sets the trap destination for Blade 
    Center Management Module, RSA II, IPMIs that are managed by the xCAT cluster. 
    xCAT has categorized some events into different event priorities (critical, 
    warning and informational) based on the MIBs we know such as MM, RSA II and 
    IPMI. All the unknown events are categorized as 'warning'. By default, 
    the xCAT trap handler will log all events into the syslog and only
    email the critical and the warning events to the mail alias called 'alerts'. 
    You can use the settings to override the default behavior.
    Use command 'monstart snmpmon' to star monitoring and 'monstop snmpmon' 
    to stop it. 
  Settings:
    ignore:  specifies the events that will be ignored. It's a comma separated 
        pairs of oid=value. For example, 
        BLADESPPALT-MIB::spTrapAppType=4,BLADESPPALT-MIB::spTrapAppType=4.
    email:  specifies the events that will get email notification.
    log:    specifies the events that will get logged.
    runcmd: specifies the events that will be passed to the user defined scripts.
    cmds:   specifies the command names that will be invoked for the events 
            specified in the runcmd row.
    
    Special keywords for specifying events:
      All -- all events.
      None -- none of the events.
      Critical -- all critical events.
      Warning -- all warning events.
      Informational -- all informational events.

    For example, you can have the following setting:
      email  CRITICAL,BLADESPPALT-MIB::pTrapPriority=4
      This means send email for all the critical events and the BladeCenter 
      system events.\n"  
}

