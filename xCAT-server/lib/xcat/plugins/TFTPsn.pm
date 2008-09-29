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
  xCAT plugin package to setup  atftp on a service node 


#-------------------------------------------------------

=head3  handled_commands 

This runs on Service Node  ( only sets up for Linux)
Checks servicenode table tfpserver attribute
Call  setup_TFTP  (actually setting up atftp)

=cut

#-------------------------------------------------------

sub handled_commands
{
    # If called in XCATBYPASS mode, don't do any setup
    if ($ENV{'XCATBYPASS'}) {
       return 0;
    }
    if (xCAT::Utils->isAIX()) { # do not run on AIX
       return 0;
    }


    my $rc = 0;

    # setup atftp
    if (xCAT::Utils->isServiceNode())
    {
        my @nodeinfo   = xCAT::Utils->determinehostname;
        my $nodename   = pop @nodeinfo;                    # get hostname
        my @nodeipaddr = @nodeinfo;                        # get ip addresses
        my $service    = "tftpserver";
        $rc = xCAT::Utils->isServiceReq($nodename, $service, \@nodeipaddr);
        if ($rc == 1)
        {

            $rc = &setup_TFTP($nodename);                  # setup TFTP (ATFTP)
            if ($rc == 0)
            {
                xCAT::Utils->update_xCATSN($service);
            }
        }
        else
        {
            if ($rc == 2)
            {    # just start the daemon
                my $cmd = "service tftpd start";
                system $cmd;
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

    # read DB for nodeinfo
    my $retdata = xCAT::Utils->readSNInfo($nodename);
    $master = $retdata->{'master'};
    $os     = $retdata->{'os'};
    $arch   = $retdata->{'arch'};
    if (!($arch))
    {    # error
        xCAT::MsgUtils->message("S", " Error reading service node arch.");
        return 1;
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

        # read tftpdir directory from database
        my @tftpdir1 = xCAT::Utils->get_site_attribute("tftpdir");
        if ($tftpdir1[0])
        {
            $tftpdir = $tftpdir1[0];
        }
        if (!(-e $tftpdir))
        {
            mkdir($tftpdir);
        }

        # check to see if tftp directory already mounted
        my $mounted = xCAT::Utils->isMounted($tftpdir);
        if ($mounted == 0)    # not already mounted
        {

            # need to  mount the directory
            my $cmd = " mount -o rw,nolock $master:$tftpdir $tftpdir";
            system $cmd;
            if ($? > 0)
            {                 # error
                $rc = 1;
                xCAT::MsgUtils->message("S", "Error $cmd");
            }
        }

        # start atftp

        $cmd = "service tftpd stop";
        system $cmd;
        if ($? > 0)
        {
            xCAT::MsgUtils->message("S", "Error from command:$cmd");
        }
        $cmd = "service tftpd start";
        system $cmd;
        if ($? > 0)
        {
            xCAT::MsgUtils->message("S", "Error from command:$cmd");
            return 1;
        }
    }
    else
    {    # no ATFTP
        xCAT::MsgUtils->message("S", "atftp is not installed");
        return 1;
    }

    if ($rc == 0)
    {

        # update fstab so that it will restart on reboot
        $cmd =
          "fgrep \"$master:$tftpdir $tftpdir nfs timeo=14,intr 1 2\" /etc/fstab";
        xCAT::Utils->runcmd($cmd, -1);
        if ($::RUNCMD_RC != 0)    # not already there
        {

            `echo "$master:$tftpdir $tftpdir nfs timeo=14,intr 1 2" >>/etc/fstab`;
        }
    }

    return $rc;
}
1;
