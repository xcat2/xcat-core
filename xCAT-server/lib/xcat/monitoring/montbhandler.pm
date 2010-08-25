#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_monitoring::montbhandler;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

use lib "$::XCATROOT/lib/perl";
use xCAT::Table;
use xCAT::MsgUtils;
use xCAT::Utils;
use xCAT_plugin::notification;
use xCAT_monitoring::monitorctrl;

1;

#-------------------------------------------------------------------------------
=head1  xCAT_monitoring:montbhandler
=head2    Package Description
  xCAT monitoring table handler module. This is a helper module for monitorctrl module
  becuase the notification infrastructure does not allow a module to register more
  than one callbacks. This module registers and unregisters notification to watch for 
  the changes in the monitoring tables. When changes occurrs, it forward the info
  back to monitorctrl module for handling.
=cut
#-------------------------------------------------------------------------------




#--------------------------------------------------------------------------------
=head3    regMonitoringNotif
      It registers this module in the notification table to watch for changes in 
      the monitoring table.
    Arguments:
        none
    Returns:
        0 for successful.
        non-0 for not successful.
=cut
#--------------------------------------------------------------------------------
sub regMonitoringNotif {

  #register for nodelist table changes if not already registered
  my $tab = xCAT::Table->new('notification');
  my $regged=0;
  if ($tab) {
    (my $ref) = $tab->getAttribs({filename => qw(montbhandler.pm)}, 'tables');
    if ($ref and $ref->{tables}) {
       $regged=1;
    }
    $tab->close();
  }

  if (!$regged) {
    xCAT_plugin::notification::regNotification([qw(montbhandler.pm monsetting -o a,u,d)]);
  }
}

#--------------------------------------------------------------------------------
=head3    unregMonitoringNotif
      It un-registers this module in the notification table.
    Arguments:
        none
    Returns:
        0 for successful.
        non-0 for not successful.
=cut
#--------------------------------------------------------------------------------
sub unregMonitoringNotif {
  my $tab = xCAT::Table->new('notification');
  my $regged=0;
  if ($tab) {
    (my $ref) = $tab->getAttribs({filename => qw(montbhandler.pm)}, "tables");
    if ($ref and $ref->{tables}) {
       $regged=1;
    }
    $tab->close();
  }

  if ($regged) {
    xCAT_plugin::notification::unregNotification([qw(montbhandler.pm)]);
  }
}


#--------------------------------------------------------------------------------
=head3    processTableChanges
      It is called by the NotifHander module
      when the monitoring tables get changed.  If a plug-in
      is added or removed from the monitoring table. this function will start
      or stop the plug-in for monitoing the xCAT cluster.  
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
        0 for successful.
        non-0 for not successful.
=cut
#--------------------------------------------------------------------------------
sub processTableChanges {
  my $action=shift;
  if ($action =~ /xCAT_plugin::montbhandler/) {
    $action=shift;
  }
  my $tablename=shift;
  my $old_data=shift;
  my $new_data=shift;


  xCAT_monitoring::monitorctrl->processMonitoringTableChanges($action, $tablename, $old_data, $new_data);
  
}

