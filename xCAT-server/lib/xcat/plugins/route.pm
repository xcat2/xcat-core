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
use xCAT::TableUtils;
use xCAT::ServiceNodeUtils;
use xCAT::NetworkUtils;
use xCAT::MsgUtils;
use Getopt::Long;
use xCAT::NodeRange;
use Data::Dumper;
use xCAT::NodeRange;
use IO::File;
use File::Copy;
use File::Path;
use Sys::Hostname;


my $xcat_config_start="# xCAT_CONFIG_START";
my $xcat_config_end="# xCAT_CONFIG_END";



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
                }
                else {
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
        }
        else { #noderange is specified, 
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
            my @servicenodes=xCAT::ServiceNodeUtils->getSNList();

            #print "noderange=@noderange, missednodes=@missednodes, servicenodes=@servicenodes\n"; 

            #pick out the service nodes from the node list
            foreach my $sn (@servicenodes) {
                if (grep /^$sn$/, @noderange) {
                    @noderange=grep(!/^$sn$/, @noderange);
                    my $reqcopy = {%$request};
                    $reqcopy->{_xcatpreprocessed}->[0] = 1;
                    $reqcopy->{'_xcatdest'} = $sn;
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
            my $sn_hash = xCAT::ServiceNodeUtils->get_ServiceNode(\@noderange, "xcat", "MN");
   
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
    }
    else {
        #get the routes for each nodes from the noderes table (for sn and cn) and site table (for mn)
        if ($nodes) {
            my $nrtab=xCAT::Table->new("noderes", -create =>1);
            my $nrhash = $nrtab->getNodesAttribs($nodes, ['routenames']) ;
            foreach(@$nodes) {
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
                        }
                        else {
                            #print "got here...., remote=$remote\n";
                            $all_routes{$r}->{process}=1;
                            if ($remote) {
                                my $pa=$all_routes{$r}->{nodes};
                                if ($pa) {
                                    push(@$pa, $node);
                                }
                                else {
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
                        }
                        else {
                            $rsp->{error}->[0]= "The routes $badroutes_s are not defined in the routes table. Please check noderes.routenames for node $node.";
                        }
                        $callback->($rsp);
                        return 1;
                    }
                }
                else {
                    my $rsp={};
                    $rsp->{data}->[0]= "No routes defined in noderes.routenames for node $node, skiping $node.";
                    $callback->($rsp);
                }
            }
        }
        else { #this is mn, get the routes from the site table
            my @mnroutes = xCAT::TableUtils->get_site_attribute("mnroutenames");
            if ($mnroutes[0]) {
                my @a=split(',', $mnroutes[0]);
                my @badroutes=();
                foreach my $r (@a) {
                    if (! exists($all_routes{$r})) {
                        push(@badroutes, $r);
                    }
                    else {
                        $all_routes{$r}->{process}=1;
                    }
                }
                if (@badroutes > 0) {
                    my $badroutes_s=join(',', @badroutes);
                    my $rsp={};
                    if (@badroutes==1) {
                        $rsp->{error}->[0]= "The route $badroutes_s is not defined in the routes table. Please check site.mnroutenames for the management node.";
                    }
                    else {
                        $rsp->{error}->[0]= "The routes $badroutes_s are not defined in the routes table. Please check site.mnroutenames for the management node.";
                    }
                    $callback->($rsp);
                    return 1;
                }
            }
            else {
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
    my $installdir = xCAT::TableUtils->getInstallDir();
    while (my ($routename, $route_hash) = each(%all_routes)) {
        if ($route_hash->{process}) {
            my ($gw_name, $gw_ip)=xCAT::NetworkUtils->gethostnameandip($route_hash->{gateway});
            push(@sns, $gw_name);

            if ($route_hash->{net} =~ /:/) {
                # Remove the subnet postfix like /64
                if ($route_hash->{net} =~ /\//) {
                    $route_hash->{net} =~ s/\/.*$//;
                }
                # Remove the "/" from the ipv6 prefixlength
                if ($route_hash->{mask}) {
                    if ($route_hash->{mask} =~ /\//) {
                        $route_hash->{mask} =~ s/^\///;
                    }
                }
            }

            if ($remote) { #to the nodes
                my $nodes_tmp=$route_hash->{nodes};
                #print "nodes=@$nodes_tmp, remote=$remote, delete=$delete\n";
                my $op="add";
                if ($delete)  { $op="delete"; }
                my $output = xCAT::Utils->runxcmd(
                                        {
                                            command => ["xdsh"], 
                                            node => $nodes_tmp, 
                                            arg => ["-e", "/$installdir/postscripts/routeop $op " . $route_hash->{net} . " " . $route_hash->{mask} . " $gw_ip" . " $route_hash->{ifname}"],
                                            _xcatpreprocessed => [1],
                                        }, 
                                        $sub_req, -1, 1);
                my $rsp={};
                $rsp->{data}=$output;
                $callback->($rsp);
            }
            else { #local on mn or sn
                if ($delete)  {
                    delete_route($callback, $route_hash->{net}, $route_hash->{mask}, $gw_ip, $gw_name, $route_hash->{ifname});
                } 
                else {
                    set_route($callback, $route_hash->{net}, $route_hash->{mask}, $gw_ip, $gw_name, $route_hash->{ifname});
                }
            }
        }
    }
    

    #not all gateways are service nodes
    my %sn_hash=();
    my @allSN=xCAT::ServiceNodeUtils->getAllSN();
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
    my $ifname = shift;

    my $islinux=xCAT::Utils->isLinux();

    # ipv6 net
    if ($net =~ /:/) {
        if ($islinux) {
            my $result = `ip -6 route show $net/$mask`;
            # ip -6 route show will return nothing if the route does not exist
            if (!$result || ($? != 0))
            {
                return 0;
            } else {
                return 1;
            }
        } else { # AIX
            # TODO
        }
    } else {
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
                             my $ifname1=$a[7];
                             if (($net1 eq $net) && ($mask1 eq $mask) && (($gw1 eq $gw) || ($gw1 eq $gw_ip) || ($ifname1 eq $ifname)))  {
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
                         } # end if (@a >= 2)
                     } #end else linux/aix
                 } # end foreach
             } # end if ($result)
        } # end if ($? == 0 
    } # end else ipv4/ipv6
    return 0;
}

# sets the route with given parameters
sub set_route {
    my $callback=shift;
    my $net = shift;
    my $mask = shift;
    my $gw_ip = shift;
    my $gw=shift;
    my $ifname=shift;

    my $host=hostname();

    #print "set_route get called\n";

    my $result;
    if (!route_exists($net, $mask, $gw_ip, $gw, $ifname)) {
        #set temporay route
        my $cmd;
        # ipv6 network
        if ($net =~ /:/) {
            if (xCAT::Utils->isLinux()) {
	        if ( $gw_ip eq "" || $gw_ip eq "::" ) {
                    $cmd="ip -6 route add $net/$mask dev $ifname";
		} else {
                    $cmd="ip -6 route add $net/$mask via $gw_ip";
		}
            } else {
                # AIX TODO
            }
        } else {
            if (xCAT::Utils->isLinux()) {
	        if ( $gw_ip eq "" || $gw_ip eq "0.0.0.0" ) {
		    $cmd="route add -net $net netmask $mask dev $ifname";
		} else {
                    $cmd="route add -net $net netmask $mask gw $gw_ip";
		}
            } else {
                $cmd="route add -net $net -netmask $mask $gw_ip";
            }
        }    
        #print "cmd=$cmd\n";
        my $rsp={};
        $rsp->{data}->[0]= "$host: Adding temporary route: $cmd";
        $callback->($rsp);

        $result=`$cmd 2>&1`;
        if ($? != 0) {
            my $rsp={};
            $rsp->{error}->[0]= "$host: $cmd\nerror code=$?, result=$result\n";
            $callback->($rsp);
            #return 1;
        } 
    } else {
        my $rsp={};
        $rsp->{data}->[0]= "$host: The temporary route already exists for $net.";
        $callback->($rsp);
    }

    #handle persistent routes
    if (xCAT::Utils->isLinux()) { #Linux
        my $os = xCAT::Utils->osver();
        #print "os=$os  $net, $mask, $gw_ip, $gw, $ifname\n";
        if ($os =~ /sles/) { #sles
            addPersistentRoute_Sles($callback, $net, $mask, $gw_ip, $gw, $ifname);
        } elsif ($os =~ /ubuntu|debian/) { #ubuntu or Debian?
            addPersistentRoute_Debian($callback, $net, $mask, $gw_ip, $gw, $ifname);
        }
        elsif ($os =~ /rh|fedora|centos/) { #RH, Ferdora, CentOS
            addPersistentRoute_RH($callback, $net, $mask, $gw_ip, $gw, $ifname);
        }   
    } else { #AIX
        # chdev -l inet0 -a route=net,-hopcount,0,,0,192.168.1.1
        # chdev -l inet0 -a route=net, -hopcount,255.255.255.128,,,,,192.168.3.155,192.168.2.1
        # lsattr -El inet0 -a route
        my $rsp={};
        $rsp->{data}->[0]= "$host: Adding persistent route on AIX is not supported yet.";
        $callback->($rsp);
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
    my $ifname=shift;

    my $host=hostname();

    #print "delete_route get called\n";

    my $result;
    if (route_exists($net, $mask, $gw_ip, $gw, $ifname)) {
        #delete  route temporarily
        my $cmd;
        if ($net =~ /:/) {
            if (xCAT::Utils->isLinux()) {
	        if ( $gw_ip eq "" || $gw_ip eq "::" ) {
                    $cmd = "ip -6 route delete $net/$mask dev $ifname";
		} else {
                    $cmd = "ip -6 route delete $net/$mask via $gw_ip";
		}
            } else {
                # AIX TODO
            }
        } else {
            if (xCAT::Utils->isLinux()) {
	        if ( $gw_ip eq "" || $gw_ip eq "0.0.0.0" ) {
                    $cmd="route delete -net $net netmask $mask dev $ifname";
		} else {
                    $cmd="route delete -net $net netmask $mask gw $gw_ip";
		}
            } else {
                $cmd="route delete -net $net -netmask $mask $gw_ip";
            }
        }
        #print "cmd=$cmd\n";
        my $rsp={};
        $rsp->{data}->[0]= "$host: Removing the temporary route: $cmd";
        $callback->($rsp);

        $result=`$cmd 2>&1`;
        if ($? != 0) {
            my $rsp={};
            $rsp->{error}->[0]= "$host: $cmd\nerror code=$?, result=$result\n";
            $callback->($rsp);
        }
    }
    else {
        my $rsp={};
        if ($net =~ /:/) {
            $rsp->{data}->[0]= "$host: The temporary route does not exist for $net/$mask.";
        } else {
            $rsp->{data}->[0]= "$host: The temporary route does not exist for $net.";
        }
        $callback->($rsp);
    }

    #handle persistent route
    if (xCAT::Utils->isLinux()) { #Linux
        my $os = xCAT::Utils->osver();
        if ($os =~ /sles/) { #sles
            deletePersistentRoute_Sles($callback, $net, $mask, $gw_ip, $gw, $ifname);
        } elsif ($os =~ /ubuntu/) { #ubuntu or Debian?
            deletePersistentRoute_Debian($callback, $net, $mask, $gw_ip, $gw, $ifname);
        }
        elsif ($os =~ /rh|fedora|centos/) { #RH, Ferdora 
            deletePersistentRoute_RH($callback, $net, $mask, $gw_ip, $gw, $ifname);
        }   
    }
    else { #AIX
        # chdev -l inet0 -a delroute=net,-hopcount,0,,0,192.168.1.1
        # chdev -l inet0 -a delroute=net,-hopcount,255.255.255.128,,,,,192.168.3.128,192.168.2.1
        my $rsp={};
        $rsp->{data}->[0]= "$host: Removing persistent route on AIX is not supported yet.";
        $callback->($rsp);
    }

    return 0;
}


#set the given route to the configuration file  
sub setConfig {
    my $filename=shift;
    my $new_conf_block=shift;
    #print "filename=$filename\n";

    my $new_config=join("\n", @$new_conf_block);
    my $last_char = substr $new_config,-1,1;
    if ($last_char ne "\n") { $new_config .= "\n"; }

    my $filename_tmp = "$filename.$$";
    open (OUTFILE, '>', $filename_tmp);
    my $found=0;
    if (-f $filename) {
	open (INFILE,  '<', $filename);
	my $inblock=0;
	while (<INFILE>) { 
	    my $line=$_;
	    if (!$inblock) {
		print OUTFILE $line;
	    }
	    if ($line =~ /$xcat_config_start/) {
		$found=1;
		$inblock=1;
		print OUTFILE $new_config; 
	    } elsif ($line =~ /$xcat_config_end/) {
		$inblock=0;
		print OUTFILE "$xcat_config_end\n";
	    }
	}
    }
    if (!$found) {
	print OUTFILE "$xcat_config_start\n";
	print OUTFILE $new_config;  
	print OUTFILE "$xcat_config_end\n";
    } 
    close (INFILE);
    close (OUTFILE);
    copy($filename_tmp, $filename);
    unlink($filename_tmp);
}
  
#gets the xCAT configurations from the given file
sub getConfig {
    my $filename=shift;
    my @output=();
    if (-f $filename) { 
	open(FILE, "<", $filename);
	my $xcatconf = 0;
	my $first=0;
	while (<FILE>) {
	    chomp;
	    if (/$xcat_config_start/) {
		$xcatconf = 1;
		$first=1;
	    }
	    elsif (/$xcat_config_end/) {
		$xcatconf = 0;
	    }
	    if ($first) {
		$first=0;
		next;
	    }
	    
	    if ($xcatconf) {
		push @output, $_;
	    }
	}
    }
    return @output;
}

#add the routes to the /etc/sysconfig/network/routes file
#The format is: destination  gateway  mask  ifname
sub addPersistentRoute_Sles {
    my $callback=shift;
    my $net=shift;
    my $mask=shift;
    my $gw_ip=shift;
    my $gw=shift;
    my $ifname=shift;

    my $host=hostname();
    
    my $filename="/etc/sysconfig/network/routes";
    my @output=getConfig($filename);
    #print "old output=" . join("\n", @output) . "\n";
    my $hasConfiged=0;
    if (@output && (@output > 0)) {
	$hasConfiged=checkConfig_Sles($net, $mask, $gw_ip, $gw, $ifname, \@output);
    }
    #print "hasConfiged=$hasConfiged\n";
    my $new_config;
    if ($net =~ /:/) {
        if ( $gw_ip eq "" || $gw_ip eq "::" ) {
            $new_config = "$net/$mask :: - $ifname\n";
	} else {
            $new_config = "$net/$mask $gw_ip - -\n";
	}
    } else {
        if ( $gw_ip eq "" || $gw_ip eq "0.0.0.0" ) {
            $new_config="$net 0.0.0.0 $mask $ifname\n";
	} else {
            $new_config="$net $gw_ip $mask $ifname\n";
	}
    }
    if (!$hasConfiged) {
	push(@output, $new_config);
	#print "new output=" . join("\n", @output) . "\n";
	#Add the route to the configuration file
        #the format is: destination  gateway  mask  ifname
	setConfig($filename, \@output);

	chomp($new_config);
	my $rsp={};
	$rsp->{data}->[0]= "$host: Added persistent route \"$new_config\" to $filename.";
	$callback->($rsp);
    } else {
	chomp($new_config);
	my $rsp={};
	$rsp->{data}->[0]= "$host: Persistent route \"$new_config\" already exists in $filename.";
	$callback->($rsp);
    }
}

#remove the routes from the /etc/sysconfig/network/routes file
sub deletePersistentRoute_Sles {
    my $callback=shift;
    my $net=shift;
    my $mask=shift;
    my $gw_ip=shift;
    my $gw=shift;
    my $ifname=shift;
    
    my $host=hostname();

    my $filename="/etc/sysconfig/network/routes";
    my @output=getConfig($filename);
    #print "old output=" . join("\n", @output) . "\n";
    my @new_output=();
    my $bigfound=0;
    foreach my $tmp_conf (@output) {
	my $found = checkConfig_Sles($net, $mask, $gw_ip, $gw, $ifname, [$tmp_conf]); 
	if (!$found) {
	    push(@new_output, $tmp_conf);
	} else {
	    $bigfound=1;
	}
    }
    #print "new output=" . join("\n", @new_output) . "\n";
    #set the new configuration to the configuration file
    setConfig($filename, \@new_output);
    if ($bigfound) {
	my $rsp={};
        if ($net =~ /:/) {
            $rsp->{data}->[0]= "$host: Removed persistent route \"$net/$mask $gw_ip\" from $filename.";
        } else {
    	    $rsp->{data}->[0]= "$host: Removed persistent route \"$net $gw_ip $mask $ifname\" from $filename.";
        }
	$callback->($rsp);
    } else {
	my $rsp={};
        if ($net =~ /:/) {
	    $rsp->{data}->[0]= "$host: Persistent route \"$net/$mask $gw_ip\" does not exist in $filename.";
        } else {
	    $rsp->{data}->[0]= "$host: Persistent route \"$net $gw_ip $mask $ifname\" does not exist in $filename.";
        }
	$callback->($rsp);
    }
}



#check if the route is in the SLES network configuration file
sub checkConfig_Sles {
    my $net = shift;
    my $mask = shift;
    my $gw_ip = shift;
    my $gw=shift;
    my $ifname=shift;
    my $output=shift;

    # Format:
    # DESTINATION GATEWAY NETMASK INTERFACE
    # DESTINATION/PREFIXLEN GATEWAY - INTERFACE

    # ipv4 format: 192.168.0.0 207.68.156.51 255.255.0.0 eth1
    # ipv6 format: fd59::/64 fd57:faaf:e1ab:336:21a:64ff:fe01:1 - -
    foreach my $line (@$output) {
	my @a=split(' ', $line);
	my ($net1,$mask1,$gw1,$ifname1);
        if ($net =~ /:/) {
            if (@a>0) {
                my $ipv6net = $a[0];
                ($net1,$mask1) = split("/",$ipv6net);
            }
	    if (@a>1) { 
	        $gw1=$a[1];
	        if ($gw1 eq '-') { $gw1=$gw_ip; }
            }
	    if (@a>3) { 
	        $ifname1=$a[3];
	        if ($ifname1 eq '-') { $ifname1=$ifname;}
	    }

	} else {
	    if (@a>0) { 
	       $net1=$a[0];
	       if ($net1 eq '-') { $net1=$net;}
	   }
	    if (@a>1) { 
	        $gw1=$a[1];
	        if ($gw1 eq '-') { $gw1=$gw_ip; }
	    }
	    if (@a>2) { 
	        $mask1=$a[2];
	        if ($mask1 eq '-') { $mask1=$mask;}
	    }
	    if (@a>3) { 
	        $ifname1=$a[3];
	        if ($ifname1 eq '-') { $ifname1=$ifname;}
	    }
       }

	#print "net=$net1,$net mask=$mask1,$mask gw=$gw1,$gw_ip ifname=$ifname1\n";
	if (($net1 && $net1 eq $net) && ($mask1 && $mask1 eq $mask) && (($gw1 && $gw1 eq $gw) || ($gw1 && $gw1 eq $gw_ip) || ($ifname1 && $ifname1 eq $ifname)))  {
	    return 1;
	}    
    }
    return 0;
}

#add the routes to the /etc/sysconfig/static-routes file
#The format is: any net 172.16.0.0 netmask 255.240.0.0 gw 192.168.0.1 eth0
sub addPersistentRoute_RH {
    my $callback=shift;
    my $net=shift;
    my $mask=shift;
    my $gw_ip=shift;
    my $gw=shift;
    my $ifname=shift;

    my $host=hostname();
    
    my $filename;
    # ipv6
    if ($net =~ /:/) {
        $filename="/etc/sysconfig/static-routes-ipv6";
    } else {
        $filename="/etc/sysconfig/static-routes";
    }
    my @output=getConfig($filename);
    #print "old output=" . join("\n", @output) . "\n";
    my $hasConfiged=0;
    if (@output && (@output > 0)) {
	$hasConfiged=checkConfig_RH($net, $mask, $gw_ip, $gw, $ifname, \@output);
    }
    #print "hasConfiged=$hasConfiged\n";
    my $new_config;
    if ($net =~ /:/) {
        # ifname is required for ipv6 routing
        if (!$ifname) {
	        my $rsp={};
	        $rsp->{data}->[0]= "$host: Could not add persistent route for ipv6 network $net/$mask, the ifname is required in the routes table.";
	        $callback->($rsp);
            return;
        }

        $new_config="$ifname $net/$mask $gw_ip";
    } else {
        if ( $gw_ip eq "" || $gw_ip eq "0.0.0.0" ) {
            $new_config="any net $net netmask $mask dev $ifname\n";
	} else {
            $new_config="any net $net netmask $mask gw $gw_ip\n";
        }
    }
    if (!$hasConfiged) {
	push(@output, $new_config);
	#print "new output=" . join("\n", @output) . "\n";
	#Add the route to the configuration file
        #the format is: destination  gateway  mask  ifname
	setConfig($filename, \@output);
	
	chomp($new_config);
	my $rsp={};
	$rsp->{data}->[0]= "$host: Added persistent route \"$new_config\" to $filename.";
	$callback->($rsp);
    } else {
	chomp($new_config);
	my $rsp={};
	$rsp->{data}->[0]= "$host: Persistent route \"$new_config\" already exists in $filename.";
	$callback->($rsp);
    }
}

#remove the routes from the /etc/sysconfig/static-routes file
sub deletePersistentRoute_RH {
    my $callback=shift;
    my $net=shift;
    my $mask=shift;
    my $gw_ip=shift;
    my $gw=shift;
    my $ifname=shift;

    my $host=hostname();
    
    my $filename;
    # ipv6
    if ($net =~ /:/) {
        $filename="/etc/sysconfig/static-routes-ipv6";
    } else {
        $filename="/etc/sysconfig/static-routes";
    }
    my @output=getConfig($filename);
    #print "old output=" . join("\n", @output) . "\n";
    my @new_output=();
    my $bigfound=0;
    foreach my $tmp_conf (@output) {
	my $found = checkConfig_RH($net, $mask, $gw_ip, $gw, $ifname, [$tmp_conf]); 
	if (!$found) {
	    push(@new_output, $tmp_conf);
	} else {
	    $bigfound=1;
	}
    }
    #print "new output=" . join("\n", @new_output) . "\n";
    #set the new configuration to the configuration file
    setConfig($filename, \@new_output);
    if ($bigfound) {
	my $rsp={};
    if ($net =~ /:/) {
        $rsp->{data}->[0]= "$host: Removed persistent route \"$ifname $net/$mask $gw_ip\" from $filename.";
    } else {
        $rsp->{data}->[0]= "$host: Removed persistent route \"any net $net netmask $mask gw $gw_ip $ifname\" from $filename.";
    }
	$callback->($rsp);
    } else {
	my $rsp={};
    if ($net =~ /:/) {
	    $rsp->{data}->[0]= "$host: Persistent route \"$ifname $net/$mask $gw_ip\" does not exist in $filename.";
    } else {
	    $rsp->{data}->[0]= "$host: Persistent route \"any net $net netmask $mask gw $gw_ip $ifname\" does not exist in $filename.";
    }
	$callback->($rsp);
    }
}

sub checkConfig_RH {
    my $net = shift;
    my $mask = shift;
    my $gw_ip = shift;
    my $gw=shift;
    my $ifname=shift;
    my $output=shift;

    foreach my $line (@$output) {
	my @a=split(' ', $line);
    #The format is: any net 172.16.0.0 netmask 255.240.0.0 gw 192.168.0.1 eth0
    # ipv6 format: eth1 fd60::/64 fd57::214:5eff:fe15:1
	my ($net1,$mask1,$gw1,$ifname1);
    if ($net =~ /:/) {
        $ifname1 = $a[0];
        if (@a>1) {
            my $ipv6net = $a[1];
            ($net1,$mask1) = split("/",$ipv6net);
        }
        if (@a>2) {
            $gw1 = $a[2];
        }
    } else {
	    if (@a>2) { 
	        $net1=$a[2];
	        if ($net1 eq '-') { $net1=$net;}
	    }
	    if (@a>4) { 
	        $mask1=$a[4];
	        if ($mask1 eq '-') { $mask1=$mask;}
    	}
    	if (@a>6) { 
	        if ( $a[5] eq 'dev' ) {
		    $ifname1=$a[6];
                    if ($ifname1 eq '-') { $ifname1=$ifname;}
		} else {
	            $gw1=$a[6];
	            if ($gw1 eq '-') { $gw1=$gw_ip; }
		}
	    }
    }

	#print "net=$net1,$net mask=$mask1,$mask gw=$gw1,$gw_ip ifname=$ifname1,ifname\n";
	if (($net1 && $net1 eq $net) && ($mask1 && $mask1 eq $mask) && (($gw1 && $gw1 eq $gw) || ($gw1 && $gw1 eq $gw_ip) || ($ifname1 && $ifname1 eq $ifname)))  {
	    return 1;
	}    
    }
    return 0;
}


sub addPersistentRoute_Debian{
    my $callback = shift;
    my $net = shift;
    my $mask = shift;
    my $gw_ip = shift;
    my $gw_name = shift;
    my $ifname = shift;
    my $host=hostname();
    my $conf_file = "/etc/network/interfaces.d/$ifname";
    my $cmd = '';
    my $route_conf = '';

    preParse_Debian();

    #ipv6
    if ( $net =~ /:/){
	if ( $gw_ip eq "" || $gw_ip eq "::" ) {
            $cmd = "grep \"$net/$mask dev $ifname\" $conf_file";
            $route_conf = "  up route -A inet6 add $net/$mask dev $ifname \n  down route -A inet6 del $net/$mask dev $ifname \n";
	} else {
            $cmd = "grep \"$net/$mask gw $gw_ip\" $conf_file";
            $route_conf = "  up route -A inet6 add $net/$mask gw $gw_ip \n  down route -A inet6 del $net/$mask gw $gw_ip \n";
	}
    }
    else { #ipv4
        $cmd = "grep \"-net $net netmask $mask gw $gw_ip\" $conf_file";
	if ( $gw_ip eq "" || $gw_ip eq "0.0.0.0" ) {
            $route_conf = "  up route add -net $net netmask $mask dev $ifname \n  down route del -net $net netmask $mask dev $ifname \n";
	} else {
	    $route_conf = "  up route add -net $net netmask $mask gw $gw_ip \n  down route del -net $net netmask $mask gw $gw_ip\n";
	}
    }

    #fine the corresponding config in the config file
    my @returninfo = `$cmd`;
    if ( @returninfo ){
        my $rsp={};
        $rsp->{data}->[0]= "$host: Persistent route \"$returninfo[0]\" already exists in $conf_file.";
        callback->($rsp);
        return;
    }

    #add the configuration to the config file
    my $readyflag = 0;
    open(FH, "<", $conf_file);
    my @content = <FH>;
    close(FH);

    #read each line of the file and find the insert place
    open(FH, ">", $conf_file);
    foreach my $line ( @content ){
        #add the route line at the end of this dev part
        if (( $readyflag == 1 ) && ( $line =~ /iface|modprobe/ )){
            $readyflag = 0;
            print FH $route_conf;
        }

        if ( $line =~ /iface $ifname/ ){
            $readyflag = 1;
        }
        
        print FH $line;
    }
    
    #the dev is the last one, add the route at the end of the file
    if ( $readyflag == 1 ){
        print FH $route_conf;
    }
    
    close(FH);
}

sub deletePersistentRoute_Debian{
    my $callback=shift;
    my $net=shift;
    my $mask=shift;
    my $gw_ip=shift;
    my $gw=shift;
    my $ifname=shift;

    my $host=hostname();
    my $conf_file = "/etc/network/interfaces.d/$ifname";
    my $match = "";
    my $modflag = 0;

    preParse_Debian();
    #ipv6
    if ( $net =~ /:/){
        if ( $gw_ip eq "" || $gw_ip eq "::" ) {
            $match = "$net/$mask dev $ifname";
	} else {
            $match = "$net/$mask gw $gw_ip";
	}
    }
    else {
        if ( $gw_ip eq "" || $gw_ip eq "0.0.0.0" ) {
            $match = "net $net netmask $mask dev $ifname";
	} else {
            $match = "net $net netmask $mask gw $gw_ip";
	}
    }

    open(FH, "<", $conf_file);
    my @lines = <FH>;
    close(FH);

    open(FH, ">", $conf_file);
    foreach my $line ( @lines ){
        #match the route config, jump to next line
        if ( $line =~ /$match/ ){
            $modflag = 1;
        }
        else{
            print FH $line;
        }
    }
    close(FH);

    my $rsp = {};
    if ( $modflag ){
        $rsp->{data}->[0]= "$host: Removed persistent route \"$match\" from $conf_file.";
    }
    else{
        $rsp->{data}->[0]= "$host: Persistent route \"$match\" does not exist in $conf_file.";
    }

    $callback->($rsp);
    
}

sub preParse_Debian{
    my $configfile;
    
    open(FH, "<", "/etc/network/interfaces");
    my @lines = <FH>;
    close(FH);

    if ($lines[0] =~ /XCAT_CONFIG/i){
        return;
    }

    unless ( -e "/etc/network/interfaces.bak" ){
        copy ("/etc/network/interfaces", "/etc/network/interfaces.bak");
    }

    unless ( -d "/etc/network/interfaces.d" ){
        mkpath( "/etc/network/interfaces.d" );
    }
    
    open(FH, ">", "/etc/network/interfaces");
    print FH "#XCAT_CONFIG\n";
    print FH "source /etc/network/interfaces.d/* \n";
    close(FH);

    foreach my $line ( @lines ){
        if ( $line =~ /^\s*$/){
            next;
        }

        if ( $line =~ /^#.*/ ){
            next;
        }
        
        my @attr = split /\s+/, $line;
        if ( $attr[0] =~ /auto|allow-hotplug/){
            my $i = 1;
            while ( $i < @attr ){
                open(SFH, ">", "/etc/network/interfaces.d/$attr[$i]");
                print SFH "$attr[0] $attr[$i]\n";
                close(SFH);
                print FH "source /etc/network/interfaces.d/$attr[$i] \n";
                $i = $i + 1;
            }
        }
        elsif ($attr[0] =~ /mapping|iface/){
            $configfile = "/etc/network/interfaces.d/$attr[1]";
            open(SFH, ">>", $configfile);
            unless ( -e $configfile){
                print SFH "auto $attr[1] \n";
            }
            print SFH $line;
            close(SFH);
        }
        else{
            open(SFH, ">>", $configfile);
            print SFH $line;
            close(SFH);
        }
    }

    return;
}


