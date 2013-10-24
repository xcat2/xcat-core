#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::ServiceNodeUtils;

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
use strict;
#-----------------------------------------------------------------------------

=head3 readSNInfo

  Read resource, NFS server, Master node, OS an ARCH from the database
  for the service node

  Input: service nodename
  Output: Masternode, OS and ARCH
  Example:
    my $retdata = xCAT::ServiceNodeUtils->readSNInfo;
=cut

#-----------------------------------------------------------------------------
sub readSNInfo
{
    my ($class, $nodename) = @_;
    my $rc = 0;
    my $et;
    my $masternode;
    my $os;
    my $arch;
    $rc = xCAT::Utils->exportDBConfig();
    if ($rc == 0)
    {

        if ($nodename)
        {
            $masternode = xCAT::TableUtils->GetMasterNodeName($nodename);
            if (!($masternode))
            {
                xCAT::MsgUtils->message('S',
                                   "Could not get Master for node $nodename\n");
                return 1;
            }

            $et = xCAT::TableUtils->GetNodeOSARCH($nodename);
            if ($et == 1)
            {
                xCAT::MsgUtils->message('S',
                                  "Could not get OS/ARCH for node $nodename\n");
                return 1;
            }
            if (!($et->{'os'} || $et->{'arch'}))
            {
                xCAT::MsgUtils->message('S',
                                  "Could not get OS/ARCH for node $nodename\n");
                return 1;
            }
        }
        $et->{'master'} = $masternode;
        return $et;
    }
    return $rc;
}

#-----------------------------------------------------------------------------

=head3 isServiceReq


  Checks the service node table in the database to see 
  if input Service should be setup on the
  input service node or Management Node (used by AAsn.pm)

  Input:servicenodename,ipaddres(s) and hostnames of service node
  Output:
        hash of services to setup  for this service node
    Globals:
        $::RUNCMD_RC = 0; good
        $::RUNCMD_RC = 1; error 
    Error:
        none
    Example:
      $servicestosetup=xCAT::ServiceNodeUtils->isServiceReq($servicenodename, @serviceip) { blah; }

=cut

#-----------------------------------------------------------------------------
sub isServiceReq
{
    require xCAT::Table;
    my ($class, $servicenodename, $serviceip) = @_;

    # list of all services from service node table
    # note this must be updated if more services added
    my @services = (
                    "nameserver", "dhcpserver", "tftpserver", "nfsserver",
                    "conserver",  "monserver",  "ldapserver", "ntpserver",
                    "ftpserver",  "ipforward"
                    );

    my @ips = @$serviceip;    # list of service node ip addresses and names
    my $rc  = 0;

    $rc = xCAT::Utils->exportDBConfig();    # export DB env
    if ($rc != 0)
    {
        xCAT::MsgUtils->message('S', "Unable export DB environment.\n");
        $::RUNCMD_RC = 1;
        return;

    }

    # get handle to servicenode table
    my $servicenodetab = xCAT::Table->new('servicenode');
    unless ($servicenodetab)
    {
        xCAT::MsgUtils->message('S', "Unable to open servicenode table.\n");
        $::RUNCMD_RC = 1;
        return;    # do not setup anything
    }

    # Are we on the MN 
    my $mname;
    if (xCAT::Utils->isMN()) {
      my @nodeinfo = xCAT::NetworkUtils->determinehostname;
       $mname   = pop @nodeinfo;                    # get hostname
    }

    my $servicehash;
    # read all the nodes from the table, for each service
    foreach my $service (@services)
    {
        my @snodelist = $servicenodetab->getAllNodeAttribs([$service]);

        foreach $serviceip (@ips)    # check the table for this servicenode
        {
            foreach my $node (@snodelist)

            {
                if ($serviceip eq $node->{'node'})
                {                    # match table entry
                    if ($node->{$service})
                    {                # returns service, only if set
                        my $value = $node->{$service};
                        $value =~ tr/a-z/A-Z/;    # convert to upper
                             # value 1 or yes  then we setup the service
                        if (($value eq "1") || ($value eq "YES"))
                        {
                            $servicehash->{$service} = "1";
                        } else {
                            $servicehash->{$service} = "0";
                        }
                    }
                    last; 
                }
            }  
        }

    }
    # if the ftpserver attribute is not defined in the service node table 
    # and we are on
    # the Linux management node, we need to look at site.vsftp
    # if the tftpserver attribute is not defined, then we default it 1
    if (($mname) && (xCAT::Utils->isLinux())) {
      if (!exists($servicehash->{'ftpserver'})) { 
        my @tmp = xCAT::TableUtils->get_site_attribute("vsftp");
        if ($tmp[0] && ($tmp[0] !~ /0|NO|No|no|N|n/ )) {
           $servicehash->{'ftpserver'} = 1;
        }
      }
      if (!exists($servicehash->{'tftpserver'})) { 
           $servicehash->{'tftpserver'} = 1;
      }
    }
    $servicenodetab->close;

    $::RUNCMD_RC = 0;
    return $servicehash;

}

#-----------------------------------------------------------------------------

=head3 getAllSN 
 
    Returns an array of all service nodes from service node table 

    Arguments:
       ALL"  - will also return the management node in the array, if
        if has been defined in the servicenode table 
    Returns:
		array of Service Nodes or empty array, if none
    Globals:
        none
    Error:
        1 - error
    Example:
         @SN=xCAT::ServiceNodeUtils->getAllSN
         @allSN=xCAT::ServiceNodeUtils->getAllSN("ALL")
    Comments:
        none

=cut

#-----------------------------------------------------------------------------
sub getAllSN
{
   
    my ($class, $options) = @_;
    require xCAT::Table;
    # reads all nodes from the service node table
    my @servicenodes;
    my $servicenodetab = xCAT::Table->new('servicenode');
    unless ($servicenodetab)    # no  servicenode table
    {
        xCAT::MsgUtils->message('I', "Unable to open servicenode table.\n");
        $servicenodetab->close;
        return @servicenodes;

    }
    my @nodes = $servicenodetab->getAllNodeAttribs(['tftpserver']);
    foreach my $nodes (@nodes)
    {
          push @servicenodes, $nodes->{node};
    }
    # if did not input "ALL" and there is a MN, remove it
    my @newservicenodes;
    if ((!defined($options)) || ($options ne "ALL")) {   
       my @mname = xCAT::Utils->noderangecontainsMn(@servicenodes);
       if (@mname) { # if there is a MN
        foreach my $node (@servicenodes) {
          # check to see if node in MN list
          if (!(grep(/^$node$/, @mname))) { # if node not in the MN array
              push @newservicenodes, $node;
          }
        }
        $servicenodetab->close;
        return @newservicenodes;  # return without the MN in the array
       }
    }
    $servicenodetab->close;
    return @servicenodes;
}

#-----------------------------------------------------------------------------

=head3 getSNandNodes 
 
    Returns an hash-array of all service nodes and the nodes they service

    Arguments:
       none 
#-----------------------------------------------------------------------------

=head3 getSNandNodes 
 
    Returns an hash-array of all service nodes and the nodes they service

    Arguments:
       none 
    Returns:
	 Service Nodes and the nodes they service or empty , if none
    Globals:
        none
    Error:
        1 - error
    Example:
        $sn=xCAT::ServiceNodeUtils->getSNandNodes()
    Comments:
        none

=cut

#-----------------------------------------------------------------------------
sub getSNandNodes
{

    require xCAT::Table;
    # read all the nodes from the nodelist table
    #  call get_ServiceNode to find which Service Node
    # the node belongs to.
    my %sn;
    my @nodes;
    my $nodelisttab = xCAT::Table->new('nodelist');
    my $recs        = $nodelisttab->getAllEntries();
    foreach (@$recs)
    {
        push @nodes, $_->{node};
    }
    $nodelisttab->close;
    my $sn = xCAT::ServiceNodeUtils->get_ServiceNode(\@nodes, "xcat", "MN");
    return $sn;
}

#-----------------------------------------------------------------------------

=head3 getSNList 
 
	Reads the servicenode table. Will return all the enabled Service Nodes
	that will setup the input Service ( e.g tftpserver,nameserver,etc)
	If service is blank, then will return the list of all enabled Service
	Nodes. 

    Arguments:
       Servicename ( xcat,tftpserver,dhcpserver,conserver,etc) 
       If no servicename, returns all Servicenodes
       "ALL" argument means you also want the MN returned. It can be in the 
       servicenode list.  If no "ALL", take out the MN if it is there. 
    Returns:
	  Array of service node names 
    Globals:
        none
    Error:
        1 - error  
    Example:
         $sn= xCAT::ServiceNodeUtils->getSNList($servicename) { blah; }
         $sn= xCAT::ServiceNodeUtils->getSNList($servicename,"ALL") { blah; }
         $sn= xCAT::ServiceNodeUtils->getSNList() { blah; }
         $sn= xCAT::ServiceNodeUtils->getSNList("","ALL") { blah; }
    Comments:
        none

=cut

#-----------------------------------------------------------------------------
sub getSNList
{
    require xCAT::Table;
    my ($class, $service,$options) = @_;

    # reads all nodes from the service node table
    my @servicenodes;
    my $servicenodetab = xCAT::Table->new('servicenode', -create => 1);
    unless ($servicenodetab)    # no  servicenode table
    {
        xCAT::MsgUtils->message('I', "Unable to open servicenode table.\n");
        return ();
    }
    my @nodes = $servicenodetab->getAllNodeAttribs([$service]);
    $servicenodetab->close;
    foreach my $node (@nodes)
    {
        if ($service eq "")     # want all the service nodes
        {
            push @servicenodes, $node->{node};
        }
        else
        {                       # looking for a particular service
            if ($node->{$service})
            {                   # if null then do not add node
                my $value = $node->{$service};
                $value =~ tr/a-z/A-Z/;    # convert to upper
                     # value 1 or yes or blank then we setup the service
                if (($value == 1) || ($value eq "YES"))
                {
                    push @servicenodes, $node->{node};

                }
            }
        }
    }
    # if did not input "ALL" and there is a MN, remove it
    my @newservicenodes;
    if ((!defined($options)) || ($options ne "ALL")) {   
       my $mname = xCAT::Utils->noderangecontainsMn(@servicenodes);
       if ($mname) { # if there is a MN
        foreach my $nodes (@servicenodes) {
           if ($mname ne ($nodes)){
              push @newservicenodes, $nodes;
           }
        }
        return @newservicenodes;  # return without the MN in the array
       }
    }

    return @servicenodes;
}


#-----------------------------------------------------------------------------

=head3 get_ServiceNode

     Will get the Service node ( name or ipaddress) as known by the Management
	 Node  or Node for the input nodename or ipadress of the node 
         which can be a Service Node.
         If the input node is a Service Node then it's Service node
         is always the Management Node.

     input: list of nodenames and/or node ipaddresses (array ref)
			service name
			"MN" or "Node"  determines if you want the Service node as known
			 by the Management Node  or by the node.

		recognized service names: xcat,tftpserver,
		nfsserver,conserver,monserver

        service "xcat" is used by command like xdsh that need to know the
		service node that will process the command but are not tied to a
		specific service like tftp

		Todo:  Handle  dhcpserver and nameserver from the networks table

	 output: A hash ref  of arrays, the key is the service node pointing to
			 an array of nodes that are serviced by that service node

     Globals:
        $::ERROR_RC
     Error:
         $::ERROR_RC=0 no error $::ERROR_RC=1 error

	 example: $sn =xCAT::ServiceNodeUtils->get_ServiceNode(\@nodes,$service,"MN");
	  $sn =xCAT::ServiceNodeUtils->get_ServiceNode(\@nodes,$service,"Node");
        Note: this rountine is important to hierarchical support in xCAT
              and used in many places.  Any changes to the logic should be
              reviewed by xCAT architecture
=cut

#-----------------------------------------------------------------------------
sub get_ServiceNode
{
    require xCAT::Table;
    my ($class, $node, $service, $request) = @_;
    my @node_list = @$node;
    my $cmd;
    my %snhash;
    my $nodehash;
    my $sn;
    my $nodehmtab;
    my $noderestab;
    my $snattribute;
    my $oshash;
    my $nodetab;
    $::ERROR_RC = 0;

    # determine if the request is for the service node as known by the MN
    # or the node

    if ($request eq "MN")
    {
        $snattribute = "servicenode";

    }
    else    # Node
    {
        $snattribute = "xcatmaster";
    }
    # get site.master this will be the default
    my $master = xCAT::TableUtils->get_site_Master();  
    $noderestab = xCAT::Table->new('noderes');

    unless ($noderestab)    # no noderes table, use default site.master
    {
        xCAT::MsgUtils->message('I',
                         "Unable to open noderes table. Using site->Master.\n");

        if ($master)        # use site Master value
        {
				
            foreach my $node (@node_list)
            {               
					push @{$snhash{$master}}, $node;
            }
        }
        else
        {
            xCAT::MsgUtils->message('E', "Unable to read site Master value.\n");
            $::ERROR_RC = 1;
        }

        return \%snhash;
    }

    if ($service eq "xcat")
    {    # find all service nodes for the nodes in the list

        $nodehash = $noderestab->getNodesAttribs(\@node_list, [$snattribute]);


        foreach my $node (@node_list)
        {
            foreach my $rec (@{$nodehash->{$node}})
            {
                if ($rec and $rec->{$snattribute}) # use noderes.servicenode
                {
                    my $key = $rec->{$snattribute};
                    push @{$snhash{$key}}, $node;
                }
                else  # use site.master
                {    
  		  push @{$snhash{$master}}, $node;
                }
            }
        }

        $noderestab->close;
        return \%snhash;

    }
    else
    {
        if (
            ($service eq "tftpserver")    # all from noderes table
            || ($service eq "nfsserver") || ($service eq "monserver")
          )
        {
            $nodehash =
              $noderestab->getNodesAttribs(\@node_list,
                                           [$service, $snattribute]);
            foreach my $node (@node_list)
            {
                foreach my $rec (@{$nodehash->{$node}})
                {
                    if ($rec and $rec->{$service})
                    {

                        # see if both  MN and Node address in attribute
                        my ($msattr, $nodeattr) = split ':', $rec->{$service};
                        my $key = $msattr;
                        if ($request eq "Node")
                        {
                            if ($nodeattr)    # override with Node, if it exists
                            {
                                $key = $nodeattr;
                            }
                        }
                        push @{$snhash{$key}}, $node;
                    }
                    else
                    {
                        if ($rec and $rec->{$snattribute})    # if it exists
                        {
                            my $key = $rec->{$snattribute};
                            push @{$snhash{$key}}, $node;
                        }
                        else
                        {                                     # use site.master
                            push @{$snhash{$master}}, $node;
                        }
                    }
                }
            }

            $noderestab->close;
            return \%snhash;

        }
        else
        {
            if ($service eq "conserver")
            {

                # read the nodehm table
                $nodehmtab = xCAT::Table->new('nodehm');
                unless ($nodehmtab)    # no nodehm table
                {
                    xCAT::MsgUtils->message('I',
                                            "Unable to open nodehm table.\n");

                    # use servicenode
                    $nodehash =
                      $noderestab->getNodesAttribs(\@node_list, [$snattribute]);
                    foreach my $node (@node_list)
                    {
                        foreach my $rec (@{$nodehash->{$node}})
                        {
                            if ($rec and $rec->{$snattribute})
                            {
                                my $key = $rec->{$snattribute};
                                push @{$snhash{$key}}, $node;
                            }
                            else
                            {    # use site.master
                                push @{$snhash{$master}}, $node;
                            }
                        }
                    }
                    $noderestab->close;
                    return \%snhash;
                }

                # can read the nodehm table
                $nodehash =
                  $nodehmtab->getNodesAttribs(\@node_list, ['conserver']);
                foreach my $node (@node_list)
                {
                    foreach my $rec (@{$nodehash->{$node}})
                    {
                        if ($rec and $rec->{'conserver'})
                        {

                            # see if both  MN and Node address in attribute
                            my ($msattr, $nodeattr) = split ':',
                              $rec->{'conserver'};
                            my $key = $msattr;
                            if ($request eq "Node")
                            {
                                if ($nodeattr
                                  )    # override with Node, if it exists
                                {
                                    $key = $nodeattr;
                                }
                            }
                            push @{$snhash{$key}}, $node;
                        }
                        else
                        {              # use service node for this node
                            $sn =
                              $noderestab->getNodeAttribs($node,
                                                          [$snattribute]);
                            if ($sn and $sn->{$snattribute})
                            {
                                my $key = $sn->{$snattribute};
                                push @{$snhash{$key}}, $node;
                            }
                            else
                            {          # no service node use master
                                push @{$snhash{$master}}, $node;
                            }
                        }
                    }
                }
                $noderestab->close;
                $nodehmtab->close;
                return \%snhash;

            }
            else
            {
                xCAT::MsgUtils->message('E',
                                        "Invalid service=$service input.\n");
                $::ERROR_RC = 1;
            }
        }
    }
    return \%snhash;

}


#-----------------------------------------------------------------------------

=head3 getSNformattedhash

     Will call get_ServiceNode to  get the Service node ( name or ipaddress)
	 as known by the Management
	 Server or Node for the input nodename or ipadress of the node
	 It will then format the output into a single servicenode key with values
	 the list of nodes service by that service node.  This routine will 
	 break up pools of service nodes into individual node in the hash unlike
	 get_ServiceNode which leaves the pool as the key.

	 input:  Same as get_ServiceNode to call get_ServiceNode
			list of nodenames and/or node ipaddresses (array ref)
			service name
			"MN" or "Node"  determines if you want the Service node as known
			 by the Management Node  or by the node.

		recognized service names: xcat,tftpserver,
		nfsserver,conserver,monserver

        service "xcat" is used by command like xdsh that need to know the
		service node that will process the command but are not tied to a
		specific service like tftp


	 output: A hash ref  of arrays, the key is a single service node 
	          pointing to
			 a list of nodes that are serviced by that service node
	        'rra000-m'=>['blade01', 'testnode']
	        'sn1'=>['blade01', 'testnode']
	        'sn2'=>['blade01']
	        'sn3'=>['testnode']

     Globals:
        $::ERROR_RC
     Error:
         $::ERROR_RC=0 no error $::ERROR_RC=1 error

	 example: $sn =xCAT::ServiceNodeUtils->getSNformattedhash(\@nodes,$service,"MN", $type);
	  $sn =xCAT::ServiceNodeUtils->getSNformattedhash(\@nodes,$service,"Node", "primary");

=cut

#-----------------------------------------------------------------------------
sub getSNformattedhash
{
    my ($class, $node, $service, $request, $btype) = @_;
    my @node_list = @$node;
    my $cmd;
    my %newsnhash;

	my $type="";
	if ($btype) {
		$type=$btype;
	}

	# get the values of either the servicenode or xcatmaster attributes
    my $sn = xCAT::ServiceNodeUtils->get_ServiceNode(\@node_list, $service, $request);

    # get the keys which are the service nodes and break apart any pool lists
    # format into individual service node keys pointing to node lists
	if ($sn)
	{
        foreach my $snkey (keys %$sn)
        {
			# split the key if pool of service nodes
			push my @tmpnodes, $sn->{$snkey};
			my @nodes;
			for my $i (0 .. $#tmpnodes) {
				for my $j ( 0 .. $#{$tmpnodes[$i]}) {
					my $check=$tmpnodes[$i][$j];
					push @nodes,$check; 
				}
			}

			# for SN backup we might only want the primary or backup
			my @servicenodes;
			my ($primary, $backup) = split /,/, $snkey;
			if (($primary) && ($type eq "primary")) {
				push @servicenodes, $primary;
			} elsif (($backup) && ($type eq "backup")) {
				push @servicenodes, $backup;
			} else {
				@servicenodes = split /,/, $snkey;
			}

			# now build new hash of individual service nodes
			foreach my $newsnkey (@servicenodes) {
				push @{$newsnhash{$newsnkey}}, @nodes;
			}
		}
	}
    return \%newsnhash;
}

#----------------------------------------------------------------------------

=head3  getAIXSNinterfaces

	Get a list of ip addresses for each service node in a list

	Arguments:
		list of service nodes
	Returns:
		hash of ips for each service node
	Globals:
		none
	Error:
		none
	Example:
		my $sni = xCAT::ServiceNodeUtils->getAIXSNinterfaces(\@servlist, $callback, $subreq);

	Comments:

=cut

#-----------------------------------------------------------------------------
sub getAIXSNinterfaces
{
    my ($class, $list, $callback, $sub_req) = @_;

    my @snlist = @$list;
    my %SNinterfaces;

    # get all the possible IPs for the node I'm running on
    my $ifcmd = "/usr/sbin/ifconfig -a | grep 'inet ' ";
    foreach my $sn (@snlist)
    {
        my $SNIP;
        my $out = xCAT::InstUtils->xcmd($callback, $sub_req, "xdsh", $sn, $ifcmd, 0);
        if ($::RUNCMD_RC != 0)
        {
			my $rsp;
			push @{$rsp->{data}}, "Could not get IP addresses from service node $sn.\n";
			xCAT::MsgUtils->message("E", $rsp, $callback);
            next;
        }

		my @result;
		foreach my $line ( split(/\n/, $out)) {
			$line =~ s/$sn:\s+//;
			push(@result, $line);
		}

		foreach my $int (@result) {
			my ($inet, $SNIP, $str) = split(" ", $int);
			chomp $SNIP;
			$SNIP =~ s/\/.*//; # ipv6 address 4000::99/64
			$SNIP =~ s/\%.*//; # ipv6 address ::1%1/128
            push(@{$SNinterfaces{$sn}}, $SNIP);
        }
    } # end foreach SN
   	return \%SNinterfaces;
}

#-----------------------------------------------------------------------------

=head3  
 
    getSNandCPnodes - Take an array of nodes and returns 
    an array of the service 
    nodes and an array of the computenode . 

    Arguments:
       none 
    Returns:
		array of Service Nodes and/or array of compute nodesarray of compute nodes       empty array, if none
    Globals:
        none
    Error:
        1 - error
    Example:
         xCAT::ServiceNodeUtils->getSNandCPnodes(\@nodes,\@SN,\@CN);
    Comments:
        none

=cut

#-----------------------------------------------------------------------------
sub getSNandCPnodes 
{
   
    my ($class, $nodes,$sn,$cn) = @_; 
    my @nodelist = @$nodes;
    # get the list of all Service nodes
    my @allSN=xCAT::ServiceNodeUtils->getAllSN;
    foreach my $node (@nodelist) {
      if (grep(/^$node$/, @allSN)) { # it is a SN
         push (@$sn,$node);
      } else {  # a CN
         push (@$cn,$node);
      }
    }

    return ; 
}
1;
