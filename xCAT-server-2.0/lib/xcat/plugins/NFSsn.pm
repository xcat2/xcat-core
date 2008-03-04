#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------
package xCAT_plugin::NFSsn;
use xCAT::Table;

use xCAT::Utils;

use xCAT::MsgUtils;
use Getopt::Long;

#-------------------------------------------------------

=head1 
  xCAT plugin package to setup of nfs and mount /install 
  and /tfptboot


#-------------------------------------------------------

=head3  handled_commands 

Check to see if on a Service Node
Check database to see if this node is a NFS server
   should be always
Call  setup_NFS

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
        my $service    = "nfsserver";
        $rc = xCAT::Utils->isServiceReq($nodename, $service, $nodeipaddr);
        if ($rc == 1)
        {

            # service needed on this Service Node
            $rc = &setup_NFS($nodename);    # setup NFS
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

=head3 setup_NFS 

    Sets up NFS services and mounts /install and /tftpboot 
	on /install and /tftpboot from Master Node  

=cut

#-----------------------------------------------------------------------------
sub setup_NFS
{
    my ($nodename) = @_;
    my $rc         = 0;
    my $tftpdir    = "/tftpboot";    # default
    my $installdir = "/install";     # default

    # read DB for nodeinfo
    my $master;
    my $os;
    my $arch;
    my $retdata = xCAT::Utils->readSNInfo($nodename);
    if ($retdata->{'arch'})
    {                                # no error
        $master = $retdata->{'master'};
        $os     = $retdata->{'os'};
        $arch   = $retdata->{'arch'};

        # read install directory from database, if it exists
        my @installdir1 = xCAT::Utils->get_site_attribute("installdir");
        if ($installdir1[0])
        {
            $installdir = $installdir1[0];
        }
        if (!(-e $installdir))
        {
            mkdir($installdir);
        }

        # read tftpdir directory from database, if it exists
        my @tftpdir1 = xCAT::Utils->get_site_attribute("tftpdir");
        if ($tftpdir1[0])
        {
            $tftpdir = $tftpdir1[0];
        }
        if (!(-e $tftpdir))
        {
            mkdir($tftpdir);
        }
        if (xCAT::Utils->isLinux())
        {

            # export /install and /tftpboot is not already there
            $cmd = "grep $installdir /etc/exports";
            xCAT::Utils->runcmd($cmd, -1);
            if ($::RUNCMD_RC != 0)
            {    # need to add to export list
                my $cmd =
                  "echo '$installdir *(ro,no_root_squash,sync)' >> /etc/exports";
                xCAT::Utils->runcmd($cmd, -1);
                if ($::RUNCMD_RC != 0)
                {    # error
                    xCAT::MsgUtils->message("S", "Error exporting $installdir");
                }
            }
            $cmd = "grep $tftpdir /etc/exports";
            xCAT::Utils->runcmd($cmd, -1);
            if ($::RUNCMD_RC != 0)
            {        # need to add to export list
                my $cmd =
                  "echo '$tftpdir *(ro,root_squash,sync)' >> /etc/exports";
                xCAT::Utils->runcmd($cmd, -1);
                if ($::RUNCMD_RC != 0)
                {    # error
                    xCAT::MsgUtils->message("S", "Error exporting $tftpdir");
                }
            }
            my $cmd = "chkconfig nfs on";
            xCAT::Utils->runcmd($cmd, 0);
            if ($::RUNCMD_RC != 0)
            {        # error
                xCAT::MsgUtils->message("S", "Error on command:$cmd");
            }

            # make sure nfs is started
            my $cmd = "/etc/rc.d/init.d/nfs restart";
            xCAT::Utils->runcmd($cmd, 0);
            if ($::RUNCMD_RC != 0)
            {        # error
                xCAT::MsgUtils->message("S", "Error on command: $cmd");
                return 1;
            }

            # export the directories
            my $cmd = "exportfs -a";
            xCAT::Utils->runcmd($cmd, 0);
            if ($::RUNCMD_RC != 0)
            {        # error
                xCAT::MsgUtils->message("S", "exportfs -a failed");
                return 1;
            }

            # check to see if install and tftp directory already mounted
            # if not mount then
            my @dirs = ($installdir, $tftpdir);
            foreach my $directory (@dirs)
            {
                $cmd = "df -P $directory";
                my @output = xCAT::Utils->runcmd($cmd, -1);
                my $found = 0;
                foreach my $line (@output)
                {
                    my ($file_sys, $blocks, $used, $avail, $cap, $mount_point) =
                      split(' ', $line);
                    if ($mount_point eq $directory)
                    {
                        $found = 1;
                        last;
                    }
                }
                if ($found == 0)
                {

                    # need to  mount the directory
                    my $cmd =
                      " mount -o rw,nolock $master:$directory $directory";
                    xCAT::Utils->runcmd($cmd, 0);
                    if ($::RUNCMD_RC != 0)
                    {    # error
                        xCAT::MsgUtils->message("S", "Error $cmd");
                    }
                }
            }

        }
        else
        {                #AIX TODO
            xCAT::MsgUtils->message('S',
                                    "AIX Service Node  not supported yet.\n");
            $rc = 1;
        }
    }
    else
    {                    # error reading Db
        $rc = 1;
    }
    if ($rc == 0)
    {

        #  update fstab so they will mount on reboot
        $cmd = "grep $master:$tftpdir $tftpdir  /etc/fstab  ";
        xCAT::Utils->runcmd($cmd, -1);
        if ($::RUNCMD_RC != 0)
        {
            `echo "$master:$tftpdir $tftpdir nfs timeo=14,intr 1 2" >>/etc/fstab`;
        }
        $cmd = "grep $master:$installdir $installdir  /etc/fstab  ";
        xCAT::Utils->runcmd($cmd, -1);
        if ($::RUNCMD_RC != 0)
        {
            `echo "$master:$installdir $installdir nfs timeo=14,intr 1 2" >>/etc/fstab`;
        }
    }
    return $rc;
}
1;
