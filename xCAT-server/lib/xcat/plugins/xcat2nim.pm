#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#####################################################
#
#  xCAT plugin package to handle the xcat2nim command.
#
#####################################################

package xCAT_plugin::xcat2nim;

use xCAT::NodeRange;
use xCAT::Schema;
use xCAT::Utils;
use xCAT::DBobjUtils;
use Data::Dumper;
use Getopt::Long;
use xCAT::MsgUtils;

# options can be bundled up like -vV
Getopt::Long::Configure("bundling");
$Getopt::Long::ignorecase = 0;

#
# Globals
#

@::noderange;       # list of nodes derived from command line

#------------------------------------------------------------------------------

=head1    xcat2nim

This program module file supports the xcat2nim command.


=cut

#------------------------------------------------------------------------------

=head2    xCAT xcat2nim command

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
            xcat2nim => "xcat2nim"
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

    # globals used by all subroutines.
    $::command  = $::request->{command}->[0];
    $::args     = $::request->{arg};
    $::filedata = $::request->{stdin}->[0];

   ($ret, $msg) = &x2n;

    if ($msg)
    {
        my $rsp;
        $rsp->{data}->[0] = $msg;
        $::callback->($rsp);
    }
	if ($ret > 0) {
		$rsp->{errorcode}->[0] = $ret;
	}
}

#----------------------------------------------------------------------------

=head3   processArgs

        Process the command line.

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
    my $gotattrs = 0;

    @ARGV = @{$::args};

    # parse the options 
	Getopt::Long::Configure("no_pass_through");
    if (
        !GetOptions(
                    'all|a'     => \$::opt_a,
                    'help|h|?'    => \$::opt_h,
					'list|l'    => \$::opt_l,
					'update|u'  => \$::opt_u,
					'remove|r'  => \$::opt_r,
                    'o=s'       => \$::opt_o,
                    't=s'       => \$::opt_t,
                    'verbose|V' => \$::opt_V,
                    'version|v' => \$::opt_v,
        )
      )
    {

        # return 2;
    }

	# can get object names in many ways - easier to keep track
    $::objectsfrom_args = 0;
    $::objectsfrom_opto = 0;
    $::objectsfrom_optt = 0;
    $::objectsfrom_opta = 0;

    #
    # process @ARGV
    #

    #  - put attr=val operands in ATTRS hash
    while (my $a = shift(@ARGV))
    {

        if (!($a =~ /=/))
        {

            # the first arg could be a noderange or a list of args
            if (($::opt_t) && ($::opt_t ne 'node'))
            {

                # if we know the type isn't "node" then set the object list
                @::clobjnames = split(',', $a);
                $::objectsfrom_args = 1;
            }
            elsif (!$::opt_t || ($::opt_t eq 'node'))
            {

                # if the type was not provided or it is "node"
                #	then set noderange
                @::noderange = &noderange($a, 0);
				@::clobjnames = @::noderange;
				$::objectsfrom_args = 1;
            }

        }
        else
        {

            # if it has an "=" sign its an attr=val - we hope
            #   - this will handle "attr= "
            my ($attr, $value) = $a =~ /^\s*(\S+?)\s*=\s*(\S*.*)$/;
            if (!defined($attr) || !defined($value))
            {
                my $rsp;
                $rsp->{data}->[0] = "Incorrect \'attr=val\' pair - $a\n";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                return 3;
            }

            $gotattrs = 1;

            # put attr=val in hash
            $::ATTRS{$attr} = $value;

        }
    }

    # Option -h for Help
    if (defined($::opt_h) )
    {
        return 2;
    }

    # Option -v for version - do we need this???
    if (defined($::opt_v))
    {
        my $rsp;
        $rsp->{data}->[0] = "$::command - version 1.0";
        xCAT::MsgUtils->message("I", $rsp, $::callback);
        return 1;    # - just exit
    }

    # Option -V for verbose output
    if (defined($::opt_V))
    {
        $::verbose = 1;
        $::VERBOSE = 1;
    }

    #
    #  determine the object types
    #

    # could have comma seperated list of types
    if ($::opt_t)
    {
        my @tmptypes;

        if ($::opt_t =~ /,/)
        {

            # can't have mult types when using attr=val
            if ($gotattrs)
            {
                my $rsp;
                $rsp->{data}->[0] =
                  "Cannot combine multiple types with \'att=val\' pairs on the command line.\n";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                return 3;
            }
            else
            {
                @tmptypes = split(',', $::opt_t);
            }
        }
        else
        {
            push(@tmptypes, $::opt_t);
        }

        # check for valid types
        my @xdeftypes;
        foreach my $k (keys %{xCAT::Schema::defspec})
        {
            push(@xdeftypes, $k);
        }

        foreach my $t (@tmptypes)
        {
            if (!grep(/$t/, @xdeftypes))
            {
                my $rsp;
                $rsp->{data}->[0] =
                  "Type \'$t\' is not a valid xCAT object type.\n";
                $rsp->{data}->[1] = "Skipping to the next type.\n";
                xCAT::MsgUtils->message("I", $rsp, $::callback);
            }
            else
            {
                chomp $t;
                push(@::clobjtypes, $t);
            }
        }
    }

    # must have object type(s) - default if not provided
    if (!@::clobjtypes && !$::opt_a)
    {

        # make the default type = 'node' if not specified
        push(@::clobjtypes, 'node');
        my $rsp;
        $rsp->{data}->[0] = "Assuming an object type of \'node\'.\n";
        xCAT::MsgUtils->message("I", $rsp, $::callback);
    }

    #
    #  determine the object names
    #

    # -  get object names from the -o option or the noderange
	#		- this assumes the ronderange was not provided as an arg!!!
    if ($::opt_o)
    {

        $::objectsfrom_opto = 1;

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

    # if there is no opt_o & no noderange then try to find all the objects
	#	of the given types.
    if ($::opt_t
        && !(   $::opt_o
             || $::opt_a
             || @::noderange
             || @::clobjnames))
    {
        my @tmplist;

        $::objectsfrom_optt = 1;

        # could have multiple type
        foreach my $t (@::clobjtypes)
        {

            #  look up all objects of this type in the DB ???
            @tmplist = xCAT::DBobjUtils->getObjectsOfType($t);

            unless (@tmplist)
            {
                my $rsp;
                $rsp->{data}->[0] =
                    "Could not get objects of type \'$t\'.\n";
                $rsp->{data}->[1] = "Skipping to the next type.\n";
                xCAT::MsgUtils->message("I", $rsp, $::callback);
                next;
        	}

            # add objname and type to hash and global list
            foreach my $o (@tmplist)
            {
                push(@::clobjnames, $o);
                $ObjTypeHash{$o} = $t;
            }
        }   
    }


    # can't have -a with other obj sources
    if ($::opt_a
        && ($::opt_o || @::noderange))
    {

        my $rsp;
        $rsp->{data}->[0] =
          "Cannot use \'-a\' with \'-o\' or a noderange.\n";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 3;
    }

    #  if -a then get a list of all DB objects
    if ($::opt_a)
    {
        my @tmplist;

		$::objectsfrom_opta = 1;

        # for every type of data object get the list of defined objects
        foreach my $t (keys %{xCAT::Schema::defspec})
        {

			# just for node and group for now!!!!!!!
			if ( ($t eq 'node') || ($t eq 'group') ) {

            	my @tmplist;
            	@tmplist = xCAT::DBobjUtils->getObjectsOfType($t);

            	# add objname and type to hash and global list
            	if (scalar(@tmplist) > 0)
            	{
                	foreach my $o (@tmplist)
                	{
                    	push(@::clobjnames, $o);
                    	$AllObjTypeHash{$o} = $t;
                	}
            	}
        	}
    	}
	}

    # must have object name(s) -
    if (!@::clobjnames)
    {
        my $rsp;
        $rsp->{data}->[0] =
          "Could not determine what object definitions to remove.\n";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 3;
    }

	# create hash with object names and types
	foreach my $o (@::clobjnames)
    {
		if ($::objectsfrom_opta) {
			# if the object names came from the "-a" option then
			%::objtype = %AllObjTypeHash;

		} elsif ($::objectsfrom_optt) {
			# if the names came from the opt_t option
			%::objtype = %ObjTypeHash;

		} elsif ($::objectsfrom_args || $::objectsfrom_opto) {
			# from the opt_o or as an argument
			#  - there can only be one type
			$::objtype{$o}=@::clobjtypes[0];
		} 
	}

    return 0;
}

#----------------------------------------------------------------------------

=head3   x2n

        Support for the xcat2nim command.

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

sub x2n
{

    my $rc    = 0;
    my $error = 0;

    # process the command line
    $rc = &processArgs;
    if ($rc != 0)
    {

        # rc: 0 - ok, 1 - return, 2 - help, 3 - error
        if ($rc != 1)
        {
            &xcat2nim_usage;
        }
        return ($rc - 1);
    }

	# get the local short host name
    ($::local_host = `hostname`) =~ s/\..*$//;
	chomp $::local_host;

	# get all the attrs for these definitions
	%::objhash = xCAT::DBobjUtils->getobjdefs(\%::objtype);
	if (!defined(%::objhash))
    {
		my $rsp;
        $rsp->{data}->[0] = "Could not get xCAT object definitions.\n";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 1;
    }

	# create NIM defs for each xCAT def
	foreach my $objname (keys %::objhash)
	{

		# list the NIM object definition - if there is one
		if ($::opt_l || $::opt_r) {
			if (&rm_or_list_nim_object($objname, $::objtype{$objname})) {
            	# the routine failed
				$error++;
				next;
			}
        } else {

		# create a NIM machine definition
		if ($::objtype{$objname} eq 'node') {
		    # need to set group type to either static or dynamic
            $::objhash{$objname}{'grouptype'}='static';
			if (mkclientdef($objname)) {
                # could not create client definition
				$error++;
            }
			next;
		}

		# create a NIM group definition
		if ($::objtype{$objname} eq 'group') {
			if (mkgrpdef($objname)) {
				# could not create group definition
				$error++;
			}
			next;
		}
		}
	}	

    if ($error)
    {
        my $rsp;
        $rsp->{data}->[0] =
          "One or more errors occured.\n";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 1;
    }
    else
    {
        if ($::verbose)
        {

            #  give results
			my $rsp;
			if ($::opt_r) {
				$rsp->{data}->[0] = "The following definitions were removed:";
			} elsif ($::opt_u) {
				$rsp->{data}->[0] = "The following definitions were updated:";
			} elsif (!$::opt_l) {
				$rsp->{data}->[0] = "The following definitions were created:";
			}

            xCAT::MsgUtils->message("I", $rsp, $::callback);

            my $n = 1;
			foreach my $o (sort(keys %::objhash))
            {
                $rsp->{data}->[$n] = "$o\n";
                $n++;
            }
            xCAT::MsgUtils->message("I", $rsp, $::callback);
        }
        else
        {
			if (!$::opt_l) {
            	my $rsp;
            	$rsp->{data}->[0] =
              	"NIM operations have completed successfully.\n";
            	xCAT::MsgUtils->message("I", $rsp, $::callback);
			}
        }
        return 0;
    }
}

#----------------------------------------------------------------------------

=head3   mkclientdef

		Create a NIM client definition.        
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

sub mkclientdef
{
	my ($node) = @_;
	my $cabletype = undef;
	my $ifattr = undef;

	# get the name of the nim master
    #  ???? assume node short hostname is unique in xCAT cluster????
    my $nim_master = &getNIMmaster($object);
	chomp $nim_master;

    if (!defined($nim_master)) {
        my $rsp;
        $rsp->{data}->[0] = "Could not find the NIM master for node \'$node\'.\n";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 1;
    }

	# check to see if the client is already defined 
	#	- sets $::client_exists
    if (&check_nim_client($node, $nim_master)) {
        # the routine failed
        return 1;
    }

	# don't update an existing def unless they say so!
	if ($::client_exists && !$::opt_u) {

        my $rsp;
        $rsp->{data}->[0] = "The NIM client machine \'$node\' already exists.  Use the \'-u\' option to update an existing definition.\n";
        xCAT::MsgUtils->message("I", $rsp, $::callback);
        return 1;

    } else {
        # either create or update the def

		# process the args and add defaults etc.
    	foreach my $attr (keys %::ATTRS) {
	
			if ( $attr =~ /^if/) {

				$ifattr = "-a $attr=\'$::ATTRS{$attr}\'";

			} elsif ( $attr =~ /^cable_type/) {
				$cabletype="-a cable_type1=\'$::ATTRS{$attr}\'";
 
			} else {
				# add to 
				$finalattrs{$attr}=$::ATTRS{$attr};
			}
		}

		# req a value for cable_type
		if (!$cabletype) {
			$cabletype="-a cable_type1=N/A ";
		}

		# need short host name for NIM client defs
		($shorthost = $node) =~ s/\..*$//;

		# req a value for "if1" interface def
		if (!$ifattr) {
			# then try to create the attr - required
			if ($::objhash{$node}{'netname'}) {
				$net_name=$::objhash{$node}{'netname'};
			} else {
				$net_name="find_net";
			}

			# only support Ethernet for management interfaces
			$adaptertype = "ent";

			if (!$::objhash{$node}{'mac'})
			{
				my $rsp;
            	$rsp->{data}->[0] = "Missing the MAC for node \'$node\'.\n";
            	xCAT::MsgUtils->message("E", $rsp, $::callback);
            	return 1;
			}
			
			$ifattr="-a if1=\'$net_name $shorthost $::objhash{$node}{'mac'} $adaptertype\'";
		}

		# only support standalone for now - will get this from node def in future
		$nim_type = "-t standalone";

		$nim_args = "$ifattr ";
		$nim_args .= "$cabletype";

		# add the rest of the attr=val to the command line
		foreach my $a (keys %finalattrs) {
			$nim_args .= " -a $a=\'$finalattrs{$a}\'";
		}

		# put together the correct NIM command
		my $cmd;


		if ($::client_exists) {
			$cmd = "nim -F -o change $nim_args $shorthost";
		} else {
			$cmd = "nim -o define $nim_type $nim_args $shorthost";
		}

		# may need to use dsh if it is a remote server
		my $nimcmd;
    	if ($nim_master ne $::local_host) {
			$nimcmd = qq~xdsh $nim_master "$cmd 2>&1"~;
		} else {
			$nimcmd = qq~$cmd 2>&1~;
		}

		# run the cmd
    	my $output = xCAT::Utils->runcmd("$nimcmd", -1);
    	if ($::RUNCMD_RC  != 0)
    	{
        	my $rsp;
        	$rsp->{data}->[0] = "Could not create a NIM definition for \'$node\'.\n";
			if ($::verbose)
        	{
				$rsp->{data}->[1] = "$output";
			}
        	xCAT::MsgUtils->message("E", $rsp, $::callback);
        	return 1;
		}
    }

	return 0;
}

#----------------------------------------------------------------------------

=head3   mkgrpdef

        Create a NIM group definition.

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

sub mkgrpdef
{
	my ($group) = @_;
    my $cmd = undef;
	my $servnode = undef; 
	my $GrpSN = undef;

	# get members and determine all the different masters
	#   For example, the xCAT group "all" will have nodes that are managed
	#  	by multiple NIM masters - so we will create a local group "all"
	#	on each of those masters
    %ServerList = &getMasterGroupLists($group);

	foreach my $servname (keys %ServerList)
	{
		my @members = @{$ServerList{$servname}};

		# check to see if the group is already defined - sets $::grp_exists
		if (&check_nim_group($group, $servname)) {
			# the routine failed
			return 1;
		}

		# don't update an existing def unless we're told 
		if ($::grp_exists && !$::opt_u) {
			my $rsp;
       		$rsp->{data}->[0] = "The NIM group \'$group\' already exists.  Use the \'-u\' option to update an existing definition.\n";
       		xCAT::MsgUtils->message("I", $rsp, $::callback);
			return 0;

		} else {
			# either create or update the group def on this master

			# any list with more than 1024 members is an error
        	#   - NIM can't handle that
        	if ($#members > 1024) {
            	my $rsp;
            	$rsp->{data}->[0] =
            		"Cannot create a NIM group definition with more than 1024 members - on \'$servname\'.";
            	xCAT::MsgUtils->message("I", $rsp, $::callback);
            	next;
        	}

			#
			#  The list may become quite long and not fit on one cmds line
			#  so we do it one at a time for now - need to revisit this
			#      (like do blocks at a time)
			#
			my $justadd=0;  # after the first define we just need to add
			foreach my $memb (@members) {

				($shorthost = $memb) =~ s/\..*$//;

				# do we change or create
				my $cmd;
				if ($::grp_exists || $justadd) {
					$cmd = "nim -o change -a add_member=$shorthost $group 2>&1";
				} else {
					$cmd = "nim -o define -t mac_group -a add_member=$shorthost $group 2>&1";
					$justadd++;
				}

				# do we need dsh
				my $nimcmd;
				if ($servname ne $::local_host) {
					$nimcmd = qq~xdsh $servname "$cmd"~;
				} else {
					$nimcmd = $cmd;
				}

				my $output = xCAT::Utils->runcmd("$cmd", -1);
        		if ($::RUNCMD_RC  != 0)
        		{
            		my $rsp;
            		$rsp->{data}->[0] = "Could not create a NIM definition for \'$group\'.\n";
					if ($::verbose)
            		{
						$rsp->{data}->[1] = "$output";
					}
            		xCAT::MsgUtils->message("E", $rsp, $::callback);
            		return 1;
				}
			}
        }
	}

	return 0;
}

#----------------------------------------------------------------------------

=head3   rm_or_list_nim_object

         List a NIM object definition.

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

sub rm_or_list_nim_object
{
	my ($object, $type) = @_;
	my $nim_master = undef;

	if ($type eq 'node') {
		# get name of nim master
		#  ???? assume node short hostname is unique in xCAT cluster????
		$nim_master = &getNIMmaster($object);
		chomp $nim_master;

		if (!defined($nim_master)) {
			my $rsp;
            $rsp->{data}->[0] = "Could not find the NIM master for node \'$object\'.\n";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            return 1;
		}
		
		if ($::opt_l) {

			# if the name of the master is not the local host then use dsh
			if ($nim_master ne $::local_host) {
				$cmd = qq~xdsh $nim_master "lsnim -l $object 2>/dev/null"~;
			} else {
				$cmd = qq~lsnim -l $object 2>/dev/null~;
			}
		
			my $outref = xCAT::Utils->runcmd("$cmd", -1);
        	if ($::RUNCMD_RC  != 0)
        	{
            	my $rsp;
            	$rsp->{data}->[0] = "Could not get the NIM definition for $object.\n";
				if ($::verbose)
                {
					$rsp->{data}->[1] = "$outref";
				}
            	xCAT::MsgUtils->message("E", $rsp, $::callback);
            	return 1;
        	} else {

				#  display to NIM output
				my $rsp;
		#		$rsp->{data}->[0] = "NIM master: $nim_master";
		#		$rsp->{data}->[1] = "Client name: $object";
        		$rsp->{data}->[0] = "$outref";
				xCAT::MsgUtils->message("I", $rsp, $::callback);
				return 0;
			}

		} elsif ($::opt_r) {
			# remove the object
			# if the name of the master is not the local host then use dsh

            if ($nim_master ne $::local_host) {
                $cmd = qq~xdsh $nim_master "nim -o remove $object 2>/dev/null"~;
            } else {
                $cmd = qq~nim -o remove $object 2>/dev/null~;
            }

			$outref = xCAT::Utils->runcmd("$cmd", -1);
            if ($::RUNCMD_RC  != 0)
            {
                my $rsp;
                $rsp->{data}->[0] = "Could not remove the NIM definition for \'$object\'.\n";
				if ($::verbose)
                {
					$rsp->{data}->[1] = "$outref";
				}
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                return 1;
            }
 		}
	}

	if ($type eq 'group') {

		# get members and determine all the different masters 
		%servgroups = &getMasterGroupLists($object);

		# get the group definition from each master and 
		# 	display it
		foreach my $servname (keys %servgroups)
    	{
			# make sure we have the short host name of the NIM master
			if ($servname) {
        		($master = $servname) =~ s/\..*$//;
    		}
			chomp $master;

			if ($::opt_l) {
				# if the name of the master is not the local host then use dsh
        		if ($master ne $::local_host) {
            		$cmd = qq~xdsh $master "lsnim -l $object 2>/dev/null"~;
        		} else {
            		$cmd = qq~lsnim -l $object 2>/dev/null~;
        		}
			
				$outref = xCAT::Utils->runcmd("$cmd", -1);
        		if ($::RUNCMD_RC  != 0)
        		{
            		my $rsp;
            		$rsp->{data}->[0] = "Could not list the NIM definition for \'$object\'.\n";
					if ($::verbose)
                    {
						$rsp->{data}->[1] = "$outref";
					}
            		xCAT::MsgUtils->message("E", $rsp, $::callback);
            		return 1;
        		} else {

            		#  display NIM output
            		my $rsp;
           	# 		$rsp->{data}->[0] = "NIM master: $master";
			#		$rsp->{data}->[1] = "Group name: $object";
					$rsp->{data}->[0] = "$outref";
            		xCAT::MsgUtils->message("I", $rsp, $::callback);
            		return 0;
        		}
			} elsif ($::opt_r) {
				# if the name of the master is not the local host then use dsh
                if ($master ne $::local_host) {
                    $cmd = qq~xdsh $instserv "nim -o remove $object 2>/dev/null"~;
                } else {
                    $cmd = qq~nim -o remove $object 2>/dev/null~;
                }

				$outref = xCAT::Utils->runcmd("$cmd", -1);
                if ($::RUNCMD_RC  != 0)
                {
                    my $rsp;
                    $rsp->{data}->[0] = "Could not remove the NIM definition for \'$object\'.\n";
					if ($::verbose)
                    {
						$rsp->{data}->[1] = "$outref";
					}
                    xCAT::MsgUtils->message("E", $rsp, $::callback);
                    return 1;
                }
			}
		}
    }   
	return 0;
}

#----------------------------------------------------------------------------

=head3   getNIMmaster

        Get the name of the NIM master for a node.

        Arguments:
        Returns:
                name  
                undef - error
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub getNIMmaster
{
	my ($node) = @_;
	my $NimMaster;
	my $master = undef;

	# get the server name
    if ($::objhash{$node}{nimmaster}) {
        $NimMaster = $::objhash{$node}{nimmaster};

    } elsif ($::objhash{$node}{servicenode}) {
        # the servicenode attr is set for this node
        $NimMaster = $::objhash{$node}{servicenode};

    } elsif ($::objhash{$node}{xcatmaster}) {
        $NimMaster = $::objhash{$node}{xcatmaster};

    } else {
        $NimMaster = $::local_host;
    }

    # assume short hostnames for now???
	if ($NimMaster) {
    	($master = $NimMaster) =~ s/\..*$//;
	}
	return $master;
}

#----------------------------------------------------------------------------

=head3   getMasterGroupLists

        Get a hash of all the masters that have a certain group defined 
			and a list of members for each masters definition.

        Arguments:
        Returns:
                server group list hash
                undef -  error
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub getMasterGroupLists
{
	my ($group) = @_;

	my $NimMaster;
	my $thismaster;

	# get the members list
    my $memberlist = xCAT::DBobjUtils->getGroupMembers($group, \%::objhash);
    my @members = split(',', $memberlist);

	#  get the node(member) definitions
    if (@members) {
        foreach my $n (@members) {
            $membhash{$n} = 'node';
        }
        %memberhash = xCAT::DBobjUtils->getobjdefs(\%membhash);
    } else {
		my $rsp;
        $rsp->{data}->[0] = "Could not get members of the xCAT group \'$group\'.\n";
		xCAT::MsgUtils->message("E", $rsp, $::callback);
		return undef;
    }

	if ( defined(%memberhash)) {
		# sort the list by server node - one list per server
    	foreach my $m (@members) {

        	if ($memberhash{$m}{nimmaster}) {
            	$NimMaster = $memberhash{$m}{nimmaster};

        	} elsif ($memberhash{$m}{servicenode}) {
            	# the servicenode attr is set for this node
            	$NimMaster = $memberhash{$m}{servicenode};

        	} elsif ($memberhash{$m}{xcatmaster}) {
            	$NimMaster = $memberhash{$m}{xcatmaster};

        	} else {
            	$NimMaster = `hostname`;
			}

        	# assume short hostnames for now???
        	($thismaster = $NimMaster) =~ s/\..*$//;

        	push(@{$ServerList{$thismaster}}, $m);
		}

	} else {
		# could not get node def
		my $rsp;
        $rsp->{data}->[0] = "Could not get xCAT node definition for all members of the xCAT group \'$group\'.\n";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
		return undef;
	}

	return %ServerList;
}

#----------------------------------------------------------------------------

=head3   check_nim_group

		See if an xCAT group has already been defined as a NIM machine group.

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

sub check_nim_group
{
	my ($group, $servnode) = @_;
	my ($cmd, @output);
	
	chomp $::local_host;
    chomp $servnode;

	if ( $::NIMGroupList{$servnode}) {
		@GroupList = @{$::NIMGroupList{$servnode}};
	} else {
		if ($servnode ne $::local_host) {
            $cmd = qq~xdsh $servnode "lsnim -c groups | cut -f1 -d' ' 2>/dev/null"~;
        } else {
            $cmd = qq~lsnim -c groups | cut -f1 -d' ' 2>/dev/null~;
        }

		@GroupList = xCAT::Utils->runcmd("$cmd", -1);
    	if ($::RUNCMD_RC  != 0)
    	{
        	my $rsp;
        	$rsp->{data}->[0] = "Could not get a list of NIM group definitions.\n";
        	xCAT::MsgUtils->message("E", $rsp, $::callback);
        	return 1;
    	}
		#  save member list for each server
		@{$::NIMGroupList{$servnode}} = @GroupList;
	}
	

	$::grp_exists = grep(/^$group$/,@GroupList) ? 1 : 0;

	return 0;
}

#----------------------------------------------------------------------------

=head3   check_nim_client

        See if an xCAT node has already been defined as a NIM client.

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

sub check_nim_client
{
	my ($node, $servnode) = @_;
    my ($cmd, @ClientList);

    if ( $::NIMclientList{$servnode}) {
        @ClientList = @{$::NIMclientList{$servnode}};
    } else {
		if ($servnode ne $::local_host) {
			$cmd = qq~xdsh $servnode "lsnim -c machines | cut -f1 -d' ' 2>/dev/null"~;
		} else {
			$cmd = qq~lsnim -c machines | cut -f1 -d' ' 2>/dev/null~;
		}

        @ClientList = xCAT::Utils->runcmd("$cmd", -1);
        if ($::RUNCMD_RC  != 0)
        {
            my $rsp;
            $rsp->{data}->[0] = "Could not get a list of NIM client definitions from \'$servnode\'.\n";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            return 1;
        }
        #  save member list for each server
        @{$::NIMclientList{$servnode}} = @ClientList;
    }

	$::client_exists = grep(/^$node$/,@ClientList) ? 1 : 0;

    return 0;
}

#----------------------------------------------------------------------------

=head3  xcat2nim_usage

        Arguments:
        Returns:
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub xcat2nim_usage
{
    my $rsp;
    $rsp->{data}->[0] =
      "\nUsage: xcat2nim - Use this command to create and manage AIX NIM definitions based on xCAT object definitions.\n";
    $rsp->{data}->[1] = "  xcat2nim [-h | --help ]\n";
    $rsp->{data}->[2] =
      "  xcat2nim [-V | --verbose] [-a | --all] [-l | --list] [-u | --update] ";

	$rsp->{data}->[3] ="    [-r | --remove] [-t object-types] [-o object-names]";
    $rsp->{data}->[4] =
      "    [noderange] [attr=val [attr=val...]]\n";
    xCAT::MsgUtils->message("I", $rsp, $::callback);
    return 0;
}

1;

