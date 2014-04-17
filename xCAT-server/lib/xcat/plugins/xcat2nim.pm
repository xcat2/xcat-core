#!/usr/bin/env perl -w
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#####################################################
#
#  xCAT plugin package to handle the xcat2nim command.
#
#####################################################

package xCAT_plugin::xcat2nim;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use Sys::Hostname;
use xCAT::NodeRange;
use xCAT::Schema;
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::ServiceNodeUtils;
use xCAT::NetworkUtils;
use xCAT::DBobjUtils;
use Data::Dumper;
use Getopt::Long;
use xCAT::MsgUtils;
use Socket;

# options can be bundled up like -vV
Getopt::Long::Configure("bundling");
$Getopt::Long::ignorecase = 0;

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

	# need for runcmd output
    $::CALLBACK=$cb;

	#exit if preprocessed
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }

    my $nodes    = $req->{node}; # this may not be the list of nodes we need!
	my $command  = $req->{command}->[0];
	$::args     = $req->{arg};
    my $service  = "xcat";
	my @requests;

	if ($command =~ /xcat2nim/) {
		
		# handle -h etc.
		#  list of nodes could be derived multiple ways!!
		my ($ret, $mynodes, $servnodes, $type) = &prexcat2nim($cb);
		if ( $ret ) { # either error or -h was processed etc.
			my $rsp;
			if ($ret eq "1") {
        		$rsp->{errorcode}->[0] = $ret;
            	push @{$rsp->{data}}, "Return=$ret.";
        		xCAT::MsgUtils->message("E", $rsp, $cb, $ret);
			}
            return undef;
        } elsif (scalar(@{$mynodes})) { 

			# set up the requests to go to the service nodes
			#   - for the nodes that were provided
			#  -  to handle node and group objects
			my $sn;
			$sn = xCAT::ServiceNodeUtils->getSNformattedhash($mynodes, $service, "MN", $type);
			foreach my $snkey (keys %$sn) {
				my $reqcopy = {%$req};
				$reqcopy->{node} = $sn->{$snkey};
				$reqcopy->{'_xcatdest'} = $snkey;
				$reqcopy->{_xcatpreprocessed}->[0] = 1;
				push @requests, $reqcopy;
			}

			return \@requests;

		} elsif (scalar(@{$servnodes} )) {
			# set up the requests to go to the service nodes
			#	for network objects
			foreach my $sn (@{$servnodes}) {
				my $reqcopy = {%$req};
				$reqcopy->{'_xcatdest'} = $sn;
				$reqcopy->{_xcatpreprocessed}->[0] = 1;
				push @requests, $reqcopy;
			}

			return \@requests;
        }
    }

	return undef;
}

#----------------------------------------------------------------------------

=head3   process_request

        Check for xCAT command and call the appropriate subroutine.

        Returns:
                0 - OK
                1 - error

=cut

#-----------------------------------------------------------------------------

sub process_request
{

    $::request  = shift;
    my $callback = shift;

	# need for runcmd output
	$::CALLBACK=$callback;

    my $ret;
    my $msg;
	my $rsp;

    # globals used by all subroutines.
    $::args     = $::request->{arg};

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

	my @nodelist=();  # pass back list of nodes - if applicable
	my @servicenodes=();  # pass back list of service nodes - if applicable

    if ( defined ($::args) && @{$::args} ) {
        @ARGV = @{$::args};
    } else {
		&xcat2nim_usage($callback);
        return 1;
    }

	Getopt::Long::Configure("no_pass_through");
    if (
        !GetOptions(
                    'all|a'     => \$::opt_a,
					'b|backupSN'  => \$::BACKUP,
                    'f|force'   => \$::FORCE,
                    'help|h|?'  => \$::opt_h,
                    'list|l'    => \$::opt_l,
                    'update|u'  => \$::opt_u,
                    'remove|r'  => \$::opt_r,
					'managementnode|M'	=> \$::MN,
                    'o=s'       => \$::opt_o,
					'p|primarySN' => \$::PRIMARY,
                    't=s'       => \$::opt_t,
					's=s'		=> \$::SERVERS,
                    'verbose|V' => \$::opt_V,
                    'version|v' => \$::opt_v,
        )
      )
    {
		&xcat2nim_usage($callback);
        return 1;
    }

	# Option -h for Help
    if ($::opt_h )
    {
		&xcat2nim_usage($callback);
        return 2;
    }

    # Option -v for version 
    if ($::opt_v)
    {
        my $rsp;
        my $version=xCAT::Utils->Version();
        $rsp->{data}->[0] = "xcat2nim - $version";
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return 2;    # - just exit
    }

	# process the command line
    my $rc = &processArgs($callback);

	my $type;
	if ($::PRIMARY && $::BACKUP) {
		# setting both is the same as all
		$type="all";
	} elsif ($::PRIMARY) {
		$type="primary";
	} elsif ($::BACKUP) {
		$type="backup";
	} else {
		$type="all";
	}

	# figure out what nodes are involved - if any
	#	- so we can send the request to the correct service nodes 
	my %objhash = xCAT::DBobjUtils->getobjdefs(\%::objtype);
	my $donet = 0;
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
		if ($::objtype{$o} eq 'network') {
			if ($::FORCE || $::opt_u || $::opt_r) {
				my $rsp;
                $rsp->{data}->[0] = "The -f, -r and -u options are not supported for network objects.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
				&xcat2nim_usage($callback);
                return 2;
    		}
			$donet = 1;
		}
	}

	# NIM network defs need to be created on the NIM primary
	my $nimprime = xCAT::InstUtils->getnimprime();
    chomp $nimprime;
	@servicenodes=($nimprime);

if(0) { # only do networks on the management node (NIM primary) for now
	if ($donet) {
		if ($::MN) {
			# only do management node 
			@servicenodes=("$nimprime");
		} elsif ($::SERVERS) {
			@servicenodes=split(',', $::SERVERS);
		} else {
			# do MN and all servers
			@servicenodes=xCAT::ServiceNodeUtils->getAllSN();
			push(@servicenodes, $nimprime);
		}
	}
 
	if (scalar(@nodelist) ) {
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
	}
}

	return (0, \@nodelist, \@servicenodes, $type);
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
	my $callback = shift;

    my $gotattrs = 0;

	if ( defined ($::args) && @{$::args} ) {
    	@ARGV = @{$::args};
	} else {
		return 3;
	}

	my %ObjTypeHash;
	@::clobjnames = ();
	@::clobjtypes = ();

    # parse the options 
	Getopt::Long::Configure("no_pass_through");
    if (
        !GetOptions(
                    'all|a'     => \$::opt_a,
					'b|backupSN'  => \$::BACKUP,
					'f|force'	=> \$::FORCE,
                    'help|h|?'    => \$::opt_h,
					'list|l'    => \$::opt_l,
					'update|u'  => \$::opt_u,
					'remove|r'  => \$::opt_r,
					'managementnode|M'  => \$::MN,
                    'o=s'       => \$::opt_o,
					'p|primarySN' => \$::PRIMARY,
					's=s'       => \$::SERVERS,
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
                xCAT::MsgUtils->message("E", $rsp, $callback);
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
                  "Cannot combine multiple types with \'att=val\' pairs on the command line.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
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
                xCAT::MsgUtils->message("I", $rsp, $callback);
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
        #my $rsp;
        #$rsp->{data}->[0] = "Assuming an object type of \'node\'.\n";
        #xCAT::MsgUtils->message("I", $rsp, $callback);
    }

    #
    #  determine the object names
    #

    # -  get object names from the -o option or the noderange
	#		- this assumes the noderange was not provided as an arg!!!
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

		if (!$::opt_t || ($::opt_t eq 'node')) {
			# if the type is "node"
			@::noderange = &noderange($::opt_o, 0);
			@::clobjnames = @::noderange;
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
                xCAT::MsgUtils->message("I", $rsp, $callback);
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
        xCAT::MsgUtils->message("E", $rsp, $callback);
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
			if ( ($t eq 'node') || ($t eq 'group') || ($t eq 'network')) {

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
			$::objtype{$o}=$::clobjtypes[0];
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

	# get this systems name as known by xCAT management node
    $::Sname = xCAT::InstUtils->myxCATname();
    chomp $::Sname;

	$::msgstr = "$::Sname: ";

	my $nimprime = xCAT::InstUtils->getnimprime();
	chomp $nimprime;

    # process the command line
    $rc = &processArgs($callback);
    if ($rc != 0)
    {

        # rc: 0 - ok, 1 - return, 2 - help, 3 - error
        if ($rc != 1)
        {
            &xcat2nim_usage($callback);
        }
        return ($rc - 1);
    }

	# get all the attrs for these definitions
	%::objhash = xCAT::DBobjUtils->getobjdefs(\%::objtype);
	if (!%::objhash)
    {
		my $rsp;
        $rsp->{data}->[0] = "Could not get xCAT object definitions.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	my @nodes;
	my @networks;
	my @groups;
	foreach my $obj (keys %::objhash) {
		if ($::objtype{$obj} eq 'node') {
			push(@nodes, $obj);
		} elsif ($::objtype{$obj} eq 'network') {
                        if ($::objhash{$obj}{'gateway'} eq '<xcatmaster>') {
                            $::objhash{$obj}{'gateway'} = xCAT::NetworkUtils->my_ip_in_subnet($::objhash{$obj}{'net'}, $::objhash{$obj}{'mask'});
                            if(!$::objhash{$obj}{'gateway'}) {
                                my $rsp;
                                $rsp->{data}->[0] = "Could not get gateway for network $obj, ...skipping\n";
                                xCAT::MsgUtils->message("E", $rsp, $callback);
                                next;
                            }
                        }
			push(@networks, $obj);
		} elsif ($::objtype{$obj} eq 'group') {
			push(@groups, $obj);
		}
	}

	#  NIM machine definitions
	if (scalar(@nodes)) {
		foreach my $objname (@nodes) {

			# does this node belong to this server?
			my $nimmaster = $nimprime;
			if ($::objhash{$objname}{servicenode}) {
				my $sn2;
				($nimmaster, $sn2) = split(/,/, $::objhash{$objname}{servicenode});
			}

			if (!xCAT::InstUtils->is_me($nimmaster)) {
				next;
			}

			if ($::opt_l || $::opt_r) {

				if (&rm_or_list_nim_object($objname, $::objtype{$objname}, $callback)) {
               		# the routine failed
               		$error++;
				}
           	} else {
				if (mkclientdef($objname, $callback)) {
           			# could not create client definition
					$error++;
           		}
			}
		} # end for each node
	}

	# NIM network definitions
	if (scalar(@networks) ){
		if ($::opt_l) {
			# list network def
			if (&listNIMnetwork($callback, \@networks, \%::objhash) ) {
				# could not create client definition
                $error++;
			}
		} elsif ($::opt_r) {
			# remove network def
			
			#if (&rmNIMnetwork($callback, \@networks) ) {
            #    # could not create client definition
            #    $error++;
            #}

			my $rsp;
            push @{$rsp->{data}}, "$::msgstr The remove option is not supported for NIM network definitions.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			$error++;

		} else  {
			if (&mkNIMnetwork($callback, \@networks, \%::objhash)) {
               	# could not create client definition
               	$error++;
			}
        }
	}

	# NIM group definitions
	if (scalar(@groups) ) {
        foreach my $objname (@groups) {

			# make sure grouptype is set  ???
			$::objhash{$objname}{'grouptype'}='static';
			my $grptab = xCAT::Table->new('nodegroup');
			#dynamic groups and static groups in nodegroup table
			my @grplist = @{$grptab->getAllEntries()}; 
			foreach my $grpdef_ref (@grplist) {
				my %grpdef = %$grpdef_ref;
				if (($grpdef{'groupname'} eq $objname) && ($grpdef{'grouptype'} eq 'dynamic')) {
					$::objhash{$objname}{'grouptype'}='dynamic';
					last;
				}
			}
			$grptab->close;

			if ($::opt_l || $::opt_r) {
                if (&rm_or_list_nim_object($objname, $::objtype{$objname}, $callback)) {
                	# the routine failed
                	$error++;
				}
            } else {
				if (&mkgrpdef($objname, $callback)) {
					# could not create group definition
					$error++;
				}
			}
			next;
		}
	}

    if ($error)
    {
        my $rsp;
        $rsp->{data}->[0] =
          "$::msgstr One or more errors occured.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }
    else
    {
        return 0;
    }
	return 0;
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
    if (&check_nim_client($node, $::Sname, $callback)) {
        # the routine failed
        return 1;
    }

	# need short host name for NIM client defs
	($shorthost = $node) =~ s/\..*$//;

	#  NIM has a limit of 39 characters for a machine name
	my $len = length($shorthost);
	if ($len > 39) {
		my $rsp;
		push @{$rsp->{data}}, "$::msgstr Could not define \'$shorthost\'. A NIM machine name can be no longer then 39 characters.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}

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
        	xCAT::MsgUtils->message("I", $rsp, $callback);
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

		if (!$::objhash{$node}{'mac'})
		{
			my $rsp;
           		$rsp->{data}->[0] = "$::msgstr Missing the MAC for node \'$node\'.\n";
           		xCAT::MsgUtils->message("E", $rsp, $callback);
           		return 1;
		} else {
			$::objhash{$node}{'mac'} =~ s/://g;
		}
			
                my $mac_or_local_link_addr;
                if (xCAT::NetworkUtils->getipaddr($shorthost) =~ /:/) #ipv6 node
                {
                    $mac_or_local_link_addr = xCAT::NetworkUtils->linklocaladdr($::objhash{$node}{'mac'});
                    $adaptertype = "ent6";
                } else {
                    $mac_or_local_link_addr = $::objhash{$node}{'mac'};
                    # only support Ethernet for management interfaces
                    $adaptertype = "ent";
                }
               
		$ifattr="-a if1=\'$net_name $shorthost $mac_or_local_link_addr $adaptertype\'";
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
       	xCAT::MsgUtils->message("E", $rsp, $callback);
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

	# get members of xCAT group
    my $memberlist = xCAT::DBobjUtils->getGroupMembers($group, \%::objhash);
    my @members = split(',', $memberlist);

	# get list of nim groups defined locally
	$cmd = qq~lsnim -c groups | cut -f1 -d' ' 2>/dev/null~;
	my @GroupList = xCAT::Utils->runcmd("$cmd", -1);
	if ($::RUNCMD_RC  != 0)
	{
		my $rsp;
		$rsp->{data}->[0] = "$::msgstr Could not get a list of NIM group definitions.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}

	# get list of nim machine defined locally
    $mcmd = qq~lsnim -c machines | cut -f1 -d' ' 2>/dev/null~;
    my @nimnodes = xCAT::Utils->runcmd("$mcmd", -1);
    if ($::RUNCMD_RC  != 0)
    {
        my $rsp;
        $rsp->{data}->[0] = "$::msgstr Could not get a list of NIM group definit
ions.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	# don't update an existing def unless we're told 
	if ( (grep(/$group/, @GroupList)) && !$::opt_u) {
		if ($::FORCE) {
			# get rid of the old definition
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
   			xCAT::MsgUtils->message("I", $rsp, $callback);
			return 1;
		}
	} 

	# either create or update the group def on this master

	# any list with more than 1024 members is an error
    #   - NIM can't handle that
    if ($#members > 1024) {
    	my $rsp;
       	$rsp->{data}->[0] = "$::msgstr Cannot create a NIM group definition with more than 1024 members.";
       	xCAT::MsgUtils->message("E", $rsp, $callback);
       	next;
    }

	#
	#  The list may become quite long and not fit on one cmd line
	#  so we do it one at a time for now - need to revisit this
	#      (like do blocks at a time)  - TODO
	#
	my $justadd=0;  # after the first define we just need to add
	foreach my $memb (@members) {

		# if this node is not defined locally then don't add it to the list
		if (!grep(/$memb/, @nimnodes)) {
			next;
		}
		
		my $shorthost;
		($shorthost = $memb) =~ s/\..*$//;

		# do we change or create
		my $cmd;
		if (((grep(/$group/, @GroupList)) && $::opt_u)  || $justadd) {
			$cmd = "nim -o change -a add_member=$shorthost $group 2>&1";
		} else {
			$cmd = "nim -o define -t mac_group -a add_member=$shorthost $group 2>&1";
			$justadd++;
		}

		my $output = xCAT::Utils->runcmd("$cmd", -1);

   		if ($::RUNCMD_RC  != 0)
   		{
   			my $rsp;
   			$rsp->{data}->[0] = "$::msgstr Error running command \'$cmd\'.\n";
			if ($::verbose)
   			{
				$rsp->{data}->[1] = "$output";
			}
   			xCAT::MsgUtils->message("E", $rsp, $callback);
   			return 1;
		}
	}
	return 0;
}

#----------------------------------------------------------------------------

=head3   rm_or_list_nim_object

         List a NIM object definition.

        Argument:
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
	my ($object, $type, $callback) = @_;

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
            	xCAT::MsgUtils->message("E", $rsp, $callback);
            	return 1;
        	} else {

				#  display to NIM output
				my $rsp;
        		$rsp->{data}->[0] = "$outref";
				xCAT::MsgUtils->message("I", $rsp, $callback);
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
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
 		}
	}

	if ($type eq 'group') {

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
       			xCAT::MsgUtils->message("E", $rsp, $callback);
       			return 1;
   			} else {

       			#  display NIM output
       			my $rsp;
				$rsp->{data}->[0] = "$outref";
       			xCAT::MsgUtils->message("I", $rsp, $callback);
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
               	xCAT::MsgUtils->message("E", $rsp, $callback);
               	return 1;
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
		my $nimprime = xCAT::InstUtils->getnimprime();
    	chomp $nimprime;
        $NimMaster = $nimprime;
    }

    # assume short hostnames for now???
	if ($NimMaster) {
    	($master = $NimMaster) =~ s/\..*$//;
	}
	return $master;
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
	my ($node, $servnode, $callback) = @_;
    my ($cmd, @ClientList);

	$cmd = qq~lsnim -c machines | cut -f1 -d' ' 2>/dev/null~;
    @ClientList = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC  != 0)
    {
        my $rsp;
        $rsp->{data}->[0] = "$::msgstr Could not get a list of NIM client definitions from \'$servnode\'.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
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
	my $callback = shift;
    my $rsp;
	push @{$rsp->{data}}, "\nUsage: xcat2nim - Use this command to create and manage AIX NIM definitions based on xCAT object definitions.\n";
	push @{$rsp->{data}}, "  xcat2nim [-h|--help ]\n";
	push @{$rsp->{data}}, "  xcat2nim [-V|--verbose] [-l|--list] [-r|--remove] [-u|--update]\n    [-f|--force] [-t object-types] [-o object-names] [-a|--allobjects]\n    [-p|--primarySN] [-b|--backupSN] [noderange] [attr=val [attr=val...]]\n";
    xCAT::MsgUtils->message("I", $rsp, $callback);
    return 0;
}

#-------------------------------------------------------------------------------

=head3 mkNIMnetwork
		Create NIM network definitions corresponding to xCAT network 
		definitions. This routine runs on the NIMprime and AIX SNs

    Arguments:

    Returns:
        

    Comments:

    ex. &mkNIMnetwork($callback, \@networks, \%nethash);

=cut

#-------------------------------------------------------------------------------
sub mkNIMnetwork
{
	my $callback = shift;
	my $xnets = shift;
    my $xnhash = shift;

	my @xnetworks = @{$xnets};
    my %xnethash;    # hash of xCAT network definitions 
    if ($xnhash) {
        %xnethash = %{$xnhash};
    }

	#
    # get all the nim network names and attrs defined on this server
	#
	my $cmd = qq~/usr/sbin/lsnim -c networks | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    my @networks = xCAT::Utils->runcmd("$cmd", -1);
	
	# for each NIM network - get the attrs
	my %NIMnets;
	foreach my $netwk (@networks) {
		my $cmd = qq~/usr/sbin/lsnim -Z -a net_addr -a snm $netwk 2>/dev/null~;
		my @result = xCAT::Utils->runcmd("$cmd", -1);
		if ($::RUNCMD_RC  != 0) {
			my $rsp;
			push @{$rsp->{data}}, "$::msgstr Could not run lsnim command: \'$cmd\'.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}

		foreach my $l (@result){
			# skip comment lines
			next if ($l =~ /^\s*#/);

			my ($nimname, $net_addr, $snm) = split(':', $l);
			$NIMnets{$netwk}{'net_addr'} = $net_addr;
            $NIMnets{$netwk}{'snm'} = $snm;
		}
	}

	#
    # for each xCAT network - see if the net we need is defined
    #
    foreach my $net (@xnetworks) {

		# see if it's already defined - or equivalent is defined
		# split  mask
        my ($nm1, $nm2, $nm3, $nm4) = split('\.', $xnethash{$net}{mask});

		# split net addr
        my ($nn1, $nn2, $nn3, $nn4) = split('\.', $xnethash{$net}{net});

		# foreach nim network name
		foreach my $netwk (@networks) {

			# split definition mask
			my ($dm1, $dm2, $dm3, $dm4) = split('\.', $NIMnets{$netwk}{'snm'});

			# split definition net addr
			my ($dn1, $dn2, $dn3, $dn4) = split('\.', $NIMnets{$netwk}{'net_addr'});
			# check for the same netmask and network address
			if ( ($nn1 == $dn1) && ($nn2 ==$dn2) && ($nn3 == $dn3) && ($nn4 == $dn4) ) {
				if ( ($nm1 == $dm1) && ($nm2 ==$dm2) && ($nm3 == $dm3) && ($nm4 == $dm4) ) {
					$foundmatch=1;
				}
			}
		}

		# if not defined then define it! 
		if (!$foundmatch) {

			# create new nim network def
			# use the same network name as xCAT uses
			my $cmd;
			$cmd = qq~/usr/sbin/nim -o define -t ent -a net_addr=$xnethash{$net}{net} -a snm=$xnethash{$net}{mask} -a routing1='default $xnethash{$net}{gateway}' $net 2>/dev/null~;

			my $output1 = xCAT::Utils->runcmd("$cmd", -1);
			if ($::RUNCMD_RC  != 0) {
				my $rsp;
				push @{$rsp->{data}}, "$::msgstr Could not run \'$cmd\'.\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
				return 1;
			}

			# get all the possible IPs for the node I'm running on
			my $ifgcmd = "ifconfig -a | grep 'inet'";
			my @result = xCAT::Utils->runcmd($ifgcmd, 0);
			if ($::RUNCMD_RC != 0) {
				my $rsp;
                push @{$rsp->{data}}, "$::msgstr Could not run \'$ifgcmd\'.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
			}

			
			my $samesubnet = 0;
			my ($inet, $myIP, $str);
			foreach my $int (@result) {
				($inet, $myIP, $str) = split(" ", $int);
				chomp $myIP;
				$myIP =~ s/\/.*//; # ipv6 address 4000::99/64
				$myIP =~ s/\%.*//; # ipv6 address ::1%1/128

				# if the ip address is in the subnet
				if ( xCAT::NetworkUtils->ishostinsubnet($myIP, $xnethash{$net}{mask}, $xnethash{$net}{net} )) {
                    # to create the nim network object within the same subnet
					$samesubnet = 1;
					last;
				}
			}

			if ($samesubnet == 1)
			{
    			#
            	# create an interface def (if*) for the master 
    			#
    			# first get the if* and cable_type* attrs
    			#  - the -A option gets the next avail index for this attr
    			my $ifcmd = qq~/usr/sbin/lsnim -A if master 2>/dev/null~;
    			my $ifindex = xCAT::Utils->runcmd("$ifcmd", -1);
                if ($::RUNCMD_RC  != 0) {
                    my $rsp;
                    push @{$rsp->{data}}, "Could not run \'$ifcmd\'.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return 1;
                }

    			my $ctcmd = qq~/usr/sbin/lsnim -A cable_type master 2>/dev/null~;
    			my $ctindex = xCAT::Utils->runcmd("$ctcmd", -1);
    			if ($::RUNCMD_RC  != 0) {
                    my $rsp;
                    push @{$rsp->{data}}, "$::msgstr Could not run \'$ctcmd\'.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return 1;
                }			    

			    # 
			    # get the local adapter hostname for this network
			    my $adapterhostname = xCAT::NetworkUtils->gethostname($myIP);

    			# define the new interface
    			my $chcmd = qq~/usr/sbin/nim -o change -a if$ifindex='$net $adapterhostname 0' -a cable_type$ctindex=N/A master 2>/dev/null~;

    			my $output2 = xCAT::Utils->runcmd("$chcmd", -1);
                if ($::RUNCMD_RC  != 0) {
                    my $rsp;
                    push @{$rsp->{data}}, "$::msgstr Could not run \'$chcmd\'.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return 1;
                }
			}
			else
			{
			    # cross subnet
			    # create static routes between the networks

    			# get master_net - always if1
    			my $hncmd = qq~/usr/sbin/lsnim -a if1 -Z master 2>/dev/null~;
    			my @ifone = xCAT::Utils->runcmd("$hncmd", -1);
    			if ($::RUNCMD_RC  != 0) {
                    my $rsp;
                    push @{$rsp->{data}}, "$::msgstr Could not run \'$hncmd\'.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return 1;
                }

    			my ($junk1, $masternet, $adapterhost);
    			foreach my $l (@ifone){
    				# skip comment lines
    				next if ($l =~ /^\s*#/);
    				($junk1, $masternet, $adapterhost) = split(':', $l);

    			}

            	# get the next index for the routing attr
    			my $ncmd = qq~/usr/sbin/lsnim -A routing $masternet 2>/dev/null~;
    			my $rtindex = xCAT::Utils->runcmd("$ncmd", -1);
    			if ($::RUNCMD_RC  != 0) {
                    my $rsp;
                    push @{$rsp->{data}}, "$::msgstr Could not run \'$ncmd\'.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return 1;
                }

                # get the gateway of master_net
    			my $gcmd = qq~/usr/sbin/lsnim -a routing1 -Z $masternet 2>/dev/null~;
    			my @gws = xCAT::Utils->runcmd("$gcmd", -1);
    			if ($::RUNCMD_RC  != 0) {
                    my $rsp;
                    push @{$rsp->{data}}, "$::msgstr Could not run \'$gcmd\'.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return 1;
                }

    			my ($junk, $dft, $gw);
    			foreach my $l (@gws){
    				# skip comment lines
    				next if ($l =~ /^\s*#/);
    				($junk, $dft, $gw) = split(':', $l);
    			}

    			my $masternetgw;
    			if ($dft =~ /default/)
    			{
    			    $masternetgw = $gw;
    			}
    			else
    			{
    			    # use the master IP as default gateway
        			# get the ip of the nim primary interface
        			my $gwIP = xCAT::NetworkUtils->getipaddr($adapterhost);
        			chomp $gwIP;
        			$masternetgw = $gwIP;
    			}

    			# create static routes between the networks
    			my $rtgcmd = qq~/usr/sbin/nim -o change -a routing$rtindex='$net $masternetgw $xnethash{$net}{gateway}' $masternet 2>/dev/null~;
    			my $output3 = xCAT::Utils->runcmd("$rtgcmd", -1);
                if ($::RUNCMD_RC  != 0) {
                    my $rsp;
                    push @{$rsp->{data}}, "$::msgstr Could not run \'$rtgcmd\'.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return 1;
                }
			    
			}
		} # end - define new nim network

	} # end - for each network
	return 0;
}

#-------------------------------------------------------------------------------

=head3 listNIMnetwork
        List NIM network definitions corresponding to xCAT network
        definitions. This routine runs on the NIMprime and AIX SNs

    Arguments:

    Returns:

    Comments:

    ex. &listNIMnetwork($callback, \@networks, \%nethash);

=cut

#-------------------------------------------------------------------------------
sub listNIMnetwork
{
    my $callback = shift;
	my $xnets = shift;
	my $xnhash = shift;

    my %xnethash;    # hash of xCAT network definitions
    if ($xnhash) {
        %xnethash = %{$xnhash};
    }

    my @xcatnetworks = @{$xnets};

	#
    # get all the nim network names
    #
    my $cmd = qq~/usr/sbin/lsnim -c networks | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    my @nimnetworks = xCAT::Utils->runcmd("$cmd", -1);
	if ($::RUNCMD_RC  != 0) {
		my $rsp;
		push @{$rsp->{data}}, "$::msgstr Could not run lsnim command: \'$cmd\'.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}

	# for each NIM network - get the attrs
    my %NIMnets;
    foreach my $netwk (@nimnetworks) {
        my $cmd = qq~/usr/sbin/lsnim -Z -a net_addr -a snm $netwk 2>/dev/null~;
        my @result = xCAT::Utils->runcmd("$cmd", -1);
        if ($::RUNCMD_RC  != 0) {
            my $rsp;
            push @{$rsp->{data}}, "$::msgstr Could not run lsnim command: \'$cmd\'.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }

        foreach my $l (@result){
            # skip comment lines
            next if ($l =~ /^\s*#/);

            my ($nimname, $net_addr, $snm) = split(':', $l);
            $NIMnets{$netwk}{'net_addr'} = $net_addr;
            $NIMnets{$netwk}{'snm'} = $snm;
        }
    }

	# for each xCAT network check for an equivalent NIM network
	#	- if a match then display the NIM def
	#	- display output of "lsnim -l <netname>"

	foreach my $xcatnet (@xcatnetworks) {

		# split  mask
        my ($nm1, $nm2, $nm3, $nm4) = split('\.', $xnethash{$xcatnet}{mask});

        # split net addr
        my ($nn1, $nn2, $nn3, $nn4) = split('\.', $xnethash{$xcatnet}{net});

		foreach my $nimnet (@nimnetworks) {
			# split definition mask
            my ($dm1, $dm2, $dm3, $dm4) = split('\.', $NIMnets{$nimnet}{'snm'});

            # split definition net addr
            my ($dn1, $dn2, $dn3, $dn4) = split('\.', $NIMnets{$nimnet}{'net_addr'});
            # check for the same netmask and network address
            if ( ($nn1 == $dn1) && ($nn2 ==$dn2) && ($nn3 == $dn3) && ($nn4 == $dn4) ) {
                if ( ($nm1 == $dm1) && ($nm2 ==$dm2) && ($nm3 == $dm3) && ($nm4== $dm4) ) {
                    # found match so display NIM net def
					my $cmd = qq~/usr/sbin/lsnim -l $nimnet 2>/dev/null~;
					my $output = xCAT::Utils->runcmd("$cmd", -1);
					if ($::RUNCMD_RC  != 0) {
				#		my $rsp;
				#		push @{$rsp->{data}}, "Could not run lsnim command: \'$cmd\'.\n";
				#		xCAT::MsgUtils->message("E", $rsp, $callback);
						next;
					} else {
						my $rsp;
						push @{$rsp->{data}}, "Note: The following is a match for \nxCAT network named \'$xcatnet\'\n";
						push @{$rsp->{data}}, "$output\n";
						xCAT::MsgUtils->message("I", $rsp, $callback);	
					}
                }
            }
		} # end for each nim net
	} # end foreach xcat net

	return 0;
}

#-------------------------------------------------------------------------------

=head3 rmNIMnetwork
        Remove NIM network definitions corresponding to xCAT network
        definitions. This routine runs on the NIMprime and AIX SNs

    Arguments:

    Returns:


    Comments:

    ex. &rmNIMnetwork($callback, \@networks);

=cut

#-------------------------------------------------------------------------------
sub rmNIMnetwork
{
    my $callback = shift;
	my $xnets = shift;




############################################
#
#    This will not work - you must first remove the master if* definition
#		and the route defs AND any objects that may reference the network
#		- it is not worth the effort - maybe a future
#		enhancement - I'll leave the code here for now.
#########################################################

    my @xcatnetworks = @{$xnets};

	#
    # get all the nim network names
    #
    my $cmd = qq~/usr/sbin/lsnim -c networks | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    my @nimnetworks = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC  != 0) {
        my $rsp;
        push @{$rsp->{data}}, "Could not run lsnim command: \'$cmd\'.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	foreach my $xcatnet (@xcatnetworks) {
		chomp $xcatnet;

		foreach my $nimnet (@nimnetworks) {
			chomp $nimnet;

			if ($xcatnet eq $nimnet) {
				# get rid of the old definition
 				my $rmcmd = "/usr/sbin/nim -Fo remove $nimnet";
				my $output = xCAT::Utils->runcmd("$rmcmd", -1);
				if ($::RUNCMD_RC  != 0) {
					my $rsp;
					push @{$rsp->{data}}, "Could not remove the existing NIM network named \'$nimnet\'.\n";
					if ($::VERBOSE) {
						push @{$rsp->{data}}, "$output";
					}
					xCAT::MsgUtils->message("E", $rsp, $callback);
				} else {
					if ($::VERBOSE) {
						my $rsp;
						push @{$rsp->{data}}, "Removed the NIM network definition called \'$nimnet\'\n";			
						xCAT::MsgUtils->message("I", $rsp, $callback);
					}
				}
			}
		}
	}

	return 0;
}

1;

