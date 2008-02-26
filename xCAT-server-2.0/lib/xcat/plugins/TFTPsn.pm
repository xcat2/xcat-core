#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------
package xCAT_plugin::TFTPsn;
use xCAT::Table;

use xCAT::Utils;

use xCAT::MsgUtils;
use Getopt::Long;

#-------------------------------------------------------

=head1 
  xCAT plugin package to setup of tftp


#-------------------------------------------------------

=head3  handled_commands 

Check to see if on a Service Node
Check database to see if this node is a TFTP server
Call  setup_TFTP

=cut

#-------------------------------------------------------

sub handled_commands
{
    my $rc = 0;
    if (xCAT::Utils->isServiceNode())
    {
        my @nodeinfo   = xCAT::Utils->determinehostname;
        my $nodename   = $nodeinfo[0];
        my $nodeipaddr = $nodeinfo[1];
        my $service    = "tftpserver";

        $rc = xCAT::Utils->isServiceReq($nodename, $service, $nodeipaddr);
        if ($rc == 1)
        {

            # service needed on this Service Node
            $rc = &setup_TFTP($nodename);    # setup TFTP
            if ($rc == 0)
            {
                xCAT::Utils->update_xCATSN($service);
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

=head3 setup_TFTP 

    Sets up TFTP services  
	Check to see installed
	Enables in /etc/xinetd.d/tftp
	Makes /tftpboot directory
	Starts with xinetd

=cut

#-----------------------------------------------------------------------------
sub setup_TFTP
{
    my ($nodename) = @_;
    my $tftpdir    = "/tftpboot";              # default
    my $msg        = "Install: Setup TFTPD";

    # check to see if tftp is installed

    my $cmd = "/usr/sbin/in.tftpd -V";
    xCAT::Utils->runcmd($cmd, -1);
    if ($::RUNCMD_RC != 0)
    {                                          # not installed
        xCAT::MsgUtils->message("S", "tftp is not installed");
        return 1;
    }

    # read tftp directory from database, if it exists
    my @tftpdir1 = xCAT::Utils->get_site_attribute("tftpdir");
    if ($tftpdir1[0])
    {
        $tftpdir = $tftpdir1[0];
    }
    if (!(-e $tftpdir))
    {                                          # if it does not already exist
        mkdir($tftpdir);                       # creates the tftp directory
    }
    if (xCAT::Utils->isLinux())
    {

        # enable tftp

        my $cmd = "chkconfig tftp on";
        xCAT::Utils->runcmd($cmd, -1);
        if ($::RUNCMD_RC != 0)
        {
            xCAT::MsgUtils->message("S", "Error running $cmd");
            return 1;
        }
        my $cmd = "service xinetd restart";
        xCAT::Utils->runcmd($cmd, -1);
        if ($::RUNCMD_RC != 0)
        {
            xCAT::MsgUtils->message("S", "Error running $cmd");
            return 1;
        }

    }
    else    # AIX
    {

        # TBD AIX  tftp may already be enabled

    }
    return 0;
}
1;
