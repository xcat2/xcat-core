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

This runs on Service Node and on Management Server
Call  setup_TFTP  (actually setting up atftp)

=cut

#-------------------------------------------------------

sub handled_commands
{
    my @nodeinfo   = xCAT::Utils->determinehostname;
    my $nodename   = $nodeinfo[0];
    my $nodeipaddr = $nodeinfo[1];
    my $service    = "tftpserver";
    my $rc         = 0;
    my $setupTFTP  = 1;

    # setup atftp
    if (xCAT::Utils->isServiceNode())
    {

        # check to see if service required
        $rc = xCAT::Utils->isServiceReq($nodename, $service, $nodeipaddr);
        if ($rc != 1)    # service not required
        {
            return 0;
        }
    }
    $rc = &setup_TFTP($nodename);    # setup TFTP
    if ($rc == 0)
    {
        if (xCAT::Utils->isServiceNode())
        {
            xCAT::Utils->update_xCATSN($service);
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

    Sets up TFTP services (using atftp) 

=cut

#-----------------------------------------------------------------------------
sub setup_TFTP
{
    my ($nodename) = @_;
    my $rc         = 0;
    my $tftpdir    = "/tftpboot";    # default
    my $cmd;
    my $master;
    my $os;
    my $arch;
    $XCATROOT = "/opt/xcat";         # default

    if ($ENV{'XCATROOT'})
    {
        $XCATROOT = $ENV{'XCATROOT'};
    }

    if (xCAT::Utils->isServiceNode())
    {

        # read DB for nodeinfo
        my $retdata = xCAT::Utils->readSNInfo($nodename);
        $master = $retdata->{'master'};
        $os     = $retdata->{'os'};
        $arch   = $retdata->{'arch'};
        if (!($arch))
        {    # error
            return 1;
        }
    }
    else
    {        # on MS
        if (-e "/etc/SuSE-release")
        {
            $os = "su";
        }
        else
        {
            $os = "rh";
        }
    }

    # check to see if atftp is installed
    $cmd = "/usr/sbin/in.tftpd -V";
    my @output = xCAT::Utils->runcmd($cmd, -1);
    if ($::RUNCMD_RC != 0)
    {    # not installed
        xCAT::MsgUtils->message("S", "atftp is not installed");
        return 1;
    }
    if ($output[0] =~ "atftp")    # it is atftp
    {

        # read tftp directory from database, if it exists
        my @tftpdir1 = xCAT::Utils->get_site_attribute("tftpdir");
        if ($tftpdir1[0])
        {
            $tftpdir = $tftpdir1[0];
        }
        mkdir($tftpdir);
        if (xCAT::Utils->isServiceNode())
        {
            $cmd =
              "fgrep \"$master:$tftpdir $tftpdir nfs timeo=14,intr 1 2\" /etc/fstab";
            xCAT::Utils->runcmd($cmd, -1);
            if ($::RUNCMD_RC != 0)    # not already there
            {

                `echo "$master:$tftpdir $tftpdir nfs timeo=14,intr 1 2" >>/etc/fstab`;
            }
        }

        if ($os =~ /su|sl/i)          # sles
        {

            # setup atftp

            $cmd = "service tftpd restart";
            xCAT::Utils->runcmd($cmd, -1);
            if ($::RUNCMD_RC != 0)
            {
                xCAT::MsgUtils->message("S", "Error from command:$cmd");
                return 1;
            }
        }
        else
        {
            if ($os =~ /rh|fe/i)    # redhat/fedora
            {

                $cmd = "service tftpd restart";
                xCAT::Utils->runcmd($cmd, -1);
                if ($::RUNCMD_RC != 0)
                {
                    xCAT::MsgUtils->message("S", "Error from command:$cmd");
                    return 1;
                }
            }
            else
            {
                if ($os =~ /AIX/i)
                {

                    # TBD AIX

                }
            }
        }
    }
    else
    {    # no ATFTP
        xCAT::MsgUtils->message("S", "atftp is not installed");
        return 1;
    }
    return $rc;
}
1;
