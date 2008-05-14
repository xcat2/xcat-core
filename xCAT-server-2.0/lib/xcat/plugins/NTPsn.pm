#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------
package xCAT_plugin::NTPsn;
use xCAT::Table;
use xCAT::Utils;
use xCAT::MsgUtils;
use File::Path;

#-------------------------------------------------------

=head1 
  xCAT plugin package to setup NTP on a  service node 


#-------------------------------------------------------

=head3  handled_commands 

This runs on Service Node 
Checks servicenode table ntpserver attribute
Call  setup_NTP

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
        my $service    = "ntpserver";
        $rc = xCAT::Utils->isServiceReq($nodename, $service, \@nodeipaddr);
        if ($rc == 1)
        {
            $rc = &setup_NTPsn($nodename);    #setup NTP on Service Node
            if ($rc == 0)
            {
                xCAT::Utils->update_xCATSN($service);
            }
        }
        else
        {
            if ($rc == 2)
            {                                 # just start the daemon
                my $cmd = "service ntpd restart";
                system $cmd;
                if ($? > 0)
                {                             # error
                    xCAT::MsgUtils->message("S", "Error on command: $cmd");
                    return 1;
                }
            }
        }
    }
    else
    {                                         # Management Node
        $rc = &setup_NTPmn();                 # setup NTP on Management Node

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
        print CFGFILE $master;
        print CFGFILE "\n";
        print CFGFILE "driftfile /var/lib/ntp/drift\n";
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

    # restart ntp

    my $cmd = "service ntpd restart";
    system $cmd;
    if ($? > 0)
    {
        xCAT::MsgUtils->message("S", "Error from command:$cmd");
        return 1;
    }
    my $cmd = "chkconfig ntpd on";
    system $cmd;
    if ($? > 0)
    {
        xCAT::MsgUtils->message("S", "Error from command:$cmd");
        return 1;
    }

    return 0;
}

#-----------------------------------------------------------------------------

=head3 backup_NTPconf 

    Starts daemon 

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

1;
