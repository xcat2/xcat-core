#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------
package xCAT_plugin::AAsn;
use strict;
use xCAT::Table;

use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::NetworkUtils;

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

  on a Linux Service Node
      if site.installloc set
          mounts /install
      if site.installloc not set
          creates /install if needed
          sets up nfs
          exports /install 

#-------------------------------------------------------

=head3  handled_commands

If bypassmode then exit
If xcat daemon reload then exit

Check to see if on a Service Node
If Linux
   Call  setupInstallloc
If this is a service Node
  Read Service Node Table
   For each service returned to be setup
	  Call the appropriate setup_service routine
else if on the Management Node
  Do any Management Node setup of services needed

=cut

#-------------------------------------------------------

sub handled_commands { return; }

sub init_plugin
{
    my $doreq = shift;

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

    #On the Servicenodes or the Management node
    if (((xCAT::Utils->isServiceNode()) && ( -s "/etc/xcat/cfgloc"))
           || (xCAT::Utils->isMN()))
    {
        my @nodeinfo   = xCAT::NetworkUtils->determinehostname;
        my $nodename   = pop @nodeinfo;                    # get hostname
        my @nodeipaddr = @nodeinfo;                        # get ip addresses
        my $service;
        # if a linux servicenode
        if ((xCAT::Utils->isLinux())&& (xCAT::Utils->isServiceNode()))
        {

            # service needed on Linux Service Node
            $service = "setupInstallloc";
            &setupInstallloc($nodename);
            $service = "ssh";

            &setup_SSH();    # setup SSH

        }

        # read the service node table
        # for a list of all functions to setup for this service node
        #
        my $servicelist = xCAT::ServiceNodeUtils->isServiceReq($nodename, \@nodeipaddr);
        my $service;
        if ($::RUNCMD_RC == 0)
        {
            if (xCAT::Utils->isLinux())
            {    #run only the following only on Linux


                if ($servicelist->{"ftpserver"} == 1)
                {
                     &setup_FTP();    # setup vsftpd
                }

                if ($servicelist->{"ldapserver"} == 1)
                {
                    &setup_LDAP();    # setup LDAP
                }

                if ($servicelist->{"tftpserver"} == 1)
                {
                 if (xCAT::Utils->isServiceNode()) { # service node
                     &setup_TFTP($nodename, $doreq);    # setup TFTP
                 } else { # management node
                    &enable_TFTPhpa();
                 }

                }
                if ($servicelist->{"proxydhcp"} == 1) {
                    &setup_proxydhcp(1);
                } else {
                    &setup_proxydhcp(0);
                }
            }    # end Linux only
            #
            # setup these services for AIX or Linux
            #
            if ($servicelist->{"conserver"} == 1)
            {
                if (xCAT::Utils->isLinux())
                {    #run only the following only on Linux

                     &setup_CONS($nodename);    # setup conserver
                } else { #AIX
                    $rc=xCAT::Utils->setupAIXconserver();
            
                }
            }
            if (($servicelist->{"nameserver"} == 1) || ($servicelist->{"nameserver"} == 2) )
            {

                &setup_DNS($servicelist);    # setup DNS

            }
            if ($servicelist->{"nfsserver"} == 1)
            {

                 &setup_NFS($nodename);    # setup NFS

                # The nfsserver field in servicenode table
                # will also setup http service for Linux
                if (xCAT::Utils->isLinux())
                {
                     &setup_HTTP($nodename);    # setup HTTP
                }

            }
            if ($servicelist->{"ipforward"} == 1)
	         {
	           # enable ip forwarding 
	            xCAT::NetworkUtils->setup_ip_forwarding(1); 
	         }

            #
            # setup dhcp only on Linux and do it last
            #
            if (xCAT::Utils->isLinux())
            {
                if ($servicelist->{"dhcpserver"} == 1)
                {

                    &setup_DHCP($nodename);    # setup DHCP

                }
            }

        }
        else
        {    # error from servicenode tbl read
            xCAT::MsgUtils->message("S",
                                "AAsn.pm:Error reading the servicenode table.");
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

=head3 setupInstallloc

    if site.installloc attribute set
          If the installdir directory is exported, unexport it
	      mount the installdir directory from the installloc location
    if site.installoc not set and we are on a Stateful install 
          If installdir mounted, unmount it 
          If installdir directory not created,  create it
          setup NFS
          export the installdir directory
          

=cut

#-----------------------------------------------------------------------------
sub setupInstallloc
{
    my ($nodename) = @_;
    my $rc         = 0;
    my $installdir = xCAT::TableUtils->getInstallDir();
    my $installloc;
    my $newinstallloc;

    # read DB for nodeinfo
    my $master;
    my $os;
    my $arch;
    my $nomount = 0;

    my $retdata = xCAT::ServiceNodeUtils->readSNInfo($nodename);
    if (ref $retdata and $retdata->{'arch'})
    {    # no error
        $master = $retdata->{'master'};    # management node
        $os     = $retdata->{'os'};
        $arch   = $retdata->{'arch'};

        # read install directory and install location from database,
        # if they exists
        my @installlocation = xCAT::TableUtils->get_site_attribute("installloc");
        my $hostname;
        my $path;
        if ($installlocation[0])
        {
            if (grep /:/, $installlocation[0])
            {
                my ($hostname, $newinstallloc) = split ":", $installlocation[0];
                if ($hostname)
                {    # hostname set in /installloc attribute
                    $master     = $hostname;         # set name for mount
                    $installloc = $newinstallloc;    #set path for mount point
                }
            }
            else
            {
                $installloc = $installlocation[0];
            }
        }
        else
        {    # if no installloc attribute then we do not mount
            $nomount = 1;
        }

        if ($nomount == 0)    # we do have installloc attribute
        {

            # mount the install directory from the installloc location
            # make the directory to mount on
            if (!(-e $installdir))
            {
                mkpath($installdir);
            }

            # check if exported, and unexport it
            my $cmd = "/bin/cat /etc/exports | grep '$installdir'";
            my $outref = xCAT::Utils->runcmd("$cmd", -1);
            if ($::RUNCMD_RC == 0)    # it is exported
            {

                # remove from /etc/exports
                my $sedcmd = "sed \\";
                $sedcmd .= "$installdir/d  /etc/exports > /etc/exports.tmp";
                system $sedcmd;
                if ($? > 0)
                {                     # error
                    xCAT::MsgUtils->message("S", "Error $cmd");
                }
                else
                {
                    $cmd = "cp /etc/exports.tmp /etc/exports";
                    system $cmd;
                    if ($? > 0)
                    {                 # error
                        xCAT::MsgUtils->message("S", "Error $cmd");
                    }
                }

                # restart nfs
                &setup_NFS($nodename);

                $cmd = " exportfs -a";
                system $cmd;
                if ($? > 0)
                {                     # error
                    $rc = 1;
                    xCAT::MsgUtils->message("S", "Error $cmd");
                }

            }

            # check to see if install  already mounted

            my $mounted = xCAT::Utils->isMounted($installdir);
            if ($mounted == 0)
            {                         # not mounted

                # need to  mount the directory
                my $cmd;
                my @nfsv4 = xCAT::TableUtils->get_site_attribute("useNFSv4onAIX");
                if ($nfsv4[0] && ($nfsv4[0] =~ /1|Yes|yes|YES|Y|y/))
                {
                    $cmd = "mount -o vers=4,rw,nolock $master:$installloc $installdir";
                }
                else
                {
                   $cmd = "mount -o rw,nolock $master:$installloc $installdir";
                }
                system $cmd;
                if ($? > 0)
                {                     # error
                    $rc = 1;
                    xCAT::MsgUtils->message("S", "Error $cmd");
                }
            }
        }

        else
        {

            # installloc not set so we will export /install on the SN, if Stateful
            if (xCAT::Utils->isStateful())
            {

                # no installloc attribute, create and export installdir
                # check to see if installdir is mounted
                my $mounted = xCAT::Utils->isMounted($installdir);
                if ($mounted == 1)
                {

                    # need to  unmount the directory
                    my $cmd = "umount $installdir";
                    system $cmd;
                    if ($? > 0)
                    {    # error
                        $rc = 1;
                        xCAT::MsgUtils->message("S", "Error $cmd");
                    }

                }

                # if it does not exist,need to make the installdir directory
                if (!(-e $installdir))
                {
                    mkpath($installdir);
                }

                # export the installdir
                #
                #  add /install to /etc/exports - if needed
                #

                my $cmd = "/bin/cat /etc/exports | grep '$installdir'";
                my $outref = xCAT::Utils->runcmd("$cmd", -1);
                my $changed_exports;
                if ($::RUNCMD_RC != 0)
                {

                    # ok - then add this entry
                    my $cmd =
                      "/bin/echo '$installdir *(rw,no_root_squash,sync,no_subtree_check)' >> /etc/exports";
                    my $outref = xCAT::Utils->runcmd("$cmd", 0);
                    if ($::RUNCMD_RC != 0)
                    {
                        xCAT::MsgUtils->message('S',
                                     "Could not update the /etc/exports file.");
                    }
                    else
                    {
                        $changed_exports++;
                    }
                }

                if ($changed_exports)
                {

                    # restart nfs
                    &setup_NFS($nodename);

                    my $cmd = "/usr/sbin/exportfs -a";
                    my $outref = xCAT::Utils->runcmd("$cmd", 0);
                    if ($::RUNCMD_RC != 0)
                    {
                        xCAT::MsgUtils->message('S', "Error with $cmd.");
                    }

                }
            }
        }
    }
    else
    {    # error reading Db
        $rc = 1;
    }
    if ($rc == 0)
    {

        # update fstab
        my $cmd = "grep $master:$installloc $installdir  /etc/fstab  ";
        xCAT::Utils->runcmd($cmd, -1);
        if ($::RUNCMD_RC != 0)
        {
            if ($nomount == 0)    # then add the entry
            {
                `echo "$master:$installloc $installdir nfs timeo=14,intr 1 2" >>/etc/fstab`;

            }
        }
        else
        {                         # fstab entry there

            if ($nomount == 1)
            {

                # then remove the entry
                my $sedcmd = "sed \\";
                $sedcmd .= "$installdir/d  /etc/fstab > /etc/fstab.tmp";
                system $sedcmd;
                if ($? > 0)
                {                 # error
                    xCAT::MsgUtils->message("S", "Error $cmd");
                }
                else
                {
                    $cmd = "cp /etc/fstab.tmp /etc/fstab";
                    system $cmd;
                    if ($? > 0)
                    {             # error
                        xCAT::MsgUtils->message("S", "Error $cmd");
                    }
                }

            }
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

    my $cmd;
    my $cmdref;
    $cmdref->{command}->[0] = "makeconservercf";
    $cmdref->{arg}->[0]     = "-l";
    $cmdref->{cwd}->[0]     = "/opt/xcat/sbin";
    $cmdref->{svboot}->[0]  = "yes";
    no strict "refs";
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
    return $rc;
}

#-----------------------------------------------------------------------------

=head3 setup_DHCP 

    Sets up DHCP services  
    If on the Management node, just check if running and if not start it.
    On Service nodes do full setup based on site.disjointdhcps setting
=cut

#-----------------------------------------------------------------------------
sub setup_DHCP
{
    my ($nodename) = @_;
    my $rc = 0;
    my $cmd;
    my $snonly = 0;
    # if on the MN check to see if dhcpd is running, and start it if not.
    if (xCAT::Utils->isMN()) { # on the MN
        my @output = xCAT::Utils->runcmd("service dhcpd status", -1);
        if ($::RUNCMD_RC != 0)  { # not running
          $rc = xCAT::Utils->startService("dhcpd");
          if ($rc != 0)
          {
            return 1;
          }
        }
        return 0;
    }

    # read the disjointdhcps attribute to determine if we will setup
    # dhcp for all nodes or just for the nodes service by this service node
    my @hs = xCAT::TableUtils->get_site_attribute("disjointdhcps");
    my $tmp = $hs[0];
    if(defined($tmp)) {
        $snonly = $tmp;
    }

    # run makedhcp
    my $XCATROOT = "/opt/xcat";    # default

    if ($ENV{'XCATROOT'})
    {
        $XCATROOT = $ENV{'XCATROOT'};
    }
    my $cmdref;
    $cmdref->{command}->[0] = "makedhcp";
    $cmdref->{arg}->[0]     = "-n";
    $cmdref->{cwd}->[0]     = "/opt/xcat/sbin";
    no strict "refs";
    my $modname = "dhcp";
    ${"xCAT_plugin::" . $modname . "::"}{process_request}
      ->($cmdref, \&xCAT::Client::handle_response);

    my $distro = xCAT::Utils->osver();
    my $serv = "dhcpd";
    if ( $distro =~ /ubuntu.*/i || $distro =~ /debian.*/i ){
        $serv = "isc-dhcp-server";	
    }

    my $rc = xCAT::Utils->startService($serv);
    if ($rc != 0)
    {
        return 1;
    }
    
    # setup DHCP 
    # 

    # clean up $::opt_n which set by last makedhcp context and conlicts with -a below.
    undef $::opt_n;

    my $modname = "dhcp";
    if ($snonly != 1)  {  # setup  dhcp for all nodes
      $cmdref;
      $cmdref->{command}->[0] = "makedhcp";
      $cmdref->{arg}->[0]     = "-a";
      $cmdref->{cwd}->[0]     = "/opt/xcat/sbin";

   } else {  # setup dhcp just for the nodes owned by the SN
     # determine my name
     # get servicenodes and their nodes
     # find the list of nodes serviced
     my @hostinfo=xCAT::NetworkUtils->determinehostname();
     my $sn_hash =xCAT::ServiceNodeUtils->getSNandNodes();
     my @nodes;
     my %iphash=();
     my $snkey;
     $cmdref;
     foreach  $snkey (keys %$sn_hash) {  # find the service node
        if (grep(/$snkey/, @hostinfo)) {
            push @nodes, @{$sn_hash->{$snkey}};
            $cmdref->{node} = $sn_hash->{$snkey};
            $cmdref->{'_xcatdest'}            = $snkey;
        }
     }
     if (@nodes) {
       my $nodelist;
       foreach my $n (@nodes) { 
        $nodelist .= $n;
        $nodelist .= ",";
       }
       chop $nodelist;
       $cmdref->{arg}->[0] = ();
       $cmdref->{command}->[0] = "makedhcp";
       $cmdref->{noderange}->[0]     = "$nodelist";
       $cmdref->{cwd}->[0]     = "/opt/xcat/sbin";
    }
   }
   ${"xCAT_plugin::" . $modname . "::"}{process_request}
        ->($cmdref, \&xCAT::Client::handle_response);
    return $rc;
}

#-----------------------------------------------------------------------------

=head3 setup_FTP

    Sets up FTP services (vsftp)

=cut

#-----------------------------------------------------------------------------
sub setup_FTP
{
    my $rc = 0;
    my $cmd;
    my $XCATROOT = "/opt/xcat";    # default

    if ($ENV{'XCATROOT'})
    {
        $XCATROOT = $ENV{'XCATROOT'};
    }

    # change ftp user id home directory to installdir
    # link installdir
    # restart the daemon
    my $installdir = xCAT::TableUtils->getInstallDir();
    if (!(-e $installdir))         # make it
    {
        mkpath($installdir);
    }
    $cmd = "usermod -d $installdir ftp 2>&1";
    my $outref = xCAT::Utils->runcmd($cmd, 0);
    if ($::RUNCMD_RC)
    {

        xCAT::MsgUtils->message("S", "Error from command:$cmd");
    }

    # start ftp

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
    my $srvclist = shift;

    my $XCATROOT = "/opt/xcat";    # default

    if ($ENV{'XCATROOT'})
    {
        $XCATROOT = $ENV{'XCATROOT'};
    }

    if ($srvclist->{"nameserver"} == 1)
    {
        # setup the named.conf file as dns forwarding/caching
        system("$XCATROOT/sbin/makenamed.conf");
     }
     else
     {
        # setup the named.conf file as dns slave
        my $cmdref;
        $cmdref->{command}->[0] = "makedns";
        $cmdref->{arg}->[0]     = "-s";
        $cmdref->{cwd}->[0]     = "/opt/xcat/sbin";
        no strict "refs";
        my $modname = "ddns";
        ${"xCAT_plugin::" . $modname . "::"}{process_request}
          ->($cmdref, \&xCAT::Client::handle_response);
     }
        
    # turn DNS on

    my $distro = xCAT::Utils->osver();
    my $serv = "named";
    if ( $distro =~ /ubuntu.*/i || $distro =~ /debian.*/i ){
        $serv = "bind9";
    }

    my $rc = xCAT::Utils->startService($serv);
    if ($rc != 0)
    {
        return 1;
    }

    # start named on boot
    if (xCAT::Utils->isAIX())
    {
        #/etc/inittab
        my $cmd = "/usr/sbin/lsitab named > /dev/null 2>&1";
        my $rc = system("$cmd") >>8;
        if ($rc != 0)
        {
            #add new entry
            my $mkcmd = qq~/usr/sbin/mkitab "named:2:once:/usr/sbin/named > /dev/console 2>&1"~;
            system("$mkcmd");
            xCAT::MsgUtils->message("SI", " named has been enabled on boot.");
        }
    }
    else
    {
        #chkconfig
        my $cmd = "/sbin/chkconfig $serv on";
        my $outref = xCAT::Utils->runcmd("$cmd", 0);
        if ($::RUNCMD_RC != 0)
        {
            xCAT::MsgUtils->message("SE", " Error: Could not enable $serv.");
        }
        else
        {
            xCAT::MsgUtils->message("SI", " $serv has been enabled on boot.");
        }
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
        if ($os =~ /sles.*/)
        {
            $rc = xCAT::Utils->startService("nfs");
            $rc = xCAT::Utils->startService("nfsserver");
        }
        else
        {
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
    my $retdata = xCAT::ServiceNodeUtils->readSNInfo($nodename);
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
                                     "Cannot open $ntpcfg for NTP update. \n");
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
    my @ntpservers = xCAT::TableUtils->get_site_attribute("ntpservers");
    if ($ntpservers[0])
    {

        # backup the existing config file
        $rc = &backup_NTPconf();
        if ($rc == 0)
        {

            # add server names
            open(CFGFILE, ">$ntpcfg")
              or xCAT::MsgUtils->message('SE',
                                      "Cannot open $ntpcfg for NTP update. \n");
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

    Sets up TFTP services  

=cut

#-----------------------------------------------------------------------------
sub setup_TFTP
{
    my ($nodename, $doreq) = @_;

    my $rc = 0;
    my $cmd;
    my $master;
    my $os;
    my $arch;
    my $XCATROOT = "/opt/xcat";    # default

    if ($ENV{'XCATROOT'})
    {
        $XCATROOT = $ENV{'XCATROOT'};
    }

    # read DB for nodeinfo
    my $retdata = xCAT::ServiceNodeUtils->readSNInfo($nodename);
    if (not ref $retdata)
    {    # error
        xCAT::MsgUtils->message("S", " Error reading service node arch.");
        return 1;
    }
    $master = $retdata->{'master'};
    $os     = $retdata->{'os'};
    $arch   = $retdata->{'arch'};
    if (!($arch))
    {    # error
        xCAT::MsgUtils->message("S", " Error reading service node arch.");
        return 1;
    }

    # check to see if tftp is installed
    $cmd = "/usr/sbin/in.tftpd -V";
    my @output = xCAT::Utils->runcmd($cmd, -1);
    if ($::RUNCMD_RC != 0)
    {    # not installed
        xCAT::MsgUtils->message("S", "atftp is not installed, ok for Power5");
    }
    my $tftpdir;
    my $mountdirectory = "1";        # default to mount tftpdir
    my $tftphost       = $master;    # default to master
         # read sharedtftp attribute from site table, if exist
    #my $stab = xCAT::Table->new('site');
    #my $sharedtftp = $stab->getAttribs({key => 'sharedtftp'}, 'value');
    my @ss = xCAT::TableUtils->get_site_attribute("sharedtftp");
    my $sharedtftp = $ss[0];
    if ( defined($sharedtftp) )
    {

        $tftphost       = $sharedtftp;    # either hostname or yes/no
        $mountdirectory = $tftphost;
        $mountdirectory =~ tr/a-z/A-Z/;            # convert to upper
        if (   $mountdirectory ne "1"
            && $mountdirectory ne "YES"
            && $mountdirectory ne "0"
            && $mountdirectory ne "NO")
        {                                          # then tftphost is hostname
                                                   # for the mount
            $mountdirectory = "1";                 # and we mount the directory
        }
        else
        {
            $tftphost = $master;                   # will mount master,if req
        }

    }
    #$stab->close;

    # read tftpdir directory from database
    $tftpdir = xCAT::TableUtils->getTftpDir();
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
            my $cmd;
            my @nfsv4 = xCAT::TableUtils->get_site_attribute("useNFSv4onAIX");
            if ($nfsv4[0] && ($nfsv4[0] =~ /1|Yes|yes|YES|Y|y/))
            {
                $cmd = " mount -o vers=4,rw,nolock $tftphost:$tftpdir $tftpdir";
            }
            else
            {
                $cmd = " mount -o rw,nolock $tftphost:$tftpdir $tftpdir";
            }
            system $cmd;
            if ($? > 0)
            {                 # error
                $rc = 1;
                xCAT::MsgUtils->message("S", "Error $cmd");
            }
        }
    }
    else
    {                         #if not mounting, have to regenerate....
        my $cmdref;
        # mknb is now run in xCATsn.spec
        #use xCAT_plugin::mknb;
        #for my $architecture ("ppc64", "x86", "x86_64")
        #{
        #    unless (-d "$::XCATROOT/share/xcat/netboot/$architecture")
        #    {
        #        next;
        #    }
        #    $cmdref->{command}->[0] = "mknb";
        #    $cmdref->{arg}->[0]     = $architecture;
        #    $doreq->($cmdref, \&xCAT::Client::handle_response);
        #}

        #now, run nodeset enact on
        my $mactab = xCAT::Table->new('mac');
        my $hmtab  = xCAT::Table->new('noderes');
        if ($mactab and $hmtab)
        {
            my @mentries = ($mactab->getAllNodeAttribs([qw(node mac)]));

            #nodeset fails if no mac entry, filter on discovered nodes first
            my %netmethods;
            my @tnodes;
            foreach (@mentries)
            {
                unless (defined $_->{mac}) { next; }
                push @tnodes, $_->{node};
            }
            my %hmhash =
              %{$hmtab->getNodesAttribs(\@tnodes, [qw(node netboot)])};
            foreach (@tnodes)
            {
                if ($hmhash{$_}->[0]->{netboot})
                {
                    push @{$netmethods{$hmhash{$_}->[0]->{netboot}}}, $_;
                }
            }
            $cmdref->{command}->[0]  = "nodeset";
            $cmdref->{inittime}->[0] = "1";
            $cmdref->{arg}->[0]      = "enact";
            $cmdref->{cwd}->[0]      = "/opt/xcat/sbin";
            my $plugins_dir = $::XCATROOT . '/lib/perl/xCAT_plugin';
            foreach my $modname (keys %netmethods)
            {
                $cmdref->{node} = $netmethods{$modname};
                $doreq->($cmdref, \&xCAT::Client::handle_response);
            }

        }
    }

    # enable the tftp-hpa
    $rc = enable_TFTPhpa();

    if ($rc == 0)
    {

        if ($mountdirectory eq "1" || $mountdirectory eq "YES")
        {

            # update fstab so that it will restart on reboot
            $cmd =
              "fgrep \"$tftphost:$tftpdir $tftpdir nfs timeo=14,intr 1 2\" /etc/fstab";
            xCAT::Utils->runcmd($cmd, -1);
            if ($::RUNCMD_RC != 0)    # not already there
            {

                `echo "$tftphost:$tftpdir $tftpdir nfs timeo=14,intr 1 2" >>/etc/fstab`;
            }
        }
    }

    return $rc;

}

#-----------------------------------------------------------------------------

=head3 setup_HTTP

    Sets up HTTP services on Service Node for Linux   

=cut

#-----------------------------------------------------------------------------
sub setup_HTTP
{
    my ($nodename) = @_;
    my $rc = 0;

    if (xCAT::Utils->isLinux())
    {
        my $os = xCAT::Utils->osver();
        if ($os =~ /sles.*/)
        {
            $rc = xCAT::Utils->startService("apache2");
        }
        else
        {
            $rc = xCAT::Utils->startService("httpd");
        }
    }
    return $rc;
}

#-----------------------------------------------------------------------------
#
#=head3 enable_TFTPhpa
#
#    Configure and enable the tftp-hpa in the xinetd.
#
#=cut
#
#-----------------------------------------------------------------------------
sub enable_TFTPhpa
{
  # Check whether the tftp-hpa has been installed, the ubuntu tftpd-hpa configure file is under /etc/default
  unless (-x "/usr/sbin/in.tftpd" and ( -e "/etc/xinetd.d/tftp" or -e "/etc/default/tftpd-hpa" )) {
    xCAT::MsgUtils->message("S", "ERROR: The tftpd was not installed, enable the tftp failed.");
    return 1;
  }

  # kill the process of atftp if it's there
  my @output = xCAT::Utils->runcmd("ps -ef | grep atftpd | grep -v grep", -1);
  foreach my $ps (@output) {
    $ps =~ s/^\s+//;    # strip any leading spaces
    my ($uid, $pid, $ppid, $desc) = split /\s+/, $ps;
    system("kill -9 $pid >/dev/null 2>&1");
  }

  # read tftpdir directory from database
  my $tftpdir = xCAT::TableUtils->getTftpDir();
  if (!(-e $tftpdir)) {
    mkdir($tftpdir);
  }

  # The location of tftp mapfile
  my $mapfile = "/etc/tftpmapfile4xcat.conf";
  if (! -e "$mapfile") {
    if (! open (MAPFILE, ">$mapfile")) {
      xCAT::MsgUtils->message("S", "ERROR: Cannot open $mapfile.");
      return 1;
    }
    # replace the \ with /
    print MAPFILE 'rg (\\\) \/';
    close (MAPFILE);
  }

  my $distro = xCAT::Utils->osver();
  if ($distro !~ /ubuntu.*/i && $distro !~ /debian.*/i ){
    if (! open (FILE, "</etc/xinetd.d/tftp")) {
      xCAT::MsgUtils->message("S", "ERROR: Cannot open /etc/xinetd.d/tftp.");
      return 1;
    }

    # The location of tftp mapfile
    my $mapfile = "/etc/tftpmapfile4xcat.conf";
    my $recfg = 0;
    my @newcfgfile;
    # Check whether need to reconfigure the /etc/xinetd.d/tftp
    while (<FILE>) {
      # check the configuration of 'server_args = -s /xx -m xx'  entry
      if (/^\s*server_args\s*=(.*)$/) {
        my $cfg_args = $1;
        # handle the -s option for the location of tftp root dir
        if ($cfg_args =~ /-s\s+([^\s]*)/) {
          my $cfgdir = $1;
          $cfgdir =~ s/\$//;
          $tftpdir =~ s/\$//;
          # make sure the tftp dir should comes from the site.tftpdir
          if ($cfgdir ne $tftpdir) {
            $recfg = 1;
          }
        }
        # handle the -m option for the mapfile
        if ($cfg_args !~ /-m\s+([^\s]*)/) {
          $recfg = 1;
        }
        if ($recfg) {
          # regenerate the entry for server_args
          my $newcfg = $_;
          $newcfg =~ s/=.*$/= -s $tftpdir -m $mapfile/;
          push @newcfgfile, $newcfg;
        } else {
          push @newcfgfile, $_;
        }
      } elsif (/^\s*disable\s*=/ && !/^\s*disable\s*=\s*yes/) {
        # disable the tftp by handling the entry 'disable = yes'
        my $newcfg = $_;
        $newcfg =~ s/=.*$/= yes/;
        push @newcfgfile, $newcfg;
        $recfg = 1;
      } else {
        push @newcfgfile, $_;
      }
    }
    close (FILE);

    # reconfigure the /etc/xinetd.d/tftp
    if ($recfg) {
      if (! open (FILE, ">/etc/xinetd.d/tftp")) {
        xCAT::MsgUtils->message("S", "ERROR: Cannot open /etc/xinetd.d/tftp");
        return 1;
      }
      print FILE @newcfgfile;
      close (FILE);
      my @output = xCAT::Utils->runcmd("service xinetd status", -1);
      if ($::RUNCMD_RC == 0) {
        if (grep(/running/, @output))
        {
          print ' ';              # indent service output to separate it from the xcatd service output
          system "service xinetd stop";
          if ($? > 0)
          {    # error
              xCAT::MsgUtils->message("S",
                                        "Error on command: service xinetd stop\n");
          }
          system "service xinetd start";
          if ($? > 0)
          {    # error
              xCAT::MsgUtils->message("S",
                                        "Error on command: service xinetd start\n");
          }
        }
      }
    }
  }

  # get the version of TCP/IP protocol
  my $protocols;
  my $v4only="-4 ";
  if (xCAT::Utils->osver() =~ /^sle[sc]10/) {
      $v4only = "";
  }

  open($protocols,"<","/proc/net/protocols");
  if ($protocols) {
	my $line;
	while ($line = <$protocols>) {
		if ($line =~ /^TCPv6/) {
			$v4only="";
			last;
		}
	}
    } else {
	$v4only="";
    }

    # get the tftpflags which set by customer
    my $tftpflags = xCAT::TableUtils->get_site_attribute("tftpflags");
    my $startcmd = "/usr/sbin/in.tftpd $v4only -v -l -s $tftpdir -m /etc/tftpmapfile4xcat.conf";
    if ($tftpflags) {
        $startcmd = "/usr/sbin/in.tftpd $v4only $tftpflags";
    }


    if (-x "/usr/sbin/in.tftpd") {
	system("killall in.tftpd"); #xinetd can leave behind blocking tftp servers even if it won't start new ones
    if ($distro =~ /ubuntu.*/i){
        sleep 1;
        my @checkproc=`ps axf|grep -v grep|grep in.tftpd`;
        if (@checkproc){
            system("stop tftpd-hpa");
        }
    }

    if ($distro =~ /debian.*/i){
        sleep 1;
        my @checkproc=`ps axf|grep -v grep|grep in.tftpd`;
        if (@checkproc){
            system("service tftpd-hpa stop");
        }
    }
    my @tftpprocs=`ps axf|grep -v grep|grep in.tftpd`;
	while (@tftpprocs) {
		sleep 0.1;
	}
        system("$startcmd");
    }

  return 0;
}

# enable or disable proxydhcp service
sub setup_proxydhcp {
    my $flag = shift;

    my $pid;
    # read the pid of proxydhcp
    if (open (PIDF, "</var/run/xcat/proxydhcp-xcat.pid")) {
        $pid = <PIDF>;
    }
    close(PIDF);

    # kill it first
    if ($pid) {
        kill 2, $pid;
    }

    # start the proxydhcp daemon if it's set to enable
    if ($flag) {
        system ("/opt/xcat/sbin/proxydhcp-xcat -d");
    }
}

1;
