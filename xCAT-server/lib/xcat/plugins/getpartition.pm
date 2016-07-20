# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle getpartition command
  Generally, the getpartitioin command is called from the stateless 
    node during the booting period to get the partition configureation
    infomation to part the hard disk on the stateless node and to 
    manage the local disk space for statelite and swap space.
=cut

#-------------------------------------------------------
package xCAT_plugin::getpartition;
use xCAT::Utils;
use xCAT::MsgUtils;
use xCAT::Table;
use xCAT::NodeRange;

#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return { 'getpartition' => "getpartition" };
}


#-------------------------------------------------------

=head3  process_request

  Process the command

=cut

#-------------------------------------------------------
sub process_request
{
    my $request  = shift;
    my $callback = shift;
    my $subreq   = shift;

    my $client;
    if ($request->{'_xcat_clienthost'}) {
        $client = $request->{'_xcat_clienthost'}->[0];
    }

    if ($client) { ($client) = noderange($client) }
    unless ($client) {    #Not able to do identify the host in question
        xCAT::MsgUtils->message("S", "Received syncfiles from $client, which couldn't be correlated to a node (domain mismatch?)");
        return;
    }

    parsepartition($client, $callback, $subreq);
}


#----------------------------------------------------------------------------

=head3  

    parseparition
    
        Description: Read the partition configuration file from 
          linuximage.partitionfile, parse the file and send back the partition
          parameters to the node.
        Arguments:
        Returns: 0 - failed; 1 - succeeded;
=cut

#-----------------------------------------------------------------------------

sub parsepartition {
    my $node     = shift;
    my $callback = shift;
    my $subreq   = shift;

    # get the partition file from linuximage.partitionfile
    my $partfile;
    my $rsp;

    my $provmethod;
    my ($os, $arch, $profile);

    my $nttab = xCAT::Table->new('nodetype', -create => 1);
    if ($nttab) {
        my $ntent = $nttab->getNodeAttribs($node, [ 'provmethod', 'os', 'arch', 'profile' ]);
        unless ($ntent) {
            push @{ $rsp->{data} }, "Error: No entry in nodetype table";
            $callback->($rsp);
            return;
        }
        $provmethod = $ntent->{'provmethod'};
        $os         = $ntent->{'os'};
        $arch       = $ntent->{'arch'};
        $profile    = $ntent->{'profile'};
    } else {
        push @{ $rsp->{data} }, "Error: Could not open nodetype table";
        $callback->($rsp);
        return;
    }

    my $imagename;
    if (($provmethod ne 'install') and ($provmethod ne 'netboot') and ($provmethod ne 'statelite')) {
        $imagename = $provmethod;
    } else {
        $imagename = "$os-$arch-$provmethod-$profile";
    }

    my $linuximagetab = xCAT::Table->new('linuximage', -create => 1);
    if ($linuximagetab) {
        my $lient = $linuximagetab->getAttribs({ imagename => $imagename }, ['partitionfile']);
        unless ($lient) {
            push @{ $rsp->{data} }, "Error: No entry in linuximage table";
            $callback->($rsp);
            return;
        }
        $partfile = $lient->{'partitionfile'};
    } else {
        push @{ $rsp->{data} }, "Error: Could not open linuximage table";
        $callback->($rsp);
        return;
    }

    my $cfgfile;
    if ($partfile =~ /s:(.*)/) {

        # It's a script that could be run directly to do the partition configuring
        $cfgfile = $1;
        push @{ $rsp->{data} }, "type=script";

        #push @{$rsp->{data}}, "enable=yes";
    } else {
        $cfgfile = $partfile;
        push @{ $rsp->{data} }, "type=format";
    }

    unless (-r $cfgfile) {
        push @{ $rsp->{data} }, "Error: Could not read the file $1";
        $callback->($rsp);
        return;
    }
    open(FILE, "<$cfgfile");
    push @{ $rsp->{data} }, <FILE>;
    $callback->($rsp);
    return;


}

1;
