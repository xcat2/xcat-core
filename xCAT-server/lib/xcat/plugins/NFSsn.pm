#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------
package xCAT_plugin::NFSsn;
use xCAT::Table;

use xCAT::Utils;

use xCAT::MsgUtils;
use File::Path;
use Getopt::Long;

#-------------------------------------------------------

=head1 
  xCAT plugin package to start nfs  on the Linux of AIX Service Node

#-------------------------------------------------------

=head3  handled_commands 

Check to see if on a Service Node
Check database to see if this node is a NFS server
Call  setup_NFS

=cut

#-------------------------------------------------------

sub handled_commands

{
    # If called in XCATBYPASS mode, don't do any setup
    if ($ENV{'XCATBYPASS'}) {
       return 0;
    }

    my $rc = 0;

    if (xCAT::Utils->isServiceNode())
    {
        my @nodeinfo   = xCAT::Utils->determinehostname;
        my $nodename   = pop @nodeinfo;                    # get hostname
        my @nodeipaddr = @nodeinfo;                        # get ip addresses
        my $service    = "nfsserver";
        $rc = xCAT::Utils->isServiceReq($nodename, $service, \@nodeipaddr);
        if ($rc == 1)
        {

            # service needed on this Service Node
            $rc = &setup_NFS($nodename);                   # setup NFS
            if ($rc == 0)
            {
                xCAT::Utils->update_xCATSN($service);
            }
        }
        else
        {
            if ($rc == 2)
            {    # just start the daemon
                if (xCAT::Utils->isLinux()) { 
                  system "service nfs restart";
                } else {  # AIX
                   system "stopsrc -s nfsd";
                   system "startsrc -s nfsd";
                }
                if ($? > 0)
                {    # error
                    xCAT::MsgUtils->message("S", "Error on command: $cmd");
                    return 1;
                }
            }
        }
    }
    return $rc;
}

#-------------------------------------------------------

=head3  process_request 

  Process the command

=cut

#-------------------------------------------------------
sub process_request
{
    return;
}

#-----------------------------------------------------------------------------

=head3 setup_NFS 

    Sets up NFS services on Service Node for AIX and Linux   

=cut

#-----------------------------------------------------------------------------
sub setup_NFS
{
    my ($nodename) = @_;
    my $rc = 0;
    if (xCAT::Utils->isLinux()) { 
      system "chkconfig nfs on";
      if ($? > 0)
      {    # error
          xCAT::MsgUtils->message("S", "Error on command:$cmd");
      }
    }

    # make sure nfs is restarted
    if (xCAT::Utils->isLinux()) { 
        system "service nfs restart";
    } else {  # AIX
        system "stopsrc -s nfsd";
        system "startsrc -s nfsd";
    }
    if ($? > 0)
    {
        xCAT::MsgUtils->message("S", "Error on command: $cmd");
        return 1;
    }

    return $rc;
}

1;
