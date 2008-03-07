#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------
package xCAT_plugin::DHCPsn;
use xCAT::Table;

use xCAT::Utils;
use xCAT_plugin::dhcp;
use xCAT::MsgUtils;

use xCAT::Client;
use Getopt::Long;

#-------------------------------------------------------

=head1 
  xCAT plugin package to setup of DHCP 


#-------------------------------------------------------

=head3  handled_commands 

Check to see if on a Service Node
Check database to see if this node is a DHCP server
Call  setup_DHCP

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
        my $service    = "dhcpserver";

        $rc = xCAT::Utils->isServiceReq($nodename, $service, \@nodeipaddr);
        if ($rc == 1)
        {

            # service needed on this Service Node
            $rc = &setup_DHCP($nodename);                  # setup DHCP
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

=head3 setup_DHCP 

    Sets up DHCP services  

=cut

#-----------------------------------------------------------------------------
sub setup_DHCP
{
    my ($nodename) = @_;
    my $rc = 0;
    my $cmd;
    my @output;

    # read DB for nodeinfo
    my $retdata = xCAT::Utils->readSNInfo($nodename);
    if ($retdata->{'arch'})
    {    # no error
        my $master = $retdata->{'master'};
        my $os     = $retdata->{'os'};
        my $arch   = $retdata->{'arch'};

        # run makedhcp
        $XCATROOT = "/opt/xcat";    # default

        if ($ENV{'XCATROOT'})
        {
            $XCATROOT = $ENV{'XCATROOT'};
        }
        my $cmdref;
        $cmdref->{command}->[0] = "makedhcp";
        $cmdref->{cwd}->[0]     = "/opt/xcat/sbin";
        $cmdref->{arg}->[0]     = "-n";

        my $modname = "dhcp";
        ${"xCAT_plugin::" . $modname . "::"}{process_request}
          ->($cmdref,\&xCAT::Client::handle_response);

        $cmd = "chkconfig dhcpd on";
        xCAT::Utils->runcmd($cmd, -1);
        if ($::RUNCMD_RC != 0)
        {
            xCAT::MsgUtils->message("S", "Error from $cmd");
            return 1;
        }
        $cmd = "/etc/rc.d/init.d/dhcpd start";
        xCAT::Utils->runcmd($cmd, -1);
        if ($::RUNCMD_RC != 0)
        {
            xCAT::MsgUtils->message("S", "Error from $cmd");
            return 1;
        }

    }
    else
    {    # error reading Db
        $rc = 1;
    }
    return $rc;
}

1;
