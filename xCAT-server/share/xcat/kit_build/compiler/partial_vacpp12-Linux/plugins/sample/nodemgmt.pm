package xCAT_plugin::<<<buildkit_WILL_INSERT_kitname_HERE>>>_nodemgmt;

use strict;
use warnings;

require xCAT::Utils;
require xCAT::Table;
require xCAT::KitPluginUtils;

# buildkit Processing
#   In order to avoid collisions with other plugins, the package
#   name for this plugin must contain the full kit name.
#   The buildkit buildtar command will copy this file from your plugins
#   directory to the the kit build directory, renaming the file with the
#   correct kit name.  All strings in this file of the form 
#      <<<buildkit_WILL_INSERT_kitname_HERE>>>
#   will be replaced with the full kit name.  In order for buildkit to
#   correctly edit this file, do not remove these strings.

# Global Variables

# This is the full name of the kit which this plugin belongs 
# to. The kit name is used by some code in process_request() 
# to determine if the plugin should run.  When you are testing 
# your plugin the kit name should be set to "TESTMODE" to 
# bypass the plugin check in process_request().

our ($PLUGIN_KITNAME);
#$PLUGIN_KITNAME = "TESTMODE";
$PLUGIN_KITNAME = "<<<buildkit_WILL_INSERT_kitname_HERE>>>";


#-------------------------------------------------------

=head1

    Node Management Kit Plugin
    This plugin contains commands to run custom actions 
    during node management operations.

=cut

#-------------------------------------------------------


#-------------------------------------------------------

=head3  handled_commands

    Return list of kit plugin commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands {
    return {
        kitnodeadd => '<<<buildkit_WILL_INSERT_kitname_HERE>>>_nodemgmt',
        kitnoderemove => '<<<buildkit_WILL_INSERT_kitname_HERE>>>_nodemgmt',
        kitnodeupdate => '<<<buildkit_WILL_INSERT_kitname_HERE>>>_nodemgmt',
        kitnoderefresh => '<<<buildkit_WILL_INSERT_kitname_HERE>>>_nodemgmt',
        kitnodefinished => '<<<buildkit_WILL_INSERT_kitname_HERE>>>_nodemgmt',
    };
}


#-------------------------------------------------------

=head3  process_request

    Process the kit plugin command.

=cut

#-------------------------------------------------------

sub process_request {
    my $request = shift;
    my $callback = shift;

    # Name of command and node list
    my $command = $request->{command}->[0];
    my $nodes = $request->{node};

    # This kit plugin is passed a list of node names.
    # We need to determine which kits are used by these
    # nodes to decide if this plugin should run or not.

    my $kitdata = $request->{kitdata};
    if (! defined($kitdata)) {
        $kitdata = xCAT::KitPluginUtils->get_kits_used_by_nodes($nodes);
        $request->{kitdata} = $kitdata;
    }

    if ($PLUGIN_KITNAME ne "TESTMODE" && ! exists($kitdata->{$PLUGIN_KITNAME})) {
        return;
    }

    # Get the nodes using this plugin's kit
    $nodes = $kitdata->{$PLUGIN_KITNAME};


    if($command eq 'kitnodeadd') {
        kitnodeadd($callback, $nodes);
    }
    elsif ($command eq 'kitnoderemove') {
        kitnoderemove($callback, $nodes);
    }
    elsif ($command eq 'kitnodeupdate') {
        kitnodeupdate($callback, $nodes);
    }
    elsif ($command eq 'kitnoderefresh') {
        kitnoderefresh($callback, $nodes);
    }
    elsif ($command eq 'kitnodefinished') {
        kitnodefinished($callback);

    } else {
        my $rsp;
        $rsp->{data}->[0] = "Command is not supported";
        xCAT::MsgUtils->message("E", $rsp, $callback);
    }
}


#-------------------------------------------------------

=head3  kitnodeadd

    This command is called when one or more nodes are added 
    to the cluster.

=cut

#-------------------------------------------------------

sub kitnodeadd {
    my $callback = shift;
    my $rsp;

    # Parameters
    my $nodes = shift;

    $rsp->{data}->[0] = "Running kitnodeadd";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    # TODO
    # ... ADD YOUR CODE HERE
}


#-------------------------------------------------------

=head3  kitnoderemove

    This command is called when one or more nodes are 
    removed from the cluster.

=cut

#-------------------------------------------------------

sub kitnoderemove {
    my $callback = shift;
    my $rsp;

    # Parameters
    my $nodes = shift;

    $rsp->{data}->[0] = "Running kitnoderemove";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    # TODO
    # ... ADD YOUR CODE HERE
}


#-------------------------------------------------------

=head3  kitnodeupdate

    This command is called when the configuration of one 
    or more nodes are updated.

=cut

#-------------------------------------------------------

sub kitnodeupdate {
    my $callback = shift;
    my $rsp;

    # Parameters
    my $nodes = shift;

    $rsp->{data}->[0] = "Running kitnodeupdate";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    # TODO
    # ... ADD YOUR CODE HERE
}


#-------------------------------------------------------

=head3  kitnoderefresh

    This command is called when node-related configuration
    files are updated.

=cut

#-------------------------------------------------------

sub kitnoderefresh {
    my $callback = shift;
    my $rsp;

    # Parameters
    my $nodes = shift;

    $rsp->{data}->[0] = "Running kitnoderefresh";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    # TODO
    # ... ADD YOUR CODE HERE
}


#-------------------------------------------------------

=head3  kitnodefinished

    This command is called at the end of a node management
    operation. 

=cut

#-------------------------------------------------------

sub kitnodefinished {
    my $callback = shift;
    my $rsp;

    $rsp->{data}->[0] = "Running kitnodefinished";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    # TODO
    # ... ADD YOUR CODE HERE
}

