# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle getadapter request from genesis.

   Supported command:
        getadapter->getadapter

=cut

#-------------------------------------------------------
package xCAT_plugin::getadapter;

BEGIN {
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}
use lib "$::XCATROOT/lib/perl";

use xCAT::Table;
use xCAT::State;
use strict;

#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {
        getadapter => "getadapter",
    };
}

#------------------------------------------------------------------

=head3  route_request

  This subroutine is used for the command called from genesis. As the client of
  genesis is not a command line interface, this hook comand can help save one
  fork compare with a common command.

  return REQUEST_UPDATE if request is received.
  return REQUEST_ERROR if error happens.

  Usage example:
        This is a hook function in xcatd, do not use it directly.
=cut

#-----------------------------------------------------------------
sub route_request {
    my $request = shift;
    my $command = $request->{command}->[0];
    if ($command eq "getadapter") {
        if (!defined($request->{'action'}) || $request->{action}->[0] ne xCAT::State->UPDATE_ACTION) {
            return xCAT::State->REQUEST_ERROR;
        }
        my $node = $request->{'_xcat_clienthost'}->[0];
        if (!$request->{nic}) {
            xCAT::MsgUtils->message("S", "$node: Could not get any nic information");
            return xCAT::State->REQUEST_ERROR;
        }
        my $nics = \@{ $request->{nic} };
        xCAT::MsgUtils->message("S", "$node: callback message from getadapter received");
        if (update_nics_info($node, $nics)!=0) {
            return xCAT::State->REQUEST_ERROR;
        }
    }
    return xCAT::State->REQUEST_UPDATE;
}

sub update_nics_info {
    my $node = shift;
    my $nics_ptr = shift;
    my (@nics, @data, %updates);
    @nics = @{$nics_ptr};

    my $update_nics_table_func = sub {
        my $node = shift;
        my $nics = shift;
        my $nics_table = xCAT::Table->new('nics');
        unless ($nics_table) {
            xCAT::MsgUtils->message("S", "Unable to open nics table for getadapter, denying");
            return -1;
        }
        $updates{'nicsadapter'} = $nics;
        if ($nics_table->setAttribs({ 'node' => $node }, \%updates) != 0) {
            xCAT::MsgUtils->message("S", "Error to update nics table for getadapter.");
            return -1;
        }
        $nics_table->close();
        return 0;
    };

    for (my $i = 0; $i < scalar(@nics); $i++) {
        if ($nics[$i]->{interface}) {
            my @nic_attrs = ();
            if ($nics[$i]->{mac}) {
                push(@nic_attrs, "mac=".$nics[$i]->{mac}->[0]);
            }
            if ($nics[$i]->{linkstate}) {
                push (@nic_attrs, "linkstate=". (split(' ', $nics[$i]->{linkstate}->[0]))[0]);
            }
            if($nics[$i]->{pcilocation}) {
                push(@nic_attrs, "pci=" . $nics[$i]->{pcilocation}->[0]);
            }
            if ($nics[$i]->{predictablename}) {
                push(@nic_attrs, "candidatename=" . $nics[$i]->{predictablename}->[0]);
            }
            if (@nic_attrs) {
                push(@data, $nics[$i]->{interface}->[0]."!".join(" ", @nic_attrs));
            }
        }
    }
    return $update_nics_table_func->($node, join(",", @data));
}

1;
