#!/usr/bin/env perl -w
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#####################################################
#
#  xCAT plugin package to handle the xcat2nim command.
#
#####################################################

package xCAT_plugin::xcat2nim;

use Sys::Hostname;
use xCAT::NodeRange;
use xCAT::Schema;
use xCAT::Utils;
use xCAT::DBobjUtils;
use Data::Dumper;
use Getopt::Long;
use xCAT::MsgUtils;
use strict;
use Socket;

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

#-------------------------------------------------------

=head3  preprocess_request

  Check and setup for hierarchy

=cut

#-------------------------------------------------------
sub preprocess_request
{
	my $req = shift;
    my $cb  = shift;
    my %sn;
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }
        #exit if preprocessed
    my $nodes    = $req->{node}; # this may not be the list of nodes we need!
	my $command  = $req->{command}->[0];
	$::args     = $req->{arg};
    my $service  = "xcat";
	my @requests;

	if ($command =~ /xcat2nim/) {
		
		# handle -h etc.
		#  list of nodes could be derived multiple ways!!
		my ($ret, $mynodes) = &prexcat2nim($cb);
		if ( $ret ) { # either error or -h was processed etc.
			my $rsp;
			if ($ret eq "1") {
        		$rsp->{errorcode}->[0] = $ret;
            	push @{$rsp->{data}}, "Return=$ret.";
        		xCAT::MsgUtils->message("E", $rsp, $cb, $ret);
			}
            return undef;
        } else {
			if ($mynodes) {
				# set up the requests to go to the service nodes
            	#   all get the same request
				# get the hash of service nodes - for the nodes that were provided
				my $sn;
				$sn = xCAT::Utils->get_ServiceNode($mynodes, $service, "MN");
            	foreach my $snkey (keys %$sn) {
                	my $reqcopy = {%$req};
                	$reqcopy->{node} = $sn->{$snkey};
                	$reqcopy->{'_xcatdest'} = $snkey;
                  $reqcopy->{_xcatpreprocessed}->[0] = 1;

                	push @requests, $reqcopy;
            	}
            	return \@requests;
			}
        }
    }
			
    return undef;
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
    my $callback = shift;

    my $ret;
    my $msg;
	my $rsp;

    # globals used by all subroutines.
    $::command  = $::request->{command}->[0];
    $::args     = $::request->{arg};
    $::filedata = $::request->{stdin}->[0];

   ($ret, $msg) = &x2n($callback);
	if ($ret > 0) {
		my $rsp;
		$rsp->{errorcode}->[0] = $ret;
		push @{$rsp->{data}}, "Return=$ret.";
		xCAT::MsgUtils->message("E", $rsp, $callback, $ret);
	}
	return 0;
}

#----------------------------------------------------------------------------

=head3   prexcat2nim

        Preprocessing for the xcat2nim command.

        Arguments:
        Returns:
                0 - OK - needs further processing
                1 - error - done processing this cmd
                2 - help or version - done processing this cmd
        Comments:
=cut

#-----------------------------------------------------------------------------
sub prexcat2nim
{
	my $callback = shift;

	$::callback = $callback;

	my @nodelist;  # pass back list of nodes

	$::msgstr = "";

    if (defined(@{$::args})) {
        @ARGV = @{$::args};
    } else {
		&xcat2nim_usage;
        return 1;
    }

	Getopt::Long::Configure("no_pass_through");
    if (
        !GetOptions(
                    'all|a'     => \$::opt_a,
                    'f|force'   => \$::FORCE,
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
		&xcat2nim_usage;
        return 1;
    }

	# Option -h for Help
    if ($::opt_h )
    {
		&xcat2nim_usage;
        return 2;
    }

    # Option -v for version - do we need this???
    if ($::opt_v)
    {
        my $rsp;
        my $version=xCAT::Utils->Version();
        $rsp->{data}->[0] = "xcat2nim - $version";
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return 2;    # - just exit
    }

########  TODO  ##################
# this needs to be cleaned up!!!!!
#   too much duplicate code being called ...
#################################

	# process the command line
    my $rc = &processArgs;

	my %objhash = xCAT::DBobjUtils->getobjdefs(\%::objtype);

	# need to figure out what nodes are involved so
	#	we can create the node/group defs on the 
	#	correct service nodes
	foreach my $o (@::clobjnames) {
		if ($::objtype{$o} eq 'node') {
			push (@nodelist, $o);
		}
		if ($::objtype{$o} eq 'group') {
			my $memberlist = xCAT::DBobjUtils->getGroupMembers($o, \%objhash);
			my @members = split(',', $memberlist);
			if (@members) {
        		foreach my $n (@members) {
					push (@nodelist, $n);
				}
			}
		}
	}
 
	# make sure the nodes are resolvable
    #  - if not then exit
    foreach my $n (@nodelist) {
        my $packed_ip = gethostbyname($n);
        if (!$packed_ip) {
            my $rsp;
            $rsp->{data}->[0] = "Could not resolve node $n.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;

        }
    }

	return (0, \@nodelist);
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

	if (defined(@{$::args})) {
    	@ARGV = @{$::args};
	} else {
		return 3;
	}

	my %ObjTypeHash;

    # parse the options 
	Getopt::Long::Configure("no_pass_through");
    if (
        !GetOptions(
                    'all|a'     => \$::opt_a,
					'f|force'	=> \$::FORCE,
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
                  "$::msgstr Cannot combine multiple types with \'att=val\' pairs on the command line.\n";
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
                  "$::msgstr Type \'$t\' is not a valid xCAT object type.\n";
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
        $rsp->{data}->[0] = "$::msgstr Assuming an object type of \'node\'.\n";
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
                    "$::msgstr Could not get objects of type \'$t\'.\n";
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
          "$::msgstr Cannot use \'-a\' with \'-o\' or a noderange.\n";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 3;
    }

    #  if -a then get a list of all DB objects
	my %AllObjTypeHash;
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
	my $callback = shift;

    my $rc    = 0;
    my $error = 0;

	# get the local short host name
    ($::local_host = hostname()) =~ s/\..*$//;
    chomp $::local_host;

	if (xCAT::Utils->isMN()){
		$::msgstr = "";
	} else {
		$::msgstr = "$::local_host: ";
	}

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

	# get all the attrs for these definitions
	%::objhash = xCAT::DBobjUtils->getobjdefs(\%::objtype);
	if (!defined(%::objhash))
    {
		my $rsp;
        $rsp->{data}->[0] = "$::msgstr Could not get xCAT object definitions.\n";
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
				if (mkclientdef($objname, $callback)) {
                	# could not create client definition
					$error++;
            	}
				next;
			}

			# create a NIM group definition
			if ($::objtype{$objname} eq 'group') {
				$::objhash{$objname}{'grouptype'}='static';
				if (mkgrpdef($objname, $callback)) {
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
          "$::msgstr One or more errors occured.\n";
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
				$rsp->{data}->[0] = "$::msgstr The following definitions were removed:";
			} elsif ($::opt_u) {
				$rsp->{data}->[0] = "$::msgstr The following definitions were updated:";
			} elsif (!$::opt_l) {
				$rsp->{data}->[0] = "$::msgstr The following definitions were created:";
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
              	"$::local_host: NIM operations have completed successfully.\n";
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
	my $node = shift;
	my $callback = shift;

	my $cabletype = undef;
	my $ifattr = undef;

	my %finalattrs;
	my $shorthost;
	my $net_name;
	my $adaptertype;
	my $nim_args;
	my $nim_type;

	# this code runs on service nodes - which are NIM masters

	# check to see if the client is already defined 
	#	- sets $::client_exists
    if (&check_nim_client($node, $::local_host)) {
        # the routine failed
        return 1;
    }

	# need short host name for NIM client defs
	($shorthost = $node) =~ s/\..*$//;

	# don't update an existing def unless they say so!
	if ($::client_exists && !$::opt_u) {

		if ($::FORCE) {
			# get rid of the old definition
			my $rmcmd = "/usr/sbin/nim -Fo reset $shorthost;/usr/sbin/nim -Fo deallocate -a subclass=all $shorthost;/usr/sbin/nim -Fo remove $shorthost";
			my $output = xCAT::Utils->runcmd("$rmcmd", -1);
			if ($::RUNCMD_RC  != 0) {
				my $rsp;
				push @{$rsp->{data}}, "$::msgstr Could not remove the existing NIM object named \'$shorthost\'.\n";
				if ($::VERBOSE) {
					push @{$rsp->{data}}, "$output";
				}
				xCAT::MsgUtils->message("E", $rsp, $callback);
				return 1;
			}

		} else { # no force
        	my $rsp;
        	$rsp->{data}->[0] = "$::msgstr The NIM client machine \'$shorthost\' already exists.  Use the \'-f\' option to remove and recreate or the \'-u\' option to update an existing definition.\n";
        	xCAT::MsgUtils->message("I", $rsp, $::callback);
        	return 1;
		}

    } 

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
           		$rsp->{data}->[0] = "$::msgstr Missing the MAC for node \'$node\'.\n";
           		xCAT::MsgUtils->message("E", $rsp, $::callback);
           		return 1;
		} else {
			$::objhash{$node}{'mac'} =~ s/://g;
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

	if ($::client_exists && $::opt_u) {
		$cmd = "nim -F -o change $nim_args $shorthost";
	} else {
		$cmd = "nim -o define $nim_type $nim_args $shorthost";
	}

	# may need to use dsh if it is a remote server
	my $nimcmd;
	$nimcmd = qq~$cmd 2>&1~;

	# run the cmd
   	my $output = xCAT::Utils->runcmd("$nimcmd", -1);
   	if ($::RUNCMD_RC  != 0)
   	{
       	my $rsp;
       	$rsp->{data}->[0] = "$::msgstr Could not create a NIM definition for \'$node\'.\n";
		if ($::verbose)
       	{
			$rsp->{data}->[1] = "$output";
		}
       	xCAT::MsgUtils->message("E", $rsp, $::callback);
       	return 1;
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
	my $group = shift;
    my $callback = shift;

    my $cmd = undef;
	my $servnode = undef;
    my $GrpSN = undef;

	# get members and determine all the different masters
    #   For example, the xCAT group "all" will have nodes that are managed
    #   by multiple NIM masters - so we will create a local group "all"
    #   on each of those masters
    my %ServerList = &getMasterGroupLists($group);

	foreach my $servname (keys %ServerList)
	{

		# get the members for the group def on this system
		my @members = @{$ServerList{$servname}};

		# check to see if the group is already defined - sets $::grp_exists
		if (&check_nim_group($group, $servname)) {
			# the routine failed
			return 1;
		}

		# don't update an existing def unless we're told 
		if ($::grp_exists && !$::opt_u) {
			if ($::FORCE) {
				# get rid of the old definition

				#  ???? - does remove alone do the deallocate??
				my $rmcmd = "/usr/sbin/nim -Fo remove $group";
				my $output = xCAT::Utils->runcmd("$rmcmd", -1);
				if ($::RUNCMD_RC  != 0) {
					my $rsp;
					push @{$rsp->{data}}, "$::msgstr Could not remove the existing NIM group named \'$group\'.\n";
					if ($::VERBOSE) {
						push @{$rsp->{data}}, "$output";
					}
					xCAT::MsgUtils->message("E", $rsp, $callback);
					return 1;
				}

			} else { # no force
				my $rsp;
   				$rsp->{data}->[0] = "$::msgstr The NIM group \'$group\' already exists.  Use the \'-f\' option to remove and recreate or the \'-u\' option to update an existing definition.\n";
   				xCAT::MsgUtils->message("I", $rsp, $::callback);
				return 1;
			}
		} 

		# either create or update the group def on this master

		# any list with more than 1024 members is an error
    	#   - NIM can't handle that
    	if ($#members > 1024) {
       		my $rsp;
       		$rsp->{data}->[0] = "$::msgstr Cannot create a NIM group definition with more than 1024 members - on \'$servname\'.";
       		xCAT::MsgUtils->message("E", $rsp, $::callback);
       		next;
    	}

		#
		#  The list may become quite long and not fit on one cmd line
		#  so we do it one at a time for now - need to revisit this
		#      (like do blocks at a time)  - TODO
		#
		my $justadd=0;  # after the first define we just need to add
		foreach my $memb (@members) {

			my $shorthost;
			($shorthost = $memb) =~ s/\..*$//;

			# do we change or create
			my $cmd;
			if (($::grp_exists && $::opt_u)  || $justadd) {
				$cmd = "nim -o change -a add_member=$shorthost $group 2>&1";
			} else {
				$cmd = "nim -o define -t mac_group -a add_member=$shorthost $group 2>&1";
				$justadd++;
			}

			my $output = xCAT::Utils->runcmd("$cmd", -1);
       		if ($::RUNCMD_RC  != 0)
       		{
       			my $rsp;
       			$rsp->{data}->[0] = "$::msgstr Could not create a NIM definition for \'$group\'.\n";
				if ($::verbose)
       			{
					$rsp->{data}->[1] = "$output";
				}
       			xCAT::MsgUtils->message("E", $rsp, $::callback);
       			return 1;
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

	if ($type eq 'node') {

		if ($::opt_l) {

			my $cmd;
			$cmd = qq~lsnim -l $object 2>/dev/null~;
		
			my $outref = xCAT::Utils->runcmd("$cmd", -1);
        	if ($::RUNCMD_RC  != 0)
        	{
            	my $rsp;
            	$rsp->{data}->[0] = "$::msgstr Could not get the NIM definition for $object.\n";
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
			my $cmd;

			if ($::FORCE) {
				$cmd = qq~nim -Fo reset $object;nim -Fo deallocate -a subclass=all $object;nim -Fo remove $object 2>/dev/null~;
			} else {
           		$cmd = qq~nim -Fo remove $object 2>/dev/null~;
			}

			my $outref = xCAT::Utils->runcmd("$cmd", -1);
            if ($::RUNCMD_RC  != 0)
            {
                my $rsp;
                $rsp->{data}->[0] = "$::msgstr Could not remove the NIM definition for \'$object\'.\n";
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
		my %servgroups = &getMasterGroupLists($object);

		# get the group definition from each master and
		#   display it
		foreach my $servname (keys %servgroups)
		{

			# only handle the defs for the local SN
			my $shortsn;
			($shortsn = $servname) =~ s/\..*$//;
			if ($shortsn ne $::local_host) {
				next;
			}

			my $cmd;
			if ($::opt_l) {
       			$cmd = qq~lsnim -l $object 2>/dev/null~;
		
				my $outref = xCAT::Utils->runcmd("$cmd", -1);
       			if ($::RUNCMD_RC  != 0)
       			{
           			my $rsp;
           			$rsp->{data}->[0] = "$::msgstr Could not list the NIM definition for \'$object\'.\n";
					if ($::verbose)
                	{
						$rsp->{data}->[1] = "$outref";
					}
           			xCAT::MsgUtils->message("E", $rsp, $::callback);
           			return 1;
       			} else {

           			#  display NIM output
           			my $rsp;
					$rsp->{data}->[0] = "$outref";
           			xCAT::MsgUtils->message("I", $rsp, $::callback);
           			return 0;
       			}
			} elsif ($::opt_r) {
            	$cmd = qq~nim -Fo remove $object 2>/dev/null~;

				my $outref = xCAT::Utils->runcmd("$cmd", -1);
            	if ($::RUNCMD_RC  != 0)
            	{
                	my $rsp;
                	$rsp->{data}->[0] = "$::msgstr Could not remove the NIM definition for \'$object\'.\n";
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
	my %membhash;
	my %memberhash;
	my %ServerList;

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
        $rsp->{data}->[0] = "$::msgstr Could not get members of the xCAT group \'$group\'.\n";
		xCAT::MsgUtils->message("E", $rsp, $::callback);
		return undef;
    }

	if ( defined(%memberhash)) {
		# sort the list by server node - one list per server
    	foreach my $m (@members) {

			$NimMaster = hostname();

        	if ($memberhash{$m}{nimmaster}) {
            	$NimMaster = $memberhash{$m}{nimmaster};
        	} 

			if ($memberhash{$m}{servicenode}) {
            	# the servicenode attr is set for this node
            	$NimMaster = $memberhash{$m}{servicenode};
        	} 

			if ($memberhash{$m}{xcatmaster}) {
            	$NimMaster = $memberhash{$m}{xcatmaster};
			}

			if ($NimMaster =~ /^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/) {
				# convert IP to hostname
				my $packedaddr = inet_aton($NimMaster);
				my $hostname = gethostbyaddr($packedaddr, AF_INET);
				$NimMaster = $hostname;
			}

        	# assume short hostnames for now???
        	($thismaster = $NimMaster) =~ s/\..*$//;

        	push(@{$ServerList{$thismaster}}, $m);
		}

	} else {
		# could not get node def
		my $rsp;
        $rsp->{data}->[0] = "$::msgstr Could not get xCAT node definition for all members of the xCAT group \'$group\'.\n";
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

	my @GroupList;
	
	chomp $::local_host;
    chomp $servnode;

	if ( $::NIMGroupList{$servnode}) {
		@GroupList = @{$::NIMGroupList{$servnode}};
	} else {
        $cmd = qq~lsnim -c groups | cut -f1 -d' ' 2>/dev/null~;

		@GroupList = xCAT::Utils->runcmd("$cmd", -1);
    	if ($::RUNCMD_RC  != 0)
    	{
        	my $rsp;
        	$rsp->{data}->[0] = "$::msgstr Could not get a list of NIM group definitions.\n";
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
		$cmd = qq~lsnim -c machines | cut -f1 -d' ' 2>/dev/null~;

        @ClientList = xCAT::Utils->runcmd("$cmd", -1);
        if ($::RUNCMD_RC  != 0)
        {
            my $rsp;
            $rsp->{data}->[0] = "$::msgstr Could not get a list of NIM client definitions from \'$servnode\'.\n";
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
    $rsp->{data}->[1] = "  xcat2nim [-h|--help ]\n";
    $rsp->{data}->[2] =
      "  xcat2nim [-V|--verbose] [-a|--all] [-l|--list] [-u|--update] ";

	$rsp->{data}->[3] ="    [-f|--force] [-r|--remove] [-t object-types] [-o object-names]";
    $rsp->{data}->[4] =
      "    [noderange] [attr=val [attr=val...]]\n";
    xCAT::MsgUtils->message("I", $rsp, $::callback);
    return 0;
}

1;

