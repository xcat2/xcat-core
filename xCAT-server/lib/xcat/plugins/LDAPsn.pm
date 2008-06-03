#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------
package xCAT_plugin::LDAPsn;
use xCAT::Table;

use xCAT::Utils;

use xCAT::MsgUtils;
use Getopt::Long;

#-------------------------------------------------------

=head1 
  xCAT plugin package to setup of LDAP on the ServiceNode 


#-------------------------------------------------------

=head3  handled_commands 

Check to see if on a Service Node
Check database to see if this node is a LDAP server
Call  setup_LDAP 

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
        my $service    = "ldapserver";

        $rc = xCAT::Utils->isServiceReq($nodename, $service, \@nodeipaddr);
        if ($rc == 1)
        {

            # service needed on this Service Node
            $rc = &setup_LDAP();
            if ($rc == 0)
            {
                xCAT::Utils->update_xCATSN($service);
            }
        }
        else
        {
            if ($rc == 2)
            {    # service setup, just start the daemon
                $cmd = "service ldap restart";
                system $cmd;
                if ($? > 0)
                {
                    xCAT::MsgUtils->message("S", "Error from $cmd");
                    return 1;
                }
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

=head3 setup_LDAP 

    Sets up LDAP  

=cut

#-----------------------------------------------------------------------------
sub setup_LDAP
{

    $cmd = "chkconfig ldap on";
    system $cmd;
    if ($? > 0)
    {
        xCAT::MsgUtils->message("S", "Error from $cmd");
        return 1;
    }
    $cmd = "service ldap restart";
    system $cmd;
    if ($? > 0)
    {
        xCAT::MsgUtils->message("S", "Error from $cmd");
        return 1;
    }

    return 0;
}
1;
