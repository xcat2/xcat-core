#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------
package xCAT_plugin::DNSsn;
use xCAT::Table;

use xCAT::Utils;

use xCAT::MsgUtils;
use Getopt::Long;

#-------------------------------------------------------

=head1 
  xCAT plugin package to setup of DNS 


#-------------------------------------------------------

=head3  handled_commands 

Check to see if on a Service Node
Check database to see if this node is a DNS server
Call  setup_DNS

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
        my $service    = "nameserver";

        $rc = xCAT::Utils->isServiceReq($nodename, $service, \@nodeipaddr);
        if ($rc == 1)
        {

            # service needed on this Service Node
            $rc = &setup_DNS();                            # setup DNS
            if ($rc == 0)
            {
                xCAT::Utils->update_xCATSN($service);
            }
        }
        else
        {
            if ($rc == 2)
            {    # service setup, just start the daemon
                $cmd = "service named start";
                xCAT::Utils->runcmd($cmd, -1);
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

=head3 setup_DNS 

    Sets up Domain Name service  
	http://www.adminschoice.com/docs/domain_name_service.htm#Introduction

=cut

#-----------------------------------------------------------------------------
sub setup_DNS
{
    # setup the named.conf file
    `/opt/xcat/sbin/makenamed.conf`;
    # turn DNS on

    $cmd = "chkconfig named on";
    xCAT::Utils->runcmd($cmd, -1);
    if ($::RUNCMD_RC != 0)
    {
        xCAT::MsgUtils->message("S", "Error from $cmd");
        return 1;
    }
    $cmd = "service named stop";
    xCAT::Utils->runcmd($cmd, -1);

    $cmd = "service named start";
    xCAT::Utils->runcmd($cmd, -1);
    if ($::RUNCMD_RC != 0)
    {
        xCAT::MsgUtils->message("S", "Error from $cmd");
        return 1;
    }

    return 0;
}
1;
