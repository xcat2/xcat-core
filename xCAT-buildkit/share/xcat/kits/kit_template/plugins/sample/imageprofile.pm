# IBM(c) 2012 EPL license http://www.eclipse.org/legal/epl-v10.html

#TEST: UNCOMMENT the first line, and COMMENT OUT the second line.
#BUILD: COMMENT OUT the first line, and UNCOMMENT the second line.
#package xCAT_plugin::imageprofile;
package xCAT_plugin::<<<buildkit_WILL_INSERT_modified_kitname_HERE>>>_imageprofile;

use strict;
use warnings;

require xCAT::Utils;
require xCAT::Table;
require xCAT::KitPluginUtils;

use Data::Dumper;

#
# KIT PLUGIN FOR IMAGE PROFILE MANAGEMENT
# =======================================
# What is this plugin used for?
#    This is an xCAT Perl plugin that lets you add custom code
#    which gets called during certain image profile management 
#    operations.
#
#
# What image profile management operations automatically call this plugin?
#
#    - Generate image profile (pcmgenerateimageprofile / pcmmgtnodeimageprofile)
#      operation calls:
#          - kitimagepregenerate():  Any code added here gets called
#                                    before an image profile is created.
#
#          - kitimagepostgenerate(): Any code added here gets called
#                                    after an image profile is created.
#
#    - Copy image profile (pcmcopyimageprofile) operation calls:
#          - kitimageprecopy():  Any code added here gets called
#                                before an image profile is copied.
#
#          - kitimagepostcopy(): Any code added here gets called
#                                after an image profile is copied.
#
#    - Update image profile (pcmupdateimageprofile) operation calls:
#          - kitimagepreupdate():  Any code added here gets called
#                                  before an image profile is updated.
#
#          - kitimagepostupdate(): Any code added here gets called
#                                  after an image profile is updated.
#
#    - Delete image profile (pcmdeleteimageprofile) operation calls:
#          - kitimagepredelete():  Any code added here gets called
#                                  before an image profile is deleted.
#
#          - kitimagepostdelete(): Any code added here gets called
#                                  after an image profile is deleted.
#
#
# How to create a new plugin for your kit?
#
#    1) Copy the sample plugin
#          % cp plugins/sample/imageprofile.pm plugins
#
#    2) Modify the sample plugin by implementing one or more of 
#       the plugin commands above.
#
#       Refer to each command's comments for command parameters 
#       and return values.
#
#       For details on how to write plugin code, refer to:
#       http://sourceforge.net/apps/mediawiki/xcat/index.php?title=XCAT_Developer_Guide
#
#    3) To test the plugin commands:
#          a) Search this file for lines that start with "TEST:" and follow the 
#              instructions
#
#          b) Refer to each command's comments for test steps.
#
#    4) After you finish the test, you can build the the kit.
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
    #TEST: UNCOMMENT the first return, and COMMENT OUT the second return.
    #BUILD: COMMENT OUT the first return, and UNCOMMENT the second return.
    #return {
    #    kitimagepregenerate => 'imageprofile',
    #    kitimagepostgenerate => 'imageprofile',
    #    kitimageprecopy => 'imageprofile',
    #    kitimagepostcopy => 'imageprofile',
    #    kitimagepreupdate => 'imageprofile',
    #    kitimagepostupdate => 'imageprofile',
    #    kitimagepredelete => 'imageprofile',
    #    kitimagepostdelete => 'imageprofile',
    #};
    return {
        kitimagepregenerate => '<<<buildkit_WILL_INSERT_modified_kitname_HERE>>>_imageprofile',
        kitimagepostgenerate => '<<<buildkit_WILL_INSERT_modified_kitname_HERE>>>_imageprofile',
        kitimageprecopy => '<<<buildkit_WILL_INSERT_modified_kitname_HERE>>>_imageprofile',
        kitimagepostcopy => '<<<buildkit_WILL_INSERT_modified_kitname_HERE>>>_imageprofile',
        kitimagepreupdate => '<<<buildkit_WILL_INSERT_modified_kitname_HERE>>>_imageprofile',
        kitimagepostupdate => '<<<buildkit_WILL_INSERT_modified_kitname_HERE>>>_imageprofile',
        kitimagepredelete => '<<<buildkit_WILL_INSERT_modified_kitname_HERE>>>_imageprofile',
        kitimagepostdelete => '<<<buildkit_WILL_INSERT_modified_kitname_HERE>>>_imageprofile',
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
    my $args = $request->{arg};

    # This kit plugin is passed the name of an image profile.
    # Before running this plugin, we should check if the 
    # image profile is using the kit which this plugin belongs to.

    if ($PLUGIN_KITNAME eq "TESTMODE") {
        # Don't do the check in test mode
    } elsif ($command eq 'kitimagepregenerate' || $command eq 'kitimageprecopy') {
        # Also, don't do the check if the image profile doesn't yet exist
    } else {
        # Do the check 
        my $imageprofile = parse_str_arg($request->{arg}->[0]);

        if (! exists($request->{kitdata}))
        {
            $rsp->{data}->[0] = "Skipped running \"$command\" plugin command for \"$PLUGIN_KITNAME\" kit.";
            xCAT::MsgUtils->message("I", $rsp, $callback);
            return;
        }
        my $kitdata = $request->{kitdata};
        if (! defined($kitdata) && !($command eq "kitimagepostdelete")) {
            $kitdata = xCAT::KitPluginUtils->get_kits_used_by_image_profiles([$imageprofile]);
            $request->{kitdata} = $kitdata;
        }

        if (! exists($kitdata->{$PLUGIN_KITNAME})) {
            # This image profile is not using this plugin's kit, so don't run the plugin.
            $rsp->{data}->[0] = "Skipped running \"$command\" plugin command for \"$PLUGIN_KITNAME\" kit.";
            xCAT::MsgUtils->message("I", $rsp, $callback);
            return;
        }
    }


    # Run the command
    
    if($command eq 'kitimagepregenerate') {
        kitimagepregenerate($callback, $args);
    }
    elsif ($command eq 'kitimagepostgenerate') {
        kitimagepostgenerate($callback, $args);
    }
    elsif ($command eq 'kitimageprecopy') {
        kitimageprecopy($callback, $args);
    }
    elsif ($command eq 'kitimagepostcopy') {
        kitimagepostcopy($callback, $args);
    }
    elsif ($command eq 'kitimagepreupdate') {
        kitimagepreupdate($callback, $args);
    }
    elsif ($command eq 'kitimagepostupdate') {
        kitimagepostupdate($callback, $args);
    }
    elsif ($command eq 'kitimagepredelete') {
        kitimagepredelete($callback, $args);
    }
    elsif ($command eq 'kitimagepostdelete') {
        kitimagepostdelete($callback, $args);
    } else {
        my $rsp;
        $rsp->{data}->[0] = "Command is not supported";
        xCAT::MsgUtils->message("E", $rsp, $callback);
    }
}


#-------------------------------------------------------

=head3  kitimagepregenerate

     This command is called before an image profile 
     is created with a specified set of parameters.

     Command-line interface:
          kitimagepregenerate imageprofile="<image profile name>"
                              osdistro="<os distro name>"
                              osdistroupdate="<os distro update name>"
                              bootparams="<boot params string>"
                              ospkgs="<comma-separated list of ospkgs>"
                              custompkgs="<comma-separated list of custompkgs>"
                              kitcomponents="<comma-separated list of kitcomponents>"
                              modules="<comma-separated list of modules>"

     Parameters:
          $imageprofile    :  image profile name
          $osdistro        :  os distro name
          $osdistroupdate  :  os distro update name
          $bootparams      :  boot params string
          @ospkgs          :  list of ospkg names
          @custompkgs      :  list of custompkg names
          @kitcomponents   :  list of kit component names
          @modules         :  list of module names

     Return value:
         Info/Debug messages should be returned like so:
             $rsp->{data}->[0] = "Info messsage";
             xCAT::MsgUtils->message("I", $rsp, $callback);

         Errors should be returned like so:
             $rsp->{data}->[0] = "Error messsage";
             xCAT::MsgUtils->message("E", $rsp, $callback);

     Test Steps:
         # cd /opt/xcat/bin
         # ln -s xcatclientnnr kitimagepregenerate
         # cd -
         # XCATBYPASS=/path/to/this/plugin kitimagepregenerate <params ...>

=cut

#-------------------------------------------------------

sub kitimagepregenerate {
    my $callback = shift;
    my $args = shift;
    my $rsp;

    # Parameters
    my $imageprofile = parse_str_arg(shift(@$args));
    my $osdistro = parse_str_arg(shift(@$args));
    my $osdistroupdate = parse_str_arg(shift(@$args));
    my $bootparams = parse_str_arg(shift(@$args));
    my @ospkgs = parse_list_arg(shift(@$args));
    my @custompkgs = parse_list_arg(shift(@$args));
    my @kitcomponents = parse_list_arg(shift(@$args));
    my @modules = parse_list_arg(shift(@$args));

    $rsp->{data}->[0] = "Running kitimagepregenerate ($PLUGIN_KITNAME) ...";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    $rsp->{data}->[0] = "Image Profile: $imageprofile";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    # TODO: ADD YOUR CODE HERE
}


#-------------------------------------------------------

=head3  kitimagepostgenerate

     This command is called after an image profile 
     is created.

     Command-line interface:
          kitimagepostgenerate imageprofile="<image profile name>"

     Parameters:
          $imageprofile    :  image profile name

     Return value:
         Info/Debug messages should be returned like so:
             $rsp->{data}->[0] = "Info messsage";
             xCAT::MsgUtils->message("I", $rsp, $callback);

         Errors should be returned like so:
             $rsp->{data}->[0] = "Error messsage";
             xCAT::MsgUtils->message("E", $rsp, $callback);

     Test Steps:
         # cd /opt/xcat/bin
         # ln -s xcatclientnnr kitimagepostgenerate
         # cd -
         # XCATBYPASS=/path/to/this/plugin kitimagepostgenerate <params ...>

=cut

#-------------------------------------------------------

sub kitimagepostgenerate {
    my $callback = shift;
    my $args = shift;
    my $rsp;

    # Parameters
    my $imageprofile = parse_str_arg(shift(@$args));

    $rsp->{data}->[0] = "Running kitimagepostgenerate ($PLUGIN_KITNAME) ...";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    $rsp->{data}->[0] = "Image Profile: $imageprofile";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    # TODO: ADD YOUR CODE HERE
}


#-------------------------------------------------------

=head3  kitimageprecopy

     This command is called before an image profile 
     is copied with a specified set of parameters.

     Command-line interface:
          kitimageprecopy  imageprofile="<image profile name>"
                           osdistro="<os distro name>"
                           osdistroupdate="<os distro update name>"
                           bootparams="<boot params string>"
                           ospkgs="<comma-separated list of ospkgs>"
                           custompkgs="<comma-separated list of custompkgs>"
                           kitcomponents="<comma-separated list of kitcomponents>"
                           modules="<comma-separated list of modules>"

     Parameters:
          $imageprofile    :  image profile name
          $osdistro        :  os distro name
          $osdistroupdate  :  os distro update name
          $bootparams      :  boot params string
          @ospkgs          :  list of ospkg names
          @custompkgs      :  list of custompkg names
          @kitcomponents   :  list of kit component names
          @modules         :  list of module names

     Return value:
         Info/Debug messages should be returned like so:
             $rsp->{data}->[0] = "Info messsage";
             xCAT::MsgUtils->message("I", $rsp, $callback);

         Errors should be returned like so:
             $rsp->{data}->[0] = "Error messsage";
             xCAT::MsgUtils->message("E", $rsp, $callback);

     Test Steps:
         # cd /opt/xcat/bin
         # ln -s xcatclientnnr kitimageprecopy
         # cd -
         # XCATBYPASS=/path/to/this/plugin kitimageprecopy <params ...>

=cut

#-------------------------------------------------------

sub kitimageprecopy {
    my $callback = shift;
    my $args = shift;
    my $rsp;

    # Parameters
    my $imageprofile = parse_str_arg(shift(@$args));
    my $osdistro = parse_str_arg(shift(@$args));
    my $osdistroupdate = parse_str_arg(shift(@$args));
    my $bootparams = parse_str_arg(shift(@$args));
    my @ospkgs = parse_list_arg(shift(@$args));
    my @custompkgs = parse_list_arg(shift(@$args));
    my @kitcomponents = parse_list_arg(shift(@$args));
    my @modules = parse_list_arg(shift(@$args));

    $rsp->{data}->[0] = "Running kitimageprecopy ($PLUGIN_KITNAME) ...";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    $rsp->{data}->[0] = "Image Profile: $imageprofile";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    # TODO: ADD YOUR CODE HERE
}


#-------------------------------------------------------

=head3  kitimagepostcopy

     This command is called after an image profile 
     is copied.

     Command-line interface:
          kitimagepostcopy imageprofile="<image profile name>"

     Parameters:
          $imageprofile    :  image profile name

     Return value:
         Info/Debug messages should be returned like so:
             $rsp->{data}->[0] = "Info messsage";
             xCAT::MsgUtils->message("I", $rsp, $callback);

         Errors should be returned like so:
             $rsp->{data}->[0] = "Error messsage";
             xCAT::MsgUtils->message("E", $rsp, $callback);

     Test Steps:
         # cd /opt/xcat/bin
         # ln -s xcatclientnnr kitimagepostcopy
         # cd -
         # XCATBYPASS=/path/to/this/plugin kitimagepostcopy <params ...>

=cut

#-------------------------------------------------------

sub kitimagepostcopy {
    my $callback = shift;
    my $args = shift;
    my $rsp;

    # Parameters
    my $imageprofile = parse_str_arg(shift(@$args));

    $rsp->{data}->[0] = "Running kitimagepostcopy ($PLUGIN_KITNAME) ...";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    $rsp->{data}->[0] = "Image Profile: $imageprofile";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    # TODO: ADD YOUR CODE HERE
}


#-------------------------------------------------------

=head3  kitimagepreupdate

     This command is called before an image profile 
     is updated with a specified set of parameters.

     Command-line interface:
          kitimagepreupdate  imageprofile="<image profile name>"
                             osdistro="<os distro name>"
                             osdistroupdate="<os distro update name>"
                             bootparams="<boot params string>"
                             ospkgs="<comma-separated list of ospkgs>"
                             custompkgs="<comma-separated list of custompkgs>"
                             kitcomponents="<comma-separated list of kitcomponents>"
                             modules="<comma-separated list of modules>"

     Parameters:
          $imageprofile    :  image profile name
          $osdistro        :  os distro name
          $osdistroupdate  :  os distro update name
          $bootparams      :  boot params string
          @ospkgs          :  list of ospkg names
          @custompkgs      :  list of custompkg names
          @kitcomponents   :  list of kit component names
          @modules         :  list of module names

     Return value:
         Info/Debug messages should be returned like so:
             $rsp->{data}->[0] = "Info messsage";
             xCAT::MsgUtils->message("I", $rsp, $callback);

         Errors should be returned like so:
             $rsp->{data}->[0] = "Error messsage";
             xCAT::MsgUtils->message("E", $rsp, $callback);

     Test Steps:
         # cd /opt/xcat/bin
         # ln -s xcatclientnnr kitimagepreupdate
         # cd -
         # XCATBYPASS=/path/to/this/plugin kitimagepreupdate <params ...>

=cut

#-------------------------------------------------------

sub kitimagepreupdate {
    my $callback = shift;
    my $args = shift;
    my $rsp;

    # Parameters
    my $imageprofile = parse_str_arg(shift(@$args));
    my $osdistro = parse_str_arg(shift(@$args));
    my $osdistroupdate = parse_str_arg(shift(@$args));
    my $bootparams = parse_str_arg(shift(@$args));
    my @ospkgs = parse_list_arg(shift(@$args));
    my @custompkgs = parse_list_arg(shift(@$args));
    my @kitcomponents = parse_list_arg(shift(@$args));
    my @modules = parse_list_arg(shift(@$args));

    $rsp->{data}->[0] = "Running kitimagepreupdate ($PLUGIN_KITNAME) ...";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    $rsp->{data}->[0] = "Image Profile: $imageprofile";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    # TODO: ADD YOUR CODE HERE
}


#-------------------------------------------------------

=head3  kitimagepostupdate

     This command is called after an image profile 
     is updated.

     Command-line interface:
          kitimagepostupdate imageprofile="<image profile name>"

     Parameters:
          $imageprofile    :  image profile name

     Return value:
         Info/Debug messages should be returned like so:
             $rsp->{data}->[0] = "Info messsage";
             xCAT::MsgUtils->message("I", $rsp, $callback);

         Errors should be returned like so:
             $rsp->{data}->[0] = "Error messsage";
             xCAT::MsgUtils->message("E", $rsp, $callback);

     Test Steps:
         # cd /opt/xcat/bin
         # ln -s xcatclientnnr kitimagepostupdate
         # cd -
         # XCATBYPASS=/path/to/this/plugin kitimagepostupdate <params ...>

=cut

#-------------------------------------------------------

sub kitimagepostupdate {
    my $callback = shift;
    my $args = shift;
    my $rsp;

    # Parameters
    my $imageprofile = parse_str_arg(shift(@$args));

    $rsp->{data}->[0] = "Running kitimagepostupdate ($PLUGIN_KITNAME) ...";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    $rsp->{data}->[0] = "Image Profile: $imageprofile";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    # TODO: ADD YOUR CODE HERE
}

#-------------------------------------------------------

=head3  kitimagepredelete

     This command is called before an image profile 
     is deleted.

     Command-line interface:
          kitimagepredelete  imageprofile="<image profile name>"

     Parameters:
          $imageprofile    :  image profile name

     Return value:
         Info/Debug messages should be returned like so:
             $rsp->{data}->[0] = "Info messsage";
             xCAT::MsgUtils->message("I", $rsp, $callback);

         Errors should be returned like so:
             $rsp->{data}->[0] = "Error messsage";
             xCAT::MsgUtils->message("E", $rsp, $callback);

     Test Steps:
         # cd /opt/xcat/bin
         # ln -s xcatclientnnr kitimagepredelete
         # cd -
         # XCATBYPASS=/path/to/this/plugin kitimagepredelete <params ...>

=cut

#-------------------------------------------------------

sub kitimagepredelete {
    my $callback = shift;
    my $args = shift;
    my $rsp;

    # Parameters
    my $imageprofile = parse_str_arg(shift(@$args));

    $rsp->{data}->[0] = "Running kitimagepredelete ($PLUGIN_KITNAME) ...";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    $rsp->{data}->[0] = "Image Profile: $imageprofile";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    # TODO: ADD YOUR CODE HERE
}


#-------------------------------------------------------

=head3  kitimagepostdelete

     This command is called after an image profile 
     is deleted.

     Command-line interface:
          kitimagepostdelete imageprofile="<image profile name>"

     Parameters:
          $imageprofile    :  image profile name

     Return value:
         Info/Debug messages should be returned like so:
             $rsp->{data}->[0] = "Info messsage";
             xCAT::MsgUtils->message("I", $rsp, $callback);

         Errors should be returned like so:
             $rsp->{data}->[0] = "Error messsage";
             xCAT::MsgUtils->message("E", $rsp, $callback);

     Test Steps:
         # cd /opt/xcat/bin
         # ln -s xcatclientnnr kitimagepostdelete
         # cd -
         # XCATBYPASS=/path/to/this/plugin kitimagepostdelete <params ...>

=cut

#-------------------------------------------------------

sub kitimagepostdelete {
    my $callback = shift;
    my $args = shift;
    my $rsp;

    # Parameters
    my $imageprofile = parse_str_arg(shift(@$args));

    $rsp->{data}->[0] = "Running kitimagepostdelete ($PLUGIN_KITNAME) ...";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    $rsp->{data}->[0] = "Image Profile: $imageprofile";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    # TODO: ADD YOUR CODE HERE
}



#-------------------------------------------------------

=head3  parse_str_arg

    Utility function to extract the string value of an 
    argument in this format:
         PARAM=string1

    Returns a string:
         'string1'
=cut

#-------------------------------------------------------
sub parse_str_arg {
  
   my $arg = shift;
   my $result;

   if (!defined($arg)) {
      return $arg;
   }
   
   $arg =~ s/.*?=//;
   $result = $arg;
 
   return $result;

}


#-------------------------------------------------------

=head3  parse_list_arg

    Utility function to extract the list of values of 
    an argument in this format:
         PARAM=value1,value2,value3

    Returns a list of values:
         ('value1', 'value2', 'value3')

=cut

#-------------------------------------------------------
sub parse_list_arg {
  
   my $arg = shift;
   my @result;
   
   if (!defined($arg)) {
      return $arg;
   }

   $arg =~ s/.*?=//;
   @result = split(/,/, $arg);
 
   return @result;

}

1;
