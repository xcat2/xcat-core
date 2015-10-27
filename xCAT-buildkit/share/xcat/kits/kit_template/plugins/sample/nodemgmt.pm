# IBM(c) 2012 EPL license http://www.eclipse.org/legal/epl-v10.html

#TEST: UNCOMMENT the first line, and COMMENT OUT the second line.
#BUILD: COMMENT OUT the first line, and UNCOMMENT the second line.
#package xCAT_plugin::nodemgmt;
package xCAT_plugin::<<<buildkit_WILL_INSERT_modified_kitname_HERE>>>_nodemgmt;

use strict;
use warnings;

require xCAT::Utils;
require xCAT::Table;
require xCAT::KitPluginUtils;

use Data::Dumper;


#
# KIT PLUGIN FOR NODE MANAGEMENT
# ==============================
# What is this plugin used for?
#    This is an xCAT Perl plugin that lets you add custom code
#    which gets called during certain node management operations.
#
#
# What node management operations automatically call this plugin?
#
#    - Import node (nodeimport) / Discover node (findme) operations call:
#          - kitnodeadd():  Any code added here gets called after
#                           one or more nodes are added to the cluster. 
#
#    - Remove node (nodepurge) operation calls:
#          - kitnoderemove():  Any code added here gets called after
#                              one or more nodes are removed from the cluster. 
#
#    - Update node's profiles (kitnodeupdate) / Update node's MAC (nodechmac)
#      operations call:
#          - kitnodeupdate():  Any code added here gets called after
#                              a node's profile(s) or MAC address changes
#
#    - Refresh node's configuration files (noderefresh) / Re-generate IPs 
#       for nodes (noderegenips) operations call:
#          - kitnoderefresh():  Any code added here gets called when 
#                               node config files need to be regenerated. 
#
#
# How to create a new plugin for your kit?
#
#    1) Copy the sample plugin
#          % cp plugins/sample/nodemgmt.pm plugins
#
#    2) Modify the sample plugin by implementing one or more of
#       the plugin commands above.
#
#      Refer to each command's comments for command parameters 
#      and return values.
#
#      For details on how to write plugin code, refer to:
#      http://sourceforge.net/p/xcat/wiki/XCAT_Developer_Guide/
#
#    3) To test the plugin commands:
#          a) Search this file for lines that start with "TEST:" and follow the
#              instructions
#
#          b) Refer to each command's comments for test steps.
#
#    4) After you finish the test, you can build the kit with your new plugin.
#       Before building, search this file for lines that start with "BUILD:" and
#       follow the instructions.
#
#    5) Run buildkit as normal to build the kit.
#


our ($PLUGIN_KITNAME);

#TEST: UNCOMMENT the first line, and COMMENT OUT the second line.
#BUILD: COMMENT OUT the first line, and UNCOMMENT the second line.
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
    #TEST: UNCOMMENT the first return, and COMMENT OUT the second return.
    #BUILD: COMMENT OUT the first return, and UNCOMMENT the second return.
    #return {
    #    kitnodeadd => 'nodemgmt',
    #    kitnoderemove => 'nodemgmt',
    #    kitnodeupdate => 'nodemgmt',
    #    kitnoderefresh => 'nodemgmt',
    #};
    return {
        kitnodeadd => '<<<buildkit_WILL_INSERT_modified_kitname_HERE>>>_nodemgmt',
        kitnoderemove => '<<<buildkit_WILL_INSERT_modified_kitname_HERE>>>_nodemgmt',
        kitnodeupdate => '<<<buildkit_WILL_INSERT_modified_kitname_HERE>>>_nodemgmt',
        kitnoderefresh => '<<<buildkit_WILL_INSERT_modified_kitname_HERE>>>_nodemgmt',
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
    my $rsp;

    # Name of command and node list
    my $command = $request->{command}->[0];
    my $nodes = $request->{node};

    # This kit plugin is passed a list of node names.
    # Before running this plugin, we should check which 
    # nodes are using the kit which this plugin belongs to,
    # and run the plugin only on these nodes.

    my $nodes2;

    if ($PLUGIN_KITNAME eq "TESTMODE") {
        # Don't do the check in test mode
        $nodes2 = $nodes;
    } else {
        # Do the check
        my $kitdata = $request->{kitdata};
        if (! defined($kitdata)) {
            $kitdata = xCAT::KitPluginUtils->get_kits_used_by_nodes($nodes);
            $request->{kitdata} = $kitdata;
        }

        if (! exists($kitdata->{$PLUGIN_KITNAME})) {
            # None of the nodes are using this plugin's kit, so don't run the plugin.
            $rsp->{data}->[0] = "Skipped running \"$command\" plugin command for \"$PLUGIN_KITNAME\" kit.";
            xCAT::MsgUtils->message("I", $rsp, $callback);
            return;
        }
        $nodes2 = $kitdata->{$PLUGIN_KITNAME};
    }

    # Run the command

    if($command eq 'kitnodeadd') {
        kitnodeadd($callback, $nodes2);
    }
    elsif ($command eq 'kitnoderemove') {
        kitnoderemove($callback, $nodes2);
    }
    elsif ($command eq 'kitnodeupdate') {
        kitnodeupdate($callback, $nodes2);
    }
    elsif ($command eq 'kitnoderefresh') {
        kitnoderefresh($callback, $nodes2);

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

    Command-line interface:
         kitnodeadd <noderange>

    Parameters:
         $nodes: list of nodes

    Return value:
         Info/Debug messages should be returned like so:
             $rsp->{data}->[0] = "Info messsage";
             xCAT::MsgUtils->message("I", $rsp, $callback);

         Errors should be returned like so:
             $rsp->{data}->[0] = "Error messsage";
             xCAT::MsgUtils->message("E", $rsp, $callback);

    Test Steps:
         # cd /opt/xcat/bin
         # ln -s xcatclient kitnodeadd
         # cd -
         # XCATBYPASS=/path/to/this/plugin kitnodeadd <noderange>

=cut

#-------------------------------------------------------

sub kitnodeadd {
    my $callback = shift;
    my $rsp;

    # Parameters
    my $nodes = shift;

    $rsp->{data}->[0] = "Running kitnodeadd ($PLUGIN_KITNAME) ...";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    $rsp->{data}->[0] = "Nodes: @$nodes";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    # TODO
    # ... ADD YOUR CODE HERE
    #
}


#-------------------------------------------------------

=head3  kitnoderemove

    This command is called when one or more nodes are 
    removed from the cluster.

    Command-line interface:
         kitnoderemove <noderange>

    Parameters:
         $nodes: list of nodes

    Return value:
         Info/Debug messages should be returned like so:
             $rsp->{data}->[0] = "Info messsage";
             xCAT::MsgUtils->message("I", $rsp, $callback);

         Errors should be returned like so:
             $rsp->{data}->[0] = "Error messsage";
             xCAT::MsgUtils->message("E", $rsp, $callback);

    Test Steps:
         # cd /opt/xcat/bin
         # ln -s xcatclient kitnoderemove
         # cd -
         # XCATBYPASS=/path/to/this/plugin kitnoderemove <noderange>

=cut

#-------------------------------------------------------

sub kitnoderemove {
    my $callback = shift;
    my $rsp;

    # Parameters
    my $nodes = shift;

    $rsp->{data}->[0] = "Running kitnoderemove ($PLUGIN_KITNAME) ...";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    $rsp->{data}->[0] = "Nodes: @$nodes";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    # TODO
    # ... ADD YOUR CODE HERE
    #
}


#-------------------------------------------------------

=head3  kitnodeupdate

    This command is called when the configuration of one 
    or more nodes are updated.

    Command-line interface:
         kitnodeupdate <noderange>

    Parameters:
         $nodes: list of nodes

    Return value:
         Info/Debug messages should be returned like so:
             $rsp->{data}->[0] = "Info messsage";
             xCAT::MsgUtils->message("I", $rsp, $callback);

         Errors should be returned like so:
             $rsp->{data}->[0] = "Error messsage";
             xCAT::MsgUtils->message("E", $rsp, $callback);

    Test Steps:
         # cd /opt/xcat/bin
         # ln -s xcatclient kitnodeupdate
         # cd -
         # XCATBYPASS=/path/to/this/plugin kitnodeupdate <noderange>

=cut

#-------------------------------------------------------

sub kitnodeupdate {
    my $callback = shift;
    my $rsp;

    # Parameters
    my $nodes = shift;

    $rsp->{data}->[0] = "Running kitnodeupdate ($PLUGIN_KITNAME) ...";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    $rsp->{data}->[0] = "Nodes: @$nodes";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    # TODO
    # ... ADD YOUR CODE HERE
    #
}


#-------------------------------------------------------

=head3  kitnoderefresh

    This command is called to refresh node-related configuration
    files. 

    Command-line interface:
         kitnoderefresh <noderange>

    Parameters:
         $nodes: list of nodes

    Return value:
         Info/Debug messages should be returned like so:
             $rsp->{data}->[0] = "Info messsage";
             xCAT::MsgUtils->message("I", $rsp, $callback);

         Errors should be returned like so:
             $rsp->{data}->[0] = "Error messsage";
             xCAT::MsgUtils->message("E", $rsp, $callback);

    Test Steps:
         # cd /opt/xcat/bin
         # ln -s xcatclient kitnoderefresh
         # cd -
         # XCATBYPASS=/path/to/this/plugin kitnoderefresh <noderange>

=cut

#-------------------------------------------------------

sub kitnoderefresh {
    my $callback = shift;
    my $rsp;

    # Parameters
    my $nodes = shift;

    $rsp->{data}->[0] = "Running kitnoderefresh ($PLUGIN_KITNAME) ...";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    $rsp->{data}->[0] = "Nodes: @$nodes";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    # TODO
    # ... ADD YOUR CODE HERE
    #
}

1;
