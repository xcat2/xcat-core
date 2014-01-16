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
	unshift(@INC, qw(/usr/opt/perl5/lib/5.8.2/aix-thread-multi /usr/opt/perl5/lib/5.8.2 /usr/opt/perl5/lib/site_perl/5.8.2/aix-thread-multi /usr/opt/perl5/lib/site_perl/5.8.2));
}

use lib "$::XCATROOT/lib/perl";
require xCAT::Table;
use POSIX qw(ceil);
use Socket;
use Sys::Hostname;
use File::Basename;
use File::Path;
use strict;
require xCAT::Schema;
use xCAT::NetworkUtils;
use xCAT::TableUtils;
#require Data::Dumper;
#use Data::Dumper;
require xCAT::NodeRange;
require DBI;

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

sub getnimprime
{

    # the primary NIM master is either specified in the site table
    # or it is the xCAT management node.

    my $nimprime = xCAT::TableUtils->get_site_Master();
    #my $sitetab  = xCAT::Table->new('site');
    #(my $et) = $sitetab->getAttribs({key => "nimprime"}, 'value');
    my @nimprimes = xCAT::TableUtils->get_site_attribute("nimprime");
    my $tmp = $nimprimes[0];
    if (defined($tmp))
    {
        $nimprime = $tmp;
    }

    my $hostname;
    if ($nimprime)
    {
        if (($nimprime =~ /\d+\.\d+\.\d+\.\d+/) || ($nimprime =~ /:/))
        {
            $hostname = xCAT::NetworkUtils->gethostname($nimprime);
        }
        else
        {
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

	# make sure xcatd is running - & db is available
	#    this routine is called during initial install of xCAT
	my $cmd="lsxcatd -d > /dev/null 2>&1";
	my $outref = [];
	@$outref = `$cmd`;
	my $rc = $? >> 8;
	if ($rc == 0)
	{
		if (xCAT::Utils->isMN())
		{
        	# read the site table, master attrib
        	my $hostname = xCAT::TableUtils->get_site_Master();
        	if (($hostname =~ /\d+\.\d+\.\d+\.\d+/) || ($hostname =~ /:/))
        	{
            	$name = xCAT::NetworkUtils->gethostname($hostname);
        	}
        	else
        	{
            	$name = $hostname;
        	}
		}
		elsif (xCAT::Utils->isServiceNode())
		{
			my $filename;
			# get any files with the format myxcatpost_*
			my $lscmd = qq~/bin/ls /xcatpost/myxcatpost_*  2>/dev/null~;
			my $output = `$lscmd`;
			my $rc = $? >> 8;
    		if ($rc == 0)
        	{
				foreach my $line ( split(/\n/, $output)) {
					my ($junk, $hostname) = split('myxcatpost_', $line);
					if (xCAT::InstUtils->is_me($hostname)) {
						$filename="/xcatpost/myxcatpost_$hostname";
						last;
					}
				}

				if ( -e $filename ) {
					my $catcmd = qq~/bin/cat $filename | grep '^NODE=' 2>/dev/null~;
					my $string = `$catcmd`;
					if ($rc == 0) {
						($junk, $name) = split('=', $string);
					}
				}
        	}
	 	}
	}

	if (!$name) {
		$name = hostname();
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

    # convert to IP
    my $nameIP = xCAT::NetworkUtils->getipaddr($name);
    chomp $nameIP;

    # shut off verbose - just for this routine
    my $verb = $::VERBOSE;
    $::VERBOSE = 0;

    # split into octets
    #my ($b1, $b2, $b3, $b4) = split /\./, $nameIP;

    # get all the possible IPs for the node I'm running on
    my $ifcmd = "ifconfig -a | grep 'inet'";
    my $result = xCAT::Utils->runcmd($ifcmd, -1, 1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        #	push @{$rsp->{data}}, "Could not run $ifcmd.\n";
        #    xCAT::MsgUtils->message("E", $rsp, $callback);
		$::VERBOSE = $verb;
        return 0;
    }

    foreach my $int (@$result)
    {
        my ($inet, $myIP, $str) = split(" ", $int);
        chomp $myIP;
        $myIP =~ s/addr://;
        $myIP =~ s/\/.*//; # ipv6 address 4000::99/64
        $myIP =~ s/\%.*//; # ipv6 address ::1%1/128

        if ($myIP eq $nameIP)
        {
			$::VERBOSE = $verb;
            return 1;
        }
    }
	$::VERBOSE = $verb;
    return 0;
}

#----------------------------------------------------------------------------

=head3  get_nim_attrs

		Use the lsnim command to get the NIM attributes and values of
		a resource.

		Arguments:
		Returns:
			hash ref - OK
			undef - error
		Globals:

		Error:

		Example:

			$attrvals = xCAT::InstUtils->
				get_nim_attrs($res, $callback, $nimprime, $subreq);


		Comments:
=cut

#-----------------------------------------------------------------------------
sub get_nim_attrs
{
    my $class    = shift;
	my $resname  = shift;
	my $callback = shift;
	my $target   = shift;
	my $sub_req  = shift;

	my %attrvals = undef;

	if (!$target)
	{
		$target = xCAT::InstUtils->getnimprime();
	}
	chomp $target;

	my $cmd  = "/usr/sbin/lsnim -l $resname 2>/dev/null";

	my @nout = xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $target, $cmd, 1);
	if ($::RUNCMD_RC != 0)
	{
		my $rsp;
		push @{$rsp->{data}}, "Could not run lsnim command: \'$cmd\'.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return undef;
	}

	foreach my $line (@nout) {

		chomp $line;
		my $junk;
		my $attrval;
		if ($line =~ /.*$target:(.*)/) {
			($junk, $attrval) = split(/:/, $line);
		} else {
			$attrval = $line;
		}

		if ($attrval =~ /=/) {

			my ($attr, $val) = $attrval =~ /^\s*(\S+?)\s*=\s*(\S*.*)$/;


			if ($attr && $val) {
		#		$attrvals{$resname}{$attr} = $val;
				$attrvals{$attr} = $val;
			}
		}
	}

	if (%attrvals) {
		return \%attrvals;
	} else {
		return undef;
	}
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
    my $class    = shift;
    my $resname  = shift;
    my $attrname = shift;
    my $callback = shift;
    my $target   = shift;
    my $sub_req  = shift;

    if (!$target)
    {
        $target = xCAT::InstUtils->getnimprime();
    }
    chomp $target;

    my $cmd  = "/usr/sbin/lsnim -a $attrname -Z $resname 2>/dev/null";
    my $nout =
      xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $target, $cmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        return undef;
    }

    # The command output may have the xdsh prefix "target:"
    my $loc;
    if ($nout =~ /.*$resname:(.*):$/)
    {
        $loc = $1;
    }

    return $loc;
}

#-------------------------------------------------------------------------------

=head3	xcmd
		Run command either locally or on a remote system.
		Calls either runcmd or runxcmd and does either xdcp or xdsh.

 	Arguments:

   	Returns:
		Output of runcmd or runxcmd or undef.

   	Comments:

	ex.	xCAT::InstUtils->xcmd($callback, $sub_req, "xdcp", $nimprime, $doarray, $cmd);

=cut

#-------------------------------------------------------------------------------
sub xcmd
{
    my $class    = shift;
    my $callback = shift;
    my $sub_req  = shift;
    my $xdcmd    = shift;    # xdcp or xdsh
    my $target   = shift;    # the node to run it on
    my $cmd      = shift;    # the actual cmd to run
    my $doarray  = shift;    # should the return be a string or array ptr?

    my $returnformat = 0;    # default is to return string
    my $exitcode     = -1;   # don't display error
    if ($doarray)
    {
        $returnformat = $doarray;
    }

    # runxcmd uses global
    $::CALLBACK = $callback;

    my $output;
    if (!ref($target))
    {                        # must be node name
        if (xCAT::InstUtils->is_me($target))
        {
            $output = xCAT::Utils->runcmd($cmd, $exitcode, $returnformat);
        }
        else
        {
            my @snodes;
            push(@snodes, $target);
            $output =
              xCAT::Utils->runxcmd(
                                   {
                                    command => [$xdcmd],
                                    node    => \@snodes,
                                    arg     => ["-s", $cmd]
                                   },
                                   $sub_req,
                                   $exitcode,
                                   $returnformat
                                   );
        }
    }
    else
    {

        # it is an array ref
        my @snodes;
        @snodes = @{$target};
        $output =
          xCAT::Utils->runxcmd(
                               {
                                command => [$xdcmd],
                                node    => \@snodes,
                                arg     => ["-s", $cmd]
                               },
                               $sub_req,
                               $exitcode,
                               $returnformat
                               );
    }
    if ($returnformat == 1)
    {
        return @$output;
    }
    else
    {
        return $output;
    }

    return undef;
}

#----------------------------------------------------------------------------

=head3 readBNDfile

	Get the contents of a NIM installp_bundle file based on the name
		of the NIM resource.

=cut

#-----------------------------------------------------------------------------
sub readBNDfile
{

    my ($class, $callback, $BNDname, $nimprime, $sub_req) = @_;

    my $junk;
    my @pkglist, my $pkgname;

    # get the location of the file from the NIM resource definition
    my $bnd_file_name =
      xCAT::InstUtils->get_nim_attr_val($BNDname,  'location', $callback,
                                        $nimprime, $sub_req);

    # The boundle file may be on nimprime
    my $ccmd = qq~cat $bnd_file_name~;
    my $output=xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $nimprime, $ccmd, 0);
    if ($::RUNCMD_RC != 0) {
        my $rsp;
        push @{$rsp->{data}}, "Command: $ccmd failed.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
    }

    # get the names of the packages
    #$output =~ s/$nimprime:\s+//g;
    foreach my $line (split(/\n/, $output))
    {
        #May include xdsh prefix $nimprime:
        $line =~ s/$nimprime:\s+//;
        # skip blank and comment lines
        next if ($line =~ /^\s*$/ || $line =~ /^\s*#/);
        push(@pkglist, $line);
    }

    return (0, \@pkglist, $bnd_file_name);
}

#----------------------------------------------------------------------------

=head3   restore_request

		Restores an xcatd request from a remote management server
		into the proper format by removing arrays that were added by
		XML and removing tags that were added to numeric hash keys.

		Arguments:
        Returns:
                ptr to hash
                undef
        Globals:
        Example:
        Comments:

=cut

#-----------------------------------------------------------------------------
sub restore_request
{
    my $class     = shift;
    my $in_struct = shift;
    my $callback  = shift;

    my $out_struct;

    if (ref($in_struct) eq "ARRAY")
    {

        # flatten the array it it has only one element
        #  otherwise leave it alone
        if (scalar(@$in_struct) == 1)
        {
            return (xCAT::InstUtils->restore_request($in_struct->[0]));
        }
        else
        {
            return ($in_struct);
        }
    }

    if (ref($in_struct) eq "HASH")
    {
        foreach my $struct_key (keys %{$in_struct})
        {
            my $stripped_key = $struct_key;
            $stripped_key =~ s/^xxXCATxx(\d)/$1/;

            # do not flatten the arg or node arrays
            if (($stripped_key =~ /^arg$/) || ($stripped_key =~ /^node$/))
            {
                $out_struct->{$stripped_key} = $in_struct->{$struct_key};
            }
            else
            {
                $out_struct->{$stripped_key} =
                  xCAT::InstUtils->restore_request($in_struct->{$struct_key});
            }
        }
        return $out_struct;
    }

    if ((ref($in_struct) eq "SCALAR") || (ref(\$in_struct) eq "SCALAR"))
    {
        return ($in_struct);
    }

    print "Unsupported data reference in restore_request().\n";
    return undef;
}

#----------------------------------------------------------------------------

=head3   taghash

		Add a non-numeric tag to any hash keys that are numeric.  

		Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:
        Example:
        Comments:
			XML will choke on numeric values.  This happens when including
			a hash in a request to a remote service node.

=cut

#-----------------------------------------------------------------------
sub taghash
{
    my ($class, $hash) = @_;

    if (ref($hash) eq "HASH")
    {
        foreach my $k (keys %{$hash})
        {
            if ($k =~ /^(\d)./)
            {
                my $tagged_key = "xxXCATxx" . $k;
                $hash->{$tagged_key} = $hash->{$k};
                delete($hash->{$k});
            }
        }
        return 0;
    }
    else
    {
        return 1;
    }
}

#-------------------------------------------------------------------------------

=head3  getOSnodes
			Split a noderange into arrays of AIX and Linux nodes.

    Arguments:
			\@noderange - reference to onde list array
    Returns:
		$rc -
			1 - yes, all the nodes are AIX
			0 - no, at least one node is not AIX
		\@aixnodes - ref to array of AIX nodes
		\@linuxnodes - ref to array of Linux nodes
		

    Comments:
		Based on "os" attr of node definition. If attr is not set,
        defaults to OS of current system.   

	Example:
    	my ($rc, $AIXnodes, $Linuxnodes) 
					= xCAT::InstUtils->getOSnodes(\@noderange) 

=cut

#-------------------------------------------------------------------------------
sub getOSnodes
{

    my ($class, $nodes) = @_;

    my @nodelist = @$nodes;
    my $rc       = 1;         # all AIX nodes
    my @aixnodes;
    my @linuxnodes;

    my $nodetab = xCAT::Table->new('nodetype');
    my $os = $nodetab->getNodesAttribs(\@nodelist, ['node', 'os']);
    foreach my $n (@nodelist)
    {
        my $osname;
        if (defined($os->{$n}->[0]->{os})) {
            $osname = $os->{$n}->[0]->{os};
        } else {
            $osname =  $^O;
        }
        if (($osname ne "AIX") && ($osname ne "aix"))
        {
            push(@linuxnodes, $n);
            $rc = 0;
        }
        else
        {
            push(@aixnodes, $n);
        }
    }
    $nodetab->close;

    return ($rc, \@aixnodes, \@linuxnodes);
}

#-------------------------------------------------------------------------------

=head3   get_server_nodes

   		Determines the server node names as known by a lists of nodes. 

    Arguments:
		A list of node names.

    Returns:
		A hash ref  of arrays, the key is the service node pointing to
             an array of nodes that are serviced by that service node

    Example
		my %servernodes = &get_server_nodes($callback, \@$AIXnodes);

    Comments:
        - Code runs on MN or SNs

=cut

#-------------------------------------------------------------------------------
sub get_server_nodes
{
	my $class = shift;
	my $callback = shift;
	my $nodes = shift;

	my @nodelist;
	if ($nodes)
    {
        @nodelist = @$nodes;
    }

	#
    # get the server name for each node - as known by node
    #
    my $noderestab  = xCAT::Table->new('noderes');
    my $xcatmasters = $noderestab->getNodesAttribs(\@nodelist, ['node', 'xcatmaster']);
	$noderestab->close;

	my %servernodes;
    foreach my $node (@nodelist)
    {
		my $serv;
        if ($xcatmasters->{$node}->[0]->{xcatmaster})
        {
			# get ip of node xcatmaster attribute
			my $xcatmaster = $xcatmasters->{$node}->[0]->{xcatmaster};			
			$serv = xCAT::NetworkUtils->getipaddr($xcatmaster);
        }
        else
        {
            #  get ip facing node
			$serv = xCAT::NetworkUtils->my_ip_facing($node);
        }
		chomp $serv;

		if (xCAT::NetworkUtils->validate_ip($serv)) {
			push (@{$servernodes{$serv}}, $node);
		}
    }

	return \%servernodes;
}

#----------------------------------------------------------------------------

=head3   dolitesetup

        Update a spot with the statelite configuration

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:
        Example:
        Comments:

=cut

#-----------------------------------------------------------------------
sub dolitesetup
{
	my $class = shift;
	my $imagename = shift;
	my $imagehash = shift;
	my $nodes     = shift;
    my $callback = shift;
	my $subreq   = shift;
	my @litefiles;  # lists of entries in the litefile table

    my %imghash;
    if ($imagehash)
    {
        %imghash = %$imagehash;
    }

	# get name as known by xCAT
    my $Sname = xCAT::InstUtils->myxCATname();
    chomp $Sname;

	my $nimprime = xCAT::InstUtils->getnimprime();

    my $target;
    if (xCAT::Utils->isSN($Sname)) {
        $target=$Sname;
    } else {
        $target=$nimprime;
    }

	my @nodelist;
	my @nodel;
	my @nl;
    if ($nodes) {
        @nl = @$nodes;
		foreach my $n (@nl) {
			push(@nodel, xCAT::NodeRange::noderange($n));
		}
    }

	#
	#   Need to set the "provmethod" attr of the node defs or the litetree 
	#		cmd wil not get the info we need
	#

	my %nodeattrs;
    foreach my $node (@nodel)
    {
		chomp $node;
		$nodeattrs{$node}{objtype} = 'node';
        $nodeattrs{$node}{os}      = "AIX";
        $nodeattrs{$node}{profile}    = $imagename;
        $nodeattrs{$node}{provmethod} = $imagename;
    }
	if (xCAT::DBobjUtils->setobjdefs(\%nodeattrs) != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not set the \'provmethod\' attribute for nodes.\n";
        xCAT::MsgUtils->message("W", $rsp, $::callback);
    }

	# the node list is always "all" nodes.  There is only one version of the
	#  statelite, litefile and litetree files in an image and these files
	#	must always contain all the info from the corresponding database
	#	table.
	@nodelist= xCAT::DBobjUtils->getObjectsOfType('node');
	my $noderange;
	if (scalar(@nodelist) > 0)
	{
		$noderange = join(',',@nodelist);
	} else {
		my $rsp;
		push @{$rsp->{data}}, "Could not get list of xCAT nodes. No statelite configuration will be done.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 2;
	}

	# get spot inst_root loc
	my $spotloc = xCAT::InstUtils->get_nim_attr_val($imghash{$imagename}{spot}, 'location', $callback, $target, $subreq);

	my $instrootloc = $spotloc . "/lpp/bos/inst_root";

	# get the statelite info - put each table into it's own file
	my $statelitetab = xCAT::Table->new('statelite', -create=>1);
	my $litefiletab = xCAT::Table->new('litefile');
	my $litetreetab = xCAT::Table->new('litetree');

	# these will wind up in the root dir on the node ("/")
	my $statelitetable = "$instrootloc/statelite.table";
	my $litefiletable = "$instrootloc/litefile.table";
	my $litetreetable = "$instrootloc/litetree.table";

	# get rid of any old files
	if (-e $statelitetable) {
		my $rc = xCAT::Utils->runcmd("rm $statelitetable", -1);
		if ($::RUNCMD_RC != 0)
    	{
        	my $rsp;
        	push @{$rsp->{data}}, "Could not remove existing $statelitetable file.";
        	xCAT::MsgUtils->message("E", $rsp, $callback);
        	return 1;
    	}
	}

	if (-e $litefiletable) {
		my $rc = xCAT::Utils->runcmd("rm $litefiletable", -1);
		if ($::RUNCMD_RC != 0)
    	{
        	my $rsp;
        	push @{$rsp->{data}}, "Could not remove existing $litefiletable file.";
        	xCAT::MsgUtils->message("E", $rsp, $callback);
        	return 1;
    	}
	}

	if (-e $litetreetable) {
		my $rc = xCAT::Utils->runcmd("rm $litetreetable", -1);
		if ($::RUNCMD_RC != 0)
    	{
        	my $rsp;
        	push @{$rsp->{data}}, "Could not remove existing $litetreetable file.";
        	xCAT::MsgUtils->message("E", $rsp, $callback);
        	return 1;
    	}
	}

	#
	# create files for each statelite table.  add them to the SPOT. 
	#	use the "|" as a separator, remove all blanks from the entries.
	#	put them in $instrootloc location. they will be available as soon
	#	as the root dir is mounted during the  boot process.

	my $foundstatelite=0;
	unless (open(STATELITE, ">$statelitetable"))
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not open $statelitetable.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	# create the statelite table file
	my $foundentry=0;
	my $stateHash = $statelitetab->getNodesAttribs(\@nodelist, ['statemnt', 'mntopts']);
	foreach my $node (@nodelist) {

		# process statelite entry
		# add line to file for each node
		# note: if statement is xcatmn:/nodedata
    	# 	/nodedata is mounted to /.statelite/persistent
    	# 	then - on node - a nodename subdir is created

		my $statemnt="";
		my $mntopts;
        if (exists($stateHash->{$node})) {

			$mntopts = $stateHash->{$node}->[0]->{mntopts};
            $statemnt = $stateHash->{$node}->[0]->{statemnt};
            my ($server, $dir) = split(/:/, $statemnt);

            #if server is blank, then its the directory
            unless($dir) {
                $dir = $server;
                $server = '';
            }

			$dir = xCAT::SvrUtils->subVars($dir, $node, 'dir', $callback);
			$dir =~ s/\/\//\//g;

            if($server) {
                $server = xCAT::SvrUtils->subVars($server, $node, 'server', $callback);
				$server =~ s/\///g;    # remove "/" - bug in subVars??
				my $serverIP = xCAT::NetworkUtils->getipaddr($server);
				$statemnt = $serverIP . "|" . $dir;
            } else {
              	$statemnt = $dir;
			}
		}

		my $entry = qq~$node|$statemnt~;
		if ($mntopts) {
			$entry = qq~$node|$statemnt|$mntopts~;
		}
		$entry =~ s/\s*//g; #remove blanks

		if ($statemnt) {
			print STATELITE $entry . "\n";
			$foundentry++;
		}
	}
	close(STATELITE);

	if (!$foundentry) {
		# don't leave empty file
		my $rc = xCAT::Utils->runcmd("rm $statelitetable", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not remove $statelitetable file.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }

	}

	unless (open(LITEFILE, ">$litefiletable"))
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not open $litefiletable.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	my @filelist = xCAT::Utils->runcmd("/opt/xcat/bin/litefile $noderange", -1);
	if (scalar(@filelist) > 0) {
		foreach my $l (@filelist) {
			$l =~ s/://g;  # remove ":"'s
			$l =~ s/\s+/|/g;  # change separator to "|"
			print LITEFILE $l . "\n";
			push (@litefiles, $l);
			$foundstatelite++;
		}
		close(LITEFILE);
	} else {
    	close(LITEFILE);
		# remove empty files
		my $rc = xCAT::Utils->runcmd("rm $litefiletable", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not remove $litefiletable file.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
	}

	# need list for just this set of nodes!!!
	my $nrange;
	my @flist;
	my @litef;
	if (scalar(@nodel) > 0)
    {
        $nrange = join(',',@nodel);
    }

	my @flist = xCAT::Utils->runcmd("/opt/xcat/bin/litefile $nrange", -1);
    if (scalar(@flist) > 0) {
        foreach my $l (@flist) {
			my ($j1, $j2, $file) = split /\s+/, $l;
            push (@litef, $file);
        }
    }
	my $foundras;
	if (scalar(@litef) > 0) {
		foreach my $f (@litef) {
			chomp $f;
			if (($f eq "/var/adm/ras/") || ($f eq "/var/adm/ras/conslog")) {
				$foundras++;
			}
		}
	}
	if ($foundras) {
		my $rsp;
		push @{$rsp->{data}}, "One or more nodes is using a persistent \/var\/adm\/ras\/ directory.  \nWhen the nodes boot up you will then have to move the conslog file to a \nlocation outside of the persistent directory. (Leaving the conslog \nfile in a persistent directory can occasionally lead to a deadlock situation.) \nThis can be done by using the xdsh command to run swcons on the \ncluster nodes. \n(Ex. xdsh <noderange> \'\/usr\/sbin\/swcons -p \/tmp\/conslog\') \n";
		xCAT::MsgUtils->message("W", $rsp, $callback);
	}

	unless (open(LITETREE, ">$litetreetable"))
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not open $litetreetable.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }
	my @treelist = xCAT::Utils->runcmd("/opt/xcat/bin/litetree $noderange", -1);
	if (scalar(@treelist) > 0) {
		foreach my $l (@treelist) {
			my ($p, $serv, $dir, $mopts) = split (/:/, $l);
			$p =~ s/\s*//g;
			$serv =~ s/\s*//g;
			$dir =~ s/\s*//g;
			$mopts =~ s/\s*//g;
        	my $serverIP = xCAT::NetworkUtils->getipaddr($serv);
			my $entry = "$p|$serverIP|$dir|$mopts";
        	print LITETREE $entry . "\n";
			$foundstatelite++;
    	}
    	close(LITETREE);
	} else {
		close(LITETREE);
		# don't leave empty file
		my $rc = xCAT::Utils->runcmd("rm $litetreetable", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not remove $litetreetable file.";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
	}

	# if there is no statelite info then just return
	if (!$foundstatelite) {

        if ($::VERBOSE)
        {
            my $rsp;
            push @{$rsp->{data}}, "Please update statlite,litefile,litetree tables if you want to use AIX statelite support.\n";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }	

		return 2;
	}

	#
	# ok -  do more statelite setup
	#

	# create some local directories in the SPOT
	# 	create .default, .statelite, 
	if ( ! -d "$instrootloc/.default" ) {
		my $mcmd = qq~/bin/mkdir -m 644 -p $instrootloc/.default ~;
		my $output = xCAT::Utils->runcmd("$mcmd", -1);
        if ($::RUNCMD_RC != 0)
		{
			my $rsp;
			push @{$rsp->{data}}, "Could not create $instrootloc/.default.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}
	}

	if ( ! -d "$instrootloc/.statelite" ) {
        my $mcmd = qq~/bin/mkdir -m 644 -p $instrootloc/.statelite ~;
        my $output = xCAT::Utils->runcmd("$mcmd", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not create $instrootloc/.statelite.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
    }

	# populate the .defaults dir with files and dirs from the image - if any
	my $default="$instrootloc/.default";

	# read the litefile and try to copy into $default
	# everything in the litefile command output should be processed

    foreach my $line (@litefiles) {
        # $file could be full path file name or dir name
        # ex. /foo/bar/  or /etc/lppcfg
        my ($node, $option, $file) = split (/\|/, $line);

		if (!$file) {
			next;
       	}

        # ex. .../inst_root/foo/bar/  or .../inst_root/etc/lppcfg
        my $instrootfile = $instrootloc . $file;

        # there's one scenario to be handled firstly
        # in litefile table, there's one entry: /path/to/file, which is one file
        # however, there's already one directory named "/path/to/file/"
        # 
        # Or:
        # the entry in litefile is "/path/to/file/", which is one directory
        # however, there's already one file named "/path/to/file"
        # 
        # in these cases,
        # need to indicate the user there's already one existing file/directory in the spot
        # then, exit

        if ($file =~ m/\/$/ and -f $instrootfile)  {
            my $rsp;
            push @{$rsp->{data}}, qq{there is already one file named "$file", but the entry in litefile table is set to one directory, please check it};
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
        if ($file !~ m/\/$/ and -d $instrootfile) {
            my $rsp;
            push @{$rsp->{data}}, qq{there is already one directory named "$file", but the entry in litefile table is set to one file, please check it};
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
    }


	my @copiedfiles;
	foreach my $line (@litefiles) {

		# $file could be full path file name or dir name
		# ex. /foo/bar/  or /etc/lppcfg
		my ($node, $option, $file) = split (/\|/, $line);

		#  entry must be an absolute path
		unless ($file =~ m{^/}) {
			my $rsp;
			push @{$rsp->{data}}, "The litefile entry \'$file\' is not an absolute path name.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		} 

		# ex. /foo or /etc
		my $filedir = dirname($file);

		# ex. .../inst_root/foo/bar/  or .../inst_root/etc/lppcfg
		my $instrootfile = $instrootloc . $file;

		my $cpcmd;
		my $mkdircmd;
		my $output;

		if (!grep (/^$instrootfile$/, @copiedfiles)) {
			# don't copy same file twice
            push (@copiedfiles, $instrootfile);
			if (-e $instrootfile) {

				if (-d $instrootfile) {
					# it's a dir so copy everything in it
					# ex. mkdir -p ../inst_root/.default/foo/bar
					# ex. cp -r .../inst_root/foo/bar/ ../inst_root/.default/foo/bar

					if ( ! -e "$default$file" ) { # do mkdir
						$mkdircmd = qq~mkdir -p $default$file 2>/dev/null~;
						$output = xCAT::Utils->runcmd("$mkdircmd", -1);
						if ($::RUNCMD_RC != 0) {
							my $rsp;
                    		push @{$rsp->{data}}, "Could not copy create $default$file.";
                    		if ($::VERBOSE)
                    		{
                        		push @{$rsp->{data}}, "$output\n";
                    		}
                    		xCAT::MsgUtils->message("E", $rsp, $callback);
                		}
					}

					# ok  - do copy
					$cpcmd = qq~cp -p -r $instrootfile* $default$file 2>/dev/null~;
					$output = xCAT::Utils->runcmd("$cpcmd", -1);

				} else {
					# copy file
					# ex. mkdir -p ../inst_root/.default/etc
					# ex. cp .../inst_root/etc/lppcfg ../inst_root/.default/etc
					$cpcmd = qq~mkdir -p $default$filedir; cp -p $instrootfile $default$filedir 2>/dev/null~;
					$output = xCAT::Utils->runcmd("$cpcmd", -1);
				}
			} else {

				# could not find file or dir in ../inst_root (spot dir)
				# so create empty file or dir
				my $mkcmd;

				# check if it's a dir
				if(grep /\/$/, $file) {
					# create dir in .default
					if ( ! -d "$default$file" ) {
						$mkcmd = qq~mkdir -p $default$file~;
						$output = xCAT::Utils->runcmd("$mkcmd", -1);
                		if ($::RUNCMD_RC != 0)
                		{
                    		my $rsp;
                    		push @{$rsp->{data}}, "Could not create $default$file.\n";
                    		if ($::VERBOSE)
                    		{
                        		push @{$rsp->{data}}, "$output\n";
                    		}
                		} 
					}
				} else {
					# create dir and touch file in .default
					my $dir = dirname($file);
					if ( ! -d "$default$dir" ) {
						$mkcmd = qq~mkdir -p $default$dir~;
						$output = xCAT::Utils->runcmd("$mkcmd", -1);
                        if ($::RUNCMD_RC != 0)
                        {
                            my $rsp;
                            push @{$rsp->{data}}, "Could not create $default$dir.";
                            if ($::VERBOSE)
                            {
                                push @{$rsp->{data}}, "$output\n";
                            }
                        }
					}

					# touch the file
 					my $tcmd = qq~touch $default$file~;
					$output = xCAT::Utils->runcmd("$tcmd", -1);
					if ($::RUNCMD_RC != 0)
					{
						my $rsp;
						push @{$rsp->{data}}, "Could not create $default$file.\n";
						if ($::VERBOSE)
						{
							push @{$rsp->{data}}, "$output\n";
						}
						xCAT::MsgUtils->message("E", $rsp, $callback);
					}
				}	
			} # end - if not exist in spot
		} # end - if not already copied
	} # end - for each line in litefile

	# add aixlitesetup to ..inst_root/aixlitesetup
	# this will wind up in the root dir on the node ("/")
	my $install_dir = xCAT::TableUtils->getInstallDir();
	my $cpcmd = "/bin/cp $install_dir/postscripts/aixlitesetup $instrootloc/aixlitesetup; chmod +x $instrootloc/aixlitesetup";

	my $out = xCAT::Utils->runcmd("$cpcmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not copy aixlitesetup.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	# if this is an update then we need to copy the new files to
	#   the shared_root location
	#		???  - maybe we should try this all the time????
	if (1) {
		# if we have a shared_root resource
		if ($imghash{$imagename}{shared_root} ) {
			my $nimprime = xCAT::InstUtils->getnimprime();
    		chomp $nimprime;
			# get the location of the shared_root directory
			my $SRloc = xCAT::InstUtils->get_nim_attr_val($imghash{$imagename}{shared_root}, 'location', $callback, $Sname, $subreq);

			# copy the statelite table file to the shared root location
			# this will not effect any running nodes that are using 
			#	this shared_root resource.  However the new table will
			#	include any info need for existing nodes - for when they 
			#	need to be rebooted

			if (-d $SRloc) {
			    my $ccmd = "/bin/cp";
			    if (-e $statelitetable)
			    {
			        $ccmd .= " $statelitetable";
			    }

			    if (-e $litefiletable)
			    {
			        $ccmd .= " $litefiletable";
			    }

			    if (-e $litetreetable)
			    {
			        $ccmd .= " $litetreetable";
			    }
			    
			    $ccmd .= " $instrootloc/aixlitesetup $SRloc";
				my $out = xCAT::Utils->runcmd("$ccmd", -1);
				if ($::RUNCMD_RC != 0)
				{
					my $rsp;
					push @{$rsp->{data}}, "Could not copy statelite files to $SRloc.";
					xCAT::MsgUtils->message("E", $rsp, $callback);
					return 1;
				}

				# also copy $instrootloc/.default contents
				$ccmd = "/usr/bin/cp -p -r $instrootloc/.default $SRloc";
				$out = xCAT::Utils->runcmd("$ccmd", -1);
				if ($::RUNCMD_RC != 0)
				{
					my $rsp;
					push @{$rsp->{data}}, "Could not copy $instrootloc/.default to $SRloc.";
					xCAT::MsgUtils->message("E", $rsp, $callback);
					return 1;
				}

				# also copy $instrootloc/.statelite contents
				$ccmd = "/usr/bin/cp -p -r $instrootloc/.statelite $SRloc";
				$out = xCAT::Utils->runcmd("$ccmd", -1);
				if ($::RUNCMD_RC != 0)
				{
					my $rsp;
					push @{$rsp->{data}}, "Could not copy $instrootloc/.statelite to $SRloc.";
					xCAT::MsgUtils->message("E", $rsp, $callback);
					return 1;
				}
			}
		}
	}
	return 0;
}

#----------------------------------------------------------------------------

=head3  convert_xcatmaster

    Convert the keyword <xcatmaster> of nameservers attr in site/networks table to IP address.
    (Either the management node or a service node)

=cut

#-----------------------------------------------------------------------------

sub convert_xcatmaster
{
    my $shorthost = xCAT::InstUtils->myxCATname();
    my $selfip = xCAT::NetworkUtils->getipaddr($shorthost);

    return $selfip;
}

1;
