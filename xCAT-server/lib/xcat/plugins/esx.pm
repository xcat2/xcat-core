package xCAT_plugin::esx;

use strict;
use warnings;
use xCAT::Table;
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::ServiceNodeUtils;
use xCAT::TZUtils;
use Time::HiRes qw (sleep);
use xCAT::Template;
use xCAT::MsgUtils;
use xCAT::SvrUtils;
use xCAT::NodeRange;
use xCAT::Common;
use xCAT::VMCommon;
use POSIX "WNOHANG";
use Getopt::Long;
use Thread qw(yield);
use POSIX qw(WNOHANG nice);
use File::Path qw/mkpath rmtree/;
use File::Temp qw/tempdir/;
use File::Copy;
use Fcntl qw/:flock/;
use IO::Socket; #Need name resolution
use Scalar::Util qw/looks_like_number/;
#use Data::Dumper;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");
my @cpiopid;
our @ISA = 'xCAT::Common';


#in xCAT, the lifetime of a process ends on every request
#therefore, the lifetime of assignments to these glabals as architected
#is to be cleared on every request
#my %esx_comm_pids;
my %limbonodes; #nodes in limbo during a forced migration due to missing parent
my %hyphash; #A data structure to hold hypervisor-wide variables (i.e. the current resource pool, virtual machine folder, connection object
my %vcenterhash; #A data structure to reflect the state of vcenter connectivity to hypervisors
my %vmhash; #store per vm info of interest
my %clusterhash;
my %hypready; #A structure for hypervisor readiness to be tracked before proceeding to normal operations
my %running_tasks; #A struct to track this processes
my $output_handler; #Pointer to the function to drive results to client
my $executerequest;
my $usehostnamesforvcenter;
my %tablecfg; #to hold the tables
my %hostrefbynode;
my $currkey;
my $requester;
my $viavcenter;
my $viavcenterbyhyp;
my $vcenterautojoin=1;
my $datastoreautomount=1;
my $vcenterforceremove=0; #used in rmhypervisor
my $reconfigreset=1;
my $vmwaresdkdetect = eval {
    require VMware::VIRuntime;
    VMware::VIRuntime->import();
    1;
};
my %lockhandles;

sub recursion_copy {
        my $source = shift;
        my $destination = shift;
        my $dirhandle;
        opendir($dirhandle,$source);
        my $entry;
        foreach $entry (readdir($dirhandle)) {
                if ($entry eq '.' or $entry eq '..') { next; }
                my $tempsource = "$source/$entry";
                my $tempdestination = "$destination/$entry";
                if ( -d $tempsource ) {
                        unless (-d $tempdestination) { mkdir $tempdestination or die "failure creating directory $tempdestination, $!"; }
                        recursion_copy($tempsource,$tempdestination);
                } else {
                        copy($tempsource,$tempdestination) or die "failed copy from $tempsource to $tempdestination, $!";
                }
        }
}
sub lockbyname {
	my $name = shift;
	my $lckh;
	mkpath("/tmp/xcat/locks/");
	while (-e "/tmp/xcat/locks/$name") { sleep 1; }
	open($lockhandles{$name},">>","/tmp/xcat/locks/$name"); 
	flock($lockhandles{$name},LOCK_EX);
}
sub unlockbyname {
	my $name = shift;
	unlink("/tmp/xcat/locks/$name");
	close($lockhandles{$name});
}

my %guestidmap = (
    "rhel.6.*" => "rhel6_",
    "rhel.5.*" => "rhel5_",
    "rhel4.*" => "rhel4_",
    "centos6.*" => "rhel6_",
    "centos5.*" => "rhel5_",
    "centos4.*" => "rhel4_",
    "sles12.*" => "sles12_",
    "sles11.*" => "sles11_",
    "sles10.*" => "sles10_",
    "win2k8" => "winLonghorn",
    "win2k8r2" => "windows7Server",
	"win2012" => "windows8Server",
	"hyperv2012" => "windows8Server",
	"esix5.*" => "vmkernel5",
	"esix4.*" => "vmkernel",
	"win8" => "windows8_",
    "win7" => "windows7_",
    "win2k3" => "winNetStandard",
    "imagex" => "winNetStandard",
    "boottarget" => "otherLinux"
#otherGuest, otherGuest64, otherLinuxGuest, otherLinux64Guest
    );

sub handled_commands{
	return {
		copycd => 'esx',
		mknetboot => "nodetype:os=(esxi.*)",
		mkinstall => "nodetype:os=(esxi[56].*)",
		rpower => 'nodehm:power,mgt',
        esxiready => "esx",
		rsetboot => 'nodehm:power,mgt',
		rmigrate => 'nodehm:power,mgt',
        formatdisk => "nodetype:os=(esxi.*)",
        rescansan => "nodetype:os=(esxi.*)",
		mkvm => 'nodehm:mgt',
		rmvm => 'nodehm:mgt',
        clonevm => 'nodehm:mgt',
        createvcluster => 'esx',
        lsvcluster => 'esx',
        rmvcluster => 'esx',
		rinv => 'nodehm:mgt',
                chvm => 'nodehm:mgt',
        rshutdown => "nodetype:os=(esxi.*)",
        lsvm => ['hypervisor:type','nodetype:os=(esx.*)'],
		rmhypervisor => ['hypervisor:type','nodetype:os=(esx.*)'],
		chhypervisor => ['hypervisor:type','nodetype:os=(esx.*)'],
		#lsvm => 'nodehm:mgt', not really supported yet
	};
}





sub preprocess_request {
	my $request = shift;
	my $callback = shift;
    if ($request->{command}->[0] eq 'createvcluster' or $request->{command}->[0] eq 'lsvcluster' or $request->{command}->[0] eq 'rmvcluster') {
        return [$request];
    }
   #if already preprocessed, go straight to request
    if (   (defined($request->{_xcatpreprocessed}))
        && ($request->{_xcatpreprocessed}->[0] == 1))
    {
        return [$request];
    }

    my $username = 'root';
    my $password = '';
    my $vusername = "Administrator";
    my $vpassword = "";

    unless ($request and $request->{command} and $request->{command}->[0]) { return; }

	if ($request->{command}->[0] eq 'copycd')
	{    #don't farm out copycd
		return [$request];
	}elsif($request->{command}->[0] eq 'mknetboot'
	      or $request->{command}->[0] eq 'mkinstall'){
		return [$request];
	}
    xCAT::Common::usage_noderange($request,$callback);

        if ($request->{_xcatpreprocessed} and $request->{_xcatpreprocessed}->[0] == 1) { return [$request]; } 
         # exit if preprocesses
	my @requests;

	my $noderange;
	my $command = $request->{command}->[0];
    if ($request->{node}) {
	    $noderange = $request->{node};  # array ref
    } elsif ($command eq "esxiready") {
        my $node;
        ($node) = noderange($request->{'_xcat_clienthost'}->[0]);
        $noderange = [$node];
        $request->{node} = $noderange;
    }

	my $extraargs = $request->{arg};
	my @exargs=($request->{arg});
	my %hyp_hash = ();
    my %cluster_hash=();

# Get nodes from mp table and assign nodes to mp hash.
    my $passtab = xCAT::Table->new('passwd');
    my $tmp;
    if ($passtab) {
        ($tmp) = $passtab->getAttribs({'key'=>'vmware'},'username','password');
        if (defined($tmp)) {
            $username = $tmp->{username};
            $password = $tmp->{password};
        }
        ($tmp) = $passtab->getAttribs({'key'=>'vcenter'},'username','password');
        if (defined($tmp)) {
            $vusername = $tmp->{username};
            $vpassword = $tmp->{password};
        }
    }
        
	my $vmtab = xCAT::Table->new("vm");
	unless($vmtab){
		$callback->({data=>["Cannot open vm table"]});
		$request = {};
		return;
	}

	my $vmtabhash = $vmtab->getNodesAttribs($noderange,['host','migrationdest']);
	foreach my $node (@$noderange){
        if ($command eq "rmhypervisor" or $command eq 'lsvm' or $command eq 'esxiready' or $command eq 'rshutdown' or $command eq "chhypervisor" or $command eq "formatdisk" or $command eq 'rescansan') {
            $hyp_hash{$node}{nodes} = [$node];
        } else {
        my $ent = $vmtabhash->{$node}->[0];
		if(defined($ent->{host})) {
			push @{$hyp_hash{$ent->{host}}{nodes}}, $node;
		} elsif (defined($ent->{migrationdest})) {
            $cluster_hash{$ent->{migrationdest}}->{nodes}->{$node}=1;
		} else {
			xCAT::SvrUtils::sendmsg([1,": no host or cluster defined for guest"], $callback,$node);
		}
        }
	}

	# find service nodes for the MMs
	# build an individual request for each service node
	my $service  = "xcat";
	my @hyps=keys(%hyp_hash);
    my %targethyps;
    if ($command eq 'rmigrate' and (scalar @{$extraargs} >= 1)) {
        @ARGV=@{$extraargs};
        my $offline;
        my $junk;
        GetOptions(
            "f" => \$offline,
            "s=s" => \$junk #wo don't care about it, but suck up nfs:// targets so they don't get added
            );
        my $dsthyp = $ARGV[0];
        if ($dsthyp) {
            push @hyps,$dsthyp;
            $targethyps{$dsthyp}=1;
        }
    }
    #TODO: per hypervisor table password lookup
    my @allnodes;
    push @allnodes,@hyps;
    push @allnodes,@$noderange;
	my $sn = xCAT::ServiceNodeUtils->get_ServiceNode(\@allnodes, $service, "MN");
    #vmtabhash was from when we had vm.host do double duty for hypervisor data
    #$vmtabhash = $vmtab->getNodesAttribs(\@hyps,['host']);
    #We now use hypervisor fields to be unambiguous
    my $hyptab = xCAT::Table->new('hypervisor');
    my $hyptabhash={};
    if ($hyptab) {
        $hyptabhash = $hyptab->getNodesAttribs(\@hyps,['mgr']);
    }


	# build each request for each service node
	foreach my $snkey (keys %$sn){
		my $reqcopy = {%$request};
		$reqcopy->{'_xcatdest'} = $snkey;
                $reqcopy->{_xcatpreprocessed}->[0] = 1;
		my $hyps1=$sn->{$snkey};
		my @moreinfo=();
		my @nodes=();
		foreach (@$hyps1) { #This preserves the constructed data to avoid redundant table lookup
			my $cfgdata;
            if (not $targethyps{$_} and not $hyp_hash{$_}) { #a vm, skip it
                next;
            } elsif ($hyp_hash{$_}{nodes}) {
			    push @nodes, @{$hyp_hash{$_}{nodes}};
                $cfgdata = "[$_][".join(',',@{$hyp_hash{$_}{nodes}})."][$username][$password][$vusername][$vpassword]"; #TODO: not use vm.host?
            } else {
                $cfgdata = "[$_][][$username][$password][$vusername][$vpassword]"; #TODO: not use vm.host?
            }
            if (defined $hyptabhash->{$_}->[0]->{mgr}) {
                $cfgdata .= "[". $hyptabhash->{$_}->[0]->{mgr}."]";
            } else { 
                $cfgdata .= "[]";
            }
			push @moreinfo, $cfgdata; #"[$_][".join(',',@{$hyp_hash{$_}{nodes}})."][$username][$password]";
		}
        foreach (keys %cluster_hash) {
            my $cluster;
            my $vcenter;
            if (/@/) {
                ($cluster,$vcenter) = split /@/,$_,2;
            } else {
                die "TODO: implement default vcenter (for now, user, do vm.migratiodest=cluster".'@'."vcentername)";
            }
            push @moreinfo,"[CLUSTER:$cluster][".join(',',keys %{$cluster_hash{$_}->{nodes}})."][$username][$password][$vusername][$vpassword][$vcenter]";
        }
        if (scalar @nodes) {
    		$reqcopy->{node} = \@nodes;
        }
		#print "nodes=@nodes\n";
		$reqcopy->{moreinfo}=\@moreinfo;
		push @requests, $reqcopy;
	}
  return \@requests;
}



sub process_request {
	#$SIG{INT} = $SIG{TERM} = sub{
	#	foreach (keys %esx_comm_pids){
	#		kill 2,$_;
	#	}
	#	exit 0;
	#};
    
	my $request = shift;
	$output_handler = shift;
	$executerequest = shift;
    if ($request->{_xcat_authname}->[0]) {
        $requester=$request->{_xcat_authname}->[0];
    }
    %vcenterhash = ();#A data structure to reflect the state of vcenter connectivity to hypervisors
	my $level = shift;
	my $distname = undef;
	my $arch = undef;
	my $path = undef;
	my $command = $request->{command}->[0];
    #The first segment is fulfilling the role of this plugin as 
    #a hypervisor provisioning plugin (akin to anaconda, windows, sles plugins)
	if($command eq 'copycd'){
		return copycd($request,$executerequest);
	}elsif($command eq 'mkinstall'){
		return mkinstall($request,$executerequest);
	}elsif($command eq 'mknetboot'){
		return mknetboot($request,$executerequest);
	}
    #From here on out, code for managing guests under VMware
    #Detect whether or not the VMware SDK is available on this specific system
    unless ($vmwaresdkdetect) {
        $vmwaresdkdetect = eval {
            require VMware::VIRuntime;
            VMware::VIRuntime->import();
            1;
        };
    }
    unless ($vmwaresdkdetect) {
        xCAT::SvrUtils::sendmsg([1,"VMWare SDK required for operation, but not installed"], $output_handler);
        return;
    }
    if ($command eq 'createvcluster') {
        create_new_cluster($request);
        return;
    }
    if ($command eq 'lsvcluster') {
        list_clusters($request);
        return;
    }
    if ($command eq 'rmvcluster') {
        remove_cluster($request);
        return;
    }

	my $moreinfo;
	my $noderange;
    if ($request->{node}) {
	    $noderange = $request->{node};  # array ref
    } elsif ($command eq "esxiready") {
        my $node;
        ($node) = noderange($request->{'_xcat_clienthost'}->[0]);
        $noderange = [$node];
    }
    xCAT::VMCommon::grab_table_data($noderange,\%tablecfg,$output_handler);
	my @exargs;
	unless($command){
		return; # Empty request
	}
	if (ref($request->{arg})) {
		@exargs = @{$request->{arg}};
	} else {
		@exargs = ($request->{arg});
	}
	#my $sitetab = xCAT::Table->new('site');
	#if($sitetab){
		#(my $ref) = $sitetab->getAttribs({key => 'usehostnamesforvcenter'}, 'value');
                my @entries =  xCAT::TableUtils->get_site_attribute("usehostnamesforvcenter");
                my $t_entry = $entries[0];
		if ( defined($t_entry) ) {
			$usehostnamesforvcenter = $t_entry;
		}
		#($ref) = $sitetab->getAttribs({key => 'vcenterautojoin'}, 'value');
                @entries =  xCAT::TableUtils->get_site_attribute("vcenterautojoin");
                $t_entry = $entries[0];
		if ( defined($t_entry) ) {
                   $vcenterautojoin = $t_entry;
                   if ($vcenterautojoin =~ /^n/ or $vcenterautojoin =~ /^dis/) {
                       $vcenterautojoin=0;
                   }
		}
		#($ref) = $sitetab->getAttribs({key => 'vmwaredatastoreautomount'}, 'value');
                @entries =  xCAT::TableUtils->get_site_attribute("vmwaredatastoreautomount");
                $t_entry = $entries[0];
		if ( defined($t_entry) ) {
			$datastoreautomount = $t_entry;
                    if ($datastoreautomount =~ /^n/ or $datastoreautomount =~ /^dis/) {
                        $datastoreautomount=0;
                    }
		}
                #($ref) = $sitetab->getAttribs({key => 'vmwarereconfigonpower'},'value');
                @entries =  xCAT::TableUtils->get_site_attribute("vmwarereconfigonpower");
                $t_entry = $entries[0];
		if ( defined($t_entry) ) {
                    $reconfigreset=$t_entry;
                    if ($reconfigreset =~ /^(n|d)/i) { #if no or disable, skip it
                        $reconfigreset=0;
                    }
                }

#	}


	if ($request->{moreinfo}) { $moreinfo=$request->{moreinfo}; }
	else {  $moreinfo=build_more_info($noderange,$output_handler);}
	foreach my $info (@$moreinfo) {
		$info=~/^\[(.*?)\]\[(.*?)\]\[(.*?)\]\[(.*?)\]\[(.*?)\]\[(.*?)\]\[(.*?)\]/;
		my $hyp=$1;
		my @nodes=split(',', $2);
        my $username = $3;
        my $password = $4;
        my $tmpvcname=$7;
        my $tmpvcuname=$5;
        my $tmpvcpass=$6;
        if ($hyp =~ /^CLUSTER:/) { #a cluster, not a host.
            $hyp =~ s/^CLUSTER://;
            $clusterhash{$hyp}->{vcenter}->{name} = $tmpvcname;
            $clusterhash{$hyp}->{vcenter}->{username} = $tmpvcuname;
            $clusterhash{$hyp}->{vcenter}->{password} = $tmpvcpass;
            foreach (@nodes) {
                $clusterhash{$hyp}->{nodes}->{$_}=1;
            }
            next;
        }
        $hyphash{$hyp}->{vcenter}->{name} = $tmpvcname;
        $hyphash{$hyp}->{vcenter}->{username} = $tmpvcuname;
        $hyphash{$hyp}->{vcenter}->{password} = $tmpvcpass;
		$hyphash{$hyp}->{username}=$username;# $nodeid;
		$hyphash{$hyp}->{password}=$password;# $nodeid;
        unless ($hyphash{$hyp}->{vcenter}->{password}) {
            $hyphash{$hyp}->{vcenter}->{password} = "";
        }
		my $ent;
		for (my $i=0; $i<@nodes; $i++){
			if ($command eq 'rmigrate' and grep /-f/, @exargs) { #offline migration, 
				$hyphash{$hyp}->{offline} = 1; #if it is migrate and it has nodes, it is a source hypervisor apt to be offline
                                               #this will hint to relevant code to operate under the assumption of a
                                               #downed hypervisor source
                                               #note this will make dangerous assumptions, it will make a very minimal attempt
                                               #to operate normally, but really should only be called if the source is down and
                                               #fenced (i.e. storage, network, or turned off and stateless
			}
			my $node = $nodes[$i];
			#my $nodeid = $ids[$i];
			$hyphash{$hyp}->{nodes}->{$node}=1;# $nodeid;
		}
	}
    my $hyptab = xCAT::Table->new('hypervisor',create=>0);
    if ($hyptab) {
        my @hyps = keys %hyphash;
        $tablecfg{hypervisor} = $hyptab->getNodesAttribs(\@hyps,['mgr','netmap','defaultnet','cluster','preferdirect','datacenter']);
    }
    my $hoststab = xCAT::Table->new('hosts',create=>0);
    if ($hoststab) {
        my @hyps = keys %hyphash;
        $tablecfg{hosts} = $hoststab->getNodesAttribs(\@hyps,['hostnames']);

    }

	#my $children = 0;
    #my $vmmaxp = 84;
	#$SIG{CHLD} = sub { my $cpid; while ($cpid = waitpid(-1, WNOHANG) > 0) { delete $esx_comm_pids{$cpid}; $children--; } };
    $viavcenter = 0;
    if ($command eq 'rmigrate' or $command eq 'rmhypervisor') { #Only use vcenter when required, fewer prereqs
        $viavcenter = 1;
    }
    if ($command eq 'rmhypervisor' and grep /-f/, @exargs) { #force remove of hypervisor
        $vcenterforceremove=1;
    }
    my $keytab = xCAT::Table->new('prodkey');
    if ($keytab) {
        my @hypes = keys %hyphash;
        $tablecfg{prodkey} = $keytab->getNodesAttribs(\@hypes,[qw/product key/]);
    }
    my $hyp;
    my %needvcentervalidation;
    my $cluster;
    foreach $cluster (keys %clusterhash) {
        my $vcenter = $clusterhash{$cluster}->{vcenter}->{name};
        unless ($vcenterhash{$vcenter}->{conn}) {
            eval {
                $vcenterhash{$vcenter}->{conn} = Vim->new(service_url=>"https://$vcenter/sdk");
                $vcenterhash{$vcenter}->{conn}->login(user_name => $clusterhash{$cluster}->{vcenter}->{username},
                                                       password => $clusterhash{$cluster}->{vcenter}->{password});
            };
            if ($@) { 
                 $vcenterhash{$vcenter}->{conn} = undef;
                 xCAT::SvrUtils::sendmsg([1,"Unable to reach $vcenter vCenter server to manage cluster $cluster: $@"], $output_handler);
                 next;
            }
            my $clusternode;
        }
        $clusterhash{$cluster}->{conn}=$vcenterhash{$vcenter}->{conn};
        foreach my $clusternode (keys %{$clusterhash{$cluster}->{nodes}}) {
            $vmhash{$clusternode}->{conn}=$vcenterhash{$vcenter}->{conn};
        }
    }
	foreach $hyp (sort(keys %hyphash)){
		#if($pid == 0){
        if ($viavcenter or (defined $tablecfg{hypervisor}->{$hyp}->[0]->{mgr} and not $tablecfg{hypervisor}->{$hyp}->[0]->{preferdirect})) {
	    $viavcenterbyhyp->{$hyp}=1;
            $hypready{$hyp} = 0; #This hypervisor requires a flag be set to signify vCenter sanenes before proceeding
            my $vcenter = $hyphash{$hyp}->{vcenter}->{name};
            unless ($vcenterhash{$vcenter}->{conn}) {
	        eval { 
                $vcenterhash{$vcenter}->{conn} =
                    Vim->new(service_url=>"https://$vcenter/sdk");
                $vcenterhash{$vcenter}->{conn}->login(
                            user_name => $hyphash{$hyp}->{vcenter}->{username},
                            password => $hyphash{$hyp}->{vcenter}->{password}
                            );
                };
                if ($@) { 
                      $vcenterhash{$vcenter}->{conn} = undef;
                      xCAT::SvrUtils::sendmsg([1,"Unable to reach $vcenter vCenter server to manage $hyp: $@"], $output_handler);
                      next;
                }
            }
            my $hypnode;
            foreach $hypnode (keys %{$hyphash{$hyp}->{nodes}}) {
                $vmhash{$hypnode}->{conn}=$vcenterhash{$hyphash{$hyp}->{vcenter}->{name}}->{conn};
            }
            $hyphash{$hyp}->{conn} = $vcenterhash{$hyphash{$hyp}->{vcenter}->{name}}->{conn};
            $hyphash{$hyp}->{vcenter}->{conn} = $vcenterhash{$hyphash{$hyp}->{vcenter}->{name}}->{conn};
            $needvcentervalidation{$hyp}=$vcenter;
            $vcenterhash{$vcenter}->{allhyps}->{$hyp}=1;
        } else {
            eval { 
              $hyphash{$hyp}->{conn} = Vim->new(service_url=>"https://$hyp/sdk");
              $hyphash{$hyp}->{conn}->login(user_name=>$hyphash{$hyp}->{username},password=>$hyphash{$hyp}->{password});
            }; 
            if ($@) {
	       $hyphash{$hyp}->{conn} = undef;
	       xCAT::SvrUtils::sendmsg([1,"Unable to reach $hyp to perform operation due to $@"], $output_handler);
                $hypready{$hyp} = -1;
	       next;
            }
            my $localnode;
            foreach $localnode (keys %{$hyphash{$hyp}->{nodes}}) {
                $vmhash{$localnode}->{conn}=$hyphash{$hyp}->{conn};
            }
              validate_licenses($hyp);
        }
		#}else{
		#	$esx_comm_pids{$pid} = 1;
		#}
	}
    foreach $hyp (keys %needvcentervalidation) {
        my $vcenter = $needvcentervalidation{$hyp};
        if (not defined $vcenterhash{$vcenter}->{hostviews}) {
           populate_vcenter_hostviews($vcenter);
        }
        if (validate_vcenter_prereqs($hyp, \&declare_ready, {
                hyp=>$hyp,
                vcenter=>$vcenter
                }) eq "failed") {
                $hypready{$hyp} = -1;
        }
    }
    while (grep { $_ == 0 } values %hypready) {
        wait_for_tasks();
        sleep (1); #We'll check back in every second.  Unfortunately, we have to poll since we are in web service land
    }
    my @badhypes;
    if (grep { $_ == -1 } values %hypready) {
        foreach (keys %hypready) {
            if ($hypready{$_} == -1) {
				unless ($hyphash{$_}->{offline}) {
                push @badhypes,$_;
				}
                my @relevant_nodes = sort (keys %{$hyphash{$_}->{nodes}});
				my $sadhypervisor=$_;
                foreach (@relevant_nodes) {
		    if ($command eq "rmigrate" and grep /-f/,@exargs) { $limbonodes{$_}=$needvcentervalidation{$sadhypervisor}; } else {
                    xCAT::SvrUtils::sendmsg([1,": hypervisor unreachable"], $output_handler,$_);
			}
				if ($command eq "rpower" and grep /stat/,@exargs) { $limbonodes{$_}=$needvcentervalidation{$sadhypervisor}; } #try to stat power anyway through vcenter of interest...
                }
                delete $hyphash{$_};
            }
        }
        if (@badhypes) { 
            xCAT::SvrUtils::sendmsg([1,": The following hypervisors failed to become ready for the operation: ".join(',',@badhypes)], $output_handler);
        }
    } 
    do_cmd($command,@exargs);
    foreach (@badhypes) { delete $hyphash{$_}; }
    foreach my $vm (sort(keys %vmhash)){
      $vmhash{$vm}->{conn}->logout();
    }
}

sub validate_licenses {
    my $hyp = shift;
    my $conn = $hyphash{$hyp}->{conn}; #This can't possibly be called via a cluster stack, so hyphash is appropriate here
    unless ($tablecfg{prodkey}->{$hyp}) { #if no license specified, no-op
        return;
    }
    my $hv = get_hostview(hypname=>$hyp,conn=>$conn,properties=>['configManager','name']);
    my $lm = $conn->get_view(mo_ref=>$hv->configManager->licenseManager);
    my @licenses;
    foreach (@{$lm->licenses}) {
        push @licenses,uc($_->licenseKey);
    }
    my @newlicenses;
    foreach (@{$tablecfg{prodkey}->{$hyp}}) {
        if (defined($_->{product}) and $_->{product} eq 'esx') {
            my $key = uc($_->{key});
            unless (grep /$key/,@licenses) {
                push @newlicenses,$key;
            }
        }
    }
    foreach (@newlicenses) {
        $lm->UpdateLicense(licenseKey=>$_);
    }
}

sub do_cmd {
    my $command = shift;
    my @exargs = @_;
    if ($command eq 'esxiready') {
        return;
    }
    if ($command eq 'rpower') {
        generic_vm_operation(['config.name','config.guestId','config.hardware.memoryMB','config.hardware.numCPU','runtime.powerState','runtime.host'],\&power,@exargs);
    } elsif ($command eq 'rmvm') {
        generic_vm_operation(['config.name','runtime.powerState','runtime.host'],\&rmvm,@exargs);
    } elsif ($command eq 'rsetboot') {
        generic_vm_operation(['config.name','runtime.host'],\&setboot,@exargs);
    } elsif ($command eq 'rinv') {
        generic_vm_operation(['config.name','config','runtime.host','layoutEx'],\&inv,@exargs);
    } elsif ($command eq 'formatdisk') {
        generic_hyp_operation(\&formatdisk,@exargs);
    } elsif ($command eq 'rescansan') {
        generic_hyp_operation(\&rescansan,@exargs);
    } elsif ($command eq 'rmhypervisor') {
        generic_hyp_operation(\&rmhypervisor,@exargs);
    } elsif ($command eq 'rshutdown') {
        generic_hyp_operation(\&rshutdown,@exargs);
    } elsif ($command eq 'chhypervisor') {
        generic_hyp_operation(\&chhypervisor,@exargs);
    } elsif ($command eq 'lsvm') {
        generic_hyp_operation(\&lsvm,@exargs);
    } elsif ($command eq 'clonevm') {
        generic_hyp_operation(\&clonevms,@exargs);
    } elsif ($command eq 'mkvm') {
        generic_hyp_operation(\&mkvms,@exargs);
    } elsif ($command eq 'chvm') {
        generic_vm_operation(['config.name','config','runtime.host'],\&chvm,@exargs);
        #generic_hyp_operation(\&chvm,@exargs);
    } elsif ($command eq 'rmigrate') { #Technically, on a host view, but vcenter path is 'weirder'
        generic_hyp_operation(\&migrate,@exargs);
    }
    wait_for_tasks();
    if ($command eq 'clonevm') { #TODO: unconditional, remove mkvms hosted copy
      my @dhcpnodes;
      foreach (keys %{$tablecfg{dhcpneeded}}) {
        push @dhcpnodes,$_;
        delete $tablecfg{dhcpneeded}->{$_};
      }
      unless ($::XCATSITEVALS{'dhcpsetup'} and ($::XCATSITEVALS{'dhcpsetup'} =~ /^n/i or $::XCATSITEVALS{'dhcpsetup'} =~ /^d/i or $::XCATSITEVALS{'dhcpsetup'} eq '0')) {
        $executerequest->({command=>['makedhcp'],node=>\@dhcpnodes});
      }
    }
}

#inventory request for esx
sub inv {
  my %args = @_;
  my $node = $args{node};
  my $hyp = $args{hyp};
  if (not defined $args{vmview}) { #attempt one refresh
    $args{vmview} = $vmhash{$node}->{conn}->find_entity_view(view_type => 'VirtualMachine',properties=>['config.name','runtime.powerState'],filter=>{name=>$node});
    if (not defined $args{vmview}) { 
      xCAT::SvrUtils::sendmsg([1,"VM does not appear to exist"], $output_handler,$node);
      return;
    }
  }
  if (not $args{vmview}->{config}) {
    xCAT::SvrUtils::sendmsg([1,"VM is in an invalid state"], $output_handler,$node);
    return;
  }

  @ARGV= @{$args{exargs}};
  require Getopt::Long;
  my $tableUpdate;
  my $rc = GetOptions(
      't' => \$tableUpdate,
  );
  $SIG{__WARN__} = 'DEFAULT';

  if(@ARGV > 1) {
    xCAT::SvrUtils::sendmsg("Invalid arguments:  @ARGV", $output_handler);
    return;
  }

  if(!$rc) {
    return;
  }

  my $vmview = $args{vmview};
  my $moref = $vmview->{mo_ref}->value;
  xCAT::SvrUtils::sendmsg("Managed Object Reference: $moref", $output_handler,$node);
  my $uuid = $vmview->config->uuid;
  $uuid =~ s/(..)(..)(..)(..)-(..)(..)-(..)(..)/$4$3$2$1-$6$5-$8$7/;
  xCAT::SvrUtils::sendmsg("UUID/GUID:  $uuid", $output_handler,$node);
  my $cpuCount = $vmview->config->hardware->numCPU;
  xCAT::SvrUtils::sendmsg("CPUs:  $cpuCount", $output_handler,$node);
  my $memory = $vmview->config->hardware->memoryMB;
  xCAT::SvrUtils::sendmsg("Memory:  $memory MB", $output_handler,$node);
  my %updatehash = ( cpus => $cpuCount, memory=>$memory);


  my $devices = $vmview->config->hardware->device;
  my $label;
  my $size;
  my $fileName;
  my $device;
  if ($tableUpdate and $hyp) {
     validate_datastore_prereqs([$node],$hyp); #need datastoremaps to verify names...
  }
  my %vmstorageurls;
  foreach $device (@$devices) {
    $label = $device->deviceInfo->label;

    if($label =~ /^Hard disk/) {
        $label .= " (d".$device->controllerKey.":".$device->unitNumber.")";
      $size = $device->capacityInKB / 1024;
      $fileName = $device->backing->fileName;
      $output_handler->({
          node=>{
              name=>$node,
              data=>{
                  desc=>$label,
                  contents=>"$size MB @ $fileName"
              }
          }
      });
	  #if ($tableUpdate) {
	  #		$fileName =~ /\[([^\]]+)\]/;
		#	$vmstorageurls{$hyphash{$hyp}->{datastoreurlmap}->{$1}}=1;
	  #}
    } elsif ($label =~ /Network/) {
        xCAT::SvrUtils::sendmsg("$label: ".$device->macAddress, $output_handler,$node);
    }
  }
  if ($tableUpdate) {
  		my $cfgdatastore;
  		foreach (@{$vmview->layoutEx->file}) {
		    #TODO, track ALL layoutEx->file....
			if ($_->type eq 'config') {
				$_->name =~ /\[([^\]]+)\]/;
				$cfgdatastore = $hyphash{$hyp}->{datastoreurlmap}->{$1};
				last;
			}
		}
		my $cfgkey;
		if ($tablecfg{vm}->{$node}->[0]->{cfgstore}) { #check the config file explicitly, ignore the rest
			$cfgkey='cfgstore';
		} elsif ($tablecfg{vm}->{$node}->[0]->{storage}) { #check the config file explicitly, ignore the rest
			$cfgkey='storage';
		}
		my $configuration = $tablecfg{vm}->{$node}->[0]->{$cfgkey}; #TODO: prune urls that map to no layoutEx->file entries anymore
		my $configappend = $configuration;
		$configappend =~ s/^[^,=]*//;
		$tablecfg{vm}->{$node}->[0]->{$cfgkey} =~ m!nfs://([^/]+)/!;
		my $tablecfgserver =$1;
		my $cfgserver = inet_aton($tablecfgserver);
		if ($cfgserver) {
			$cfgserver = inet_ntoa($cfgserver); #get the IP address (TODO: really need to wrap getaddrinfo this handily...
			my $cfgurl = $tablecfg{vm}->{$node}->[0]->{$cfgkey};
			$cfgurl =~ s/$tablecfgserver/$cfgserver/;
			if ($cfgurl ne $cfgdatastore) {
				$updatehash{$cfgkey} = $cfgdatastore.$configappend;
		    }
		}
  }
  if($tableUpdate){
    my $vm=xCAT::Table->new('vm',-create=>1);
    $vm->setNodeAttribs($node,\%updatehash);
  }

}


#changes the memory, number of cpus and device size
#can also add,resize and remove disks
sub chvm {
	my %args = @_;
	my $node = $args{node};
	my $hyp = $args{hyp};
	if (not defined $args{vmview}) { #attempt one refresh
		$args{vmview} = $vmhash{$node}->{conn}->find_entity_view(view_type => 'VirtualMachine',
				properties=>['config.name','runtime.powerState'],
				filter=>{name=>$node});
	  if (not defined $args{vmview}) {
		xCAT::SvrUtils::sendmsg([1,"VM does not appear to exist"], $output_handler,$node);
		return;
	  }
        }
	@ARGV= @{$args{exargs}};
	my @deregister;
	my @purge;
	my @add;
	my %resize;
	my $cpuCount;
	my $memory;
	my $vmview = $args{vmview};

	require Getopt::Long;
	$SIG{__WARN__} = sub {
		xCAT::SvrUtils::sendmsg([1,"Could not parse options, ".shift()], $output_handler);
	};
    my @otherparams;
    my $cdrom;
    my $eject;
	my $rc = GetOptions(
		"d=s"       => \@deregister,
		"p=s"       => \@purge,
		"a=s"       => \@add,
        "o=s"       => \@otherparams,
		"resize=s%" => \%resize,
		"optical|cdrom|c=s" => \$cdrom,
		"eject" => \$eject,
		"cpus=s"    => \$cpuCount,
		"mem=s"     => \$memory
	);
	$SIG{__WARN__} = 'DEFAULT';

	if(@ARGV) {
		xCAT::SvrUtils::sendmsg("Invalid arguments:  @ARGV", $output_handler);
		return;
	}

	if(!$rc) {
		return;
	}

	#use Data::Dumper;
	#xCAT::SvrUtils::sendmsg("dereg = ".Dumper(\@deregister));
	#xCAT::SvrUtils::sendmsg("purge = ".Dumper(\@purge));
	#xCAT::SvrUtils::sendmsg("add = ".Dumper(\@add));
	#xCAT::SvrUtils::sendmsg("resize = ".Dumper(\%resize));
	#xCAT::SvrUtils::sendmsg("cpus = $cpuCount");
	#xCAT::SvrUtils::sendmsg("mem = ".getUnits($memory,"K",1024));


	my %conargs;
	if($cpuCount) {
        if ($cpuCount =~ /^\+(\d+)/) {
            $cpuCount = $vmview->config->hardware->numCPU+$1;
        } elsif ($cpuCount =~ /^-(\d+)/) {
            $cpuCount = $vmview->config->hardware->numCPU-$1;
        }
		$conargs{numCPUs} = $cpuCount;
	}

	if($memory) {
        if ($memory =~ /^\+(.+)/) {
            $conargs{memoryMB} = $vmview->config->hardware->memoryMB + getUnits($1,"M",1048576);
        } elsif ($memory =~ /^-(\d+)/) {
            $conargs{memoryMB} = $vmview->config->hardware->memoryMB - getUnits($1,"M",1048576);
        } else {
		    $conargs{memoryMB} = getUnits($memory, "M", 1048576);
        }
	}

	my $disk;
	my $devices = $vmview->config->hardware->device;
	my $label;
	my $device;
	my $cmdLabel;
	my $newSize;
	my @devChanges;

	if(@deregister) {
		for $disk (@deregister) {
			$device = getDiskByLabel($disk, $devices);
			unless($device) {
				xCAT::SvrUtils::sendmsg([1,"Disk:  $disk does not exist"], $output_handler,$node);
				return;
			}
			#xCAT::SvrUtils::sendmsg(Dumper($device));
			push @devChanges, VirtualDeviceConfigSpec->new(
						device => $device,
						operation =>  VirtualDeviceConfigSpecOperation->new('remove'));

		}
	}

	if(@purge) {
		for $disk (@purge) {
			$device = getDiskByLabel($disk, $devices);
			unless($device) {
				xCAT::SvrUtils::sendmsg([1,"Disk:  $disk does not exist"], $output_handler,$node);
				return;
			}
			#xCAT::SvrUtils::sendmsg(Dumper($device));
			push @devChanges, VirtualDeviceConfigSpec->new(
						device => $device,
						operation =>  VirtualDeviceConfigSpecOperation->new('remove'),
						fileOperation =>  VirtualDeviceConfigSpecFileOperation->new('destroy'));

		}
     
	}
  
	if(@add) {
		my $addSizes = join(',',@add);
		my $scsiCont;
		my $scsiUnit;
		my $ideCont;
		my $ideUnit;
		my $label;
        my $idefull=0;
        my $scsifull=0;
		foreach $device (@$devices) {
			$label = $device->deviceInfo->label;
			if($label =~ /^SCSI controller/) {
				my $tmpu=getAvailUnit($device->{key},$devices,maxnum=>15);
                if ($tmpu > 0) {
                    $scsiCont = $device;
                    $scsiUnit=$tmpu;
                } else {
                    $scsifull=1;
                }
                    #ignore scsiControllers that are full, problem still remains if trying to add across two controllers in one go
            }
			if($label =~ /^IDE/ and not $ideCont) {
				my $tmpu=getAvailUnit($device->{key},$devices,maxnum=>1);
                                if ($tmpu >= 0) {
				    $ideCont = $device;
                                    $ideUnit = $tmpu;
				} elsif ($device->{key} == 201) {
                    $idefull=1;
                }
            }
		}
        unless ($hyphash{$hyp}->{datastoremap}) { validate_datastore_prereqs([],$hyp); }
        push @devChanges, create_storage_devs($node,$hyphash{$hyp}->{datastoremap},$addSizes,$scsiCont,$scsiUnit,$ideCont,$ideUnit,$devices,idefull=>$idefull,scsifull=>$scsifull);
    }

	if ($cdrom or $eject) {
		my $opticalbackingif;
		my $opticalconnectable;
    	if ($cdrom) {
		    my $storageurl;
			if ($cdrom =~ m!://!) {
				$storageurl=$cdrom;
				$storageurl =~ s!/[^/]*\z!!;
				unless (validate_datastore_prereqs([],$hyp,{$storageurl=>[$node]})) {
					xCAT::SvrUtils::sendmsg([1,"Unable to find/mount datastore holding $cdrom"], $output_handler,$node);
					return;
				}
				$cdrom =~ s!.*/!!;
			} else {
				$storageurl = $tablecfg{vm}->{$node}->[0]->{storage};
				$storageurl =~ s/=.*//;
				$storageurl =~ s/.*,//;
				$storageurl =~ s/\/\z//;
			}
	        $opticalbackingif = VirtualCdromIsoBackingInfo->new( fileName => "[".$hyphash{$hyp}->{datastoremap}->{$storageurl}."] $cdrom");
	    	$opticalconnectable = VirtualDeviceConnectInfo->new(startConnected=>1,allowGuestControl=>1,connected=>1);
		} elsif ($eject) {
			$opticalbackingif=VirtualCdromRemoteAtapiBackingInfo->new(deviceName=>"");
	    	$opticalconnectable=VirtualDeviceConnectInfo->new(startConnected=>0,allowGuestControl=>1,connected=>0);
		}
			my $oldcd;
			foreach my $dev (@$devices) {
				if ($dev->deviceInfo->label eq "CD/DVD drive 1") {
					$oldcd=$dev;
					last;
				}
			}
			unless ($oldcd) {
				if ($cdrom) {
					xCAT::SvrUtils::sendmsg([1,"Unable to find Optical drive in VM to insert ISO image"], $output_handler,$node);
				} else {
					xCAT::SvrUtils::sendmsg([1,"Unable to find Optical drive in VM to perform eject"], $output_handler,$node);
				}
				return;
			}
			my $newDevice = VirtualCdrom->new(backing => $opticalbackingif,
						key=>$oldcd->key,
						controllerKey=>201,
						unitNumber=>0,
                        connectable=>$opticalconnectable,
						);
				push @devChanges, VirtualDeviceConfigSpec->new(
						device => $newDevice,
						operation =>  VirtualDeviceConfigSpecOperation->new('edit'));

	}
	if(%resize) {
		while( my ($key, $value) = each(%resize) ) {
			my @drives = split(/,/, $key);
			for my $device ( @drives ) {
				my $disk = $device;
				$device = getDiskByLabel($disk, $devices);
				unless($device) {
					xCAT::SvrUtils::sendmsg([1,"Disk:  $disk does not exist"], $output_handler,$node);
					return;
				}
                if ($value =~ /^\+(.+)/) {
                    $value = $device->capacityInKB + getUnits($1,"G",1024);
                } else {
				    $value = getUnits($value, "G", 1024);
                }
				my $newDevice = VirtualDisk->new(deviceInfo => $device->deviceInfo,
                        			key => $device->key,
						controllerKey => $device->controllerKey,
						unitNumber => $device->unitNumber,
						deviceInfo => $device->deviceInfo,
						backing => $device->backing,
                        			capacityInKB => $value); 
				push @devChanges, VirtualDeviceConfigSpec->new(
						device => $newDevice,
						operation =>  VirtualDeviceConfigSpecOperation->new('edit'));
			}
		}

	}
	if(@devChanges) {
		$conargs{deviceChange} = \@devChanges;
	}
    if (@otherparams) {
        my $key;
        my $value;
        my @optionvals;
        foreach (@otherparams) {
            ($key,$value) = split /=/;
            unless ($key) {
	            xCAT::SvrUtils::sendmsg([1,"Invalid format for other parameter specification"], $output_handler,$node);
                return;
            }
            if ($value) {
                push @optionvals,OptionValue->new(key=>$key,value=>$value);
            } else {
                push @optionvals,OptionValue->new(key=>$key); #the api doc says this is *supposed* to delete a key, don't think it works though, e.g. http://communities.vmware.com/message/1602644
            }
        }
        $conargs{extraConfig} = \@optionvals;
    }

	my $reconfigspec = VirtualMachineConfigSpec->new(%conargs);
	
	#xCAT::SvrUtils::sendmsg("reconfigspec = ".Dumper($reconfigspec));
	my $task = $vmview->ReconfigVM_Task(spec=>$reconfigspec);
	$running_tasks{$task}->{task} = $task;
	$running_tasks{$task}->{callback} = \&chvm_task_callback;
	$running_tasks{$task}->{hyp} = $hyp;
	$running_tasks{$task}->{data} = { node => $node, successtext => "node successfully changed",cpus=>$cpuCount,mem=>$memory };

}

sub getUsedUnits {
  my $contKey = shift;
  my $devices = shift;
  my %usedids;
  $usedids{7}=1;
  $usedids{'7'}=1; #TODO: figure out which of these is redundant, the string or the number variant
  for my $device (@$devices) {
    if($device->{controllerKey} eq $contKey) {
        $usedids{$device->{unitNumber}}=1;
    }
  }
  return \%usedids;
}
sub getAvailUnit {
  my $contKey = shift;
  my $devices = shift;
  my %args = @_;
  my $maxunit=-1;
  if (defined $args{maxnum}) {
     $maxunit=$args{maxnum};
  }
  my %usedids;
  $usedids{7}=1;
  $usedids{'7'}=1; #TODO: figure out which of these is redundant, the string or the number variant
  for my $device (@$devices) {
    if($device->{controllerKey} eq $contKey) {
        $usedids{$device->{unitNumber}}=1;
    }
  }
  my $highestUnit=0;
  while ($usedids{$highestUnit}) {
      if ($highestUnit == $maxunit) {
         return -1;
      }
      $highestUnit++;
  }
  return $highestUnit;
}

#given a device list from a vm and a label for a hard disk, returns the device object
sub getDiskByLabel {
  my $cmdLabel = shift;
  my $devices = shift;
  my $device;
  my $label;

  $cmdLabel = commandLabel($cmdLabel);
  foreach $device (@$devices) {
    $label = $device->deviceInfo->label;

    if($cmdLabel eq $label) {
      return $device;
    } elsif (($label =~ /^Hard disk/) and ($cmdLabel =~ /^d(.*)/)) {
        my $desc = $1;
        if ($desc =~ /(.*):(.*)/) {#specific
            my $controller=$1;
            my $unit=$2;
            if ($device->unitNumber == $unit and $device->controllerKey == $controller) {
                return $device;
            }
        } elsif ($desc =~ /\d+/ and $device->unitNumber == $desc) { #not specific
            return $device;
        }
    }

  }
  return undef;
}

#takes a label for a hard disk and prepends "Hard disk " if it's not there already
sub commandLabel {
  my $label = shift;
  if(($label =~ /^Hard disk/) or ($label =~ /^d\d+/)) {
    return $label;
  }
  return "Hard disk ".$label;
}

#this function will check pending task status
sub process_tasks {
        foreach (keys %running_tasks) {
            my $curcon;
            if (defined $running_tasks{$_}->{conn}) {
                $curcon = $running_tasks{$_}->{conn};
            } elsif ($running_tasks{$_}->{hyp}) {
                $curcon = $hyphash{$running_tasks{$_}->{hyp}}->{conn}; 
            } elsif ($running_tasks{$_}->{vm}) {
                $curcon = $vmhash{$running_tasks{$_}->{vm}}->{conn}; 
            } elsif ($running_tasks{$_}->{cluster}) {
                 $curcon = $clusterhash{$running_tasks{$_}->{cluster}}->{conn};
            } else {
                use Carp qw/confess/;
                confess "This stack trace indicates a cluster unfriendly path";
            }
            my $curt = $curcon->get_view(mo_ref=>$running_tasks{$_}->{task});
            my $state = $curt->info->state->val;
            unless ($state eq 'running' or $state eq 'queued') {
                $running_tasks{$_}->{callback}->($curt,$running_tasks{$_}->{data});
                delete $running_tasks{$_};
            }
            if ($state eq 'running' and not $running_tasks{$_}->{questionasked}) { # and $curt->info->progress == 95) { #This is unfortunate, there should be a 'state' to indicate a question is blocking
                    #however there isn't, so if we see something running at 95%, we just manually see if a question blocked the rest
                    my $vm;
                    $@="";
                    eval {
                       $vm = $curcon->get_view(mo_ref=>$curt->info->entity);
                    }; 
                    if ($@) { $vm = 0; }
                    if ($vm and $vm->{summary} and  $vm->summary->{runtime} and $vm->summary->runtime->{question} and $vm->summary->runtime->question) {
                        $running_tasks{$_}->{questionasked}=1;
                         $running_tasks{$_}->{callback}->($curt,$running_tasks{$_}->{data},$vm->summary->runtime->question,$vm);
                    } 
            }
        }
}
#this function is a barrier to ensure prerequisites are met
sub wait_for_tasks {
    while (scalar keys %running_tasks) {
        process_tasks;
        sleep (1); #We'll check back in every second.  Unfortunately, we have to poll since we are in web service land
    }
}

sub connecthost_callback {
    my $task = shift;
    my $args = shift;
    my $hv = $args->{hostview};
    my $state = $task->info->state->val;
    if ($state eq "success") {
        $hypready{$args->{hypname}}=1; #declare readiness
        enable_vmotion(hypname=>$args->{hypname},hostview=>$args->{hostview},conn=>$args->{conn});
        $vcenterhash{$args->{vcenter}}->{goodhyps}->{$args->{hypname}} = 1;
        if (defined $args->{depfun}) { #If a function is waiting for the host connect to go valid, call it
            $args->{depfun}->($args->{depargs});
        }
        return;
    }
    my $thumbprint;
    eval {
        $thumbprint = $task->{info}->error->fault->thumbprint;
    };
    if ($thumbprint) { #was an unknown certificate error, retry and accept the unknown certificate
       $args->{connspec}->{sslThumbprint}=$task->info->error->fault->thumbprint;
       my $task;
       if (defined $args->{hostview}) {#It was a reconnect request
           $task = $hv->ReconnectHost_Task(cnxSpec=>$args->{connspec});
       } elsif (defined $args->{foldview}) {#was an add host request
            $task = $args->{foldview}->AddStandaloneHost_Task(spec=>$args->{connspec},addConnected=>1);
       } elsif (defined $args->{cluster}) {#was an add host to cluster request
            $task = $args->{cluster}->AddHost_Task(spec=>$args->{connspec},asConnected=>1);
       }
       $running_tasks{$task}->{task} = $task;
       $running_tasks{$task}->{callback} = \&connecthost_callback;
       $running_tasks{$task}->{conn} = $args->{conn};
       $running_tasks{$task}->{data} = $args; #{ conn_spec=>$connspec,hostview=>$hv,hypname=>$args->{hypname},vcenter=>$args->{vcenter} };
    } elsif ($state eq 'error') {
        my $error = $task->info->error->localizedMessage;
        if (defined ($task->info->error->fault->faultMessage)) { #Only in 4.0, support of 3.5 must be careful?
            foreach(@{$task->info->error->fault->faultMessage}) {
                $error.=$_->message;
            }
        }
        xCAT::SvrUtils::sendmsg([1,$error], $output_handler); #,$node);
        $hypready{$args->{hypname}} = -1; #Impossible for this hypervisor to ever be ready
        $vcenterhash{$args->{vcenter}}->{badhyps}->{$args->{hypname}} = 1;
    }
}

sub delhost_callback { #only called in rmhypervisor -f case during validate vcenter phase
    my $task = shift;
    my $args = shift;
    my $hv = $args->{hostview};
    my $state = $task->info->state->val;
    if ($state eq "success") {
       xCAT::SvrUtils::sendmsg("removed", $output_handler,$args->{hypname});
       $hypready{$args->{hypname}} = -1; #Impossible for this hypervisor to ever be ready
       $vcenterhash{$args->{vcenter}}->{badhyps}->{$args->{hypname}} = 1;
    } elsif ($state eq 'error') {
        my $error = $task->info->error->localizedMessage;
        if (defined ($task->info->error->fault->faultMessage)) { #Only in 4.0, support of 3.5 must be careful?
            foreach(@{$task->info->error->fault->faultMessage}) {
                $error.=$_->message;
            }
        }
        xCAT::SvrUtils::sendmsg([1,$error], $output_handler); #,$node);
        $hypready{$args->{hypname}} = -1; #Impossible for this hypervisor to ever be ready
        $vcenterhash{$args->{vcenter}}->{badhyps}->{$args->{hypname}} = 1;
    }
}

sub get_clusterview {
    my %args = @_;
    my $clustname = $args{clustname};
    my %subargs = (
        view_type=>'ClusterComputeResource',
    );
    if ($args{properties}) {
        $subargs{properties}=$args{properties};
    }
    $subargs{filter}={name=>$clustname};
    my $view = $args{conn}->find_entity_view(%subargs);
    return $view;
   #foreach (@{$args{conn}->find_entity_views(%subargs)}) {
   #   if ($_->name eq "$clustname") {
   #       return $_;
   #       last;
   #   }
   #}
}

sub get_hostview {
    my %args = @_;
    my $host = $args{hypname};
    my %subargs = (
        view_type=>'HostSystem',
    );
    if ($args{properties}) {
        $subargs{properties}=$args{properties};
    }
    my @addrs = gethostbyname($host);
    my $ip;
    my $name;
    my $aliases;
    if ($addrs[4]) {
        $ip=inet_ntoa($addrs[4]);
        ($name, $aliases) = gethostbyaddr($addrs[4],AF_INET); #TODO: IPv6
    } else  {
        ($ip,$name,$aliases) = ($host,$host,"");
    }
    my @matchvalues = ($host,$ip,$name);
    foreach (split /\s+/,$aliases) {
        push @matchvalues,$_;
    }
    my $view;
    $subargs{filter}={'name' => qr/$host(?:\.|\z)/};
    $view = $args{conn}->find_entity_view(%subargs);
    if ($view) { return $view; }
    foreach (@matchvalues) {
        $subargs{filter}={'name' => qr/$_(?:\.|\z)/};
        $view = $args{conn}->find_entity_view(%subargs);
        if ($view) { return $view; }
    }
    $subargs{filter}={'name' => qr/localhost(?:\.|\z)/};
    $view = $args{conn}->find_entity_view(%subargs);
    if ($view) { return $view; }
    return undef; #rest of function should be obsoleted, going to run with that assumption for 2.5 at least
#    $subargs{filter}={'name' =~ qr/.*/};
#   foreach (@{$args{conn}->find_entity_views(%subargs)}) {
#      my $view = $_;
#      if ($_->name =~ /$host(?:\.|\z)/ or $_->name =~ /localhost(?:\.|\z)/ or grep { $view->name =~ /$_(?:\.|\z)/ } @matchvalues) {
#          return $view;
#          last;
#      }
#   }
}
sub enable_vmotion {
#TODO: vmware 3.x semantics too?  this is 4.0...
    my %args = @_;
    unless ($args{hostview}) {
        $args{hostview} = get_hostview(conn=>$args{conn},hypname=>$args{hypname},properties=>['configManager','name']);
    }
    my $nicmgr=$args{conn}->get_view(mo_ref=>$args{hostview}->configManager->virtualNicManager);
    my $qnc = $nicmgr->QueryNetConfig(nicType=>"vmotion");
    if ($qnc->{selectedVnic}) {
        return 1;
    } else {
        my $vniccount=scalar @{$qnc->candidateVnic};
        if ($vniccount==1 or ($vniccount==2 and $qnc->candidateVnic->[1]->spec->ip->ipAddress =~ /^169.254/)) { #There is only one possible path, use it
            $nicmgr->SelectVnicForNicType(nicType=>"vmotion",device=>$qnc->candidateVnic->[0]->device);
            return 1;
        } else {
            xCAT::SvrUtils::sendmsg([1,"TODO: use configuration to pick the nic ".$args{hypname}], $output_handler);
        }
        return 0;
    }
}
sub mkvm_callback {
    my $task = shift;
    my $args = shift;
    my $node = $args->{node};
    my $hyp = $args->{hyp};
    if ($task->info->state->val eq 'error') {
        my $error = $task->info->error->localizedMessage;
        xCAT::SvrUtils::sendmsg([1,$error], $output_handler,$node);
    }
}

sub relay_vmware_err {
    my $task = shift;
    my $extratext = shift;
    my @nodes = @_;
    my $error = $task->info->error->localizedMessage;
    if (defined ($task->info->error->fault->faultMessage)) { #Only in 4.0, support of 3.5 must be careful?
        foreach(@{$task->info->error->fault->faultMessage}) {
          $error.=$_->message;
        }
    }
    if (@nodes) {
        foreach (@nodes) {
            xCAT::SvrUtils::sendmsg([1,$extratext.$error], $output_handler,$_);
        }
    }else {
            xCAT::SvrUtils::sendmsg([1,$extratext.$error], $output_handler);
    }
}

sub relocate_callback {
    my $task = shift;
    my $parms = shift;
    my $state = $task->info->state->val;
    if ($state eq 'success') {
        my $vmtab = xCAT::Table->new('vm'); #TODO: update vm.storage?
        my $prevloc = $tablecfg{vm}->{$parms->{node}}->[0]->{storage}; 
        my $model;
        ($prevloc,$model) = split /=/,$prevloc;
        my $target = $parms->{target};
        if ($model) {
            $target.="=$model";
        }
        $vmtab->setNodeAttribs($parms->{node},{storage=>$target});
        xCAT::SvrUtils::sendmsg(":relocated to to ".$parms->{target}, $output_handler,$parms->{node});
    } else {
        relay_vmware_err($task,"Relocating to ".$parms->{target}." ",$parms->{node});
    }
}
sub migrate_ok { #look like a successful migrate, callback for registering a vm
     my %args = @_;
     my $vmtab = xCAT::Table->new('vm');
     $vmtab->setNodeAttribs($args{nodes}->[0],{host=>$args{target}});
     xCAT::SvrUtils::sendmsg("migrated to ".$args{target}, $output_handler,$args{nodes}->[0]);
}
sub migrate_callback {
    my $task = shift;
    my $parms = shift;
    my $state = $task->info->state->val;
    if (not $parms->{skiptodeadsource} and $state eq 'success') {
        my $vmtab = xCAT::Table->new('vm');
        $vmtab->setNodeAttribs($parms->{node},{host=>$parms->{target}});
        xCAT::SvrUtils::sendmsg("migrated to ".$parms->{target}, $output_handler,$parms->{node});
    } elsif($parms->{offline}) { #try a forceful RegisterVM instead
        my $target = $parms->{target};
        my $hostview = $hyphash{$target}->{conn}->find_entity_view(view_type=>'VirtualMachine',properties=>['config.name'],filter=>{name=>$parms->{node}});
   if ($hostview) { #this means vcenter still has it in inventory, but on a dead node...
                    #unfortunately, vcenter won't give up the old one until we zap the dead hypervisor
                    #also unfortunately, it doesn't make it easy to find said hypervisor..
        $hostview = $hyphash{$parms->{src}}->{conn}->get_view(mo_ref=>$hyphash{$parms->{src}}->{deletionref});
       	$task = $hostview->Destroy_Task();
        $running_tasks{$task}->{task} = $task;
        $running_tasks{$task}->{callback} = \&migrate_callback;
        $running_tasks{$task}->{conn} = $hyphash{$target}->{vcenter}->{conn};
        $running_tasks{$task}->{data} = { offline=>1, src=>$parms->{src}, node=>$parms->{node}, target=>$target, skiptodeadsource=>1 };
	} else { #it is completely gone, attempt a register_vm strategy
           register_vm($target,$parms->{node},undef,\&migrate_ok,{ nodes => [$parms->{node}], target=>$target, },"failonerror");
	}
    } else {
        relay_vmware_err($task,"Migrating to ".$parms->{target}." ",$parms->{node});
    }
}

sub poweron_task_callback {
    my $task = shift;
    my $parms = shift;
    my $q = shift; #question if blocked
    my $vm = shift; #path to answer questions if asked
    my $state = $task->info->state->val;
    my $node = $parms->{node};
    my $intent = $parms->{successtext};
    if ($state eq 'success') {
        xCAT::SvrUtils::sendmsg($intent, $output_handler,$node);
    } elsif ($state eq 'error') {
        relay_vmware_err($task,"",$node);
    }  elsif ($q and $q->text =~ /^msg.uuid.altered:/ and ($q->choice->choiceInfo->[0]->summary eq 'Cancel' and ($q->choice->choiceInfo->[0]->key eq '0'))) { #make sure it is what is what we have seen it to be
        if ($parms->{forceon} and $q->choice->choiceInfo->[1]->summary =~ /I (_)?moved it/ and $q->choice->choiceInfo->[1]->key eq '1') { #answer the question as 'moved'
            $vm->AnswerVM(questionId=>$q->id,answerChoice=>'1');
        } else {
            $vm->AnswerVM(questionId=>$q->id,answerChoice=>'0');
            xCAT::SvrUtils::sendmsg([1,"Failure powering on VM, it mismatched against the hypervisor.  If positive VM is not running on another hypervisor, use -f to force VM on"], $output_handler,$node);
        }
    } elsif ($q) {
        if ($q->choice->choiceInfo->[0]->summary eq 'Cancel') {
            xCAT::SvrUtils::sendmsg([1,":Cancelling due to unexpected question executing task: ".$q->text], $output_handler,$node);
        } else {
            xCAT::SvrUtils::sendmsg([1,":Task hang due to unexpected question executing task, need to use VMware tools to clean up the mess for now: ".$q->text], $output_handler,$node);
        }
    }

}
sub chvm_task_callback {
    my $task = shift;
    my $parms = shift;
    my $state = $task->info->state->val;
    my $node = $parms->{node};
    my $intent = $parms->{successtext};
    if ($state eq 'success') {
        my $updatehash;
        if ($parms->{cpus} and  $tablecfg{vm}->{$node}->[0]->{cpus}) { #need to update
            $updatehash->{cpus}=$parms->{cpus};
        }
        if ($parms->{mem} and  $tablecfg{vm}->{$node}->[0]->{memory}) { #need to update
            $updatehash->{memory}=$parms->{mem};
        }
        if ($updatehash) {
            my $vmtab = xCAT::Table->new('vm',-create=>1);
            $vmtab->setNodeAttribs($node,$updatehash);
        }
        xCAT::SvrUtils::sendmsg($intent, $output_handler,$node);
    } elsif ($state eq 'error') {
        relay_vmware_err($task,"",$node);
    }
}
sub generic_task_callback {
    my $task = shift;
    my $parms = shift;
    my $state = $task->info->state->val;
    my $node = $parms->{node};
    my $intent = $parms->{successtext};
    if ($state eq 'success') {
        xCAT::SvrUtils::sendmsg($intent, $output_handler,$node);
    } elsif ($state eq 'error') {
        relay_vmware_err($task,"",$node);
    }
}

sub migrate {
    my %args = @_;
    my @nodes = @{$args{nodes}};
    my $hyp = $args{hyp};
    my $vcenter = $hyphash{$hyp}->{vcenter}->{name};
    my $datastoredest;
    my $offline;
    @ARGV=@{$args{exargs}};
    unless (GetOptions(
        's=s' => \$datastoredest,
        'f' => \$offline,
        )) {
        xCAT::SvrUtils::sendmsg([1,"Error parsing arguments"], $output_handler);
        return;
    }
    my $target=$hyp; #case for storage migration
    if ($datastoredest) { $datastoredest =~ s/=.*//; }#remove =scsi and similar if specified
    if ($datastoredest and scalar @ARGV) {
        xCAT::SvrUtils::sendmsg([1,"Unable to mix storage migration and processing of arguments ".join(' ',@ARGV)], $output_handler);
        return;
    } elsif (@ARGV) {
        $target=shift @ARGV;
        if (@ARGV) {
            xCAT::SvrUtils::sendmsg([1,"Unrecognized arguments ".join(' ',@ARGV)], $output_handler);
            return;
        }
    } elsif ($datastoredest) { #storage migration only
        unless (validate_datastore_prereqs([],$hyp,{$datastoredest=>\@nodes})) {
            xCAT::SvrUtils::sendmsg([1,"Unable to find/mount target datastore $datastoredest"], $output_handler);
            return;
        }
        foreach (@nodes) {
            my $hostview = $hyphash{$hyp}->{conn}->find_entity_view(view_type=>'VirtualMachine',properties=>['config.name'],filter=>{name=>$_});
            my $relocatspec = VirtualMachineRelocateSpec->new(
                datastore=>$hyphash{$hyp}->{datastorerefmap}->{$datastoredest},
                );
            my $task = $hostview->RelocateVM_Task(spec=>$relocatspec);
            $running_tasks{$task}->{task} = $task;
            $running_tasks{$task}->{callback} = \&relocate_callback;
            $running_tasks{$task}->{hyp} = $args{hyp}; 
            $running_tasks{$task}->{data} = { node => $_, target=>$datastoredest }; 
            process_tasks; #check for tasks needing followup actions before the task is forgotten (VMWare's memory is fairly short at times
        }
        return;
    }
    if ((not $offline and $vcenterhash{$vcenter}->{badhyps}->{$hyp}) or $vcenterhash{$vcenter}->{badhyps}->{$target}) {
        xCAT::SvrUtils::sendmsg([1,"Unable to migrate ".join(',',@nodes)." to $target due to inability to validate vCenter connectivity"], $output_handler);
        return;
    }
    if (($offline or $vcenterhash{$vcenter}->{goodhyps}->{$hyp}) and $vcenterhash{$vcenter}->{goodhyps}->{$target}) {
        unless (validate_datastore_prereqs(\@nodes,$target)) {
            xCAT::SvrUtils::sendmsg([1,"Unable to verify storage state on target system"], $output_handler);
            return;
        }
        unless (validate_network_prereqs(\@nodes,$target)) {
            xCAT::SvrUtils::sendmsg([1,"Unable to verify target network state"], $output_handler);
            return;
        }
        my $dstview = get_hostview(conn=>$hyphash{$target}->{conn},hypname=>$target,properties=>['name','parent']);
        unless ($hyphash{$target}->{pool}) {
            $hyphash{$target}->{pool} = $hyphash{$target}->{conn}->get_view(mo_ref=>$dstview->parent,properties=>['resourcePool'])->resourcePool;
        }
        foreach (@nodes) {
            process_tasks; #check for tasks needing followup actions before the task is forgotten (VMWare's memory is fairly short at times
            my $srcview = $hyphash{$target}->{conn}->find_entity_view(view_type=>'VirtualMachine',properties=>['config.name'],filter=>{name=>$_});
	    if ($offline and not $srcview) { #we have a request to resurrect the dead..
           	register_vm($target,$_,undef,\&migrate_ok,{ nodes => [$_], exargs => $args{exargs}, target=>$target, hyp => $args{hyp}, offline => $offline },"failonerror");
		return;
	    } elsif (not $srcview) { 
                $srcview = $hyphash{$hyp}->{conn}->find_entity_view(view_type=>'VirtualMachine',properties=>['config.name'],filter=>{name=>$_});
	    }
	    unless ($srcview) {
		xCAT::SvrUtils::sendmsg([1,"Unable to locate node in vCenter"], $output_handler,$_);
		next;
	    }
		
            my $task = $srcview->MigrateVM_Task(
                host=>$dstview,
                pool=>$hyphash{$target}->{pool},
                priority=>VirtualMachineMovePriority->new('highPriority'));
            $running_tasks{$task}->{task} = $task;
            $running_tasks{$task}->{callback} = \&migrate_callback;
            $running_tasks{$task}->{hyp} = $args{hyp}; 
            $running_tasks{$task}->{data} = { node => $_, src=>$hyp, target=>$target, offline => $offline }; 
        }
    } else {
        #xCAT::SvrUtils::sendmsg("Waiting for BOTH to be 'good'");
        return; #One of them is still 'pending'
    }
}


sub reconfig_callback {
    my $task = shift;
    my $args = shift;
    #$args->{reconfig_args}->{vmview}->update_view_data();
    delete $args->{reconfig_args}->{vmview}; #Force a reload of the view, update_view_data seems to not work as advertised..
    $args->{reconfig_fun}->(%{$args->{reconfig_args}});
}

sub repower { #Called to try power again after power down for reconfig
    my $task = shift;
    my $args  = shift;
    my $powargs=$args->{power_args};
    $powargs->{pretendop}=1;
    #$powargs->{vmview}->update_view_data();
    delete $powargs->{vmview}; #Force a reload of the view, update_view_data seems to not work as advertised..
    power(%$powargs);
}

sub retry_rmvm {
    my $task = shift;
    my $args = shift;
    my $node = $args->{node};
    my $state = $task->info->state->val;
    if ($state eq "success") {
    #$Data::Dumper::Maxdepth=2;
        delete $args->{args}->{vmview};
        rmvm(%{$args->{args}});
    } elsif ($state eq 'error') {
        relay_vmware_err($task,"",$node);
    }
}

sub rmvm {
    my %args = @_;
    my $node = $args{node};
    my $hyp = $args{hyp};
    if (not defined $args{vmview}) { #attempt one refresh
        $args{vmview} = $vmhash{$node}->{conn}->find_entity_view(view_type => 'VirtualMachine',properties=>['config.name','runtime.powerState'],filter=>{name=>$node});
        if (not defined $args{vmview}) { 
            xCAT::SvrUtils::sendmsg([1,"VM does not appear to exist"], $output_handler,$node);
            return;
        }
    }
    @ARGV= @{$args{exargs}};
    require Getopt::Long;
    my $forceremove;
    my $purge;
    GetOptions(
        'f' => \$forceremove,
        'p' => \$purge,
        );
    my $task;
    unless ($args{vmview}->{'runtime.powerState'}->val eq 'poweredOff') {
        if ($forceremove) {
            $task = $args{vmview}->PowerOffVM_Task();
            $running_tasks{$task}->{task} = $task;
            $running_tasks{$task}->{callback} = \&retry_rmvm,
            $running_tasks{$task}->{hyp} = $args{hyp}; 
            $running_tasks{$task}->{vm} = $node;
            $running_tasks{$task}->{data} = { node => $node, args=>\%args }; 
            return;
        } else {
            xCAT::SvrUtils::sendmsg([1,"Cannot rmvm active guest (use -f argument to force)"], $output_handler,$node);
            return;
        }
    }
    if ($purge) {
        $task = $args{vmview}->Destroy_Task();
        $running_tasks{$task}->{data} = { node => $node, successtext => 'purged' };
        $running_tasks{$task}->{task} = $task;
        $running_tasks{$task}->{callback} = \&generic_task_callback;
        $running_tasks{$task}->{hyp} = $args{hyp}; #$hyp_conns->{$hyp};
        $running_tasks{$task}->{vm} = $node;
    } else {
        $task = $args{vmview}->UnregisterVM();
    }
}



sub getreconfigspec {
    my %args = @_;
    my $node = $args{node};
    my $vmview = $args{view};
    my $currid=$args{view}->{'config.guestId'};
    my $rightid=getguestid($node);
    my %conargs;
    my $reconfigneeded=0;
    if ($currid ne $rightid) {
        $reconfigneeded=1;
        $conargs{guestId}=$rightid;
    }
    my $newmem;
    if ($tablecfg{vm}->{$node}->[0]->{memory} and $newmem = getUnits($tablecfg{vm}->{$node}->[0]->{memory},"M",1048576)) {
        my $currmem = $vmview->{'config.hardware.memoryMB'};
        if ($newmem ne $currmem) {
            $conargs{memoryMB} = $newmem;
            $reconfigneeded=1;
        }
    }
    my $newcpus;
    if ($tablecfg{vm}->{$node}->[0]->{cpus} and $newcpus = $tablecfg{vm}->{$node}->[0]->{cpus}) {
        my $currncpu = $vmview->{'config.hardware.numCPU'};
        if ($newcpus ne $currncpu) {
            $conargs{numCPUs} = $newcpus;
            $reconfigneeded=1;
        }
    }
    if ($reconfigneeded) {
        return VirtualMachineConfigSpec->new(%conargs);
    } else {
        return 0;
    }
}

#This routine takes a single node, managing vmv instance, and task tracking hash to submit a power on request
sub power {
    my %args = @_;
    my $node = $args{node};
    my $hyp = $args{hyp};
    my $pretendop = $args{pretendop}; #to pretend a system was on for reset or boot when we have to turn it off internally for reconfig
    if (not defined $args{vmview}) { #attempt one refresh
        $args{vmview} = $vmhash{$node}->{conn}->find_entity_view(view_type => 'VirtualMachine',properties=>['config.name','config.guestId','config.hardware.memoryMB','config.hardware.numCPU','runtime.powerState'],filter=>{name=>$node});
        #vmview not existing now is not an issue, this function
        #is designed to handle that and correct if reasonably possible
        #comes into play particularly in a stateless context
    }
    @ARGV = @{$args{exargs}}; #for getoptions;
    my $forceon;
    require Getopt::Long;
    GetOptions(
        'force|f' => \$forceon,
        );
    my $subcmd = $ARGV[0];
    my $intent="";
    my $task;
    my $currstat;

    if ($args{vmview}) {
       $currstat = $args{vmview}->{'runtime.powerState'}->val;
       if (grep /$subcmd/,qw/on reset boot/) {
           my $reconfigspec;
           if ($reconfigreset and ($reconfigspec = getreconfigspec(node=>$node,view=>$args{vmview}))) {
               if ($currstat eq 'poweredOff') {
                   #xCAT::SvrUtils::sendmsg("Correcting guestId because $currid and $rightid are not the same...");#DEBUG
                    my $task = $args{vmview}->ReconfigVM_Task(spec=>$reconfigspec);
                    $running_tasks{$task}->{task} = $task;
                    $running_tasks{$task}->{callback} = \&reconfig_callback;
                    $running_tasks{$task}->{hyp} = $args{hyp}; 
                    $running_tasks{$task}->{vm} = $node;
                    $running_tasks{$task}->{data} = { node => $node, reconfig_fun=>\&power, reconfig_args=>\%args }; 
                return;
               } elsif (grep /$subcmd/,qw/reset boot/) { #going to have to do a 'cycle' and present it up normally..
                    #xCAT::SvrUtils::sendmsg("DEBUG: forcing a cycle");
                    $task = $args{vmview}->PowerOffVM_Task();
                    $running_tasks{$task}->{task} = $task;
                    $running_tasks{$task}->{callback} = \&repower;
                    $running_tasks{$task}->{hyp} = $args{hyp}; 
                    $running_tasks{$task}->{vm} = $node;
                    $running_tasks{$task}->{data} = { node => $node, power_args=>\%args}; 
                    return; #we have to wait
               }
#TODO: fixit
           #xCAT::SvrUtils::sendmsg("I see vm has $currid and I want it to be $rightid");
           }
       }
    } else {
        $currstat = 'off';
    }
    if ($currstat eq 'poweredOff') {
                $currstat = 'off';
            } elsif ($currstat eq 'poweredOn') {
                $currstat = 'on';
            } elsif ($currstat eq 'suspended') {
                $currstat = 'suspend';
            }
            if ($subcmd =~ /^stat/) {
                xCAT::SvrUtils::sendmsg($currstat, $output_handler,$node);
                return;
            }
            if ($subcmd =~ /boot/) {
                $intent = "$currstat ";
                if ($currstat eq 'on' or $args{pretendop}) {
                    $intent = "on ";
                    $subcmd = 'reset';
                } else {
                    $subcmd = 'on';
                }
            }
            if ($subcmd =~ /on/) {
                if ($currstat eq 'off' or $currstat eq 'suspend') {
                    if (not $args{vmview}) { #We are asking to turn on a system the hypervisor
                        #doesn't know, attempt to register it first
                        register_vm($hyp,$node,undef,\&power,\%args);
                        return; #We'll pick it up on the retry if it gets registered
                    } 
                    eval {
                        if ($hyp) {
                            $task = $args{vmview}->PowerOnVM_Task(host=>$hyphash{$hyp}->{hostview});
                        } else {
                            $task = $args{vmview}->PowerOnVM_Task(); #DRS may have it's way with me
                        }
                    };
                    if ($@) {
                        xCAT::SvrUtils::sendmsg([1,":".$@], $output_handler,$node);
                        return;
                    }
                    $running_tasks{$task}->{task} = $task;
                    $running_tasks{$task}->{callback} = \&poweron_task_callback;
                    $running_tasks{$task}->{hyp} = $args{hyp}; #$hyp_conns->{$hyp};
                    $running_tasks{$task}->{vm} = $node;
                    $running_tasks{$task}->{data} = { node => $node, successtext => $intent.'on', forceon=>$forceon };
                } else {
                    xCAT::SvrUtils::sendmsg($currstat, $output_handler,$node);
                }
            } elsif ($subcmd =~ /softoff/) {
                if ($currstat eq 'on') {
                    $args{vmview}->ShutdownGuest();
                    xCAT::SvrUtils::sendmsg("softoff", $output_handler,$node);
                } else {
                    xCAT::SvrUtils::sendmsg($currstat, $output_handler,$node);
                }
            } elsif ($subcmd =~ /off/) {
                if ($currstat eq 'on') {
                    $task = $args{vmview}->PowerOffVM_Task();
                    $running_tasks{$task}->{task} = $task;
                    $running_tasks{$task}->{callback} = \&generic_task_callback;
                    $running_tasks{$task}->{hyp} = $args{hyp}; 
                    $running_tasks{$task}->{vm} = $node;
                    $running_tasks{$task}->{data} = { node => $node, successtext => 'off' }; 
                } else {
                    xCAT::SvrUtils::sendmsg($currstat, $output_handler,$node);
                }
            } elsif ($subcmd =~ /suspend/) {
                if ($currstat eq 'on') {
                    $task = $args{vmview}->SuspendVM_Task();
                    $running_tasks{$task}->{task} = $task;
                    $running_tasks{$task}->{callback} = \&generic_task_callback;
                    $running_tasks{$task}->{hyp} = $args{hyp}; 
                    $running_tasks{$task}->{vm} = $node;
                    $running_tasks{$task}->{data} = { node => $node, successtext => 'suspend' }; 
                } else {
                    xCAT::SvrUtils::sendmsg("off", $output_handler,$node);
                }
            } elsif ($subcmd =~ /reset/) {
                if ($currstat eq 'on') {
                    $task = $args{vmview}->ResetVM_Task();
                    $running_tasks{$task}->{task} = $task;
                    $running_tasks{$task}->{callback} = \&generic_task_callback;
                    $running_tasks{$task}->{hyp} = $args{hyp}; 
                    $running_tasks{$task}->{vm} = $node;
                    $running_tasks{$task}->{data} = { node => $node, successtext => $intent.'reset' }; 
                } elsif ($args{pretendop}) { #It is off, but pretend it was on
                    eval {
                        if ($hyp) {
                            $task = $args{vmview}->PowerOnVM_Task(host=>$hyphash{$hyp}->{hostview});
                        } else {
                            $task = $args{vmview}->PowerOnVM_Task(); #allow DRS
                        }
                    };
                    if ($@) {
                        xCAT::SvrUtils::sendmsg([1,":".$@], $output_handler,$node);
                        return;
                    }
                    $running_tasks{$task}->{task} = $task;
                    $running_tasks{$task}->{callback} = \&generic_task_callback;
                    $running_tasks{$task}->{hyp} = $args{hyp}; 
                    $running_tasks{$task}->{vm} = $node;
                    $running_tasks{$task}->{data} = { node => $node, successtext => $intent.'reset' }; 
                } else {
                    xCAT::SvrUtils::sendmsg($currstat, $output_handler,$node);
                }
            }
}
sub generic_vm_operation { #The general form of firing per-vm requests to ESX hypervisor
    my $properties = shift; #The relevant properties to the general task, MUST INCLUDE config.name
    my $function = shift; #The function to actually run against the right VM view
    my @exargs = @_; #Store the rest to pass on
    my $hyp; 
    my $vmviews;
    my %vcviews; #views populated once per vcenter server for improved performance
    my $node;
    foreach $hyp (keys %hyphash) {
        if ($viavcenterbyhyp->{$hyp}) {
    	    foreach $node (keys %{$hyphash{$hyp}->{nodes}}){
                $vcenterhash{$hyphash{$hyp}->{vcenter}->{name}}->{vms}->{$node}=1;
            }
        }
    }
	foreach (keys %limbonodes) {
		$vcenterhash{$limbonodes{$_}}->{vms}->{$_}=1;
	}
    my $cluster;
    foreach $cluster (keys %clusterhash) {
        foreach $node (keys %{$clusterhash{$cluster}->{nodes}}) {
            $vcenterhash{$clusterhash{$cluster}->{vcenter}->{name}}->{vms}->{$node}=1;
        }
    }
    my $currentvcenter;
    my %foundlimbo;
    foreach $currentvcenter (keys %vcenterhash) {
        #retrieve all vm views in one gulp
        my $vmsearchstring = join(")|(",keys %{$vcenterhash{$currentvcenter}->{vms}});
        $vmsearchstring = '^(('.$vmsearchstring.'))(\z|\.)';
        my $regex = qr/$vmsearchstring/;
        $vcviews{$currentvcenter} = $vcenterhash{$currentvcenter}->{conn}->find_entity_views(view_type => 'VirtualMachine',properties=>$properties,filter=>{'config.name'=>$regex});
            foreach (@{$vcviews{$currentvcenter}}) {
                my $node = $_->{'config.name'};
                unless (defined $tablecfg{vm}->{$node}) {
                    $node =~ s/\..*//; #try the short name;
                }
                if (defined $tablecfg{vm}->{$node}) { #see if the host pointer requires a refresh 
		    my $hostref = $hostrefbynode{$node};
		    if ($hostref and $hostref eq $_->{'runtime.host'}->value) { next; } #the actual host reference  matches the one that we got when populating hostviews based on what the table had to say #TODO: does this mean it is buggy if we want to mkvm/rmigrate/etc if the current vm.host is wrong and the noderange doesn't have something on the right hostview making us not get it in the
		    #mass request?  Or is it just slower because it hand gets host views?
                    my $host = $vcenterhash{$currentvcenter}->{conn}->get_view(mo_ref=>$_->{'runtime.host'},properties=>['summary.config.name']);
		    $host = $host->{'summary.config.name'};
                    my $shost = $host;
                    $shost =~ s/\..*//;
                    #time to figure out which of these is a node
                    my @nodes = noderange("$host,$shost");
                    my $vmtab = xCAT::Table->new("vm",-create=>1);
                    unless($vmtab){
                        die "Error opening vm table";
                    }
                    if ($nodes[0]) {
						if ($limbonodes{$node}) { $foundlimbo{$node}=$currentvcenter; }
                        $vmtab->setNodeAttribs($node,{host=>$nodes[0]});
                    } #else {
                      #  $vmtab->setNodeAttribs($node,{host=>$host});
                    #}
                }
            }
    }
	foreach my $lnode (keys %foundlimbo) {
                $vmviews= $vcviews{$foundlimbo{$lnode}};
                my %mgdvms; #sort into a hash for convenience
                foreach (@$vmviews) {
                     $mgdvms{$_->{'config.name'}} = $_;
                }
                $function->(
                    node=>$lnode,
                    vm=>$lnode,
                    vmview=>$mgdvms{$node},
                    exargs=>\@exargs
                    );
	}
    my @entitylist;
    push @entitylist,keys %hyphash;
    push @entitylist,keys %clusterhash;
    foreach my $entity (@entitylist) {
        if ($hyphash{$entity}) {
            $hyp=$entity; #save some retyping...
            if ($viavcenterbyhyp->{$hyp}) { 
                $vmviews= $vcviews{$hyphash{$hyp}->{vcenter}->{name}}
            } else {
                $vmviews = [];
                my $node;
        	    foreach $node (sort (keys %{$hyphash{$hyp}->{nodes}})){
        		    push @{$vmviews},$hyphash{$hyp}->{conn}->find_entity_view(view_type => 'VirtualMachine',properties=>$properties,filter=>{'config.name'=>qr/^$node/});
                }
    		    #$vmviews = $hyphash{$hyp}->{conn}->find_entity_views(view_type => 'VirtualMachine',properties=>$properties);
    	    }
            my %mgdvms; #sort into a hash for convenience
            foreach (@$vmviews) {
                 $mgdvms{$_->{'config.name'}} = $_;
            }
            my $node;
        	foreach $node (sort (keys %{$hyphash{$hyp}->{nodes}})){
                $function->(
                    node=>$node,
                    hyp=>$hyp,
                    vmview=>$mgdvms{$node},
                    exargs=>\@exargs
                );
            process_tasks; #check for tasks needing followup actions before the task is forgotten (VMWare's memory is fairly short at times
        }
        } else { #a cluster.
                $vmviews= $vcviews{$clusterhash{$entity}->{vcenter}->{name}};
                my %mgdvms; #sort into a hash for convenience
                foreach (@$vmviews) {
                     $mgdvms{$_->{'config.name'}} = $_;
                }
                my $node;
                foreach $node (sort (keys %{$clusterhash{$entity}->{nodes}})){
                $function->(
                    node=>$node,
                    cluster=>$entity,
                    vm=>$node,
                    vmview=>$mgdvms{$node},
                    exargs=>\@exargs
                    );
            }
        }
    }
}

sub generic_hyp_operation { #The general form of firing per-hypervisor requests to ESX hypervisor
    my $function = shift; #The function to actually run against the right VM view
    my @exargs = @_; #Store the rest to pass on
    my $hyp;
    if (scalar keys %limbonodes) { #we are in forced migration with dead sources, try to register them
    	@ARGV=@exargs;
	my $datastoredest;
	my $offline;
        unless (GetOptions(
	        's=s' => \$datastoredest,
               'f' => \$offline,
        )) {
        xCAT::SvrUtils::sendmsg([1,"Error parsing arguments"], $output_handler);
        return;
        }
    if ($datastoredest) {
        xCAT::SvrUtils::sendmsg([1,"Storage migration impossible with dead hypervisor, must be migrated to live hypervisor first"], $output_handler);
        return;
    } elsif (@ARGV) {
        my $target=shift @ARGV;
        if (@ARGV) {
            xCAT::SvrUtils::sendmsg([1,"Unrecognized arguments ".join(' ',@ARGV)], $output_handler);
            return;
        }
	foreach (keys %limbonodes) {
	       register_vm($target,$_,undef,\&migrate_ok,{ nodes => [$_], target=>$target, },"failonerror");
	}
    } else { #storage migration only
            xCAT::SvrUtils::sendmsg([1,"No target hypervisor specified"], $output_handler);

    }
    }
    foreach $hyp (keys %hyphash) {
         process_tasks; #check for tasks needing followup actions before the task is forgotten (VMWare's memory is fairly short at times
        my @relevant_nodes = sort (keys %{$hyphash{$hyp}->{nodes}});
        unless (scalar @relevant_nodes) {
            next;
        }
        $function->(
            nodes => \@relevant_nodes,
            hyp => $hyp,
            exargs => \@exargs
        );
        #my $vmviews = $hyp_conns->{$hyp}->find_entity_views(view_type => 'VirtualMachine',properties=>['runtime.powerState','config.name']);
        #my %mgdvms; #sort into a hash for convenience
        #foreach (@$vmviews) {
        # $mgdvms{$_->{'config.name'}} = $_;
        #}
        #my $node;
    	#foreach $node (sort (keys %{$hyp_hash->{$hyp}->{nodes}})){
        #    $function->($node,$mgdvms{$node},$taskstotrack,$callback,@exargs);
#REMINDER FOR RINV TO COME
#     foreach (@nothing) { #@{$mgdvms{$node}->config->hardware->device}) {
#           if (defined $_->{macAddress}) {
#                  print "\nFound a mac: ".$_->macAddress."\n";
#               }
#           }
#        }
    }
    foreach $hyp (keys %clusterhash) { #clonevm, mkvm, rmigrate could land here in clustered mode with DRS/HA
        process_tasks;
        my @relevant_nodes = sort (keys %{$clusterhash{$hyp}->{nodes}});
        unless (scalar @relevant_nodes) {
            next;
        }
        $function->(nodes => \@relevant_nodes,cluster=>$hyp,exargs => \@exargs,conn=>$clusterhash{$hyp}->{conn});
    }
}

sub rmhypervisor_disconnected {
    my $task = shift;
    my $parms = shift;
    my $node = $parms->{node};
    my $hyp = $node;
    my $state = $task->info->state->val;
    if ($state eq 'success') {
        my $task = $hyphash{$hyp}->{hostview}->Destroy_Task();
	$running_tasks{$task}->{data} = { node => $node, successtext => 'removed' };
	$running_tasks{$task}->{task} = $task;
	$running_tasks{$task}->{callback} = \&generic_task_callback;
        $running_tasks{$task}->{hyp} =$hyp;
    } elsif ($state eq 'error') {
        relay_vmware_err($task,"",$node);
    }
}
sub rmhypervisor_inmaintenance {
    my $task = shift;
    my $parms = shift;
    my $state = $task->info->state->val;
    my $node = $parms->{node};
    my $intent = $parms->{successtext};
    if ($state eq 'success') {
        my $hyp = $parms->{node};
        my $task = $hyphash{$hyp}->{hostview}->DisconnectHost_Task();
        $running_tasks{$task}->{task} = $task;
        $running_tasks{$task}->{callback} = \&rmhypervisor_disconnected;
        $running_tasks{$task}->{hyp} = $hyp; 
        $running_tasks{$task}->{data} = { node => $hyp }; 
    } elsif ($state eq 'error') {
        relay_vmware_err($task,"",$node);
    }
}

sub lsvm {
    my %args = @_;
    my $hyp = $args{hyp};
    $hyphash{$hyp}->{hostview} = get_hostview(hypname=>$hyp,conn=>$hyphash{$hyp}->{conn}); #,properties=>['config','configManager']); 
    use Data::Dumper;
    my $vms = $hyphash{$hyp}->{hostview}->vm;
    unless ($vms) {
        return;
    }
    foreach (@$vms) {
        my $vmv = $hyphash{$hyp}->{conn}->get_view(mo_ref=>$_);
        xCAT::SvrUtils::sendmsg($vmv->name, $output_handler,$hyp);
    }
    return;
}

sub chhypervisor {
    my %args = @_;
    @ARGV = @{$args{exargs}}; #for getoptions;
    my $maintenance;
	my $online;
    my $stat;
    my $vlanaddspec;
    my $vlanremspec;
    require Getopt::Long;
    GetOptions(
        'maintenance|m' => \$maintenance,
        'online|o' => \$online,
        'show|s' => \$stat,
        'show|s' => \$stat,
        'addvlan=s' => \$vlanaddspec,
        'removevlan=s' => \$vlanremspec,
        );
    my $hyp = $args{hyp};
    $hyphash{$hyp}->{hostview} = get_hostview(hypname=>$hyp,conn=>$hyphash{$hyp}->{conn}); #,properties=>['config','configManager']); 
    if ($maintenance) {
    if (defined $hyphash{$hyp}->{hostview}) {
        my $task = $hyphash{$hyp}->{hostview}->EnterMaintenanceMode_Task(timeout=>0);
        $running_tasks{$task}->{task} = $task;
        $running_tasks{$task}->{callback} = \&generic_task_callback;
        $running_tasks{$task}->{hyp} = $args{hyp}; 
        $running_tasks{$task}->{data} = { node => $hyp , successtext => "hypervisor in maintenance mode"}; 
    }
    } elsif ($online) {
    if (defined $hyphash{$hyp}->{hostview}) {
        my $task = $hyphash{$hyp}->{hostview}->ExitMaintenanceMode_Task(timeout=>0);
        $running_tasks{$task}->{task} = $task;
        $running_tasks{$task}->{callback} = \&generic_task_callback;
        $running_tasks{$task}->{hyp} = $args{hyp}; 
        $running_tasks{$task}->{data} = { node => $hyp , successtext => "hypervisor online"}; 
    }
    } elsif ($stat) {
        if (defined $hyphash{$hyp}->{hostview}) {
                if ($hyphash{$hyp}->{hostview}->runtime->inMaintenanceMode) {
                        xCAT::SvrUtils::sendmsg("hypervisor in maintenance mode", $output_handler,$hyp);
                } else {
                        xCAT::SvrUtils::sendmsg("hypervisor online", $output_handler,$hyp);
                }
        }
    } elsif ($vlanaddspec) {
        fixup_hostportgroup($vlanaddspec, $hyp);
    } elsif ($vlanremspec) {
        fixup_hostportgroup($vlanremspec, $hyp, action=>'remove');
    }
    return;
}
  
sub rshutdown { #TODO: refactor with next function too
    my %args = @_;
    my $hyp = $args{hyp};
    $hyphash{$hyp}->{hostview} = get_hostview(hypname=>$hyp,conn=>$hyphash{$hyp}->{conn}); #,properties=>['config','configManager']); 
    if (defined $hyphash{$hyp}->{hostview}) {
        my $task = $hyphash{$hyp}->{hostview}->EnterMaintenanceMode_Task(timeout=>0);
        $running_tasks{$task}->{task} = $task;
        $running_tasks{$task}->{callback} = \&rshutdown_inmaintenance;
        $running_tasks{$task}->{hyp} = $args{hyp}; 
        $running_tasks{$task}->{data} = { node => $hyp }; 
    }
    return;
}

sub rshutdown_inmaintenance {
    my $task = shift;
    my $parms = shift;
    my $state = $task->info->state->val;
    my $node = $parms->{node};
    my $intent = $parms->{successtext};
    if ($state eq 'success') {
        my $hyp = $parms->{node};
        if (defined $hyphash{$hyp}->{hostview}) {
            my $task = $hyphash{$hyp}->{hostview}->ShutdownHost_Task(force=>0);
            $running_tasks{$task}->{task} = $task;
            $running_tasks{$task}->{callback} = \&generic_task_callback;
            $running_tasks{$task}->{hyp} = $hyp;
            $running_tasks{$task}->{data} = { node => $hyp, successtext => "shutdown initiated" };
        }
    } elsif ($state eq 'error') {
        relay_vmware_err($task,"",$node);
    }
    return;
}

sub rescansan {
    my %args = @_;
    my $hyp = $args{hyp};
    my $hostview = get_hostview(hypname=>$hyp,conn=>$hyphash{$hyp}->{conn},properties=>['config','configManager']);
    if (defined $hostview) {
        my $hdss = $hostview->{vim}->get_view(mo_ref=>$hostview->configManager->storageSystem);
        $hdss->RescanAllHba();
        $hdss->RescanVmfs();
    }
}

sub formatdisk {
    my %args = @_;
    my $hyp = $args{hyp};
    $hyphash{$hyp}->{hostview} = get_hostview(hypname=>$hyp,conn=>$hyphash{$hyp}->{conn},properties=>['config','configManager']);
    @ARGV = @{$args{exargs}};
    my $nid;
    my $name;
    GetOptions(
        'id=s' => \$nid,
        'name=s' => \$name,
        );
    my $hostview = $hyphash{$hyp}->{hostview};
    if (defined $hyphash{$hyp}->{hostview}) {
        my $hdss = $hostview->{vim}->get_view(mo_ref=>$hostview->configManager->storageSystem);
        $hdss->RescanAllHba();
        my $dss = $hostview->{vim}->get_view(mo_ref=>$hostview->configManager->datastoreSystem);
        my $diskList = $dss->QueryAvailableDisksForVmfs(); 
        foreach my $disk (@$diskList) {
            foreach my $id (@{$disk->{descriptor}}) {
                if (lc($id->{id}) eq lc('naa.'.$nid)) {
                    my $options = $dss->QueryVmfsDatastoreCreateOptions(devicePath => $disk->devicePath);
                    @$options[0]->spec->vmfs->volumeName($name);
                    my $newDatastore = $dss->CreateVmfsDatastore(spec => @$options[0]->spec );
                }
            }
        }

    }
    return;
}

sub rmhypervisor {
    my %args = @_;
    my $hyp = $args{hyp};
    $hyphash{$hyp}->{hostview} = get_hostview(hypname=>$hyp,conn=>$hyphash{$hyp}->{conn}); #,properties=>['config','configManager']); 
    if (defined $hyphash{$hyp}->{hostview}) {
        my $task = $hyphash{$hyp}->{hostview}->EnterMaintenanceMode_Task(timeout=>0);
        $running_tasks{$task}->{task} = $task;
        $running_tasks{$task}->{callback} = \&rmhypervisor_inmaintenance;
        $running_tasks{$task}->{hyp} = $args{hyp}; 
        $running_tasks{$task}->{data} = { node => $hyp }; 
    }
    return;
}

sub clonevms {
    my %args=@_;
    my $nodes = $args{nodes};
    my $hyp = $args{hyp};
    my $cluster = $args{cluster};
    @ARGV = @{$args{exargs}}; #for getoptions;
    my $base;
    my $force;
    my $detach;
	my $specialize;
    my $target;
    require Getopt::Long;
    GetOptions(
        'b=s' => \$base,
        'f' => \$force,
        'd' => \$detach,
		'specialize' => \$specialize,
        't=s' => \$target,
        );
    if ($base and $target) {
        foreach my $node (@$nodes) {
            xCAT::SvrUtils::sendmsg([1,"Cannot specify both base (-b) and target (-t)"], $output_handler,$node);
        }
        return;
    }
    unless ($base or $target) {
        foreach my $node (@$nodes) {
            xCAT::SvrUtils::sendmsg([1,"Must specify one of base (-b) or target (-t)"], $output_handler,$node);
        }
        return;
    }
    if ($target and (scalar @{$nodes} != 1)) {
        foreach my $node (@$nodes) {
            xCAT::SvrUtils::sendmsg([1,"Cannot specify mulitple nodes to create a master from"], $output_handler,$node);
        }
        return;
    }
    if ($hyp) {
        $hyphash{$hyp}->{hostview} = get_hostview(hypname=>$hyp,conn=>$hyphash{$hyp}->{conn});
    }
    my $newdatastores;
    my $mastername;
    my $url;
    my $masterref;
    if ($base) { #if base, we need to pull in the target datastores
        my $mastertab=xCAT::Table->new('vmmaster');
        $masterref=$mastertab->getNodeAttribs( $base,[qw/storage os arch profile storagemodel nics specializeparameters/]);
        unless ($masterref) {
            foreach my $node (@$nodes) {
                xCAT::SvrUtils::sendmsg([1,"Cannot find master $base in vmmaster table"], $output_handler,$node);
            }
            return;
        }
        $newdatastores->{$masterref->{storage}}=[]; #make sure that the master datastore is mounted...
        foreach (@$nodes) {
            my $url;
            if ($tablecfg{vm}->{$_}->[0]->{storage}) {
                $url=$tablecfg{vm}->{$_}->[0]->{storage};
				$url =~ s/=.*//;
            } else {
                $url=$masterref->{storage};
            }
            unless ($url) { die "Shouldn't be possible"; }
            if (ref $newdatastores->{$_}) {
                push @{$newdatastores->{$url}},$_;
            } else {
               $newdatastores->{$url}=[$_];
            }
        }
    } elsif ($target) {
      if ($url =~ m!/!) {
        $url=$target;
	$url =~ s!/([^/]*)\z!!;
        $mastername=$1;
      } else {
	  $url = $tablecfg{vm}->{$nodes->[0]}->[0]->{storage};
	  $url =~ s/.*\|//;
	  $url =~ s/=(.*)//;
	  $url =~ s/,.*//;
	  $mastername=$target
      }
      $newdatastores->{$url}=[$nodes->[0]];
    }
    if ($hyp) {
        unless (validate_datastore_prereqs($nodes,$hyp,$newdatastores)) {
            return;
        }
    } else { #need to build datastore map for cluster
        refreshclusterdatastoremap($cluster);
    }
    sortoutdatacenters(nodes=>$nodes,hyp=>$hyp,cluster=>$cluster);
    if ($target) {
        return promote_vm_to_master(node=>$nodes->[0],target=>$target,force=>$force,detach=>$detach,cluster=>$cluster,hyp=>$hyp,url=>$url,mastername=>$mastername);
    } elsif ($base) {
        return clone_vms_from_master(nodes=>$nodes,base=>$base,detach=>$detach,cluster=>$cluster,hyp=>$hyp,mastername=>$base,masterent=>$masterref,specialize=>$specialize);
    }
}
sub sortoutdatacenters { #figure out all the vmfolders for all the nodes passed in
    my %args=@_;
    my $nodes=$args{nodes};
    my $hyp=$args{hyp};
    my $cluster=$args{cluster};
    my %nondefaultdcs;
    my $deffolder;
    my $conn;
    if ($hyp) {
        unless (defined $hyphash{$hyp}->{vmfolder}) {
            $hyphash{$hyp}->{vmfolder} = $hyphash{$hyp}->{conn}->get_view(mo_ref=>$hyphash{$hyp}->{conn}->find_entity_view(view_type=>'Datacenter',properties=>['vmFolder'])->vmFolder);
        }
        $conn= $hyphash{$hyp}->{conn};
        $deffolder=$hyphash{$hyp}->{vmfolder};
    } else { #clustered
        unless (defined $clusterhash{$cluster}->{vmfolder}) {
            $clusterhash{$cluster}->{vmfolder} = $clusterhash{$cluster}->{conn}->get_view(mo_ref=>$clusterhash{$cluster}->{conn}->find_entity_view(view_type=>'Datacenter',properties=>['vmFolder'])->vmFolder);
        }
        $deffolder=$clusterhash{$cluster}->{vmfolder};
        $conn= $clusterhash{$cluster}->{conn};
    }
    foreach (@$nodes) {
        if ($tablecfg{vm}->{$_}->[0]->{datacenter}) {
            $nondefaultdcs{$tablecfg{vm}->{$_}->[0]->{datacenter}}->{$_}=1;
        } else {
            $vmhash{$_}->{vmfolder}=$deffolder;
        }
    }
    my $datacenter;
    foreach $datacenter (keys %nondefaultdcs) {
        my $vmfolder= $conn->get_view(mo_ref=>$conn->find_entity_view(view_type=>'Datacenter',properties=>['vmFolder'],filter=>{name=>$datacenter})->vmFolder,filter=>{name=>$datacenter});
        foreach (keys %{$nondefaultdcs{$datacenter}}) {
            $vmhash{$_}->{vmfolder}=$vmfolder;
        }
    }
}
sub clone_vms_from_master {
    my %args = @_;
    my $mastername=$args{mastername};
	my $specialize=$args{specialize};
    my $hyp = $args{hyp};
    my $cluster=$args{cluster};
    my $regex=qr/^$mastername\z/;
    my @nodes=@{$args{nodes}};
    my $node;
    my $conn;
    if ($hyp) {
        $conn=$hyphash{$hyp}->{conn};
    } else {
        $conn=$clusterhash{$cluster}->{conn};
    }
    my $masterviews =  $conn->find_entity_views(view_type => 'VirtualMachine',filter=>{'config.name'=>$regex});
    if (scalar(@$masterviews) != 1) { 
        foreach $node (@nodes) {
            xCAT::SvrUtils::sendmsg([1,"Unable to find master $mastername in VMWare infrastructure"], $output_handler,$node);
        }
        return;
    }
    my $masterview=$masterviews->[0];
    my $masterent=$args{masterent};
    my $ostype;
    foreach $node (@nodes) {
        my $destination=$tablecfg{vm}->{$node}->[0]->{storage};
        my $nodetypeent;
        my $vment;
	    
        $ostype=$masterent->{'os'};
        foreach (qw/os arch profile/) {
            $nodetypeent->{$_}=$masterent->{$_};
        }
        foreach (qw/storagemodel nics/) {
            $vment->{$_}=$masterent->{$_};
        }
        $vment->{master}=$args{mastername};
        unless ($destination) {
            $destination=$masterent->{storage};
            $vment->{storage}=$destination;
        }
		$destination =~ s/=.*//;
        my $placement_resources=get_placement_resources(hyp=>$hyp,cluster=>$cluster,destination=>$destination);
        my $pool=$placement_resources->{pool};
        my $dstore=$placement_resources->{datastore};
        my %relocatespecargs =  (
           datastore=>$dstore, #$hyphash{$hyp}->{datastorerefmap}->{$destination},
           pool=>$pool,
           #diskMoveType=>"createNewChildDiskBacking", #fyi, requires a snapshot, which isn't compatible with templates, moveChildMostDiskBacking would potentially be fine, but either way is ha incopmatible and limited to 8, arbitrary limitations hard to work around...
           );
	unless ($args{detach}) {
	  $relocatespecargs{diskMoveType}="createNewChildDiskBacking";
	}
        if ($hyp) { $relocatespecargs{host}=$hyphash{$hyp}->{hostview} }
        my $relocatespec = VirtualMachineRelocateSpec->new(%relocatespecargs);
	my %clonespecargs = (        
            location=>$relocatespec,
            template=>0,
            powerOn=>0
            );
	unless ($args{detach}) {
	  $clonespecargs{snapshot}=$masterview->snapshot->currentSnapshot;
	}
	if ($specialize) {
	    my %custargs;
		if ($masterent->{specializeparameters}) { %custargs = ( parameters=>$masterent->{specializeparameters} ); }
		$clonespecargs{customization} = make_customization_spec($node,ostype=>$ostype,%custargs);
    }
	my $clonespec = VirtualMachineCloneSpec->new(%clonespecargs);
        my $vmfolder = $vmhash{$node}->{vmfolder};
        my $task = $masterview->CloneVM_Task(folder=>$vmfolder,name=>$node,spec=>$clonespec);
        $running_tasks{$task}->{data} = { node => $node, conn=>$conn, successtext => 'Successfully cloned from '.$args{mastername}, 
					  mastername=>$args{mastername}, nodetypeent=>$nodetypeent,vment=>$vment, 
					  hyp=>$args{hyp},
	};
        $running_tasks{$task}->{task} = $task;
        $running_tasks{$task}->{callback} = \&clone_task_callback;
        $running_tasks{$task}->{hyp} = $args{hyp}; #$hyp_conns->{$hyp};
        $running_tasks{$task}->{vm} = $node; #$hyp_conns->{$hyp};
    }
}

sub make_customization_spec {
	my $node = shift;
    my %args = @_;
	my $password;
	my $wintimezone;
	#map of number to strings can be found at 
	#http://osman-shener-en.blogspot.com/2008/02/unattendedtxt-time-zone-index.html
	my $fullname="Unspecified User";
	my $orgName="Unspecified Organization";
	if ($::XCATSITEVALS{winfullname}) { $fullname = $::XCATSITEVALS{winfullname}; }
	if ($::XCATSITEVALS{winorgname}) { $orgName = $::XCATSITEVALS{winorgname}; }
	my @runonce=(); #to be read in from postscripts table
	$wintimezone=xCAT::TZUtils::get_wintimezonenum();
	my $ptab=xCAT::Table->new('postscripts',-create=>0);
	
	if ($ptab) {
		my $psent = $ptab->getNodeAttribs($node,[qw/postscripts postbootscripts/]);
		if ($psent and $psent->{postscripts}) {
			push @runonce,split /,/,$psent->{postscripts};
		}
		if ($psent and $psent->{postbootscripts}) {
			push @runonce,split /,/,$psent->{postbootscripts};
		}
	}
    $ptab = xCAT::Table->new('passwd',-create=>0);
	unless ($ptab) {
		die "passwd table needed";
	}
	my ($passent) = $ptab->getAttribs({"key"=>"system",username=>"Administrator"},'password');
	unless ($passent) {
		die "need passwd table entry for system account Administrator";
	}
	$password=$passent->{password};
    my %lfpd;
    if ($args{ostype} and $args{ostype} =~ /win2k3/) {
		%lfpd = (
			licenseFilePrintData=>CustomizationLicenseFilePrintData->new(
				autoMode=>CustomizationLicenseDataMode->new(
				    'perSeat'
				)
			)
		);
    }
	my %runonce;
	if (scalar @runonce) { #skip section if no postscripts or postbootscripts
		%runonce=(
			guiRunOnce=>CustomizationGuiRunOnce->new(
            	commandList=>\@runonce,
            )
        );
    }
    my %autologonargs = ( autoLogon=>0, autoLogonCount=>1, );
    if ($args{parameters} and $args{parameters} =~ /autoLogonCount=([^,]*)/i) {
		my $count = $1;
		if ($count) { 
			$autologonargs{autoLogon}=1;
			$autologonargs{autoLogonCount}=$count;
        }
    }
	my $identity = CustomizationSysprep->new(
		%runonce,
		%lfpd,
		guiUnattended => CustomizationGuiUnattended->new(
			%autologonargs,
			password=>CustomizationPassword->new(
				plainText=>1,
				value=>$password,
			),
			timeZone=>$wintimezone,
		),
	identification=>get_customizedidentification(),
	userData=>CustomizationUserData->new(
		computerName=>CustomizationFixedName->new(name=>$node),
		fullName=>$fullname,
		orgName=>$orgName,
		productId=>"",
	),
  );
  my $options = CustomizationWinOptions->new(changeSID=>1,deleteAccounts=>0); 
  my $customizationspec = CustomizationSpec->new(
  	globalIPSettings=>CustomizationGlobalIPSettings->new(),
	identity=>$identity,
	nicSettingMap=>[
		CustomizationAdapterMapping->new(adapter=>CustomizationIPSettings->new(ip=>CustomizationDhcpIpGenerator->new()))
		],
	options=>$options,
  );
  return $customizationspec;

}

sub get_customizedidentification {
	#for now, just do a 'TBD' workgroup.  VMWare not supporting joining without domain admin password is rather unfortunate
     return CustomizationIdentification->new(
	            joinWorkgroup=>"TBD",
     );
}




sub get_placement_resources {
    my %args = @_;
    my $pool;
    my $dstore;
    my $hyp = $args{hyp};
    my $cluster = $args{cluster};
    my $destination=$args{destination};
    if ($hyp) {
      unless (defined $hyphash{$hyp}->{pool}) {
            $hyphash{$hyp}->{pool} = $hyphash{$hyp}->{conn}->get_view(mo_ref=>$hyphash{$hyp}->{hostview}->parent,properties=>['resourcePool'])->resourcePool;
        }
        $pool=$hyphash{$hyp}->{pool};
        if ($destination) { $dstore=$hyphash{$hyp}->{datastorerefmap}->{$destination} };
    } else {#clustered...
        unless (defined $clusterhash{$cluster}->{pool}) {
            my $cview = get_clusterview(clustname=>$cluster,conn=>$clusterhash{$cluster}->{conn});
            $clusterhash{$cluster}->{pool}=$cview->resourcePool;
        }
        $pool=$clusterhash{$cluster}->{pool};
        if ($destination) { $dstore=$clusterhash{$cluster}->{datastorerefmap}->{$destination} };
    }
    return {
        pool=>$pool,
        datastore=>$dstore,
    }
}

sub clone_task_callback {
    my $task = shift;
    my $parms = shift;
    my $state = $task->info->state->val;
    my $node = $parms->{node};
    my $conn = $parms->{conn};
    my $intent = $parms->{successtext};
    if ($state eq 'success') {
        #xCAT::SvrUtils::sendmsg($intent, $output_handler,$node);
        my $nodetype=xCAT::Table->new('nodetype',-create=>1);
        my $vm=xCAT::Table->new('vm',-create=>1);
        $vm->setAttribs({node=>$node},$parms->{vment});
	
        $nodetype->setAttribs({node=>$node},$parms->{nodetypeent});
	foreach (keys %{$parms->{vment}}) {
	  $tablecfg{vm}->{$node}->[0]->{$_}=$parms->{vment}->{$_};
	}
	
	my @networks = split /,/,$tablecfg{vm}->{$node}->[0]->{nics};
	my @macs = xCAT::VMCommon::getMacAddresses(\%tablecfg,$node,scalar @networks);
        #now with macs, change all macs in the vm to match our generated macs
	my $regex = qr/^$node(\z|\.)/;
	#have to do an expensive pull of the vm view, since it is brand new
	my $nodeviews = $conn->find_entity_views(view_type => 'VirtualMachine',filter=>{'config.name'=>$regex});
	unless (scalar @$nodeviews == 1) { die "this should be impossible"; }
	my $vpdtab=xCAT::Table->new('vpd',-create=>1);
	$vpdtab->setAttribs({node=>$node},{uuid=>$nodeviews->[0]->config->uuid});
	my $ndev;
	my @devstochange;
	foreach $ndev (@{$nodeviews->[0]->config->hardware->device}) {
	  unless ($ndev->{macAddress}) { next; } #not an ndev
	  $ndev->{macAddress}=shift @macs;
	  $ndev->{addressType}="manual";
	  push @devstochange, VirtualDeviceConfigSpec->new(
						device => $ndev,
						operation =>  VirtualDeviceConfigSpecOperation->new('edit'));
	}
	if (@devstochange) {
	  my $reconfigspec = VirtualMachineConfigSpec->new(deviceChange=>\@devstochange);
	  my $task = $nodeviews->[0]->ReconfigVM_Task(spec=>$reconfigspec);
	  $running_tasks{$task}->{task} = $task;
	  $running_tasks{$task}->{callback} = \&generic_task_callback;
	  $running_tasks{$task}->{hyp} = $parms->{hyp};
	  $running_tasks{$task}->{conn} = $parms->{conn};
	  $running_tasks{$task}->{data} = { node => $node, successtext => $intent};
	}


    } elsif ($state eq 'error') {
        relay_vmware_err($task,"",$node);
    }
}

sub promote_vm_to_master {
    my %args = @_;
    my $node=$args{node};
    my $hyp=$args{hyp};
    my $cluster=$args{cluster};
    my $regex=qr/^$node(\z|\.)/;
    my $conn;
    if ($hyp) {
        $conn=$hyphash{$hyp}->{conn};
    } else {
        $conn=$clusterhash{$cluster}->{conn};
    }
    my $nodeviews = $conn->find_entity_views(view_type => 'VirtualMachine',filter=>{'config.name'=>$regex});
    if (scalar(@$nodeviews) != 1) {
        xCAT::SvrUtils::sendmsg([1,"Cannot find $node in VMWare infrastructure"], $output_handler,$node);
        return;
    }
    my $nodeview = shift @$nodeviews;
    my $dstore;
    if ($hyp) {
       $dstore=$hyphash{$hyp}->{datastorerefmap}->{$args{url}},
    } else {
       $dstore=$clusterhash{$cluster}->{datastorerefmap}->{$args{url}},
    }
    my $relocatespec = VirtualMachineRelocateSpec->new(
       datastore=>$dstore,
    );
    my $clonespec = VirtualMachineCloneSpec->new(
        location=>$relocatespec,
        template=>0, #can't go straight to template, need to clone, then snap, then templatify
        powerOn=>0
        );

    my $vmfolder=$vmhash{$node}->{vmfolder};
    my $task = $nodeview->CloneVM_Task(folder=>$vmfolder,name=>$args{mastername},spec=>$clonespec);
    $running_tasks{$task}->{data} = { node => $node, hyp => $args{hyp}, conn => $conn, successtext => 'Successfully copied to '.$args{mastername}, mastername=>$args{mastername}, url=>$args{url} };
    $running_tasks{$task}->{task} = $task;
    $running_tasks{$task}->{callback} = \&promote_task_callback;
    $running_tasks{$task}->{hyp} = $args{hyp}; #$hyp_conns->{$hyp};
    $running_tasks{$task}->{vm}=$node;
}
sub promote_task_callback {
    my $task = shift;
    my $parms = shift;
    my $state = $task->info->state->val;
    my $node = $parms->{node};
    my $intent = $parms->{successtext};
    if ($state eq 'success') { #now, we have to make one snapshot for linked clones
      my $mastername=$parms->{mastername};
      my $regex=qr/^$mastername\z/;
      my $masterviews = $parms->{conn}->find_entity_views(view_type => 'VirtualMachine',filter=>{'config.name'=>$regex});
      unless (scalar @$masterviews == 1) {
	die "Impossible";
      }
      my $masterview = $masterviews->[0];
      my $task = $masterview->CreateSnapshot_Task(name=>"xcatsnap",memory=>"false",quiesce=>"false");
      $parms->{masterview}=$masterview;
      $running_tasks{$task}->{data} = $parms;
      $running_tasks{$task}->{task} = $task;
      $running_tasks{$task}->{callback} = \&promotesnap_task_callback;
      $running_tasks{$task}->{hyp} = $parms->{hyp}; #$hyp_conns->{$hyp};
      $running_tasks{$task}->{vm}=$parms->{node};
      #xCAT::SvrUtils::sendmsg($intent, $output_handler,$node);
    } elsif ($state eq 'error') {
        relay_vmware_err($task,"",$node);
    }
}
sub promotesnap_task_callback {
    my $task = shift;
    my $parms = shift;
    my $state = $task->info->state->val;
    my $node = $parms->{node};
    my $intent = $parms->{successtext};
    if ($state eq 'success') {
      $parms->{masterview}->MarkAsTemplate; #time to be a template
        xCAT::SvrUtils::sendmsg($intent, $output_handler,$node);
        my $mastertabentry = {
            originator=>$requester,
            vintage=>scalar(localtime),
            storage=>$parms->{url},
        };
        foreach (qw/os arch profile/) {
            if (defined ($tablecfg{nodetype}->{$node}->[0]->{$_})) {
                $mastertabentry->{$_}=$tablecfg{nodetype}->{$node}->[0]->{$_};
            }
        }
        foreach (qw/storagemodel nics/) {
            if (defined ($tablecfg{vm}->{$node}->[0]->{$_})) {
                $mastertabentry->{$_}=$tablecfg{vm}->{$node}->[0]->{$_};
            }
        }
        my $vmmastertab=xCAT::Table->new('vmmaster',-create=>1);
        my $date=scalar(localtime);
        $vmmastertab->setAttribs({name=>$parms->{mastername}},$mastertabentry);
    } elsif ($state eq 'error') {
        relay_vmware_err($task,"",$node);
    }
}
sub mkvms {
    my %args = @_;
    my $nodes = $args{nodes};
    my $hyp = $args{hyp};
    my $cluster = $args{cluster};
    @ARGV = @{$args{exargs}}; #for getoptions;
    my $disksize;
    require Getopt::Long;
    my $cpuCount;
    my $memory;
    GetOptions(
        'size|s=s' => \$disksize,
		"cpus=s"    => \$cpuCount,
		"mem=s"     => \$memory
        );
    my $node;
    my $conn;
    if ($hyp) {
        $hyphash{$hyp}->{hostview} = get_hostview(hypname=>$hyp,conn=>$hyphash{$hyp}->{conn}); #,properties=>['config','configManager']); 
        unless (validate_datastore_prereqs($nodes,$hyp)) {
            return;
        }
        $conn=$hyphash{$hyp}->{conn};
    } else {
        refreshclusterdatastoremap($cluster);
        $conn=$clusterhash{$cluster}->{conn};
    }
    sortoutdatacenters(nodes=>$nodes,hyp=>$hyp,cluster=>$cluster);
    my $placement_resources=get_placement_resources(hyp=>$hyp,cluster=>$cluster);
    #$hyphash{$hyp}->{pool} = $hyphash{$hyp}->{conn}->get_view(mo_ref=>$hyphash{$hyp}->{hostview}->parent,properties=>['resourcePool'])->resourcePool;
    my $cfg;
    foreach $node (@$nodes) {
         process_tasks; #check for tasks needing followup actions before the task is forgotten (VMWare's memory is fairly short at times
        if ($conn->find_entity_view(view_type=>"VirtualMachine",filter=>{name=>$node})) {
            xCAT::SvrUtils::sendmsg([1,"Virtual Machine already exists"], $output_handler,$node);
            next;
        } else {
            register_vm($hyp,$node,$disksize,undef,undef,undef,cpus=>$cpuCount,memory=>$memory,cluster=>$cluster);
        }
    }
    my @dhcpnodes;
    foreach (keys %{$tablecfg{dhcpneeded}}) {
        push @dhcpnodes,$_;
        delete $tablecfg{dhcpneeded}->{$_};
    }
    unless ($::XCATSITEVALS{'dhcpsetup'} and ($::XCATSITEVALS{'dhcpsetup'} =~ /^n/i or $::XCATSITEVALS{'dhcpsetup'} =~ /^d/i or $::XCATSITEVALS{'dhcpsetup'} eq '0')) {
        $executerequest->({command=>['makedhcp'],node=>\@dhcpnodes});
    }
}

sub setboot {
    my %args = @_;
    my $node = $args{node};
    my $hyp = $args{hyp};
    if (not defined $args{vmview}) { #attempt one refresh
        $args{vmview} = $vmhash{$node}->{conn}->find_entity_view(view_type => 'VirtualMachine',properties=>['config.name'],filter=>{name=>$node});
        if (not defined $args{vmview}) { 
            xCAT::SvrUtils::sendmsg([1,"VM does not appear to exist"], $output_handler,$node);
            return;
        }
    }
    my $bootorder = ${$args{exargs}}[0];
    #NOTE: VMware simply does not currently seem to allow programatically changing the boot
    #order like other virtualization solutions supported by xCAT.
    #This doesn't behave quite like any existing mechanism:
    #vm.bootorder was meant to take the place of system nvram, vmware imitates that unfortunate aspect of bare metal too well..
    #rsetboot was created to describe the ipmi scenario of a transient boot device, this is persistant *except* for setup, which is not
    #rbootseq was meant to be entirely persistant and ordered.  
    #rsetboot is picked, the usage scenario matches about as good as I could think of
    my $reconfigspec;
    if ($bootorder =~ /setup/) {
        unless ($bootorder eq 'setup') {
            xCAT::SvrUtils::sendmsg([1,"rsetboot parameter may not contain 'setup' with other items, assuming vm.bootorder is just 'setup'"], $output_handler,$node);
        }
        $reconfigspec = VirtualMachineConfigSpec->new(
            bootOptions=>VirtualMachineBootOptions->new(enterBIOSSetup=>1),
            );
    } else {
        $bootorder = "allow:".$bootorder;
        $reconfigspec = VirtualMachineConfigSpec->new(
                bootOptions=>VirtualMachineBootOptions->new(enterBIOSSetup=>0),
                extraConfig => [OptionValue->new(key => 'bios.bootDeviceClasses',value=>$bootorder)]
                );
    }
    my $task = $args{vmview}->ReconfigVM_Task(spec=>$reconfigspec);
    $running_tasks{$task}->{task} = $task;
    $running_tasks{$task}->{callback} = \&generic_task_callback;
    $running_tasks{$task}->{hyp} = $args{hyp}; 
    $running_tasks{$task}->{vm} = $args{node}; 
    $running_tasks{$task}->{data} = { node => $node, successtext => ${$args{exargs}}[0] }; 
}
sub register_vm {#Attempt to register existing instance of a VM
    my $hyp = shift;
    my $node = shift;
    my $disksize = shift;
    my $blockedfun = shift; #a pointer to a blocked function to call on success
    my $blockedargs = shift; #hash reference to call blocked function with
    my $failonerr = shift;
    my %args=@_; #ok, went overboard with positional arguments, from now on, named arguments
    my $task;
    if ($hyp) {
        validate_network_prereqs([keys %{$hyphash{$hyp}->{nodes}}],$hyp);
        unless (defined $hyphash{$hyp}->{datastoremap} or validate_datastore_prereqs([keys %{$hyphash{$hyp}->{nodes}}],$hyp)) {
            die "unexpected condition";
        }
    } else {
        scan_cluster_networks($args{cluster});
    }

    sortoutdatacenters(nodes=>[$node],hyp=>$hyp,cluster=>$args{cluster});
    my $placement_resources=get_placement_resources(hyp=>$hyp,cluster=>$args{cluster});

    # Try to add an existing VM to the machine folder
    my $success = eval {
        if ($hyp) {
            $task = $vmhash{$node}->{vmfolder}->RegisterVM_Task(path=>getcfgdatastore($node,$hyphash{$hyp}->{datastoremap})." /$node/$node.vmx",name=>$node,pool=>$hyphash{$hyp}->{pool},host=>$hyphash{$hyp}->{hostview},asTemplate=>0);
        } else {
            $task = $vmhash{$node}->{vmfolder}->RegisterVM_Task(path=>getcfgdatastore($node,$clusterhash{$args{cluster}}->{datastoremap})." /$node/$node.vmx",name=>$node,pool=>$placement_resources->{pool},asTemplate=>0);
        }
    };
    # if we couldn't add it then it means it wasn't created yet.  So we create it.
    my $cluster=$args{cluster};
    if ($@ or not $success) {
        #if (ref($@) eq 'SoapFault') {
        # if (ref($@->detail) eq 'NotFound') {
        register_vm_callback(undef, {
            node => $node,
            disksize => $disksize,
            blockedfun => $blockedfun,
            blockedargs => $blockedargs,
            errregister=>$failonerr,
            cpus=>$args{cpus},
            memory=>$args{memory},
            hyp => $hyp,
            cluster=>$cluster,
        });
    }
    if ($task) {
        $running_tasks{$task}->{task} = $task;
        $running_tasks{$task}->{callback} = \&register_vm_callback;
        $running_tasks{$task}->{hyp} = $hyp;
        $running_tasks{$task}->{cluster} = $cluster;
        $running_tasks{$task}->{data} = { 
            node => $node,
            disksize => $disksize,
            blockedfun => $blockedfun,
            blockedargs => $blockedargs,
            errregister=>$failonerr,
            cpus=>$args{cpus},
            memory=>$args{memory},
            hyp => $hyp,
            cluster=>$cluster,
        };
    }
}

sub register_vm_callback {
    my $task = shift;
    my $args = shift;
    if (not $task or $task->info->state->val eq 'error') { #TODO: fail for 'rpower' flow, mkvm is too invasive in VMWare to be induced by 'rpower on'
        if (not defined $args->{blockedfun}) {
            mknewvm($args->{node},$args->{disksize},$args->{hyp},$args);
        } elsif ($args->{errregister}) {
            relay_vmware_err($task,"",$args->{node});
        } else {
            xCAT::SvrUtils::sendmsg([1,"mkvm must be called before use of this function"], $output_handler,$args->{node});
        }
    } elsif (defined $args->{blockedfun}) { #If there is a blocked function, call it here) 
        $args->{blockedfun}->(%{$args->{blockedargs}});
    }
}
   

sub getURI {
    my $method = shift;
    my $location = shift;
    my $uri = '';

    if($method =~ /nfs/){

        (my $server,my $path) = split/\//,$location,2;
        $server =~ s/:$//; #tolerate habitual colons
        my $servern = inet_aton($server);
        unless ($servern) {
            xCAT::SvrUtils::sendmsg([1,"could not resolve '$server' to an address from vm.storage/vm.cfgstore"], $output_handler);
        }
        $server = inet_ntoa($servern);
        $uri = "nfs://$server/$path";
    }elsif($method =~ /vmfs/){
        (my $name, undef) = split /\//,$location,2;
        $name =~ s/:$//; #remove a : if someone put it in for some reason.  
        $uri = "vmfs://$name";
    }else{
        xCAT::SvrUtils::sendmsg([1,"Unsupported VMware Storage Method: $method.  Please use 'vmfs or nfs'"], $output_handler);
    }

    return $uri;
}

 
sub getcfgdatastore {
    my $node = shift;
    my $dses = shift;
    my $cfgdatastore = $tablecfg{vm}->{$node}->[0]->{cfgstore};
    unless ($cfgdatastore) {
        $cfgdatastore = $tablecfg{vm}->{$node}->[0]->{storage}; 
        #TODO: if multiple drives are specified, make sure to split this out
        #DONE: I believe the regex after this conditional takes care of that case already..
    }
    $cfgdatastore =~ s/=.*//;
    (my $method,my $location) = split /:\/\//,$cfgdatastore,2;
    my $uri = $cfgdatastore;
    unless ($dses->{$uri}) {  #don't call getURI if map works out fine already
        $uri = getURI($method,$location);
    }
    $cfgdatastore = "[".$dses->{$uri}."]";
    #$cfgdatastore =~ s/,.*$//; #these two lines of code were kinda pointless
    #$cfgdatastore =~ s/\/$//;
    return $cfgdatastore;
}


sub mknewvm {
        my $node=shift;
        my $disksize=shift;
        my $hyp=shift;
        my $otherargs=shift;
        my $cluster=$otherargs->{cluster};
        my $placement_resources=get_placement_resources(hyp=>$hyp,cluster=>$cluster);
        my $pool=$placement_resources->{pool};
        my $cfg;
        if ($hyp) {
           $cfg = build_cfgspec($node,$hyphash{$hyp}->{datastoremap},$hyphash{$hyp}->{nets},$disksize,$hyp,$otherargs);
        } else { #cluster based..
           $cfg = build_cfgspec($node,$clusterhash{$cluster}->{datastoremap},$clusterhash{$cluster}->{nets},$disksize,$hyp,$otherargs);
        }
        my $task;
        if ($hyp) {
          $task = $vmhash{$node}->{vmfolder}->CreateVM_Task(config=>$cfg,pool=>$hyphash{$hyp}->{pool},host=>$hyphash{$hyp}->{hostview});
        } else {
          $task = $vmhash{$node}->{vmfolder}->CreateVM_Task(config=>$cfg,pool=>$pool); #drs away
        }
        $running_tasks{$task}->{task} = $task;
        $running_tasks{$task}->{callback} = \&mkvm_callback;
        $running_tasks{$task}->{hyp} = $hyp;
        $running_tasks{$task}->{cluster} = $cluster;
        $running_tasks{$task}->{data} = { hyp=>$hyp, cluster=>$cluster, node => $node };
}


sub getUnits {
    my $amount = shift;
    my $defunit = shift;
    my $divisor=shift;
    unless ($amount) { return; }
    unless ($divisor) {
        $divisor = 1;
    }
    if ($amount =~ /(\D)$/) { #If unitless, add unit
        $defunit=$1;
        chop $amount;
    }
    if ($defunit =~ /k/i) {
        return $amount*1024/$divisor;
    } elsif ($defunit =~ /m/i) {
        return $amount*1048576/$divisor;
    } elsif ($defunit =~ /g/i) {
        return $amount*1073741824/$divisor;
    }
}


sub getguestid {
    my $osfound=0;
    my $node = shift;
    if ($tablecfg{vm}->{$node}->[0]->{guestostype}) { #if admin wants to skip derivation from nodetype.os value, let em
        return $tablecfg{vm}->{$node}->[0]->{guestostype};
    }
    my $nodeos = $tablecfg{nodetype}->{$node}->[0]->{os};
    my $nodearch = $tablecfg{nodetype}->{$node}->[0]->{arch};
    foreach (keys %guestidmap) {
        if (defined($nodeos) and $nodeos =~ /$_/) {
            if ($nodearch eq 'x86_64' and $_ !~ /vmkernel/) {
                $nodeos=$guestidmap{$_}."64Guest";
            } else {
                $nodeos=$guestidmap{$_};
                $nodeos =~ s/_$//;
                $nodeos .= "Guest";
            }
            $osfound=1;
            last;
        }
    }
    unless ($osfound) {
        if (defined($nodearch) and $nodearch eq 'x86_64') {
            $nodeos="otherGuest64";
        } else {
            $nodeos="otherGuest";
        }
    }
    return $nodeos;
}

sub build_cfgspec {
    my $node = shift;
    my $dses = shift; #map to match vm table to datastore names
    my $netmap = shift;
    my $disksize = shift;
    my $hyp = shift;
    my $otherargs=shift;
    my $memory;
    my $ncpus;
    my $updatehash;
    if ($otherargs->{memory}) {
        $memory=getUnits($otherargs->{memory},"M",1048576);
        if ($tablecfg{vm}->{$node}->[0]->{memory}) {
            $updatehash->{memory}=$memory;
        }
    } elsif ($tablecfg{vm}->{$node}->[0]->{memory}) {
        $memory = getUnits($tablecfg{vm}->{$node}->[0]->{memory},"M",1048576);
    } else {
        $memory = 512;
    }
    if ($otherargs->{cpus}) {
        $ncpus=$otherargs->{cpus};
        if ($tablecfg{vm}->{$node}->[0]->{cpus}) {
            $updatehash->{cpus}=$ncpus;
        }
    } elsif ($tablecfg{vm}->{$node}->[0]->{cpus}) {
        $ncpus = $tablecfg{vm}->{$node}->[0]->{cpus};
    } else {
        $ncpus = 1;
    }
    if ($updatehash) {
        my $vmtab = xCAT::Table->new('vm',-create=>1);
        $vmtab->setNodeAttribs($node,$updatehash);
    }
    my @devices;
    $currkey=0;
    my $opticalbacking = VirtualCdromRemoteAtapiBackingInfo->new(deviceName=>"");
    my $opticalconnectable = VirtualDeviceConnectInfo->new(startConnected=>0,allowGuestControl=>1,connected=>0);
    my $optical =VirtualCdrom->new( controllerKey => 201,
                        connectable=>$opticalconnectable,
                        backing=>$opticalbacking,
                        key => $currkey++,
                        unitNumber => 0, );
	push @devices,VirtualDeviceConfigSpec->new(device => $optical, operation =>  VirtualDeviceConfigSpecOperation->new('add'));
    push @devices,create_storage_devs($node,$dses,$disksize);
    push @devices,create_nic_devs($node,$netmap,$hyp);
    #my $cfgdatastore = $tablecfg{vm}->{$node}->[0]->{storage}; #TODO: need a new cfglocation field in case of stateless guest?
    #$cfgdatastore =~ s/,.*$//;
    #$cfgdatastore =~ s/\/$//;
    #$cfgdatastore = "[".$dses->{$cfgdatastore}."]";
    my $cfgdatastore = getcfgdatastore($node,$dses);
    my $vfiles = VirtualMachineFileInfo->new(vmPathName=>$cfgdatastore);
    #my $nodeos = $tablecfg{nodetype}->{$node}->[0]->{os};
    #my $nodearch = $tablecfg{nodetype}->{$node}->[0]->{arch};
    my $nodeos = getguestid($node); #nodeos=>$nodeos,nodearch=>$nodearch);
    my $uuid;
    if ($tablecfg{vpd}->{$node}->[0]->{uuid}) {
        $uuid = $tablecfg{vpd}->{$node}->[0]->{uuid};
    } else {
        if ($tablecfg{mac}->{$node}->[0]->{mac}) { #a uuidv1 is possible, generate that for absolute uniqueness guarantee
            my $mac = $tablecfg{mac}->{$node}->[0]->{mac};
            $mac =~ s/\|.*//;
            $mac =~ s/!.*//;
            $uuid=xCAT::Utils::genUUID(mac=>$mac);
        } else {
            $uuid=xCAT::Utils::genUUID();
        }
	
        my $vpdtab = xCAT::Table->new('vpd');
       	$vpdtab->setNodeAttribs($node,{uuid=>$uuid});
    }
    $uuid =~ s/^(..)(..)(..)(..)-(..)(..)-(..)(..)/$4$3$2$1-$6$5-$8$7/;
    my @optionvals;
    if ($tablecfg{vm}->{$node}->[0]->{othersettings}) {
        my $key;
        my  $value;
        foreach (split /;/,$tablecfg{vm}->{$node}->[0]->{othersettings}) {
            ($key,$value)=split /=/;
            if ($value) {
                push @optionvals,OptionValue->new(key=>$key,value=>$value);
            } else {
                push @optionvals,OptionValue->new(key=>$key);
            }
        }
    }
    my %specargs = (
            name => $node,
            files => $vfiles,
            guestId=>$nodeos,
            memoryMB => $memory,
            numCPUs => $ncpus,
            deviceChange => \@devices,
            uuid=>$uuid,
    );
    if (@optionvals) {
        $specargs{extraConfig}=\@optionvals;
    }
    return VirtualMachineConfigSpec->new(%specargs);
}

sub create_nic_devs {
    my $node = shift;
    my $netmap = shift;
    my $hyp = shift;
    my @networks = split /,/,$tablecfg{vm}->{$node}->[0]->{nics};
    my @devs;
    my $idx = 0;
    my @macs = xCAT::VMCommon::getMacAddresses(\%tablecfg,$node,scalar @networks);
    my $connprefs=VirtualDeviceConnectInfo->new(
                            allowGuestControl=>1,
                            connected=>0,
                            startConnected => 1
                            );
    my $model=$tablecfg{vm}->{$node}->[0]->{nicmodel};
    unless ($model) {
        $model='e1000';
    }
    foreach (@networks) {
        my $pgname=$_;
        if ($hyp) {
           $pgname = $hyphash{$hyp}->{pgnames}->{$_};
        }
        s/.*://;
        my $hadspecmodel=0;
        if (m/=/) {
            $hadspecmodel=1;
            s/=(.*)$//;
        }
        my $tmpmodel=$model;
        if ($hadspecmodel) { $tmpmodel=$1; }
        my $netname = $_;
        my $backing = VirtualEthernetCardNetworkBackingInfo->new(
            network => $netmap->{$pgname},
            deviceName=>$pgname,
        );
        my %newcardargs=(
            key=>0,#3, #$currkey++,
            backing=>$backing,
            addressType=>"manual",
            macAddress=>shift @macs,
            connectable=>$connprefs,
            wakeOnLanEnabled=>1, #TODO: configurable in tables?
            );
        my $newcard;
        if ($tmpmodel eq 'e1000') {
            $newcard=VirtualE1000->new(%newcardargs);
        } elsif ($tmpmodel eq 'vmxnet3') {
            $newcard=VirtualVmxnet3->new(%newcardargs);
        } elsif ($tmpmodel eq 'pcnet32') {
            $newcard=VirtualPCNet32->new(%newcardargs);
        } elsif ($tmpmodel eq 'vmxnet2') {
            $newcard=VirtualVmxnet2->new(%newcardargs);
        } elsif ($tmpmodel eq 'vmxnet') {
            $newcard=VirtualVmxnet->new(%newcardargs);
        } else {
            xCAT::SvrUtils::sendmsg([1,"$tmpmodel not a recognized nic type, falling back to e1000 (vmxnet3, e1000, pcnet32, vmxnet2, vmxnet are recognized"], $output_handler,$node);
            $newcard=VirtualE1000->new(%newcardargs);
        }
            
        push @devs,VirtualDeviceConfigSpec->new(device => $newcard,
                                                operation =>  VirtualDeviceConfigSpecOperation->new('add'));
        $idx++;
    }
    return @devs;
    die "Stop running for test";
}

sub create_storage_devs {
    my $node = shift;
    my $sdmap = shift;
    my $sizes = shift;
    my @sizes = split /[,:]/, $sizes;
    my $existingScsiCont = shift;
    my $scsiUnit = shift;
    my $existingIdeCont = shift;
    my $ideUnit = shift;
    my $devices = shift; 
    my %args=@_;
    my $scsicontrollerkey=0;
    my $idecontrollerkey=200; #IDE 'controllers' exist at 200 and 201 invariably, with no flexibility?
                              #Cannot find documentation that declares this absolute, but attempts to do otherwise
                              #lead in failure, also of note, these are single-channel controllers, so two devs per controller

    my $backingif;
    my @devs;
    my $havescsidevs =0;
    my $disktype = 'ide';
    my $ideunitnum=0; 
    my $scsiunitnum=0;
    my $havescsicontroller=0;
    my %usedideunits;
    my %usedscsiunits=(7=>1,'7'=>1);
    if (defined $existingScsiCont) { 
    $havescsicontroller=1;
	$scsicontrollerkey = $existingScsiCont->{key};
	$scsiunitnum = $scsiUnit;
    %usedscsiunits = %{getUsedUnits($scsicontrollerkey,$devices)};
    }
    if (defined $existingIdeCont) { 
	$idecontrollerkey = $existingIdeCont->{key};
	$ideunitnum = $ideUnit;
    %usedideunits = %{getUsedUnits($idecontrollerkey,$devices)};
    }
    my $unitnum;
    my %disktocont;
    my $dev;
    my @storelocs = split /,/,$tablecfg{vm}->{$node}->[0]->{storage};
    my $globaldisktype = $tablecfg{vm}->{$node}->[0]->{storagemodel};
    unless ($globaldisktype) { $globaldisktype='ide'; }
    #number of devices is the larger of the specified sizes (TODO: masters) or storage pools to span
    my $numdevs = (scalar @storelocs > scalar @sizes ? scalar @storelocs : scalar @sizes);
	my $controllertype='scsi';
    while ($numdevs-- > 0) {
        my $storeloc = shift @storelocs;
        unless (scalar @storelocs) { @storelocs = ($storeloc); } #allow reuse of one cfg specified pool for multiple devs
        my $disksize = shift @sizes;
        unless (scalar @sizes) { @sizes = ($disksize); } #if we emptied the array, stick the last entry back on to allow it to specify all remaining disks
        $disksize = getUnits($disksize,'G',1024);
        $disktype = $globaldisktype;
        if ($storeloc =~ /=/) {
            ($storeloc,$disktype) = split /=/,$storeloc;
        }
        if ($disktype eq 'ide' and $args{idefull}) {
            xCAT::SvrUtils::sendmsg([1,"VM is at capacity for IDE devices, a drive was not added"], $output_handler,$node);
            return;
        } elsif (($disktype eq 'scsi' or $disktype eq 'sas' or $disktype eq 'pvscsi') and $args{scsifull}) {
            xCAT::SvrUtils::sendmsg([1,"SCSI Controller at capacity, a drive was not added"], $output_handler,$node);
            return;
        }

        $storeloc =~ s/\/$//;
        (my $method,my $location) = split /:\/\//,$storeloc,2;
        my $uri = $storeloc;
        unless ($sdmap->{$uri}) {  #don't call getURI if map works out fine already
            $uri = getURI($method,$location);
        }
        #(my $server,my $path) = split/\//,$location,2;
        #$server =~ s/:$//; #tolerate habitual colons
        #my $servern = inet_aton($server);
        #unless ($servern) {
        #    xCAT::SvrUtils::sendmsg([1,"could not resolve '$server' to an address from vm.storage"]);
        #    return;
        #}
        #$server = inet_ntoa($servern);
        #my $uri = "nfs://$server/$path";
        $backingif = VirtualDiskFlatVer2BackingInfo->new(diskMode => 'persistent',
                                                          thinProvisioned => 1,
                                                           fileName => "[".$sdmap->{$uri}."]");
        if ($disktype eq 'ide' and $idecontrollerkey == 1 and $ideunitnum == 0) { #reserve a spot for CD
            $ideunitnum = 1;
        } elsif ($disktype eq 'ide' and $ideunitnum == 2) { #go from current to next ide 'controller'
            $idecontrollerkey++;
            $ideunitnum=0;
        }
        unless ($disktype eq 'ide') {
            push @{$disktocont{$scsicontrollerkey}},$currkey;
        }
        my $controllerkey;
        if ($disktype eq 'ide') {
            $controllerkey = $idecontrollerkey;
	    $unitnum = 0;
            while ($usedideunits{$unitnum}) {
              $unitnum++;
            }
			if ($unitnum == 2) {
				$idecontrollerkey++;
				$ideunitnum=1;
				$unitnum=1;
				$controllerkey=$idecontrollerkey;
			}
            $usedideunits{$unitnum}=1;
        } else {
			$controllertype=$disktype;
            $controllerkey = $scsicontrollerkey;
	    $unitnum = 0;
            while ($usedscsiunits{$unitnum}) {
              $unitnum++;
            }
            $usedscsiunits{$unitnum}=1;
            $havescsidevs=1;
        }

        $dev =VirtualDisk->new(backing=>$backingif,
                        controllerKey => $controllerkey,
                        key => $currkey++,
                        unitNumber => $unitnum,
                        capacityInKB => $disksize); 
        push @devs,VirtualDeviceConfigSpec->new(device => $dev,
                                                fileOperation => VirtualDeviceConfigSpecFileOperation->new('create'),
                                                operation =>  VirtualDeviceConfigSpecOperation->new('add'));
    }

    #It *seems* that IDE controllers are not subject to require creation, so we skip it
   if ($havescsidevs and not $havescsicontroller) { #need controllers to attach the disks to
       foreach(0..$scsicontrollerkey) {
	   	   if ($controllertype eq 'scsi') {
           $dev=VirtualLsiLogicController->new(key => $_,
                                               device => \@{$disktocont{$_}},
                                               sharedBus => VirtualSCSISharing->new('noSharing'),
                                               busNumber => $_);
		  } elsif ($controllertype eq 'sas') {
           $dev=VirtualLsiLogicSASController->new(key => $_,
                                               device => \@{$disktocont{$_}},
                                               sharedBus => VirtualSCSISharing->new('noSharing'),
                                               busNumber => $_);
		  } elsif ($controllertype eq 'pvscsi') {
           $dev=ParaVirtualSCSIController->new(key => $_,
                                               device => \@{$disktocont{$_}},
                                               sharedBus => VirtualSCSISharing->new('noSharing'),
                                               busNumber => $_);
		  }
		  	
           push @devs,VirtualDeviceConfigSpec->new(device => $dev,
                                               operation =>  VirtualDeviceConfigSpecOperation->new('add'));
                                                
       }
   }
    return  @devs;
#    my $ctlr = VirtualIDEController->new(
}

sub declare_ready {
    my %args = %{shift()};
    $hypready{$args{hyp}}=1;
}

sub populate_vcenter_hostviews {
    my $vcenter = shift;
    my @hypervisors;
    my %nametohypmap;
    my $iterations=1;
    if ($usehostnamesforvcenter and $usehostnamesforvcenter !~ /no/i) {
        $iterations=2; #two passes possible
        my $hyp;
        foreach $hyp (keys %{$vcenterhash{$vcenter}->{allhyps}}) {

            if ($tablecfg{hosts}->{$hyp}->[0]->{hostnames}) {
                $nametohypmap{$tablecfg{hosts}->{$hyp}->[0]->{hostnames}}=$hyp;
            }
        }
        @hypervisors = keys %nametohypmap;
    } else {
        @hypervisors = keys %{$vcenterhash{$vcenter}->{allhyps}};
    }
    while ($iterations and scalar(@hypervisors)) {
        my $hosts = join(")|(",@hypervisors);
        $hosts = '^(('.$hosts.'))(\z|\.)';
        my $search = qr/$hosts/;
        my @hypviews = @{$vcenterhash{$vcenter}->{conn}->find_entity_views(view_type=>'HostSystem',properties=>['summary.config.name','summary.runtime.connectionState','runtime.inMaintenanceMode','parent','configManager','summary.host'],filter=>{'summary.config.name'=>$search})};
        foreach (@hypviews) {
            my $hypname = $_->{'summary.config.name'};
	    my $hypv=$_;
	    my $hyp;
            if ($vcenterhash{$vcenter}->{allhyps}->{$hypname}) { #simplest case, config.name is exactly the same as node name
                $vcenterhash{$vcenter}->{hostviews}->{$hypname} = $_;
		$hyp=$hypname;
            } elsif ($nametohypmap{$hypname}) { #second case, there is a name mapping this to a real name
                $vcenterhash{$vcenter}->{hostviews}->{$nametohypmap{$hypname}} = $_;
		$hyp=$nametohypmap{$hypname};
            } else { #name as-is doesn't work, start stripping domain and hope for the best
                $hypname =~ s/\..*//;
                if ($vcenterhash{$vcenter}->{allhyps}->{$hypname}) { #shortname is a node
                    $vcenterhash{$vcenter}->{hostviews}->{$hypname} = $_;
		    $hyp=$hypname;
                } elsif ($nametohypmap{$hypname}) { #alias for node
                    $vcenterhash{$vcenter}->{hostviews}->{$nametohypmap{$hypname}} = $_;
		    $hyp=$nametohypmap{$hypname};
                }
            }
	    foreach my $nodename (keys %{$hyphash{$hyp}->{nodes}}) {
	    	$hostrefbynode{$nodename}=$hypv->{'summary.host'}->value;
	    }
        }
        $iterations--;
        @hypervisors=();
        if ($usehostnamesforvcenter and $usehostnamesforvcenter !~ /no/i) { #check for hypervisors by native node name if missed above
            foreach my $hyp (keys %{$vcenterhash{$vcenter}->{allhyps}}) {
                unless ($vcenterhash{$vcenter}->{hostviews}->{$hyp}) {
                    push @hypervisors,$hyp;
                }
            }
        }
    }
}

sub create_new_cluster {
  my $req = shift;
  @ARGV = @{$req->{arg}};
  my $vcenter;
  my $password;
  my $user;
  my $datacenter;
  GetOptions(
		'vcenter=s' => \$vcenter,
        'password=s' => \$password,
        'datacenter=s' => \$datacenter,
        'username=s' => \$user,
    );
  my $clustername = shift @ARGV;
  my $conn = Vim->new(service_url=>"https://$vcenter/sdk");
  $conn->login(user_name=>$user, password=>$password);
    if ($datacenter) {
        $datacenter = $conn->find_entity_view(view_type => 'Datacenter', properties=>['hostFolder'],filter=>{name=>$datacenter});
        unless ($datacenter) {
            xCAT::SvrUtils::sendmsg([1,": Unable to find requested datacenter"], $output_handler);
            return;
        }
    } else {
        $datacenter = $conn->find_entity_view(view_type => 'Datacenter', properties=>['hostFolder']);
    }
    my $hfolder =  $conn->get_view(mo_ref=>$datacenter->hostFolder);
    my $cfgspec = ClusterConfigSpecEx->new();
    $hfolder->CreateClusterEx(name=>$clustername, spec=>$cfgspec);
}
sub remove_cluster {
  my $req = shift;
  @ARGV = @{$req->{arg}};
  my $vcenter;
  my $user;
  my $password;
  my $clustername;
  GetOptions(
		'vcenter=s' => \$vcenter,
        'password=s' => \$password,
        'username=s' => \$user,
    );
    $clustername = shift @ARGV;
  my $conn = Vim->new(service_url=>"https://$vcenter/sdk");
  $conn->login(user_name=>$user, password=>$password);
#  $clustview = $hyphash{$hyp}->{vcenter}->{conn}->find_entity_view(view_type => 'Datacenter', properties=>['hostFolder'],filter=>{name=>$tablecfg{hypervisor}->{$hyp}->[0]->{datacenter}});
  #my $conn = Vim->new(service_url=>"https://$vcenter/sdk");
  $conn->login(user_name=>$user, password=>$password);
  my $clustview = $conn->find_entity_view(view_type=> 'ClusterComputeResource', filter=>{name=>$clustername});
  my $task = $clustview->Destroy_Task();
  my $done = 0;
  while (not $done) {
      my $curt = $conn->get_view(mo_ref=>$task);
      my $state = $curt->info->state->val;
      unless ($state eq 'running' or $state eq 'queued') {
        $done = 1;
      }
   }
}


sub list_clusters {
  my $req = shift;
  @ARGV = @{$req->{arg}};
  my $vcenter;
  my $password;
  my $user;
  my $datacenter;
  GetOptions(
		'vcenter=s' => \$vcenter,
        'password=s' => \$password,
        'datacenter=s' => \$datacenter,
        'username=s' => \$user,
    );
  my $clustername = shift @ARGV;
  my $conn = Vim->new(service_url=>"https://$vcenter/sdk");
  $conn->login(user_name=>$user, password=>$password);
  use Data::Dumper;
  my $clustviews = $conn->find_entity_views(view_type=> 'ClusterComputeResource');
  foreach (@$clustviews) {
            xCAT::SvrUtils::sendmsg($_->{name}, $output_handler);
  }
  return;
}

sub validate_vcenter_prereqs { #Communicate with vCenter and ensure this host is added correctly to a vCenter instance when an operation requires it
    my $hyp = shift;
    my $depfun = shift;
    my $depargs = shift;
    my $vcenter = $hyphash{$hyp}->{vcenter}->{name};
    unless ($hyphash{$hyp}->{vcenter}->{conn}) {
        eval {
           $hyphash{$hyp}->{vcenter}->{conn} = Vim->new(service_url=>"https://$vcenter/sdk");
           $hyphash{$hyp}->{vcenter}->{conn}->login(user_name=>$hyphash{$hyp}->{vcenter}->{username},password=>$hyphash{$hyp}->{vcenter}->{password});
        };
        if ($@) {
          $hyphash{$hyp}->{vcenter}->{conn} = undef;
        }
    }
    unless ($hyphash{$hyp}->{vcenter}->{conn}) {
        xCAT::SvrUtils::sendmsg([1,": Unable to reach vCenter server managing $hyp"], $output_handler);
        return undef;
    }


    my $foundhyp;
    my $name=$hyp;
    if ($usehostnamesforvcenter and $usehostnamesforvcenter !~ /no/i) {
        if ($tablecfg{hosts}->{$hyp}->[0]->{hostnames}) {
            $name = $tablecfg{hosts}->{$hyp}->[0]->{hostnames};
        }
    }
    my $connspec = HostConnectSpec->new(
        hostName=>$name,
        password=>$hyphash{$hyp}->{password},
        userName=>$hyphash{$hyp}->{username},
        force=>1,
        );
    my $hview;
    $hview = $vcenterhash{$vcenter}->{hostviews}->{$hyp};
    if ($hview) { 
        if ($hview->{'summary.config.name'} =~ /^$hyp(?:\.|\z)/ or $hview->{'summary.config.name'} =~ /^$name(?:\.|\z)/) { #Looks good, call the dependent function after declaring the state of vcenter to hypervisor as good
            if ($hview->{'summary.runtime.connectionState'}->val eq 'connected') {
                if ($vcenterautojoin) { #admin has requested manual vcenter management, don't mess with vmotion settings
                    enable_vmotion(hypname=>$hyp,hostview=>$hview,conn=>$hyphash{$hyp}->{vcenter}->{conn});
                }
                $vcenterhash{$vcenter}->{goodhyps}->{$hyp} = 1;
                $depfun->($depargs);
                if ($hview->parent->type eq 'ClusterComputeResource') { #if it is in a cluster, we can directly remove it
                    $hyphash{$hyp}->{deletionref} = $hview->{mo_ref}; 
                } elsif ($hview->parent->type eq 'ComputeResource') { #For some reason, we must delete the container instead
                    $hyphash{$hyp}->{deletionref} = $hview->{parent}; #save off a reference to delete hostview off just in case
                }


                return 1;
            } elsif ($vcenterautojoin or $vcenterforceremove) { #if allowed autojoin and the current view seems corrupt, throw it away and rejoin
                my $ref_to_delete;
                if ($hview->parent->type eq 'ClusterComputeResource') { #We are allowed to specifically kill a host in a cluster
                    $ref_to_delete = $hview->{mo_ref};
                } elsif ($hview->parent->type eq 'ComputeResource') { #For some reason, we must delete the container instead
                    $ref_to_delete = $hview->{parent};
                }
                my $task = $hyphash{$hyp}->{vcenter}->{conn}->get_view(mo_ref=>$ref_to_delete)->Destroy_Task();
                $running_tasks{$task}->{task} = $task;
		if ($vcenterautojoin) {
               	    $running_tasks{$task}->{callback} = \&addhosttovcenter;
		} elsif ($vcenterforceremove) {
                    $running_tasks{$task}->{callback} = \&delhost_callback;
                }
                $running_tasks{$task}->{conn} = $hyphash{$hyp}->{vcenter}->{conn};
                $running_tasks{$task}->{data} = { depfun => $depfun, depargs => $depargs, conn=>  $hyphash{$hyp}->{vcenter}->{conn}, connspec=>$connspec,hostview=>$hview,hypname=>$hyp,vcenter=>$vcenter };
                return undef;
#The rest would be shorter/ideal, but seems to be confused a lot by stateless
#Maybe in a future VMWare technology level the following would work better
#than it does today
#               my $task = $hview_->ReconnectHost_Task(cnxSpec=>$connspec);
#               my $task = $hview->DisconnectHost_Task();
#               $running_tasks{$task}->{task} = $task;
#               $running_tasks{$task}->{callback} = \&disconnecthost_callback;
#               $running_tasks{$task}->{conn} = $hyphash{$hyp}->{vcenter}->{conn};
#               $running_tasks{$task}->{data} = { depfun => $depfun, depargs => $depargs, conn=>  $hyphash{$hyp}->{vcenter}->{conn}, connspec=>$connspec,hostview=>$hview,hypname=>$hyp,vcenter=>$vcenter };
#ADDHOST
            } else {
				if ($hyphash{$hyp}->{offline}) {
            	xCAT::SvrUtils::sendmsg(": Failed to communicate with $hyp, vCenter reports it as in inventory but not connected and xCAT is set to not autojoin", $output_handler);
				} else {
            	xCAT::SvrUtils::sendmsg([1,": Failed to communicate with $hyp, vCenter reports it as in inventory but not connected and xCAT is set to not autojoin"], $output_handler);
				}
                    $hyphash{$hyp}->{conn} = undef;
                    return "failed";
            }
        }
    }
    unless ($vcenterautojoin) {
				if ($hyphash{$hyp}->{offline}) {
            		xCAT::SvrUtils::sendmsg(": Failed to communicate with $hyp, vCenter does not have it in inventory and xCAT is set to not autojoin", $output_handler);
				} else {
            		xCAT::SvrUtils::sendmsg([1,": Failed to communicate with $hyp, vCenter does not have it in inventory and xCAT is set to not autojoin"], $output_handler);
				}
                    $hyphash{$hyp}->{conn} = undef;
                    return "failed";
    }
    #If still in function, haven't found any likely host entries, make a new one
    unless ($hyphash{$hyp}->{offline}) {
        eval {
            $hyphash{$hyp}->{conn} = Vim->new(service_url=>"https://$hyp/sdk"); #Direct connect to install/check licenses
        	$hyphash{$hyp}->{conn}->login(user_name=>$hyphash{$hyp}->{username},password=>$hyphash{$hyp}->{password});
        };
        if ($@) {
    		xCAT::SvrUtils::sendmsg([1,": Failed to communicate with $hyp due to $@"], $output_handler);
                     $hyphash{$hyp}->{conn} = undef;
                    return "failed";
        }
        validate_licenses($hyp);
    }
    addhosttovcenter(undef,{
        depfun => $depfun,
        depargs => $depargs,
        conn=>$hyphash{$hyp}->{vcenter}->{conn},
        connspec=>$connspec,
        hypname=>$hyp,
        vcenter=>$vcenter,
    });
}
sub  addhosttovcenter {
    my $task = shift;
    my $args = shift;
    my $hyp = $args->{hypname};
    my $depfun = $args->{depfun};
    my $depargs = $args->{depargs};
    my $connspec = $args->{connspec};
    my $vcenter = $args->{vcenter};
    if ($task) { 
        my $state = $task->info->state->val;
        if ($state eq 'error') {
            die;
        }
    }
    if ($hyphash{$args->{hypname}}->{offline}) { #let it stay offline
        $hypready{$args->{hypname}}=1; #declare readiness
        #enable_vmotion(hypname=>$args->{hypname},hostview=>$args->{hostview},conn=>$args->{conn});
        $vcenterhash{$args->{vcenter}}->{goodhyps}->{$args->{hypname}} = 1;
        if (defined $args->{depfun}) { #If a function is waiting for the host connect to go valid, call it
            $args->{depfun}->($args->{depargs});
        }
        return;
    }
    if ($tablecfg{hypervisor}->{$hyp}->[0]->{cluster}) {
        my $cluster = get_clusterview(clustname=>$tablecfg{hypervisor}->{$hyp}->[0]->{cluster},conn=>$hyphash{$hyp}->{vcenter}->{conn});
        unless ($cluster) {
            xCAT::SvrUtils::sendmsg([1,$tablecfg{hypervisor}->{$hyp}->[0]->{cluster}. " is not a known cluster to the vCenter server."], $output_handler);
            $hypready{$hyp}=-1; #Declare impossiblility to be ready
            return;
        }
        $task = $cluster->AddHost_Task(spec=>$connspec,asConnected=>1);
        $running_tasks{$task}->{task} = $task;
        $running_tasks{$task}->{callback} = \&connecthost_callback;
        $running_tasks{$task}->{conn} = $hyphash{$hyp}->{vcenter}->{conn};
        $running_tasks{$task}->{data} = { depfun => $depfun, depargs=> $depargs, conn=>  $hyphash{$hyp}->{vcenter}->{conn}, connspec=>$connspec, cluster=>$cluster, hypname=>$hyp, vcenter=>$vcenter };
    } else {
        my $datacenter = validate_datacenter_prereqs($hyp);
        unless ($datacenter) { return; }
        my $hfolder =  $datacenter->hostFolder; #$hyphash{$hyp}->{vcenter}->{conn}->find_entity_view(view_type=>'Datacenter',properties=>['hostFolder'])->hostFolder;
        $hfolder = $hyphash{$hyp}->{vcenter}->{conn}->get_view(mo_ref=>$hfolder);
        $task = $hfolder->AddStandaloneHost_Task(spec=>$connspec,addConnected=>1);
        $running_tasks{$task}->{task} = $task;
        $running_tasks{$task}->{callback} = \&connecthost_callback;
        $running_tasks{$task}->{conn} = $hyphash{$hyp}->{vcenter}->{conn};
        $running_tasks{$task}->{data} = { depfun => $depfun, depargs=> $depargs, conn=>  $hyphash{$hyp}->{vcenter}->{conn}, connspec=>$connspec, foldview=>$hfolder, hypname=>$hyp, vcenter=>$vcenter };
    }

    #print Dumper @{$hyphash{$hyp}->{vcenter}->{conn}->find_entity_views(view_type=>'HostSystem',properties=>['runtime.connectionState'])};
}

sub validate_datacenter_prereqs {
    my ($hyp) = @_;

    my $datacenter;
    if ($tablecfg{hypervisor}->{$hyp}->[0]->{datacenter}) {
        $datacenter = $hyphash{$hyp}->{vcenter}->{conn}->find_entity_view(view_type => 'Datacenter', properties=>['hostFolder'],filter=>{name=>$tablecfg{hypervisor}->{$hyp}->[0]->{datacenter}});
        unless ($datacenter) {
            xCAT::SvrUtils::sendmsg([1,": Unable to find requested datacenter (hypervisor.datacenter for $hyp is ".$tablecfg{hypervisor}->{$hyp}->[0]->{datacenter}.")"], $output_handler);
            return;
        }
    } else {
        $datacenter = $hyphash{$hyp}->{vcenter}->{conn}->find_entity_view(view_type => 'Datacenter', properties=>['hostFolder']);
    }

    if (!defined $datacenter) {
        my $vconn = $hyphash{$hyp}->{vcenter}->{conn};
        my $root_folder = $vconn->get_view(mo_ref=>$vconn->get_service_content()->rootFolder);
        $root_folder->CreateDatacenter(name=>'xcat-datacenter');
        $datacenter = $hyphash{$hyp}->{vcenter}->{conn}->find_entity_view(view_type => 'Datacenter', properties=>['hostFolder']);
    }

    return $datacenter;
}



sub  get_default_switch_for_hypervisor {
    #This will make sure the default, implicit switch is in order in accordance
#with the configuration.  If nothing specified, it just spits out vSwitch0
#if something specified, make sure it exists
#if it doesn't exist, and the syntax explains how to build it, build it
#return undef if something is specified, doesn't exist, and lacks instruction
    my $hyp = shift;
    my $defswitch = 'vSwitch0';
    my $switchmembers;
    if ($tablecfg{hypervisor}->{$hyp}->[0]->{defaultnet}) {
        $defswitch = $tablecfg{hypervisor}->{$hyp}->[0]->{defaultnet};
        ($defswitch,$switchmembers) = split /=/,$defswitch,2;
        my $vswitch;
        my $hostview = $hyphash{$hyp}->{hostview};
        foreach $vswitch (@{$hostview->config->network->vswitch}) {
            if ($vswitch->name eq $defswitch) {
                return $defswitch;
            }
        }
        #If still here, means we need to build the switch
        unless ($switchmembers) { return undef; } #No hope, no idea how to make it
        return create_vswitch($hyp,$defswitch,split(/&/,$switchmembers));
    } else {
        return 'vSwitch0';
    }
}
sub get_switchname_for_portdesc {
#Thisk function will examine all current switches to find or create a switch to match the described requirement
    my $hyp = shift;
    my $portdesc = shift;
    my $description; #actual name to use for the virtual switch
    if ($tablecfg{hypervisor}->{$hyp}->[0]->{netmap}) {
        foreach (split /,/,$tablecfg{hypervisor}->{$hyp}->[0]->{netmap}) {
            if (/^$portdesc=/) {
                ($description,$portdesc) = split /=/,$_,2;
                last;
            }
        }
    } else {
        $description = 'vsw'.$portdesc;
    }
    unless ($description) {
        xCAT::SvrUtils::sendmsg([1,": Invalid format for hypervisor.netmap detected for $hyp"], $output_handler);
        return undef;
    }
    my %requiredports;
    my %portkeys;
    foreach (split /&/,$portdesc) {
        $requiredports{$_}=1;
    }

    my $hostview = $hyphash{$hyp}->{hostview};
    unless ($hostview) {
        $hyphash{$hyp}->{hostview} = get_hostview(hypname=>$hyp,conn=>$hyphash{$hyp}->{conn}); #,properties=>['config','configManager']);  #clustered can't run here, hyphash conn reference good
        $hostview = $hyphash{$hyp}->{hostview};
    }
    foreach (@{$hostview->config->network->pnic}) {
        if ($requiredports{$_->device}) { #We establish lookups both ways
            $portkeys{$_->key}=$_->device;
            delete $requiredports{$_->device};
        }
    }
    if (keys %requiredports) {
        xCAT::SvrUtils::sendmsg([1,":Unable to locate the following nics on $hyp: ".join(',',keys %requiredports)], $output_handler);
        return undef;
    }
    my $foundmatchswitch;
    my $cfgmismatch=0;
    my $vswitch;
    foreach $vswitch (@{$hostview->config->network->vswitch}) {
        $cfgmismatch=0; #new switch, no sign of mismatch
        foreach (@{$vswitch->pnic}) {
            if ($portkeys{$_}) {
                $foundmatchswitch=$vswitch->name;
                delete $requiredports{$portkeys{$_}};
                delete $portkeys{$_};
            } else {
                $cfgmismatch=1; #If this turns out to have anything, it is bad
            }
        }
        if ($foundmatchswitch) { last; }
    }
    if ($foundmatchswitch) {
        if ($cfgmismatch) {
            xCAT::SvrUtils::sendmsg([1,": Aggregation mismatch detected, request nic is aggregated with a nic not requested"], $output_handler);
            return undef;
        }
        unless (keys %portkeys) {
            return $foundmatchswitch;
        }
        die "TODO: add physical nics to aggregation if requested";
    } else {
        return create_vswitch($hyp,$description,values %portkeys);
    }
    die "impossible occurance";
    return undef;
}
sub create_vswitch {
    my $hyp = shift;
    my $description = shift;
    my @ports = @_;
    my $vswitch = HostVirtualSwitchBondBridge->new(
        nicDevice=>\@ports
        );
    my $vswspec = HostVirtualSwitchSpec->new(
        bridge=>$vswitch,
        mtu=>1500,
        numPorts=>64
    );
    my $hostview = $hyphash{$hyp}->{hostview};
    my $netman=$hyphash{$hyp}->{conn}->get_view(mo_ref=>$hostview->configManager->networkSystem); #can't run in clustered mode, fine path..
    $netman->AddVirtualSwitch(
        vswitchName=>$description,
        spec=>$vswspec
    );
    return $description;
}

sub scan_cluster_networks {
    my $cluster = shift;
    use Data::Dumper;
    my $conn = $clusterhash{$cluster}->{conn};
    my $cview = get_clusterview(clustname=>$cluster,conn=>$conn);
    if (defined $cview->{network}) {
        foreach (@{$cview->network}) {
            my $nvw = $conn->get_view(mo_ref=>$_);
            if (defined $nvw->name) {
                $clusterhash{$cluster}->{nets}->{$nvw->name}=$_;
            }
        }
    }
}

sub fixup_hostportgroup {
    my $vlanspec = shift;
    my $hyp = shift;
    my %args = @_;
    my $action = 'add';
    if ($args{action}) { $action = $args{action} }
    my $hostview = $hyphash{$hyp}->{hostview};
    my $switchsupport = 0;
    eval {
        require xCAT::SwitchHandler;
        $switchsupport = 1;
    };
    my $hypconn = $hyphash{$hyp}->{conn}; #this function can't work in clustered mode anyway, so this is appropriote.
    my $vldata = $vlanspec;
    my $switchname = get_default_switch_for_hypervisor($hyp);
    my $pgname;
    $vldata =~ s/=.*//; #TODO specify nic model with <blah>=model
    if ($vldata =~ /:/) { #The config specifies a particular path in some way
        $vldata =~ s/(.*)://;
        $switchname = get_switchname_for_portdesc($hyp,$1);
        $pgname=$switchname."-".$vldata;
    } else { #Use the default vswitch per table config to connect this through, use the same name we did before to maintain compatibility
        $pgname=$vldata;
    }
    my $netsys;
    $hyphash{$hyp}->{pgnames}->{$vlanspec}=$pgname;
    my $policy = HostNetworkPolicy->new();
    unless ($hyphash{$hyp}->{nets}->{$pgname}) {
        my $vlanid;
        if (looks_like_number($vldata)) {
            $vlanid = $vldata;
        } elsif ($vldata =~ /trunk/) {
            $vlanid=4095;
        } elsif ($vldata =~ /vl(an)?(\d+)$/) {
            $vlanid=$2;
        } else {
            $vlanid = 0;
        }
        if ($vlanid > 0 and $vlanid < 4095 and $switchsupport) {
            my $switchtab = xCAT::Table->new("switch", -create=>0);
            if ($switchtab) {
                my $swent = $switchtab->getNodeAttribs($hyp, [qw/switch port/]);
                if ($swent and $swent->{'switch'}) {
                    my $swh = new xCAT::SwitchHandler->new($swent->{'switch'});
                    my @vlids = $swh->get_vlan_ids();
                    if ($action eq 'add') {
                        unless (grep {$_ eq $vlanid} @vlids) {
                            $swh->create_vlan($vlanid);
                        }
                        $swh->add_ports_to_vlan($vlanid, $swent->{'port'});
                    } elsif ($action eq 'remove') {
                        $swh->remove_ports_from_vlan($vlanid, $swent->{'port'});
                    }
                }
            }
        }
        my $hostgroupdef = HostPortGroupSpec->new(
            name =>$pgname,
            vlanId=>$vlanid,
            policy=>$policy,
            vswitchName=>$switchname
            );
        unless ($netsys) {
            $netsys = $hyphash{$hyp}->{conn}->get_view(mo_ref=>$hostview->configManager->networkSystem);
        }
        if ($action eq 'remove') {
            $netsys->RemovePortGroup(pgName=>$pgname);
            return;
        } elsif ($action eq 'add') {
            $netsys->AddPortGroup(portgrp=>$hostgroupdef);
        }
        #$hyphash{$hyp}->{nets}->{$netname}=1;
        while ((not defined $hyphash{$hyp}->{nets}->{$pgname}) and sleep 1) { #we will only sleep if we know something will be waiting for
            $hostview->update_view_data(); #pull in changes induced by previous activity
            if (defined $hostview->{network}) { #We load the new object references
                foreach (@{$hostview->network}) {
                    my $nvw = $hypconn->get_view(mo_ref=>$_);
                    if (defined $nvw->name) {
                        $hyphash{$hyp}->{nets}->{$nvw->name}=$_;
                    }
                }
            }
        }
    }
}

sub validate_network_prereqs {
    my $nodes = shift;
    my $hyp  = shift;
    my $hypconn = $hyphash{$hyp}->{conn}; #this function can't work in clustered mode anyway, so this is appropriote.
    my $hostview = $hyphash{$hyp}->{hostview};
    if ($hostview) {
        $hostview->update_view_data(); #pull in changes induced by previous activity
    } else {
        $hyphash{$hyp}->{hostview} = get_hostview(hypname=>$hyp,conn=>$hyphash{$hyp}->{conn}); #,properties=>['config','configManager','network']); 
        $hostview = $hyphash{$hyp}->{hostview};
    }
    my $node;
    my $method;
    my $location;
    if (defined $hostview->{network}) {
        foreach (@{$hostview->network}) {
            my $nvw = $hypconn->get_view(mo_ref=>$_);
            if (defined $nvw->name) {
                $hyphash{$hyp}->{nets}->{$nvw->name}=$_;
            }
        }
    }
    foreach $node (@$nodes) {
        my @networks = split /,/,$tablecfg{vm}->{$node}->[0]->{nics};
        foreach (@networks) {
            fixup_hostportgroup($_, $hyp);
        }
    }
    return 1;

}
sub refreshclusterdatastoremap {
    my $cluster = shift;
    my $conn=$clusterhash{$cluster}->{conn};
    my $cview = get_clusterview(clustname=>$cluster,conn=>$conn);
    if (defined $cview->{datastore}) {
        foreach (@{$cview->datastore}) {
             my $dsv = $conn->get_view(mo_ref=>$_);
             if (defined $dsv->info->{nas}) {
                 if ($dsv->info->nas->type eq 'NFS') {
                     my $mnthost = $dsv->info->nas->remoteHost;
             #        my $mnthost = inet_aton($dsv->info->nas->remoteHost);
             #        if ($mnthost) {
             #            $mnthost = inet_ntoa($mnthost);
             #        } else {
             #            $mnthost = $dsv->info->nas->remoteHost;
             #            xCAT::SvrUtils::sendmsg([1,"Unable to resolve VMware specified host '".$dsv->info->nas->remoteHost."' to an address, problems may occur"], $output_handler);
             #        }
                     $clusterhash{$cluster}->{datastoremap}->{"nfs://".$mnthost.$dsv->info->nas->remotePath}=$dsv->info->name;
                     $clusterhash{$cluster}->{datastoreurlmap}->{$dsv->info->name} = "nfs://".$mnthost.$dsv->info->nas->remotePath; #save off a suitable URL if needed
                     $clusterhash{$cluster}->{datastorerefmap}->{"nfs://".$mnthost.$dsv->info->nas->remotePath}=$_;
                } #TODO: care about SMB
            }elsif(defined $dsv->info->{vmfs}){
                my $name = $dsv->info->vmfs->name;
                $clusterhash{$cluster}->{datastoremap}->{"vmfs://".$name} = $dsv->info->name;     
				$clusterhash{$cluster}->{datastoreurlmap}->{$dsv->info->name} = "vmfs://".$name;
                $clusterhash{$cluster}->{datastorerefmap}->{"vmfs://".$name} = $_;
            }
        }
    }
    #that's... about it... not doing any of the fancy mounting and stuff, if you do it cluster style, you are on your own.  It's simply too terrifying to try to fixup
    #a whole cluster instead of chasing one host, a whole lot slower.  One would hope vmware would've done this, but they don't
}
sub validate_datastore_prereqs {
	my $hyp = $_[1];
	lockbyname($hyp.".datastores");
	$@="";
	my $rc;
	eval { $rc=validate_datastore_prereqs_inlock(@_); };
	unlockbyname($hyp.".datastores");
	if ($@) { die $@; }
	return $rc;
}
sub validate_datastore_prereqs_inlock {
    my $nodes = shift;
    my $hyp = shift;
    my $newdatastores = shift; # a hash reference of URLs to afflicted nodes outside of table space
    my $hypconn = $hyphash{$hyp}->{conn};
    my $hostview = $hyphash{$hyp}->{hostview};
    unless ($hostview) {
        $hyphash{$hyp}->{hostview} = get_hostview(hypname=>$hyp,conn=>$hypconn); #,properties=>['config','configManager']);
        $hostview = $hyphash{$hyp}->{hostview};
    }
    my $node;
    my $method;
    my $location;
    # get all of the datastores that are currently available on this node.
    # and put them into a hash
    if (defined $hostview->{datastore}) { # only iterate if it exists
        foreach (@{$hostview->datastore}) {
            my $dsv = $hypconn->get_view(mo_ref=>$_);
            if (defined $dsv->info->{nas}) {
                if ($dsv->info->nas->type eq 'NFS') {
                    my $mnthost = inet_aton($dsv->info->nas->remoteHost);
                    if ($mnthost) {
                     $mnthost = inet_ntoa($mnthost);
                    } else {
                        $mnthost = $dsv->info->nas->remoteHost;
                        xCAT::SvrUtils::sendmsg([1,"Unable to resolve VMware specified host '".$dsv->info->nas->remoteHost."' to an address, problems may occur"], $output_handler);
                    }
                    $hyphash{$hyp}->{datastoremap}->{"nfs://".$mnthost.$dsv->info->nas->remotePath}=$dsv->info->name;
                    $hyphash{$hyp}->{datastoreurlmap}->{$dsv->info->name} = "nfs://".$mnthost.$dsv->info->nas->remotePath;
                    $hyphash{$hyp}->{datastorerefmap}->{"nfs://".$mnthost.$dsv->info->nas->remotePath}=$_;
                } #TODO: care about SMB
            }elsif(defined $dsv->info->{vmfs}){
                my $name = $dsv->info->vmfs->name;
                $hyphash{$hyp}->{datastoremap}->{"vmfs://".$name} = $dsv->info->name;     
                $hyphash{$hyp}->{datastoreurlmap}->{$dsv->info->name} = "vmfs://".$name;
                $hyphash{$hyp}->{datastorerefmap}->{"vmfs://".$name} = $_;
            }
        }
    }
    my $refresh_names=0;
    # now go through the nodes and make sure that we have matching datastores.
    # E.g.: if its NFS, then mount it (if not mounted)
    # E.g.: if its VMFS, then create it if not created already.  Note:  VMFS will persist on 
    # machine reboots, unless its destroyed by being overwritten.
    foreach $node (@$nodes) {
        my @storage = split /,/,$tablecfg{vm}->{$node}->[0]->{storage};
        if ($tablecfg{vm}->{$node}->[0]->{cfgstore}) {
            push @storage,$tablecfg{vm}->{$node}->[0]->{cfgstore};
        }
        foreach (@storage) { #TODO: merge this with foreach loop below.  Here we could build onto $newdatastores instead, for faster operation at scale
            s/=.*//; #remove device type information from configuration
            s/\/$//; #Strip trailing slash if specified, to align to VMware semantics
            if (/:\/\//) {
                ($method,$location) = split /:\/\//,$_,2;
                if($method =~ /nfs/){
                # go through and see if NFS is mounted, if not, then mount it.
                    (my $server, my $path) = split /\//,$location,2;
                    $server =~ s/:$//; #remove a : if someone put it in out of nfs mount habit
                    my $servern = inet_aton($server);
                    unless ($servern) {
                        xCAT::SvrUtils::sendmsg([1,": Unable to resolve '$server' to an address, check vm.cfgstore/vm.storage"], $output_handler);
                        return 0;
                    }
                    $server = inet_ntoa($servern);
                    my $uri = "nfs://$server/$path";
                    unless ($hyphash{$hyp}->{datastoremap}->{$uri}) { #If not already there, must mount it
						unless ($datastoreautomount) {
                    		xCAT::SvrUtils::sendmsg([1,": $uri is not currently accessible at the given location and automount is disabled in site table"], $output_handler,$node);
							return 0;
						}
                        $refresh_names=1;
                        ($hyphash{$hyp}->{datastoremap}->{$uri},$hyphash{$hyp}->{datastorerefmap}->{$uri})=mount_nfs_datastore($hostview,$location);
						$hyphash{$hyp}->{datastoreurlmap}->{$hyphash{$hyp}->{datastoremap}->{$uri}} = $uri;
                    }
                }elsif($method =~ /vmfs/){
                    (my $name, undef) = split /\//,$location,2;
                    $name =~ s/:$//; #remove a : if someone put it in for some reason.  
                    my $uri = "vmfs://$name";
                    # check and see if this vmfs is on the node.
                    unless ($hyphash{$hyp}->{datastoremap}->{$uri}) { #If not already there, try creating it.
						unless ($datastoreautomount) {
                    		xCAT::SvrUtils::sendmsg([1,": $uri is not currently accessible at the given location and automount is disabled in site table"], $output_handler,$node);
							return 0;
						}
                        $refresh_names=1;
                        ($hyphash{$hyp}->{datastoremap}->{$uri},$hyphash{$hyp}->{datastorerefmap}->{$uri})=create_vmfs_datastore($hostview,$name,$hyp);
                        unless($hyphash{hyp}->{datastoremap}->{$uri}){ return 0; }
						$hyphash{$hyp}->{datastoreurlmap}->{$hyphash{$hyp}->{datastoremap}->{$uri}} = $uri;
                    }
                }else{
                    xCAT::SvrUtils::sendmsg([1,": $method is unsupported at this time (nfs would be)"], $output_handler,$node);
                    return 0;
                }
            } else {
                xCAT::SvrUtils::sendmsg([1,": $_ not supported storage specification for ESX plugin,\n\t'nfs://<server>/<path>'\n\t\tor\n\t'vmfs://<vmfs>'\n only currently supported vm.storage supported for ESX at the moment"], $output_handler,$node);
                return 0;
            } #TODO: raw device mapping, VMFS via iSCSI, VMFS via FC?
        }
    }
    # newdatastores are for migrations or changing vms.  
    # TODO: make this work for VMFS.  Right now only NFS.
    if (ref $newdatastores) {
        foreach (keys %$newdatastores) {
            my $origurl=$_;
            s/\/$//; #Strip trailing slash if specified, to align to VMware semantics
            if (/:\/\//) {
                ($method,$location) = split /:\/\//,$_,2;
                if($method =~ /nfs/){
                    (my $server, my $path) = split /\//,$location,2;
               	    $server =~ s/:$//; #remove a : if someone put it in out of nfs mount habit
                    my $servern = inet_aton($server);
               	    unless ($servern) {
                        xCAT::SvrUtils::sendmsg([1,": Unable to resolve '$server' to an address, check vm.cfgstore/vm.storage"], $output_handler);
                        return 0;
                    }
                    $server = inet_ntoa($servern);
                    my $uri = "nfs://$server/$path";
                    unless ($method =~ /nfs/) {
                        foreach (@{$newdatastores->{$_}}) {
                            xCAT::SvrUtils::sendmsg([1,": $method is unsupported at this time (nfs would be)"], $output_handler,$_);
                        }
                        return 0;
                    }
                    unless ($hyphash{$hyp}->{datastoremap}->{$uri}) { #If not already there, must mount it
						unless ($datastoreautomount) {
                    		xCAT::SvrUtils::sendmsg([1,":) $uri is not currently accessible at the given location and automount is disabled in site table"], $output_handler,$node);
							return 0;
						}
                        $refresh_names=1;
                        ($hyphash{$hyp}->{datastoremap}->{$uri},$hyphash{$hyp}->{datastorerefmap}->{$uri})=mount_nfs_datastore($hostview,$location);
                    }
					$hyphash{$hyp}->{datastoreurlmap}->{$hyphash{$hyp}->{datastoremap}->{$uri}} = $uri;
                    $hyphash{$hyp}->{datastoremap}->{$origurl}=$hyphash{$hyp}->{datastoremap}->{$uri}; #we track both the uri xCAT expected and the one vCenter actually ended up with
                    $hyphash{$hyp}->{datastorerefmap}->{$origurl}=$hyphash{$hyp}->{datastorerefmap}->{$uri};
                }elsif($method =~ /vmfs/){
                    (my $name, undef) = split /\//,$location,2;
                    $name =~ s/:$//; #remove a : if someone put it in for some reason.  
                    my $uri = "vmfs://$name";
                    unless ($hyphash{$hyp}->{datastoremap}->{$uri}) { #If not already there, it should be!
						unless ($datastoreautomount) {
                    		xCAT::SvrUtils::sendmsg([1,": $uri is not currently accessible at the given location and automount is disabled in site table"], $output_handler,$node);
							return 0;
						}
                        $refresh_names=1;
                        ($hyphash{$hyp}->{datastoremap}->{$uri},$hyphash{$hyp}->{datastorerefmap}->{$uri})=create_vmfs_datastore($hostview,$name,$hyp);
                        unless($hyphash{hyp}->{datastoremap}->{$uri}){ return 0; }
                    }
					$hyphash{$hyp}->{datastoreurlmap}->{$hyphash{$hyp}->{datastoremap}->{$uri}} = $uri;
                    $hyphash{$hyp}->{datastoremap}->{$origurl}=$hyphash{$hyp}->{datastoremap}->{$uri};
                    $hyphash{$hyp}->{datastorerefmap}->{$origurl}=$hyphash{$hyp}->{datastorerefmap}->{$uri};
                }else{
                    print "$method: not NFS and not VMFS here!\n";
                }
            } else {
                my $datastore=$_;
                foreach my $ds (@{$newdatastores->{$_}}) {
                    xCAT::SvrUtils::sendmsg([1,": $datastore not supported storage specification for ESX plugin, 'nfs://<server>/<path>' only currently supported vm.storage supported for ESX at the moment"], $output_handler,$ds);
                }
                return 0;
            } #TODO: raw device mapping, VMFS via iSCSI, VMFS via FC, VMFS on same local drive?
        }
    }
    if ($refresh_names) { #if we are in a vcenter context, vmware can rename a datastore behind our backs immediately after adding
        $hostview->update_view_data();
        if (defined $hostview->{datastore}) { # only iterate if it exists
            foreach (@{$hostview->datastore}) {
                my $dsv = $hypconn->get_view(mo_ref=>$_);
                if (defined $dsv->info->{nas}) {
                    if ($dsv->info->nas->type eq 'NFS') {
                        my $mnthost = inet_aton($dsv->info->nas->remoteHost);
                        if ($mnthost) {
                         $mnthost = inet_ntoa($mnthost);
                        } else {
                            $mnthost = $dsv->info->nas->remoteHost;
                            xCAT::SvrUtils::sendmsg([1,"Unable to resolve VMware specified host '".$dsv->info->nas->remoteHost."' to an address, problems may occur"], $output_handler);
                        }
                        $hyphash{$hyp}->{datastoremap}->{"nfs://".$mnthost.$dsv->info->nas->remotePath}=$dsv->info->name;
					    $hyphash{$hyp}->{datastoreurlmap}->{$dsv->info->name} = "nfs://".$mnthost.$dsv->info->nas->remotePath;
                        $hyphash{$hyp}->{datastorerefmap}->{"nfs://".$mnthost.$dsv->info->nas->remotePath}=$_;
                    } #TODO: care about SMB
                } #TODO: care about VMFS
            }
        }
    }
    return 1;
}

sub getlabel_for_datastore {
    my $method = shift;
    my $location = shift;

    $location =~ s/\//_/g;
    $location= $method.'_'.$location;
    #VMware has a 42 character limit, we will start mangling to get under 42.
    #Will try to preserve as much informative detail as possible, hence several conditionals instead of taking the easy way out
    if (length($location) > 42) {
        $location =~ s/nfs_//; #Ditch unique names for different protocols to the same path, seems unbelievably unlikely
    }
    if (length($location) > 42) {
        $location =~ s/\.//g; #Next, ditch host delimiter, it is unlikely that hosts will have unique names if their dots are removed
    }
    if (length($location) > 42) {
        $location =~ s/_//g; #Next, ditch path delimiter, it is unlikely that two paths will happen to look the same without delimiters
    }
    if (length($location) > 42) { #finally, replace the middle with ellipsis
        substr($location,20,-20,'..');
    }
    return $location;
}

sub mount_nfs_datastore {
    my $hostview = shift;
    my $location = shift;
    my $server;
    my $path;
	unless ($datastoreautomount) {
		die "automount of VMware datastores is disabled in site configuration, not continuing";
	}
    ($server,$path) = split /\//,$location,2;
    $location = getlabel_for_datastore('nfs',$location);

    my $nds = HostNasVolumeSpec->new(accessMode=>'readWrite',
                                    remoteHost=>$server,
                                    localPath=>$location,
                                    remotePath=>"/".$path);
    my $dsmv = $hostview->{vim}->get_view(mo_ref=>$hostview->configManager->datastoreSystem);

    my $dsref;
    eval {
      $dsref=$dsmv->CreateNasDatastore(spec=>$nds);
    };

    if ($@) {
      die "$@" unless $@ =~ m/Fault detail: DuplicateNameFault/;

      die "esx plugin: a datastore was discovered with the same name referring to a different nominatum- cannot continue\n$@"
        unless &match_nfs_datastore($server,"/$path",$hostview->{vim});
    }

    return ($location,$dsref);
}

# create a VMFS data store on a node so that VMs can live locally instead of NFS
sub create_vmfs_datastore {
    my $hostview = shift; # VM object
    my $name = shift; # name of storage we wish to create.
    my $hyp = shift;
	unless ($datastoreautomount) {
		die "automount of VMware datastores is disabled in site configuration, not continuing";
	}
    # call some VMware API here to create
    my $hdss = $hostview->{vim}->get_view(mo_ref=>$hostview->configManager->datastoreSystem);

    my $diskList = $hdss->QueryAvailableDisksForVmfs(); 
    my $count = scalar(@$diskList); # get the number of disks available for formatting.  
    unless($count >0){
        #die "No disks are available to create VMFS volume for $name";
        $output_handler->({error=>["No disks are available on $hyp to create VMFS volume for $name"],errorcode=>1});
	return 0;
    }
    foreach my $disk(@$diskList){
        my $options = $hdss->QueryVmfsDatastoreCreateOptions(devicePath => $disk->devicePath);
        @$options[0]->spec->vmfs->volumeName($name);
        my $newDatastore = $hdss->CreateVmfsDatastore(spec => @$options[0]->spec );
        #return $newDatastore; 
        # create it on the first disk we see.  
        return ($name, $newDatastore);
    }
    return 0;
}



sub build_more_info{
  die("TODO: fix this function if called");
  print "Does this acually get called????**********************************\n";
  my $noderange=shift;
  my $callback=shift;
  my $vmtab = xCAT::Table->new("vm");
  my @moreinfo=();
  unless ($vmtab) {
    $callback->({data=>["Cannot open mp table"]});
    return @moreinfo;
  }
  my %mpa_hash=();
  foreach my $node (@$noderange) {
    my $ent=$vmtab->getNodeAttribs($node,['mpa', 'id']);
    if (defined($ent->{mpa})) { push @{$mpa_hash{$ent->{mpa}}{nodes}}, $node;}
    else {
      $callback->({data=>["no mpa defined for node $node"]});
      return @moreinfo;
    }
    if (defined($ent->{id})) { push @{$mpa_hash{$ent->{mpa}}{ids}}, $ent->{id};}
    else { push @{$mpa_hash{$ent->{mpa}}{ids}}, "";}
  }

  foreach (keys %mpa_hash) {
    push @moreinfo, "\[$_\]\[" . join(',',@{$mpa_hash{$_}{nodes}}) ."\]\[" . join(',',@{$mpa_hash{$_}{ids}}) . "\]";

  }

  return \@moreinfo;
}

sub copycd {
	my $request  = shift;
	my $doreq    = shift;
	my $distname = "";
    my $path;
    my $arch;
    my $darch;
	my $installroot;
	$installroot = "/install";
	#my $sitetab = xCAT::Table->new('site');
	#if($sitetab){
		#(my $ref) = $sitetab->getAttribs({key => 'installdir'}, 'value');
                my @entries =  xCAT::TableUtils->get_site_attribute("installdir");
                my $t_entry = $entries[0];
		if ( defined($t_entry) ) {
			$installroot = $t_entry;
		}
	#}
	@ARGV = @{$request->{arg}};
    my $includeupdate = 0;
	GetOptions(
		'n=s' => \$distname,
		'a=s' => \$arch,
		'm=s' => \$path,
        's' => \$includeupdate
	);
	# run a few tests to see if the copycds should use this plugin
	unless ($path){
		# can't use us cause we need a path and you didn't provide one!
		return;
	}
	if( $distname and $distname !~ /^esx/  ){
		# we're for esx, so if you didn't specify that its not us!
		return;
	}
    my $found = 0;

    if (-r $path . "/README" and -r $path . "/build_number" and -d $path . "/VMware" and -r $path . "/packages.xml") { #We have a probable new style ESX media
        open(LINE,$path."/packages.xml");
        my $product;
        my $version;
        while (<LINE>) {
            if (/roductLineId>([^<]*)<\/Prod/) {
                $product = $1;
            }
            if (/ersion>([^<]*)<\/version/) {
                $version = $1;
                $version =~ s/\.0$//;
            }
            if (/arch>([^>]*)<\/arch/) {
                unless ($darch and $darch =~ /x86_64/) {  #prefer to be characterized as x86_64
                    $darch = $1;
                    $arch = $1;
                }

            }
        }
        close(LINE);
        if ($product and $version) {
            unless ($distname) { $distname = $product.$version; }
            $found = 1;
        }
    } elsif (-r $path . "/README" and -r $path . "/open_source_licenses.txt" and -d $path . "/VMware") { #Candidate to be ESX 3.5
        open(LINE,$path."/README");
        while(<LINE>) {
            if (/VMware ESX Server 3.5\s*$/) {
                $darch ='x86';
                $arch = 'x86';
                unless ($distname) { $distname = 'esx3.5'; }
                $found = 1;
                last;
            }
        }
        close(LINE);
    } elsif (-r $path . "/README.txt" and -r $path . "/vmkernel.gz"){
		# its an esxi dvd!
        # if we got here its probably ESX they want to copy
        my $line;
        my $darch;
        open(LINE, $path . "/README.txt") or die "couldn't open!";
        while($line = <LINE>){
            chomp($line);
            if($line =~ /VMware ESXi(?: version)? 4\.(\d+)/){
                $darch = "x86_64";
				unless ($distname) { 
                $distname = "esxi4";
                if ($1) {
                    $distname .= '.'.$1;
                }
                }
                $found = 1;
                if( $arch and $arch ne $darch){
                    xCAT::SvrUtils::sendmsg([1, "Requested distribution architecture $arch, but media is $darch"], $output_handler);
                    return;
                }	
                $arch = $darch;
                last;	 # we found our distro!  end this loop madness.
            }
        }
        close(LINE);
        unless($found){
            xCAT::SvrUtils::sendmsg([1,"I don't recognize this VMware ESX DVD"], $output_handler);
            return; # doesn't seem to be a valid DVD or CD
        }
    } elsif (-r $path . "/vmkernel.gz" and -r $path . "/isolinux.cfg"){
        open(LINE,$path . "/isolinux.cfg");
        while (<LINE>) {
            if (/ThinESX Installer/) {
                $darch = 'x86';
                $arch='x86';
                unless ($distname) { $distname='esxi3.5'; }
                $found=1;
                last;
            }
        }
        close(LINE);
    } elsif (-r $path . "/upgrade/metadata.xml") {
	open(LINE,$path."/upgrade/metadata.xml");
	my $detectdistname;
    	while (<LINE>) {
            if (/esxVersion>([^<]*)</) {
                my $version = $1;
                while ($version =~ /\.0$/) {
                    $version =~ s/\.0$//;
                }
			    $darch="x86_64";
    			$arch="x86_64";
                $detectdistname = 'esxi' . $version;
		$found=1;
            } elsif (/esxRelease>([^<]*)</) {
                unless ($includeupdate) {
                    next;
                }
		my $release = $1;
                while ($release =~ /\.0$/) {
                    $release =~ s/\.0$//;
                }
		unless ($release ne "0") {
			next;
		}
                $detectdistname .= '_' . $release;
            }
        }
			unless ($distname) { $distname=$detectdistname; }
    } elsif (-r $path . "/vmware-esx-base-readme") {
	open(LINE,$path."/vmware-esx-base-readme");
	while (<LINE>) {
		if (/VMware ESXi 5\.0/) {
			$darch="x86_64";
			$arch="x86_64";
			unless ($distname) { $distname='esxi5'; }
			$found=1;
			last;
		}
		if (/VMware ESXi 5\.1/) {
			$darch="x86_64";
			$arch="x86_64";
			unless ($distname) { $distname='esxi5.1'; }
			$found=1;
			last;
		}
		if (/VMware ESXi 5\.5/) {
			$darch="x86_64";
			$arch="x86_64";
			unless ($distname) { $distname='esxi5.5'; }
			$found=1;
			last;
		}
	}
     }

    unless ($found) { return; } #not our media
    if ($::XCATSITEVALS{osimagerequired}){
          my ($nohaveimages,$errstr)=xCAT::SvrUtils->update_tables_with_templates($distname, $arch,"","",checkonly=>1);
          if ($nohaveimages) { 
               $output_handler->({error => "No Templates found to support $distname($arch)",errorcode=>2});
          }
    }

	xCAT::SvrUtils::sendmsg("Copying media to $installroot/$distname/$arch/", $output_handler);
    my $omask = umask 0022;
    mkpath("$installroot/$distname/$arch");
    umask $omask;
    my $rc;
    my $reaped = 0;
    $SIG{INT} = $SIG{TERM} = sub {
        foreach(@cpiopid){
            kill 2, $_;
        }
        if ($path) {
            chdir("/");
            system("umount $path");
        }
    };
    my $KID;
    chdir $path;
    my $numFiles = `find . -print | wc -l`;
    my $child = open($KID, "|-");
    unless (defined $child)
    {
        xCAT::SvrUtils::sendmsg([1,"Media copy operation fork failure"], $output_handler);
        return;
    }
    if ($child)
    {
        push @cpiopid, $child;
        my @finddata = `find .`;
        for (@finddata)
        {
            print $KID $_;
        }
        close($KID);
        $rc = $?;
    }
    else
    {
        nice 10;
        my $c = "nice -n 20 cpio -vdump $installroot/$distname/$arch";
        my $k2 = open(PIPE, "$c 2>&1 |") ||
            xCAT::SvrUtils::sendmsg([1,"Media copy operation fork failure"], $output_handler);
        push @cpiopid, $k2;
        my $copied = 0;
        my ($percent, $fout);
        while(<PIPE>){
          next if /^cpio:/;
          $percent = $copied / $numFiles;
          $fout = sprintf "%0.2f%%", $percent * 100;
          $output_handler->({sinfo => "$fout"});
          ++$copied;
        }
        exit;
	}
	# let everyone read it
	#chdir "/tmp";
	chmod 0755, "$installroot/$distname/$arch";
	if ($distname =~ /esxi[56]/) { #going to tweak boot.cfg for install and default stateless case
	  if (! -r "$installroot/$distname/$arch/boot.cfg.stateless") {
	    copy("$installroot/$distname/$arch/boot.cfg","$installroot/$distname/$arch/boot.cfg.stateless");
	    my $bootcfg;
	    open($bootcfg,"<","$installroot/$distname/$arch/boot.cfg");
	    my @bootcfg = <$bootcfg>;
	    close($bootcfg);
	    foreach (@bootcfg) { #no point in optimizing trivial, infrequent code, readable this way
	      s!kernel=/!kernel=!; # remove leading /
	      s!modules=/!modules=!; #remove leading /
	      s!--- /!--- !g; #remove all the 'absolute' slashes
	    }
	    open($bootcfg,">","$installroot/$distname/$arch/boot.cfg.install");
	    foreach (@bootcfg) {
	      if (/^modules=/ and $_ !~ /xcatmod.tgz/ and not $::XCATSITEVALS{xcatesximoddisable}) {
			chomp();
			s! *\z! --- xcatmod.tgz\n!;
	      }
	      print $bootcfg $_;
	    }
	    close($bootcfg);
	    foreach (@bootcfg) { #no point in optimizing trivial, infrequent code, readable this way
	      s/runweasel//; #don't run the installer in stateless mode
	      s!--- imgdb.tgz!!; #don't need the imgdb for stateless
	      s!--- imgpayld.tgz!!; #don't need the boot payload since we aren't installing
	      s!--- tools.t00!!; #tools could be useful, but for now skip the memory requirement
	      s!--- weaselin.i00!!; #and also don't need the weasel install images if... not installing
	      
	      if (/^modules=/ and $_ !~ /xcatmod.tgz/ and not $::XCATSITEVALS{xcatesximoddisable}) {
		chomp();
		s! *\z! --- xcatmod.tgz\n!;
	      }
	      s!Loading ESXi installer!xCAT is loading ESXi stateless!;
	    }
	    open($bootcfg,">","$installroot/$distname/$arch/boot.cfg.stateless");
	    foreach (@bootcfg) {
	      print $bootcfg $_;
	    }
	    close($bootcfg);
	 	if (grep /LSIProvi.v00/,@bootcfg and ! -r "$installroot/$distname/$arch/LSIProvi.v00" and -r "$installroot/$distname/$arch/lsiprovi.v00") { #there is media with LSIProv.v00 expected, but the install media was mal-constructed, fix it
			move("$installroot/$distname/$arch/lsiprovi.v00","$installroot/$distname/$arch/LSIProvi.v00");
	    }
	  }
	}
	
	if ($rc != 0){
        xCAT::SvrUtils::sendmsg([1,"Media copy operation failed, status $rc"], $output_handler);
	}else{
	    xCAT::SvrUtils::sendmsg("Media copy operation successful", $output_handler);
	    my @ret=xCAT::SvrUtils->update_tables_with_templates($distname, $arch);
	    if ($ret[0] != 0) {
		xCAT::SvrUtils::sendmsg("Error when updating the osimage tables: " . $ret[1], $output_handler);
	    }
	

	}
}
sub  makecustomizedmod {
    my $osver = shift;
    my $dest = shift;
	if ($::XCATSITEVALS{xcatesximoddisable}) { return 1; }
    my $modname;
    if ($osver =~ /esxi4/) { #want more descriptive name,but don't break esxi4 setups.
      $modname="mod.tgz";
    # if it already exists, do not overwrite it because it may be someone
    # else's custom image
      if(-f "$dest/$modname"){ return 1; }
    } else {
      $modname="xcatmod.tgz";
    }
    my $passtab = xCAT::Table->new('passwd');
    my $tmp;
    my $password;
    if ($passtab) {
        ($tmp) = $passtab->getAttribs({'key'=>'vmware'},'username','password');
        if (defined($tmp)) {
            $password = $tmp->{password};
        }
    }
    unless ($password) {
        xCAT::SvrUtils::sendmsg([1,": Unable to find a password entry for esxi in passwd table"], $output_handler);
        return 0;
    }
    mkpath("/tmp/xcat");
    my $tempdir = tempdir("/tmp/xcat/esxmodcustXXXXXXXX");
    my $shadow;
    mkpath($tempdir."/etc/");
    my $oldmask=umask(0077);
    open($shadow,">",$tempdir."/etc/shadow");
    $password = crypt($password,'$1$'.xCAT::Utils::genpassword(8));
    my $dayssince1970 = int(time()/86400); #Be truthful about /etc/shadow
    my @otherusers = qw/nobody nfsnobody dcui daemon/;
    if ($osver =~ /esxi4/) {
      push @otherusers,"vimuser";
    } elsif ($osver =~ /esxi[56]/) {
      push @otherusers,"vpxuser";
    }
    print $shadow "root:$password:$dayssince1970:0:99999:7:::\n";
    foreach (@otherusers) {
        print $shadow "$_:*:$dayssince1970:0:99999:7:::\n";
    }
    close($shadow);
    umask($oldmask);
    if ($osver =~ /esxi4/ and -e "$::XCATROOT/share/xcat/netboot/esxi/38.xcat-enableipv6") {
        mkpath($tempdir."/etc/vmware/init/init.d");
        copy( "$::XCATROOT/share/xcat/netboot/esxi/38.xcat-enableipv6",$tempdir."/etc/vmware/init/init.d/38.xcat-enableipv6");
    } elsif ($osver =~ /esxi[56]/ and -e "$::XCATROOT/share/xcat/netboot/esxi/xcat-ipv6.json") {
        mkpath($tempdir."/usr/libexec/jumpstart/plugins/");
        copy( "$::XCATROOT/share/xcat/netboot/esxi/xcat-ipv6.json",$tempdir."/usr/libexec/jumpstart/plugins/xcat-ipv6.json");
    }
    if ($osver =~ /esxi4/ and -e "$::XCATROOT/share/xcat/netboot/esxi/47.xcat-networking") {
        copy( "$::XCATROOT/share/xcat/netboot/esxi/47.xcat-networking",$tempdir."/etc/vmware/init/init.d/47.xcat-networking");
    } elsif ($osver =~ /esxi[56]/ and -e "$::XCATROOT/share/xcat/netboot/esxi/39.ipv6fixup") {
        mkpath($tempdir."/etc/init.d");
        copy( "$::XCATROOT/share/xcat/netboot/esxi/39.ipv6fixup",$tempdir."/etc/init.d/39.ipv6fixup");
		chmod(0755,"$tempdir/etc/init.d/39.ipv6fixup");
    }
    if ($osver =~ /esxi[56]/ and -e "$::XCATROOT/share/xcat/netboot/esxi/48.esxifixup") {
        mkpath($tempdir."/etc/init.d");
        copy( "$::XCATROOT/share/xcat/netboot/esxi/48.esxifixup",$tempdir."/etc/init.d/48.esxifixup");
		chmod(0755,"$tempdir/etc/init.d/48.esxifixup");
    }
    if ($osver =~ /esxi5/ and -e "$::XCATROOT/share/xcat/netboot/esxi/99.esxiready") {
        mkpath($tempdir."/etc/init.d");
        copy( "$::XCATROOT/share/xcat/netboot/esxi/99.esxiready",$tempdir."/etc/init.d/99.esxiready");
		chmod(0755,"$tempdir/etc/init.d/99.esxiready");
    }
    if (-e "$::XCATROOT/share/xcat/netboot/esxi/xcatsplash") {
      mkpath($tempdir."/etc/vmware/");
        copy( "$::XCATROOT/share/xcat/netboot/esxi/xcatsplash",$tempdir."/etc/vmware/welcome");
    }
    my $dossh=0;
    if (-r "/root/.ssh/id_rsa.pub") {
        $dossh=1;
        my $umask = umask(0077);#don't remember if dropbear is picky, but just in case
        if ($osver =~ /esxi4/) { #esxi4 used more typical path
	  mkpath($tempdir."/.ssh");
	  copy("/root/.ssh/id_rsa.pub",$tempdir."/.ssh/authorized_keys");
	} elsif ($osver =~ /esxi5/) { #weird path to keys
	  mkpath($tempdir."/etc/ssh/keys-root");
	  copy("/root/.ssh/id_rsa.pub",$tempdir."/etc/ssh/keys-root/authorized_keys");
	}
        umask($umask);
    }
    my $tfile;
    mkpath($tempdir."/var/run/vmware");
    open $tfile,">",$tempdir."/var/run/vmware/show-tech-support-login";
    close($tfile);
    #TODO: auto-enable ssh and request boot-time customization rather than on-demand?
    require Cwd;
    my $dir=Cwd::cwd();
    chdir($tempdir);
    if (-e "$dest/$modname") {
        unlink("$dest/$modname");
    }
    if ($dossh and $osver =~ /esxi4/) {
        system("tar czf $dest/$modname * .ssh");
    } else {
        system("tar czf $dest/$modname *");
    }
    chdir($dir);
    rmtree($tempdir);
    return 1;
}
sub getplatform {
	my $os = shift;
	if ($os =~ /esxi/) {
		return "esxi";
	}
	return $os;
}
sub	esxi_kickstart_from_template {
	my %args=@_;
	my $installdir = "/install";
	if ($::XCATSITEVALS{installdir}) { $installdir = $::XCATSITEVALS{installdir}; }
	my $plat = getplatform($args{os});
	my $template = xCAT::SvrUtils::get_tmpl_file_name("$installdir/custom/install/$plat",$args{profile},$args{os},$args{arch},$args{os});
	unless ($template) {
	   $template = xCAT::SvrUtils::get_tmpl_file_name("$::XCATROOT/share/xcat/install/$plat",$args{profile},$args{os},$args{arch},$args{os});
	}
	my $tmperr;
	if (-r "$template") {
		$tmperr=xCAT::Template->subvars($template,"$installdir/autoinst/".$args{node},$args{node},undef);
	} else {
		 $tmperr="Unable to find template in /install/custom/install/$plat or $::XCATROOT/share/xcat/install/$plat (for $args{profile}/$args{os}/$args{arch} combination)";
	}
	if ($tmperr) {
			xCAT::SvrUtils::sendmsg([1,$tmperr], $output_handler,$args{node});
	}

}
sub mkinstall {
	return mkcommonboot("install",@_);
}
sub mknetboot {
	return mkcommonboot("stateless",@_);
}
sub merge_esxi5_append {
	my $tmpl = shift;
	my $append = shift;
	my $outfile = shift;
	my $in;
	my $out;
	open($in,"<",$tmpl);
	open($out,">",$outfile);
	my $line;
	while ($line = <$in>) {
		if ($line =~ /kernelopt=/) {
		   chomp($line);
		   $line .= $append."\n";
		#if ($line =~ /modules=b.b00/) {
		#	$line =~ s/modules=b.b00/modules=b.b00 $append/;
		}
		unless ($line =~ /^prefix=/) {
			print $out $line;
		}
	}
}
sub mkcommonboot {
    my $bootmode = shift;
	my $req      = shift;
	my $doreq    = shift;
	my $globaltftpdir  = "/tftpboot";
	my @nodes    = @{$req->{node}};
	my $ostab    = xCAT::Table->new('nodetype');
	#my $sitetab  = xCAT::Table->new('site');
	my $bptab		 = xCAT::Table->new('bootparams',-create=>1);
	my $installroot = "/install";
	#if ($sitetab){
		#(my $ref) = $sitetab->getAttribs({key => 'installdir'}, 'value');
                my @entries =  xCAT::TableUtils->get_site_attribute("installdir");
                my $t_entry = $entries[0];
		if ( defined($t_entry) ) {
                    $installroot = $t_entry;
		}
		#($ref) = $sitetab->getAttribs({key => 'tftpdir'}, 'value');
                @entries =  xCAT::TableUtils->get_site_attribute("tftpdir");
                $t_entry = $entries[0];
		if ( defined($t_entry) ) {
                    $globaltftpdir = $t_entry;
		}
	#}
	my %donetftp=();

	my $bpadds = $bptab->getNodesAttribs(\@nodes,['addkcmdline']);
	my $nodehmtab = xCAT::Table->new('nodehm',-create=>0);
	my $serialconfig;
	if ($nodehmtab) {
		$serialconfig = $nodehmtab->getNodesAttribs(\@nodes,['serialport','serialspeed']);
	}
    my $restab = xCAT::Table->new('noderes',-create=>0);
    my $resents;
    if ($restab) {
        $resents = $restab->getNodesAttribs(\@nodes,['tftpdir','nfsserver']);
    }
		
    my %tablecolumnsneededforaddkcmdline;
    my %nodesubdata;
	foreach my $key (keys %$bpadds){ #First, we identify all needed table.columns needed to aggregate database call
        my $add = $bpadds->{$key}->[0]->{addkcmdline};

        next if ! defined $add;

        while ($add =~ /#NODEATTRIB:([^:#]+):([^:#]+)#/) { 
            push @{$tablecolumnsneededforaddkcmdline{$1}},$2;
            $add =~ s/#NODEATTRIB:([^:#]+):([^:#]+)#//;
        }
    }
    foreach my $table (keys %tablecolumnsneededforaddkcmdline) {
        my $tab = xCAT::Table->new($table,-create=>0);
        if ($tab) {
            $nodesubdata{$table}=$tab->getNodesAttribs(\@nodes,$tablecolumnsneededforaddkcmdline{$table});
        }
    }

    my $osents = $ostab->getNodesAttribs(\@nodes, ['os', 'arch', 'profile']);
	foreach my $node (@nodes){
		my $ent =  $osents->{$node}->[0]; 
		my $arch = $ent->{'arch'};
		my $profile = $ent->{'profile'};
		my $osver = $ent->{'os'};
        my $tftpdir;
	    my $ksserver;
        if ($resents and $resents->{$node}->[0]->{nfsserver}) {
			$ksserver=$resents->{$node}->[0]->{nfsserver};
		} else {
			$ksserver='!myipfn!';
		}

        if ($resents and $resents->{$node}->[0]->{tftpdir}) {
           $tftpdir = $resents->{$node}->[0]->{tftpdir};
        } else {
           $tftpdir = $globaltftpdir;
        }
		#if($arch ne 'x86'){	
		#	xCAT::SvrUtils::sendmsg([1,"VMware ESX hypervisors are x86, please change the nodetype.arch value to x86 instead of $arch for $node before proceeding:
        #e.g: nodech $node nodetype.arch=x86\n"]);
		#	return;
		#}
		# first make sure copycds was done:
        my $custprofpath = $profile;
        unless ($custprofpath =~ /^\//) {#If profile begins with a /, assume it already is a path
            $custprofpath = $installroot."/custom/install/$osver/$arch/$profile";
            unless(-d $custprofpath) {
                $custprofpath = $installroot."/custom/install/esxi/$arch/$profile";
            }
        }
		unless(
            -r "$custprofpath/vmkboot.gz"
			or -r "$custprofpath/b.z"
			or	-r "$custprofpath/mboot.c32"
			or -r "$custprofpath/install.tgz"
			or	-r "$installroot/$osver/$arch/mboot.c32"
			or -r "$installroot/$osver/$arch/install.tgz" ){
			xCAT::SvrUtils::sendmsg([1,"Please run copycds first for $osver or create custom image in $custprofpath/"], $output_handler);
		}

        my @reqmods = qw/vmkboot.gz vmk.gz sys.vgz cim.vgz/; #Required modules for an image to be considered complete
		if ( -r "$custprofpath/b.z" ) { #if someone hand extracts from imagedd, a different name scheme is used
			@reqmods = qw/b.z k.z s.z c.z/;
		}
        my %mods;
        foreach (@reqmods) {
            $mods{$_} = 1;
        }
        my $shortprofname = $profile;
        $shortprofname =~ s/\/\z//;
        $shortprofname =~ s/.*\///;
		mkpath("$tftpdir/xcat/netboot/$osver/$arch/$shortprofname/");
        my $havemod=0;
		unless($donetftp{$osver,$arch,$profile,$tftpdir}) {
			my $srcdir = "$installroot/$osver/$arch";
			my $dest = "$tftpdir/xcat/netboot/$osver/$arch/$shortprofname";
			cpNetbootImages($osver,$srcdir,$dest,$custprofpath,\%mods,bootmode=>$bootmode);
            if ($havemod = makecustomizedmod($osver,$dest)) {
                push @reqmods,"mod.tgz";
                $mods{"mod.tgz"}=1;
            }
            if ($osver =~ /esxi4/ and -r "$::XCATROOT/share/xcat/netboot/syslinux/mboot.c32") { #prefer xCAT patched mboot.c32 with BOOTIF for mboot
			    copy("$::XCATROOT/share/xcat/netboot/syslinux/mboot.c32", $dest);
            } elsif (-r "$custprofpath/mboot.c32") {
			    copy("$custprofpath/mboot.c32", $dest);
            } elsif (-r "$srcdir/mboot.c32") {
			    copy("$srcdir/mboot.c32", $dest);
 			}
            if (-f "$srcdir/efiboot.img") {
				copy("$srcdir/efiboot.img",$dest);
				print("$srcdir/efi");
                mkpath("$dest/efi");
				recursion_copy("$srcdir/efi","$dest/efi");
            }
			$donetftp{$osver,$arch,$profile,$tftpdir} = 1;
		}
		my $tp = "xcat/netboot/$osver/$arch/$shortprofname";
	my $kernel;
	my $kcmdline;
	my $append;
    my $shortappend;
	if ($osver =~ /esxi4/) {
	  my $bail=0;
	  foreach (@reqmods) {
	      unless (-r "$tftpdir/$tp/$_") { 
		  xCAT::SvrUtils::sendmsg([1,"$_ is missing from the target destination, ensure that either copycds has been run or that $custprofpath contains this file"], $output_handler);
		  $bail=1; #only flag to bail, present as many messages as possible to user
	      }
	  }
	  if ($bail) { #if the above loop detected one or more failures, bail out
	    return;
	  }	
	      # now make <HEX> file entry stuff
		$kernel = "$tp/mboot.c32";
		my $prepend;
		if ($reqmods[0] eq "vmkboot.gz") {
			$prepend = "$tp/vmkboot.gz";
	        delete $mods{"vmkboot.gz"};
			$append = " --- $tp/vmk.gz";
	        delete $mods{"vmk.gz"};
			$append .= " --- $tp/sys.vgz";
	        delete $mods{"sys.vgz"};
			$append .= " --- $tp/cim.vgz";
	        delete $mods{"cim.vgz"};
		} else { #the single letter style
			$prepend = "$tp/b.z";
	        delete $mods{"b.z"};
			$append = " --- $tp/k.z";
	        delete $mods{"k.z"};
			$append .= " --- $tp/s.z";
	        delete $mods{"s.z"};
			$append .= " --- $tp/c.z";
	        delete $mods{"c.z"};
		}
			
        if ($mods{"mod.tgz"}) {
		    $append .= " --- $tp/mod.tgz";
            delete $mods{"mod.tgz"};
        }
        foreach (keys %mods) {
            $append .= " --- $tp/$_";
        }
		if (defined $bpadds->{$node}->[0]->{addkcmdline}) {
            my $modules;
            ($kcmdline,$modules) = split /---/,$bpadds->{$node}->[0]->{addkcmdline},2;
            $kcmdline =~ s/#NODEATTRIB:([^:#]+):([^:#]+)#/$nodesubdata{$1}->{$node}->[0]->{$2}/eg;
            if ($modules) {
                $append .= " --- ".$modules;
            }
            $prepend .= " ".$kcmdline;
		}
        $append = $prepend.$append;
	}
	elsif ($osver =~ /esxi5/) { #do a more straightforward thing..
	  $kernel = "$tp/mboot.c32";
      if (-r "$tftpdir/$tp/boot.cfg.$bootmode.tmpl") { #so much for straightforward..
	  	$shortappend = "-c $tp/boot.cfg.$bootmode.$node";
	} else {
	  $append = "-c $tp/boot.cfg.$bootmode";
	}
    $append .= " xcatd=$ksserver:3001";
	  if ($bootmode eq "install") {
	  	$append .= " ks=http://$ksserver/install/autoinst/$node";
		esxi_kickstart_from_template(node=>$node,os=>$osver,arch=>$arch,profile=>$profile);
	  }
	  if ($bootmode ne "install" and $serialconfig->{$node}) { #don't do it for install, installer croaks currently
		my $comport = 1;
		if (defined $serialconfig->{$node}->[0]->{serialport}) {
			 $comport = $serialconfig->{$node}->[0]->{serialport}+1;
			 $append .= " -S $comport tty2port=com$comport";
		}
		if (defined $serialconfig->{$node}->[0]->{serialspeed}) {
			$append .= " -s ".$serialconfig->{$node}->[0]->{serialspeed}." com".$comport."_baud=".$serialconfig->{$node}->[0]->{serialspeed};
		}
	}
		if (defined $bpadds->{$node}->[0]->{addkcmdline}) {
			$append .= " ".$bpadds->{$node}->[0]->{addkcmdline};
            $append =~ s/#NODEATTRIB:([^:#]+):([^:#]+)#/$nodesubdata{$1}->{$node}->[0]->{$2}/eg;
		}
	}
    if ($shortappend) { #esxi5 user desiring to put everything in one boot config file. . .
		merge_esxi5_append("$tftpdir/$tp/boot.cfg.$bootmode.tmpl",$append,"$tftpdir/$tp/boot.cfg.$bootmode.$node");
    	$append=$shortappend;
    }
	$output_handler->({node=>[{name=>[$node],'_addkcmdlinehandled'=>[1]}]});



		$bptab->setNodeAttribs(
			$node,
			{
			kernel => $kernel,
			initrd => "",
			kcmdline => $append
			}
		);
	} # end of node loop

}
# this is where we extract the netboot images out of the copied ISO image
sub cpNetbootImages {
	my $osver = shift;
	my $srcDir = shift;
	my $destDir = shift;	
    my $overridedir = shift;
    my $modulestoadd = shift;
	my %parmargs = @_;
	my $bootmode="stateless";
	if ($parmargs{bootmode}) { $bootmode = $parmargs{bootmode} }
	my $tmpDir = "/tmp/xcat.$$";
	if($osver =~ /esxi4/){
		# we don't want to go through this all the time, so if its already
		# there we're not going to extract:
		unless(   -r "$destDir/vmk.gz" 
			and -r "$destDir/vmkboot.gz"
			and -r "$destDir/sys.vgz"
			and -r "$destDir/cim.vgz"
			and -r "$destDir/cimstg.tgz"
		){
            if (-r "$srcDir/image.tgz") { #it still may work without image.tgz if profile customization has everything replaced
		    mkdir($tmpDir);
		    chdir($tmpDir);
            xCAT::SvrUtils::sendmsg("extracting netboot files from OS image.  This may take about a minute or two...hopefully you have ~1GB free in your /tmp dir\n", $output_handler);
            my $cmd = "tar zxf $srcDir/image.tgz";
            if(system($cmd)){
                xCAT::SvrUtils::sendmsg([1,"Unable to extract $srcDir/image.tgz\n"], $output_handler); 
            }
            # this has the big image and may take a while.
            # this should now create:
            # /tmp/xcat.1234/usr/lib/vmware/installer/VMware-VMvisor-big-164009-x86_64.dd.bz2 or some other version.  We need to extract partition 5 from it.
            system("bunzip2 $tmpDir/usr/lib/vmware/installer/*bz2");
            xCAT::SvrUtils::sendmsg("finished extracting, now copying files...\n", $output_handler);
	
            # now we need to get partition 5 which has the installation goods in it.
            my $scmd = "fdisk -lu $tmpDir/usr/lib/vmware/installer/*dd 2>&1 | grep dd5 | awk '{print \$2}'";
            my $sector = `$scmd`;
            chomp($sector);
            my $offset = $sector * 512;
            mkdir "/mnt/xcat";
            my $mntcmd = "mount $tmpDir/usr/lib/vmware/installer/*dd  /mnt/xcat -o loop,offset=$offset";
            if(system($mntcmd)){
                xCAT::SvrUtils::sendmsg([1,"unable to mount partition 5 of the ESX netboot image to /mnt/xcat"], $output_handler);
                return;
            }

            if (! -d $destDir) {
                if ( -e $destDir ) {
                    xCAT::SvrUtils::sendmsg([1,"Could not copy netboot contents to $destDir, it exists but is not currently a directory"], $output_handler);
                    return;
                }
                mkpath($destDir);
            }
            
            if(system("cp /mnt/xcat/* $destDir/")){
                xCAT::SvrUtils::sendmsg([1,"Could not copy netboot contents to $destDir"], $output_handler);
				chdir("/");
                system("umount /mnt/xcat");
                return;
            }
            chdir("/tmp");
            system("umount /mnt/xcat");
            system("rm -rf $tmpDir");
            } elsif (-r "$srcDir/cim.vgz" and -r "$srcDir/vmkernel.gz" and -r "$srcDir/vmkboot.gz" and -r "$srcDir/sys.vgz") {
                use File::Basename;
                if (! -d $destDir) {
                    mkpath($destDir);
                }
                #In ESXI 4.1, the above breaks, this seems to work, much simpler too
                foreach ("$srcDir/cim.vgz","$srcDir/vmkernel.gz","$srcDir/vmkboot.gz","$srcDir/sys.vgz","$srcDir/sys.vgz") {
                    my $mod = scalar fileparse($_);
                    if ($mod =~ /vmkernel.gz/) {
                        copy($_,"$destDir/vmk.gz") or xCAT::SvrUtils::sendmsg([1,"Could not copy netboot contents from $_ to $destDir/$mod"], $output_handler);
                    } else {
                        copy($_,"$destDir/$mod") or xCAT::SvrUtils::sendmsg([1,"Could not copy netboot contents from $_ to $destDir/$mod"], $output_handler);
                    }
                }

            }
        }

        #this is the override directory if there is one, otherwise it's actually the default dir
        if (-d $overridedir) {
            mkdir($overridedir);
        }

        #Copy over all modules 
        use File::Basename;
        foreach (glob "$overridedir/*") {
            my $mod = scalar fileparse($_);
            if ($mod =~ /gz\z/ and $mod !~ /pkgdb.tgz/ and $mod !~ /vmkernel.gz/) {
                $modulestoadd->{$mod}=1;
                copy($_,"$destDir/$mod") or xCAT::SvrUtils::sendmsg([1,"Could not copy netboot contents from $overridedir to $destDir"], $output_handler);
            } elsif ($mod =~ /vmkernel.gz/) {
                $modulestoadd->{"vmk.gz"}=1;
                copy($_,"$destDir/vmk.gz") or xCAT::SvrUtils::sendmsg([1,"Could not copy netboot contents from $overridedir to $destDir"], $output_handler);
            }
        }

	}elsif ($osver =~ /esxi[56]/) { #we need boot.cfg.stateles
	  my @filestocopy = ("boot.cfg.$bootmode");
	  if (-r "$srcDir/boot.cfg.$bootmode" or -r "$overridedir/boot.cfg.$bootmode") {
	     @filestocopy = ("boot.cfg.$bootmode");
      } elsif (-r "$srcDir/boot.cfg.$bootmode.tmpl" or -r "$overridedir/boot.cfg.$bootmode.tmpl") {
	     @filestocopy = ("boot.cfg.$bootmode.tmpl");
      } else {
	    xCAT::SvrUtils::sendmsg([1,"$srcDir is missing boot.cfg.$bootmode file required for $bootmode boot"], $output_handler);
	    return;
	  }
	  my $statelesscfg;
	  if (-r "$overridedir/boot.cfg.$bootmode.tmpl") {
	    open ($statelesscfg,"<","$overridedir/boot.cfg.$bootmode.tmpl");
	    @filestocopy = ("boot.cfg.$bootmode.tmpl");
	  } elsif (-r "$overridedir/boot.cfg.$bootmode") {
	    open ($statelesscfg,"<","$overridedir/boot.cfg.$bootmode");
	  } elsif (-r "$srcDir/boot.cfg.$bootmode.tmpl") {
	    @filestocopy = ("boot.cfg.$bootmode.tmpl");
	    open ($statelesscfg,"<","$srcDir/boot.cfg.$bootmode.tmpl");
	  } elsif (-r "$srcDir/boot.cfg.$bootmode") {
	    open ($statelesscfg,"<","$srcDir/boot.cfg.$bootmode");
	  } else {
	    die "boot.cfg.$bootmode was missing from $srcDir???";
	  }
	  my @statelesscfg=<$statelesscfg>;
	  
	  foreach (@statelesscfg) { #search for files specified by the boot cfg and pull them in
	    if (/^kernel=(.*)/) {
	      push @filestocopy,$1;
	    } elsif (/^modules=(.*)/) {
	      foreach (split / --- /,$1) {
			s/^\s*//;
			s/\s.*//;
		push @filestocopy,$_;
	      }
	    }
	  }
	    #now that we have a list, do the copy (mostly redundant, but PXE needs them tftp accessible)
	    foreach (@filestocopy) {
	      chomp;
	      s/ *\z//;
	      my $mod = scalar fileparse($_);
	      if (-r "$overridedir/$mod") {
		copyIfNewer("$overridedir/$mod","$destDir/$mod") or xCAT::SvrUtils::sendmsg([1,"Could not copy netboot contents from $overridedir/$mod to $destDir/$mod, $!"], $output_handler);
	      } elsif (-r "$srcDir/$mod") {
		copyIfNewer($srcDir."/".$mod,"$destDir/$mod") or xCAT::SvrUtils::sendmsg([1,"Could not copy netboot contents from $srcDir/$mod to $destDir/$mod, $!"], $output_handler);
	      } elsif ($mod ne "xcatmod.tgz") {
		xCAT::SvrUtils::sendmsg([1,"Could not copy netboot contents from $srcDir/$mod to $destDir/$mod, $srcDir/$mod not found"], $output_handler);
	      }
	    }
	} else {
			xCAT::SvrUtils::sendmsg([1,"VMware $osver is not supported for netboot"], $output_handler);	  
	}

}

sub copyIfNewer {
  my $source = shift;
  my $dest = shift;
  if (! -e $dest or -C $source < -C $dest) {
    return copy($source,$dest);
  }
  return 1; 
}

# compares nfs target described by parameters to every share mounted by target hypervisor
# returns 1 if matching datastore is present and 0 otherwise
sub match_nfs_datastore {
  my ($host, $path, $hypconn) = @_;
  
  die "esx plugin bug: no host provided for match_datastore" unless defined $host;
  die "esx plugin bug: no path provided for match_datastore" unless defined $path;

  my @ip;

  eval {
    if ($host =~ m/\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\//) {
      use Socket;

      @ip = ( $host );
      $host = gethostbyaddr(inet_aton($host, AF_INET), AF_INET);
    } else {
      use Socket;

      (undef, undef, undef, undef, @ip) = gethostbyname($host);

      my @ip_ntoa = ();
      foreach (@ip) {
        push (@ip_ntoa, inet_ntoa($_));
      }
      @ip = @ip_ntoa;
    }
    
  };

  if ($@) {
    die "error while resolving datastore host: $@\n";
  } 

  my %viewcrit = (
    view_type => 'HostSystem',
    properties => [ 'config.fileSystemVolume' ],
  );

  my $dsviews = $hypconn->find_entity_views(%viewcrit);

  foreach (@$dsviews) {
    foreach my $mount (@{$_->get_property('config.fileSystemVolume.mountInfo')}) {
      next unless $mount->{'volume'}{'type'} eq 'NFS';

      my $hostMatch = 0;
      HOSTMATCH: foreach (@ip, $host) {
        next HOSTMATCH unless $mount->{'volume'}{'remoteHost'} eq $_;

        $hostMatch = 1;
        last HOSTMATCH;
      } 
      next unless $hostMatch;

      next unless $mount->{'volume'}{'remotePath'} eq $path;

      return 1;
    }
  }

  return 0; 
}

1;
# vi: set ts=4 sw=4 filetype=perl: 
