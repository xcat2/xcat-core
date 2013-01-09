package xCAT::IMMUtils;
use xCAT::SvrUtils qw/sendmsg/;
use xCAT::SSHInteract;
use xCAT_plugin::bmcconfig;
#For IMMs, there are a few contexts where setup is most sensibly done remotely via CLI automation, or must be done remotely.
#If slp driven discovery, this is the sensible path pretty much in all scenarios (rack and flex)
#for bmcsetup, it still makes sense for IBM Flex system servers where the server is forbidden from manipulation local authentication
#data

#setupIMM
#Arguments:
#    first argument: the nodename to be managed (*NOT* the IMM, the node managed by the IMM)
#    named arguments:
#       nodedata - structure containing miscellaneous information about the target IMM.  Currently, macaddress is the only member of interest
#       skipbmcidcheck - if true will do the ssh in even if the bmcid indicates otherwis.  remoteimmsetup context, for example, is better served with this strategy
#	skipnetconfig - if true, will not issue ifconfig type commands.  In remoteimmsetup, this is handled in the typical bmcsetup way
#	callback - function to handle getting output back to client
#	cliusername - username to use for ssh (might not match ipmi)
#	clipassword - password for cli
#	curraddr - current address (in case current address does not match intended address
# example invocation:
# xCAT::IMMUtils::setupIMM($node,nodedata=>$immdata,curraddr=>$addr,cliusername=>$user,clipassword=>$pass,callback=>$callback);

sub setupIMM {
	my $node = shift;
	my %args = @_;
	my $nodedata = $args{nodedata};
	my $callback = $args{callback};
	my $ipmitab = xCAT::Table->new('ipmi',-create=>1);
	my $ient = $ipmitab->getNodeAttribs($node,[qw/bmc bmcid/],prefetchcache=>1);
	my $ipmiauthmap = xCAT::PasswordUtils::getIPMIAuth(noderange=>[$node]);
	my $newaddr;
	if ($ient) {
		my $bmcid=$ient->{bmcid};
		if (not $args{skipbmcidcheck} and $bmcid and $nodedata->{macaddress} =~ /$bmcid/) { 
			sendmsg("The IMM has been configured (ipmi.bmcid). Skipped.",$callback, $node);
			return; 
		} #skip configuration, we already know this one
		$newaddr = $ient->{bmc};
	}
	my @ips=();
        my $autolla=0;
	if ($newaddr and not $newaddr =~ /^fe80:.*%.*/) {
		@ips = xCAT::NetworkUtils::getipaddr($newaddr,GetAllAddresses=>1);
	} else {
		if ($args{curraddr} =~ /^fe80:.*%.*/) {  #if SLP were able to glean an LLA out of this, let's just roll with that result
			$ipmitab->setNodeAttribs($node,{bmc=>$args{curraddr}});
			$autolla=1; 
		}
	}
	if (not scalar @ips and not $autolla) {
		sendmsg(":Cannot find the IP attribute for bmc",$callback,$node);
		return;
	}
        my $targips;
        my $sship = $args{curraddr};
        if (scalar(@ips)) { 
		$targips = join(',',@ips);
		unless ($sship) { $sship = $ips[0]; }
	} elsif ($autolla) {
		$targips=$args{curraddr};
	}
	sendmsg(":Configuration of ".$node."[$targips] commencing, configuration may take a few minutes to take effect",$callback);
	my $child = fork();
	if ($child) { return; }
	unless (defined $child) { die "error spawining process" }
	
	#ok, with all ip addresses in hand, time to enable IPMI and set all the ip addresses (still static only, TODO: dhcp
	my $ssh = new xCAT::SSHInteract(-username=>$args{cliusername},
					-password=>$args{clipassword},
					-host=>$sship,
					-nokeycheck=>1,
					-output_record_separator=>"\r",
					Timeout=>15,
					Errmode=>'return',
					Prompt=>'/> $/');
	if ($ssh and $ssh->atprompt) { #we are in and good to issue commands
		$ssh->cmd("accseccfg -pe 0 -rc 0 -ci 0 -lf 0 -lp 0"); #disable the more insane password rules, this isn't by and large a human used interface
		$ssh->cmd("users -1 -n ".$ipmiauthmap->{$node}->{username}." -p ".$ipmiauthmap->{$node}->{password}." -a super"); #this gets ipmi going
		unless ($args{skipnetconfig}) { 
		   foreach my $ip (@ips) {
			if ($ip =~ /:/) { 
				$ssh->cmd("ifconfig eth0 -ipv6static enable -i6 $ip");
			} else {
				(my $sip,my $mask,my $gw) = xCAT_plugin::bmcconfig::net_parms($ip);
				my $cmd = "ifconfig eth0 -c static -i $ip -s $mask";
				if ($gw) { $cmd .= " -g $gw"; }
				$ssh->cmd($cmd);
			}
		   }
		}
		$ssh->close();
		$ipmitab->setNodeAttribs($node,{bmcid=>$nodedata->{macaddress}});
	}
	exit(0);
}

1;
