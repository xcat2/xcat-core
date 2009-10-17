#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::InstUtils;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

# if AIX - make sure we include perl 5.8.2 in INC path.
#       Needed to find perl dependencies shipped in deps tarball.
if ($^O =~ /^aix/i) {
        use lib "/usr/opt/perl5/lib/5.8.2/aix-thread-multi";
        use lib "/usr/opt/perl5/lib/5.8.2";
        use lib "/usr/opt/perl5/lib/site_perl/5.8.2/aix-thread-multi";
        use lib "/usr/opt/perl5/lib/site_perl/5.8.2";
}

use lib "$::XCATROOT/lib/perl";
require xCAT::Table;
use POSIX qw(ceil);
use Socket;
use strict;
require xCAT::Schema;
require Data::Dumper;
require xCAT::NodeRange;
require DBI;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(genpassword);

#-------------------------------------------------------------------------------

=head1    xCAT::InstUtils

=head2    Package Description

This program module file, is a set of utilities used by xCAT install
related commands.

=cut

#-------------------------------------------------------------

#----------------------------------------------------------------------------

=head3  getnimprime

	Get the name of the primary AIX NIM master

    Returns:

			hostname - short hostname of primary NIM master
			undef	 - could not find primary NIM master
    Example:

		my $nimprime = xCAT::InstUtils->getnimprime();
    Comments:

=cut

#-----------------------------------------------------------------------------

sub  getnimprime
{

	# the primary NIM master is either specified in the site table
	# or it is the xCAT management node.

	my $nimprime = xCAT::Utils->get_site_Master();
	my $sitetab = xCAT::Table->new('site');
	(my $et) = $sitetab->getAttribs({key => "NIMprime"}, 'value');
	if ($et and $et->{value}) {
		$nimprime = $et->{value};
	}

	my $hostname;
	if ($nimprime) {
		if ($nimprime =~ /\d+\.\d+\.\d+\.\d+/) {
			my $packedaddr = inet_aton($nimprime);
			$hostname = gethostbyaddr($packedaddr, AF_INET);
		} else {
			$hostname = $nimprime;
		}

		my $shorthost;
		($shorthost = $hostname) =~ s/\..*$//;
		chomp $shorthost;
		return $shorthost;
	} 

	return undef;
}

#----------------------------------------------------------------------------

=head3  myxCATname

	Gets the name of the node I'm running on - as known by xCAT
	(Either the management node or a service node)


=cut

#-----------------------------------------------------------------------------

sub myxCATname
{
	my ($junk, $name);

	$name = hostname();

	if (xCAT::Utils->isMN()) {
		# read the site table, master attrib
		my $hostname = xCAT::Utils->get_site_Master(); 
		if ($hostname =~ /\d+\.\d+\.\d+\.\d+/) {
			my $packedaddr = inet_aton($hostname);
			$name = gethostbyaddr($packedaddr, AF_INET);
		} else {
			$name = $hostname;
		}

	} elsif (xCAT::Utils->isServiceNode()) {

		# the myxcatpost_<nodename> file should exist on all nodes!
		my $catcmd="cat /xcatpost/myxcatpost_* | grep '^NODE='";
		my $output = xCAT::Utils->runcmd("$catcmd", -1);
		if ($::RUNCMD_RC == 0) {
			($junk, $name) = split('=', $output);
		}
	}

	my $shorthost;
    ($shorthost = $name) =~ s/\..*$//;
    chomp $shorthost;
    return $shorthost;
}

#----------------------------------------------------------------------------

=head3  is_me

	returns 1 if the hostname is the node I am running on

	Gets all the interfcaes defined on this node and sees if 
		any of them match the IP of the hostname passed in

    Arguments:
        none
    Returns:
        1 -  this is the node I am running on
        0 -  this is not the node I am running on
    Globals:
        none
    Error:
        none
    Example:
         if (xCAT::InstUtils->is_me(&somehostname)) { blah; }
    Comments:
        none

=cut

#-----------------------------------------------------------------------------

sub is_me
{
    my ($class, $name) = @_;
	#my $name = shift;

	# convert to IP
	my $nameIP = inet_ntoa(inet_aton($name));
    chomp $nameIP;

	# split into octets
	my ($b1, $b2, $b3, $b4) = split /\./, $nameIP;

	# get all the possible IPs for the node I'm running on
    my $ifcmd = "ifconfig -a | grep 'inet '";
    my $result = xCAT::Utils->runcmd($ifcmd, 0, 1);
    if ($::RUNCMD_RC != 0)
    {
		my $rsp;
	#	push @{$rsp->{data}}, "Could not run $ifcmd.\n";
    #    xCAT::MsgUtils->message("E", $rsp, $callback);
		return 0;
    }

    foreach my $int (@$result)
    {
        my ($inet, $myIP, $str) = split(" ", $int);
		chomp $myIP;
		# Split the two ip addresses up into octets
    	my ($a1, $a2, $a3, $a4) = split /\./, $myIP;		

		if ( ($a1 == $b1) && ($a2 == $b2) && ($a3 == $b3) && ($a4 == $b4) ) {
			return 1;
		}		
    }
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

				xCAT::InstUtils->get_nim_attr_val

        Comments:
=cut

#-----------------------------------------------------------------------------
sub get_nim_attr_val 
{
	my $class = shift;
	my $resname = shift;
	my $attrname = shift;
	my $callback = shift;
	my $target = shift;

	if (!$target) {
		$target = xCAT::InstUtils->getnimprime();
	}
	chomp $target;

	my $cmd = "/usr/sbin/lsnim -a $attrname -Z $resname 2>/dev/null";
    my $nout = xCAT::InstUtils->xcmd($callback, "xdsh", $target, $cmd, 0);
    if ($::RUNCMD_RC  != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not run lsnim command: \'$cmd\'.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return undef;
    }

    my ($junk, $junk, $junk, $loc) = split(/:/, $nout);
    chomp $loc;

    return $loc;
}



#-------------------------------------------------------------------------------

=head3	xcmd
		Run command either locally or on a remote system.
		Calls either runcmd or runxcmd and does either xdcp or xdsh.

 	Arguments:

   	Returns:
		Output of runcmd or runxcmd or blank.

   	Comments:

	ex.	xCAT::InstUtils->xcmd($callback, "xdcp", $nimprime, $cmd);
=cut

#-------------------------------------------------------------------------------
sub xcmd
{
	my $class = shift;
	my $callback = shift;
	my $xdcmd = shift;		# xdcp or xdsh
	my $target = shift;		# the node to run it on
	my $cmd = shift; 		# the actual cmd to run
	my $doarray = shift;    # should the return be a string or array ptr?

	my $returnformat = 0;   # default is to return string
	my $exitcode = 0;
	if ($doarray) {
		$returnformat = $doarray;
	}

	my $output;
    if (xCAT::InstUtils->is_me($target)) {
        $output=xCAT::Utils->runcmd($cmd, $exitcode, $returnformat);

    } else {
        # need xdsh or xdcp
        my @snodes;
        push( @snodes, $target );
        $output=xCAT::Utils->runxcmd(
                                {
                                    command => [$xdcmd],
                                    node    => \@snodes,
                                    arg     => [ $cmd ]
                                },
                                $::sub_req,
                                $exitcode, $returnformat
        );
    }

	if ($::VERBOSE) {
		my $rsp;
		if(ref($output) eq 'ARRAY'){
			if (scalar(@$output)) {
				push @{$rsp->{data}}, "Running command \'$cmd\' on \'$target\'\n";
				push @{$rsp->{data}}, "Output from command: \'@$output\'.\n";
				xCAT::MsgUtils->message("I", $rsp, $callback);
			}
		} else {
			if ($output) {	
				push @{$rsp->{data}}, "Running command \'$cmd\' on \'$target\'\n";
				push @{$rsp->{data}}, "Output from command: \'$output\'.\n";
				xCAT::MsgUtils->message("I", $rsp, $callback);
			}
		}
	}

	return $output;
}

#----------------------------------------------------------------------------

=head3 readBNDfile

	Get the contents of a NIM installp_bundle file based on the name
		of the NIM resource.

=cut

#-----------------------------------------------------------------------------
sub  readBNDfile
{

	my ($class, $callback, $BNDname, $nimprime) = @_;

	my $junk;
	my @pkglist,
	my $pkgname;

	# get the location of the file from the NIM resource definition
	my $bnd_file_name = xCAT::InstUtils->get_nim_attr_val($BNDname, 'location', $callback, $nimprime);

	# open the file
	unless (open(BNDFILE, "<$bnd_file_name")) {
		return (1);
	}

	# get the names of the packages
	while (my $l = <BNDFILE>) {

		chomp $l;

		# skip blank and comment lines
        next if ($l =~ /^\s*$/ || $l =~ /^\s*#/);

		push (@pkglist, $l);
	}
	close(BNDFILE);

	return (0, \@pkglist, $bnd_file_name);
}


1;
