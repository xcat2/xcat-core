#!/usr/bin/env perl -w
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#####################################################
#
#  xCAT plugin package to handle the following commands.
#	 mkdsklsnode, rmdsklsnode, mknimimage,
#	 rmnimimage, chkosimage, nimnodecust,  & nimnodeset
#
#####################################################

package xCAT_plugin::aixinstall;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use Sys::Hostname;
use File::Basename;
use xCAT::NodeRange;
use xCAT::Schema;
use xCAT::Utils;
use xCAT::NetworkUtils;
use xCAT::InstUtils;
use xCAT::DBobjUtils;
use XML::Simple;
use Data::Dumper;
use Getopt::Long;
use xCAT::MsgUtils;
use strict;
use Socket;
use File::Path;

# options can be bundled up like -vV
Getopt::Long::Configure("bundling");
$Getopt::Long::ignorecase = 0;


my $errored = 0;


#------------------------------------------------------------------------------

=head1    aixinstall

This program module file supports the mkdsklsnode, rmdsklsnode,
rmnimimage, chkosimage, mknimimage, nimnodecust, & nimnodeset commands.


=cut

#------------------------------------------------------------------------------

=head2    xCAT for AIX support

=cut

#------------------------------------------------------------------------------
#----------------------------------------------------------------------------

=head3  pass_along

        The call back function for prescripts invocation

=cut

#-----------------------------------------------------------------------------
sub pass_along { 
    my $resp = shift;
    if ($resp and ($resp->{errorcode} and $resp->{errorcode}->[0]) or ($resp->{error} and $resp->{error}->[0])) {
        $errored=1;
    }
    foreach (@{$resp->{node}}) {
	if ($_->{error} or $_->{errorcode}) {
	    $errored=1;
	}
    }
    $::callback->($resp);
}

#----------------------------------------------------------------------------

=head3  handled_commands

        Return a list of commands handled by this plugin

=cut

#-----------------------------------------------------------------------------

sub handled_commands
{
    return {
            mknimimage  => "aixinstall",
            rmnimimage  => "aixinstall",
			chkosimage  => "aixinstall",
            mkdsklsnode => "aixinstall",
            rmdsklsnode => "aixinstall",
            nimnodeset  => "aixinstall",
            nimnodecust => "aixinstall"
            };
}

#-------------------------------------------------------

=head3  preprocess_request

  Check and setup for hierarchy

=cut

#-------------------------------------------------------
sub preprocess_request
{
    my $req     = shift;
    my $cb      = shift;
    my $sub_req = shift;

    my $command = $req->{command}->[0];
    $::args     = $req->{arg};
    $::filedata = $req->{stdin}->[0];

    my %sn;

    # need for runcmd output
    $::CALLBACK = $cb;

    # don't want preprocess to run on service node but _xcatdest is not set??
    #if ($req->{_xcatdest}) { return [$req]; }    #exit if preprocessed

    my $nodes   = $req->{node}; # this may not be the list of nodes we need!
    my $service = "xcat";
    my @requests;
    my $lochash;
    my $nethash;
    my $nodehash;
    my $imagehash;
    my $attrs;
    my $locs;

    # get this systems name as known by xCAT management node
    my $Sname = xCAT::InstUtils->myxCATname();
    chomp $Sname;

    # get the name of the primary NIM server
    #	- either the NIMprime attr of the site table or the management node
    my $nimprime = xCAT::InstUtils->getnimprime();
    chomp $nimprime;
    my $nimprimeip = xCAT::NetworkUtils->getipaddr($nimprime);
    if ($nimprimeip =~ /:/) #IPv6, needs NFSv4 support
    {
        $::NFSV4 = 1;
    }

    #exit if preprocessed
    # if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }

    # if this is a service node and not the NIM primary then just return
    #       don't want to do preprocess again

    if (xCAT::Utils->isServiceNode() && !xCAT::InstUtils->is_me($nimprime))
    {
        return [$req];
    }

    #
    # preprocess each cmd - (help, version, gather data etc.)
    #	set up requests for service nodes
    #

    if ($command =~ /mknimimage/)


    {

        my $reqcopy = {%$req};
        $reqcopy->{'_xcatdest'} = $nimprime;
        push @requests, $reqcopy;

        return \@requests;
    }

    if ($command =~ /rmnimimage/)
    {
        # take care of -h etc.
        # also get osimage hash to pass on!!
        my ($rc, $imagehash, $servers) = &prermnimimage($cb, $sub_req);
        if ($rc)
        {    # either error or -h was processed etc.
            my $rsp;
            if ($rc eq "1")
            {
                $rsp->{errorcode}->[0] = $rc;
                push @{$rsp->{data}}, "Return=$rc.";
                xCAT::MsgUtils->message("E", $rsp, $cb, $rc);
            }
            return undef;
        }

        # if something more than -h etc. then pass on the request
        if (defined($imagehash) && scalar(@{$servers}))
        {
            foreach my $snkey (@{$servers})
            {
                my $reqcopy = {%$req};
                $reqcopy->{'_xcatdest'} = $snkey;

                #$reqcopy->{_xcatpreprocessed}->[0] = 1;
                if ($imagehash)
                {

                    # add tags to the hash keys that start with a number
                    xCAT::InstUtils->taghash($imagehash);
                    $reqcopy->{'imagehash'} = $imagehash;
                }
                push @requests, $reqcopy;
            }
            return \@requests;
        }
        else
        {
            return undef;
        }
    }

	if ($command =~ /chkosimage/)
	{
		my $reqcopy = {%$req};
		$reqcopy->{'_xcatdest'} = $nimprime;
		push @requests, $reqcopy;

		return \@requests;
	}

    # these commands might be merged some day??
    if (($command =~ /nimnodeset/) || ($command =~ /mkdsklsnode/))
    {
        my ($rc, $nodehash, $nethash, $imagehash, $lochash, $attrs, $nimhash, $mynodes, $type) = &prenimnodeset($cb, $command, $sub_req);

        if ($rc)
        {    # either error or -h was processed etc.
            my $rsp;
            if ($rc eq "1")
            {
                $rsp->{errorcode}->[0] = $rc;
                push @{$rsp->{data}}, "Return=$rc.";
                xCAT::MsgUtils->message("E", $rsp, $cb, $rc);
            }
            return undef;
        }

		if (scalar(@{$mynodes})) {
        	# set up the requests to go to the service nodes
			my $snodes;
			$snodes = xCAT::Utils->getSNformattedhash($mynodes, $service, "MN", $type);

        	foreach my $snkey (keys %$snodes)
        	{
            	my $reqcopy = {%$req};
            	$reqcopy->{node} = $snodes->{$snkey};
            	$reqcopy->{'_xcatdest'} = $snkey;

            	# might as well pass along anything we had to look up
            	#   in the preprocessing
            	if ($nodehash)
            	{

                	# add tags to the hash keys that start with a number
                	#  XML cannot handle keys that start with number
                	xCAT::InstUtils->taghash($nodehash);
                	$reqcopy->{'nodehash'} = $nodehash;
            	}

            	if ($imagehash)
            	{
                	xCAT::InstUtils->taghash($imagehash);
                	$reqcopy->{'imagehash'} = $imagehash;
            	}

            	if ($lochash)
            	{
                	xCAT::InstUtils->taghash($lochash);
                	$reqcopy->{'lochash'} = $lochash;
            	}

            	if ($nethash)
            	{
                	xCAT::InstUtils->taghash($nethash);
                	$reqcopy->{'nethash'} = $nethash;
            	}

            	if ($attrs)
            	{
                	$reqcopy->{'attrval'} = $attrs;
            	}

				if ($nimhash)
				{
					xCAT::InstUtils->taghash($nimhash);
					$reqcopy->{'nimhash'} = $nimhash;
				}
				push @requests, $reqcopy;
			}
        }
        return \@requests;
    }

    if ($command =~ /nimnodecust/)
    {

		#
		#  THIS COMMAND IS NO LONGER SUPPORTED!!!
		#
        # handle -h etc.
        # copy stuff to service nodes

        my ($rc, $bndloc) = &prenimnodecust($cb, $nodes, $sub_req);
        if ($rc)
        {    # either error or -h was processed etc.
            my $rsp;
            if ($rc eq "1")
            {
                $rsp->{errorcode}->[0] = $rc;
                push @{$rsp->{data}}, "Return=$rc.";
                xCAT::MsgUtils->message("E", $rsp, $cb, $rc);
            }
            return undef;
        }

		my $sn;
		if ($nodes)
		{
			$sn = xCAT::Utils->getSNformattedhash($nodes, $service, "MN");
		}

        # set up the requests to go to the service nodes
        #   all get the same request
        foreach my $snkey (keys %$sn)
        {
            my $reqcopy = {%$req};
            $reqcopy->{node} = $sn->{$snkey};
            $reqcopy->{'_xcatdest'} = $snkey;
            if ($bndloc)
            {

                # add tags to the hash keys that start with a number
                xCAT::InstUtils->taghash($bndloc);
                $reqcopy->{'lochash'} = $bndloc;
            }

            push @requests, $reqcopy;
        }
        return \@requests;
    }

    if ($command =~ /rmdsklsnode/)
    {
        # handle -h etc.
		my ($rc, $mynodes, $type) = &prermdsklsnode($cb, $sub_req);

        if ($rc)
        {    # either error or -h was processed etc.
            my $rsp;
            if ($rc eq "1")
            {
                $rsp->{errorcode}->[0] = $rc;
                push @{$rsp->{data}}, "Return=$rc.";
                xCAT::MsgUtils->message("E", $rsp, $cb, $rc);
            }
            return undef;
        }
        elsif (scalar(@{$mynodes})) 
        {
            # set up the requests to go to the service nodes
            #   all get the same request
			my $snodes;
			$snodes = xCAT::Utils->getSNformattedhash($mynodes, $service, "MN", $type);
			foreach my $snkey (keys %$snodes)
            {
                my $reqcopy = {%$req};
                $reqcopy->{node} = $snodes->{$snkey};
                $reqcopy->{'_xcatdest'} = $snkey;

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

    $::callback = $callback;

    # need for runcmd output
    $::CALLBACK = $callback;

    # convert the hashes back to the way they were passed in
    #   XML created arrays - we need to strip them out
    my $flatreq = xCAT::InstUtils->restore_request($request, $callback);

    my $command = $flatreq->{command};
    $::args     = $flatreq->{arg};
    $::filedata = $flatreq->{stdin}->[0];
    $::cwd      = $flatreq->{cwd};

    # set the data passed in by the preprocess_request routine
    my $nodehash  = $flatreq->{'nodehash'};
    my $nethash   = $flatreq->{'nethash'};
    my $imagehash = $flatreq->{'imagehash'};
    my $lochash   = $flatreq->{'lochash'};
    my $attrval   = $flatreq->{'attrval'};
	my $nimhash   = $flatreq->{'nimhash'};
    my $nodes     = $flatreq->{node};

    my $ip_forwarding_enabled = xCAT::NetworkUtils->ip_forwarding_enabled();
    my $gwerr = 0;
    foreach my $fnode (keys %{$nethash})
    {
        if($nethash->{$fnode}->{'myselfgw'} eq '1')
        {
            if ($ip_forwarding_enabled)
            {
                $nethash->{$fnode}->{'gateway'} = xCAT::NetworkUtils->my_ip_in_subnet($nethash->{$fnode}->{'net'}, $nethash->{$fnode}->{'mask'});
            }
            else
            {
                $gwerr = 1;
                $nethash->{$fnode}->{'gateway'} = '';
            }
        }
     }

    if($gwerr == 1)
    {
        my $rsp;

        my $name = hostname();
        my $msg = "The ipforwarding is not enabled on $name, it will not be able to act as default gateway for the compute nodes, check the ipforward setting in servicenode table or enable ipforwarding manually.\n"; 
        push @{$rsp->{data}}, $msg;
        xCAT::MsgUtils->message("E", $rsp, $callback);
    }
        
    # figure out which cmd and call the subroutine to process
    if ($command eq "mkdsklsnode")
    {
        ($ret, $msg) =
          &mkdsklsnode($callback,  $nodes,   $nodehash, $nethash,
                       $imagehash, $lochash, $nimhash, $sub_req);
    }
    elsif ($command eq "mknimimage")
    {
        ($ret, $msg) = &mknimimage($callback, $sub_req);
    }
    elsif ($command eq "rmnimimage")
    {
        ($ret, $msg) = &rmnimimage($callback, $imagehash, $sub_req);
    }
	elsif ($command eq "chkosimage")
	{
		($ret, $msg) = &chkosimage($callback, $imagehash, $sub_req);
	}
    elsif ($command eq "rmdsklsnode")
    {
        ($ret, $msg) = &rmdsklsnode($callback, $nodes, $sub_req);
    }
    elsif ($command eq "nimnodeset")
    {
        ($ret, $msg) =
          &nimnodeset($callback,  $nodes,   $nodehash, $nethash,
                      $imagehash, $lochash, $nimhash, $sub_req);
    }

    elsif ($command eq "nimnodecust")
    {
        ($ret, $msg) = &nimnodecust($callback, $lochash, $nodes, $sub_req);
    }

    if ($ret > 0)
    {
        my $rsp;

        if ($msg)
        {
            push @{$rsp->{data}}, $msg;
        }
        else
        {
            push @{$rsp->{data}}, "Return=$ret.";
        }

        $rsp->{errorcode}->[0] = $ret;

        xCAT::MsgUtils->message("E", $rsp, $callback, $ret);

    }
    return 0;
}

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
    my $nodes    = shift;
    my $nodehash = shift;
    my $nethash  = shift;
    my $imaghash = shift;
    my $locs     = shift;
	my $nimres   = shift;
    my $subreq   = shift;

    my %lochash   = %{$locs};
    my %objhash   = %{$nodehash};    # node definitions
    my %nethash   = %{$nethash};
    my %imagehash = %{$imaghash};    # osimage definition
    my @nodelist  = @$nodes;
	my %nimhash   = %{$nimres};

    my $error = 0;
    my @nodesfailed;
    my $image_name;

    # some subroutines require a global callback var
    #	- need to change to pass in the callback
    #	- just set global for now
    $::callback = $callback;

    my $Sname = xCAT::InstUtils->myxCATname();

    if (defined(@{$::args}))
    {
        @ARGV = @{$::args};
    }
    else
    {
        &nimnodeset_usage($callback);
        return 0;
    }

    # parse the options
    Getopt::Long::Configure("no_pass_through");
    if (
        !GetOptions(
					'b|backupSN'  => \$::BACKUP,
                    'f|force'   => \$::FORCE,
                    'h|help'    => \$::HELP,
                    'i=s'       => \$::OSIMAGE,
					'l=s'       => \$::opt_l,
					'p|primarySN' => \$::PRIMARY,
                    'verbose|V' => \$::VERBOSE,
                    'v|version' => \$::VERSION,
                    'nfsv4'     => \$::NFSV4,
        )
      )
    {
        &nimnodeset_usage($callback);
        return 1;
    }

    my %objtype;
    my %attrs;          # attr=val pairs from cmd line
    my %cmdargs;        # args for the "nim -o bos_inst" cmd line
    my @machines;       # list of defined NIM machines
    my @nimrestypes;    # list of NIM resource types

    # the first arg should be a noderange - the other should be attr=val
    #  - put attr=val operands in %attrs hash
    while (my $a = shift(@ARGV))
    {
        if ($a =~ /=/)
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

    #now run the begin part of the prescripts
    #the call is distrubuted to the service node already, so only need to handles my own children
    $errored=0;
    $subreq->({command=>['runbeginpre'],
		node=>\@nodelist,
		arg=>["standalone", '-l']},\&pass_along);
    if ($errored) { 
	my $rsp;
	$rsp->{errorcode}->[0]=1;
	$rsp->{error}->[0]="Failed in running begin prescripts.\n";
	$callback->($rsp);
	return 1; 
    }
 

    #
    #  Get a list of the defined NIM machines
    #
    my $cmd =
      qq~/usr/sbin/lsnim -c machines | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    @machines = xCAT::Utils->runcmd("$cmd", -1);

    # don't fail - maybe just don't have any defined!

    #
    #  Get a list of all nim resource types
    #
    $cmd =
      qq~/usr/sbin/lsnim -P -c resources | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    @nimrestypes = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "$Sname: Could not get NIM resource types.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    #
    # get all the image names needed and make sure they are defined on the
    # local server
    #
    my @image_names;
    my %nodeosi;
    foreach my $node (@nodelist)
    {
        if ($::OSIMAGE)
        {

            # from the command line
            $nodeosi{$node} = $::OSIMAGE;
        }
        else
        {
            if ($objhash{$node}{provmethod})
            {
                $nodeosi{$node} = $objhash{$node}{provmethod};
            }
            elsif ($objhash{$node}{profile})
            {
                $nodeosi{$node} = $objhash{$node}{profile};
            }
            else
            {
                my $rsp;
                push @{$rsp->{data}},
                  "$Sname: Could not determine an OS image name for node \'$node\'.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                push(@nodesfailed, $node);
                $error++;
                next;
            }
        }
        if (!grep (/^$nodeosi{$node}$/, @image_names))
        {
            push(@image_names, $nodeosi{$node});
        }
    }

    if (scalar(@image_names) == 0)
    {

        # if no images then error
        return 1;
    }

    #
    # get the primary NIM master - default to management node
    #
    my $nimprime = xCAT::InstUtils->getnimprime();
    chomp $nimprime;

    #
    # if this isn't the NIM primary then make sure the local NIM defs
    #   have been created etc.
    #
    if (!xCAT::InstUtils->is_me($nimprime))
    {
        &make_SN_resource($callback,   \@nodelist, \@image_names,
                          \%imagehash, \%lochash,  \%nethash);
    }

    #
    # See if we need to create a resolv_conf resource
    #
    my $RChash;
    $RChash = &chk_resolv_conf($callback, \%objhash, \@nodelist, \%nethash, \%imagehash, \%attrs, \%nodeosi, $subreq);
    if ( !defined($RChash) ){
        my $rsp;
        push @{$rsp->{data}}, "Could not check NIM resolv_conf resource.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
    }
    my %resolv_conf_hash = %{$RChash};

    $error = 0;
    foreach my $node (@nodelist)
    {

        # get the image name to use for this node
        my $image_name = $nodeosi{$node};
        chomp $image_name;

        # check if node is in ready state
        my $shorthost;
        ($shorthost = $node) =~ s/\..*$//;
        chomp $shorthost;

		# need to pass in this server name
		my $cstate = xCAT::InstUtils->get_nim_attr_val($shorthost, "Cstate", $callback, "$Sname", $subreq);

        if (defined($cstate) && (!($cstate =~ /ready/)))
        {
            if ($::FORCE)
            {

                # if it's not in a ready state then reset it
                if ($::VERBOSE)
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "$Sname: Reseting NIM definition for $shorthost.\n";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }

                my $rcmd =
                  "/usr/sbin/nim -o reset -a force=yes $shorthost;/usr/sbin/nim -Fo deallocate -a subclass=all $shorthost";
                my $output = xCAT::Utils->runcmd("$rcmd", -1);
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "$Sname: Could not reset the existing NIM object named \'$shorthost\'.\n";
                    if ($::VERBOSE)
                    {
                        push @{$rsp->{data}}, "$output";
                    }
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    $error++;
                    push(@nodesfailed, $node);
                    next;
                }
            }
            else
            {

                my $rsp;
                push @{$rsp->{data}},
                  "$Sname: The NIM machine named $shorthost is not in the ready state and cannot be initialized.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                $error++;
                push(@nodesfailed, $node);
                next;

            }
        }

        # set the NIM machine type
        my $type = "standalone";
        if ($imagehash{$image_name}{nimtype})
        {
            $type = $imagehash{$image_name}{nimtype};
        }
        chomp $type;

        if (!($type =~ /standalone/))
        {

            #error - only support standalone for now
            #   - use mkdsklsnode for diskless/dataless nodes
            my $rsp;
            push @{$rsp->{data}},
              "$Sname: Use the mkdsklsnode command to initialize diskless/dataless nodes.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            $error++;
            push(@nodesfailed, $node);
            next;
        }

        # set the NIM install method (rte or mksysb)
        my $method = "rte";
        if ($imagehash{$image_name}{nimmethod})
        {
            $method = $imagehash{$image_name}{nimmethod};
        }
        chomp $method;

        # by convention the nim name is the short hostname of our node
        my $nim_name;
        ($nim_name = $node) =~ s/\..*$//;
        chomp $nim_name;
        if (!grep(/^$nim_name$/, @machines))
        {
            my $rsp;
            push @{$rsp->{data}},
              "$Sname: The NIM machine \'$nim_name\' is not defined.\n";
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
        my $script_string = "";
        my $bnd_string    = "";

        foreach my $restype (sort(keys %{$imagehash{$image_name}}))
        {

            # restype is res type (spot, script etc.)
            # resname is the name of the resource (61spot etc.)
            my $resname = $imagehash{$image_name}{$restype};

            # if the attr is an actual resource type then add it
            #	to the list of args
            if (grep(/^$restype$/, @nimrestypes))
            {
                if ($resname)
                {

					# don't add resolv.conf here!!
					#   - it is done below
					if ($restype eq 'resolv_conf')
					{
						next;
					}

                    # handle multiple script & installp_bundles
                    if ($restype eq 'script')
                    {
                        foreach (split /,/, $resname)
                        {
                            chomp $_;
                            $script_string .= "-a script=$_ ";
                        }
                    }
                    elsif ($restype eq 'installp_bundle')
                    {
                        foreach (split /,/, $resname)
                        {
                            chomp $_;
                            $bnd_string .= "-a installp_bundle=$_ ";
                        }

                    }
                    else
                    {

                        # ex. attr=spot resname=61spot
                        $cmdargs{$restype} = $resname;
                    }
                }

            }
        }

        # now add/overwrite with what was provided on the cmd line
        if (%attrs)
        {
            foreach my $attr (keys %attrs)
            {

                # assume each attr corresponds to a valid
                #   "nim -o bos_inst" attr
                # handle multiple script & installp_bundles
                if ($attr eq 'script')
                {
                    $script_string = "";
                    foreach (split /,/, $attrs{$attr})
                    {
                        chomp $_;
                        $script_string .= "-a script=$_ ";
                    }
                }
                elsif ($attr eq 'installp_bundle')
                {
                    $bnd_string = "";
                    foreach (split /,/, $attrs{$attr})
                    {
                        chomp $_;
                        $bnd_string .= "-a installp_bundle=$_ ";
                    }

                }
                else
                {

                    # ex. attr=spot resname=61spot
                    $cmdargs{$attr} = $attrs{$attr};
                }
            }
        }

        if ($method eq "mksysb")
        {
            $cmdargs{source} = "mksysb";

            # check for req attrs

        }
        elsif ($method eq "rte")
        {
            $cmdargs{source} = "rte";

            # TODO - check for req attrs
        }

        # must add script res
        #$cmdargs{script} = $resname;
        #$cmdargs{script} = "xcataixpost";

        # set boot_client
        if (!defined($cmdargs{boot_client}))
        {
            $cmdargs{boot_client} = "no";
        }

        # set accept_licenses
        if (!defined($cmdargs{accept_licenses}))
        {
            $cmdargs{accept_licenses} = "yes";
        }

        # create the cmd line args
        my $arg_string = " ";
        foreach my $attr (keys %cmdargs)
        {
            $arg_string .= "-a $attr=\"$cmdargs{$attr}\" ";
        }

        if ($script_string)
        {
            $arg_string .= "$script_string";
        }

        if ($bnd_string)
        {
            $arg_string .= "$bnd_string";
        }

		# see if we have a resolv_conf resource
		if ($resolv_conf_hash{$node}) {
			$arg_string .= "-a resolv_conf=$resolv_conf_hash{$node}" ;
		}

        my $initcmd;
        $initcmd = "/usr/sbin/nim -o bos_inst $arg_string $nim_name 2>&1";

        if ($::VERBOSE)
        {
            my $rsp;
            push @{$rsp->{data}}, "$Sname: Running- \'$initcmd\'\n";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }

        my $output = xCAT::Utils->runcmd("$initcmd", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}},
              "$Sname: The NIM bos_inst operation failed for \'$nim_name\'.\n";
            if ($::VERBOSE)
            {
                push @{$rsp->{data}}, "$output";
            }
            xCAT::MsgUtils->message("E", $rsp, $callback);
            $error++;
            push(@nodesfailed, $node);
            next;
        }
    }    # end - for each node

    # update the node definitions with the new osimage - if provided
    my %nodeattrs;
    foreach my $node (keys %objhash)
    {
        chomp $node;

        if (!grep(/^$node$/, @nodesfailed))
        {

            # change the node def if we were successful
            $nodeattrs{$node}{objtype} = 'node';
            $nodeattrs{$node}{os}      = "AIX";
            if ($::OSIMAGE)
            {
                $nodeattrs{$node}{profile}    = $::OSIMAGE;
                $nodeattrs{$node}{provmethod} = $::OSIMAGE;
            }
        }
    }

    if (xCAT::DBobjUtils->setobjdefs(\%nodeattrs) != 0)
    {
        my $rsp;
        push @{$rsp->{data}},
          "$Sname: Could not write data to the xCAT database.\n";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        $error++;
    }

    # TODO
    # use xdcp and assume the proper setup has been done by servicenode
    #   post script??
    if (0)
    {

        # update the .rhosts file on the server so the rcp from the node works
        if ($::VERBOSE)
        {
            my $rsp;
            push @{$rsp->{data}}, "Updating .rhosts on $Sname.\n";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }
        if (&update_rhosts(\@nodelist, $callback) != 0)
        {
            my $rsp;
            push @{$rsp->{data}},
              "$Sname: Could not update the /.rhosts file.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            $error++;
        }
    }

    # restart inetd
    if ($::VERBOSE)
    {
        my $rsp;
        push @{$rsp->{data}}, "Restarting inetd on $Sname.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }

    if (0)
    {    # don't do inetd for now
        my $scmd = "stopsrc -s inetd";
        my $output = xCAT::Utils->runcmd("$scmd", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not stop inetd on $Sname.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            $error++;
        }
        $scmd = "startsrc -s inetd";
        $output = xCAT::Utils->runcmd("$scmd", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not start inetd on $Sname.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            $error++;
        }
    }

    my  $retcode=0;
    if ($error)
    {
        my $rsp;
        push @{$rsp->{data}},
          "$Sname: One or more errors occurred when attempting to initialize AIX NIM nodes.\n";

        if ($::VERBOSE && (@nodesfailed))
        {
            push @{$rsp->{data}},
              "$Sname: The following node(s) could not be initialized.\n";
            foreach my $n (@nodesfailed)
            {
                push @{$rsp->{data}}, "$n";
            }
        }

        xCAT::MsgUtils->message("I", $rsp, $callback);
        $retcode = 1;
    }
    else
    {
        my $rsp;
        push @{$rsp->{data}}, "$Sname: AIX/NIM nodes were initialized.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }

    #now run the end part of the prescripts
    #the call is distrubuted to the service node already, so only need to handles my own children
    $errored=0;
    if (@nodesfailed > 0) {
	my @good_nodes=();
	foreach my $node (@nodelist) {
	    if (!grep(/^$node$/, @nodesfailed)) {
                 push(@good_nodes, $node);
            }
        }    
        $subreq->({command=>['runendpre'],
                      node=>\@good_nodes,
                      arg=>["standalone", '-l']},\&pass_along);
    } else {
        $subreq->({command=>['runendpre'],
                node=>\@nodelist,
                arg=>["standalone", '-l']},\&pass_along);
    }
    if ($errored) { 
	my $rsp;
	$rsp->{errorcode}->[0]=1;
	$rsp->{error}->[0]="Failed in running end prescripts.\n";
	$callback->($rsp);
	return 1; 
    }

    return  $retcode;
}

#----------------------------------------------------------------------------

=head3	spot_updates
			Update a NIM SPOT resource on the NIM primary 

		Arguments:
		Returns:
			0 - OK
			1 - error

		Error:   

		Example:

		Usage:
	my $rc = 
		&spot_updates($callback, $imagename, \%osimagehash, \%attrvals, $lpp_source, $subreq);

		Comments:

=cut

#-----------------------------------------------------------------------------
sub spot_updates
{
    my $callback        = shift;
    my $image_name      = shift;
    my $image           = shift;
    my $attrs           = shift;
    my $lpp_source_name = shift;
    my $subreq          = shift;

    my %imagedef = %{$image};    # osimage definition
    my %attrvals = %{$attrs};    # cmd line attr=val pairs

    #my $spot_name=$imagedef{$image_name}{spot};
    my $spot_name = $image_name;
    chomp $spot_name;

	my $SRname = $imagedef{$image_name}{shared_root};

    my @allservers;              # list of all service nodes

    #
    # see if spot is defined on NIM prime and if so, update it
    #

    # get the name of the primary NIM server
    #   - either the NIMprime attr of the site table or the management node
    my $nimprime = xCAT::InstUtils->getnimprime();
    chomp $nimprime;

    # see if the spot exists and if it is allocated.
    # get list of SPOTS
    my @spots;
    my $lcmd = qq~/usr/sbin/lsnim -t spot | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    @spots =
      xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $lcmd, 1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}},
          "Could not get NIM spot definitions from $nimprime.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    # see if spot defined
    if (!grep(/^$spot_name$/, @spots))
    {
        my $rsp;
        push @{$rsp->{data}},
          "The NIM resource named \'$spot_name\' is not defined and therefore cannot be updated.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    else
    {

        # ok - spot is defined - see if the spot is allocated
        my $alloc_count =
          xCAT::InstUtils->get_nim_attr_val($spot_name, "alloc_count",
                                            $callback, $nimprime, $subreq);
        if (defined($alloc_count) && ($alloc_count != 0))
        {
            my $rsp;
            push @{$rsp->{data}},
              "The resource named \'$spot_name\' is currently allocated. It cannot be updated.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
    }

    # if this is an update - check the SNs
    my @SNlist;    # list of SNs to have spot removed
    if ($::UPDATE)
    {
        # get list of SNs
        @allservers = xCAT::Utils->getAllSN();

        # we don't want to include the nimprime in the list of SNs
        #  need to compare IPs of nimprime and SN
        #my $ip = inet_ntoa(inet_aton($nimprime));
        my $ip = xCAT::NetworkUtils->getipaddr($nimprime);
        chomp $ip;

        my ($p1, $p2, $p3, $p4) = split /\./, $ip;

        # for each SN -
        foreach my $srvnode (@allservers)
        {

            # if the SN is the same as the nim prime then skip it
            #  nimprime is handle differently
            #my $ip = inet_ntoa(inet_aton($srvnode));
            my $ip = xCAT::NetworkUtils->getipaddr($srvnode);
            chomp $ip;
            my ($s1, $s2, $s3, $s4) = split /\./, $ip;
            if (($s1 == $p1) && ($s2 == $p2) && ($s3 == $p3) && ($s4 == $p4))
            {
                next;
            }

            # get list of SPOTS
            my $lscmd = qq~/usr/sbin/lsnim -t spot | /usr/bin/cut -f1 -d' ' ~;


			my $spotlist = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $srvnode, $lscmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not get NIM spot definitions from $srvnode.";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }

			my @SNspots;
			foreach my $line ( split(/\n/, $spotlist )) {
				$line =~ s/$srvnode:\s+//;
				push(@SNspots, $line);
			}

			if (grep(/$spot_name$/, @SNspots)) {

                # ok - spot is defined on this SN
                # 	- see if the spot is allocated
                my $alloc_count =
                  xCAT::InstUtils->get_nim_attr_val($spot_name, "alloc_count",
                                                  $callback, $srvnode, $subreq);

                if (defined($alloc_count) && ($alloc_count != 0))
                {
                    my $rsp;

                    push @{$rsp->{data}},
                      "The resource named \'$spot_name\' is currently allocated on service node \'$srvnode\' and cannot be removed.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return 1;
                }
                else
                {

                    # spot exists and is not allocated
                    #  so it can be removed - just make a list of SNs for now
                    push @SNlist, $srvnode;
                }
            }
        }    # end - for each SN

    }    # end - if UPDATE

    # ok -then the spot can be updated
	my $rsp;
	push @{$rsp->{data}}, "Updating the NIM spot resource named \'$spot_name\'. This could take a while.\n";
	xCAT::MsgUtils->message("I", $rsp, $callback);

    #
    # update spot with additional software if have bnds
    # 	or otherpkgs
    #

    # if have no bndls, pkgs or sync files on cmd line then use osimage def
    #    otherwise just use what is on the cmd line only
    my $bundles      = undef;
    my $otherpkgs    = undef;
    my $synclistfile = undef;
    my $osimageonly  = 0;
    my $cmdlineonly  = 0;

    # if this is an update - either use the osimage only or the
    #	 cmd line only
    if ($::UPDATE)
    {
        if (   !$attrvals{installp_bundle}
            && !$attrvals{otherpkgs}
            && !$attrvals{synclists})
        {

            # if nothing is provided on the cmd line then we just use
            # 	the osimage def - used for permanent updates - saved
            # 	in the osimage def
            $osimageonly = 1;
        }
        else
        {

            # if anything is provided on the cmd line then just use that
            #	 - used for ad hoc updates
            $cmdlineonly = 1;
        }
    }

    # if this is the initial creation of the osimage then we
    #	just look at the cmd line
    if (!$::UPDATE)
    {
        $cmdlineonly = 1;
    }

    if (defined($imagedef{$image_name}{installp_bundle}) && $osimageonly)
    {
        $bundles = $imagedef{$image_name}{installp_bundle};
    }
    if ($attrvals{installp_bundle} && $cmdlineonly)
    {
        $bundles = $attrvals{installp_bundle};
    }

    if (defined($imagedef{$image_name}{otherpkgs}) && $osimageonly)
    {
        $otherpkgs = $imagedef{$image_name}{otherpkgs};
    }
    if ($attrvals{otherpkgs} && $cmdlineonly)
    {
        $otherpkgs = $attrvals{otherpkgs};
    }

    # -b as the default installp flag to prevent bosboot in SPOT update.
    my $installp_flags = "-abgQXY ";
    if ($attrvals{installp_flags})
    {
        $installp_flags = $attrvals{installp_flags};
    }

    my $rpm_flags = "-Uvh --replacepkgs";
    if ($attrvals{rpm_flags})
    {
        $rpm_flags = $attrvals{rpm_flags};
    }

    # no default flag for emgr
    my $emgr_flags = undef;
    if ($attrvals{emgr_flags})
    {
        $emgr_flags = $attrvals{emgr_flags};
    }

    # if have bundles or otherpkgs then then add software
    #	to image (spot)
    if ($bundles || $otherpkgs)
    {
        my $rc       = 0;
        my $lpp_name = $lpp_source_name;

        $rc =
          &update_spot_sw($callback, $spot_name, $lpp_name, $nimprime, $bundles,
                          $otherpkgs, $installp_flags, $rpm_flags, $emgr_flags, $subreq);
        if ($rc != 0)
        {
            my $rsp;
            push @{$rsp->{data}},
              "Could not update software in the NIM SPOT called \'$spot_name\'.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
        else
        {
            if ($::VERBOSE)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Updated software in the NIM SPOT called \'$spot_name\'.\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }
        }
    }

    # update spot with cfg files if have synclists file
    # check image def and command line
    if (defined($imagedef{$image_name}{synclists}) && $osimageonly)
    {
        $synclistfile = $imagedef{$image_name}{synclists};
    }
    if ($attrvals{synclists} && $cmdlineonly)
    {
        $synclistfile = $attrvals{synclists};
    }

    # if synclistfile then add files to image (spot)
    if (defined($synclistfile))
    {
        my $rc = 0;
        $rc =
          &sync_spot_files($callback,     $image_name, $nimprime,
                           $synclistfile, $spot_name,  $subreq);
        if ($rc != 0)
        {
            my $rsp;
            $rsp->{data}->[0] = "Could not update synclists files.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
        else
        {
            if ($::VERBOSE)
            {
                my $rsp;
                $rsp->{data}->[0] = "Updated synclists files.\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }
        }
    }

    #
    # if this is an update then check each SN and remove the spot if it exists
    #
    if ($::UPDATE)
    {
        foreach my $sn (@SNlist)
        {
            # remove the spot
            if ($::VERBOSE)
            {
                my $rsp;
                $rsp->{data}->[0] =
                  "Removing SPOT \'$spot_name\' on service node $sn. This could take a while.\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }

            my $rmcmd = qq~nim -o remove $spot_name 2>/dev/null~;
            my $nout  =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $sn, $rmcmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not remove $spot_name from service node $sn.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
            }


			# if there is a shared_root then remove that also
			#   - see if the shared_root exist and if it is allocated
			my $alloc_count = xCAT::InstUtils->get_nim_attr_val($SRname, "alloc_count", $callback, $sn, $subreq);

			if (defined($alloc_count)) {  # then the res exists
 				if ($alloc_count != 0) {
                	my $rsp;
                	push @{$rsp->{data}}, "The resource named \'$SRname\' is currently allocated on service node \'$sn\' and cannot be removed.\n";
                	xCAT::MsgUtils->message("E", $rsp, $callback);
            	}
            	else
            	{

                	# shared_root  exists and is not allocated
                	#  so it can be removed 
					if ($::VERBOSE)
            		{
                		my $rsp;
                		$rsp->{data}->[0] =
                  		"Removing shared_root \'$SRname\' on service node $sn.\n";
                		xCAT::MsgUtils->message("I", $rsp, $callback);
            		}

            		my $rmcmd = qq~nim -o remove $SRname 2>/dev/null~;
            		my $nout  = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $sn, $rmcmd, 0);
            		if ($::RUNCMD_RC != 0)
            		{
                		my $rsp;
               			push @{$rsp->{data}}, "Could not remove \'$SRname\' from service node $sn.\n";
                		xCAT::MsgUtils->message("E", $rsp, $callback);
            		}
				}
            }
        }
    } # end UPDATE
    return 0;
}

#----------------------------------------------------------------------------

=head3   chkosimage

		Checks an xCAT osimage

		Arguments:
		Returns:
			0 - OK
			1 - error
																						Usage:
																							chkosimage -h
			chkosimage [-V] osimage_name

=cut

#-----------------------------------------------------------------------------
sub chkosimage
{
	my $callback = shift;
	my $subreq   = shift;

	my $image_name;

	if (defined(@{$::args}))
	{
		@ARGV = @{$::args};
	}
	else
	{
		&chkosimage_usage($callback);
		return 0;
	}

	Getopt::Long::Configure("no_pass_through");
	if (
		!GetOptions(
					'c|clean'	   => \$::CLEANLPP,
					'h|help'       => \$::HELP,
					'verbose|V'    => \$::VERBOSE,
					'v|version'    => \$::VERSION,
					)
		)
	{
				&chkosimage_usage($callback);
				return 0;
	}

	# display the usage if -h or --help is specified
	if ($::HELP)
	{
		&chkosimage_usage($callback);
		return 0;
	}

	# display the version statement if -v or --verison is specified
	if ($::VERSION)
	{
		my $version = xCAT::Utils->Version();
		my $rsp;
		push @{$rsp->{data}}, "chkosimage $version\n";
		xCAT::MsgUtils->message("I", $rsp, $callback);
		return 0;
	}

	# get the name of the primary NIM server
	#   - either the NIMprime attr of the site table or the management node
	my $nimprime = xCAT::InstUtils->getnimprime();
	chomp $nimprime;

    #
    # process @ARGV
    #

    # the first arg should be a noderange - the other should be attr=val
    #  - put attr=val operands in %::attrres hash
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
                return 1;
            }

            # put attr=val in hash
            $::attrres{$attr} = $value;
        }
    }

	# get the xCAT image definition
	my %objtype;
	$objtype{$image_name} = 'osimage';
	my %imagedef = xCAT::DBobjUtils->getobjdefs(\%objtype, $callback);
	if (!(%imagedef))
	{
		my $rsp;
		push @{$rsp->{data}}, "Could not get xCAT image definition.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}

	#
	# check the diskless osimage def
	#
	if ($imagedef{$image_name}{nimtype} eq 'diskless') {
		# must have spot, root or shared_root and paging

		if (!$imagedef{$image_name}{spot} ) {
            my $rsp;
            push @{$rsp->{data}}, "A diskless osimage must include a spot resource.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
		}

        if (!$imagedef{$image_name}{paging} ) {
            my $rsp;
            push @{$rsp->{data}}, "A diskless osimage must include a paging resource.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
        }

		#
        # make sure they have either a root or a shared_root - but not both
        #

		if (!$imagedef{$image_name}{root} && !$imagedef{$image_name}{shared_root} ) {
            my $rsp;
            push @{$rsp->{data}}, "A diskless osimage must include either a \'root\' or a 'shared_root\' resource.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
		}

		#
    	# make sure they don't have both
    	#
		if ($imagedef{$image_name}{root} && $imagedef{$image_name}{shared_root} ) {
			my $rsp;
			push @{$rsp->{data}}, "Cannot have both a \'root\' and a \'shared_root\' resources.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
        }

	}

	#
	# check to see if all the software is available in the lpp_source 
	# 	directories
	#

	# create a list
	my @pkglist;
	my @install_list;

	# start with otherpkgs
	if ($imagedef{$image_name}{otherpkgs})
	{
		foreach my $pkg (split(/,/, $imagedef{$image_name}{otherpkgs}))
		{
			if (!grep(/^$pkg$/, @pkglist))
			{
				push(@pkglist, $pkg);
			}
		}
	}

	# add installp_bundle contents
	if ($imagedef{$image_name}{installp_bundle})
	{
		my @bndlist = split(/,/, $imagedef{$image_name}{installp_bundle});
		foreach my $bnd (@bndlist)
		{
			$bnd =~ s/\s*//g;    # remove blanks
			my ($rc, $list, $loc) = xCAT::InstUtils->readBNDfile($callback, $bnd, $nimprime, $subreq);
			foreach my $pkg (@$list)
			{
				chomp $pkg;
				if (!grep(/^$&pkg$/, @pkglist))
				{
					push(@pkglist, $pkg);
				}
			}
		}
	}
	
	my %pkgtype;
	foreach my $pkg (@pkglist)
	{
		if (($pkg =~ /R:/) || ($pkg =~ /I:/) )
		{
			my ($junk, $pname) = split(/:/, $pkg);
			push(@install_list, $pname);
		} else {
			push(@install_list, $pkg);
		}

		if (($pkg =~ /R:/)) {
			# get a separate list of just the rpms - they must be preceded
			#	by R:
			my ($junk, $pname) = split(/:/, $pkg);
			$pname =~ s/\*//g; # drop *
			$pkgtype{$pname} = "rpm";
		}
	}

	if ( scalar(@install_list) == 0) {
		 my $rsp;
		 push @{$rsp->{data}}, "\nThere was no additional software listed in the \'otherpkgs\' or \'installp_bundle\' attributes.\n";
		 xCAT::MsgUtils->message("I", $rsp, $callback);
		 return 0;
	}

	# get a list of software from the lpp_source dirs
	my @srclist;

	my $lpp_loc = xCAT::InstUtils->get_nim_attr_val($imagedef{$image_name}{lpp_source}, 'location', $callback, $nimprime, $subreq);

	my $rpm_srcdir = "$lpp_loc/RPMS/ppc";
	my $instp_srcdir = "$lpp_loc/installp/ppc";

	# get rpm packages
	my $rcmd = qq~/usr/bin/ls $rpm_srcdir 2>/dev/null~;
	my @rlist = xCAT::Utils->runcmd("$rcmd", -1);
	foreach my $f (@rlist) {
		if ($f =~ /\.rpm/) {
			if (!grep(/^$f$/, @srclist)) {
				push (@srclist, $f);
			}	
		}
	}

	# get epkg files
	# epkg files should go with installp filesets - I think?
	my $ecmd = qq~/usr/bin/ls $instp_srcdir 2>/dev/null~;
	my @elist = xCAT::Utils->runcmd("$ecmd", -1);
	foreach my $f (@elist) {
		if (($f =~ /epkg\.Z/)) {
			if (!grep(/^$f$/, @srclist)) {
				push (@srclist, $f);
			}
		}
	}

	# get installp filesets in this dir
	my $icmd = qq~installp -L -d $instp_srcdir | /usr/bin/cut -f2 -d':' 2>/dev/null~;
	my @ilist = xCAT::Utils->runcmd("$icmd", -1);
	foreach my $f (@ilist) {
		chomp $f;
		push (@srclist, $f);
	}
	
	my $error = 0;
	my $rpmerror = 0;
	my $remlist;
	# check for each one - give msg if missing
	foreach my $file (@install_list) {

		$file =~ s/\*//g;		
		$file =~ s/\s*//g;
		chomp $file;

		if ($::VERBOSE) {
			my $rsp;
			push @{$rsp->{data}}, "Check for \'$file\'.\n";
			xCAT::MsgUtils->message("I", $rsp, $callback);
		}

		my $foundit=0;
		my $foundlist = "";

		foreach my $lppfile (@srclist) {
			if ($lppfile =~ /$file/) {
				$foundit++;
				$foundlist .= "$lppfile  ";
			}
		}

		if (!$foundit)
		{
			my $rsp;
			push @{$rsp->{data}}, "Could not find $file in $imagedef{$image_name}{lpp_source}.\n";
			xCAT::MsgUtils->message("W", $rsp, $callback);
			$error++;
		} else {
			if ($::VERBOSE) {
				my $rsp;
				push @{$rsp->{data}}, "Found \'$foundlist\'.\n";
				xCAT::MsgUtils->message("I", $rsp, $callback);
			}
		}

		# if this is an rpm & we got more then one match that
		#   could be a problem
		if ( ($foundit > 1) && (( $file =~ /\.rpm/) || ($pkgtype{$file} eq "rpm")) ){

			if ($::CLEANLPP) {
				my $ret = &clean_lpp($callback, $rpm_srcdir, $file);
				if ($ret != 1) {
					$remlist .= $ret;
				}
			} else {
				my $rsp;
				push @{$rsp->{data}}, "Found multiple matches for $file: ($foundlist)\n";
				xCAT::MsgUtils->message("I", $rsp, $callback);
				$rpmerror++;
			}
		}
	}

	if ($::CLEANLPP && $remlist) {
		my $rsp;
		push @{$rsp->{data}}, "Removed the following duplicate rpms:\n$remlist\n";
		xCAT::MsgUtils->message("I", $rsp, $callback);
	}

	if ($error) {
		my $rsp;
		push @{$rsp->{data}}, "One or more software packages could not be found in or selected from the $imagedef{$image_name}{lpp_source} resource.\n";
		xCAT::MsgUtils->message("W", $rsp, $callback);
	} else {
		my $rsp;
		push @{$rsp->{data}}, "All the software packages were found in the lpp_source \'$imagedef{$image_name}{lpp_source}\'\n";
		xCAT::MsgUtils->message("I", $rsp, $callback);
	}

	if ($rpmerror) {
		my $rsp;
		push @{$rsp->{data}}, "Found multiple matches for one or more rpm packages. This will cause installation errors. Remove the unwanted rpm packages from the lpp_source directory $rpm_srcdir.\n(Use the chkosimage -c option to remove all but the most recently added rpm.)\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
	}

	if ( $rpmerror || $error) {
		return 1;
	}

	return 0;
}

#----------------------------------------------------------------------------

=head3   clean_lpp

	Removes old versions of rpms from the lpp_resource.
	Based on timestamps - just keep the latest version.

	Arguments:
	Returns:
		0 - OK 
		1 - error
	Globals:
	Example:
	Usage:
	Usage:
	Comments:

=cut

#-----------------------------------------------------------------------------
sub clean_lpp
{
	my $callback      = shift;
	my $dir_name      = shift;
	my $file         = shift;

	my @rpm_list;

	my $removelist;

	# if ends in * good else add one
	if (!($file =~ /\*$/) ) {
		$file .= "\*";
	}

	# get sorted list - most recent is first
	my $cmd = qq~cd $dir_name; /bin/ls -t $file 2>/dev/null~;

	@rpm_list = xCAT::Utils->runcmd("$cmd", -1);
	if ($::RUNCMD_RC != 0)
	{
		my $rsp;
		push @{$rsp->{data}}, "Could not get list of rpms in \'$dir_name\'";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}

	# remove all but the biggest
	my $index = 0;
	foreach my $rpm (@rpm_list) {
		if ($index > 0) {
			my $cmd = qq~cd $dir_name; /bin/rm $rpm 2>/dev/null~;
			my $ret = xCAT::Utils->runcmd("$cmd", -1);
			if ($::RUNCMD_RC != 0)
			{
				my $rsp;
				push @{$rsp->{data}}, "Could not remove \'$rpm\'";
				xCAT::MsgUtils->message("I", $rsp, $callback);
			}
			$removelist .= "$rpm\n"; 
		}
		$index++;
	}
	
	if ($removelist) {
		return $removelist;
	}

	return 1;
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
		   [-u |--update] [-i current_image] image_name 
			[attr=val [attr=val ...]]

		Comments:

=cut

#-----------------------------------------------------------------------------
sub mknimimage
{
    my $callback = shift;
    my $subreq   = shift;

    my $lppsrcname;      # name of the lpp_source resource for this image
    my $spot_name;       # name of SPOT/COSI  default to image_name
    my $rootres;         # name of the root resource
    my $dumpres;         #  dump resource
    my $pagingres;       # paging
    my $currentimage;    # the image to copy
    my %newres;          # NIM resource type and names create by this cmd
    my %osimagedef;      # NIM resource type and names for the osimage def
    my $bosinst_data_name;
    my $resolv_conf_name;
    my $mksysb_name;
    my $lpp_source_name;
    my $root_name;
    my $dump_name;
    my $install_dir = xCAT::Utils->getInstallDir();

    if (defined(@{$::args}))
    {
        @ARGV = @{$::args};
    }
    else
    {
        &mknimimage_usage($callback);
        return 0;
    }

    # parse the options
    Getopt::Long::Configure("no_pass_through");
    if (
        !GetOptions(
                    'b=s'          => \$::SYSB,
                    'D|mkdumpres'  => \$::MKDUMP,
                    'f|force'      => \$::FORCE,
                    'h|help'       => \$::HELP,
                    's=s'          => \$::opt_s,
                    'r|sharedroot' => \$::SHAREDROOT,
                    'l=s'          => \$::opt_l,
                    'i=s'          => \$::opt_i,
                    't=s'          => \$::NIMTYPE,
                    'm=s'          => \$::METHOD,
                    'n=s'          => \$::MKSYSBNODE,
					'p|cplpp'      => \$::opt_p,
                    'u|update'     => \$::UPDATE,
                    'verbose|V'    => \$::VERBOSE,
                    'v|version'    => \$::VERSION,
                    'nfsv4'        => \$::NFSV4,
        )
      )
    {

        &mknimimage_usage($callback);
        return 0;
    }

    # display the usage if -h or --help is specified
    if ($::HELP)
    {
        &mknimimage_usage($callback);
        return 0;
    }

    # display the version statement if -v or --verison is specified
    if ($::VERSION)
    {
        my $version = xCAT::Utils->Version();
        my $rsp;
        push @{$rsp->{data}}, "mknimimage $version\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return 0;
    }

	if ($::opt_p  && !$::opt_i) {
		my $rsp;
		push @{$rsp->{data}}, "The \'-p\' option is only valid when using the \-i\' option.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}

    if ($::SHAREDROOT)
    {
        if ($::NIMTYPE ne 'diskless')
        {
            my $rsp;
            push @{$rsp->{data}},
              "The \'-r\' option is only valid for diskless images.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            &mknimimage_usage($callback);
            return 1;
        }
    }

    # get this systems name as known by xCAT management node
    my $Sname = xCAT::InstUtils->myxCATname();
    chomp $Sname;

    # get the name of the primary NIM server
    #   - either the NIMprime attr of the site table or the management node
    my $nimprime = xCAT::InstUtils->getnimprime();
    chomp $nimprime;

    if (!$::UPDATE)
    {

        # the type is standalone by default
        if (!$::NIMTYPE)
        {
            $::NIMTYPE = "standalone";
        }

        # the NIM method is rte by default
        if (($::NIMTYPE eq "standalone") && !$::METHOD)
        {
            $::METHOD = "rte";
        }
    }

    if ($::opt_l)
    {

        # This is not a full path
        if ($::opt_l !~ /^\//)
        {
            my $abspath = xCAT::Utils->full_path($::opt_l, $::cwd);
            if ($abspath)
            {
                $::opt_l = $abspath;
            }
        }
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

    if (($::NIMTYPE eq "standalone") && $::opt_i)
    {
        my $rsp;
        push @{$rsp->{data}},
          "The \'-i\' option is only valid for diskless and dataless nodes.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        &mknimimage_usage($callback);
        return 1;
    }

    #
    #  Install/config NIM master if needed
    #

    # see if NIM is configured
    my $lsnimcmd = qq~/usr/sbin/lsnim -l >/dev/null 2>&1~;

    # xcmd decides whether to run local or remote and calls
    #	either runcmd or runxcmd
    my $out =
      xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $lsnimcmd,
                            0);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Configuring NIM.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);

        # if its not installed then run nim_master_setup
        if ($::opt_s !~ /^\//)
        {
            my $abspath = xCAT::Utils->full_path($::opt_s, $::cwd);
            if ($abspath)
            {
                $::opt_s = $abspath;
            }
        }

        #  - add location ($::opt_l or default) - so all res go in same place!
		my $loc;
		if ($::opt_l) {
			$loc=$::opt_l;
		} else {
			$loc = "$install_dir/nim";
		}

        if ($::NFSV4)
        {
            #nim_master_setup does not support IPv6, needs to use separate nim commands
            #1. start ndpd-host service for IPv6
            my $nimcmd = qq~lssrc -s ndpd-host~;
            my $nimout =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd,
                                    0);
            if ($nimout =~ /inoperative/)
            {
                my $nimcmd = qq~startsrc -s ndpd-host~;
                my $nimout =
                  xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd,
                                        0);
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp;
                    push @{$rsp->{data}}, "Could not start ndpd-host service\n";
                    if ($::VERBOSE)
                    {
                        push @{$rsp->{data}}, "$nimout";
                    }
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return 1;
                } 
            }
            #2. Configure nfs domain for nfs version 4
            # check site table - get domain attr
            my $sitetab = xCAT::Table->new('site');
            my ($tmp) = $sitetab->getAttribs({'key' => 'domain'}, 'value');
            my $domain = $tmp->{value};
            $sitetab->close;
            if (!$domain)
            {
                my $rsp;
                push @{$rsp->{data}}, "Can not determine domain name, check site table.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
            $nimcmd = qq~chnfsdom $domain~;
            $nimout =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd,
                                    0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not change nfsv4 domain to $domain.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$nimout";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
            $nimcmd = qq~stopsrc -g nfs~;
            $nimout =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd,
                                    0);
            sleep 2;
            $nimcmd = qq~startsrc -g nfs~;
            $nimout =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd,
                                    0);
                
            #3. install bos.sysmgt.nim.master bos.sysmgt.nim.spot
            $nimcmd = qq~installp -aXYd $::opt_s bos.sysmgt.nim.master bos.sysmgt.nim.spot~;
            $nimout =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd,
                                    0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not install bos.sysmgt.nim.master bos.sysmgt.nim.spot.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$nimout";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
            #4. Initialize NIM
            $nimcmd = qq~hostname~;
            my $hname =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd,
                                    0);
            chomp($hname);
            $hname =~ s/\..*//; #shorthostname
            $nimcmd = qq~netstat -if inet~;
            $nimout =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd,
                                    0);
            my $pif;
            foreach my $line (split(/\n/,$nimout))
            {
                if ($line =~ /(.*?)\s+\d+\s+$hname/)
                {
                    $pif = $1;
                    last;
                }
            }
            if (!$pif)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not get the primary nim master interface.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$nimout";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
            #get the link local address for the primary nim interface
            my $linklocaladdr;
            $nimcmd = qq~ifconfig $pif~;
            $nimout =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd,
                                    0);
            foreach my $line (split(/\n/,$nimout))
            {
                #ignore the address fe80::1%2/64 
                if ($line =~ /%/)
                {
                    next;
                }
                if ($line =~ /inet6\s+(fe80.*?)\//)
                {
                    $linklocaladdr = $1;
                    last;
                }
            }
            if (!$linklocaladdr)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not get the link local address of the interface $pif.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$nimout";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
           
            $nimcmd = qq~nimconfig -aplatform=chrp -anetboot_kernel=64 -acable_type=N/A -a netname=master_net -apif_name=$pif~;
            if ($::VERBOSE)
            {
                my $rsp;
                push @{$rsp->{data}}, "Running: \'$nimcmd\'\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }
            $nimout =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd,
                                    0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not initialize nim.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$nimout";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

            #5. Conigure NIM master
            $nimcmd = qq~nim -o change -a global_export=yes master~;
            if ($::VERBOSE)
            {
                my $rsp;
                push @{$rsp->{data}}, "Running: \'$nimcmd\'\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }
            $nimout =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd,
                                    0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not change global_export for master.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$nimout";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

            $nimcmd = qq~nim -o change -a nfs_domain=clusters.com master~;
            if ($::VERBOSE)
            {
                my $rsp;
                push @{$rsp->{data}}, "Running: \'$nimcmd\'\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }
            $nimout =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd,
                                    0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not change nfs_domain for master.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$nimout";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

            #6. Add ipv6 network
            my $net;
            my $prefixlength;
            my $gw;
            my $netname;
            my $nettab = xCAT::Table->new('networks');
            my @nets = $nettab->getAllAttribs('netname', 'net','mask','gateway');
            if (scalar(@nets) == 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "No entries in networks table, check networks table.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
            foreach my $enet (@nets)
            {
                #use the first IPv6 network in networks table
                if ($enet->{'net'} =~ /:/) { #ipv6
                    $net = $enet->{'net'};
                    $prefixlength = $enet->{'mask'};
                    $gw = $enet->{'gateway'};
                    $netname = $enet->{'netname'};
                    last;
                }
            }
            if (!$netname || !$gw || !$net)
            {
                my $rsp;
                push @{$rsp->{data}}, "Can not get the netname, gateway or net in networks table.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
            my $mask = xCAT::NetworkUtils->prefixtomask($prefixlength);
            $nimcmd = qq~nim -o define -t ent6 -a net_addr=$net -a snm=$mask -a routing1="default $gw" $netname~;
            if ($::VERBOSE)
            {
                my $rsp;
                push @{$rsp->{data}}, "Running: \'$nimcmd\'\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }
            $nimout =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd,
                                    0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not create nim network $netname.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$nimout";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
            
            #7. Add an IPv6 interface to master
            my $hip = xCAT::NetworkUtils->getipaddr($hname);
            $nimcmd = qq~nim -o change -a if2="$netname $hname $linklocaladdr" -a cable_type2=N/A master~;
            if ($::VERBOSE)
            {
                my $rsp;
                push @{$rsp->{data}}, "Running: \'$nimcmd\'\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }
            $nimout =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd,
                                    0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not add ipv6 network to nim master.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$nimout";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

        }
        else
        {
            my $nimcmd = qq~nim_master_setup -a file_system=$loc -a mk_resource=no -a device=$::opt_s~;
            if ($::VERBOSE)
            {
                my $rsp;
                push @{$rsp->{data}}, "Running: \'$nimcmd\'\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }
            my $nimout =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd,
                                    0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not install and configure NIM.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$nimout";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
        }
    }

    #
    #  get list of defined xCAT osimage objects
    #
    my @deflist = undef;
    @deflist = xCAT::DBobjUtils->getObjectsOfType("osimage");

    # if our image is defined get the defnition
    my $is_defined = 0;
    my %imagedef   = undef;
    if (grep(/^$::image_name$/, @deflist))
    {

        # get the osimage def
        my %objtype;
        $objtype{$::image_name} = 'osimage';
        %imagedef = xCAT::DBobjUtils->getobjdefs(\%objtype, $callback);
        if (!(%imagedef))
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not get the xCAT osimage definition for
 \'$::image_name\'.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
        $is_defined = 1;
    }

    #
    # do diskless spot update - if requested
    #
    if ($::UPDATE)
    {

        # don't update spot unlees it is for diskless/dataless
        if ($imagedef{$::image_name}{nimtype} eq "standalone")
        {
            my $rsp;
            push @{$rsp->{data}},
              "The \'-u\' option is only valid for diskless and dataless nodes.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            &mknimimage_usage($callback);
            return 1;
        }

        # if it doesn't exist we can't update it!
        if (!$is_defined)
        {
            my $rsp;
            push @{$rsp->{data}},
              "The osimage object named \'$::image_name\' is not defined.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
        else
        {

            # just update the existing spot on the NIM primary
            #	- and remove spot from the other SNs
            #   - when dskls nodes are re-init the new spot will be created
            #		on the SNs and the root dirs will be re-synced

            if (
                &spot_updates(
                            $callback,                            $::image_name,
                            \%imagedef,                           \%::attrres,
                            $imagedef{$::image_name}{lpp_source}, $subreq
                ) != 0
              )
            {

                # error - could not update spots
                return 1;
            }
            return 0;
        }
    }

    #
    #   if exists and not doing update then remove or return
    #
    if ($is_defined)
    {
        if ($::FORCE)
        {

            # remove the existing osimage def and continue
            my %objhash;
            $objhash{$::image_name} = "osimage";
            if (xCAT::DBobjUtils->rmobjdefs(\%objhash) != 0)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not remove the existing xCAT definition for \'$::image_name\'.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
            }
        }
        else
        {

            # just return with error
            my $rsp;
            push @{$rsp->{data}},
              "The osimage definition \'$::image_name\' already exists.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
    }

    #
    #  Get a list of the all defined resources
    #
    my $cmd =
      qq~/usr/sbin/lsnim -c resources | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    @::nimresources =
      xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cmd, 1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get NIM resource definitions.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    #
    #  Handle diskless, rte, & mksysb
    #
    if (($::NIMTYPE eq "diskless") | ($::NIMTYPE eq "dataless"))
    {

        # get the xCAT image definition if provided
        if ($::opt_i)
        {
            my %objtype;
            my $currentimage = $::opt_i;

            # get the image def
            $objtype{$::opt_i} = 'osimage';

            %::imagedef = xCAT::DBobjUtils->getobjdefs(\%objtype, $callback);
            if (!defined(%::imagedef))
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not get xCAT image definition.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
        }

        # must have a source and a name
        if (!($::opt_s || $::opt_i) || !defined($::image_name))
        {
            my $rsp;
            push @{$rsp->{data}},
              "The image name and either the -s or -i option are required.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            &mknimimage_usage($callback);
            return 1;
        }

        #
        # get lpp_source

        #
        $lpp_source_name = &mk_lpp_source(\%::attrres, $callback);
        chomp $lpp_source_name;
        $newres{lpp_source} = $lpp_source_name;
        if (!defined($lpp_source_name))
        {

            # error
            my $rsp;
            push @{$rsp->{data}}, "Could not create lpp_source definition.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }

        #
        # spot resource
        #

        $spot_name = &mk_spot($lpp_source_name, \%::attrres, $callback);

        chomp $spot_name;
        $newres{spot} = $spot_name;
        if (!defined($spot_name))
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not create spot definition.\n";
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

        # check the command line attrs first
        if ($::attrres{root})
        {
            $root_name = $::attrres{root};
        }
        if ($::attrres{shared_root})
        {
            $root_name = $::attrres{shared_root};
        }
        chomp $root_name;

        # if we don't have a root/shared_root then
        #	we may need to create one
        if (!$root_name)
        {
            # use naming convention
            if ($::SHAREDROOT || ($::imagedef{$::opt_i}{shared_root}))
            {
                $root_name = $::image_name . "_shared_root";
            }
            else
            {
                $root_name = $::image_name . "_root";
            }
            chomp $root_name;

            # see if it's already defined
            if (grep(/^$root_name$/, @::nimresources))
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Using existing root resource named \'$root_name\'.\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }
            else
            {

                # it doesn't exist so create it

                my $type;
                if ($::SHAREDROOT || ($::imagedef{$::opt_i}{shared_root}))
                {
                    $type = "shared_root";
                }
                else
                {
                    $type = "root";
                }

                if (&mknimres($root_name, $type, $callback, $::opt_l, $spot_name, \%::attrres) != 0 )
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "Could not create a NIM definition for \'$root_name\'.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return 1;
                }
            }
        }    # end root res

        if ($::SHAREDROOT || ($::imagedef{$::opt_i}{shared_root}))
        {
            $newres{shared_root} = $root_name;
        }
        else
        {
            $newres{root} = $root_name;
        }

        #
        # dump res
        #  - dump is optional with new AIX versions
        #
        $::dodumpold = 0;
        my $vrmf = xCAT::Utils->get_OS_VRMF();
        if (defined($vrmf))
        {
            if (xCAT::Utils->testversion($vrmf, "<", "6.1.4.0", "", ""))
            {
                $::dodumpold = 1;
            }
        }

        if ($::dodumpold || $::MKDUMP)
        {
            my $dump_name;
            if ($::attrres{dump})
            {
                # if provided then use it
                $dump_name = $::attrres{dump};
            }
            elsif ($::opt_i)
            {
                # if one is provided in osimage
                if ($::imagedef{$::opt_i}{dump})
                {
                    $dump_name = $::imagedef{$::opt_i}{dump};
                }
            }
            else
            {

                # may need to create new one
                # all use the same dump res unless another is specified
                $dump_name = $::image_name . "_dump";

                # see if it's already defined
                if (grep(/^$dump_name$/, @::nimresources))
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "Using existing dump resource named \'$dump_name\'.\n";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }
                else
                {

                    # create it
                    my $type = "dump";
                    if (
                        &mkdumpres(
                                   $dump_name, \%::attrres, $callback, $::opt_l
                        ) != 0
                      )
                    {
                        my $rsp;
                        push @{$rsp->{data}},
                          "Could not create a NIM definition for \'$dump_name\'.\n";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                        return 1;
                    }
                }
            }    # end dump res
            chomp $dump_name;
            $newres{dump} = $dump_name;
        }    # end dodump old

        #
        # paging res
        #
        my $paging_name;
        if ($::attrres{paging})
        {

            # if provided then use it
            $paging_name = $::attrres{paging};
        }
        if ($::opt_i)
        {

            # if one is provided in osimage
            if ($::imagedef{$::opt_i}{paging})
            {
                $paging_name = $::imagedef{$::opt_i}{paging};
            }
        }
        chomp $paging_name;

        if (!$paging_name)
        {

            # create it
            # only if type diskless
            my $nimtype;
            if ($::NIMTYPE)
            {
                $nimtype = $::NIMTYPE;
            }
            else
            {
                $nimtype = "diskless";
            }
            chomp $nimtype;

            if ($nimtype eq "diskless")
            {

                $paging_name = $::image_name . "_paging";

                # see if it's already defined
                if (grep(/^$paging_name$/, @::nimresources))
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "Using existing paging resource named \'$paging_name\'.\n";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }
                else
                {

                    # it doesn't exist so create it
                    my $type = "paging";
					my $junk;
                    if (&mknimres($paging_name, $type, $callback, $::opt_l, $junk, \%::attrres) !=
                        0)
                    {
                        my $rsp;
                        push @{$rsp->{data}},
                          "Could not create a NIM definition for \'$paging_name\'.\n";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                        return 1;
                    }
                }
            }
        }    # end paging res

        chomp $paging_name;
        $newres{paging} = $paging_name;

        # need to update spot if needed
        # but put it later, after xcat osimage obj defined since xcatchroot needs it.
        
        #
        # end diskless section
        #

    }
    elsif ($::NIMTYPE eq "standalone")
    {

        # includes rte & mksysb methods

        #
        # create bosinst_data
        #
        $bosinst_data_name = &mk_bosinst_data(\%::attrres, $callback);
        chomp $bosinst_data_name;
        $newres{bosinst_data} = $bosinst_data_name;
        if (!defined($bosinst_data_name))
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not create bosinst_data definition.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }

		#
		#  create a dump res if requested
		#
        if ($::MKDUMP)
        {
            my $dump_name;
            if ($::attrres{dump})
            {
                # if provided then use it
                $dump_name = $::attrres{dump};
            }
            elsif ($::opt_i)
            {
                # if one is provided in osimage
                if ($::imagedef{$::opt_i}{dump})
                {
                    $dump_name = $::imagedef{$::opt_i}{dump};
                }
            }
            else
            {
                # may need to create new one
                # all use the same dump res unless another is specified
                $dump_name = $::image_name . "_dump";

                # see if it's already defined
                if (grep(/^$dump_name$/, @::nimresources))
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "Using existing dump resource named \'$dump_name\'.\n";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }
                else
                {
                    # create it
                    my $type = "dump";
                    if (
                        &mkdumpres(
                                   $dump_name, \%::attrres, $callback, $::opt_l
                        ) != 0
                      )
                    {
                        my $rsp;
                        push @{$rsp->{data}},
                          "Could not create a NIM definition for \'$dump_name\'.\n";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                        return 1;
                    }
                }
            }    # end dump res
            chomp $dump_name;
            $newres{dump} = $dump_name;
        }    # end create dump

        if ($::METHOD eq "rte")
        {

            # need lpp_source, spot & bosinst_data
            # optionally resolv_conf
            # user can specify others

            # must have a source and a name
            if (!($::opt_s) || !defined($::image_name))
            {
                my $rsp;
                push @{$rsp->{data}},
                  "The image name and -s option are required.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                &mknimimage_usage($callback);
                return 1;
            }

            #
            # get lpp_source
            #
            $lpp_source_name = &mk_lpp_source(\%::attrres, $callback);
            chomp $lpp_source_name;
            $newres{lpp_source} = $lpp_source_name;
            if (!defined($lpp_source_name))
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not create lpp_source definition.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

        }
        elsif ($::METHOD eq "mksysb")
        {

            # need mksysb bosinst_data
            # user provides SPOT
            #  TODO - create SPOT from mksysb
            # user can specify others
            #
            # get mksysb resource
            #
            $mksysb_name = &mk_mksysb(\%::attrres, $callback);
            chomp $mksysb_name;
            $newres{mksysb} = $mksysb_name;
            if (!defined($mksysb_name))
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not create mksysb definition.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
        }

        #
        # get spot resource
        #
        $spot_name = &mk_spot($lpp_source_name, \%::attrres, $callback);
        chomp $spot_name;
        $newres{spot} = $spot_name;
        if (!defined($spot_name))
        {

            my $rsp;
            push @{$rsp->{data}}, "Could not create spot definition.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
    }

    #
    # Put together the osimage def information
    #
    $osimagedef{$::image_name}{objtype}   = "osimage";
    $osimagedef{$::image_name}{imagetype} = "NIM";
    $osimagedef{$::image_name}{osname}    = "AIX";
    $osimagedef{$::image_name}{nimtype}   = $::NIMTYPE;
    if ($::METHOD)
    {
        $osimagedef{$::image_name}{nimmethod} = $::METHOD;
    }

    #
    # get resources from the original osimage if provided
    #
    if ($::opt_i)
    {

        foreach my $type (keys %{$::imagedef{$::opt_i}})
        {

            # could be comma list!!
            my $include = 1;
            my @reslist = split(/,/, $::imagedef{$::opt_i}{$type});
            foreach my $res (@reslist)
            {
                if (!grep(/^$res$/, @::nimresources))
                {
                    my $include = 0;
                    last;
                }
            }

            if ($include)
            {
                $osimagedef{$::image_name}{$type} =
                  $::imagedef{$::opt_i}{$type};
            }
        }
    }

    if (%newres)
    {

        # overlay/add the resources defined above
        foreach my $type (keys %newres)
        {
            $osimagedef{$::image_name}{$type} = $newres{$type};
        }
    }

    #
    # overwrite with anything provided on the command line
    #
    if (defined(%::attrres))
    {

        # add overlay/any additional from the cmd line if provided
        foreach my $type (keys %::attrres)
        {

            # could be comma list!!
            my $include = 1;
            my @reslist = split(/,/, $::attrres{$type});
            foreach my $res (@reslist)
            {
                if (!grep(/^$res$/, @::nimresources))
                {
                    my $include = 0;
                    last;
                }
            }

            if ($include)
            {
                $osimagedef{$::image_name}{$type} = $::attrres{$type};
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

    # put diskless spot update after xcat obj def
    # since xcatchroot needs osimage defined first

    if (($::NIMTYPE eq "diskless") || ($::NIMTYPE eq "dataless"))
    {
        # update spot with additional software and sync files
        if (
            &spot_updates(
                          $callback,   $::image_name, \%imagedef,
                          \%::attrres, $lpp_source_name
            ) != 0
          )
        {

            # error - could not update spots
            return 1;
        }
    }    


	#
	# Set root password in diskless images
	#
	my $rootpw;
	my $method;
	if (($::NIMTYPE eq "diskless") || ($::NIMTYPE eq "dataless"))
	{
		my $passwdtab = xCAT::Table->new('passwd');
		unless ( $passwdtab) {
			my $rsp;
			push @{$rsp->{data}}, "Unable to open passwd table.";
			xCAT::MsgUtils->message("E", $rsp, $callback);
		}

		if ($passwdtab) {
			my $et = $passwdtab->getAttribs({key => 'system', username => 'root'}, 'password','cryptmethod');
			if ($et and defined ($et->{'password'})) {
				$rootpw = $et->{'password'};
			}
			if ($et and defined ($et->{'cryptmethod'})) {
                $method = $et->{'cryptmethod'};
            }
		}
	}

	if ($rootpw) {
		if ( $::VERBOSE) {
			my $rsp;
			$rsp->{data}->[0] = "Setting the root password in the spot \'$spot_name\'\n";
			xCAT::MsgUtils->message("I", $rsp, $callback);

		}

		chomp $rootpw;
		my $pwcmd;
		if ($method) {
			$pwcmd = qq~$::XCATROOT/bin/xcatchroot -i $spot_name "/usr/bin/echo root:$rootpw | /usr/bin/chpasswd -e -c" >/dev/null 2>&1~;
		} else {
			$pwcmd = qq~$::XCATROOT/bin/xcatchroot -i $spot_name "/usr/bin/echo root:$rootpw | /usr/bin/chpasswd -c" >/dev/null 2>&1~;
		}

		my $out = xCAT::Utils->runcmd("$pwcmd", -1);
		if ($::RUNCMD_RC != 0)
		{
			my $rsp;
            push @{$rsp->{data}}, "Unable to set root password.";
			push @{$rsp->{data}}, "$out\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
		}
	}

    #
    # Output results
    #
    #

    # only display the attrs for the osimage def
    my $datatype = $xCAT::Schema::defspec{'osimage'};
    my @osattrlist;
    foreach my $this_attr (@{$datatype->{'attrs'}})
    {
        my $attr = $this_attr->{attr_name};
        push(@osattrlist, $attr);
    }

    my $rsp;
    push @{$rsp->{data}},
      "The following xCAT osimage definition was created. Use the xCAT lsdef command \nto view the xCAT definition and the AIX lsnim command to view the individual \nNIM resources that are included in this definition.";

    push @{$rsp->{data}}, "\nObject name: $::image_name";

    foreach my $attr (sort(keys %{$osimagedef{$::image_name}}))
    {
        if ($attr eq 'objtype')
        {
            next;
        }
        if (!grep (/^$attr$/, @osattrlist))
        {
            next;
        }
        if ($osimagedef{$::image_name}{$attr} ne '')
        {
            push @{$rsp->{data}}, "\t$attr=$osimagedef{$::image_name}{$attr}";
        }
    }
    xCAT::MsgUtils->message("I", $rsp, $callback);

    return 0;

}    # end mknimimage

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
	my $attrs    = shift;
    my $callback = shift;

	my %attrres;
	if ($attrs) {
		%attrres = %{$attrs};
	}

	my @validattrs = ("verbose", "nfs_vers", "nfs_sec", "packages", "use_source_simages", "arch", "show_progress", "multi_volume", "group");

    my @lppresources;
    my $lppsrcname;
    my $install_dir = xCAT::Utils->getInstallDir();

    #
    #  Get a list of the defined lpp_source resources
    #
    my $cmd =
      qq~/usr/sbin/lsnim -t lpp_source | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    @lppresources = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get NIM lpp_source definitions.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return undef;
    }

    #
    # get an lpp_source resource to use
    #
    if ($attrres{lpp_source})
    {

        # if lpp_source provided then use it
        $lppsrcname = $attrres{lpp_source};

    }
    elsif ($::opt_i)
    {

		# if -p then also make a copy of the lpp_source
		if ($::opt_p) {

			# create a new lpp_source - with new name
			#  copy one from opt_i image to new location and define

			# get name of lpp provided
			# if we have lpp_source name in osimage def then use that
			my $origlpp;
            if ($::imagedef{$::opt_i}{lpp_source})
            {
                $origlpp = $::imagedef{$::opt_i}{lpp_source};
            }
            else
            {
                my $rsp;
                push @{$rsp->{data}},
                "The $::opt_i image definition did not contain a value for lpp_source.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return undef;
            }

			#   make a new name using the convention 
			#		and check if it already exists
			$lppsrcname = $::image_name . "_lpp_source";
			if (grep(/^$lppsrcname$/, @lppresources))
			{
				my $rsp;
				push @{$rsp->{data}}, "Cannot create $lppsrcname. It already exists.\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
			}

			# get location of orig lpp_source
			my $nimprime = xCAT::InstUtils->getnimprime();
			my $origloc;
			$origloc = xCAT::InstUtils->get_nim_attr_val($::imagedef{$::opt_i}{lpp_source}, 'location', $callback, $nimprime);

			# get new location
			if ($::opt_l =~ /\/$/)
            {
                $::opt_l =~ s/\/$//; #remove tailing slash if needed
            }

            my $loc;
            if ($::opt_l)
            {
                $loc = "$::opt_l/lpp_source/$lppsrcname";
            }
            else
            {
                $loc = "$install_dir/nim/lpp_source/$lppsrcname";
            }

			# create resource location
            my $cmd = "/usr/bin/mkdir -p $loc";
            my $output = xCAT::Utils->runcmd("$cmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not create $loc.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$output\n";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return undef;
            }

			# check the file system space needed ????
            #  about 1500 MB for a basic lpp_source???
            my $lppsize = 1500;
            if (&chkFSspace($loc, $lppsize, $callback) != 0)
            {
                return undef;
            }

			# copy original lpp_source
            my $cpcmd = qq~mkdir -m 644 -p $loc; cp -r $origloc/* $loc~;
			$output = xCAT::Utils->runcmd("$cpcmd", -1);
			if ($::RUNCMD_RC != 0)
			{
				my $rsp;
				push @{$rsp->{data}}, "Could not copy $origloc to $loc.\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
			}

            # build an lpp_source
            my $rsp;
            push @{$rsp->{data}},
              "Creating a NIM lpp_source resource called \'$lppsrcname\'.  This could take a while.\n";
            xCAT::MsgUtils->message("I", $rsp, $callback);
			# make cmd
            my $lpp_cmd =
              "/usr/sbin/nim -Fo define -t lpp_source -a server=master ";

            # check for relevant cmd line attrs
            my %cmdattrs;
            if ( ($::NFSV4) && (!$attrres{nfs_vers}) )
            {
                $cmdattrs{nfs_vers}=4;
            }

            if (%attrres) {
                foreach my $attr (keys %attrres) {
                    if (grep(/^$attr$/, @validattrs) ) {
                        $cmdattrs{$attr} = $attrres{$attr};
                    }
                }
            }

			if (%cmdattrs) {
                foreach my $attr (keys %cmdattrs) {
                    $lpp_cmd .= "-a $attr=$cmdattrs{$attr} ";
                }
            }

            # where to put it - the default is /install
            $lpp_cmd .= "-a location=$loc $lppsrcname";

			# don't need source since the lpp dirs/file have already 
			#	been created in the location

            $output = xCAT::Utils->runcmd("$lpp_cmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not run command \'$lpp_cmd\'. (rc = $::RUNCMD_RC)\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return undef;
            }

		} else {

        	# if we have lpp_source name in osimage def then use that
        	if ($::imagedef{$::opt_i}{lpp_source})
        	{
            	$lppsrcname = $::imagedef{$::opt_i}{lpp_source};
        	}
        	else
        	{
            	my $rsp;
            	push @{$rsp->{data}},
              	"The $::opt_i image definition did not contain a value for lpp_source.\n";
            	xCAT::MsgUtils->message("E", $rsp, $callback);
            	return undef;
        	}
		}
    }
    elsif ($::opt_s)
    {

        # if source is provided we may need to create a new lpp_source

        # if existing lpp_source then use it
        if ((grep(/^$::opt_s$/, @lppresources)))
        {

            # if an lpp_source was provided then use it
            return $::opt_s;

        }

        #   make a name using the convention and check if it already exists
        $lppsrcname = $::image_name . "_lpp_source";

        if (grep(/^$lppsrcname$/, @lppresources))
        {
            my $rsp;
            push @{$rsp->{data}},
              "Using the existing lpp_source named \'$lppsrcname\'\n";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }
        else
        {

            # create a new one

            # the opt_s must be a source directory or an existing
            #	lpp_source resource
            if (!(grep(/^$::opt_s$/, @lppresources)))
            {
                if ($::opt_s !~ /^\//)
                {
                    my $abspath = xCAT::Utils->full_path($::opt_s, $::cwd);
                    if ($abspath)
                    {
                        $::opt_s = $abspath;
                    }
                }
                if (!(-e $::opt_s))
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "\'$::opt_s\' is not a source directory or the name of a NIM lpp_source resource.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    &mknimimage_usage($callback);
                    return undef;
                }
            }

			if ($::opt_l =~ /\/$/)
			{
				$::opt_l =~ s/\/$//; #remove tailing slash if provided
			}

            my $loc;
            if ($::opt_l)
            {
                $loc = "$::opt_l/lpp_source/$lppsrcname";
            }
            else
            {
                $loc = "$install_dir/nim/lpp_source/$lppsrcname";
            }

            # create resource location
            my $cmd = "/usr/bin/mkdir -p $loc";
            my $output = xCAT::Utils->runcmd("$cmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not create $loc.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$output\n";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return undef;
            }

            # check the file system space needed ????
            #  about 1500 MB for a basic lpp_source???
            my $lppsize = 1500;
            if (&chkFSspace($loc, $lppsize, $callback) != 0)
            {
                return undef;
            }

            # build an lpp_source
            my $rsp;
            push @{$rsp->{data}},
              "Creating a NIM lpp_source resource called \'$lppsrcname\'.  This could take a while.\n";
            xCAT::MsgUtils->message("I", $rsp, $callback);

            # make cmd
            my $lpp_cmd =
              "/usr/sbin/nim -Fo define -t lpp_source -a server=master ";

			# check for relevant cmd line attrs
			my %cmdattrs;
			if ( ($::NFSV4) && (!$attrres{nfs_vers}) )
			{
				$cmdattrs{nfs_vers}=4;
			}

			if (%attrres) {
				foreach my $attr (keys %attrres) {
					if (grep(/^$attr$/, @validattrs) ) {
						$cmdattrs{$attr} = $attrres{$attr};
					}
				}
			}

			if (%cmdattrs) {
				foreach my $attr (keys %cmdattrs) {
					$lpp_cmd .= "-a $attr=$cmdattrs{$attr} ";
				}
			}

            # where to put it - the default is /install
            $lpp_cmd .= "-a location=$loc ";

            $lpp_cmd .= "-a source=$::opt_s $lppsrcname";
            $output = xCAT::Utils->runcmd("$lpp_cmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not run command \'$lpp_cmd\'. (rc = $::RUNCMD_RC)\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return undef;
            }

			#
			# make sure we get the extra packages we need
			#   - openssh, ?
			#
			my $out;
			my $outp;
			my $ccmd;

			# try to find openssh and copy it to the new lpp_source loc
			my $fcmd = "/usr/bin/find $::opt_s -print | /usr/bin/grep openssh.base";
			$outp = xCAT::Utils->runcmd("$fcmd", -1);
			if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not find openssh file sets in source location.\n";
                xCAT::MsgUtils->message("W", $rsp, $callback);
            }

			chomp $outp;
			my $dir = dirname($outp);

			$ccmd = "/usr/bin/cp $dir/openssh* $loc/installp/ppc 2>/dev/null";
			$out = xCAT::Utils->runcmd("$ccmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not copy openssh to $loc/installp/ppc.\n";
                xCAT::MsgUtils->message("W", $rsp, $callback);
            }
			
			# run inutoc
			my $icmd = "/usr/sbin/inutoc $loc/installp/ppc";
			$out = xCAT::Utils->runcmd("$icmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not run inutoc on $loc/installp/ppc.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
            }
        }
    }
    else
    {
        my $rsp;
        push @{$rsp->{data}},
          "Could not get an lpp_source resource for this diskless image.\n";
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
	my $attrs    = shift;
    my $callback   = shift;

	my %attrres;
	if ($attrs) {
		%attrres = %{$attrs};
	}

	my @validattrs = ("verbose", "nfs_vers", "nfs_sec", "auto_expand", "installp_flags", "source", "show_progress", "debug", );

    my $spot_name;
    my $currentimage;
    my $install_dir = xCAT::Utils->getInstallDir();

    if ($::attrres{spot})
    {

        # if spot provided then use it
        $spot_name = $::attrres{spot};

    }
    elsif ($::opt_i)
    {

        # copy the spot named in the osimage def

        # use the image name for the new SPOT/COSI name
        $spot_name = $::image_name;

        if ($::imagedef{$::opt_i}{spot})
        {

            # a spot was provided as a source so copy it to create a new one
            my $cpcosi_cmd = "/usr/sbin/cpcosi ";

            # name of cosi to copy
            $currentimage = $::imagedef{$::opt_i}{spot};
            chomp $currentimage;
            $cpcosi_cmd .= "-c $currentimage ";

            # do we want verbose output?
            if ($::VERBOSE)
            {
                $cpcosi_cmd .= "-v ";
            }

            # where to put it - the default is /install
			my $spotloc;
            if ($::opt_l)
            {
                $cpcosi_cmd .= "-l $::opt_l/spot ";
				$spotloc ="$::opt_l/spot";
            }
            else
            {
                $cpcosi_cmd .= "-l $install_dir/nim/spot  ";
				$spotloc ="$install_dir/nim/spot";
            }

            $cpcosi_cmd .= "$spot_name  2>&1";

			# check the file system space needed
			#   800 MB for spot
			my $spotsize = 800;
			if (&chkFSspace($spotloc, $spotsize, $callback) != 0)
			{
				# error
				return undef;
			}

            # run the cmd
            my $rsp;
            push @{$rsp->{data}},
              "Creating a NIM SPOT resource. This could take a while.\n";
            xCAT::MsgUtils->message("I", $rsp, $callback);
            my $output = xCAT::Utils->runcmd("$cpcosi_cmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not create a NIM definition for \'$spot_name\'.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return undef;
            }
        }
        else
        {
            my $rsp;
            push @{$rsp->{data}},
              "The $::opt_i image definition did not contain a value for a SPOT resource.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return undef;
        }

    }
    else
    {

        # create a new spot from the lpp_source

        # use the image name for the new SPOT/COSI name
        $spot_name = $::image_name;

        if (grep(/^$spot_name$/, @::nimresources))
        {
            my $rsp;
            push @{$rsp->{data}},
              "Using the existing SPOT named \'$spot_name\'.\n";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }
        else
        {

            # Create the SPOT/COSI
            my $cmd = "/usr/sbin/nim -o define -t spot -a server=master ";

			# check for relevant cmd line attrs
			my %cmdattrs;
			if ( ($::NFSV4) && (!$attrres{nfs_vers}) )
			{
				$cmdattrs{nfs_vers}=4;
			}

			# check for relevant cmd line attrs
			if (%attrres) {
				foreach my $attr (keys %attrres) {
					if (grep(/^$attr$/, @validattrs) ) {
						$cmdattrs{$attr} = $attrres{$attr};
					}
				}
			}

			if (%cmdattrs) {
				foreach my $attr (keys %cmdattrs) {
					$cmd .= "-a $attr=$cmdattrs{$attr} ";
				}
			}

            # source of images
            if ($::METHOD eq "mksysb")
            {

                # Create spot from mksysb image
                my $mksysbname = $::image_name . "_mksysb";
                $cmd .= "-a source=$mksysbname ";
            }
            else
            {
                $cmd .= "-a source=$lppsrcname ";
            }

            # where to put it - the default is /install
            my $loc;
            if ($::opt_l)
            {
                $cmd .= "-a location=$::opt_l/spot ";
                $loc = "$::opt_l/spot";
            }
            else
            {
                $cmd .= "-a location=$install_dir/nim/spot  ";
                $loc = "$install_dir/nim/spot";
            }

            # create resource location
            my $mkdircmd = "/usr/bin/mkdir -p $loc";
            my $output = xCAT::Utils->runcmd("$mkdircmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not create $loc.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$output\n";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return undef;
            }

            # check the file system space needed
            #	800 MB for spot ?? 64MB for tftpboot???
            my $spotsize = 800;
            if (&chkFSspace($loc, $spotsize, $callback) != 0)
            {
                # error
                return undef;
            }

            $loc = "/tftpboot";

            # create resource location
            $mkdircmd = "/usr/bin/mkdir -p $loc";
            $output = xCAT::Utils->runcmd("$mkdircmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not create $loc.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$output\n";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return undef;
            }
            my $tftpsize = 64;
            if (&chkFSspace($loc, $tftpsize, $callback) != 0)
            {

                # error
                return undef;
            }

            $cmd .= "$spot_name  2>&1";

            # run the cmd
            my $rsp;
            push @{$rsp->{data}},
              "Creating a NIM SPOT resource. This could take a while.\n";
            xCAT::MsgUtils->message("I", $rsp, $callback);
            $output = xCAT::Utils->runcmd("$cmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not create a NIM definition for \'$spot_name\'.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                if ($::VERBOSE)
                {
                    my $rsp;
                    push @{$rsp->{data}}, "Error message is: \'$output\'\n";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }
                return undef;
            }
        }    # end - if spot doesn't exist
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
	my $attrs    = shift;
    my $callback = shift;

	my %attrres;
	if ($attrs) {
		%attrres = %{$attrs};
	}

    my $bosinst_data_name = $::image_name . "_bosinst_data";

	my @validattrs = ("verbose", "nfs_vers", "nfs_sec", "dest_dir", "group", "source");
	my $install_dir = xCAT::Utils->getInstallDir();

    if ($attrres{bosinst_data})
    {

        # if provided then use it
        $bosinst_data_name = $attrres{bosinst_data};

    }
    elsif ($::opt_i)
    {

        # if one is provided in osimage and we don't want a new one
        if ($::imagedef{$::opt_i}{bosinst_data})
        {
            $bosinst_data_name = $::imagedef{$::opt_i}{bosinst_data};
        }

    }
    else
    {

        # see if it's already defined
        if (grep(/^$bosinst_data_name$/, @::nimresources))
        {
            my $rsp;
            push @{$rsp->{data}},
              "Using existing bosinst_data resource named \'$bosinst_data_name\'.\n";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }
        else
        {

            my $loc;
            if ($::opt_l)
            {
                $loc = "$::opt_l/bosinst_data";
            }
            else
            {
                $loc = "$install_dir/nim/bosinst_data";
            }

            my $cmd = "mkdir -p $loc";

            my $output = xCAT::Utils->runcmd("$cmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not create a NIM definition for \'$bosinst_data_name\'.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$output\n";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return undef;
            }

            # copy/modify the template supplied by NIM
            my $sedcmd =
              "/usr/bin/sed 's/GRAPHICS_BUNDLE = .*/GRAPHICS_BUNDLE = no/; s/SYSTEM_MGMT_CLIENT_BUNDLE = .*/SYSTEM_MGMT_CLIENT_BUNDLE = no/; s/CONSOLE = .*/CONSOLE = Default/; s/INSTALL_METHOD = .*/INSTALL_METHOD = overwrite/; s/PROMPT = .*/PROMPT = no/; s/EXISTING_SYSTEM_OVERWRITE = .*/EXISTING_SYSTEM_OVERWRITE = yes/; s/RECOVER_DEVICES = .*/RECOVER_DEVICES = no/; s/ACCEPT_LICENSES = .*/ACCEPT_LICENSES = yes/; s/DESKTOP = .*/DESKTOP = NONE/' /usr/lpp/bosinst/bosinst.template >$loc/$bosinst_data_name";

            $output = xCAT::Utils->runcmd("$sedcmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not create bosinst_data file.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$output\n";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return undef;
            }

            # define the new bosinst_data resource
            $cmd = "/usr/sbin/nim -o define -t bosinst_data -a server=master ";

			# check for relevant cmd line attrs
			my %cmdattrs;
			if ( ($::NFSV4) && (!$attrres{nfs_vers}) )
			{
				$cmdattrs{nfs_vers}=4;
			}

			# check for relevant cmd line attrs
			if (%attrres) {
				foreach my $attr (keys %attrres) {
					if (grep(/^$attr$/, @validattrs) ) {
						$cmdattrs{$attr} = $attrres{$attr};
					}
				}
			}

			if (%cmdattrs) {
				foreach my $attr (keys %cmdattrs) {
					$cmd .= "-a $attr=$cmdattrs{$attr} ";
				}
			}

            $cmd .= "-a location=$loc/$bosinst_data_name  ";
            $cmd .= "$bosinst_data_name  2>&1";

            if ($::VERBOSE)
            {
                my $rsp;
                push @{$rsp->{data}}, "Running: \'$cmd\'\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }

            $output = xCAT::Utils->runcmd("$cmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not create a NIM definition for \'$bosinst_data_name\'.\n";
                if ($::VERBOSE)
                {
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

=head3   mk_resolv_conf_file

        Create a resolv.conf file from data in xCAT site table.

		Only if the node "domain" & "nameservers" attrs are set!

        Returns:
                0 - OK
                1 - error
=cut

#-----------------------------------------------------------------------------
sub mk_resolv_conf_file
{
    my $callback = shift;
    my $loc      = shift;
    my $subreq   = shift;

    my $nimprime = xCAT::InstUtils->getnimprime();
    chomp $nimprime;

    my $fullname = "$loc/resolv.conf";

    # check site table - get domain, nameservers attr
    my $sitetab = xCAT::Table->new('site');
    my ($tmp) = $sitetab->getAttribs({'key' => 'domain'}, 'value');
    my $domain = $tmp->{value};
    my ($tmp2) = $sitetab->getAttribs({'key' => 'nameservers'}, 'value');

    # convert <xcatmaster> to nameserver IP
    my $nameservers;
    if ($tmp2->{value} eq '<xcatmaster>')
    {
        $nameservers = xCAT::InstUtils->convert_xcatmaster();
    }
    else
    {
        $nameservers = $tmp2->{value};
    }

    $sitetab->close;

    # if set then create file
    if ($domain && $nameservers)
    {

        # fullname is something like
        #	/install/nim/resolv_conf/610img_resolv_conf/resolv.conf

        my $mkcmd  = qq~/usr/bin/mkdir -p $loc~;
        my $output =
          xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $mkcmd,
                                0);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not create $loc.\n";
            if ($::VERBOSE)
            {
                push @{$rsp->{data}}, "$output\n";
            }
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return undef;
        }

        my $cmd = qq~echo search $domain > $fullname~;
        if ($::VERBOSE)
        {
            my $rsp;

            push @{$rsp->{data}}, "Set domain $domain into $fullname";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }

        # add the domain
        $output =
          xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not add domain into $fullname";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }

        # add nameservers
        my $nameserverstr;
        foreach (split /,/, $nameservers)
        {
            $nameserverstr = "nameserver $_";
            chomp($nameserverstr);

            $cmd = qq~echo $nameserverstr >> $fullname~;
            if ($::VERBOSE)
            {
                my $rsp;
                push @{$rsp->{data}}, "Add $nameserverstr into $fullname";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }

            $output =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not add nameservers into $fullname";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }   
        }
    }
    else
    {
        return 1;
    }
    return 0;
}

#----------------------------------------------------------------------------

=head3   chk_resolv_conf

        See if new NIM resolv_conf resource is needed.

		Create if needed.  Created on local server.

		Called by: nimnodeset() and mkdsklsnode()

        Returns:
               0 - undef
               1 - ptr to hash of resolv_conf resource names
=cut

#-----------------------------------------------------------------------------
sub chk_resolv_conf
{
    my $callback = shift;
	my $nodedefs = shift;
	my $nodes    = shift;
	my $networks = shift;
	my $imgdefs  = shift;
	my $attr     = shift;
	my $nosi     = shift;
    my $subreq   = shift;

	my %nodehash;
    if ($nodedefs) {
        %nodehash = %{$nodedefs};
    }
	my @nodelist;
    if ($nodes) {
        @nodelist = @{$nodes};
    }
	my %nethash;
    if ($networks) {
        %nethash = %{$networks};
    }
	my %attrres;
    if ($attr) {
        %attrres = %{$attr};
    }
	my %imghash;
    if ($imgdefs) {
        %imghash = %{$imgdefs};
    }
	my %nodeosi;
	if ($nosi) {
		%nodeosi = %{$nosi};
	}

	# get name as known by xCAT
    my $Sname = xCAT::InstUtils->myxCATname();
    chomp $Sname;

	my %resolv_conf_hash;
	my $resolv_conf_name;

	my $nimprime = xCAT::InstUtils->getnimprime();
    chomp $nimprime;

	# get site domain and nameservers values
	my $sitetab = xCAT::Table->new('site');
	my ($tmp) = $sitetab->getAttribs({'key' => 'domain'}, 'value');
    my $site_domain = $tmp->{value};

	my ($tmp2) = $sitetab->getAttribs({'key' => 'nameservers'}, 'value');
    my $site_nameservers = $tmp2->{value};
    $sitetab->close;

	#  Get a list of the all NIM resources
    #
    my $cmd =
      qq~/usr/sbin/lsnim -c resources | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    my @nimresources =
      xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Sname, $cmd, 1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get list of NIM resources.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	# 
	# get all the possible IPs for the node I'm running on
	#
	my $ifgcmd = "ifconfig -a | grep 'inet '";
	my @result = xCAT::Utils->runcmd($ifgcmd, 0);
	if ($::RUNCMD_RC != 0)
	{
		my $rsp;
		push @{$rsp->{data}}, "Could not run \'$ifgcmd\'.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}

	my @myIPs;
	foreach my $int (@result) {
		my ($inet, $IP, $str) = split(" ", $int);
		chomp $IP;
		$IP =~ s/\/.*//; # ipv6 address 4000::99/64
		$IP =~ s/\%.*//; # ipv6 address ::1%1/128
		push @myIPs, $IP;
	}

	#
	# check each node to make sure we have the correct resolv.conf 
	#	for each one
	#
	foreach my $node (@nodelist) {

		my $domain;
		my $create_res=0;
		my $nameservers;
		my @nservers;
		my $ns;

		my $image_name = $nodeosi{$node};
        chomp $image_name;

		#
		#  if provided in osimage def then use that
		# 		- this would have been provided by the user and should
		#		    take precedence
		#
		#  otherwise see if we can create a new resolv_conf resource
		#
		if ( $imghash{$image_name}{resolv_conf} ) {

			# first priority -  osimage oriented
			# don't need to create new resolv_conf

			# keep track of what resource should be used for each node
			$resolv_conf_hash{$node} = $imghash{$image_name}{resolv_conf};

		} elsif ( ($nethash{$node}{nameservers} && $nethash{$node}{domain}) ){

			# second priority - from network def
			#
            #  if the network def corresponding to the node has a domain AND
            #       nameservers value
            #

			# use convention for res name "<netname>_resolv_conf"
			$resolv_conf_name = $nethash{$node}{netname} . "_resolv_conf";
			$resolv_conf_hash{$node} = $resolv_conf_name;

			# then create resolv_conf using these values
			$domain=$nethash{$node}{domain};
			if ( $nethash{$node}{nameservers} =~ /xcatmaster/ ) {

				# -  service node/network  oriented

				# then use xcatmaster value of node def
#ndebug
				# with statelite we need to set up both primary and backup SNs
				# see which one we are and set the correct server
				my $xmast;
				my ($sn1, $sn2) = split(/,/, $nodehash{$node}{servicenode});

				# if I'm the primary SN then just use the 
				#		the xcatmaster value.
				if ($sn1) {
					if (xCAT::InstUtils->is_me($sn1)) {
						$xmast = $nodehash{$node}{xcatmaster};
					}
				} 
				
				# if I'm the backup SN then figure out which interface
				#	 to use for the node server name (ie. xcatmaster value)
				if ($sn2) {
					if (xCAT::InstUtils->is_me($sn2)) {
						foreach my $int (@myIPs) {
							if ( xCAT::NetworkUtils->ishostinsubnet($int, $nethash{$node}{mask}, $nethash{$node}{net} )) {
								$xmast = xCAT::NetworkUtils->gethostname($int);
								last;
							}
						}
					}
				}

				my $server;
                if ($xmast) {
                    $server=$xmast;
                } else {
                    $server=$nimprime;
                }

				my $n = xCAT::NetworkUtils->getipaddr($server);
       			chomp $n;
				push(@nservers, $n);

			} else {

				# - network oriented

				# use actual value of nameservers
				my @tmp = split /,/, $nethash{$node}{nameservers};
				foreach my $s (@tmp) {
					my $n = xCAT::NetworkUtils->getipaddr($s);
					chomp $n;
					push(@nservers, $n);
				}
			}
			$create_res++;

		} elsif ( $site_nameservers && $site_domain ) {

			# third priority - from site table

			$domain=$site_domain;

			if ( $site_nameservers =~ /xcatmaster/ ) {

				# service node oriented

				# then use xcatmaster value of node def

#ndebug
				# with statelite we need to set up both primary and backup SNs
                # see which one we are and set the correct server
                my $xmast;
                my ($sn1, $sn2) = split(/,/, $nodehash{$node}{servicenode});

                # if I'm the primary SN then just use the
                #       the xcatmaster value.
                if ($sn1) {
                    if (xCAT::InstUtils->is_me($sn1)) {
                        $xmast = $nodehash{$node}{xcatmaster};
                    }
                }

				# if I'm the backup SN then figure out which interface
                #    to use for the node server name (ie. xcatmaster value)
                if ($sn2) {
                    if (xCAT::InstUtils->is_me($sn2)) {
                        foreach my $int (@myIPs) {
                            if ( xCAT::NetworkUtils->ishostinsubnet($int, $nethash{$node}{mask}, $nethash{$node}{net} )) {
								$xmast = xCAT::NetworkUtils->gethostname($int);
                                last;
                            }
                        }
                    }
                }

				my $server;
                if ($xmast) {
                    $server=$xmast;
                } else {
                    $server=$nimprime;
                }

                my $n = xCAT::NetworkUtils->getipaddr($server);
                chomp $n;
                push(@nservers, $n);

				# use convention for res name "<SN>_resolv_conf"
				$resolv_conf_name = $server . "_resolv_conf";
				$resolv_conf_hash{$node} = $resolv_conf_name;

			} else {

				# - cluster oriented

				# use actual value of nameservers
				my @tmp = split /,/, $site_nameservers;
				foreach my $s (@tmp) {
                    my $n = xCAT::NetworkUtils->getipaddr($s);
                    chomp $n;
                    push(@nservers, $n);
                }

				# use convention for res name
                $resolv_conf_name = "site_resolv_conf";
				$resolv_conf_hash{$node} = $resolv_conf_name;
			}
			$create_res++;
		}

		#
		# create a new NIM resolv_conf resource - if needed
		#
		if ($create_res) {

            my $fileloc;
            my $loc;
			my @validattrs = ("nfs_vers", "nfs_sec");

   			my $install_dir = xCAT::Utils->getInstallDir();
            if ($::opt_l)
            {
                $loc = "$::opt_l/resolv_conf/$resolv_conf_name";
            }
            else
            {
                $loc = "$install_dir/nim/resolv_conf/$resolv_conf_name";
            }

            my $filename = "$loc/resolv.conf";

			# remove any existing file - 
			if ( -e $filename ) {
				my $cmd = qq~/bin/rm $filename 2>/dev/null~;
				xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Sname, $cmd, 0);
				if ($::RUNCMD_RC != 0)
				{
					my $rsp;
					push @{$rsp->{data}}, "Could not remove \'$resolv_conf_name\'";
					xCAT::MsgUtils->message("I", $rsp, $callback);
				}
			}

            # create the resolv.conf file 
			my $mkcmd  = qq~/usr/bin/mkdir -p $loc~;
			my $output = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Sname, $mkcmd, 0);
			if ($::RUNCMD_RC != 0)
			{
				my $rsp;
				push @{$rsp->{data}}, "Could not create $loc.\n";
				if ($::VERBOSE)
				{
					push @{$rsp->{data}}, "$output\n";
				}
				xCAT::MsgUtils->message("E", $rsp, $callback);
				return undef;
			}

			#
			# add domain
			#
			# add the domain
			$cmd = qq~echo "search $domain" > $filename~;
       		$output = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Sname, $cmd, 0);
       		if ($::RUNCMD_RC != 0)
       		{
           		my $rsp;
           		push @{$rsp->{data}}, "Could not add domain to $filename";
           		xCAT::MsgUtils->message("E", $rsp, $callback);
           		return undef;
       		}

			# add nameservers entries
       		my $nameserverstr;
			foreach my $s (@nservers) 
       		{
           		$nameserverstr = "nameserver $s";
           		chomp($nameserverstr);

				$cmd = qq~echo $nameserverstr >> $filename~;

				$output = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Sname, $cmd, 0);
           		if ($::RUNCMD_RC != 0)
           		{
               		my $rsp;
               		push @{$rsp->{data}}, "Could not add nameservers to $filename";
               		xCAT::MsgUtils->message("E", $rsp, $callback);
               		return undef;
           		}
			}

			#
            # define the new resolv_conf resource
			#
			if (!grep(/^$resolv_conf_name$/, @nimresources))
            {

            	$cmd = "/usr/sbin/nim -o define -t resolv_conf -a server=master ";
				# check for relevant cmd line attrs
				my %cmdattrs;
				if ( ($::NFSV4) && (!$attrres{nfs_vers}) )
				{
					$cmdattrs{nfs_vers}=4;
				}

				if (%attrres) {
					foreach my $attr (keys %attrres) {
						if (grep(/^$attr$/, @validattrs) ) {
							$cmdattrs{$attr} = $attrres{$attr};
						}
					}
				}

				if (%cmdattrs) {
					foreach my $attr (keys %cmdattrs) {
						$cmd .= "-a $attr=$cmdattrs{$attr} ";
					}
				}

            	$cmd .= "-a location=$filename ";
            	$cmd .= "$resolv_conf_name  2>&1";

				$output = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Sname, $cmd, 0);
            	if ($::RUNCMD_RC != 0)
            	{
                	my $rsp;
                	push @{$rsp->{data}},
                  		"Could not create a NIM definition for \'$resolv_conf_name\'.\n";
                	xCAT::MsgUtils->message("E", $rsp, $callback);
                	return undef;
            	}

				my $rsp;
				push @{$rsp->{data}}, "Created a new resolv_conf resource called \'$resolv_conf_name\'.\n";
				xCAT::MsgUtils->message("I", $rsp, $callback);
			}
		}
	} # end foreach node

	return \%resolv_conf_hash;
}

#----------------------------------------------------------------------------

=head3   mk_resolv_conf

        Create a NIM   resource.

		Only if the node "domain" & "nameservers" attrs are set!  If
		not set assume user does not want resolv.conf file

        Returns:
                0 - OK
                1 - error
=cut

#-----------------------------------------------------------------------------
sub mk_resolv_conf
{
	my $attrs    = shift;
    my $callback = shift;
    my $subreq   = shift;

	my %attrres;
	if ($attrs) {
		%attrres = %{$attrs};
	}

	my @validattrs = ("verbose", "nfs_vers", "nfs_sec", "dest_dir", "group", "source");

    my $resolv_conf_name = $::image_name . "_resolv_conf";
    my $install_dir = xCAT::Utils->getInstallDir();

    if ($attrres{resolv_conf})
    {

        # if provided on cmd line then use it
        $resolv_conf_name = $attrres{resolv_conf};

    }
    elsif ($::opt_i)
    {

        # if one is provided in osimage def - use that
        if ($::imagedef{$::opt_i}{resolv_conf})
        {
            $resolv_conf_name = $::imagedef{$::opt_i}{resolv_conf};
        }

    }
    else
    {

        # we may need to create a new one
        # check site table - get domain, nameservers attr
        my $sitetab = xCAT::Table->new('site');
        my ($tmp) = $sitetab->getAttribs({'key' => 'domain'}, 'value');
        my $domain = $tmp->{value};
        my ($tmp2) = $sitetab->getAttribs({'key' => 'nameservers'}, 'value');
        # convert <xcatmaster> to nameserver IP
        my $nameservers;
        if ($tmp2->{value} eq '<xcatmaster>')
        {
            $nameservers = xCAT::InstUtils->convert_xcatmaster();
        }
        else
        {
            $nameservers = $tmp2->{value};
        }
        $sitetab->close;

        # if set then we want a resolv_conf file
        if (defined($domain) && defined($nameservers))
        {

            # see if it's already defined
            if (grep(/^$resolv_conf_name$/, @::nimresources))
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Using existing resolv_conf resource named \'$resolv_conf_name\'.\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }
            else
            {

                my $fileloc;
                my $loc;
                if ($::opt_l)
                {
                    $loc = "$::opt_l/resolv_conf/$resolv_conf_name";
                }
                else
                {
                    $loc = "$install_dir/nim/resolv_conf/$resolv_conf_name";
                }

                $fileloc = "$loc/resolv.conf";

                # create the resolv.conf file based on the domain & nameservers
                #	attrs in the xCAT site table
                my $rc = &mk_resolv_conf_file($callback, $loc, $subreq);
                if ($rc != 0)
                {
                    return undef;
                }

                # define the new resolv_conf resource
                my $cmd =
                  "/usr/sbin/nim -o define -t resolv_conf -a server=master ";

				# check for relevant cmd line attrs
				my %cmdattrs;
				if ( ($::NFSV4) && (!$attrres{nfs_vers}) )
				{
					$cmdattrs{nfs_vers}=4;
				}

				if (%attrres) {
					foreach my $attr (keys %attrres) {
						if (grep(/^$attr$/, @validattrs) ) {
							$cmdattrs{$attr} = $attrres{$attr};
						}
					}
				}

				if (%cmdattrs) {
					foreach my $attr (keys %cmdattrs) {
						$cmd .= "-a $attr=$cmdattrs{$attr} ";
					}
				}

                $cmd .= "-a location=$fileloc ";
                $cmd .= "$resolv_conf_name  2>&1";

                if ($::VERBOSE)
                {
                    my $rsp;
                    push @{$rsp->{data}}, "Running: \'$cmd\'\n";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }

                my $output = xCAT::Utils->runcmd("$cmd", -1);
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "Could not create a NIM definition for \'$resolv_conf_name\'.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return undef;
                }

            }
        }
        else
        {
            return undef;
        }
    }    # end resolv_conf res

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
	my $attrs    = shift;
    my $callback = shift;

	my %attrres;
	if ($attrs) {
		%attrres = %{$attrs};
	}

	my @validattrs = ("verbose", "nfs_vers", "nfs_sec", "dest_dir", "group", "source", "size_preview", "exclude_files", "mksysb_flags", "mk_image");

    my $mksysb_name = $::image_name . "_mksysb";
	my $install_dir = xCAT::Utils->getInstallDir();
	
    if ($attrres{mksysb})
    {

        # if provided on cmd line then use it
        $mksysb_name = $attrres{mksysb};

    }
    else
    {

        # see if it's already defined
        if (grep(/^$mksysb_name$/, @::nimresources))
        {
            my $rsp;
            push @{$rsp->{data}},
              "Using existing mksysb resource named \'$mksysb_name\'.\n";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }
        else
        {

            # create the mksysb definition

            if ($::MKSYSBNODE)
            {

                my $loc;
                if ($::opt_l)
                {
                    $loc = "$::opt_l/mksysb/$::image_name";
                }
                else
                {
                    $loc = "$install_dir/nim/mksysb/$::image_name";
                }

                # create resource location for mksysb image
                my $cmd = "/usr/bin/mkdir -p $loc";
                my $output = xCAT::Utils->runcmd("$cmd", -1);
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp;
                    push @{$rsp->{data}}, "Could not create $loc.\n";
                    if ($::VERBOSE)
                    {
                        push @{$rsp->{data}}, "$output\n";
                    }
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return undef;
                }

                # check the file system space needed
                # about 1800 MB for a mksysb image???
                my $sysbsize = 1800;
                if (&chkFSspace($loc, $sysbsize, $callback) != 0)
                {

                    # error
                    return undef;
                }

                my $rsp;
                push @{$rsp->{data}},
                  "Creating a NIM mksysb resource called \'$mksysb_name\'.  This could take a while.\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);

                # create sys backup from remote node and define res
                my $location = "$loc/$mksysb_name";
                my $nimcmd = "/usr/sbin/nim -o define -t mksysb -a server=master ";

				# check for relevant cmd line attrs
				my %cmdattrs;
				if ( ($::NFSV4) && (!$attrres{nfs_vers}) )
				{
					$cmdattrs{nfs_vers}=4;
				}

				if (%attrres) {
					foreach my $attr (keys %attrres) {
						if (grep(/^$attr$/, @validattrs) ) {
							$cmdattrs{$attr} = $attrres{$attr};
						}
					}
				}

				if (%cmdattrs) {
					foreach my $attr (keys %cmdattrs) {
						$nimcmd .= "-a $attr=$cmdattrs{$attr} ";
					}
				}

				$nimcmd .= " -a location=$location -a mk_image=yes -a source=$::MKSYSBNODE $mksysb_name 2>&1";
                $output = xCAT::Utils->runcmd("$nimcmd", -1);
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "Could not define mksysb resource named \'$mksysb_name\'.\n";
                    if ($::VERBOSE)
                    {
                        push @{$rsp->{data}}, "$output\n";
                    }
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return undef;
                }

            }
            elsif ($::SYSB)
            {
                if ($::SYSB !~ /^\//)
                {    #relative path
                    $::SYSB = xCAT::Utils->full_path($::SYSB, $::cwd);
                }

                # def res with existing mksysb image
                my $mkcmd;
                if ($::NFSV4)
                {
                  $mkcmd = "/usr/sbin/nim -o define -t mksysb -a server=master -a nfs_vers=4 -a location=$::SYSB $mksysb_name 2>&1";
                }
                else
                {
                  $mkcmd = "/usr/sbin/nim -o define -t mksysb -a server=master -a location=$::SYSB $mksysb_name 2>&1";
                }

                if ($::VERBOSE)
                {
                    my $rsp;
                    push @{$rsp->{data}}, "Running: \'$mkcmd\'\n";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }

                my $output = xCAT::Utils->runcmd("$mkcmd", -1);
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "Could not define mksysb resource named \'$mksysb_name\'.\n";
                    if ($::VERBOSE)
                    {
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


=head3   prermnimimage

        Preprocessing for the rmnimimage command.

        Arguments:
        Returns:
        Globals:
        Error:
        Example:
        Comments:
=cut

#-----------------------------------------------------------------------------
sub prermnimimage
{
    my $callback = shift;

    my @servicenodes = ();    # pass back list of service nodes
    my %imagedef;             # pass back image def hash

    if (defined(@{$::args}))
    {
        @ARGV = @{$::args};
    }
    else
    {
        &rmnimimage_usage($callback);
        return (1);
    }

    # parse the options
    Getopt::Long::Configure("no_pass_through");
    if (
        !GetOptions(
                    'f|force'          => \$::FORCE,
                    'h|help'           => \$::HELP,
                    'd|delete'         => \$::DELETE,
                    'managementnode|M' => \$::MN,
                    's=s'              => \$::SERVERLIST,
                    'verbose|V'        => \$::VERBOSE,
                    'v|version'        => \$::VERSION,
                    'x|xcatdef'        => \$::XCATDEF,
        )
      )
    {

        &rmnimimage_usage($callback);
        return (1);
    }

    # display the usage if -h or --help is specified
    if ($::HELP)
    {
        &rmnimimage_usage($callback);
        return (2);
    }

    # display the version statement if -v or --verison is specified
    if ($::VERSION)
    {
        my $version = xCAT::Utils->Version();
        my $rsp;
        push @{$rsp->{data}}, "rmnimimage $version\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return (2);
    }

    my $image_name = shift @ARGV;

    # must have an image name
    if (!defined($image_name))
    {
        my $rsp;
        push @{$rsp->{data}}, "The xCAT osimage name is required.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        &rmnimimage_usage($callback);
        return (1);
    }

    #
    #  get list of defined xCAT osimage objects
    #
    my @deflist = undef;
    @deflist = xCAT::DBobjUtils->getObjectsOfType("osimage");

    # check if the provided image is valid.
    #
    if (!grep(/^$image_name$/, @deflist))
    {
        my $rsp;
        push @{$rsp->{data}}, "\'$image_name\' is not a valid xCAT image name.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return (1);
    } 

    # get the xCAT image definition
    my %objtype;
    $objtype{$image_name} = 'osimage';
    %imagedef = xCAT::DBobjUtils->getobjdefs(\%objtype, $callback);
    if (!(%imagedef))
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get xCAT image definition.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return (0);
    }

    #
    #  get a list of servers that we need to remove resources from
    #
    # NIM resources need to be removed on the NIM primary
    #	- not necessarily the management node - in mixed cluster
    my $nimprime = xCAT::InstUtils->getnimprime();
    chomp $nimprime;

    if ($::MN)
    {

        # only do management node
        @servicenodes = ("$nimprime");
    }
    elsif ($::SERVERLIST)
    {
        @servicenodes = xCAT::NodeRange::noderange($::SERVERLIST, 1);
    }
    else
    {

        # do MN and all servers
        # 	get all the service nodes
        my @nlist = xCAT::Utils->list_all_nodes;
        my $sn;
        my $service = "xcat";
        if (\@nlist)
        {
            $sn = xCAT::Utils->getSNformattedhash(\@nlist, $service, "MN");
        }
        foreach my $snkey (keys %$sn)
        {
            push(@servicenodes, $snkey);
        }
    }

    #
    # remove the osimage def - if requested
    #
    if ($::XCATDEF)
    {
        my %objhash;
        $objhash{$image_name} = "osimage";

        if (xCAT::DBobjUtils->rmobjdefs(\%objhash) != 0)
        {
            my $rsp;
            push @{$rsp->{data}},
              "Could not remove the existing xCAT definition for \'$image_name\'.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
        }
        else
        {
            my $rsp;
            push @{$rsp->{data}},
              "Removed the xCAT osimage definition \'$image_name\'.\n";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }
    }

    return (0, \%imagedef, \@servicenodes);
}

#----------------------------------------------------------------------------

=head3   rmnimimage

		Support for the rmnimimage command.

		Removes AIX/NIM resources

		Returns:
				0 - OK
				1 - error

=cut

#-----------------------------------------------------------------------------
sub rmnimimage
{
    my $callback = shift;
    my $imaghash = shift;
    my $subreq   = shift;

    my @servernodelist;

    my %imagedef;
    if ($imaghash)
    {
        %imagedef = %{$imaghash};
    }
    else
    {
        return 0;
    }

    if (defined(@{$::args}))
    {
        @ARGV = @{$::args};
    }
    else
    {
        &rmnimimage_usage($callback);
        return 0;
    }

    # parse the options
    Getopt::Long::Configure("no_pass_through");
    if (
        !GetOptions(
                    'f|force'          => \$::FORCE,
                    'h|help'           => \$::HELP,
                    'd|delete'         => \$::DELETE,
                    'managementnode|M' => \$::MN,
                    's=s'              => \$::SERVERLIST,
                    'verbose|V'        => \$::VERBOSE,
                    'v|version'        => \$::VERSION,
                    'x|xcatdef'        => \$::XCATDEF,
        )
      )
    {

        &rmnimimage_usage($callback);
        return 1;
    }

    my $image_name = shift @ARGV;

    # must have an image name
    if (!defined($image_name))
    {
        my $rsp;
        push @{$rsp->{data}}, "The xCAT osimage name is required.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        &rmnimimage_usage($callback);
        return 1;
    }

    # get this systems name as known by xCAT management node
    my $Sname = xCAT::InstUtils->myxCATname();
    chomp $Sname;

    #  should not need the next two checks???
    if ($::SERVERLIST)
    {
        @servernodelist = xCAT::NodeRange::noderange($::SERVERLIST, 1);
        if (!grep(/^$Sname$/, @servernodelist))
        {

            #  this node is not in the list so return
            return 0;
        }
    }

    if ($::MN)
    {
        if (!xCAT::Utils->isMN())
        {
            return 0;
        }
    }

    #
    #  Get a list of all nim resource types
    #
    my $cmd =
      qq~/usr/sbin/lsnim -P -c resources | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    my @nimrestypes = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "$Sname: Could not get NIM resource types.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    #
    #  Get a list of the all the locally defined nim resources
    #
    $cmd =
      qq~/usr/sbin/lsnim -c resources | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    my @nimresources = ();
    @nimresources = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "$Sname: Could not get NIM resource definitions.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    # foreach attr in the image def
    my $error;
    foreach my $attr (sort(keys %{$imagedef{$image_name}}))
    {
        chomp $attr;

        if (!grep(/^$attr$/, @nimrestypes))
        {
            next;
        }

		# don't remove lpp_source resource unless they specify delete
		if ( ($attr eq 'lpp_source')  && !$::DELETE)
		{
			next;
		}

        my @res_list;
        my $res_name = $imagedef{$image_name}{$attr};
        chomp $res_name;

        if ($attr eq 'script')
        {
            foreach (split /,/, $res_name)
            {
                chomp $_;
                push @res_list, $_;
            }
        }
        elsif ($attr eq 'installp_bundle')
        {
            foreach (split /,/, $res_name)
            {
                chomp $_;
                push @res_list, $_;
            }
        }
        else
        {
            push @res_list, $res_name;
        }

        foreach my $resname (@res_list)
        {

            # if it's a defined resource name we can try to remove it
            if ($resname && grep(/^$resname$/, @nimresources))
            {

                # is it allocated?
                my $alloc_count;
                # only change the logic for -s flag,
                # keep the original logic for other scenarios
                if ($::SERVERLIST)
                {
                    # get local hostname as target
                    my $hn = `hostname`;
                    $alloc_count =
                      xCAT::InstUtils->get_nim_attr_val($resname, "alloc_count",
                                                    $callback, $hn, $subreq);
                }
                else
                {
                    $alloc_count =
                      xCAT::InstUtils->get_nim_attr_val($resname, "alloc_count",
                                                    $callback, "", $subreq);
                }

                if (defined($alloc_count) && ($alloc_count != 0))
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "$Sname: The resource named \'$resname\' is currently allocated. It will not be removed.\n";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                    next;
                }

                my $loc;
                if ($::DELETE)
                {

                    # just use the NIM location value to remove these
                    if (   ($attr eq "lpp_source")
                        || ($attr eq "bosinst_data")
                        || ($attr eq "script")
                        || ($attr eq "installp_bundle")
                        || ($attr eq "root")
                        || ($attr eq "shared_root")
                        || ($attr eq "paging"))
                    {
                        $loc =
                          xCAT::InstUtils->get_nim_attr_val($resname,
                                            'location', $callback, $Sname, $subreq);
                    }

                    #  need the directory name to remove these
                    if (($attr eq "resolv_conf") || ($attr eq "spot"))
                    {
                        my $tmp =
                          xCAT::InstUtils->get_nim_attr_val($resname,
                                            'location', $callback, $Sname, $subreq);
                        $loc = dirname($tmp);
                    }
                }

                # try to remove it
                my $cmd = "nim -o remove $resname";

                my $output;
                $output = xCAT::Utils->runcmd("$cmd", -1);
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "$Sname: Could not remove the NIM resource definition \'$resname\'.\n";
                    push @{$rsp->{data}}, "$output";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    $error++;
                    next;
                }
                else
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "$Sname: Removed the NIM resource named \'$resname\'.\n";
                    xCAT::MsgUtils->message("I", $rsp, $callback);

                }

                if ($::DELETE)
                {
                    if ($loc)
                    {
                        my $cmd = qq~/usr/bin/rm -R $loc 2>/dev/null~;
                        my $output = xCAT::Utils->runcmd("$cmd", -1);
                    }
                }

            }
            else
            {
               # my $rsp;
               # push @{$rsp->{data}},
               #   "$Sname: A NIM resource named \'$resname\' is not defined.\n";
               # xCAT::MsgUtils->message("W", $rsp, $callback);
            }
        }
    }

    if ($error)
    {
        my $rsp;
        push @{$rsp->{data}},
          "$Sname: One or more errors occurred when trying to remove the xCAT osimage definition \'$image_name\' and the related NIM resources.\n";
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
    my $resname  = shift;
    my $respath  = shift;
    my $nimprime = shift;
    my $callback = shift;
    my $subreq   = shift;

    my ($defcmd, $output, $rc);

    my $cmd =
      qq~/usr/sbin/lsnim -c resources | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    my @nimresources =
      xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cmd, 1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get NIM resource definitions.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }
    if (!grep(/^$resname$/, @nimresources))
    {

        my $defcmd;
        if ($::NFSV4)
        {
           $defcmd = qq~/usr/sbin/nim -o define -t script -a server=master -a nfs_vers=4 -a location=$respath $resname 2>/dev/null~;
        }
        else
        {
           $defcmd = qq~/usr/sbin/nim -o define -t script -a server=master -a location=$respath $resname 2>/dev/null~;
        }

        my $output =
          xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $defcmd,
                                0);
        if ($::RUNCMD_RC != 0)
        {
            if ($::VERBOSE)
            {
                my $rsp;
                push @{$rsp->{data}}, "$output";
                xCAT::MsgUtils->message("E", $rsp, $callback);
            }
            return 1;
        }
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

    my $rhostname = "/.rhosts";
    my @addnodes;

    # make a list of node entries to add
    foreach my $node (@$nodelist)
    {

        # get the node IP for the file entry
        #my $IP = inet_ntoa(inet_aton($node));
        my $IP = xCAT::NetworkUtils->getipaddr($node);
        chomp $IP;
        unless (($IP =~ /\d+\.\d+\.\d+\.\d+/) || ($IP =~ /:/))
        {
            my $rsp;
            push @{$rsp->{data}},
              "Could not get valid IP address for node $node.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            next;
        }

        # is this node already in the file
        my $entry = "$IP root";

        #my $cmd = "cat $rhostname | grep '$IP root'";
        my $cmd = "cat $rhostname | grep $entry";
        my @result = xCAT::Utils->runcmd("$cmd", -1);
        if ($::RUNCMD_RC == 0)
        {

            # it's already there so next
            next;
        }
        push @addnodes, $entry;
    }

    if (@addnodes)
    {

        # add the new entries to the file
        unless (open(RHOSTS, ">>$rhostname"))
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not open $rhostname for appending.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
        foreach (@addnodes)
        {
            print RHOSTS $_ . "\n";
        }

        close(RHOSTS);
    }
    return 0;
}

#-------------------------------------------------------------------------

=head3   update_inittab  
                                                                         
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
    my $subreq   = shift;
    my $nimprime = xCAT::InstUtils->getnimprime();
    chomp $nimprime;

    my ($rc, $entry);

    my $spotinittab = "$spot_loc/lpp/bos/inst_root/etc/inittab";

    $entry = "xcat:2:wait:/opt/xcat/xcataixpost";

    # see if xcataixpost is already in the file
    my $cmd    = "cat $spotinittab | grep xcataixpost";
    my @result =
      xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cmd, 1);
    if ($::RUNCMD_RC == 0)
    {

        # it's already there so return
        return 0;
    }

    my $ecmd = qq~echo "$entry" >>$spotinittab~;
    @result =
      xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $ecmd, 1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not open $spotinittab for appending.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    return 0;
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
sub get_res_loc
{

    my $spotname = shift;
    my $callback = shift;
    my $subreq   = shift;

    #
    # get the primary NIM master - default to management node
    #
    my $nimprime = xCAT::InstUtils->getnimprime();
    chomp $nimprime;

    my $cmd = "/usr/sbin/lsnim -l $spotname 2>/dev/null";

    my @result =
      xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cmd, 1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not run lsnim command: \'$cmd\'.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    foreach my $line (@result)
    {

        # may contains the xdsh prefix <nodename>:
        $line =~ s/.*?://;
        my ($attr, $value) = split('=', $line);
        chomp $attr;
        $attr =~ s/\s*//g;    # remove blanks
        chomp $value;
        $value =~ s/\s*//g;    # remove blanks
        if ($attr eq 'location')
        {
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
sub chkFSspace
{
    my $location = shift;
    my $size     = shift;
    my $callback = shift;

    # get free space
    # ex. 1971.06 (Free MB)
    my $dfcmd =
      qq~/usr/bin/df -m $location | /usr/bin/awk '(NR==2){print \$3":"\$7}'~;

    my $output;
    $output = xCAT::Utils->runcmd("$dfcmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not run: \'$dfcmd\'\n";
        if ($::VERBOSE)
        {
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
    if ($size >= $free_space)
    {

        $space_needed = int($size - $free_space);
        my $addsize  = $space_needed + 100;
        my $sizeattr = "-a size=+$addsize" . "M";
        my $chcmd    = "/usr/sbin/chfs $sizeattr $FSname";

        my $output;
        $output = xCAT::Utils->runcmd("$chcmd", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}},
              "Could not increase file system size for \'$FSname\'. Additonal $addsize MB is needed.\n";
            if ($::VERBOSE)
            {
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
sub enoughspace
{

    my $spotname   = shift;
    my $rootname   = shift;
    my $pagingsize = shift;
    my $callback   = shift;

    #
    #  how much space do we need for a root dir?
    #

    #  Get the SPOT location ( path to ../usr)
    my $spot_loc = &get_res_loc($spotname, $callback);
    if (!defined($spot_loc))
    {
        my $rsp;
        push @{$rsp->{data}},
          "Could not get the location of the SPOT/COSI named $spot_loc.\n";
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
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not run: \'$ducmd\'\n";
        if ($::VERBOSE)
        {
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
    if (!defined($root_loc))
    {
        my $rsp;
        push @{$rsp->{data}},
          "Could not get the location of the SPOT/COSI named $root_loc.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    # get free space
    # ex. 1971.06 (Free MB)
    my $dfcmd =
      qq~/usr/bin/df -m $root_loc | /usr/bin/awk '(NR==2){print \$3":"\$7}'~;

    my $output;
    $output = xCAT::Utils->runcmd("$dfcmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not run: \'$dfcmd\'\n";
        if ($::VERBOSE)
        {
            push @{$rsp->{data}}, "$output";
        }
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    my ($root_free_space, $FSname) = split(':', $output);

    #
    #  see if we need to increase the size of the fs
    #
    if ($inst_root_size >= $root_free_space)
    {

        # try to increase the size of the root dir
        my $addsize  = int($inst_root_size + 10);
        my $sizeattr = "-a size=+$addsize" . "M";
        my $chcmd    = "/usr/sbin/chfs $sizeattr $FSname";

        my $output;
        $output = xCAT::Utils->runcmd("$chcmd", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not run: \'$chcmd\'\n";
            if ($::VERBOSE)
            {
                push @{$rsp->{data}}, "$output";
            }
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;

        }
    }

    return 0;
}

#----------------------------------------------------------------------------

=head3  mkdumpres

       Create a NIM diskless dump resource

        Returns:
                0 - OK
                1 - error
        Globals:

        Example:
			$rc = &mkdumpres($res_name, \%attrs, $callback, $location, 
				\%nimres);

        Comments:
=cut

#-----------------------------------------------------------------------------
sub mkdumpres
{
    my $res_name = shift;
    my $attrs    = shift;
    my $callback = shift;
    my $location = shift;
	my $nimres   = shift;

    my %attrvals; # cmd line attr=val pairs (from mknimimage)
	if ($attrs) {
		%attrvals = %{$attrs};   
	}
	my %nimhash; # NIM res attrs (from mkdsklsnode or nimnodeset)
	if ($nimres) {
		%nimhash  = %{$nimres};
	}

    if ($::VERBOSE)
    {
        my $rsp;
        push @{$rsp->{data}}, "Creating \'$res_name\'.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }

    my $type = 'dump';
	my @validattrs = ("dumpsize", "max_dumps", "notify", "snapcollect", "verbose", "nfs_vers", "group");

    my $cmd = "/usr/sbin/nim -o define -t $type -a server=master ";
    my $install_dir = xCAT::Utils->getInstallDir();

	my %cmdattrs;

	if ( ($::NFSV4) && (!$attrvals{nfs_vers}) )
	{
		$cmdattrs{nfs_vers}=4;
	}

	# add additional attributes - if provided - from the NIM definition on the 
	#		NIM primary - (when replicating on a service node)
	if (%nimhash) {
		foreach my $attr (keys %{$nimhash{$res_name}}) {
			if (grep(/^$attr$/, @validattrs) ) {
				$cmdattrs{$attr} = $nimhash{$res_name}{$attr};
			}
		}
	}

	# add any additional supported attrs from cmd line
	if (%attrvals) {
		foreach my $attr (keys %attrvals) {
			if (grep(/^$attr$/, @validattrs) ) {
				$cmdattrs{$attr} = $attrvals{$attr};
			}
		}
	}

	if (%cmdattrs) {
		foreach my $attr (keys %cmdattrs) {
			$cmd .= "-a $attr=$cmdattrs{$attr} ";
		}
	}

    # where to put it - the default is /install
    if ($location)
    {
        $cmd .= "-a location=$location "; 
    }
    else
    {
        $cmd .= "-a location=$install_dir/nim/dump/$res_name ";
    }


    $cmd .= "$res_name  2>&1";
    my $output = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        return 1;
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
			$rc = &mknimres($res_name, $res_type, $callback, $location, $spot_name);

        Comments: Handles: root, shared_root, home, shared_home, tmp, & paging
=cut

#-----------------------------------------------------------------------------
sub mknimres
{
    my $res_name  = shift;
    my $type      = shift;
    my $callback  = shift;
    my $location  = shift;
    my $spot_name = shift;
	my $attrs    = shift;
	my $nimres   = shift;

	my %attrvals; # cmd line attr=val pairs (from mknimimage)
	if ($attrs) {
		%attrvals = %{$attrs};
	}

	my %nimhash; # NIM res attrs (from mkdsklsnode or nimnodeset)
	if ($nimres) {
		%nimhash  = %{$nimres};
	}

    if ($::VERBOSE)
    {
        my $rsp;
        push @{$rsp->{data}}, "Creating \'$res_name\'.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }

	my @validattrs;
	@validattrs = ("nfs_vers", "verbose", "group");

    my $cmd = "/usr/sbin/nim -o define -t $type -a server=master ";
    my $install_dir = xCAT::Utils->getInstallDir();

	my %cmdattrs;
    if ($::NFSV4)
    {
		$cmdattrs{nfs_vers}=4;
    }

	# add additional attributes - if provided - from the NIM definition on the
	#       NIM primary - (when replicating on a service node)
	if (%nimhash) {
		foreach my $attr (keys %{$nimhash{$res_name}}) {
			if (grep(/^$attr$/, @validattrs) ) {
				$cmdattrs{$attr} = $nimhash{$res_name}{$attr};
			}
		}
	}

	# add any additional supported attrs from cmd line
	if (%attrvals) {
		foreach my $attr (keys %attrvals) {
			if (grep(/^$attr$/, @validattrs) ) {
				$cmdattrs{$attr} = $attrvals{$attr};
			}
		}
	}

	if (%cmdattrs) {
		foreach my $attr (keys %cmdattrs) {
			$cmd .= "-a $attr=$cmdattrs{$attr} ";
		}
	}

    # if this is a shared_root we need the spot name
    if ( ($type eq 'shared_root') && (!$cmdattrs{spot}) )
    {
        $cmd .= "-a spot=$spot_name ";
    }

    # where to put it - the default is /install
    if ($location)
    {
        $cmd .= "-a location=$location/$type/$res_name ";
    }
    else
    {
        $cmd .= "-a location=$install_dir/nim/$type/$res_name ";
    }
    $cmd .= "$res_name  2>&1";
    if ($::VERBOSE)
    {
        my $rsp;
        push @{$rsp->{data}}, "Running command: \'$cmd\'.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }
    my $output = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC != 0)
    {
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
sub updatespot
{
	my $image      = shift;
	my $imagehash  = shift;
	my $nodes      = shift;
	my $callback   = shift;
	my $subreq     = shift;

	my %imghash;  # osimage def
	if ($imagehash) {
		%imghash = %{$imagehash};
	}

	my @nodelist;
	if ($nodes) {
		@nodelist = @$nodes;
	}

	my $spot_name = $imghash{$image}{spot};
	my $lppsrcname = $imghash{$image}{lpp_source};

    my $spot_loc;

    if ($::VERBOSE)
    {
        my $rsp;
        push @{$rsp->{data}}, "Updating $spot_name.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }

    # get the name of the primary NIM server
    #   - either the NIMprime attr of the site table or the management node
    my $nimprime = xCAT::InstUtils->getnimprime();
    chomp $nimprime;

    #
    #  Get the SPOT location ( path to ../usr)
    #
    $spot_loc = &get_res_loc($spot_name, $callback, $subreq);
    if (!defined($spot_loc))
    {
        my $rsp;
        push @{$rsp->{data}},
          "Could not get the location of the SPOT/COSI named $spot_loc.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    #
    # Create ODMscript in the SPOT and modify the rc.dd-boot script
    #	- need for rnetboot to work - handles default console setting
    #
    my $odmscript    = "$spot_loc/ODMscript";
    my $odmscript_mn = "/tmp/ODMscript";
    my $cmd    = qq~ls $odmscript~;
    my $output =
      xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        if ($::VERBOSE)
        {
            my $rsp;
            push @{$rsp->{data}}, "Adding $odmscript to the image.\n";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }

        #  Create ODMscript script
        my $text =
          "CuAt:\n\tname = sys0\n\tattribute = syscons\n\tvalue = /dev/vty0\n\ttype = R\n\tgeneric =\n\trep = s\n\tnls_index = 0";

        if (open(ODMSCRIPT, ">$odmscript_mn"))
        {
            print ODMSCRIPT $text;
            close(ODMSCRIPT);
        }
        else
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not open $odmscript for writing.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
        my $cmd = "chmod 444 $odmscript_mn";
        my @result = xCAT::Utils->runcmd("$cmd", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not run the chmod command.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
        if (!xCAT::InstUtils->is_me($nimprime))
        {
            $cmd = "$::XCATROOT/bin/xdcp $nimprime $odmscript_mn $odmscript";
        }
        else
        {
            $cmd = "cp $odmscript_mn $odmscript";
        }
        @result = xCAT::Utils->runcmd("$cmd", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not copy the odmscript back";

            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
    }

	#
	#   check/do statelite setup
	#
	my $statelite=0;
	if ($imghash{$image}{shared_root}) {

		# if this has a shared_root resource then
		#   it might need statelite setup
		my $rc=xCAT::InstUtils->dolitesetup($image, \%imghash, \@nodelist, $callback, $subreq);
        if ($rc eq 1) { # error
            my $rsp;
            push @{$rsp->{data}}, qq{Could not complete the statelite setup.};

            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
	}

    # Modify the rc.dd-boot script 
	$statelite=1;
    my $boot_file = "$spot_loc/lib/boot/network/rc.dd_boot";
    if (&update_dd_boot($boot_file, $callback, $statelite, $subreq) != 0)
    {
        my $rsp;
        push @{$rsp->{data}},
          "Could not update the rc.dd_boot file in the SPOT.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    #
    # Copy the xcataixpost script to the SPOT/COSI and add an entry for it
    #	to the /etc/inittab file
    #
    if ($::VERBOSE)
    {
        my $rsp;
        push @{$rsp->{data}}, "Adding xcataixpost script to the image.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }

    # copy the script
    my $install_dir = xCAT::Utils->getInstallDir();
    my $cpcmd =
      "mkdir -m 644 -p $spot_loc/lpp/bos/inst_root/opt/xcat; cp $install_dir/postscripts/xcataixpost $spot_loc/lpp/bos/inst_root/opt/xcat/xcataixpost; chmod +x $spot_loc/lpp/bos/inst_root/opt/xcat/xcataixpost";

    my @result =
      xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cpcmd, 1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}},
          "Could not copy the xcataixpost script to the SPOT.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    # add an entry to the /etc/inittab file in the COSI/SPOT
    if (&update_inittab($spot_loc, $callback, $subreq) != 0)
    {
        my $rsp;
        push @{$rsp->{data}},
          "Could not update the /etc/inittab file in the SPOT.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    # change the inst_root dir to "root system"
    # the default is "bin bin" which will not work if the user
    #   wants to use ssh as the remote shell for the nodes
    my $inst_root_dir = "$spot_loc/lpp/bos/inst_root";
    my $chcmd         =
      "/usr/bin/chgrp system $inst_root_dir; /usr/bin/chown root $inst_root_dir";
    if ($::VERBOSE)
    {
        my $rsp;
        push @{$rsp->{data}}, "Running: \'$chcmd\'\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }

    @result =
      xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $chcmd, 1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}},
          "Could not change the group and owner for the inst_root directory.\n";
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
sub update_dd_boot
{

    my $dd_boot_file = shift;
    my $callback     = shift;
	my $statelite    = shift;
    my $subreq       = shift;

    my $nimprime = xCAT::InstUtils->getnimprime();
    chomp $nimprime;
    my $dd_boot_file_mn;
    my @lines;

    # see if orig file exists
    my $cmd;
    if (!xCAT::InstUtils->is_me($nimprime))
    {
        $cmd             = "$::XCATROOT/bin/xdcp $nimprime -P $dd_boot_file /tmp";
        $dd_boot_file_mn = "/tmp/rc.dd_boot._$nimprime";
    }
    else
    {
        $cmd             = "cp $dd_boot_file /tmp";
        $dd_boot_file_mn = "/tmp/rc.dd_boot";
    }
    my @result = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC == 0)
    {

        # only update if it has not been done yet
        #my $cmd = "cat $dd_boot_file_mn | grep 'xCAT basecust support'";
        #my @result = xCAT::Utils->runcmd("$cmd", -1);
        #if ($::RUNCMD_RC != 0)
        #{
            if ($::VERBOSE)
            {
                my $rsp;
                push @{$rsp->{data}}, "Updating the $dd_boot_file file.\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }

			my $odmrestore =qq~\n
	# xCAT basecust support #1
	#  when using a shared_root we need to see if there is a persistent 
	#		/etc/basecust file available.  If we have one we need to 
	#		restore it.  This will restore anything previously 
	#		saved in the ODM.
	if [ -n "\${NIM_SHARED_ROOT}" ]
	then
		#  Get the name of the server and the name of the persistent 
		#     directory to mount
		#  - /mnt is the shared_root dir at this point
		#  - the statelite.table file has entries like: 
		#			"compute04|10.2.0.200|/nodedata"
		if [ -f "/mnt/statelite.table" ]
		then
			# make sure we have the commands we need
			cp /SPOT/usr/bin/cat /usr/bin
			cp /SPOT/usr/bin/awk /usr/bin
			cp /SPOT/usr/bin/grep /usr/bin

			# statelite entry for this node
			SLLINE=`/usr/bin/cat /mnt/statelite.table | /usr/bin/grep \${NIM_NAME}`
			# the statelite server
			SLSERV=`echo \$SLLINE | /usr/bin/awk -F'|' '{print \$2}'`

			# statelite directory to mount
			SLDIR=`echo \$SLLINE | /usr/bin/awk -F'|' '{print \$3}'`

			mount \${SLSERV}:\${SLDIR} /tmp

			# - get the persistent version of basecust from the server
			if [ -f /tmp/\${NIM_NAME}/etc/basecust  ]; then
				cp -p /tmp/\${NIM_NAME}/etc/basecust /etc
				cp /SPOT/usr/lib/boot/restbase /usr/sbin
				cp /SPOT/usr/bin/uncompress /usr/bin
			fi
			umount /tmp
		fi
	fi
			\n\n~;
			
			my $mntbase=qq~
	# xCAT basecust support #2
    if [ -n "\${NIM_SHARED_ROOT}" ]
	then
		# if we found a statelite directory - above
		if [ -n "\${SLDIR}" ]
		then
			# need to mount persistent basecust over the one in RAM FS
			mount -o rw \${SLSERV}:\${SLDIR} /tmp
			/usr/bin/touch /etc/basecust
			mount /tmp/\${NIM_NAME}/etc/basecust /etc/basecust
		fi
	fi \n\n~;

            my $patch =
              qq~\n\t# xCAT support #3\n\tif [ -z "\$(odmget -qattribute=syscons CuAt)" ] \n\tthen\n\t  \${SHOWLED} 0x911\n\t  cp /usr/ODMscript /tmp/ODMscript\n\tchmod 600 /tmp/ODMscript\n\t  [ \$? -eq 0 ] && odmadd /tmp/ODMscript\n\tfi \n\n~;

			my $scripthook = qq~
		# xCAT support #4
		# do statelite setup if needed
		cp /../SPOT/niminfo /etc/niminfo
		if [ -f "/aixlitesetup" ]
		then
			/aixlitesetup
		fi
	\n\n~;

        	my $basecustrm = qq~
        # xCAT basecust removal support #5
        # Check if BASECUST_REMOVAL is specified, 
        # if yes, then remove the specified device
        # This change will finally go into AIX NIM support
        [ -n "\${BASECUST_REMOVAL}" ] && {
            cp /SPOT/usr/sbin/rmdev /usr/sbin
            rmdev -l \${BASECUST_REMOVAL} -d
            rm -f /usr/sbin/rmdev
        }    
    \n\n~;

            if (open(DDBOOT, "<$dd_boot_file_mn"))
            {
                @lines = <DDBOOT>;
                close(DDBOOT);
            }
            else
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not open $dd_boot_file for reading.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

            # remove the file
            my $cmd    = qq~rm $dd_boot_file~;
            my $output =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cmd,
                                    0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not remove original $dd_boot_file.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

            # Create a new one
            my $dontupdt1 = 0;
            my $dontupdt2 = 0;
            my $dontupdt3 = 0;
            if (open(DDBOOT, ">$dd_boot_file_mn"))
            {
                foreach my $l (@lines)
                {
                    if ($l =~ /xCAT basecust support/)
                    {
                        $dontupdt1 = 1;
                    }
                    if ($l =~ /xCAT support/)
                    {
                        $dontupdt2 = 1;
                    }
                    if ($l =~ /xCAT basecust removal support/)
                    {
                        $dontupdt3 = 1;
                    }
					if (($l =~ /network boot phase 1/) && (!$dontupdt1)) {
						# add /etc/basecust to restore
						print DDBOOT $odmrestore;
					}
					if (($l =~ /configure paging - local or NFS network/) && (!$dontupdt1)) {
						# make basecust persistent
						print DDBOOT $mntbase;
					}
                    if (($l =~ /0x620/) && (!$dontupdt2))
                    {
                        # add the patch to set the console 
                        print DDBOOT $patch;
                    }
					if (($l =~ /Copy the local_domain file to/) && (!$dontupdt2)) {
						# add the aixlitesetup hook for xCAT statelite support
						print DDBOOT $scripthook;
					}
					if (($l =~ /Start NFS remote paging/) && (!$dontupdt3))
					{
					    # add basecuse removal for swapdev
					    print DDBOOT $basecustrm;
					}
                    print DDBOOT $l;
                }
                close(DDBOOT);
            }
            else
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not open $dd_boot_file for writing.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
            if (!xCAT::InstUtils->is_me($nimprime))
            {
                $cmd = "$::XCATROOT/bin/xdcp $nimprime $dd_boot_file_mn $dd_boot_file";
            }
            else
            {
                $cmd = "cp $dd_boot_file_mn $dd_boot_file";
            }

            $output = xCAT::Utils->runcmd("$cmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not copy the $dd_boot_file back";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

            if ($::VERBOSE)
            {
                my $rsp;
                push @{$rsp->{data}}, "Updated $dd_boot_file.\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }
        }
    #}
    else
    {    # dd_boot file doesn't exist
        return 1;
    }

    return 0;
}

#----------------------------------------------------------------------------

=head3   prenimnodecust

        Preprocessing for the nimnodecust command.

        Runs on the xCAT management node only!

        Arguments:
        Returns:
                0 - OK - need to forward request
                1 - error - done
				2 - help or version - done
        Globals:
        Example:
        Comments:
            - If needed, copy files to the service nodes

=cut

#-----------------------------------------------------------------------------
sub prenimnodecust
{
    my $callback = shift;
    my $nodes    = shift;
    my $subreq   = shift;

    my @nodelist;

    if ($nodes)
    {
        @nodelist = @$nodes;
    }

    if (defined(@{$::args}))
    {
        @ARGV = @{$::args};
    }
    else
    {
        &nimnodecust_usage($callback);
        return 1;
    }

    # parse the options
    if (
        !GetOptions(
                    'h|help'    => \$::HELP,
                    'b=s'       => \$::BUNDLES,
                    's=s'       => \$::LPPSOURCE,
                    'p=s'       => \$::PACKAGELIST,
                    'verbose|V' => \$::VERBOSE,
                    'v|version' => \$::VERSION,
        )
      )
    {
        return 1;
    }

    if ($::HELP)
    {
        &nimnodecust_usage($callback);
        return 2;
    }

    # display the version statement if -v or --verison is specified
    if ($::VERSION)
    {
        my $version = xCAT::Utils->Version();
        my $rsp;
        push @{$rsp->{data}}, "nimnodecust $version\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return 2;
    }

    # make sure the nodes are resolvable
    #  - if not then exit
    foreach my $n (@nodelist)
    {
        #my $packed_ip = gethostbyname($n);
        my $packed_ip = xCAT::NetworkUtils->getipaddr($n);
        if (!$packed_ip)
        {
            my $rsp;
            $rsp->{data}->[0] = "Could not resolve node $n.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
    }

    # get the NIM primary server name
    my $nimprime = xCAT::InstUtils->getnimprime();
    chomp $nimprime;

    # get a list of packages that will be installed
    my @pkglist;
    my %bndloc;
    if ($::PACKAGELIST)
    {
        @pkglist = split(/,/, $::PACKAGELIST);
    }
    elsif ($::BUNDLES)
    {
        my @bndlist = split(/,/, $::BUNDLES);
        foreach my $bnd (@bndlist)
        {
            my ($rc, $list, $loc) =
              xCAT::InstUtils->readBNDfile($callback, $bnd, $nimprime, $subreq);
            push(@pkglist, @$list);
            $bndloc{$bnd} = $loc;
        }
    }

    # get the location of the lpp_source
    my $lpp_source_loc =
      xCAT::InstUtils->get_nim_attr_val(
                                        $::LPPSOURCE, 'location',
                                        $callback,    $nimprime,
                                        $subreq
                                        );
    my $rpm_srcdir   = "$lpp_source_loc/RPMS/ppc";
    my $instp_srcdir = "$lpp_source_loc/installp/ppc";

    #
    #  Get the service nodes for this list of nodes
    #
    my $sn = xCAT::Utils->getSNformattedhash(\@nodelist, "xcat", "MN");
    if ($::ERROR_RC)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get list of xCAT service nodes.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    # copy the packages to the service nodes - if needed
    foreach my $snkey (keys %$sn)
    {

        # if it's not me then we need to copy the pkgs there
        if (!xCAT::InstUtils->is_me($snkey))
        {

            my $cmdstr;
            if (!xCAT::InstUtils->is_me($nimprime))
            {
                $cmdstr = "$::XCATROOT/bin/xdsh $nimprime ";
            }
            else
            {
                $cmdstr = "";
            }
            foreach my $pkg (@pkglist)
            {
                my $rcpcmd;

                # note the xCAT rpm entries end in "*" - ex. "R:perl-xCAT-2.1*"
                if (($pkg =~ /rpm\s*$/) || ($pkg =~ /xCAT/) || ($pkg =~ /R:/))
                {

                    $rcpcmd =
                      "$cmdstr '$::XCATROOT/bin/xdcp $snkey $rpm_srcdir/$pkg $rpm_srcdir'";

                    my $output = xCAT::Utils->runcmd("$rcpcmd", -1);
                    if ($::RUNCMD_RC != 0)
                    {
                        my $rsp;
                        push @{$rsp->{data}},
                          "Could not copy $pkg to $snkey.\n";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                    }

                }
                else
                {
                    $rcpcmd .=
                      "$cmdstr '$::XCATROOT/bin/xdcp $snkey $instp_srcdir/$pkg $instp_srcdir'";

                    my $output = xCAT::Utils->runcmd("$rcpcmd", -1);
                    if ($::RUNCMD_RC != 0)
                    {
                        my $rsp;
                        push @{$rsp->{data}},
                          "Could not copy $pkg to $snkey.\n";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                    }

                }
            }
        }
    }

    # the NIM primary master may not be the management node
    my $cmdstr;
    if (!xCAT::InstUtils->is_me($nimprime))
    {
        $cmdstr = "$::XCATROOT/bin/xdsh $nimprime ";
    }
    else
    {
        $cmdstr = "";
    }

    #
    # if bundles provided then copy bnd files to SNs
    #
    if ($::BUNDLES)
    {
        foreach my $snkey (keys %$sn)
        {

            if (!xCAT::InstUtils->is_me($snkey))
            {
                my @bndlist = split(/,/, $::BUNDLES);
                foreach my $bnd (@bndlist)
                {
                    my $bnd_file_loc = $bndloc{$bnd};
                    my $bnddir       = dirname($bnd_file_loc);
                    my $cmd = "$cmdstr '$::XCATROOT/bin/xdcp $snkey $bnd_file_loc $bnddir'";
                    my $output = xCAT::Utils->runcmd("$cmd", -1);
                    if ($::RUNCMD_RC != 0)
                    {
                        my $rsp;
                        push @{$rsp->{data}},
                          "Could not copy $bnd_file_loc to $snkey.\n";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                    }
                }
            }
        }
    }

    return (0, \%bndloc);
}

#----------------------------------------------------------------------------

=head3   nimnodecust

        Processing for the nimnodecust command.

		Does AIX node customization.

        Arguments:
        Returns:
                0 - OK 
                1 - error 
        Globals:
        Example:
        Comments:

=cut

#-----------------------------------------------------------------------------
sub nimnodecust
{
    my $callback = shift;
    my $locs     = shift;
    my $nodes    = shift;

    my %bndloc;
    if ($locs)
    {
        %bndloc = %{$locs};
    }

    my @nodelist;
    if ($nodes)
    {
        @nodelist = @$nodes;
    }

    if (defined(@{$::args}))
    {
        @ARGV = @{$::args};
    }
    else
    {
        &nimnodecust_usage($callback);
        return 1;
    }

    # parse the options
    if (
        !GetOptions(
                    'h|help'    => \$::HELP,
                    'b=s'       => \$::BUNDLES,
                    's=s'       => \$::LPPSOURCE,
                    'p=s'       => \$::PACKAGELIST,
                    'verbose|V' => \$::VERBOSE,
                    'v|version' => \$::VERSION,
        )
      )
    {
        return 1;
    }

    my $Sname = xCAT::InstUtils->myxCATname();
    chomp $Sname;

    # get list of NIM machines defined locally

    my @machines = ();
    my $cmd      =
      qq~/usr/sbin/lsnim -c machines | /usr/bin/cut -f1 -d' ' 2>/dev/null~;

    @machines = xCAT::Utils->runcmd("$cmd", -1);

    # see if lpp_source is defined locally
    $cmd =
      qq~/usr/sbin/lsnim -c resources | /usr/bin/cut -f1 -d' ' 2>/dev/null~;

    my @nimresources = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "$Sname: Could not get NIM resource definitions.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }
    if (!grep(/^$::LPPSOURCE$/, @nimresources))
    {
        return 1;
    }

    # put together a cust cmd line for NIM
    my @pkglist;
    my $custcmd =
      "nim -o cust -a lpp_source=$::LPPSOURCE -a installp_flags=agQXY ";
    if ($::PACKAGELIST)
    {
        @pkglist = split(/,/, $::PACKAGELIST);
        $custcmd .= "-a filesets=\"";
        foreach my $p (@pkglist)
        {
            $custcmd .= " $p";
        }
        $custcmd .= "\"";

    }

    if ($::BUNDLES)
    {

        my @bndlist = split(/,/, $::BUNDLES);
        foreach my $bnd (@bndlist)
        {

            # check if bundles defined locally
            if (!grep(/^$bnd$/, @nimresources))
            {

                # try to define it
                my $bcmd =
                  "/usr/sbin/nim -Fo define -t installp_bundle -a server=master -a location=$bndloc{$bnd} $bnd";
                if ($::NFSV4)
                {
                    $bcmd .= "-a nfs_vers=4 ";
                }

                my $output = xCAT::Utils->runcmd("$bcmd", -1);
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "$Sname: Could not create bundle resource $bnd.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return 1;
                }
            }

            # need a separate -a for each one !

            $custcmd .= " -a installp_bundle=$bnd ";
        }
    }

    # for each node run NIM -o cust operation
    foreach my $n (@nodelist)
    {

        # TODO - check if machine is defined???

        # run the cust cmd - one for each node???
        my $cmd .= "$custcmd  $n";

        my $output = xCAT::Utils->runcmd("$cmd", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "$Sname: Could not customize node $n.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
    }

    return 0;
}

#----------------------------------------------------------------------------

=head3   prenimnodeset

        Preprocessing for the nimnodeset & mkdsklsnode command.

		Runs on the xCAT management node only!

        Arguments:
        Returns:
                 - OK
                 - error
        Globals:
        Example:
        Comments:
			- Gather info from the management node and/or the NIM 
			 	primary server and pass it along to the requests that
			 	go to the service nodes.
			- If needed, copy NIM files to the service nodes

=cut

#-----------------------------------------------------------------------------
sub prenimnodeset
{
    my $callback = shift;
    my $command  = shift;
    my $subreq   = shift;
    my $error    = 0;

    if (defined(@{$::args}))
    {
        @ARGV = @{$::args};
    }
    else
    {
        if ($command eq 'mkdsklsnode')
        {
            &mkdsklsnode_usage($callback);
        }
        else
        {
            &nimnodeset_usage($callback);
        }
        return (2);
    }

    # parse the options
    Getopt::Long::Configure("no_pass_through");
    if (
        !GetOptions(
					'b|backupSN'  => \$::BACKUP,
                    'f|force'   => \$::FORCE,
                    'h|help'    => \$::HELP,
                    'i=s'       => \$::OSIMAGE,
					'l=s'       => \$::opt_l,
                    'n|new'     => \$::NEWNAME,
					'p|primarySN' => \$::PRIMARY,
                    'verbose|V' => \$::VERBOSE,
                    'v|version' => \$::VERSION,
                    'nfsv4'     => \$::NFSV4,
        )
      )
    {
        if ($command eq 'mkdsklsnode')
        {
            &mkdsklsnode_usage($callback);
        }
        else
        {
            &nimnodeset_usage($callback);
        }
        return 1;
    }

    if ($::HELP)
    {
        if ($command eq 'mkdsklsnode')
        {
            &mkdsklsnode_usage($callback);
        }
        else
        {
            &nimnodeset_usage($callback);
        }
        return (2);
    }

    # display the version statement if -v or --verison is specified
    if ($::VERSION)
    {
        my $version = xCAT::Utils->Version();
        my $rsp;
        if ($command eq 'mkdsklsnode')
        {
            push @{$rsp->{data}}, "mkdsklsnode $version\n";
        }
        else
        {
            push @{$rsp->{data}}, "nimnodeset $version\n";
        }
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return (2);
    }

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

    # if an osimage is included make sure it is defined
    if ($::OSIMAGE)
    {
        my @oslist = xCAT::DBobjUtils->getObjectsOfType('osimage');
        if (!grep(/^$::OSIMAGE$/, @oslist))
        {
            my $rsp;
            $rsp->{data}->[0] =
              "The xCAT osimage named \'$::OSIMAGE\' is not defined.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
    }

    my @nodelist;
    my %objtype;
    my %objhash;
    my %attrs;
	my %nimhash;

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

    my $Sname = xCAT::InstUtils->myxCATname();
    chomp $Sname;

    # make sure the nodes are resolvable
    #  - if not then exit
    foreach my $n (@nodelist)
    {
        my $packed_ip = xCAT::NetworkUtils->getipaddr($n);
        if (!$packed_ip)
        {
            my $rsp;
            $rsp->{data}->[0] = "$Sname: Could not resolve node $n.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
    }

    #
    # get all the attrs for these node definitions
    #
    foreach my $o (@nodelist)
    {
        $objtype{$o} = 'node';
    }
    %objhash = xCAT::DBobjUtils->getobjdefs(\%objtype, $callback);
    if (!(%objhash))
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get xCAT object definitions.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return (1);
    }

    #
    # Get the network info for each node
    #
    my %nethash = xCAT::DBobjUtils->getNetwkInfo(\@nodelist, $callback);
    if (!(%nethash))
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get xCAT network definitions for one or
 more nodes.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return (1);
    }

    #
    # get a list of os images
    #
    my @image_names;    # list of osimages needed
    my %nodeosi;        # hash of osimage for each node
    foreach my $node (@nodelist)
    {
        if ($::OSIMAGE)
        {

            # from the command line
            $nodeosi{$node} = $::OSIMAGE;

        }
        else
        {
            if ($objhash{$node}{provmethod})
            {
                $nodeosi{$node} = $objhash{$node}{provmethod};
            }
            elsif ($objhash{$node}{profile})
            {
                $nodeosi{$node} = $objhash{$node}{profile};
            }
            else
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not determine an OS image name for node \'$node\'.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                next;
            }
        }
        if (!grep (/^$nodeosi{$node}$/, @image_names))
        {
            push(@image_names, $nodeosi{$node});
        }
    }

    #
    # get the primary NIM master - default to management node
    #
    my $nimprime = xCAT::InstUtils->getnimprime();
    chomp $nimprime;

    #
    #  Get a list of all nim resource types
    #
    my $cmd =
      qq~/usr/sbin/lsnim -P -c resources | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    my @nimrestypes =
      xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cmd, 1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get NIM resource definitions.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return (1);
    }

    #
    # get the image defs from the DB
    #
    my %lochash;
    my %imghash;
    foreach my $m (@image_names)
    {
        $objtype{$m} = 'osimage';
    }
    %imghash = xCAT::DBobjUtils->getobjdefs(\%objtype, $callback);
    if (!(%imghash))
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get xCAT osimage definitions.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return (1);
    }

    #
    # modify the image hash with whatever was passed in with attr=val
    #	- also add xcataixpost if appropriate
    #
    my $add_xcataixpost = 0;
    if (%attrs)
    {
        foreach my $i (@image_names)
        {
            foreach my $restype (keys %{$imghash{$i}})
            {
                if ($attrs{$restype})
                {
                    $imghash{$i}{$restype} = $attrs{$restype};
                }
            }
        }
    }

    # add the "xcataixscript" script to each image def for standalone systems
    foreach my $i (@image_names)
    {
        if ($imghash{$i}{nimtype} =~ /standalone/)
        {

            # add it to the list of scripts for this image
            if (defined($imghash{$i}{'script'}))
            {
                $imghash{$i}{'script'} .= ",xcataixscript";
            }
            else
            {
                $imghash{$i}{'script'} .= "xcataixscript";
            }

            # also make sure to create the resource
            $add_xcataixpost++;
        }
    }

    #
    # create a NIM script resource using xcataixscript
    #

    if ($add_xcataixpost)
    {    # if we have at least one standalone node

        my $createscript = 0;
        my $install_dir = xCAT::Utils->getInstallDir();

        # see if it already exists

        my $scmd = qq~/usr/sbin/lsnim -l 'xcataixscript' 2>/dev/null~;
        my $out  =
          xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $scmd,
                                0);
        if ($::RUNCMD_RC != 0)
        {

            # doesn't exist so create it
            $createscript = 1;
        }
        else
        {

            # it exists so see if it's in the correct location
            my $loc =
              xCAT::InstUtils->get_nim_attr_val('xcataixscript', 'location',

                                                $callback, $nimprime, $subreq);

            # see if it's in the wrong place
            # TODO - how handle migration????
            if ($loc ne "$install_dir/nim/scripts/xcataixscript")
            {

                # need to remove this def and create a new one
                $createscript = 1;

                my $rcmd =
                  qq~/usr/sbin/nim -Fo remove 'xcataixscript' 2>/dev/null~;
                my $out =
                  xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime,
                                        $rcmd, 0);
                if ($::RUNCMD_RC != 0)
                {

                    # error - could not remove NIM xcataixscript script resource.
                }
            }

        }

        # create a new one if we need to
        if ($createscript)
        {

            # copy file to /install/nim/scripts
            my $ccmd =
              qq~mkdir -m 644 -p $install_dir/nim/scripts; cp $install_dir/postscripts/xcataixscript $install_dir/nim/scripts 2>/dev/null; chmod +x $install_dir/nim/scripts/xcataixscript~;
            my $out =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime,
                                    $ccmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not copy xcataixscript.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

            # define the xcataixscript resource
            my $dcmd;
            if ($::NFSV4)
            {
              $dcmd = qq~/usr/sbin/nim -o define -t script -a server=master -a nfs_vers=4 -a location=$install_dir/nim/scripts/xcataixscript xcataixscript 2>/dev/null~;
            }
            else
            {
              $dcmd = qq~/usr/sbin/nim -o define -t script -a server=master -a location=$install_dir/nim/scripts/xcataixscript xcataixscript 2>/dev/null~;
            }
            $out =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime,
                                    $dcmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not create a NIM resource for xcataixscript.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return (1);
            }
        }

        # make sure we clean up the /etc/exports file of old post script
        my $ecmd =
          qq~/usr/sbin/rmnfsexp -d $install_dir/postscripts/xcataixpost -B 2>/dev/null~;
        $out =
          xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $ecmd,
                                0);

        #	$lochash{'xcataixpost'} = "/install/nim/scripts/xcataixpost";
    }

    #
    # create a hash containing the locations of the NIM resources
    #	that are used for each osimage
    # - the NIM resource names are unique!
    #
    foreach my $i (@image_names)
    {
        foreach my $restype (keys %{$imghash{$i}})
        {
            my @reslist;
            if (grep (/^$restype$/, @nimrestypes))
            {

                # spot, mksysb etc.
                my $resname = $imghash{$i}{$restype};

                # if comma list - split and put in list
                if ($resname)
                {
                    foreach (split /,/, $resname)
                    {
                        chomp $_;
                        push(@reslist, $_);
                    }
                }
            }

            foreach my $res (@reslist)
            {

                # go to primary NIM master to get resource defs and
                #	pick out locations
                # TODO - handle NIM prime!!
                my $loc =
                  xCAT::InstUtils->get_nim_attr_val($res, "location", $callback,
                                                    $nimprime, $subreq);

                # add to hash
                $lochash{$res} = "$loc";

				# new subr
				 my $attrvals = xCAT::InstUtils->get_nim_attrs($res, $callback, $nimprime, $subreq);
				 if (defined($attrvals)) {
					%{$nimhash{$res}} = %{$attrvals};
				}
            }
        }
    }

    # make sure any diskless images are updated
    foreach my $i (@image_names)
    {
        if (!($imghash{$i}{nimtype} =~ /standalone/))
        {

            # must be diskless or dataless so update spot
			my $rsp;
			push @{$rsp->{data}}, "Updating the spot named \'$i\'.\n";
			xCAT::MsgUtils->message("I", $rsp, $callback);

			my $rc = &updatespot($i, \%imghash, \@nodelist, $callback, $subreq);
            if ($rc != 0)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not update the SPOT resource named \'$imghash{$i}{'spot'}\'.\n";
				push @{$rsp->{data}}, "Could not initialize the nodes.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return (1);
            }
        }
    }

    # Checks the various credential files on the Management Node to
    #   make sure the permission are correct for using and transferring
    #   to the nodes and service nodes.
    #   Also removes /install/postscripts/etc/xcat/cfgloc if found
    my $result = xCAT::Utils->checkCredFiles($callback);

    #####################################################
    #
    #	Copy files/dirs to remote service nodes so they can be
    #		defined locally when this cmd runs there
    #
    ######################################################


	my $snhash;
	$snhash = &doSNcopy($callback, \@nodelist, $nimprime, \@nimrestypes, \%imghash, \%lochash,  \%nodeosi, $subreq, $type);
    if ( !defined($snhash) ) {
        my $rsp;
        push @{$rsp->{data}},
          "Could not copy NIM resources to the xCAT service nodes.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return (1);
    }

    # pass this along to the process_request routine
    return (0, \%objhash, \%nethash, \%imghash, \%lochash, \%attrs, \%nimhash, \@nodelist, $type);
}

#----------------------------------------------------------------------------

=head3   bkupNIMresources

        Backup NIM spot or lpp_source resource

        Arguments:
        Returns:
                file name  - OK
                undef - error
        Globals:
        Example:
        Comments:

	my $bkfile = &bkupNIMresources($callback, $bkdir, $resname);
=cut

#-----------------------------------------------------------------------------
sub bkupNIMresources
{
    my $callback = shift;
    my $bkdir    = shift;
    my $resname  = shift;

    # create file name
    my $dir    = dirname($bkdir);
    my $bkfile = $dir . "/" . $resname . ".bk";

    # remove the old file
    if (-e $bkfile)
    {
        my $cmd = "rm $bkfile";
        my $output = xCAT::Utils->runcmd("$cmd", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not remove $bkfile.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
        }
    }

    # verify FS size before creating new backup
    # get bkdir size
    my $ducmd = qq~/usr/bin/du -sm $bkdir | /usr/bin/awk '{print \$1}'~;
    my $bksize = xCAT::Utils->runcmd("$ducmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not run: \'$ducmd\'\n";
        if ($::VERBOSE)
        {
            push @{$rsp->{data}}, "$bksize";
        }
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    # check FS space, add it if needed
    if (&chkFSspace($bkdir, $bksize, $callback) != 0)
    {
        return undef;
    }

    # create a new backup file
    my $bkcmd = "find $bkdir -print |backup -ivqf $bkfile";

    if ($::VERBOSE)
    {
        my $rsp;
        push @{$rsp->{data}}, "Backing up $bkdir. Running command- \'$bkcmd\'";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }

    my $output = xCAT::Utils->runcmd("$bkcmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not create $bkfile.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return undef;
    }

    return $bkfile;
}

#----------------------------------------------------------------------------

=head3   tarNIMresources

        Tar and gzip NIM spot & lpp_source resources

        Arguments:
        Returns:
                file name  - OK
                undef - error
        Globals:
        Example:
        Comments:

	my $gzfile = &tarNIMresources($callback, $tardir, $resname);
=cut

#-----------------------------------------------------------------------------
sub tarNIMresources
{
    my $callback = shift;
    my $tardir   = shift;
    my $resname  = shift;

    # create tar file names
    my $tarfile = $tardir . "/" . $resname . ".tar";
    my $gzfile  = $tarfile . ".gz";

    # remove the old file
    if (-e $gzfile)
    {
        my $cmd = "rm $gzfile";
        my $output = xCAT::Utils->runcmd("$cmd", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not remove $gzfile.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
        }
    }

    # create a new tar file
    my $tarcmd = "tar -cvpf $tarfile $tardir 2>/dev/null; gzip $tarfile";

    my $output = xCAT::Utils->runcmd("$tarcmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not archive $tarfile.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return undef;
    }

    return $gzfile;
}

#----------------------------------------------------------------------------

=head3   copyres

        Copy NIM resource files/dirs to remote service nodes 

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:
        Example:
        Comments:

=cut

#-----------------------------------------------------------------------------
sub copyres
{
    my $callback = shift;
    my $dest     = shift;
    my $restype  = shift;
    my $resloc   = shift;
    my $resname  = shift;
    my $nimprime = shift;

    # get the directory location of the resource
    #  - could be the NIM location or may have to strip off a file name
    my $dir;
    if ($restype eq "lpp_source")
    {
        $dir = $resloc;
    }
    else
    {
        $dir = dirname($resloc);
    }
    chomp $dir;

    # make sure the directory loc is created on the SN
    my $cmd = "$::XCATROOT/bin/xdsh $dest '/usr/bin/mkdir -m 644 -p $dir'";

    my $output = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not create $dir on $dest.\n";
        if ($::VERBOSE)
        {
            push @{$rsp->{data}}, "$output\n";
        }
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return undef;
    }

    # how much free space is available on the SN ($dest)?
    my $dfcmd = qq~$::XCATROOT/bin/xdsh $dest /usr/bin/df -m $dir |/usr/bin/awk '(NR==2)'~;

    $output = xCAT::Utils->runcmd("$dfcmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not run: \'$dfcmd\'\n";
        if ($::VERBOSE)
        {
            push @{$rsp->{data}}, "$output";
        }
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }
    my @fslist = split(/\s+/, $output);

    my $free_space = $fslist[3];
    my $FSname     = $fslist[7];

    # How much space is the resource using?
    my $ducmd = qq~/usr/bin/du -sm $dir | /usr/bin/awk '{print \$1}'~;

    my $reqsize = xCAT::Utils->runcmd("$ducmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not run: \'$ducmd\'\n";
        if ($::VERBOSE)
        {
            push @{$rsp->{data}}, "$reqsize";
        }
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    # how much space do we need
    my $needspace;
    if (($restype eq 'lpp_source') || ($restype eq 'spot'))
    {

        # need size of resource plus size of tar file plus fudge factor
        $needspace = int($reqsize + $reqsize + 100);
    }
    else
    {
        $needspace = int($reqsize + 10);
    }

    # increase FS if needed
    my $addsize = 0;
    if ($needspace > $free_space)
    {

        # how much should we increase FS?
        $addsize = int($needspace - $free_space);
        my $sizeattr = "-a size=+$addsize" . "M";
        my $chcmd    = "$::XCATROOT/bin/xdsh $dest /usr/sbin/chfs $sizeattr $FSname";

        my $output;
        $output = xCAT::Utils->runcmd("$chcmd", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not run: \'$chcmd\'\n";
            if ($::VERBOSE)
            {
                push @{$rsp->{data}}, "$output";
            }
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
    }

    #	if ($::VERBOSE) {
    #        my $rsp;
    #        push @{$rsp->{data}}, "Space available on $dest=$free_space, space needed=$needspace, amount of space that will be added is \'$addsize\'\n";
    #        xCAT::MsgUtils->message("I", $rsp, $callback);
    #    }


    # do copy from NIM primary
    my $cpcmd;
    if (!xCAT::InstUtils->is_me($nimprime))
    {

        # if NIM primary is another system
        $cpcmd = "$::XCATROOT/bin/xdsh $nimprime ";
    }
    else
    {
        $cpcmd = "";
    }

    # if res is spot or lpp_source then
    #   backup dir it first!
    my $bkdir;    # directory to backup
    if ($restype eq "lpp_source")
    {
        $bkdir = $resloc;

        # Ex. /install/nim/lpp_source/61D_lpp_source
        my $dir = dirname($bkdir);

        # ex. /install/nim/lpp_source
        my $bkfile = $dir . "/" . $resname . ".bk";

        if (!grep(/^$resname$/, @::resbacked))
        {
            $bkfile = &bkupNIMresources($callback, $bkdir, $resname);
            if (!defined($bkfile))
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not archive $bkdir.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
            push @::resbacked, $resname;
            push @::removebk,  $bkfile;
        }

        # copy the file to the SN
        $cpcmd .= "$::XCATROOT/bin/xdcp $dest $bkfile $dir 2>/dev/null";
    }
    elsif ($restype eq 'spot')
    {
        $bkdir = dirname($resloc);

        # ex. /install/nim/spot/61dimg

        my $dir = dirname($bkdir);

        # ex. /install/nim/spot

        my $bkfile = $dir . "/" . $resname . ".bk";
        if (!grep(/^$resname$/, @::resbacked))
        {
            $bkfile = &bkupNIMresources($callback, $bkdir, $resname);
            if (!defined($bkfile))
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not archive $bkdir.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
            push @::resbacked, $resname;
            push @::removebk,  $bkfile;
        }

        # copy the file to the SN
        $cpcmd .= "$::XCATROOT/bin/xdcp $dest $bkfile $dir 2>/dev/null";

    }
    else
    {

        # copy the resource file to the SN dir
        # covers- bosinst_data, script, resolv_conf, installp_bundle, mksysb
        # - the NIM location includes the actual file name
        my $dir = dirname($resloc);
        $cpcmd .= "$::XCATROOT/bin/xdcp $dest $resloc $dir 2>/dev/null";
    }

    $output = xCAT::Utils->runcmd("$cpcmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}},
          "Could not copy NIM resource $resname to $dest.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    if ($::VERBOSE)
    {
        my $rsp;
        push @{$rsp->{data}},
          "Copying NIM resource to service node. Running command \'$cpcmd\'.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }

    return 0;
}

#----------------------------------------------------------------------------

=head3   doSNcopy

        Copy NIM resource files/dirs to remote service nodes so they can be
           defined locally

		Also copy /etc/hosts to make sure we have name res for nodes
            from SN

        Arguments:
        Returns:
                snhash
                undef - error
        Globals:
        Example:
        Comments:

=cut

#-----------------------------------------------------------------------------
sub doSNcopy
{
    my $callback = shift;
    my $nodes    = shift;
    my $nimprime = shift;
    my $restypes = shift;
    my $imaghash = shift;
    my $locs     = shift;
    my $nosi     = shift;
    my $subreq   = shift;
	my $type     = shift;

    my %lochash     = %{$locs};
    my %imghash     = %{$imaghash};
    my @nodelist    = @$nodes;
    my @nimrestypes = @$restypes;
    my %nodeosi     = %{$nosi};
    my $install_dir = xCAT::Utils->getInstallDir();

    #
    #  Get a list of nodes for each service node
    #
    my $sn = xCAT::Utils->getSNformattedhash(\@nodelist, "xcat", "MN", $type);
    if ($::ERROR_RC)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get list of xCAT service nodes.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return undef;
    }

    #
    # Get a list of images for each SN
    #
    my %SNosi;
    foreach my $snkey (keys %$sn)
    {
        my @nodes = @{$sn->{$snkey}};
        foreach my $n (@nodes)
        {
            if (!grep (/^$nodeosi{$n}$/, @{$SNosi{$snkey}}))
            {
                push(@{$SNosi{$snkey}}, $nodeosi{$n});
            }
        }
    }

    #
    #  For each SN
    #	- copy whatever is needed to the SNs
    #

    foreach my $snkey (keys %$sn)
    {
        my @nimresources;
        if (!xCAT::InstUtils->is_me($snkey))
        {

            # running on the management node so
            # copy the /etc/hosts file to the SN
            my $rcpcmd = "$::XCATROOT/bin/xdcp $snkey /etc/hosts /etc ";
            my $output = xCAT::Utils->runcmd("$rcpcmd", -1);

            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not copy /etc/hosts to $snkey.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
            }

            # update the postscripts on the SN
            my $lscmd = "$::XCATROOT/bin/xdsh $snkey 'ls $install_dir/postscripts' >/dev/null 2>&1";
            $output = xCAT::Utils->runcmd("$lscmd", -1);
            if ($::RUNCMD_RC == 0)
            {

                # if the dir exists then we can update it
                my $cpcmd =
                  "$::XCATROOT/bin/xdcp $snkey -p -R $install_dir/postscripts/* $install_dir/postscripts ";
                $output = xCAT::Utils->runcmd("$cpcmd", -1);
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "Could not copy $install_dir/postscripts to $snkey.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                }
            }

            # copy NIM files/dir to the remote SN - so that
            #	the NIM res defs can be created when the rest of this cmd
            # 	runs on that SN

            # get a list of the resources that are defined on the SN
            my $cmd =
              qq~$::XCATROOT/bin/xdsh $snkey "/usr/sbin/lsnim -c resources | /usr/bin/cut -f1 -d' '"~;

            my @resources = xCAT::Utils->runcmd("$cmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not get NIM resource definitions.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return undef;
            }

            foreach my $r (@resources)
            {
                my ($node, $nimres) = split(': ', $r);
                chomp $nimres;
                push(@nimresources, $nimres);
            }

            # for each image
            foreach my $image (@{$SNosi{$snkey}})
            {

                # for each resource
                foreach my $restype (keys(%{$imghash{$image}}))
                {

                    my $nimtype = $imghash{$image}{'nimtype'};
                    if (   ($nimtype ne 'standalone')
                        && ($restype eq 'lpp_source'))
                    {

                        # don't copy lpp_source for diskless/dataless nodes
                        next;
                    }

                    # if a valid NIM type and a value is set
                    if (   ($imghash{$image}{$restype})
                        && (grep(/^$restype$/, @nimrestypes)))
                    {

                        # could have a comma separated list - ex. script etc.
                        foreach my $res (split /,/, $imghash{$image}{$restype})
                        {
                            chomp $res;

                            # if the resources are not defined on the SN
                            if (!grep(/^$res$/, @nimresources))
                            {

                                # copy appropriate files to the SN
                                # use same location on all NIM servers
                                # cp dirs/files to corresponding dirs on
                                #   each SN - always in /install!!!
                                # only care about these resource types for now

                                my @dorestypes = (
                                              "mksysb",       "resolv_conf",
                                              "script",       "installp_bundle",
                                              "bosinst_data", "lpp_source",
                                              "spot"
                                              );
                                if (grep(/^$restype$/, @dorestypes))
                                {
                                    my $resloc = $lochash{$res};

                                    #   if ($::VERBOSE) {
                                    if (0)
                                    {
                                        my $rsp;
                                        push @{$rsp->{data}},
                                          "Copying NIM resources to the xCAT $snkey service node. This could take a while.";
                                        xCAT::MsgUtils->message("I", $rsp,
                                                                $callback);

                                    }

                                    if (
                                        &copyres($callback, $snkey, $restype,
                                                 $resloc,   $res,   $nimprime)
                                      )
                                    {

                                        # error
                                    }
                                }

                            }    # end - if res not defined
                        }    # end foreach resource of this type
                    }    # end - if it's a valid res type
                }    # end - for each resource
            }    # end - for each image
        }    # end - if the SN is not me
    }    # end - for each SN

    # remove any lpp_source or spot backup files that were created
    foreach my $file (@::removebk)
    {
        my $rmcmd = "/usr/bin/rm -f $file";
        my $output = xCAT::Utils->runcmd("$rmcmd", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not remove backup file: $file\n";
            if ($::VERBOSE)
            {
                push @{$rsp->{data}}, "$output";
            }
            xCAT::MsgUtils->message("E", $rsp, $callback);
        }
    }

    return \%$sn;
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

		This runs on the service node in a hierarchical env

=cut

#-----------------------------------------------------------------------------
sub mkdsklsnode
{
    my $callback = shift;
    my $nodes    = shift;
    my $nodehash = shift;
    my $nethash  = shift;
    my $imaghash = shift;
    my $locs     = shift;
	my $nimres   = shift;
    my $subreq   = shift;

    my %lochash   = %{$locs};
    my %objhash   = %{$nodehash};
    my %nethash   = %{$nethash};
    my %imagehash = %{$imaghash};
    my @nodelist  = @$nodes;

	my %nimhash;
	if ($nimres) {
		%nimhash   = %{$nimres};
	}

    my $error = 0;
    my @nodesfailed;
    my $image_name;

    # get name as known by xCAT
    my $Sname = xCAT::InstUtils->myxCATname();
    chomp $Sname;

    # make sure the nodes are resolvable
    #  - if not then exit
    foreach my $n (@nodelist)
    {
        #my $packed_ip = gethostbyname($n);
        my $packed_ip = xCAT::NetworkUtils->getipaddr($n);
        if (!$packed_ip)
        {
            my $rsp;
            $rsp->{data}->[0] = "$Sname: Could not resolve node $n.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
    }

    # some subroutines require a global callback var
    #	- need to change to pass in the callback
    #	- just set global for now
    $::callback = $callback;

    if (defined(@{$::args}))
    {
        @ARGV = @{$::args};
    }
    else
    {
        &mkdsklsnode_usage($callback);
        return 0;
    }

    # parse the options
    if (
        !GetOptions(
					'b|backup'  => \$::BACKUP,
                    'f|force'   => \$::FORCE,
                    'h|help'    => \$::HELP,
                    'i=s'       => \$::OSIMAGE,
					'l=s'       => \$::opt_l,
                    'n|new'     => \$::NEWNAME,
					'p|primary' => \$::PRIMARY,
                    'verbose|V' => \$::VERBOSE,
                    'v|version' => \$::VERSION,
                    'nfsv4'     => \$::NFSV4,
        )
      )
    {
        return 1;
    }

    my %objtype;
    my %attrs;

    #  - put attr=val operands in %attrs hash
    while (my $a = shift(@ARGV))
    {
        if ($a =~ /=/)
        {

            # if it has an "=" sign its an attr=val - we hope
            my ($attr, $value) = $a =~ /^\s*(\S+?)\s*=\s*(\S*.*)$/;
            if (!defined($attr) || !defined($value))
            {
                my $rsp;
                $rsp->{data}->[0] =
                  "$Sname: Incorrect \'attr=val\' pair - $a\n";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                return 1;
            }

            # put attr=val in hash
            $attrs{$attr} = $value;
        }
    }

	my $rsp;
	$rsp->{data}->[0] = "$Sname: Initializing AIX diskless nodes.  This could take a while.\n";
	xCAT::MsgUtils->message("I", $rsp, $callback);

    #now run the begin part of the prescripts
    #the call is distrubuted to the service node already, so only need to handles my own children
    $errored=0;
    $subreq->({command=>['runbeginpre'],
		node=>\@nodelist,
		arg=>["diskless", '-l']},\&pass_along);
    if ($errored) { 
	my $rsp;
	$rsp->{errorcode}->[0]=1;
	$rsp->{error}->[0]="Failed in running begin prescripts.\n";
	$callback->($rsp);
	return 1; 
    }


    #
    #  Get a list of the defined NIM machines
    #    these are machines defined on this server
    #
    my @machines = ();
    my $cmd      =
      qq~/usr/sbin/lsnim -c machines | /usr/bin/cut -f1 -d' ' 2>/dev/null~;

    @machines = xCAT::Utils->runcmd("$cmd", -1);

    # don't fail - maybe just don't have any defined!

    #
    # get all the image names and create a hash of osimage
    #	names for each node
    #
    my @image_names;
    my %nodeosi;
    foreach my $node (@nodelist)
    {
        if ($::OSIMAGE)
        {

            # from the command line
            $nodeosi{$node} = $::OSIMAGE;
        }
        elsif ($objhash{$node}{provmethod})
        {
            $nodeosi{$node} = $objhash{$node}{provmethod};
        }
        elsif ($objhash{$node}{profile})
        {
            $nodeosi{$node} = $objhash{$node}{profile};
        }
        if (!grep (/^$nodeosi{$node}$/, @image_names))
        {
            push(@image_names, $nodeosi{$node});
        }
    }

    if (scalar(@image_names) == 0)
    {

        # if no images then error
        my $rsp;
        push @{$rsp->{data}},
          "$Sname: Could not determine which xCAT osimage to use.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    #
    # get the primary NIM master -
    #
    my $nimprime = xCAT::InstUtils->getnimprime();
    chomp $nimprime;

    #
    # if this isn't the NIM primary then make sure the local NIM defs
    #	have been created
    #
    if (!xCAT::InstUtils->is_me($nimprime))
    {
        &make_SN_resource($callback,   \@nodelist, \@image_names,
                          \%imagehash, \%lochash,  \%nethash, \%nimhash);
    }
    else
    {

        # if this is the NIM primary make sure we update any shared_root
        # resources that are being used
        foreach my $img (@image_names)
        {

            # if have shared_root
            if ($imagehash{$img}{shared_root})
            {

                # if it's allocated then don't update it
                my $alloc_count =
                  xCAT::InstUtils->get_nim_attr_val(
                                         $imagehash{$img}{shared_root},
                                         "alloc_count", $callback, "", $subreq);
                if (defined($alloc_count) && ($alloc_count != 0))
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "The resource named \'$imagehash{$img}{shared_root}\' is currently allocated. It will not be re-synchronized.\n";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                    next;
                }
                if (1)
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "$Sname: Synchronizing the NIM \'$imagehash{$img}{shared_root}\' resource.\n";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }
                my $scmd = "nim -F -o sync_roots $imagehash{$img}{spot}";
                my $output = xCAT::Utils->runcmd("$scmd", -1);
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "$Sname: Could not update $imagehash{$img}{shared_root}.\n";
                    if ($::VERBOSE)
                    {
                        push @{$rsp->{data}}, "$output";
                    }
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                }
            }
        }
    }    # end re-sync shared_root

	#
    #   check/do statelite setup
    #
	#  already did this on the primary
	if (!xCAT::InstUtils->is_me($nimprime)) {
    	my $statelite=0;
		foreach my $image (@image_names){
    		if ($imagehash{$image}{shared_root}) {

        		# if this has a shared_root resource then
        		#   it might need statelite setup
        		my $rc=xCAT::InstUtils->dolitesetup($image, \%imagehash, \@nodelist, $callback, $subreq);
        		if ($rc eq 1) { # error
            		my $rsp;
            		push @{$rsp->{data}}, qq{Could not complete the statelite setup.};
            		xCAT::MsgUtils->message("E", $rsp, $callback);
            		return 1;
        		}
			}
    	}
	}

	#
    # See if we need to create a resolv_conf resource
    #
	my $RChash;
	$RChash = &chk_resolv_conf($callback, \%objhash, \@nodelist, \%nethash, \%imagehash, \%attrs, \%nodeosi, $subreq); 
	if ( !defined($RChash) ){
        my $rsp;
        push @{$rsp->{data}}, "Could not check NIM resolv_conf resource.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
    }
	my %resolv_conf_hash = %{$RChash};

    #
    # define and initialize the diskless/dataless nodes
    #
    $error = 0;
    my $node_syncfile = xCAT::SvrUtils->getsynclistfile($nodes);
    foreach my $node (@nodelist)
    {
        my $image_name = $nodeosi{$node};
        chomp $image_name;

        # set the NIM machine type
        my $type = "diskless";
        if ($imagehash{$image_name}{nimtype})
        {
            $type = $imagehash{$image_name}{nimtype};
        }
        chomp $type;

        if (($type =~ /standalone/))
        {

            #error - only support diskless/dataless
            my $rsp;
            push @{$rsp->{data}},
              "$Sname: Use the nimnodeset command to initialize NIM standalone type nodes.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            $error++;
            push(@nodesfailed, $node);
            next;
        }

        # generate a NIM client name
        my $nim_name;
        if ($::NEWNAME)
        {

            # generate a new nim name
            # "<xcat_node_name>_<image_name>"
            my $name;
            ($name = $node) =~ s/\..*$//; # make sure we have the short hostname
            $nim_name = $name . "_" . $image_name;
        }
        else
        {

            # the nim name is the short hostname of our node
            ($nim_name = $node) =~ s/\..*$//;
        }
        chomp $nim_name;

        # need the short host name for NIM cmds
        my $nodeshorthost;
        ($nodeshorthost = $node) =~ s/\..*$//;
        chomp $nodeshorthost;

        my $todef = 0;
        my $toinit = 0;
        my $toremove = 0;

		#  NIM has a limit of 39 characters for a macine name
		my $len = length($nim_name);
		if ($len > 39) {
			my $rsp;
			push @{$rsp->{data}}, "$Sname: Could not define \'$nim_name\'. A NIM machine name can be no longer then 39 characters.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			push(@nodesfailed, $node);
			$error++;
			next;
		}

        # 	see if it's already defined first
        if (grep(/^$nim_name$/, @machines))
        {
            # Already defined
            if ($::FORCE)
            {
                # To determine if the defined node is standalone
                my $tstring;
                $cmd      =
                  qq~/usr/sbin/lsnim -l $nim_name | grep "type " 2>/dev/null~;

                $tstring = xCAT::Utils->runcmd("$cmd", -1);

                my ($junk, $mtype) = split(/=/, $tstring);
                chomp $mtype;

                if ($mtype =~ /standalone/)
                {
                    # Need to remove the machine and define it as diskless
                    $toremove = 1;
                    $todef = 1;
                }
                
                # Reinitialize

                # Deallocate the nim resources for the existing machine, but not remove machine definition
                if ($::VERBOSE)
                {
                    my $rsp;
                    push @{$rsp->{data}},
                    "$Sname: Deallocate NIM resources for $nim_name.\n";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }

                my $rmcmd =
                    "/usr/sbin/nim -o reset -a force=yes $nim_name;/usr/sbin/nim -Fo deallocate -a subclass=all $nim_name";
                my $output = xCAT::Utils->runcmd("$rmcmd", -1);
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp;
                    push @{$rsp->{data}},
                        "$Sname: Could not deallocate the existing NIM object named \'$nim_name\'.\n";
                    if ($::VERBOSE)
                    {
                        push @{$rsp->{data}}, "$output";
                    }
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    $error++;
                    push(@nodesfailed, $node);
                    next;
                }

                if ($toremove == 1)
                {
                    $cmd =
                        "/usr/sbin/nim -Fo remove $nim_name";
                    $output = xCAT::Utils->runcmd("$cmd", -1);
                    if ($::RUNCMD_RC != 0)
                    {
                        my $rsp;
                        push @{$rsp->{data}},
                            "$Sname: Could not remove the existing NIM object named \'$nim_name\'.\n";
                        if ($::VERBOSE)
                        {
                            push @{$rsp->{data}}, "$output";
                        }
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                        $error++;
                        push(@nodesfailed, $node);
                        next;
                    }
                }

                # To be reinitialized
                $toinit = 1;
                
            }
            else
            {
                # Give a message to confirm if reinitialization is needed.
                my $rsp;
                push @{$rsp->{data}},
                  "$Sname: The node \'$node\' is already defined. Use the force option to reinitialize.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                push(@nodesfailed, $node);
                $error++;
                next;
            }
        }
        else
        {
            # new node to define and initialize
            
            # 1. define diskless machine
            $todef = 1;
            # 2. dkls_init for this machine
            $toinit = 1;
        }

        my @attrlist;
        my $output;
        
        if ($todef == 1)
        {
            # get, check the node IP
            # TODO - need IPv6 update
            #my $IP = inet_ntoa(inet_aton($node));
            my $IP = xCAT::NetworkUtils->getipaddr($node);
            chomp $IP;
            unless (($IP =~ /\d+\.\d+\.\d+\.\d+/) || ($IP =~ /:/))
            {
                my $rsp;
                push @{$rsp->{data}},
                  "$Sname: Could not get valid IP address for node $node.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                $error++;
                push(@nodesfailed, $node);
                next;
            }

            # check for required attrs
            if (($type ne "standalone"))
            {

                # could be diskless or dataless
                # mask, gateway, cosi, root, dump, paging
                # TODO - need to fix this check for shared_root
                if (   !$nethash{$node}{'mask'}
                    || !$nethash{$node}{'gateway'}
                    || !$imagehash{$image_name}{spot})
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "$Sname: Missing required information for node \'$node\'.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    $error++;
                    push(@nodesfailed, $node);
                    next;
                }
            }

            # set some default values
            # overwrite with cmd line values - if any
            my $speed  = "100";
            my $duplex = "full";
            if ($attrs{duplex})
            {
                $duplex = $attrs{duplex};
            }
            if ($attrs{speed})
            {
                $speed = $attrs{speed};
            }

            # define the node
            my $mac_or_local_link_addr;
            my $adaptertype;
            my $netmask;
            my $if = 1;
            my $netname;
            # Use -F to workaround ping time during diskless node defined in nim
            my $defcmd = "/usr/sbin/nim -Fo define -t $type ";

            $objhash{$node}{'mac'} =~ s/://g;    # strip out colons if any
            my @macs = split /\|/, $objhash{$node}{'mac'};
            foreach my $mac (@macs)
            {
                if (xCAT::NetworkUtils->getipaddr($nodeshorthost) =~ /:/) #ipv6 node
                {
                    $mac_or_local_link_addr = xCAT::NetworkUtils->linklocaladdr($mac);
                    $adaptertype = "ent6";
                    $netmask = xCAT::NetworkUtils->prefixtomask($nethash{$node}{'mask'});
                } else {
                    $mac_or_local_link_addr = $mac;
                    # only support Ethernet for management interfaces
                    if ($nethash{$node}{'mgtifname'} =~ /hf/)
                    {
                        $adaptertype = "hfi0";
                    } else {
                        $adaptertype = "ent";
                    }
                    $netmask = $nethash{$node}{'mask'};
                }

                $netname = $nethash{$node}{'netname'};

                if ($::NEWNAME)
                {
                    $defcmd .= "-a if$if='find_net $nodeshorthost 0' ";
                } else
                {
                    $defcmd .=
                          "-a if$if='find_net $nodeshorthost $mac_or_local_link_addr $adaptertype' ";
                }

                $defcmd .= "-a cable_type$if=N/A ";
                $if = $if + 1;
            }

            $defcmd .= "-a netboot_kernel=mp ";

            if ($nethash{$node}{'mgtifname'} !~ /hf/)
            {
                $defcmd .=
                    "-a net_definition='$adaptertype $netmask $nethash{$node}{'gateway'}' ";
                $defcmd .= "-a net_settings1='$speed $duplex' ";
            }

            # add any additional supported attrs from cmd line
            @attrlist = ("dump_iscsi_port");
            foreach my $attr (keys %attrs)
            {
                if (grep(/^$attr$/, @attrlist))
                {
                    $defcmd .= "-a $attr=$attrs{$attr} ";
                }
            }
            $defcmd .= "$nim_name  2>&1";
            if ($::VERBOSE)
            {
                my $rsp;
                push @{$rsp->{data}}, "$Sname: Creating NIM node definition.\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            } else {
                               my $rsp;
                               push @{$rsp->{data}}, "$Sname: Creating NIM client definition \'$nim_name.\'\n";
                               xCAT::MsgUtils->message("I", $rsp, $callback);
                       }
            $output = xCAT::Utils->runcmd("$defcmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "$Sname: Could not create a NIM definition for \'$nim_name\'.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$output";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                $error++;
                push(@nodesfailed, $node);
                next;
            }
        }

        if ($toinit == 1)
        {
            # diskless also needs a defined paging res
            if ($type eq "diskless")
            {
                if (!$imagehash{$image_name}{paging})
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "$Sname: Missing required information for node \'$node\'.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    $error++;
                    push(@nodesfailed, $node);
                    next;
                }
            }

            #
            # initialize node
            #

            my $psize = "64";
            if ($attrs{psize})
            {
                $psize = $attrs{psize};
            }

            my $arg_string;
            if ($imagehash{$image_name}{shared_root})
            {
                $arg_string =
                  "-a spot=$imagehash{$image_name}{spot} -a shared_root=$imagehash{$image_name}{shared_root} -a size=$psize ";
            }
            else
            {
                $arg_string =
                  "-a spot=$imagehash{$image_name}{spot} -a root=$imagehash{$image_name}{root} -a size=$psize ";
            }

            # the rest of these resources may or may not be provided
            if ($imagehash{$image_name}{paging})
            {
                $arg_string .= "-a paging=$imagehash{$image_name}{paging} ";
                               # add extras from the cmd line
                               if ($attrs{sparse_paging} ) {
                                       $arg_string .= "-a sparse_paging=$attrs{sparse_paging} ";
                               }
            }

			# see if we have a resolv_conf resource 
            if ($resolv_conf_hash{$node}) {
				$arg_string .= " -a resolv_conf=$resolv_conf_hash{$node} " ;
			}

            if ($imagehash{$image_name}{dump})
            {
                $arg_string .= "-a dump=$imagehash{$image_name}{dump} ";
                               if ($attrs{configdump} ) {
                                       $arg_string .= "-a configdump=$attrs{configdump} ";
                               } else {
                                       # the default is selective
                                       $arg_string .= "-a configdump=selective ";
                               }
            }
            if ($imagehash{$image_name}{home})
            {
                $arg_string .= "-a home=$imagehash{$image_name}{home} ";
            }
            if ($imagehash{$image_name}{tmp})
            {
                $arg_string .= "-a tmp=$imagehash{$image_name}{tmp} ";
            }
            if ($imagehash{$image_name}{shared_home})
            {
                $arg_string .=
                  "-a shared_home=$imagehash{$image_name}{shared_home} ";
            }

            my $initcmd;
            if ($type eq "diskless")
            {
                $initcmd = "/usr/sbin/nim -o dkls_init $arg_string $nim_name 2>&1";
            }
            else
            {
                $initcmd = "/usr/sbin/nim -o dtls_init $arg_string $nim_name 2>&1";
            }

            my $time = `date | cut -f5 -d' '`;
            chomp $time;

            my $rsp;
            push @{$rsp->{data}}, "$Sname: Initializing NIM machine \'$nim_name\'. \n";
			xCAT::MsgUtils->message("I", $rsp, $callback);

            $output = xCAT::Utils->runcmd("$initcmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "$Sname: Could not initialize NIM client named \'$nim_name\'.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$output";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                $error++;
                push(@nodesfailed, $node);
                next;
            }
        }

        # Update /tftpboot/nodeip.info to export the variable BASECUST_REMOVAL
        # then during the network boot, rc.dd_boot script will check this variable
        # to see if we need remove any device after restbase /etc/basecust.
        # For now, we only need to remove swapnfs0.

        # Only for the ODM persistent feature
        if ($imagehash{$image_name}{shared_root})
        {
            # This has a shared_root resource, then it might have /etc/basecust restore

            # Update /tftpboot/nodeip.info
            my ($nodehost, $nodeip) = xCAT::NetworkUtils->gethostnameandip($node);
            if (!$nodehost || !$nodeip)
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Can not resolve the node $node";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                next;
            }
                        
            my $tftpdir = xCAT::Utils->getTftpDir();
            my $niminfoloc = "$tftpdir/${nodeip}.info";

            my $cmd = "cat $niminfoloc | grep 'BASECUST_REMOVAL'";
            my @result = xCAT::Utils->runcmd("$cmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                if ($::VERBOSE)
                {
                    my $rsp;
                    push @{$rsp->{data}}, "Updating the $niminfoloc file.\n";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }

                unless (open(NIMINFOFILE, "<$niminfoloc"))
                {
                    my $rsp = {};
                    $rsp->{data}->[0] = "Can not open the niminfo file $niminfoloc for reading.";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                }

                my @infofile = <NIMINFOFILE>;
                close(NIMINFOFILE);
                
                push @infofile, "export BASECUST_REMOVAL=swapnfs0\n";

                unless (open(NEWINFO, ">$niminfoloc"))
                {
                    my $rsp = {};
                    $rsp->{data}->[0] = "Can not open the file $niminfoloc for writing";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                }

                for my $line (@infofile)
                {
                    print NEWINFO $line;
                }
                close(NEWINFO);
            }    
        }
        
        if (0)
        {

            # Update the files in /install/custom/netboot/AIX/syncfile to the root image
            # figure out the path of root image
            my $cmd =
              "/usr/sbin/lsnim -a location $imagehash{$image_name}{root} | /usr/bin/grep location 2>/dev/null";
            my $location = xCAT::Utils->runcmd("$cmd", -1);
            $location =~ s/\s*location = //;
            chomp($location);
            my $root_location = $location . '/' . $nim_name . '/';
            if (-d $root_location)
            {
                my $syncfile = $$node_syncfile{$node};
                xCAT::MsgUtils->message("S",
                                      "mkdsklsnode: $root_location, $syncfile");

                my $arg = ["-i", "$root_location", "-F", "$syncfile"];
                my $env = ["RSYNCSN=yes", "DSH_RSYNC_FILE=$syncfile"];
                $subreq->(
                          {
                           command => ['xdcp'],
                           node    => [$node],
                           arg     => $arg,
                           env     => $env
                          },
                          $callback
                          );
            }

        }

        # Update /etc/bootptab for HFI mac address failover
        my $if = 1;
        my $firstmac;
        my @macs = split /\|/, $objhash{$node}{'mac'};
        my $cmd = "cat /etc/bootptab | grep $macs[0]";
        my @result = xCAT::Utils->runcmd("$cmd", -1);
        if ($::RUNCMD_RC == 0)
        {
            foreach my $mac (@macs)
            {
                my $newline = $result[0];
                if ($if == 1)
                {
                    $if = $if + 1;
                    $firstmac = $mac;
                    next;
                }
                my $cmd = "cat /etc/bootptab | grep $mac";
                my @rt = xCAT::Utils->runcmd("$cmd", -1);
                if ($::RUNCMD_RC == 0)
                {
                    $if = $if + 1;
                    next;
                }
                $newline =~ s/^(.*)$firstmac(.*)$/$1$mac$2/g;
                $cmd = "echo $newline >> /etc/bootptab";
                xCAT::Utils->runcmd("$cmd", -1);
                $if = $if + 1;
           }
        }
    }    # end - for each node

    #
    # External NFS support:
    #   For shared_root:
    #       Update shared_root/etc/.client_data/hosts.<nodename>
    #       Update shared_root/etc/.client_data/filesystems.<nodename>
    #   For non-shared_root:
    #       Update root/<nodename>/etc/hosts
    #       Update root/<nodename>/etc/filesystems
    #

    # convert the @nodesfailed to hash for search performance considerations
    my %fnhash = ();
    foreach my $fnd (@nodesfailed)
    {
        $fnhash{$fnd} = 1;
    }

    # Only do the update for the successful nodes
    my @snode = ();
    foreach my $nd (@nodelist)
    {
        if(!defined($fnhash{$nd}) || ($fnhash{$nd} != 1))
        {
            push(@snode, $nd);
        }
    }

    if(scalar(@snode) > 0)
    {
        my $nfshash;
        my $restab = xCAT::Table->new('noderes');
        if ($restab)
        {
            $nfshash = $restab->getNodesAttribs(\@nodelist, ['nfsserver']);
        }
        foreach my $snd (@snode)
        {
            # nfsserver defined for this node
            if($nfshash->{$snd}->[0]->{'nfsserver'})
            {
                # if nfsserver is set to the service node itself, nothing needs to do
                if(!xCAT::InstUtils->is_me($nfshash->{$snd}->[0]->{'nfsserver'}))
                {
                    my $osimg = $nodeosi{$snd};
                    my ($nfshost,$nfsip) = xCAT::NetworkUtils->gethostnameandip($nfshash->{$snd}->[0]->{'nfsserver'});
                    if (!$nfshost || !$nfsip)
                    {
                        my $rsp = {};
                        $rsp->{data}->[0] = "Can not resolve the nfsserver $nfshost for node $snd";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                        next;
                    }
                    #shared_root configuration
                    my $hostfile;
                    my $filesystemsfile;
                    if($imagehash{$osimg}{'shared_root'})
                    {
                        my $imgsrdir = xCAT::InstUtils->get_nim_attr_val(
                                                        $imagehash{$osimg}{'shared_root'}, 
                                                        "location", $callback, $Sname, $subreq);
                        $hostfile = "$imgsrdir/etc/.client_data/hosts.$snd";
                        $filesystemsfile = "$imgsrdir/etc/.client_data/filesystems.$snd";
                    }
                    else # non-shared_root configuration
                    {
                        my $imgrootdir = xCAT::InstUtils->get_nim_attr_val(
                                                          $imagehash{$osimg}{'root'},
                                                          "location", $callback, $Sname, $subreq);
                        $hostfile = "$imgrootdir/$snd/etc/hosts";
                        $filesystemsfile = "$imgrootdir/$snd/etc/filesystems";
                        my ($nodehost, $nodeip) = xCAT::NetworkUtils->gethostnameandip($snd);
                        if (!$nodehost || !$nodeip)
                        {
                            my $rsp = {};
                            $rsp->{data}->[0] = "Can not resolve the node $snd";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                            next;
                        }
                        my $tftpdir = xCAT::Utils->getTftpDir();
                        my $niminfofile = "$tftpdir/${nodeip}.info";
                        #Update /tftpboot/<node>.info file
                        my $fscontent;
                        unless (open(NIMINFOFILE, "<$niminfofile"))
                        {
                            my $rsp = {};
                            $rsp->{data}->[0] = "Can not open the niminfo file $niminfofile for node $snd";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                            next;
                        }
                        while (my $line = <NIMINFOFILE>)
                        {
                            $fscontent .= $line;
                        }

                        # Update the ROOT & NIM_HOSTS
                        $fscontent =~ s/(export\s+SPOT=)(.*):/$1$nfshost:/;
                        $fscontent =~ s/(export\s+ROOT=)(.*):/$1$nfshost:/;
                        $fscontent =~ s/(export\s+NIM_HOSTS=.*)"/$1$nfsip:$nfshost "/;
                        close(NIMINFOFILE);

                        unless (open(TMPFILE, ">$niminfofile"))
                        {
                            my $rsp = {};
                            $rsp->{data}->[0] = "Can not open the file $niminfofile for writing";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                            next;
                        }
                        print TMPFILE $fscontent;
                        close(TMPFILE);

                    }
                    
                    # Update /etc/hosts file in the shared_root or root
                    my $line = "$nfsip    $nfshost";
                    my $cmd = "echo  $line >> $hostfile";
                    xCAT::Utils->runcmd($cmd, 0);
                    if ($::RUNCMD_RC != 0)
                    {
                        my $rsp = {};
                        $rsp->{data}->[0] = "Can not update the NIM hosts file $hostfile for node $snd";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                        next;
                    }

                    #Update etc/filesystems file in the shared_root or root
                    my $fscontent;
                    unless (open(FSFILE, "<$filesystemsfile"))
                    {
                        my $rsp = {};
                        $rsp->{data}->[0] = "Can not open the filesystems file $filesystemsfile for node $snd";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                        next;
                    }
                    while (my $line = <FSFILE>)
                    {
                        $fscontent .= $line;
                    }

                    # Update the mount server for / and /usr
                    $fscontent =~ s/(\/:\s*\n\s+nodename\s+=\s+)(.*)/$1$nfshost/;
                    $fscontent =~ s/(\/usr:\s*\n\s+nodename\s+=\s+)(.*)/$1$nfshost/;
                    close(FSFILE);

                    my $tmpfile = $filesystemsfile . ".tmp";
                    unless (open(FSTMPFILE, ">$tmpfile"))
                    {
                        my $rsp = {};
                        $rsp->{data}->[0] = "Can not open the file $tmpfile for writing";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                        next;
                    }
                    print FSTMPFILE $fscontent;
                    close(FSTMPFILE);

                    my $cpcmd = "cp $tmpfile $filesystemsfile";
                    xCAT::Utils->runcmd($cpcmd, 0);
                    if ($::RUNCMD_RC != 0)
                    {
                        my $rsp = {};
                        $rsp->{data}->[0] = "Can not update the NIM filesystems file $filesystemsfile for node $snd";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                        next;
                    }

                } #end if(!xCAT::InstUtils->is_me...
            }

            # Enable /proc filesystem by default

            my $filesystemsfile;
            my $osimg = $nodeosi{$snd};

            #shared_root or root configuration
            if($imagehash{$osimg}{'shared_root'})
            {
                my $imgsrdir = xCAT::InstUtils->get_nim_attr_val(
                                                $imagehash{$osimg}{'shared_root'},
                                                 "location", $callback, $Sname, $subreq);
                $filesystemsfile = "$imgsrdir/etc/.client_data/filesystems.$snd";
            }
            else # non-shared_root configuration
            {
                my $imgrootdir = xCAT::InstUtils->get_nim_attr_val(
                                                  $imagehash{$osimg}{'root'},
                                                  "location", $callback, $Sname, $subreq);
                $filesystemsfile = "$imgrootdir/$snd/etc/filesystems";
            }

            my $fscontent;
            unless (open(FSFILE, "<$filesystemsfile"))
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Can not open the filesystems file $filesystemsfile for node $snd";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                next;
            }
            while (my $line = <FSFILE>)
            {
                $fscontent .= $line;
            }

            if (!grep(/proc:/, $fscontent))
            {
                my $line = qq~/proc:\n	dev		=	/proc\n	vol		=	\"/proc\"\n	mount		=	true\n	check		=	false\n	free		=	false\n	vfs		=	procfs~;

                $cmd = "echo \"$line\" >> $filesystemsfile";
                xCAT::Utils->runcmd($cmd, 0);
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp = {};
                    $rsp->{data}->[0] = "Can not update the NIM filesystems file $filesystemsfile for node $snd";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    next;
                }
            }
        }
    }

    #
    # update the node definitions with the new osimage - if provided
    #
    my %nodeattrs;
    foreach my $node (keys %objhash)
    {
        chomp $node;
        if (!grep(/^$node$/, @nodesfailed))
        {

            # change the node def if we were successful
            $nodeattrs{$node}{objtype} = 'node';
            $nodeattrs{$node}{os}      = "AIX";
            if ($::OSIMAGE)
            {
                $nodeattrs{$node}{profile}    = $::OSIMAGE;
                $nodeattrs{$node}{provmethod} = $::OSIMAGE;
            }
        }
    }
    if (xCAT::DBobjUtils->setobjdefs(\%nodeattrs) != 0)
    {
        my $rsp;
        push @{$rsp->{data}},
          "$Sname: Could not write data to the xCAT database.\n";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        $error++;
    }

    # restart inetd
    if ($::VERBOSE)
    {
        my $rsp;
        push @{$rsp->{data}}, "Restarting inetd on $Sname.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }
    my $scmd = "stopsrc -s inetd";
    my $output = xCAT::Utils->runcmd("$scmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not stop inetd on $Sname.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        $error++;
    }
    $scmd = "startsrc -s inetd";
    $output = xCAT::Utils->runcmd("$scmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not start inetd on $Sname.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        $error++;
    }

    #
    # process any errors
    #
    my $retcode=0;
    if ($error)
    {
        my $rsp;
        push @{$rsp->{data}},
          "$Sname: One or more errors occurred when attempting to initialize AIX NIM diskless nodes.\n";

        if ($::VERBOSE && (@nodesfailed))
        {
            push @{$rsp->{data}},
              "$Sname: The following node(s) could not be initialized.\n";
            foreach my $n (@nodesfailed)
            {
                push @{$rsp->{data}}, "$n";
            }
        }

        xCAT::MsgUtils->message("E", $rsp, $callback);
	$retcode =  1;
    }
    else
    {
        my $rsp;
        push @{$rsp->{data}},
          "$Sname: AIX/NIM diskless nodes were initialized.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }

    
    #now run the end part of the prescripts
    #the call is distrubuted to the service node already, so only need to handles my own children
    $errored=0;
    if (@nodesfailed > 0) {
	my @good_nodes=();
	foreach my $node (@nodelist) {
	    if (!grep(/^$node$/, @nodesfailed)) {
                 push(@good_nodes, $node);
            }
        }
        $subreq->({command=>['runendpre'],
                      node=>\@good_nodes,
                      arg=>["diskless", '-l']},\&pass_along);
    } else {
        $subreq->({command=>['runendpre'],
                      node=>\@nodelist,
                      arg=>["diskless", '-l']},\&pass_along);
    }
    if ($errored) { 
	my $rsp;
	$rsp->{errorcode}->[0]=1;
	$rsp->{error}->[0]="Failed in running end prescripts.\n";
	$callback->($rsp);
	return 1; 
    }


    return  $retcode;
}

#----------------------------------------------------------------------------

=head3   checkNIMnetworks

		See if there is a NIM network definition for the networks these
			nodes are on.

		If not then create the NIM definitions etc.

        Arguments:
        Returns:
                0 - OK
                1 - error
        Comments:

=cut

#-----------------------------------------------------------------------------
sub checkNIMnetworks
{
    my $callback = shift;
    my $nodes    = shift;
    my $nethash  = shift;


    my @nodelist = @{$nodes};
    my %nethash;    # hash of xCAT network definitions for each node
    if ($nethash)
    {
        %nethash = %{$nethash};
    }

    #
    # get all the nim network names and attrs defined on this SN
    #
    my $cmd =
      qq~/usr/sbin/lsnim -c networks | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    my @networks = xCAT::Utils->runcmd("$cmd", -1);

    # for each NIM network - get the attrs
    my %NIMnets;
    foreach my $netwk (@networks)
    {
        my $cmd = qq~/usr/sbin/lsnim -Z -a net_addr -a snm $netwk 2>/dev/null~;
        my @result = xCAT::Utils->runcmd("$cmd", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not run lsnim command: \'$cmd\'.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }

        foreach my $l (@result)
        {

            # skip comment lines
            next if ($l =~ /^\s*#/);

            my ($nimname, $net_addr, $snm) = split(':', $l);
            $NIMnets{$netwk}{'net_addr'} = $net_addr;
            $NIMnets{$netwk}{'snm'}      = $snm;
        }
    }

    #
    # for each node - see if the net we need is defined
    #
    foreach my $node (@nodelist)
    {

        # see if the NIM net we need is defined

        my $foundmatch = 0;
        # foreach nim network name
        foreach my $netwk (@networks) {

        # check for the same netmask and network address
              if ( ($nethash{$node}{net} eq $NIMnets{$netwk}{'net_addr'}) ) {
                      if ( $nethash{$node}{mask} eq $NIMnets{$netwk}{'snm'} ) {
                             $foundmatch=1;
                      }
               }
     }

        # if not defined then define it!
        if (!$foundmatch)
        {

            # create new nim network def
            # use the same network name as xCAT uses
            my $devtype;
            if ($nethash{$node}{'mgtifname'} =~ /hf/)
            {
                $devtype = "hfi";
            } else {
                $devtype = "ent";
            }
            my $cmd =
              qq~/usr/sbin/nim -o define -t $devtype -a net_addr=$nethash{$node}{net} -a snm=$nethash{$node}{mask} -a routing1='default $nethash{$node}{gateway}' $nethash{$node}{netname} 2>/dev/null~;

            my $output1 = xCAT::Utils->runcmd("$cmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not run \'$cmd\'.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

            #
            # create an interface def (if*) for the master
            #
            # first get the if* and cable_type* attrs
            #  - the -A option gets the next avail index for this attr
            my $ifcmd = qq~/usr/sbin/lsnim -A if master 2>/dev/null~;
            my $ifindex = xCAT::Utils->runcmd("$ifcmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not run \'$ifcmd\'.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

            my $ctcmd = qq~/usr/sbin/lsnim -A cable_type master 2>/dev/null~;
            my $ctindex = xCAT::Utils->runcmd("$ctcmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not run \'$ctcmd\'.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

            # get the local adapter hostname for this network
            # get all the possible IPs for the node I'm running on
            my $ifgcmd = "ifconfig -a | grep 'inet '";
            my @result = xCAT::Utils->runcmd($ifgcmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not run \'$ifgcmd\'.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

            my $adapterhostname;
            foreach my $int (@result) {
                    my ($inet, $myIP, $str) = split(" ", $int);
                    chomp $myIP;
                    $myIP =~ s/\/.*//; # ipv6 address 4000::99/64
                    $myIP =~ s/\%.*//; # ipv6 address ::1%1/128

                    # if the ip address is in the subnet
                    #       the right interface
                    if ( xCAT::NetworkUtils->ishostinsubnet($myIP, $nethash{$node}{mask}, $nethash{$node}{net} )) {
                            $adapterhostname = xCAT::NetworkUtils->gethostname($myIP);
                            last;
                    }
            }

            # define the new interface
            my $chcmd =
              qq~/usr/sbin/nim -o change -a if$ifindex='$nethash{$node}{netname} $adapterhostname 0' -a cable_type$ctindex=N/A master 2>/dev/null~;

            my $output2 = xCAT::Utils->runcmd("$chcmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not run \'$chcmd\'.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

            # get the next index for the routing attr
            my $ncmd = qq~/usr/sbin/lsnim -A routing master_net 2>/dev/null~;
            my $rtindex = xCAT::Utils->runcmd("$ncmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not run \'$ncmd\'.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

            # get hostname of primary int - always if1
            my $hncmd = qq~/usr/sbin/lsnim -a if1 -Z master 2>/dev/null~;
            my $ifone = xCAT::Utils->runcmd("$hncmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not run \'$hncmd\'.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

			my $junk1;
			my $junk2;
			my $adapterhost;
			my @ifcontent = split('\n',$ifone);
			foreach my $line (@ifcontent) {
				next if ($line =~ /^#/);
				($junk1, $junk2, $adapterhost) = split(':', $line);
				last;
			}

            # create static routes between the networks
            my $rtgcmd =
              qq~/usr/sbin/nim -o change -a routing$rtindex='master_net $nethash{$node}{gateway} $adapterhost' $nethash{$node}{netname} 2>/dev/null~;
            my $output3 = xCAT::Utils->runcmd("$rtgcmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not run \'$rtgcmd\'.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

        }    # end - define new nim network

    }    # end - for each node

    return 0;
}

#----------------------------------------------------------------------------

=head3   make_SN_resource 

		See if the required NIM resources are created on the local server.
		
		Create local definitions if necessary.

		Runs only on service nodes that are not the NIM primary

		Supports the following NIM resources:
		 	bosinst_data, dump, home, mksysb,
            installp_bundle, lpp_source, script, paging
            root, shared_home, spot, tmp, resolv_conf

		Also does the NIM setup for additional networks if necessary.

        Arguments:
        Returns:
                0 - OK
                1 - error
        Comments:

=cut

#-----------------------------------------------------------------------------
sub make_SN_resource
{
    my $callback = shift;
    my $nodes    = shift;
    my $images   = shift;
    my $imghash  = shift;
    my $lhash    = shift;
    my $nethash  = shift;
	my $nimres 	 = shift;

    my @nodelist    = @{$nodes};
    my @image_names = @{$images};
    my %imghash;    # hash of osimage defs
    my %lochash;    # hash of res locations
    my %nethash;
	my %nimhash;
    if ($imghash)
    {
        %imghash = %{$imghash};
    }
    if ($lhash)
    {
        %lochash = %{$lhash};
    }
    if ($nethash)
    {
        %nethash = %{$nethash};
    }
	if ($nimres) 
	{
		%nimhash = %{$nimres};
	}

	my %attrs;
	if (defined(@{$::args}))
	{
		@ARGV = @{$::args};
	}
	while (my $a = shift(@ARGV))
	{
		if ($a =~ /=/)
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

    my $cmd;

    my $SNname = "";
	$SNname = xCAT::InstUtils->myxCATname();
    chomp $SNname;

    my $nimprime = xCAT::InstUtils->getnimprime();
    chomp $nimprime;

	my $rsp;
	push @{$rsp->{data}}, "Checking NIM resources on $SNname.\n";
	xCAT::MsgUtils->message("I", $rsp, $callback);

    #
    #  Install/config NIM master if needed
    #
    my $lsnimcmd = "/usr/sbin/lsnim -l >/dev/null 2>&1";
    my $out = xCAT::Utils->runcmd("$lsnimcmd", -1);
    if ($::RUNCMD_RC != 0)
    {

        # then we need to configure NIM on this node
        if ($::VERBOSE)
        {
            my $rsp;
            push @{$rsp->{data}}, "Configuring NIM.\n";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }

        #  NIM filesets should already be installed on the service node
        my $nimcmd = "nim_master_setup -a mk_resource=no";
        my $nimout = xCAT::Utils->runcmd("$nimcmd", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not install and configure NIM.\n";
            if ($::VERBOSE)
            {
                push @{$rsp->{data}}, "$nimout";
            }
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
    }

    # make sure we have the NIM networks defs etc we need for these nodes
    if (&checkNIMnetworks($callback, \@nodelist, \%nethash) != 0)
    {
        return 1;
    }

    #
    # get list of valid NIM resource types from local NIM
    #
    $cmd =
      qq~/usr/sbin/lsnim -P -c resources | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    my @nimrestypes = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}},
          "Could not get NIM resource types on \'$SNname\'.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    #
    # get the local defined res names
    #
    $cmd =
      qq~/usr/sbin/lsnim -c resources | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    my @nimresources = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}},
          "Could not get NIM resource definitions on \'$SNname\'.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    #
    # go through each osimage needed on this server
    #	- if the NIM resource is not already defined then define it
    #

    # for each image
    foreach my $image (@image_names)
    {
        my @orderedtypelist;

        # always do lpp 1st, spot 2nd, rest after that
        #   ex. shared_root requires spot
        if ($imghash{$image}{lpp_source})
        {
            push(@orderedtypelist, 'lpp_source');
        }
        if ($imghash{$image}{spot})
        {
            push(@orderedtypelist, 'spot');
        }
        foreach my $restype (keys(%{$imghash{$image}}))
        {
            if (($restype ne 'lpp_source') && ($restype ne 'spot'))
            {
                push(@orderedtypelist, $restype);
            }
        }

        # for each resource
        foreach my $restype (@orderedtypelist)
        {

            # if a valid NIM type and a value is set
            if (   ($imghash{$image}{$restype})
                && (grep(/^$restype$/, @nimrestypes)))
            {

                #  Note: - for now keep it simple - if the resource exists
                #   then don't try to recreate it

                #  see if it already exists on this SN
                # if (grep(/^$imghash{$image}{$restype}$/, @nimresources))
                if (0)
                {

                    # is it allocated?
                    my $cmd =
                      "/usr/sbin/lsnim -l $imghash{$image}{$restype} 2>/dev/null";
                    my @result = xCAT::Utils->runcmd("$cmd", -1);
                    if ($::RUNCMD_RC != 0)
                    {
                        my $rsp;
                        push @{$rsp->{data}},
                          "Could not run lsnim command: \'$cmd\'.\n";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                        next;
                    }

                    my $alloc_count;
                    foreach (@result)
                    {
                        my ($attr, $value) = split('=');
                        chomp $attr;
                        $attr =~ s/\s*//g;    # remove blanks
                        chomp $value;
                        $value =~ s/^\s*//;
                        if ($attr eq "alloc_count")
                        {
                            $alloc_count = $value;
                            last;
                        }
                    }

                    if (defined($alloc_count) && ($alloc_count != 0))
                    {
                        my $rsp;
                        push @{$rsp->{data}},
                          "The resource named \'$imghash{$image}{$restype}\' is currently allocated. It will not be recreated.\n";
                        xCAT::MsgUtils->message("I", $rsp, $callback);
                        next;
                    }
                    else
                    {

                        # it's not allocated so remove and recreate
                        my $cmd = "nim -Fo remove $imghash{$image}{$restype}";
                        my $output = xCAT::Utils->runcmd("$cmd", -1);
                        if ($::RUNCMD_RC != 0)
                        {
                            my $rsp;
                            push @{$rsp->{data}},
                              "Could not remove the NIM resource definition \'$imghash{$image}{$restype}\'.\n";
                            push @{$rsp->{data}}, "$output";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                            next;
                        }
                    }
                }

                #  see if it already exists on this SN
                if (grep(/^$imghash{$image}{$restype}$/, @nimresources))
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "Using existing resource called \'$imghash{$image}{$restype}\'.\n";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                    next;
                }

				# if dump res
				if (($restype eq "dump") && ($imghash{$image}{"nimtype"} eq 'diskless')) {
					my $loc = $lochash{$imghash{$image}{$restype}};
					chomp $loc;
					if (&mkdumpres( $imghash{$image}{$restype}, \%attrs, $callback, $loc, \%nimhash) != 0 ) {
						next;
					}
				}

                # if root, shared_root, tmp, home, shared_home, 
                #	paging then
                # 	these dont require copying anything from the nim primary
                my @dir_res = (
                               "root",        "shared_root",
                               "tmp",         "home",
                               "shared_home", 
                               "paging"
                               );
                if (grep(/^$restype$/, @dir_res))
                {


                    my $loc =
                      dirname(dirname($lochash{$imghash{$image}{$restype}}));
                    chomp $loc;
                    if (
                        &mknimres(
                                  $imghash{$image}{$restype}, $restype,
                                  $callback,                  $loc,
                                  $imghash{$image}{spot}, \%attrs, \%nimhash
                        ) != 0
                      )
                    {
                        next;
                    }
                }

                # only make lpp_source for standalone type images
                if (   ($restype eq "lpp_source")
                    && ($imghash{$image}{"nimtype"} eq 'standalone'))
                {

                    # restore the backup file - then remove it
                    my $bkname = $imghash{$image}{$restype} . ".bk";

                    my $resdir = $lochash{$imghash{$image}{$restype}};

                    # ex. /install/nim/lpp_source/61D_lpp_source

                    my $dir = dirname($resdir);

                    # ex. /install/nim/lpp_source
                    if (0)
                    {
                        my $rsp;
                        push @{$rsp->{data}},
                          "Restoring $bkname on $SNname. Running command \'mv $dir/$bkname $resdir/$bkname; cd $resdir; restore -xvqf $bkname; rm $bkname\'.\n";
                        xCAT::MsgUtils->message("I", $rsp, $callback);
                    }
                    my $restcmd =
                      "mv $dir/$bkname $resdir/$bkname; cd $resdir; restore -xvqf $bkname; rm $bkname";
                    my $output = xCAT::Utils->runcmd("$restcmd", -1);
                    if ($::RUNCMD_RC != 0)
                    {
                        my $rsp;
                        push @{$rsp->{data}},
                          "Could not restore NIM resource backup file called \'$bkname\'.\n";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                    }

                    # define the local res
					my $cmd = "/usr/sbin/nim -Fo define -t lpp_source -a server=master -a location=$lochash{$imghash{$image}{$restype}} ";

					my @validattrs = ("verbose", "nfs_vers", "nfs_sec", "packages", "use_source_simages", "arch", "show_progress", "multi_volume", "group");

					my %cmdattrs;
					if ($::NFSV4)
					{
						$cmdattrs{nfs_vers}=4;
					}

					# add additional attributes - if provided - from the 
					#NIM definition on the
    				#    NIM primary - (when replicating on a service node)
    				if (%nimhash) {
        				foreach my $attr (keys %{$nimhash{$imghash{$image}{$restype}}}) {
            				if (grep(/^$attr$/, @validattrs) ) {
                				$cmdattrs{$attr} = $nimhash{$imghash{$image}{$restype}}{$attr};
            				}
        				}
    				}

					# add any additional supported attrs from cmd line
    				if (%attrs) {
        				foreach my $attr (keys %attrs) {
            				if (grep(/^$attr$/, @validattrs) ) {
                 				$cmdattrs{$attr} = $attrs{$attr};
            				}
        				}
    				}

    				if (%cmdattrs) {
        				foreach my $attr (keys %cmdattrs) {
            				$cmd .= "-a $attr=$cmdattrs{$attr} ";
        				}
    				}
					$cmd .= " $imghash{$image}{$restype}";
                    $output = xCAT::Utils->runcmd("$cmd", -1);
                    if ($::RUNCMD_RC != 0)
                    {
                        my $rsp;
                        push @{$rsp->{data}},
                          "Could not create NIM resource $imghash{$image}{$restype} on $SNname \n";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                    }
                }

                # if installp_bundle or script they could have multiple names
                #		so the imghash name must be split
                #  the lochash is based on names
                if (($restype eq "installp_bundle") || ($restype eq "script"))
                {
                    foreach my $res (split /,/, $imghash{$image}{$restype})
                    {

                        # if the resource is not defined on the SN
                        if (!grep(/^$res$/, @nimresources))
                        {

                            # define the local resource
                            my $cmd; 
							$cmd = "/usr/sbin/nim -Fo define -t $restype -a server=master -a location=$lochash{$res} ";
							my @validattrs = ("verbose", "nfs_vers", "nfs_sec", "source", "dest_dir", "group");

							my %cmdattrs;
							if ($::NFSV4)
							{
								$cmdattrs{nfs_vers}=4;
							}

							# add additional attributes - if provided - from the 
							#NIM definition on the
    						#    NIM primary - (when replicating on a service node)
    						if (%nimhash) {
        						foreach my $attr (keys %{$nimhash{$imghash{$image}{$restype}}}) {
            						if (grep(/^$attr$/, @validattrs) ) {
                						$cmdattrs{$attr} = $nimhash{$imghash{$image}{$restype}}{$attr};
            						}
        						}
    						}

							# add any additional supported attrs from cmd line
    						if (%attrs) {
        						foreach my $attr (keys %attrs) {
            						if (grep(/^$attr$/, @validattrs) ) {
                 						$cmdattrs{$attr} = $attrs{$attr};
            						}
        						}
    						}

    						if (%cmdattrs) {
        						foreach my $attr (keys %cmdattrs) {
            						$cmd .= "-a $attr=$cmdattrs{$attr} ";
        						}
    						}
							$cmd .= " $res";
                        	my $output = xCAT::Utils->runcmd("$cmd", -1);
                            if ($::RUNCMD_RC != 0)
                            {
                                my $rsp;
                                push @{$rsp->{data}},
                                  "Could not create NIM resource $res on $SNname \n";
                                xCAT::MsgUtils->message("E", $rsp, $callback);
                            }
                        }
                    }
                }

				# do mksysb
				if ($restype eq "mksysb") {		
					my $cmd;
					$cmd = "/usr/sbin/nim -Fo define -t $restype -a server=master -a location=$lochash{$imghash{$image}{$restype}} ";

					my @validattrs = ("verbose", "nfs_vers", "nfs_sec", "dest_dir", "group", "source", "size_preview", "exclude_files", "mksysb_flags", "mk_image");
					my %cmdattrs;
					if ($::NFSV4)
					{
						$cmdattrs{nfs_vers}=4;
					}

					# add additional attributes - if provided - from the 
					#	NIM definition on the
    				#    NIM primary - (when replicating on a service node)
    				if (%nimhash) {
        				foreach my $attr (keys %{$nimhash{$imghash{$image}{$restype}}}) {
            				if (grep(/^$attr$/, @validattrs) ) {
                				$cmdattrs{$attr} = $nimhash{$imghash{$image}{$restype}}{$attr};
            				}
        				}
    				}

					# add any additional supported attrs from cmd line
    				if (%attrs) {
        				foreach my $attr (keys %attrs) {
            				if (grep(/^$attr$/, @validattrs) ) {
                 				$cmdattrs{$attr} = $attrs{$attr};
            				}
        				}
    				}

    				if (%cmdattrs) {
        				foreach my $attr (keys %cmdattrs) {
            				$cmd .= "-a $attr=$cmdattrs{$attr} ";
        				}
    				}
					$cmd .= " $imghash{$image}{$restype}";
					my $output = xCAT::Utils->runcmd("$cmd", -1);
                    if ($::RUNCMD_RC != 0)
                    {
                        my $rsp;
                        push @{$rsp->{data}},
                          "Could not create NIM resource $imghash{$image}{$restype} on $SNname \n";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                    }
				}

                # if resolv_conf, bosinst_data  then
                #   the last part of the location is the actual file name
                # 	but not necessarily the resource name!
                my @usefileloc = ("resolv_conf", "bosinst_data");
                if (grep(/^$restype$/, @usefileloc))
                {
                    # define the local resource
                    my $cmd;
					$cmd = "/usr/sbin/nim -Fo define -t $restype -a server=master -a location=$lochash{$imghash{$image}{$restype}} ";
					my @validattrs = ("verbose", "nfs_vers", "nfs_sec", "group");
					my %cmdattrs;
					if ($::NFSV4)
					{
						$cmdattrs{nfs_vers}=4;
					}

					# add additional attributes - if provided - from the 
					#	NIM definition on the
    				#    NIM primary - (when replicating on a service node)
    				if (%nimhash) {
        				foreach my $attr (keys %{$nimhash{$imghash{$image}{$restype}}}) {
            				if (grep(/^$attr$/, @validattrs) ) {
                				$cmdattrs{$attr} = $nimhash{$imghash{$image}{$restype}}{$attr};
            				}
        				}
    				}

					# add any additional supported attrs from cmd line
    				if (%attrs) {
        				foreach my $attr (keys %attrs) {
            				if (grep(/^$attr$/, @validattrs) ) {
                 				$cmdattrs{$attr} = $attrs{$attr};
            				}
        				}
    				}

    				if (%cmdattrs) {
        				foreach my $attr (keys %cmdattrs) {
            				$cmd .= "-a $attr=$cmdattrs{$attr} ";
        				}
    				}
					$cmd .= " $imghash{$image}{$restype}";
                    my $output = xCAT::Utils->runcmd("$cmd", -1);
                    if ($::RUNCMD_RC != 0)
                    {
                        my $rsp;
                        push @{$rsp->{data}},
                          "Could not create NIM resource $imghash{$image}{$restype} on $SNname \n";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                    }
                }

                # if spot
                if ($restype eq "spot")
                {

                    my $rsp;
                    push @{$rsp->{data}},
                      "Creating a SPOT resource on $SNname.  This could take a while.\n";
                    xCAT::MsgUtils->message("I", $rsp, $callback);

                    # restore the backup file - then remove it
                    my $bkname = $imghash{$image}{$restype} . ".bk";
                    my $resdir = dirname($lochash{$imghash{$image}{$restype}});
                    chomp $resdir;

                    # ex. /install/nim/spot/612dskls

                    my $dir = dirname($resdir);

                    # ex. /install/nim/spot

                    if (0)
                    {
                        my $rsp;
                        push @{$rsp->{data}},
                          "Restoring $bkname on $SNname. Running command \'mv $dir/$bkname $resdir/$bkname; cd $resdir; restore -xvqf $bkname; rm $bkname\'\n";
                        xCAT::MsgUtils->message("I", $rsp, $callback);
                    }

                    my $restcmd =
                      "mv $dir/$bkname $resdir/$bkname; cd $resdir; restore -xvqf $bkname; rm $bkname";

                    my $output = xCAT::Utils->runcmd("$restcmd", -1);
                    if ($::RUNCMD_RC != 0)
                    {
                        my $rsp;
                        push @{$rsp->{data}},
                          "Could not restore NIM resource backup file called \'$bkname\'.\n";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                    }

                    # location for spot is odd
                    # ex. /install/nim/spot/611image/usr
                    # want /install/nim/spot for loc when creating new one
                    my $loc =
                      dirname(dirname($lochash{$imghash{$image}{$restype}}));
                    chomp $loc;

					my $spotcmd;
					$spotcmd = "/usr/sbin/nim -o define -t spot -a server=master -a location=$loc ";
	
					my @validattrs = ("verbose", "nfs_vers", "nfs_sec", "installp_flags", "auto_expand", "show_progress", "debug");

					my %cmdattrs;
					if ($::NFSV4)
					{
						$cmdattrs{nfs_vers}=4;
					}

					# add additional attributes - if provided - from the 
					#NIM definition on the
    				#    NIM primary - (when replicating on a service node)
    				if (%nimhash) {
        				foreach my $attr (keys %{$nimhash{$imghash{$image}{$restype}}}) {
            				if (grep(/^$attr$/, @validattrs) ) {
                				$cmdattrs{$attr} = $nimhash{$imghash{$image}{$restype}}{$attr};
            				}
        				}
    				}

					# add any additional supported attrs from cmd line
    				if (%attrs) {
        				foreach my $attr (keys %attrs) {
            				if (grep(/^$attr$/, @validattrs) ) {
                 				$cmdattrs{$attr} = $attrs{$attr};
            				}
        				}
    				}

    				if (%cmdattrs) {
        				foreach my $attr (keys %cmdattrs) {
            				$spotcmd .= "-a $attr=$cmdattrs{$attr} ";
        				}
    				}
					$spotcmd .= " $imghash{$image}{$restype}";


                    $output = xCAT::Utils->runcmd("$spotcmd", -1);
                    if ($::RUNCMD_RC != 0)
                    {
                        my $rsp;
                        push @{$rsp->{data}},
                          "Could not create NIM resource $imghash{$image}{$restype} on $SNname \n";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                    }
                }    # end  - if spot
            }    # end - if valid NIM res type
        }    # end - for each restype in osimage def
    }    # end - for each image

    return 0;
}

#----------------------------------------------------------------------------

=head3   prermdsklsnode

        Preprocessing for the mkdsklsnode command.

        Arguments:
        Returns:
                0 - OK
                1 - error
				2 - done processing this cmd
        Comments:
=cut

#-----------------------------------------------------------------------------
sub prermdsklsnode
{
    my $callback = shift;

    if (defined(@{$::args}))
    {
        @ARGV = @{$::args};
    }
    else
    {
        &rmdsklsnode_usage($callback);
        return 2;
    }

    # parse the options
    Getopt::Long::Configure("no_pass_through");
    if (
        !GetOptions(
					'b|backupSN'  => \$::BACKUP,
                    'f|force'   => \$::FORCE,
                    'h|help'    => \$::HELP,
                    'i=s'       => \$::opt_i,
					'p|primarySN' => \$::PRIMARY,
                    'verbose|V' => \$::VERBOSE,
                    'v|version' => \$::VERSION,
        )
      )
    {
        &rmdsklsnode_usage($callback);
        return;
    }

    if ($::HELP)
    {
        &rmdsklsnode_usage($callback);
        return 2;
    }

    # display the version statement if -v or --verison is specified
    if ($::VERSION)
    {
        my $version = xCAT::Utils->Version();
        my $rsp;
        push @{$rsp->{data}}, "rmdsklsnode $version\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return 2;
    }

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

	# the first arg should be a noderange - the other should be attr=val
	my @nodelist;
	while (my $a = shift(@ARGV))
	{
		if (!($a =~ /=/))
		{
			@nodelist = &noderange($a, 0);
			last;
		}
	}

	if (scalar(@nodelist) == 0) {
		my $rsp;
		push @{$rsp->{data}}, "A noderange is required.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		&rmdsklsnode_usage($callback);
		return 2;
	}

    return (0, \@nodelist, $type);
}

#----------------------------------------------------------------------------

=head3   rmdsklsnode

        Support for the rmdsklsnode command.

		Remove NIM diskless client definitions.

        Arguments:
        Returns:
                0 - OK
                1 - error
        Comments:

			rmdsklsnode [-V] [-f | --force] {-i image_name} noderange
=cut

#-----------------------------------------------------------------------------
sub rmdsklsnode
{
    my $callback = shift;
    my $nodes    = shift;
    my $subreq   = shift;
    my @nodelist = @$nodes;

    # To-Do
    # some subroutines require a global callback var
    #   - need to change to pass in the callback
    #   - just set global for now
    $::callback = $callback;

    if (defined(@{$::args}))
    {
        @ARGV = @{$::args};
    }
    else
    {
        &rmdsklsnode_usage($callback);
        return 2;
    }

    my $Sname = xCAT::InstUtils->myxCATname();
    chomp $Sname;

    # parse the options
    if (
        !GetOptions(
                    'f|force'   => \$::FORCE,
                    'h|help'    => \$::HELP,
                    'i=s'       => \$::opt_i,
                    'verbose|V' => \$::VERBOSE,
                    'v|version' => \$::VERSION,
        )
      )
    {
        &rmdsklsnode_usage($callback);
        return 1;
    }

    if (!(@nodelist))
    {

        # error - must have list of nodes
        &rmdsklsnode_usage($callback);
        return 1;
    }

	#now run the begin part of the prescripts
	#the call is distrubuted to the service node already, so only need 
	#	to handles my own children
	$errored=0;
	$subreq->({command=>['runbeginpre'], node=>\@nodelist, arg=>["remove", '-l']},\&pass_along);
	if ($errored) { 
	    my $rsp;
	    $rsp->{errorcode}->[0]=1;
	    $rsp->{error}->[0]="Failed in running begin prescripts.\n";
	    $callback->($rsp);
	    return 1; 
	}

    # for each node
    my @nodesfailed;
    my $error;
    foreach my $node (@nodelist)
    {

        my $nodename;
        my $name;
        ($name = $node) =~ s/\..*$//;    # always use short hostname
        $nodename = $name;
        if ($::opt_i)
        {
            $nodename = $name . "_" . $::opt_i;
        }

        # see if the node is running
        my $mstate =
          xCAT::InstUtils->get_nim_attr_val($nodename, "Mstate", $callback,
                                            $Sname, $subreq);

        # if it's not in ready state then
        if (defined($mstate) && ($mstate =~ /currently running/))
        {
            if ($::FORCE)
            {

                if ($::VERBOSE)
                {
                    my $rsp;
                    push @{$rsp->{data}}, "Shutting down node \'$nodename\'";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }

                # shut down the node
                my $scmd = "shutdown -F &";
                my $output;
                $output =
                  xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nodename,
                                        $scmd, 0);
            }
            else
            {

                # don't remove the def
                my $rsp;
                push @{$rsp->{data}},
                  "Node \'$nodename\' is currently in running state.  The NIM definition will not be removed.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                $error++;
                push(@nodesfailed, $nodename);
                next;
            }
        }

        if ($::VERBOSE)
        {
            my $rsp;
            push @{$rsp->{data}}, "Resetting node \'$nodename\'";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }

        # nim -Fo reset c75m5ihp05_53Lcosi
        my $cmd = "nim -o reset -a force=yes $nodename  >/dev/null 2>&1";
        my $output;

        $output = xCAT::Utils->runcmd("$cmd", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            if ($::VERBOSE)
            {
                push @{$rsp->{data}},
                  "Could not reset the NIM machine definition for \'$nodename\'.\n";
                push @{$rsp->{data}}, "$output";
            }
            xCAT::MsgUtils->message("E", $rsp, $callback);
            $error++;
            push(@nodesfailed, $nodename);
            next;
        }

        if ($::VERBOSE)
        {
            my $rsp;
            push @{$rsp->{data}},
              "Deallocating resources for node \'$nodename\'";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }

        $cmd = "nim -Fo deallocate -a subclass=all $nodename  >/dev/null 2>&1";
        $output = xCAT::Utils->runcmd("$cmd", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            if ($::VERBOSE)
            {
                push @{$rsp->{data}},
                  "Could not deallocate resources for the NIM machine definition \'$nodename\'.\n";
                push @{$rsp->{data}}, "$output";
            }
            xCAT::MsgUtils->message("E", $rsp, $callback);
            $error++;
            push(@nodesfailed, $nodename);
            next;
        }

        if ($::VERBOSE)
        {
            my $rsp;
            push @{$rsp->{data}},
              "Removing the NIM definition for node \'$nodename\'";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }

        $cmd = "nim -Fo remove $nodename  >/dev/null 2>&1";
        $output = xCAT::Utils->runcmd("$cmd", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            if ($::VERBOSE)
            {
                push @{$rsp->{data}},
                  "Could not remove the NIM machine definition \'$nodename\'.\n";
                push @{$rsp->{data}}, "$output";
            }
            xCAT::MsgUtils->message("E", $rsp, $callback);
            $error++;
            push(@nodesfailed, $nodename);
            next;
        }

    }    # end - for each node
	my  $retcode=0;
    if ($error)
    {
        my $rsp;
        push @{$rsp->{data}},
          "The following NIM machine definitions could NOT be removed.\n";

        foreach my $n (@nodesfailed)
        {
            push @{$rsp->{data}}, "$n";
        }
        xCAT::MsgUtils->message("E", $rsp, $callback);
        $retcode = 1;
    }
    else
    {
        my $rsp;
        push @{$rsp->{data}},
          "NIM machine definitions were successfully removed.";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }


    #now run the end part of the prescripts
    #the call is distrubuted to the service node already, so only need to handles my own children
    $errored=0;
    if (@nodesfailed > 0) {
	my @good_nodes=();
	foreach my $node (@nodelist) {
	    if (!grep(/^$node$/, @nodesfailed)) {
                 push(@good_nodes, $node);
            }
        }    
        $subreq->({command=>['runendpre'],
                      node=>\@good_nodes,
                      arg=>["remove", '-l']},\&pass_along);
    } else {
        $subreq->({command=>['runendpre'],
                node=>\@nodelist,
                arg=>["remove", '-l']},\&pass_along);
    }
    if ($errored) { 
	my $rsp;
	$rsp->{errorcode}->[0]=1;
	$rsp->{error}->[0]="Failed in running end prescripts.\n";
	$callback->($rsp);
	return 1; 
    }

    return  $retcode;

}

#----------------------------------------------------------------------------

=head3  mkdsklsnode_usage

=cut

#-----------------------------------------------------------------------------

sub mkdsklsnode_usage
{
    my $callback = shift;

    my $rsp;
    push @{$rsp->{data}},
      "\n  mkdsklsnode - Use this xCAT command to define and initialize AIX \n\t\t\tdiskless nodes.";
    push @{$rsp->{data}}, "  Usage: ";
    push @{$rsp->{data}}, "\tmkdsklsnode [-h | --help ]";
    push @{$rsp->{data}}, "or";
    push @{$rsp->{data}},
      "\tmkdsklsnode [-V|--verbose] [-f|--force] [-n|--newname] \n\t\t[-i image_name] [-l location] [-p|--primarySN] [-b|--backupSN]\n\t\tnoderange [attr=val [attr=val ...]]\n";
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
    push @{$rsp->{data}},
      "\n  rmdsklsnode - Use this xCAT command to remove AIX/NIM diskless client definitions.";
    push @{$rsp->{data}}, "  Usage: ";
    push @{$rsp->{data}}, "\trmdsklsnode [-h | --help ]";
    push @{$rsp->{data}}, "or";
    push @{$rsp->{data}},
      "\trmdsklsnode [-V|--verbose] [-f|--force] {-i image_name}\n\t\t[-p|--primarySN] [-b|--backupSN]  noderange";
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
    push @{$rsp->{data}},
      "\n  mknimimage - Use this xCAT command to create xCAT osimage definitions \n\t\tand related AIX/NIM resources. The command can also be used \n\t\tto update an existing AIX diskless image(SPOT).\n";
    push @{$rsp->{data}}, "  Usage: ";
    push @{$rsp->{data}}, "\tmknimimage [-h | --help]";
    push @{$rsp->{data}}, "or";
    push @{$rsp->{data}},
      "\tmknimimage [-V] -u osimage_name [attr=val [attr=val ...]]";
    push @{$rsp->{data}}, "or";
    push @{$rsp->{data}},
      "\tmknimimage [-V] [-f|--force] [-t nimtype] [-m nimmethod]\n\t\t[-r|--sharedroot] [-D|--mkdumpres] [-l <location>]\n\t\t[-s image_source] [-i current_image] [-p|--cplpp] [-t nimtype]\n\t\t[-m nimmethod] [-n mksysbnode] [-b mksysbfile] osimage_name\n\t\t[attr=val [attr=val ...]]\n";
    xCAT::MsgUtils->message("I", $rsp, $callback);
    return 0;
}

#----------------------------------------------------------------------------

=head3  chkosimage_usage

=cut

#-----------------------------------------------------------------------------
sub chkosimage_usage
{
	my $callback = shift;

	my $rsp;
	push @{$rsp->{data}}, "\n  chkosimage - Check an xCAT osimage.";
	push @{$rsp->{data}}, "  Usage: ";
	push @{$rsp->{data}}, "\tchkosimage [-h | --help]";
	push @{$rsp->{data}}, "or";
	push @{$rsp->{data}}, "\tchkosimage [-V] [-c|--clean] image_name\n";
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
    push @{$rsp->{data}},
      "\n  rmnimimage - Use this xCAT command to remove an xCAT osimage definition\n             and associated NIM resources.";
    push @{$rsp->{data}}, "  Usage: ";
    push @{$rsp->{data}}, "\trmnimimage [-h | --help]";
    push @{$rsp->{data}}, "or";
    push @{$rsp->{data}},
      "\trmnimimage [-V] [-f|--force] [-d|--delete] [-M|--managementnode] \n\t\t[-s <servernoderange>] [-x|--xcatdef] image_name\n";
    xCAT::MsgUtils->message("I", $rsp, $callback);
    return 0;
}

#----------------------------------------------------------------------------

=head3  nimnodecust_usage

=cut

#-----------------------------------------------------------------------------

sub nimnodecust_usage
{
    my $callback = shift;

    my $rsp;
    push @{$rsp->{data}},
      "\n  nimnodecust - Use this xCAT command to customize AIX \n\t\t\tstandalone nodes.";
    push @{$rsp->{data}}, "  Usage: ";
    push @{$rsp->{data}}, "\tnimnodecust [-h | --help ]";
    push @{$rsp->{data}}, "or";
    push @{$rsp->{data}},
      "\tnimnodecust [-V] [ -s lpp_source_name ]\n\t\t[-p packages] [-b installp_bundles] noderange [attr=val [attr=val ...]]\n";
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
    push @{$rsp->{data}},
      "\n  nimnodeset - Use this xCAT command to initialize AIX \n\t\t\tstandalone nodes.";
    push @{$rsp->{data}}, "  Usage: ";
    push @{$rsp->{data}}, "\tnimnodeset [-h | --help ]";
    push @{$rsp->{data}}, "or";
    push @{$rsp->{data}},
      "\tnimnodeset [-V|--verbose] [-f|--force] [ -i osimage_name]\n\t\t[-l location] [-p|--primarySN] [-b|--backupSN] noderange \n\t\t[attr=val [attr=val ...]]\n";
    xCAT::MsgUtils->message("I", $rsp, $callback);
    return 0;
}

#----------------------------------------------------------------------------

=head3  getNodesetStates
       returns the nodeset state for the given nodes. The possible nodeset
           states are: diskless, dataless, standalone and undefined.
    Arguments:
        nodes  --- a pointer to an array of nodes
        states -- a pointer to a hash table. This hash will be filled by this
             function.  The key is the nodeset status and the value is a pointer
             to an array of nodes.
    Returns:
       (return code, error message)
=cut

#-----------------------------------------------------------------------------
sub getNodesetStates
{
    my $noderef = shift;
    if ($noderef =~ /xCAT_plugin::aixinstall/)
    {
        $noderef = shift;
    }
    my @nodes   = @$noderef;
    my $hashref = shift;

    if (@nodes > 0)
    {
        my $nttab  = xCAT::Table->new('nodetype');
        my $nimtab = xCAT::Table->new('nimimage');
        if (!$nttab)  { return (1, "Unable to open nodetype table."); }
        if (!$nimtab) { return (1, "Unable to open nimimage table."); }

        my %nimimage  = ();
        my $nttabdata =
          $nttab->getNodesAttribs(\@nodes, ['node', 'profile', 'provmethod']);
        foreach my $node (@nodes)
        {
            my $tmp1 = $nttabdata->{$node}->[0];
            my $stat;
            if ($tmp1)
            {
                my $profile;
                if ($tmp1->{provmethod})
                {
                    $profile = $tmp1->{provmethod};
                }
                elsif ($tmp1->{profile})
                {
                    $profile = $tmp1->{profile};
                }

                if (!exists($nimimage{$profile}))
                {
                    (my $tmp) =
                      $nimtab->getAttribs({'imagename' => $profile}, 'nimtype');
                    if (defined($tmp)) {
                        $nimimage{$profile} = $tmp->{nimtype};
                    }

                    else { $nimimage{$profile} = "undefined"; }
                }
                $stat = $nimimage{$profile};
            }
            else { $stat = "undefined"; }
            if (exists($hashref->{$stat}))
            {
                my $pa = $hashref->{$stat};
                push(@$pa, $node);
            }
            else
            {
                $hashref->{$stat} = [$node];
            }
        }
        $nttab->close();
        $nimtab->close();
    }
    return (0, "");

}

#-------------------------------------------------------------------------------

=head3   getNodesetState
       get current nodeset stat for the given node.
    Arguments:
        nodes -- node name.
    Returns:
       nodesetstate 

=cut

#-------------------------------------------------------------------------------
sub getNodesetState
{
    my $node   = shift;
    my $state  = "undefined";
    my $nttab  = xCAT::Table->new('nodetype');
    my $nimtab = xCAT::Table->new('nimimage');
    if ($nttab && $nimtab)
    {
        my $tmp1 = $nttab->getNodeAttribs($node, ['profile', 'provmethod']);
        if ($tmp1 && ($tmp1->{provmethod}) || $tmp1->{profile})
        {
            my $profile;
            if ($tmp1->{provmethod})
            {
                $profile = $tmp1->{provmethod};
            }
            elsif ($tmp1->{profile})
            {
                $profile = $tmp1->{profile};
            }
            my $tmp2 =
              $nimtab->getAttribs({'imagename' => $profile}, 'nimtype');
            if (defined($tmp2)) { $state = $tmp2->{nimtype}; }
        }
        $nttab->close();
        $nimtab->close();
    }

    return $state;
}

#-------------------------------------------------------------------------------

=head3   update_spot_sw
	   			Update the NIM spot resource for diskless images
				- on NIM primary only
				- install the additional software specified in the NIM
					installp_bundle resources
				- install the additional software specified by the 
					fileset names
				- use installp flags if specified
				- uses bnds, filesets and flags from osimage def or
					command line
   Arguments:
		   
   Returns:
			0 - OK
			1 - error

   Comments:
			This uses the NIM "nim -o cust" command.
	Note - this assumes bnd and fileset lists are comma separated!
=cut

#-------------------------------------------------------------------------------
sub update_spot_sw
{
    my $callback  = shift;
    my $spotname  = shift;
    my $lppsource = shift;
    my $nimprime  = shift;
    my $bndls     = shift;
    my $otherpkgs = shift;
    my $iflags    = shift;
    my $rflags    = shift;
    my $eflags    = shift;
    my $subreq    = shift;

    my @bndlnames;

    # if installp bundles are provided make sure they are defined
    if ($bndls)
    {

        # get a list of defined installp_bundle resources
        my $cmd =
          qq~/usr/sbin/lsnim -t installp_bundle | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
        my @bndresources =
          xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cmd, 1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}},
              "Could not get NIM installp_bundle resource definitions.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }

        # see if the NIM installp_bundle resources are defined
        @bndlnames = split(',', $bndls);
        foreach my $bnd (@bndlnames)
        {
            chomp $bnd;
            if (!grep(/^$bnd$/, @bndresources))
            {
                my $rsp;
                push @{$rsp->{data}},
                  "The installp_bundle resource \'$bnd' is not defined to NIM.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
        }
    }    # end - checking bundles

# It's decided to handle install_bundle file by xCAT itself, not using nim -o cust anymore
# nim installs RPMs first then installp fileset, it causes perl-Net_SSLeay.pm pre-install
# verification failed due to openssl not installed.

    # do installp_bundles - if any
    # install installp/RPM without nim, use xcatchroot

    # need pkg source
    my $spotloc = &get_res_loc($spotname, $callback);
    if (!defined($spotloc))
    {
        my $rsp;
        push @{$rsp->{data}},
          "Could not get the location for $spotloc.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    # get lpp_source location in chroot env
    # such as /install/nim/spot/61Ldskls_test/usr/lpp/bos/inst_root/lpp_source
    my $chroot_lpploc = $spotloc . "/lpp/bos/inst_root/lpp_source";
    my $chroot_rpmloc = $chroot_lpploc . "/RPMS/ppc";
    my $chroot_epkgloc = $chroot_lpploc . "/emgr/ppc";
      
    if ($::VERBOSE)
    {
        my $rsp;
        push @{$rsp->{data}}, "NIM lpp_resource location in chroot env: \'$chroot_lpploc\'.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }
    
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}},
          "Could not get NIM lpp_source resource location in chroot env.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }
      
    if (scalar(@bndlnames) > 0)
    {
        # do installp/RPM install for each bndls
        foreach my $bndl (@bndlnames)
        {
            # generate installp list from bndl file

            # get bndl location
            my $bndlloc = &get_res_loc($bndl, $callback);
            if (!defined($bndlloc))
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not get the location for $bndl.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

            # construct tmp file to hold the pkg list.
            my ($tmp_installp, $tmp_rpm) = parse_installp_bundle($callback, $bndlloc);

            # use xcatchroot to install sw in SPOT on nimprime.
            
    		# install installp with file first.
			if (defined($tmp_installp) ) {
            	my $rc = update_spot_installp($callback, $chroot_lpploc, $tmp_installp, $iflags, $spotname, $nimprime, $subreq);
            	if ($rc)
            	{
                	#failed to update installp
                	return 1;
            	}

            	# remove tmp file
            	my $cmd = qq~/usr/bin/rm -f $tmp_installp~;
            
            	my $output =
              		xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cmd, 0);   

            	if ($::RUNCMD_RC != 0)
            	{
                	my $rsp;
                	push @{$rsp->{data}},
                  	"Could not run command: $cmd.\n";
                	xCAT::MsgUtils->message("E", $rsp, $callback);
                	return 1;
            	}

        		# - run updtvpkg to make sure installp software
				#       is registered with rpm
				#
				$cmd   = qq~$::XCATROOT/bin/xcatchroot -i $spotname "/usr/sbin/updtvpkg"~;
			
            	$output =
              		xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cmd, 0);   

            	if ($::RUNCMD_RC != 0)
            	{
                	my $rsp;
                	push @{$rsp->{data}},
                  		"Could not run command: $cmd.\n";
                	xCAT::MsgUtils->message("E", $rsp, $callback);
                	return 1;
            	}

			}

			# then to install RPMs.
			if (defined($tmp_rpm) ) {
            	unless (open(RFILE, "<$tmp_rpm"))
            	{
                	my $rsp;
                	push @{$rsp->{data}}, "Could not open $tmp_rpm for reading.\n";
                	xCAT::MsgUtils->message("E", $rsp, $callback);
                	return 1;
            	}

            	my @rlist = <RFILE>;
            	close(RFILE);
            
            	my $rc = update_spot_rpm($callback, $chroot_rpmloc, \@rlist,
                                          $rflags, $spotname, $nimprime, $subreq);
            	if ($rc)
            	{
                	#failed to update RPM
                	return 1;
            	}
            
            	# remove tmp file
            	my $cmd = qq~/usr/bin/rm -f $tmp_rpm~;

            	my $output =
              		xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cmd, 0);   

            	if ($::RUNCMD_RC != 0)
            	{
                	my $rsp;
                	push @{$rsp->{data}},
                  		"Could not run command: $cmd.\n";
                	xCAT::MsgUtils->message("E", $rsp, $callback);
                	return 1;
            	}
			}
        }
    }
    
    # do the otherpkgs - if any
    # otherpkgs may include installp, rpm and epkg.
    if (defined($otherpkgs))
    {
        # get pkg list to be updated
        my ($i_pkgs, $r_pkgs, $epkgs) = parse_otherpkgs($callback, $otherpkgs);

        # 1. update installp in spot
        if (scalar @$i_pkgs)
        {
            # put installp list into tmp file
            my $tmp_installp = "/tmp/tmp_installp";

            unless (open(IFILE, ">$tmp_installp"))
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not open $tmp_installp for writing.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

            foreach (@$i_pkgs)
            {
                print IFILE $_ . "\n";
            }
            close(IFILE);

            my $rc = update_spot_installp($callback, $chroot_lpploc, $tmp_installp,
                                          $iflags, $spotname, $nimprime, $subreq);
            if ($rc)
            {
                #failed to update installp
                return 1;
            }

            # remove tmp file
            my $cmd = qq~/usr/bin/rm -f $tmp_installp~;
            
            my $output =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cmd, 0);   

            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not run command: $cmd.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
        }
        
        # 2. update rpm in spot
        if (scalar @$r_pkgs)
        {
            my $rc = update_spot_rpm($callback, $chroot_rpmloc, \@$r_pkgs,
                                          $rflags, $spotname, $nimprime, $subreq);
            if ($rc)
            {
                #failed to update RPM
                return 1;
            }
        }
        
        # 3. update epkg in spot
        if (scalar @$epkgs)
        {
            # put epkg list into tmp file
            my $tmp_epkg = "/tmp/tmp_epkg";

            unless (open(FILE, ">$tmp_epkg"))
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not open $tmp_epkg for writing.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

            foreach (@$epkgs)
            {
                print FILE $_ . "\n";
            }
            close(FILE);

            my $rc = update_spot_epkg($callback, $chroot_epkgloc, $tmp_epkg,
                                          $eflags, $spotname, $nimprime, $subreq);
            if ($rc)
            {
                #failed to update epkgs
                return 1;
            }

            # remove tmp file
            my $cmd = qq~/usr/bin/rm -f $tmp_epkg~;
            
            my $output =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cmd, 0);   

            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not run command: $cmd.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
        }
    }
    # end otherpkgs

    return 0;
}

#-------------------------------------------------------------------------------

=head3   sync_spot_files

	Update a NIM SPOT resource by synchronizing configurations files listed
	in an xCAT synclist file.

   	Arguments:

  	Returns:
	  0 - OK
	  1 - error

 	Comments:

=cut

#-------------------------------------------------------------------------------

sub sync_spot_files
{
    my $callback  = shift;
    my $imagename = shift;
    my $nimprime  = shift;
    my $syncfile  = shift;
    my $spot_name = shift;
    my $subreq    = shift;

    #  spot location is - ex. /install/nim/spot/61H39Adskls/usr
    #  dskls nodes /usr is mounted /install/nim/spot/61H39Adskls/usr
    #  root in spot is /install/nim/spot/61H38dskls/usr/lpp/bos/inst_root
    #  inst_root is used to populate nodes / when dskls nodes
    #	are initialized - node root dir is mounted to diskless node
    # if file is in /usr then goes to spot location
    # if not then it goes in the path of inst_root
    #   - add file dest path to usr or inst_root path

    # get location of spot dirs
    my $lcmd =
      qq~/usr/sbin/lsnim -a location $spot_name | /usr/bin/grep location 2>/dev/null~;
    my $usrloc =
      xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $lcmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not run lsnim command: \'$lcmd\'.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }
    $usrloc =~ s/\s*location = //;
    chomp($usrloc);

    my $rootloc = "$usrloc/lpp/bos/inst_root";
    chomp $rootloc;

    # process file to get list of files to copy to spot
    #  !!!! synclist file is always on MN - but files contained in list
    #	must have been copied to the nimprime

    # TODO  - need to support auotmatically copying files to nimprime if needed

    unless (open(SYNCFILE, "<$syncfile"))
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not open $syncfile.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    while (my $line = <SYNCFILE>)
    {
        chomp $line;
        if ($line =~ /(.+) -> (.+)/)
        {
            my $imageupdatedir;
            my $imageupdatepath;
            my $src_file  = $1;
            my $dest_file = $2;
            $dest_file =~ s/[\s;]//g;
            my @srcfiles = (split ' ', $src_file);
            my $arraysize = scalar @srcfiles;    # of source files on the line
            my $dest_dir;

            # if more than one file on the line then
            # the destination  is a directory
            # else assume a file
            if ($arraysize > 1)
            {
                $dest_dir = $dest_file;
                $dest_dir =~ s/\s*//g;    #remove blanks
                $imageupdatedir  .= $dest_dir;    # save the directory
                $imageupdatepath .= $dest_dir;    # path is a directory
            }
            else                                  # only one file
            {                                     # strip off the file
                $dest_dir = dirname($dest_file);
                $dest_dir =~ s/\s*//g;            #remove blanks
                $imageupdatedir  .= $dest_dir;    # save directory
                $imageupdatepath .= $dest_file;   # path to a file
            }

            # add the spot path to the dest_dir
            if ($imageupdatepath =~ /^\/usr/)
            {
                my $dname = dirname($usrloc);
                $imageupdatepath = "$dname" . "$imageupdatepath";
                $imageupdatedir  = "$dname" . "$imageupdatedir";
            }
            else
            {
                $imageupdatepath = "$rootloc" . "$imageupdatepath";
                $imageupdatedir  = "$rootloc" . "$imageupdatedir";
            }

            # make sure the dest dir exists in the spot
            my $mcmd   = qq~/usr/bin/mkdir -p $imageupdatedir~;
            my $output =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime,
                                    $mcmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Command: $mcmd failed.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
            }

            # for each file on the line
            # create rsync cmd
            #  run from management node even if it's not the nim primary
            my $synccmd = "rsync -Lprogtz ";

            my $syncopt = "";
            foreach my $srcfile (@srcfiles)
            {

                $syncopt .= $srcfile;
                $syncopt .= " ";
            }

            $syncopt .= $imageupdatepath;
            $synccmd .= $syncopt;

            # ex. xdsh $nimprime "rsync -Lprogtz /etc/foo /install/nim/spot/.../inst_root/etc"
            if ($::VERBOSE)
            {
                my $rsp;
                push @{$rsp->{data}}, "Running \'$synccmd\' on $nimprime.\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }

            $output =
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime,
                                    $synccmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Command: \'$synccmd\' failed.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
        }
    }

    close SYNCFILE;
    return 0;
}

#-------------------------------------------------------------------------------

=head3   parse_installp_bundle

	generate tmp files for installp filesets and RPMs separately 
	based on NIM installp_bundles
	
	/tmp/tmp_installp, /tmp/tmp_rpm

   	Arguments:
   	callback, installp_bundle location

  	Returns:
	  installp list file, rpm list file

 	Comments:
 	  my ($tmp_installp, $tmp_rpm) = parse_installp_bundle($callback, $bndlloc);

=cut

#-------------------------------------------------------------------------------

sub parse_installp_bundle
{
    
    my $callback = shift;
    my $bndfile = shift;

    # open bundle file
    unless (open(BNDL, "<$bndfile"))
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not open $bndfile.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;                
    }

    # put installp/rpm into an array
    my @ilist;
    my @rlist;

    while (my $line = <BNDL>)
    {
        chomp $line;
        
        if ($line =~ /^I:/)
        {
            my ($junk, $iname) = split(/:/, $line);
            push (@ilist, $iname);
        }
        elsif ($line =~ /^R:/)
        {
            my ($junk, $rname) = split(/:/, $line);
            push (@rlist, $rname);
        }
    }

    close(BNDL);

    # put installp list into tmp file
    my $tmp_installp = "/tmp/tmp_installp";
    my $tmp_rpm = "/tmp/tmp_rpm";

	if ( scalar @ilist) {
    	unless (open(IFILE, ">$tmp_installp"))
    	{
        	my $rsp;
        	push @{$rsp->{data}}, "Could not open $tmp_installp for writing.\n";
        	xCAT::MsgUtils->message("E", $rsp, $callback);
        	return 1;
    	}

    	foreach (@ilist)
    	{
        	print IFILE $_ . "\n";
    	}
    	close(IFILE);
	} else {
		$tmp_installp=undef;
	}

	if ( scalar @rlist) {
    	# put rpm list into tmp file
    	unless (open(RFILE, ">$tmp_rpm"))
    	{
        	my $rsp;
        	push @{$rsp->{data}}, "Could not open $tmp_rpm for writing.\n";
        	xCAT::MsgUtils->message("E", $rsp, $callback);
        	return 1;
    	}
    
    	foreach (@rlist)
    	{
        	print RFILE $_ . "\n";
    	}
    	close(RFILE);
	} else {
		$tmp_rpm=undef;
	}

    return ($tmp_installp, $tmp_rpm);
    
}

#-------------------------------------------------------------------------------

=head3   parse_otherpkgs

    parse the "otherpkgs" string and separate installp/rpm/epkg
	return the ref of each array.

   	Arguments:
   	callback, otherpkgs string

  	Returns:
	  @installp_pkgs, @rpm_pkgs, @epkgs, or undef

 	Comments:
 	  my ($i_pkgs, $r_pkgs, $epkgs) = parse_otherpkgs($callback, $otherpkgs);

=cut

#-------------------------------------------------------------------------------

sub parse_otherpkgs
{
    my $callback = shift;
    my $otherpkgs = shift;

    my @installp_pkgs;
    my @rpm_pkgs;
    my @epkgs;

    my @pkglist = split(/,/, $otherpkgs);

    unless(scalar(@pkglist))
    {
        if ($::VERBOSE)
        {
            my $rsp;
            push @{$rsp->{data}}, "No otherpkgs to update.\n";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }    
        return (undef,undef,undef);
    }

    my ($junk, $pname);
    foreach my $p (@pkglist)
    {
        chomp $p;
        if (($p =~ /\.rpm/) || ($p =~ /R:/))
        {
            if ($p =~ /:/)
            {
                ($junk, $pname) = split(/:/, $p);
            }
            else
            {
                $pname = $p;
            }
            push @rpm_pkgs, $pname;    
        }
        elsif (($p =~ /epkg\.Z/))
        {
            push @epkgs, $p;
        }
        else
        {
            if ($p =~ /:/)
            {
                ($junk, $pname) = split(/:/, $p);
            }
            else
            {
                $pname = $p;
            }
            push @installp_pkgs, $pname;    
        }
        
    }

    return (\@installp_pkgs, \@rpm_pkgs, \@epkgs);
}

#-------------------------------------------------------------------------------

=head3   update_spot_installp

	   			Update the NIM spot resource for diskless images
				- on NIM primary only
				- install installp filesets included in a listfile
				- use installp flags if specified

   Arguments:
   callback, source_dir, listfile, installp_flags, spotname, niprime, subreq
		   
   Returns:
			0 - OK
			1 - error

   Comments:
			This uses "xcatchroot" and "installp" commands directly.

=cut

#-------------------------------------------------------------------------------
sub update_spot_installp
{
    my $callback   = shift;
    my $source_dir = shift;
    my $listfile   = shift;
    my $installp_flags = shift;
    my $spotname   = shift;
    my $nimprime   = shift;
    my $subreq     = shift;

    if ($::VERBOSE)
    {
        my $rsp;
        push @{$rsp->{data}}, "Installing installp filesets in SPOT $spotname.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }    

    my $icmd = "export INUCLIENTS=1;/usr/sbin/installp ";

    # these installp flags can be used with -d
    if ($installp_flags =~ /l|L|i|A|a/)
    {
        $icmd .= "-d $source_dir ";
    }

    $icmd .= "$installp_flags -f $listfile";

    # run icmd!
    my $cmd = qq~$::XCATROOT/bin/xcatchroot -i $spotname "$icmd"~;

    my $output =
      xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cmd, 0);   

    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}},
          "Could not install installp packages in SPOT $spotname.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    if ($::VERBOSE)
    {
        my $rsp;
        push @{$rsp->{data}}, "Completed Installing installp filesets in SPOT $spotname.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }    

    return 0;
}

#-------------------------------------------------------------------------------

=head3   update_spot_rpm

	   			Update the NIM spot resource for diskless images
				- on NIM primary only
				- install rpm pkgs included in an array
				- use rpm flags if specified

   Arguments:
   callback, source_dir, ref_rlist, rpm_flags, spotname, niprime, subreq
		   
   Returns:
			0 - OK
			1 - error

   Comments:
			This uses "xcatchroot" and "rpm" commands directly.

=cut

#-------------------------------------------------------------------------------
sub update_spot_rpm
{
    my $callback   = shift;
    my $source_dir = shift;
    my $ref_rlist  = shift;
    my $rpm_flags  = shift;
    my $spotname   = shift;
    my $nimprime    = shift;
    my $subreq     = shift;

    if ($::VERBOSE)
    {
        my $rsp;
        push @{$rsp->{data}}, "Installing RPM packages in SPOT $spotname.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }    
    
    my $rpmpkgs;
    foreach my $line (@$ref_rlist)
    {
        chomp $line;
        $rpmpkgs .= "$line ";
        
    }
    
    my $cdcmd = qq~cd $source_dir;~;
    my $cmd = qq~$::XCATROOT/bin/xcatchroot -i $spotname "$cdcmd export INUCLIENTS=1; /usr/bin/rpm $rpm_flags $rpmpkgs"~;

    my $output =
      xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cmd, 0);   

    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}},
          "Could not install rpm packages in SPOT $spotname.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    if ($::VERBOSE)
    {
        my $rsp;
        push @{$rsp->{data}}, "Completed Installing RPM packages in SPOT $spotname.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }    

    return 0;
}

#-------------------------------------------------------------------------------

=head3   update_spot_epkg

	   			Update the NIM spot resource for diskless images
				- on NIM primary only
				- install epkgs included in an array
				- use emgr flags if specified

   Arguments:
   callback, source_dir, $listfile, eflags, spotname, niprime, subreq
		   
   Returns:
			0 - OK
			1 - error

   Comments:
			This uses "xcatchroot" and "emgr" commands directly.
   Note: assume the *.epkg.Z is copied to lpp_source dir already!	

=cut

#-------------------------------------------------------------------------------
sub update_spot_epkg
{
    my $callback   = shift;
    my $source_dir = shift;
    my $listfile  = shift;
    my $eflags  = shift;
    my $spotname   = shift;
    my $nimprime    = shift;
    my $subreq     = shift;
    
    if ($::VERBOSE)
    {
        my $rsp;
        push @{$rsp->{data}}, "Installing the interim fix in SPOT $spotname.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }
    
    my $cdcmd = qq~cd $source_dir;~;
    my $ecmd  = qq~/usr/sbin/emgr $eflags -f $listfile~;
    my $cmd = qq~$::XCATROOT/bin/xcatchroot -i $spotname "$cdcmd $ecmd"~;

    my $output =
      xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cmd, 0);   

    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}},
          "Could not install the interim fix in SPOT $spotname.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    if ($::VERBOSE)
    {
        my $rsp;
        push @{$rsp->{data}}, "Completed Installing the interim fixes in SPOT $spotname.\n";
        xCAT::MsgUtils->message("I", $rsp, $callback);
    }    

    return 0;
}

1;
