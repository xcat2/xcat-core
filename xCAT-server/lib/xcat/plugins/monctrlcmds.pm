#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::monctrlcmds;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use xCAT::NodeRange;
use xCAT::Table;
use xCAT::MsgUtils;
use xCAT_monitoring::monitorctrl;
use xCAT::Utils;
use Sys::Hostname;
use Data::Dumper;


1;



#-------------------------------------------------------------------------------
=head1  xCAT_plugin:monctrlcmds
=head2    Package Description
  xCAT monitoring control commands plugini module. This modules handles
  monitoring related commands.
=cut
#-------------------------------------------------------------------------------



#--------------------------------------------------------------------------------
=head3   handled_commands
      It returns a list of commands handled by this plugin.
    Arguments:
        none
    Returns:
        a list of commands.
=cut
#--------------------------------------------------------------------------------
sub handled_commands {
  return {
    monstart => "monctrlcmds",
    monstop => "monctrlcmds",
    monls => "monctrlcmds",
    monadd => "monctrlcmds",
    monrm => "monctrlcmds",
    moncfg => "monctrlcmds",
    mondecfg => "monctrlcmds",
    monshow => "monctrlcmds",
  }
}

#-------------------------------------------------------
=head3  preprocess_request

  Check and setup for hierarchy 

=cut
#-------------------------------------------------------
sub preprocess_request
{
  my $req = shift;
  my $callback  = shift;
  my $command = $req->{command}->[0];
#  if ($req->{_xcatdest}) { return [$req]; }    #exit if preprocessed
  if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }

  if ($req->{module}) { return [$req]; }
  my $args=$req->{arg};

  my @requests=();

 
  if (($command eq "monstart") || ($command eq "monstop") || ($command eq "moncfg") || ($command eq "mondecfg") || ($command eq "monshow"))  {
    my @a_ret; #(0, $modulename, $nodestatutmon, $scope, \@nodes)
    if ($command eq "monstart") {
      @a_ret=preprocess_monstart($args, $callback);
    } elsif ($command eq "monstop") {
      @a_ret=preprocess_monstop($args, $callback);
    } elsif ($command eq "moncfg") {
      @a_ret=preprocess_moncfg($args, $callback);
    } elsif ($command eq "mondecfg") {  
      @a_ret=preprocess_mondecfg($args, $callback);
    } elsif ($command eq "monshow") {
      @a_ret=preprocess_monshow($args, $callback);
    }

    if ($a_ret[0] != 0) {
      $req = {};
      return;               
    } else {
      my $allnodes=$a_ret[4];
      #print "allnodes=@$allnodes\n";
      my $pname=$a_ret[1];
      my $file_name="$::XCATROOT/lib/perl/xCAT_monitoring/$pname.pm";
      my $module_name="xCAT_monitoring::$pname";
      undef $SIG{CHLD};
      if(($command eq "monshow") && (@$allnodes==0) && ($a_ret[2]&0x2!=0)){
        my $reqcopy = {%$req};
	push @{$reqcopy->{module}}, $a_ret[1];
	push @{$reqcopy->{priv}}, $a_ret[2];
	push @{$reqcopy->{priv}}, $a_ret[3];
	push @{$reqcopy->{priv}}, $a_ret[5];
	push @{$reqcopy->{priv}}, $a_ret[6];
        push @{$reqcopy->{priv}}, $a_ret[7];
	push @requests, $reqcopy;
	return \@requests;
      }
      #initialize and start monitoring
      no strict  "refs";
      my $mon_hierachy;
      if (defined(${$module_name."::"}{getNodesMonServers})) {
        $mon_hierachy = ${$module_name."::"}{getNodesMonServers}->($allnodes, $callback);
      } else {
        $mon_hierachy=xCAT_monitoring::monitorctrl->getNodeMonServerPair($allnodes, 1);
      }
      
      #print Dumper($mon_hierachy);

      if (ref($mon_hierachy) eq 'ARRAY') { 
          my $rsp2={};
          $rsp2->{data}->[0]=$mon_hierachy->[1];
          $callback->($rsp2);
	  $req = {};
	  return;               
      } 

     
      my @mon_servers=keys(%$mon_hierachy); 
      my @hostinfo=xCAT::NetworkUtils->determinehostname();
      #print "hostinfo=@hostinfo\n";
      my $isSV=xCAT::Utils->isServiceNode();
      my %iphash=();
      foreach(@hostinfo) {$iphash{$_}=1;}
      if (!$isSV) { $iphash{'noservicenode'}=1;}

      #check if we should also pass nodes that are managed by the sn to mn. 
      my $handleGrands=0;
      if (!$isSV) {
	  if (defined(${$module_name."::"}{handleGrandChildren})) {
	      $handleGrands=${$module_name."::"}{handleGrandChildren}->();
	  }  
      }
      #print "handleGrands=$handleGrands\n";
     
      my $index=0;
      my $reqcopy_grands = {%$req};
      foreach my $sv_pair (@mon_servers) {
        #service node come in pairs, the first one is the monserver adapter that facing the mn,
        # the second one is facing the cn. we use the first one here
        my @server_pair=split(':', $sv_pair); 
        my $sv=$server_pair[0];
        my $sv1;
	if (@server_pair>1) {
	    $sv1=$server_pair[1];
	}
        my $mon_nodes=$mon_hierachy->{$sv_pair};
        if ((!$mon_nodes) || (@$mon_nodes ==0)) { next; }
        #print "sv=$sv, nodes=@$mon_nodes\n";

        my $reqcopy = {%$req};
	if (! $iphash{$sv}) {
	    if ($isSV) { next; } #if the command is issued on the monserver, only handle its children.
	    else {
		if ($handleGrands) {
		    $index++;
		    $reqcopy_grands->{"grand_$index"}="$sv,$sv1," . join(',', @$mon_nodes);
		}
	    }
	    $reqcopy->{'_xcatdest'}=$sv;
	    $reqcopy->{_xcatpreprocessed}->[0] = 1;
	    my $rsp2={};
	    $rsp2->{data}->[0]="sending request to $sv..., ".join(',', @$mon_nodes);
	    $callback->($rsp2);
	} 
	    
	push @{$reqcopy->{module}}, $a_ret[1];
	if($command eq "monshow"){
	    push @{$reqcopy->{priv}}, $a_ret[2];
	    push @{$reqcopy->{priv}}, $a_ret[3];
	    push @{$reqcopy->{priv}}, $a_ret[5];
	    push @{$reqcopy->{priv}}, $a_ret[6];
	    push  @{$reqcopy->{priv}}, $a_ret[7];
	} else {
	    push @{$reqcopy->{nodestatmon}}, $a_ret[2];
	    push @{$reqcopy->{scope}}, $a_ret[3];
	}
	push @{$reqcopy->{nodeinfo}}, join(',', @$mon_nodes);
	push @requests, $reqcopy;
      }

      #add the a request for mn to handle all its grand children
      if ($index > 0) {
	  $reqcopy_grands->{grand_total}=$index;
	  push @{$reqcopy_grands->{module}}, $a_ret[1];
	  if($command eq "monshow"){
	      push @{$reqcopy_grands->{priv}}, $a_ret[2];
	      push @{$reqcopy_grands->{priv}}, $a_ret[3];
	      push @{$reqcopy_grands->{priv}}, $a_ret[5];
	      push @{$reqcopy_grands->{priv}}, $a_ret[6];
	      push @{$reqcopy_grands->{priv}}, $a_ret[7];
	  } else {
	      push @{$reqcopy_grands->{nodestatmon}}, $a_ret[2];
	      push @{$reqcopy_grands->{scope}}, $a_ret[3];
	  }
	  push @requests, $reqcopy_grands;
      }
    }
  } else {
    my $reqcopy = {%$req};
    push @requests, $reqcopy;
  } 

  return \@requests;
}


#--------------------------------------------------------------------------------
=head3   process_request
      It processes the monitoring control commands.
    Arguments:
      request -- a hash table which contains the command name and the arguments.
      callback -- a callback pointer to return the response to.
    Returns:
        0 for success. The output is returned through the callback pointer.
        1. for unsuccess. The error messages are returns through the callback pointer.
=cut
#--------------------------------------------------------------------------------
sub process_request {
  use Getopt::Long;
  # options can be bundled up like -vV
  Getopt::Long::Configure("bundling") ;
  $Getopt::Long::ignorecase=0;
  
  #print "process_request get called\n";
  my $request = shift;
  my $callback = shift;
  my $command = $request->{command}->[0];
  my $args=$request->{arg};
  my $doreq = shift;

  if ($command eq "monstart") {
    return monstart($request, $callback, $doreq);
  } 
  elsif ($command eq "monstop") {
    return monstop($request, $callback, $doreq);
  } 
  elsif ($command eq "monls") {
    return monls($request,  $callback, $doreq);

  }
  elsif ($command eq "monadd") {
    return monadd($request, $callback, $doreq);
  }
  elsif ($command eq "monrm") {
    return monrm($request, $callback, $doreq);
  }
  elsif ($command eq "moncfg") {
    return moncfg($request, $callback, $doreq);
  }
  elsif ($command eq "mondecfg") {
    return mondecfg($request, $callback, $doreq);
  }
  elsif ($command eq "monshow") {
    return monshow($request, $callback, $doreq);
  } else {
    my $rsp={};
    $rsp->{data}->[0]= "unsupported command: $command.";
    $callback->($rsp);
    return 1;
  }
}


#--------------------------------------------------------------------------------
=head3  preprocess_monstart
        This function handles the syntax checking for monstart command,
     turn on the given monitoring plug-in to the 'monitoring' table.
    Arguments:
      callback - the pointer to the callback function.
      args - The format of the args is:
        [-h|--help|-v|--version] or
        name [noderange] [-r|--remote]        
        where
          name is the monitoring plug-in name. For example: rmcmon. 
              The specified plug-in will be invoked for monitoring the xCAT cluster.
          noderange a range of nodes to be monitored. Default is all.
          -r|--remote indicates that both monservers and the nodes need to be called to start
             the monitoring. The defaults is monservers only.
    Returns:
        (0, $modulename, $nodestatutmon, $scope, \@nodes) for success. scope is the scope of the
            actions. 1 means monervers only, 2 means both nodes and monservers.
        (1, "") for unsuccess. The error messages are returns through the callback pointer.
=cut
#--------------------------------------------------------------------------------
sub preprocess_monstart 
{
  my $args=shift;
  my $callback=shift;

  if (xCAT::Utils->isServiceNode()) {
    my $rsp={};
    $rsp->{data}->[0]= "This command is not supported on a service node.";
    $callback->($rsp);
    return (1, "");
  }

  # subroutine to display the usage
  sub monstart_usage
  {
    my $cb=shift;
    my $rsp={};
    $rsp->{data}->[0]= "Usage:";
    $rsp->{data}->[1]= "  monstart name [noderange] [-r|--remote]";
    $rsp->{data}->[2]= "  monstart [-h|--help|-v|--version]";
    $rsp->{data}->[3]= "     name is the name of the monitoring plug-in module to be invoked.";
    $rsp->{data}->[4]= "       Use 'monls -a' command to list all the monitoring plug-in names.";
    $rsp->{data}->[5]= "     noderange is a range of nodes to be monitored. The default is all nodes.";
    $rsp->{data}->[6]= "      -r|--remote indicates that both monservers and the nodes need to be called\n       to start the monitoring. The default is monservers only.";
    $cb->($rsp);
  }
  
  @ARGV=();
  if ($args) { @ARGV=@{$args};}
  
  my $settings;

  # parse the options
  if(!GetOptions(
      'h|help'     => \$::HELP,
      'v|version'  => \$::VERSION,
      'r|remote'  => \$::REMOTE,))
  {
    &monstart_usage($callback);
    return (1, "");
  }

  # display the usage if -h or --help is specified
  if ($::HELP) { 
    &monstart_usage($callback);
    return 1;
  }
  # display the version statement if -v or --verison is specified
  if ($::VERSION)
  {
    my $rsp={};
    $rsp->{data}->[0]= xCAT::Utils->Version();
    $callback->($rsp);
    return (1, "");
  }

  my $pname="";
  my $scope=0; #set it to 0 instead of 1 because it will be distributed to monservers. 
  my @nodes=();
  my $nodestatmon=0;

  if ($::REMOTE) { $scope=2; }

  if (@ARGV < 1)
  {
    &monstart_usage($callback);
    return (1, "");
  }
  else {
    #@product_names=split(/,/, $ARGV[0]);
    $pname=$ARGV[0];
    if (@ARGV > 1) { 
      my $noderange=$ARGV[1];
      @nodes = noderange($noderange);
      if (nodesmissed) {
        my $rsp={};
        $rsp->{data}->[0]= "Invalid nodes in noderange:".join(',',nodesmissed);
        $callback->($rsp);
        return (1, "");
      }
    } 

    my $file_name="$::XCATROOT/lib/perl/xCAT_monitoring/$pname.pm";
    if (!-e $file_name) {
      my $rsp={};
      $rsp->{data}->[0]="File $file_name does not exist.";
      $callback->($rsp);
      return (1, "");
    }  else {
      #load the module in memory
      eval {require($file_name)};
      if ($@) {   
        my $rsp={};
        $rsp->{data}->[0]="The file $file_name has compiling errors:\n$@\n";
        $callback->($rsp);
        return (1, "");  
      }      
    }
  }
  my $table=xCAT::Table->new("monitoring", -create => 1,-autocommit => 1);
  if ($table) {
    my $found=0;
    my $tmp1=$table->getAllEntries("all");
    if (defined($tmp1) && (@$tmp1 > 0)) {
      foreach(@$tmp1) {
	if ($pname eq $_->{name}) {
	  $found=1;
          if ($_->{disable} !~ /0|NO|No|no|N|n/) {
            my %key_col = (name=>$pname);
            my %tb_cols=(disable=>"0");
            $table->setAttribs(\%key_col, \%tb_cols);
          }
          if ($_->{nodestatmon}  =~ /1|Yes|yes|YES|Y|y/) { $nodestatmon=1;}
          last;
	}
      }
    }

    if (!$found) {
      my $rsp={};
      $rsp->{data}->[0]="$pname has not been added to the monitoring table. Please run 'monadd' command to add.";
      $callback->($rsp);
      $table->close(); 
      return (1, "");
    }

    $table->close(); 
  } else {
    my $rsp={};
    $rsp->{data}->[0]="Failed to open the monitoring table.";
    $callback->($rsp);
    return (1, "");
  }

  return (0, $pname, $nodestatmon, $scope, \@nodes);
}

#--------------------------------------------------------------------------------
=head3   monstart
        This function calls moniutoring control to start the monitoring and node
    status monitoring for the given plug-in module. 
    Arguments:
      request -- pointer to a hash with keys are command, module and nodestatmon.
      callback - the pointer to the callback function.
    Returns:
        0 for success. The output is returned through the callback pointer.
        1. for unsuccess. The error messages are returns through the callback pointer.
=cut
#--------------------------------------------------------------------------------
sub monstart {
  my $request=shift;
  my $callback=shift;
  
  my $pname=$request->{module}->[0];
  my $nodestatmon=$request->{nodestatmon}->[0];
  my $scope=$request->{scope}->[0];
  my $nodeinfo=$request->{nodeinfo}->[0];

  my $grands={};
  my $total=0;
  if (exists($request->{grand_total})) {
      $total=$request->{grand_total};
  }
  for (my $i=1; $i<= $total; $i++) {
       if (exists($request->{"grand_$i"})) {
	   my $temp=$request->{"grand_$i"};
	   my @tmpnodes=split(',', $temp);
	   if (@tmpnodes > 2) {
	       my $sv=shift(@tmpnodes);
	       my $sv1=shift(@tmpnodes);
	       $grands->{"$sv,$sv1"}=\@tmpnodes;
	   }
       }
  }
  #print "-------grands" . Dumper($grands);


  my @nodes=split(',', $nodeinfo);
  #print "monstart get called: pname=$pname\nnodestatmon=$nodestatmon\nnodeinfo=$nodeinfo\nscope=$scope\n"; 

  xCAT_monitoring::monitorctrl->startMonitoring([$pname], \@nodes, $scope, $callback, $grands); 

  if ($nodestatmon) {
    xCAT_monitoring::monitorctrl->startNodeStatusMonitoring($pname, \@nodes, $scope, $callback, $grands); 
  }
  return;
}

#--------------------------------------------------------------------------------
=head3   preprocess_monstop
        This function unregisters the given monitoring plug-in from the 'monitoring' table.
    Arguments:
      callback - the pointer to the callback function.
      args - The format of the args is:
        [-h|--help|-v|--version] or
        name [noderange] [-r|--remote]
        name
        where
          name is the monitoring plug-in name. For example: rmcmon. 
              The specified plug-in will be stoped for monitoring the xCAT cluster.
          noderange a range of nodes. Default is all.
          -r|--remote indicates that both monservers and the nodes need to be called to stop
             the monitoring. The defaults is monservers only.
    Returns:
        (0, $modulename, $nodestatutmon, $scope, \@nodes) for success. scope is the scope of the
            actions. 1 means monervers only, 2 means both nodes and monservers.
        (1, "") for unsuccess. The error messages are returns through the callback pointer.
=cut
#--------------------------------------------------------------------------------
sub preprocess_monstop 
{
  my $args=shift;
  my $callback=shift;

  if (xCAT::Utils->isServiceNode()) {
    my $rsp={};
    $rsp->{data}->[0]= "This command is not supported on a service node.";
    $callback->($rsp);
    return (1, "");
  }

  # subroutine to display the usage
  sub monstop_usage
  {
    my $cb=shift;
    my $rsp={};
    $rsp->{data}->[0]= "Usage:";
    $rsp->{data}->[1]= "  monstop name [noderange] [-r|--remote]";
    $rsp->{data}->[2]= "  monstop [-h|--help|-v|--version]";
    $rsp->{data}->[3]= "      name is the name of the monitoring plug-in module registered in the monitoring table.";
    $cb->($rsp);
  }

  @ARGV=();
  if ($args) { @ARGV=@{$args};}
  
  # parse the options
  if(!GetOptions(
      'h|help'     => \$::HELP,
      'r|remote'  => \$::REMOTE,
      'v|version'  => \$::VERSION,))
  {
    &monstop_usage($callback);
    return (1, "");
  }

  # display the usage if -h or --help is specified
  if ($::HELP) { 
    &monstop_usage($callback);
    return  (1, "");
  }

  # display the version statement if -v or --verison is specified
  if ($::VERSION)
  {
    my $rsp={};
    $rsp->{data}->[0]= xCAT::Utils->Version();;
    $callback->($rsp);
    return (1, "");
  }

  my $pname="";
  my $scope=0;
  my @nodes=();
  my $nodestatmon=0;

  if ($::REMOTE) { $scope=2;}

  if (@ARGV < 1)
  {
    &monstop_usage($callback);
    return (1, "");
  }
  else {
    $pname=$ARGV[0];
    if (@ARGV > 1) { 
      my $noderange=$ARGV[1];
      @nodes = noderange($noderange);
      if (nodesmissed) {
        my $rsp={};
        $rsp->{data}->[0]= "Invalid nodes in noderange:".join(',',nodesmissed);
        $callback->($rsp);
        return (1, "");
      }
    } 

    my $file_name="$::XCATROOT/lib/perl/xCAT_monitoring/$pname.pm";
    if (!-e $file_name) {
      my $rsp={};
      $rsp->{data}->[0]="File $file_name does not exist.";
      $callback->($rsp);
      return (1, "");
    }  else {
      #load the module in memory
      eval {require($file_name)};
      if ($@) {   
        my $rsp={};
        $rsp->{data}->[0]="The file $file_name has compiling errors:\n$@\n";
        $callback->($rsp);
        return (1, "");  
      }      
    }
  }
  my $table=xCAT::Table->new("monitoring", -create => 1,-autocommit => 1);
  if ($table) {
    my $found=0;
    my $tmp1=$table->getAllEntries("all");
    if (defined($tmp1) && (@$tmp1 > 0)) {
      foreach(@$tmp1) {
	if ($pname eq $_->{name}) {
	  $found=1;
          if ($_->{disable} =~ /0|NO|No|no|N|n/) {
            my %key_col = (name=>$pname);
            my %tb_cols=(disable=>"1");
            $table->setAttribs(\%key_col, \%tb_cols);
          }
          if ($_->{nodestatmon}  =~ /1|Yes|yes|YES|Y|y/) { $nodestatmon=1;}
          last;
	}
      }
    }

    if (!$found) {
      my $rsp={};
      $rsp->{data}->[0]="$pname cannot be found in the monitoring table.";
      $callback->($rsp);
      $table->close(); 
      return (1, "");
    }

    $table->close(); 
  } else {
    my $rsp={};
    $rsp->{data}->[0]="Failed to open the monitoring table.";
    $callback->($rsp);
    return (1, "");
  }

  return (0, $pname, $nodestatmon, $scope, \@nodes);
}

#--------------------------------------------------------------------------------
=head3   monstop
        This function calls moniutoring control to stop the monitoring and node
    status monitoring for the given plug-in module. 
    Arguments:
      request -- pointer to a hash with keys are command, module and nodestatmon.
      callback - the pointer to the callback function.
    Returns:
        0 for success. The output is returned through the callback pointer.
        1. for unsuccess. The error messages are returns through the callback pointer.
=cut
#--------------------------------------------------------------------------------
sub monstop {
  my $request=shift;
  my $callback=shift;
  
  my $pname=$request->{module}->[0];
  my $nodestatmon=$request->{nodestatmon}->[0];
  my $scope=$request->{scope}->[0];
  my $nodeinfo=$request->{nodeinfo}->[0];


  my $grands={};
  my $total=0;
  if (exists($request->{grand_total})) {
      $total=$request->{grand_total};
  }
  for (my $i=1; $i<= $total; $i++) {
       if (exists($request->{"grand_$i"})) {
	   my $temp=$request->{"grand_$i"};
	   my @tmpnodes=split(',', $temp);
	   if (@tmpnodes > 2) {
	       my $sv=shift(@tmpnodes);
	       my $sv1=shift(@tmpnodes);
	       $grands->{"$sv,$sv1"}=\@tmpnodes;
	   }
       }
  }
  #print "-------grands" . Dumper($grands);


  my @nodes=split(',', $nodeinfo);
  #print "monstop get called: pname=$pname\nnodestatmon=$nodestatmon\nnodeinfo=@nodes\nscope=$scope\n"; 

  if ($nodestatmon) {
    xCAT_monitoring::monitorctrl->stopNodeStatusMonitoring($pname, \@nodes, $scope, $callback, $grands); 
  }

  xCAT_monitoring::monitorctrl->stopMonitoring([$pname], \@nodes, $scope, $callback, $grands); 

  return;
}


#--------------------------------------------------------------------------------
=head3   monls
        This function list the monitoring plug-in module names, status and description. 
    Arguments:
      callback - the pointer to the callback function.
      args - The format of the args is:
        [-h|--help|-v|--version] or
        [name] [-a|all] [-d|--description]         
    Returns:
        0 for success. The output is returned through the callback pointer.
        1. for unsuccess. The error messages are returns through the callback pointer.
=cut
#--------------------------------------------------------------------------------
sub monls {
  my $request = shift;
  my $callback = shift;
  my $args=$request->{arg};
  my $doreq = shift;

  # subroutine to display the usage
  sub monls_usage
  {
    my $cb=shift;
    my $rsp={};
    $rsp->{data}->[0]= "Usage:";
    $rsp->{data}->[1]= "  monls name [-d|--description]";
    $rsp->{data}->[2]= "  monls [-a|--all] [-d|--description]";
    $rsp->{data}->[3]= "  monls [-h|--help|-v|--version]";
    $rsp->{data}->[4]= "     name is the name of the monitoring plug-in module.";
    $cb->($rsp);
  }
  
  @ARGV=();
  if ($args) {
    @ARGV=@{$args};
  }

  # parse the options
  if(!GetOptions(
      'h|help'     => \$::HELP,
      'v|version'  => \$::VERSION,
      'a|all'  => \$::ALL,
      'd|discription'  => \$::DESC))
  {
    &monls_usage($callback);
    return;
  }

  # display the usage if -h or --help is specified
  if ($::HELP) { 
    &monls_usage($callback);
    return;
  }

  # display the version statement if -v or --verison is specified
  if ($::VERSION)
  {
    my $rsp={};
    $rsp->{data}->[0]= xCAT::Utils->Version();
    $callback->($rsp);
    return;
  }

  my $usetab=0;
  my %names=();
  my $plugin_dir="$::XCATROOT/lib/perl/xCAT_monitoring";
  if (@ARGV > 0)
  {
    $names{$ARGV[0]}=0; 
  }
  else {
    if ($::ALL) {
      #get all the module names from /opt/xcat/lib/perl/XCAT_monitoring directory   
      my @plugins=glob($plugin_dir."/*.pm");
      foreach (@plugins) {
        /.*\/([^\/]*).pm$/;
        $names{$1}=0;
      }
      # remove 2 files that are not plug-ins
      delete($names{monitorctrl});
      delete($names{montbhandler});
    }
    else {
      $usetab=1;
    }
  }

  #get the list from the table
  my $table=xCAT::Table->new("monitoring", -create =>1);
  if ($table) {
    my $tmp1=$table->getAllEntries("all");
    if (defined($tmp1) && (@$tmp1 > 0)) {
      foreach(@$tmp1) {
        my $pname=$_->{name};
        if (($usetab) || exists($names{$pname})) {
          $names{$pname}=1;
          #find out the monitoring plugin file and module name for the product
          my $rsp={};

          my $file_name="$::XCATROOT/lib/perl/xCAT_monitoring/$pname.pm";
          my $module_name="xCAT_monitoring::$pname";
          #load the module in memory
          eval {require($file_name)};
          if ($@) {  
            $rsp->{data}->[0]="$pname: The file $file_name cannot be located or has compiling errors.";       
            $callback->($rsp);
            next;      
          } else {
            no strict  "refs";
	    if (! defined(${$module_name."::"}{start})) { next; }
          }

          my $monnode=0;
          my $disable=1;
          if ($_->{nodestatmon} =~ /1|Yes|yes|YES|Y|y/) { $monnode=1; }
          if ($_->{disable} =~ /0|NO|No|no|N|n/) { $disable=0; }
	  if ($disable) { $monnode=0; }
          $rsp->{data}->[0]="$pname\t\t". 
                             ($disable ? "not-monitored" : "monitored") . 
                             ($monnode ? "\tnode-status-monitored" : "");
          if ($::DESC) { getModuleDescription($rsp, $module_name); }
          $callback->($rsp);
	}
      } #foreach
    }
    $table->close();
  }

    
  #now handle the ones that are not in the table
  foreach(keys(%names)) {
    my $pname=$_;
    if (! $names{$pname}) { 
      my $rsp={};
      #find out the monitoring plugin file and module name for the product
      my $file_name="$::XCATROOT/lib/perl/xCAT_monitoring/$pname.pm";
      my $module_name="xCAT_monitoring::$pname";
      #load the module in memory
      eval {require($file_name)}; 
      if ($@) {  
        $rsp->{data}->[0]="$pname: The file $file_name cannot be located or has compiling errors.";       
        $callback->($rsp);
        next;      
      } else {
        no strict  "refs";
        if (! defined(${$module_name."::"}{start})) { next; }
      }
      $rsp->{data}->[0]="$pname\t\tnot-monitored";

      if ($::DESC) {
	getModuleDescription($rsp, $module_name);
      }
      $callback->($rsp);
    }
  }
  return;
}


#--------------------------------------------------------------------------------
=head3   getModuleDescription
        This function gets description, postscripts and other info from the
     the given monitoring plug_in and stored it in the given hash. 
    Arguments:
    Returns:
        0 for success.
        1. for unsuccess.
=cut
#--------------------------------------------------------------------------------
sub getModuleDescription {
  my $rsp=shift;
  my $module_name=shift;
  no strict  "refs";
  #description
  if (defined(${$module_name."::"}{getDescription})) {
    $rsp->{data}->[1]=${$module_name."::"}{getDescription}->();  
  } else {
    $rsp->{data}->[1]="    No description available.";  
  }

  #postscripts
  $rsp->{data}->[2] = "  Postscripts:\n";
  if (defined(${$module_name."::"}{getPostscripts})) {
    my $desc=${$module_name."::"}{getPostscripts}->();
    my @pn=keys(%$desc);

    if (@pn>0) {
      foreach my $group (@pn) {
        $rsp->{data}->[2] .= "    $group: " . $desc->{$group}; 
      }
    } else { $rsp->{data}->[2] .= "    None";} 
  } else { $rsp->{data}->[2] .= "    None";} 

  #support node status monitoring
  $rsp->{data}->[3] = "  Support node status monitoring:\n";
  my $snodestatusmon=0; 
  if (defined(${$module_name."::"}{supportNodeStatusMon})) {
    $snodestatusmon=${$module_name."::"}{supportNodeStatusMon}->();
  }
  if ($snodestatusmon) { $rsp->{data}->[3] .= "    Yes\n";}
  else { $rsp->{data}->[3] .= "    No\n"; }
  return 0;
}

#--------------------------------------------------------------------------------
=head3   monadd
        This function adds the given module name into the monitoring table and
     sets the postsctipts in the postsctipts table. It also sets the given
     settings into the monsetting table. 
    Arguments:
      request -- a hash table which contains the command name and the arguments.
      callback - the pointer to the callback function.
      args - The format of the args is:
        [-h|--help|-v|--version] or
        name [-n|--nodestatmon] [-s|--settings ...]        
        where
          name is the monitoring plug-in name. For example: rmcmon. 
              The specified plug-in will be registered and invoked 
              for monitoring the xCAT cluster.
          -n|--nodestatmon  indicates that this plug-in will be used for feeding the node liveness
              status to the xCAT nodelist table.  If not specified, the plug-in will not be used 
              for feeding node status to xCAT. 
          -s|--settings settings are used by the plug-in to customize it behavor.
    Returns:
        0 for success. The output is returned through the callback pointer.
        1. for unsuccess. The error messages are returns through the callback pointer.
=cut
#--------------------------------------------------------------------------------
sub monadd {
  my $request = shift;
  my $callback = shift;
  my $args=$request->{arg};
  my $doreq = shift;

  # subroutine to display the usage
  sub monadd_usage
  {
    my $cb=shift;
    my $rsp={};
    $rsp->{data}->[0]= "Usage:";
    $rsp->{data}->[1]= "  monadd name [-n|--nodestatmon] [-s|--settings settings]";
    $rsp->{data}->[2]= "  monadd [-h|--help|-v|--version]";
    $rsp->{data}->[3]= "     name is the name of the monitoring plug-in module to be added.";
    $rsp->{data}->[4]= "       Use 'monls -a' command to list all the monitoring plug-in names.";
    $rsp->{data}->[5]= "     settings is used by the monitoring plug-in to customize its behavior.";
    $rsp->{data}->[6]= "       Format: -s key1=value1 -s key2=value2 ... ";
    $rsp->{data}->[7]= "       Please note that the square brackets are needed. ";
    $rsp->{data}->[7]= "       Use 'monls name -d' command to look for the possible settings for a plug-in.";
    $rsp->{data}->[8]= "  Example: monadd xcatmon -n -s ping-interval=10";
    $cb->($rsp);
  }
  
  @ARGV=();
  if ($args) { @ARGV=@{$args};}
  my $settings;

  # parse the options
  if(!GetOptions( 
      'h|help'     => \$::HELP,
      'v|version'  => \$::VERSION,
      'n|nodestatmon'  => \$::NODESTATMON,
      's|settings=s@'  => \$settings))
  {
    &monadd_usage($callback);
    return 1;
  }

  # display the usage if -h or --help is specified
  if ($::HELP) { 
    &monadd_usage($callback);
    return 1;
  }
  # display the version statement if -v or --verison is specified
  if ($::VERSION)
  {
    my $rsp={};
    $rsp->{data}->[0]= xCAT::Utils->Version();
    $callback->($rsp);
    return 1;
  }

  #my @product_names;
  my $pname;
  my $nodestatmon=0;
  if (@ARGV < 1)
  {
    &monadd_usage($callback);
    return 1;
  }
  else {
    #@product_names=split(/,/, $ARGV[0]);
    $pname=$ARGV[0];
    my $file_name="$::XCATROOT/lib/perl/xCAT_monitoring/$pname.pm";
    if (!-e $file_name) {
      my $rsp={};
      $rsp->{data}->[0]="File $file_name does not exist.";
      $callback->($rsp);
      return 1;
    }  else {
      #load the module in memory
      eval {require($file_name)};
      if ($@) {   
        my $rsp={};
        $rsp->{data}->[0]="The file $file_name has compiling errors:\n$@\n";
        $callback->($rsp);
        return 1;  
      }      
    }
  }
  my $table=xCAT::Table->new("monitoring", -create =>1);
  if ($table) {
    #my $tmp1=$table->getAllEntries("all");
    #if (defined($tmp1) && (@$tmp1 > 0)) {
    #  foreach(@$tmp1) {
    #    my $name=$_->{name};
    #    if ($name eq $pname) { 
    #      my $rsp={};
    #      $rsp->{data}->[0]="$pname has already been added in the monitoring table.";
    #      $callback->($rsp);
    #      $table->close(); 
    #      return 1;
    #    }
    #  }
    #}

    my $module_name="xCAT_monitoring::$pname";

    #check if the module suppors node status monitoring or not.
    if ($::NODESTATMON) {
      no strict  "refs";
      my $snodestatusmon=0; 
      if (defined(${$module_name."::"}{supportNodeStatusMon})) {
        $snodestatusmon=${$module_name."::"}{supportNodeStatusMon}->();
      }
      if (!$snodestatusmon) { 
        my $rsp={};
        $rsp->{data}->[0]="$pname does not support node status monitoring.";
        $callback->($rsp);
        $table->close(); 
        return 1;
      } 
    }

    #update the monsetting table
    if ($settings) {  
      my $table1=xCAT::Table->new("monsetting", -create => 1,-autocommit => 1);
      my %key_col1 = (name=>$pname);
      #parse the settings. Setting format: key="value",key="value"....
      foreach (@$settings) {
        if (/^\[(.*)\]$/) { #backward compatible
	    while (s/^\[([^\[\]\=]*)=([^\[\]]*)\](,)*//) { 
		$key_col1{key}=$1; 
		my %setting_hash=();
		$setting_hash{value}=$2;
		$table1->setAttribs(\%key_col1, \%setting_hash);
	    }
	} else {
	    /^([^\=]*)=(.*)/;
	    $key_col1{key}=$1;
	    my %setting_hash=();
	    $setting_hash{value}=$2;
	    $table1->setAttribs(\%key_col1, \%setting_hash);
	}
      }
      $table1->close();
    }
    #update the monitoring table
    my %key_col = (name=>$pname);
    my $nstat='N';
    if ($::NODESTATMON) {
     $nstat='Y';
     $nodestatmon=1;
    }
    my %tb_cols=(nodestatmon=>$nstat, disable=>"1");
    $table->setAttribs(\%key_col, \%tb_cols);
    $table->close(); 

    #updating the postscript table
    no strict  "refs";
    my $postscripts_h={};
    if (defined(${$module_name."::"}{getPostscripts})) {
      my $postscripts_h=${$module_name."::"}{getPostscripts}->();
      my @pn=keys(%$postscripts_h);
      if (@pn>0) {
        my $table2=xCAT::Table->new("postscripts", -create =>1);
        if (!$table2) {
          my $rsp={};
          $rsp->{data}->[0]="Cannot open the postscripts table.\nFailed to set the postscripts for $pname.";
          $callback->($rsp);
          return 1;
        }
        foreach my $group (@pn) {
          my $posts=$postscripts_h->{$group};
          if ($posts) {
	    (my $ref) = $table2->getAttribs({node => $group}, 'postscripts');
            if ($ref and $ref->{postscripts}) {
              my @old_a=split(',', $ref->{postscripts}); 
              my @new_a=split(',', $posts);
              my %new_h=();
              foreach my $new_tmp (@new_a) {
		my $found=0;
                foreach my $old_tmp (@old_a) {
		  if ($old_tmp eq $new_tmp) { $found=1; last; }
                }
                if (!$found) { $new_h{$new_tmp}=1;}
              }
              
              if (keys(%new_h) > 0) {
                foreach (keys(%new_h)) { push(@old_a, $_); }
                my $new_post=join(',', @old_a); 
                my %key_col2 = (node=>$group);
                my %tb_cols2=(postscripts=>$new_post);
                $table2->setAttribs(\%key_col2, \%tb_cols2);
               }
            } else {
              my %key_col2 = (node=>$group);
              my %tb_cols2=(postscripts=>$posts);
              $table2->setAttribs(\%key_col2, \%tb_cols2);
            }
          } 
        }
        $table2->close();
      }
    }     
  } else {
    my $rsp={};
    $rsp->{data}->[0]="Failed to open the monitoring table.";
    $callback->($rsp);
    return 1;
  }

  return 0;
}


#--------------------------------------------------------------------------------
=head3   monrm
      This function removes the given monitoring plug-in from the 'monitoring' table.
    It also removed the postscritps for the module from the 'postscritps' table.
    Arguments:
      request -- a hash table which contains the command name and the arguments.
      callback - the pointer to the callback function.
       args - The format of the args is:
        [-h|--help|-v|--version] or
        name
        where
          name is the monitoring plug-in name. For example: rmcmon. 
              The specified plug-in will be stopped for monitoring the xCAT 
              cluster if it is running and then removed from the monitoring table. 
    Returns:
        0 for success.
        1 for unsuccess. The error messages are returns through the callback pointer.
=cut
#--------------------------------------------------------------------------------
sub monrm {
  my $request = shift;
  my $callback = shift;
  my $args=$request->{arg};
  my $doreq = shift;

  if (xCAT::Utils->isServiceNode()) {
    my $rsp={};
    $rsp->{data}->[0]= "This command is not supported on a service node.";
    $callback->($rsp);
    return (1, "");
  }

  # subroutine to display the usage
  sub monrm_usage
  {
    my $cb=shift;
    my $rsp={};
    $rsp->{data}->[0]= "Usage:";
    $rsp->{data}->[1]= "  monrm name";
    $rsp->{data}->[2]= "  monrm [-h|--help|-v|--version]";
    $rsp->{data}->[3]= "      name is the name of the monitoring plug-in module registered in the monitoring table.";
    $cb->($rsp);
  }

  @ARGV=();
  if ($args) { @ARGV=@{$args};}
  
  # parse the options
  if(!GetOptions(
      'h|help'     => \$::HELP,
      'v|version'  => \$::VERSION,))
  {
    &monrm_usage($callback);
    return (1, "");
  }

  # display the usage if -h or --help is specified
  if ($::HELP) { 
    &monrm_usage($callback);
    return  (1, "");
  }

  # display the version statement if -v or --verison is specified
  if ($::VERSION)
  {
    my $rsp={};
    $rsp->{data}->[0]= xCAT::Utils->Version();;
    $callback->($rsp);
    return (1, "");
  }

  my $pname;
  if (@ARGV < 1)
  {
    &monrm_usage($callback);
    return (1, "");
  }
  else {
    $pname=$ARGV[0];
  }

  my $disable=1;
  my $found=0;
  my $table=xCAT::Table->new("monitoring", -create =>1);
  if ($table) {
    my $tmp1=$table->getAllEntries("all");
    if (defined($tmp1) && (@$tmp1 > 0)) {
      foreach(@$tmp1) {
	if ($pname eq $_->{name}) {
          if ($_->{disable} =~ /0|NO|No|no|N|n/) { $disable=0; }
	  $found=1;
        }
      }
    }
    
    if (!$found) {
      my $rsp={};
      $rsp->{data}->[0]="$pname is not in the monitoring talble.";
      $callback->($rsp);
      $table->close();
      return 0;
    }

    if (!$disable) {
      my $rsp={};
      $rsp->{data}->[0]="Please run command 'monstop $pname' to stop monitoring before running this command.";
      $callback->($rsp);
      $table->close();
      return 0;
    }

    my %key_col = (name=>$pname);
    $table->delEntries(\%key_col);
    $table->close();


    #remove the postscripts for the module from the postscript table
    no strict  "refs";
    my $file_name="$::XCATROOT/lib/perl/xCAT_monitoring/$pname.pm";
    my $module_name="xCAT_monitoring::$pname";
    if (!-e $file_name) {
      return 0;
    }  else {
      #load the module in memory
      eval {require($file_name)};
      if ($@) {   
       return 0;  
      }      
    }
    
    my $postscripts_h={};
    if (defined(${$module_name."::"}{getPostscripts})) {
      my $postscripts_h=${$module_name."::"}{getPostscripts}->();
      my @pn=keys(%$postscripts_h);
      if (@pn>0) {
        my $table2=xCAT::Table->new("postscripts", -create =>1);
        if (!$table2) {
          my $rsp={};
          $rsp->{data}->[0]="Cannot open the postscripts table.\nFailed to remove the postscripts for $pname.";
          $callback->($rsp);
          return 1;
        }
        foreach my $group (@pn) {
          my $posts=$postscripts_h->{$group};
          if ($posts) {
            (my $ref) = $table2->getAttribs({node => $group}, 'postscripts');
            if ($ref and $ref->{postscripts}) {
              my @old_a=split(',', $ref->{postscripts}); 
              my @new_a=split(',', $posts);
              my %new_h=();
              my @new_post_a=();
              foreach my $old_tmp (@old_a) {
		my $found=0;
                foreach my $new_tmp (@new_a) {
		  if ($old_tmp eq $new_tmp) { $found=1; last; }
                }
                if (!$found) { push(@new_post_a,$old_tmp); }
              }

              if (@new_post_a > 0) {
                my $new_post=join(',', @new_post_a);
                if ( $new_post ne $ref->{postscripts} ) {
                  my %key_col2 = (node=>$group);
                  my %tb_cols2=(postscripts=>$new_post);
                  $table2->setAttribs(\%key_col2, \%tb_cols2);
	        } 
              } else {
                my %key_col2 = (node=>$group);
                $table2->delEntries(\%key_col2);
              }
            } 
          } 
        }
        $table2->close();
      }
    }     
  } else {
    my $rsp={};
    $rsp->{data}->[0]="Cannot open monitoring table.";
    $callback->($rsp);
    return 1; 
  }

  return 0; 
}

#--------------------------------------------------------------------------------
=head3  preprocess_moncfg
        This function handles the syntax checking for moncfg command.
    Arguments:
      callback - the pointer to the callback function.
      args - The format of the args is:
        [-h|--help|-v|--version] or
        name [noderange] [-r|--remote]        
        where
          name is the monitoring plug-in name. For example: rmcmon. 
              The specified plug-in will be invoked for configuring the cluster to monitor the nodes.
          noderange a range of nodes to be configured for. Default is all.
          -r|--remote indicates that both monservers and the nodes need to configured.
             The defaults is monservers only.
    Returns:
        (0, $modulename, $nodestatutmon, $scope, \@nodes) for success. scope is the scope of the
            actions. 1 means monervers only, 2 means both nodes and monservers.
        (1, "") for unsuccess. The error messages are returns through the callback pointer.
=cut
#--------------------------------------------------------------------------------
sub preprocess_moncfg 
{
  my $args=shift;
  my $callback=shift;

  # subroutine to display the usage
  sub moncfg_usage
  {
    my $cb=shift;
    my $rsp={};
    $rsp->{data}->[0]= "Usage:";
    $rsp->{data}->[1]= "  moncfg name [noderange] [-r|--remote]";
    $rsp->{data}->[2]= "  moncfg [-h|--help|-v|--version]";
    $rsp->{data}->[3]= "     name is the name of the monitoring plug-in module to be invoked.";
    $rsp->{data}->[4]= "        Use 'monls -a' command to list all the monitoring plug-in names.";
    $rsp->{data}->[5]= "     noderange is a range of nodes to be configured for. The default is all nodes.";
    $rsp->{data}->[6]= "      -r|--remote indicates that both monservers and the nodes need to be configured.\n       The default is monservers only.";
    $rsp->{data}->[7]= "        The default is monservers only.";
    $cb->($rsp);
  }

  @ARGV=();
  if ($args) { @ARGV=@{$args};}
  
  # parse the options
  if(!GetOptions(
      'h|help'     => \$::HELP,
      'v|version'  => \$::VERSION,      
      'r|remote'  => \$::REMOTE,))
  {
    &moncfg_usage($callback);
    return;
  }

  # display the usage if -h or --help is specified
  if ($::HELP) { 
    &moncfg_usage($callback);
    return;
  }

  # display the version statement if -v or --verison is specified
  if ($::VERSION)
  {
    my $rsp={};
    $rsp->{data}->[0]= xCAT::Utils->Version();
    $callback->($rsp);
    return;
  }


  my $pname="";
  my $scope=0;
  my @nodes=();
  my $nodestatmon=0;

  if ($::REMOTE) { $scope=2;}

  if (@ARGV < 1)
  {
    &moncfg_usage($callback);
    return (1, "");
  }
  else {
    $pname=$ARGV[0];
    if (@ARGV > 1) { 
      my $noderange=$ARGV[1];
      @nodes = noderange($noderange);
      if (nodesmissed) {
        my $rsp={};
        $rsp->{data}->[0]= "Invalid nodes in noderange:".join(',',nodesmissed);
        $callback->($rsp);
        return (1, "");
      }
    } 

    my $file_name="$::XCATROOT/lib/perl/xCAT_monitoring/$pname.pm";
    if (!-e $file_name) {
      my $rsp={};
      $rsp->{data}->[0]="File $file_name does not exist.";
      $callback->($rsp);
      return (1, "");
    }  else {
      #load the module in memory
      eval {require($file_name)};
      if ($@) {   
        my $rsp={};
        $rsp->{data}->[0]="The file $file_name has compiling errors:\n$@\n";
        $callback->($rsp);
        return (1, "");  
      }      
    }
  }

  my $table=xCAT::Table->new("monitoring", -create => 1,-autocommit => 1);
  if ($table) {
    my $found=0;
    my $tmp1=$table->getAllEntries("all");
    if (defined($tmp1) && (@$tmp1 > 0)) {
      foreach(@$tmp1) {
	if ($pname eq $_->{name}) {
	  $found=1;
          if ($_->{nodestatmon}  =~ /1|Yes|yes|YES|Y|y/) { $nodestatmon=1;}
          last;
	}
      }
    }

    if (!$found) {
      my $rsp={};
      $rsp->{data}->[0]="$pname cannot be found in the monitoring table.";
      $callback->($rsp);
      $table->close(); 
      return (1, "");
    }

    $table->close(); 
  } else {
    my $rsp={};
    $rsp->{data}->[0]="Failed to open the monitoring table.";
    $callback->($rsp);
    return (1, "");
  }

  return (0, $pname, $nodestatmon, $scope, \@nodes);
}


#--------------------------------------------------------------------------------
=head3   moncfg
      This function configures the cluster for the given nodes. It includes configuring 
      and setting up the 3rd party monitoring software for monitoring the given nodes.  
    Arguments:
      request -- a hash table which contains the command name and the arguments.
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
        0 for success. The output is returned through the callback pointer.
        1. for unsuccess. The error messages are returns through the callback pointer.
=cut
#--------------------------------------------------------------------------------
sub moncfg 
{
  my $request=shift;
  my $callback=shift;
  
  my $pname=$request->{module}->[0];
  my $nodestatmon=$request->{nodestatmon}->[0];
  my $scope=$request->{scope}->[0];
  my $nodeinfo=$request->{nodeinfo}->[0];

  #print "---------monctrlcmnd::moncfg request=" . Dumper($request);
  
  my $grands={};
  my $total=0;
  if (exists($request->{grand_total})) {
      $total=$request->{grand_total};
  }
  for (my $i=1; $i<= $total; $i++) {
       if (exists($request->{"grand_$i"})) {
	   my $temp=$request->{"grand_$i"};
	   my @tmpnodes=split(',', $temp);
	   if (@tmpnodes > 2) {
	       my $sv=shift(@tmpnodes);
	       my $sv1=shift(@tmpnodes);
	       $grands->{"$sv,$sv1"}=\@tmpnodes;
	   }
       }
  }
  #print "-------grands" . Dumper($grands);

  my @nodes=split(',', $nodeinfo);
  #print "moncfg get called: pname=$pname\nnodestatmon=$nodestatmon\nnodeinfo=@nodes\nscope=$scope\n"; 

  xCAT_monitoring::monitorctrl->config([$pname], \@nodes, $scope, $callback, $grands); 
  return 0;
}


#--------------------------------------------------------------------------------
=head3  preprocess_mondecfg
        This function handles the syntax checking for mondecfg command.
    Arguments:
      callback - the pointer to the callback function.
      args - The format of the args is:
        [-h|--help|-v|--version] or
        name [noderange] [-r|--remote]        
        where
          name is the monitoring plug-in name. For example: rmcmon. 
              The specified plug-in will be invoked for deconfiguring the cluster to monitor the nodes.
          noderange a range of nodes to be deconfigured for. Default is all.
          -r|--remote indicates that both monservers and the nodes need to be deconfigured.
             The defaults is monservers only.
    Returns:
        (0, $modulename, $nodestatutmon, $scope, \@nodes) for success. scope is the scope of the
            actions. 1 means monervers only, 2 means both nodes and monservers.
        (1, "") for unsuccess. The error messages are returns through the callback pointer.
=cut
#--------------------------------------------------------------------------------
sub preprocess_mondecfg 
{
  my $args=shift; 
  my $callback=shift; 

  # subroutine to display the usage
  sub mondecfg_usage
  {
    my $cb=shift;
    my $rsp={};
    $rsp->{data}->[0]= "Usage:";
    $rsp->{data}->[1]= "  mondecfg name [noderange] [-r|--remote]";
    $rsp->{data}->[2]= "  mondecfg [-h|--help|-v|--version]";
    $rsp->{data}->[3]= "     name is the name of the monitoring plug-in module to be invoked.";
    $rsp->{data}->[4]= "        Use 'monls -a' command to list all the monitoring plug-in names.";
    $rsp->{data}->[5]= "     noderange is a range of nodes to be deconfigured for."; 
    $rsp->{data}->[6]= "        The default is all nodes.";
    $rsp->{data}->[7]= "      -r|--remote indicates that both monservers and the nodes need to be deconfigured.";
    $rsp->{data}->[8]= "        The default is monservers only.";
    $cb->($rsp);
  }

  @ARGV=();
  if ($args) { @ARGV=@{$args} ; }
  
  # parse the options
  if(!GetOptions(
      'h|help'     => \$::HELP,
      'v|version'  => \$::VERSION,      
      'r|remote'  => \$::REMOTE,))
  {
    &mondecfg_usage($callback);
    return;
  }

  # display the usage if -h or --help is specified
  if ($::HELP) { 
    &mondecfg_usage($callback);
    return;
  }

  # display the version statement if -v or --verison is specified
  if ($::VERSION)
  {
    my $rsp={};
    $rsp->{data}->[0]= xCAT::Utils->Version();
    $callback->($rsp);
    return;
  }

 
  my $pname="";
  my $scope=0;
  my @nodes=();
  my $nodestatmon=0;

  if ($::REMOTE) { $scope=2;}

  if (@ARGV < 1)
  {
    &mondecfg_usage($callback);
    return (1, "");
  }
  else {
    $pname=$ARGV[0];
    if (@ARGV > 1) { 
      my $noderange=$ARGV[1];
      @nodes = noderange($noderange);
      if (nodesmissed) {
        my $rsp={};
        $rsp->{data}->[0]= "Invalid nodes in noderange:".join(',',nodesmissed);
        $callback->($rsp);
        return (1, "");
      }
    } 

    my $file_name="$::XCATROOT/lib/perl/xCAT_monitoring/$pname.pm";
    if (!-e $file_name) {
      my $rsp={};
      $rsp->{data}->[0]="File $file_name does not exist.";
      $callback->($rsp);
      return (1, "");
    }  else {
      #load the module in memory
      eval {require($file_name)};
      if ($@) {   
        my $rsp={};
        $rsp->{data}->[0]="The file $file_name has compiling errors:\n$@\n";
        $callback->($rsp);
        return (1, "");  
      }      
    }
  }

  my $table=xCAT::Table->new("monitoring", -create => 1,-autocommit => 1);
  if ($table) {
    my $found=0;
    my $tmp1=$table->getAllEntries("all");
    if (defined($tmp1) && (@$tmp1 > 0)) {
      foreach(@$tmp1) {
	if ($pname eq $_->{name}) {
	  $found=1;
          if ($_->{nodestatmon}  =~ /1|Yes|yes|YES|Y|y/) { $nodestatmon=1;}
          last;
	}
      }
    }

    if (!$found) {
      my $rsp={};
      $rsp->{data}->[0]="$pname cannot be found in the monitoring table.";
      $callback->($rsp);
      $table->close(); 
      return (1, "");
    }

    $table->close(); 
  } else {
    my $rsp={};
    $rsp->{data}->[0]="Failed to open the monitoring table.";
    $callback->($rsp);
    return (1, "");
  }

  return (0, $pname, $nodestatmon, $scope, \@nodes);
}

#--------------------------------------------------------------------------------
=head3   mondecfg
      This function deconfigures the cluster for the given nodes. It includes deconfiguring 
      and clearning up the 3rd party monitoring software for monitoring the given nodes.  
    Arguments:
       names -- a pointer to an  array of monitoring plug-in names. If non is specified,
         all the plug-ins registered in the monitoring table will be notified.
       p_nodes -- a pointer to an arrays of nodes to be removed from the monitoring domain. 
                  none means all.
       scope -- the action scope, it indicates the node type the action will take place.
                0 means localhost only. 
                1 means monserver only, 
                2 means both monservers and nodes, 
       callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
        0 for success. The output is returned through the callback pointer.
        1. for unsuccess. The error messages are returns through the callback pointer.
=cut
#--------------------------------------------------------------------------------
sub mondecfg 
{
  my $request=shift;
  my $callback=shift;
  
  my $pname=$request->{module}->[0];
  my $nodestatmon=$request->{nodestatmon}->[0];
  my $scope=$request->{scope}->[0];
  my $nodeinfo=$request->{nodeinfo}->[0];

  my $grands={};
  my $total=0;
  if (exists($request->{grand_total})) {
      $total=$request->{grand_total};
  }
  for (my $i=1; $i<= $total; $i++) {
       if (exists($request->{"grand_$i"})) {
	   my $temp=$request->{"grand_$i"};
	   my @tmpnodes=split(',', $temp);
	   if (@tmpnodes > 2) {
	       my $sv=shift(@tmpnodes);
	       my $sv1=shift(@tmpnodes);
	       $grands->{"$sv,$sv1"}=\@tmpnodes;
	   }
       }
  }
  #print "-------grands" . Dumper($grands);

  my @nodes=split(',', $nodeinfo);
  #print "mondecfg get called: pname=$pname\nnodestatmon=$nodestatmon\nnodeinfo=@nodes\nscope=$scope\n"; 

  xCAT_monitoring::monitorctrl->deconfig([$pname], \@nodes, $scope, $callback, $grands); 

  return 0;
}

#--------------------------------------------------------------------------------
=head3  preprocess_monshow
        This function handles the syntax checking for monshow command.
    Arguments:
      callback - the pointer to the callback function.
      args - The format of the args is:
        [-h|--help|-v|--version] or
        name [noderange] [-s] [-t time] [-a attributes] [-w attr<operator>val [-w attr<operator>val] ...] [-o pe]        
        where
          name is the monitoring plug-in name. For example: rmcmon. Only for rmcmon currently.
          noderange a range of nodes to be showed for. If omitted, the data for all the nodes will be displayed.
          -s shows the summary data only
          -t specify a range of time for the data, default is last 60 minutes
	  -a specifies a comma-separated list of attributes or metrics names. The default is all.
    Returns:
        (0, $modulename, $sum, $time, \@nodes, $attrs, $pe, $where) for success.
        (1, "") for unsuccess. The error messages are returns through the callback pointer.
=cut
#--------------------------------------------------------------------------------
sub preprocess_monshow
{
  my $args=shift; 
  my $callback=shift; 

  # subroutine to display the usage
  sub monshow_usage
  {
    my $cb=shift;
    my $error=shift;
    my $rsp={};
    $rsp->{data}->[0]= "Usage:";
    $rsp->{data}->[1]= "  monshow name noderange [-s] [-t time] [-a attributes] [-w attr<operator>val[-w attr<operator>val ...]][-o pe]";
    $rsp->{data}->[2]= "  monshow [-h|--help|-v|--version]";
    $rsp->{data}->[3]= "     name is the name of the monitoring plug-in module to be invoked.";
    $rsp->{data}->[4]= "     noderange is a list of nodes to be showed for. If omitted,";
    $rsp->{data}->[5]= "        the data for all the nodes will be displayed."; 
    $rsp->{data}->[6]= "     -s shows the summary data.";
    $rsp->{data}->[7]= "     -t specifies a range of time for the data, The default is last 60 minutes";
    $rsp->{data}->[8]= "     -a specifies a comma-separated list of attributes or metrics names. The default is all.";
    $rsp->{data}->[9]= "     -w specifies one or multiple selection string that can be used to select events.";
    $rsp->{data}->[10]= "     -o specifies montype, it can be p, e or pe.";
    $rsp->{data}->[11]= "        p means performance, e means events, default is e";
#    $cb->($rsp);
      xCAT::MsgUtils->message("D", $rsp, $callback, $error);
  }

  @ARGV=();
  if ($args) { @ARGV=@{$args} ; }
  
  # parse the options
  if(!GetOptions(
      'h|help'     => \$::HELP,
      'v|version'  => \$::VERSION,      
      's'  => \$::SUMMARY,
      't=s' => \$::TIME,
      'a=s' => \$::ATTRS,
      'o=s' => \$::PE,
      'w=s@' => \$::OPT_W))
  {
    &monshow_usage($callback, 1);
    return (1, "");
  }

  # display the usage if -h or --help is specified
  if ($::HELP) { 
    &monshow_usage($callback, 0);
    return (1, "");
  }

  # display the version statement if -v or --verison is specified
  if ($::VERSION)
  {
    my $rsp={};
    $rsp->{data}->[0]= xCAT::Utils->Version();
    $callback->($rsp);
    return (1, "");
  }

  my $pname="";
  my $sum=0;
  my $time = 60;
  my @nodes=();
  my $attrs=undef;
  my $pe = 'e';
  my $where = [];

  if(@ARGV < 1) {
    &monshow_usage($callback, 1);
    return (1, "");
  }

  if($::SUMMARY) {$sum=1;}
  if($::TIME) {$time=$::TIME;}
  if($::ATTRS) {
    $attrs=$::ATTRS;
  } else {
    my $conftable = xCAT::Table->new('monsetting');
    my @metrixconf = $conftable->getAttribs({'name'=>'rmcmon'}, ('key','value'));
    foreach (@metrixconf){
      my $key = $_->{key};
      my $value = $_->{value};
      my $temp = undef;
      if($key =~ /^rmetrics/){
        if($value =~ /\]/){
	  ($temp, $value) = split /\]/, $value;	
	}
	($value, $temp) = split /:/, $value;
	if($attrs){
	  $attrs = "$attrs,$value";
	} else {
	  $attrs = $value;
	}
      } 
    }
  }
  if($::PE) {$pe=$::PE;}
  if($::OPT_W) {
    $where = $::OPT_W;
  }
  
  $pname=$ARGV[0];

  my $noderange = '';;
  if(@ARGV == 1) {
    if($sum){
      $sum |= 0x2;
    } 
  } else {
    $noderange = $ARGV[1];
  }

  @nodes = noderange($noderange);

  if (xCAT::Utils->isMN() && nodesmissed) {
    my $rsp={};
    $rsp->{data}->[0]= "Invalid nodes in noderange:".join(',',nodesmissed);
    xCAT::MsgUtils->message("E", $rsp, $callback);
    return (1, "");
  } 

  my $file_name="$::XCATROOT/lib/perl/xCAT_monitoring/$pname.pm";
  if (!-e $file_name) {
    my $rsp={};
    $rsp->{data}->[0]="File $file_name does not exist.";
    xCAT::MsgUtils->message("E", $rsp, $callback);
    return (1, "");
  }  else {
    #load the module in memory
    eval {require($file_name)};
    if ($@) {   
      my $rsp={};
      $rsp->{data}->[0]="The file $file_name has compiling errors:\n$@\n";
      xCAT::MsgUtils->message("E", $rsp, $callback);
      return (1, "");  
    }      
  }

  my $table=xCAT::Table->new("monitoring", -create => 1,-autocommit => 1);
  if ($table) {
    my $found=0;
    my $tmp1=$table->getAllEntries();
    if (defined($tmp1) && (@$tmp1 > 0)) {
      foreach(@$tmp1) {
	if ($pname eq $_->{name}) {
	  $found=1;
          last;
	}
      }
    }

    if (!$found) {
      my $rsp={};
      $rsp->{data}->[0]="$pname cannot be found in the monitoring table.";
      xCAT::MsgUtils->message("E", $rsp, $callback);
      $table->close(); 
      return (1, "");
    }

    $table->close(); 
  } else {
    my $rsp={};
    $rsp->{data}->[0]="Failed to open the monitoring table.";
    xCAT::MsgUtils->message("E", $rsp, $callback);
    return (1, "");
  }
  
  return (0, $pname, $sum, $time, \@nodes, $attrs, $pe,$where);
}

#--------------------------------------------------------------------------------
=head3   monshow
      This function configures the cluster performance for the given nodes.  
    Arguments:
      request -- a hash table which contains the command name and the arguments.
      callback -- the callback pointer for error and status displaying. It can be null.
    Returns:
        0 for success. The output is returned through the callback pointer.
        1. for unsuccess. The error messages are returns through the callback pointer.
=cut
#--------------------------------------------------------------------------------
sub monshow
{
  my $request=shift;
  my $callback=shift;
  
  my $pname=$request->{module}->[0];
  my $nodeinfo=$request->{nodeinfo}->[0];
  my $sum=$request->{priv}->[0];
  my $time=$request->{priv}->[1];
  my $attrs=$request->{priv}->[2];
  my $pe=$request->{priv}->[3];
  my $where=$request->{priv}->[4];

  my @nodes=split(',', $nodeinfo);

  xCAT_monitoring::monitorctrl->show([$pname], \@nodes,  $sum, $time, $attrs, $pe, $where, $callback); 
  return 0;
}

