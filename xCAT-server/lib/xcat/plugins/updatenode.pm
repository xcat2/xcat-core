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
    my $command  = $request->{command}->[0];
    if ($request->{_xcatdest}) { return [$request]; }    #exit if preprocessed
    my @requests=();

    if ($command eq "updatenode")
    {
      return preprocess_updatenode($request, $callback);
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
    my $command  = $request->{command}->[0];
    my $localhostname=hostname();

    if ($command eq "updatenode") {
       return updatenode($request, $callback);
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
            [noderange [postscripts]]         
      callback - the pointer to the callback function.
    Returns:
      A pointer to an array of requests.
=cut
#--------------------------------------------------------------------------------
sub preprocess_updatenode {
  my $request = shift;
  my $callback = shift;
  my $args=$request->{arg};
  my @requests=();

  # subroutine to display the usage
  sub updatenode_usage
  {
    my $cb=shift;
    my $rsp={};
    $rsp->{data}->[0]= "Usage:";
    $rsp->{data}->[1]= "  updatenode <noderange> [posts]";
    $rsp->{data}->[2]= "  updatenode [-h|--help|-v|--version]";
    $rsp->{data}->[3]= "     noderange is a list of nodes or groups.";
    $rsp->{data}->[4]= "     posts is a comma separated list of postscript names.";
    $rsp->{data}->[5]= "     if omitted, all the postscripts will be run.";
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
      'h|help'     => \$::HELP,
      'v|version'  => \$::VERSION))
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
  
  my $nodes = $request->{node};
  if (!$nodes) {
    &updatenode_usage($callback);
    return  \@requests;;
  }

  my @nodes=@$nodes; 
  my $postscripts;

  if (@nodes == 0) { return \@requests; }

  if (@ARGV > 0) {
    $postscripts=$ARGV[0];
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

  # find service nodes for requested nodes
  # build an individual request for each service node
  my $sn = xCAT::Utils->get_ServiceNode(\@nodes, "xcat", "MN");
    
  # build each request for each service node
  foreach my $snkey (keys %$sn)
  {
    my $reqcopy = {%$request};
    $reqcopy->{node} = $sn->{$snkey};
    $reqcopy->{'_xcatdest'} = $snkey;
    $reqcopy->{postscripts} = [$postscripts];
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
  my $postscripts="";
  if (($request->{postscripts}) && ($request->{postscripts}->[0])) {  $postscripts=$request->{postscripts}->[0];}
  my $nodes      =$request->{node};  
  my $localhostname=hostname();

  my $nodestring=join(',', @$nodes);
  #print "postscripts=$postscripts, nodestring=$nodestring\n";

  if ($nodestring) {
    my $output;
    if (xCAT::Utils->isLinux()) {
      $output=`XCATBYPASS=Y $::XCATROOT/bin/xdsh $nodestring -e /install/postscripts/xcatdsklspost 1 $postscripts 2>&1`;
    }
    else {
      $output=`XCATBYPASS=Y $::XCATROOT/bin/xdsh $nodestring -e /install/postscripts/xcataixpost 1 $postscripts 2>&1`;
    }
    my $rsp={};
    $rsp->{data}->[0]= "$output\n";
    $callback->($rsp);
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





