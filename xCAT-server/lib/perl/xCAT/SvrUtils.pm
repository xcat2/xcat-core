#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::SvrUtils;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
require xCAT::Table;

use strict;


#-------------------------------------------------------------------------------

=head3   getNodesetStates
       get current nodeset stat for the given nodes 
    Arguments:
        nodes -- a pointer to an array of nodes
        hashref -- A pointer to a hash that contains the nodeset status.  
    Returns:
       (ret code, error message) 

=cut

#-------------------------------------------------------------------------------
sub getNodesetStates
{
    my $noderef = shift;
    if ($noderef =~ /xCAT::SvrUtils/)
    {
        $noderef = shift;
    }
    my @nodes   = @$noderef;
    my $hashref = shift;

    if (@nodes > 0)
    {
        my $tab = xCAT::Table->new('noderes');
        if (!$tab) { return (1, "Unable to open noderes table."); }

        my @aixnodes    = ();
        my @pxenodes    = ();
        my @yabootnodes = ();
        my $tabdata     = $tab->getNodesAttribs(\@nodes, ['node', 'netboot']);
        foreach my $node (@nodes)
        {
            my $nb   = "aixinstall";
            my $tmp1 = $tabdata->{$node}->[0];
            if (($tmp1) && ($tmp1->{netboot})) { $nb = $tmp1->{netboot}; }
            if ($nb eq "yaboot")
            {
                push(@yabootnodes, $node);
            }
            elsif ($nb eq "pxe")
            {
                push(@pxenodes, $node);
            }
            elsif ($nb eq "aixinstall")
            {
                push(@aixnodes, $node);
            }
        }

        my @retarray;
        my $retcode = 0;
        my $errormsg;

        # print "ya=@yabootnodes, pxe=@pxenodes, aix=@aixnodes\n";
        if (@yabootnodes > 0)
        {
            require xCAT_plugin::yaboot;
            @retarray =
              xCAT_plugin::yaboot::getNodesetStates(\@yabootnodes, $hashref);
            if ($retarray[0])
            {
                $retcode = $retarray[0];
                $errormsg .= $retarray[1];
                xCAT::MsgUtils->message('E', $retarray[1]);
            }
        }
        if (@pxenodes > 0)
        {
            require xCAT_plugin::pxe;
            @retarray =
              xCAT_plugin::pxe::getNodesetStates(\@pxenodes, $hashref);
            if ($retarray[0])
            {
                $retcode = $retarray[0];
                $errormsg .= $retarray[1];
                xCAT::MsgUtils->message('E', $retarray[1]);
            }
        }
        if (@aixnodes > 0)
        {
            require xCAT_plugin::aixinstall;
            @retarray =
              xCAT_plugin::aixinstall::getNodesetStates(\@aixnodes, $hashref);
            if ($retarray[0])
            {
                $retcode = $retarray[0];
                $errormsg .= $retarray[1];
                xCAT::MsgUtils->message('E', $retarray[1]);
            }
        }
    }
    return (0, "");
}

#-------------------------------------------------------------------------------

=head3   get_nodeset_state
       get current nodeset stat for the given node.
    Arguments:
        nodes -- node name.
    Returns:
       nodesetstate 

=cut

#-------------------------------------------------------------------------------
sub get_nodeset_state
{
    my $node = shift;
    if ($node =~ /xCAT::SvrUtils/)
    {
        $node = shift;
    }

    my $state = "undefined";

    #get boot type (pxe, yaboot or aixinstall)  for the node
    my $noderestab = xCAT::Table->new('noderes', -create => 0);
    my $ent = $noderestab->getNodeAttribs($node, [qw(netboot)]);
    if ($ent && $ent->{netboot})
    {
        my $boottype = $ent->{netboot};

        #get nodeset state from corresponding files
        if ($boottype eq "pxe")
        {
            require xCAT_plugin::pxe;
            my $tmp = xCAT_plugin::pxe::getstate($node);
            my @a = split(' ', $tmp);
            $state = $a[0];

        }
        elsif ($boottype eq "yaboot")
        {
            require xCAT_plugin::yaboot;
            my $tmp = xCAT_plugin::yaboot::getstate($node);
            my @a = split(' ', $tmp);
            $state = $a[0];
        }
        elsif ($boottype eq "aixinstall")
        {
            require xCAT_plugin::aixinstall;
            $state = xCAT_plugin::aixinstall::getNodesetState($node);
        }
    }
    else
    {    #default to AIX because AIX does not set noderes.netboot value
        require xCAT_plugin::aixinstall;
        $state = xCAT_plugin::aixinstall::getNodesetState($node);
    }

    #get the nodeset state from the chain table as a backup.
    if ($state eq "undefined")
    {
        my $chaintab = xCAT::Table->new('chain');
        my $stref = $chaintab->getNodeAttribs($node, ['currstate']);
        if ($stref and $stref->{currstate}) { $state = $stref->{currstate}; }
    }

    return $state;
}


1;
