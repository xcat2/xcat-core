#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#####################################################
#
#  xCAT plugin package to handle commands that manage the xCAT object
#     definitions
#
#####################################################
package xCAT_plugin::DBobjectdefs;
use xCAT::NodeRange;
use xCAT::Schema;
use Data::Dumper;
use Getopt::Long;

# options can be bundled up like -vV
Getopt::Long::Configure("bundling");

# calculate the following sets of attr values for each object definition
#    (where appropriate)
# - order of precedence: CLIATTRS overrides FILEATTRS
%::CLIATTRS;      # attr=values provided on the command line
%::FILEATTRS;     # attr=values provided in a file
%::FINALATTRS;    # actual attr=values that are used to define the object

@::objects;       # list of object names to define
$::noderange;     # noderange from command line

#------------------------------------------------------------------------------

=head1    DBobjectdefs

This program module file supports the management of the xCAT data object 
definitions.

Supported xCAT data object commands/subroutines:
     defmk - create xCAT data object definitions.
     defls - list xCAT data object definitions.
     defch - change xCAT data object definitions.
     defrm - remove xCAT data object definitions.

If adding to this file, please take a moment to ensure that:

    1. Your contrib has a readable pod header describing the purpose and use of
      the subroutine.

    2. Your contrib is under the correct heading and is in alphabetical order
    under that heading.

    3. You have run tidypod on your this file and saved the html file

=cut

#------------------------------------------------------------------------------

=head2    xCAT data object definition support

=cut

#------------------------------------------------------------------------------

#----------------------------------------------------------------------------

=head3  handled_commands

        Return a list of commands handled by this plugin

=cut

#-----------------------------------------------------------------------------

sub handled_commands
{
    return {
            defmk => "DBobjectdefs",
            defls => "DBobjectdefs",
            defch => "DBobjectdefs",
            defrm => "DBobjectdefs"
            };
}

#----------------------------------------------------------------------------

=head3   process_request

        Check for xCAT command and call the appropriate subroutine.

        Arguments:
                
        Returns:
                0 - OK
                1 - error
        Globals:
               
        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub process_request
{

    $::request  = shift;
    $::callback = shift;

    my $ret;
    my $msg;
    my %rsp = ();

    # globals used by all subroutines.
    $::command = $::request->{command}->[0];
    $::args    = $::request->{arg};

    # figure out which cmd and call the subroutine to process
    if ($::command eq "defmk")
    {
        ($ret, $msg) = &defmk;
    }
    elsif ($::command eq "defls")
    {
        ($ret, $msg) = &defls;
    }
    elsif ($::command eq "defch")
    {
        ($ret, $msg) = &defch;
    }
    elsif ($::command eq "defrm")
    {
        ($ret, $msg) = &defrm;
    }

    if ($msg)
    {
        my %rsp = ();
        $rsp->{data}->[0] = $msg;
        $::callback->($rsp);
    }
    return $ret;
}

#----------------------------------------------------------------------------

=head3   processArgs

        Process the command line. Covers all four commands.

		Also - Process any input files provided on cmd line.

        Arguments:

        Returns:
                0 - OK
                1 - just print usage
				2 - error
        Globals:
                
        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub processArgs
{
    $gotattrs = 0;

    @ARGV = @{$::args};

    # parse the options - include any option from all 4 cmds
    if (
        !GetOptions(
                    'a=s'       => \$::opt_a,
                    'dynamic|d' => \$::opt_d,
                    'f=s'       => \$::opt_f,
                    'i=s'       => \$::opt_i,
                    'help|h'    => \$::opt_h,
                    'long|l'    => \$::opt_l,
                    'm|minus'   => \$::opt_m,
                    'o=s'       => \$::opt_o,
                    'r|relace'  => \$::opt_r,
                    't=s'       => \$::opt_t,
                    'verbose|V' => \$::opt_V,
                    'version|v' => \$::opt_v,
                    'w=s'       => \$::opt_w,
                    'x=s'       => \$::opt_x,
                    'z=s'       => \$::opt_z
        )
      )
    {
        return 1;
    }

    # put attr=val operands in ATTRS hash
    while (my $a = shift(@ARGV))
    {

        #print "arg= $a\n";

        if (!($a =~ /=/))
        {
            @::noderange = &noderange($a, 0);
        }
        else
        {

            # if it has an "=" sign its an attr=val - we hope
            my ($attr, $value) = $a =~ /^\s*(\S+?)\s*=\s*(\S+.*)$/;
            if (!defined($attr) || !defined($value))
            {
                print "bad attr=val pair - $a\n";
            }

            $gotattrs = 1;

            my $found = 0;

            # replace the following with check based on schema.pm

            #foreach my $va (@::VALID_ATTRS)
            #{
            #    if (($attr =~ /^$va$/i) && !$found)
            #    {
            #        $::ATTRS{$va} = $value;
            #        $found = 1;
            #    }
            #}

            # put attr=val in hash
            $::ATTRS{$attr} = $value;

            #print "attr=$attr, val= $::ATTRS{$attr} \n";
            $found = 1;

            if (!$found)
            {
                print "$attr - is not a valid attribute!\n";
            }
        }
    }

    # Option -h for Help
    if (defined($::opt_h))
    {
        return 1;
    }

    # Option -v for version - do we need this???
    if (defined($::opt_v))
    {
        my %rsp;
        $rsp->{data}->[0] = "$::command - version 1.0";
        $::callback->($rsp);
        return 0;
    }

    # Option -V for verbose output
    if (defined($::opt_V))
    {
        $::verbose = 1;
        print "set verbose mode\n";
    }

    # could have comma seperated list of types
    if ($::opt_t)
    {

        # make a list
        # - is this a valid type? - check schema !!
        #    note: if type is used with file then just do that type even
        #   if there are others in the file
        if ($::opt_t =~ /,/)
        {

            # can't have mult types when using attr=val
            if ($gotattrs)
            {
                print
                  "error - can't have multiple type with attr=value pairs.\n";
            }
            else
            {
                @::clobjtypes = split(',', $::opt_t);
            }
        }
        else
        {
            push(@::clobjtypes, $::opt_t);
        }
    }

    # if there is no other input for object names then we need to
    #	find all the object names for the specified types
    if (
        $::opt_t
        && !(
                $::opt_o
             || $::opt_f
             || $::opt_x
             || $::opt_z
             || $::opt_a
             || @::noderange
        )
      )
    {
        foreach my $t (@::clobjtypes)
        {

            #  look up all objects of this type in the DB ???

            # add them to the list of objects
            #push(@::clobjnames, $);

        }

    }

    # -  get object names from the -o option or the noderange
    if ($::opt_o)
    {
        print "object = $::opt_o\n";

        # make a list
        if ($::opt_o =~ /,/)
        {
            @::clobjnames = split(',', $::opt_o);
        }
        else
        {
            push(@::clobjnames, $::opt_o);
        }
    }
    elsif (@::noderange && (grep(/node/, @::clobjtypes)))
    {

        # if there's no object list and the type is node then the
        # 	noderange list is assumed to be the object names list
        @::clobjnames = @::noderange;
    }

    # - does input file exist etc. - read input file - stanza
    # 	- add support for XML files later!

    # check for stanza file
    if ($::opt_z)
    {
        print "filename = $::opt_z\n";

        if (!-e $::opt_z)
        {
            print "Error: the file \'$::opt_z\' does not exist!\n";
            print "Errors occurred when processing the command line args.\n";
            return 2;
        }
        else
        {

            # process the file
            # create hash of objects/attrs etc. %::FILEATTRS
            # &readstanzafile();
            #	- %::FILEATTRS{fileobjname}{attr}=val
            # set @::fileobjtypes, @::fileobjnames, %::FILEATTRS
        }
    }

    # check for object list file
    if ($::opt_f)
    {
        print "obj list filename = $::opt_f\n";

        # read the file and cp the name into @::objfilelist

    }

    # can't have -a with other obj sources
    if ($::opt_a
        && ($::opt_o || $::opt_f || $::opt_x || $::opt_z || @::noderange))
    {

        # error
        # usage
    }

    #  if -a then get a list of all DB objects
    if ($::opt_a)
    {
        print "all objects \n";

        # get a list of all objects defined in the DB
        # @::clobjnames = whatever

    }

    # must have object type(s) -
    if (!@::clobjtypes && !@::fileobjtypes)
    {
        print "Error - must specify object type on command line or in file!\n";
        return 2;
    }

    # must have object name(s) -
    if (!@::clobjnames && !@::fileobjnames)
    {
        print "Error - must specify object name on command line or in file!\n";
        return 2;
    }

    # combine object name from file with obj names from cmd line ??
    @::allobjnames = @::clobjnames;
    if (@::fileobjnames)
    {
        push @::allobjnames, @::fileobjnames;
    }

    return 0;
}

#----------------------------------------------------------------------------

=head3   defmk

        Support for the xCAT defmk command.

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Comments:
			Object names to create are derived from 
				-o, -t, w, -z, -x, or noderange!
			Attr=val pairs come from cmd line args or -z/-x files
=cut

#-----------------------------------------------------------------------------

sub defmk
{
    my $lookup_key;
    my $lookup_value;
    my $lookup_table;
    my $lookup_attr;
    my $lookup_type;
    my $lookup_data;

    # process the command line
    my $rc = &processArgs;
    if ($rc != 0)
    {

        # rc: 0 - ok, 1 - help, 2 - error
        &defmk_usage;
        return ($rc - 1);
    }

    #  !!! can only have one type on cmd line when defining objects!!!
    #  if # elements in @::clobjtypes is > 1 then error!

    #	set $objtype & fill in cmd line hash
    if (%::ATTRS)
    {

        # if attr=val on cmd line then could only have one type
        $::objtype = $::opt_t;

        #
        #  set cli attrs for each object definition
        #
        if (&setCLIattrs != 0)
        {
            print "Could not set command line values for object definitions!\n";
            return 1;
        }
    }

    #
    #   Pull all the pieces together for the final hash
    #
    if (&setFINALattrs != 0)
    {
        print "Could not determine attribute values for object definitions!\n";
        return 1;
    }

    #
    #  OK - create the tables in the xCAT database
    #
    foreach my $objname (@::allobjnames)
    {

        print
          "defmk: object name = $objname, type= $::FINALATTRS{$objname}{objtype}
\n";

        my $type = $::FINALATTRS{$objname}{objtype};

        # get the object type decription from Schema.pm
        my $datatype = $xCAT::Schema::defspec{$type};

        #  this is the list of valid attr names for this type object
        my @validattrs = keys %{$datatype->{'attrs'}};

        #print "validattrs= \'@validattrs\'\n";

        # if type is osimage, site, network, dynamic group then all attrs
        #  	go in the same table
        # 	- just need to check for valid attrs then write to table
        #	- the node type is the only one that needs the special
        #		processing below
        if (($type eq 'site') || ($type eq 'network') || ($type eq 'osimage'))
        {

            next;
        }

        if (($type eq 'group') && $::opt_d)
        {

            #  if it's a dynamic group it all goes in the group table

            next;
        }

        #  for other object types we need to figure out what table to
        #		store each attr
        foreach my $attr (keys %{$::FINALATTRS{$objname}})
        {
            if ($attr eq "objtype")
            {

                # objtype not stored in object definition
                next;
            }

            print "attr= $attr , val = $::FINALATTRS{$objname}{$attr}\n";

            # if valid attr for this type then add to def
            if (!grep(/^$attr$/, @validattrs))
            {
                print
                  "\'$attr\' is not a valid attribute for type \'$type\'.\n";
                print "Skipping to the next attribute.\n";
                next;
            }

            # check the defspec to see where this attr goes
            my @this_attr_array = $datatype->{'attrs'}->{$attr};

            foreach (@this_attr_array)
            {

                # ex. this_attr='node'
                my $this_attr = $_->[0];

                # the table might depend on the value of the attr
                #	- like if 'mgtmethod=mp'
                if (exists($this_attr->{only_if}))
                {
                    my ($check_attr, $check_value) =
                      split('\=', $this_attr->{only_if});

                    # if my attr value for the attr to check doesn't
                    #  	match this then try the next one
                    # ex. say I want to set hdwctrlpoint, the table
                    #	will depend on the mgtmethod attr - so I need
                    #   to find the 'only_if' that matches the value
                    #   specified for that attr
                    #print "attr=$check_attr, myval= $::FINALATTRS{$objname}{$check_attr}\n";

                    next
                      if $::FINALATTRS{$objname}{$check_attr} ne $check_value;
                }

                #  OK - get the info needed to add to the DB table

                # ex. 'nodelist.node', 'attr:node'
                ($lookup_key, $lookup_value) =
                  split('\=', $this_attr->{access_tabentry});

                # ex. 'nodelist', 'node'
                ($lookup_table, $lookup_attr) = split('\.', $lookup_key);

                # ex. 'attr', 'node'
                ($lookup_type, $lookup_data) = split('\:', $lookup_value);

            }

            print
              "lookup_table=$lookup_table, lookup_attr=$lookup_attr, lookup_type=$lookup_type\n";

            # write the attr to the DB table
            #	- future - may want to gather all attrs for each table
            #		- maybe reduce DB calls

        }
        print "\n";

    }

    return 0;
}

#----------------------------------------------------------------------------

=head3   setCLIattrs

		get list of object names to define
		create hash w/cmd line attrs
       		  %::CLIATTRS{objname}{attr}=val

        Arguments:

        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub setCLIattrs
{

    foreach my $objname (@::clobjnames)
    {

        #  set the objtype attr - if provided
        if ($::objtype)
        {
            $::CLIATTRS{$objname}{objtype} = $::objtype;
        }

        # set the attrs from the attr=val pairs
        foreach my $attr (keys %::ATTRS)
        {
            $::CLIATTRS{$objname}{$attr} = $::ATTRS{$attr};
        }
    }

    return 0;
}

#----------------------------------------------------------------------------

=head3   setFINALattrs

		create %::FINALATTRS{objname}{attr}=val hash
		conbines %::FILEATTRS, and %::CLIATTR

        Arguments:

        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------
sub setFINALattrs
{

    # set the final hash based on the info from the input file
    if (@::fileobjnames)
    {
        foreach my $objname (@::fileobjnames)
        {

            #  check if this object is one of the type specified
            if (grep(/$::FILEATTRS{$objname}{objtype}/, @::clobtypes))
            {

                # if so then add it to the final hash
                foreach my $attr (keys %{$::FILEATTRS{$objname}})
                {
                    $::FINALATTRS{$objname}{$attr} =
                      $::FILEATTRS{$objname}{$attr};
                }
            }

        }

    }

    # set the final hash based on the info from the cmd line hash
    foreach my $objname (@::clobjnames)
    {
        foreach my $attr (keys %{$::CLIATTRS{$objname}})
        {
            $::FINALATTRS{$objname}{$attr} = $::CLIATTRS{$objname}{$attr};
        }
    }

    return 0;
}

#----------------------------------------------------------------------------

=head3   defch

        Support for the xCAT defch command.

        Arguments:
                
        Returns:
                0 - OK
                1 - error
        Globals:
               
        Error:

        Example:

        Comments:
			Object names to change are derived from 
				-o, -t, w, -z, -x, or noderange!
			Attrs may be set, added to, replaced(-r), or be 
				partially rewmoved (-m)
=cut

#-----------------------------------------------------------------------------

sub defch
{

    # process the command line
    my $rc = &processArgs;
    if ($rc != 0)
    {

        # rc: 0 - ok, 1 - help, 2 - error
        &defch_usage;
        return ($rc - 1);
    }

    #
    #  set cli attrs for each object definition
    #
    if (%::ATTRS)    # if we had any attr=val on the cmd line
    {
        if (&setCLIattrs != 0)
        {
            print "Could not set command line values for object definitions!\n";
            return 1;
        }

    }

    #
    #   Pull all the pieces together for the final hash
    #		- from cmd line and/or file
    #
    if (&setFINALattrs != 0)
    {
        print "Could not determine attribute values for object definitions!\n";
        return 1;
    }

    #
    # get the current object definitions from DB!!
    #	could have multiple types, objects and attrs
    #	want to get hash of attr values for each object
    #
    foreach my $objname (@::allobjnames)
    {

        # get values for this object & attrs
        my @attrlist = keys %{$::FINALATTRS{$objname}};
        print "get these attrs for object \'$objname\': @attrlist\n";

        # add the info to the DBdefs hash
        foreach my $attr (@attrlist)
        {

            #		if ($val) {
            #			$DBdefs{$objname}{$attr}=val
            #		}
        }
    }

    # now go throught our objects
    foreach my $objname (@::allobjnames)
    {
        my @attrval;

        #  is this a valid object name
        #??  if (!grep(/$objname/, @::DBobjnames)  error - msg - next

        # go through the new attrs for this object
        foreach my $attr (keys %{$::FINALATTRS{$objname}})
        {
            if ($::opt_r)
            {

                #   - just set/replace the attribute
                push(@attrval, "$attr=$::FINALATTRS{$objname}{$attr}");
            }
            elsif ($::opt_m)
            {

                # if value is a list then remove the specified attrs from it
                #    TBD
            }
            else
            {

                # default behavior
                #  either set it - if blank
                #  or add it to attr list - if already set
                if ($DBdefs{$objname}{$attr})
                {

                    # add the new attr to the old attrs - comma seperated
                    my $val =
                        $DBdefs{$objname}{$attr} . ","
                      . $::FINALATTRS{$objname}{$attr};
                    push(@attrval, $val);
                }
                else
                {

                    # - just set it
                    push(@attrval, "$attr=$::FINALATTRS{$objname}{$attr}");
                }
            }
        }

        #  OK - change the tables in the xCAT database
        #   - write %NEWDEFS to the DB
        print "set: $objname, @attrval\n";
    }

    return 0;
}

#----------------------------------------------------------------------------

=head3   defls

        Support for the xCAT defls command.

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:
             
        Error:

        Example:

        Comments:
			Object names derived from -o, -t, w, -a or noderange!
            List of attrs to display is given by -i.
            Output goes to standard out or a stanza/xml file (-z or -x)
		
=cut

#-----------------------------------------------------------------------------

sub defls
{
    my $long = 0;
    my %DBhash;

    my @objectlist;

    # process the command line
    my $rc = &processArgs;
    if ($rc != 0)
    {

        # rc: 0 - ok, 1 - help, 2 - error
        &defls_usage;
        return ($rc - 1);
    }

    if ($::opt_l)
    {
        $long = 1;
    }

    # get a list of all the object names to display  -> $objnames

    #  object names provided
    # convert -o to list - @objectlist
    # if a, t, w, or noderange then error - cannot be combined
    # ?  assume long?? $long = 1;
    #  use noderange as $objnames
    # convert noderange to list - @objectlist
    # if a, t, w, or o then error
    # ?  assume long?? $long = 1;
    #  if all - get list of all objects
    # get list from DB - for each type check for names
    # if o, t, w, or noderange then error
    #  assume want names only  - unless opt_l
    #  if types  - get all objs of that type
    # get list of all object names of these types
    # if a, o, w, or noderange then error
    #  assume want names only  - unless opt_l
    #  use where values to gather names of objects
    #	- need to check all object names - could be time consuming!
    #   - make local hash - also use it below
    # if a, t, o, or noderange then error
    #  assume want names only - unless opt_l

    # get complete object defs - if need attrs - use @objectlist
    # if not already done then
    # if ($::opt_i || $long = 1; || $::opt_w)
    # foreach my $obj (@objnames)
    # get object definition from DB
    # put in hash - %DBhash{$objname}{$attr}

    #  for each object

    # if (!($::opt_i)) - just display long or short info
    #if ( $::opt_l) -  display details of obj def
    # else - just diplay names

    # else if (%DBhash{$objname}{$attr} =~ /$::opt_i/)
    # if the attr is one of the ones I want then add it to the
    #	output hash

    # display and/or write to output file

    return 0;
}

#----------------------------------------------------------------------------

=head3  defrm

        Support for the xCAT defrm command.

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:
           
        Error:

        Example:

        Comments:
			Object names to remove are derived from -o, -t, w, -a, -f,
				 or noderange!
=cut

#-----------------------------------------------------------------------------

sub defrm
{

    # process the command line
    my $rc = &processArgs;
    if ($rc != 0)
    {

        # rc: 0 - ok, 1 - help, 2 - error
        &defrm_usage;
        return ($rc - 1);
    }

    # if list of objects provided in a file then add them
    if (@::objfilelist)
    {
        push(@::allobjnames, @::objfilelist);
    }

    # foreach objname
    foreach my $objname (@::allobjnames)
    {

        #	remove object
        #if ($::FINALATTRS{$objname}{objtype} eq "group")
        #   if (defined($::opt_d))
        #       print "make dynamic groups\n";
        #       next;

        # if type= site -> remove site table
        # if type=network -> remove entry in network table
        # if node -> remove node entries in all node tables
        # if group
        #	- if dynamic -> remove entry from group table
        #	- if static -> remove group name entries from relevant tables
    }

    #  what happens to group if all nodes removed???
    #	? - if remove nodes then check for empty groups to clean up??
    #  if (@::objtypes =~ /node/)
    #		- get all group member lists
    #		- if member list is empty
    #			- remove group - ie. remove group name entry in all DB tables??

    return 0;
}

#----------------------------------------------------------------------------

=head3  defmk_usage

        Arguments:
        Returns:
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

# subroutines to display the usage
sub defmk_usage
{
    my %rsp;
    $rsp->{data}->[0] =
      "\nUsage: defmk - create xCAT data object definitions.\n";
    $rsp->{data}->[1] =
      "  defmk [-h | --help ] [-V | --verbose] [-t <object types>]";
    $rsp->{data}->[2] =
      "      [-o <object names>] [-z <stanza file>] [-x <xml file>]";
    $rsp->{data}->[3] =
      "      [-w attr=val,[attr=val...]][-d | --dynamic] <noderange>";
    $rsp->{data}->[4] = "      attr=val [attr=val...]\n";
    $::callback->($rsp);
}

#----------------------------------------------------------------------------

=head3  defch_usage

        Arguments:
        Returns:
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub defch_usage
{
    my %rsp;
    $rsp->{data}->[0] =
      "\nUsage: defch - change xCAT data object definitions.\n";
    $rsp->{data}->[1] =
      "  defch [-h | --help ] [-V | --verbose] [-t <object types>]";
    $rsp->{data}->[2] =
      "    [-o <object names>] [-z <stanza file>] [-x <xml file>]";
    $rsp->{data}->[3] =
      "    [-m | --minus] [-r | --replace] [-w attr=val,[attr=val...] ]";
    $rsp->{data}->[4] = "    <noderange> attr=val [attr=val...]\n";
    $::callback->($rsp);
}

#----------------------------------------------------------------------------

=head3  defls_usage

        Arguments:
        Returns:
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub defls_usage
{
    my %rsp;
    $rsp->{data}->[0] = "\nUsage: defls - list xCAT data object definitions.\n";
    $rsp->{data}->[1] =
      "  defls [-h | --help ] [-V | --verbose] [ -l | --long] [-a | --all]";
    $rsp->{data}->[2] =
      "    [-t <object types>] [-o <object names>] [-z <stanza file>]";
    $rsp->{data}->[3] =
      "    [-x <xml file>] [-i attr-list] [-w attr=val,[attr=val...] ]";
    $rsp->{data}->[4] = "    <noderange>\n";
    $::callback->($rsp);
}

#----------------------------------------------------------------------------

=head3  defrm_usage

        Arguments:
        Returns:
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub defrm_usage
{
    my %rsp;
    $rsp->{data}->[0] =
      "\nUsage: defrm - remove xCAT data object definitions.\n";
    $rsp->{data}->[1] = "  defrm [-h | --help ] [-V | --verbose] [-a | --all]";
    $rsp->{data}->[2] =
      "    [-t <object types>] [-o <object names>] [-f <object list file>]";
    $rsp->{data}->[3] = "    [-w attr=val,[attr=val...] <noderange>\n";
    $::callback->($rsp);
}

1;
