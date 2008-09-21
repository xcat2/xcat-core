#!/usr/bin/env perl -w
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#####################################################
#
#  xCAT plugin package to handle the following commands.
#	 mkdsklsnode, rmdsklsnode, mknimimage,  
#	 rmnimimage & nimnodeset
#
#####################################################

package xCAT_plugin::aixinstall;

use xCAT::NodeRange;
use xCAT::Schema;
use xCAT::Utils;
use xCAT::DBobjUtils;
use Data::Dumper;
use Getopt::Long;
use xCAT::MsgUtils;
use strict;
use Socket;
use File::Path;

# options can be bundled up like -vV
Getopt::Long::Configure("bundling");
$Getopt::Long::ignorecase = 0;


#------------------------------------------------------------------------------

=head1    aixinstall

This program module file supports the mkdsklsnode, rmdsklsnode,
rmnimimage, mknimimage, & nimnodeset commands.


=cut

#------------------------------------------------------------------------------

=head2    xCAT for AIX support

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
            mknimimage => "aixinstall",
			rmnimimage => "aixinstall",
            mkdsklsnode => "aixinstall",
			rmdsklsnode => "aixinstall",
			nimnodeset => "aixinstall"
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

    my $request  = shift;
    my $callback = shift;
    my $sub_req = shift; 
    my $ret;
    my $msg;
    
    $::callback=$callback;

    my $command  = $request->{command}->[0];
    $::args     = $request->{arg};
    $::filedata = $request->{stdin}->[0];

    # figure out which cmd and call the subroutine to process
    if ($command eq "mkdsklsnode")
    {
        ($ret, $msg) = &mkdsklsnode($callback, $sub_req);
    }
    elsif ($command eq "mknimimage")
    {
        ($ret, $msg) = &mknimimage($callback);
    }
	elsif ($command eq "rmnimimage")
	{
		($ret, $msg) = &rmnimimage($callback);
					}
	elsif ($command eq "rmdsklsnode")
	{
		($ret, $msg) = &rmdsklsnode($callback);
	} 
	elsif ($command eq "nimnodeset")
	{
		($ret, $msg) = &nimnodeset($callback, $sub_req);
	}


	if ($ret > 0) {
		my $rsp;

		if ($msg) {
			push @{$rsp->{data}}, $msg;
		} else {
			push @{$rsp->{data}}, "Command returned an error.";
		}

		$rsp->{errorcode}->[0] = $ret;
		
		xCAT::MsgUtils->message("E", $rsp, $callback, $ret);

	}

	return 0;
}
    
my $errored = 0;


#----------------------------------------------------------------------------

=head3   nimnodeset 

        Support for the nimnodeset command.

		Does the NIM setup for xCAT cluster nodes.

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:
        Example:
        Comments:

=cut

#-----------------------------------------------------------------------------
sub nimnodeset
{
    my $callback = shift;
    my $sub_req = shift;

	my $error=0;
	my @nodesfailed;
	my $image_name;

	# some subroutines require a global callback var
	#	- need to change to pass in the callback 
	#	- just set global for now
    $::callback=$callback;

	if (defined(@{$::args})) {
        @ARGV = @{$::args};
    } else {
        &nimnodeset_usage($callback);
		return 0;
    }

	# parse the options
	if(!GetOptions(
		'f|force'	=> \$::FORCE,
		'h|help'    => \$::HELP,
		'i=s'       => \$::OSIMAGE,
		'verbose|V' => \$::VERBOSE,
		'v|version' => \$::VERSION,))
	{
		&nimnodeset_usage($callback);
		return 1;
	}

	if ($::HELP) {
		&nimnodeset_usage($callback);
		return 0;
	}

	# display the version statement if -v or --verison is specified
    if ($::VERSION)
    {
		my $version=xCAT::Utils->Version();
        my $rsp;
        push @{$rsp->{data}}, "nimnodeset $version\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return 0;
    }

	my @nodelist;
	my %objtype;
	my %objhash;    # node definitions
	my %attrs;  	# attr=val pairs from cmd line 
	my %cmdargs; 	# args for the "nim -o bos_inst" cmd line
	my @machines;	# list of defined NIM machines
	my @nimrestypes;	# list of NIM resource types 
	my @nodesfailed;	# list of xCAT nodes that could not be initialized
	my %imagehash;		# osimage definition

	# the first arg should be a noderange - the other should be attr=val
    #  - put attr=val operands in %attrs hash
    while (my $a = shift(@ARGV))
    {
        if (!($a =~ /=/))
        {
			@nodelist = &noderange($a, 0);
        }
        else
        {
            # if it has an "=" sign its an attr=val - we hope
            my ($attr, $value) = $a =~ /^\s*(\S+?)\s*=\s*(\S*.*)$/;
            if (!defined($attr) || !defined($value))
            {
                my $rsp;
                $rsp->{data}->[0] = "Incorrect \'attr=val\' pair - $a\n";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                return 1;
            }
            # put attr=val in hash
			$attrs{$attr} = $value;
        }
    }

	# get all the attrs for these node definitions
	foreach my $o (@nodelist)
	{
		$objtype{$o} = 'node';
	}
	%objhash = xCAT::DBobjUtils->getobjdefs(\%objtype,$callback);
	if (!defined(%objhash))
	{
		my $rsp;
		push @{$rsp->{data}}, "Could not get xCAT object definitions.\n";
	    xCAT::MsgUtils->message("E", $rsp, $callback);
    	return 1;
	}


    #
    #  Get a list of the defined NIM machines
    #
    my $cmd = qq~/usr/sbin/lsnim -c machines | /usr/bin/cut -f1 -d' ' 2>/dev/nu
ll~;
    @machines = xCAT::Utils->runcmd("$cmd", -1);
	# don't fail - maybe just don't have any defined!

	#
    #  Get a list of all nim resource types
    #
    my $cmd = qq~/usr/sbin/lsnim -P -c resources | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    @nimrestypes = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC  != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get NIM resource definitions.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	# get the osimage definition
	if ($::OSIMAGE) {
        my %objtype;
        $objtype{$::OSIMAGE} = 'osimage';
        %imagehash = xCAT::DBobjUtils->getobjdefs(\%objtype,$callback);
        if (!defined(%imagehash))
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not get an osimage definition for \'$image_name\'.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
	}

	# create a NIM script resource using the xcataixpost script
	my $resname = "xcataixpost";
	my $respath = "/install/postscripts/xcataixpost";
	if (&mkScriptRes($resname, $respath, $callback) != 0) {
		my $rsp;
		push @{$rsp->{data}}, "Could not create a NIM resource for xcataixpost.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}

	my $error=0;
    foreach my $node (keys %objhash)
    {
		
		# get the image name to use for this node
		# either from cmd line or node def
		if ($::OSIMAGE){
			# from the command line
			$image_name=$::OSIMAGE;
			chomp $image_name;
		} elsif ( $objhash{$node}{profile} ) {

			# from the node definition
			$image_name=$objhash{$node}{profile};
			chomp $image_name;

			# get this osimage definition
			my %objtype;
			$objtype{$image_name} = 'osimage';
			%imagehash = xCAT::DBobjUtils->getobjdefs(\%objtype,$callback);
			if (!defined(%imagehash))
			{
				my $rsp;
				push @{$rsp->{data}}, "Could not get an osimage definition for \'$image_name\'.\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
				push(@nodesfailed, $node);
				$error++;
				next;
			}

		} else {
			my $rsp;
            push @{$rsp->{data}}, "Could not determine an OS image name for node \'$node\'.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
			push(@nodesfailed, $node);
			$error++;
			next;
		}

		# check if node is in ready state
		my $shorthost;
		($shorthost = $node) =~ s/\..*$//;
        chomp $shorthost;
		my $cstate = &get_nim_attr_val($shorthost, "Cstate", $callback);
		if ( defined($cstate) && (!($cstate =~ /ready/)) ){
			if ($::FORCE) {
				# if it's not in a ready state then reset it
				my $rcmd = "/usr/sbin/nim -Fo reset $shorthost;/usr/sbin/nim -Fo deallocate -a subclass=all $shorthost";
				my $output = xCAT::Utils->runcmd("$rcmd", -1);
            	if ($::RUNCMD_RC  != 0) {
                	my $rsp;
                	push @{$rsp->{data}}, "Could not reset the existing NIM object named \'$shorthost\'.\n";
                	if ($::VERBOSE) {
                    	push @{$rsp->{data}}, "$output";
                	}
                	xCAT::MsgUtils->message("E", $rsp, $callback);
                	$error++;
                	push(@nodesfailed, $node);
                	next;
            	}
			} else {

				my $rsp;
				push @{$rsp->{data}}, "The NIM machine named $shorthost is not in the ready state and cannot be initialized.\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
                $error++;
                push(@nodesfailed, $node);
                next;

			}
		}

		# set the NIM machine type
		my $type="standalone";
		if ($imagehash{$image_name}{nimtype} ) {
			$type = $imagehash{$image_name}{nimtype};
		}
		chomp $type;

		if ( !($type =~ /standalone/) ) {
            #error - only support standalone for now
            #   - use mkdsklsnode for diskless/dataless nodes
            my $rsp;
            push @{$rsp->{data}}, "Use the mkdsklsnode command to initialize diskless/dataless nodes.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            $error++;
            push(@nodesfailed, $node);
            next;
        }

		# set the NIM install method (rte or mksysb)
        my $method="rte";
        if ($imagehash{$image_name}{nimmethod} ) {
            $method = $imagehash{$image_name}{nimmethod};
        }
        chomp $method;
		
		# by convention the nim name is the short hostname of our node
		my $nim_name;
		($nim_name = $node) =~ s/\..*$//;
		chomp $nim_name;
		if (!grep(/^$nim_name$/, @machines)) {
			my $rsp;
			push @{$rsp->{data}}, "The NIM machine \'$nim_name\' is not defined.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
            $error++;
            push(@nodesfailed, $node);
            next;
		}

		# figure out what resources and options to pass to NIM "bos_inst"
		#  first set %cmdargs to osimage info then set to cmd line %attrs info
		#  TODO - what about resource groups????

		#  add any resources that are included in the osimage def
		#		only take the attrs that are actual NIM resource types
		my $script_string="";
        my $bnd_string="";
        foreach my $restype (sort(keys %{$imagehash{$image_name}})) {
            # restype is res type (spot, script etc.)
            # resname is the name of the resource (61spot etc.)
            my $resname = $imagehash{$image_name}{$restype};

			# if the attr is an actual resource type then add it 
			#	to the list of args
            if (grep(/^$restype$/, @nimrestypes)) {
                if ($resname) {
					# handle multiple script & installp_bundles
                    if ( $restype eq 'script') {
                        foreach (split /,/,$resname) {
                            chomp $_;
                            $script_string .= "-a script=$_ ";
                        }
                    } elsif ( $restype eq 'installp_bundle') {
                        foreach (split /,/,$resname) {
                            chomp $_;
                            $bnd_string .= "-a installp_bundle=$_ ";
                        }

                    } else {
                        # ex. attr=spot resname=61spot
                        $cmdargs{$restype} = $resname;
                    }
                }
            }
        }

		# now add/overwrite with what was provided on the cmd line
		if (defined(%attrs)) {
			foreach my $attr (keys %attrs) {
				# assume each attr corresponds to a valid
                #   "nim -o bos_inst" attr
                # handle multiple script & installp_bundles
                if ( $attr eq 'script') {
                    $script_string = "";
                    foreach (split /,/,$attrs{$attr}) {
                        chomp $_;
                        $script_string .= "-a script=$_ ";
                    }
                } elsif ( $attr eq 'installp_bundle'){
                    $bnd_string="";
                    foreach (split /,/,$attrs{$attr}) {
                        chomp $_;
                        $bnd_string .= "-a installp_bundle=$_ ";
                    }

                } else {
                    # ex. attr=spot resname=61spot
                    $cmdargs{$attr} = $attrs{$attr};
                }
			}
		}

		if ($method eq "mksysb") {
			$cmdargs{source} = "mksysb";

			# check for req attrs

		} elsif ($method eq "rte") {
			$cmdargs{source} = "rte";

			# TODO - check for req attrs
		}

		# must add script res
		$cmdargs{script} = $resname;

		# set boot_client
		if (!defined($cmdargs{boot_client})) {
			$cmdargs{boot_client} = "no";
		}

		# set accept_licenses
        if (!defined($cmdargs{accept_licenses})) {
            $cmdargs{accept_licenses} = "yes";
        }

		# create the cmd line args
		my $arg_string=" ";
		foreach my $attr (keys %cmdargs) {
			$arg_string .= "-a $attr=$cmdargs{$attr} ";
		}

		if ($script_string) {
            $arg_string .= "$script_string";
        }

        if ($bnd_string) {
            $arg_string .= "$bnd_string";
        }

		my $initcmd;
		$initcmd="/usr/sbin/nim -o bos_inst $arg_string $nim_name 2>&1";

		my $output = xCAT::Utils->runcmd("$initcmd", -1);
		if ($::RUNCMD_RC  != 0)
		{
			my $rsp;
			push @{$rsp->{data}}, "The NIM bos_inst operation failed for \'$nim_name\'.\n";
			if ($::VERBOSE) {
				push @{$rsp->{data}}, "$output";
			}
			xCAT::MsgUtils->message("E", $rsp, $callback);
			$error++;
            push(@nodesfailed, $node);
			next;
		}
	} # end - for each node

	# update the node definitions with the new osimage - if provided
	my %nodeattrs;
	if ($::OSIMAGE) {
		foreach my $node (keys %objhash) {
			chomp $node;

			if (!grep(/^$node$/, @nodesfailed)) {
				# change the node def if we were successful
				$nodeattrs{$node}{objtype} = 'node';
				$nodeattrs{$node}{profile} = $image_name;
			}
		}


		if (xCAT::DBobjUtils->setobjdefs(\%nodeattrs) != 0) {
			my $rsp;
			push @{$rsp->{data}}, "Could not write data to the xCAT database.\n";
			xCAT::MsgUtils->message("E", $rsp, $::callback);
			$error++;
		}
	}

	# update the .rhosts file on the server so the rcp from the node works
    if (&update_rhosts(\@nodelist, $callback) != 0) {
        my $rsp;
        push @{$rsp->{data}}, "Could not update the /.rhosts file.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        $error++;
    }

	if ($error) {
		my $rsp;
		push @{$rsp->{data}}, "One or more errors occurred when attempting to initialize AIX NIM nodes.\n";

		if ($::VERBOSE && (defined(@nodesfailed))) {
			push @{$rsp->{data}}, "The following node(s) could not be initialized.\n";
			foreach my $n (@nodesfailed) {
				push @{$rsp->{data}}, "$n";
			}
		}

		xCAT::MsgUtils->message("I", $rsp, $callback);
		return 1;
	} else {
		my $rsp;
		push @{$rsp->{data}}, "AIX/NIM nodes were initialized.\n";
		xCAT::MsgUtils->message("I", $rsp, $callback);

		return 0;
	}
	return 0;
}

#----------------------------------------------------------------------------

=head3   mknimimage


		Creates an AIX/NIM image 

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Usage:

		mknimimage [-V] [-f | --force] [-l location] [-s image_source]
		   [-i current_image] image_name [attr=val [attr=val ...]]

		Comments:

=cut

#-----------------------------------------------------------------------------
sub mknimimage
{
	my $callback = shift;

	my $lppsrcname; # name of the lpp_source resource for this image
	$::image_name; # name of xCAT osimage to create
	my $spot_name;  # name of SPOT/COSI  default to image_name
	my $rootres;    # name of the root resource
	my $dumpres;    #  dump resource
	my $pagingres;  # paging
	my $currentimage; # the image to copy
	%::attrres;   # NIM resource type and names passed in as attr=val
	my %newres;   # NIM resource type and names create by this cmd
	%::imagedef;    # osimage info provided by "-i" option
	my %osimagedef; # NIM resource type and names for the osimage def 
	my $bosinst_data_name;
	my $resolv_conf_name;
	my $mksysb_name;
	my $lpp_source_name;
	my $root_name;
	my $dump_name;

	if (defined(@{$::args})) {
        @ARGV = @{$::args};
    } else {
        &mknimimage_usage($callback);
        return 0;
    }

	# parse the options
	Getopt::Long::Configure("no_pass_through");
	if(!GetOptions(
		'b=s'		=> \$::SYSB,
		'f|force'	=> \$::FORCE,
		'h|help'     => \$::HELP,
		's=s'       => \$::opt_s,
		'l=s'       => \$::opt_l,
		'i=s'       => \$::opt_i,
		't=s'		=> \$::NIMTYPE,
		'm=s'		=> \$::METHOD,
		'n=s'		=> \$::MKSYSBNODE,
		'verbose|V' => \$::VERBOSE,
		'v|version'  => \$::VERSION,))
	{

		&mknimimage_usage($callback);
        return 1;
	}

	# display the usage if -h or --help is specified
    if ($::HELP) {
        &mknimimage_usage($callback);
        return 0;
    }

	# display the version statement if -v or --verison is specified
    if ($::VERSION)
    {
		my $version=xCAT::Utils->Version();
        my $rsp;
        push @{$rsp->{data}}, "mknimimage $version\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return 0;
    }

	# the type is standalone by default
	if (!$::NIMTYPE) {
		$::NIMTYPE = "standalone";
	}

	# the NIM method is rte by default
	if (($::NIMTYPE eq "standalone") && !$::METHOD) {
		$::METHOD = "rte";
	}

	#
    # process @ARGV
    #

	# the first arg should be a noderange - the other should be attr=val
    #  - put attr=val operands in %::attrres hash
    while (my $a = shift(@ARGV))
    {
        if (!($a =~ /=/))
        {
			$::image_name = $a;
			chomp $::image_name;
        }
        else
        {
            # if it has an "=" sign its an attr=val - we hope
			# attr must be a NIM resource type and val must be a resource name
            my ($attr, $value) = $a =~ /^\s*(\S+?)\s*=\s*(\S*.*)$/;
            if (!defined($attr) || !defined($value))
            {
                my $rsp;
                $rsp->{data}->[0] = "Incorrect \'attr=val\' pair - $a\n";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                return 3;
            }
            # put attr=val in hash
			$::attrres{$attr} = $value;
        }
    }

	if ( ($::NIMTYPE eq "standalone") && $::OSIMAGE) {
		my $rsp;
		push @{$rsp->{data}}, "The \'-i\' option is only valid for diskless and dataless nodes.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		&mknimimage_usage($callback);
        return 1;
	}

	#
	#  Install/config NIM master if needed
	#
	# check for master file set
	my $lsnimcmd = "/usr/bin/lslpp -l bos.sysmgt.nim.master >/dev/null 2>&1";
	my $out = xCAT::Utils->runcmd("$lsnimcmd", -1);
	if ($::RUNCMD_RC  != 0) {
		# if its not installed then run
		#   - takes 21 sec even when already configured
		my $nimcmd = "nim_master_setup -a mk_resource=no -a device=$::opt_s";
		my $nimout = xCAT::Utils->runcmd("$nimcmd", -1);
		if ($::RUNCMD_RC  != 0) {
			my $rsp;
			push @{$rsp->{data}}, "Could install and configure NIM.\n";
			if ($::VERBOSE) {
                push @{$rsp->{data}}, "$nimout";
            }
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}
	}

	#
	# see if the image_name (osimage) provided is already defined
	#
	my @deflist = xCAT::DBobjUtils->getObjectsOfType("osimage");
	if (grep(/^$::image_name$/, @deflist)) {
		if ($::FORCE) {
			# remove the existing osimage def and continue
			my %objhash;
			$objhash{$::image_name} = "osimage";
			if (xCAT::DBobjUtils->rmobjdefs(\%objhash) != 0) {
				my $rsp;
				push @{$rsp->{data}}, "Could not remove the existing xCAT definition for \'$::image_name\'.\n";
				xCAT::MsgUtils->message("E", $rsp, $::callback);
			}
		} else {
			my $rsp;
			push @{$rsp->{data}}, "The osimage definition \'$::image_name\' already exists.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}
	}

	#
    #  Get a list of the all defined resources
    #
    my $cmd = qq~/usr/sbin/lsnim -c resources | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    @::nimresources = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC  != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get NIM resource definitions.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	#
	#  Handle diskless, rte, & mksysb 
	#

	if ( ($::NIMTYPE eq "diskless") | ($::NIMTYPE eq "dataless") ) {

		# need lpp_source, spot, dump, paging, & root
		# user can specify others 

		# get the xCAT image definition if provided
    	if ($::opt_i) {
        	my %objtype;
			my $currentimage=$::opt_i;

			# get the image def
        	$objtype{$::opt_i} = 'osimage';

			%::imagedef = xCAT::DBobjUtils->getobjdefs(\%objtype,$callback);
			if (!defined(%::imagedef))
			{
				my $rsp;
				push @{$rsp->{data}}, "Could not get xCAT image definition.\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
				return 1;
			}
		}

		# must have a source and a name
		if (!($::opt_s || $::opt_i) || !defined($::image_name) ) {
			my $rsp;
			push @{$rsp->{data}}, "The image name and either the -s or -i option are required.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			&mknimimage_usage($callback);
			return 1;
		}

		#
		# get lpp_source
		#
		$lpp_source_name = &mk_lpp_source($callback);
		chomp $lpp_source_name;
		$newres{lpp_source} = $lpp_source_name;
		if ( !defined($lpp_source_name)) {
			# error
			my $rsp;
            push @{$rsp->{data}}, "Could not create lpp_source definition.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
		}

		#
		# spot resource
		#

		$spot_name=&mk_spot($lpp_source_name, $callback);
		chomp $spot_name;
		$newres{spot} = $spot_name;
		if ( !defined($spot_name)) {
			my $rsp;
            push @{$rsp->{data}}, "Could not create spot definition.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
		}

		#
		#  Update the SPOT resource
		#
		my $rc=&updatespot($spot_name, $lpp_source_name, $callback);
		if ($rc != 0) {
			my $rsp;
			push @{$rsp->{data}}, "Could not update the SPOT resource named \'$spot_name\'.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}

		#
		#  Identify or create the rest of the resources for this diskless image
		#
		# 	- required - root, dump, paging, 
		#  

		#
		# root res
		#
		my $root_name;
		if ( $::attrres{root} ) {

        	# if provided on cmd line then use it
        	$root_name=$::attrres{root};

		} elsif ($::opt_i) {

			# if one is provided in osimage use it    
			if ($::imagedef{$::opt_i}{root}) {
				$root_name=$::imagedef{$::opt_i}{root};
			}

    	} else {

			# may need to create new one

			# use naming convention
			# all will use the same root res for now
			$root_name=$::image_name . "_root"; 

			# see if it's already defined
        	if (grep(/^$root_name$/, @::nimresources)) {
				my $rsp;
				push @{$rsp->{data}}, "Using existing root resource named \'$root_name\'.\n";
				xCAT::MsgUtils->message("I", $rsp, $callback);
        	} else {
				# it doesn't exist so create it
				my $type="root";
				if (&mknimres($root_name, $type, $callback) != 0) {
					my $rsp;
					push @{$rsp->{data}}, "Could not create a NIM definition for \'$root_name\'.\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
					return 1;
				}
			}
		} # end root res
		chomp $root_name;
		$newres{root} = $root_name;

		#
		# dump res
		#
		my $dump_name;
		if ( $::attrres{dump} ) {

        	# if provided then use it
        	$dump_name=$::attrres{dump};

		} elsif ($::opt_i) {

        	# if one is provided in osimage 
        	if ($::imagedef{$::opt_i}{dump}) {
            	$dump_name=$::imagedef{$::opt_i}{dump};
        	}

    	} else {

			# may need to create new one
			# all use the same dump res unless another is specified
			$dump_name= $::image_name . "_dump";
			# see if it's already defined
        	if (grep(/^$dump_name$/, @::nimresources)) {
				my $rsp;
				push @{$rsp->{data}}, "Using existing dump resource named \'$dump_name\'.\n";
				xCAT::MsgUtils->message("I", $rsp, $callback);
        	} else {
				# create it
				my $type="dump";
				if (&mknimres($dump_name, $type, $callback) != 0) {
					my $rsp;
					push @{$rsp->{data}}, "Could not create a NIM definition for \'$dump_name\'.\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
					return 1;
				}
			}
		} # end dump res
		chomp $dump_name;
        $newres{dump} = $dump_name;

		#
		# paging res
		#
		my $paging_name;
		if ( $::attrres{paging} ) {

        	# if provided then use it
        	$paging_name=$::attrres{paging};

		} elsif ($::opt_i) {

        	# if one is provided in osimage and we don't want a new one
        	if ($::imagedef{$::opt_i}{paging}) {
            	$paging_name=$::imagedef{$::opt_i}{paging};
        	}

    	} else {
			# create it
			# only if type diskless
			my $nimtype;
			if ($::NIMTYPE) {
				$nimtype = $::NIMTYPE;
			} else {
				$nimtype = "diskless";
			}
			chomp $nimtype;
		
			if ($nimtype eq "diskless" ) {

				$paging_name= $::image_name . "_paging";

				# see if it's already defined
        		if (grep(/^$paging_name$/, @::nimresources)) {
					my $rsp;
					push @{$rsp->{data}}, "Using existing paging resource named \'$paging_name\'.\n";
					xCAT::MsgUtils->message("I", $rsp, $callback);
        		} else {
					# it doesn't exist so create it
					my $type="paging";
					if (&mknimres($paging_name, $type, $callback) != 0) {
						my $rsp;
						push @{$rsp->{data}}, "Could not create a NIM definition for \'$paging_name\'.\n";
						xCAT::MsgUtils->message("E", $rsp, $callback);
						return 1;
					}
				}
			}
		} # end paging res
		chomp $paging_name;
        $newres{paging} = $paging_name;

		# end diskless section 

	} elsif ( $::NIMTYPE eq "standalone") {

		#
        # create bosinst_data
		#
		$bosinst_data_name = &mk_bosinst_data($callback);
        chomp $bosinst_data_name;
        $newres{bosinst_data} = $bosinst_data_name;
        if ( !defined($bosinst_data_name)) {
			my $rsp;
            push @{$rsp->{data}}, "Could not create bosinst_data definition.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }

		#
        # create resolv_conf
		#
		$resolv_conf_name = &mk_resolv_conf($callback);
        chomp $resolv_conf_name;
        $newres{resolv_conf} = $resolv_conf_name;
        if ( !defined($resolv_conf_name)) {
            # error
			my $rsp;
            push @{$rsp->{data}}, "Could not create resolv_conf definition.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }

		if ($::METHOD eq "rte" ) {

			# need lpp_source, spot, resolv_conf, & bosinst_data
			# user can specify others

			# must have a source and a name
			if (!($::opt_s) || !defined($::image_name) ) {
				my $rsp;
				push @{$rsp->{data}}, "The image name and -s option are required.\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
				&mknimimage_usage($callback);
				return 1;
			}

			#
			# get lpp_source
			#
			$lpp_source_name = &mk_lpp_source($callback);
			chomp $lpp_source_name;
			$newres{lpp_source} = $lpp_source_name;
			if ( !defined($lpp_source_name)) {
				my $rsp;
                push @{$rsp->{data}}, "Could not create lpp_source definition.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
			}

			#
			# get spot resource
			#
			$spot_name=&mk_spot($lpp_source_name, $callback);
			chomp $spot_name;
			$newres{spot} = $spot_name;
			if ( !defined($spot_name)) {
				my $rsp;
                push @{$rsp->{data}}, "Could not create spot definition.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
			}

		} elsif ($::METHOD eq "mksysb" ) {

			# need mksysb, resolv_conf, & bosinst_data
			# user provides SPOT
            # user can specify others
			#
			# get mksysb resource
			#
			$mksysb_name=&mk_mksysb($callback);
            chomp $mksysb_name;
            $newres{mksysb} = $mksysb_name;
            if ( !defined($mksysb_name)) {
				my $rsp;
				push @{$rsp->{data}}, "Could not create mksysb definition.\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
				return 1;
            }
		} 
	}

	#
	# Put together the osimage def information
	#
	$osimagedef{$::image_name}{objtype}="osimage";
    $osimagedef{$::image_name}{imagetype}="NIM";
    $osimagedef{$::image_name}{osname}="AIX";
    $osimagedef{$::image_name}{nimtype}=$::NIMTYPE;
	if ($::METHOD) {
		$osimagedef{$::image_name}{nimmethod}=$::METHOD;
	}

	# get resources from the original osimage if provided
	if ($::opt_i) {

		foreach my $type (keys %{$::imagedef{$::opt_i}}) {

            if (grep(/^$::imagedef{$::opt_i}{$type}$/, @::nimresources)) {
                # if this is a resource then add it to the new osimage
				# ex. type=spot, name = myspot
                $osimagedef{$::image_name}{$type}=$::imagedef{$::opt_i}{$type};
            }
        }
	}

	if (defined(%newres)) {

		# overlay/add the resources defined above
		foreach my $type (keys %newres) {
			$osimagedef{$::image_name}{$type}=$newres{$type};
		}
	}

	if (defined(%::attrres)) {

		# add overlay/any additional from the cmd line if provided
		foreach my $type (keys %::attrres) {
			if (grep(/^$type$/, @::nimresources)) {
				$osimagedef{$::image_name}{$type}=$::attrres{$type};
			}
		}
	}

	# create the osimage def
	if (xCAT::DBobjUtils->setobjdefs(\%osimagedef) != 0)
    {
        my $rsp;
        $rsp->{data}->[0] = "Could not create xCAT osimage definition.\n";
		xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 1;
    }

	#
	# Output results
	#
	#
	my $rsp;
	push @{$rsp->{data}}, "The following xCAT osimage definition was created. Use the xCAT lsdef command \nto view the xCAT definition and the AIX lsnim command to view the individual \nNIM resources that are included in this definition.";

	push @{$rsp->{data}}, "\nObject name: $::image_name";

	foreach my $attr (sort(keys %{$osimagedef{$::image_name}}))
	{
		if ($attr eq 'objtype') {
			next;
		}
		push @{$rsp->{data}}, "\t$attr=$osimagedef{$::image_name}{$attr}";
	}
	xCAT::MsgUtils->message("I", $rsp, $callback);

	return 0;

} # end mknimimage

#----------------------------------------------------------------------------

=head3   mk_lpp_source

        Create a NIM   resource.

        Returns:
                lpp_source name -ok
                undef - error
=cut

#-----------------------------------------------------------------------------
sub mk_lpp_source
{
	my $callback = shift;

	my @lppresources;
	my $lppsrcname;

	#
    #  Get a list of the defined lpp_source resources
    #
    my $cmd = qq~/usr/sbin/lsnim -t lpp_source | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    @lppresources = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC  != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get NIM lpp_source definitions.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return undef;
    }

	#
	# get an lpp_source resource to use
	#
	if ( $::attrres{lpp_source} ) { 

		# if lpp_source provided then use it
		$lppsrcname=$::attrres{lpp_source};

	} elsif ($::opt_i) { 

		# if we have lpp_source name in osimage def then use that
		if ($::imagedef{$::opt_i}{lpp_source}) {
			$lppsrcname=$::imagedef{$::opt_i}{lpp_source};
		} else {
			my $rsp;
			push @{$rsp->{data}}, "The $::opt_i image definition did not contain a value for lpp_source.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return undef;
		}

	} elsif ($::opt_s) { 

		# if source is provided we may need to create a new lpp_source

		#   make a name using the convention and check if it already exists
		$lppsrcname= $::image_name . "_lpp_source";

		if (grep(/^$lppsrcname$/, @lppresources)) {
			my $rsp;
			push @{$rsp->{data}}, "Using the existing lpp_source named \'$lppsrcname\'\n";
			xCAT::MsgUtils->message("I", $rsp, $callback);
		} else {

			# create a new one

			# the source could be a directory or an existing 
			#	lpp_source resource
			if ( !(-d $::opt_s) ) {
				# if it's not a directory then is it the name of 
				#	an existing lpp_source?
				if (!(grep(/^$::opt_s$/, @lppresources))) {
					my $rsp;
					push @{$rsp->{data}}, "\'$::opt_s\' is not a source directory or the name of a NIM lpp_source resource.\n";
               		xCAT::MsgUtils->message("E", $rsp, $callback);
               		&mknimimage_usage($callback);
               		return undef;
				}
			}
			
			my $loc;
			if ($::opt_l) {
				$loc = "$::opt_l/$lppsrcname";
			} else {
				$loc = "/install/nim/lpp_source/$lppsrcname";
			}
			
			# create resource location 
            my $cmd = "/usr/bin/mkdir -p $loc";
            my $output = xCAT::Utils->runcmd("$cmd", -1);
            if ($::RUNCMD_RC  != 0) {
                my $rsp;
                push @{$rsp->{data}}, "Could not create $loc.\n";
                if ($::VERBOSE) {
                    push @{$rsp->{data}}, "$output\n";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return undef;
            }

			# check the file system space needed ????
			#  about 1500 MB for a basic lpp_source???
			my $lppsize = 1500;
            if (&chkFSspace($loc, $lppsize, $callback) != 0) {
				return undef;
            }

			# build an lpp_source 
			my $rsp;
			push @{$rsp->{data}}, "Creating a NIM lpp_source resource called \'$lppsrcname\'.  This could take a while.\n";
			xCAT::MsgUtils->message("I", $rsp, $callback);

			# make cmd
			my $lpp_cmd = "/usr/sbin/nim -Fo define -t lpp_source -a server=master ";
			# where to put it - the default is /install
			$lpp_cmd .= "-a location=$loc ";

			$lpp_cmd .= "-a source=$::opt_s $lppsrcname";
			my $output = xCAT::Utils->runcmd("$lpp_cmd", -1);
   			if ($::RUNCMD_RC  != 0)
   			{
       			my $rsp;
       			push @{$rsp->{data}}, "Could not run command \'$lpp_cmd\'. (rc = $::RUNCMD_RC)\n";
       			xCAT::MsgUtils->message("E", $rsp, $callback);
   				return undef;
   			}
		}
	} else {
		my $rsp;
		push @{$rsp->{data}}, "Could not get an lpp_source resource for this diskless image.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return undef;
	} 

	return $lppsrcname;
}

#----------------------------------------------------------------------------

=head3   mk_spot

        Create a NIM   resource.

        Returns:
               OK - spot name
               error - undef
=cut

#-----------------------------------------------------------------------------
sub mk_spot
{
	my $lppsrcname = shift;
    my $callback = shift;

	my $spot_name;
	my $currentimage;

		if ( $::attrres{spot} ) { 

			# if spot provided then use it
        	$spot_name=$::attrres{spot};

    	} elsif ($::opt_i) {
			# copy the spot named in the osimage def

			# use the image name for the new SPOT/COSI name
			$spot_name=$::image_name;
	
			if ($::imagedef{$::opt_i}{spot}) {
				# a spot was provided as a source so copy it to create a new one 
				my $cpcosi_cmd = "/usr/sbin/cpcosi ";

				# name of cosi to copy
				$currentimage=$::imagedef{$::opt_i}{spot};
				chomp $currentimage;
            	$cpcosi_cmd .= "-c $currentimage ";

				# do we want verbose output?
				if ($::VERBOSE) {
					$cpcosi_cmd .= "-v ";
				}

				# where to put it - the default is /install
				if ($::opt_l) {
					$cpcosi_cmd .= "-l $::opt_l ";
				} else {
					$cpcosi_cmd .= "-l /install/nim/spot  ";
				}

            	$cpcosi_cmd .= "$spot_name  2>&1";

				# run the cmd
				my $rsp;
				push @{$rsp->{data}}, "Creating a NIM SPOT resource. This could take a while.\n";
				xCAT::MsgUtils->message("I", $rsp, $callback);

				if ($::VERBOSE) {
					my $rsp;
					push @{$rsp->{data}}, "Running: \'$cpcosi_cmd\'\n";
					xCAT::MsgUtils->message("I", $rsp, $callback);
				}
				my $output = xCAT::Utils->runcmd("$cpcosi_cmd", -1);
				if ($::RUNCMD_RC  != 0)
				{
					my $rsp;
					push @{$rsp->{data}}, "Could not create a NIM definition for \'$spot_name\'.\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
					return undef;
				}
			} else {
				my $rsp;
				push @{$rsp->{data}}, "The $::opt_i image definition did not contain a value for a SPOT resource.\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
            	return undef;
        	}

		} else {

			# create a new spot from the lpp_source 

			# use the image name for the new SPOT/COSI name
			$spot_name=$::image_name;

        	if (grep(/^$spot_name$/, @::nimresources)) {
            	my $rsp;
            	push @{$rsp->{data}}, "Using the existing SPOT named \'$spot_name\'.\n";
            	xCAT::MsgUtils->message("I", $rsp, $callback);
        	} else {

				# Create the SPOT/COSI
				my $cmd = "/usr/sbin/nim -o define -t spot -a server=master ";

				# source of images
				$cmd .= "-a source=$lppsrcname ";

				# where to put it - the default is /install
				my $loc;
				if ($::opt_l) {
					$cmd .= "-a location=$::opt_l ";
					$loc = "$::opt_l";
				} else {
					$cmd .= "-a location=/install/nim/spot  ";
					$loc = "/install/nim/spot";
				}

				# create resource location
                my $mkdircmd = "/usr/bin/mkdir -p $loc";
                my $output = xCAT::Utils->runcmd("$mkdircmd", -1);
                if ($::RUNCMD_RC  != 0) {
                    my $rsp;
                    push @{$rsp->{data}}, "Could not create $loc.\n";
                    if ($::VERBOSE) {
                        push @{$rsp->{data}}, "$output\n";
                    }
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return undef;
                }

				# check the file system space needed 
				#	500 MB for spot ?? 64MB for tftpboot???
				my $spotsize = 500;
                if (&chkFSspace($loc, $spotsize, $callback) != 0) {
                	# error
					return undef;
                }

				$loc = "/tftpboot";
				# create resource location
                my $mkdircmd = "/usr/bin/mkdir -p $loc";
                my $output = xCAT::Utils->runcmd("$mkdircmd", -1);
                if ($::RUNCMD_RC  != 0) {
                    my $rsp;
                    push @{$rsp->{data}}, "Could not create $loc.\n";
                    if ($::VERBOSE) {
                        push @{$rsp->{data}}, "$output\n";
                    }
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return undef;
                }
				my $tftpsize = 64;
				if (&chkFSspace($loc, $tftpsize, $callback) != 0) {
                    # error
					return undef;
                }

				$cmd .= "$spot_name  2>&1";
				# run the cmd
				my $rsp;
				push @{$rsp->{data}}, "Creating a NIM SPOT resource. This could take a while.\n";
				xCAT::MsgUtils->message("I", $rsp, $callback);

				my $output = xCAT::Utils->runcmd("$cmd", -1);
				if ($::RUNCMD_RC  != 0)
				{
					my $rsp;
					push @{$rsp->{data}}, "Could not create a NIM definition for \'$spot_name\'.\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
					return undef;
				}
			} # end - if spot doesn't exist
		}

    return $spot_name;
}


#----------------------------------------------------------------------------

=head3   mk_bosinst_data

        Create a NIM   resource.

        Returns:
                0 - OK
                1 - error
=cut

#-----------------------------------------------------------------------------
sub mk_bosinst_data
{
    my $callback = shift;

	my $bosinst_data_name = $::image_name . "_bosinst_data";

    if ( $::attrres{bosinst_data} ) {

        # if provided then use it
        $bosinst_data_name=$::attrres{bosinst_data};

	} elsif ($::opt_i) {

        # if one is provided in osimage and we don't want a new one
        if ($::imagedef{$::opt_i}{bosinst_data}) {
            $bosinst_data_name=$::imagedef{$::opt_i}{bosinst_data};
        }

    } else {

		# see if it's already defined
		if (grep(/^$bosinst_data_name$/, @::nimresources)) {
			my $rsp;
			push @{$rsp->{data}}, "Using existing bosinst_data resource named \'$bosinst_data_name\'.\n";
			xCAT::MsgUtils->message("I", $rsp, $callback);
		} else {

			my $loc;
			if ($::opt_l) {
				$loc = $::opt_l;
			} else {
				$loc = "/install/nim/bosinst_data";
			}

			my $cmd = "mkdir -p $loc";

           	my $output = xCAT::Utils->runcmd("$cmd", -1);
           	if ($::RUNCMD_RC  != 0) {
                my $rsp;
                push @{$rsp->{data}}, "Could not create a NIM definition for \'$bosinst_data_name\'.\n";
				if ($::VERBOSE) {
                    push @{$rsp->{data}}, "$output\n";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
				return undef;
            }

			# copy/modify the template supplied by NIM
			my $sedcmd = "/usr/bin/sed 's/CONSOLE = .*/CONSOLE = Default/; s/INSTALL_METHOD = .*/INSTALL_METHOD = overwrite/; s/PROMPT = .*/PROMPT = no/; s/EXISTING_SYSTEM_OVERWRITE = .*/EXISTING_SYSTEM_OVERWRITE = yes/; s/RECOVER_DEVICES = .*/RECOVER_DEVICES = no/; s/ACCEPT_LICENSES = .*/ACCEPT_LICENSES = yes/; s/DESKTOP = .*/DESKTOP = NONE/' /usr/lpp/bosinst/bosinst.template >$loc/$bosinst_data_name";

			my $output = xCAT::Utils->runcmd("$sedcmd", -1);
			if ($::RUNCMD_RC  != 0) {
				my $rsp;
				push @{$rsp->{data}}, "Could not create bosinst_data file.\n";
				if ($::VERBOSE) {
					push @{$rsp->{data}}, "$output\n";
				}
				xCAT::MsgUtils->message("E", $rsp, $callback);
                return undef;
			}

			# define the new resolv_conf resource
			my $cmd = "/usr/sbin/nim -o define -t bosinst_data -a server=master ";
			$cmd .= "-a location=$loc/$bosinst_data_name  ";
			$cmd .= "$bosinst_data_name  2>&1";

			if ($::VERBOSE) {
                my $rsp;
                push @{$rsp->{data}}, "Running: \'$cmd\'\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }

			my $output = xCAT::Utils->runcmd("$cmd", -1);
			if ($::RUNCMD_RC  != 0) {
				my $rsp;
				push @{$rsp->{data}}, "Could not create a NIM definition for \'$bosinst_data_name\'.\n";
				if ($::VERBOSE) {
                    push @{$rsp->{data}}, "$output\n";
                }
				xCAT::MsgUtils->message("E", $rsp, $callback);
				return undef;
			}
		}
	} 

    return $bosinst_data_name;
}

#----------------------------------------------------------------------------

=head3   mk_resolv_conf

        Create a NIM   resource.

        Returns:
                0 - OK
                1 - error
=cut

#-----------------------------------------------------------------------------
sub mk_resolv_conf
{
    my $callback = shift;

	my $resolv_conf_name = $::image_name . "_resolv_conf";

    if ( $::attrres{resolv_conf} ) {

        # if provided then use it
        $resolv_conf_name=$::attrres{resolv_conf};

	} elsif ($::opt_i) {

        # if one is provided in osimage and we don't want a new one
        if ($::imagedef{$::opt_i}{resolv_conf}) {
            $resolv_conf_name=$::imagedef{$::opt_i}{resolv_conf};
        }

    } else {

		# see if it's already defined
		if (grep(/^$resolv_conf_name$/, @::nimresources)) {
			my $rsp;
			push @{$rsp->{data}}, "Using existing resolv_conf resource named \'$resolv_conf_name\'.\n";
			xCAT::MsgUtils->message("I", $rsp, $callback);
		} elsif ( -e "/etc/resolv.conf")  {

			# use the resolv.conf file to create a res if it exists
			my $loc;
			if ($::opt_l) {
				$loc = $::opt_l;
			} else {
				$loc = "/install/nim/resolv_conf/$resolv_conf_name";
			}

			my $cmd = "mkdir -p $loc; cp /etc/resolv.conf $loc/resolv.conf";

           my $output = xCAT::Utils->runcmd("$cmd", -1);
           if ($::RUNCMD_RC  != 0) {
                my $rsp;
                push @{$rsp->{data}}, "Could not create a NIM definition for \'$resolv_conf_name\'.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
				return undef;
            }

			# define the new resolv_conf resource
			my $cmd = "/usr/sbin/nim -o define -t resolv_conf -a server=master ";
			$cmd .= "-a location=$loc/resolv.conf  ";
			$cmd .= "$resolv_conf_name  2>&1";

			if ($::VERBOSE) {
                my $rsp;
                push @{$rsp->{data}}, "Running: \'$cmd\'\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }

			my $output = xCAT::Utils->runcmd("$cmd", -1);
			if ($::RUNCMD_RC  != 0) {
				my $rsp;
				push @{$rsp->{data}}, "Could not create a NIM definition for \'$resolv_conf_name\'.\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
				return undef;
			}
		} else {
			my $rsp;
			push @{$rsp->{data}}, "Could not create a NIM definition for \'$resolv_conf_name\'.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return undef;
		}
	} # end resolv_conf res

    return $resolv_conf_name;

}

#----------------------------------------------------------------------------

=head3   mk_mksysb

        Create a NIM   resource.

        Returns:
                0 - OK
                1 - error
=cut

#-----------------------------------------------------------------------------
sub mk_mksysb
{
    my $callback = shift;

	my $mksysb_name = $::image_name . "_mksysb";

	if ( $::attrres{mksysb} ) {

        # if provided on cmd line then use it
        $mksysb_name=$::attrres{mksysb};

    } else {
		# see if it's already defined
        if (grep(/^$mksysb_name$/, @::nimresources)) {
            my $rsp;
            push @{$rsp->{data}}, "Using existing mksysb resource named \'$mksysb_name\'.\n";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        } else {

			# create the mksysb definition

			if ($::MKSYSBNODE) {

				my $loc;
            	if ($::opt_l) {
                	$loc = $::opt_l;
            	} else {
					$loc = "/install/nim/mksysb/$::image_name";
            	}

				# create resource location for mksysb image
				my $cmd = "/usr/bin/mkdir -p $loc";
				my $output = xCAT::Utils->runcmd("$cmd", -1);
            	if ($::RUNCMD_RC  != 0) {
                	my $rsp;
                	push @{$rsp->{data}}, "Could not create $loc.\n";
                	if ($::VERBOSE) {
                    	push @{$rsp->{data}}, "$output\n";
                	}
                	xCAT::MsgUtils->message("E", $rsp, $callback);
                	return undef;
            	}

				# check the file system space needed
				# about 1800 MB for a mksysb image???
				my $sysbsize = 1800;
				if (&chkFSspace($loc, $sysbsize, $callback) != 0) {
					# error
					return undef;
				}

				my $rsp;
				push @{$rsp->{data}}, "Creating a NIM mksysb resource called \'$mksysb_name\'.  This could take a while.\n";
				xCAT::MsgUtils->message("I", $rsp, $callback);

				# create sys backup from remote node and define res
				my $location = "$loc/$mksysb_name";
				my $nimcmd = "/usr/sbin/nim -o define -t mksysb -a server=master -a location=$location -a mk_image=yes -a source=$::MKSYSBNODE $mksysb_name 2>&1";

				my $output = xCAT::Utils->runcmd("$nimcmd", -1);
            	if ($::RUNCMD_RC  != 0) {
                	my $rsp;
                	push @{$rsp->{data}}, "Could not define mksysb resource named \'$mksysb_name\'.\n";
                	if ($::VERBOSE) {
                    	push @{$rsp->{data}}, "$output\n";
                	}
                	xCAT::MsgUtils->message("E", $rsp, $callback);
                	return undef;
            	}

			} elsif ($::SYSB) {

				# def res with existing mksysb image
				my $mkcmd = "/usr/sbin/nim -o define -t mksysb -a server=master -a location=$::SYSB $mksysb_name 2>&1";

				if ($::VERBOSE) {
                    my $rsp;
                    push @{$rsp->{data}}, "Running: \'$mkcmd\'\n";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }

				my $output = xCAT::Utils->runcmd("$mkcmd", -1);
				if ($::RUNCMD_RC  != 0) {
					my $rsp;
					push @{$rsp->{data}}, "Could not define mksysb resource named \'$mksysb_name\'.\n";
					if ($::VERBOSE) {
						push @{$rsp->{data}}, "$output\n";
					}
					xCAT::MsgUtils->message("E", $rsp, $callback);
					return undef;
				}
			}
		}
	}

    return $mksysb_name;
}

#----------------------------------------------------------------------------

=head3   rmnimimage

		Support for the rmnimimage command.

		Removes an AIX/NIM diskless image - referred to as a SPOT or COSI.

		Arguments:
		Returns:
				0 - OK
				1 - error
		Globals:

		Error:

		Example:

		Comments:

			rmnimimage [-V] [-f|--force] image_name
=cut

#-----------------------------------------------------------------------------
sub rmnimimage
{
	my $callback = shift;

	if (defined(@{$::args})) {
        @ARGV = @{$::args};
    } else {
		&rmnimimage_usage($callback);
        return 0;
    }	

    # parse the options
    Getopt::Long::Configure("no_pass_through");
    if(!GetOptions(
        'f|force'   => \$::FORCE,
        'h|help'    => \$::HELP,
        'verbose|V' => \$::VERBOSE,
        'v|version' => \$::VERSION,))
    {

        &rmnimimage_usage($callback);
        return 1;
    }

    # display the usage if -h or --help is specified
    if ($::HELP) {
        &rmnimimage_usage($callback);
        return 0;
	}

	# display the version statement if -v or --verison is specified
    if ($::VERSION)
    {
		my $version=xCAT::Utils->Version();
        my $rsp;
        push @{$rsp->{data}}, "rmnimimage $version\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return 0;
    }

	my $image_name = shift @ARGV;

    # must have an image name
    if (!defined($image_name) ) {
        my $rsp;
        push @{$rsp->{data}}, "The xCAT osimage name is required.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        &rmnimimage_usage($callback);
        return 1;
    }

	# get the xCAT image definition 
	my %imagedef;
	my %objtype;
	$objtype{$image_name} = 'osimage';
	%imagedef = xCAT::DBobjUtils->getobjdefs(\%objtype,$callback);
	if (!defined(%imagedef)) {
		my $rsp;
 		push @{$rsp->{data}}, "Could not get xCAT image definition.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}

	#
	#  Get a list of the all nim resources
	#
	my $cmd = qq~/usr/sbin/lsnim -c resources | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
	my @nimresources = [];
	@nimresources = xCAT::Utils->runcmd("$cmd", -1);
	if ($::RUNCMD_RC  != 0)
	{
		my $rsp;
        push @{$rsp->{data}}, "Could not get NIM resource definitions.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
	}

	my $rsp;
	push @{$rsp->{data}}, "Removing NIM resource definitions. This could take a while!";
	xCAT::MsgUtils->message("I", $rsp, $callback);

	# foreach attr in the image def
	my $error;
	foreach my $attr (sort(keys %{$imagedef{$image_name}}))
    {
        if ($attr eq 'objtype') {
            next;
        }

		my $resname = $imagedef{$image_name}{$attr};
		# if it's a defined resource name we can try to remove it
		if ( ($resname)  && (grep(/^$resname$/, @nimresources))) {

			# is it allocated?
			my $alloc_count = &get_nim_attr_val($resname, "alloc_count", $callback);

			if ( defined($alloc_count) && ($alloc_count != 0) ){
				my $rsp;
				push @{$rsp->{data}}, "The resource named \'$resname\' is currently allocated. It will not be removed.\n";
				xCAT::MsgUtils->message("I", $rsp, $callback);
				next;
			}

			# try to remove it
			my $cmd = "nim -o remove $resname";

			my $output;
		    $output = xCAT::Utils->runcmd("$cmd", -1);
		    if ($::RUNCMD_RC  != 0)
       		{
				my $rsp;
				push @{$rsp->{data}}, "Could not remove the NIM resource definition \'$resname\'.\n";
				push @{$rsp->{data}}, "$output";
				xCAT::MsgUtils->message("E", $rsp, $callback);
				$error++;
				next;
			} else {
				my $rsp;
				push @{$rsp->{data}}, "Removed the NIM resource named \'$resname\'.\n";
				xCAT::MsgUtils->message("I", $rsp, $callback);

			}
		}

	}


	#	
	# remove the osimage def 
	#
	my %objhash;
	$objhash{$image_name} = "osimage";
	if (xCAT::DBobjUtils->rmobjdefs(\%objhash) != 0) {
		my $rsp;
		push @{$rsp->{data}}, "Could not remove the existing xCAT definition for \'$image_name\'.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		$error++;
	} else {
		my $rsp;
		push @{$rsp->{data}}, "Removed the xCAT osimage definition \'$image_name\'.\n";
		xCAT::MsgUtils->message("I", $rsp, $callback);
	}	

	if ($error) {
		my $rsp;
		push @{$rsp->{data}}, "One or more errors occurred when trying to remove the xCAT osimage definition \'$image_name\' and the related NIM resources.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}

	return 0;
}

#-------------------------------------------------------------------------

=head3   mkScriptRes

   Description
		- define NIM script resource if needed
   Arguments:    None.
   Return Codes: 0 - All was successful.
                 1 - An error occured.
=cut

#------------------------------------------------------------------------
sub mkScriptRes
{
	my $resname = shift;
	my $respath = shift;
	my $callback = shift;

    my ($cmd, $output, $rc);

    my $defcmd = "lsnim -t script | grep \"$resname \" || nim -o define -t script -a server=master -a location=$respath $resname";

    my $output = xCAT::Utils->runcmd("$defcmd", -1);
    if ($::RUNCMD_RC != 0)
    {
		if ($::VERBOSE) {
			my $rsp;
            push @{$rsp->{data}}, "$output";
			xCAT::MsgUtils->message("E", $rsp, $callback);
        }
        return 1;
    }
    return 0;
}

#-------------------------------------------------------------------------

=head3   update_rhosts

   Description
         - add node entries to the /.rhosts file on the server
			- AIX only

   Arguments:    None.

   Return Codes: 0 - All was successful.
                 1 - An error occured.
=cut

#------------------------------------------------------------------------
sub update_rhosts 
{
	my $nodelist = shift;
	my $callback = shift;

	my $rhostname ="/.rhosts";
	my @addnodes;

	# make a list of node entries to add
	foreach my $node (@$nodelist) {

		# get the node IP for the file entry
		# TODO - need IPv6 update
		my $IP = inet_ntoa(inet_aton($node));
		chomp $IP;
		unless ($IP =~ /\d+\.\d+\.\d+\.\d+/)
		{
			my $rsp;
			push @{$rsp->{data}}, "Could not get valid IP address for node $node.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			next;
		}

		# is this node already in the file
		my $entry = "$IP root";
		my $cmd = "cat $rhostname | grep $IP";
    	my @result = xCAT::Utils->runcmd("$cmd", -1);
    	if ($::RUNCMD_RC == 0)
    	{
        	# it's already there so next
        	next;
    	}
		push @addnodes, $entry;
	}

	if (defined(@addnodes)) {
		# add the new entries to the file
    	unless (open(RHOSTS, ">>$rhostname")) {
        	my $rsp;
        	push @{$rsp->{data}}, "Could not open $rhostname for appending.\n";
        	xCAT::MsgUtils->message("E", $rsp, $callback);
        	return 1;
    	}
		foreach (@addnodes) {
    		print RHOSTS $_ . "\n";
		}

    	close (RHOSTS);
	}
    return 0;
}

#-------------------------------------------------------------------------

=head3   update_inittab  
		 - add an entry for xcatdsklspost to /etc/inittab    
                                                                         
   Description:  This function updates the /etc/inittab file. 
                                                                         
   Arguments:    None.                                                   
                                                                         
   Return Codes: 0 - All was successful.                                 
                 1 - An error occured.                                   
=cut

#------------------------------------------------------------------------
sub update_inittab
{
	my $spot_loc = shift;
	my $callback = shift;
    my ($cmd, $rc, $entry);

	my $spotinittab = "$spot_loc/lpp/bos/inst_root/etc/inittab";

	my $entry = "xcat:2:wait:/opt/xcat/xcataixpost\n";

	# see if xcataixpost is already in the file
	my $cmd = "cat $spotinittab | grep xcataixpost";
	my @result = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC == 0)
    {
		# it's already there so return
		return 0;
    }

	unless (open(INITTAB, ">>$spotinittab")) {
		my $rsp;
		push @{$rsp->{data}}, "Could not open $spotinittab for appending.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}

	print INITTAB $entry;

	close (INITTAB);

	return 0;
}
#----------------------------------------------------------------------------

=head3  get_nim_attr_val

        Use the lsnim command to find the value of a resource attribute.

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
sub get_nim_attr_val {

	my $resname = shift;
	my $attrname = shift;
	my $callback = shift;

	my $cmd = "/usr/sbin/lsnim -l $resname";

	my @result = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC  != 0)
    {
		my $rsp;
        push @{$rsp->{data}}, "Could not run lsnim command.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	foreach (@result){
		my ($attr,$value) = split('=');
		chomp $attr;
		$attr =~ s/\s*//g;  # remove blanks
		chomp $value;
		$value =~ s/^\s*//;
		if ($attr eq $attrname) {
			return $value;
		}
	}
	return undef;
}


#----------------------------------------------------------------------------

=head3  get_res_loc

        Use the lsnim command to find the location of a spot resource.

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
sub get_res_loc {

	my $spotname = shift;
	my $callback = shift;

	my $cmd = "/usr/sbin/lsnim -l $spotname";

	my @result = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC  != 0)
    {
		my $rsp;
        push @{$rsp->{data}}, "Could not run lsnim command.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	foreach (@result){
		my ($attr,$value) = split('=');
		chomp $attr;
		$attr =~ s/\s*//g;  # remove blanks
		chomp $value;
		$value =~ s/\s*//g;  # remove blanks
		if ($attr eq 'location') {
			return $value;
		}
	}
	return undef;
}
#----------------------------------------------------------------------------

=head3  chkFSspace
	
	See if there is enough space in file systems. If not try to increase 
	the size.

        Arguments:
        Returns:
                0 - OK
                1 - error
=cut

#-----------------------------------------------------------------------------
sub chkFSspace {
	my $location = shift;
    my $size = shift;
    my $callback = shift;

# TODO - test this !!!

	# get free space
    # ex. 1971.06 (Free MB)
    my $dfcmd = qq~/usr/bin/df -m $location | /usr/bin/awk '(NR==2){print \$3":"\$7}'~;

    my $output;
    $output = xCAT::Utils->runcmd("$dfcmd", -1);
    if ($::RUNCMD_RC  != 0) {
        my $rsp;
        push @{$rsp->{data}}, "Could not run: \'$dfcmd\'\n";
        if ($::VERBOSE) {
            push @{$rsp->{data}}, "$output";
        }
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	my ($free_space, $FSname) = split(':', $output);

	#
    #  see if we need to increase the size of the fs
    #
	my $space_needed;
    if ( $size >= $free_space) {

		$space_needed = int ($size - $free_space);
		my $addsize = $space_needed+10;
		my $sizeattr = "-a size=+$addsize" . "M";
        my $chcmd = "/usr/sbin/chfs $sizeattr $FSname";

        my $output;
        $output = xCAT::Utils->runcmd("$chcmd", -1);
        if ($::RUNCMD_RC  != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not increase file system size for \'$FSname\'. Additonal $addsize MB is needed.\n";
            if ($::VERBOSE) {
                push @{$rsp->{data}}, "$output";
            }
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
	}
	return 0;
}

#----------------------------------------------------------------------------

=head3  enoughspace

        See if the NIM root resource has enough space to initialize 
			another node.  If not try to add space to the FS.

        Arguments:
        Returns:
                0 - OK
                1 - error
=cut

#-----------------------------------------------------------------------------
sub enoughspace {

	my $spotname = shift;
	my $rootname = shift;
	my $pagingsize = shift;
    my $callback = shift;

	#
	#  how much space do we need for a root dir?
	#

    #  Get the SPOT location ( path to ../usr)
    my $spot_loc = &get_res_loc($spotname, $callback);
    if (!defined($spot_loc) ) {
        my $rsp;
        push @{$rsp->{data}}, "Could not get the location of the SPOT/COSI named $spot_loc.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	# get the inst_root location
	# ex. /install/nim/spot/61cosi/61cosi/usr/lpp/bos/inst_root
	my $spot_root_loc = "$spot_loc/lpp/bos/inst_root";

	# get the size of the SPOTs inst_root dir (ex. 50.45 MB)
	#	 i.e. how much space is used/needed for a new root dir
	my $ducmd = "/usr/bin/du -sm $spot_root_loc | /usr/bin/awk '{print \$1}'";

	my $inst_root_size;
	$inst_root_size = xCAT::Utils->runcmd("$ducmd", -1);
	if ($::RUNCMD_RC  != 0) {
		my $rsp;
		push @{$rsp->{data}}, "Could not run: \'$ducmd\'\n";
		if ($::VERBOSE) {
			push @{$rsp->{data}}, "$inst_root_size";
		}
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}

	# size needed should be size of root plus size of paging space
	#  - root and paging dirs are in the same FS
	#  - also dump - but that doesn't work for diskless now
	$inst_root_size += $pagingsize;

	#
	#  see how much free space we have in the root res location
	#

	#  Get the root res location 
	#  ex. /export/nim/root
    my $root_loc = &get_res_loc($rootname, $callback);
    if (!defined($root_loc) ) {
        my $rsp;
        push @{$rsp->{data}}, "Could not get the location of the SPOT/COSI named $root_loc.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	# get free space 
	# ex. 1971.06 (Free MB)
	my $dfcmd = qq~/usr/bin/df -m $root_loc | /usr/bin/awk '(NR==2){print \$3":"\$7}'~;

	my $output;
    $output = xCAT::Utils->runcmd("$dfcmd", -1);
    if ($::RUNCMD_RC  != 0) {
        my $rsp;
        push @{$rsp->{data}}, "Could not run: \'$dfcmd\'\n";
        if ($::VERBOSE) {
            push @{$rsp->{data}}, "$output";
        }
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	my ($root_free_space, $FSname) = split(':', $output);

	#
	#  see if we need to increase the size of the fs
	#
	if ( $inst_root_size >= $root_free_space) {
		# try to increase the size of the root dir
		my $addsize = int ($inst_root_size+10);
		my $sizeattr = "-a size=+$addsize" . "M";
		my $chcmd = "/usr/sbin/chfs $sizeattr $FSname";

		my $output;
		$output = xCAT::Utils->runcmd("$chcmd", -1);
		if ($::RUNCMD_RC  != 0)
		{
			my $rsp;
			push @{$rsp->{data}}, "Could not run: \'$chcmd\'\n";
			if ($::VERBOSE) {
				push @{$rsp->{data}}, "$output";
			}
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}
	}

	return 0;
}

#----------------------------------------------------------------------------

=head3  mknimres

       Create a NIM resource

        Returns:
                0 - OK
                1 - error
        Globals:

        Example:
            $rc = &mknimres($res_name, $res_type, $callback);

        Comments:
=cut

#-----------------------------------------------------------------------------
sub mknimres {
    my $res_name = shift;
	my $type = shift;
    my $callback = shift;

	if ($::VERBOSE) {
		my $rsp;
		push @{$rsp->{data}}, "Creating \'$res_name\'.\n";
		xCAT::MsgUtils->message("I", $rsp, $callback);
	}

	my $cmd = "/usr/sbin/nim -o define -t $type -a server=master ";

	# where to put it - the default is /install
	if ($::opt_l) {
		$cmd .= "-a location=$::opt_l ";
	} else {
		$cmd .= "-a location=/install/nim/$type ";
	}
	$cmd .= "$res_name  2>&1";

	if ($::VERBOSE) {
        my $rsp;
        push @{$rsp->{data}}, "Running command: \'$cmd\'.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }
	my $output = xCAT::Utils->runcmd("$cmd", -1);
	if ($::RUNCMD_RC  != 0) {
		return 1;
	}
	return 0;
}

#----------------------------------------------------------------------------

=head3  updatespot

        Update the SPOT resource.

        Returns:
                0 - OK
                1 - error
        Globals:

        Example:
			$rc = &updatespot($spot_name, $lppsrcname, $callback);

        Comments:
=cut

#-----------------------------------------------------------------------------
sub updatespot {
	my $spot_name = shift;
	my $lppsrcname = shift;
    my $callback = shift;

	my $spot_loc;

	my $rsp;
	push @{$rsp->{data}}, "Updating $spot_name.\n";
	xCAT::MsgUtils->message("I", $rsp, $callback);

	#
	#  add rpm.rte to the SPOT 
	#	- it contains gunzip which is needed on the nodes
	#   - also needed if user wants to install RPMs
	#	- assume the source for the spot also has the rpm.rte fileset
	#
	my $cmd = "/usr/sbin/nim -o showres $spot_name | grep rpm.rte";
	my $output = xCAT::Utils->runcmd("$cmd", -1);
	if ($::RUNCMD_RC  != 0) {
		# it's not already installed - so install it

		if ($::VERBOSE) {
        	my $rsp;
        	push @{$rsp->{data}}, "Installing rpm.rte in the image.\n";
        	xCAT::MsgUtils->message("I", $rsp, $callback);
    	}

		my $cmd = "/usr/sbin/chcosi -i -s $lppsrcname -f rpm.rte $spot_name";
		my $output = xCAT::Utils->runcmd("$cmd", -1);
		if ($::RUNCMD_RC  != 0)
		{
			my $rsp;
			push @{$rsp->{data}}, "Could not run command \'$cmd\'. (rc = $::RUNCMD_RC)\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}
	} # end - install rpm.rte

	#
	#  Get the SPOT location ( path to ../usr)
	#
	$spot_loc = &get_res_loc($spot_name, $callback);
	if (!defined($spot_loc) ) {
		my $rsp;
		push @{$rsp->{data}}, "Could not get the location of the SPOT/COSI named $spot_loc.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}

	#
	# Create ODMscript in the SPOT and modify the rc.dd-boot script
	#	- need for rnetboot to work - handles default console setting
	#
	my $odmscript = "$spot_loc/ODMscript";
	if ( !(-e $odmscript)) {
		if ($::VERBOSE) {
        	my $rsp;
        	push @{$rsp->{data}}, "Adding $odmscript to the image.\n";
        	xCAT::MsgUtils->message("I", $rsp, $callback);
    	}

		#  Create ODMscript script
		my $text = "CuAt:\n\tname = sys0\n\tattribute = syscons\n\tvalue = /dev/vty0\n\ttype = R\n\tgeneric =\n\trep = s\n\tnls_index = 0";

		if ( open(ODMSCRIPT, ">$odmscript") ) {
			print ODMSCRIPT $text;
			close(ODMSCRIPT);
		} else {
			my $rsp;
			push @{$rsp->{data}}, "Could not open $odmscript for writing.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}
		my $cmd = "chmod 444 $odmscript";
		my @result = xCAT::Utils->runcmd("$cmd", -1);
		if ($::RUNCMD_RC  != 0)
		{
			my $rsp;
			push @{$rsp->{data}}, "Could not run the chmod command.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}

		# Modify the rc.dd-boot script to set the ODM correctly
		my $boot_file = "$spot_loc/lib/boot/network/rc.dd_boot";
		if (&update_dd_boot($boot_file, $callback) != 0) {
			my $rsp;
			push @{$rsp->{data}}, "Could not update the rc.dd_boot file in the SPOT.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}
	}

	#
	# Copy the xcataixpost script to the SPOT/COSI and add an entry for it
	#	to the /etc/inittab file
	#
	if ($::VERBOSE) {
		my $rsp;
		push @{$rsp->{data}}, "Adding xcataixpost script to the image.\n";
		xCAT::MsgUtils->message("I", $rsp, $callback);
	}

	# copy the script
	my $cpcmd = "mkdir -m 644 -p $spot_loc/lpp/bos/inst_root/opt/xcat; cp /install/postscripts/xcataixpost $spot_loc/lpp/bos/inst_root/opt/xcat/xcataixpost; chmod +x $spot_loc/lpp/bos/inst_root/opt/xcat/xcataixpost";

	if ($::VERBOSE) {
		my $rsp;
		push @{$rsp->{data}}, "Running: \'$cpcmd\'\n";
		xCAT::MsgUtils->message("I", $rsp, $callback);
	}

	my @result = xCAT::Utils->runcmd("$cpcmd", -1);
	if ($::RUNCMD_RC  != 0)
	{
		my $rsp;
        push @{$rsp->{data}}, "Could not copy the xcatdsklspost script to the SPOT.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }	

	# add an entry to the /etc/inittab file in the COSI/SPOT
	if (&update_inittab($spot_loc, $callback) != 0) {
		my $rsp;
        push @{$rsp->{data}}, "Could not update the /etc/inittab file in the SPOT.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
	}

	return 0;
}

#----------------------------------------------------------------------------

=head3   update_dd_boot

         Add the workaround for the default console to rc.dd_boot.

        Returns:
                0 - OK
                1 - error

        Comments:
=cut

#-----------------------------------------------------------------------------
sub update_dd_boot {

	my $dd_boot_file = shift;
	my $callback = shift;

	my @lines;

	# see if orig file exists
	if (-e $dd_boot_file) {

		my $patch = qq~\n\t# xCAT support\n\tif [ -z "\$(odmget -qattribute=syscons CuAt)" ] \n\tthen\n\t  \${SHOWLED} 0x911\n\t  cp /usr/ODMscript /tmp/ODMscript\n\t  [ \$? -eq 0 ] && odmadd /tmp/ODMscript\n\tfi \n\n~;

		# back up the original file
		my $cmd    = "cp -f $dd_boot_file $dd_boot_file.orig";
 		my $output = xCAT::Utils->runcmd("$cmd", -1);
		if ($::RUNCMD_RC  != 0)
		{
			my $rsp;
        	push @{$rsp->{data}}, "Could not copy $dd_boot_file.\n";
        	xCAT::MsgUtils->message("E", $rsp, $callback);
        	return 1;
		}
	
		if ( open(DDBOOT, "<$dd_boot_file") ) {
			@lines = <DDBOOT>;
			close(DDBOOT);
		} else {
			my $rsp;
        	push @{$rsp->{data}}, "Could not open $dd_boot_file for reading.\n";
        	xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}

		# remove the file
		my $cmd    = "rm $dd_boot_file";
		my $output = xCAT::Utils->runcmd("$cmd", -1);
		if ($::RUNCMD_RC  != 0)
    	{
			my $rsp;
        	push @{$rsp->{data}}, "Could not remove original $dd_boot_file.\n";
        	xCAT::MsgUtils->message("E", $rsp, $callback);
        	return 1;
    	}

		# Create a new one
		my $dontupdate=0;
		if ( open(DDBOOT, ">$dd_boot_file") ) {
			foreach my $l (@lines)
			{
				if ($l =~ /xCAT support/) {
					$dontupdate=1;
				}

				if ( ($l =~ /0x620/) && (!$dontupdate) ){
					# add the patch
					print DDBOOT $patch;
				}
				print DDBOOT $l;
			}
			close(DDBOOT);

		} else {
			my $rsp;
        	push @{$rsp->{data}}, "Could not open $dd_boot_file for writing.\n";
        	xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
    	}

		if ($::VERBOSE) {
			my $rsp;
        	push @{$rsp->{data}}, "Updated $dd_boot_file.\n";
        	xCAT::MsgUtils->message("I", $rsp, $callback);
		}

	} else {  # dd_boot file doesn't exist
		return 1;
	}

	return 0;
}

#----------------------------------------------------------------------------

=head3   mkdsklsnode

        Support for the mkdsklsnode command.

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:
        Example:
        Comments:

=cut

#-----------------------------------------------------------------------------
sub mkdsklsnode 
{
	my $callback = shift;
	my $sub_req = shift;

	my $error=0;
	my @nodesfailed;
	my $image_name;

	# some subroutines require a global callback var
	#	- need to change to pass in the callback 
	#	- just set global for now
    $::callback=$callback;

	if (defined(@{$::args})) {
        @ARGV = @{$::args};
    } else {
        &mkdsklsnode_usage($callback);
        return 0;
    }

	# parse the options
	if(!GetOptions(
		'f|force'	=> \$::FORCE,
		'h|help'    => \$::HELP,
		'i=s'       => \$::OSIMAGE,
		'n|new'		=> \$::NEWNAME,
		'verbose|V' => \$::VERBOSE,
		'v|version' => \$::VERSION,))
	{
		&mkdsklsnode_usage($callback);
		return 1;
	}

	if ($::HELP) {
		&mkdsklsnode_usage($callback);
		return 0;
	}

	# display the version statement if -v or --verison is specified
    if ($::VERSION)
    {
		my $version=xCAT::Utils->Version();
        my $rsp;
        push @{$rsp->{data}}, "mkdsklsnode $version\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return 0;
    }

	my @nodelist;
	my %objtype;
	my %objhash;
	my %attrs;

	# the first arg should be a noderange - the other should be attr=val
    #  - put attr=val operands in %attrs hash
    while (my $a = shift(@ARGV))
    {
        if (!($a =~ /=/))
        {
			@nodelist = &noderange($a, 0);
        }
        else
        {
            # if it has an "=" sign its an attr=val - we hope
            my ($attr, $value) = $a =~ /^\s*(\S+?)\s*=\s*(\S*.*)$/;
            if (!defined($attr) || !defined($value))
            {
                my $rsp;
                $rsp->{data}->[0] = "Incorrect \'attr=val\' pair - $a\n";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                return 1;
            }
            # put attr=val in hash
			$attrs{$attr} = $value;
        }
    }

	# get all the attrs for these node definitions
	foreach my $o (@nodelist)
	{
		$objtype{$o} = 'node';
	}
	%objhash = xCAT::DBobjUtils->getobjdefs(\%objtype,$callback);
	if (!defined(%objhash))
	{
		my $rsp;
		push @{$rsp->{data}}, "Could not get xCAT object definitions.\n";
	    xCAT::MsgUtils->message("E", $rsp, $callback);
    	return 1;
	}

	#Get the network info for each node
	my %nethash = xCAT::DBobjUtils->getNetwkInfo(\@nodelist, $callback);
	if (!defined(%nethash))
	{
		my $rsp;
		push @{$rsp->{data}}, "Could not get xCAT network definitions for one or more nodes.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}

   
    #
    #  Get a list of the defined NIM machines
    #
	my @machines = [];
    my $cmd = qq~/usr/sbin/lsnim -c machines | /usr/bin/cut -f1 -d' ' 2>/dev/nu
ll~;

    @machines = xCAT::Utils->runcmd("$cmd", -1);
	# don't fail - maybe just don't have any defined!

	my $error=0;
	my @nodesfailed;
	foreach my $node (keys %objhash)
	{
		# get the image name to use for this node
		# either from cmd line or node def
		if ($::OSIMAGE){
			# from the command line
			$image_name=$::OSIMAGE;
		} elsif ( $objhash{$node}{profile} ) {
			# from the node definition
			$image_name=$objhash{$node}{profile};
		} else {
			my $rsp;
            push @{$rsp->{data}}, "Could not determine an OS image name for node \'$node\'.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
			push(@nodesfailed, $node);
			$error++;
			next;
		}
		chomp $image_name;

		# get the osimage definition
		#  getobjdefs does caching
		my %objtype;
		$objtype{$image_name} = 'osimage';
    	my %imagehash = xCAT::DBobjUtils->getobjdefs(\%objtype,$callback);
		if (!defined(%imagehash))
		{
			my $rsp;
			push @{$rsp->{data}}, "Could not get an osimage definition for \'$image_name\'.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			push(@nodesfailed, $node);
			$error++;
			next;
		}

		# set the NIM machine type
		my $type="diskless";
		if ($imagehash{$image_name}{nimtype} ) {
			$type = $imagehash{$image_name}{nimtype};
		}
		chomp $type;

		if ( ($type =~ /standalone/) ) {
            #error - only support diskless/dataless
            my $rsp;
            push @{$rsp->{data}}, "Use the nimnodeset command to initialize standalone type nodes.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            $error++;
            push(@nodesfailed, $node);
            next;
        }
		
		# generate new NIM client name
		my $nim_name;
		if ($::NEWNAME) {
			# generate a new nim name 
			# "<xcat_node_name>_<image_name>"
			my $name;
			($name = $node) =~ s/\..*$//; # make sure we have the short hostname
			$nim_name=$name . "_" . $image_name;
		} else {
			# the nim name is the short hostname of our node
			($nim_name = $node) =~ s/\..*$//;
		}
		chomp $nim_name;

		# need short host name for NIM cmds 
        my $nodeshorthost;
        ($nodeshorthost = $node) =~ s/\..*$//;
        chomp $nodeshorthost;

		# 
		#  define/initialize the new machine
		#

		# see if it's already defined
		if (grep(/^$nim_name$/, @machines)) { 
			if ($::FORCE) {
				# get rid of the old definition

				#  ???? - does remove alone do the deallocate??
				my $rmcmd = "/usr/sbin/nim -Fo reset $nim_name;/usr/sbin/nim -Fo deallocate -a subclass=all $nim_name;/usr/sbin/nim -Fo remove $nim_name";
				my $output = xCAT::Utils->runcmd("$rmcmd", -1);
				if ($::RUNCMD_RC  != 0) {
					my $rsp;
					push @{$rsp->{data}}, "Could not remove the existing NIM object named \'$nim_name\'.\n";
					if ($::VERBOSE) {
						push @{$rsp->{data}}, "$output";
					}
					xCAT::MsgUtils->message("E", $rsp, $callback);
					$error++;
					push(@nodesfailed, $node);
					next;
				}

			} else { # no force
				my $rsp;
				push @{$rsp->{data}}, "The node \'$node\' is already defined. Use the force option to remove and reinitialize.";
				xCAT::MsgUtils->message("E", $rsp, $callback);
				push(@nodesfailed, $node);
				$error++;
				next;
			}

		} # end already defined

       	# get, check the node IP
		# TODO - need IPv6 update
       	my $IP = inet_ntoa(inet_aton($node));
       	chomp $IP;
       	unless ($IP =~ /\d+\.\d+\.\d+\.\d+/)
       	{
			my $rsp;
			push @{$rsp->{data}}, "Could not get valid IP address for node $node.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			$error++;
			push(@nodesfailed, $node);
			next;
       	}

		# check for required attrs
		if (($type ne "standalone")) {
			# mask, gateway, cosi, root, dump, paging
			if (!$nethash{$node}{'mask'} || !$nethash{$node}{'gateway'} || !$imagehash{$image_name}{spot} || !$imagehash{$image_name}{root} || !$imagehash{$image_name}{dump}) {
				my $rsp;
           		push @{$rsp->{data}}, "Missing required information for node \'$node\'.\n";
           		xCAT::MsgUtils->message("E", $rsp, $callback);
				$error++;
           		push(@nodesfailed, $node);
           		next;
       		}
		}

		# diskless also needs a defined paging res
		if ($type eq "diskless" ) {
			if (!$imagehash{$image_name}{paging} ) {
				my $rsp;
				push @{$rsp->{data}}, "Missing required information for node \'$node\'.\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
				$error++;
				push(@nodesfailed, $node);
				next;
			}
		}	

		# set some default values
		my $speed="100";
       	my $duplex="full";
		if ($attrs{duplex}) {
			$duplex=$attrs{duplex};
		}
		if ($attrs{speed}) {
			$speed=$attrs{speed};
		}

		# define the node 
		my $defcmd = "/usr/sbin/nim -o define -t $type ";
		$defcmd .= "-a if1='find_net $nodeshorthost 0' ";
		$defcmd .= "-a cable_type1=N/A -a netboot_kernel=mp ";
		$defcmd .= "-a net_definition='ent $nethash{$node}{'mask'} $nethash{$node}{'gateway'}' ";
		$defcmd .= "-a net_settings1='$speed $duplex' ";
		$defcmd .= "$nim_name  2>&1";

		if ($::VERBOSE) {
           	my $rsp;
           	push @{$rsp->{data}}, "Creating NIM node definition.\n";
           	push @{$rsp->{data}}, "Running: \'$defcmd\'\n";
           	xCAT::MsgUtils->message("I", $rsp, $callback);
		}

       	my $output = xCAT::Utils->runcmd("$defcmd", -1);
       	if ($::RUNCMD_RC  != 0)
       	{
           	my $rsp;
           	push @{$rsp->{data}}, "Could not create a NIM definition for \'$nim_name\'.\n";
           	if ($::VERBOSE) {
             	push @{$rsp->{data}}, "$output";
           	}
         	xCAT::MsgUtils->message("E", $rsp, $callback);
           	$error++;
           	push(@nodesfailed, $node);
           	next;
       	}

		#
		# initialize node
		#

		my $psize="64";
		if ($attrs{psize}) {
			$psize=$attrs{psize};
		}

		my $arg_string="-a spot=$imagehash{$image_name}{spot} -a root=$imagehash{$image_name}{root} -a dump=$imagehash{$image_name}{dump} -a size=$psize ";

		# the rest of these resources may or may not be provided
		if ($imagehash{$image_name}{paging} ) {
			$arg_string .= "-a paging=$imagehash{$image_name}{paging} "
		}
		if ($imagehash{$image_name}{resolv_conf}) {
			$arg_string .= "-a resolv_conf=$imagehash{$image_name}{resolv_conf} ";
		}
		if ($imagehash{$image_name}{home}) {
			$arg_string .= "-a home=$imagehash{$image_name}{home} ";
		}
		if ($imagehash{$image_name}{tmp}) {	
			$arg_string .= "-a tmp=$imagehash{$image_name}{tmp} ";
		}
		if ($imagehash{$image_name}{shared_home}) {
			$arg_string .= "-a shared_home=$imagehash{$image_name}{shared_home} ";
		}

		#
		#  make sure we have enough space for the new node root dir
		#
# TODO - test FS resize
		if (&enoughspace($imagehash{$image_name}{spot}, $imagehash{$image_name}{root}, $psize, $callback) != 0) {
			my $rsp;
			push @{$rsp->{data}}, "Could not initialize node \'$node\'\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}

		my $initcmd;
		if ( $type eq "diskless") {
			$initcmd="/usr/sbin/nim -o dkls_init $arg_string $nim_name 2>&1";
		} else {
			$initcmd="/usr/sbin/nim -o dtls_init $arg_string $nim_name 2>&1";
		}

	#	if ($::VERBOSE) {
			my $rsp;
			push @{$rsp->{data}}, "Initializing NIM machine \'$nim_name\'. This could take a while.\n";
			push @{$rsp->{data}}, "Running: \'$initcmd\'\n";
			xCAT::MsgUtils->message("I", $rsp, $callback);
	#	}

       	my $output = xCAT::Utils->runcmd("$initcmd", -1);
       	if ($::RUNCMD_RC  != 0)
       	{
			my $rsp;
			push @{$rsp->{data}}, "Could not initialize NIM client named \'$nim_name\'.\n";
			if ($::VERBOSE) {
				push @{$rsp->{data}}, "$output";
	   		}
			xCAT::MsgUtils->message("E", $rsp, $callback);
			$error++;
			push(@nodesfailed, $node);
			next;
       	}
	}

	# update the node definitions with the new osimage - if provided
	my %nodeattrs;
	if ($::OSIMAGE) {
		foreach my $node (keys %objhash) {
			chomp $node;
			if (!grep(/^$node$/, @nodesfailed)) {
				# change the node def if we were successful
				$nodeattrs{$node}{objtype} = 'node';
				$nodeattrs{$node}{profile} = $image_name;
			}
		}
		if (xCAT::DBobjUtils->setobjdefs(\%nodeattrs) != 0) {
			my $rsp;
			push @{$rsp->{data}}, "Could not write data to the xCAT database.\n";
			xCAT::MsgUtils->message("E", $rsp, $::callback);
			$error++;
		}
	}

	# update the .rhosts file on the server so the rcp from the node works
	if (&update_rhosts(\@nodelist, $callback) != 0) {
		my $rsp;
		push @{$rsp->{data}}, "Could not update the /.rhosts file.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
		$error++;
    }

	if ($error) {
		my $rsp;
		push @{$rsp->{data}}, "One or more errors occurred when attempting to initialize AIX NIM diskless nodes.\n";

		if ($::VERBOSE && (defined(@nodesfailed))) {
			push @{$rsp->{data}}, "The following node(s) could not be initialized.\n";
			foreach my $n (@nodesfailed) {
				push @{$rsp->{data}}, "$n";
			}
		}

		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	} else {
		my $rsp;
		push @{$rsp->{data}}, "AIX/NIM diskless nodes were initialized.\n";
		xCAT::MsgUtils->message("I", $rsp, $callback);

 		return 0;
	}
}

#----------------------------------------------------------------------------

=head3   rmdsklsnode

        Support for the mkdsklsnode command.

		Remove NIM diskless client definitions.

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Comments:

			rmdsklsnode [-V] [-f | --force] {-i image_name} noderange
=cut

#-----------------------------------------------------------------------------
sub rmdsklsnode
{
	my $callback = shift;

	# To-Do
    # some subroutines require a global callback var
    #   - need to change to pass in the callback
    #   - just set global for now
    $::callback=$callback;

	if (defined(@{$::args})) {
        @ARGV = @{$::args};
    } else {
        &rmdsklsnode_usage($callback);
        return 0;
    }

    # parse the options
    if(!GetOptions(
        'f|force'   => \$::FORCE,
        'h|help'     => \$::HELP,
        'i=s'       => \$::opt_i,
        'verbose|V' => \$::VERBOSE,
        'v|version'  => \$::VERSION,))
    {
        &rmdsklsnode_usage($callback);
        return 1;
    }

    if ($::HELP) {
        &rmdsklsnode_usage($callback);
        return 0;
	}

	# display the version statement if -v or --verison is specified
    if ($::VERSION)
    {
		my $version=xCAT::Utils->Version();
        my $rsp;
        push @{$rsp->{data}}, "rmdsklsnode $version\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return 0;
    }

    my $a = shift @ARGV;

	# need a node range
    unless ($a) {
		# error - must have list of nodes
        &rmdsklsnode_usage($callback);
        return 1;
    }
    my @nodelist = &noderange($a, 0);
	if (!defined(@nodelist) ) {
		# error - must have list of nodes
		&rmdsklsnode_usage($callback);
		return 1;
	}

	# for each node
	my @nodesfailed;
	my $error;
	foreach my $node (@nodelist) {

		my $nodename;
		my $name;
		($name = $node) =~ s/\..*$//; # always use short hostname
		$nodename = $name;
		if ($::opt_i) {
			$nodename=$name . "_" . $::opt_i;
		}

		# nim -Fo reset c75m5ihp05_53Lcosi
		my $cmd = "nim -Fo reset $nodename";
		my $output;

    	$output = xCAT::Utils->runcmd("$cmd", -1);
    	if ($::RUNCMD_RC  != 0)
		{
			my $rsp;
			if ($::VERBOSE) {
				push @{$rsp->{data}}, "Could not remove the NIM machine definition \'$nodename\'.\n";
				push @{$rsp->{data}}, "$output";
			}
			xCAT::MsgUtils->message("E", $rsp, $callback);
			$error++;
			push(@nodesfailed, $nodename);
			next;
		}

		$cmd = "nim -o deallocate -a subclass=all $nodename";

    	$output = xCAT::Utils->runcmd("$cmd", -1);
    	if ($::RUNCMD_RC  != 0)
		{
			my $rsp;
			if ($::VERBOSE) {
				push @{$rsp->{data}}, "Could not remove the NIM machine definition \'$nodename\'.\n";
				push @{$rsp->{data}}, "$output";
			}
			xCAT::MsgUtils->message("E", $rsp, $callback);
			$error++;
			push(@nodesfailed, $nodename);
			next;
		}

		$cmd = "nim -o remove $nodename";

    	$output = xCAT::Utils->runcmd("$cmd", -1);
    	if ($::RUNCMD_RC  != 0)
		{
			my $rsp;
			if ($::VERBOSE) {
				push @{$rsp->{data}}, "Could not remove the NIM machine definition \'$nodename\'.\n";
				push @{$rsp->{data}}, "$output";
			}
			xCAT::MsgUtils->message("E", $rsp, $callback);
			$error++;
			push(@nodesfailed, $nodename);
			next;
		}

	} # end - for each node

	if ($error) {
		my $rsp;
		push @{$rsp->{data}}, "The following NIM machine definitions could NOT be removed.\n";
		
		foreach my $n (@nodesfailed) {
			push @{$rsp->{data}}, "$n";
		}
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}
	return 0;
}

#----------------------------------------------------------------------------

=head3  mkdsklsnode_usage

=cut

#-----------------------------------------------------------------------------

sub mkdsklsnode_usage
{
	my $callback = shift;

	my $rsp;
	push @{$rsp->{data}}, "\n  mkdsklsnode - Use this xCAT command to define and initialize AIX \n\t\t\tdiskless nodes.";
	push @{$rsp->{data}}, "  Usage: ";
	push @{$rsp->{data}}, "\tmkdsklsnode [-h | --help ]";
	push @{$rsp->{data}}, "or";
	push @{$rsp->{data}}, "\tmkdsklsnode [-V] [-f|--force] [-n|--newname] \n\t\t[-i image_name] noderange [attr=val [attr=val ...]]\n";
	xCAT::MsgUtils->message("I", $rsp, $callback);
    return 0;
}

#----------------------------------------------------------------------------

=head3  rmdsklsnode_usage

=cut

#-----------------------------------------------------------------------------
sub rmdsklsnode_usage
{
	my $callback = shift;

	my $rsp;
	push @{$rsp->{data}}, "\n  rmdsklsnode - Use this xCAT command to remove AIX/NIM diskless client definitions.";
	push @{$rsp->{data}}, "  Usage: ";
	push @{$rsp->{data}}, "\trmdsklsnode [-h | --help ]";
	push @{$rsp->{data}}, "or";
	push @{$rsp->{data}}, "\trmdsklsnode [-V] [-f|--force] {-i image_name} noderange";
	xCAT::MsgUtils->message("I", $rsp, $callback);
	return 0;
}


#----------------------------------------------------------------------------

=head3  mknimimage_usage

=cut

#-----------------------------------------------------------------------------
sub mknimimage_usage
{
	my $callback = shift;

	my $rsp;
    push @{$rsp->{data}}, "\n  mknimimage - Use this xCAT command to create AIX image definitions.";
    push @{$rsp->{data}}, "  Usage: ";
    push @{$rsp->{data}}, "\tmknimimage [-h | --help]";
    push @{$rsp->{data}}, "or";
    push @{$rsp->{data}}, "\tmknimimage [-V] [-f|--force] [-l <location>] -s [image_source] \n\t\t[-i current_image] [-t nimtype] [-m nimmethod] [-n mksysbnode]\n\t\t[-b mksysbfile] osimage_name [attr=val [attr=val ...]]\n";
    xCAT::MsgUtils->message("I", $rsp, $callback);
    return 0;
}

#----------------------------------------------------------------------------

=head3  rmnimimage_usage

=cut

#-----------------------------------------------------------------------------
sub rmnimimage_usage
{
	my $callback = shift;

	my $rsp;
	push @{$rsp->{data}}, "\n  rmnimimage - Use this xCAT command to remove an image definition.";
	push @{$rsp->{data}}, "  Usage: ";
	push @{$rsp->{data}}, "\trmnimimage [-h | --help]";
	push @{$rsp->{data}}, "or";
	push @{$rsp->{data}}, "\trmnimimage [-V] [-f|--force] image_name\n";
	xCAT::MsgUtils->message("I", $rsp, $callback);
	return 0;
}

#----------------------------------------------------------------------------

=head3  nimnodeset_usage

=cut

#-----------------------------------------------------------------------------

sub nimnodeset_usage
{
    my $callback = shift;

    my $rsp;
    push @{$rsp->{data}}, "\n  nimnodeset - Use this xCAT command to initialize AIX \n\t\t\tstandalone nodes.";
    push @{$rsp->{data}}, "  Usage: ";
    push @{$rsp->{data}}, "\tnimnodeset [-h | --help ]";
    push @{$rsp->{data}}, "or";
    push @{$rsp->{data}}, "\tnimnodeset [-V] [-f|--force] [ -i osimage_name]\n\t\tnoderange [attr=val [attr=val ...]]\n";
    xCAT::MsgUtils->message("I", $rsp, $callback);
    return 0;
}

1;
