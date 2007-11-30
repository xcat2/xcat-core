#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::monctrlcmds;
use xCAT::NodeRange;
use xCAT::Table;
use xCAT::MsgUtils;
require($::XCATPREFIX."/lib/xcat/monitoring/monitorctrl.pm");

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
    startmon => "monctrlcmds",
    stopmon => "monctrlcmds",
    updatemon => "monctrlcmds",
  }
}

#--------------------------------------------------------------------------------
=head3   process_request
      It processes the monitoring control commands.
    Arguments:
      request -- a hash table which contains the command name.
      callback -- a callback pointer to return the response to.
      args -- a list of arguments that come with the command. 
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
  
  my $request = shift;
  my $callback = shift;
  my $command = $request->{command}->[0];
  my $args=$request->{arg};

  if ($command eq "startmon") {
    my ($ret, $msg) = startmon($args, $callback);
    if ($msg) {
      my %rsp=();
      $rsp->{dara}->[0]= $msg;
      $callback->($rsp);
    }
    return $ret;
  } 
  elsif ($command eq "stopmon") {
    my ($ret, $msg) = stopmon($args, $callback);
    if ($msg) {
      my %rsp=();
      $rsp->{data}->[0]= $msg;
      $callback->($rsp);
    }
    return $ret;
  } 
  elsif ($command eq "updatemon") {
    xCAT_monitoring::monitorctrl::sendMonSignal();
  }
  else {
    my %rsp=();
    $rsp->{data}->[0]= "unsupported command: $command.";
    $callback->($rsp);
    return 1;
  }
}


#--------------------------------------------------------------------------------
=head3   startmon
        This function starts the given products for monitoring the xCAT cluster. 
    Arguments:
      callback - the pointer to the callback function.
      args - The format of the args is:
        [-h|--help|-v|--version] or
        [product_name[,product_name]...]        
        where
          product_name is the name of the monitoring product short name. 
          For example: Ganglia. The specified products will be started 
          for monitoring the xCAT cluster. 
    Returns:
        0 for success. The output is returned through the callback pointer.
        1. for unsuccess. The error messages are returns through the callback pointer.
=cut
#--------------------------------------------------------------------------------
sub startmon {
  my $args=shift;
  my $callback=shift;
  my $VERSION;
  my $HELP;

  # subroutine to display the usage
  sub startmon_usage
  {
    my %rsp;
    $rsp->{data}->[0]= "Usage:";
    $rsp->{data}->[1]= "  startmon [product_name[,product_name]...]";
    $rsp->{data}->[2]= "  startmon [-h|--help|-v|--version]";
    $rsp->{data}->[3]= "     product_name is the name of the monitoring product registered in the monitoring table.";
    $callback->($rsp);
  }
  
  @ARGV=@{$args};

  # parse the options
  if(!GetOptions(
      'h|help'     => \$::HELP,
      'v|version'  => \$::VERSION,))
  {
    &startmon_usage;
    return;
  }

  # display the usage if -h or --help is specified
  if ($::HELP) { 
    &startmon_usage;
    return;
  }

  # display the version statement if -v or --verison is specified
  if ($::VERSION)
  {
    my %rsp;
    $rsp->{data}->[0]= "startmon version 1.0";
    $callback->($rsp);
    return;
  }

  my @product_names;
  if (@ARGV < 1)
  {
    &startmon_usage;
    return;
  }
  else {
    @product_names=split(/,/, $ARGV[0]);
  }

  my %ret = xCAT_monitoring::monitorctrl::startMonitoring(@product_names);
  
  my %rsp;
  $rsp->{data}->[0]= "starting @product_names";
  my $i=1;
  foreach (keys %ret) {
    my $ret_array=$ret{$_};
    $rsp->{data}->[$i++]= "$_: $ret_array->[1]";
  }

  my $nodestatmon=xCAT_monitoring::monitorctrl::nodeStatMonName();
  if ($nodestatmon) {
    foreach (@product_names) {
      if ($_ eq $nodestatmon) { 
	my ($code, $msg)=xCAT_monitoring::monitorctrl::startNodeStatusMonitoring($nodestatmon);
        $rsp->{data}->[$i++]="node status monitoring with $nodestatmon: $msg"; 
      }
    }
  }

  $rsp->{data}->[$i++]="done.";
  $callback->($rsp);
  
  return;
}

#--------------------------------------------------------------------------------
=head3   stopmon
        This function stops the given products for monitoring the xCAT cluster.
    Arguments:
      callback - the pointer to the callback function.
      args - The format of the args is:
        [-h|--help|-v|--version] or
        [product_name[,product_name]...]
        where
          product_name is the name of the monitoring product short name.
          For example: Ganglia. The specified products will be stoped
          for monitoring the xCAT cluster. 
    Returns:
        0 for success. The output is returned through the callback pointer.
        1. for unsuccess. The error messages are returns through the callback pointer.
=cut
#--------------------------------------------------------------------------------
sub stopmon {
  my $args=shift;
  my $callback=shift;
  my $VERSION;
  my $HELP;

  # subroutine to display the usage
  sub stopmon_usage
  {
    my %rsp;
    $rsp->{data}->[0]= "Usage:";
    $rsp->{data}->[1]= "  stopmon [product_name[,product_name]...]";
    $rsp->{data}->[2]= "  stopmon [-h|--help|-v|--version]";
    $rsp->{data}->[3]= "      product_name is the name of the monitoring product registered in the montoring table.";
    $callback->($rsp);
  }

  @ARGV=@{$args};
  # parse the options
  if(!GetOptions(
      'h|help'     => \$::HELP,
      'v|version'  => \$::VERSION,))
  {
    &stopmon_usage;
    return;
  }

  # display the usage if -h or --help is specified
  if ($::HELP) { 
    &stopmon_usage;
    return;
  }

  # display the version statement if -v or --verison is specified
  if ($::VERSION)
  {
    my %rsp;
    $rsp->{data}->[0]= "stopmon version 1.0";
    $callback->($rsp);
    return;
  }


  my @product_names;
  if (@ARGV < 1)
  {
    &startmon_usage;
    return;
  }
  else {
    @product_names=split(/,/, $ARGV[0]);
  }

  my %ret = xCAT_monitoring::monitorctrl::stopMonitoring(@product_names);
  my %rsp;
  $rsp->{data}->[0]= "stopping @product_names";
  my $i=1;
  foreach (keys %ret) {
    my $ret_array=$ret{$_};
    $rsp->{data}->[$i++]= "$_: $ret_array->[1]";
  }

  my $nodestatmon=xCAT_monitoring::monitorctrl::nodeStatMonName();
  if ($nodestatmon) {
    foreach (@product_names) {
      if ($_ eq $nodestatmon) { 
	my ($code, $msg)=xCAT_monitoring::monitorctrl::stopNodeStatusMonitoring($nodestatmon);
        $rsp->{data}->[$i++]="node status monitoring with $nodestatmon: $msg"; 
      }
    }
  }
  $rsp->{data}->[$i++]="done.";
  $callback->($rsp);
  
  return;
}







