#!/usr/bin/env perl -w
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#####################################################
#
#  xCAT plugin package to handle the mkdsklsnode, mknimimage 
#	rmdsklsnode, & rmnimimage commands.
#
#####################################################

package xCAT_plugin::aixdskls;

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

=head1    aixdskls

This program module file supports the mkdsklsnode, rmdsklsnode,
rmnimimage & mknimimage commands.


=cut

#------------------------------------------------------------------------------

=head2    xCAT for AIX diskless support

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
            mknimimage => "aixdskls",
			rmnimimage => "aixdskls",
            mkdsklsnode => "aixdskls",
			rmdsklsnode => "aixdskls"
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

    my $ret;
    my $msg;

    my $command  = $request->{command}->[0];
    $::args     = $request->{arg};
    $::filedata = $request->{stdin}->[0];

    # figure out which cmd and call the subroutine to process
    if ($command eq "mkdsklsnode")
    {
        ($ret, $msg) = &mkdsklsnode($callback);
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

#----------------------------------------------------------------------------

=head3   mknimimage


		Creates an AIX/NIM image - referred to as a SPOT or COSI.

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

		1.Creates a NIM lpp_source resource if needed.  The NIM name of the 
		  resource 
		  will be the name provided for the image with "_lpp" appended to 
		  the end. ("<image_name>_lpp")
		2.Create a NIM SPOT/COSI resource using the lpp_source resource that 
		  was provided or just created.  (The lpp_source resource will  
		  be used when when updating the COSI.)
		3.Modifies the SPOT so that other xCAT features, such as rnetboot, 
		  will work correctly.  
		4.Creates  "root", "dump", and "paging" resources to be used along 
		  with this image.  
		5.Creates an xCAT image definition for this AIX diskless image.   

=cut

#-----------------------------------------------------------------------------
sub mknimimage
{
	my $callback = shift;

	my $lppsrcname; # name of the lpp_source resource for this image
	my $image_name; # name of xCAT osimage to create
	my $spot_name;  # name of SPOT/COSI  default to image_name
	my $rootres;    # name of the root resource
	my $dumpres;    #  dump resource
	my $pagingres;  # paging
	my $currentimage; # the image to copy
	my %resnames;   # NIM resource type and names passed in as attr=val
	my %osimagedef; # the osimage def info

	@ARGV = @{$::args};

	# parse the options
	Getopt::Long::Configure("no_pass_through");
	if(!GetOptions(
		'f|force'	=> \$::FORCE,
		'h|help'     => \$::HELP,
		's=s'       => \$::opt_s,
		'l=s'       => \$::opt_l,
		'i=s'       => \$::opt_i,
		't=s'		=> \$::NIMTYPE,
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
        my $rsp;
        push @{$rsp->{data}}, "mknimimage version 2.0\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return 0;
    }

	# the type is standalone by default
	if (!$::NIMTYPE) {
		$::NIMTYPE = "standalone";
	}

	#  this command will be enhanced for standalone shortly - but not yet
	if ( ($::NIMTYPE ne "diskless") && ($::NIMTYPE ne "diskless")) {
		my $rsp;
		push @{$rsp->{data}}, "NIM standalone type machines are not yet supported with this command.  Coming soon!\n";
		xCAT::MsgUtils->message("I", $rsp, $callback);
		return 0;
	}

	#
    # process @ARGV
    #

	# the first arg should be a noderange - the other should be attr=val
    #  - put attr=val operands in %resnames hash
    while (my $a = shift(@ARGV))
    {
        if (!($a =~ /=/))
        {
			$image_name = $a;
			chomp $image_name;
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
			$resnames{$attr} = $value;
        }
    }

	# see if the image_name provided is already defined
	my @deflist = xCAT::DBobjUtils->getObjectsOfType("osimage");
	if (grep(/^$image_name$/, @deflist)) {
		if ($::FORCE) {
			# remove the existing osimage def and continue
			my %objhash;
			$objhash{$image_name} = "osimage";
			if (xCAT::DBobjUtils->rmobjdefs(\%objhash) != 0) {
				my $rsp;
				push @{$rsp->{data}}, "Could not remove the existing xCAT definition for \'$image_name\'.\n";
				xCAT::MsgUtils->message("E", $rsp, $::callback);
			}
		} else {
			my $rsp;
			push @{$rsp->{data}}, "The osimage definition \'$image_name\' already exists.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}
	}

	# get the xCAT image definition if provided
	my %imagedef;
    if ($::opt_i) {
        my %objtype;

		my $currentimage=$::opt_i;

		# get the image def
        $objtype{$::opt_i} = 'osimage';

		%imagedef = xCAT::DBobjUtils->getobjdefs(\%objtype,$callback);
		if (!defined(%imagedef))
		{
			my $rsp;
			push @{$rsp->{data}}, "Could not get xCAT image definition.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}
	}

#ndebug
#print "src = $::opt_s, image= \'$image_name\', root = $resnames{root}\n";
#print "opt_i = $::opt_i, osname= $imagedef{$::opt_i}{osname}\n";

	# must have a source and a name
	if (!($::opt_s || $::opt_i) || !defined($image_name) ) {
		my $rsp;
		push @{$rsp->{data}}, "The image name and either the -s or -i option are required.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		&mknimimage_usage($callback);
		return 1;
	}

	#
	#  Get a list of the all defined resources
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

	#
    #  Get a list of the defined lpp_source resources
    #
    my @lppresources = [];
    my $cmd = qq~/usr/sbin/lsnim -t lpp_source | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    @lppresources = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC  != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get NIM lpp_source definitions.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	#
	# NIM lpp_source resource.
	#
	#   If lpp_source is provided in attr=val then use that
	# 	If opt_i then use the lpp_source from the osimage def
	#	If opt_s then we could have either an existing lpp_source or 
	#		a directory containing source
	#
	if ( $resnames{lpp_source} ) { 

		# if lpp_source provided then use it
		$lppsrcname=$resnames{lpp_source};

	} elsif ($::opt_i) { 

		# if we have lpp_source name in osimage def then use that
		if ($imagedef{$::opt_i}{lpp_source}) {
			$lppsrcname=$imagedef{$::opt_i}{lpp_source};
		} else {
			my $rsp;
			push @{$rsp->{data}}, "The $::opt_i image definition did not contain a value for lpp_source.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}

	} elsif ($::opt_s) { 

		# if source is provided we may need to create a new lpp_source

		#   make a name using the convention and check if it already exists
		$lppsrcname= $image_name . "_lpp_source";

		if (grep(/^$lppsrcname$/, @lppresources)) {
			my $rsp;
			push @{$rsp->{data}}, "Using the existing lpp_source named \'$lppsrcname\'\n";
			xCAT::MsgUtils->message("I", $rsp, $callback);
		} else {

			# create a new one

			# the source could be a directory or an existing lpp_source resource
			if ( !(-d $::opt_s) ) {
				# if it's not a directory then is it the name of 
				#	an existing lpp_source?
				if (!(grep(/^$::opt_s$/, @lppresources))) {
					my $rsp;
					push @{$rsp->{data}}, "\'$::opt_s\' is not a source directory or the name of a NIM lpp_source resource.\n";
                	xCAT::MsgUtils->message("E", $rsp, $callback);
                	&mknimimage_usage($callback);
                	return 1;
				}
			}

			# build an lpp_source 
			my $rsp;
			push @{$rsp->{data}}, "Creating a NIM lpp_source resource called \'$lppsrcname\'.  This could take a while.\n";
			xCAT::MsgUtils->message("I", $rsp, $callback);

			# make cmd
			my $lpp_cmd = "/usr/sbin/nim -Fo define -t lpp_source -a server=master ";
			# where to put it - the default is /install
			if ($::opt_l) {
				$lpp_cmd .= "-a location=$::opt_l/$lppsrcname ";
			} else {
				$lpp_cmd .= "-a location=/install/nim/lpp_source/$lppsrcname  ";
			}

			$lpp_cmd .= "-a source=$::opt_s $lppsrcname";

			if ($::VERBOSE) {
				my $rsp;
				push @{$rsp->{data}}, "Running: \'$lpp_cmd\'\n";
				xCAT::MsgUtils->message("I", $rsp, $callback);
			}
#ndebug

			my $output = xCAT::Utils->runcmd("$lpp_cmd", -1);
       		if ($::RUNCMD_RC  != 0)
       		{
           		my $rsp;
           		push @{$rsp->{data}}, "Could not run command \'$cmd\'. (rc = $::RUNCMD_RC)\n";
           		xCAT::MsgUtils->message("E", $rsp, $callback);
           		return 1;
       		}
		}
	} else {
		my $rsp;
		push @{$rsp->{data}}, "Could not get an lpp_source resource for this diskless image.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	} # end - get lpp_source

	#
	# spot resource
	#
	if ( $resnames{spot} ) { 

		# if spot provided then use it
        $spot_name=$resnames{spot};

    } elsif ($::opt_i) {
		# copy the spot named in the osimage def

		# use the image name for the new SPOT/COSI name
		$spot_name=$image_name;
	
		if ($imagedef{$::opt_i}{spot}) {
			# a spot was provided as a source so copy it to create a new one 
			my $cpcosi_cmd = "/usr/sbin/cpcosi ";

			# name of cosi to copy
			$currentimage=$imagedef{$::opt_i}{spot};
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
#ndebug
			my $output = xCAT::Utils->runcmd("$cpcosi_cmd", -1);
			if ($::RUNCMD_RC  != 0)
			{
				my $rsp;
				push @{$rsp->{data}}, "Could not create a NIM definition for \'$spot_name\'.\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
				return 1;
			}
		} else {
			my $rsp;
			push @{$rsp->{data}}, "The $::opt_i image definition did not contain a value for a SPOT resource.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }

	} else {

		# create a new spot from the lpp_source 

		# use the image name for the new SPOT/COSI name
		$spot_name=$image_name;

        if (grep(/^$spot_name$/, @nimresources)) {
            my $rsp;
            push @{$rsp->{data}}, "Using the existing SPOT named \'$spot_name\'.\n";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        } else {

			# Create the SPOT/COSI
			my $cmd = "/usr/sbin/nim -o define -t spot -a server=master ";

			# source of images
			$cmd .= "-a source=$lppsrcname ";

			# where to put it - the default is /install
			if ($::opt_l) {
				$cmd .= "-a location=$::opt_l/$spot_name ";
			} else {
				$cmd .= "-a location=/install/nim/spot/$spot_name  ";
			}

			$cmd .= "$spot_name  2>&1";

			# run the cmd
			my $rsp;
			push @{$rsp->{data}}, "Creating a NIM SPOT resource. This could take a while.\n";
			xCAT::MsgUtils->message("I", $rsp, $callback);

			if ($::VERBOSE) {
            	my $rsp;
            	push @{$rsp->{data}}, "Running: \'$cmd\'\n";
            	xCAT::MsgUtils->message("I", $rsp, $callback);
			}

#ndebug

			my $output = xCAT::Utils->runcmd("$cmd", -1);
			if ($::RUNCMD_RC  != 0)
			{
				my $rsp;
				push @{$rsp->{data}}, "Could not create a NIM definition for \'$spot_name\'.\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
				return 1;
			}

		} # end - if spot doesn't exist
	}

	#
	#  Update the SPOT resource
	#
	my $rc=&updatespot($spot_name, $lppsrcname, $callback);
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
	#   - resolv_conf - create if not provided
	#   - optional - tmp, home, shared_home
	#  
    # - basic logic 
    #   - if resource name is provided then use that resource
	#	- if it was in image def provided use that
    #   - if named resource already exists then use it
    #   - if doesn't exist then create it

	#
	# root res
	#
	my $root_name;
	if ( $resnames{root} ) {

        # if provided on cmd line then use it
        $root_name=$resnames{root};

	} elsif ($::opt_i) {

		# if one is provided in osimage use it    
		if ($imagedef{$::opt_i}{root}) {
			$root_name=$imagedef{$::opt_i}{root};
		}

    } else {

		# may need to create new one

		# use naming convention
		# all will use the same root res for now
		#		$root_name=$image_name . "_root";
		$root_name="root";

		# see if it's already defined
        if (grep(/^$root_name$/, @nimresources)) {
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

	#
	# dump res
	#
	my $dump_name;
	if ( $resnames{dump} ) {

        # if provided then use it
        $dump_name=$resnames{dump};

	} elsif ($::opt_i) {

        # if one is provided in osimage 
        if ($imagedef{$::opt_i}{dump}) {
            $dump_name=$imagedef{$::opt_i}{dump};
        }

    } else {

		# may need to create new one
		# all use the same dump res unless another is specified
		$dump_name="dump";
		# see if it's already defined
        if (grep(/^$dump_name$/, @nimresources)) {
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

	#
	# paging res
	#
	my $paging_name;
	if ( $resnames{paging} ) {

        # if provided then use it
        $paging_name=$resnames{paging};

	} elsif ($::opt_i) {

        # if one is provided in osimage and we don't want a new one
        if ($imagedef{$::opt_i}{paging}) {
            $paging_name=$imagedef{$::opt_i}{paging};
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

			$paging_name="paging";

			# see if it's already defined
        	if (grep(/^$paging_name$/, @nimresources)) {
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

	#
	# resolv_conf res
	#
# don't create this for now - just use it if provided
if (0) {
    my $resolv_conf_name;
    if ( $resnames{resolv_conf} ) {

        # if provided then use it
        $resolv_conf_name=$resnames{resolv_conf};

	} elsif ($::opt_i) {

        # if one is provided in osimage and we don't want a new one
        if ($imagedef{$::opt_i}{resolv_conf}) {
            $resolv_conf_name=$imagedef{$::opt_i}{resolv_conf};
        }

    } else {

		# default res
		$resolv_conf_name="master_net_conf";

		# see if it's already defined
		if (grep(/^$resolv_conf_name$/, @nimresources)) {
			my $rsp;
			push @{$rsp->{data}}, "Using existing resolv_conf resource named \'$resolv_conf_name\'.\n";
			xCAT::MsgUtils->message("I", $rsp, $callback);
		} elsif ( -e "/etc/resolv.conf")  {

			# use the resolv.conf file to create a res if it exists
			my $loc;
			if ($::opt_l) {
				$loc = $::opt_l;
			} else {
				$loc = "/install/nim/resolv_conf";
			}

			my $cmd = "cp /etc/resolv.conf $loc/resolv.conf";

			#ndebug
#           my $output = xCAT::Utils->runcmd("$cmd", -1);
#           if ($::RUNCMD_RC  != 0) {
if (0) {
                my $rsp;
                push @{$rsp->{data}}, "Could not create a NIM definition for \'$
resolv_conf_name\'.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
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

#ndebug
#			my $output = xCAT::Utils->runcmd("$cmd", -1);
#			if ($::RUNCMD_RC  != 0) {
if (0) {
				my $rsp;
				push @{$rsp->{data}}, "Could not create a NIM definition for \'$resolv_conf_name\'.\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
			}
		}
	} # end resolv_conf res

} # end - don't create resolv_conf

	#
	#  Create xCAT osimage def
	#
	$osimagedef{$image_name}{objtype}="osimage";
	$osimagedef{$image_name}{imagetype}="NIM";
	$osimagedef{$image_name}{osname}="AIX";

	if ($::NIMTYPE) {
		$osimagedef{$image_name}{nimtype}=$::NIMTYPE;
	} else {
		$osimagedef{$image_name}{nimtype}="diskless";
	}
	$osimagedef{$image_name}{lpp_source}=$lppsrcname;
	$osimagedef{$image_name}{spot}=$spot_name;
	$osimagedef{$image_name}{root}=$root_name;
	$osimagedef{$image_name}{dump}=$dump_name;

	if ($paging_name) {
		$osimagedef{$image_name}{paging}=$paging_name;
	}

	# there could be additional res names
	#   either from the cmd line or from an image def - if provided
	if ($resnames{resolv_conf}) {
		$osimagedef{$image_name}{resolv_conf}=$resnames{resolv_conf};
	} elsif ($imagedef{$::opt_i}{resolv_conf}) {
		$osimagedef{$image_name}{resolv_conf}=$imagedef{$::opt_i}{resolv_conf};
	}

	if ($resnames{tmp}) {
		$osimagedef{$image_name}{tmp}=$resnames{tmp};
	} elsif ($imagedef{$::opt_i}{tmp}) {
		$osimagedef{$image_name}{tmp}=$imagedef{$::opt_i}{tmp};
	}

	if ($resnames{home}) {
	 	$osimagedef{$image_name}{home}=$resnames{home};
	} elsif ($imagedef{$::opt_i}{home}) {
        $osimagedef{$image_name}{home}=$imagedef{$::opt_i}{home};
    }

	if ($resnames{shared_home}) {
	 	$osimagedef{$image_name}{shared_home}=$resnames{shared_home};
	} elsif ($imagedef{$::opt_i}{shared_home}) {
        $osimagedef{$image_name}{shared_home}=$imagedef{$::opt_i}{shared_home};
    }

	if ($resnames{res_group}) {
		$osimagedef{$image_name}{res_group}=$resnames{res_group};
	} elsif ($imagedef{$::opt_i}{res_group}) {
		$osimagedef{$image_name}{res_group}=$imagedef{$::opt_i}{res_group};
	}

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

	push @{$rsp->{data}}, "\nObject name: $image_name";

	foreach my $attr (sort(keys %{$osimagedef{$image_name}}))
	{
		if ($attr eq 'objtype') {
			next;
		}
		push @{$rsp->{data}}, "\t$attr=$osimagedef{$image_name}{$attr}";
	}
	xCAT::MsgUtils->message("I", $rsp, $callback);

	return 0;

} # end mknimimage

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

    @ARGV = @{$::args};

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
        my $rsp;
        push @{$rsp->{data}}, "rmnimimage version 2.0\n";
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

	#
    #  Get a list of the all nim resource types ???
    #
    # lsnim -P -c resources

	my $rsp;
	push @{$rsp->{data}}, "Removing NIM resource definitions. This could take a while!";
	xCAT::MsgUtils->message("I", $rsp, $callback);

	# foreach attr in imagedef
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
	my $callback = shift;
    my ($cmd, $rc, $entry);

	my $spotinittab = "$::spot_loc/lpp/bos/inst_root/etc/inittab";

	my $entry = "xcat:2:wait:/opt/xcat/xcatdsklspost\n";

	# see if xcatdsklspost is already in the file
	my $cmd = "cat $spotinittab | grep xcatdsklspost";
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
		$value =~ s/\s*//g;  # remove blanks
		if ($attr eq $attrname) {
			return $value;
		}
	}
	return undef;
}


#----------------------------------------------------------------------------

=head3  get_spot_loc

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
sub get_spot_loc {

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

=head3  mknimres

        Update the SPOT resource.

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
		$cmd .= "-a location=$::opt_l/$res_name ";
	} else {
		$cmd .= "-a location=/install/nim/$type/$res_name  ";
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
	$spot_loc = &get_spot_loc($spot_name, $callback);
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
	# Copy the xcatdsklspost script to the SPOT/COSI and add an entry for it
	#	to the /etc/inittab file
	#
	if ($::VERBOSE) {
		my $rsp;
		push @{$rsp->{data}}, "Adding xcatdsklspost script to the image.\n";
		xCAT::MsgUtils->message("I", $rsp, $callback);
	}

	# copy the script
	my $cpcmd = "mkdir -m 644 -p $spot_loc/lpp/bos/inst_root/opt/xcat; cp /install/postscripts/xcatdsklspost $spot_loc/lpp/bos/inst_root/opt/xcat/xcatdsklspost";

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
#	if (&update_inittab($callback) != 0) {
#		my $rsp;
#        push @{$rsp->{data}}, "Could not update the /etc/inittab file in the SPOT.\n";
#        xCAT::MsgUtils->message("E", $rsp, $callback);
#        return 1;
#	}

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

        Error:

        Example:

			mkdsklsnode [-V] [-f|--force] [-n|--newname] [-s|--switch]
          [-i osimage_name] noderange [attr=val [attr=val ...]]

        Comments:

=cut

#-----------------------------------------------------------------------------
sub mkdsklsnode 
{
	my $callback = shift;

	my $error=0;
	my @nodesfailed;
	my $image_name;

	# some subroutines require a global callback var
	#	- need to change to pass in the callback 
	#	- just set global for now
    $::callback=$callback;

	@ARGV = @{$::args};

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
        my $rsp;
        push @{$rsp->{data}}, "mkdsklsnode version 2.0\n";
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

	# get the node defs
	# get all the attrs for these definitions
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
    #  Get a list of the defined machines
    #
	my @machines = [];
    my $cmd = qq~/usr/sbin/lsnim -c machines | /usr/bin/cut -f1 -d' ' 2>/dev/nu
ll~;

    @machines = xCAT::Utils->runcmd("$cmd", -1);
# don't fail - maybe just don't have any defined!
    #if ($::RUNCMD_RC  != 0)
	if (0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get NIM machine definitions.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	my $error=0;
	my @nodesfailed;
	foreach my $node (keys %objhash)
	{

#print "node = $node\n";

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

#print "image = $image_name\n";

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

		my $type="diskless";
		if ($imagehash{$image_name}{nimtype} ) {
			$type = $imagehash{$image_name}{nimtype};
		}
		chomp $type;
		

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

		# need short host name for NIM cmds ???
        my $nodeshorthost;
        ($nodeshorthost = $node) =~ s/\..*$//;
        chomp $nodeshorthost;

#print "nim_name=$nim_name, nodeshorthost=$nodeshorthost, spot = $imagehash{$image_name}{spot}\n";


# ndebug
		if ($::SWITCH) { # just uninit 

# ndebug
print "Switch to a new image.  This could take a whaile.\n";

			# uninitialize the node
			my $resetcmd = "/usr/sbin/nim -Fo reset $nim_name";
			my $output = xCAT::Utils->runcmd("$resetcmd", -1);
			if ($::RUNCMD_RC  != 0) {
				my $rsp;
				push @{$rsp->{data}}, "Could not reset the existing NIM machine named \'$nim_name\'.\n";
				if ($::VERBOSE) {
					push @{$rsp->{data}}, "$output";
				}
				xCAT::MsgUtils->message("E", $rsp, $callback);
				$error++;
				push(@nodesfailed, $node);
				next;
			}

			my $uncmd = "/usr/sbin/nim -Fo deallocate -a subclass=all $nim_name";
			my $output = xCAT::Utils->runcmd("$uncmd", -1);
			if ($::RUNCMD_RC  != 0) {
				my $rsp;
				push @{$rsp->{data}}, "Could not deallocate NIM resources for the NIM machine named \'$nim_name\'.\n";
				if ($::VERBOSE) {
					push @{$rsp->{data}}, "$output";
				}
				xCAT::MsgUtils->message("E", $rsp, $callback);
				$error++;
				push(@nodesfailed, $node);
				next;
			}

		} else { # define new machine

			# 
			# otherwise define/initialize the new machine
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

			} else {  # not defined - so define it!

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

				# increase size of root fs if needed???

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

# ndebug
#print "defcmd =\'$defcmd\'\n";

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
			} 
		} # end define new machine

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

# ndebug
#print "initcmd = \'$initcmd\'\n";
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
			if (!grep(/^$node$/, @nodesfailed)) {
				# change the node def if we were successful
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

	if ($error) {
		my $rsp;
		push @{$rsp->{data}}, "One or more errors occurred when attempting to initialize AIX NIM diskless nodes.\n";

		if ($::VERBOSE) {
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

    @ARGV = @{$::args};

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
        my $rsp;
        push @{$rsp->{data}}, "rmdsklsnode version 2.0\n";
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

#print "reset cmd= $cmd\n";

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

#print "deall cmd= $cmd\n";

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

#print "remove cmd= $cmd\n";

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
    push @{$rsp->{data}}, "\tmknimimage [-V] [-f|--force] [-l <location>] -s [image_source] \n\t\t[-i current_image] [-t nimtype] osimage_name \n\t\t[attr=val [attr=val ...]]\n";
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


1;
