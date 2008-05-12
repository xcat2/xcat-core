#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------
package xCAT_plugin::AAsn;
use xCAT::Table;

use xCAT::Utils;

use xCAT::MsgUtils;
use File::Path;
use Getopt::Long;

#-------------------------------------------------------

=head1 
    
  mounts /install if site->installoc set 


#-------------------------------------------------------

=head3  handled_commands 

Check to see if on a Service Node
Call  mountInstall 

=cut

#-------------------------------------------------------

sub handled_commands

{
    my $rc = 0;

    if (xCAT::Utils->isServiceNode())
    {
        my @nodeinfo   = xCAT::Utils->determinehostname;
        my $nodename   = pop @nodeinfo;                    # get hostname
        my @nodeipaddr = @nodeinfo;                        # get ip addresses
        my $service    = "mountInstall";

        # service needed on this Service Node
        $rc = &mountInstall($nodename);                    # setup NFS
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

=head3 mountInstall 

    if site->installoc attribute set  
	  mount the install directory  

=cut

#-----------------------------------------------------------------------------
sub mountInstall
{
    my ($nodename) = @_;
    my $rc         = 0;
    my $installdir = "/install";    # default
    my $installoc  = "/install";    # default

    # read DB for nodeinfo
    my $master;
    my $os;
    my $arch;
    my $nomount = 0;

    my $retdata = xCAT::Utils->readSNInfo($nodename);
    if ($retdata->{'arch'})
    {                               # no error
        $master = $retdata->{'master'};    # management node
        $os     = $retdata->{'os'};
        $arch   = $retdata->{'arch'};

        # read install directory and install location from database,
        # if they exists
        my @installocation= xCAT::Utils->get_site_attribute("installoc");
        my $hostname;
        my $path;
        if ($installocation[0])
        {
           if (grep /:/, $installocation[0]){ 
              my ($hostname, $installoc) = split ":",$installocation[0];
              if ($hostname)
              {    # hostname set in /installoc attribute
                  $master = $hostname;    # set name for mount
              }
            } else {
              $installoc=$installocation[0];
            }
        }
        else
        {    # if no install location then we do not mount
            $nomount = 1;
        }

        if ($nomount == 0)
        {    # mount the install directory
            my @installdir1 = xCAT::Utils->get_site_attribute("installdir");
            if ($installdir1[0])
            {
                $installdir = $installdir1[0];    # save directory to mount to
            }
            if (!(-e $installdir))
            {
                mkpath($installdir);
            }

            # check to see if install  already mounted

            my $mounted = xCAT::Utils->isMounted($installdir);
            if ($mounted == 0)
            {                                     # not mounted

                # need to  mount the directory
                my $cmd= "mount -o rw,nolock $master:$installoc $installdir";
                system $cmd;
                if ($? > 0)
                {                                 # error
                    $rc = 1;
                    xCAT::MsgUtils->message("S", "Error $cmd");
                }
            }
        }

    }
    else
    {                                             # error reading Db
        $rc = 1;
    }
    if ($rc == 0 && $nomount == 0)
    {

        # update fstab to mount on reboot
        $cmd = "grep $master:$installoc $installdir  /etc/fstab  ";
        xCAT::Utils->runcmd($cmd, -1);
        if ($::RUNCMD_RC != 0)
        {
            `echo "$master:$installoc $installdir nfs timeo=14,intr 1 2" >>/etc/fstab`;
        }
    }
    return $rc;
}

1;
