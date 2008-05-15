#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------
package xCAT_plugin::SSHsn;
use xCAT::Table;

use xCAT::Utils;

use xCAT::MsgUtils;
use Getopt::Long;

#-------------------------------------------------------

=head1 
  xCAT plugin package to setup of SSH on service node 


#-------------------------------------------------------

=head3  handled_commands 

Check to see if on a Service Node
Call  setup_SSH

=cut

#-------------------------------------------------------

sub handled_commands
{
    my $rc = 0;
    if (xCAT::Utils->isServiceNode())
    {
        my $service = "ssh";

        $rc = &setup_SSH();    # setup SSH
        if ($rc == 0)
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

=head3 setup_SSH 

    Sets up SSH default configuration for root  
	Turns strict host checking off


=cut

#-----------------------------------------------------------------------------
sub setup_SSH
{

    my $configfile;
    my $cmd;
    my $configinfo;
    my $sshdir;
    my $cmd;

    # build the $HOMEROOT/.ssh/config
    if (xCAT::Utils->isLinux())
    {
        $configfile = "/root/.ssh/config";
        $sshdir="/root/.ssh";
    }
    else
    {    #AIX
        $configfile = "/.ssh/config";
        $sshdir="/.ssh";
    }
    if (!(-e $sshdir)){ # directory does not exits
        mkdir($sshdir, 0700);
    }
    $configinfo = "StrictHostKeyChecking no";
    
    if (-e $configfile)
    {
        $cmd = "grep StrictHostKeyChecking $configfile";
        xCAT::Utils->runcmd($cmd, -1);
        if ($::RUNCMD_RC != 0)
        {    # not there
            $cmd = "echo  $configinfo >> $configfile";
            my @output = xCAT::Utils->runcmd($cmd, 0);
            if ($::RUNCMD_RC != 0)
            {    # error
                xCAT::MsgUtils->message("S", "Error on $cmd, @output");
                return 1;
            }

        }
    }
    else         # file does not exist
    {
        $cmd = "echo  $configinfo >> $configfile";
        my @output = xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {        # error
            xCAT::MsgUtils->message("S", "Error on $cmd, @output");
            return 1;
        }
        else
        {
            chmod 0600, $configfile;

        }
    }

    return 0;
}
1;
