# IBM(c) 2010 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle xdsh

   Supported command:
         nodenetconn
         ipforward (internal command)

=cut

#-------------------------------------------------------
package xCAT_plugin::route;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use strict;
use xCAT::Table;
use xCAT::Utils;
use xCAT::NetworkUtils;
use xCAT::MsgUtils;
use Getopt::Long;
use xCAT::NodeRange;
use Data::Dumper;
use xCAT::NodeRange;

1;

#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {
            makeroutes => "route",
            ipforward => "route"
           };
}


#-------------------------------------------------------

=head3  preprocess_request

  Preprocess the command

=cut

#-------------------------------------------------------
sub preprocess_request
{

    my $request  = shift;
    my $callback = shift;
    my $sub_req  = shift;
    my $command = $request->{command}->[0];
    my $args    = $request->{arg};

    #if already preprocessed, go straight to request
    if ((defined($request->{_xcatpreprocessed}))
        && ($request->{_xcatpreprocessed}->[0] == 1))
    {
        return [$request];
    }


    if ($command eq "ipforward") {
        my $nodes=$request->{node};
	my @sns=();
	if ($nodes) {
	    @sns=@$nodes;
	}
	#print "sns=@sns\n";
	my @requests=();
	foreach (@sns) {
	    my $reqcopy = {%$request};
	    $reqcopy->{'node'}=[];
	    $reqcopy->{'_xcatdest'}=$_;
	    $reqcopy->{_xcatpreprocessed}->[0] = 1;
	    push @requests, $reqcopy;
	}
	return \@requests;
    } else {
	# parse the options
	@ARGV=();
	if ($args) {
	    @ARGV=@{$args};
	}
	Getopt::Long::Configure("bundling");
	Getopt::Long::Configure("no_pass_through");
	
	my $routelist_in;
	my $delete=0;
	if(!GetOptions(
		'h|help'     => \$::HELP,
		'v|version'  => \$::VERSION,
		'r|routename=s'  => \$routelist_in,
		'd|delete'  => \$delete,
	   ))
	{
	    &usage($callback);
	    return 1;
	}
	
	# display the usage if -h or --help is specified
	if ($::HELP) {
	    &usage($callback);
	    return 0;
	}
	
	
	# display the version statement if -v or --verison is specified
	if ($::VERSION)
	{
	    my $rsp={};
	    $rsp->{data}->[0]= xCAT::Utils->Version();
	    $callback->($rsp);
	    return 0;
	}

        #make sure the input routes are in the routes table.
	if ($routelist_in) {
	    my %all_routes=();
	    my $routestab=xCAT::Table->new("routes", -create =>1);
	    if ($routestab) {
		my @tmp1=$routestab->getAllAttribs(('routename', 'net'));
		if (@tmp1 > 0) {
		    foreach(@tmp1) {
			$all_routes{$_->{routename}} = $_;
			$_->{process} = 0;
		    }
		}
	    }
	    
	    my @badroutes=();
	    foreach(split(',', $routelist_in)) {
		if (!exists($all_routes{$_})) {
		    push(@badroutes, $_);
		} 
	    }
	    if (@badroutes>0) {
		my $rsp={};
		my $badroutes_s=join(',', @badroutes);
		if (@badroutes==1) {
		    $rsp->{error}->[0]= "The route $badroutes_s is not defined in the routes table.";
		} else {
		    $rsp->{error}->[0]= "The routes $badroutes_s are not defined in the routes table.";
		}
		$callback->($rsp);
		return 1;
	    }
	} 

	if (@ARGV == 0) { #no noderange is specifiled, assume it is on the mn
	    my $reqcopy = {%$request};
	    $reqcopy->{_xcatpreprocessed}->[0] = 1;
	    if ($routelist_in) {
		$reqcopy->{routelist}->[0]=$routelist_in;
	    }
	    if ($delete) {
		$reqcopy->{delete}->[0]=1;
	    }
	    return [$reqcopy];
	} else { #noderange is specified, 
	    my $ret=[];
	    my $nr=$ARGV[0];
	    my @noderange = xCAT::NodeRange::noderange($nr, 1);
	    my @missednodes=xCAT::NodeRange::nodesmissed();
	    if (@missednodes > 0) {
		my $rsp={};
		$rsp->{error}->[0]= "Invalide nodes in noderange: " . join(',', @missednodes);
		$callback->($rsp);
		return 1;
	    }
	    my @servicenodes=xCAT::Utils->getSNList();

            #print "noderange=@noderange, missednodes=@missednodes, servicenodes=@servicenodes\n"; 

	    #pick out the service nodes from the node list
	    foreach my $sn (@servicenodes) {
		if (grep /^$sn$/, @noderange) {
		    @noderange=grep(!/^$sn$/, @noderange);
		    my $reqcopy = {%$request};
		    $reqcopy->{_xcatpreprocessed}->[0] = 1;
		    $reqcopy->{'_xcatdest'}	= $sn;	
		    $reqcopy->{node} = [$sn];
		    if ($routelist_in) {
			$reqcopy->{routelist}->[0]=$routelist_in;
		    }
		    if ($delete) {
			$reqcopy->{delete}->[0]=1;
		    }
		    push(@$ret, $reqcopy);
		}
	    }
      
            #now find out the service nodes for each node and 
            #send the request to the service node
	    my $sn_hash = xCAT::Utils->get_ServiceNode(\@noderange, "xcat", "MN");
    
	    # build each request for each service node
	    foreach my $sn (keys %$sn_hash)
	    {
		my $reqcopy = {%$request};
		$reqcopy->{node} = $sn_hash->{$sn};
		$reqcopy->{'_xcatdest'} = $sn;
		$reqcopy->{_xcatpreprocessed}->[0] = 1;
		$reqcopy->{remote}->[0] = 1;
		if ($routelist_in) {
		    $reqcopy->{routelist}->[0]=$routelist_in;
		}
		if ($delete) {
		    $reqcopy->{delete}->[0]=1;
		}
		push(@$ret, $reqcopy);
	    }

	    return $ret;
	}
    }
}

#-------------------------------------------------------

=head3  process_request

  Process the command

=cut

#-------------------------------------------------------
sub process_request
{

    my $request  = shift;
    my $callback = shift;
    my $sub_req  = shift;
    my $command = $request->{command}->[0];

    if ($command eq "makeroutes") {
	return process_makeroutes($request, $callback, $sub_req);
    } elsif ($command eq "ipforward") {
	return process_ipforward($request, $callback, $sub_req);
    }
    return;
}

sub process_makeroutes {
    my $request  = shift;
    my $callback = shift;
    my $sub_req  = shift;
    my $command = $request->{command}->[0];

    my $nodes;
    if (exists($request->{node})) {
	$nodes=$request->{node};
    }

    my $delete=0;
    if (exists($request->{delete})) {
	$delete=$request->{delete}->[0];
    }

    my $remote=0;
    if (exists($request->{remote})) {
	$remote=$request->{remote}->[0];
    }


    my $routelist;
    if (exists($request->{routelist})) {
	$routelist=$request->{routelist}->[0];
    }


    #get all the routes from the routes table
    my %all_routes=();
    my $routestab=xCAT::Table->new("routes", -create =>1);
    if ($routestab) {
	my @tmp1=$routestab->getAllAttribs(('routename', 'net', 'mask', 'gateway', 'ifname'));
	if (@tmp1 > 0) {
	    foreach(@tmp1) {
		$all_routes{$_->{routename}} = $_;
		$_->{process} = 0;
	    }
	}
    }
    
    if ($routelist) {
	foreach(split(',', $routelist)) {
	    $all_routes{$_}->{process}=1;
	    if (($nodes) && ($remote)) {
		$all_routes{$_}->{nodes}=$nodes;
	    }
	}
    } else {
	#get the routes for each nodes from the noderes table (for sn and cn) and site table (for mn)
	if ($nodes) {
	    my $nrtab=xCAT::Table->new("noderes", -create =>1);
	    my $nrhash = $nrtab->getNodesAttribs($nodes, ['routenames']) ;
	    foreach(@$nodes) {
		my @badroutes=();
		my $node=$_;
		my $rn;
		my $ent=$nrhash->{$node}->[0];
		if (ref($ent) and defined $ent->{routenames}) {
		    $rn = $ent->{routenames};
		}
		if ($rn) {
		    my @a=split(',', $rn);
		    my @badroutes=();
		    foreach my $r (@a) {
			if (! exists($all_routes{$r})) {
			    push(@badroutes, $r);
			} else {
			    #print "got here...., remote=$remote\n";
			    $all_routes{$r}->{process}=1;
			    if ($remote) {
				my $pa=$all_routes{$r}->{nodes};
				if ($pa) {
				    push(@$pa, $node);
				} else {
				    $all_routes{$r}->{nodes}=[$node];
				}
			    }
			}
		    }
		    if (@badroutes > 0) {
			my $badroutes_s=join(',', @badroutes);
			my $rsp={};
			if (@badroutes==1) {
			    $rsp->{error}->[0]= "The route $badroutes_s is not defined in the routes table. Please check noderes.routenames for node $node.";
			} else {
			    $rsp->{error}->[0]= "The routes $badroutes_s are not defined in the routes table. Please check noderes.routenames for node $node.";
			}
			$callback->($rsp);
			return 1;
		    }
		} else {
		    my $rsp={};
		    $rsp->{data}->[0]= "No routes defined in noderes.routenames for node $node, skiping $node.";
		    $callback->($rsp);
		}
	    }
	}
	else { #this is mn, get the routes from the site table
	    my @mnroutes = xCAT::Utils->get_site_attribute("mnroutenames");
	    if ($mnroutes[0]) {
		my @a=split(',', $mnroutes[0]);
		my @badroutes=();
		foreach my $r (@a) {
		    if (! exists($all_routes{$r})) {
			push(@badroutes, $r);
		    } else {
			$all_routes{$r}->{process}=1;
		    }
		}
		if (@badroutes > 0) {
		    my $badroutes_s=join(',', @badroutes);
		    my $rsp={};
		    if (@badroutes==1) {
			$rsp->{error}->[0]= "The route $badroutes_s is not defined in the routes table. Please check site.mnroutenames for the management node.";
		    } else {
			$rsp->{error}->[0]= "The routes $badroutes_s are not defined in the routes table. Please check site.mnroutenames for the management node.";
		    }
		    $callback->($rsp);
		    return 1;
		}
	    } else {
		my $rsp={};
		$rsp->{data}->[0]= "No routes defined in the site.mnroutenames for the management node.";
		$callback->($rsp);
		return 1;
	    }
	}
    }

    #print Dumper(%all_routes); 

    #now let's handle the route creatation and deletion
    my @sns=(); 
    my $installdir = xCAT::Utils->getInstallDir();
    while (my ($routename, $route_hash) = each(%all_routes)) {
	if ($route_hash->{process}) {
	    my ($gw_name, $gw_ip)=xCAT::NetworkUtils->gethostnameandip($route_hash->{gateway});
	    push(@sns, $gw_name);

	    if ($remote) { #to the nodes
		my $nodes_tmp=$route_hash->{nodes};
		print "nodes=@$nodes_tmp, remote=$remote, delete=$delete\n";
		my $op="add";
		if ($delete)  { $op="delete"; }
		my $output = xCAT::Utils->runxcmd(
		    {
			command => ["xdsh"], 
			node => $nodes_tmp, 
			arg => ["-e", "/$installdir/postscripts/routeop $op " . $route_hash->{net} . " " . $route_hash->{mask} . " $gw_ip"],
			_xcatpreprocessed => [1],
		    }, 
		    $sub_req, -1, 1);
		my $rsp={};
		$rsp->{data}=$output;
		$callback->($rsp);
	    } else { #local on mn or sn
		if ($delete)  {
		    delete_route($callback, $route_hash->{net}, $route_hash->{mask}, $gw_ip, $gw_name);
		} 
		else {
		    set_route($callback, $route_hash->{net}, $route_hash->{mask}, $gw_ip, $gw_name);
		}
	    }
	}
    }
    

    #not all gateways are service nodes
    my %sn_hash=();
    my @allSN=xCAT::Utils->getAllSN();
    my %allSN_hash=();
    foreach(@allSN) {$allSN_hash{$_}=1;}
    foreach my $sn (@sns) {
	if (exists($allSN_hash{$sn})) {
	    $sn_hash{$sn}=1;
	}
    }

    #update servicenode.ipforward 
    my $sntab=xCAT::Table->new("servicenode", -create => 1,-autocommit => 1);
    my %valuehash=();
    my $value=1;
    if ($delete) {$value=0;}
    foreach my $sn (keys %sn_hash)  {
	$valuehash{$sn} = { ipforward=>$value };
    }
    $sntab->setNodesAttribs(\%valuehash);

    #go to the service nodes to enable/disable ipforwarding
    my @nodes=keys(%sn_hash);
    $sub_req->({
	command=>['ipforward'],
	node=>\@nodes,
	arg=>[$delete]}, 
	       $callback);


}

sub process_ipforward {
    my $request  = shift;
    my $callback = shift;
    my $sub_req  = shift;
    my $args    = $request->{arg};

    my $delete=0;
    if ($args) {
	$delete = $args->[0];
    }
    
    if ($delete) {
	xCAT::NetworkUtils->setup_ip_forwarding(0);
    } else {
	xCAT::NetworkUtils->setup_ip_forwarding(1);
    }

}


sub usage {
    my $cb=shift;
    my $rsp={};

    $rsp->{data}->[0]= "Usage: makeroutes -h";
    $rsp->{data}->[1]= "       makeroutes -v";
    $rsp->{data}->[2]= "       makeroutes [-r routename[,routename...]]";
    $rsp->{data}->[3]= "       makeroutes [-r routename[,routename...]] -d ";
    $rsp->{data}->[4]= "       makeroutes noderange [-r routename[,routename...]]";
    $rsp->{data}->[5]= "       makeroutes noderange [-r routename[,routename...]] -d";
    $cb->($rsp);
}

#check if the route exits or not from the route table
sub route_exists {
    my $net = shift;
    my $mask = shift;
    my $gw_ip = shift;
    my $gw=shift;

    my $islinux=xCAT::Utils->isLinux();
    my $result;
    $result=`netstat -nr|grep $net`;
    if ($? == 0) {
	if ($result) {
            my @b=split('\n', $result);
	    foreach my $tmp (@b) {
		chomp($tmp);
		my @a=split(' ', $tmp);
		if ($islinux) { #Linux
		    if (@a >= 3) {
			my $net1=$a[0];
			my $mask1=$a[2];
			my $gw1=$a[1];
			if (($net1 eq $net) && ($mask1 eq $mask) && (($gw1 eq $gw) || ($gw1 eq $gw_ip)))  {
			    return 1;
			}
		    }
		} 
		else { #AIX
		    if (@a >= 2) {
			my $tmp1=$a[0];
			my $gw1=$a[1];

                        #now convert $mask to bits
			$net =~ /([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/;
			my $netnum = ($1<<24)+($2<<16)+($3<<8)+$4;
                        my $bits=32;
			while (($netnum % 2) == 0) {
			    $bits--;
			    $netnum=$netnum>>1;
			}
			my $tmp2="$net/$bits";
			if (($tmp1 eq $tmp2) && (($gw1 eq $gw) || ($gw1 eq $gw_ip)))  {
			    return 1;
			}
		    }
		}
	    }
	}
    } 
    return 0;
}

# sets the route with given parameters
sub set_route {
    my $callback=shift;
    my $net = shift;
    my $mask = shift;
    my $gw_ip = shift;
    my $gw=shift;

    my $result;
    if (!route_exists($net, $mask, $gw_ip, $gw)) {
	#set temporay route
        my $cmd;
	if (xCAT::Utils->isLinux()) {
	    $cmd="route add -net $net netmask $mask gw $gw_ip";
	} else {
	    $cmd="route add -net $net -netmask $mask $gw_ip";
	}
	#print "cmd=$cmd\n";
	$result=`$cmd 2>&1`;
	if ($? != 0) {
	    my $rsp={};
	    $rsp->{error}->[0]= "$cmd\nerror code=$?, result=$result\n";
	    $callback->($rsp);
	    return 1;
	} else {
	    #TODO: set per permanent route
	}
    }
    return 0;
}

# deletes the route with given parameters
sub delete_route {
    my $callback=shift;
    my $net = shift;
    my $mask = shift;
    my $gw_ip = shift;
    my $gw=shift;

    my $result;
    if (route_exists($net, $mask, $gw_ip, $gw)) {
	#delete  route temporarily
        my $cmd;
	if (xCAT::Utils->isLinux()) {
	    $cmd="route delete -net $net netmask $mask gw $gw_ip";
	} else {
	    $cmd="route delete -net $net -netmask $mask $gw_ip";
	}
	#print "cmd=$cmd\n";
	$result=`$cmd 2>&1`;
	if ($? != 0) {
	    my $rsp={};
	    $rsp->{error}->[0]= "$cmd\nerror code=$?, result=$result\n";
	    $callback->($rsp);
	    return 1;
	} else {
	    #TODO: delete route permanently
	}
    }
    return 0;
}


