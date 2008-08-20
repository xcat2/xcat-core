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
      print "scope is: $scope \n";
      my $callback=shift;
      my $localhost=hostname();
      print "local host is $localhost \n";
      print "starting gmond locally \n";
      my $res_gmond = `/etc/init.d/gmond restart 2>&1`;
      print "res_gmond=$res_gmond\n";
      print "the result gmond before  is $? \n";
      if ($?)
       {
         print "gmond result after is $? \n";
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
 
        print "starting gmetad locally \n";
        my $res_gmetad = `/etc/init.d/gmetad restart 2>&1`;
        print "the result gmetad before  is $? \n";
        if ($?)
         {
            print "gmetad result after is $? \n";
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
           print "opening scope \n";
           print "inside scope is:$scope";
           print "noderef is: @$noderef \n"; 
           my $pPairHash=xCAT_monitoring::monitorctrl->getMonServer($noderef);
  	   print "pairhash: $pPairHash\n";
	   #identification of this node
	   my @hostinfo=xCAT::Utils->determinehostname();
	   print "host:@hostinfo\n";
	   my $isSV=xCAT::Utils->isServiceNode();
	   print "is sv is:$isSV \n";
           my %iphash=();	
	   foreach(@hostinfo) {$iphash{$_}=1;}
	   if (!$isSV) { $iphash{'noservicenode'}=1;}
        
           my @children;
	   foreach my $key (keys (%$pPairHash))
            { #opening foreach1
              print "opening foreach1 \n";
              print "key is: $key \n";
              my @key_a=split(',', $key);
              print "a[0] is: $key_a[0] \n";
              print "a[1] is: $key_a[1] \n";
              if (! $iphash{$key_a[0]}) { next;}   
	      my $mon_nodes=$pPairHash->{$key};

	      foreach(@$mon_nodes)
	        { #opening foreach2
	          my $node=$_->[0];
	          my $nodetype=$_->[1];
                  print "node=$node, nodetype=$nodetype\n";
	          if (($nodetype) && ($nodetype =~ /$::NODETYPE_OSI/))
	           { 
                    push(@children,$node);
	           }
  	        } #closing foreach2
            }  #closing foreach1
          print "children:@children\n";
          my $rec = join(',',@children);
          print "the string is $rec";
     print "XCATBYPASS=Y $::XCATROOT/bin/xdsh  $rec /etc/init.d/gmond restart 2>& \n"; 
      my $result=`XCATBYPASS=Y $::XCATROOT/bin/xdsh  $rec /etc/init.d/gmond restart 2>&1`;
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
     print "scope is $scope \n";
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
    print "scope inside Gmonc is $scope \n";
    my $callback=shift;

    my $localhost=hostname();

    chomp(my $hostname = `hostname`);
    print "cluster is: $hostname \n";

    print "checking gmond settings \n";
    `/bin/grep "xCAT gmond settings done" /etc/gmond.conf`;
    print "result is $? \n";

       if($?)
        { #openinf if ?
         if($callback) {
         my $resp={};
         $resp->{data}->[0]="$localhost: $?";
         $callback->($resp);
         } else {   xCAT::MsgUtils->message('S', "Gmond not configured $? \n"); }
        
            #backup the original file
            print "backing up original gmond file \n";
            `/bin/cp -f /etc/gmond.conf /etc/gmond.conf.orig`;
            print "original file backed up \n";
             my $master=xCAT::Utils->get_site_Master();
             print "obtained site master: $master \n";
             open(FILE1, "</etc/gmond.conf");
             open(FILE, "+>/etc/gmond.conf.tmp");
             print "files opened for config \n";
             my $fname = "/etc/gmond.conf";
             unless ( open( CONF, $fname ))
              {
                return(0);
              }

               my @raw_data = <CONF>;
               close( CONF );
               print "trying to pattern matching \n";
               my $str = join('',@raw_data);
               $str =~ s/setuid = yes/setuid = no/;
               $str =~ s/bind/#bind/;
               $str =~ s/mcast_join = .*/host = $master/;
               print "Phase 1 pattern matching done and trying to use monitoctrl \n";
            my $pPairHash=xCAT_monitoring::monitorctrl->getMonServer($noderef);
            print "pair has obtained \n";
            print "pairHash: $pPairHash \n";
            #identification of this node
            my @hostinfo=xCAT::Utils->determinehostname();
            print "host:@hostinfo\n";
            my $isSV=xCAT::Utils->isServiceNode();
            my %iphash=();
            foreach(@hostinfo) {$iphash{$_}=1;}
            if (!$isSV) { $iphash{'noservicenode'}=1;}
           
           # my @children;
            foreach my $key (keys (%$pPairHash))
             { #opening for each
               my @key_a=split(',', $key);
               if (! $iphash{$key_a[0]}) { next;}
               print "a[0] is: $key_a[0] \n";
               print "a[1] is: $key_a[1] \n";
               my $pattern = '^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})';
               if ( $key_a[0]!~/$pattern/ )
                {
                 my $cluster = $key_a[0];
                 print "it workrd cluster is: $cluster \n";
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
               print "Gmond conf succ \n"; 
             close(FILE1);
              close(FILE);
               print "files closed \n";
            `/bin/cp -f /etc/gmond.conf.tmp /etc/gmond.conf`;

      #      } #closing for each

       } #closing if ?
       
      if ($scope)
       {#opening if scope of confGmond
        print "opening scope \n";
        print "inside scope is:$scope";
        my $pPairHash=xCAT_monitoring::monitorctrl->getMonServer($noderef);

        print "pairHash: $pPairHash \n";
        #identification of this node
        my @hostinfo=xCAT::Utils->determinehostname();
        print "host:@hostinfo\n";
        my $isSV=xCAT::Utils->isServiceNode();
        my %iphash=();
        foreach(@hostinfo) {$iphash{$_}=1;}
        if (!$isSV) { $iphash{'noservicenode'}=1;}

       my @children;
       foreach my $key (keys (%$pPairHash))
        { #opening for each
          my @key_a=split(',', $key);
          if (! $iphash{$key_a[0]}) { next;}
          print "a[0] is: $key_a[0] \n";
          print "a[1] is: $key_a[1] \n";
          if (! $iphash{$key_a[0]}) { next;}   
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
              print "the children are: $node \n";
              print "copying into CP node \n";
              my $res_cp = `XCATBYPASS=Y $::XCATROOT/bin/xdcp $node /install/postscripts/confGang /tmp 2>&1`;
              if($?)
                { #openinf if ?
                  if($callback) 
                    {
                     my $resp={};
                     $resp->{data}->[0]="$localhost: $res_cp";
                     $callback->($resp);
                    } 
                  else {   xCAT::MsgUtils->message('S', "Cannot copy confGang into /tmp: $res_cp \n"); }
                 } #closing if ?

               
              print "shell script time \n";
              print "MONSERVER is $key_a[0] \n";
              print "MONMASTER is $key_a[1] \n";
              my $res_conf=`XCATBYPASS=Y $::XCATROOT/bin/xdsh $node MONSERVER=$key_a[0] MONMASTER=$key_a[1] /tmp/confGang 2>&1`;
              if($?)
                { #openinf if ?
                  if($callback) 
                    {
                     my $resp={};
                     $resp->{data}->[0]="$localhost: $res_conf";
                     $callback->($resp);
                    } 
                  else {   xCAT::MsgUtils->message('S', "Cannot configure gmond in nodes: $res_conf \n"); }
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
    print "scope inside confGmetad is $scope \n";
    my $callback=shift;

    my $localhost=hostname();

    chomp(my $hostname = `hostname`);
    print "cluster is: $hostname \n";
    
    print "checking gmetad settings \n";
    `/bin/grep "xCAT gmetad settings done" /etc/gmetad.conf`;
    print "result is $? \n";
      
       if($?)
        { #openinf if ?
         if($callback) {
         my $resp={};
         $resp->{data}->[0]="$localhost: $?";
         $callback->($resp);
         } else {   xCAT::MsgUtils->message('S', "Gmetad not configured $? \n"); }
          # backup the original file
          print "backing up original gmetad file \n";
          `/bin/cp -f /etc/gmetad.conf /etc/gmetad.conf.orig`;

          open(FILE1, "</etc/gmetad.conf");
          open(FILE, "+>/etc/gmetad.conf.tmp");
        
          while (readline(FILE1))
          {
            # print STDERR "READ = $_\n";
            s/data_source/#data_source/g;
            # print STDERR "POST-READ = $_\n";
            print FILE $_;
          }
          close(FILE1);
          close(FILE);
          `/bin/cp -f /etc/gmetad.conf.tmp /etc/gmetad.conf`;
        
          open(OUTFILE,"+>>/etc/gmetad.conf")
                  or die ("Cannot open file \n"); 
          print(OUTFILE "# Setting up GMETAD configuration file \n");
         
          if (-e "/etc/xCATMN")
          {
           print "\n Managmt node \n";
           print(OUTFILE "data_source \"$hostname\" localhost \n");
          }
          my $noderef=xCAT_monitoring::monitorctrl->getMonHierarchy();
          my @hostinfo=xCAT::Utils->determinehostname();
          print "host:@hostinfo\n";
          my $isSV=xCAT::Utils->isServiceNode();
          my %iphash=();
          foreach(@hostinfo) {$iphash{$_}=1;}
          if (!$isSV) { $iphash{'noservicenode'}=1;}

          my @children;
          my $cluster;
          foreach my $key (keys (%$noderef))
           {
            my @key_g=split(',', $key);
         #    print "a[0] is: $key_g[0] \n";
             if (! $iphash{$key_g[0]}) { next;}
             my $mon_nodes=$noderef->{$key};
             print "a[0] is hi: $key_g[0] \n";
             my $pattern = '^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})';
             if ( $key_g[0]!~/$pattern/ )
             { 
               no warnings;
               $cluster = $key_g[0];
               print "found cluster: $cluster \n";
             }
             foreach(@$mon_nodes)
              {
                my $node=$_->[0];
                my $nodetype=$_->[1];
                print "node=$node, nodetype=$nodetype\n";
                 if (($nodetype) && ($nodetype =~ /$::NODETYPE_OSI/))
                  {
                    push(@children,$node);
                  }
              }
  
           }
         print "children:@children\n";
         my $num=@children;
         print "the number of children is: $num \n";
          if (-e "/etc/xCATSN")
                {
                 print "culster hi is $cluster \n";
                 for (my $i = 0; $i < $num; $i++)
                  {
                   print "childred is $children[ $i ] \n";
                   print ( OUTFILE "data_source \"$cluster\" $children[ $i ]  \n");
                   print "children printed \n";
                  }
                } 
       
             else
              {
                for (my $j = 0; $j < $num; $j++)
                 {
                  print "childred is $children[ $j ] \n";
                  print ( OUTFILE "data_source \"$children[ $j ]\" $children[ $j ]  \n");
                  print "children printed \n";
                 }
              }
       print(OUTFILE "# xCAT gmetad settings done \n");
       close(OUTFILE);
       
     } #closing if? loop

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
     print "scope is $scope \n";
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
    print "scope inside Gmond is $scope \n";
    my $callback=shift;

    my $localhost=hostname();

     print "saving configured Gmond file \n";
     `/bin/cp -f /etc/gmond.conf /etc/gmond.conf.save`;
     print "deconfiguring Ganglia Gmond \n";
     my $decon_gmond=`/bin/cp -f /etc/gmond.conf.orig /etc/gmond.conf`;
      if($?)
        { #openinf if ?
          if($callback) {
          my $resp={};
          $resp->{data}->[0]="$localhost:$decon_gmond";
          $callback->($resp);
          } else {   xCAT::MsgUtils->message('S', "Gmond not deconfigured $decon_gmond \n"); } 
        }
     
      if ($scope)
       {#opening if scope of confGmond
        print "opening scope \n";
        print "inside scope is:$scope";
        my $pPairHash=xCAT_monitoring::monitorctrl->getMonServer($noderef);

        print "pairHash: $pPairHash \n";
        #identification of this node
        my @hostinfo=xCAT::Utils->determinehostname();
        print "host:@hostinfo\n";
        my $isSV=xCAT::Utils->isServiceNode();
        my %iphash=();
        foreach(@hostinfo) {$iphash{$_}=1;}
        if (!$isSV) { $iphash{'noservicenode'}=1;}

       my @children;
       foreach my $key (keys (%$pPairHash))
        { #opening for each
          my @key_a=split(',', $key);
          if (! $iphash{$key_a[0]}) { next;}
          print "a[0] is: $key_a[0] \n";
          print "a[1] is: $key_a[1] \n";
          if (! $iphash{$key_a[0]}) { next;}   
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
              print "the children are: $node \n";
              print "saving the configured Gmond file in childern \n";
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
    print "scope inside Gmetad is $scope \n";
    my $callback=shift;

    my $localhost=hostname();

     print "saving configured Gmetad file \n";
     `/bin/cp -f /etc/gmetad.conf /etc/gmetad.conf.save`;
     print "deconfiguring Ganglia Gmetad \n";
     my $decon_gmetad=`/bin/cp -f /etc/gmetad.conf.orig /etc/gmetad.conf`;
      if($?)
        { #openinf if ?
          if($callback) {
          my $resp={};
          $resp->{data}->[0]="$localhost: $decon_gmetad";
          $callback->($resp);
          } else {   xCAT::MsgUtils->message('S', "Gmetadd not deconfigured $decon_gmetad \n"); } 
        }
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
      print "local host is $localhost \n";
      print "stopping gmond locally \n";
      my $res_gmond = `/etc/init.d/gmond stop 2>&1`;
      print "res_gmond=$res_gmond\n";
      print "the result gmond before  is $? \n";
      if ($?)
       {
         print "gmond result after is $? \n";
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

        print "stopping gmetad locally \n";
        my $res_gmetad = `/etc/init.d/gmetad stop 2>&1`;
        print "the result gmetad before  is $? \n";
        if ($?)
         {
            print "gmetad result after is $? \n";
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



        if ($scope)
         { #opening if scope
           print "opening scope \n";
           print "noderef is: @$noderef \n";
           my $pPairHash=xCAT_monitoring::monitorctrl->getMonServer($noderef);
           print "pairhash: $pPairHash\n";
           #identification of this node
           my @hostinfo=xCAT::Utils->determinehostname();
           print "host:@hostinfo\n";
           my $isSV=xCAT::Utils->isServiceNode();
           print "is sv is:$isSV \n";
           my %iphash=();
           foreach(@hostinfo) {$iphash{$_}=1;}
           if (!$isSV) { $iphash{'noservicenode'}=1;}

           my @children;
           foreach my $key (keys (%$pPairHash))
            { #opening foreach1
              print "opening foreach1 \n";
              print "key is: $key \n";
              my @key_a=split(',', $key);
              print "a[1] is: $key_a[1] \n";
              if (! $iphash{$key_a[0]}) { next;}
              my $mon_nodes=$pPairHash->{$key};

              foreach(@$mon_nodes)
                { #opening foreach2
                  my $node=$_->[0];
                  my $nodetype=$_->[1];
                  print "node=$node, nodetype=$nodetype\n";
                  if (($nodetype) && ($nodetype =~ /$::NODETYPE_OSI/))
                   {
                    push(@children,$node);
                   }
                } #closing foreach2
            }  #closing foreach1
          print "children:@children\n";
          my $rec = join(',',@children);
          print "the string is $rec";
     print "XCATBYPASS=Y $::XCATROOT/bin/xdsh  $rec /etc/init.d/gmond stop 2>& \n";
       my $result=`XCATBYPASS=Y $::XCATROOT/bin/xdsh  $rec /etc/init.d/gmond stop 2>&1`;
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


