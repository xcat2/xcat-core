package xCAT_plugin::nodestat;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";


use strict;
use warnings;



use Socket;
use IO::Handle;
use Getopt::Long;
use Data::Dumper;
use xCAT::GlobalDef;
use xCAT::NetworkUtils;


my %nodesetstats;
my %chainhash;
my %default_ports = (
    'ftp' => '21',
    'ssh' => '22',
    'sshd' => '22',
    'pbs' => '15002',
    'pbs_mom' => '15002',
    'xend' => '8002',
    'll' => '9616',
    'loadl' => '9616',
    'loadl_master' => '9616',
    'loadleveler' => '9616',
    'gpfs' => '1191',
    'rdp' => '3389',
    'msrpc' => '135',
    );

sub handled_commands {
   return { 
      nodestat => 'nodestat',
      nodestat_internal => 'nodestat',
   };
}

sub pinghost {
   my $node = shift;
   my $rc = system("ping -q -n -c 1 -w 1 $node > /dev/null");
   if ($rc == 0) {
      return 1;
   } else {
      return 0;
   }
}

sub nodesockopen {
   my $node = shift;
   my $port = shift;
   my $socket;
   my $addr = gethostbyname($node);
   my $sin = sockaddr_in($port,$addr);
   my $proto = getprotobyname('tcp');
   socket($socket,PF_INET,SOCK_STREAM,$proto) || return 0;
   connect($socket,$sin) || return 0;
   return 1;
}

sub installer_query {
   my $node = shift;
   my $destport = 3001;
   my $socket;
   my $text = "";
   my $proto = getprotobyname('tcp');
   socket($socket,PF_INET,SOCK_STREAM,$proto) || return 0;
   my $addr = gethostbyname($node);
   my $sin = sockaddr_in($destport,$addr);
   connect($socket,$sin) || return 0;
   print $socket "stat \n";
   $socket->flush;
   while (<$socket>) { 
      $text.=$_;
   }
   $text =~ s/\n.*//;
   return $text;
   close($socket);
}


sub getstat {
   my $response = shift;
   foreach (@{$response->{node}}) {
        $nodesetstats{$_->{name}->[0]} = $_->{data}->[0];
   }
}

#-------------------------------------------------------

=head3  preprocess_request

  Check and setup for hierarchy 

=cut

#-------------------------------------------------------
sub preprocess_request
{
    my $req = shift;
    my $cb  = shift;
    my %sn;
    if (defined $req->{_xcatpreprocessed}->[0] && $req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }
    #exit if preprocessed

    my $command = $req->{command}->[0];
    if ($command eq "nodestat") { 

	@ARGV=();
	my $args=$req->{arg};  
	if ($args) {
	@ARGV = @{$args};
	} 
	
	# parse the options
	$::UPDATE=0;
	$::QUITE=0;
	$::MON=0;
	$::POWER=0;
	#Getopt::Long::Configure("posix_default");
	#Getopt::Long::Configure("no_gnu_compat");
	Getopt::Long::Configure("bundling");
	$Getopt::Long::ignorecase=0;
	if (!GetOptions(
		 'm|usemon' => \$::MON,
		 'q|quite'   => \$::QUITE, #this is a internal flag used by monitoring
		 'u|updatedb'   => \$::UPDATE,
		 'p|powerstat'   => \$::POWER,
		 'h|help'     => \$::HELP,
		 'v|version'  => \$::VERSION))
	{
	    &usage($cb);
	    return(1);
	}
	if ($::HELP) {
	    &usage($cb);
	    return(0);
	} 
	if ($::VERSION) {
	    my $version = xCAT::Utils->Version();
	    my $rsp={};
	    $rsp->{data}->[0] = "$version";
	    xCAT::MsgUtils->message("I", $rsp, $cb);
	    return(0);
	} 
	my $nodes    = $req->{node};
	if (!$nodes)
	{
	    &usage($cb);
	    return (1);
	}
	
	$req->{'update'}->[0]=$::UPDATE;
	$req->{'quite'}->[0]=$::QUITE;
        $req->{'mon'}->[0]=$::MON;
        $req->{'power'}->[0]=$::POWER;
	return [$req];
    }
    
    #the following is for nodestat_internal command
    my $nodes    = $req->{node};
    my $service  = "xcat";
    my @requests;
    if ($nodes) { 
	my $usenmapfrommn=0;
	if (-x '/usr/bin/nmap' or -x '/usr/local/bin/nmap') {
	    my $sitetab = xCAT::Table->new('site');
	    if ($sitetab) {
		(my $ref) = $sitetab->getAttribs({key => 'useNmapfromMN'}, 'value');
		if ($ref) {
		    if ($ref->{value} =~ /1|yes|YES|Y|y/) { $usenmapfrommn=1; }
		}
	    }
	}

	#get monsettings
	my %apps = ();
        my $mon=$req->{'mon'}->[0];
        if ($mon == 1) { %apps=getStatusMonsettings(); }
   
        #if no apps specified in the monsetting table, add sshd, pbs and xend
	if (keys(%apps) == 0) {
	    $apps{'sshd'}->{'group'} = "ALL";   #ALL means anything on the nodelist table, it is different from all
	    $apps{'sshd'}->{'port'} = "22"; 
 	    $apps{'pbs'}->{'group'} = "ALL"; 
	    $apps{'pbs'}->{'port'} = "15002"; 
	    $apps{'xend'}->{'group'} = "ALL"; 
	    $apps{'xend'}->{'port'} = "8002"; 
            $apps{'rdp'}->{'group'} = "ALL";
            $apps{'rdp'}->{'port'} = "3389";
            $apps{'msrpc'}->{'group'} = "ALL";
            $apps{'msrpc'}->{'port'} = "135";
            $apps{'APPS'}=['sshd', 'pbs', 'xend'];
        } else {
	    #go thorugh the settings and put defaults in
	    foreach my $app (keys(%apps)) {
                if ($app eq 'APPS') { next; }
		if (!exists($apps{$app}->{'group'})) { $apps{$app}->{'group'} = "ALL"; }
		if (exists($apps{$app}->{'cmd'}) || exists($apps{$app}->{'dcmd'}) || exists($apps{$app}->{'lcmd'})) { next; }
		if (exists($apps{$app}->{'port'})) { next; }
		#add port number in if nothing is specified
		if (exists($default_ports{$app})) { $apps{$app}->{'port'} = $default_ports{$app}; }
		else {
		    my $p=`grep "^$app" /etc/services`;
		    if ($? == 0) {
			my @a_list=sort(split('\n', $p));
			my @a_temp=split('/',$a_list[0]);
			my @a=split(' ', $a_temp[0]);
			$apps{$app}->{'port'}=$a[1];
		    } else {
			my $rsp={};
			$rsp->{data}->[0]= "Cannot find port number for application $app. Please either specify a port number or a command in monsetting table for $app.";;
			xCAT::MsgUtils->message("I", $rsp, $cb);
			return (0);
		    }
		}
	    }

	    #always add sshd
	    if (!exists($apps{'ssh'}) || !exists($apps{'sshd'}) ) { 
		$apps{'sshd'}->{'group'} = "ALL"; 
		$apps{'sshd'}->{'port'} = "22"; 
                my $pa=$apps{'APPS'};
                push @$pa, 'sshd';
	    }
	}

	#print Dumper(%apps);
	# find service nodes for requested nodes
	# build an individual request for each service node
	my $sn = xCAT::Utils->get_ServiceNode($nodes, $service, "MN");

        #get the member for each group
        my %groups=();
	foreach my $app (keys %apps) {
	    if ($app eq 'APPS') { next; }
	    my $group=$apps{$app}->{'group'};
	    if (($group) && ($group ne "ALL") && (! exists($groups{$group}))) {
		my @tmp_nodes = xCAT::NodeRange::noderange($group);
		foreach (@tmp_nodes) {
		    $groups{$group}->{$_}=1;
		}
	    }
	}

	# build each request for each service node
        my $all_apps=$apps{'APPS'};
        my %all_porthash=(); #stores all the port apps if usenmapfrommn=1
	my %lcmdhash=(); #('myapp2,myapp3'=> {
	                 #       lcmd=>'/tmp/mycmd1,/usr/bin/date',
	                 #       node=>[node1,node2]
	                 #     }
	                 #)
	foreach my $snkey (keys %$sn)
	{
	    my $reqcopy = {%$req};
	    $reqcopy->{node} = $sn->{$snkey};
            $reqcopy->{'_xcatdest'} = $snkey;
            $reqcopy->{_xcatpreprocessed}->[0] = 1;

	    $reqcopy->{'useNmapfromMN'}->[0]=$usenmapfrommn;
            $reqcopy->{'allapps'}=$all_apps;

            my %porthash=(); #('sshd,ll'=> {
                             #       port=>'22,5001',
                             #       node=>[node1,node2]
                             #     }
                             #)
	    my %cmdhash=();  #('gpfs,myapp'=> {
                             #       cmd=>'/tmp/mycmd1,/usr/bin/date',
                             #       node=>[node1,node2]
                             #     }
                             #)
            my %dcmdhash=(); #('myapp2,myapp3'=> {
                             #       dcmd=>'/tmp/mycmd1,/usr/bin/date',
                             #       node=>[node1,node2]
                             #     }
                             #)
	    my @nodes_for_sn=@{$sn->{$snkey}};
           
            foreach my $node (@nodes_for_sn) {
		my @ports;
                my @portapps;
                my @cmds;
                my @cmdapps;
                my @dcmds;
                my @dcmdapps;
		my @lcmdapps;
		my @lcmds;
		foreach my $app (keys %apps) {
		    if ($app eq 'APPS') { next; }
		    my $group=$apps{$app}->{'group'};
		    if (($group eq "ALL") || ($groups{$group}->{$node})) {
                        #print "app=$app\n";
			if (exists($apps{$app}->{'port'})) {
			    push @ports, $apps{$app}->{'port'};
			    push @portapps, $app;
			}
			elsif (exists($apps{$app}->{'cmd'})) {
			    push @cmds, $apps{$app}->{'cmd'};
			    push @cmdapps, $app;
			}
			elsif (exists($apps{$app}->{'dcmd'})) {
			    push @dcmds, $apps{$app}->{'dcmd'};
			    push @dcmdapps, $app;
			}
			elsif (exists($apps{$app}->{'lcmd'})) {
			    push @lcmds, $apps{$app}->{'lcmd'};
			    push @lcmdapps, $app;
			}
		    }
		}
		#print "ports=@ports\n";
                #print "portapps=@portapps\n";
                #print "cmds=@cmds\n";
                #print "cmdapps=@cmdapps\n";
                #print "dcmds=@dcmds\n";
                #print "dcmdapps=@dcmdapps\n";
                if (@portapps>0) {
                    my $tmpapps=join(',', @portapps);
		    if (($usenmapfrommn==1) && (@cmdapps==0) && (@dcmdapps==0) && (@lcmdapps==0)) {
			#this is the case where mn handles ports for all nodes using nmap
                        #The current limitation is that when there are cmd or dcmd specified for the node
                        # nmap has to be done on the service node because if both mn and sn update the appstatus
                        # one will overwites the other. 
			if (exists($all_porthash{$tmpapps})) {
			    my $pa=$all_porthash{$tmpapps}->{'node'};
			    push @$pa, $node;
			} else {
			    $all_porthash{$tmpapps}->{'node'}=[$node];
			    $all_porthash{$tmpapps}->{'port'}=join(',', @ports);
			}
		    } else { 
			if (exists($porthash{$tmpapps})) {
			    my $pa=$porthash{$tmpapps}->{'node'};
			    push @$pa, $node;
			} else {
			    $porthash{$tmpapps}->{'node'}=[$node];
			    $porthash{$tmpapps}->{'port'}=join(',', @ports);
			}
		    }
		}
                if (@cmdapps>0) {
                    my $tmpapps=join(',', @cmdapps);
		    if (exists($cmdhash{$tmpapps})) {
			my $pa=$cmdhash{$tmpapps}->{'node'};
                        push @$pa, $node;
		    } else {
			$cmdhash{$tmpapps}->{'node'}=[$node];
                        $cmdhash{$tmpapps}->{'cmd'}=join(',', @cmds);
		    }
		}
                if (@dcmdapps>0) {
                    my $tmpapps=join(',', @dcmdapps);
		    if (exists($dcmdhash{$tmpapps})) {
			my $pa=$dcmdhash{$tmpapps}->{'node'};
                        push @$pa, $node;
		    } else {
			$dcmdhash{$tmpapps}->{'node'}=[$node];
                        $dcmdhash{$tmpapps}->{'dcmd'}=join(',', @dcmds);
		    }
		}
                if (@lcmdapps>0) {
                    my $i=0;
                    foreach my $lapp (@lcmdapps) {
			if (exists($lcmdhash{$lapp})) {
			    my $pa=$lcmdhash{$lapp}->{'node'};
			    push @$pa, $node;
			} else {
			    $lcmdhash{$lapp}->{'node'}=[$node];
			    $lcmdhash{$lapp}->{'lcmd'}=$lcmds[$i];
			}
                        $i++;
		    }
		}
	    } #end foreach (@nodes_for_sn)

            #print Dumper(%porthash);
            #print "cmdhash=" . Dumper(%cmdhash);
            #now push the settings into the requests
	    my $i=1;
            if ((keys(%porthash) == 0) && (keys(%cmdhash) == 0) && (keys(%dcmdhash) == 0) && (keys(%lcmdhash) == 0)) { next; }
            foreach my $tmpapps (keys %porthash) {
		$reqcopy->{'portapps'}->[0]= scalar keys %porthash;
                $reqcopy->{"portapps$i"}->[0]= $tmpapps;
                $reqcopy->{"portapps$i" . "port"}->[0]= $porthash{$tmpapps}->{'port'};
                $reqcopy->{"portapps$i" . "node"} = $porthash{$tmpapps}->{'node'};;
                $i++;
	    }
            $i=1;
            foreach my $tmpapps (keys %cmdhash) {
		$reqcopy->{'cmdapps'}->[0]= scalar keys %cmdhash;
                $reqcopy->{"cmdapps$i"}->[0]= $tmpapps;
                $reqcopy->{"cmdapps$i" . "cmd"}->[0]= $cmdhash{$tmpapps}->{'cmd'};
                $reqcopy->{"cmdapps$i" . "node"} = $cmdhash{$tmpapps}->{'node'};;
                $i++;
	    }
            $i=1;
            foreach my $tmpapps (keys %dcmdhash) {
		$reqcopy->{'dcmdapps'}->[0]= scalar keys %dcmdhash;
                $reqcopy->{"dcmdapps$i"}->[0]= $tmpapps;
                $reqcopy->{"dcmdapps$i" . "dcmd"}->[0]= $dcmdhash{$tmpapps}->{'dcmd'};
                $reqcopy->{"dcmdapps$i" . "node"} = $dcmdhash{$tmpapps}->{'node'};
		$i++;
	    }


	    #done
	    push @requests, $reqcopy;
	} #enf sn_key


	#print "apps=" . Dumper(%apps);

        #mn handles all nmap when useNmapfromMN=1 on the site table
        if (($usenmapfrommn == 1) && (keys(%all_porthash) > 0)) {
	    my @hostinfo=xCAT::Utils->determinehostname();
	    my %iphash=();
	    foreach(@hostinfo) {$iphash{$_}=1;}
            my $handled=0;
            foreach my $req (@requests) {
		my $currsn=$req->{'_xcatdest'};
		if (exists($iphash{$currsn}))  {
		    my $i=1;
		    foreach my $tmpapps (keys %all_porthash) {
			$req->{'portapps'}->[0]= scalar keys %all_porthash;
			$req->{"portapps$i"}->[0]= $tmpapps;
			$req->{"portapps$i" . "port"}->[0]= $all_porthash{$tmpapps}->{'port'};
			$req->{"portapps$i" . "node"} = $all_porthash{$tmpapps}->{'node'};;
                        $i++;
		    }
                    $handled=1;
                    last;
		}
	    }

	    if (!$handled) {
		my $reqcopy = {%$req};
		$reqcopy->{_xcatpreprocessed}->[0] = 1;
		$reqcopy->{'useNmapfromMN'}->[0]=$usenmapfrommn;
		$reqcopy->{'allapps'}=$all_apps;
		my $i=1;
		foreach my $tmpapps (keys %all_porthash) {
		    $reqcopy->{'portapps'}->[0]= scalar keys %all_porthash;
		    $reqcopy->{"portapps$i"}->[0]= $tmpapps;
		    $reqcopy->{"portapps$i" . "port"}->[0]= $all_porthash{$tmpapps}->{'port'};
		    $reqcopy->{"portapps$i" . "node"} = $all_porthash{$tmpapps}->{'node'};;
                    $i++;
		}
		push @requests, $reqcopy;
	    }
	}

  
	#if ($usenmapfrommn) { 
	#    my $reqcopy = {%$req};
	#    $reqcopy->{'update'}->[0]=$::UPDATE;
	#    $reqcopy->{'useNmapfromMN'}->[0]=1;
	#    if (!$::UPDATE) {
	#	push @requests, $reqcopy;
	#	return \@requests; #do not distribute, nodestat seems to lose accuracy and slow down distributed, if using nmap
	#    }
	#}

        #now handle local commands
	#print "lcmdhash=" . Dumper(%lcmdhash);
        if (keys(%lcmdhash) > 0) {
	    my @hostinfo=xCAT::Utils->determinehostname();
	    my %iphash=();
	    foreach(@hostinfo) {$iphash{$_}=1;}
            my $handled=0;
            foreach my $req (@requests) {
		my $currsn=$req->{'_xcatdest'};
		if (exists($iphash{$currsn}))  {
		    my $i=1;
		    foreach my $lapp (keys %lcmdhash) {
			$req->{'lcmdapps'}->[0]= scalar keys %lcmdhash;
			$req->{"lcmdapps$i"}->[0]= $lapp;
			$req->{"lcmdapps$i" . "cmd"}->[0]= $lcmdhash{$lapp}->{'lcmd'};
			$req->{"lcmdapps$i" . "node"} = $lcmdhash{$lapp}->{'node'};;
                        $i++;
		    }
                    $handled=1;
                    last;
		}
	    }

	    if (!$handled) {
		my $reqcopy = {%$req};
		$reqcopy->{_xcatpreprocessed}->[0] = 1;
		$reqcopy->{'allapps'}=$all_apps;
		my $i=1;
		foreach my $lapp (keys %lcmdhash) {
		    $reqcopy->{'lcmdapps'}->[0]= scalar keys %lcmdhash;
		    $reqcopy->{"lcmdapps$i"}->[0]= $lapp;
		    $reqcopy->{"lcmdapps$i" . "cmd"}->[0]= $lcmdhash{$lapp}->{'lcmd'};
		    $reqcopy->{"lcmdapps$i" . "node"} = $lcmdhash{$lapp}->{'node'};;
                    $i++;
		}
		push @requests, $reqcopy;
	    }
	}	
    }

    return \@requests;
}

sub interrogate_node { #Meant to run against confirmed up nodes
    my $node=shift;
    my $doreq=shift;
    my $p_tmp=shift;
    my %portservices = %$p_tmp;

    my $status = "";
    my $appsd=""; #detailed status
    my $ret={};
    $ret->{'status'}="ping";

    foreach my $port (keys(%portservices)) {
	if (nodesockopen($node,$port)) {
	    $status.=$portservices{$port} . ",";
	    $appsd.=$portservices{$port} . "=up,";
	} else {
	    $appsd.=$portservices{$port} . "=down,";
	}
    }

    $status =~ s/,$//;
    $appsd =~ s/,$//;
    $ret->{'appsd'}=$appsd;
    if ($status) {
	$ret->{'appstatus'}=$status;
        return $ret;
    }
    if ($status = installer_query($node)) {
	$ret->{'status'}=$status;
        return  $ret;
    } else { #pingable, but no *clue* as to what the state may be
         $doreq->({command=>['nodeset'],
                  node=>[$node],
                  arg=>['stat']},
                  \&getstat);
         $ret->{'status'} =  'ping '.$nodesetstats{$node};
         return $ret;
     }
}

sub process_request_nmap {
   my $request = shift;
   my $callback = shift;
   my $doreq = shift;
   my $nodelist=shift;
   my $p_tmp=shift;
   my %portservices = %$p_tmp;
   my @nodes =();
   if ($nodelist) { @nodes=@$nodelist;}

   my %nodebyip;
   my @livenodes;
   my %unknownnodes;
   my $chaintab = xCAT::Table->new('chain',-create=>0);
   if ($chaintab) {
	%chainhash = %{$chaintab->getNodesAttribs(\@nodes,['currstate'])};
   }
   foreach (@nodes) {
	$unknownnodes{$_}=1;
	my $ip = undef;
        $ip = xCAT::NetworkUtils->getipaddr($_);
        if( !defined $ip) {
                my %rsp;
                $rsp{name}=[$_];
                $rsp{data} = [ "Please make sure $_ exists in /etc/hosts or DNS" ];
                $callback->({node=>[\%rsp]});
        } else {
            $nodebyip{$ip} = $_;
        }
   }

   my $ret={};
   my $node;
   my $fping;
   my $ports = join ',',keys %portservices;
   my %deadnodes;
   foreach (@nodes) {
       $deadnodes{$_}=1;
   }
   #print "nmap -PE --send-ip -p $ports,3001 ".join(' ',@nodes) . "\n";
   # open($fping,"nmap -PE --send-ip -p $ports,3001 ".join(' ',@nodes). " 2> /dev/null|") or die("Can't start nmap: $!");
   open($fping,"nmap -PE --send-ip -p $ports,3001 ".join(' ',@nodes). " 2> /dev/null|") or die("Can't start nmap: $!");
   my $currnode='';
   my $port;
   my $state;
   my %states;
   my %rsp;
   my $installquerypossible=0;
   my @nodesetnodes=();
   while (<$fping>) {
      if (/Interesting ports on ([^ ]*) / or /Nmap scan report for ([^ ]*)/) {
          my $tmpnode=$1;
          if ($currnode) {     #if still thinking about last node, flush him out
              my $status = join ',',sort keys %states ;
              my $appsd="";
              foreach my $portnum(keys %portservices) {
                  my $app_t=$portservices{$portnum};
		  if ($states{$app_t}) {$appsd .= $app_t . "=up,";}
		  else {$appsd .= $app_t . "=down,";}
	      }
	      $appsd =~ s/,$//;

              if ($status or ($installquerypossible and $status = installer_query($currnode))) { #pingable, but no *clue* as to what the state may be
                  $ret->{$currnode}->{'status'}="ping";
                  $ret->{$currnode}->{'appstatus'}=$status;
                  $ret->{$currnode}->{'appsd'}=$appsd;
                  $currnode="";
                  %states=();
              } else {
                 push @nodesetnodes,$currnode; #Aggregate call to nodeset
              }
          }
          $currnode=$tmpnode;

          my $nip;
          if ($nip = xCAT::NetworkUtils->getipaddr($currnode)) { #reverse lookup may not resemble the nodename, key by ip
              if ($nodebyip{$nip}) {
                 $currnode = $nodebyip{$nip};
              }
          }
          $installquerypossible=0; #reset possibility indicator
          %rsp=();
          unless ($deadnodes{$1}) {
              my $shortname;
              foreach (keys %deadnodes) {
                  if (/\./) {
                      $shortname = $_;
                      $shortname =~ s/\..*//;
                  }
                  if ($currnode =~ /^$_\./ or ($shortname and $shortname eq $currnode)) {
                      $currnode = $_;
                      last;
                  }
              }
          }
          delete $deadnodes{$currnode};
      } elsif ($currnode) {
          #if (/^MAC/) {  #oops not all nmap records end with MAC
          if (/^PORT/) { next; }
          ($port,$state) = split;
          if ($port and $port =~ /^(\d*)\// and $state eq 'open') {
              if ($1 eq "3001" and $chainhash{$currnode}->[0]->{currstate} =~ /^install/) {
                $installquerypossible=1; #It is possible to actually query node
              } elsif ($1 ne "3001") {
                $states{$portservices{$1}}=1;
              }
          }
      } 
   }

   if ($currnode) {
       my $status = join ',',sort keys %states ;
       my $appsd="";
       foreach my $portnum(keys %portservices) {
	   my $app_t=$portservices{$portnum};
	   if ($states{$app_t}) {$appsd .= $app_t . "=up,";}
	   else {$appsd .= $app_t . "=down,";}
       }
       $appsd =~ s/,$//;
   
       if ($status or ($installquerypossible and $status = installer_query($currnode))) { #pingable, but no *clue* as to what the state may be
	   $ret->{$currnode}->{'status'}="ping";
	   $ret->{$currnode}->{'appstatus'}=$status;
	   $ret->{$currnode}->{'appsd'}=$appsd;
	   $currnode="";
	   %states=();
       } else {
	   push @nodesetnodes,$currnode; #Aggregate call to nodeset
       }
   }
   
    if (@nodesetnodes) {
        $doreq->({command=>['nodeset'],
                  node=>\@nodesetnodes,
                  arg=>['stat']},
                  \&getstat);
        foreach (@nodesetnodes) {
              $ret->{$_}->{'status'}=$nodesetstats{$_};
        }
    }
    foreach $currnode (sort keys %deadnodes) {
	$ret->{$currnode}->{'status'}="noping";
    }

   return $ret;
}


sub process_request_port {
   my $request = shift;
   my $callback = shift;
   my $doreq = shift;
   my $nodelist=shift;
   my $p_tmp=shift;
   my %portservices = %$p_tmp;
   my @nodes = ();
   if ($nodelist) { @nodes=@$nodelist;}

   my %unknownnodes;
   foreach (@nodes) {
	$unknownnodes{$_}=1;
	my $packed_ip = undef;
        $packed_ip = xCAT::NetworkUtils->getipaddr($_);
        if( !defined $packed_ip) {
                my %rsp;
                $rsp{name}=[$_];
                $rsp{data} = [ "Please make sure $_ exists in /etc/hosts" ];
                $callback->({node=>[\%rsp]});
        }
   }

   my $status={};

   if (@nodes>0) {
       my $node;
       my $fping;
       open($fping,"fping ".join(' ',@nodes). " 2> /dev/null|") or die("Can't start fping: $!");
       while (<$fping>) {
	   my %rsp;
	   my $node=$_;
	   $node =~ s/ .*//;
	   chomp $node;
	   if (/ is alive/) {
               $status->{$node} = interrogate_node($node,$doreq, $p_tmp);
	   } elsif (/is unreachable/) {
               $status->{$node}->{'status'}="noping";
	   } elsif (/ address not found/) {
	       $status->{$node}->{'status'}="nosuchhost";
	   }
       }
   }

   return $status;
}   


sub process_request_local_command {
   my $request = shift;
   my $callback = shift;
   my $doreq = shift;
   my $nodelist=shift;
   my $p_tmp=shift;
   my %cmdhash = %$p_tmp;

   my @nodes = ();
   if ($nodelist) { @nodes=@$nodelist;}

   my $status={};

   if (@nodes>0) {
       foreach my $tmp_cmds (keys %cmdhash) {
           my @cmds=split(',', $tmp_cmds);
           my @apps=split(',', $cmdhash{$tmp_cmds});
	   my $index=0;
           foreach my $cmd (@cmds) {
               my $nodes_string=join(',', @nodes);
	       my $ret=`$cmd $nodes_string`; 
	       #print "ret=$ret\n";
	       if (($? ==0) && ($ret)) {
		   my @ret_array=split('\n', $ret);
                   foreach(@ret_array) {
                       my @a=split(':', $_);
                       chomp($a[1]);
		       if (exists($status->{$a[0]})) {
			   $status->{$a[0]} .= "," . $apps[$index] . "=" . $a[1];
		       } else {
			   $status->{$a[0]} = $apps[$index] . "=" . $a[1];;
		       }
		   }
	       }
               $index++;
	   }
       }
   }

   return $status;
}   


sub process_request_remote_command {
   my $request = shift;
   my $callback = shift;
   my $doreq = shift;
   my $nodelist=shift;
   my $p_tmp=shift;
   my %cmdhash = %$p_tmp;
   my @nodes = ();
   if ($nodelist) { @nodes=@$nodelist;}

   my $status={};

   if (@nodes>0) {
       foreach my $tmp_cmds (keys %cmdhash) {
           my @cmds=split(',', $tmp_cmds);
           my @apps=split(',', $cmdhash{$tmp_cmds});
	   my $index=0;
           foreach my $cmd (@cmds) {
               my $nodes_string=join(',', @nodes);
               #print "XCATBYPASS=Y xdsh $nodes_string $cmd\n";
	       my $ret=`XCATBYPASS=Y xdsh $nodes_string $cmd`; 
	       if ($ret) {
		   my @ret_array=split('\n', $ret);
                   foreach(@ret_array) {
                       my @a=split(':', $_, 2);
                       chomp($a[1]); #remove newline
		       $a[1] =~ s/^\s+//; #remove leading white spaces
		       $a[1] =~ s/\s+$//; #remove tailing white spaces

		       if (exists($status->{$a[0]})) {
			   $status->{$a[0]} .= "," . $apps[$index] . "=" . $a[1];
		       } else {
			   $status->{$a[0]} = $apps[$index] . "=" . $a[1];;
		       }
		   }
	       }
               $index++;
	   }
       }
   }

   return $status;
}   

sub process_request {
   my $request = shift;
   my $callback = shift;
   my $doreq = shift;
   %nodesetstats=();
   my $command = $request->{command}->[0];
   my $separator="XXXXXYYYYYZZZZZ";
	my $usefping;
	if (ref $request->{arg}) {
		@ARGV=@{$request->{arg}};
		GetOptions(	
			'f' => \$usefping
		);
	}


   if ($command eq "nodestat_internal") {
      
       #if ( -x '/usr/bin/nmap' ) {
       #    my %portservices = (
       #	   '22' => 'sshd',
       #	   '15002' => 'pbs',
       #	   '8002' => 'xend',
       #	   );
       #
       #    return process_request_nmap($request, $callback, $doreq, $request->{node}, \%portservices);
       # }
       
       #handle ports and nodelist.status
       my $status={};
       if (exists($request->{'portapps'})) {
	   for (my $i=1; $i<=$request->{'portapps'}->[0]; $i++) {
	       my %portservices=();
	       my @apps=split(',', $request->{"portapps$i"}->[0]);
	       my @ports=split(',', $request->{"portapps$i" . "port"}->[0]);
	       my $nodes=$request->{"portapps$i" . "node"};
	       for (my $j=0; $j <@ports; $j++) {
		   $portservices{$ports[$j]}=$apps[$j];
	       } 
	       
	       my $ret={};
	       if ( not $usefping and -x '/usr/bin/nmap' ) {
		   $ret=process_request_nmap($request, $callback, $doreq, $nodes, \%portservices);
	       }  else {
		   $ret=process_request_port($request, $callback, $doreq, $nodes, \%portservices);
	       } 
	       %$status=(%$status, %$ret);
	   }
       }
       
      
       #handle local commands
       if (exists($request->{'cmdapps'})) {
	   for (my $i=1; $i<=$request->{'cmdapps'}->[0]; $i++) {
	       my %cmdhash=();
	       my @apps=split(',', $request->{"cmdapps$i"}->[0]);
	       my @cmds=split(',', $request->{"cmdapps$i" . "cmd"}->[0]);
	       my $nodes=$request->{"cmdapps$i" . "node"};
	       for (my $j=0; $j <@cmds; $j++) {
		   $cmdhash{$cmds[$j]}=$apps[$j];
	       } 
	       
	       my $ret = process_request_local_command($request, $callback, $doreq, $nodes, \%cmdhash);
	       #print Dumper($ret);

	       foreach my $node1 (keys(%$ret)) {
		   if (exists($status->{$node1})) {
		       my $appstatus=$status->{$node1}->{'appstatus'};
		       if ($appstatus) { $status->{$node1}->{'appstatus'} .= "," . $ret->{$node1}; }
		       else { $status->{$node1}->{'appstatus'} = $ret->{$node1}; }
		       my $appsd=$status->{$node1}->{'appsd'};
		       if ($appsd) { $status->{$node1}->{'appsd'} .= "," . $ret->{$node1}; }
		       else { $status->{$node1}->{'appsd'} = $ret->{$node1}; }
		   } else {
		       $status->{$node1}->{'appstatus'} = $ret->{$node1};
		       $status->{$node1}->{'appsd'} = $ret->{$node1};
		   }
	       }    
	   }
       }

       #handle local l commands 
       if (exists($request->{'lcmdapps'})) {
	   for (my $i=1; $i<=$request->{'lcmdapps'}->[0]; $i++) {
	       my %cmdhash=();
	       my @apps=split(',', $request->{"lcmdapps$i"}->[0]);
	       my @cmds=split(',', $request->{"lcmdapps$i" . "cmd"}->[0]);
	       my $nodes=$request->{"lcmdapps$i" . "node"};
	       for (my $j=0; $j <@cmds; $j++) {
		   $cmdhash{$cmds[$j]}=$apps[$j];
	       } 
	              
	       my $ret = process_request_local_command($request, $callback, $doreq, $nodes, \%cmdhash);

	       foreach my $node1 (keys(%$ret)) {
		   if (exists($status->{$node1})) {
		       my $appstatus=$status->{$node1}->{'appstatus'};
		       if ($appstatus) { $status->{$node1}->{'appstatus'} .= "," . $ret->{$node1}; }
		       else { $status->{$node1}->{'appstatus'} = $ret->{$node1}; }
		       my $appsd=$status->{$node1}->{'appsd'};
		       if ($appsd) { $status->{$node1}->{'appsd'} .= "," . $ret->{$node1}; }
		       else { $status->{$node1}->{'appsd'} = $ret->{$node1}; }
		   } else {
		       $status->{$node1}->{'appstatus'} = $ret->{$node1};
		       $status->{$node1}->{'appsd'} = $ret->{$node1};
		   }
		   
	       }    
	   }
       }
       
       
       #handle remote commands
       if (exists($request->{'dcmdapps'})) {
	   for (my $i=1; $i<=$request->{'dcmdapps'}->[0]; $i++) {
	       my %dcmdhash=();
	       my @apps=split(',', $request->{"dcmdapps$i"}->[0]);
	       my @dcmds=split(',', $request->{"dcmdapps$i" . "dcmd"}->[0]);
	       my $nodes=$request->{"dcmdapps$i" . "node"};
	       for (my $j=0; $j <@dcmds; $j++) {
		   $dcmdhash{$dcmds[$j]}=$apps[$j];
	       } 
	       
	       my $ret = process_request_remote_command($request, $callback, $doreq, $nodes, \%dcmdhash);
	       foreach my $node1 (keys(%$ret)) {
		   if (exists($status->{$node1})) {
		       my $appstatus=$status->{$node1}->{'appstatus'};
		       if ($appstatus) { $status->{$node1}->{'appstatus'} .= "," . $ret->{$node1}; }
		       else { $status->{$node1}->{'appstatus'} = $ret->{$node1}; }
		       my $appsd=$status->{$node1}->{'appsd'};
		       if ($appsd) { $status->{$node1}->{'appsd'} .= "," . $ret->{$node1}; }
		       else { $status->{$node1}->{'appsd'} = $ret->{$node1}; }
		   } else {
		       $status->{$node1}->{'appstatus'} = $ret->{$node1};
		       $status->{$node1}->{'appsd'} = $ret->{$node1};
		   }
	       }    
	   }
       }


       #nodestat_internal command the output, nodestat command will collect it
       foreach my $node1 (sort keys(%$status)) {
	   my %rsp;
	   $rsp{name}=[$node1];
	   my $st=$status->{$node1}->{'status'};
	   my $ast= $status->{$node1}->{'appstatus'};
           my $appsd = $status->{$node1}->{'appsd'};
	   $st=$st?$st:'';
	   $ast=$ast?$ast:'';
	   $appsd=$appsd?$appsd:'';
	   
	   $rsp{data}->[0] = "$st$separator$ast$separator$appsd";
	   $callback->({node=>[\%rsp]});
       }  
   } else {  #nodestat command
       #first collect the status from the nodes
       my $reqcopy = {%$request};
       $reqcopy->{command}->[0]='nodestat_internal';
       my $ret = xCAT::Utils->runxcmd($reqcopy, $doreq, 0, 1);

       #print Dumper($ret);
       my $status={};
       my @noping_nodes=();
       my $power=$request->{'power'}->[0];
       foreach my $tmpdata (@$ret) {
	   if ($tmpdata =~ /([^:]+): (.*)$separator(.*)$separator(.*)/) {
	      #print "node=$1, status=$2, appstatus=$3, appsd=$4\n";
	      if ($status->{$1}->{'status'}) {
		  $status->{$1}->{'status'}=$status->{$1}->{'status'} . ",$2";
	      } else {
		  $status->{$1}->{'status'}=$2;
	      }
	      if ($status->{$1}->{'appstatus'}) {
		  $status->{$1}->{'appstatus'}= $status->{$1}->{'appstatus'} . ",$3";
	      } else {
		  $status->{$1}->{'appstatus'}=$3;
	      }
	      if ($status->{$1}->{'appsd'}) {
		  $status->{$1}->{'appsd'}=$status->{$1}->{'appsd'} . ",$4";
	      } else {
		  $status->{$1}->{'appsd'}=$4;
	      }
               if (($power) && ($2 eq "noping")) {
		   push(@noping_nodes, $1);
	       }
	   } else  {
	       my $rsp;
	       $rsp->{data}->[0]= "$tmpdata";
	       xCAT::MsgUtils->message("I", $rsp, $callback);
           }
       }

       #print Dumper($status);
       #get power status for noping nodes
       if (($power) && (@noping_nodes > 0)) {
	   #print "noping_nodes=@noping_nodes\n";
	   my $ret = xCAT::Utils->runxcmd(
	       {
		   command => ['rpower'],
		   node    => \@noping_nodes,
		   arg     => [ 'stat' ]
	       },
	       $doreq, 0, 1 );

	   foreach my $tmpdata (@$ret) {
	       if ($tmpdata =~ /([^:]+): (.*)/) {
		   $status->{$1}->{'status'}="noping($2)";
	       } else  {
		   my $rsp;
		   $rsp->{data}->[0]= "$tmpdata";
		   xCAT::MsgUtils->message("I", $rsp, $callback);
	       }
	   }
       }
      
       #print Dumper($request);
       my $update=$request->{'update'}->[0];
       my $quite=$request->{'quite'}->[0];

       
      #show the output 
       if (!$quite) {
	   foreach my $node1 (sort keys(%$status)) {
	       my %rsp;
	       $rsp{name}=[$node1];
	       my $st=$status->{$node1}->{'status'};
	       my $ast= $status->{$node1}->{'appstatus'};
	       if ($st) {
		   if ($st eq 'ping') { $st = $ast ? "$ast" : "$st"; }
                   else {  $st = $ast ? "$st,$ast" : "$st"; }
	       } else {
		   $st=$ast;
	       }
	       $rsp{data}->[0] = $st;
	       $callback->({node=>[\%rsp]});
	   }  
       }
       
       #update the nodelist table
       if ($update) {
	   my $nodetab=xCAT::Table->new('nodelist', -create=>1);
	   if ($nodetab) {
	       my $status1={};
	       #get current values and compare with the new value to decide if update of db is necessary
	       my @nodes1=keys(%$status); 
	       my $stuff = $nodetab->getNodesAttribs(\@nodes1, ['node', 'status', 'appstatus']);
	       
	       #get current local time
	       my (
		   $sec,  $min,  $hour, $mday, $mon,
		   $year, $wday, $yday, $isdst
		   )
		   = localtime(time);
	       my $currtime = sprintf("%02d-%02d-%04d %02d:%02d:%02d",
				      $mon + 1, $mday, $year + 1900,
				      $hour, $min, $sec);
	       
	       foreach my $node1 (@nodes1) {
		   my $oldstatus=$stuff->{$node1}->[0]->{status};
		   my $newstatus=$status->{$node1}->{status};
		   if ($newstatus) {
		       if ((!$oldstatus) || ($newstatus ne $oldstatus)) { 
			   $status1->{$node1}->{status}= $newstatus;
			   $status1->{$node1}->{statustime}= $currtime;
		       }   
		   } 
		   else {
		       if ($oldstatus) {
			   $status1->{$node1}->{status}= "";
			   $status1->{$node1}->{statustime}= "";
		       }
		   }
		   
		   my $oldappstatus=$stuff->{$node1}->[0]->{'appstatus'};
		   my $newappstatus=$status->{$node1}->{'appsd'};
		   while ($newappstatus =~ /(\w+)\=(\w+)/) {
                       my $tmp1=$1;
                       my $tmp2=$2;
		       if ($oldappstatus) {
			   if($oldappstatus =~ /$tmp1\=/){
			       $oldappstatus =~ s/$tmp1\=\w+/$tmp1\=$tmp2/g;
			   }else{
			       $oldappstatus = $oldappstatus."\,$tmp1\=$tmp2";
			   }
		       } else {
			   $oldappstatus = "$tmp1\=$tmp2";
		       }
		       $newappstatus =~ s/(\w+)\=(\w+)//;
                    }
	 	    $status1->{$node1}->{appstatus}= $oldappstatus; 
		    $status1->{$node1}->{appstatustime}= $currtime; 
	       }  
	       #print Dumper($status1);    
	       $nodetab->setNodesAttribs($status1);
	   }
       }
   }
}

sub usage
{
    my $cb=shift;
    my $rsp={};
    $rsp->{data}->[0]= "Usage:";
    $rsp->{data}->[1]= "  nodestat [noderange] [-m|--usemon] [-p|powerstat] [-u|--updatedb]";
    $rsp->{data}->[2]= "  nodestat [-h|--help|-v|--version]";
    xCAT::MsgUtils->message("I", $rsp, $cb);
}

#--------------------------------------------------------------------------------
=head3    getStatusMonsettings
      This function goes to the monsetting table to retrieve the settings related to
      the node status and app status monitoring.
    Arguments:
       none.
    Returns:
       a hash that has settings from the monsetting table for node status and 
       app status monitoring. For example:
       (  'APPS'=>[ll,gpfs],
          'll' =>
           {
              'group' => 'service,compute',
              'port' => '5001'
           },
        'gpfs' =>
           {
               'group' => 'service',
               'cmd' => '/tmp/gpfscmd'
           };
       )
=cut
#--------------------------------------------------------------------------------
sub getStatusMonsettings {
    my %apps=();
    my $tab=xCAT::Table->new('monsetting');
    if ( defined($tab)) {
	my ($ent) = $tab->getAttribs({name => 'xcatmon', key => 'apps' }, 'value');
	if ( defined($ent) ) {
	    my $tmp_list=$ent->{value};
	    if ($tmp_list) {
		my @applist=split(',', $tmp_list); 
		foreach my $app (@applist) {
		    $apps{$app}={};
		}
                $apps{'APPS'}=\@applist;
		my @results = $tab->getAttribs({name => 'xcatmon'}, 'key','value');
		if (@results) {
		    foreach(@results) {
			my $key=$_->{key};
			my $value=$_->{value};
			if (exists($apps{$key})) {
			    my @tem_value=split(',',$value);
			    foreach my $pair (@tem_value) {
				my @tmp_action=split('=', $pair);
				if (exists($apps{$key}->{$tmp_action[0]})) {
				    $apps{$key}->{$tmp_action[0]} = $apps{$key}->{$tmp_action[0]} . "," . $tmp_action[1];
				} else {
				    $apps{$key}->{$tmp_action[0]}=$tmp_action[1];
				}
			    }
			}
		    }
		}
	    }
	}
    }
    return %apps;

}

#--------------------------------------------------------------------------------
=head3    getNodeStatusAndAppstatus
      This function goes to the xCAT nodelist table to retrieve the saved node status and appstatus
      for all the node that are managed by local nodes.
    Arguments:
       nodelist--- an array of nodes
    Returns:
       a hash pointer that has the node status and appstatus. The format is: 
          { node1=> {
                     status=>'active',appstatus=>'sshd=up,ll=up,gpfs=down'
                   } , 
            node2=> {
                     status=>'active',appstatus=>'sshd=up,ll=down,gpfs=down'
                   } 
           }
           
=cut
#--------------------------------------------------------------------------------
sub getMonNodesStatusAndAppStatus {
    my @nodes=@_;

    my %status=();
    my $table=xCAT::Table->new("nodelist", -create =>1);
    my $tabdata=$table->getNodesAttribs(\@nodes,['node', 'status', 'appstatus']);
    foreach my $node (@nodes) {
	my $tmp1=$tabdata->{$node}->[0];
	if ($tmp1) {
	    $status{$node}->{status}=$tmp1->{status};
	    $status{$node}->{appstatus}=$tmp1->{appstatus};
	}
    }
    return %status;
}



1;
