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


print "xCAT_monitoring::snmpmon loaded\n";
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
      monservers --A hash reference keyed by the monitoring server nodes 
         and each value is a ref to an array of [nodes, nodetype, status] arrays  
         monitored by the server. So the format is:
           {monserver1=>[['node1', 'osi', 'active'], ['node2', 'switch', 'booting']...], ...}   
    Returns:
      (return code, message)      
=cut
#--------------------------------------------------------------------------------
sub start {
  print "snmpmon::start called\n";

  $noderef=shift;
  if ($noderef =~ /xCAT_monitoring::snmpmon/) {
    $noderef=shift;
  }

  # do not turn it on on the service node
  if (xCAT::Utils->isServiceNode()) { return (0, "");}

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

  return (0, "started")
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
  print "pid=$pid here\n";
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
  print "snmpmon::stop called\n";

  # do not turn it on on the service node
  if (xCAT::Utils->isServiceNode()) { return (0, "");}
 
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
  print "pid=$pid\n";
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
      monservers --A hash reference keyed by the monitoring server nodes 
         and each value is a ref to an array of [nodes, nodetype, status] arrays  
         monitored by the server. So the format is:
           {monserver1=>[['node1', 'osi', 'active'], ['node2', 'switch', 'booting']...], ...}   
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
      nodes --nodes to be added. It is a  hash reference keyed by the monitoring server 
        nodes and each value is a ref to an array of [nodes, nodetype, status] arrays  monitored 
        by the server. So the format is:
          {monserver1=>[['node1', 'osi', 'active'], ['node2', 'switch', 'booting']...], ...} 
      verbose -- verbose mode. 1 for yes, 0 for no.
    Returns:
       none
=cut
#--------------------------------------------------------------------------------
sub addNodes {
    
  return 0;
}

#--------------------------------------------------------------------------------
=head3    removeNodes
      This function removes the nodes from the SNMP domain.
    Arguments:
      nodes --nodes to be removed. It is a hash reference keyed by the monitoring server 
        nodes and each value is a ref to an array of [nodes, nodetype, status] arrays  monitored 
        by the server. So the format is:
        {monserver1=>[['node1', 'osi', 'active'], ['node2', 'switch', 'booting']...], ...} 
      verbose -- verbose mode. 1 for yes, 0 for no.
    Returns:
       none
=cut
#--------------------------------------------------------------------------------
sub removeNodes {

  return 0;
}

