#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------
package xCAT_plugin::CONSsn;
use xCAT::Table;

use xCAT::Utils;
use xCAT_plugin::conserver;

use xCAT::Client;
use xCAT::MsgUtils;
use Getopt::Long;

#-------------------------------------------------------

=head1 
  xCAT plugin package to setup of nfs and mount /install 
  and /tfptboot


#-------------------------------------------------------

=head3  handled_commands 

Check to see if on a Service Node
Check database to see if this node is going to have Conserver setup 
   should be always
Call  setup_CONS

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

        my $service = "cons";
        $rc = xCAT::Utils->isServiceReq($nodename, $service, \@nodeipaddr);
        if ($rc == 1)
        {

            # service needed on this Service Node
            $rc = &setup_CONS($nodename);                  # setup CONS
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
        $cmdref->{cwd}->[0]     = "/opt/xcat/sbin";

        my $modname = "conserver";
        ${"xCAT_plugin::" . $modname . "::"}{process_request}
          ->($cmdref,\&xCAT::Client::handle_response);
        my $cmd = "chkconfig conserver on";
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {    # error
            xCAT::MsgUtils->message("S", "Error chkconfig conserver on");
            return 1;
        }

        # start conserver
        my $cmd = "/etc/rc.d/init.d/conserver start";
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {    # error
            xCAT::MsgUtils->message("S", "Error starting Conserver");
            return 1;
        }

    }
    else
    {        # error reading Db
        $rc = 1;
    }
    return $rc;
}

1;
