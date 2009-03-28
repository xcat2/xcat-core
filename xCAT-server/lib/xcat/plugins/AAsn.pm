#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------
package xCAT_plugin::AAsn;
use xCAT::Table;

use xCAT::Utils;

use xCAT::MsgUtils;
use xCAT_plugin::dhcp;
use xCAT_plugin::conserver;
use File::Path;
use Getopt::Long;

#-------------------------------------------------------

=head1  AAsn

 This is the Service Node Plugin, although it does perform a few functions on
 the Management Node.   
 It reads the servicenode table for the service node it is running on,
 and run the appropriate
 setup routine for each service that is designated to be setup in the 
 servicenode table for this service node. Some functions are only done for 
 Linux.
 A few functions are done not based on the servicenode table. For example:

  mounts /install if site.installloc set
  on a Linux Service Node

#-------------------------------------------------------

=head3  handled_commands

If bypassmode then exit
If xcat daemon reload then exit

Check to see if on a Service Node
If Linux
   Call  mountInstall
If this is a service Node
  Read Service Node Table
   For each service returned to be setup
	  Call the appropriate setup_service routine
else if on the Management Node
  Do any Management Node setup of services needed

=cut

#-------------------------------------------------------

sub handled_commands

{

    # If called in XCATBYPASS mode, don't do any setup
    if ($ENV{'XCATBYPASS'})
    {
        return 0;
    }

    # If a xcat daemon reload, don't do any setup
    if ($ENV{'XCATRELOAD'})
    {
        return 0;
    }

    my $rc = 0;

    if (xCAT::Utils->isServiceNode())
    {
        my @nodeinfo   = xCAT::Utils->determinehostname;
        my $nodename   = pop @nodeinfo;                    # get hostname
        my @nodeipaddr = @nodeinfo;                        # get ip addresses
        my $service;

        if (xCAT::Utils->isLinux())
        {

            # service needed on Linux Service Node
            $service = "mountInstall";
            $rc      = &mountInstall($nodename);           # mount install
            if ($rc == 0)
            {
                xCAT::Utils->update_xCATSN($service);
            }
            $service = "ssh";

            $rc = &setup_SSH();                            # setup SSH
            if ($rc == 0)
            {
                xCAT::Utils->update_xCATSN($service);
            }

        }

        # read the service node table
        # for a list of all functions to setup for this service node
        #
        my @servicelist = xCAT::Utils->isServiceReq($nodename, \@nodeipaddr);
        if ($::RUNCMD_RC == 0)
        {
            if (xCAT::Utils->isLinux())
            {    #run only the following only on Linux

                my $service = "conserver";
                if (grep(/$service/, @servicelist))
                {

                    $rc = &setup_CONS($nodename);    # setup conserver
                    if ($rc == 0)
                    {
                        xCAT::Utils->update_xCATSN($service);
                    }

                }


                $service = "ftpserver";
                if (grep(/$service/, @servicelist))
                {

                    # make sure ftpserver not tftpserver
                    my $match = 0;
                    foreach my $service (@servicelist)
                    {
                        if ($service eq "ftpserver")
                        {
                            $match = 1;
                        }
                    }
                    if ($match == 1)
                    {    # it was ftpserver
                        $rc = &setup_FTP();    # setup vsftpd
                        if ($rc == 0)
                        {
                            xCAT::Utils->update_xCATSN($service);
                        }
                    }

                }

                $service = "ldapserver";
                if (grep(/$service/, @servicelist))
                {

                    $rc = &setup_LDAP();    # setup LDAP
                    if ($rc == 0)
                    {
                        xCAT::Utils->update_xCATSN($service);
                    }

                }

                $service = "tftpserver";
                if (grep(/$service/, @servicelist))
                {

                    $rc = &setup_TFTP($nodename);    # setup TFTP
                    if ($rc == 0)
                    {
                        xCAT::Utils->update_xCATSN($service);
                    }

                }


            }    # end Linux only

            #
            # setup these services for AIX or Linux
            #
            my $service = "nameserver";
            if (grep(/$service/, @servicelist))
            {

                $rc = &setup_DNS();    # setup DNS
                if ($rc == 0)
                {
                    xCAT::Utils->update_xCATSN($service);
                }

            }
            $service = "nfsserver";
            if (grep(/$service/, @servicelist))
            {

                $rc = &setup_NFS($nodename);    # setup NFS
                if ($rc == 0)
                {
                    xCAT::Utils->update_xCATSN($service);
                }

            }
            #
            # setup dhcp only on Linux and last 
            #
            if (xCAT::Utils->isLinux())  {
                my $service = "dhcpserver";
                if (grep(/$service/, @servicelist))
                {

                    $rc = &setup_DHCP($nodename);    # setup DHCP
                    if ($rc == 0)
                    {
                        xCAT::Utils->update_xCATSN($service);
                    }

                }
            }


            # done now in setupntp postinstall script, but may change
            #$service = "ntpserver";
            #if (grep(/$service/, @servicelist))
            #{

            # $rc = &setup_NTPsn($nodename);    # setup NTP on SN
            # if ($rc == 0)
            # {
            #     xCAT::Utils->update_xCATSN($service);
            # }

            #}
        }
        else
        {    # error from servicenode tbl read
            xCAT::MsgUtils->message("S",
                                "AAsn.pm:Error reading the servicenode table.");
        }

    }
    else     # management node
    {

        # $rc = &setup_NTPmn();  # setup NTP on the Management Node
        if (xCAT::Utils->isLinux())
        {
            $rc = &setup_FTP();    # setup FTP
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

    if site.installloc attribute set
	  mount the install directory

=cut

#-----------------------------------------------------------------------------
sub mountInstall
{
    my ($nodename) = @_;
    my $rc         = 0;
    my $installdir = "/install";    # default
    my $installloc = "/install";    # default

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
        my @installlocation = xCAT::Utils->get_site_attribute("installloc");
        my $hostname;
        my $path;
        if ($installlocation[0])
        {
            if (grep /:/, $installlocation[0])
            {
                my ($hostname, $installloc) = split ":", $installlocation[0];
                if ($hostname)
                {    # hostname set in /installloc attribute
                    $master = $hostname;    # set name for mount
                }
            }
            else
            {
                $installloc = $installlocation[0];
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
                my $cmd = "mount -o rw,nolock $master:$installloc $installdir";
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
        $cmd = "grep $master:$installloc $installdir  /etc/fstab  ";
        xCAT::Utils->runcmd($cmd, -1);
        if ($::RUNCMD_RC != 0)
        {
            `echo "$master:$installloc $installdir nfs timeo=14,intr 1 2" >>/etc/fstab`;
        }
    }
    return $rc;
}

#-----------------------------------------------------------------------------

=head3 setup_CONS

    Sets up Conserver

=cut

#-----------------------------------------------------------------------------
sub setup_CONS
{
    my ($nodename) = @_;
    my $rc = 0;

    # read DB for nodeinfo
    my $master;
    my $os;
    my $arch;
    my $cmd;
    my $retdata = xCAT::Utils->readSNInfo($nodename);
    if ($retdata->{'arch'})
    {    # no error
        $master = $retdata->{'master'};
        $os     = $retdata->{'os'};
        $arch   = $retdata->{'arch'};

        # make the consever 8 configuration file
        my $cmdref;
        $cmdref->{command}->[0] = "makeconservercf";
        $cmdref->{arg}->[0] = "-l";
        $cmdref->{cwd}->[0]     = "/opt/xcat/sbin";
        $cmdref->{svboot}->[0]  = "yes";

        my $modname = "conserver";
        ${"xCAT_plugin::" . $modname . "::"}{process_request}
          ->($cmdref, \&xCAT::Client::handle_response);

        # start conserver. conserver needs 2 CA files to start
        my $ca_file1 = "/etc/xcat/ca/ca-cert.pem";
        my $ca_file2 = "/etc/xcat/cert/server-cred.pem";
        if (!-e $ca_file1)
        {
            print
              "conserver cannot be started because the file $ca_file1 cannot be found\n";
        }
        elsif (!-e $ca_file2)
        {
            print
              "conserver cannot be started because the file $ca_file2 cannot be found\n";
        }
        else
        {
            my $rc = xCAT::Utils->startService("conserver");
            if ($rc != 0)
            {
                return 1;
            }
        }
    }
    else
    {    # error reading Db
        $rc = 1;
    }
    return $rc;
}

#-----------------------------------------------------------------------------

=head3 setup_DHCP 

    Sets up DHCP services  

=cut

#-----------------------------------------------------------------------------
sub setup_DHCP
{
    my ($nodename) = @_;
    my $rc = 0;
    my $cmd;

    # run makedhcp
    $XCATROOT = "/opt/xcat";    # default

    if ($ENV{'XCATROOT'})
    {
        $XCATROOT = $ENV{'XCATROOT'};
    }
    my $cmdref;
    $cmdref->{command}->[0] = "makedhcp";
    $cmdref->{arg}->[0] = "-l";
    $cmdref->{cwd}->[0]     = "/opt/xcat/sbin";
    $cmdref->{arg}->[0]     = "-n";

    my $modname = "dhcp";
    ${"xCAT_plugin::" . $modname . "::"}{process_request}
      ->($cmdref, \&xCAT::Client::handle_response);

    my $rc = xCAT::Utils->startService("dhcpd");
    if ($rc != 0)
    {
        return 1;
    }
    $cmdref;
    $cmdref->{command}->[0] = "makedhcp";
    $cmdref->{arg}->[0] = "-l";
    $cmdref->{cwd}->[0]     = "/opt/xcat/sbin";
    $cmdref->{arg}->[0]     = "-a";

    my $modname = "dhcp";
    ${"xCAT_plugin::" . $modname . "::"}{process_request}
      ->($cmdref, \&xCAT::Client::handle_response);

    return $rc;
}

#-----------------------------------------------------------------------------

=head3 setup_FTP

    Sets up FTP services (vstftp)

=cut

#-----------------------------------------------------------------------------
sub setup_FTP
{
    my $rc = 0;
    my $cmd;
    $XCATROOT = "/opt/xcat";    # default

    if ($ENV{'XCATROOT'})
    {
        $XCATROOT = $ENV{'XCATROOT'};
    }

    # change ftp user id home directory to installdir
    # link installdir
    # restart the daemon
    my $installdir = "/install";    # default
                                    # read from database
    my @installdir1 = xCAT::Utils->get_site_attribute("installdir");
    if ($installdir1[0])            # if exists
    {
        $installdir = $installdir1[0];
    }
    if (!(-e $installdir))          # make it
    {
        mkpath($installdir);
    }
    $cmd = "usermod -d $installdir ftp";
    my $outref = xCAT::Utils->runcmd($cmd, 0);
    if ($::RUNCMD_RC)
    {

        xCAT::MsgUtils->message("S", "Error from command:$cmd");
    }

    # start tftp

    my $rc = xCAT::Utils->startService("vsftpd");
    if ($rc != 0)
    {
        return 1;
    }

    return $rc;
}

#-----------------------------------------------------------------------------

=head3 setup_DNS

    Sets up Domain Name service
	http://www.adminschoice.com/docs/domain_name_service.htm#Introduction

=cut

#-----------------------------------------------------------------------------
sub setup_DNS
{

    # setup the named.conf file
    system("/opt/xcat/sbin/makenamed.conf");

    # turn DNS on

    my $rc = xCAT::Utils->startService("named");
    if ($rc != 0)
    {
        return 1;
    }

    return 0;
}

#-----------------------------------------------------------------------------

=head3 setup_LDAP 

    Sets up LDAP  

=cut

#-----------------------------------------------------------------------------
sub setup_LDAP
{

    my $rc = xCAT::Utils->startService("ldap");
    if ($rc != 0)
    {
        return 1;
    }

    return 0;
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

    # make sure nfs is restarted
    my $rc = 0;
    if (xCAT::Utils->isLinux())
    {
       my $os = xCAT::Utils->osver();
       if ($os =~ /sles.*/) {
         $rc = xCAT::Utils->startService("nfs");
         $rc = xCAT::Utils->startService("nfsserver");
       } else {
         $rc = xCAT::Utils->startService("nfs");
       }
    }
    else
    {    #AIX
        $rc = xCAT::Utils->startService("nfsd");
    }
    if ($rc != 0)
    {
        return 1;
    }

    return $rc;
}

#-----------------------------------------------------------------------------

=head3 setup_NTPsn 

    Sets up NTP services on service node

=cut

#-----------------------------------------------------------------------------
sub setup_NTPsn
{
    my ($nodename) = @_;
    my $rc = 0;
    my $cmd;
    my $master;
    my $os;
    my $arch;
    my $ntpcfg = "/etc/ntp.conf";

    # read DB for nodeinfo
    my $retdata = xCAT::Utils->readSNInfo($nodename);
    $master = $retdata->{'master'};
    $os     = $retdata->{'os'};
    $arch   = $retdata->{'arch'};
    if (!($arch))
    {    # error
        xCAT::MsgUtils->message("S", " Error reading service node info.");
        return 1;
    }

    # backup the existing config file
    $rc = &backup_NTPconf();
    if ($rc == 0)
    {

        # create config file
        open(CFGFILE, ">$ntpcfg")
          or xCAT::MsgUtils->message('SE',
                                  "Cannot open $configfile for NTP update. \n");
        print CFGFILE "server ";
        print CFGFILE $master;
        print CFGFILE "\n";
        print CFGFILE "driftfile /var/lib/ntp/drift\n";
        print CFGFILE "restrict 127.0.0.1\n";
        close CFGFILE;

        $rc = &start_NTP();    # restart ntp
    }
    return $rc;
}

#-----------------------------------------------------------------------------

=head3 setup_NTPmn 

    Sets up NTP services on Management Node 
    Get ntpservers from site table.  If they do not exist, warn cannot setup NTP
=cut

#-----------------------------------------------------------------------------
sub setup_NTPmn
{
    my $rc     = 0;
    my $ntpcfg = "/etc/ntp.conf";

    # get timeservers from site table
    my @ntpservers = xCAT::Utils->get_site_attribute("ntpservers");
    if ($ntpservers[0])
    {

        # backup the existing config file
        $rc = &backup_NTPconf();
        if ($rc == 0)
        {

            # add server names
            open(CFGFILE, ">$ntpcfg")
              or xCAT::MsgUtils->message('SE',
                                  "Cannot open $configfile for NTP update. \n");
            my @servers = split ',', $ntpservers[0];
            foreach my $addr (@servers)
            {
                print CFGFILE "server ";
                print CFGFILE $addr;
                print CFGFILE "\n";
            }
            print CFGFILE "driftfile /var/lib/ntp/drift\n";
            print CFGFILE "restrict 127.0.0.1\n";
            close CFGFILE;

            $rc = &start_NTP();    # restart ntp
        }
    }
    else
    {                              # no servers defined
        xCAT::MsgUtils->message(
            "S",
            "No NTP servers defined in the ntpservers attribute in the site table.\n"
            );
        return 1;
    }
    return $rc;
}

#-----------------------------------------------------------------------------

=head3 start_NTP 

    Starts daemon 

=cut

#-----------------------------------------------------------------------------
sub start_NTP
{

    my $rc = xCAT::Utils->startService("ntpd");
    if ($rc != 0)
    {
        return 1;
    }

    return 0;
}

#-----------------------------------------------------------------------------

=head3 backup_NTPconf 

   backup configuration 

=cut

#-----------------------------------------------------------------------------
sub backup_NTPconf
{
    my $ntpcfg           = "/etc/ntp.conf";
    my $ntpcfgbackup     = "/etc/ntp.conf.orig";
    my $ntpxcatcfgbackup = "/etc/ntp.conf.xcatbackup";
    if (!-e $ntpcfgbackup)
    {    # if original backup does not already exist
        my $cmd = "mv $ntpcfg $ntpcfgbackup";
        system $cmd;
        if ($? > 0)
        {
            xCAT::MsgUtils->message("S", "Error from command:$cmd");
            return 1;
        }
    }
    else
    {    # backup xcat cfg
        my $cmd = "mv $ntpcfg $ntpxcatcfgbackup";
        system $cmd;
        if ($? > 0)
        {
            xCAT::MsgUtils->message("S", "Error from command:$cmd");
            return 1;
        }
    }
    return 0;
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
        $sshdir     = "/root/.ssh";
    }
    else
    {    #AIX
        $configfile = "/.ssh/config";
        $sshdir     = "/.ssh";
    }
    if (!(-e $sshdir))
    {    # directory does not exits
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

#-----------------------------------------------------------------------------

=head3 setup_TFTP 

    Sets up TFTP services (using atftp) 

=cut

#-----------------------------------------------------------------------------
sub setup_TFTP
{
    my ($nodename) = @_;
    my $rc         = 0;
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
    my $mountdirectory = "1";    # default to mount tftpboot dir
    if ($output[0] =~ "atftp")   # it is atftp
    {

        # read sharedtftp attribute from site table, if exist
        my @sharedtftp = xCAT::Utils->get_site_attribute("sharedtftp");
        if (exists($sharedtftp[0]))
        {
            $mountdirectory = $sharedtftp[0];
            $mountdirectory =~ tr/a-z/A-Z/;    # convert to upper
        }

        # read tftpdir directory from database
        my $tftpdir    = "/tftpboot";    # default
        my @tftpdir1 = xCAT::Utils->get_site_attribute("tftpdir");
        if (exists($tftpdir1[0]))
        {
            $tftpdir = $tftpdir1[0];
        }
        if (!(-e $tftpdir))
        {
            mkdir($tftpdir);
        }

        # if request to mount
        if ($mountdirectory eq "1" || $mountdirectory eq "YES")
        {

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
        } else { #if not mounting, have to regenerate....
            #first, run mknb to get nbfs and such going?
            my $cmdref;
            $cmdref->{command}->[0] = "mknb";
            $cmdref->{arg}->[0] = "ppc64";
            ${"xCAT_plugin::mknb::"}{process_request}->($cmdref, \&xCAT::Client::handle_response);
            $cmdref->{arg}->[0] = "x86";
            ${"xCAT_plugin::mknb::"}{process_request}->($cmdref, \&xCAT::Client::handle_response);
            $cmdref->{arg}->[0] = "x86_64";
            ${"xCAT_plugin::mknb::"}{process_request}->($cmdref, \&xCAT::Client::handle_response);
            #now, run nodeset enact on
            #now, run nodeset enact on
            my $mactab = xCAT::Table->new('mac');
            my $hmtab = xCAT::Table->new('nodehm');
            if ($mactab and $hmtab) {
                my @mentries = ($mactab->getAllNodeAttribs([qw(node mac)])); #nodeset fails if no mac entry, filter on discovered nodes first...
                my %netmethods;
                my @tnodes;
                foreach (@mentries) {
                    unless (defined $_->{mac}) { next; }
                    push @tnodes,$_->{node};
                }
                my %hmhash = %{$hmtab->getNodesAttribs(\@tnodes,[qw(node netboot)])};
                foreach (@tnodes) {
                  if ($hmhash{$_}->[0]->{netboot}) {
                      push @{$netmethods{$hmhash{$_}->[0]->{netboot}}},$_;
                  }
                }
                $cmdref->{command}->[0] = "nodeset";
                $cmdref->{arg}->[0] = "enact";
                $cmdref->{cwd}->[0]     = "/opt/xcat/sbin";
                foreach my $modname (keys %netmethods) {
                    $cmdref->{node} = $netmethods{$modname};
                    ${"xCAT_plugin::" . $modname . "::"}{process_request}->($cmdref, \&xCAT::Client::handle_response);
                }
                
            }
        }

        # start atftp
        my $rc = xCAT::Utils->startService("tftpd");
        if ($rc != 0)
        {
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

        if ($mountdirectory eq "1" || $mountdirectory eq "YES")
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
    }

    return $rc;

}
1;
