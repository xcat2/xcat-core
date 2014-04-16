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
use xCAT::SvrUtils;
use xCAT::TableUtils;
use xCAT::NetworkUtils;
use xCAT::ServiceNodeUtils;
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

    #if already preprocessed, go straight to request 
    if (   (defined($req->{_xcatpreprocessed}))
        && ($req->{_xcatpreprocessed}->[0] == 1))
    {
        return [$req];
    }

    my $nodes   = $req->{node}; # this may not be the list of nodes we need!
    my $service = "xcat";
    my @requests;
    my $lochash;
    my $nethash;
    my $nodehash;
    my $imagehash;
    my $attrs;
    my $locs;
    $::MOUNT = "mount";

    # get this systems name as known by xCAT management node
    my $Sname = xCAT::InstUtils->myxCATname();
    chomp $Sname;

    # get the name of the primary NIM server
    #	- either the NIMprime attr of the site table or the management node
    my $nimprime = xCAT::InstUtils->getnimprime();
    chomp $nimprime;
    if (!defined($nimprime))
    {
       my $rsp={};
       $rsp->{error}->[0] = "Could not determine nimprime. Check if nimprime defined in site table or site table master is not resolvable to the MN name.";
       xCAT::MsgUtils->message("E", $rsp, $cb,1);
       return undef;
    }
    my $nimprimeip = xCAT::NetworkUtils->getipaddr($nimprime);
    if ($nimprimeip =~ /:/) #IPv6
    {
        $::IPv6 = 1;
    }

    my @tmp = xCAT::TableUtils->get_site_attribute("useNFSv4onAIX");
    my $nfsv4entry = $tmp[0];
    if( defined ($nfsv4entry) )
    {
        if ($nfsv4entry =~ /1|Yes|yes|YES|Y|y/)
        { 
            $::NFSv4 = 1;
            $::MOUNT = "mount -o vers=4";
        }
    }
    #$sitetab->close;

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
        my ($rc, $imagehash, $servers, $mnsn) = &prermnimimage($cb, $sub_req);
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
            my %allsn;
            foreach my $sn (@{$mnsn}) # convert array to hash
            {
                $allsn{$sn} = 1;
            }
            
            foreach my $snkey (@{$servers})
            {
                my $reqcopy = {%$req};
                $reqcopy->{'_xcatdest'} = $snkey;

                # put servicenode list in req, will use it in rmnimimage().
                if(%allsn)
                {
                    # add tags to the hash keys that start with a number
                    xCAT::InstUtils->taghash(\%allsn);
                    $reqcopy->{'nodehash'} = \%allsn;
                }

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
			$snodes = xCAT::ServiceNodeUtils->getSNformattedhash($mynodes, $service, "MN", $type);

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
			$sn = xCAT::ServiceNodeUtils->getSNformattedhash($nodes, $service, "MN");
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
			$snodes = xCAT::ServiceNodeUtils->getSNformattedhash($mynodes, $service, "MN", $type);
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
        
    my @nfsv4entries = xCAT::TableUtils->get_site_attribute("useNFSv4onAIX");
    my $tmp = $nfsv4entries[0];
    if ( defined($tmp) && $tmp =~ /1|Yes|yes|YES|Y|y/)
    { 
        $::NFSv4 = 1;
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
        ($ret, $msg) = &rmnimimage($callback, $imagehash, $nodehash, $sub_req);
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

    if ( defined ($::args) && @{$::args} ) 
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
					'd|defonly'   => \$::DEFONLY,
                    'f|force'   => \$::FORCE,
                    'h|help'    => \$::HELP,
                    'i=s'       => \$::OSIMAGE,
					'l=s'       => \$::opt_l,
					'p|primarySN' => \$::PRIMARY,
                    'verbose|V' => \$::VERBOSE,
                    'v|version' => \$::VERSION,
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
    my $sharedinstall = "no";
    if (!xCAT::InstUtils->is_me($nimprime))
    {
        &make_SN_resource($callback,   \@nodelist, \@image_names,
                          \%imagehash, \%lochash,  \%nethash, \%nimhash,
                          $sharedinstall, $Sname, $subreq);
    }

    #
    # See if we need to create a resolv_conf resource
    #
    my %resolv_conf_hash = &chk_resolv_conf($callback, \%objhash, \@nodelist, \%nethash, \%imagehash, \%attrs, \%nodeosi, $subreq);
    if ( !%resolv_conf_hash ){
        #my $rsp;
        #push @{$rsp->{data}}, "Could not check NIM resolv_conf resource.\n";
        #xCAT::MsgUtils->message("E", $rsp, $callback);
    }

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

    $error = 0;
    foreach my $node (@nodelist)
    {
        # set the NIM machine type
        my $type = "standalone";
        if ($imagehash{$image_name}{nimtype})
        {
            $type = $imagehash{$image_name}{nimtype};
        }
        chomp $type;

        # get the image name to use for this node
        my $image_name = $nodeosi{$node};
        chomp $image_name;


        # define the node if it doesn't exist
        if (!grep(/^$node$/, @machines))
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

			my $foundneterror;
			if (!$nethash{$node}{'mask'} )
			{
				my $rsp;
                push @{$rsp->{data}},"$Sname: Missing network mask for node \'$node\'.\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
				$foundneterror++;
			}
			if (!$nethash{$node}{'gateway'})
			{
				my $rsp;
                push @{$rsp->{data}},"$Sname: Missing network gateway for node \'$node\'.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                $foundneterror++;
			}	
			if (!$imagehash{$image_name}{spot})
			{
                my $rsp;
                push @{$rsp->{data}},"$Sname: Missing spot name for osimage \n'$image_name\'.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                $foundneterror++;
            }
			if ($foundneterror) {
				$error++;
                push(@nodesfailed, $node);
                next;
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

            # need a short hostname to define in NIM
            my $nodeshorthost;
            ($nodeshorthost = $node) =~ s/\..*$//;
            chomp $nodeshorthost;

            my $nim_name = $nodeshorthost;

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
            my $output = xCAT::Utils->runcmd("$defcmd", -1);
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



        # check if node is in ready state
        my $shorthost;
        ($shorthost = $node) =~ s/\..*$//;
        chomp $shorthost;
       
        if ($::FORCE)
        {
            if ($::VERBOSE)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "$Sname: Reseting NIM definition for $shorthost.\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }

            my $rcmd =
              "/usr/sbin/nim -Fo reset -a force=yes $shorthost;/usr/sbin/nim -Fo deallocate -a subclass=all $shorthost";
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
        
        # need to pass in this server name
        my $cstate = xCAT::InstUtils->get_nim_attr_val($shorthost, "Cstate", $callback, "$Sname", $subreq);
        if (defined($cstate) && (!($cstate =~ /ready/)))
        {
            my $rsp;
            push @{$rsp->{data}},
              "$Sname: The NIM machine named $shorthost is not in the ready state and cannot be initialized. Use -f flag to forcely initialize it.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            $error++;
            push(@nodesfailed, $node);
            next;

        }

        # set the NIM machine type
        $type = "standalone";
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

        # read machines again to make sure they have been defined
        my $cmd =
          qq~/usr/sbin/lsnim -c machines | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
        my @updatedmachines = xCAT::Utils->runcmd("$cmd", -1);

        if (!grep(/^$nim_name$/, @updatedmachines))
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
        $initcmd = "/usr/sbin/nim -Fo bos_inst $arg_string $nim_name 2>&1";

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
        @allservers = xCAT::ServiceNodeUtils->getAllSN();

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

	my $rpm_flags = " -Uvh ";
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

		#  don't remove spots if SNs are using shared file system
		#   mkdsklsnode will take care of copying out the updated spot
		# check the sharedinstall attr
		my @sharedinstalls=xCAT::TableUtils->get_site_attribute('sharedinstall');
		my $sharedinstall = $sharedinstalls[0];
		chomp $sharedinstall;

	  	if ( $sharedinstall ne "sns" )
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

            	my $rmcmd = qq~nim -Fo remove $spot_name 2>/dev/null~;
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
	    		if ( $SRname ) {
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

            				my $rmcmd = qq~nim -Fo remove $SRname 2>/dev/null~;
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

        if ( defined ($::args) && @{$::args} ) 
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

		#  Get a list of the defined NIM installp_bundle resources
		#
		my $cmd = qq~/usr/sbin/lsnim -t installp_bundle | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
		my @instp_bnds = xCAT::Utils->runcmd("$cmd", -1);
		if ($::RUNCMD_RC != 0)
		{
			my $rsp;
			push @{$rsp->{data}}, "Could not get NIM installp_bundle definitions.";
			xCAT::MsgUtils->message("E", $rsp, $callback);
		}


		foreach my $bnd (@bndlist)
		{
			$bnd =~ s/\s*//g;    # remove blanks

			# make sure the NIM installp_bundle resource is defined
			if (!grep(/^$bnd$/, @instp_bnds) ) {
				next;
			}

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
		if (($pkg =~ /^R:/) || ($pkg =~ /^I:/) || ($pkg =~ /^E:/) )
		{
			my ($junk, $pname) = split(/:/, $pkg);
			push(@install_list, $pname);
		} else {
			push(@install_list, $pkg);
		}

		if (($pkg =~ /^R:/)) {
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
	my $emgr_srcdir = "$lpp_loc/emgr/ppc";

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
	my $ecmd = qq~/usr/bin/ls $emgr_srcdir 2>/dev/null~;
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

			# need both these checks to cover different naming issues
			if ( ($lppfile eq $file) || ($lppfile =~ /^$file/)) {
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
	my $install_dir = xCAT::TableUtils->getInstallDir();

    if ( defined ($::args) && @{$::args} ) 
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
					'c|completeosimage'   => \$::COMPLOS,
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
            chomp $::image_name;  # the name of the osimage to create or update
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


    #  get list of defined xCAT osimage objects
    my @deflist = undef;
    @deflist = xCAT::DBobjUtils->getObjectsOfType("osimage");

    # if our image is already defined get the defnition
    my $is_defined = 0;
    my %imagedef   = undef;  # the $::image_name definition!
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

	# determine the NIMTYPE, METHOD, and SHAREDROOT values
	#	- could be from existing osimage
	if (!$::NIMTYPE) {
		if (($imagedef{$::image_name}{nimtype}) && $::COMPLOS)
        {
			$::NIMTYPE = $imagedef{$::image_name}{nimtype};
		} else {
			if ($::UPDATE) {
				$::NIMTYPE = "diskless";
			} else {
				$::NIMTYPE = "standalone";
			}
		}	
	}

	if (!$::METHOD) {
		if (($imagedef{$::image_name}{nimmethod}) && $::COMPLOS)
		{
			$::METHOD = $imagedef{$::image_name}{nimmethod};
		} else {
			if ($::UPDATE) {
				$::METHOD = "";
			} else {
				if (($::NIMTYPE eq "standalone") && !$::METHOD) {
					$::METHOD = "rte";
				}		
			}
		}
	}

	if (!$::SHAREDROOT) {
		if (($imagedef{$::image_name}{shared_root}) && $::COMPLOS) {
			$::SHAREDROOT++;
		}
	}

	if (!$::opt_s) {
		if (($imagedef{$::image_name}{lpp_source}) && $::COMPLOS) {
			$::opt_s = $imagedef{$::image_name}{lpp_source};
		}
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

        if ($::IPv6)
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
			my @domains = xCAT::TableUtils->get_site_attribute("domain");
			my $domain = $domains[0];
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
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd, 0);
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
              xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd, 0);
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
            $nimcmd = qq~nim -Fo change -a global_export=yes master~;
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

            $nimcmd = qq~nim -Fo change -a nfs_domain=clusters.com master~;
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
            $nimcmd = qq~nim -Fo define -t ent6 -a net_addr=$net -a snm=$mask -a routing1="default $gw" $netname~;
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
            $nimcmd = qq~nim -Fo change -a if2="$netname $hname $linklocaladdr" -a cable_type2=N/A master~;
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

    if ($::NFSv4 || ($::UPDATE && ($::attrres{'nfs_vers'} == 4)))
    {
        my $nimcmd = qq~chnfsdom~;
        my $nimout = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd,0);
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
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not get NFSv4 domain setting.\n";
            if ($::VERBOSE)
            {
                push @{$rsp->{data}}, "$nimout";
            }
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
        # NFSv4 domain is not set yet
        if ($nimout =~ /N\/A/)
        {
            $nimcmd = qq~chnfsdom $domain~;
            $nimout = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd,0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not change NFSv4 domain to $domain.\n";
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

        }
        $nimcmd = qq~lsnim -FZ -a nfs_domain master~;
        $nimout = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd,0);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not get NFSv4 domain setting for nim master.\n";
            if ($::VERBOSE)
            {
                push @{$rsp->{data}}, "$nimout";
            }
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
        # NFSv4 domain is not set to nim master
        if (!$nimout)
        {
            #nim -o change -a nfs_domain=$nfsdom master
            $nimcmd = qq~nim -Fo change -a nfs_domain=$domain master~;
            $nimout = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd,0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not set NFSv4 domain with nim master.\n";
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
    # do diskless spot update - if requested
    #
    if ($::UPDATE)
    {

        if(($::attrres{'nfs_vers'} == 4) && $is_defined)
        {
            # Check site.useNFSv4onAIX
            if(!$::NFSv4)
            {
                my $rsp;
                push @{$rsp->{data}},
                "Setting site.useNFSv4onAIX to yes.\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
                my $cmd = "$::XCATROOT/sbin/chtab key=useNFSv4onAIX site.value=yes";
                my $out = xCAT::Utils->runcmd("$cmd", -1);
		if ($::RUNCMD_RC != 0)
                {
                    my $rsp;
                    push @{$rsp->{data}}, "Unable to set site.useNFSv4onAIX.";
                    push @{$rsp->{data}}, "$out\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
		}
                $::NFSv4 = 1;
            }
            # For standalone image:
            #        lpp_source, spot
            # For non-shared_root image:
            #        lpp_source, spot
            # For shared_root image:
            #        lpp_source, spot
            my @nimrestoupdate = ();
            my @nimresupdated = ();
            if ($imagedef{$::image_name}{nimtype} eq "standalone")
            {
                @nimrestoupdate = ("lpp_source", "spot", "bosinst_data", "installp_bundle", "image_data", "resolv_conf");
            } 
            if (($imagedef{$::image_name}{nimtype} eq "diskless") && $imagedef{$::image_name}{root})
            {
                @nimrestoupdate = ("lpp_source", "spot", "installp_bundle", "root", "paging", "resolv_conf");
            }
            if (($imagedef{$::image_name}{nimtype} eq "diskless") && $imagedef{$::image_name}{shared_root})
            {
                @nimrestoupdate = ("lpp_source", "spot", "installp_bundle", "shared_root", "paging", "resolv_conf");
            }

            foreach my $nimres (@nimrestoupdate)
            {
                my $ninresname = $imagedef{$::image_name}{$nimres};
                if ($ninresname)
                {
                    foreach my $res2update (split /,/, $ninresname)
                    {
                        push @nimresupdated, $res2update;
                        my $nimcmd = qq~nim -Fo change -a nfs_vers=4 $res2update~;
                        my $nimout = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd,0);
                        if ($::RUNCMD_RC != 0)
                        {
                            my $rsp;
                            push @{$rsp->{data}}, "Could not set nfs_vers=4 for resource $res2update.\n";
                            if ($::VERBOSE)
                            {
                                push @{$rsp->{data}}, "$nimout";
                            }
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                            return 1;
                        }
                    }
                }
            }
            if ($::VERBOSE)
            {
                my $strnimresupdated = join(',', @nimresupdated);
                my $rsp;
                push @{$rsp->{data}},
                  "Updated the NIM resources $strnimresupdated with nfs_vers=4.\n";
                xCAT::MsgUtils->message("I", $rsp, $callback);
            }
            return 0;
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

	# don't remove the osimage if the user wants it to be completed
	if (!$::COMPLOS ) {
    	#   if exists and not doing update then remove or return
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
				#  reset %imagedefs
				%imagedef   = undef;
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
			
			# get the osimage def for the -i option osimage
            %::imagedef = xCAT::DBobjUtils->getobjdefs(\%objtype, $callback);
            if (!(%::imagedef))
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not get xCAT image definition.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
        }

		if (!$::COMPLOS) {
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
		}

        #
        # get lpp_source
        #

		if (($imagedef{$::image_name}{lpp_source})  && $::COMPLOS)
		{
			$lpp_source_name=$imagedef{$::image_name}{lpp_source};
		} else {

        	$lpp_source_name = &mk_lpp_source(\%::attrres, $callback);
        	chomp $lpp_source_name;
		}
        $newres{lpp_source} = $lpp_source_name;
        if (!($lpp_source_name))
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
		if (($imagedef{$::image_name}{spot})  && $::COMPLOS)
		{
			$spot_name = $imagedef{$::image_name}{spot};
		} else {
        	$spot_name = &mk_spot($lpp_source_name, \%::attrres, $callback);
		}

        chomp $spot_name;
        $newres{spot} = $spot_name;
        if (!($spot_name))
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

		if (($imagedef{$::image_name}{root})  && $::COMPLOS)
        {
			$root_name = $imagedef{$::image_name}{root};
		}
		if (($imagedef{$::image_name}{shared_root})  && $::COMPLOS)
        {
            $root_name = $imagedef{$::image_name}{shared_root};
        }

		# check the command line attrs 
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

        if ($::SHAREDROOT || $::imagedef{$::opt_i}{shared_root} || $imagedef{$::image_name}{shared_root})
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

		my $dump_name;
		if ($imagedef{$::image_name}{dump} ) {
			$dump_name = $imagedef{$::image_name}{dump};
            $newres{dump} = $dump_name;
		} else {
       		if ($::dodumpold || $::MKDUMP)
        	{
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
        	}  
		} # end dump setup

        #
        # paging res
        #
        my $paging_name;
		if ($imagedef{$::image_name}{paging} ) {
			$paging_name = $imagedef{$::image_name}{paging};
		}
        if ($::attrres{paging})
        {

            # if provided then use it
            $paging_name = $::attrres{paging};
        }

		if (!$paging_name)
        {
			# use the one from the -i osimage or create a new one
        	if ($::opt_i)
        	{

            	# if one is provided in osimage
            	if ($::imagedef{$::opt_i}{paging})
            	{
                	$paging_name = $::imagedef{$::opt_i}{paging};
            	}
        	} else {

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
                    	if (&mknimres($paging_name, $type, $callback, $::opt_l, $junk, \%::attrres) != 0)
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
		}

        chomp $paging_name;
        $newres{paging} = $paging_name;

        # end diskless section
    }
    elsif ($::NIMTYPE eq "standalone")
    {

        # includes rte & mksysb methods

        #
        # create bosinst_data
        #
		if ($imagedef{$::image_name}{bosinst_data}) 
		{
			$bosinst_data_name = $imagedef{$::image_name}{bosinst_data};
		} else {
        	$bosinst_data_name = &mk_bosinst_data(\%::attrres, $callback);
		}
        if (!defined($bosinst_data_name))
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not create bosinst_data definition.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
		chomp $bosinst_data_name;
		$newres{bosinst_data} = $bosinst_data_name;

		#
		#  create a dump res if requested
		#
		if ($imagedef{$::image_name}{dump} ) {
            $dump_name = $imagedef{$::image_name}{dump};
            $newres{dump} = $dump_name;
        } else {

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
            	}   
            	chomp $dump_name;
            	$newres{dump} = $dump_name;
        	}  
		} # end create dump

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
			if (($imagedef{$::image_name}{lpp_source}) && $::COMPLOS)
			{
				$lpp_source_name=$imagedef{$::image_name}{lpp_source};
			} else {
				$lpp_source_name = &mk_lpp_source(\%::attrres, $callback);
			}
	
            if (!defined($lpp_source_name))
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not create lpp_source definition.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
			chomp $lpp_source_name;
			$newres{lpp_source} = $lpp_source_name;
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
            $mksysb_name = &mk_mksysb(\%::attrres, $callback, $subreq);
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
		if (($imagedef{$::image_name}{spot}) && $::COMPLOS)
        {
            $spot_name = $imagedef{$::image_name}{spot};
        } else {
        	$spot_name = &mk_spot($lpp_source_name, \%::attrres, $callback);
		}
        if (!defined($spot_name))
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not create spot definition.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
		chomp $spot_name;
		$newres{spot} = $spot_name;
    } # end standalone set up

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
    if (%::attrres)
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
	my $rootpw = 'cluster';
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

			# secure passwd in verbose mode
			my $tmpv = $::VERBOSE;
			$::VERBOSE = 0;
	
			my $out = xCAT::Utils->runcmd("$pwcmd", -1);
			if ($::RUNCMD_RC != 0)
			{
				my $rsp;
            	push @{$rsp->{data}}, "Unable to set root password.";
				push @{$rsp->{data}}, "$out\n";
            	xCAT::MsgUtils->message("E", $rsp, $callback);
			}
			$::VERBOSE = $tmpv;
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
    my $install_dir = xCAT::TableUtils->getInstallDir();

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
            if ( ($::NFSv4) && (!$attrres{nfs_vers}) )
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
			if ( ($::NFSv4) && (!$attrres{nfs_vers}) )
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
			my @outp;
			my $ccmd;

			# try to find openssh and copy it to the new lpp_source loc
			my $fcmd = "/usr/bin/find $::opt_s -print | /usr/bin/grep openssh.base";
			@outp = xCAT::Utils->runcmd("$fcmd", -1);
			if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not find openssh file sets in source location.\n";
                xCAT::MsgUtils->message("W", $rsp, $callback);
            }

        	foreach my $line (@outp)
        	{
    			chomp $line;
    			my $dir = dirname($line);
    			$ccmd = "/usr/bin/cp $dir/openssh* $loc/installp/ppc 2>/dev/null";
    			$out = xCAT::Utils->runcmd("$ccmd", -1);
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp;
                    push @{$rsp->{data}}, "Could not copy openssh to $loc/installp/ppc.\n";
                    xCAT::MsgUtils->message("W", $rsp, $callback);
                }    			
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
    my $install_dir = xCAT::TableUtils->getInstallDir();

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
				push @{$rsp->{data}}, " The cpcosi command failed. \n$output\n";
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
            my $cmd = "/usr/sbin/nim -Fo define -t spot -a server=master ";

			# check for relevant cmd line attrs
			my %cmdattrs;
			if ( ($::NFSv4) && (!$attrres{nfs_vers}) )
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
	my $install_dir = xCAT::TableUtils->getInstallDir();

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
            $cmd = "/usr/sbin/nim -Fo define -t bosinst_data -a server=master ";

			# check for relevant cmd line attrs
			my %cmdattrs;
			if ( ($::NFSv4) && (!$attrres{nfs_vers}) )
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
    my @domains = xCAT::TableUtils->get_site_attribute("domain");
    my $domain = $domains[0];
    my @nameserver = xCAT::TableUtils->get_site_attribute("nameservers");
    my $tmp2 = $nameserver[0];

    # convert <xcatmaster> to nameserver IP
    my $nameservers;
    #if ($tmp2->{value} eq '<xcatmaster>')
    if ( defined($tmp2) && $tmp2 eq '<xcatmaster>')
    {
        $nameservers = xCAT::InstUtils->convert_xcatmaster();
    }
    else
    {
        $nameservers = $tmp2;
    }

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
                - undef
                - hash of resolv_conf resource names
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
    my @domains = xCAT::TableUtils->get_site_attribute("domain");
    my $site_domain = $domains[0];

    my @nameserver = xCAT::TableUtils->get_site_attribute("nameservers");
    my $site_nameservers = $nameserver[0];

	# get a list of all domains listed in xCAT network defs
	my @alldomains;
	my $nettab = xCAT::Table->new("networks");
	my @doms = $nettab->getAllAttribs('domain');
	foreach(@doms){
		if ($_->{domain}) {
			push (@alldomains, $_->{domain});
		}
	}
	$nettab->close;

	# add the site domain
	if ($site_domain) {
		if (!grep(/^$site_domain$/, @alldomains)) {
			push (@alldomains, $site_domain);
		}
	}

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
        return undef;
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
		return undef;
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
	my @donedefs;
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

				# make sure to use the short host name or
				#		NIM will be unhappy !
				my ($host, $ip) = xCAT::NetworkUtils->gethostnameandip($server);
                chomp $host;
				chomp $ip;

				if (!$host || !$ip)
				{
					my $rsp = {};
					$rsp->{data}->[0] = "Can not resolve the node $node";
					xCAT::MsgUtils->message("E", $rsp, $callback);
					next;
				}
                push(@nservers, $ip);

				# use convention for res name "<SN>_resolv_conf"
				$resolv_conf_name = $host . "_resolv_conf";
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

		# don't define the same resource again
		if (grep(/^$resolv_conf_name$/, @donedefs)) {
			next;
		}

		#
		# create a new NIM resolv_conf resource - if needed
		#
		if ($create_res) {

            my $fileloc;
            my $loc;
			my @validattrs = ("nfs_vers", "nfs_sec");

   			my $install_dir = xCAT::TableUtils->getInstallDir();
            if ($::opt_l)
            {
				if ($::opt_l =~ /\/$/)
                {
                    $::opt_l =~ s/\/$//; #remove tailing slash if needed
                }
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
			# add all the domains from site and network defs
			#
			chomp $domain;
			my $domainstring = "$domain";
			foreach my $dom (@alldomains) {
				chomp $dom;
                if ($dom ne $domain){
					$domainstring .= " $dom";
				}
			}

			$cmd = qq~echo "search $domainstring" > $filename~;
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

            	$cmd = "/usr/sbin/nim -Fo define -t resolv_conf -a server=master ";
				# check for relevant cmd line attrs
				my %cmdattrs;
				if ( ($::NFSv4) && (!$attrres{nfs_vers}) )
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

				push @donedefs, $resolv_conf_name;

				my $rsp;
				push @{$rsp->{data}}, "Created a new resolv_conf resource called \'$resolv_conf_name\'.\n";
				xCAT::MsgUtils->message("I", $rsp, $callback);
		} else {
                    if ($::NFSv4) {
                        my $cmd = qq~/usr/sbin/lsnim -Z -a nfs_vers $resolv_conf_name 2>/dev/null~;
                        my @result = xCAT::Utils->runcmd("$cmd", -1);
                        if ($::RUNCMD_RC != 0)
                        {
                            my $rsp;
                            push @{$rsp->{data}}, "Could not run lsnim command: \'$cmd\'.\n";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                            return undef;
                        }
                        my $nfsvers;
                        my $nimname;
                        foreach my $l (@result)
                        {

                            # skip comment lines
                            next if ($l =~ /^\s*#/);

                            ($nimname, $nfsvers) = split(':', $l);
                            if ($nfsvers) {
                                last;
                            }
                         }
                         if (!$nfsvers || ($nfsvers eq 3))
                         {
                             my $ecmd = qq~/usr/sbin/rmnfsexp -d $install_dir/nim/resolv_conf/$resolv_conf_name/resolv.conf -B 2>/dev/null~;
                             xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $ecmd,0);
                             my $nimcmd = qq~nim -Fo change -a nfs_vers=4 $resolv_conf_name~;
                             my $nimout = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd,0);
                             if ($::RUNCMD_RC != 0)
                             {
                                 my $rsp;
                                 push @{$rsp->{data}}, "Could not set nfs_vers=4 for resource $resolv_conf_name.\n";
                                 if ($::VERBOSE)
                                 {
                                     push @{$rsp->{data}}, "$nimout";
                                 }
                                 xCAT::MsgUtils->message("E", $rsp, $callback);
                                 return undef;
                             }
                         }
                    } #end if $::NFSv4
                } # end else
            } # end if $create_res
	} # end foreach node

	return %resolv_conf_hash;
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
    my $install_dir = xCAT::TableUtils->getInstallDir();

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
        #my $sitetab = xCAT::Table->new('site');
        #my ($tmp) = $sitetab->getAttribs({'key' => 'domain'}, 'value');
        #my $domain = $tmp->{value};
        my @domains = xCAT::TableUtils->get_site_attribute("domain");
        my $domain = $domains[0];
        #my ($tmp2) = $sitetab->getAttribs({'key' => 'nameservers'}, 'value');
        my @nameserver = xCAT::TableUtils->get_site_attribute("nameservers");
        my $tmp2 = $nameserver[0];
        # convert <xcatmaster> to nameserver IP
        my $nameservers;
        if ($tmp2 eq '<xcatmaster>')
        {
            $nameservers = xCAT::InstUtils->convert_xcatmaster();
        }
        else
        {
            $nameservers = $tmp2;
        }
        #$sitetab->close;

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
                  "/usr/sbin/nim -Fo define -t resolv_conf -a server=master ";

				# check for relevant cmd line attrs
				my %cmdattrs;
				if ( ($::NFSv4) && (!$attrres{nfs_vers}) )
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
	my $sub_req = shift;

	my %attrres;
	if ($attrs) {
		%attrres = %{$attrs};
	}

	my $snode;

	my @validattrs = ("verbose", "nfs_vers", "nfs_sec", "dest_dir", "group", "source", "size_preview", "exclude_files", "mksysb_flags", "mk_image");

    my $mksysb_name = $::image_name . "_mksysb";
	my $install_dir = xCAT::TableUtils->getInstallDir();
	
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
			my $rsp;
			push @{$rsp->{data}},  "Creating a NIM mksysb resource called \'$mksysb_name\'.  This could take a while.\n";
			xCAT::MsgUtils->message("I", $rsp, $callback);

            if ($::MKSYSBNODE)
            {

				# get the server for the node
				my $nrtab = xCAT::Table->new('noderes');
				my @nodes;
				push @nodes, $::MKSYSBNODE;

				my $nrhash;
				if ($nrtab)
				{
					$nrhash = $nrtab->getNodesAttribs(\@nodes, ['servicenode']);
				}

				my ($remote_server, $junk) = (split /,/, $nrhash->{$::MKSYSBNODE}->[0]->{'servicenode'});
				$nrtab->close();
	
				my $nimprime = xCAT::InstUtils->getnimprime();
				chomp $nimprime;

				if ($remote_server) {
					$snode = $remote_server;
				} else {
					$snode = $nimprime;
				}
				chomp $snode;

				# do we have a seperate service node to handle
				my $doSN;
				my $nimprimeip = xCAT::NetworkUtils->getipaddr($nimprime);
                my $snodeip = xCAT::NetworkUtils->getipaddr($snode);
                if ($nimprimeip ne $snodeip) {
					$doSN++;
				}

				# get the location for the new resource
                my $loc;
                if ($::opt_l)
                {
                    $loc = "$::opt_l/mksysb/$::image_name";
                }
                else
                {
                    $loc = "$install_dir/nim/mksysb/$::image_name";
                }

				# create the nim command
				my $location = "$loc/$mksysb_name";
                my $nimcmd = "/usr/sbin/nim -Fo define -t mksysb -a server=master ";
                # check for relevant cmd line attrs
                my %cmdattrs;
                if ( ($::NFSv4) && (!$attrres{nfs_vers}) )
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

                # create resource location for mksysb image
                my $cmd = "/usr/bin/mkdir -p $loc";

				# create a local dir on nimprime
				my $output=xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $nimprime, $cmd, 0);
				if ($::RUNCMD_RC != 0)
                {
                    my $rsp;
                    push @{$rsp->{data}}, "Could not create $loc on $nimprime.\n";
                    if ($::VERBOSE)
                    {
                        push @{$rsp->{data}}, "$output\n";
                    }
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return undef;
                }


				# if $snode is not nimprime then create dir on snode
				if ($doSN) {
					$output=xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $snode, $cmd, 0);
					if ($::RUNCMD_RC != 0)
                	{
                    	my $rsp;
                    	push @{$rsp->{data}}, "Could not create $loc on $snode.\n";
                    	if ($::VERBOSE)
                    	{
                        	push @{$rsp->{data}}, "$output\n";
                    	}
                    	xCAT::MsgUtils->message("E", $rsp, $callback);
                    	return undef;
                	}
				}

				# check if the res is already defined on $snode
				#  Get a list of all defined resources
				$cmd = qq~/usr/sbin/lsnim -c resources | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
				my $reslist = xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $snode, $cmd, 0);
				if ($::RUNCMD_RC != 0)
				{
					my $rsp;
					push @{$rsp->{data}}, "Could not get NIM resource definitions on $snode.";
					xCAT::MsgUtils->message("E", $rsp, $callback);
					return undef;
				}
				my @nimres;
				foreach my $res (split(/\n/, $reslist )) {
					$res =~ s/$snode:\s+//;
					chomp $res;
					push @nimres, $res;
				}

				if (grep(/^$mksysb_name$/, @nimres))
				{
					# error if it is
					my $rsp;
					push @{$rsp->{data}}, "The $mksysb_name resource is already defined on $snode.\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
					return undef;
				}
				else
				{
					# otherwise create it

					# check the file system space needed
					# about 1800 MB for a mksysb image???
					# can't really predict how big it could be 1G, 6G ??
					# TBD - maybe check size of / on target node???
#					if (&chkFS($loc, $sysbsize, $snode, $sub_req, $callback) != 0) {
#						# error
#						my $rsp;
#						push @{$rsp->{data}}, "Insufficient space available for $loc on $snode.\n";
#						xCAT::MsgUtils->message("E", $rsp, $callback);
#					}

					# create the mksysb image of a node - run the command on
					# 	the NIM master for the node

					$output=xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $snode, $nimcmd, 0);
                	if ($::RUNCMD_RC != 0)
                	{
                    	my $rsp;
                    	push @{$rsp->{data}},
                      		"Could not define mksysb resource named \'$mksysb_name\' on $snode.\n";
                    	if ($::VERBOSE)
                    	{
                        	push @{$rsp->{data}}, "$output\n";
                    	}
                    	xCAT::MsgUtils->message("E", $rsp, $callback);
                    	return undef;
                	}
				}

				# if this service node is not the nimprime (management node)
				#	then copy the mksysb to the nimprime and define it there.
				if ($doSN) {  # we have a seperate SN

					# check space on nimprime
					my $sysbsize = 1800;
					# can't really predict how big it could be 1G, 6G ??
#                    if (&chkFS($loc, $sysbsize, $nimprime, $sub_req, $callback) != 0) {
#                        # error
#                        my $rsp;
#                        push @{$rsp->{data}}, "Insufficient space available for $loc on $nimprime.\n";
#                        xCAT::MsgUtils->message("E", $rsp, $callback);
#                    }

					# xdsh to SN and xdcp to nimprime
					my $dcpcmd = "/opt/xcat/bin/xdcp $snode -P $location $loc";
					$output=xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $nimprime, $dcpcmd, 0);
					if ($::RUNCMD_RC != 0)
                    {
                        my $rsp;
                        push @{$rsp->{data}}, "Could not copy $location from $snode to $nimprime.\n";
                        if ($::VERBOSE)
                        {
                            push @{$rsp->{data}}, "$output\n";
                        }
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                        return undef;
                    }

					# change the file name $mksysb_name._snode -> $mksysb_name
					my $newname = "$loc/$mksysb_name";
					my $oldname = "$loc/$mksysb_name._$snode";
					my $mvcmd = "/bin/mv $oldname $newname 2>&1";
					$output=xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $nimprime, $mvcmd, 0);
                    if ($::RUNCMD_RC != 0)
                    {
                        my $rsp;
                        push @{$rsp->{data}}, "Could not rename $oldname to $newname on $nimprime.\n";
                        if ($::VERBOSE)
                        {
                            push @{$rsp->{data}}, "$output\n";
                        }
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                        return undef;
                    }

					# now define it on the nimprime
					my $mkcmd;
					if ($::NFSv4)
					{
						$mkcmd = "/usr/sbin/nim -Fo define -t mksysb -a server=master -a nfs_vers=4 -a location=$location $mksysb_name 2>&1";
					}
					else
					{
						$mkcmd = "/usr/sbin/nim -Fo define -t mksysb -a server=master -a location=$location $mksysb_name 2>&1";
					}
					$output=xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $nimprime, $mkcmd, 0);
					if ($::RUNCMD_RC != 0)
					{
						my $rsp;
						push @{$rsp->{data}}, "Could not define mksysb resource named \'$mksysb_name\' on $nimprime.\n";
						if ($::VERBOSE)
						{
							push @{$rsp->{data}}, "$output\n";
						}
						xCAT::MsgUtils->message("E", $rsp, $callback);
						return undef;
					}
				}
            }
            elsif ($::SYSB)
            {
				# we have a mksysb file - so just define the NIM resource
                if ($::SYSB !~ /^\//)
                {    #relative path
                    $::SYSB = xCAT::Utils->full_path($::SYSB, $::cwd);
                }

                # def res with existing mksysb image
                my $mkcmd;
                if ($::NFSv4)
                {
                  $mkcmd = "/usr/sbin/nim -Fo define -t mksysb -a server=master -a nfs_vers=4 -a location=$::SYSB $mksysb_name 2>&1";
                }
                else
                {
                  $mkcmd = "/usr/sbin/nim -Fo define -t mksysb -a server=master -a location=$::SYSB $mksysb_name 2>&1";
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
	my $sub_req = shift;

    my @servicenodes = ();    # pass back list of service nodes
    my %imagedef;             # pass back image def hash

    if ( defined ($::args) && @{$::args} ) 
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

	#  need to check if NIM res is mentioned in another osimage def
	#  if not force then don't remove osimage

	if (!$::FORCE) {
		my %allosimages;
		my %objtype;
		foreach my $os (@deflist) {
			$objtype{$os} = 'osimage';
		}
		%allosimages = xCAT::DBobjUtils->getobjdefs(\%objtype, $callback);
		if (!(%allosimages))
    	{
        	my $rsp;
        	push @{$rsp->{data}}, "Could not get xCAT image definitions.\n";
        	xCAT::MsgUtils->message("E", $rsp, $callback);
        	return (0);
    	}

		#  Get a list of all nim resource types
		#
		my @nimrestypes;
		my $cmd = qq~/usr/sbin/lsnim -P -c resources | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
		@nimrestypes = xCAT::Utils->runcmd("$cmd", -1);
		if ($::RUNCMD_RC != 0)
		{
			my $rsp;
			push @{$rsp->{data}}, "Could not get NIM resource types.";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}

		my $found=0;
		foreach my $restype (@nimrestypes) {
			foreach my $img (@deflist) {
				if ($image_name ne $img) {

					if ( $allosimages{$image_name}{$restype} && ($allosimages{$img}{$restype} eq $allosimages{$image_name}{$restype} )) {
						# these two images share a resource
						if ($::VERBOSE) {
							my $rsp;
							push @{$rsp->{data}}, "The osimage $image_name and $img share the common resource $allosimages{$img}{$restype}\n";
							xCAT::MsgUtils->message("I", $rsp, $callback);
						}
						$found++;
					}
				}
			}
		}

		if ($found) {
			my $rsp;
			push @{$rsp->{data}}, "One or more resources are being used in other osimage definitions.  The osimage $image_name will not be removed.  Use the force option to override this check.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}
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

    # by default, get MN and all servers
    my @allsn = ();
    my @nlist = xCAT::TableUtils->list_all_nodes;
    my $sn;
    my $service = "xcat";
    if (\@nlist)
    {
        $sn = xCAT::ServiceNodeUtils->getSNformattedhash(\@nlist, $service, "MN");
    }
    foreach my $snkey (keys %$sn)
    {
        push(@allsn, $snkey);
    }

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
        # do mn and all sn
        @servicenodes = @allsn;
    }

	# get the sharedinstall value
	my $sharedinstall=xCAT::TableUtils->get_site_attribute('sharedinstall');
	chomp $sharedinstall;

	#	- if shared file system then we need to remove resources 
	#		from a target SN first
	#   - this avoids contention issues with NIM removing resources
	#       on the rest of the SNs
	if ( $sharedinstall eq "sns" ) {

		#	- get a target SN and see if it is available
		# pick a SN and make sure it is available
		my $targetsn;
		foreach $sn (@servicenodes) {
			# pick something other than the management node
			if (!xCAT::InstUtils->is_me($sn) ) {
				my $snIP = xCAT::Utils::getNodeIPaddress($sn);
				if(!defined $snIP) {
					next;
				}
				if (xCAT::Utils::isPingable($snIP)) {
					$targetsn=$sn;
					last;
				}
			}
		}

		if ($targetsn) {
			# remove these osimage resources on the SN
			my $rc = &rmnimres($callback, \%imagedef, $targetsn, $image_name, \@allsn, $sub_req);

			if ($rc != 0)
			{
				my $rsp;
				push @{$rsp->{data}}, "One or more errors occurred when trying to remove the xCAT osimage definition \'$image_name\' and the related NIM resources.\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
				return 1;
			}
		}

		#  remove targetsn from the sn list?????
		my @tmpsn;
		foreach my $s (@servicenodes) 
		{
			if ($s ne $targetsn) {
				push(@tmpsn, $s);
			}
		}	
		@servicenodes = @tmpsn;
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

    return (0, \%imagedef, \@servicenodes, \@allsn);
}

#----------------------------------------------------------------------------

=head3   rmnimres

		Remove the specified NIM resources from the specified service node

        Returns:
                0 - OK
                1 - error

=cut

#-----------------------------------------------------------------------------
sub rmnimres
{
	my $callback = shift;
    my $imaghash = shift;
    my $targetsn = shift; 
	my $osimage	 = shift;
	my $snall    = shift;
    my $subreq   = shift;

	my %imagedef;
    if ($imaghash)
    {
        %imagedef = %{$imaghash};
    }

	my @allsn;
	if ($snall) {
		@allsn = @$snall;
	}

    #
    #  Get a list of all nim resource types
	#		(can do this on local system)
    #
    my $cmd =
      qq~/usr/sbin/lsnim -P -c resources | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    my @nimrestypes = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get NIM resource types.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    #
    #  Get a list of the all the nim resources defined on the SN
    #
    $cmd =
      qq~/usr/sbin/lsnim -c resources | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    my @nimresources = ();
	my $out = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $targetsn, $cmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get NIM resource definitions from $targetsn.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	foreach my $line ( split(/\n/, $out)) {
		$line =~ s/$targetsn:\s+//;
		push(@nimresources, $line);
	}

    # foreach attr in the image def
    my $error=0;
    foreach my $attr (sort(keys %{$imagedef{$osimage}}))
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
        my $res_name = $imagedef{$osimage}{$attr};
        chomp $res_name;

        unless($res_name)
        {
            next;
        }

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
				foreach my $sn (@allsn)
				{
					my $acount = xCAT::InstUtils->get_nim_attr_val($resname, "alloc_count",$callback, $sn, $subreq);
					if ($acount != 0)
					{
						my $rsp;
						push @{$rsp->{data}}, "The resource named \'$resname\' is currently allocated on $sn.\n";
						xCAT::MsgUtils->message("I", $rsp, $callback);
						$alloc_count++;
					}
				}

                if (defined($alloc_count) && ($alloc_count != 0))
                {
                    my $rsp;
                    push @{$rsp->{data}}, "The resource named \'$resname\' will not be removed.\n";
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
                        $loc = xCAT::InstUtils->get_nim_attr_val($resname, 'location', $callback, $targetsn, $subreq);
                    }

                    #  need the directory name to remove these
                    if (($attr eq "resolv_conf") || ($attr eq "spot"))
                    {
                        my $tmp = xCAT::InstUtils->get_nim_attr_val($resname, 'location', $callback, $targetsn, $subreq);
                        $loc = dirname($tmp);
                    }
                }

                # try to remove it
                my $cmd = "nim -Fo remove $resname";

                my $output;
				$output = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $targetsn,  $cmd, 0);
                if ($::RUNCMD_RC != 0)
                {
                    my $rsp;
                    push @{$rsp->{data}}, "Could not remove the NIM resource $resname on $targetsn.\n";
                    push @{$rsp->{data}}, "$output";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    $error++;
                    next;
                }
                else
                {
                    my $rsp;
                    push @{$rsp->{data}}, "Removed the NIM resource named \'$resname\' on $targetsn\n";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                }

                if ($::DELETE)
                {
                    if ($loc)
                    {
                        my $cmd = qq~/usr/bin/rm -R $loc~;
						$output = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $targetsn,  $cmd, 0);
                    }
                }
            }
        }
    }

    if ($error)
    {
        return 1;
    }
	return 0;
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
    my $nodehash = shift;  # store all servicenodes.
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

    my %allsn;
    if ($nodehash)
    {
        %allsn = %{$nodehash};
    }

    if ( defined ($::args) && @{$::args} ) 
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

        unless($res_name)
        {
            next;
        }

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
                    if ($::MN)
                    {
                        # check nim resources on mn or nimprime
                        $alloc_count =
                          xCAT::InstUtils->get_nim_attr_val($resname, "alloc_count",
                                                        $callback, "", $subreq);
                    }
                    else
                    {
                        # get local hostname as target, since the req has been dispatched.
                        my $hn = `hostname`;
                        $alloc_count =
                          xCAT::InstUtils->get_nim_attr_val($resname, "alloc_count",
                                                        $callback, $hn, $subreq);
                    }
                    
                    # if this is mn, check the alloc_count on sn too.
                    if (xCAT::Utils->isMN())
                    {
                        foreach my $sn (keys %allsn)
                        {
                            my $acount =
                              xCAT::InstUtils->get_nim_attr_val($resname, "alloc_count",
                                                            $callback, $sn, $subreq);
                            if ($acount != 0)
                            {
                                 my $rsp;
                                push @{$rsp->{data}},
                                  "$Sname: The resource named \'$resname\' is currently allocated on $sn. It will not be removed.\n";
                                xCAT::MsgUtils->message("I", $rsp, $callback);
                                
                                $alloc_count = $alloc_count + $acount;
                            }
                        }
                    }
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
                my $cmd = "nim -Fo remove $resname";

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
        if ($::NFSv4)
        {
           $defcmd = qq~/usr/sbin/nim -Fo define -t script -a server=master -a nfs_vers=4 -a location=$respath $resname 2>/dev/null~;
        }
        else
        {
           $defcmd = qq~/usr/sbin/nim -Fo define -t script -a server=master -a location=$respath $resname 2>/dev/null~;
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

=head3  chkFS

    See if there is enough space in file systems. If not try to increase
    the size. (Works for remote systems)

        Arguments:
        Returns:
                0 - OK
                1 - error
=cut

#-----------------------------------------------------------------------------
sub chkFS
{
    my $location = shift;
    my $size     = shift;
	my $target = shift;
	my $sub_req = shift;
	my $callback = shift;

	# get free space
    # ex. 1971.06 (Free MB)
    my $dfcmd = qq~/usr/bin/df -m $location | /usr/bin/awk '(NR==2){print \$3":"\$7}'~;

	my $output = xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $target, $dfcmd, 0);
	if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not run: \'$dfcmd\' on $target.\n";
        if ($::VERBOSE)
        {
            push @{$rsp->{data}}, "$output";
        }
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	# strip off target name if any
	$output =~ s/$target:\s+//;
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
        $output = xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $target, $chcmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not increase file system size for \'$FSname\' on $target. Additonal $addsize MB is needed.\n";
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
	my $target   = shift;
    my $subreq   = shift;

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

    my $cmd = "/usr/sbin/nim -Fo define -t $type -a server=master ";
    my $install_dir = xCAT::TableUtils->getInstallDir();

	my %cmdattrs;

	if ( ($::NFSv4) && (!$attrvals{nfs_vers}) )
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

	if ($target) {
         my $output = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $target, $cmd, 0);
    } else {
        my $output = xCAT::Utils->runcmd("$cmd", -1);
    }
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
	my $target   = shift;
    my $subreq   = shift;

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

    my $cmd = "/usr/sbin/nim -Fo define -t $type -a server=master ";
    my $install_dir = xCAT::TableUtils->getInstallDir();

	my %cmdattrs;
    if ($::NFSv4)
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

	if ($target) {
        my $output = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $target, $cmd, 0);
    } else {
        my $output = xCAT::Utils->runcmd("$cmd", -1);
    }
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
		my $sharedinstall=xCAT::TableUtils->get_site_attribute('sharedinstall');
		chomp $sharedinstall;
		if ( $sharedinstall eq "sns" ) {
			my $rc=xCAT::InstUtils->dolitesetup($image, \%imghash, \@nodelist, $callback, $subreq);
        	if ($rc eq 1) { # error
            	my $rsp;
            	push @{$rsp->{data}}, qq{Could not complete the statelite setup.};
            	xCAT::MsgUtils->message("E", $rsp, $callback);
            	return 1;
        	}
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
    my $install_dir = xCAT::TableUtils->getInstallDir();
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
			cp /SPOT/usr/bin/cut  /usr/bin

			SHOST=`echo \${NIM_HOSTNAME} | /usr/bin/cut -d . -f 1`

			# statelite entry for this node
			SLLINE=`/usr/bin/cat /mnt/statelite.table | /usr/bin/grep \${SHOST}`
			# the statelite server
			SLSERV=`echo \$SLLINE | /usr/bin/awk -F'|' '{print \$2}'`

			# statelite directory to mount
			SLDIR=`echo \$SLLINE | /usr/bin/awk -F'|' '{print \$3}'`

			cp /SPOT/usr/bin/mkdir /usr/bin
			/usr/bin/mkdir -p /slmnt

			$::MOUNT \${SLSERV}:\${SLDIR} /slmnt

			# - get the persistent version of basecust from the server
			if [ -f /slmnt/\${SHOST}/etc/basecust  ]; then
				cp -p /slmnt/\${SHOST}/etc/basecust /etc
				cp /SPOT/usr/lib/boot/restbase /usr/sbin
				cp /SPOT/usr/bin/uncompress /usr/bin
			fi
			umount /slmnt
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
			cp /SPOT/usr/bin/mkdir /usr/bin
			/usr/bin/mkdir -p /slmnt
			$::MOUNT -o rw \${SLSERV}:\${SLDIR} /slmnt
			/usr/bin/touch /etc/basecust
			SHOST=`echo \${NIM_HOSTNAME} | cut -d . -f 1`
			# if we have a basecust file
			if [ -f /slmnt/\${SHOST}/etc/basecust  ]; then
				# need to mount persistent basecust to RAM FS
				mount /slmnt/\${SHOST}/etc/basecust /etc/basecust
			fi
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
            my $dontupdt4 = 0;
            my $dontupdt5 = 0;
            if (open(DDBOOT, ">$dd_boot_file_mn"))
            {
                if (grep(/Remove ODM object definition/, @lines))
                {
                    $dontupdt5 = 1;
                }
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
                    if ($l =~ /Write tmp file to create remote paging device/)
                    {
                        $dontupdt4 = 1;
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

                    if (($l =~ /odmadd \/tmp\/swapnfs/) || ($l =~ /odmadd \/swapnfs/))
                    {
                        if (!$dontupdt4)
                        {
                            print DDBOOT "#Write tmp file to create remote paging device\n";
                            print DDBOOT "echo \"CuDv:\" > /swapnfs\n";
                            print DDBOOT "echo \"name = \$SWAPDEV\" >> /swapnfs\n";
                            print DDBOOT "echo \"status = 0\" >> /swapnfs\n";
                            print DDBOOT "echo \"chgstatus = 1\" >> /swapnfs\n";
                            print DDBOOT "echo \"PdDvLn = swap/nfs/paging\" >> /swapnfs\n\n";
                        }
                    }

                    if ($l =~ /odmadd \/tmp\/swapnfs/)
                    {
                        $l =~ s/tmp\/swapnfs/swapnfs/g;
                        print DDBOOT $l;
                        print DDBOOT "\n                        rm -f /swapnfs\n";
                    }
                    elsif ($l =~ /echo "CuDv:" >> \/swapnfs/ )
                    {
                        print DDBOOT "echo \"CuDv:\" > /swapnfs\n";
                    } else {
                        if ($l =~ /tmp\/swapnfs/)
                        {
                           $l =~ s/tmp\/swapnfs/swapnfs/g;
                        }
                        print DDBOOT $l;
                    }
                    if ($l =~ /rmdev -l \${BASECUST_REMOVAL}/ && !$dontupdt5)
                    {
                        print DDBOOT "            #Remove ODM object definition\n";
                        print DDBOOT "            odmdelete -o CuDv -q name=\${BASECUST_REMOVAL}\n";
                    }
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

    if ( defined ($::args) && @{$::args} ) 
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
    my $sn = xCAT::ServiceNodeUtils->getSNformattedhash(\@nodelist, "xcat", "MN");
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

    if ( defined ($::args) && @{$::args} ) 
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
      "nim -Fo cust -a lpp_source=$::LPPSOURCE -a installp_flags=agQXY ";
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
                if ($::NFSv4)
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

    if ( defined ($::args) && @{$::args} ) 
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
					'd|defonly'   => \$::DEFONLY,
                    'f|force'   => \$::FORCE,
                    'h|help'    => \$::HELP,
                    'i=s'       => \$::OSIMAGE,
					'k|skipsync' => \$::SKIPSYNC,
					'l=s'       => \$::opt_l,
                    'n|new'     => \$::NEWNAME,
					'p|primarySN' => \$::PRIMARY,
					'r|resonly'   => \$::RESONLY,
                    'S|setuphanfs' => \$::SETUPHANFS,
					'u|updateSN'   => \$::UPDATESN,
                    'verbose|V' => \$::VERBOSE,
                    'v|version' => \$::VERSION,
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
    # currently supported valid attributes, may append later..
    my @validattr = ("duplex", "speed", "psize", "sparse_paging", "dump_iscsi_port", "configdump");
    my @badattr;

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

            if ($command eq 'mkdsklsnode')
            {

                # if it has an "=" sign its an attr=val - we hope
                my ($attr, $value) = $a =~ /^\s*(\S+?)\s*=\s*(\S*.*)$/;
                if (!$attr || !$value)
                {
                    my $rsp;
                    push @{$rsp->{data}}, "Incorrect \'attr=val\' pair - $a\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    return 1;
                }

                # check the valid attributes.
                if (grep(/^$attr$/, @validattr))
                {
                    $attrs{$attr} = $value;
                }
                else
                {
                    push @badattr, $attr;
                }
            }
        }
    }

    if (scalar(@badattr))
    {
        my $rsp;
        my $bad = join(', ', @badattr);
        my $valid = join(', ', @validattr);
        push @{$rsp->{data}}, "Bad attributes '$bad'. The valid attributes are '$valid'.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    my $Sname = xCAT::InstUtils->myxCATname();
    chomp $Sname;

	# see if this is a shared filesystem environment
    #my $sitetab = xCAT::Table->new('site');
    #my ($tmp) = $sitetab->getAttribs({'key' => 'sharedinstall'}, 'value');
    #my $sharedinstall = $tmp->{value};
    #$sitetab->close;
    my @sharedinstalls = xCAT::TableUtils->get_site_attribute("sharedinstall");
    my $sharedinstall = $sharedinstalls[0];
    if (!$sharedinstall) {
        $sharedinstall="no";
    }

    chomp $sharedinstall;

    #
    #   TODO - if $sharedinstall is "all" or "sns", add check for proper
    #       level of AIX nfsV4 software
    #

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
    # Get a list of all the nim resrouces defined.
    #
    $cmd = qq~/usr/sbin/lsnim | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    my @nimres = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cmd, 1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get NIM resources on $nimprime.";
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

	#  if a configdump value was provided then add it to the osimage defs
	if ($attrs{configdump})
	{
		foreach my $i (@image_names)
		{
			$imghash{$i}{configdump} = $attrs{configdump};
		}

		# update the osimage defs
		if (xCAT::DBobjUtils->setobjdefs(\%imghash) != 0)
		{
			my $rsp;
			$rsp->{data}->[0] = "Could not update xCAT osimage definitions.\n";
			xCAT::MsgUtils->message("E", $rsp, $::callback);
			return 1;
		}
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

    # no dump resource defined for osimage, 
	#	but configdump is specified, report error.
    my @badosi;
    if (%attrs)
    {
        foreach my $attr (keys %attrs)
        {
            if ($attr =~ /^configdump$/)
            {
                foreach my $i (@image_names)
                {
                    if (!$imghash{$i}{dump})
                    {
            			push @badosi, $i;
                    }
                }
            }

            if (scalar @badosi)
            {
                my $badstring = join(',', @badosi);
                my $rsp;
                push @{$rsp->{data}}, "$Sname: No \'dump\' resource is defined for the osimage \'$badstring\', but the attribute \'$attr\' is specified. \n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
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
        my $install_dir = xCAT::TableUtils->getInstallDir();

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
            # TODO: xcataixscript is having problem with NFSv4, will be fixed in the next AIX release
            #if ($::NFSv4)
            #{
            #  $dcmd = qq~/usr/sbin/nim -Fo define -t script -a server=master -a nfs_vers=4 -a location=$install_dir/nim/scripts/xcataixscript xcataixscript 2>/dev/null~;
            #}
            #else
            #{
              $dcmd = qq~/usr/sbin/nim -Fo define -t script -a server=master -a location=$install_dir/nim/scripts/xcataixscript xcataixscript 2>/dev/null~;
            #}
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

			# add this res to @nimres
			push(@nimres, 'xcataixscript');

        } else {
                # TODO: xcataixscript is having problem with NFSv4, will be fixed in the next AIX release
                if (0 && $::NFSv4) {
                    my $cmd = qq~/usr/sbin/lsnim -Z -a nfs_vers xcataixscript 2>/dev/null~;
                        my @result = xCAT::Utils->runcmd("$cmd", -1);
                        if ($::RUNCMD_RC != 0)
                        {
                            my $rsp;
                            push @{$rsp->{data}}, "Could not run lsnim command: \'$cmd\'.\n";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                            return 1;
                        }
                        my $nfsvers;
                        my $nimname;
                        foreach my $l (@result)
                        {

                            # skip comment lines
                            next if ($l =~ /^\s*#/);

                            ($nimname, $nfsvers) = split(':', $l);
                            if ($nfsvers) {
                                last;
                            }
                         }
                         if (!$nfsvers || ($nfsvers eq 3))
                         {
                             # make sure we clean up the /etc/exports file of NFSv3 exports
                             my $ecmd = qq~/usr/sbin/rmnfsexp -d $install_dir/nim/scripts/xcataixscript -B 2>/dev/null~;
                             xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $ecmd,0);
                             my $nimcmd = qq~nim -Fo change -a nfs_vers=4 xcataixscript~;
                             my $nimout = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $nimcmd,0);
                             if ($::RUNCMD_RC != 0)
                             {
                                 my $rsp;
                                 push @{$rsp->{data}}, "Could not set nfs_vers=4 for resource xcataixscript.\n";
                                 if ($::VERBOSE)
                                 {
                                     push @{$rsp->{data}}, "$nimout";
                                 }
                                 xCAT::MsgUtils->message("E", $rsp, $callback);
                                 return 1;
                             }
                         }
                    } #end if $::NFSv4

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

				# before get location, we need to validate if the nimres exists
                unless (grep (/^$res$/, @nimres))
                {
                     my $rsp;
                     push @{$rsp->{data}}, "NIM resource $res is not defined on $nimprime.\n";
                     xCAT::MsgUtils->message("E", $rsp, $callback);
                     return 1;

                }

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

			# need list of nodes that use this image only!!!
			my @osinodes;
			foreach my $n (@nodelist) {
				if ($i eq $nodeosi{$n} ) {
					push @osinodes, $n;
				}
			}

			my $rc = &updatespot($i, \%imghash, \@osinodes, $callback, $subreq);
            if ($rc != 0)
            {
                my $rsp;
                push @{$rsp->{data}},
                  "Could not update the SPOT resource named \'$imghash{$i}{'spot'}\'.\n";
				push @{$rsp->{data}}, "Could not initialize the nodes.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return (1);
            }

			# if we're using a shared file system we should  re-sync
            #   the shared_root resource
            if ( ($sharedinstall eq "sns") || ($sharedinstall eq "all")) {

				my $moveit = 0;
				my $origloc;
				my $locbak;

				# if the management node also shares the file system then
				#	save/restore the .client data files.
				if (( $sharedinstall eq "all") && ($lochash{$imghash{$i}{shared_root}}) ) {
					my $resloc =  $lochash{$imghash{$i}{shared_root}};	
					# ex. /install/nim/shared_root/71Bdskls_shared_root

					$origloc = "$resloc/etc/.client_data";
					$locbak = "$resloc/etc/.client_data_bkup";

					if (-d $origloc) {
						my $cpcmd = qq~/usr/bin/mkdir -m 644 -p $locbak; /usr/sbin/cp -r -p $origloc/* $locbak~;

						my $output = xCAT::Utils->runcmd("$cpcmd", -1);
						if ($::RUNCMD_RC != 0) {
							my $rsp;
							push @{$rsp->{data}}, "Could not copy $origloc.\n";
							xCAT::MsgUtils->message("E", $rsp, $callback);
						}
						$moveit++;
					}
				}
				if (!$::SKIPSYNC) {

                	# do a re-sync
					# if it's allocated then don't update it
                	my $alloc_count = xCAT::InstUtils->get_nim_attr_val($imghash{$i}{shared_root}, "alloc_count", $callback, "", $subreq);
                	if (defined($alloc_count) && ($alloc_count != 0))
                	{
                    	my $rsp;
                    	push @{$rsp->{data}}, "The resource named \'$imghash{$i}{shared_root}\' is currently allocated. It will not be re-synchronized.\n";
                    	xCAT::MsgUtils->message("I", $rsp, $callback);
                	}
					else
					{

                		my $scmd = "nim -Fo sync_roots $imghash{$i}{spot}";
                		my $output = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $scmd, 0);
                		if ($::RUNCMD_RC != 0)
                		{
                    		my $rsp;
                    		push @{$rsp->{data}}, "Could not update $imghash{$i}{shared_root}.\n";
                    		if ($::VERBOSE)
                    		{
                        		push @{$rsp->{data}}, "$output";
                    		}
                    		xCAT::MsgUtils->message("E", $rsp, $callback);
                		}
					}
				}

				if ($moveit) {
					# copy back the .client data files
					my $cpcmd = qq~/usr/sbin/cp -r -p $locbak/* $$origloc~;

					my $output = xCAT::Utils->runcmd("$cpcmd", -1);
					if ($::RUNCMD_RC != 0) {
						my $rsp;
						push @{$rsp->{data}}, "Could not copy $locbak.\n";
						xCAT::MsgUtils->message("E", $rsp, $callback);
					}
				}
            }
        }
    }

    # Checks the various credential files on the Management Node to
    #   make sure the permission are correct for using and transferring
    #   to the nodes and service nodes.
    #   Also removes /install/postscripts/etc/xcat/cfgloc if found
    my $result = xCAT::TableUtils->checkCredFiles($callback);

    #####################################################
    #
    #	Copy files/dirs to remote service nodes so they can be
    #		defined locally when this cmd runs there
    #
    ######################################################

    if ($sharedinstall eq "sns" ) {

		# copy NIM resources and statelite files to SFS (shared file system)
        my $rc = &doSFScopy($callback, \@nodelist, $nimprime, \@nimrestypes, \%imghash, \%lochash,  \%nodeosi, $subreq, $type);
		if ($rc != 0 ){
			my $rsp;
			push @{$rsp->{data}}, "Could not copy NIM resources to the shared file system.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return (1);
		}

		# Define the required resources on the SNs
        $rc = &defSNres($callback, \@nodelist, \%imghash, \%lochash, \%nodeosi, \%nimhash, $subreq, $type);
        if ($rc != 0 ) {
            my $rsp;
            push @{$rsp->{data}}, "Could not define NIM resources on service nodes.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return (1);
        }

	} else {

		# don't copy if define only is set
    	if (!$::DEFONLY) {
			my $rc = &doSNcopy2($callback, \@nodelist, $nimprime, \@nimrestypes, \%imghash, \%lochash,  \%nodeosi, $subreq, $type);
			if ($rc != 0 ){
        		my $rsp;
        		push @{$rsp->{data}},
          			"Could not copy NIM resources to the xCAT service nodes.\n";
        		xCAT::MsgUtils->message("E", $rsp, $callback);
        		return (1);
			}
    	}
	}

	if ($::UPDATESN || $::RESONLY) {
		return (2);
	} else {
    	# pass this along to the process_request routine
    	return (0, \%objhash, \%nethash, \%imghash, \%lochash, \%attrs, \%nimhash, \@nodelist, $type);
	}
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
    my $dfcmd = qq~$::XCATROOT/bin/xdsh $dest /usr/bin/df -m $dir | /usr/bin/awk '(NR==2)'~;

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

=head3   copyres2

		Copy NIM resource files/dirs to remote service nodes

		- this version does the copies in parallel using prsync

		Arguments:
		Returns:
			0 - OK
			1 - error
		Globals:
		Example:
		Comments:

=cut

#----------------------------------------------------------------------
sub copyres2
{
	my $callback = shift;
	my $resinfo = shift;
	my $nimprime   = shift;
	my $subreq   = shift;

	my %reshash  = %{$resinfo};

	#
	#  do the copies in parallel
	#

	foreach my $res (keys %reshash)
	{
		# get the directory location of the resource
		#  - could be the NIM location or may have to strip off a file name
		my $dir;
		if ($reshash{$res}{restype} eq "lpp_source")
		{
			$dir = $reshash{$res}{resloc};
		}
		else
		{
			$dir = dirname($reshash{$res}{resloc});
		}
		chomp $dir;


		my $restype=$reshash{$res}{restype};
		my $resloc=$reshash{$res}{resloc};
		my $resname=$res;
		my $SNlist= join(',', @{$reshash{$res}{snlist}});

		# make sure the directory exists on the service nodes
		my $mkcmd = qq~/usr/bin/mkdir -m 644 -p $dir~;
		my $output = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $SNlist, $mkcmd, 0);
		if ($::RUNCMD_RC != 0)
		{
			my $rsp;
			push @{$rsp->{data}}, "Could not create $dir on service nodes.\n";
			if ($::VERBOSE)
			{
				push @{$rsp->{data}}, "$output\n";
			}
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}

		# How much space does the resource need?
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

		# try to increase FS space on SNs if needed
		foreach my $dest (@{$reshash{$res}{snlist}})
		{
			# how much free space is available on the SN ($dest)?
			my $dfcmd = qq~$::XCATROOT/bin/xdsh $dest /usr/bin/df -m $dir | /usr/bin/awk '(NR==2)'~;

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
				my $chcmd = "$::XCATROOT/bin/xdsh $dest /usr/sbin/chfs $sizeattr $FSname";
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
		}

		# 
		#  Copy resources to service nodes
		#       - from NIM primary server
		#
    	my $cpcmd;
		if ($restype eq "lpp_source")
		{
			# resloc - Ex. /install/nim/lpp_source/61D_lpp_source

			my $dir = dirname($resloc);
			# ex. /install/nim/lpp_source

        	# copy the file to the SNs
			$cpcmd = qq~$::XCATROOT/bin/prsync -o "rlHpEAogDz" $resloc  $SNlist:$dir 2>/dev/null~;
    	}
		elsif ($restype eq 'spot')
		{
			# resloc  ex. /install/nim/spot/61dimg/usr

			my $loc = dirname($resloc);
			#  /install/nim/spot/61dimg

			my $dir = dirname($loc);
			# ex. /install/nim/spot

			# copy the file to the SN
			$cpcmd = qq~$::XCATROOT/bin/prsync -o "rlHpEAogDz" $loc  $SNlist:$dir 2>/dev/null~;

		}
		else
		{
			# copy the resource file to the SN dir - as is
			# - bosinst_data, script, resolv_conf, installp_bundle, mksysb
			# - the NIM location includes the actual file name
			my $dir = dirname($resloc);
			$cpcmd = qq~$::XCATROOT/bin/prsync -o "rlHpEAogDz" $resloc  $SNlist:$dir 2>/dev/null~;
		}

		if ($::VERBOSE)
		{
			my $rsp;
			push @{$rsp->{data}}, "Copying NIM resource $res to service nodes.\n";
			xCAT::MsgUtils->message("I", $rsp, $callback);
		}

		$output=xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cpcmd, 0);
		if ($::RUNCMD_RC != 0)
		{
			my $rsp;
			push @{$rsp->{data}}, "Could not copy NIM resource $res to service nodes.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}
	} # end - foreach resource
	return 0;
}


#----------------------------------------------------------------------------

=head3   doSNcopy2

        Copy NIM resource files/dirs to remote service nodes so they can be
           defined locally

        Also 
			-copy /etc/hosts to make sure we have name res for nodes
            from SN
			- copy /install/postscripts so we have the latest

        Returns:
            0 - OK
			1 - error

=cut

#-----------------------------------------------------------------------------
sub doSNcopy2
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
    my $install_dir = xCAT::TableUtils->getInstallDir();

	my %resinfo;

    #
    #  Get a list of nodes for each service node
    #
    my $sn = xCAT::ServiceNodeUtils->getSNformattedhash(\@nodelist, "xcat", "MN", $type);
    if ($::ERROR_RC)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get list of xCAT service nodes.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	#
	#  running on the management node 
	#

    #
    # Get a list of images for each SN
    #
	my @SNlist;
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
        # get list of service nodes for these nodes
		#	- don't include the MN
		if (!xCAT::InstUtils->is_me($snkey)) {
        	push (@SNlist, $snkey);
		}
    }

    unless(scalar @SNlist)
    {
        return;
    }
    
	my $snlist=join(',',@SNlist);

	# copy the /etc/hosts file all the SNs
	my $rcpcmd = "$::XCATROOT/bin/xdcp $snlist /etc/hosts /etc ";
	my $output = xCAT::Utils->runcmd("$rcpcmd", -1);
	if ($::RUNCMD_RC != 0)
	{
		my $rsp;
		push @{$rsp->{data}}, "Could not copy /etc/hosts to service nodes.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
	}

	# update the postscripts on the SNs
	my $cpcmd = "$::XCATROOT/bin/xdcp $snlist -p -R $install_dir/postscripts/* $install_dir/postscripts ";
	$output = xCAT::Utils->runcmd("$cpcmd", -1);
	if ($::RUNCMD_RC != 0)
	{
		my $rsp;
		push @{$rsp->{data}}, "Could not copy $install_dir/postscripts to service nodes.\n";
 		xCAT::MsgUtils->message("E", $rsp, $callback);
	}

	# - what resources need to be copied? - 
	# - which SNs need to get each resource
	foreach my $snkey (@SNlist)
    {
        my @nimresources;
	
		# get a list of the resources that are defined on the SN
		my $cmd =
              qq~$::XCATROOT/bin/xdsh $snkey "/usr/sbin/lsnim -c resources | /usr/bin/cut -f1 -d' '"~;

		my @resources = xCAT::Utils->runcmd("$cmd", -1);
		if ($::RUNCMD_RC != 0)
		{
			my $rsp;
			push @{$rsp->{data}}, "Could not get NIM resource definitions from $snkey.";
			xCAT::MsgUtils->message("E", $rsp, $callback);
			return 1;
		}

		foreach my $r (@resources)
		{
			my ($node, $nimres) = split(': ', $r);
			chomp $nimres;
			push(@nimresources, $nimres);
		}

		# for each osimage needed on a SN
		foreach my $image (@{$SNosi{$snkey}})
		{
			# for each resource contained in the osimage def
			foreach my $restype (keys(%{$imghash{$image}}))
			{
				my $nimtype = $imghash{$image}{'nimtype'};
				if (   ($nimtype ne 'standalone') && ($restype eq 'lpp_source')) 
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
							# only care about these resource types for now

							my @dorestypes = (
                                              "mksysb",       "resolv_conf",
                                              "script",       "installp_bundle",
                                              "bosinst_data", "lpp_source",
                                              "spot", "image_data"
                                              );
							if (grep(/^$restype$/, @dorestypes))
							{
								push @{$resinfo{$res}{snlist}}, $snkey;
								$resinfo{$res}{restype}=$restype;
								$resinfo{$res}{resloc}=$lochash{$res};
							}

						}    # end - if res not defined
					}    # end foreach resource of this type
				}    # end - if it's a valid res type
			}    # end - for each resource
		}    # end - for each image
	}   # end - for each SN

	if (&copyres2($callback, \%resinfo, $nimprime, $subreq) ) {
		# error
		my $rsp;
		push @{$rsp->{data}}, "Could not copy NIM resources to the service nodes.";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	}
	return 0; 
}

#----------------------------------------------------------------------------

=head3   defSNres

		Define NIM resources on the service nodes

        Arguments:
        Returns:
            0 - OK
            1 - error
        Globals:
        Example:
        Comments:

=cut

#-----------------------------------------------------------------------------
sub defSNres
{
 	my $callback = shift;
    my $nodes    = shift;
    my $imaghash = shift;
    my $locs     = shift;
    my $nosi     = shift;
	my $nhash    = shift;
    my $subreq   = shift;
    my $type     = shift;

    my %lochash     = %{$locs}; # resource locations
    my %imghash     = %{$imaghash}; # osimage defs
    my @nodelist    = @$nodes;
    my %nodeosi     = %{$nosi};  # osimage name for each node
	my %nimhash     = %{$nhash};

	my @SNlist;
    #  Get a list of nodes for each service node
    my $snlist = xCAT::ServiceNodeUtils->getSNformattedhash(\@nodelist, "xcat", "MN", $type);
    if ($::ERROR_RC)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get list of xCAT service nodes.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	# get a list of service nodes
	my %SNosi;
	my %SNnodes;
    foreach my $snkey (keys %$snlist)
    {
		@{$SNnodes{$snkey}} = @{$snlist->{$snkey}};
		my @nodes = @{$snlist->{$snkey}};
        foreach my $n (@nodes)
        {
            if (!grep (/^$nodeosi{$n}$/, @{$SNosi{$snkey}}))
            {
                push(@{$SNosi{$snkey}}, $nodeosi{$n});
            }
        }

        # get list of service nodes for these nodes
        #   - don't include the MN
        if (!xCAT::InstUtils->is_me($snkey)) {
            push (@SNlist, $snkey);
        }
    }

    unless(scalar @SNlist)
    {
        return 0;
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

	# for each SN
    foreach my $sn (@SNlist) {

		my @nodelist = @{$SNnodes{$sn}};
		&define_SN_resource($callback, \@nodelist, $sn, \%imghash, \%lochash, \%SNosi, \%nethash, \%nimhash, $type, $subreq);

	}

	return 0;
}

#----------------------------------------------------------------------------

=head3   define_SN_resource

        See if the required NIM resources are created on the remote
			service node.

        Create NIM resource  definitions on remote service node if necessary.

        handles service nodes that are not the NIM primary

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
sub define_SN_resource
{
    my $callback = shift;
    my $nodes    = shift;
	my $Snode	 = shift;
    my $imghash  = shift;
	my $lhash    = shift;
	my $nosi     = shift;
	my $nthash  = shift;
	my $nhash	 = shift; 
    my $type     = shift;
	my $subreq   = shift;

	my @nodelist    = @{$nodes};
	my %imghash;    # hash of osimage defs
    my %lochash;    # hash of res locations
    my %nethash;
	my %nodeosi;
	my %SNosi;
	my %nimhash;

	if ($imghash)
    {
        %imghash = %{$imghash};
    }
    if ($lhash)
    {
        %lochash = %{$lhash};
    }
    if ($nosi)
    {
        %SNosi = %{$nosi};
    }
    if ($nthash)
    {
        %nethash = %{$nthash};
    }
	if ($nhash)
    {
        %nimhash = %{$nhash};
    }

    my %attrs;
    if ( defined ($::args) && @{$::args} ) 
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

    my $rsp;
    push @{$rsp->{data}}, "Checking NIM resources on $Snode.\n";
    xCAT::MsgUtils->message("I", $rsp, $callback);

    #
    #  Install/config NIM master if needed
    #
    my $lsnimcmd = "/usr/sbin/lsnim -l >/dev/null 2>&1";
	my $out = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Snode, $lsnimcmd, 0);
    if ($::RUNCMD_RC != 0)
    {

        # then we need to configure NIM on this node
        if ($::VERBOSE)
        {
            my $rsp;
            push @{$rsp->{data}}, "Configuring NIM on $Snode.\n";
            xCAT::MsgUtils->message("I", $rsp, $callback);
        }

        #  NIM filesets should already be installed on the service node
        my $nimcmd = "nim_master_setup -a mk_resource=no";
		my $nimout = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Snode, $nimcmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not install and configure NIM on $Snode.\n";
            if ($::VERBOSE)
            {
                push @{$rsp->{data}}, "$nimout";
            }
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
    }

    # Check NFSv4 settings
    if ($::NFSv4)
    {
        my $scmd = "chnfsdom";
		my $nimout = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Snode, $scmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not get NFSv4 domain setting on $Snode.\n";
            if ($::VERBOSE)
            {
                push @{$rsp->{data}}, "$nimout";
            }
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
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
        # NFSv4 domain is not set yet
        if ($nimout =~ /N\/A/)
        {
            $scmd = "chnfsdom $domain";
			$nimout = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Snode, $scmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not change NFSv4 domain to $domain on $Snode.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$nimout";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

            $scmd = "stopsrc -g nfs";
			$nimout = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Snode, $scmd, 0);
            sleep 2;
            $scmd = qq~startsrc -g nfs~;
			$nimout = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Snode, $scmd, 0);
        }
        $scmd = "lsnim -FZ -a nfs_domain master";
		$nimout = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Snode, $scmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not get NFSv4 domain setting for nim master on $Snode.\n";
            if ($::VERBOSE)
            {
                push @{$rsp->{data}}, "$nimout";
            }
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
        # NFSv4 domain is not set to nim master
        if (!$nimout)
        {
            $scmd = "nim -Fo change -a nfs_domain=$domain master";
			$nimout = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Snode, $scmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not set NFSv4 domain with nim master on $Snode.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$nimout";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
        } #end if $domain eq N/A
    } # end if $::NFSv4

    # make sure we have the NIM networks defs etc we need for these nodes
    if (&checkNIMnetworks($callback, \@nodelist, \%nethash, $Snode, $subreq) != 0)
    {
        return 1;
    }

    #
    # get list of valid NIM resource types from local NIM
    #
    my $cmd =
      qq~/usr/sbin/lsnim -P -c resources | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    my @nimrestypes = xCAT::Utils->runcmd("$cmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}},
          "Could not get NIM resource types.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    # get a list of NIM resources defined on this SN
	my @nimresources;
    $cmd =
            qq~/usr/sbin/lsnim -c resources | /usr/bin/cut -f1 -d' ' 2>/dev/null
~;
    my $nimres =
            xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Snode, $cmd, 0);

    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}},
         "Could not get NIM resource definitions on \'$Snode\'.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    foreach my $line ( split(/\n/, $nimres )) {
        $line =~ s/$Snode:\s+//;
        push(@nimresources, $line);
    }

    # run the sync operation on the node to make sure the GPFS res
    #       location is refreshed

    my $scmd = qq~/usr/sbin/sync; /usr/sbin/sync; /usr/sbin/sync~;
	my $output = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Snode, $scmd, 0);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not run $scmd on $Snode\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
    }

	# for each osimage needed on a SN
    foreach my $image (@{$SNosi{$Snode}})
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
                if (grep(/^$imghash{$image}{$restype}$/, @nimresources))
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "$Snode: Using existing resource called \'$imghash{$image}{$restype}\'.\n";
                    xCAT::MsgUtils->message("I", $rsp, $callback);
                    next;
                }

				# if dump res
				if (($restype eq "dump") && ($imghash{$image}{"nimtype"} eq 'diskless')) {
					my $loc = $lochash{$imghash{$image}{$restype}};
					chomp $loc;

					if (&mkdumpres( $imghash{$image}{$restype}, \%attrs, $callback, $loc, \%nimhash, $Snode, $subreq) != 0 ) {
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

					my $loc = dirname(dirname($lochash{$imghash{$image}{$restype}}));
                    chomp $loc;

					#  if shared_root and DEFONLY that means there may
					# already be a directory created.   So we need to 
					# move the existing dir so we can create the resource.
					# we'll move the original dir back after the res
					# is defined
					my $moveit = 0;
					my $origloc;
					my $origlocbak;
					if (  $restype eq "shared_root") {


						$origloc =  $lochash{$imghash{$image}{$restype}};
                        $origlocbak = "$origloc.bak";
                        # ex. /install/nim/shared_root/71Bdskls_shared_root
						#
						if (-d $origloc) {
							my $mvcmd = qq~/usr/sbin/mvdir $origloc $origlocbak~;
							my $output = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Snode, $mvcmd, 0);
							if ($::RUNCMD_RC != 0)
							{
								my $rsp;
								push @{$rsp->{data}}, "$Snode: Could not move $origloc.\n";
								xCAT::MsgUtils->message("E", $rsp, $callback);
							}
							$moveit++;
						}
					}

                    if (
                        &mknimres(
                                  $imghash{$image}{$restype}, $restype,
                                  $callback,                  $loc,
                                  $imghash{$image}{spot}, \%attrs, \%nimhash, $Snode, $subreq ) != 0 ) {
                        next;
                    }

					if ($moveit) {
						# remove the directory
						my $rmcmd = qq~/bin/rm -R $origloc~;
						my $out2 = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Snode, $rmcmd, 0);

                        if ($::RUNCMD_RC != 0)
                        {
                            my $rsp;
                            push @{$rsp->{data}}, "$Snode: Could not remove $origloc.\n";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                        }

						# move over the original
						# in case it contains info for other node already
						my $mvcmd2 = qq~/usr/sbin/mvdir $origlocbak $origloc~;
						my $out3 = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Snode, $mvcmd2, 0);
                        if ($::RUNCMD_RC != 0)
                        {
                            my $rsp;
                            push @{$rsp->{data}}, "$Snode: Could not move $origlocbak to $origloc.\n";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                        }
					}
				}
                # only make lpp_source for standalone type images
                if (   ($restype eq "lpp_source")
                    && ($imghash{$image}{"nimtype"} eq 'standalone'))
                {

                    my $resdir = $lochash{$imghash{$image}{$restype}};
                    # ex. /install/nim/lpp_source/61D_lpp_source

                    my $loc = dirname($resdir);
                    # ex. /install/nim/lpp_source

                    # define the local res
					my $cmd = "/usr/sbin/nim -Fo define -t lpp_source -a server=master -a location=$resdir ";

					my @validattrs = ("verbose", "nfs_vers", "nfs_sec", "packages", "use_source_simages", "arch", "show_progress", "multi_volume", "group");

					my %cmdattrs;
					if ($::NFSv4)
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
					my $output = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Snode, $cmd, 0);
                    if ($::RUNCMD_RC != 0)
                    {
                        my $rsp;
                        push @{$rsp->{data}},
                          "Could not create NIM resource $imghash{$image}{$restype} on $Snode.\n";
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
							if ($::NFSv4)
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
							my $output = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Snode, $cmd, 0);
                            if ($::RUNCMD_RC != 0)
                            {
                                my $rsp;
                                push @{$rsp->{data}},
                                  "Could not create NIM resource $res on $Snode. \n";
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
					if ($::NFSv4)
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
					my $output = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Snode, $cmd, 0);
                    if ($::RUNCMD_RC != 0)
                    {
                        my $rsp;
                        push @{$rsp->{data}},
                          "Could not create NIM resource $imghash{$image}{$restype} on $Snode \n";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                    }
				}

                # if resolv_conf, bosinst_data, image_data then
                #   the last part of the location is the actual file name
                # 	but not necessarily the resource name!
                my @usefileloc = ("resolv_conf", "bosinst_data", "image_data");
                if (grep(/^$restype$/, @usefileloc))
                {
                    # define the local resource
                    my $cmd;
					$cmd = "/usr/sbin/nim -Fo define -t $restype -a server=master -a location=$lochash{$imghash{$image}{$restype}} ";
					my @validattrs = ("verbose", "nfs_vers", "nfs_sec", "group");
					my %cmdattrs;
					if ($::NFSv4)
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
					my $output = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Snode, $cmd, 0);
                    if ($::RUNCMD_RC != 0)
                    {
                        my $rsp;
                        push @{$rsp->{data}},
                          "Could not create NIM resource $imghash{$image}{$restype} on $Snode \n";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                    }
                }

                # if spot
                if ($restype eq "spot")
                {
                    my $rsp;
                    push @{$rsp->{data}},
                      "Creating a SPOT resource on $Snode.  This could take a while.\n";
                    xCAT::MsgUtils->message("I", $rsp, $callback);

                    my $resdir = dirname($lochash{$imghash{$image}{$restype}});
                    chomp $resdir;
                    # ex. resdir = /install/nim/spot/612dskls

					# location for spot is odd
					# ex. /install/nim/spot/611image/usr
					# want /install/nim/spot for loc when creating new one
                    my $loc = dirname($resdir);
                    chomp $loc;

					my $spotcmd;
					$spotcmd = "/usr/sbin/nim -Fo define -t spot -a server=master -a location=$loc ";
	
					my @validattrs = ("verbose", "nfs_vers", "nfs_sec", "installp_flags", "auto_expand", "show_progress", "debug");

					my %cmdattrs;
					if ($::NFSv4)
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
					my $output = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Snode, $spotcmd, 0);
                    if ($::RUNCMD_RC != 0)
                    {
                        my $rsp;
                        push @{$rsp->{data}},
                          "Could not create NIM resource $imghash{$image}{$restype} on $Snode. \n";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                    }
                }    # end  - if spot
            }    # end - if valid NIM res type
        }    # end - for each restype in osimage def

		#  try to make sure the spot and boot image is in correct state
		if ($imghash{$image}{spot}) {
			my $ckcmd = qq~/usr/sbin/nim -Fo check $imghash{$image}{spot} 2>/dev/null~;
			my $output = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $Snode, $ckcmd, 0);
			if ($::RUNCMD_RC != 0)
			{
				#if ($::VERBOSE) {
				if (0) {
					my $rsp;
					push @{$rsp->{data}}, "$Snode: Could not run $ckcmd.\n";
					xCAT::MsgUtils->message("I", $rsp, $callback);
				}
			}
		}
    }    # end - for each image

	return 0;
}

#----------------------------------------------------------------------------

=head3   doSFScopy

		copy NIM resources and statelite files to SFS (shared file system)

		Also copy /etc/hosts to make sure we have name res for nodes
            from SN

        Arguments:
        Returns:
 			0 - OK
            1 - error
        Globals:
        Example:
        Comments:

=cut

#-----------------------------------------------------------------------------
sub doSFScopy
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

    my %lochash     = %{$locs}; # resource locations
    my %imghash     = %{$imaghash}; # osimage defs
    my @nodelist    = @$nodes;
    my @nimrestypes = @$restypes;
    my %nodeosi     = %{$nosi};  # osimage name for each node
    my $install_dir = xCAT::TableUtils->getInstallDir();

	my $error;

	#  Basic Flow
	# 1) copy /etc/hosts to ALL SNs
	# 2) get a list of images that need to be copied
	# 3) pick a SN and make sure it is available ($targetsn)
	# 4) copy the /install/postscripts to $targetsn
	# 5) copy the /install/prescripts to $targetsn
	# 6) decide what NIM resources to copy
	# 	- if res is allocated anywhere then don't copy
	#   - see if it is a valid resource
	# 7) if shared_root is allocated then still copy the statelite stuff 
	# 8) copy NIM resource files/dirs to $targetsn

	#  the /etc/hosts file should be copied to each SN
	my @SNlist;

	#  Get a list of nodes for each service node
    my $sn = xCAT::ServiceNodeUtils->getSNformattedhash(\@nodelist, "xcat", "MN", $type);
    if ($::ERROR_RC)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not get list of xCAT service nodes.";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

	foreach my $snkey (keys %$sn)
    {
		# get list of service nodes for these nodes
        #   - don't include the MN
        if (!xCAT::InstUtils->is_me($snkey)) {
            push (@SNlist, $snkey);
        }
	}

	unless(scalar @SNlist)
    {
        return 0;
    }

    my $snlist=join(',',@SNlist);

    # copy the /etc/hosts file all the SNs
    my $rcpcmd = "$::XCATROOT/bin/xdcp $snlist /etc/hosts /etc ";
    my $output = xCAT::Utils->runcmd("$rcpcmd", -1);
    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}}, "Could not copy /etc/hosts to service nodes.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
		$error++;
    }

	# get a list of images that need to be copied?
	my @imagenames;  # images that need to be copied to SFS
	foreach my $node (@nodelist) {
		if (!grep (/^$nodeosi{$node}$/, @imagenames) ) {
			push(@imagenames, $nodeosi{$node});
		}
	}

	# pick a SN and make sure it is available
	my @targetSN;
	my $targetsn;
	foreach $sn (@SNlist) {
		if (!xCAT::InstUtils->is_me($sn) ) {
			$targetsn=$sn;
			last;
		}
	}
	push(@targetSN, $targetsn);

    # copy the /install/postscripts to $targetsn

#  TODO - don't really need prsync since we're only copying to 
#	one service node

	#	assume this directory always exists on the nimprime
	my $cpcmd = qq~$::XCATROOT/bin/prsync -o "rlHpEAogDz" $install_dir/postscripts @targetSN:$install_dir~;
	$output=xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cpcmd, 0);
	if ($::RUNCMD_RC != 0)
	{
		my $rsp;
		push @{$rsp->{data}}, "Could not copy $install_dir/postscripts to $targetsn.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		$error++;
	}

	# copy the /install/prescripts to targetSN

	# check if there is anything to copy from the nimprime
	my $lscmd = qq~/usr/bin/ls $install_dir/prescripts >/dev/null 2>&1~;
	my $out = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $lscmd, 0);
	if ($::RUNCMD_RC == 0)
    {
        # if the dir exists then we can update it on the targetsn
        my $cpcmd = qq~$::XCATROOT/bin/prsync -o "rlHpEAogDz" $install_dir/prescripts  @targetSN:$install_dir~;
		$output=xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cpcmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not copy $install_dir/prescripts to $targetsn.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
			$error++;
        }
    }

	# Get list of resources that are allocated on any SNs
	my %liteonly;
	my @dontcopy;

	# by default, get MN and all servers
    my @allsn = ();
    my @nlist = xCAT::TableUtils->list_all_nodes;
    my $snode;
    my $service = "xcat";
    if (\@nlist)
    {
		$snode = xCAT::ServiceNodeUtils->getSNformattedhash(\@nlist, $service, "MN");
    }
    foreach my $sn (keys %$snode) {
		foreach my $img (@imagenames) {
			foreach my $restype (keys(%{$imghash{$img}})) {

				if (!grep(/^$restype$/, @nimrestypes)) {
					next;
				}

				#  don't copy dump or paging
				if ( ($restype eq 'dump') || ($restype eq 'paging') ) {
					if (!grep(/^$imghash{$img}{$restype}$/, @dontcopy))
					{
						push(@dontcopy, $imghash{$img}{$restype});
					}
					next;
				}

				# restype is spot, shared_root etc.
				my $nimtype = $imghash{$img}{'nimtype'};
				if ( ($nimtype ne 'standalone') && ($restype eq 'lpp_source'))
				{
					# don't copy lpp_source for diskless/dataless nodes
					if (!grep(/^$imghash{$img}{'lpp_source'}$/, @dontcopy))
                    {
						push(@dontcopy, $imghash{$img}{'lpp_source'});
					}
					next;
				}

				foreach my $res (split /,/, $imghash{$img}{$restype})
				{
					if (grep (/^$res$/, @dontcopy)) {
						next;
					}

					# could have a comma separated list - ex. script
					my $alloc_count = xCAT::InstUtils->get_nim_attr_val($res, "alloc_count", $callback, $sn, $subreq);

					if (defined($alloc_count) && ($alloc_count != 0)) {
						# if it's allocated then don't copy it
						if (!grep(/^$res$/, @dontcopy))
                   		{
							push(@dontcopy, $res);
						}

						my $rsp;
						push @{$rsp->{data}}, "NIM resource $res is currently allocated on service node $sn and will not be re-copied to the service nodes.\n";
						xCAT::MsgUtils->message("I", $rsp, $callback);

						if ( ($nimtype ne 'standalone') && ($restype eq 'shared_root'))
						{
							$liteonly{$res}=$imghash{$img}{spot};
						}
					}
				} # end - for each resource 
			}
		}
	} # end - for each SN

	# copy NIM resource files/dirs to $targetsn
	#  - not necessary to copy paging or dump!!!

	# for each image
	foreach my $image (@imagenames)
	{
		# for each resource
		foreach my $restype (keys(%{$imghash{$image}}))
		{

			#  don't copy dump or paging
			if ( ($restype eq 'dump') || ($restype eq 'paging') ) {
				next;
			}


			# if a valid NIM type and a value is set
			if (($imghash{$image}{$restype}) && (grep(/^$restype$/, @nimrestypes)))
			{
				# could have a comma separated list - ex. script etc.
				foreach my $res (split /,/, $imghash{$image}{$restype})
				{
					chomp $res;

					# if the resources need to be copied
					my %resinfo;

					if (!grep(/^$res$/, @dontcopy))
					{
						# copy appropriate files to the SN
						# use same location on all NIM servers
						my @dorestypes = (
							"mksysb",       "resolv_conf",
							"script",       "installp_bundle",
							"bosinst_data", "lpp_source",
							"spot", "image_data",
							"root", "shared_root",
							"shared_home" 
						);
						if (grep(/^$restype$/, @dorestypes))
						{
							push @{$resinfo{$res}{snlist}}, $targetsn;
							$resinfo{$res}{restype}=$restype;
							$resinfo{$res}{resloc}=$lochash{$res};

							if (&copyres2($callback, \%resinfo, $nimprime, $subreq) ) {
								# error
								my $rsp;
								push @{$rsp->{data}}, "Could not copy NIM resource $res.\n";
								xCAT::MsgUtils->message("E", $rsp, $callback);
								$error++;
                            }    
                        }    # end - if it's a valid res type
                    } # end if we should copy 

					# if this is a shared_root and we didn't copy it
					#	then we need to copy the statelite updates.
					if ( ($restype eq 'shared_root') && grep(/^$res$/, @dontcopy)) {

						my $rsp;
						push @{$rsp->{data}}, "Copying xCAT statelite files to service node $targetsn.\n";
						xCAT::MsgUtils->message("I", $rsp, $callback);

						my $srloc = $lochash{$res};
						my $cpcmd = qq~$::XCATROOT/bin/xdcp $targetsn ~;
						my $output;
						if (-f "$srloc/statelite.table") {
							$cpcmd .= qq~$srloc/statelite.table ~;
						}

						if (-f "$srloc/litefile.table") {
							$cpcmd .= qq~$srloc/litefile.table ~;
						}

						if (-f "$srloc/litetree.table") {
							$cpcmd .= qq~$srloc/litetree.table ~;
						}

						if (-f "$srloc/aixlitesetup") {
							$cpcmd .= qq~$srloc/aixlitesetup ~;
						}
						$cpcmd .= qq~$srloc/ ~;
						$output=xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cpcmd, 0);
						if ($::RUNCMD_RC != 0)
						{
							my $rsp;
							push @{$rsp->{data}}, "Could not copy new statelite file to $targetsn\n";
							xCAT::MsgUtils->message("E", $rsp, $callback);
						}

						my $ddir = "$srloc/.default";
						if (-d $ddir ) {
							$cpcmd = qq~$::XCATROOT/bin/xdcp $targetsn -R $srloc/.default $srloc/~;
						}

						$output=xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cpcmd, 0);
						if ($::RUNCMD_RC != 0)
						{
							my $rsp;
							push @{$rsp->{data}}, "Could not copy new statelite information to $targetsn\n";
							xCAT::MsgUtils->message("E", $rsp, $callback);
						}
					}
                }    # end - for each resource
            }    # end - if valid type
        }    # end -  foreach type res
    }    # end - for each osimage

	if ($error)
    {
		my $rsp;
		push @{$rsp->{data}}, "One or more errors occured while attempting to copy files to $targetsn.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
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

    if ( defined ($::args) && @{$::args} ) 
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
					'd|defonly' => \$::DEFONLY,
                    'f|force'   => \$::FORCE,
                    'h|help'    => \$::HELP,
                    'i=s'       => \$::OSIMAGE,
					'k|skipsync' => \$::SKIPSYNC,
                    'l=s'       => \$::opt_l,
                    'n|new'     => \$::NEWNAME,
                    'p|primary' => \$::PRIMARY,
					'r|resonly'   => \$::RESONLY,
                    'S|setuphanfs' => \$::SETUPHANFS,
                    'verbose|V' => \$::VERBOSE,
                    'v|version' => \$::VERSION,
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

            # attributes already checked in prenimnodeset
            # put attr=val in hash
            $attrs{$attr} = $value;
        }
    }

	#my $sitetab = xCAT::Table->new('site');
    #my ($tmp) = $sitetab->getAttribs({'key' => 'sharedinstall'}, 'value');
    #my $sharedinstall = $tmp->{value};
    #$sitetab->close;
    my @sharedinstalls = xCAT::TableUtils->get_site_attribute("sharedinstall");
    my $sharedinstall = $sharedinstalls[0];
    if (!$sharedinstall) {
        $sharedinstall="no";
    }
    chomp $sharedinstall;

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
		# skip this for sns
        if ( $sharedinstall ne "sns" ) {
        	&make_SN_resource($callback, \@nodelist, \@image_names, \%imagehash, \%lochash,  \%nethash, \%nimhash, $sharedinstall, $Sname, $subreq);
		}
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
                my $scmd = "nim -Fo sync_roots $imagehash{$img}{spot}";
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
	#  not needed if using a shared file system
	if ($sharedinstall eq "no") {
    	my $statelite=0;
		foreach my $image (@image_names){
    		if ($imagehash{$image}{shared_root}) {

       			# if this has a shared_root resource then
       			#   it might need statelite setup

				# need list of nodes that use this image only!!!
				my @osinodes;
				foreach my $n (@nodelist) {
					if ($image eq $nodeosi{$n} ) {
						push @osinodes, $n;
					}
				}

       			my $rc=xCAT::InstUtils->dolitesetup($image, \%imagehash, \@osinodes, $callback, $subreq);
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
	my %resolv_conf_hash = &chk_resolv_conf($callback, \%objhash, \@nodelist, \%nethash, \%imagehash, \%attrs, \%nodeosi, $subreq); 
	if ( !%resolv_conf_hash ){
        #my $rsp;
        #push @{$rsp->{data}}, "Could not check NIM resolv_conf resource.\n";
        #xCAT::MsgUtils->message("E", $rsp, $callback);
    }

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
                    "/usr/sbin/nim -Fo reset -a force=yes $nim_name;/usr/sbin/nim -Fo deallocate -a subclass=all $nim_name";
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
				my $foundneterror;
				if (!$nethash{$node}{'mask'} )
				{
					my $rsp;
                	push @{$rsp->{data}},"$Sname: Missing network mask for node \'$node\'.\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
					$foundneterror++;
				}
				if (!$nethash{$node}{'gateway'})
				{
					my $rsp;
                	push @{$rsp->{data}},"$Sname: Missing network gateway for node \'$node\'.\n";
                	xCAT::MsgUtils->message("E", $rsp, $callback);
                	$foundneterror++;
				}	
				if (!$imagehash{$image_name}{spot})
				{
                	my $rsp;
                	push @{$rsp->{data}},"$Sname: Missing spot name for osimage \n'$image_name\'.\n";
                	xCAT::MsgUtils->message("E", $rsp, $callback);
                	$foundneterror++;
            	}
				if ($foundneterror) {
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
                      "$Sname: Missing paging resource name for osimage \'$image_name\'.\n";
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

				if ($imagehash{$image_name}{configdump}) {
					$arg_string .= "-a configdump=$imagehash{$image_name}{configdump} ";
				} elsif ($attrs{configdump} ) {
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
                $initcmd = "/usr/sbin/nim -Fo dkls_init $arg_string $nim_name 2>&1";
            }
            else
            {
                $initcmd = "/usr/sbin/nim -Fo dtls_init $arg_string $nim_name 2>&1";
            }

            my $time = `date | cut -f5 -d' '`;
            chomp $time;

			# see if the shared_root is being modified
			my $origloc;
			if ($imagehash{$image_name}{shared_root} ) {
				# get the shared_root location
				$origloc = xCAT::InstUtils->get_nim_attr_val($imagehash{$image_name}{shared_root}, 'location', $callback, $Sname);

				# see if this is a shared filesystem environment
				my @sharedinstalls = xCAT::TableUtils->get_site_attribute("sharedinstall");
				my $sharedinstall = $sharedinstalls[0];
				if (!$sharedinstall) {
					$sharedinstall="no";
				}
				chomp $sharedinstall;
			}

            my $rsp;
            push @{$rsp->{data}}, "$Sname: Initializing NIM machine \'$nim_name\'. \n";
			xCAT::MsgUtils->message("I", $rsp, $callback);

            $output = xCAT::Utils->runcmd("$initcmd", -1);
            if ($::RUNCMD_RC != 0)
            {
				sleep 2;
                $output = xCAT::Utils->runcmd("$initcmd", -1);
				if ($::RUNCMD_RC != 0)
				{
                	my $rsp;
                	push @{$rsp->{data}},
                  		"$Sname: Could not initialize NIM client named \'$nim_name\'.\n";
                    push @{$rsp->{data}}, "$output";
                	xCAT::MsgUtils->message("E", $rsp, $callback);
                	$error++;
                	push(@nodesfailed, $node);
                	next;
				}
            }
        } # end doinit

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
                        
            my $tftpdir = xCAT::TableUtils->getTftpDir();
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

		#
		# If NEWNAME is specified we need to update either the /etc/bootptab
		#	file or the /etc/dhcpsd.cnf
		#	- the NIM alt def has to be created with no mac included - 
		#	- once the dkls_init is done we can then add the mac back
		#	- the the bootptab and or dhcpsd.cnf file
		#  This is only an issue if the "-n" (NEWNAME) option was specified
		#

		if ($::NEWNAME) {

			#  Only need to update this file if we are using dhcpsd daemon

			#Check if dhcpd is running
			my @res = xCAT::Utils->runcmd('lssrc -s dhcpsd',0);
			if ( $::RUNCMD_RC != 0)
			{
				my $rsp;
				push @{$rsp->{data}}, "Failed to check dhcpsd status.\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
			}
			if ( grep /\sactive/, @res)
			{
				# if dhcpsd is active then assume we need to update
				#	/etc/dhcpsd.cnf

				# read the dhcpsd.cnf file into an array
				my $dhcpfile = "/etc/dhcpsd.cnf";
				open(DHCPFILE, "<$dhcpfile");
				my @lines = <DHCPFILE>;
				close DHCPFILE;

				# copy file to backup
				my $cpcmd = qq~/usr/bin/cp $dhcpfile $dhcpfile.bak~;
				my $output = xCAT::Utils->runcmd("$cpcmd", -1);
				if ($::RUNCMD_RC != 0)
				{
					my $rsp;
					push @{$rsp->{data}}, "Could not copy $dhcpfile to $dhcpfile.bak.\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
				}

				foreach my $nd (@nodelist) {
					# short hostname for node
					$nd =~ s/\..*$//;

					# get the IP for the node
					my $ndIP = xCAT::NetworkUtils->getipaddr($nd);
					chomp $ndIP;

					# get mac for node
					my $mac=$objhash{$nd}{'mac'};

					# foreach line in file
					foreach my $l (@lines) {

						if (( $l =~ /client/) && ($l =~ /$ndIP/)  ) {

							# replace the "0" with the mac
							$l =~ s/ 0 / $mac /;
						} 
					} # end - foreach line

				} # end - foreach node

				# update the file
				unless (open(DHCPFILE, ">$dhcpfile")) {
					my $rsp;
					push @{$rsp->{data}}, "Could not open $dhcpfile.\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
				}
				foreach (@lines)
				{
					#print DHCPFILE $_ . "\n";
					print DHCPFILE $_;
				}
				close DHCPFILE;

				# refresh the dhcpsd daemon
				# my $dcmd=qq~/usr/bin/refresh -s dhcpsd~;
				my $out = xCAT::Utils->runcmd('/usr/bin/refresh -s dhcpsd',0);
				if ($::RUNCMD_RC != 0)
				{
					my $rsp;
					push @{$rsp->{data}}, "Failed to refresh dhcpsd configuration\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
				}

			} # end - dhcpsd.cnf file

			# assume we always need to update the /etc/bootptab file.

			# read the bootptab file into an array
			my $bpfile = "/etc/bootptab";
			open(BPFILE, "<$bpfile");
			my @lines = <BPFILE>;
			close BPFILE;

			# copy file to backup
			my $cpcmd = qq~/usr/bin/cp $bpfile $bpfile.bak~;
			my $output = xCAT::Utils->runcmd("$cpcmd", -1);
			if ($::RUNCMD_RC != 0)
			{
				my $rsp;
				push @{$rsp->{data}}, "Could not copy $bpfile to $bpfile.bak.\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
			}

			foreach my $nd (@nodelist) {
				# get short hostname for node
				$nd =~ s/\..*$//;

				# get mac for node
				my $mac=$objhash{$nd}{'mac'};

				# foreach line in file
				foreach my $l (@lines) {

					# split line
					my ($hn, $rest) = split(/:/, $l);

					# if this is the line for this hostname
					$hn =~ s/\..*$//;
					if ($hn eq $nd) {
						# if it doesn't have ha then add it
						if (!($l =~ /:ha=/)) {
							$l =~ s/:sa/:ha=$mac:sa/;
						}
					}
				} # end - foreach line

			} # end - foreach node

			# update the file
			unless (open(BPFILE, ">$bpfile")) {
				my $rsp;
				push @{$rsp->{data}}, "Could not open $bpfile.\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
			}
			foreach (@lines)
			{
				print BPFILE $_ ;
			}
			close BPFILE;

		} # end - if NEWNAME

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
	# need to replace <shared_root>/etc/.client_data/hosts.<node>
	#   with the contents of the hosts file in <shared_root>/etc
	#   - which is the one from the SPOT
	#
	# doesn't hurt to create new file for all nodes passed in

	my @imgsdone;
	foreach my $n (@nodelist) {
		my $img = $nodeosi{$n};

		$n =~ s/\..*$//; # make sure we have the short hostname
		my $node;
		if ($::NEWNAME)
		{
			# need to use a new name for the node name
			#	- not node hostname
			# "<xcat_node_name>_<image_name>"
			$node = $n . "_" . $img;
		} else {
			$node = $n;
		}

		push(@imgsdone, $img);
		# Only when using a shared_root resource
		if ($imagehash{$img}{shared_root}) {
			my $SRdir = xCAT::InstUtils->get_nim_attr_val( $imagehash{$img}{'shared_root'}, "location", $callback, $Sname, $subreq);
			my $cpcmd = qq~/usr/bin/cp $SRdir/etc/hosts $SRdir/etc/.client_data/hosts.$node 2>/dev/null~;
			my $output = xCAT::Utils->runcmd("$cpcmd", -1);
			if ($::RUNCMD_RC != 0)
			{
				my $rsp;
				push @{$rsp->{data}}, "Could not copy $SRdir/etc/hosts to $SRdir/etc/.client_data/hosts.$node.\n";
				xCAT::MsgUtils->message("E", $rsp, $callback);
			}
		}
	}

    #
    # External NFS support:
    #   For shared_root:
    #       Update shared_root/etc/.client_data/hosts.<nodename>
    #       Update shared_root/etc/.client_data/filesystems.<nodename>
    #   For non-shared_root:
    #       Update root/<nodename>/etc/hosts
    #       Update root/<nodename>/etc/filesystems
    #
	# Note: if "-n" option then we need a NIM name and not the nodename
	#   in some cases - ex. file and dir names
	#   - if NEWNAME then nim name = <nodename>_<osimage name>

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
				my $nimname;
				if ($::NEWNAME)
				{
			 		# need to use a new name for the node name
					#   - not node hostname
					# used for filenames and dirs in shared_root
					# "<xcat_node_name>_<image_name>"
					$snd =~ s/\..*$//; # make sure we have the short hostname
					$nimname = $snd . "_" . $nodeosi{$snd};
				} else {
					$nimname = $snd;
				}

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
                        	$hostfile = "$imgsrdir/etc/.client_data/hosts.$nimname";
                        	$filesystemsfile = "$imgsrdir/etc/.client_data/filesystems.$nimname";
                    	}
                    	else # non-shared_root configuration
                    	{
                        	my $imgrootdir = xCAT::InstUtils->get_nim_attr_val(
                                                          $imagehash{$osimg}{'root'},
                                                          "location", $callback, $Sname, $subreq);
                        	$hostfile = "$imgrootdir/$nimname/etc/hosts";
                        	$filesystemsfile = "$imgrootdir/$nimname/etc/filesystems";
                        	my ($nodehost, $nodeip) = xCAT::NetworkUtils->gethostnameandip($snd);
                        	if (!$nodehost || !$nodeip)
                        	{
                            	my $rsp = {};
                            	$rsp->{data}->[0] = "Can not resolve the node $snd";
                            	xCAT::MsgUtils->message("E", $rsp, $callback);
                            	next;
                        	}
                        	my $tftpdir = xCAT::TableUtils->getTftpDir();
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
                	$filesystemsfile = "$imgsrdir/etc/.client_data/filesystems.$nimname";
            	}
            	else # non-shared_root configuration
            	{
                	my $imgrootdir = xCAT::InstUtils->get_nim_attr_val(
                                                  $imagehash{$osimg}{'root'},
                                                  "location", $callback, $Sname, $subreq);
                	$filesystemsfile = "$imgrootdir/$nimname/etc/filesystems";
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

	# if this is shared_root and "sns" then make a 
	#	backup of the .client_data dir
	#   this will be restored by snmove when failing over to this SN
	if ($sharedinstall eq "sns")
	{
		foreach my $i (@image_names) 
		{

			if ($imagehash{$i}{'shared_root'} )
			{
				my $loc = $lochash{$imagehash{$i}{shared_root}};
				my $cdloc = "$loc/etc/.client_data";	
				# Sname is name of SN as known by management node
				my $snbk = $Sname . "_" . $i;
				my $bkloc = "$loc/$snbk/.client_data";

				my $mkcmd;
				if (! -d $bkloc) 
				{
					# else create dir
					$mkcmd=qq~/usr/bin/mkdir -m 644 -p $bkloc ~;
					my $output = xCAT::Utils->runcmd("$mkcmd", -1);
					if ($::RUNCMD_RC != 0)
					{
						my $rsp;
						push @{$rsp->{data}}, "Could not create $bkloc\n";
						xCAT::MsgUtils->message("E", $rsp, $callback);
					}
				}

				# should only backup files for the specific nodes

				# get list of files from $cdloc dir
				my $rcmd = qq~/usr/bin/ls $cdloc 2>/dev/null~;
				my @rlist = xCAT::Utils->runcmd("$rcmd", -1);
				if ($::RUNCMD_RC != 0)
				{
					my $rsp;
					push @{$rsp->{data}}, "Could not list contents of $cdloc.\n";
					xCAT::MsgUtils->message("E", $rsp, $callback);
					$error++;
				}

				foreach my $nd (@nodelist) {
                	$nd =~ s/\..*$//;

                    # for each file in $cdloc
					my $filestring = "";
					foreach my $f (@rlist) {
						# if file contains node name then copy it
						if ($f =~ /$nd/) {
							$filestring .="$cdloc/$f ";
						}
					}

					if ($filestring) {
						my $ccmd=qq~/usr/bin/cp -p $filestring $bkloc 2>/dev/null~;
						my $output = xCAT::Utils->runcmd("$ccmd", -1);
						if ($::RUNCMD_RC != 0)
						{
							my $rsp;
							push @{$rsp->{data}}, "Could not copy files to $bkloc. \n";
							xCAT::MsgUtils->message("E", $rsp, $callback);
							$error++;
						}
					}
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
			$nodeattrs{$node}{profile}    = $nodeosi{$node};
			$nodeattrs{$node}{provmethod} = $nodeosi{$node};
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

	# check that inetd is active
	$cmd = "/usr/bin/lssrc -s inetd";
	my @output=xCAT::Utils->runcmd($cmd, 0);

	if (grep /\sinoperative/, @output)	
	{
		if ($::VERBOSE)
		{
			my $rsp;
			push @{$rsp->{data}}, "Starting inetd on $Sname.\n";
			xCAT::MsgUtils->message("I", $rsp, $callback);
		}

    	my $scmd = "startsrc -s inetd";
    	my $output = xCAT::Utils->runcmd("$scmd", -1);
    	if ($::RUNCMD_RC != 0)
    	{
        	my $rsp;
        	push @{$rsp->{data}}, "Could not start inetd on $Sname.\n";
        	xCAT::MsgUtils->message("E", $rsp, $callback);
    	}
	}

    if ($::SETUPHANFS)
    {
        # Determine the service nodes pair
        my %snhash = ();  #  keys are all SNs listed in node object defs
        my %xcatmasterhash = ();
        my $setuphanfserr = 0;
        foreach my $tnode (@nodelist)
        {
            # Use hash for performance consideration
            my $sns = $objhash{$tnode}{'servicenode'};
            my @snarray = split(/,/, $sns);
            foreach my $sn (@snarray)
            {
                $snhash{$sn} = 1;
            }

            my $xcatmaster = $objhash{$tnode}{'xcatmaster'};
            $xcatmasterhash{$xcatmaster} = 1;
        }
        if (scalar(keys %snhash) ne 2)
        {
            $setuphanfserr++;
            my $rsp;
            my $snstr = join(',', keys %snhash);
            push @{$rsp->{data}}, "Could not determine the service nodes pair, the service nodes are $snstr.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
        }

        if (scalar(keys %xcatmasterhash) ne 1)
        {
            my %masteriphash = ();
            foreach my $master (keys %xcatmasterhash)
            {
                my $xcatmasterip = xCAT::NetworkUtils->getipaddr($master);
                $masteriphash{$xcatmasterip} = 1;
            }
            if (scalar(keys %masteriphash) ne 1)
            {
                $setuphanfserr++;
                my $rsp;
                my $xcatmasterstr = join(',', keys %xcatmasterhash);
                push @{$rsp->{data}}, "There are more than one xcatmaster for the nodes, the xcatmasters are $xcatmasterstr.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
            }
        }

        my $xcatmasterip = xCAT::NetworkUtils->getipaddr((keys %xcatmasterhash)[0]);
		# get local host ips
        my @allips = xCAT::Utils->gethost_ips();

        my $snlocal;
        my $snremote;
		# get the local and remote hostname
        foreach my $snhost (keys %snhash)
        {
            my $snip = xCAT::NetworkUtils->getipaddr($snhost); 

            if (grep(/^$snip$/, @allips))
            {
                $snlocal = $snhost;
            }
            else
            {
                $snremote = $snhost;
            }
        }

        if (!$snlocal || !$snremote)
        {
            $setuphanfserr++;
            my $rsp;
            my $snstr = join(',', keys %snhash);
            push @{$rsp->{data}}, "Wrong service nodes pair: $snstr\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
        }

        if (!$setuphanfserr)
        {
            my $localip;
            # Get the ip address on the local service node
            my $lscmd = "ifconfig -a | grep 'inet '";
            my $out = xCAT::Utils->runcmd("$lscmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}},
                "Could not run command: $lscmd on node $snlocal.\n";
                xCAT::MsgUtils->message("W", $rsp, $callback);
            }
            else
            {
                foreach my $line (split(/\n/, $out))
                {
                     $line =~ /inet\s+(.*?)\s+netmask\s+(.*?)\s+/;
                     #$1 is ip address, $2 is netmask
                      if ($1 && $2)
                      {
                            my $ip = $1;
                            my $netmask = $2;
                            if(xCAT::NetworkUtils::isInSameSubnet($xcatmasterip, $ip, $netmask, 2))
                            {
                                $localip = $ip;
                                last;
                            }
                      }
                 }
             }
             if (!$localip)
             {
             	my $rsp;
               	push @{$rsp->{data}},
               	"Could not find an ip address in the samesubnet with xcatmaster ip $xcatmasterip on node $snlocal, falling back to service node $snlocal.\n";
              	xCAT::MsgUtils->message("W", $rsp, $callback);
                $localip = xCAT::NetworkUtils->getipaddr($snlocal);
             }
            
            my $remoteip;
            # Get the ip address on the remote service node
            $lscmd = qq~ifconfig -a | grep 'inet '~;
	    $out = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $snremote, $lscmd, 0);
            if ($::RUNCMD_RC != 0)
            {
             	my $rsp;
               	push @{$rsp->{data}},
               	"Could not run command: $lscmd against node $snremote.\n";
              	xCAT::MsgUtils->message("W", $rsp, $callback);
            }
            else
            {
                foreach my $line (split(/\n/, $out))
                {
                     $line =~ /inet\s+(.*?)\s+netmask\s+(.*?)\s+/;
                     #$1 is ip address, $2 is netmask
                      if ($1 && $2)
                      {
                            my $ip = $1;
                            my $netmask = $2;
                            if(xCAT::NetworkUtils::isInSameSubnet($xcatmasterip, $ip, $netmask, 2))
                            {
                                $remoteip = $ip;
                                last;
                            }
                        }
					}
              	}

              	if (!$remoteip)
              	{
             		my $rsp;
               		push @{$rsp->{data}},
               		"Could not find an ip address in the samesubnet with xcatmaster ip $xcatmasterip on node $snremote, falling back to service node $snremote.\n";
              		xCAT::MsgUtils->message("W", $rsp, $callback);
                	$remoteip = xCAT::NetworkUtils->getipaddr($snremote);
              	}

				my $install_dir = xCAT::TableUtils->getInstallDir();
				my $scmd = "lsnfsexp -c";
				my @output = xCAT::Utils->runcmd("$scmd", -1);
				if ($::RUNCMD_RC != 0)
				{
                   	my $rsp;
                    push @{$rsp->{data}}, "Could not list nfs exports on $Sname.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback);
                    $error++;
                }
                my $needexport = 1;
				my $replicastr;
                foreach my $line (@output)
                {
                    next if ($line =~ /^#/);
                    my ($directory,$anonuid,$public,$versions,$exname,$refer,$replica,$allother) = split(':', $line);
					if ($directory eq $install_dir) {
						if ($replica) {

							# get $replicastr 
							my @replist = split(/,/, $replica);
							my ($dir, $repip);
							my $foundlocalip;
							my $foundremoteip;
							foreach my $rep (@replist) {
								($dir, $repip) = split(/@/, $rep);

								if ($remoteip eq $repip)  {
									$foundremoteip++;
								}
								if ($localip eq $repip)  {
                                	$foundlocalip++;
                            	}

								if ($foundlocalip && $foundremoteip) {
									$needexport = 0;
									last;
								}

								if (($remoteip ne $repip) && ($localip ne $repip)) {
									$replicastr .= ":$dir\@$repip";
								}
							}

                    	} else {
                        	my $scmd = "rmnfsexp -d $directory";
                        	my $output = xCAT::Utils->runcmd("$scmd", -1);
                        	if ($::RUNCMD_RC != 0)
                        	{
                            	my $rsp;
                            	push @{$rsp->{data}}, "Could not unexport NFS directory $directory on $Sname.\n";
                            	xCAT::MsgUtils->message("E", $rsp, $callback);
                            	$error++;
							}
                        }
                    }
                }

                if ($needexport)
                {

					# Setup NFSv4 replication
                	if ($::VERBOSE)
                	{
                    	my $rsp;
                    	push @{$rsp->{data}}, "Setting up NFSv4 replication on $Sname.\n";
                    	xCAT::MsgUtils->message("I", $rsp, $callback);
                	}

					# if no replicas
					my $scmd;
				  	if (!$replicastr) { 

                    	$scmd = "exportfs -ua";
                    	my $output = xCAT::Utils->runcmd("$scmd", -1);
                    	if ($::RUNCMD_RC != 0)
                    	{
                        	my $rsp;
                        	push @{$rsp->{data}}, "Could not un-exportfs on $Sname.\n";
                        	xCAT::MsgUtils->message("E", $rsp, $callback);
                        	$error++;
                    	}

                    	$scmd = "chnfs -R on";
                    	$output = xCAT::Utils->runcmd("$scmd", -1);
                    	if ($::RUNCMD_RC != 0)
                    	{
                        	my $rsp;
                        	push @{$rsp->{data}}, "Could not enable NFSv4 replication on $Sname.\n";
                        	xCAT::MsgUtils->message("E", $rsp, $callback);
                        	$error++;
                    	}

                    	$scmd = "stopsrc -g nfs";
                    	$output = xCAT::Utils->runcmd("$scmd", -1);
                    	if ($::RUNCMD_RC != 0)
                    	{
                        	my $rsp;
                        	push @{$rsp->{data}}, "Could not stop nfs group on $Sname.\n";
                        	xCAT::MsgUtils->message("E", $rsp, $callback);
                        	$error++;
                    	}

                    	$scmd = "startsrc -g nfs";
                    	$output = xCAT::Utils->runcmd("$scmd", -1);
                    	if ($::RUNCMD_RC != 0)
                    	{
                        	my $rsp;
                        	push @{$rsp->{data}}, "Could not stop nfs group on $Sname.\n";
                        	xCAT::MsgUtils->message("E", $rsp, $callback);
                        	$error++;
                    	}

                    	$scmd = "exportfs -a";
                    	$output = xCAT::Utils->runcmd("$scmd", -1);
                    	if ($::RUNCMD_RC != 0)
                    	{
                        	my $rsp;
                        	push @{$rsp->{data}}, "Could not exportfs on $Sname.\n";
                        	xCAT::MsgUtils->message("E", $rsp, $callback);
                        	$error++;
                    	}

                   		$scmd = "mknfsexp -d $install_dir -B -v 4 -g $install_dir\@$localip:$install_dir\@$remoteip -x -t rw -r '*'";
				  	} else {

						$scmd = "chnfsexp -d $install_dir -B -v 4 -g $install_dir\@$localip:$install_dir\@$remoteip$replicastr -x -t rw -r '*'";

					}

                    my $output = xCAT::Utils->runcmd("$scmd", -1);
                    if ($::RUNCMD_RC != 0)
                    {
                        my $rsp;
                        push @{$rsp->{data}}, "Could not export directory $install_dir with NFSv4 replication settings on $Sname.\n";
                        xCAT::MsgUtils->message("E", $rsp, $callback);
                        $error++;
                    }

                } # end if $needexport
            } # end else
    } # end if $::SETUPHANFS

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

        xCAT::MsgUtils->message("I", $rsp, $callback);
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
	my $target   = shift;
    my $subreq   = shift;

    if (!$target) {
        $target = xCAT::InstUtils->getnimprime();
    }

    my @nodelist = @{$nodes};
    my %nethash;    # hash of xCAT network definitions for each node
    if ($nethash)
    {
        %nethash = %{$nethash};
    }

    #
    # get all the nim network names and attrs defined on this SN
    #
	my @networks;
    my $cmd = qq~/usr/sbin/lsnim -c networks | /usr/bin/cut -f1 -d' ' 2>/dev/null~;
    my $netw = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $target, $cmd, 0);
    foreach my $line ( split(/\n/, $netw)) {
        $line =~ s/$target:\s+//;
        push(@networks, $line);
    }

    # for each NIM network - get the attrs
    my %NIMnets;
    foreach my $netwk (@networks)
    {
        my $cmd = qq~/usr/sbin/lsnim -Z -a net_addr -a snm $netwk 2>/dev/null~;
		my $out = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $target, $cmd, 0);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not run lsnim command: \'$cmd\' on $target.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }

        my @result;
        foreach my $line ( split(/\n/, $out)) {
            $line =~ s/$target:\s+//;
            push(@result, $line);
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
              qq~/usr/sbin/nim -Fo define -t $devtype -a net_addr=$nethash{$node}{net} -a snm=$nethash{$node}{mask} -a routing1='default $nethash{$node}{gateway}' $nethash{$node}{netname} 2>/dev/null~;

			my $output1 = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $target, $cmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not run \'$cmd\' on $target.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

			# add new network to our list - so we don't try to recreate
			push (@networks, $nethash{$node}{netname});
			$NIMnets{$nethash{$node}{netname}}{'net_addr'}=$nethash{$node}{net};
			$NIMnets{$nethash{$node}{netname}}{'snm'}=$nethash{$node}{mask};

            #
            # create an interface def (if*) for the master
            #
            # first get the if* and cable_type* attrs
            #  - the -A option gets the next avail index for this attr
            my $ifcmd = qq~/usr/sbin/lsnim -A if master 2>/dev/null~;
			my $ifindex = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $target, $ifcmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not run \'$ifcmd\' on $target.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
			$ifindex =~ s/$target:\s+//;
			chomp $ifindex;

            my $ctcmd = qq~/usr/sbin/lsnim -A cable_type master 2>/dev/null~;
			my $ctindex = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $target, $ctcmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not run \'$ctcmd\' on $target.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
			$ctindex =~ s/$target:\s+//;
			chomp $ctindex;

            # get the local adapter hostname for this network
            # get all the possible IPs for the node I'm running on
            my $ifgcmd = "ifconfig -a | grep 'inet '";
			my $out = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $target,$ifgcmd, 0);
				
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not run \'$ifgcmd\' on $target.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

			my @result;
            foreach my $line ( split(/\n/, $out)) {
                $line =~ s/$target:\s+//;
                push(@result, $line);
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
              qq~/usr/sbin/nim -Fo change -a if$ifindex='$nethash{$node}{netname} $adapterhostname 0' -a cable_type$ctindex=N/A master 2>/dev/null~;

			my $output2 = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $target, $chcmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not run \'$chcmd\' on $target.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

            # get the next index for the routing attr
            my $ncmd = qq~/usr/sbin/lsnim -A routing master_net 2>/dev/null~;
			my $rtindex = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $target, $ncmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not run \'$ncmd\' on $target.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
			$rtindex =~ s/$target:\s+//;
            chomp $rtindex;

            # get hostname of primary int - always if1
            my $hncmd = qq~/usr/sbin/lsnim -a if1 -Z master 2>/dev/null~;
			my $ifone = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $target, $hncmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not run \'$hncmd\' on $target.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

			my $junk1;
			my $junk2;
			my $adapterhost;
			my @ifcontent = split('\n',$ifone);
			foreach my $line (@ifcontent) {
				$line =~ s/$target:\s+//;
				next if ($line =~ /^#/);
				($junk1, $junk2, $adapterhost) = split(':', $line);
				last;
			}

            # create static routes between the networks
            my $rtgcmd =
              qq~/usr/sbin/nim -Fo change -a routing$rtindex='master_net $nethash{$node}{gateway} $adapterhost' $nethash{$node}{netname} 2>/dev/null~;
			my $output3 = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $target, $rtgcmd, 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not run \'$rtgcmd\' on $target.\n";
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
	my $sharedinstall = shift;
	my $Sname    = shift;
    my $subreq   = shift;

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
        if ( defined ($::args) && @{$::args} ) 
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
    # Check NFSv4 settings
    if ($::NFSv4)
    {
        my $scmd = "chnfsdom";
        my $nimout = xCAT::Utils->runcmd("$scmd", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not get NFSv4 domain setting.\n";
            if ($::VERBOSE)
            {
                push @{$rsp->{data}}, "$nimout";
            }
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
        my @domains = xCAT::TableUtils->get_site_attribute("domain");
        my $domain = $domains[0];
        if (!$domain)
        {
            my $rsp;
            push @{$rsp->{data}}, "Can not determine domain name, check site table.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
        # NFSv4 domain is not set yet
        if ($nimout =~ /N\/A/)
        {
            $scmd = "chnfsdom $domain";
            $nimout = xCAT::Utils->runcmd("$scmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not change NFSv4 domain to $domain.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$nimout";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }

            $scmd = "stopsrc -g nfs";
            $nimout = xCAT::Utils->runcmd("$scmd", -1);
            sleep 2;
            $scmd = qq~startsrc -g nfs~;
            $nimout = xCAT::Utils->runcmd("$scmd", -1);
        }
        $scmd = "lsnim -FZ -a nfs_domain master";
        $nimout = xCAT::Utils->runcmd("$scmd", -1);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not get NFSv4 domain setting for nim master.\n";
            if ($::VERBOSE)
            {
                push @{$rsp->{data}}, "$nimout";
            }
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }
        # NFSv4 domain is not set to nim master
        if (!$nimout)
        {
            #nim -Fo change -a nfs_domain=$nfsdom master
            $scmd = "nim -Fo change -a nfs_domain=$domain master";
            $nimout = xCAT::Utils->runcmd("$scmd", -1);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp;
                push @{$rsp->{data}}, "Could not set NFSv4 domain with nim master.\n";
                if ($::VERBOSE)
                {
                    push @{$rsp->{data}}, "$nimout";
                }
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            }
        } #end if $domain eq N/A
    } # end if $::NFSv4

    # make sure we have the NIM networks defs etc we need for these nodes
	if (&checkNIMnetworks($callback, \@nodelist, \%nethash, $SNname, $subreq) !=
0)
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

	# run the sync operation on the node to make sure the GPFS res
	#       location is refreshed

	my $scmd = qq~/usr/sbin/sync; /usr/sbin/sync; /usr/sbin/sync~;
	my $output = xCAT::Utils->runcmd("$scmd", -1);
	if ($::RUNCMD_RC != 0)
	{
		my $rsp;
		push @{$rsp->{data}}, "Could not run $scmd on SNname\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
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

					my $loc = dirname(dirname($lochash{$imghash{$image}{$restype}}));
                    chomp $loc;

					#  if shared_root and DEFONLY that means there may
					# already be a directory created.   So we need to 
					# move the existing dir so we can create the resource.
					# we'll move the original dir back after the res
					# is defined
					my $moveit = 0;
					my $origloc;
					my $origlocbak;
					if ( ($::DEFONLY || ($sharedinstall eq "sns")) && ( $restype eq "shared_root")) {


						$origloc =  $lochash{$imghash{$image}{$restype}};
                        $origlocbak = "$origloc.bak";
                        # ex. /install/nim/shared_root/71Bdskls_shared_root
						if (-d $origloc) {
							my $mvcmd = qq~/usr/sbin/mvdir $origloc $origlocbak~;
							my $output = xCAT::Utils->runcmd("$mvcmd", -1);
							if ($::RUNCMD_RC != 0)
							{
								my $rsp;
								push @{$rsp->{data}}, "Could not move $origloc.\n";
								xCAT::MsgUtils->message("E", $rsp, $callback);
							}
							$moveit++;
						}
					}

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

					if ($moveit) {
						# remove the directory
						my $rmcmd = qq~/bin/rm -R $origloc~;
						my $out2 = xCAT::Utils->runcmd("$rmcmd", -1);
                        if ($::RUNCMD_RC != 0)
                        {
                            my $rsp;
                            push @{$rsp->{data}}, "Could not remove $origloc.\n";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                        }

						# move over the original
						# in case it contains info for other node already
						my $mvcmd2 = qq~/usr/sbin/mvdir $origlocbak $origloc~;
						my $out3 = xCAT::Utils->runcmd("$mvcmd2", -1);
                        if ($::RUNCMD_RC != 0)
                        {
                            my $rsp;
                            push @{$rsp->{data}}, "Could not move $origlocbak to $origloc.\n";
                            xCAT::MsgUtils->message("E", $rsp, $callback);
                        }
					}
				}
                # only make lpp_source for standalone type images
                if (   ($restype eq "lpp_source")
                    && ($imghash{$image}{"nimtype"} eq 'standalone'))
                {

                    my $resdir = $lochash{$imghash{$image}{$restype}};
                    # ex. /install/nim/lpp_source/61D_lpp_source

                    my $loc = dirname($resdir);
                    # ex. /install/nim/lpp_source

                    # define the local res
					my $cmd = "/usr/sbin/nim -Fo define -t lpp_source -a server=master -a location=$resdir ";

					my @validattrs = ("verbose", "nfs_vers", "nfs_sec", "packages", "use_source_simages", "arch", "show_progress", "multi_volume", "group");

					my %cmdattrs;
					if ($::NFSv4)
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
                    my $output = xCAT::Utils->runcmd("$cmd", -1);
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
							if ($::NFSv4)
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
					if ($::NFSv4)
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

                # if resolv_conf, bosinst_data, image_data then
                #   the last part of the location is the actual file name
                # 	but not necessarily the resource name!
                my @usefileloc = ("resolv_conf", "bosinst_data", "image_data");
                if (grep(/^$restype$/, @usefileloc))
                {
                    # define the local resource
                    my $cmd;
					$cmd = "/usr/sbin/nim -Fo define -t $restype -a server=master -a location=$lochash{$imghash{$image}{$restype}} ";
					my @validattrs = ("verbose", "nfs_vers", "nfs_sec", "group");
					my %cmdattrs;
					if ($::NFSv4)
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

                    my $resdir = dirname($lochash{$imghash{$image}{$restype}});
                    chomp $resdir;
                    # ex. resdir = /install/nim/spot/612dskls

					# location for spot is odd
					# ex. /install/nim/spot/611image/usr
					# want /install/nim/spot for loc when creating new one
                    my $loc = dirname($resdir);
                    chomp $loc;

					my $spotcmd;
					$spotcmd = "/usr/sbin/nim -Fo define -t spot -a server=master -a location=$loc ";
	
					my @validattrs = ("verbose", "nfs_vers", "nfs_sec", "installp_flags", "auto_expand", "show_progress", "debug");

					my %cmdattrs;
					if ($::NFSv4)
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


                    my $output = xCAT::Utils->runcmd("$spotcmd", -1);
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

		#  try to make sure the spot and boot image is in correct state
		if ($imghash{$image}{spot}) {
			my $ckcmd = qq~/usr/sbin/nim -Fo check $imghash{$image}{spot} 2>/dev/null~;
			my $output = xCAT::Utils->runcmd("$ckcmd", -1);
			if ($::RUNCMD_RC != 0)
			{
				#if ($::VERBOSE) {
				if (0) {
					my $rsp;
					push @{$rsp->{data}}, "Could not run $ckcmd.\n";
					xCAT::MsgUtils->message("I", $rsp, $callback);
				}
			}
		}
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

    if ( defined ($::args) && @{$::args} ) 
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
					'r|remdef'        => \$::REMDEF,
                    'verbose|V' => \$::VERBOSE,
                    'v|version' => \$::VERSION,
        )
      )
    {
        &rmdsklsnode_usage($callback);
        return 1;
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

    if ( defined ($::args) && @{$::args} ) 
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
					'r|remdef'        => \$::REMDEF,
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

	# save the existing bootptab file so it can be restored
	# this is needed when using alternate NIM clients (ex. mkdsklsnode -n)
	# NIM will remove files and entries but we may still need them for the 
	#	nodes since they may be booted using alternate NIM client defs
	# leaving the files and entries in place should not cause any issues
	# since they will be replaced the next time mkdsklsnode is run
	my $bootptabfile = "/etc/bootptab";
	my $bootptabback = "/etc/bootptab.bak";
	my $cpcmd = qq~/usr/bin/cp -p $bootptabfile $bootptabback~;
	my $output = xCAT::Utils->runcmd("$cpcmd", -1);
	if ($::RUNCMD_RC != 0)
	{
		my $rsp;
		push @{$rsp->{data}}, "Could not copy $bootptabfile to $bootptabback.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
	}

	# back up /tftpboot files so they can be restored
	# this is needed when using alternate NIM clients (ex. mkdsklsnode -n)
	my $tftploc = "/tftpboot";
	my $tftpbak = "/tftpboot/bak";

	# make sure to preserve links etc.
	my $cpcmd2 = qq~mkdir -m 644 -p $tftpbak; /usr/bin/cp -h -p $tftploc/* $tftpbak~;
	$output = xCAT::Utils->runcmd("$cpcmd2", -1);

    # for each node
    my @nodesfailed;
    my $error;

    # read nodelist.status
    my $nlhash;
    
    my $nltab = xCAT::Table->new('nodelist');
    if ($nltab)
    {
        $nlhash = $nltab->getNodesAttribs(\@nodelist, ['status']);
    }
    else
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Can not open nodelist table.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
    }

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

		# see if the node is defined as a nim client
		my $lscmd = qq~/usr/sbin/lsnim -l $nodename 2>/dev/null~;
		$output = xCAT::Utils->runcmd("$lscmd", -1);
        if ($::RUNCMD_RC != 0)
        {
            # doesn't exist 
			if ($::VERBOSE)
			{
				my $rsp;
				push @{$rsp->{data}}, "Node \'$nodename\' is not defined.";
				xCAT::MsgUtils->message("I", $rsp, $callback);
			}
			next;
        }

		# see if the node is running
		# check BOTH Mstate and nodestat
		my $nimMstate;
		my $runstatus;

		# check NIM Mstate for node
		my $mstate = xCAT::InstUtils->get_nim_attr_val($nodename, "Mstate", $callback, $Sname, $subreq);
		if ($mstate && ($mstate =~ /currently running/) ) {
			# NIM thinks the node is running
			$nimMstate++;
		}

		# check xCAT nodelist.status for the node
		if ($nlhash && ($nlhash->{$name}->[0]->{'status'} eq 'booted') || ($nlhash->{$name}->[0]->{'status'} eq 'alive') ) {
			$runstatus++;
		}

		#  do we think the node is running?
		my $noderunning = 0;

		# ???  one or the other or both?
		if ($nimMstate || $runstatus) {
    		$noderunning++;
		}

		# if node is running then try to shut it down or give error
		if ( $noderunning ) {
			# REMDEF means just remove the client def 
			#	- don't try to shut down
          	if (!$::REMDEF)
          	{
            	if ($::FORCE)
            	{
                	if ($::VERBOSE)
                	{
                    	my $rsp;
                    	push @{$rsp->{data}}, "Shutting down node \'$name\'";
                    	xCAT::MsgUtils->message("I", $rsp, $callback);
					}

                	# shut down the node
                	my $scmd = "shutdown -F &";
                	my $output;
                	$output =
                  		xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $name, $scmd, 0);
					# assume the node is down now
					$noderunning = 0;
            	}
            	else
            	{
                	# don't remove the def
                	my $rsp;
                	push @{$rsp->{data}},
                  		"The node \'$name\' is currently running. Use the -f flag to force the removal of the NIM client definition.";
                	xCAT::MsgUtils->message("E", $rsp, $callback);
                	$error++;
                	push(@nodesfailed, $nodename);
                	next;
            	}
		  	} # end - if not REMDEF
        } # end of if running shut down

		# if not running or REMDEF then do the remove of the client def
		if (!$noderunning || $::REMDEF) {
        	if ($::VERBOSE)
        	{
            	my $rsp;
            	push @{$rsp->{data}}, "Resetting NIM client node \'$nodename\'";
            	xCAT::MsgUtils->message("I", $rsp, $callback);
        	}

        	# nim -Fo reset c75m5ihp05_53Lcosi
        	my $cmd = "nim -Fo reset $nodename  >/dev/null 2>&1";
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
              		"Deallocating resources for NIM node \'$nodename\'";
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
              		"Removing the NIM definition for NIM node \'$nodename\'";
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
		}
    }    # end - for each node

	#   restore tftpboot and bootptab files
	$cpcmd = qq~/usr/bin/cp -p $bootptabback $bootptabfile; /usr/bin/rm $bootptabback~;
	$output = xCAT::Utils->runcmd("$cpcmd", -1);
	if ($::RUNCMD_RC != 0)
	{
		my $rsp;
		push @{$rsp->{data}}, "Could not copy $bootptabback to $bootptabfile.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
	}

	# make sure to preserve links etc.
	$cpcmd2 = qq~/usr/bin/cp -h -p $tftpbak/* $tftploc; /usr/bin/rm -R $tftpbak 2>/dev/null~;
	$output = xCAT::Utils->runcmd("$cpcmd2", -1);
	if ($::RUNCMD_RC != 0)
	{
		my $rsp;
		push @{$rsp->{data}}, "Could not copy $tftpbak to $tftploc.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
	}

	my  $retcode=0;
    if ($error)
    {
        my $rsp;
        push @{$rsp->{data}},
          "The following NIM client machine definitions could NOT be removed.\n";

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
      "\tmkdsklsnode [-V|--verbose] [-f|--force] [-d|--defonly] [-n|--newname] \n\t\t[-i image_name] [-u|--updateSN] [-l location] [-p|--primarySN]\n\t\t[-b|--backupSN] [-k|--skipsync]\n\t\t[-r|--resonly] noderange [attr=val [attr=val ...]]\n";
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
      "\trmdsklsnode [-V|--verbose] [-f|--force] [-r|--remdef]\n\t\t{-i image_name} [-p|--primarySN] [-b|--backupSN]  noderange";
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
      "\tmknimimage [-V] [-f|--force] [-t nimtype] [-m nimmethod]\n\t\t[-c|--completeosimage] [-r|--sharedroot] [-D|--mkdumpres]\n\t\t[-l <location>] [-s image_source] [-i current_image]\n\t\t[-p|--cplpp] [-n mksysbnode] [-b mksysbfile]\n\t\tosimage_name [attr=val [attr=val ...]]\n";
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
			This uses the NIM "nim -Fo cust" command.
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

	# It's decided to handle install_bundle file by xCAT itself, 
	#	not using nim -o cust anymore
	# nim installs RPMs first then installp fileset, it causes 
	#	perl-Net_SSLeay.pm pre-install verification failed due
	# 	to openssl not installed.

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
      
	my $error;
    if (scalar(@bndlnames) > 0)
    {
		# gather up all installp/rpm/emgr package  names
		my @ilist;
        my @rlist;
        my @elist;
        foreach my $bndl (@bndlnames)
        {
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

            # get the package lists from this bundle file
			# open bundle file
    		unless (open(BNDL, "<$bndlloc"))
    		{
        		my $rsp;
        		push @{$rsp->{data}}, "Could not open $bndlloc.\n";
        		xCAT::MsgUtils->message("E", $rsp, $callback);
        		return 1;
    		}

    		# put installp/rpm/emgr into an array
			my ($junk, $pname);
    		while (my $line = <BNDL>)
    		{
				# skip blank and comment lines
        		next if ($line =~ /^\s*$/ || $line =~ /^\s*#/);
				chomp $line;

				if (($line =~ /\.rpm/) || ($line =~ /^R:/))
				{
					if ($line =~ /:/) {
						($junk, $pname) = split(/:/, $line);
					} else {
						$pname = $line;
					}
					push (@rlist, $pname);
				}
				elsif (($line =~ /epkg\.Z/) || ($line =~ /^E:/)) 
				{
					if ($line =~ /:/) {
						($junk, $pname) = split(/:/, $line);
					} else {
                		$pname = $line;
            		}
            		push (@elist, $pname);
				} else {
					if ($line =~ /:/) {
						($junk, $pname) = split(/:/, $line);
					} else {
						$pname = $line;
            		}
            		push (@ilist, $pname);
				}
			}

    		close(BNDL);

		}			

    	# put installp list into tmp file
    	my $tmp_installp = "/tmp/tmp_installp";
    	my $tmp_rpm = "/tmp/tmp_rpm";
		my $tmp_emgr = "/tmp/tmp_emgr";

		if ( scalar(@ilist)) {

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
			$tmp_installp="";
		}

		if ( scalar(@rlist)) {
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
			$tmp_rpm="";
		}

		if ( scalar(@elist)) {
        	# put emgr list into tmp file
        	unless (open(EFILE, ">$tmp_emgr"))
        	{
            	my $rsp;
            	push @{$rsp->{data}}, "Could not open $tmp_emgr for writing.\n";
            	xCAT::MsgUtils->message("E", $rsp, $callback);
            	return 1;
        	}

        	foreach (@elist)
        	{
            	print EFILE $_ . "\n";
        	}
        	close(EFILE);
    	} else {
        	$tmp_emgr="";
    	}

  		# install installp with file first.
		if ( -e $tmp_installp ){
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

		# then install epkgs.
		if ( -e $tmp_emgr ) {
           	unless (open(EFILE, "<$tmp_emgr"))
           	{
               	my $rsp;
               	push @{$rsp->{data}}, "Could not open $tmp_emgr for reading.\n";
               	xCAT::MsgUtils->message("E", $rsp, $callback);
               	return 1;
           	} else {
           		my @elist = <EFILE>;
           		close(EFILE);
            
           		my $rc = update_spot_epkg($callback, $chroot_epkgloc, $tmp_emgr, $eflags, $spotname, $nimprime, $subreq);
           		if ($rc)
           		{
               		#failed to update RPM
					return 1;
           		}
            
           		# remove tmp file
           		my $cmd = qq~/usr/bin/rm -f $tmp_emgr~;

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

		# then to install RPMs.
		if (-e $tmp_rpm) {
           	unless (open(RFILE, "<$tmp_rpm"))
           	{
               	my $rsp;
              	push @{$rsp->{data}}, "Could not open $tmp_rpm for reading.\n";
               	xCAT::MsgUtils->message("E", $rsp, $callback);
               	return 1;
           	} else {

           		my @rlist = <RFILE>;
           		close(RFILE);
            
           		my $rc = update_spot_rpm($callback, $chroot_rpmloc, \@rlist,$rflags, $spotname, $nimprime, $subreq);
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
        }
        
        # 2. update rpm in spot
        if (scalar @$r_pkgs)
        {
            my $rc = update_spot_rpm($callback, $chroot_rpmloc, \@$r_pkgs,$rflags, $spotname, $nimprime, $subreq);
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

            my $rc = update_spot_epkg($callback, $chroot_epkgloc, $tmp_epkg, $eflags, $spotname, $nimprime, $subreq);
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
	
	/tmp/tmp_installp, /tmp/tmp_rpm, /tmp/tmp_epkg

   	Arguments:
   	callback, installp_bundle location

  	Returns:
	  installp list file, rpm list file, epkg list file

 	Comments:
 	  my ($tmp_installp, $tmp_rpm, $tmp_emgr) = parse_installp_bundle($callback, $bndlloc);

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
	my @elist;

	my ($junk, $pname);
    while (my $line = <BNDL>)
    {
		# skip blank and comment lines
        next if ($line =~ /^\s*$/ || $line =~ /^\s*#/);
		chomp $line;

		if (($line =~ /\.rpm/) || ($line =~ /^R:/))
		{
			if ($line =~ /:/) {
				($junk, $pname) = split(/:/, $line);
			} else {
				$pname = $line;
			}
			push (@rlist, $pname);
		}
		elsif (($line =~ /epkg\.Z/) || ($line =~ /^E:/)) 
		{
			if ($line =~ /:/) {
				($junk, $pname) = split(/:/, $line);
			} else {
                $pname = $line;
            }
            push (@elist, $pname);
		} else {
			if ($line =~ /:/) {
				($junk, $pname) = split(/:/, $line);
			} else {
				$pname = $line;
            }
            push (@ilist, $pname);
		}
	}

    close(BNDL);

    # put installp list into tmp file
    my $tmp_installp = "/tmp/tmp_installp";
    my $tmp_rpm = "/tmp/tmp_rpm";
	my $tmp_emgr = "/tmp/tmp_emgr";

	if ( scalar(@ilist)) {

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
		$tmp_installp="";
	}

	if ( scalar(@rlist)) {
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
		$tmp_rpm="";
	}

	if ( scalar(@elist)) {
        # put emgr list into tmp file
        unless (open(EFILE, ">$tmp_emgr"))
        {
            my $rsp;
            push @{$rsp->{data}}, "Could not open $tmp_emgr for writing.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback);
            return 1;
        }

        foreach (@elist)
        {
            print EFILE $_ . "\n";
        }
        close(EFILE);
    } else {
        $tmp_emgr="";
    }

    return ($tmp_installp, $tmp_rpm, $tmp_emgr);
    
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
        if (($p =~ /\.rpm/) || ($p =~ /^R:/))
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

		elsif (($p =~ /epkg\.Z/) || ($p =~ /^E:/))
        {
			if ($p =~ /:/)
			{
				($junk, $pname) = split(/:/, $p);
			} else {
				$pname = $p;
			}
            push @epkgs, $pname;
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
		push @{$rsp->{data}}, "Command output:\n\n$output\n\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    } 

    if ($::VERBOSE)
    {
        my $rsp;
		push @{$rsp->{data}}, "Command output:\n\n$output\n\n";
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

	my $error;

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
    my $cmd;

	# - need to test rpms to make sure all will install
	#	- add test to rpm cmd if not included in rpm_flags
	#  
	my @doinstall = split /\s+/, $rpmpkgs;
	my @dontinstall=();
	# see if this is an install or update 
	if ( ($rpm_flags =~ /\-i/ ) || ($rpm_flags =~ /install / ) || ($rpm_flags =~ /U/ ) || ($rpm_flags =~ /update / ) ) {

		# if so then do test
		@doinstall = ();

		my $rflags;
		# if the flags don't include test then add it
		if ( !($rpm_flags =~ /\-test/ ) ) {
			$rflags = " $rpm_flags  --test ";
		}

		my $tcmd = qq~$::XCATROOT/bin/xcatchroot -i $spotname "$cdcmd export INUCLIENTS=1; /usr/bin/rpm $rflags $rpmpkgs"~;
		my @outpt = xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $tcmd, 1);

		my @badrpms;
		foreach my $line (@outpt) {
			chomp $line;
			$line =~ s/^\s+//; #remove leading spaces
			my ($first, $second, $rest) = split /\s+/, $line;
			chomp $first;
			if ($first eq 'package') {
				push @badrpms, $second;
			}
		}

		my @origrpms = split /\s+/, $rpmpkgs;
		foreach my $sr ( @origrpms) {
			my $r = $sr;
			$r =~ s/\*$//g;
			my $found=0;
			foreach my $b (@badrpms) {
				if ($b =~ /$r/) {
					push @dontinstall, $sr;
					$found++;
					last;
				}
			}
			if (!$found ) {
				push @doinstall, $sr;
			}
		}	

		if (scalar(@doinstall)) {
			$rpmpkgs= join(' ', @doinstall);
			
		} else {
			$rpmpkgs="";
		}
	}

	if (scalar(@doinstall)) {

		if ($::VERBOSE)
		{
			$cmd = qq~$::XCATROOT/bin/xcatchroot -V -i $spotname "$cdcmd export INUCLIENTS=1; /usr/bin/rpm $rpm_flags $rpmpkgs"~;
		} else {
			$cmd = qq~$::XCATROOT/bin/xcatchroot -i $spotname "$cdcmd export INUCLIENTS=1; /usr/bin/rpm $rpm_flags $rpmpkgs"~;
		}

    	my $output =
      		xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cmd, 0); 

    	if ($::RUNCMD_RC != 0)
    	{
			$error++;
			my $rsp;
			push @{$rsp->{data}}, "Command output:\n\n$output\n\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
    	} elsif ($::VERBOSE)
		{
			my $rsp;
			push @{$rsp->{data}}, "Command output:\n\n$output\n\n";
			xCAT::MsgUtils->message("I", $rsp, $callback);
		}
	}

	if (scalar(@dontinstall)) {
		my $rsp;
		push @{$rsp->{data}}, "The following RPM packages were already installed and were not reinstalled:\n";
		xCAT::MsgUtils->message("W", $rsp, $callback);
		my $rsp2;
		foreach my $rpm (@dontinstall) {
            push @{$rsp2->{data}}, "$rpm";
        }
		push @{$rsp2->{data}}, "\n";
		xCAT::MsgUtils->message("I", $rsp2, $callback);
	}

	if ($error)
	{
		my $rsp;
		push @{$rsp->{data}}, "One or more errors occurred while installing rpm packages in SPOT $spotname.\n";
		xCAT::MsgUtils->message("E", $rsp, $callback);
		return 1;
	} elsif (scalar(@doinstall))  {
		my $rsp;
		push @{$rsp->{data}}, "Completed Installing the following RPM packages in SPOT $spotname:\n";
		foreach my $rpm (@doinstall) {
            push @{$rsp->{data}}, "$rpm";
        }
		push @{$rsp->{data}}, "\n";
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
		(   ....<lpp_source>/emgr/ppc/*.Z )

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
    
	my $cdcmd = qq~cd $source_dir; export INUCLIENTS=1;~;
    my $ecmd  = qq~/usr/sbin/emgr $eflags -f $listfile~;
    my $cmd = qq~$::XCATROOT/bin/xcatchroot -i $spotname "$cdcmd $ecmd"~;

    my $output =
      xCAT::InstUtils->xcmd($callback, $subreq, "xdsh", $nimprime, $cmd, 0);   

    if ($::RUNCMD_RC != 0)
    {
        my $rsp;
        push @{$rsp->{data}},
          "Could not install the interim fix in SPOT $spotname.\n";
		push @{$rsp->{data}}, "One or more errors occurred while trying to install interim fix packages in $spotname.\n";
		push @{$rsp->{data}}, "Command output:\n\n$output\n\n";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    } elsif ($::VERBOSE)
   	{
       	my $rsp;
       	push @{$rsp->{data}}, "Completed Installing the interim fixes in SPOT $spotname.\n";
		push @{$rsp->{data}}, "Command output:\n\n$output\n\n";
       	xCAT::MsgUtils->message("I", $rsp, $callback);
    }    

    return 0;
}

1;
