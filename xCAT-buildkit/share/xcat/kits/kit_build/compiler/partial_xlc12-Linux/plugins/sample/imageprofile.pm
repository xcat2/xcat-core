package xCAT_plugin::<<<buildkit_WILL_INSERT_kitname_HERE>>>_imageprofile;

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

    Image Profile Kit Plugin
    This plugin contains commands to run custom actions 
    during image profile operations.

=cut

#-------------------------------------------------------


#-------------------------------------------------------

=head3  handled_commands

    Return list of kit plugin commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands {
    return {
        kitimagevalidatecomps => '<<<buildkit_WILL_INSERT_kitname_HERE>>>_imageprofile',
        kitimageimport => '<<<buildkit_WILL_INSERT_kitname_HERE>>>_imageprofile',
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

    # This kit plugin is passed the name of an image profile.
    # We need to determine which kits is used by this
    # image profile to decide if this plugin should run or not.

    my $imgprofilename = $request->{arg}->[0];

    my $kitdata = $request->{kitdata};
    if (! defined($kitdata)) {
        $kitdata = xCAT::KitPluginUtils->get_kits_used_by_image_profiles([$imgprofilename]);
        $request->{kitdata} = $kitdata;
    }

    if ($PLUGIN_KITNAME ne "TESTMODE" && ! exists($kitdata->{$PLUGIN_KITNAME})) {
        return;
    }

    # Name of command and node list
    my $command = $request->{command}->[0];
    my $args = $request->{arg};

    if($command eq 'kitimagevalidatecomps') {
        kitimagevalidatecomps($callback, $args);
    }
    elsif ($command eq 'kitimageimport') {
        kitimageimport($callback, $args);

    } else {
        my $rsp;
        $rsp->{data}->[0] = "Command is not supported";
        xCAT::MsgUtils->message("E", $rsp, $callback);
    }
}


#-------------------------------------------------------

=head3  kitimagevalidatecomps

     This command is called to validate new changes to an 
     image profile's kit component list before the changes 
     are committed.

=cut

#-------------------------------------------------------

sub kitimagevalidatecomps {
    my $callback = shift;
    my $args = shift;
    my $rsp;

    # Parameters
    my $imgprofilename =  $args->[0];
    my $newcomplist = $args->[1];
    my @newcomplist = ();
    if (defined($newcomplist)) {
        @newcomplist = split(/,/, $newcomplist);
    }
    my $newosdistro = $args->[2];
    my $newosdistroupdate = $args->[3];

    $rsp->{data}->[0] = "Running kitimagevalidatecomps";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    # TODO
    # ... ADD YOUR CODE HERE
}


#-------------------------------------------------------

=head3  kitimageimport

    This command is called after changes to an image profile 
    have been committed.

=cut

#-------------------------------------------------------

sub kitimageimport {
    my $callback = shift;
    my $args = shift;
    my $rsp;

    # Parameters
    my $imgprofilename = $args->[0];

    $rsp->{data}->[0] = "Running kitimageimport";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    # TODO
    # ... ADD YOUR CODE HERE
}


