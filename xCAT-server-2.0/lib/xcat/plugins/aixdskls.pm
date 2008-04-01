#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#####################################################
#
#  xCAT plugin package to handle the mkdsklsnode & mkdsklsimage command.
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

# options can be bundled up like -vV
Getopt::Long::Configure("bundling");
$Getopt::Long::ignorecase = 0;

#------------------------------------------------------------------------------

=head1    aixdskls

This program module file supports the mkdsklsnode & mkdsklsimage command.


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
            mkdsklsimage => "aixdskls",
            mkdsklsnode => "aixdskls"
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

    # figure out which cmd and call the subroutine to process
    if ($::command eq "mkdsklsnode")
    {
        ($ret, $msg) = &dsklsnode;
    }
    elsif ($::command eq "mkdsklsimage")
    {
        ($ret, $msg) = &dsklsimage;
    }

	if ($ret > 0) {
		my $rsp;

		if ($msg) {
			push @{$rsp->{data}}, $msg;
		} else {
			push @{$rsp->{data}}, "Command returned an error.";
		}

		$rsp->{errorcode}->[0] = $ret;
		
		xCAT::MsgUtils->message("E", $rsp, $::callback, $ret);
	}

	return 0;
}

#----------------------------------------------------------------------------

=head3   dsklsimage

        Support for the mkdsklsimage command.

		Creates an AIX/NIM diskless image - referred to as a SPOT or COSI.

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
sub dsklsimage
{
	# parse the options
	Getopt::Long::Configure("no_pass_through");
	if(!GetOptions(
		'h|help'     => \$::HELP,
		's=s'       => \$::opt_s,
		'l=s'       => \$::opt_l,
		'S=s'       => \$::opt_S,
		'verbose|V' => \$::opt_V,
		'v|version'  => \$::VERSION,))
	{

		&dsklsimage_usage;
        return 1;
	}

	# display the usage if -h or --help is specified
    if ($::HELP) {
        &dsklsimage_usage;
        return 0;
    }

	# display the version statement if -v or --verison is specified
    if ($::VERSION)
    {
        my $rsp;
        push @{$rsp->{data}}, "mkdsklsimage version 2.0\n";
        xCAT::MsgUtils->message("I", $rsp, $::callback);
        return 0;
    }

	my $spot_name = shift @ARGV;
	unless ($spot_name) {
		&dsklsimage_usage;
		return 1;
	}

	# must have a source and a name
	if (!$::opt_s || !defined($spot_name) ) {
		&dsklsimage_usage;
		return 1;
	}

	#
	#  See if this NIM SPOT definition already exists
	#
	my $spot_exists=0;
	my $cmd = qq~lsnim -c resources | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
	my @output = xCAT::Utils->runcmd("$cmd", -1);
	if ($::RUNCMD_RC  != 0)
	{
		my $rsp;
        push @{$rsp->{data}}, "Could not get NIM resource definitions.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 1;
	}
	elsif (grep(/^$spot_name$/, @output))
	{
		$spot_exists=1;
		my $rsp;
		push @{$rsp->{data}}, "A NIM SPOT resource named \'$spot_name\' already exists.";
		xCAT::MsgUtils->message("E", $rsp, $::callback);
		return 1;
	}

	if (!$spot_exists) {

		#
		# Create the SPOT/COSI
		#
		my $mkcosi_cmd = "/usr/sbin/mkcosi ";

		# do we want verbose output?
		if ($::opt_V) {
			$mkcosi_cmd .= "-v ";
		}

		# source of images
		$mkcosi_cmd .= "-s $::opt_s ";

		# where to put it - the default is /install
		if ($::opt_l) {
			$mkcosi_cmd .= "-l $::opt_l ";
		} else {
			$mkcosi_cmd .= "-l /install  ";
		}

		# what server do we want this created on? 
		#	- default is server I'm running this cmd on
		# !! might want to hide this for xCAT support??
		if ($::opt_S ) {
			$mkcosi_cmd .= "-S $::opt_S ";
		}

		# must have the name of the SPOT/COSI to create
		$mkcosi_cmd .= "$spot_name  2>&1";

		# run the cmd
		my $rsp;
		push @{$rsp->{data}}, "Creating a NIM SPOT resource. This could take a while.\n";
		xCAT::MsgUtils->message("I", $rsp, $::callback);

		my $output = xCAT::Utils->runcmd("$mkcosi_cmd", -1);
		if ($::RUNCMD_RC  != 0)
		{
			my $rsp;
			push @{$rsp->{data}}, "Could not create a NIM definition for \'$spot_name\'.\n";
			xCAT::MsgUtils->message("E", $rsp, $::callback);
			return 1;
		}

	} # end if spot doesn't exist

	#
	#  Get the SPOT location ( path to ../usr)
	#
	$::spot_loc = &get_spot_loc($spot_name);
	if (!defined($::spot_loc) ) {
		my $rsp;
		push @{$rsp->{data}}, "Could not get the location of the SPOT/COSI named $::spot_loc.\n";
		xCAT::MsgUtils->message("E", $rsp, $::callback);
		return 1;
	}

	#
	# Create ODMscript in the SPOT and modify the rc.dd-boot script
	#	- need for rnetboot to work - handles default console setting
	#

	#  Create ODMscript script
	my $odmscript = "$::spot_loc/ODMscript";
	my $text = "CuAt:\n\tname = sys0\n\tattribute = syscons\n\tvalue = /dev/vty0\n\ttype = R\n\tgeneric =\n\trep = s\n\tnls_index = 0";

	if ( open(ODMSCRIPT, ">$odmscript") ) {
		print ODMSCRIPT $text;
		close(ODMSCRIPT);
	} else {
		my $rsp;
		push @{$rsp->{data}}, "Could not open $odmscript for writing.\n";
		xCAT::MsgUtils->message("E", $rsp, $::callback);
		return 1;
	}
	my $cmd = "chmod 444 $odmscript";
	my @result = xCAT::Utils->runcmd("$cmd", -1);
	if ($::RUNCMD_RC  != 0)
	{
		my $rsp;
		push @{$rsp->{data}}, "Could not run the chmod command.\n";
		xCAT::MsgUtils->message("E", $rsp, $::callback);
		return 1;
	}

	# Modify the rc.dd-boot script to set the ODM correctly
	my $boot_file = "$::spot_loc/lib/boot/network/rc.dd_boot";
	if (&update_dd_boot($boot_file) != 0) {
		my $rsp;
		push @{$rsp->{data}}, "Could not update the rc.dd_boot file in the SPOT.\n";
		xCAT::MsgUtils->message("E", $rsp, $::callback);
		return 1;
	}

	#
	# Copy the xcatAIXpost script to the SPOT/COSI and add an entry for it
	#	to the /etc/inittab file
	#

	# copy the script
	my $cpcmd = "mkdir -m 644 -p $::spot_loc/lpp/bos/inst_root/opt/xcat; cp $::XCATROOT/share/xcat/netboot/aix/xcatAIXpost $::spot_loc/lpp/bos/inst_root/opt/xcat/xcatAIXpost";
	my @result = xCAT::Utils->runcmd("$cpcmd", -1);
	if ($::RUNCMD_RC  != 0)
	{
		my $rsp;
        push @{$rsp->{data}}, "Could not copy the xcatAIXpost script to the SPOT.\n";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 1;
    }	

	# add an entry to the /etc/inittab file in the COSI/SPOT
	if (&update_inittab != 0) {
		my $rsp;
        push @{$rsp->{data}}, "Could not update the /etc/inittab file in the SPOT.\n";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 1;
	}

	#
	# Output results
	#
	# - use lsnim or nim -o showres  ??
	my $rsp;
	push @{$rsp->{data}}, "A diskless image called $spot_name was created and updated.\n";
	xCAT::MsgUtils->message("I", $rsp, $::callback);

	return 0;

} # end dsklsimage


#-------------------------------------------------------------------------

=head3   update_inittab  
		 - add an entry for xcatAIXpost to /etc/inittab    
                                                                         
   Description:  This function updates the /etc/inittab file. 
                                                                         
   Arguments:    None.                                                   
                                                                         
   Return Codes: 0 - All was successful.                                 
                 1 - An error occured.                                   
=cut

#------------------------------------------------------------------------
sub update_inittab
{

    my ($cmd, $rc, $entry);

	my $spotinittab = "$::spot_loc/lpp/bos/inst_root/etc/inittab";

	my $entry = "xcat:2:wait:/opt/xcat/xcatAIXpost\n";

	unless (open(INITTAB, ">>$spotinittab")) {
		print "Could not open $spotinittab for appending.\n";
		return 1;
	}

	print INITTAB $entry;

	close (INITTAB);

	return 0;
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

	my ($spotname) = @_;

	my $cmd = "/usr/sbin/lsnim -l $spotname";

	my @result = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC  != 0)
    {
        print "Could not run lsnim command.\n";
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

=head3   update_dd_boot

         Add the workaround for the default console to rc.dd_boot.

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
sub update_dd_boot {

	my ($dd_boot_file) = @_;
	my @lines;
	my $patch = qq~\n\t# xCAT support\n\tif [ -z "\$(odmget -qattribute=syscons CuAt)" ] \n\tthen\n\t  \${SHOWLED} 0x911\n\t  cp /usr/ODMscript /tmp/ODMscript\n\t  [ \$? -eq 0 ] && odmadd /tmp/ODMscript\n\tfi \n\n~;

	# back up the original file
	my $cmd    = "cp -f $dd_boot_file $dd_boot_file.orig";
 	my $output = xCAT::Utils->runcmd("$cmd", -1);
	if ($::RUNCMD_RC  != 0)
	{
		print "Could not copy $dd_boot_file.\n";
	}
	
	if ( open(DDBOOT, "<$dd_boot_file") ) {
		@lines = <DDBOOT>;
		close(DDBOOT);
	} else {
		print "Could not open $dd_boot_file for reading.\n";
		return 1;
	}

	# remove the file
	my $cmd    = "rm $dd_boot_file";
	my $output = xCAT::Utils->runcmd("$cmd", -1);
	if ($::RUNCMD_RC  != 0)
    {
        print "Could not remove original $dd_boot_file.\n";
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
        print "Could not open $dd_boot_file for writing.\n";
		return 1;
    }

	if ($::opt_V) {
		print "Updated $dd_boot_file.\n";
	}
	return 0;
}

#----------------------------------------------------------------------------

=head3   dsklsnode

        Support for the mkdsklsnode command.

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
sub dsklsnode 
{

	# parse the options
	if(!GetOptions(
		'h|help'     => \$::HELP,
		'c=s'       => \$::opt_c,
		'verbose|V' => \$::opt_V,
		'v|version'  => \$::VERSION,))
	{
		&dsklsnode_usage;
		return 1;
	}

	if ($::HELP) {
		&dsklsnode_usage;
		return 0;
	}

	# display the version statement if -v or --verison is specified
    if ($::VERSION)
    {
        my $rsp;
        push @{$rsp->{data}}, "mkdsklsnode version 2.0\n";
        xCAT::MsgUtils->message("I", $rsp, $::callback);
        return 0;
    }

	my $a = shift @ARGV;
	unless ($a) {
		return 1;
	}
	my @nodelist = &noderange($a, 0);
	my %objtype;
	my %objhash;

	# get the node defs
	# get all the attrs for these definitions
	foreach my $o (@nodelist)
	{
		push(@::clobjnames, $o);
		$objtype{$o} = 'node';
	}

	%objhash = xCAT::DBobjUtils->getobjdefs(\%objtype);
	if (!defined(%objhash))
	{
		my $rsp;
		push @{$rsp->{data}}, "Could not get xCAT object definitions.\n";
	    xCAT::MsgUtils->message("E", $rsp, $::callback);
    	return 1;
	}

	#
	#  Create config file for each node
	#       - will contain list of scripts to run on node
	#       - use postscripts.rules & postcripts dir
	#

	#Get the network info for each node
	my %nethash = xCAT::DBobjUtils->getNetwkInfo(\@nodelist);

	foreach my $node (keys %objhash)
	{
		# need short host name for NIM client defs
		my $shorthost;
		($shorthost = $node) =~ s/\..*$//;
        chomp $shorthost;

        # get, check the node IP
        my $IP = inet_ntoa(inet_aton($node));
        chomp $IP;
        unless ($IP =~ /\d+\.\d+\.\d+\.\d+/)
        {
                next;
        }

        my $cosi = $::opt_c;

        my $cmd = qq~mkts -i $IP -m $nethash{$node}{'mask'} -g $nethash{$node}{'gateway'} -c $cosi -l $shorthost 2>&1~;

#ndebug
# add - this could take a while!

        my $output = xCAT::Utils->runcmd("$cmd", -1);
        if ($::RUNCMD_RC  != 0)
        {
			my $rsp;
			push @{$rsp->{data}}, "Could not create a NIM definition for \'$node\'.\n";
			if ($::verbose) {
				push @{$rsp->{data}}, "$output";
	    	}
			xCAT::MsgUtils->message("E", $rsp, $::callback);
			return 1;
        }
	}
	return 0;
}

#----------------------------------------------------------------------------

=head3  dsklsnode_usage

        Arguments:
        Returns:
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub dsklsnode_usage
{

	my $rsp;
	push @{$rsp->{data}}, "  mkdsklsnode - Create an AIX NIM diskless node using information from the xCAT database.\n";
	push @{$rsp->{data}}, "  Usage: ";
	push @{$rsp->{data}}, "\tmkdsklsnode [-h | --help ]";
	push @{$rsp->{data}}, "or";
	push @{$rsp->{data}}, "\tmkdsklsnode [-V] -c image_name noderange";
	xCAT::MsgUtils->message("I", $rsp, $::callback);
    return 0;
}
#----------------------------------------------------------------------------

=head3  dsklsimage_usage

        Arguments:
        Returns:
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub dsklsimage_usage
{
	my $rsp;
    push @{$rsp->{data}}, "  mkdsklsimage - Create an AIX NIM diskless image (SPOT/COSI).\n";
    push @{$rsp->{data}}, "  Usage: ";
    push @{$rsp->{data}}, "\tmkdsklsimage [-h | --help ]";
    push @{$rsp->{data}}, "or";
    push @{$rsp->{data}}, "\tmkdsklsimage -s source [-l <location>] [-V] image_name\n";
    xCAT::MsgUtils->message("I", $rsp, $::callback);
    return 0;
}

1;
