#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT_plugin::updatenode;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use strict;
use warnings;
use xCAT::Table;
use xCAT::Schema;
use Data::Dumper;
use xCAT::Utils;
use Getopt::Long;
use xCAT::GlobalDef;
use Sys::Hostname;
use xCAT::GlobalDef;
use xCAT_monitoring::monitorctrl;

1;


#-------------------------------------------------------------------------------
=head1  xCAT_plugin:updatenode
=head2    Package Description
  xCAT plug-in module. It handles the updatenode command.
=cut
#------------------------------------------------------------------------------

#--------------------------------------------------------------------------------
=head3   handled_commands
      It returns a list of commands handled by this plugin.
    Arguments:
        none
    Returns:
        a list of commands.
=cut
#--------------------------------------------------------------------------------
sub handled_commands
{
  return {
    updatenode     => "updatenode",
    updatenodestat     => "updatenode"};
}


#-------------------------------------------------------
=head3  preprocess_request
  Check and setup for hierarchy 
=cut
#-------------------------------------------------------
sub preprocess_request
{
    my $request  = shift;
    my $callback = shift;
    my $subreq = shift;
    my $command  = $request->{command}->[0];
    #if ($request->{_xcatdest}) { return [$request]; }    #exit if preprocessed
    #if already preprocessed, go straight to request
    if ($request->{_xcatpreprocessed}->[0] == 1) { return [$request]; }

    my @requests=();

    if ($command eq "updatenode")
    {
      return preprocess_updatenode($request, $callback, $subreq);
    } elsif ($command eq "updatenodestat") {
      return [$request];
    }
    else {
      my $rsp={};
      $rsp->{data}->[0]= "unsupported command: $command.";
      $callback->($rsp);
      return \@requests;
    }    
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
sub process_request
{
    my $request  = shift;
    my $callback = shift;
    my $subreq = shift;
    my $command  = $request->{command}->[0];
    my $localhostname=hostname();

    if ($command eq "updatenode") {
       return updatenode($request, $callback, $subreq);
    } elsif ($command eq "updatenodestat") {
       return updatenodestat($request, $callback);
    } else {
	my $rsp={};
	$rsp->{data}->[0]= "$localhostname: unsupported command: $command.";
	$callback->($rsp);
	return 1;
    } 
}


#--------------------------------------------------------------------------------
=head3   preprocess_updatenode
        This function checks for the syntax of the updatenode command
     and distribute the command to the right server. 
    Arguments:
      request - the request. The request->{arg} is of the format:
            [-h|--help|-v|--version] or
            [noderange [-s | -S] [postscripts]]         
      callback - the pointer to the callback function.
    Returns:
      A pointer to an array of requests.
=cut
#--------------------------------------------------------------------------------
sub preprocess_updatenode {
  my $request = shift;
  my $callback = shift;
  my $subreq = shift;
  my $args=$request->{arg};
  my @requests=();

  # subroutine to display the usage
  sub updatenode_usage
  {
    my $cb=shift;
    my $rsp={};
    $rsp->{data}->[0]= "Usage:";
    $rsp->{data}->[1]= "  updatenode [-h|--help|-v|--version]";
    $rsp->{data}->[2]= "  updatenode <noderange> [-V|--verbose] [-F|--sync] [-S|--sw] [-P|--scripts [script1,script2,...]]";
    $rsp->{data}->[3]= "  updatenode <noderange> [-V|--verbose] [script1,script2,...]";
    $rsp->{data}->[4]= "     <noderange> is a list of nodes or groups.";
    $rsp->{data}->[5]= "     -F|--sync: Perform File Syncing.";
    $rsp->{data}->[6]= "     -S|--sw: Perform Software Maintenance.";
    $rsp->{data}->[7]= "     -P|--scripts: Perform Postscripts listed in postscripts table or parameters.";
    $rsp->{data}->[8]= "     [script1,script2,...] is a comma separated list of postscript names.";
    $rsp->{data}->[9]= "         If omitted, all the postscripts defined for the nodes will be run.";
    $cb->($rsp);
  }
  
  @ARGV=();
  if ($args) {
    @ARGV=@{$args};
  }


  # parse the options
  Getopt::Long::Configure("bundling");
  Getopt::Long::Configure("no_pass_through");
  if(!GetOptions(
      'h|help'      => \$::HELP,
      'v|version'  => \$::VERSION,
      'V|verbose'   => \$::VERBOSE,
      'F|sync'              => \$::FILESYNC,
      'S|sw'              => \$::SWMAINTENANCE,
      'P|scripts:s'           => \$::RERUNPS))
  {
    &updatenode_usage($callback);
    return  \@requests;;
  }

  # display the usage if -h or --help is specified
  if ($::HELP) { 
    &updatenode_usage($callback);
    return  \@requests;;
  }

  # display the version statement if -v or --verison is specified
  if ($::VERSION)
  {
    my $rsp={};
    $rsp->{data}->[0]= xCAT::Utils->Version();
    $callback->($rsp);
    return  \@requests;
  }
 
  # the -P flag is omitted when only postscritps are specified, 
  # so if there are parameters without any flags, it means
  # to re-run the postscripts.
  if (@ARGV) {
    if ($#ARGV == 0 &&
        !($::FILESYNC || $::SWMAINTENANCE || defined($::RERUNPS)) ) {
      $::RERUNPS = $ARGV[0];
    } else {
      &updatenode_usage($callback);
      return  \@requests;
    }
  } else {
    if ( !($::FILESYNC || $::SWMAINTENANCE || defined($::RERUNPS)) ) {
      $::FILESYNC = 1;
      $::SWMAINTENANCE = 1;
      $::RERUNPS = "";
    }
  } 

  my $nodes = $request->{node};
  if (!$nodes) {
    &updatenode_usage($callback);
    return  \@requests;;
  }

  my @nodes=@$nodes; 
  my $postscripts;

  if (@nodes == 0) { return \@requests; }

  # handle the re-run postscripts option -P
  if (defined ($::RERUNPS)) {
    if ($::RERUNPS eq "") {
      $postscripts = "";
    } else {
      $postscripts=$::RERUNPS;
      my @posts=split(',',$postscripts);
      foreach (@posts) { 
        if ( ! -e "/install/postscripts/$_") {
          my $rsp={};
          $rsp->{data}->[0]= "The postcript /install/postscripts/$_ does not exist.";
          $callback->($rsp);
          return \@requests;
        }
      }
    }
  }

  # If -F option specified, sync files to the noderange.
  # Note: This action only happens on MN, since xdcp handles the hierarchical scenario
  if ($::FILESYNC) {
    my $reqcopy = {%$request};
    $reqcopy->{FileSyncing}->[0] = "yes";
    push @requests, $reqcopy;
  }

  # when specified -S or -P
  # find service nodes for requested nodes
  # build an individual request for each service node
  unless (defined($::SWMAINTENANCE) || defined($::RERUNPS)) {
    return \@requests; 
  }
  
  my $sn = xCAT::Utils->get_ServiceNode(\@nodes, "xcat", "MN");
    
  # build each request for each service node
  foreach my $snkey (keys %$sn)
  {
    #print "sn=$snkey\n";
    my $reqcopy = {%$request};
    $reqcopy->{node} = $sn->{$snkey};
    $reqcopy->{'_xcatdest'} = $snkey;
    $reqcopy->{_xcatpreprocessed}->[0] = 1;

    if (defined ($::SWMAINTENANCE)) {
      $reqcopy->{swmaintenance}->[0] = "yes";
    }
    if (defined ($::RERUNPS)) {
      $reqcopy->{rerunps}->[0] = "yes";
      $reqcopy->{postscripts} = [$postscripts];
    }
    
    push @requests, $reqcopy;
  }
  
  return \@requests;    
}



#--------------------------------------------------------------------------------
=head3   updatenode
        This function implements the updatenode command. 
    Arguments:
      request - the request.        
      callback - the pointer to the callback function.
    Returns:
        0 for success. The output is returned through the callback pointer.
        1. for unsuccess. The error messages are returns through the callback pointer.
=cut
#--------------------------------------------------------------------------------
sub updatenode {
  my $request = shift;
  my $callback = shift;
  my $subreq = shift;
  #print Dumper($request);

  my $nodes      =$request->{node};  
  my $localhostname=hostname();

  if ($request->{FileSyncing} && $request->{FileSyncing}->[0] eq "yes") {
    my %syncfile_node = ();
    my %syncfile_rootimage = ();
    my $node_syncfile = xCAT::SvrUtils->getsynclistfile($nodes);
    foreach my $node (@$nodes) {
      my $synclist = $$node_syncfile{$node};

      if ($synclist) {
        push @{$syncfile_node{$synclist}}, $node;
      }
    }

    # Sync files to the target nodes
    foreach my $synclist (keys %syncfile_node) {
      my $args = ["-F", "$synclist"];
      my $env = ["DSH_RSYNC_FILE=$synclist"];
      $subreq->({command=>['xdcp'], node=>$syncfile_node{$synclist}, arg=>$args, env=>$env}, $callback);
    }
    my $rsp={};
    $rsp->{data}->[0]= "Complete the File Syncing";
    $callback->($rsp);
  }

  if ($request->{swmaintenance} && $request->{swmaintenance}->[0] eq "yes") {
    my $cmd;
    my $nodestring=join(',', @$nodes);
    if (xCAT::Utils->isLinux()) {
      $cmd="XCATBYPASS=Y $::XCATROOT/bin/xdsh $nodestring -s -e /install/postscripts/xcatdsklspost 2 otherpkgs 2>&1";
    }
    else {
      my $rsp={};
      $rsp->{data}->[0]= "Dose not support Software Maintenance for AIX nodes";
      $callback->($rsp); 
    }
    if ($cmd && ! open (CMD, "$cmd |")) {
      my $rsp={};
      $rsp->{data}->[0]= "Cannot run command $cmd";
      $callback->($rsp);    
    } else {
      while (<CMD>) {
        my $rsp={};
        my $output = $_;
        if ($output =~ /returned from postscript/) {
          $output =~ s/returned from postscript/Complete the Software Maintenance/;
        }
        $rsp->{data}->[0]= "$output";
        $callback->($rsp);
      }
      close(CMD);
    }
  }

  if ($request->{rerunps} && $request->{rerunps}->[0] eq "yes") {
    my $postscripts="";
    if (($request->{postscripts}) && ($request->{postscripts}->[0])) {  $postscripts=$request->{postscripts}->[0];}

    my $nodestring=join(',', @$nodes);
    #print "postscripts=$postscripts, nodestring=$nodestring\n";
  
    if ($nodestring) {
      my $cmd;
      if (xCAT::Utils->isLinux()) {
        $cmd="XCATBYPASS=Y $::XCATROOT/bin/xdsh $nodestring -s -e /install/postscripts/xcatdsklspost 1 $postscripts 2>&1";
      }
      else {
        $cmd="XCATBYPASS=Y $::XCATROOT/bin/xdsh $nodestring -s -e /install/postscripts/xcataixpost -c 1 $postscripts 2>&1";
      }
      if (! open (CMD, "$cmd |")) {
        my $rsp={};
        $rsp->{data}->[0]= "Cannot run command $cmd";
        $callback->($rsp);    
      } else {
        while (<CMD>) {
          my $rsp={};
          my $output = $_;
          if ($output =~ /returned from postscript/) {
            $output =~ s/returned from postscript/Complete the Running Postscripts/;
          }
          $rsp->{data}->[0]= "$output";
          $callback->($rsp);
        }
        close(CMD);
      }
    }
  }

  return 0;  
}


sub updatenodestat {
  my $request = shift;
  my $callback = shift;
  my @nodes=();
  my @args=();
  if (ref($request->{node})) {
    @nodes = @{$request->{node}};
  } else {
     if ($request->{node}) { @nodes = ($request->{node}); }
  }
  if (ref($request->{arg})) {
    @args=@{$request->{arg}};
  } else {
    @args=($request->{arg});
  }

  if ((@nodes>0) && (@args>0)) {
    my %node_status=();
    my $stat=$args[0];
    $node_status{$stat}=[];
    foreach my $node (@nodes) {
       my $pa=$node_status{$stat};
       push(@$pa, $node);
    }
    xCAT_monitoring::monitorctrl::setNodeStatusAttributes(\%node_status, 1);     
  }

  return 0;
}





