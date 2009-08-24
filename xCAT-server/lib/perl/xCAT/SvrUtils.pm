#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::SvrUtils;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
require xCAT::Table;
require xCAT::Utils;

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

#-----------------------------------------------------------------------------


=head3 getsynclistfile
    Get the synclist file for the nodes;
    The arguments $os,$arch,$profile,$insttype are only available when no $nodes is specified

    Arguments:
      $nodes
      $os
      $arch
      $profile
      $insttype  - installation type (can be install or netboot)
    Returns:
      When specified $nodes: reference of a hash of node=>synclist
      Otherwise: full path of the synclist file
    Globals:
        none
    Error:
    Example:
         my $node_syncfile=xCAT::SvrUtils->getsynclistfile($nodes);
         my $syncfile=xCAT::SvrUtils->getsynclistfile(undef, 'sles11', 'ppc64', 'compute', 'netboot');
    Comments:
        none

=cut

#-----------------------------------------------------------------------------



sub getsynclistfile()
{
  my $nodes = shift;
  if (($nodes) && ($nodes =~ /xCAT::SvrUtils/))
  {
    $nodes = shift;
  }

  my ($os, $arch, $profile, $inst_type) = @_;

  # for aix node, use the node figure out the profile, then use the value of
  # profile (osimage name) to get the synclist file path (osimage.synclists)
  if (xCAT::Utils->isAIX()) {
    my %node_syncfile = ();
    my %osimage_syncfile = ();
    my @profiles = ();

    # get the profile attributes for the nodes
    my $nodetype_t = xCAT::Table->new('nodetype');
    unless ($nodetype_t) {
      return ;
    }
    my $nodetype_v = $nodetype_t->getNodesAttribs($nodes, ['profile']);

    # the vaule of profile for AIX node is the osimage name
    foreach my $node (@$nodes) {
      my $profile = $nodetype_v->{$node}->[0]->{'profile'};
      $node_syncfile{$node} = $profile;

      if (! grep /$profile/, @profiles) {
        push @profiles, $profile;
      }
    }

    # get the syncfiles base on the osimage
    my $osimage_t = xCAT::Table->new('osimage');
    unless ($osimage_t) {
      return ;
    }
    foreach my $osimage (@profiles) {
      my $synclist = $osimage_t->getAttribs({imagename=>"$osimage"}, 'synclists');
      $osimage_syncfile{$osimage} = $synclist->{'synclists'};
    }

    # set the syncfiles to the nodes
    foreach my $node (@$nodes) {
      $node_syncfile{$node} = $osimage_syncfile{$node_syncfile{$node}};
    }

    return \%node_syncfile;
  }

  # if does not specify the $node param, default consider for genimage command
  if ($nodes) {
    my %node_syncfile = ();

    my %node_insttype = ();
    my %insttype_node = ();
    # get the nodes installation type
    xCAT::SvrUtils->getNodesetStates($nodes, \%insttype_node);
    # convert the hash to the node=>type
    foreach my $type (keys %insttype_node) {
      foreach my $node (@{$insttype_node{$type}}) {
        $node_insttype{$node} = $type;
      }
    }

    # get the os,arch,profile attributes for the nodes
    my $nodetype_t = xCAT::Table->new('nodetype');
    unless ($nodetype_t) {
      return ;
    }
    my $nodetype_v = $nodetype_t->getNodesAttribs($nodes, ['profile','os','arch']);

    foreach my $node (@$nodes) {
      $inst_type = $node_insttype{$node};
      if ($inst_type eq "netboot" || $inst_type eq "diskless") {
        $inst_type = "netboot";
      } else {
        $inst_type = "install";
      }

      $profile = $nodetype_v->{$node}->[0]->{'profile'};
      $os = $nodetype_v->{$node}->[0]->{'os'};
      $arch = $nodetype_v->{$node}->[0]->{'arch'};

      my $platform = "";
      if ($os) {
        if ($os =~ /rh.*/)    { $platform = "rh"; }
        elsif ($os =~ /centos.*/) { $platform = "centos"; }
        elsif ($os =~ /fedora.*/) { $platform = "fedora"; }
        elsif ($os =~ /sles.*/) { $platform = "sles"; }
        elsif ($os =~ /AIX.*/) { $platform = "AIX"; }
      }

      my $base =  "/install/custom/$inst_type/$platform";
      if (-r "$base/$profile.$os.$arch.synclist") {
        $node_syncfile{$node} = "$base/$profile.$os.$arch.synclist";
      } elsif (-r "$base/$profile.$arch.synclist") {
        $node_syncfile{$node} = "$base/$profile.$arch.synclist";
      } elsif (-r "$base/$profile.$os.synclist") {
        $node_syncfile{$node} = "$base/$profile.$os.synclist";
      } elsif (-r "$base/$profile.synclist") {
        $node_syncfile{$node} = "$base/$profile.synclist";
      }
    }

    return \%node_syncfile;
  } else {
    my $platform = "";
    if ($os) {
      if ($os =~ /rh.*/)    { $platform = "rh"; }
      elsif ($os =~ /centos.*/) { $platform = "centos"; }
      elsif ($os =~ /fedora.*/) { $platform = "fedora"; }
      elsif ($os =~ /sles.*/) { $platform = "sles"; }
      elsif ($os =~ /AIX.*/) { $platform = "AIX"; }
    }

    my $base = "/install/custom/$inst_type/$platform";
    if (-r "$base/$profile.$os.$arch.synclist") {
      return "$base/$profile.$os.$arch.synclist";
    } elsif (-r "$base/$profile.$arch.synclist") {
      return "$base/$profile.$arch.synclist";
    } elsif (-r "$base/$profile.$os.synclist") {
      return "$base/$profile.$os.synclist";
    } elsif (-r "$base/$profile.synclist") {
      return "$base/$profile.synclist";
    }

  }

}


1;
