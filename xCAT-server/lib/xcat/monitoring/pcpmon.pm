#!/usr/bin/env perl 
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_monitoring::pcpmon;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::NodeRange;
use Sys::Hostname;
use Socket;
use xCAT::Utils;
use xCAT::GlobalDef;
use xCAT_monitoring::monitorctrl;
use xCAT::MsgUtils;
use strict;
use warnings;
1;

#-------------------------------------------------------------------------------
=head1  xCAT_monitoring:pcpmon  
=head2    Package Description
  xCAT monitoring plugin package to handle PCP monitoring.
=cut
#-------------------------------------------------------------------------------

#--------------------------------------------------------------------------------
=head3    start
      This function gets called by the monitorctrl module when xcatd starts and 
      when monstart command is issued by the user. It starts the daemons and 
      does necessary startup process for the PCP monitoring. 
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
sub start 
{ # starting sub routine
    print "pcp::start called\n";
    my $noderef=shift;
    if ($noderef =~ /xCAT_monitoring::pcpmon/)
    {
	$noderef=shift;
    }
    my $scope=shift;
    my $callback=shift;
    
    my $cmd="$::XCATROOT/sbin/pcp_collect";
    #figure out the ping-intercal setting
    my $value=5; #default
    my %settings=xCAT_monitoring::monitorctrl->getPluginSettings("pcpmon");
    
    my $reading;
    if (exists($settings{'ping-interval'})) {
      $reading=$settings{'ping-interval'};;
      if ($reading>0) { $value=$reading;}
    }
    
    #create the cron job, it will run the command every 5 minutes(default and can be changed).
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
	    $rsp->{data}->[0]="$localhostname: started. Refresh interval is $value minute(s)";
	    $callback->($rsp);
	}
	#return (0, "started"); 
    }
    else {
	if ($callback) {
	    my $rsp={};
	    $rsp->{data}->[0]="$localhostname: $code  $msg";
	    $callback->($rsp);
	}
	
	#return ($code, $msg);
    }
    
    my $localhost=hostname();
    my $res_pcp = `/etc/init.d/pcp restart 2>&1`;
    if ($?)
    {
	if ($callback)
	{
	    my $resp={};
	    $resp->{data}->[0]="$localhost: PCP not started successfully: $res_pcp \n";
	    $callback->($resp);
	}  
	else
	{
            xCAT::MsgUtils->message('S', "[mon]: $res_pcp \n");
	}
	
	return(1,"PCP not started successfully. \n");
    }
    
    if ($scope)
    { #opening if scope
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

	#identification of this node
	my @hostinfo=xCAT::NetworkUtils->determinehostname();
	my $isSV=xCAT::Utils->isServiceNode();
	my %iphash=();	
	foreach(@hostinfo) {$iphash{$_}=1;}
	if (!$isSV) { $iphash{'noservicenode'}=1;}
        
	my @children;
	foreach my $key (keys (%$pPairHash))
	{ #opening foreach1
	    my @key_a=split(':', $key);
	    if (! $iphash{$key_a[0]}) {  next; }
	    my $mon_nodes=$pPairHash->{$key};
    
	    foreach(@$mon_nodes)
	    { #opening foreach2
		my $node=$_->[0];
		my $nodetype=$_->[1];
		if (($nodetype) && ($nodetype =~ /$::NODETYPE_OSI/))
		{ 
                    push(@children,$node);
		}
	    } #closing foreach2
	}  #closing foreach1
	my $rec = join(',',@children);
	my $result=`XCATBYPASS=Y $::XCATROOT/bin/xdsh  $rec /etc/init.d/pcp restart 2>&1`;
	if ($result)
        {
	    if ($callback)
	    {
		my $resp={};
		$resp->{data}->[0]="$localhost: $result\n";
		$callback->($resp);
	    }
	    else 
	    {
		xCAT::MsgUtils->message('S', "[mon]: $result\n");
	    }
        }
	
    } #closing if scope
    
    if ($callback)
    {
	my $resp={};
	$resp->{data}->[0]="$localhost: started. \n";
	$callback->($resp);
    }
    
    return (0, "started");
    
} # closing sub routine
#--------------------------------------------------------------
=head3    config
      This function configures the cluster for the given nodes. This function is called 
      when moncfg command is issued or when xcatd starts on the service node. 
       Returns: 1
=cut 
#--------------------------------------------------------------
sub config
   {
    return 1;
   }


#--------------------------------------------------------------
=head3    deconfig
      	This function de-configures the cluster for the given nodes. This function is called 
	when mondecfg command is issued by the user. 
      Returns: 1
=cut 
#--------------------------------------------------------------
sub deconfig
   {
     return 1;
   }


#--------------------------------------------------------------------------------
=head3    stop
      This function gets called by the monitorctrl module when
      xcatd stops or when monstop command is issued by the user.
      It stops the monitoring on all nodes, stops
      the daemons and does necessary cleanup process for the
      PCP monitoring.
    Arguments:
       p_nodes -- a pointer to an arrays of nodes to be stopped for monitoring. null means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only.
                2 means both monservers and nodes,
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
      (return code, message)
      if the callback is set, use callback to display the status and error.
=cut


#--------------------------------------------------------------------------------
sub stop
    { # starting sub routine
            print "pcpmon::stop called\n";
      my $noderef=shift;
      if ($noderef =~ /xCAT_monitoring::pcpmon/)
        {
         $noderef=shift;
        }
      my $scope=shift;
      my $callback=shift;

        my $job="$::XCATROOT/sbin/pcp_collect";
  my ($code, $msg)=xCAT::Utils::remove_cron_job($job);
  my $localhostname=hostname(); 
  if ($code==0) { 
    if ($callback) {
      my $rsp={};
      $rsp->{data}->[0]="$localhostname: stopped.";
      $callback->($rsp);
    }
    #return (0, "stopped"); 
	}
  else {
    if ($callback) {
      my $rsp={};
      $rsp->{data}->[0]="$localhostname: $code  $msg";
      $callback->($rsp);
    }
    #return ($code, $msg); 
  } 


      my $localhost=hostname();
      my $res_pcp = `/etc/init.d/pcp stop 2>&1`;
      if ($?)
       {
         if ($callback)
            {
             my $resp={};
             $resp->{data}->[0]="$localhost: PCP not stopped successfully: $res_pcp \n";
             $callback->($resp);
            }
          else
           {
            xCAT::MsgUtils->message('S', "[mon]: $res_pcp \n");
           }

           return(1,"PCP not stopped successfully. \n");
        }

        
        if ($scope)
         { #opening if scope
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


           #identification of this node
           my @hostinfo=xCAT::NetworkUtils->determinehostname();
           my $isSV=xCAT::Utils->isServiceNode();
           my %iphash=();
           foreach(@hostinfo) {$iphash{$_}=1;}
           if (!$isSV) { $iphash{'noservicenode'}=1;}

           my @children;
           foreach my $key (keys (%$pPairHash))
            { #opening foreach1
              my @key_a=split(':', $key);
	      if (! $iphash{$key_a[0]}) {  next; }
              my $mon_nodes=$pPairHash->{$key};

              foreach(@$mon_nodes)
                { #opening foreach2
                  my $node=$_->[0];
                  my $nodetype=$_->[1];
                  if (($nodetype) && ($nodetype =~ /$::NODETYPE_OSI/))
                   {
                    push(@children,$node);
                   }
                } #closing foreach2
            }  #closing foreach1
          my $rec = join(',',@children);
       my $result=`XCATBYPASS=Y $::XCATROOT/bin/xdsh  $rec /etc/init.d/pcp stop 2>&1`;
       if ($result)
        {
         if ($callback)
           {
            my $resp={};
            $resp->{data}->[0]="$localhost: $result\n";
            $callback->($resp);
           }
        else
           {
            xCAT::MsgUtils->message('S', "[mon]: $result\n");
           }
        }

      } #closing if scope

   if ($callback)
    {
     my $resp={};
     $resp->{data}->[0]="$localhost: stopped. \n";
     $callback->($resp);
    }

 return (0, "stopped");
 }


#--------------------------------------------------------------------------------
=head3    supportNodeStatusMon
    This function is called by the monitorctrl module to check
    if PCP can help monitoring and returning the node status.
    
    Arguments:
        none
    Returns:
         1  
=cut

#--------------------------------------------------------------------------------
sub supportNodeStatusMon {
  #print "pcpmon::supportNodeStatusMon called\n";
  return 1;
}



#--------------------------------------------------------------------------------
=head3   startNodeStatusMon
    This function is called by the monitorctrl module to tell
    PCP to start monitoring the node status and feed them back
    to xCAT. PCP will start setting up the condition/response 
    to monitor the node status changes.  

    Arguments:
       None.
    Returns:
        (return code, message)

=cut
#--------------------------------------------------------------------------------
sub startNodeStatusMon {
  #print "pcpmon::startNodeStatusMon called\n";
  return (0, "started");
}


#--------------------------------------------------------------------------------
=head3   stopNodeStatusMon
    This function is called by the monitorctrl module to tell
    PCP to stop feeding the node status info back to xCAT. It will
    stop the condition/response that is monitoring the node status.

    Arguments:
        none
    Returns:
        (return code, message)
=cut
#--------------------------------------------------------------------------------
sub stopNodeStatusMon {
  #print "pcpmon::stopNodeStatusMon called\n";
  return (0, "stopped");
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
sub getDescription 
{
  return "Description: This plugin will help interface the xCAT cluster with PCP monitoring software 
       ping-interval:  the number of minutes between  the metric collection operation. 
        The default value is 5 \n ";
}
