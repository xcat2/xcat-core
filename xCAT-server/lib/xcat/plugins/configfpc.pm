# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::configfpc;

BEGIN
{
	$::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use strict;
use lib "$::XCATROOT/lib/perl";
use xCAT::Utils;
use xCAT::MsgUtils;
use xCAT::SvrUtils;
use Sys::Hostname;
use xCAT::Table;
use xCAT::TableUtils;
use xCAT::NetworkUtils;
#use Data::Dumper;
use xCAT::MacMap;
use Socket;
use Net::Ping;
my $interface;

##########################################################################
## Command handler method from tables
###########################################################################
sub handled_commands {
	return {
		configfpc => "configfpc",
	};
}


#sub preprocess_request {

    #   set management node as server for all requests
    #   any requests sent to service node need to get
    #   get sent up to the MN

    #my $req = shift;
     ##if already preprocessed, go straight to request
    #if (   (defined($req->{_xcatpreprocessed}))
        #&& ($req->{_xcatpreprocessed}->[0] == 1))
    #{
        #return [$req];
    #}
#
    #$req->{_xcatdest} = xCAT::TableUtils->get_site_Master();
    #return [$req];
#}



sub process_request {
	my $request  = shift;
	my $callback = shift;
	my $subreq = shift;
	#my $subreq = $request->{command};
 	
	$::CALLBACK = $callback;

	if ($request && $request->{arg}) { @ARGV = @{$request->{arg}}; }
	else { @ARGV = (); }

	Getopt::Long::Configure( "bundling", "no_ignore_case", "no_pass_through" );
	my $getopt_success = Getopt::Long::GetOptions(
		'help|h|?'  => \$::opt_h,
		'i|I=s' => \$::opt_I,
		'verbose|V' => \$::opt_V,
	);

	# Option -h for Help
	if ( defined($::opt_h) || (!$getopt_success) ) {
        	&configfpc_usage;
		return 0;
            }

	if ( (!$::opt_I) ) {   # missing required option - msg and return
		my $rsp;
		push @{ $rsp->{data} }, "Missing required option -i <adapter_interface> \n";
		xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
        	&configfpc_usage;
		return 0;
	}

	# Option -V for verbose output
	if ( defined($::opt_V) ) {
		$::VERBOSE=$::opt_V;
	}

	# Option -i for kit component attributes
	if ( defined($::opt_I) ) {
		$interface = $::opt_I;
	} 

	my $command       = $request->{command}->[0];
	my $localhostname = hostname();

	if ($command eq "configfpc")
	{
	my $rc;
    		$rc = configfpc($request, $callback, $subreq);
	}
	else
	{
		my $rsp;
		push @{ $rsp->{data} }, "$localhostname: Unsupported command: $command";
		xCAT::MsgUtils->message( "I", $rsp, $callback );
		return 1;
	}

return 0;
}

sub configfpc_usage {
    my $rsp;
    push @{ $rsp->{data} },
      "\nUsage: configfpc - Configure the NeXtScale FPCs.i This command requires the -i option to give specify which network adapter to use to look for the FPCs.\n";
    push @{ $rsp->{data} },
      "  configfpc -i interface \n ";
    push @{ $rsp->{data} },
      "  configfpc [-V|--verbose] -i interface \n ";
    push @{ $rsp->{data} }, "  configfpc [-h|--help|-?] \n";
    xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
    return 0;
}

#
# Main process subroutine
#
###########################################################################
# This routine will look for NeXtWcale Fan Power Controllers (FPC) that have
# a default IP address of 192.169.0.100
#
# For each FPC found the code will 
# 1 - ping the default IP address to get the default IP and MAC in the arp table
# 2 - use arp to get the MAC address
# 3 - lookup the MAC address
# ------ check for the MAC on the switch adn save the port number
# ------ lookup the node with that switch port number
# 4 - get the IP address for the node name found
# 5 - determine the assocaited netmask and gateway for this node IP
# 6 - use rspconfig (IPMI) to set the netmask, gateway, and IP address
# 7 - check to make sure that the new FPC IP address is responding
# 8 - remove the default FPC IP from the arp table
# 9 - use ping to determine if there is another default FPC IP and if so start this process again
###########################################################################
sub configfpc {
	my $request = shift;
	my $callback = shift;
	my $subreq = shift;

	$::CALLBACK = $callback;

	# Use default userid and passwd
	my $ipmiuser = 'USERID';
	my $ipmipass = 'PASSW0RD';
	my $fpcip = '192.168.0.100';
	my $defnode = 'deffpc';

	# This is the default FPC IP that we are looking for 
	my $foundfpc = 0;

	# Setup routing to 182.168.0.100 network
	if($::VERBOSE){
		my $rsp;
		push@{ $rsp->{data} }, "Adding route definition for 192.168.0.101/16 to $::interface interface";
		xCAT::MsgUtils->message( "I", $rsp, $callback );
	}
	my $setroute = `ip addr add dev $::interface 192.168.0.101/16`;
	
	#
	# check for an FPC - this ping will also add the FPC IP and MAC  to the ARP table 
	#
	my $res = `LANG=C ping -c 1 -w 5 $fpcip`;
	if ( $res =~ /100% packet loss/g) { 
		$foundfpc = 0;

		my $rsp;
		push@{ $rsp->{data} }, "No default $fpcip IP addresses found";
		xCAT::MsgUtils->message( "I", $rsp, $callback );
		exit; # EXIT if we find no more default IP addresses on the network
	}
	else {
		if($::VERBOSE){
			my $rsp;
			push@{ $rsp->{data} }, "Found $fpcip address";
			xCAT::MsgUtils->message( "I", $rsp, $callback );
		}
		$foundfpc = 1;
	}


	my $addnode = &add_node($defnode,$fpcip,$callback);

	#
	# Main loop - check to see if we found an FPC and continue to set the FPC infomration and look for the next one
	#
	while ($foundfpc){
	
		# Process the default FPC IP to find the node associated with this FPC MAC
		my ($node,$fpcmac) = &get_node($callback);
		
		# Found the Node and MAC associated with this MAC - continue to setup this FPC
		if ($node) { 
			
			# get the network settings for this node
			my ($netmask,$gateway,$newfpcip) = &get_network_parms($node,$callback);
	
			# Change the FPC network netmask, gateway, and ip
			&set_FPC_network_parms($defnode,$netmask,$gateway,$newfpcip,$callback,$subreq);

			# message changed network settings
			my $rsp;
			push@{ $rsp->{data} }, "Configured FPC with MAC $fpcmac as $node ($newfpcip)";
			xCAT::MsgUtils->message( "I", $rsp, $callback );
	
			# Validate that new IP is working - Use ping to check if the new IP has been set
			my $p = Net::Ping->new();
			my $ping_success=1;
			while ($ping_success) {
				if ($p->ping($newfpcip)) {
					my $rsp; 
					push@{ $rsp->{data} }, "Verified the FPC with MAC $fpcmac is responding to the new IP $newfpcip as node $node";
					xCAT::MsgUtils->message( "I", $rsp, $callback );
					$ping_success=0;
				}
				else {
					if($::VERBOSE){
						my $rsp;
						push@{ $rsp->{data} }, "ping to $newfpcip is unsuccessful. Retrying ";
						xCAT::MsgUtils->message( "I", $rsp, $callback );
					}
				}
			}
			$p->close();

		# The Node associated with this MAC was not found - print an infomrational message and continue
		} else { 
			my $rsp;
			push@{ $rsp->{data} }, "No FPC found that is associated with MAC address $fpcmac.\nCheck to see if the switch and switch table contain the information needed to locate this FPC MAC";
			xCAT::MsgUtils->message( "E", $rsp, $callback );
			$foundfpc = 0;
		}  
	
		#
		# Delete this FPC default IP Arp entry to get ready to look for another defautl FPC
		#
		if($::VERBOSE){
			my $rsp;
			push@{ $rsp->{data} }, "Removing default IP $fpcip from the arp table";
			xCAT::MsgUtils->message( "I", $rsp, $callback );
		}
		my $arpout = `arp -d $fpcip`;
		
		if ( ($foundfpc==1) ) { # if the last FPC was found and processed
 
			# check for another FPC 
			$res = `LANG=C ping -c 1 -w 5 $fpcip 2>&1`;
			if ( ($res =~ /100% packet loss/g) && ($foundfpc==1) ) { 
				my $rsp;
				push@{ $rsp->{data} }, "There are no more  default IP address to process";
				xCAT::MsgUtils->message( "I", $rsp, $callback );
				$foundfpc = 0;
			}
			else {
				$foundfpc = 1;
			}
		}
	}

	#
	# Cleanup on the way out - Delete route and remove the deffpc node definition 
	#
	# Delete routing to 182.168.0.100 network
	if($::VERBOSE){
		my $rsp;
		push@{ $rsp->{data} }, "Deleting route definition for 192.168.0.101/16 on interface $::interface";
		xCAT::MsgUtils->message( "I", $rsp, $callback );
	}
	my $setroute = `ip addr del dev $::interface 192.168.0.101/16`;
	
	# Delete routing to 182.168.0.100 network
	if($::VERBOSE){
		my $rsp;
		push@{ $rsp->{data} }, "Removing default FPC node definition $defnode";
		xCAT::MsgUtils->message( "I", $rsp, $callback );
	}


	# Remove the defnode node entry
	my $out = xCAT::Utils->runxcmd({command=>["noderm"], node=>["$defnode"]}, $subreq, 0, 2);

	return 1;
}

#
# The get_network_parms subroutine
# takes the node name and gets the IP address for this node 
# and collects the netmask and gateway and returns netmask, gateway, and IP address
#
sub get_network_parms {

	my $node = shift;
	my $callback = shift;
	# Get the new ip address for this FPC
	my $newfpc = `getent hosts $node`;
	my ($newfpcip, $junk) = split(/\s/,$newfpc);
	
	# collect gateway and netmask 
	my $ip = $newfpcip;
	my $gateway;
	my $netmask;
	if (inet_aton($ip)) {
		$ip = inet_ntoa(inet_aton($ip));
	} else {
		my $rsp;
		push@{ $rsp->{data} }, "Unable to resolve $ip";
		xCAT::MsgUtils->message( "I", $rsp, $callback );
		return undef;
	}
	my $nettab = xCAT::Table->new('networks');
	unless ($nettab) { return undef };
	my @nets = $nettab->getAllAttribs('net','mask','gateway');
	foreach (@nets) {
		my $net = $_->{'net'};
		my $mask =$_->{'mask'};
		my $gw = $_->{'gateway'};
		$ip =~ /([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/;
		my $ipnum = ($1<<24)+($2<<16)+($3<<8)+$4;
		$mask =~ /([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/;
		my $masknum = ($1<<24)+($2<<16)+($3<<8)+$4;
		$net =~ /([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/ or next; #next if ipv6, TODO: IPv6 support
		my $netnum = ($1<<24)+($2<<16)+($3<<8)+$4;
		if ($gw eq '<xcatmaster>') {
		$gw=xCAT::NetworkUtils->my_ip_facing($ip);
		}
		if (($ipnum & $masknum)==$netnum) {
			$netmask = $mask;
			$gateway = $gw;
		} 
	}
	return ($netmask,$gateway,$newfpcip);
}

#
# The set_FPC_network_parms subroutine 
# uses rspconfig to set the netmask, gateway, and new ip address for this FPC 
#  
sub set_FPC_network_parms {

	my $defnode = shift;
	my $netmask = shift;
	my $gateway = shift;
	my $newfpcip = shift;
	my $callback = shift;
	my $request = shift;
	my $error;
	
	# Proceed with changing the FPC network parameters.
	# Set FPC Netmask
	if($::VERBOSE){
		my $rsp;
		push@{ $rsp->{data} }, "Use rspconfig to set the FPC netmask $netmask";
		xCAT::MsgUtils->message( "I", $rsp, $callback );
	}
	my $netmaskout = xCAT::Utils->runxcmd( 
		{ 
		command => ["rspconfig"],
		node => ["$defnode"],
		arg     => [ "netmask=$netmask" ], 
		sequential=>["1"],
		}, 
		$request, 0,1);
	if ($::RUNCMD_RC != 0) {
		my $rsp;
		push@{ $rsp->{data} }, "Could not change nemask $netmask";
		xCAT::MsgUtils->message( "I", $rsp, $callback );
		$error++;
	}
	
	# Set FPC gateway
	if($::VERBOSE){
		my $rsp;
		push@{ $rsp->{data} }, "Use rspconfig to set the FPC gateway $gateway";
		xCAT::MsgUtils->message( "I", $rsp, $callback );
	}
	my $gatewayout = xCAT::Utils->runxcmd( 
		{ 
		command => ["rspconfig"],
		node => ["$defnode"],
		arg     => [ "gateway=$gateway" ],
		sequential=>["1"],
		}, 
		$request, 0,1);
	if ($::RUNCMD_RC != 0) {
		my $rsp;
		push@{ $rsp->{data} }, "Could not change gateway $gateway";
		xCAT::MsgUtils->message( "I", $rsp, $callback );
		$error++;
	}
	
	# Set FPC Ip address
	if($::VERBOSE){
		my $rsp;
		push@{ $rsp->{data} }, "Use rspconfig to set the FPC IP address $newfpcip";
		xCAT::MsgUtils->message( "I", $rsp, $callback );
	}
	my $ipout = xCAT::Utils->runxcmd( 
		{ 
		command => ["rspconfig"],
		node => ["$defnode"],
		arg     => [ "ip=$newfpcip" ], 
		sequential=>["1"],
		},  
		$request, 0,1);
	if ($::RUNCMD_RC != 0) {
		my $rsp;
		push@{ $rsp->{data} }, "Could not change ip address $newfpcip on default FPC";
		xCAT::MsgUtils->message( "S", $rsp, $callback );
		$error++;
	}
	return 1;
}

#
# This subroutine 
# 1) gets the MAC from the arp table
# 2) uses Macmap to find the node associated with this MAC
# 3) returns the node and MAC 
sub get_node {
	my $callback = shift;

	my $fpcip = '192.168.0.100';
	
	# get the FPC from the arp table
	my $arpout = `arp -a | grep $fpcip`;
	
	# format of arp command is: feihu-fpc (10.1.147.170) at 6c:ae:8b:08:20:35 [ether] on eth0
	# extract the MAC address
	my ($junk1, $junk2, $junk3, $fpcmac, $junk4, $junk5, $junk6) = split(" ", $arpout);
	
	# set the FPC MAC as static for the arp table
	my $arpout = `arp -s $fpcip $fpcmac`;
	
	# Print a message that this MAC has been found
	my $rsp;
	push@{ $rsp->{data} }, "Found IP $fpcip and MAC $fpcmac";
	xCAT::MsgUtils->message( "I", $rsp, $callback );
	
	# Usee find_mac to 1) look for which switch port contains this MAC address
	# and 2) look in the xcat DB to find the node associated with the switch port this MAC was found in
	my $macmap = xCAT::MacMap->new();
	my $node = '';
	$node = $macmap->find_mac($fpcmac,0);
	# verbose
	if($::VERBOSE){
		my $rsp;
		push@{ $rsp->{data} }, "Mapped MAC $fpcmac to node $node";
		xCAT::MsgUtils->message( "I", $rsp, $callback );
	}
	
	return ($node,$fpcmac);
}

#
# This subroutine adds the deffpc node entry for use by rspconfig
# 
sub add_node {
	my $defnode = shift;
	my $fpcip = shift;
	my $callback = shift;
# add this node entry
# Object name: feihu-fpc
#     bmc=feihu-fpc		(Table:ipmi - Key:node - Column:bmc)
#     bmcpassword=PASSW0RD	(Table:ipmi - Key:node - Column:password)
#     bmcusername=USERID	(Table:ipmi - Key:node - Column:username)
#     cons=ipmi			(Table:nodehm - Key:node - Column:cons)
#     groups=fpc		(Table:nodelist - Key:node - Column:groups)
#     mgt=ipmi			(Table:nodehm - Key:node - Column:mgt)
#

	if($::VERBOSE){
		my $rsp;
		push@{ $rsp->{data} }, "Creating default FPC node deffpc with IP 192.168.0.100 for later use with rspconfig";
		xCAT::MsgUtils->message( "I", $rsp, $callback );
	}

	my $nodelisttab  = xCAT::Table->new('nodelist',-create=>1);
	$nodelisttab->setNodeAttribs($defnode, {groups =>'defaultfpc'});
	my $nodehmtab  = xCAT::Table->new('nodehm',-create=>1);
	$nodehmtab->setNodeAttribs($defnode, {mgt => 'ipmi'});
	my $ipmitab  = xCAT::Table->new('ipmi',-create=>1);
	$ipmitab->setNodeAttribs($defnode, {bmc => $fpcip, username => 'USERID', password => 'PASSW0RD'});
return 0;
}

1;
