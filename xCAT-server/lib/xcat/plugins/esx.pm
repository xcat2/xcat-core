package xCAT_plugin::esx;

use strict;
use warnings;
use xCAT::Table;
use xCAT::Utils;
use Time::HiRes qw (sleep);
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
use IO::Socket; #Need name resolution
#use Data::Dumper;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");
my @cpiopid;
our @ISA = 'xCAT::Common';


#in xCAT, the lifetime of a process ends on every request
#therefore, the lifetime of assignments to these glabals as architected
#is to be cleared on every request
#my %esx_comm_pids;
my %hyphash; #A data structure to hold hypervisor-wide variables (i.e. the current resource pool, virtual machine folder, connection object
my %vcenterhash; #A data structure to reflect the state of vcenter connectivity to hypervisors
my %hypready; #A structure for hypervisor readiness to be tracked before proceeding to normal operations
my %running_tasks; #A struct to track this processes
my $output_handler; #Pointer to the function to drive results to client
my $executerequest;
my $usehostnamesforvcenter;
my %tablecfg; #to hold the tables
my $currkey;
my $viavcenter;
my $viavcenterbyhyp;
my $vmwaresdkdetect = eval {
    require VMware::VIRuntime;
    VMware::VIRuntime->import();
    1;
};


my %guestidmap = (
    "rhel.5.*" => "rhel5_",
    "rhel4.*" => "rhel4_",
    "centos5.*" => "rhel5_",
    "centos4.*" => "rhel4_",
    "sles11.*" => "sles11_",
    "sles10.*" => "sles10_",
    "win2k8" => "winLonghorn",
    "win2k8r2" => "windows7Server",
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
		rpower => 'nodehm:power,mgt',
		rsetboot => 'nodehm:power,mgt',
		rmigrate => 'nodehm:power,mgt',
		mkvm => 'nodehm:mgt',
		rmvm => 'nodehm:mgt',
		rinv => 'nodehm:mgt',
                chvm => 'nodehm:mgt',
        lsvm => 'hypervisor:type',
		rmhypervisor => 'hypervisor:type',
		#lsvm => 'nodehm:mgt', not really supported yet
	};
}





sub preprocess_request {
	my $request = shift;
	my $callback = shift;
    my $username = 'root';
    my $password = '';
    my $vusername = "Administrator";
    my $vpassword = "";

    unless ($request and $request->{command} and $request->{command}->[0]) { return; }

	if ($request->{command}->[0] eq 'copycd')
	{    #don't farm out copycd
		return [$request];
	}elsif($request->{command}->[0] eq 'mknetboot'){
		return [$request];
	}
    xCAT::Common::usage_noderange($request,$callback);

        if ($request->{_xcatpreprocessed} and $request->{_xcatpreprocessed}->[0] == 1) { return [$request]; } 
         # exit if preprocesses
	my @requests;

	my $noderange = $request->{node};  # array ref
	my $command = $request->{command}->[0];
	my $extraargs = $request->{arg};
	my @exargs=($request->{arg});	
	my %hyp_hash = ();

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

	my $vmtabhash = $vmtab->getNodesAttribs($noderange,['host']);
	foreach my $node (@$noderange){
        if ($command eq "rmhypervisor" or $command eq 'lsvm') {
            $hyp_hash{$node}{nodes} = [$node];
        } else {
        my $ent = $vmtabhash->{$node}->[0];
		if(defined($ent->{host})) {
			push @{$hyp_hash{$ent->{host}}{nodes}}, $node;
		} else {
			$callback->({data=>["no host defined for guest $node"]});
			$request = {};
			return;
		}
		if(defined($ent->{id})) {
			push @{$hyp_hash{$ent->{host}}{ids}},$ent->{id};
		}else{
 			push @{$hyp_hash{$ent->{host}}{ids}}, "";
		}
        }
	}

	# find service nodes for the MMs
	# build an individual request for each service node
	my $service  = "xcat";
	my @hyps=keys(%hyp_hash);
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
        }
    }
    #TODO: per hypervisor table password lookup
	my $sn = xCAT::Utils->get_ServiceNode(\@hyps, $service, "MN");
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
            if ($hyp_hash{$_}{nodes}) {
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
		$reqcopy->{node} = \@nodes;
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
	my $level = shift;
	my $distname = undef;
	my $arch = undef;
	my $path = undef;
	my $command = $request->{command}->[0];
    #The first segment is fulfilling the role of this plugin as 
    #a hypervisor provisioning plugin (akin to anaconda, windows, sles plugins)
	if($command eq 'copycd'){
		return copycd($request,$executerequest);
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
        sendmsg([1,"VMWare SDK required for operation, but not installed"]);
        return;
    }

	my $moreinfo;
	my $noderange = $request->{node};
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
	my $sitetab = xCAT::Table->new('site');
	if($sitetab){
		(my $ref) = $sitetab->getAttribs({key => 'usehostnamesforvcenter'}, 'value');
		if ($ref and $ref->{value}) {
			$usehostnamesforvcenter = $ref->{value};
		}
	}


	if ($request->{moreinfo}) { $moreinfo=$request->{moreinfo}; }
	else {  $moreinfo=build_more_info($noderange,$output_handler);}
	foreach my $info (@$moreinfo) {
		$info=~/^\[(.*?)\]\[(.*?)\]\[(.*?)\]\[(.*?)\]\[(.*?)\]\[(.*?)\]\[(.*?)\]/;
		my $hyp=$1;
		my @nodes=split(',', $2);
        my $username = $3;
        my $password = $4;
        $hyphash{$hyp}->{vcenter}->{name} = $7;
        $hyphash{$hyp}->{vcenter}->{username} = $5;
        $hyphash{$hyp}->{vcenter}->{password} = $6;
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
        $tablecfg{hypervisor} = $hyptab->getNodesAttribs(\@hyps,['mgr','netmap','defaultnet','cluster','preferdirect']);
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
    my $keytab = xCAT::Table->new('prodkey');
    if ($keytab) {
        my @hypes = keys %hyphash;
        $tablecfg{prodkey} = $keytab->getNodesAttribs(\@hypes,[qw/product key/]);
    }
	foreach my $hyp (sort(keys %hyphash)){
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
                      sendmsg([1,"Unable to reach $vcenter vCenter server to manage $hyp: $@"]);
                      next;
                }
            }
            $hyphash{$hyp}->{conn} = $vcenterhash{$hyphash{$hyp}->{vcenter}->{name}}->{conn};
            $hyphash{$hyp}->{vcenter}->{conn} = $vcenterhash{$hyphash{$hyp}->{vcenter}->{name}}->{conn};
            if (validate_vcenter_prereqs($hyp, \&declare_ready, {
                hyp=>$hyp,
                vcenter=>$vcenter
                }) eq "failed") {
                $hypready{$hyp} = -1;
            }
        } else {
            eval { 
              $hyphash{$hyp}->{conn} = Vim->new(service_url=>"https://$hyp/sdk");
              $hyphash{$hyp}->{conn}->login(user_name=>$hyphash{$hyp}->{username},password=>$hyphash{$hyp}->{password});
            }; 
            if ($@) {
	       $hyphash{$hyp}->{conn} = undef;
	       sendmsg([1,"Unable to reach $hyp to perform operation"]);
                $hypready{$hyp} = -1;
	       next;
            }
              validate_licenses($hyp);
        }
		#}else{
		#	$esx_comm_pids{$pid} = 1;
		#}
	}
    while (grep { $_ == 0 } values %hypready) {
        wait_for_tasks();
        sleep (1); #We'll check back in every second.  Unfortunately, we have to poll since we are in web service land
    }
    my @badhypes;
    if (grep { $_ == -1 } values %hypready) {
        foreach (keys %hypready) {
            if ($hypready{$_} == -1) {
                push @badhypes,$_;
                my @relevant_nodes = sort (keys %{$hyphash{$_}->{nodes}});
                foreach (@relevant_nodes) {
                    sendmsg([1,": hypervisor unreachable"],$_);
                }
                delete $hyphash{$_};
            }
        }
        if (@badhypes) { 
            sendmsg([1,": The following hypervisors failed to become ready for the operation: ".join(',',@badhypes)]);
        }
    } 
    do_cmd($command,@exargs);
    foreach (@badhypes) { delete $hyphash{$_}; }
    foreach my $hyp (sort(keys %hyphash)){
      $hyphash{$hyp}->{conn}->logout();
    }
}

sub validate_licenses {
    my $hyp = shift;
    my $conn = $hyphash{$hyp}->{conn};
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
    if ($command eq 'rpower') {
        generic_vm_operation(['config.name','config','runtime.powerState','runtime.host'],\&power,@exargs);
    } elsif ($command eq 'rmvm') {
        generic_vm_operation(['config.name','runtime.powerState','runtime.host'],\&rmvm,@exargs);
    } elsif ($command eq 'rsetboot') {
        generic_vm_operation(['config.name','runtime.host'],\&setboot,@exargs);
    } elsif ($command eq 'rinv') {
        generic_vm_operation(['config.name','config','runtime.host'],\&inv,@exargs);
    } elsif ($command eq 'rmhypervisor') {
        generic_hyp_operation(\&rmhypervisor,@exargs);
    } elsif ($command eq 'lsvm') {
        generic_hyp_operation(\&lsvm,@exargs);
    } elsif ($command eq 'mkvm') {
        generic_hyp_operation(\&mkvms,@exargs);
    } elsif ($command eq 'chvm') {
        generic_vm_operation(['config.name','config','runtime.host'],\&chvm,@exargs);
        #generic_hyp_operation(\&chvm,@exargs);
    } elsif ($command eq 'rmigrate') { #Technically, on a host view, but vcenter path is 'weirder'
        generic_hyp_operation(\&migrate,@exargs);
    }
    wait_for_tasks();
}

#inventory request for esx
sub inv {
  my %args = @_;
  my $node = $args{node};
  my $hyp = $args{hyp};
  if (not defined $args{vmview}) { #attempt one refresh
    $args{vmview} = $hyphash{$hyp}->{conn}->find_entity_view(view_type => 'VirtualMachine',properties=>['config.name','runtime.powerState'],filter=>{name=>$node});
    if (not defined $args{vmview}) { 
      sendmsg([1,"VM does not appear to exist"],$node);
      return;
    }
  }
  my $vmview = $args{vmview};
  my $uuid = $vmview->config->uuid;
  sendmsg("UUID/GUID:  $uuid",$node);
  my $cpuCount = $vmview->config->hardware->numCPU;
  sendmsg("CPUs:  $cpuCount",$node);
  my $memory = $vmview->config->hardware->memoryMB;
  sendmsg("Memory:  $memory MB",$node);
  my $devices = $vmview->config->hardware->device;
  my $label;
  my $size;
  my $fileName;
  my $device;
  foreach $device (@$devices) {
    $label = $device->deviceInfo->label;

    if($label =~ /^Hard disk/) {
        $label .= " (d".$device->unitNumber.")";
      $size = $device->capacityInKB / 1024;
      $fileName = $device->backing->fileName;
      sendmsg("$label:  $size MB @ $fileName",$node);
    } elsif ($label =~ /Network/) {
        sendmsg("$label: ".$device->macAddress,$node);
    }
  }
}


#changes the memory, number of cpus and device size
#can also add,resize and remove disks
sub chvm {
	my %args = @_;
	my $node = $args{node};
	my $hyp = $args{hyp};
	if (not defined $args{vmview}) { #attempt one refresh
		$args{vmview} = $hyphash{$hyp}->{conn}->find_entity_view(view_type => 'VirtualMachine',
				properties=>['config.name','runtime.powerState'],
				filter=>{name=>$node});
	  if (not defined $args{vmview}) {
		sendmsg([1,"VM does not appear to exist"],$node);
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
		sendmsg([1,"Could not parse options, ".shift()]);
	};
	my $rc = GetOptions(
		"d=s"       => \@deregister,
		"p=s"       => \@purge,
		"a=s"       => \@add,
		"resize=s%" => \%resize,
		"cpus=s"    => \$cpuCount,
		"mem=s"     => \$memory
	);
	$SIG{__WARN__} = 'DEFAULT';

	if(@ARGV) {
		sendmsg("Invalid arguments:  @ARGV");
		return;
	}

	if(!$rc) {
		return;
	}

	#use Data::Dumper;
	#sendmsg("dereg = ".Dumper(\@deregister));
	#sendmsg("purge = ".Dumper(\@purge));
	#sendmsg("add = ".Dumper(\@add));
	#sendmsg("resize = ".Dumper(\%resize));
	#sendmsg("cpus = $cpuCount");
	#sendmsg("mem = ".getUnits($memory,"K",1024));


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
				sendmsg([1,"Disk:  $disk does not exist"],$node);
				return;
			}
			#sendmsg(Dumper($device));
			push @devChanges, VirtualDeviceConfigSpec->new(
						device => $device,
						operation =>  VirtualDeviceConfigSpecOperation->new('remove'));

		}
	}

	if(@purge) {
		for $disk (@purge) {
			$device = getDiskByLabel($disk, $devices);
			unless($device) {
				sendmsg([1,"Disk:  $disk does not exist"],$node);
				return;
			}
			#sendmsg(Dumper($device));
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
		foreach $device (@$devices) {
			$label = $device->deviceInfo->label;
			if($label =~ /^SCSI controller/) {
				$scsiCont = $device;
			}
			if($label =~ /^IDE/) {
				$ideCont = $device;
			}
		}
		if($scsiCont) {
			$scsiUnit = getAvailUnit($scsiCont->{key},$devices);
		}
		if($ideCont) {
			$ideUnit = getAvailUnit($ideCont->{key},$devices);
		}
		unless ($hyphash{$hyp}->{datastoremap}) { validate_datastore_prereqs([],$hyp); }
    		push @devChanges, create_storage_devs($node,$hyphash{$hyp}->{datastoremap},$addSizes,$scsiCont,$scsiUnit,$ideCont,$ideUnit,$devices);
	}

	if(%resize) {
		while( my ($key, $value) = each(%resize) ) {
			my @drives = split(/,/, $key);
			for my $device ( @drives ) {
				my $disk = $device;
				$device = getDiskByLabel($disk, $devices);
				unless($device) {
					sendmsg([1,"Disk:  $disk does not exist"],$node);
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

	my $reconfigspec = VirtualMachineConfigSpec->new(%conargs);
	
	#sendmsg("reconfigspec = ".Dumper($reconfigspec));
	my $task = $vmview->ReconfigVM_Task(spec=>$reconfigspec);
	$running_tasks{$task}->{task} = $task;
	$running_tasks{$task}->{callback} = \&generic_task_callback;
	$running_tasks{$task}->{hyp} = $hyp;
	$running_tasks{$task}->{data} = { node => $node, successtext => "node successfully changed" };

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
    } elsif (($label =~ /^Hard disk/) and ($cmdLabel =~ /^d(\d+)/)) {
        if ($device->unitNumber == $1) {
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
            } else {
                $curcon = $hyphash{$running_tasks{$_}->{hyp}}->{conn};
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
        $vcenterhash{$args->{vcenter}}->{$args->{hypname}} = 'good';
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
        sendmsg([1,$error]); #,$node);
        $hypready{$args->{hypname}} = -1; #Impossible for this hypervisor to ever be ready
        $vcenterhash{$args->{vcenter}}->{$args->{hypname}} = 'bad';
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
        if (scalar @{$qnc->candidateVnic} eq 1) { #There is only one possible path, use it
            $nicmgr->SelectVnicForNicType(nicType=>"vmotion",device=>$qnc->candidateVnic->[0]->device);
            return 1;
        } else {
            sendmsg([1,"TODO: use configuration to pick the nic ".$args{hypname}]);
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
        sendmsg([1,$error],$node);
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
            sendmsg([1,$extratext.$error],$_);
        }
    }else {
            sendmsg([1,$extratext.$error]);
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
        sendmsg(":relocated to to ".$parms->{target},$parms->{node});
    } else {
        relay_vmware_err($task,"Relocating to ".$parms->{target}." ",$parms->{node});
    }
}
sub migrate_ok { #look like a successful migrate, callback for registering a vm
     my %args = @_;
     my $vmtab = xCAT::Table->new('vm');
     $vmtab->setNodeAttribs($args{nodes}->[0],{host=>$args{target}});
     sendmsg("migrated to ".$args{target},$args{nodes}->[0]);
}
sub migrate_callback {
    my $task = shift;
    my $parms = shift;
    my $state = $task->info->state->val;
    if (not $parms->{skiptodeadsource} and $state eq 'success') {
        my $vmtab = xCAT::Table->new('vm');
        $vmtab->setNodeAttribs($parms->{node},{host=>$parms->{target}});
        sendmsg("migrated to ".$parms->{target},$parms->{node});
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
        sendmsg($intent,$node);
    } elsif ($state eq 'error') {
        relay_vmware_err($task,"",$node);
    }  elsif ($q and $q->text =~ /^msg.uuid.altered:/ and ($q->choice->choiceInfo->[0]->summary eq 'Cancel' and ($q->choice->choiceInfo->[0]->key eq '0'))) { #make sure it is what is what we have seen it to be
        if ($parms->{forceon} and $q->choice->choiceInfo->[1]->summary eq 'I (_)?moved it' and $q->choice->choiceInfo->[1]->key eq '1') { #answer the question as 'moved'
            $vm->AnswerVM(questionId=>$q->id,answerChoice=>'1');
        } else {
            $vm->AnswerVM(questionId=>$q->id,answerChoice=>'0');
            sendmsg([1,"Failure powering on VM, it mismatched against the hypervisor.  If positive VM is not running on another hypervisor, use -f to force VM on"],$node);
        }
    } elsif ($q) {
        if ($q->choice->choiceInfo->[0]->summary eq 'Cancel') {
            sendmsg([1,":Cancelling due to unexpected question executing task: ".$q->text],$node);
        } else {
            sendmsg([1,":Task hang due to unexpected question executing task, need to use VMware tools to clean up the mess for now: ".$q->text],$node);
        }
    }

}
sub generic_task_callback {
    my $task = shift;
    my $parms = shift;
    my $state = $task->info->state->val;
    my $node = $parms->{node};
    my $intent = $parms->{successtext};
    if ($state eq 'success') {
        sendmsg($intent,$node);
    } elsif ($state eq 'error') {
        relay_vmware_err($task,"",$node);
    }
}

sub sendmsg {
    my $callback = $output_handler;
    my $text = shift;
    my $node = shift;
    my $descr;
    my $rc;
    if (ref $text eq 'HASH') {
        return $callback->($text);
    } elsif (ref $text eq 'ARRAY') {
        $rc = $text->[0];
        $text = $text->[1];
    }
    if ($text =~ /:/) {
        ($descr,$text) = split /:/,$text,2;
    }
    $text =~ s/^ *//;
    $text =~ s/ *$//;
    my $msg;
    my $curptr;
    if ($node) {
        $msg->{node}=[{name => [$node]}];
        $curptr=$msg->{node}->[0];
    } else {
        $msg = {};
        $curptr = $msg;
    }
    if ($rc) {
        $curptr->{errorcode}=[$rc];
        $curptr->{error}=[$text];
        $curptr=$curptr->{error}->[0];
    } else {
        $curptr->{data}=[{contents=>[$text]}];
        $curptr=$curptr->{data}->[0];
        if ($descr) { $curptr->{desc}=[$descr]; }
    }
    $callback->($msg);
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
        sendmsg([1,"Error parsing arguments"]);
        return;
    }
    my $target=$hyp; #case for storage migration
    if ($datastoredest and scalar @ARGV) {
        sendmsg([1,"Unable to mix storage migration and processing of arguments ".join(' ',@ARGV)]);
        return;
    } elsif (@ARGV) {
        $target=shift @ARGV;
        if (@ARGV) {
            sendmsg([1,"Unrecognized arguments ".join(' ',@ARGV)]);
            return;
        }
    } elsif ($datastoredest) { #storage migration only
        unless (validate_datastore_prereqs([],$hyp,{$datastoredest=>\@nodes})) {
            sendmsg([1,"Unable to find/mount target datastore $datastoredest"]);
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
    if ((not $offline and $vcenterhash{$vcenter}->{$hyp} eq 'bad') or $vcenterhash{$vcenter}->{$target} eq 'bad') {
        sendmsg([1,"Unable to migrate ".join(',',@nodes)." to $target due to inability to validate vCenter connectivity"]);
        return;
    }
    if (($offline or $vcenterhash{$vcenter}->{$hyp} eq 'good') and $vcenterhash{$vcenter}->{$target} eq 'good') {
        unless (validate_datastore_prereqs(\@nodes,$target)) {
            sendmsg([1,"Unable to verify storage state on target system"]);
            return;
        }
        unless (validate_network_prereqs(\@nodes,$target)) {
            sendmsg([1,"Unable to verify target network state"]);
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
		sendmsg([1,"Unable to locate node in vCenter"],$_);
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
        #sendmsg("Waiting for BOTH to be 'good'");
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
        $args{vmview} = $hyphash{$hyp}->{conn}->find_entity_view(view_type => 'VirtualMachine',properties=>['config.name','runtime.powerState'],filter=>{name=>$node});
        if (not defined $args{vmview}) { 
            sendmsg([1,"VM does not appear to exist"],$node);
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
            $running_tasks{$task}->{data} = { node => $node, args=>\%args }; 
            return;
        } else {
            sendmsg([1,"Cannot rmvm active guest (use -f argument to force)"],$node);
            return;
        }
    }
    if ($purge) {
        $task = $args{vmview}->Destroy_Task();
        $running_tasks{$task}->{data} = { node => $node, successtext => 'purged' };
        $running_tasks{$task}->{task} = $task;
        $running_tasks{$task}->{callback} = \&generic_task_callback;
        $running_tasks{$task}->{hyp} = $args{hyp}; #$hyp_conns->{$hyp};
    } else {
        $task = $args{vmview}->UnregisterVM();
    }
}



sub getreconfigspec {
    my %args = @_;
    my $node = $args{node};
    my $vmview = $args{view};
    my $currid=$args{view}->config->guestId();
    my $rightid=getguestid($node);
    my %conargs;
    my $reconfigneeded=0;
    if ($currid ne $rightid) {
        $reconfigneeded=1;
        $conargs{guestId}=$rightid;
    }
    my $newmem;
    if ($newmem = getUnits($tablecfg{vm}->{$node}->[0]->{memory},"M",1048576)) {
        my $currmem = $vmview->config->hardware->memoryMB;
        if ($newmem ne $currmem) {
            $conargs{memoryMB} = $newmem;
            $reconfigneeded=1;
        }
    }
    my $newcpus;
    if ($newcpus = $tablecfg{vm}->{$node}->[0]->{cpus}) {
        my $currncpu = $vmview->config->hardware->numCPU;
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
        $args{vmview} = $hyphash{$hyp}->{conn}->find_entity_view(view_type => 'VirtualMachine',properties=>['config.name','config','runtime.powerState'],filter=>{name=>$node});
        if (not defined $args{vmview}) { 
            sendmsg([1,"VM does not appear to exist"],$node);
            return;
        }
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
           if ($reconfigspec = getreconfigspec(node=>$node,view=>$args{vmview})) {
               if ($currstat eq 'poweredOff') {
                   #sendmsg("Correcting guestId because $currid and $rightid are not the same...");#DEBUG
                    my $task = $args{vmview}->ReconfigVM_Task(spec=>$reconfigspec);
                    $running_tasks{$task}->{task} = $task;
                    $running_tasks{$task}->{callback} = \&reconfig_callback;
                    $running_tasks{$task}->{hyp} = $args{hyp}; 
                    $running_tasks{$task}->{data} = { node => $node, reconfig_fun=>\&power, reconfig_args=>\%args }; 
                return;
               } elsif (grep /$subcmd/,qw/reset boot/) { #going to have to do a 'cycle' and present it up normally..
                    #sendmsg("DEBUG: forcing a cycle");
                    $task = $args{vmview}->PowerOffVM_Task();
                    $running_tasks{$task}->{task} = $task;
                    $running_tasks{$task}->{callback} = \&repower;
                    $running_tasks{$task}->{hyp} = $args{hyp}; 
                    $running_tasks{$task}->{data} = { node => $node, power_args=>\%args}; 
                    return; #we have to wait
               }
#TODO: fixit
           #sendmsg("I see vm has $currid and I want it to be $rightid");
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
                sendmsg($currstat,$node);
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
                        $task = $args{vmview}->PowerOnVM_Task(host=>$hyphash{$hyp}->{hostview});
                    };
                    if ($@) {
                        sendmsg([1,":".$@],$node);
                        return;
                    }
                    $running_tasks{$task}->{task} = $task;
                    $running_tasks{$task}->{callback} = \&poweron_task_callback;
                    $running_tasks{$task}->{hyp} = $args{hyp}; #$hyp_conns->{$hyp};
                    $running_tasks{$task}->{data} = { node => $node, successtext => $intent.'on', forceon=>$forceon };
                } else {
                    sendmsg($currstat,$node);
                }
            } elsif ($subcmd =~ /off/) {
                if ($currstat eq 'on') {
                    $task = $args{vmview}->PowerOffVM_Task();
                    $running_tasks{$task}->{task} = $task;
                    $running_tasks{$task}->{callback} = \&generic_task_callback;
                    $running_tasks{$task}->{hyp} = $args{hyp}; 
                    $running_tasks{$task}->{data} = { node => $node, successtext => 'off' }; 
                } else {
                    sendmsg($currstat,$node);
                }
            } elsif ($subcmd =~ /suspend/) {
                if ($currstat eq 'on') {
                    $task = $args{vmview}->SuspendVM_Task();
                    $running_tasks{$task}->{task} = $task;
                    $running_tasks{$task}->{callback} = \&generic_task_callback;
                    $running_tasks{$task}->{hyp} = $args{hyp}; 
                    $running_tasks{$task}->{data} = { node => $node, successtext => 'suspend' }; 
                } else {
                    sendmsg("off",$node);
                }
            } elsif ($subcmd =~ /reset/) {
                if ($currstat eq 'on') {
                    $task = $args{vmview}->ResetVM_Task();
                    $running_tasks{$task}->{task} = $task;
                    $running_tasks{$task}->{callback} = \&generic_task_callback;
                    $running_tasks{$task}->{hyp} = $args{hyp}; 
                    $running_tasks{$task}->{data} = { node => $node, successtext => $intent.'reset' }; 
                } elsif ($args{pretendop}) { #It is off, but pretend it was on
                    eval {
                        $task = $args{vmview}->PowerOnVM_Task(host=>$hyphash{$hyp}->{hostview});
                    };
                    if ($@) {
                        sendmsg([1,":".$@],$node);
                        return;
                    }
                    $running_tasks{$task}->{task} = $task;
                    $running_tasks{$task}->{callback} = \&generic_task_callback;
                    $running_tasks{$task}->{hyp} = $args{hyp}; 
                    $running_tasks{$task}->{data} = { node => $node, successtext => $intent.'reset' }; 
                } else {
                    sendmsg($currstat,$node);
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
    foreach $hyp (keys %hyphash) {
        if ($viavcenterbyhyp->{$hyp}) {
            if ($vcviews{$hyphash{$hyp}->{vcenter}->{name}}) { next; }
            my @localvcviews=();
            my $node;
    	    foreach $node (sort (keys %{$hyphash{$hyp}->{nodes}})){
                push @localvcviews,$hyphash{$hyp}->{conn}->find_entity_view(view_type => 'VirtualMachine',properties=>$properties,filter=>{'config.name'=>qr/^$node/});
            }
            $vcviews{$hyphash{$hyp}->{vcenter}->{name}} = \@localvcviews;
            #$vcviews{$hyphash{$hyp}->{vcenter}->{name}} = $hyphash{$hyp}->{conn}->find_entity_views(view_type => 'VirtualMachine',properties=>$properties);
            foreach (@{$vcviews{$hyphash{$hyp}->{vcenter}->{name}}}) {
                my $node = $_->{'config.name'};
                unless (defined $tablecfg{vm}->{$node}) {
                    $node =~ s/\..*//; #try the short name;
                }
                if (defined $tablecfg{vm}->{$node}) { #see if the host pointer requires a refresh 
                    my $host = $hyphash{$hyp}->{conn}->get_view(mo_ref=>$_->{'runtime.host'});
                    $host = $host->summary->config->name;
                    if ( $tablecfg{vm}->{$node}->[0]->{host} eq "$host" ) { next; }
                    my $newnhost = inet_aton($host);
                    my $oldnhost = inet_aton($tablecfg{vm}->{$node}->[0]->{host});
                    if ($newnhost eq $oldnhost) { next; } #it resolved fine
                    my $shost = $host;
                    $shost =~ s/\..*//;
                    if ( $tablecfg{vm}->{$node}->[0]->{host} eq "$shost" ) { next; }
                    #time to figure out which of these is a node
                    my @nodes = noderange("$host,$shost");
                    my $vmtab = xCAT::Table->new("vm",-create=>1);
                    unless($vmtab){
                        die "Error opening vm table";
                    }
                    if ($nodes[0]) {
                        print $node. " and ".$nodes[0];
                        $vmtab->setNodeAttribs($node,{host=>$nodes[0]});
                    } #else {
                      #  $vmtab->setNodeAttribs($node,{host=>$host});
                    #}

                }
            }
        }
    }
    foreach $hyp (keys %hyphash) {
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
    }
}

sub generic_hyp_operation { #The general form of firing per-hypervisor requests to ESX hypervisor
    my $function = shift; #The function to actually run against the right VM view
    my @exargs = @_; #Store the rest to pass on
    my $hyp;
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
        sendmsg($vmv->name,$hyp);
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

sub mkvms {
    my %args = @_;
    my $nodes = $args{nodes};
    my $hyp = $args{hyp};
    @ARGV = @{$args{exargs}}; #for getoptions;
    my $disksize;
    require Getopt::Long;
    GetOptions(
        'size|s=s' => \$disksize
        );
    my $node;
    $hyphash{$hyp}->{hostview} = get_hostview(hypname=>$hyp,conn=>$hyphash{$hyp}->{conn}); #,properties=>['config','configManager']); 
    unless (validate_datastore_prereqs($nodes,$hyp)) {
        return;
    }
    $hyphash{$hyp}->{vmfolder} = $hyphash{$hyp}->{conn}->get_view(mo_ref=>$hyphash{$hyp}->{conn}->find_entity_view(view_type=>'Datacenter',properties=>['vmFolder'])->vmFolder);
    $hyphash{$hyp}->{pool} = $hyphash{$hyp}->{conn}->get_view(mo_ref=>$hyphash{$hyp}->{hostview}->parent,properties=>['resourcePool'])->resourcePool;
    my $cfg;
    foreach $node (@$nodes) {
         process_tasks; #check for tasks needing followup actions before the task is forgotten (VMWare's memory is fairly short at times
        if ($hyphash{$hyp}->{conn}->find_entity_view(view_type=>"VirtualMachine",filter=>{name=>$node})) {
            sendmsg([1,"Virtual Machine already exists"],$node);
            next;
        } else {
            register_vm($hyp,$node,$disksize);
        }
    }
    my @dhcpnodes;
    foreach (keys %{$tablecfg{dhcpneeded}}) {
        push @dhcpnodes,$_;
        delete $tablecfg{dhcpneeded}->{$_};
    }
    $executerequest->({command=>['makedhcp'],node=>\@dhcpnodes});
}

sub setboot {
    my %args = @_;
    my $node = $args{node};
    my $hyp = $args{hyp};
    if (not defined $args{vmview}) { #attempt one refresh
        $args{vmview} = $hyphash{$hyp}->{conn}->find_entity_view(view_type => 'VirtualMachine',properties=>['config.name'],filter=>{name=>$node});
        if (not defined $args{vmview}) { 
            sendmsg([1,"VM does not appear to exist"],$node);
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
            sendmsg([1,"rsetboot parameter may not contain 'setup' with other items, assuming vm.bootorder is just 'setup'"],$node);
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
    $running_tasks{$task}->{data} = { node => $node, successtext => ${$args{exargs}}[0] }; 
}
sub register_vm {#Attempt to register existing instance of a VM
    my $hyp = shift;
    my $node = shift;
    my $disksize = shift;
    my $blockedfun = shift; #a pointer to a blocked function to call on success
    my $blockedargs = shift; #hash reference to call blocked function with
    my $failonerr = shift;
    my $task;
    validate_network_prereqs([keys %{$hyphash{$hyp}->{nodes}}],$hyp);
    unless (defined $hyphash{$hyp}->{datastoremap} or validate_datastore_prereqs([keys %{$hyphash{$hyp}->{nodes}}],$hyp)) {
        die "unexpected condition";
    }
    unless (defined $hyphash{$hyp}->{vmfolder}) {
        $hyphash{$hyp}->{vmfolder} = $hyphash{$hyp}->{conn}->get_view(mo_ref=>$hyphash{$hyp}->{conn}->find_entity_view(view_type=>'Datacenter',properties=>['vmFolder'])->vmFolder);
    }
    unless (defined $hyphash{$hyp}->{pool}) {
        $hyphash{$hyp}->{pool} = $hyphash{$hyp}->{conn}->get_view(mo_ref=>$hyphash{$hyp}->{hostview}->parent,properties=>['resourcePool'])->resourcePool;
    }

    # Try to add an existing VM to the machine folder
    my $success = eval {
        $task = $hyphash{$hyp}->{vmfolder}->RegisterVM_Task(path=>getcfgdatastore($node,$hyphash{$hyp}->{datastoremap})." /$node/$node.vmx",name=>$node,pool=>$hyphash{$hyp}->{pool},asTemplate=>0);
    };
    # if we couldn't add it then it means it wasn't created yet.  So we create it.
    if ($@ or not $success) {
        #if (ref($@) eq 'SoapFault') {
        # if (ref($@->detail) eq 'NotFound') {
        register_vm_callback(undef, {
            node => $node,
            disksize => $disksize,
            blockedfun => $blockedfun,
            blockedargs => $blockedargs,
            errregister=>$failonerr,
            hyp => $hyp
        });
    }
    if ($task) {
        $running_tasks{$task}->{task} = $task;
        $running_tasks{$task}->{callback} = \&register_vm_callback;
        $running_tasks{$task}->{hyp} = $hyp;
        $running_tasks{$task}->{data} = { 
            node => $node,
            disksize => $disksize,
            blockedfun => $blockedfun,
            blockedargs => $blockedargs,
            errregister=>$failonerr,
            hyp => $hyp
        };
    }
}

sub register_vm_callback {
    my $task = shift;
    my $args = shift;
    if (not $task or $task->info->state->val eq 'error') { #TODO: fail for 'rpower' flow, mkvm is too invasive in VMWare to be induced by 'rpower on'
        if (not defined $args->{blockedfun}) {
            mknewvm($args->{node},$args->{disksize},$args->{hyp});
        } elsif ($args->{errregister}) {
            relay_vmware_err($task,"",$args->{node});
        } else {
            sendmsg([1,"mkvm must be called before use of this function"],$args->{node});
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
            sendmsg([1,"could not resolve '$server' to an address from vm.storage/vm.cfgstore"]);
        }
        $server = inet_ntoa($servern);
        $uri = "nfs://$server/$path";
    }elsif($method =~ /vmfs/){
        (my $name, undef) = split /\//,$location,2;
        $name =~ s/:$//; #remove a : if someone put it in for some reason.  
        $uri = "vmfs://$name";
    }else{
        sendmsg([1,"Unsupported VMware Storage Method: $method.  Please use 'vmfs or nfs'"]);
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
    my $uri = getURI($method,$location);
    $cfgdatastore = "[".$dses->{$uri}."]";
    #$cfgdatastore =~ s/,.*$//; #these two lines of code were kinda pointless
    #$cfgdatastore =~ s/\/$//;
    return $cfgdatastore;
}


sub mknewvm {
        my $node=shift;
        my $disksize=shift;
        my $hyp=shift;
#TODO: above
        my $cfg = build_cfgspec($node,$hyphash{$hyp}->{datastoremap},$hyphash{$hyp}->{nets},$disksize,$hyp);
        my $task = $hyphash{$hyp}->{vmfolder}->CreateVM_Task(config=>$cfg,pool=>$hyphash{$hyp}->{pool},host=>$hyphash{$hyp}->{hostview});
        $running_tasks{$task}->{task} = $task;
        $running_tasks{$task}->{callback} = \&mkvm_callback;
        $running_tasks{$task}->{hyp} = $hyp;
        $running_tasks{$task}->{data} = { hyp=>$hyp, node => $node };
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
    my $nodeos = $tablecfg{nodetype}->{$node}->[0]->{os};
    my $nodearch = $tablecfg{nodetype}->{$node}->[0]->{arch};
    foreach (keys %guestidmap) {
        if (defined($nodeos) and $nodeos =~ /$_/) {
            if ($nodearch eq 'x86_64') {
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
    my $memory;
    my $ncpus;
    unless ($memory = getUnits($tablecfg{vm}->{$node}->[0]->{memory},"M",1048576)) {
        $memory = 512;
    }
    unless ($ncpus = $tablecfg{vm}->{$node}->[0]->{cpus}) {
        $ncpus = 1;
    }
    my @devices;
    $currkey=0;
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
    return VirtualMachineConfigSpec->new(
            name => $node,
            files => $vfiles,
            guestId=>$nodeos,
            memoryMB => $memory,
            numCPUs => $ncpus,
            deviceChange => \@devices,
            uuid=>$uuid,
        );
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
    foreach (@networks) {
        my $pgname = $hyphash{$hyp}->{pgnames}->{$_};
        s/.*://;
        s/=.*//;
        my $netname = $_;
        #print Dumper($netmap);
        my $backing = VirtualEthernetCardNetworkBackingInfo->new(
            network => $netmap->{$pgname},
            deviceName=>$pgname,
        );
        my $newcard=VirtualE1000->new(
            key=>0,#3, #$currkey++,
            backing=>$backing,
            addressType=>"manual",
            macAddress=>shift @macs,
            connectable=>$connprefs,
            wakeOnLanEnabled=>1, #TODO: configurable in tables?
            );
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
    #number of devices is the larger of the specified sizes (TODO: masters) or storage pools to span
    my $numdevs = (scalar @storelocs > scalar @sizes ? scalar @storelocs : scalar @sizes);
    while ($numdevs-- > 0) {
        my $storeloc = shift @storelocs;
        unless (scalar @storelocs) { @storelocs = ($storeloc); } #allow reuse of one cfg specified pool for multiple devs
        my $disksize = shift @sizes;
        unless (scalar @sizes) { @sizes = ($disksize); } #if we emptied the array, stick the last entry back on to allow it to specify all remaining disks
        $disksize = getUnits($disksize,'G',1024);
        $disktype = 'ide';
        if ($storeloc =~ /=/) {
            ($storeloc,$disktype) = split /=/,$storeloc;
        }
        $storeloc =~ s/\/$//;
        (my $method,my $location) = split /:\/\//,$storeloc,2;
        my $uri = getURI($method, $location);
        #(my $server,my $path) = split/\//,$location,2;
        #$server =~ s/:$//; #tolerate habitual colons
        #my $servern = inet_aton($server);
        #unless ($servern) {
        #    sendmsg([1,"could not resolve '$server' to an address from vm.storage"]);
        #    return;
        #}
        #$server = inet_ntoa($servern);
        #my $uri = "nfs://$server/$path";
        $backingif = VirtualDiskFlatVer2BackingInfo->new(diskMode => 'persistent',
                                                          thinProvisioned => 1,
                                                           fileName => "[".$sdmap->{$uri}."]");
        if ($disktype eq 'ide' and $idecontrollerkey eq 1 and $ideunitnum eq 0) { #reserve a spot for CD
            $ideunitnum = 1;
        } elsif ($disktype eq 'ide' and $ideunitnum eq 2) { #go from current to next ide 'controller'
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
            $usedideunits{$unitnum}=1;
        } else {
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
           $dev=VirtualLsiLogicController->new(key => $_,
                                               device => \@{$disktocont{$_}},
                                               sharedBus => VirtualSCSISharing->new('noSharing'),
                                               busNumber => $_);
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
        sendmsg([1,": Unable to reach vCenter server managing $hyp"]);
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
    $hview = $hyphash{$hyp}->{vcenter}->{conn}->find_entity_view(view_type=>'HostSystem',properties=>['summary.config.name','summary.runtime.connectionState','runtime.inMaintenanceMode','parent','configManager'],filter=>{'summary.config.name'=>qr/^$hyp(?:\.|\z)/});
    unless ($hview) {
         $hview = $hyphash{$hyp}->{vcenter}->{conn}->find_entity_view(view_type=>'HostSystem',properties=>['summary.config.name','summary.runtime.connectionState','runtime.inMaintenanceMode','parent','configManager'],filter=>{'summary.config.name'=>qr/^$name(?:\.|\z)/});
    }
    if ($hview) { 
        if ($hview->{'summary.config.name'} =~ /^$hyp(?:\.|\z)/ or $hview->{'summary.config.name'} =~ /^$name(?:\.|\z)/) { #Looks good, call the dependent function after declaring the state of vcenter to hypervisor as good
            if ($hview->{'summary.runtime.connectionState'}->val eq 'connected') {
                enable_vmotion(hypname=>$hyp,hostview=>$hview,conn=>$hyphash{$hyp}->{vcenter}->{conn});
                $vcenterhash{$vcenter}->{$hyp} = 'good';
                $depfun->($depargs);
                if ($hview->parent->type eq 'ClusterComputeResource') { #if it is in a cluster, we can directly remove it
                    $hyphash{$hyp}->{deletionref} = $hview->{mo_ref}; 
                } elsif ($hview->parent->type eq 'ComputeResource') { #For some reason, we must delete the container instead
                    $hyphash{$hyp}->{deletionref} = $hview->{parent}; #save off a reference to delete hostview off just in case
                }


                return 1;
            } else {
                my $ref_to_delete;
                if ($hview->parent->type eq 'ClusterComputeResource') { #We are allowed to specifically kill a host in a cluster
                    $ref_to_delete = $hview->{mo_ref};
                } elsif ($hview->parent->type eq 'ComputeResource') { #For some reason, we must delete the container instead
                    $ref_to_delete = $hview->{parent};
                }
                my $task = $hyphash{$hyp}->{vcenter}->{conn}->get_view(mo_ref=>$ref_to_delete)->Destroy_Task();
                $running_tasks{$task}->{task} = $task;
                $running_tasks{$task}->{callback} = \&addhosttovcenter;
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
            }
        }
    }
    #If still in function, haven't found any likely host entries, make a new one
    unless ($hyphash{$hyp}->{offline}) {
        eval {
            $hyphash{$hyp}->{conn} = Vim->new(service_url=>"https://$hyp/sdk"); #Direct connect to install/check licenses
        	$hyphash{$hyp}->{conn}->login(user_name=>$hyphash{$hyp}->{username},password=>$hyphash{$hyp}->{password});
        };
        if ($@) {
    		sendmsg([1,": Failed to communicate with $hyp"]);
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
        $vcenterhash{$args->{vcenter}}->{$args->{hypname}} = 'good';
        if (defined $args->{depfun}) { #If a function is waiting for the host connect to go valid, call it
            $args->{depfun}->($args->{depargs});
        }
        return;
    }
    if ($tablecfg{hypervisor}->{$hyp}->[0]->{cluster}) {
        my $cluster = get_clusterview(clustname=>$tablecfg{hypervisor}->{$hyp}->[0]->{cluster},conn=>$hyphash{$hyp}->{vcenter}->{conn});
        unless ($cluster) {
            sendmsg([1,$tablecfg{hypervisor}->{$hyp}->[0]->{cluster}. " is not a known cluster to the vCenter server."]);
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

    my $datacenter = $hyphash{$hyp}->{vcenter}->{conn}->find_entity_view(view_type => 'Datacenter', properties=>['hostFolder']);

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
        sendmsg([1,": Invalid format for hypervisor.netmap detected for $hyp"]);
        return undef;
    }
    my %requiredports;
    my %portkeys;
    foreach (split /&/,$portdesc) {
        $requiredports{$_}=1;
    }

    my $hostview = $hyphash{$hyp}->{hostview};
    unless ($hostview) {
        $hyphash{$hyp}->{hostview} = get_hostview(hypname=>$hyp,conn=>$hyphash{$hyp}->{conn}); #,properties=>['config','configManager']); 
        $hostview = $hyphash{$hyp}->{hostview};
    }
    foreach (@{$hostview->config->network->pnic}) {
        if ($requiredports{$_->device}) { #We establish lookups both ways
            $portkeys{$_->key}=$_->device;
            delete $requiredports{$_->device};
        }
    }
    if (keys %requiredports) {
        sendmsg([1,":Unable to locate the following nics on $hyp: ".join(',',keys %requiredports)]);
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
            sendmsg([1,": Aggregation mismatch detected, request nic is aggregated with a nic not requested"]);
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
    my $netman=$hyphash{$hyp}->{conn}->get_view(mo_ref=>$hostview->configManager->networkSystem);
    $netman->AddVirtualSwitch(
        vswitchName=>$description,
        spec=>$vswspec
    );
    return $description;
}

sub validate_network_prereqs {
    my $nodes = shift;
    my $hyp  = shift;
    my $hypconn = $hyphash{$hyp}->{conn};
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
            my $switchname = get_default_switch_for_hypervisor($hyp); 
            my $tabval=$_;
            my $pgname;
            s/=.*//; #TODO specify nic model with <blah>=model
            if (/:/) { #The config specifies a particular path in some way
                s/(.*)://;
                $switchname = get_switchname_for_portdesc($hyp,$1);
                $pgname=$switchname."-".$_;
            } else { #Use the default vswitch per table config to connect this through, use the same name we did before to maintain compatibility
                $pgname=$_;
            }
            my $netname = $_;
            my $netsys;
            $hyphash{$hyp}->{pgnames}->{$tabval}=$pgname;
            my $policy = HostNetworkPolicy->new();
            unless ($hyphash{$hyp}->{nets}->{$pgname}) {
                my $vlanid;
                if ($netname =~ /trunk/) {
                    $vlanid=4095;
                } elsif ($netname =~ /vl(an)?(\d+)$/) {
                    $vlanid=$2;
                } else {
                    $vlanid = 0;
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
                $netsys->AddPortGroup(portgrp=>$hostgroupdef);
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
                } #end while loop
            }
        }
    }
    return 1;

}
sub validate_datastore_prereqs {
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
                        sendmsg([1,"Unable to resolve VMware specified host '".$dsv->info->nas->remoteHost."' to an address, problems may occur"]);
                    }
                    $hyphash{$hyp}->{datastoremap}->{"nfs://".$mnthost.$dsv->info->nas->remotePath}=$dsv->info->name;
                    $hyphash{$hyp}->{datastorerefmap}->{"nfs://".$mnthost.$dsv->info->nas->remotePath}=$_;
                } #TODO: care about SMB
            }elsif(defined $dsv->info->{vmfs}){
                my $name = $dsv->info->vmfs->name;
                $hyphash{$hyp}->{datastoremap}->{"vmfs://".$name} = $dsv->info->name;     
                $hyphash{$hyp}->{datasotrerefmap}->{"vmfs://".$name} = $_;
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
                        sendmsg([1,": Unable to resolve '$server' to an address, check vm.cfgstore/vm.storage"]);
                        return 0;
                    }
                    $server = inet_ntoa($servern);
                    my $uri = "nfs://$server/$path";
                    unless ($hyphash{$hyp}->{datastoremap}->{$uri}) { #If not already there, must mount it
                        $refresh_names=1;
                        ($hyphash{$hyp}->{datastoremap}->{$uri},$hyphash{$hyp}->{datastorerefmap}->{$uri})=mount_nfs_datastore($hostview,$location);
                    }
                }elsif($method =~ /vmfs/){
                    (my $name, undef) = split /\//,$location,2;
                    $name =~ s/:$//; #remove a : if someone put it in for some reason.  
                    my $uri = "vmfs://$name";
                    # check and see if this vmfs is on the node.
                    unless ($hyphash{$hyp}->{datastoremap}->{$uri}) { #If not already there, try creating it.
                        ($hyphash{$hyp}->{datastoremap}->{$uri},$hyphash{$hyp}->{datastorerefmap}->{$uri})=create_vmfs_datastore($hostview,$name);
                    }
                }else{
                    sendmsg([1,": $method is unsupported at this time (nfs would be)"],$node);
                    return 0;
                }
            } else {
                sendmsg([1,": $_ not supported storage specification for ESX plugin,\n\t'nfs://<server>/<path>'\n\t\tor\n\t'vmfs://<vmfs>'\n only currently supported vm.storage supported for ESX at the moment"],$node);
                return 0;
            } #TODO: raw device mapping, VMFS via iSCSI, VMFS via FC?
        }
    }
    # newdatastores are for migrations or changing vms.  
    # TODO: make this work for VMFS.  Right now only NFS.
    if (ref $newdatastores) {
        foreach (keys %$newdatastores) {
            s/\/$//; #Strip trailing slash if specified, to align to VMware semantics
            if (/:\/\//) {
                ($method,$location) = split /:\/\//,$_,2;
                (my $server, my $path) = split /\//,$location,2;
                $server =~ s/:$//; #remove a : if someone put it in out of nfs mount habit
                my $servern = inet_aton($server);
                unless ($servern) {
                    sendmsg([1,": Unable to resolve '$server' to an address, check vm.cfgstore/vm.storage"]);
                    return 0;
                }
                $server = inet_ntoa($servern);
                my $uri = "nfs://$server/$path";
                unless ($method =~ /nfs/) {
                    foreach (@{$newdatastores->{$_}}) {
                        sendmsg([1,": $method is unsupported at this time (nfs would be)"],$_);
                    }
                    return 0;
                }
                unless ($hyphash{$hyp}->{datastoremap}->{$uri}) { #If not already there, must mount it
                    $refresh_names=1;
                    ($hyphash{$hyp}->{datastoremap}->{$uri},$hyphash{$hyp}->{datastorerefmap}->{$uri})=mount_nfs_datastore($hostview,$location);
                }
            } else {
                foreach (@{$newdatastores->{$_}}) {
                    sendmsg([1,": $_ not supported storage specification for ESX plugin, 'nfs://<server>/<path>' only currently supported vm.storage supported for ESX at the moment"],$_);
                }
                return 0;
            } #TODO: raw device mapping, VMFS via iSCSI, VMFS via FC?
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
                            sendmsg([1,"Unable to resolve VMware specified host '".$dsv->info->nas->remoteHost."' to an address, problems may occur"]);
                        }
                        $hyphash{$hyp}->{datastoremap}->{"nfs://".$mnthost.$dsv->info->nas->remotePath}=$dsv->info->name;
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
    # call some VMware API here to create
    my $hdss = $hostview->{vim}->get_view(mo_ref=>$hostview->configManager->datastoreSystem);
    my $diskList = $hdss->QueryAvailableDisksForVmfs(); 
    my $count = scalar(@$diskList); # get the number of disks available for formatting.  
    unless($count >0){
        die "No disks are available to create VMFS volume for $name";
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
      return @moreinfo;;
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
	my $sitetab = xCAT::Table->new('site');
	if($sitetab){
		(my $ref) = $sitetab->getAttribs({key => 'installdir'}, 'value');
		if ($ref and $ref->{value}) {
			$installroot = $ref->{value};
		}
	}
	@ARGV = @{$request->{arg}};
	GetOptions(
		'n=s' => \$distname,
		'a=s' => \$arch,
		'p=s' => \$path
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
            $distname = $product.$version;
            $found = 1;
        }
    } elsif (-r $path . "/README" and -r $path . "/open_source_licenses.txt" and -d $path . "/VMware") { #Candidate to be ESX 3.5
        open(LINE,$path."/README");
        while(<LINE>) {
            if (/VMware ESX Server 3.5\s*$/) {
                $darch ='x86';
                $arch = 'x86';
                $distname = 'esx3.5';
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
                $distname = "esxi4";
                if ($1) {
                    $distname .= '.'.$1;
                }
                $found = 1;
                if( $arch and $arch ne $darch){
                    sendmsg([1, "Requested distribution architecture $arch, but media is $darch"]);
                    return;
                }	
                $arch = $darch;
                last;	 # we found our distro!  end this loop madness.
            }
        }
        close(LINE);
        unless($found){
            sendmsg([1,"I don't recognize this VMware ESX DVD"]);
            return; # doesn't seem to be a valid DVD or CD
        }
    } elsif (-r $path . "/vmkernel.gz" and -r $path . "/isolinux.cfg"){
        open(LINE,$path . "/isolinux.cfg");
        while (<LINE>) {
            if (/ThinESX Installer/) {
                $darch = 'x86';
                $arch='x86';
                $distname='esxi3.5';
                $found=1;
                last;
            }
        }
        close(LINE);
    }

    unless ($found) { return; } #not our media
	sendmsg("Copying media to $installroot/$distname/$arch/");
    my $omask = umask 0022;
    mkpath("$installroot/$distname/$arch");
    umask $omask;
    my $rc;
    my $reaped = 0;
    $SIG{INT} = $SIG{TERM} = sub {
        foreach(@cpiopid){
            kill 2, $_;
        }
        if ($::CDMOUNTPATH) {
            chdir("/");
            system("umount $::CDMOUNTPATH");
        }
    };
    my $KID;
    chdir $path;
    my $numFiles = `find . -print | wc -l`;
    my $child = open($KID, "|-");
    unless (defined $child)
    {
        sendmsg([1,"Media copy operation fork failure"]);
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
            sendmsg([1,"Media copy operation fork failure"]);
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
	if ($rc != 0){
        sendmsg([1,"Media copy operation failed, status $rc"]);
	}else{
	    sendmsg("Media copy operation successful");
	    my @ret=xCAT::SvrUtils->update_tables_with_templates($distname, $arch);
	    if ($ret[0] != 0) {
		sendmsg("Error when updating the osimage tables: " . $ret[1]);
	    }
	

	}
}
sub  makecustomizedmod {
    my $osver = shift;
    my $dest = shift;
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
        return 0;
    }
    mkpath("/tmp/xcat");
    my $tempdir = tempdir("/tmp/xcat/esxmodcustXXXXXXXX");
    my $shadow;
    mkpath($tempdir."/etc/");
    open($shadow,">",$tempdir."/etc/shadow");
    $password = crypt($password,'$1$'.xCAT::Utils::genpassword(8));
    my $dayssince1970 = int(time()/86400); #Be truthful about /etc/shadow
    my @otherusers = qw/nobody nfsnobody dcui daemon vimuser/;
    print $shadow "root:$password:$dayssince1970:0:99999:7:::\n";
    foreach (@otherusers) {
        print $shadow "$_:*:$dayssince1970:0:99999:7:::\n";
    }
    close($shadow);
    if (-e "$::XCATROOT/share/xcat/netboot/esxi/47.xcat-networking") {
        mkpath($tempdir."/etc/vmware/init/init.d");
        copy( "$::XCATROOT/share/xcat/netboot/esxi/47.xcat-networking",$tempdir."/etc/vmware/init/init.d/47.xcat-networking");
    }
    #TODO: auto-enable ssh and request boot-time customization rather than on-demand?
    require Cwd;
    my $dir=Cwd::cwd();
    chdir($tempdir);
    if (-e "$dest/mod.tgz") {
        unlink("$dest/mod.tgz");
    }
    system("tar czf $dest/mod.tgz *");
    chdir($dir);
    rmtree($tempdir);
    return 1;
}
sub mknetboot {
	my $req      = shift;
	my $doreq    = shift;
	my $tftpdir  = "/tftpboot";
	my @nodes    = @{$req->{node}};
	my $ostab    = xCAT::Table->new('nodetype');
	my $sitetab  = xCAT::Table->new('site');
	my $bptab		 = xCAT::Table->new('bootparams',-create=>1);
	my $installroot = "/install";
	if ($sitetab){
		(my $ref) = $sitetab->getAttribs({key => 'installdir'}, 'value');
		if ($ref and $ref->{value}) {
			$installroot = $ref->{value};
		}
		($ref) = $sitetab->getAttribs({key => 'tftpdir'}, 'value');
		if ($ref and $ref->{value}) {
			$tftpdir = $ref->{value};
		}
	}
	my %donetftp=();

	my $bpadds = $bptab->getNodesAttribs(\@nodes,['addkcmdline']);
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


	foreach my $node (@nodes){
		my $ent =  $ostab->getNodeAttribs($node, ['os', 'arch', 'profile']);
		my $arch = $ent->{'arch'};
		my $profile = $ent->{'profile'};
		my $osver = $ent->{'os'};
		#if($arch ne 'x86'){	
		#	sendmsg([1,"VMware ESX hypervisors are x86, please change the nodetype.arch value to x86 instead of $arch for $node before proceeding:
        #e.g: nodech $node nodetype.arch=x86\n"]);
		#	return;
		#}
		# first make sure copycds was done:
        my $custprofpath = $profile;
        unless ($custprofpath =~ /^\//) {#If profile begins with a /, assume it already is a path
            $custprofpath = $installroot."/custom/install/esxi/$arch/$profile";
        }
		unless(
            -r "$custprofpath/vmkboot.gz"
			or	-r "$installroot/$osver/$arch/mboot.c32"
			or -r "$installroot/$osver/$arch/install.tgz" ){
			sendmsg([1,"Please run copycds first for $osver or create custom image in $custprofpath/"]);
		}

		mkpath("$tftpdir/xcat/netboot/$osver/$arch/");
        my @reqmods = qw/vmkboot.gz vmk.gz sys.vgz cim.vgz/; #Required modules for an image to be considered complete
        my %mods;
        foreach (@reqmods) {
            $mods{$_} = 1;
        }
        my $shortprofname = $profile;
        $shortprofname =~ s/\/\z//;
        $shortprofname =~ s/.*\///;
		unless($donetftp{$osver,$arch}) {
			my $srcdir = "$installroot/$osver/$arch";
			my $dest = "$tftpdir/xcat/netboot/$osver/$arch/$shortprofname";
			cpNetbootImages($osver,$srcdir,$dest,$custprofpath,\%mods);
            if (makecustomizedmod($osver,$dest)) {
                push @reqmods,"mod.tgz";
                $mods{"mod.tgz"}=1;
            }
            if (-r "$::XCATROOT/share/xcat/netboot/syslinux/mboot.c32") { #prefer xCAT patched mboot.c32 with BOOTIF for mboot
			    copy("$::XCATROOT/share/xcat/netboot/syslinux/mboot.c32", $dest);
            } else {
			    copy("$srcdir/mboot.c32", $dest);
            }
			$donetftp{$osver,$arch,$profile} = 1;
		}
		my $tp = "xcat/netboot/$osver/$arch/$shortprofname";
        my $bail=0;
        foreach (@reqmods) {
            unless (-r "$tftpdir/$tp/$_") { 
                sendmsg([1,"$_ is missing from the target destination, ensure that either copycds has been run or that $custprofpath contains this file"]);
                $bail=1; #only flag to bail, present as many messages as possible to user
            }
        }
        if ($bail) { #if the above loop detected one or more failures, bail out
           return;
        }
		# now make <HEX> file entry stuff
		my $kernel = "$tp/mboot.c32";
		my $prepend = "$tp/vmkboot.gz";
        delete $mods{"vmkboot.gz"};
		my $append = " --- $tp/vmk.gz";
        delete $mods{"vmk.gz"};
		$append .= " --- $tp/sys.vgz";
        delete $mods{"sys.vgz"};
		$append .= " --- $tp/cim.vgz";
        delete $mods{"cim.vgz"};
        if ($mods{"mod.tgz"}) {
		    $append .= " --- $tp/mod.tgz";
            delete $mods{"mod.tgz"};
        }
        foreach (keys %mods) {
            $append .= " --- $tp/$_";
        }
		if (defined $bpadds->{$node}->[0]->{addkcmdline}) {
            my $modules;
            my $kcmdline;
            ($kcmdline,$modules) = split /---/,$bpadds->{$node}->[0]->{addkcmdline},2;
            $kcmdline =~ s/#NODEATTRIB:([^:#]+):([^:#]+)#/$nodesubdata{$1}->{$node}->[0]->{$2}/eg;
            if ($modules) {
                $append .= " --- ".$modules;
            }
            $prepend .= " ".$kcmdline;
		}
        $append = $prepend.$append;
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
            sendmsg("extracting netboot files from OS image.  This may take about a minute or two...hopefully you have ~1GB free in your /tmp dir\n");
            my $cmd = "tar zxvf $srcDir/image.tgz";
            print "\n$cmd\n";
            if(system("tar zxf $srcDir/image.tgz")){
                sendmsg([1,"Unable to extract $srcDir/image.tgz\n"]); 
            }
            # this has the big image and may take a while.
            # this should now create:
            # /tmp/xcat.1234/usr/lib/vmware/installer/VMware-VMvisor-big-164009-x86_64.dd.bz2 or some other version.  We need to extract partition 5 from it.
            system("bunzip2 $tmpDir/usr/lib/vmware/installer/*bz2");
            sendmsg("finished extracting, now copying files...\n");
	
            # now we need to get partition 5 which has the installation goods in it.
            my $scmd = "fdisk -lu $tmpDir/usr/lib/vmware/installer/*dd 2>&1 | grep dd5 | awk '{print \$2}'";
            print "running: $scmd\n";
            my $sector = `$scmd`;
            chomp($sector);
            my $offset = $sector * 512;
            mkdir "/mnt/xcat";
            my $mntcmd = "mount $tmpDir/usr/lib/vmware/installer/*dd  /mnt/xcat -o loop,offset=$offset";
            print "$mntcmd\n";
            if(system($mntcmd)){
                sendmsg([1,"unable to mount partition 5 of the ESX netboot image to /mnt/xcat"]);
                return;
            }

            if (! -d $destDir) {
                mkpath($destDir);
            }
            
            if(system("cp /mnt/xcat/* $destDir/")){
                sendmsg([1,"Could not copy netboot contents to $destDir"]);
                system("umount /mnt/xcat");
                return;
            }
            chdir("/tmp");
            system("umount /mnt/xcat");
            print "tempDir: $tmpDir\n";
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
                        copy($_,"$destDir/vmk.gz") or sendmsg([1,"Could not copy netboot contents from $_ to $destDir/$mod"]);
                    } else {
                        copy($_,"$destDir/$mod") or sendmsg([1,"Could not copy netboot contents from $_ to $destDir/$mod"]);
                    }
                }

            }
        }
        if (-d $overridedir) { #Copy over all modules 
            use File::Basename;
            foreach (glob "$overridedir/*") {
                my $mod = scalar fileparse($_);
                if ($mod =~ /gz\z/ and $mod !~ /pkgdb.tgz/ and $mod !~ /vmkernel.gz/) {
                    $modulestoadd->{$mod}=1;
                    copy($_,"$destDir/$mod") or sendmsg([1,"Could not copy netboot contents from $overridedir to $destDir"]);
                } elsif ($mod =~ /vmkernel.gz/) {
                    $modulestoadd->{"vmk.gz"}=1;
                    copy($_,"$destDir/vmk.gz") or sendmsg([1,"Could not copy netboot contents from $overridedir to $destDir"]);
                }
            }
        }


	}else{
			sendmsg([1,"VMware $osver is not supported for netboot"]);
	}

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
