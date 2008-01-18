#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::monctrlcmds;
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use xCAT::NodeRange;
use xCAT::Table;
use xCAT::MsgUtils;
use xCAT_monitoring::monitorctrl;

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
        This function registers the given monitoring plug-in to the 'monitoring' table.
        xCAT will invoke the monitoring plug-in to start the 3rd party software, which
        this plug-in connects to, to monitor the xCAT cluster. 
    Arguments:
      callback - the pointer to the callback function.
      args - The format of the args is:
        [-h|--help|-v|--version] or
        name [-n|--nodestatmon]        
        where
          name is the monitoring plug-in name. For example: rmcmon. 
              The specified plug-in will be registered and invoked 
              for monitoring the xCAT cluster.
          -n|--nodestatmon  indicates that this plug-in will be used for feeding the node liveness
              status to the xCAT nodelist table.  If not specified, the plug-in will not be used 
              for feeding node status to xCAT. 
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
    $rsp->{data}->[1]= "  startmon name [-n|--nodestatmon]";
    $rsp->{data}->[2]= "  startmon [-h|--help|-v|--version]";
    $rsp->{data}->[3]= "     name is the name of the monitoring plug-in to be registered and invoked.";
    $callback->($rsp);
  }
  
  @ARGV=@{$args};

  # parse the options
  if(!GetOptions(
      'h|help'     => \$::HELP,
      'v|version'  => \$::VERSION,
      'n|nodestatmon'  => \$::NODESTATMON))
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

  #my @product_names;
  my $pname;
  if (@ARGV < 1)
  {
    &startmon_usage;
    return;
  }
  else {
    #@product_names=split(/,/, $ARGV[0]);
    $pname=$ARGV[0];
    $file_name="$::XCATROOT/lib/perl/xCAT_monitoring/$pname.pm";
      if (!-e $file_name) {
        my %rsp;
        $rsp->{data}->[0]="File $file_name does not exist.";
        $callback->($rsp);
        return 1;
      }  else {
        #load the module in memory
        eval {require($file_name)};
        if ($@) {   
          my %rsp;
          $rsp->{data}->[0]="The file $file_name has compiling errors:\n$@\n";
          $callback->($rsp);
          return 1;  
        }      
      }
  }

  #my %ret = xCAT_monitoring::monitorctrl::startMonitoring(@product_names);
  
  #my %rsp;
  #$rsp->{data}->[0]= "starting @product_names";
  #my $i=1;
  #foreach (keys %ret) {
  #  my $ret_array=$ret{$_};
  #  $rsp->{data}->[$i++]= "$_: $ret_array->[1]";
  #}

  #my $nodestatmon=xCAT_monitoring::monitorctrl::nodeStatMonName();
  #if ($nodestatmon) {
  #  foreach (@product_names) {
  #    if ($_ eq $nodestatmon) { 
  #	my ($code, $msg)=xCAT_monitoring::monitorctrl::startNodeStatusMonitoring($nodestatmon);
  #      $rsp->{data}->[$i++]="node status monitoring with $nodestatmon: $msg"; 
  #    }
  #  }
  #}

  my $table=xCAT::Table->new("monitoring", -create => 1,-autocommit => 1);
  if ($table) {
    (my $ref) = $table->getAttribs({name => $pname}, name);
    if ($ref and $ref->{name}) {
      my %rsp;
      $rsp->{data}->[0]="$pname is already registered in the monitoring table.";
      $callback->($rsp);
    }
    else {
      my %key_col = (name=>$pname);
      my $nstat='N';
      if ($::NODESTATMON) {
	$nstat='Y';
      }
      my %tb_cols=(nodestatmon=>$nstat);
      $table->setAttribs(\%key_col, \%tb_cols);
    }   
  }

  my %rsp1;
  $rsp1->{data}->[0]="done.";
  $callback->($rsp1);

  return;
}

#--------------------------------------------------------------------------------
=head3   stopmon
        This function unregisters the given monitoring plug-in from the 'monitoring' table.
        xCAT will ask the monitoring plug-in to stop the 3rd party software, which
        this plug-in connects to, to monitor the xCAT cluster. 
    Arguments:
      callback - the pointer to the callback function.
      args - The format of the args is:
        [-h|--help|-v|--version] or
        name
        where
          name is the monitoring plug-in name. For example: rmcmon. 
              The specified plug-in will be un-registered and stoped  
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
    $rsp->{data}->[1]= "  stopmon name";
    $rsp->{data}->[2]= "  stopmon [-h|--help|-v|--version]";
    $rsp->{data}->[3]= "      name is the name of the monitoring plug-in registered in the monitoring table.";
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


  #my @product_names;
  my $pname;
  if (@ARGV < 1)
  {
    &stopmon_usage;
    return;
  }
  else {
    #@product_names=split(/,/, $ARGV[0]);
    $pname=$ARGV[0];
  }

  #my %ret = xCAT_monitoring::monitorctrl::stopMonitoring(@product_names);
  #my %rsp;
  #$rsp->{data}->[0]= "stopping @product_names";
  #my $i=1;
  #foreach (keys %ret) {
  #  my $ret_array=$ret{$_};
  #  $rsp->{data}->[$i++]= "$_: $ret_array->[1]";
  #}

  #my $nodestatmon=xCAT_monitoring::monitorctrl::nodeStatMonName();
  #if ($nodestatmon) {
  #  foreach (@product_names) {
  #    if ($_ eq $nodestatmon) { 
  #	my ($code, $msg)=xCAT_monitoring::monitorctrl::stopNodeStatusMonitoring($nodestatmon);
  #      $rsp->{data}->[$i++]="node status monitoring with $nodestatmon: $msg"; 
  #    }
  #  }
  #}
  my $table=xCAT::Table->new("monitoring", -create => 1,-autocommit => 1);
  if ($table) {
    (my $ref) = $table->getAttribs({name => $pname}, name);
    if ($ref and $ref->{name}) {
      my %key_col = (name=>$pname);
      $table->delEntries(\%key_col);
    }
    else {
      my %rsp;
      $rsp->{data}->[0]="$pname is not registered in the monitoring table.";
      $callback->($rsp);
    }   
  }

  my %rsp1;
  $rsp1->{data}->[0]="done.";
  $callback->($rsp1);
  
  return;
}







