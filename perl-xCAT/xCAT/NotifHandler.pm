#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::NotifHandler;
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}
use lib "$::XCATROOT/lib/perl";

use File::Basename qw(fileparse);
use xCAT::Utils;
use Data::Dumper;

#%notif is a cache that holds the info from the "notification" table.
#the format of it is:
#   {tablename=>{'a'=>[filename,...]
#                'u'=>[filename,,..]
#                'd'=>[filename,...]
#                }
#   }
my %notif;
my $masterpid;
my $dbworkerid;

1;

#-------------------------------------------------------------------------------
=head1  xCATi::NotifHandler
=head2    Package Description
  This mondule caches the notification table and tracks the changes of it.
  It also handles the event notification when xCAT database changes.
=cut
#-------------------------------------------------------------------------------


#--------------------------------------------------------------------------------
=head3  setup
      It is called by xcatd to get set the pid of the parent of all this object.
      Setup the signal to trap any changes in the notification table. It also
      initializes the cache with the current data in the notification table.
      table and store it into %notif variable.
    Arguments:
      pid -- the process id of the caller.
      pid1 -- the process id of the dbworker.
    Returns:
      none
=cut
#-------------------------------------------------------------------------------
sub setup
{
  $masterpid=shift;
  if ($masterpid =~ /xCAT::NotifHandler/) {
    $masterpid=shift;
  }
  $dbworkerid=shift;

  refreshNotification();

  $SIG{USR1}=\&handleNotifSignal;
}

#--------------------------------------------------------------------------------
=head3  handleNotifSignal
      It is called when the signal is received. It then update the cache with the
      latest data in the notification table.
    Arguments:
      none.
    Returns:
      none
=cut
#-------------------------------------------------------------------------------
sub handleNotifSignal {
   #print "handleNotifSignal pid=$$\n";
   refreshNotification();
   $SIG{USR1}=\&handleNotifSignal;
}

#--------------------------------------------------------------------------------
=head3  sendNotifSignal
      It is called by any module that has made changes to the notification table.
    Arguments:
      none.
    Returns:
      none
=cut
#-------------------------------------------------------------------------------
sub sendNotifSignal {
  if ($masterpid) {
    kill('USR1', $masterpid);
  }
  if ($dbworkerid) {
    kill('USR1', $dbworkerid);
  }
}


#--------------------------------------------------------------------------------
=head3   refreshNotification
      It loads the notification info from the "notification"
      table and store it into %notif variable.
      The format of it is:
         {tablename=>{filename=>{'ops'=>['y/n','y/n','y/n'], 'disable'=>'y/n'}}}
    Arguments:
      none
    Returns:
      none
=cut
#-------------------------------------------------------------------------------
sub refreshNotification
{
  #print "refreshNotification get called\n";
  #flush the cache
  %notif=();
  my $table=xCAT::Table->new("notification", -create =>0);
  if ($table) {
    #get array of rows out of the notification table
    my @row_array= $table->getTable;
    if (@row_array) {
      #store the information to the cache
      foreach(@row_array) {
        my $module=$_->{filename};
        my $ops=$_->{tableops};
        my $disable= $_->{disable};
        my @tablenames=split(/,/, $_->{tables});

        foreach(@tablenames) {
          if (!exists($notif{$_})) {
            $notif{$_}={};
          }


          my $tempdisable=0;
          if ($disable) {
            if ($disable =~ m/^(yes|YES|Yes|Y|y|1)$/) {
              $tempdisable=1;
            }
          }

          if (!$disable) {
            if ($ops) {
              if ($ops =~ m/a/) {
                if (exists($notif{$_}->{a})) {
                  my $pa=$notif{$_}->{a};
                  push(@$pa, $module);
                } else {
                  $notif{$_}->{a}=[$module];
                }
              }
              if ($ops =~ m/d/) {
                if (exists($notif{$_}->{d})) {
                  my $pa=$notif{$_}->{d};
                  push(@$pa, $module);
                } else {
                  $notif{$_}->{d}=[$module];
                }
              }
              if ($ops =~ m/u/) {
                if (exists($notif{$_}->{u})) {
                  my $pa=$notif{$_}->{u};
                  push(@$pa, $module);
                } else {
                  $notif{$_}->{u}=[$module];
                }
              }
            } #end if
          }
        } #end foreach

      } #end foreach(@row_array)
    }#end if (@row_array)
  } #end if ($table)

   #print Dumper(%notif);
  return 1;
}


#--------------------------------------------------------------------------------
=head3   dumpNotificationCache
      It print out the content of the notification cache for debugging purpose.
    Arguments:
      none
    Returns:
      0
=cut
#-------------------------------------------------------------------------------
sub dumpNotificationCache {
  print "dump the notification cache:\n";
  foreach(keys(%notif)) {
    my $tmptn=$_;
    print " $tmptn: \n";

    if (exists($notif{$_}->{a})) {
      print "   a--:";
      my $files=$notif{$_}->{a};
      print "@$files\n";
    }
    if (exists($notif{$_}->{u})) {
      print "   u--:";
      my $files=$notif{$_}->{u};
      print "@$files\n";
    }
    if (exists($notif{$_}->{d})) {
      print "   d--:";
      my $files=$notif{$_}->{d};
      print "@$files\n";
    }
  }
  return 0;
}


#--------------------------------------------------------------------------------
=head3   needToNotify
      It check if the given table has interested parties watching for its changes.
    Arguments:
      tablename - the name of the table to be checked.
      tableop - the operation on the table. 'a' for add, 'u' for update
                and 'd' for delete.
    Returns:
      1 - if the table has interested parties.
      0 - if no parties are interested in its changes.
=cut
#-------------------------------------------------------------------------------
sub needToNotify {

  #print "needToNotify pid=$$, notify=" . Dumper(%notif) . "\n";

  if (!%notif) {
    # print "notif not defined\n";
    refreshNotification();
  }

  my $tablename=shift;
  if ($tablename =~ /xCAT::NotifHandler/) {
    $tablename=shift;
  }
  my $tableop=shift;

  if (%notif) {
    if (exists($notif{$tablename})) {
      if (exists($notif{$tablename}->{$tableop})) {
        return 1;
      }
    }
  }
  return 0;
}


#--------------------------------------------------------------------------------
=head3   notify
      It notifies the registered the modules with the latest changes in
      a DB table.
    Arguments:
      action - table action. It can be d for rows deleted, a for rows added
                    or u for rows updated.
      tablename - string. The name of the DB table whose data has been changed.
      old_data - an array reference of the old row data that has been changed.
           The first element is an array reference that contains the column names.
           The rest of the elelments are also array references each contains
           attribute values of a row.
           It is set when the action is u or d.
      new_data - a hash refernce of new row data; only changed values are present
           in the hash.  It is keyed by column names.
           It is set when the action is u or a.
    Returns:
      0
    Comments:
      If the curent table is watched by a perl module, the module must implement
      the following routine:
         processTableChanges(action, table_name, old_data, new_data)
      If it is a watched by a command, the data will be passed to the command
      through STDIN. The format is:
         action
         table_name
         [old data]
         col1_name,col2_name,...
         col1_value,col2_value,...
         ...
         [new data]
         col1_name,col2_name,...
         col1_value,col2_value,...
         ...

=cut
#-------------------------------------------------------------------------------
sub notify {
  my $action=shift;
  if ($action =~ /xCAT::NotifHandler/) {
    $action=shift;
  }
  my $tablename=shift;
  my $old_data=shift;
  my $new_data=shift;

  # print "notify called: tablename=$tablename, action=$action\n";

  my @filenames=();
  if (%notif) {
    if (exists($notif{$tablename})) {
      if (exists($notif{$tablename}->{$action})) {
        my $pa=$notif{$tablename}->{$action};
        @filenames=@$pa;
      }
    }
  }


  foreach(@filenames) {
    my ($modname, $path, $suffix) = fileparse($_, ".pm");
     # print "modname=$modname, path=$path, suffix=$suffix\n";
    if ($suffix =~ /.pm/) { #it is a perl module
	my $fname;
        if (($path eq "") || ($path eq ".\/")) {
          #default path is /opt/xcat/lib/perl/xCAT_monitoring/ if there is no path specified
          $fname = "$::XCATROOT/lib/perl/xCAT_monitoring/".$modname.".pm";
        } else {
          $fname = $_;
        }
        eval {require($fname)};
        if ($@) {
          print "The file $fname cannot be located or has compiling errors.\n";
        }
        else {
          ${"xCAT_monitoring::".$modname."::"}{processTableChanges}->($action, $tablename, $old_data, $new_data);
        }
        return 0;
    }
    else { #it is a command
      my $pid;
      if ($pid=xCAT::Utils->xfork()) { }
      elsif (defined($pid)) {
        # print "command=$_\n";
        if (open(CMD, "|$_")) {
          print(CMD "$action\n");
          print(CMD "$tablename\n");

          print(CMD  "[old data]\n");
          foreach (@$old_data) {
            print(CMD join(',', @$_)."\n");
          }

          print(CMD  "[new data]\n");
          if (%$new_data) {
            print(CMD join(',', keys %$new_data) . "\n");
            print(CMD join(',', values %$new_data) . "\n");
          }
          close(CMD) or print "Cannot close the command $_\n";
        }
        else {
          print "Command $_ cannot be found\n";
        }

        exit 0;
      } #elsif
    }
  }  #foreach

  return 0;
}

