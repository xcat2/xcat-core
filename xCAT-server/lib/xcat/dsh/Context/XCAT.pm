#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package XCAT;
use base xCAT::DSHContext;
use strict;
use Socket;
use xCAT::Utils;
use xCAT::MsgUtils;
# Define remote shell globals from xCAT

our $XCAT_RSH_CMD;
our $XCAT_RCP_CMD;

#
# get the remote command settings
#

XCAT->get_xcat_remote_cmds;

# Global Data structures for xCAT context

our @xcat_node_list       = ();
our %xcat_nodegroup_table = ();

#-------------------------------------------------------------------------------

=head3
        context_defaults

        Assign default properties for the xCAT context.  A default
        property for a context will be used if the property is
        not user configured in any other way.

        Arguments:
        	None

        Returns:
        	A reference to a hash table with the configured
        	default properties for the xCAT context
                
        Globals:
        	$XCAT_RSH_CMD
    
        Error:
        	None
    
        Example:
        	$default_properties = XCAT->config_defaults;

        Comments:
        	$defaults hash table contents:
        	
        		$defaults{'NodeRemoteShell'} - default remote shell to use for node targets

=cut

#-------------------------------------------------------------------------------
sub context_defaults
{
    my %defaults = ();

    $defaults{'NodeRemoteShell'} = $XCAT_RSH_CMD;

    return \%defaults;
}

#-------------------------------------------------------------------------------

=head3
        context_properties

        Configure the user specified context properties for the xCAT context.
        These properties are configured by the user through environment
        variables or external configuration files.

        Arguments:
        	None

        Returns:
        	A reference to a hash table of user-configured properties for
        	the xCAT context.
                
        Globals:
        	None
    
        Error:
        	None
    
        Example:
        	$properties = XCAT->config_properties

        Comments:

=cut

#-------------------------------------------------------------------------------
sub context_properties
{
    my %properties = ();

    $properties{'RemoteShell'}   = $XCAT_RSH_CMD;
    $properties{'RemoteCopyCmd'} = $XCAT_RCP_CMD;

    return \%properties;
}

#-------------------------------------------------------------------------------

=head3
        all_devices
            
        Comments: devices are nodes in the XCAT context.  Use node flags
        and not device flags.

=cut

#-------------------------------------------------------------------------------
sub all_devices
{
    my ($class, $resolved_targets) = @_;

    xCAT::MsgUtils->message(
        "E",
        " Nodes and Devices are considered nodes in xCAT.\n The -A flag is not supported. Use the all group in XCAT to dsh to all node/devices.\n"
        );
    return;
}

#-------------------------------------------------------------------------------

=head3
        all_nodes

        Returns an array of all node names in the xCAT context
		Note in xCAT everything is a node including devices

        Arguments:
        	None

        Returns:
        	An array of node/device names
                
        Globals:
        	@xcat_node_list
    
        Error:
        	None
    
        Example:
        	@nodes = XCAT->get_xcat_node_list;

        Comments:

=cut

#-------------------------------------------------------------------------------
sub all_nodes
{
    scalar(@xcat_node_list) || XCAT->get_xcat_node_list;
    return @xcat_node_list;
}

#-------------------------------------------------------------------------------

=head3
        all_nodegroups

        Returns an array of all node group names in the xCAT context
		Note in xCAT everything is a node including devices

        Arguments:
        	None

        Returns:
        	An array of node/device group names
                
        Globals:
        	%xcat_nodegroup_table
    
        Error:
        	None
    
        Example:
        	@nodegroups = XCAT->all_nodegroups;

        Comments:

=cut

#-------------------------------------------------------------------------------
sub all_nodegroups
{
    scalar(%xcat_nodegroup_table) || XCAT->get_xcat_nodegroup_table;
    return keys(%xcat_nodegroup_table);
}

#-------------------------------------------------------------------------------

=head3
        nodegroup_members

        Given a node/device group in the xCAT context, this routine expands the
        membership of the  group and returns a list of its members.

        Arguments:
        	$nodegroup - node group name

        Returns:
        	An array of node group members
                
        Globals:
        	$nodegroup_path
    
        Error:
        	None
    
        Example:
        	$members = XCAT->nodegroup_members('MyGroup1');

        Comments:

=cut

#-------------------------------------------------------------------------------
sub nodegroup_members
{
    my ($class, $nodegroup) = @_;
    my %node_list = ();
    scalar(%xcat_nodegroup_table) || XCAT->get_xcat_nodegroup_table;
    !defined($xcat_nodegroup_table{$nodegroup}) && return undef;

    my @nodes = split /,/, $xcat_nodegroup_table{$nodegroup};

    foreach my $node (@nodes)
    {
        $node_list{$node}++;
    }

    my @members = keys(%node_list);
    return \@members;

}

#-------------------------------------------------------------------------------

=head3
        resolve_node

        Within the xCAT context, resolve the name of a given node and
        augment the supplied property hash table with xCAT node information.        

        Arguments:
        	$target_properties - basic properties hash table reference for a node

        Returns:
        	1 if resolution was successful
        	undef otherwise
                
        Globals:
        	$XCAT_RSH_CMD
        	$XCAT_RCP_CMD
    
        Error:
        	None
    
        Example:
        	XCAT->resolve_node($target_properties);

        Comments:

=cut

#-------------------------------------------------------------------------------
sub resolve_node
{
    my ($class, $target_properties) = @_;

    $$target_properties{'remote-shell'} = $XCAT_RSH_CMD;
    $$target_properties{'remote-copy'}  = $XCAT_RCP_CMD;

    return 1;
}

#-------------------------------------------------------------------------------

=head3
        get_xcat_remote_cmds

        Using xCAT native commands,check the useSSHonAIX attribute for AIX 
          on Linux use ssh    
          on AIX, check for useSSHonAIX,  if says use ssh and
           it is installed and configured, use it
          , otherwise use rsh

        site.rsh and site.rcp are no longer used

        Arguments:
        	None

        Returns:
        	None
        	                
        Globals:
        	$XCAT_RSH_CMD
        	$XCAT_RCP_CMD
    
        Error:
        	None
    
        Example:
        	XCAT->get_xcat_remote_cmds

        Comments:
        	Internal routine only

=cut

#-------------------------------------------------------------------------------
sub get_xcat_remote_cmds
{
    # override with site table settings, if they exist 
    my $ssh_setup = 0;
    my @useSSH = xCAT::Utils->get_site_attribute("useSSHonAIX");
    if (defined($useSSH[0])) {
      $useSSH[0] =~ tr/a-z/A-Z/;    # convert to upper 
      if (($useSSH[0] eq "1") || ($useSSH[0] eq "YES"))
      {
          $ssh_setup = 1;
      }
    } else {   # default is SSH
          $ssh_setup = 1;
    }
    if (xCAT::Utils->isLinux()) { 
      $XCAT_RSH_CMD = "/usr/bin/ssh";    # use ssh
      $XCAT_RCP_CMD = "/usr/bin/scp"; 
    } else { # AIX
      if ((-e "/usr/bin/ssh") && ( $ssh_setup == 1)) {  # ssh is configured 
        $XCAT_RSH_CMD = "/usr/bin/ssh";    # use ssh 
        $XCAT_RCP_CMD = "/usr/bin/scp"; 
      } else {
        $XCAT_RSH_CMD = "/usr/bin/rsh";    #  use rsh
        $XCAT_RCP_CMD = "/usr/bin/rcp"; 
      }
    }

}

#-------------------------------------------------------------------------------

=head3
        get_xcat_node_list

        Using xCAT native commands, this routine builds a cached list of
        node/device names defined in the xCAT context

        Arguments:
        	None

        Returns:
        	None
                
        Globals:
        	%xcat_node_list
    
        Error:
        	None
    
        Example:
        	XCAT->get_xcat_node_list

        Comments:
        	Internal routine only

=cut

#-------------------------------------------------------------------------------
sub get_xcat_node_list
{
    @xcat_node_list = xCAT::Utils->get_node_list;
    chomp(@xcat_node_list);
}

#-------------------------------------------------------------------------------

=head3
        get_xcat_nodegroup_table

        Using xCAT native commands, this routine builds a cached list of
        node groups and their members defined in the xCAT context

        Arguments:
        	None

        Returns:
        	None
                
        Globals:
        	%xcat_nodegroup_table
    
        Error:
        	None
    
        Example:
           XCAT->get_xcat_nodegroup_table

        Comments:
        	Internal routine only

=cut

#-------------------------------------------------------------------------------
sub get_xcat_nodegroup_table
{
    my $node_list = "";
    my @nodegroups = xCAT::Utils->list_all_node_groups;
    for my $group (@nodegroups)
    {
        chomp($group);
        my @nodes = `nodels $group`;
        my $node_list;
        while (@nodes)
        {
            my $nodename = shift @nodes;
            chomp($nodename);
            $node_list .= $nodename;
            $node_list .= ",";
        }
        chop($node_list);
        $xcat_nodegroup_table{$group} = $node_list;
        $node_list = "";
    }
}

sub query_node
{
    my ($class, $node, $flag) = @_;
    my @xcat_nodes = all_nodes();

    $~ = "NODES";
    if ($flag)
    {
        if (grep(/^$node$/, @xcat_nodes))
        {
            print("$node : Valid\n");
        }
        else
        {
            print("$node : Invalid\n");
        }
    }
    else
    {
        print("$node : Invalid\n");
    }
}

sub query_group
{

    my ($class, $group) = @_;
    my @xcat_groups = all_nodegroups();

    $~ = "GROUPS";
    if (grep(/^$group$/, @xcat_groups))
    {
        print("$group : Valid\n");
    }
    else
    {
        print("$group : Invalid\n");
    }
}

1;    #end
