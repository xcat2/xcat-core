#!/usr/bin/env perl 
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_monitoring::gangliamon;
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
=head1  xCAT_monitoring:gangliamon  
=head2    Package Description
  xCAT monitoring plugin package to handle Ganglia monitoring.
=cut
#-------------------------------------------------------------------------------

#--------------------------------------------------------------------------------
=head3    start
      This function gets called by the monitorctrl module when xcatd starts and 
      when monstart command is issued by the user. It starts the daemons and 
      does necessary startup process for the Ganglia monitoring. 
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
      print "gangliamon::start called\n";
      my $noderef=shift;
      if ($noderef =~ /xCAT_monitoring::gangliamon/)
        {
         $noderef=shift;
        }
      my $scope=shift;
      my $callback=shift;
      my $localhost=hostname();
      my $OS=`uname`;
	  my $res_gmond;
      if ( $OS =~ /AIX/ )
      {
       $res_gmond = `/etc/rc.d/init.d/gmond restart 2>&1`;
      }
      else
      {
       $res_gmond = `/etc/init.d/gmond restart 2>&1`;
      }
      if ($?)
       {
         if ($callback)
            {
             my $resp={};
             $resp->{data}->[0]="$localhost: Ganglia Gmond not started successfully: $res_gmond \n";
             $callback->($resp);
            }  
          else
           {
            xCAT::MsgUtils->message('S', "[mon]: $res_gmond \n");
           }
 
           return(1,"Ganglia Gmond not started successfully. \n");
        }
 
		my $res_gmetad;
      if ( $OS =~ /AIX/ )
      {
       $res_gmetad = `/etc/rc.d/init.d/gmetad restart 2>&1`;
      }
      else
      {
       $res_gmetad = `/etc/init.d/gmetad restart 2>&1`;
      }

        if ($?)
         {
           if ($callback)
            {
             my $resp={};
             $resp->{data}->[0]="$localhost: Ganglia Gmetad not started successfully:$res_gmetad \n";
             $callback->($resp);
             }
           else
            {
             xCAT::MsgUtils->message('S', "[mon]: $res_gmetad \n");
            }

           return(1,"Ganglia Gmetad not started successfully. \n");
         }
   

    
        if ($scope)
         { #opening if scope
           my $OS=`uname`;
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
	   my @hostinfo=xCAT::Utils->determinehostname();
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
          my $rec = undef;
          my $result = undef;
          if(exists($children[0])){
            $rec = join(',',@children);
          }
      if($rec){
        if ( $OS =~ /AIX/ )
        {
         $result = `XCATBYPASS=Y $::XCATROOT/bin/xdsh  $rec /etc/rc.d/init.d/gmond restart 2>&1`;
        }
        else
        {
         $result = `XCATBYPASS=Y $::XCATROOT/bin/xdsh  $rec /etc/init.d/gmond restart 2>&1`;
        }
      }

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
      when moncfg command is issued or when xcatd starts on the service node. It will 
      configure the cluster to include the given nodes within the monitoring domain. This 
      calls two other functions called as confGmond and confGmetad which are used for configuring
      the Gmond and Gmetad configuration files respectively.
    Arguments:
       p_nodes -- a pointer to an arrays of nodes to be added for monitoring. none means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only. 
                2 means localhost and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
       (error code, error message)
=cut 
#--------------------------------------------------------------
sub config
   {
     print "gangliamon:config called\n";
     my $noderef=shift;
     if ($noderef =~ /xCAT_monitoring::gangliamon/) {
     $noderef=shift;
     }
     my $scope=shift;
     my $callback=shift;
     
     confGmond($noderef,$scope,$callback);
     confGmetad($noderef,$scope,$callback);
   }


#--------------------------------------------------------------
=head3    confGmond
	This function is called by the config() function. It configures the Gmond 
       configuration files for the given nodes
    Arguments:
       p_nodes -- a pointer to an arrays of nodes to be added for monitoring. none means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only. 
                2 means localhost and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns: none
=cut
#--------------------------------------------------------------

sub confGmond
{
    print "gangliamon:confGmond called \n";
    no warnings;
    #  no strict 'vars';
    my $noderef=shift;
    if ($noderef =~ /xCAT_monitoring::gangliamon/) {
		$noderef=shift;
    }

    my $scope=shift;
    my $callback=shift;
    my $configure_file = '';
    my $localhost=hostname();
    chomp(my $hostname = `hostname`);
    
    #version 3.1.0
    if (-e "/etc/ganglia/gmond.conf"){
    	$configure_file = '/etc/ganglia/gmond.conf';
	}
	#version 3.0.7
	elsif (-e "/etc/gmond.conf"){
		$configure_file = '/etc/gmond.conf';
	}
	#non should install
	else
	{
		if ($callback){
			my $resp={};
			$resp->{data}->[0]="gangliamon: Please install the Ganglia.";
			$callback->($resp);	
		}
		else{
			xCAT::MsgUtils->message('E', "gangliamon: Please install the Ganglia. \n");
		}
		return;
	}

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
    my @hostinfo=xCAT::Utils->determinehostname();
    my $isSV=xCAT::Utils->isServiceNode();
    my %iphash=();
    foreach(@hostinfo) {$iphash{$_}=1;}
    if (!$isSV) { $iphash{'noservicenode'}=1;}

    #check the configure file
	`/bin/grep "xCAT gmond settings done" $configure_file`;
	if($?) { #openinf if ?
	    if($callback) {
			my $resp={};
			$resp->{data}->[0]="$localhost: $?";
			$callback->($resp);
		}
		else {
			xCAT::MsgUtils->message('S', "Gmond not configured $? \n"); 
		}
	    
        #backup the original file
	    `/bin/cp -f $configure_file $configure_file.orig`;
	    open(FILE, "+>$configure_file.tmp");
	    my $fname = $configure_file;
	    unless ( open( CONF, $fname ))
	    {
	        return(0);
	    }
	    
	    my @raw_data = <CONF>;
	    close( CONF );
	    my $str = join('', @raw_data);
	    $str =~ s/setuid = yes/setuid = no/;
	    $str =~ s/bind/#bind/;
	    $str =~ s/mcast_join = .*/host = $hostname/;

	    # my @children;
	    foreach my $key (keys (%$pPairHash))
	    { #opening for each
			my @key_a=split(':', $key);
			if (! $iphash{$key_a[0]}) {  next; }
			my $pattern = '^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})';
			if ( $key_a[0]!~/$pattern/ ){
			    my $cluster = $key_a[0];
			    if (-e "/etc/xCATSN")
			    {
					$str =~ s/name = "unspecified"/name="$cluster"/;
			    }
	        }
	    } #closing for each
	    
	    $str =~ s/name = "unspecified"/name="$hostname"/;
	    $str =~ s/mcast_join/# mcast_join/;
	    print FILE $str;
	    print FILE "# xCAT gmond settings done \n";
	    close(FILE);
	    `/bin/cp -f $configure_file.tmp $configure_file`;
	    
	} #closing if ?
 
    if ($scope)
    {#opening if scope of confGmond
		my @children;
	    my $install_root = xCAT::Utils->getInstallDir();
		foreach my $key (keys (%$pPairHash)) { #opening for each
		    my @key_a=split(':', $key);
		    if (! $iphash{$key_a[0]}) {  next; }
		    my $mon_nodes=$pPairHash->{$key};
		    
		    foreach(@$mon_nodes)
		    { #opening foreach2
				my $node=$_->[0];
				my $nodetype=$_->[1];
				#print "node=$node, nodetype=$nodetype\n";
				if (($nodetype) && ($nodetype =~ /$::NODETYPE_OSI/))
				{ 
				    push(@children,$node);
				}
		    } #closing foreach2
		    
		    my $node = join(',',@children);
		    my $res_cp = `XCATBYPASS=Y $::XCATROOT/bin/xdcp $node $install_root/postscripts/confGang /tmp 2>&1`;
		    if($?)
		    { #openinf if ?
				if($callback) {
				    my $resp={};
				    $resp->{data}->[0]="$localhost: $res_cp";
				    $callback->($resp);
				} 
				else {
					xCAT::MsgUtils->message('S', "Cannot copy confGang into /tmp: $res_cp \n"); 
				}
		    } #closing if ?
		    
		    my $res_conf;
		    if ( $key_a[0] =~ /noservicenode/ ){
				$res_conf=`XCATBYPASS=Y $::XCATROOT/bin/xdsh $node MONSERVER=$hostname MONMASTER=$key_a[1] /tmp/confGang 2>&1`;
		    }		    
		    else {
				$res_conf=`XCATBYPASS=Y $::XCATROOT/bin/xdsh $node MONSERVER=$key_a[0] MONMASTER=$key_a[1] /tmp/confGang 2>&1`;
		    }
		    if($?)
		    { #openinf if ?
				if($callback) 
				{
				    my $resp={};
				    $resp->{data}->[0]="$localhost: $res_conf";
				    $callback->($resp);
				} 
				else {
					xCAT::MsgUtils->message('S', "Cannot configure gmond in nodes: $res_conf \n"); 
				}
		    } #closing if ?
		} #closing for each
        
    }#closing if scope
} # closing subroutine

#--------------------------------------------------------------
=head3    confGmetad
     	This function is called by the config() function. It configures the Gmetad
       configuration files for the given nodes
    Arguments:
       p_nodes -- a pointer to an arrays of nodes to be added for monitoring. none means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only. 
                2 means localhost and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns : none
=cut
#--------------------------------------------------------------

sub confGmetad
  {
    print "gangliamon:confGmetad called \n";
	# no warnings;
	my $noderef=shift;
    if ($noderef =~ /xCAT_monitoring::gangliamon/) {
	    $noderef=shift;
    }
    my $scope=shift;
    my $callback=shift;
	my $configure_file = '';
    my $localhost=hostname();

    chomp(my $hostname = `hostname`);

    #version 3.1.0
    if (-e "/etc/ganglia/gmond.conf"){
    	$configure_file = '/etc/ganglia/gmond.conf';
	}
	#version 3.0.7
	elsif (-e "/etc/gmond.conf"){
		$configure_file = '/etc/gmond.conf';
	}
	#non should install
	else
	{
		return;
	}
	
	`/bin/grep "xCAT gmetad settings done" $configure_file`;

	if($?)
	{ #openinf if ?
		if($callback) {
			my $resp={};
			$resp->{data}->[0]="$localhost: $?";
			$callback->($resp);
		} 
		else {   
			xCAT::MsgUtils->message('S', "Gmetad not configured $? \n"); 
		}
		
		# backup the original file
		`/bin/cp -f $configure_file $configure_file.orig`;

		open(FILE1, "<$configure_file");
		open(FILE, "+>$configure_file.tmp");

		while (readline(FILE1))
		{
			# print STDERR "READ = $_\n";
			s/data_source/#data_source/g;
			# print STDERR "POST-READ = $_\n";
			print FILE $_;
		}
		close(FILE1);
		close(FILE);
		`/bin/cp -f $configure_file.tmp $configure_file`;

		open(OUTFILE,"+>>$configure_file")
		or die ("Cannot open file \n"); 
		print(OUTFILE "# Setting up GMETAD configuration file \n");

		if (-e "/etc/xCATMN")
		{
			print(OUTFILE "data_source \"$hostname\" localhost \n");
		}
		my $noderef=xCAT_monitoring::monitorctrl->getMonHierarchy();
		if (ref($noderef) eq 'ARRAY') {
			if ($callback) {
				my $resp={};
				$resp->{data}->[0]=$noderef->[1];
				$callback->($resp);
			} else {
				xCAT::MsgUtils->message('S', "[mon]: " . $noderef->[1]);
			}
			return (1, "");	
		}


		my @hostinfo=xCAT::Utils->determinehostname();
		my $isSV=xCAT::Utils->isServiceNode();
		my %iphash=();
		foreach(@hostinfo) {$iphash{$_}=1;}
		if (!$isSV) { $iphash{'noservicenode'}=1;}

		my @children;
		my $cluster;
		foreach my $key (keys (%$noderef))
		{
			my @key_g=split(':', $key);
			if (! $iphash{$key_g[0]}) { next;}
			my $mon_nodes=$noderef->{$key};
			my $pattern = '^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})';
			if ( $key_g[0]!~/$pattern/ )
			{ 
				no warnings;
				$cluster = $key_g[0];
			}
			foreach(@$mon_nodes)
			{
				my $node=$_->[0];
				my $nodetype=$_->[1];
				if (($nodetype) && ($nodetype =~ /$::NODETYPE_OSI/))
				{
					push(@children,$node);
				}
			}

		}
		my $num=@children;
		if (-e "/etc/xCATSN")
		{
			print ( OUTFILE "gridname \"$cluster\"\n");
			print ( OUTFILE "data_source \"$cluster\" localhost\n");
			my $master=xCAT::Utils->get_site_Master();
			print ( OUTFILE "trusted_hosts $master\n");
		}
		else
		{
			for (my $j = 0; $j < $num; $j++)
			{
				print ( OUTFILE "data_source \"$children[ $j ]\" $children[ $j ]:8651  \n");
			}
		}
		print(OUTFILE "# xCAT gmetad settings done \n");
		close(OUTFILE);
	} #closing if?
} # closing subrouting


#--------------------------------------------------------------
=head3    deconfig
      	This function de-configures the cluster for the given nodes. This function is called 
	when mondecfg command is issued by the user. This function restores the original Gmond
	and Gmetad configuration files by calling the deconfGmond and deconfGmetad functions 
	respectively.
      
    Arguments:
       p_nodes -- a pointer to an arrays of nodes to be removed for monitoring. none means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means local host only. 
                2 means both local host and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns: none
=cut 
#--------------------------------------------------------------
sub deconfig
   {
     print "gangliamon:deconfig called\n";
     my $noderef=shift;
     if ($noderef =~ /xCAT_monitoring::gangliamon/) {
     $noderef=shift;
     }
     my $scope=shift;
     my $callback=shift;
     
     deconfGmond($noderef,$scope,$callback);
     deconfGmetad($noderef,$scope,$callback);
   }


#--------------------------------------------------------------
=head3    deconfGmond
     This function is called by the deconfig() function. It deconfigures the Gmetad
       configuration files for the given nodes
    Arguments:
       p_nodes -- a pointer to an arrays of nodes to be added for monitoring. none means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only. 
                2 means localhost and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:none
=cut
#--------------------------------------------------------------

sub deconfGmond
  {
    print "gangliamon:deconfGmond called \n";
    no warnings;
    my $noderef=shift;
    if ($noderef =~ /xCAT_monitoring::gangliamon/) {
    $noderef=shift;
    }
    my $scope=shift;
    my $callback=shift;

    my $localhost=hostname();

	 if (-e "/etc/ganglia/gmond.conf")
	  { #opening if V3.1.0
      `/bin/cp -f /etc/ganglia/gmond.conf /etc/ganglia/gmond.conf.save`;
      my $decon_gmond=`/bin/cp -f /etc/ganglia/gmond.conf.orig /etc/ganglia/gmond.conf`;
       if($?)
        { #openinf if ?
          if($callback) {
          my $resp={};
          $resp->{data}->[0]="$localhost:$decon_gmond";
          $callback->($resp);
          } else {   xCAT::MsgUtils->message('S', "Gmond not deconfigured $decon_gmond \n"); } 
        } # closing if ?
	  } #closing if V3.1.0
	  
	 else 
	  { #opening V3.0.7
	   `/bin/cp -f /etc/gmond.conf /etc/gmond.conf.save`;
       my $decon_gmond=`/bin/cp -f /etc/gmond.conf.orig /etc/gmond.conf`;
        if($?)
        { #openinf if ?
          if($callback) {
          my $resp={};
          $resp->{data}->[0]="$localhost:$decon_gmond";
          $callback->($resp);
          } else {   xCAT::MsgUtils->message('S', "Gmond not deconfigured $decon_gmond \n"); } 
        } # closing if?
	  } #closing V3.0.7

      if ($scope)
       {#opening if scope of confGmond
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
        my @hostinfo=xCAT::Utils->determinehostname();
        my $isSV=xCAT::Utils->isServiceNode();
        my %iphash=();
        foreach(@hostinfo) {$iphash{$_}=1;}
        if (!$isSV) { $iphash{'noservicenode'}=1;}

	my @children;
	foreach my $key (keys (%$pPairHash))
        { #opening for each
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

              my $node = join(',',@children);
			  if (-e "/etc/ganglia/gmond.conf")
			  { # opening if V3.1.0
               my $res_sv = `XCATBYPASS=Y $::XCATROOT/bin/xdsh $node /bin/cp -f /etc/ganglia/gmond.conf /etc/ganglia/gmond.conf.save`;

               my $res_cp = `XCATBYPASS=Y $::XCATROOT/bin/xdsh $node /bin/cp -f /etc/ganglia/gmond.conf.orig /etc/ganglia/gmond.conf`;
               if($?)
                { #openinf if ?
                  if($callback) 
                    {
                     my $resp={};
                     $resp->{data}->[0]="$localhost: $res_cp";
                     $callback->($resp);
                    } 
                  else {   xCAT::MsgUtils->message('S', "Gmond not deconfigured: $res_cp \n"); }
                 } #closing if ?
              } # closing if V3.1.0

		     else
			{
               my $res_sv = `XCATBYPASS=Y $::XCATROOT/bin/xdsh $node /bin/cp -f /etc/gmond.conf /etc/gmond.conf.save`;

               my $res_cp = `XCATBYPASS=Y $::XCATROOT/bin/xdsh $node /bin/cp -f /etc/gmond.conf.orig /etc/gmond.conf`;
               if($?)
                { #openinf if ?
                  if($callback) 
                    {
                     my $resp={};
                     $resp->{data}->[0]="$localhost: $res_cp";
                     $callback->($resp);
                    } 
                  else {   xCAT::MsgUtils->message('S', "Gmond not deconfigured: $res_cp \n"); }
                 } #closing if ?
              } # closing if V3.1.0
          } # closing for each
    } # closing if scope

  } # closing subroutine


#--------------------------------------------------------------
=head3    deconfGmetad
     This function is called by the deconfig() function. It deconfigures the Gmetad
       configuration files for the given nodes
    Arguments:
       p_nodes -- a pointer to an arrays of nodes to be added for monitoring. none means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only. 
                2 means localhost and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:none
=cut
#--------------------------------------------------------------

sub deconfGmetad
  {
    print "gangliamon:deconfGmetad called \n";
    no warnings;
    my $noderef=shift;
    if ($noderef =~ /xCAT_monitoring::gangliamon/) {
    $noderef=shift;
    }
    my $scope=shift;
    my $callback=shift;

    my $localhost=hostname();

	 if (-e "/etc/ganglia/gmetad.conf")
	  { #opening V3.1.0
     `/bin/cp -f /etc/ganglia/gmetad.conf /etc/ganglia/gmetad.conf.save`;
     my $decon_gmetad=`/bin/cp -f /etc/ganglia/gmetad.conf.orig /etc/ganglia/gmetad.conf`;
      if($?)
        { #openinf if ?
          if($callback) {
          my $resp={};
          $resp->{data}->[0]="$localhost: $decon_gmetad";
          $callback->($resp);
          } else {   xCAT::MsgUtils->message('S', "Gmetadd not deconfigured $decon_gmetad \n"); } 
        }
	  } #closing V3.1.0

	 else 
	  { #opening V3.0.7
	   `/bin/cp -f /etc/gmetad.conf /etc/gmetad.conf.save`;
       my $decon_gmetad=`/bin/cp -f /etc/gmetad.conf.orig /etc/gmetad.conf`;
       if($?)
        { #openinf if ?
          if($callback) {
          my $resp={};
          $resp->{data}->[0]="$localhost: $decon_gmetad";
          $callback->($resp);
          } else {   xCAT::MsgUtils->message('S', "Gmetadd not deconfigured $decon_gmetad \n"); } 
        }
	  } #closing 3.0.7

   } # closing subroutine

#--------------------------------------------------------------------------------
=head3    stop
      This function gets called by the monitorctrl module when
      xcatd stops or when monstop command is issued by the user.
      It stops the monitoring on all nodes, stops
      the daemons and does necessary cleanup process for the
      Ganglia monitoring.
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
sub stop
    { # starting sub routine
            print "gangliamon::stop called\n";
      my $noderef=shift;
      if ($noderef =~ /xCAT_monitoring::gangliamon/)
        {
         $noderef=shift;
        }
      my $scope=shift;
      my $callback=shift;
      my $localhost=hostname();
	  my $OS=`uname`;
      my $res_gmond;
      if ( $OS =~ /AIX/ )
       {
         $res_gmond = `/etc/rc.d/init.d/gmond stop 2>&1`;
       }
      else
      {
       $res_gmond = `/etc/init.d/gmond stop 2>&1`;
      }

    if ($?)
       {
         if ($callback)
            {
             my $resp={};
             $resp->{data}->[0]="$localhost: Ganglia Gmond not stopped successfully: $res_gmond \n";
             $callback->($resp);
            }
          else
           {
            xCAT::MsgUtils->message('S', "[mon]: $res_gmond \n");
           }

           return(1,"Ganglia Gmond not stopped successfully. \n");
        }

        my $res_gmetad;
      if ( $OS =~ /AIX/ )
      {
       $res_gmetad = `/etc/rc.d/init.d/gmetad stop 2>&1`;
      }
      else
      {
       $res_gmetad = `/etc/init.d/gmetad stop 2>&1`;
      }

		if ($?)
         {
           if ($callback)
            {
             my $resp={};
             $resp->{data}->[0]="$localhost: Ganglia Gmetad not stopped successfully:$res_gmetad \n";
             $callback->($resp);
             }
           else
            {
             xCAT::MsgUtils->message('S', "[mon]: $res_gmetad \n");
            }

           return(1,"Ganglia Gmetad not stopped successfully. \n");
         }



        if ($scope) { #opening if scope
	     my $OS=`uname`;
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
           my @hostinfo=xCAT::Utils->determinehostname();
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
          my $result = undef; 
         my $rec = undef;
	 if( exists($children[0]) ){
           $rec = join(',',@children);
         }
         if($rec){
           if ( $OS =~ /AIX/ )
           {
            $result = `XCATBYPASS=Y $::XCATROOT/bin/xdsh  $rec /etc/rc.d/init.d/gmond stop 2>&1`;
           }
           else
           {
           $result = `XCATBYPASS=Y $::XCATROOT/bin/xdsh  $rec /etc/init.d/gmond stop 2>&1`;
           }
         }

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
    if Ganglia can help monitoring and returning the node status.
    
    Arguments:
        none
    Returns:
         1  
=cut

#--------------------------------------------------------------------------------
sub supportNodeStatusMon {
  #print "gangliamon::supportNodeStatusMon called\n";
  return 1;
}



#--------------------------------------------------------------------------------
=head3   startNodeStatusMon
    This function is called by the monitorctrl module to tell
    Ganglia to start monitoring the node status and feed them back
    to xCAT. Ganglia will start setting up the condition/response 
    to monitor the node status changes.  

    Arguments:
       None.
    Returns:
        (return code, message)

=cut
#--------------------------------------------------------------------------------
sub startNodeStatusMon {
  #print "gangliamon::startNodeStatusMon called\n";
  return (0, "started");
}


#--------------------------------------------------------------------------------
=head3   stopNodeStatusMon
    This function is called by the monitorctrl module to tell
    Ganglia to stop feeding the node status info back to xCAT. It will
    stop the condition/response that is monitoring the node status.

    Arguments:
        none
    Returns:
        (return code, message)
=cut
#--------------------------------------------------------------------------------
sub stopNodeStatusMon {
  #print "gangliamon::stopNodeStatusMon called\n";
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
  return "Description: This plugin will help interface the xCat cluster with
   Gangliam monitoring software \n";
}

#--------------------------------------------------------------------------------
=head3    getPostscripts
      This function returns the postscripts needed for the nodes.
     Arguments: none
    Returns:
     The the postscripts. It a pointer to an array with the node group names as the keys
    and the comma separated poscript names as the value. For example:
    {service=>"cmd1,cmd2", xcatdefaults=>"cmd3,cmd4"} where xcatdefults is a group
    of all nodes including the service nodes.
=cut
#--------------------------------------------------------------------------------
sub getPostscripts {
  my $ret={};
  $ret->{compute}="confGang";
  return $ret;
}
