#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------
package xCAT_plugin::FTPsn;
use xCAT::Table;

use xCAT::Utils;
use File::Basename;
use File::Path;
use xCAT::MsgUtils;
use Getopt::Long;

#-------------------------------------------------------

=head1
  xCAT plugin package to setup vstftp on a  service node


#-------------------------------------------------------

=head3  handled_commands

This runs on Service Node
Checks servicenode table ftpserver attribute
Call  setup_TFTP  (actually setting up atftp)

=cut

#-------------------------------------------------------

sub handled_commands
{
    # If called in XCATBYPASS mode, don't do any setup
    if ($ENV{'XCATBYPASS'}) {
       return 0;
    }

    my $rc = 0;

    # setup vstftp
    if (xCAT::Utils->isServiceNode())
    {
        my @nodeinfo   = xCAT::Utils->determinehostname;
        my $nodename   = pop @nodeinfo;                    # get hostname
        my @nodeipaddr = @nodeinfo;                        # get ip addresses
        my $service    = "ftpserver";
        $rc = xCAT::Utils->isServiceReq($nodename, $service, \@nodeipaddr);
        if ($rc == 1)
        {

            $rc = &setup_FTP();                   # setup vsftpd
            if ($rc == 0)
            {
                xCAT::Utils->update_xCATSN($service);
            }
        }
        else
        {
            if ($rc == 2)
            {    # just start the daemon
                my $cmd = "service vsftpd restart";
                system $cmd;
                if ($? > 0)
                {    # error
                    xCAT::MsgUtils->message("S", "Error on command: $cmd");
                    return 1;
                }
            }
        }
    } else { # Management Node
            $rc = &setup_FTP();                   # setup vsftpd
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

=head3 setup_FTP

    Sets up FTP services (vstftp)

=cut

#-----------------------------------------------------------------------------
sub setup_FTP
{
    my $rc         = 0;
    my $cmd;
    $XCATROOT = "/opt/xcat";         # default

    if ($ENV{'XCATROOT'})
    {
        $XCATROOT = $ENV{'XCATROOT'};
    }

    # change ftp user id home directory to installdir
    # link installdir
    # restart the daemon
    my $installdir = "/install";     # default
                                     # read from database
    my @installdir1 = xCAT::Utils->get_site_attribute("installdir");
    if ($installdir1[0])             # if exists
    {
        $installdir = $installdir1[0];
    }
    if (!(-e $installdir))           # make it
    {
        mkpath($installdir);
    }
    $cmd = "usermod -d $installdir ftp";
    system $cmd;
    if ($? > 0) {

       xCAT::MsgUtils->message("S", "Error from command:$cmd");
    }

    # restart tftp

    my $cmd = "service vsftpd restart";
    system $cmd;
    if ($? > 0)
    {
        xCAT::MsgUtils->message("S", "Error from command:$cmd");
        return 1;
    }
    my $cmd = "chkconfig vsftpd on";
    system $cmd;
    if ($? > 0)
    {
        xCAT::MsgUtils->message("S", "Error from command:$cmd");
        return 1;
    }

    return $rc;
}
1;
