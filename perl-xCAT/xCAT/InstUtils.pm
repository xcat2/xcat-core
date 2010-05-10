#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::InstUtils;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

# if AIX - make sure we include perl 5.8.2 in INC path.
#       Needed to find perl dependencies shipped in deps tarball.
if ($^O =~ /^aix/i)
{
    use lib "/usr/opt/perl5/lib/5.8.2/aix-thread-multi";
    use lib "/usr/opt/perl5/lib/5.8.2";
    use lib "/usr/opt/perl5/lib/site_perl/5.8.2/aix-thread-multi";
    use lib "/usr/opt/perl5/lib/site_perl/5.8.2";
}

use lib "$::XCATROOT/lib/perl";
require xCAT::Table;
use POSIX qw(ceil);
use Socket;
use Sys::Hostname;
use strict;
require xCAT::Schema;
use xCAT::NetworkUtils;

#require Data::Dumper;
use Data::Dumper;
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

sub getnimprime
{

    # the primary NIM master is either specified in the site table
    # or it is the xCAT management node.

    my $nimprime = xCAT::Utils->get_site_Master();
    my $sitetab  = xCAT::Table->new('site');
    (my $et) = $sitetab->getAttribs({key => "NIMprime"}, 'value');
    if ($et and $et->{value})
    {
        $nimprime = $et->{value};
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

    $name = hostname();

    if (xCAT::Utils->isMN())
    {

        # read the site table, master attrib
        my $hostname = xCAT::Utils->get_site_Master();
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

        # the myxcatpost_<nodename> file should exist on all nodes!
        my $catcmd = "cat /xcatpost/myxcatpost_* | grep '^NODE='";
        my $output = xCAT::Utils->runcmd("$catcmd", -1);
        if ($::RUNCMD_RC == 0)
        {
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

    # convert to IP
    my $nameIP = xCAT::NetworkUtils->getipaddr($name);
    chomp $nameIP;

    # split into octets
    #my ($b1, $b2, $b3, $b4) = split /\./, $nameIP;

    # get all the possible IPs for the node I'm running on
    my $ifcmd = "ifconfig -a | grep 'inet'";
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
        $myIP =~ s/\/.*//; # ipv6 address 4000::99/64
        $myIP =~ s/\%.*//; # ipv6 address ::1%1/128

        if ($myIP eq $nameIP)
        {
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
        my $rsp;
        push @{$rsp->{data}}, "Could not run lsnim command: \'$cmd\'.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return undef;
    }

    # The command output may have the xdsh prefix "target:"
    #my ($junk, $junk, $junk, $loc) = split(/:/, $nout);
    #chomp $loc;
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
			$serv = xCAT::Utils->getFacingIP($node);
        }
		chomp $serv;

		if (xCAT::Utils->validate_ip($serv)) {
			push (@{$servernodes{$serv}}, $node);
		}
    }

	return \%servernodes;
}


1;
