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
  xCAT plugin package to setup  conserver


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
    # If called in XCATBYPASS mode, don't do any setup
    if ($ENV{'XCATBYPASS'}) {
       return 0;
    }

    my $rc = 0;
    if (xCAT::Utils->isServiceNode())
    {
        my @nodeinfo   = xCAT::Utils->determinehostname;
        my $nodename   = pop @nodeinfo;                    # get hostname
        my @nodeipaddr = @nodeinfo;                        # get ip addresses

        my $service = "conserver";
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
        else
        {
            if ($rc == 2)
            {    # already setup, just start the daemon
                    # start conserver
                my $cmd = "/etc/rc.d/init.d/conserver start";
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
        $cmdref->{svboot}->[0]  = "yes";

        my $modname = "conserver";
        ${"xCAT_plugin::" . $modname . "::"}{process_request}
          ->($cmdref, \&xCAT::Client::handle_response);

        my $cmd = "chkconfig conserver on";
        xCAT::Utils->runcmd($cmd, 0);
        if ($::RUNCMD_RC != 0)
        {    # error
            xCAT::MsgUtils->message("S", "Error chkconfig conserver on");
            return 1;
        }

        # start conserver. conserver needs 2 CA files to start
        my $ca_file1="/etc/xcat/ca/ca-cert.pem";
        my $ca_file2="/etc/xcat/cert/server-cred.pem";
        if (! -e $ca_file1) {
	    print "conserver cannot be started because the file $ca_file1 cannot be found\n";
        } elsif (! -e $ca_file2) {
	    print "conserver cannot be started because the file $ca_file2 cannot be found\n";
        } else {
          my $cmd = "/etc/rc.d/init.d/conserver stop";
          my @out = xCAT::Utils->runcmd($cmd, 0);
          if ($::RUNCMD_RC != 0)
          {    # error
            xCAT::MsgUtils->message("S", "Error stopping conserver:".join("\n", @out));
          } else {	# Zero rc, but with the service cmds that does not mean they succeeded
          	my $output = join("\n", @out);
          	if (length($output)) { print "\n$output\n"; }
	    	else { print "\nconserver stopped\n"; }
          }
       
          $cmd = "/etc/rc.d/init.d/conserver start";
          @out = xCAT::Utils->runcmd($cmd, 0);
          if ($::RUNCMD_RC != 0)
          {    # error
            xCAT::MsgUtils->message("S", "Error starting conserver:".join("\n", @out));
            return 1;
          } else {      # Zero rc, but with the service cmds that does not mean they succeeded
                my $output = join("\n", @out);
                if (length($output)) { print "\n$output\n"; }
                else { print "\nconserver started\n"; }
          }
       }
    }
    else
    {        # error reading Db
        $rc = 1;
    }
    return $rc;
}

1;
