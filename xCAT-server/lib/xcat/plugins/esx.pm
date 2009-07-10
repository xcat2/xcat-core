package xCAT_plugin::esx;

use strict;
use warnings;
use xCAT::Table;
use xCAT::Utils;
use Time::HiRes qw (sleep);
use xCAT::MsgUtils;
use xCAT::Common;
use xCAT::VMCommon;
use POSIX "WNOHANG";
use Getopt::Long;
use Thread qw(yield);
use POSIX qw(WNOHANG nice);
use File::Path;
use File::Temp qw/tempdir/;
use File::Copy;
use IO::Socket; #Need name resolution
use Data::Dumper;
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
my %running_tasks; #A struct to track this processes
my $output_handler; #Pointer to the function to drive results to client
my $executerequest;
my %tablecfg; #to hold the tables
my $currkey;


my %guestidmap = (
    "rhel.5.*" => "rhel5_",
    "rhel4.*" => "rhel4_",
    "centos5.*" => "rhel5_",
    "centos4.*" => "rhel4_",
    "sles11.*" => "sles11_",
    "sles10.*" => "sles10_",
    "win2k8" => "winLonghorn",
    "win2k8r2" => "windows7Server",
    "win2k3" => "winNetStardard"
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
		lsvm => 'nodehm:mgt',
	};
}

#CANDIDATE FOR COMMON CODE
sub getMacAddresses {
    my $node = shift;
    my $count = shift;
    my $macdata = $tablecfg{mac}->{$node}->[0]->{mac};
    unless ($macdata) { $macdata ="" }
    my @macs;
    my $macaddr;
    foreach $macaddr (split /\|/,$macdata) {
         $macaddr =~ s/\!.*//;
         push @macs,lc($macaddr);
    }
    $count-=scalar(@macs);
    my $updatesneeded=0;
    if ($count > 0) {
        $updatesneeded = 1;
    }

    while ($count > 0) { #still need more, autogen
        $macaddr = "";
        while (not $macaddr) {
            $macaddr = lc(genMac($node));
            if ($tablecfg{usedmacs}->{$macaddr}) {
                $macaddr = "";
            }
        }
        $count--;
        $tablecfg{usedmacs}->{$macaddr} = 1;
        if (not $macdata) {
            $macdata = $macaddr;
        } else {
            $macdata .= "|".$macaddr;
        }
        push @macs,$macaddr;
    }
    if ($updatesneeded) {
        my $mactab = xCAT::Table->new('mac',-create=>1);
        $mactab->setNodeAttribs($node,{mac=>$macdata});
        $tablecfg{dhcpneeded}->{$node}=1; #at our leisure, this dhcp binding should be updated
    }
    return @macs;
#    $cfghash->{usedmacs}-{lc{$mac}};

}

sub genMac { #Generates a mac address for a node
    my $node=shift;
    my $allbutmult = 0xfeff; # to & with a number to ensure multicast bit is *not* set
    my $locallyadministered = 0x200; # to | with the 16 MSBs to indicate a local mac
    my $leading = int(rand(0xffff));
    $leading = $leading & $allbutmult;
    $leading = $leading | $locallyadministered;
    #If this nodename is a resolvable name, we'll use that for the other 32 bits
    my $low32;
    my $n;
    if ($n = inet_aton($node)) {
        $low32= unpack("N",$n);
    }
    unless ($low32) { #If that failed, just do 32 psuedo-random bits
        $low32 = int(rand(0xffffffff));
    }
    my $mac;
    $mac = sprintf("%04x%08x",$leading,$low32);
    $mac =~s/(..)(..)(..)(..)(..)(..)/$1:$2:$3:$4:$5:$6/;
    return $mac;

}




sub preprocess_request {
	my $request = shift;
	my $callback = shift;
    my $username = 'root';
    my $password = '';
    my $vusername = "Administrator";
    my $vpassword = "";

    xCAT::Common::usage_noderange($request,$callback);
    unless ($request) { return; }

	if ($request->{command}->[0] eq 'copycd')
	{    #don't farm out copycd
		return [$request];
	}elsif($request->{command}->[0] eq 'mknetboot'){
		return [$request];
	}

	if ($request->{_xcatdest}) { return [$request]; }    #exit if preprocessed
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

	# find service nodes for the MMs
	# build an individual request for each service node
	my $service  = "xcat";
	my @hyps=keys(%hyp_hash);
    if ($command eq 'rmigrate') {
        my $dsthyp = $extraargs->[0];
        push @hyps,$dsthyp;
    }
    #TODO: per hypervisor table password lookup
	my $sn = xCAT::Utils->get_ServiceNode(\@hyps, $service, "MN");
    $vmtabhash = $vmtab->getNodesAttribs(\@hyps,['host']);

	# build each request for each service node
	foreach my $snkey (keys %$sn){
		my $reqcopy = {%$request};
		$reqcopy->{'_xcatdest'} = $snkey;
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
            if (defined $vmtabhash->{$_}->[0]->{host}) {
                $cfgdata .= "[". $vmtabhash->{$_}->[0]->{host}."]";
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
    my $vmwaresdkdetect = eval {
        require VMware::VIRuntime;
        VMware::VIRuntime->import();
        1;
    };
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
			my $node = $nodes[$i];
			#my $nodeid = $ids[$i];
			$hyphash{$hyp}->{nodes}->{$node}=1;# $nodeid;
		}
	}

	#my $children = 0;
    #my $vmmaxp = 84;
	#$SIG{CHLD} = sub { my $cpid; while ($cpid = waitpid(-1, WNOHANG) > 0) { delete $esx_comm_pids{$cpid}; $children--; } };
    my $viavcenter = 0;
    if ($command eq 'rmigrate') { #Only use vcenter when required, fewer prereqs
        $viavcenter = 1;
    }
    my $keytab = xCAT::Table->new('prodkey');
    if ($keytab) {
        my @hypes = keys %hyphash;
        $tablecfg{prodkey} = $keytab->getNodesAttribs(\@hypes,[qw/product key/]);
    }
	foreach my $hyp (sort(keys %hyphash)){
		#if($pid == 0){
        if ($viavcenter) {
            my $vcenter = $hyphash{$hyp}->{vcenter}->{name};
            unless ($vcenterhash{$vcenter}->{conn}) {
                $vcenterhash{$vcenter}->{conn} =
                    Vim->new(service_url=>"https://$vcenter/sdk");
                $vcenterhash{$vcenter}->{conn}->login(
                            user_name => $hyphash{$hyp}->{vcenter}->{username},
                            password => $hyphash{$hyp}->{vcenter}->{password}
                            );
            }
            $hyphash{$hyp}->{conn} = $vcenterhash{$hyphash{$hyp}->{vcenter}->{name}}->{conn};
            $hyphash{$hyp}->{vcenter}->{conn} = $vcenterhash{$hyphash{$hyp}->{vcenter}->{name}}->{conn};
        } else {
            $hyphash{$hyp}->{conn} = Vim->new(service_url=>"https://$hyp/sdk");
            $hyphash{$hyp}->{conn}->login(user_name=>$hyphash{$hyp}->{username},password=>$hyphash{$hyp}->{password});
            validate_licenses($hyp);
        }
		#}else{
		#	$esx_comm_pids{$pid} = 1;
		#}
	}
    do_cmd($command,@exargs);
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
        if ($_->{product} eq 'esx') {
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
        generic_vm_operation(['config.name','config','runtime.powerState'],\&power,@exargs);
    } elsif ($command eq 'rmvm') {
        generic_vm_operation(['config.name','runtime.powerState'],\&rmvm,@exargs);
    } elsif ($command eq 'rsetboot') {
        generic_vm_operation(['config.name'],\&setboot,@exargs);
    } elsif ($command eq 'mkvm') {
        generic_hyp_operation(\&mkvms,@exargs);
    } elsif ($command eq 'rmigrate') { #Technically, on a host view, but vcenter path is 'weirder'
        generic_hyp_operation(\&migrate,@exargs);
    }
    wait_for_tasks();
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
        $vcenterhash{$args->{vcenter}}->{$args->{hypname}} = 'good';
        if (defined $args->{depfun}) { #If a function is waiting for the host connect to go valid, call it
            enable_vmotion(hypname=>$args->{hypname},hostview=>$args->{hostview},conn=>$args->{conn});
            $args->{depfun}->($args->{depargs});
        }
        return;
    }
    my $thumbprint;
    eval {
        $thumbprint = $task->{info}->error->fault->thumbprint;
    };
    if ($thumbprint) {
       $args->{connspec}->{sslThumbprint}=$task->info->error->fault->thumbprint;
       my $task;
       if (defined $args->{hostview}) {#It was a reconnect request
           $task = $hv->ReconnectHost_Task(cnxSpec=>$args->{connspec});
       } elsif (defined $args->{foldview}) {#was an add host request
            $task = $args->{foldview}->AddStandaloneHost_Task(spec=>$args->{connspec},addConnected=>1);
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
        $vcenterhash{$args->{vcenter}}->{$args->{hypname}} = 'bad';
    }
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
    foreach (@{$args{conn}->find_entity_views(%subargs)}) {
       if ($_->name =~ /$host[\.\$]/ or $_->name =~ /localhost[\.\$]/) {
           return $_;
           last;
       }
    }
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

sub migrate_callback {
    my $task = shift;
    my $parms = shift;
    my $state = $task->info->state->val;
    if ($state eq 'success') {
        my $vmtab = xCAT::Table->new('vm');
        $vmtab->setNodeAttribs($parms->{node},{host=>$parms->{target}});
        sendmsg("migrated to ".$parms->{target},$parms->{node});
    } else {
        relay_vmware_err($task,"Migrating to ".$parms->{target}." ",$parms->{node});
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


sub actually_migrate {
    my %args = %{shift()};
    my @nodes = @{$args{nodes}};
    my $target = $args{target};
    my $hyp = $args{hyp};
    my $vcenter = $args{vcenter};
    if ($vcenterhash{$vcenter}->{$hyp} eq 'bad' or $vcenterhash{$vcenter}->{$target} eq 'bad') {
        sendmsg([1,"Unable to migrate ".join(',',@nodes)." to $target due to inability to validate vCenter connectivity"]);
        return;
    }
    if ($vcenterhash{$vcenter}->{$hyp} eq 'good' and $vcenterhash{$vcenter}->{$target} eq 'good') {
        unless (validate_datastore_prereqs(\@nodes,$target)) {
            sendmsg([1,"Unable to verify storage state on target system"]);
            return;
        }
        unless (validate_network_prereqs(\@nodes,$target)) {
            sendmsg([1,"Unable to verify target network state"]);
            return;
        }
        my $dstview;# = $hyphash{$target}->{conn}->find_entity_view(view_type=>'HostSystem',filter=>{'name'=>$target});
        foreach (@{$hyphash{$target}->{conn}->find_entity_views(view_type=>'HostSystem',properties=>['name','parent'])}) {
            if ($_->name =~ /$target[\.\$]/) {
                $dstview = $_;
                last;
            }
        }
        unless ($hyphash{$target}->{pool}) {
            $hyphash{$target}->{pool} = $hyphash{$target}->{conn}->get_view(mo_ref=>$dstview->parent,properties=>['resourcePool'])->resourcePool;
        }
        foreach (@nodes) {
            my $srcview = $hyphash{$hyp}->{conn}->find_entity_view(view_type=>'VirtualMachine',properties=>['config.name'],filter=>{name=>$_});
            my $task = $srcview->MigrateVM_Task(
                host=>$dstview,
                pool=>$hyphash{$target}->{pool},
                priority=>VirtualMachineMovePriority->new('highPriority'));
            $running_tasks{$task}->{task} = $task;
            $running_tasks{$task}->{callback} = \&migrate_callback;
            $running_tasks{$task}->{hyp} = $args{hyp}; 
            $running_tasks{$task}->{data} = { node => $_, target=>$target }; 
        }
    } else {
        #sendmsg("Waiting for BOTH to be 'good'");
        return; #One of them is still 'pending'
    }
}

sub migrate {
    my %args = @_;
    my $nodes = $args{nodes};
    my $hyp = $args{hyp};
    my $exargs = $args{exargs};
    my $tgthyp = $exargs->[0];
    my $destination = ${$args{exargs}}[0];
    my $vcenter = $hyphash{$hyp}->{vcenter}->{name};
#We do target first to prevent multiple sources to single destination from getting confused
#one source to multiple destinations (i.e. revacuate) may require other provisions
    validate_vcenter_prereqs($tgthyp, \&actually_migrate, {
        nodes=>$nodes,
        hyp=>$hyp,
        target=>$tgthyp,
        vcenter=>$vcenter
    });
    validate_vcenter_prereqs($hyp, \&actually_migrate, {
        nodes=>$nodes,
        hyp=>$hyp,
        target=>$tgthyp,
        vcenter=>$vcenter
    });
}

sub reconfig_callback {
    my $task = shift;
    my $args = shift;
    print Dumper($task->info);
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
    $Data::Dumper::Maxdepth=2;
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
    }
    if (not defined $args{vmview}) { 
        sendmsg([1,"VM does not appear to exist"],$node);
        return;
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
    }
    my $subcmd = ${$args{exargs}}[0];
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
                if ($currstat eq 'off') {
                    if (not $args{vmview}) { #We are asking to turn on a system the hypervisor
                        #doesn't know, attempt to register it first
                        register_vm($hyp,$node,undef,\&power,\%args);
                        return; #We'll pick it up on the retry if it gets registered
                    } 
                    eval {
                        $task = $args{vmview}->PowerOnVM_Task();
                    };
                    if ($@) {
                        sendmsg([1,":".$@],$node);
                        return;
                    }
                    $running_tasks{$task}->{task} = $task;
                    $running_tasks{$task}->{callback} = \&generic_task_callback;
                    $running_tasks{$task}->{hyp} = $args{hyp}; #$hyp_conns->{$hyp};
                    $running_tasks{$task}->{data} = { node => $node, successtext => $intent.'on' };
                } else {
                    sendmsg("on",$node);
                }
            } elsif ($subcmd =~ /off/) {
                if ($currstat eq 'on') {
                    $task = $args{vmview}->PowerOffVM_Task();
                    $running_tasks{$task}->{task} = $task;
                    $running_tasks{$task}->{callback} = \&generic_task_callback;
                    $running_tasks{$task}->{hyp} = $args{hyp}; 
                    $running_tasks{$task}->{data} = { node => $node, successtext => 'off' }; 
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
                        $task = $args{vmview}->PowerOnVM_Task();
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
    foreach $hyp (keys %hyphash) {
        my $vmviews = $hyphash{$hyp}->{conn}->find_entity_views(view_type => 'VirtualMachine',properties=>$properties);
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
#REMINDER FOR RINV TO COME
#     foreach (@nothing) { #@{$mgdvms{$node}->config->hardware->device}) {
#           if (defined $_->{macAddress}) {
#                  print "\nFound a mac: ".$_->macAddress."\n";
#               }
#           }
        }
    }
}

sub generic_hyp_operation { #The general form of firing per-hypervisor requests to ESX hypervisor
    my $function = shift; #The function to actually run against the right VM view
    my @exargs = @_; #Store the rest to pass on
    my $hyp;
    foreach $hyp (keys %hyphash) {
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
    $disksize = getUnits($disksize,'G',1024);
    my $node;
    $hyphash{$hyp}->{hostview} = $hyphash{$hyp}->{conn}->find_entity_view(view_type=>'HostSystem'); #TODO: beware of vCenter case??
    unless (validate_datastore_prereqs($nodes,$hyp)) {
        return;
    }
    $hyphash{$hyp}->{vmfolder} = $hyphash{$hyp}->{conn}->get_view(mo_ref=>$hyphash{$hyp}->{conn}->find_entity_view(view_type=>'Datacenter',properties=>['vmFolder'])->vmFolder);
    $hyphash{$hyp}->{pool} = $hyphash{$hyp}->{conn}->get_view(mo_ref=>$hyphash{$hyp}->{hostview}->parent,properties=>['resourcePool'])->resourcePool;
    my $cfg;
    foreach $node (@$nodes) {
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
    }
    my $bootorder = ${$args{exargs}}[0];
    #NOTE: VMware simply does not currently seem to allow programatically changing the boot
    #order like other virtualiazation solutions supported by xCAT.
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

    my $success = eval {
        $task = $hyphash{$hyp}->{vmfolder}->RegisterVM_Task(path=>getcfgdatastore($node,$hyphash{$hyp}->{datastoremap})." /$node/$node.vmx",name=>$node,pool=>$hyphash{$hyp}->{pool},asTemplate=>0);
    };
    if ($@ or not $success) {
        print $@;
        register_vm_callback(undef, {
            node => $node,
            disksize => $disksize,
            blockedfun => $blockedfun,
            blockedargs => $blockedargs,
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
        } else {
            sendmsg([1,"mkvm must be called before use of this function"],$args->{node});
        }
    } elsif (defined $args->{blockedfun}) { #If there is a blocked function, call it here) 
        $args->{blockedfun}->(%{$args->{blockedargs}});
    }
}
    
sub getcfgdatastore {
    my $node = shift;
    my $dses = shift;
    my $cfgdatastore = $tablecfg{vm}->{$node}->[0]->{cfgstore};
    unless ($cfgdatastore) {
        $cfgdatastore = $tablecfg{vm}->{$node}->[0]->{storage}; 
        #TODO: if multiple drives are specified, make sure to split this out
    }
    $cfgdatastore =~ s/,.*$//;
    $cfgdatastore =~ s/\/$//;
    $cfgdatastore = "[".$dses->{$cfgdatastore}."]";
    return $cfgdatastore;
}


sub mknewvm {
        my $node=shift;
        my $disksize=shift;
        my $hyp=shift;
#TODO: above
        my $cfg = build_cfgspec($node,$hyphash{$hyp}->{datastoremap},$hyphash{$hyp}->{nets},$disksize);
        my $task = $hyphash{$hyp}->{vmfolder}->CreateVM_Task(config=>$cfg,pool=>$hyphash{$hyp}->{pool});
        $running_tasks{$task}->{task} = $task;
        $running_tasks{$task}->{callback} = \&mkvm_callback;
        $running_tasks{$task}->{hyp} = $hyp;
        $running_tasks{$task}->{data} = { node => $node };
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
        if ($nodeos =~ /$_/) {
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
        if ($nodearch eq 'x86_64') {
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
    push @devices,create_nic_devs($node,$netmap);
    my $cfgdatastore = $tablecfg{vm}->{$node}->[0]->{storage}; #TODO: need a new cfglocation field in case of stateless guest?
    $cfgdatastore =~ s/,.*$//;
    $cfgdatastore =~ s/\/$//;
    $cfgdatastore = "[".$dses->{$cfgdatastore}."]";
    my $vfiles = VirtualMachineFileInfo->new(vmPathName=>$cfgdatastore);
    #my $nodeos = $tablecfg{nodetype}->{$node}->[0]->{os};
    #my $nodearch = $tablecfg{nodetype}->{$node}->[0]->{arch};
    my $nodeos = getguestid($node); #nodeos=>$nodeos,nodearch=>$nodearch);


    return VirtualMachineConfigSpec->new(
            name => $node,
            files => $vfiles,
            guestId=>$nodeos,
            memoryMB => $memory,
            numCPUs => $ncpus,
            deviceChange => \@devices,
        );
}

sub create_nic_devs {
    my $node = shift;
    my $netmap = shift;
    my @networks = split /,/,$tablecfg{vm}->{$node}->[0]->{nics};
    my @devs;
    my $idx = 0;
    my @macs = getMacAddresses($node,scalar @networks);
    my $connprefs=VirtualDeviceConnectInfo->new(
                            allowGuestControl=>1,
                            connected=>0,
                            startConnected => 1
                            );
    foreach (@networks) {
        s/.*://;
        s/=.*//;
        my $netname = $_;
        my $backing = VirtualEthernetCardNetworkBackingInfo->new(
            network => $netmap->{$netname},
            deviceName=>$netname,
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
    my $size = shift;
    my $scsicontrollerkey=0;
    my $idecontrollerkey=200; #IDE 'controllers' exist at 200 and 201 invariably, with no flexibility?
                              #Cannot find documentation that declares this absolute, but attempts to do otherwise
                              #lead in failure, also of note, these are single-channel controllers, so two devs per controller

    my $backingif;
    my @devs;
    my $havescsidevs =0;
    my $disktype = 'ide';
    my $unitnum=0; #Going to make IDE controllers for now, aiming for
                   #lowest common denominator guest driver for 
                   #changing hypervisor technology
    my %disktocont;
    my $dev;
    foreach (split /,/,$tablecfg{vm}->{$node}->[0]->{storage}) {
        s/\/$//;
        $backingif = VirtualDiskFlatVer2BackingInfo->new(diskMode => 'persistent',
                                                           fileName => "[".$sdmap->{$_}."]");
        if ($disktype eq 'ide' and $idecontrollerkey eq 1 and $unitnum eq 0) { #reserve a spot for CD
            $unitnum = 1;
        } elsif ($disktype eq 'ide' and $unitnum eq 2) { #go from current to next ide 'controller'
            $idecontrollerkey++;
            $unitnum=0;
        }
        push @{$disktocont{$idecontrollerkey}},$currkey;
        my $controllerkey;
        if ($disktype eq 'ide') {
            $controllerkey = $idecontrollerkey;
        } else {
            $controllerkey = $scsicontrollerkey;
        }

        $dev =VirtualDisk->new(backing=>$backingif,
                        controllerKey => $idecontrollerkey,
                        key => $currkey++,
                        unitNumber => $unitnum++,
                        capacityInKB => $size); 
        push @devs,VirtualDeviceConfigSpec->new(device => $dev,
                                                fileOperation => VirtualDeviceConfigSpecFileOperation->new('create'),
                                                operation =>  VirtualDeviceConfigSpecOperation->new('add'));
    }
    #It *seems* that IDE controllers are not subject to require creation, so we skip it
    if ($havescsidevs) { #need controllers to attach the disks to
        foreach(0..$scsicontrollerkey) {
            $dev=VirtualLsiLogicController->new(key => $_,
                                                device => \@{$disktocont{$_}},
#                                                sharedBus => VirtualSCSISharing->new('noSharing'),
                                                busNumber => $_);
            push @devs,VirtualDeviceConfigSpec->new(device => $dev,
                                                operation =>  VirtualDeviceConfigSpecOperation->new('add'));
                                                 
        }
    }
    return  @devs;
#    my $ctlr = VirtualIDEController->new(
}

sub validate_vcenter_prereqs { #Communicate with vCenter and ensure this host is added correctly to a vCenter instance when an operation requires it
    my $hyp = shift;
    my $depfun = shift;
    my $depargs = shift;
    my $vcenter = $hyphash{$hyp}->{vcenter}->{name};
    unless ($hyphash{$hyp}->{vcenter}->{conn}) {
        $hyphash{$hyp}->{vcenter}->{conn} = Vim->new(service_url=>"https://$vcenter/sdk");
        $hyphash{$hyp}->{vcenter}->{conn}->login(user_name=>$hyphash{$hyp}->{vcenter}->{username},password=>$hyphash{$hyp}->{vcenter}->{password});
    }
    unless ($hyphash{$hyp}->{vcenter}->{conn}) {
        sendmsg([1,": Unable to reach vCenter server managing $hyp"]);
        return undef;
    }


    my $foundhyp;
    my $connspec = HostConnectSpec->new(
        hostName=>$hyp,
        password=>$hyphash{$hyp}->{password},
        userName=>$hyphash{$hyp}->{username},
        force=>1,
        );
    foreach  (@{$hyphash{$hyp}->{vcenter}->{conn}->find_entity_views(view_type=>'HostSystem',properties=>['summary.config.name','summary.runtime.connectionState','runtime.inMaintenanceMode','parent','configManager'])}) {
        if ($_->{'summary.config.name'} =~ /^$hyp[\.\$]/) { #Looks good, call the dependent function after declaring the state of vcenter to hypervisor as good
            if ($_->{'summary.runtime.connectionState'}->val eq 'connected') {
                enable_vmotion(hypname=>$hyp,hostview=>$_,conn=>$hyphash{$hyp}->{vcenter}->{conn});
                $vcenterhash{$vcenter}->{$hyp} = 'good';
                $depfun->($depargs);
                return 1;
            } else {
                my $task = $hyphash{$hyp}->{vcenter}->{conn}->get_view(mo_ref=>$_->parent)->Destroy_Task();
                $running_tasks{$task}->{task} = $task;
                $running_tasks{$task}->{callback} = \&addhosttovcenter;
                $running_tasks{$task}->{conn} = $hyphash{$hyp}->{vcenter}->{conn};
                $running_tasks{$task}->{data} = { depfun => $depfun, depargs => $depargs, conn=>  $hyphash{$hyp}->{vcenter}->{conn}, connspec=>$connspec,hostview=>$_,hypname=>$hyp,vcenter=>$vcenter };
                return undef;
#The rest would be shorter/ideal, but seems to be confused a lot by stateless
#Maybe in a future VMWare technology level the following would work better
#than it does today
#               my $task = $_->ReconnectHost_Task(cnxSpec=>$connspec);
#               my $task = $_->DisconnectHost_Task();
#               $running_tasks{$task}->{task} = $task;
#               $running_tasks{$task}->{callback} = \&disconnecthost_callback;
#               $running_tasks{$task}->{conn} = $hyphash{$hyp}->{vcenter}->{conn};
#               $running_tasks{$task}->{data} = { depfun => $depfun, depargs => $depargs, conn=>  $hyphash{$hyp}->{vcenter}->{conn}, connspec=>$connspec,hostview=>$_,hypname=>$hyp,vcenter=>$vcenter };
#ADDHOST
            }
            last;
        }
    }
    #If still in function, haven't found any likely host entries, make a new one
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
    my $hfolder =  $hyphash{$hyp}->{vcenter}->{conn}->find_entity_view(view_type=>'Datacenter',properties=>['hostFolder'])->hostFolder;
    $hfolder = $hyphash{$hyp}->{vcenter}->{conn}->get_view(mo_ref=>$hfolder);
    $task = $hfolder->AddStandaloneHost_Task(spec=>$connspec,addConnected=>1);
    $running_tasks{$task}->{task} = $task;
    $running_tasks{$task}->{callback} = \&connecthost_callback;
    $running_tasks{$task}->{conn} = $hyphash{$hyp}->{vcenter}->{conn};
    $running_tasks{$task}->{data} = { depfun => $depfun, depargs=> $depargs, conn=>  $hyphash{$hyp}->{vcenter}->{conn}, connspec=>$connspec, foldview=>$hfolder, hypname=>$hyp, vcenter=>$vcenter };

    #print Dumper @{$hyphash{$hyp}->{vcenter}->{conn}->find_entity_views(view_type=>'HostSystem',properties=>['runtime.connectionState'])};
}


sub validate_network_prereqs {
    my $nodes = shift;
    my $hyp  = shift;
    my $hypconn = $hyphash{$hyp}->{conn};
    my $hostview = $hyphash{$hyp}->{hostview};
    if ($hostview) {
        $hostview->update_view_data(); #pull in changes induced by previous activity
    } else {
        $hyphash{$hyp}->{hostview} = $hyphash{$hyp}->{hostview} = $hyphash{$hyp}->{conn}->find_entity_view(view_type=>'HostSystem'); #TODO: beware of vCenter case??
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
            my $switchname = 'vSwitch0'; #TODO: more than just vSwitch0
            s/=.*//; #TODO specify nic model with <blahe>=model
            s/.*://; #TODO: support specifiying physical ports with :
            my $netname = $_;
            my $netsys;
            my $policy = HostNetworkPolicy->new();
            unless ($hyphash{$hyp}->{nets}->{$netname}) {
                my $vlanid;
                if ($netname =~ /trunk/) {
                    $vlanid=4095;
                } elsif ($netname =~ /vl(an)?(\d+)$/) {
                    $vlanid=$2;
                } else {
                    $vlanid = 0;
                }
                my $hostgroupdef = HostPortGroupSpec->new(
                    name =>$netname,
                    vlanId=>$vlanid,
                    policy=>$policy,
                    vswitchName=>$switchname
                    );
                unless ($netsys) {
                    $netsys = $hyphash{$hyp}->{conn}->get_view(mo_ref=>$hostview->configManager->networkSystem);
                }
                $netsys->AddPortGroup(portgrp=>$hostgroupdef);
                #$hyphash{$hyp}->{nets}->{$netname}=1;
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
    return 1;

}
sub validate_datastore_prereqs {
    my $nodes = shift;
    my $hyp = shift;
    my $hypconn = $hyphash{$hyp}->{conn};
    my $hostview = $hyphash{$hyp}->{hostview};
    unless ($hostview) {
        #$hyphash{$hyp}->{hostview} = $hyphash{$hyp}->{hostview} = $hyphash{$hyp}->{conn}->find_entity_view(view_type=>'HostSystem'); #TODO: beware of vCenter case??
        foreach  (@{$hyphash{$hyp}->{conn}->find_entity_views(view_type=>'HostSystem')}) {
            if ($_->name =~ /$hyp[\.\$]/) {
                 $hyphash{$hyp}->{hostview} = $_;
                 last;
            }
        }
        $hostview = $hyphash{$hyp}->{hostview};
    }
    my $node;
    my $method;
    my $location;
    if (defined $hostview->{datastore}) { # only iterate if it exists
        foreach (@{$hostview->datastore}) {
            my $dsv = $hypconn->get_view(mo_ref=>$_);
            if (defined $dsv->info->{nas}) {
                if ($dsv->info->nas->type eq 'NFS') {
                    $hyphash{$hyp}->{datastoremap}->{"nfs://".$dsv->info->nas->remoteHost.$dsv->info->nas->remotePath}=$dsv->info->name;
                } #TODO: care about SMB
            } #TODO: care about VMFS
        }
    }
    foreach $node (@$nodes) {
        my @storage = split /,/,$tablecfg{vm}->{$node}->[0]->{storage};
        foreach (@storage) {
            s/\/$//; #Strip trailing slash if specified, to align to VMware semantics
            if (/:\/\//) {
                ($method,$location) = split /:\/\//,$_,2;
                unless ($method =~ /nfs/) {
                    sendmsg([1,": $method is unsupported at this time (nfs would be)"],$node);
                    return 0;
                }
                unless ($hyphash{$hyp}->{datastoremap}->{$_}) { #If not already there, must mount it
                    $hyphash{$hyp}->{datastoremap}->{$_}=mount_nfs_datastore($hostview,$location);
                }
            } else {
                sendmsg([1,": $_ not supported storage specification for ESX plugin, 'nfs://<server>/<path>' only currently supported vm.storage supported for ESX at the moment"],$node);
                return 0;
            } #TODO: raw device mapping, VMFS via iSCSI, VMFS via FC?
        }
    }
    return 1;
}

sub mount_nfs_datastore {
    my $hostview = shift;
    my $location = shift;
    my $server;
    my $path;
    ($server,$path) = split /\//,$location,2;
    $location =~ s/\//_/g;
    $location= 'nfs_'.$location;
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
        

    my $nds = HostNasVolumeSpec->new(accessMode=>'readWrite',
                                    remoteHost=>$server,
                                    localPath=>$location,
                                    remotePath=>"/".$path);
    my $dsmv = $hostview->{vim}->get_view(mo_ref=>$hostview->configManager->datastoreSystem);
    $dsmv->CreateNasDatastore(spec=>$nds);
    return $location;
}
sub lsvm {
	my $hyp = shift;
	my $hyphash = shift;
	my $callback = shift;
	my ($node,$img, $imgname, $out);
	my $f1 = `ssh $hyp "ls /vmfs/volumes/images/"`;
 	$callback->({data=>[$f1]});
}


sub mkvm {
	my $mpa = shift;
	my $mpahash = shift;
	my $callback = shift;
	my ($node,$img, $imgname, $out);
	# get console
	my $nodehmtab = xCAT::Table->new("nodehm");
	# get os
	my $nodetypetab = xCAT::Table->new("nodetype");
	# get mac address
	my $mactab = xCAT::Table->new("mac");
	unless ($nodehmtab) {
   	$callback->({data=>["Cannot open nodehm table"]});
 	}
	unless ($nodetypetab) {
		$callback->({data=>["Cannot open nodetype table"]});
	}
	unless ($mactab) {
		$callback->({data=>["Cannot open mac table"]});
	}


	
	foreach $node (sort (keys %{$mpahash->{$mpa}->{nodes}})){
		my $vncEnt=$nodehmtab->getNodeAttribs($node,['termport']);
		# the comment is where we put the network name (ANodes,BNodes,CNodes)
		my $osEnt=$nodetypetab->getNodeAttribs($node,['profile' ,'os','comments']);
		my $mac=$mactab->getNodeAttribs($node,['mac']);
		my $file = "/install/autoinst/$node";
		my $targetdir = "/vmfs/volumes/images/$node";
		open(FH, ">$file") or die "Can't open $file for writing!\n";
		print FH <<	"EOF";
#!/bin/sh
mkdir -p $targetdir
cat > $targetdir/$node.vmx <<END
guestOS = "$osEnt->{os}"
config.version = "8"
virtualHW.version = "4"
displayName = "$node"
scsi0.present = "true"
scsi0.sharedBus = "none"
scsi0.virtualDev = "lsilogic"
scsi0:0.present = "true"
scsi0:0.fileName = "$node.vmdk"
scsi0:0.deviceType = "scsi-hardDisk"
memsize = "128"
ethernet0.present = "true"
ethernet0.allowGuestConnectionControl = "false"
ethernet0.networkName = "$osEnt->{comments}"
ethernet0.address = "$mac->{mac}"
ethernet0.addressType = "static"
remoteDisplay.vnc.enabled = "true"
remoteDisplay.vnc.port = "$vncEnt->{termport}"
END

vmkfstools -i /install/$osEnt->{os}/$osEnt->{profile} $targetdir/$node.vmdk
vmware-cmd -s register $targetdir/$node.vmx

EOF
	close(FH);	
	system("chmod 755 $file");
	`ssh $mpa $file`;
	}
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
            if($line =~ /VMware ESXi version 4.0.0/){
                $darch = "x86";
                $distname = "esxi4";
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
	}
}
sub  makecustomizedmod {
    my $osver = shift;
    my $dest = shift;
    mkpath("/tmp/xcat");
    my $tempdir = tempdir("/tmp/xcat/esxmodcustXXXXXXXX");
    my $shadow;
    mkpath($tempdir."/etc/");
    open($shadow,">",$tempdir."/etc/shadow");
    my $passtab = xCAT::Table->new('passwd');
    my $tmp;
    my $password;
    if ($passtab) {
        ($tmp) = $passtab->getAttribs({'key'=>'vmware'},'username','password');
        if (defined($tmp)) {
            $password = $tmp->{password};
        }
    }
    $password = crypt($password,'$1$'.xCAT::Utils::genpassword(8));
    my $dayssince1970 = int(time()/86400); #Be truthful about /etc/shadow
    my @otherusers = qw/nobody nfsnobody dcui daemon vimuser/;
    print $shadow "root:$password:$dayssince1970:0:99999:7:::\n";
    foreach (@otherusers) {
        print $shadow "$_:*:$dayssince1970:0:99999:7:::\n";
    }
    close($shadow);
    require Cwd;
    my $dir=Cwd::cwd();
    chdir($tempdir);
    if (-e "$dest/mod.tgz") {
        unlink("$dest/mod.tgz");
    }
    system("tar czf $dest/mod.tgz *");
    chdir($dir);
    rmtree($tempdir);
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

	foreach my $node (@nodes){
		my $ent =  $ostab->getNodeAttribs($node, ['os', 'arch', 'profile']);
		my $arch = $ent->{'arch'};
		my $profile = $ent->{'profile'};
		my $osver = $ent->{'os'};
		if($arch ne 'x86'){	
			sendmsg([1,"VMware ESX hypervisors are x86, please change the nodetype.arch value to x86 instead of $arch for $node before proceeding:
e.g: nodech $node nodetype.arch=x86\n"]);
			return;
		}
		# first make sure copycds was done:
		unless(
				-r "$installroot/$osver/$arch/mboot.c32"
			or -r "$installroot/$osver/$arch/install.tgz" ){
			sendmsg([1,"Please run copycds first for $osver"]);
		}

		mkpath("$tftpdir/xcat/netboot/$osver/$arch/");
		unless($donetftp{$osver,$arch}) {
			my $srcdir = "$installroot/$osver/$arch";
			my $dest = "$tftpdir/xcat/netboot/$osver/$arch";
			cpNetbootImages($osver,$srcdir,$dest);
            makecustomizedmod($osver,$dest);
			copy("$srcdir/mboot.c32", $dest);
			$donetftp{$osver,$arch,$profile} = 1;
		}
		# now make <HEX> file entry stuff
		my $tp = "xcat/netboot/$osver/$arch";
		my $kernel = "$tp/mboot.c32";
		my $append = "$tp/vmkboot.gz";
		$append .= " --- $tp/vmk.gz";
		$append .= " --- $tp/sys.vgz";
		$append .= " --- $tp/cim.vgz";
		$append .= " --- $tp/oem.tgz";
		$append .= " --- $tp/license.tgz";
		$append .= " --- $tp/mod.tgz";

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
	my $tmpDir = "/tmp/xcat.$$";
	if($osver =~ /esxi4/){
		# we don't want to go through this all the time, so if its already
		# there we're not going to extract:
		if(   -r "$destDir/vmk.gz" 
			and -r "$destDir/vmkboot.gz"
			and -r "$destDir/sys.vgz"
			and -r "$destDir/license.tgz"
			and -r "$destDir/oem.tgz"
			and -r "$destDir/pkgdb.tgz"
			and -r "$destDir/cim.vgz"
			and -r "$destDir/cimstg.tgz"
			and -r "$destDir/boot.cfg"
		){
			# files already copied don't need to replace.
            sendmsg("images ready in $destDir");
			return;
		}
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
		
		if(system("cp /mnt/xcat/* $destDir/")){
			sendmsg([1,"Could not copy netboot contents to $destDir"]);
			system("umount /mnt/xcat");
			return;
		}
		chdir("/tmp");
		system("umount /mnt/xcat");
		print "tempDir: $tmpDir\n";
		system("rm -rf $tmpDir");
	}else{
			sendmsg([1,"VMware $osver is not supported for netboot"]);
	}

}


1;
