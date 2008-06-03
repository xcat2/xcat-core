#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::notification;
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::Table;
use xCAT::NotifHandler;
1;

#-------------------------------------------------------------------------------
=head1  xCAT_plugin:notification
=head2    Package Description
  xCAT notification plugini module. This mondule allows users to register and
  unregister for the xCAT database table changes. 
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
#-------------------------------------------------------------------------------
sub handled_commands {
  return {
    regnotif => "notification",
    unregnotif => "notification",
    refnotif => "notification",
    lsnotif => "notification",
    enablenotif => "notification",
    disablenotif => "notification",
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
#-------------------------------------------------------------------------------
sub process_request {
  use Getopt::Long;
  # options can be bundled up like -vV
  Getopt::Long::Configure("bundling") ;
  $Getopt::Long::ignorecase=0;
  
  my $request = shift;
  my $callback = shift;
  my $command = $request->{command}->[0];
  my $args=$request->{arg};

  if ($command eq "regnotif") {
    my ($ret, $msg) = regNotification($args, $callback);
    if ($msg) {
      my %rsp=();
      $rsp->{dara}->[0]= $msg;
      $callback->($rsp);
    }
    return $ret;
  } 
  elsif ($command eq "unregnotif") {
    my ($ret, $msg) = unregNotification($args, $callback);
    if ($msg) {
      my %rsp=();
      $rsp->{data}->[0]= $msg;
      $callback->($rsp);
    }
    return $ret;
  } 
  else {
    my %rsp=();
    $rsp->{data}->[0]= "unsupported command: $command.";
    $callback->($rsp);
    return 1;
  }
}


#--------------------------------------------------------------------------------
=head3   regNotification
      It registers a notification routine or a command which
      will be called when there are changes in the data base tables
      that the routine/command is interested in.
    Arguments:
      args - The format of the args is:
         [-h|--help|-v|--version] or
          filename tablename[,tablename]... [-o|--operation tableop[,tableop][,tableop]]]
        where
          tablename - string. a list of comma seperated names of the tables whose changes
              will be watched.
          filename - string. The name of the module (e.g. /usr/lib/xxx.pm) or
              command (e.g. /usr/bin/xxx) that handles the notification.
              If it is a perl module, the module  must implement the following routine:
                processTableChanges(action, table_name, old_data, new_data)
              Refer to notify() subroutine for the meaning of the parameters.
              If it is a command, the command format should be:
                command [-d|-a|-u] tablename {[colnames][rowvalues][rowvalues]...} {[colnames][rowvalues]}
          tableop - it can be 'a' for add, 'd' for delete and 'u' for update.
      callback - the pointer to the callback function.
    Returns:
      none
    Comments:
       If the module or the command already exists in the notification table, this subroutine
       will replace it.
=cut
#-------------------------------------------------------------------------------
sub regNotification {
  my $args=shift;
  my $callback=shift;
  my $VERSION;
  my $HELP;
  my $tableops;

  # subroutine to display the usage
  sub regnotif_usage
  {
    my $callbk=shift;
    if (! $callbk) { return;}

    my %rsp;
    $rsp->{data}->[0]= "Usage:";
    $rsp->{data}->[1]= "  regnotif filename tablename[,tablename]... [-o|--operation tableop[,tableop][,tableop]]]";
    $rsp->{data}->[2]= "       where tableop can be 'a' for add, 'd' for delete and 'u' for update";
    $rsp->{data}->[3]= "  regnotif [-h|--help|-v|--version]";
    $callbk->($rsp);
  }
  
  @ARGV=@{$args};
  # parse the options
  if(!GetOptions(
      'o|operation=s' => \$tableops,
      'h|help'     => \$::HELP,
      'v|version'  => \$::VERSION,))
  {
    &regnotif_usage($callback);
    return;
  }

  # display the usage if -h or --help is specified
  if ($::HELP) { 
    &regnotif_usage($callback);
    return;
  }

  # display the version statement if -v or --verison is specified
  if ($::VERSION)
  {
    my %rsp;
    $rsp->{data}->[0]= "regnotif version 1.0";
    if ($callback) {
      $callback->($rsp);
    }
    return;
  }

  # must specify the file name and table names
  if (@ARGV < 2)
  {
    &regnotif_usage($callback);
    return;
  }

  #table operations must be a,d or u seperated by ','
  if ($tableops)
  {
    if ($tableops !~ m/^(a|d|u)(,(a|d|u)){0,2}$/) {
      my %rsp;
      $rsp->{data}->[0]= "Invalid table operations: $tableops";
      if ($callback) {
        $callback->($rsp);
      }
      return;
    }
  }
  else
  {
     $tableops="a,d,u";
  }
 
  my $fname=shift(@ARGV);
  my $table_names=shift(@ARGV);
  
  my $table=xCAT::Table->new("notification", -create => 1,-autocommit => 0);
  if ($table) {
    my %key_col = (filename=>$fname);
    my %tb_cols=(tables=>$table_names, tableops=>$tableops);
    $table->setAttribs(\%key_col, \%tb_cols);
    $table->commit;
  }

  #update notification cache
  xCAT::NotifHandler::sendNotifSignal();
  return;
}

#--------------------------------------------------------------------------------
=head3   unregNotification 
      It unregisters a notification routine or a command.
    Arguments:
      args - the format of the ares is:
          [-h|--help|-v|--version] or
          filename
        where
          filename - string. The name of the module or command that handles the notification.
      callback - the pointer to the callback funtion.
    Returns:
      none
=cut
#-------------------------------------------------------------------------------
sub unregNotification {
  my $args=shift;
  my $callback=shift;
  my $VERSION;
  my $HELP;

  # subroutine to display the usage
  sub unregnotif_usage
  {
    my $callbk=shift;
    if (! $callbk) { return;}

    my %rsp;
    $rsp->{data}->[0]= "Usage:";
    $rsp->{data}->[1]= "  unregnotif filename";
    $rsp->{data}->[2]= "  unregnotif [-h|--help|-v|--version]";
    $callbk->($rsp);
  }

  @ARGV=@{$args};
  # parse the options
  if(!GetOptions(
      'h|help'     => \$::HELP,
      'v|version'  => \$::VERSION,))
  {
    &unregnotif_usage($callback);
    return;
  }

  # display the usage if -h or --help is specified
  if ($::HELP) { 
    &unregnotif_usage($callback);
    return;
  }

  # display the version statement if -v or --verison is specified
  if ($::VERSION)
  {
    my %rsp;
    $rsp->{data}->[0]= "unregnotif version 1.0";
    if ($callback) {
      $callback->($rsp);
    }
    return;
  }

  # must specify the node range
  if (@ARGV < 1) {
    &unregnotif_usage($callback);
    return;
  }


  my $fname=shift(@ARGV);

  my $table=xCAT::Table->new("notification", -create => 1,-autocommit => 0);
  if ($table) {
    my %key_col = (filename=>$fname);
    $table->delEntries(\%key_col);
    $table->commit;
  }

  #update notification cache
  xCAT::NotifHandler::sendNotifSignal();
  return;
}

