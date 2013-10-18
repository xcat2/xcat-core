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
use Data::Dumper;
use xCAT::MacMap;
use Socket;

##########################################################################
## Command handler method from tables
###########################################################################
sub handled_commands {
	return {
		configfpc => "configfpc",
	};
}

sub process_request {
	my $request  = shift;
	my $callback = shift;
	my $subreq = shift;
 	
	$::CALLBACK = $callback;

	my $command       = $request->{command}->[0];
	my $localhostname = hostname();

	if ($command eq "configfpc")
	{
	my $rc;
    		$rc = configfpc($request, $callback, $subreq);
	}
	else
	{
		my %rsp;
		push@{ $rsp{data} }, "$localhostname: Unsupported command: $command";
		xCAT::MsgUtils->message( "I", \%rsp, $callback );
		return 1;
	}

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


	# Use default userid and passwd
	my $ipmiuser = 'USERID';
	my $ipmipass = 'PASSW0RD';
	my $fpcip = '192.168.0.100';
	my $defnode = "deffpc";

	# This is the default FPC IP that we are looking for 
	my $foundfpc = 0;
	
	#
	# check for an FPC - this ping will also add the FPC IP and MAC  to the ARP table 
	#
	my $res = `LANG=C ping -c 1 -w 5 $fpcip`;
	#my $res = system("LANG=C ping -c 1 -w 5 $fpcip 2>&1");
	if ( $res =~ /100% packet loss/g) { 
#		xCAT::MsgUtils->message ("I", "There are no default $fpcip FPC IP addresses to process");
		$foundfpc = 0;
		exit; # EXIT if we find no more default IP addresses on the network
	}
	else {
#		xCAT::MsgUtils->message ("I", "Found $fpcip FPC IP addresses to process");
		$foundfpc = 1;
	}

	#
	# make the FPC node definition - this is removed at the end of processing the FPCs
	# this default FPC node definition is used by rspconfig to change the netmask, default route, and IP address of the default FPC
	#
	# Object name: deffpc
	#    bmc=deffpc
	#    bmcpassword=PASSW0RD
	#    bmcusername=USERID
	#    cons=ipmi
	#    groups=deffpc
	#    mgt=ipmi
	#    mpa=deffpc
	#
	my $out = xCAT::Utils->runxcmd( 
		{ 
		command => ["mkdef"],
		arg     => [ "-t","node","-o",$defnode,"bmc=deffpc","bmcpassword=Passw0rd","bmcusername=USERID","cons=ipmi","groups=deffpc","mgt=ipmi","mpa=deffpc" ] 
		}, 
		$subreq, 0,1);
	
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
	
			# sleep for 4 seconds to allow rspconfig to change the IP value before validating with ping
			sleep 5;
	
			#
			# Validate that new IP is working - Use ping to check if the new IP has been set
			#
			$res = `LANG=C ping -c 1 -w 5 $newfpcip`;
			#$res = system("LANG=C ping -c 1 -w 5 $fpcip 2>&1");
			if ( $res =~ /100% packet loss/g) { 
				my %rsp;
				push@{ $rsp{data} }, "The new ip $newfpcip was not accessible";
				xCAT::MsgUtils->message( "I", \%rsp, $callback );
				#xCAT::MsgUtils->message("I","The new ip $newfpcip was not accessible");
			} else {
				my %rsp;
				push@{ $rsp{data} }, "Changed the IP address for the FPC with $fpcmac MAC to $newfpcip IP for node $node";
				xCAT::MsgUtils->message( "I", \%rsp, $callback );
				#xCAT::MsgUtils->message("I","Changed the IP address for the FPC with $fpcmac MAC to $newfpcip IP for node $node");
			}
		# The Node associated with this MAC was not found - print an infomrational message and continue
		} else { 
			my %rsp;
			push@{ $rsp{data} }, "No FPC node found that is associated with MAC address $fpcmac\nCheck to see if the switch and switch table conta    ins the information needed to locate this FPC MAC";
			xCAT::MsgUtils->message( "I", \%rsp, $callback );
		#	xCAT::MsgUtils->message("I","No FPC node found that is associated with MAC address $fpcmac\nCheck to see if the switch and switch table contains the information needed to locate this FPC MAC");
		}  
	
		#
		# Delete this FPC default IP Arp entry to get ready to look for another defautl FPC
		#
		my $arpout = `arp -d $fpcip`;
		
		# check for another FPC 
		$res = `LANG=C ping -c 1 -w 5 $fpcip 2>&1`;
		if ( $res =~ /100% packet loss/g) { 
			my %rsp;
			push@{ $rsp{data} }, "There are no more default $fpcip FPC IP addresses to process";
			xCAT::MsgUtils->message( "I", \%rsp, $callback );
			#xCAT::MsgUtils->message("I","There are no more default $fpcip FPC IP addresses to process");
			$foundfpc = 0;
		}
		else {
			$foundfpc = 1;
		}
	}

	#
	# Cleanup on the way out - Remove the deffpc node definition 
	#
	$out=xCAT::Utils->runxcmd( 
		{ 
		command => ['rmdef'],
		arg     => [ "deffpc"]
		}, 
		$subreq, 0,1);

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
		my %rsp;
		push@{ $rsp{data} }, "Unable to resolve $ip";
		xCAT::MsgUtils->message( "I", \%rsp, $callback );
		#xCAT::MsgUtils->message("S","Unable to resolve $ip");
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


	my $netmaskout = xCAT::Utils->runxcmd( 
		{ 
		command => ["rspconfig"],
		node => [$defnode],
		arg     => [ "netmask=$netmask" ]
		}, 
		$request, 0,1);
	
	if ($::RUNCMD_RC != 0) {
		my %rsp;
		push@{ $rsp{data} }, "Could not change nemask $netmask on default FPC";
		xCAT::MsgUtils->message( "I", \%rsp, $callback );
		$error++;
	}
	
	# Set FPC gateway
	my $gatewayout = xCAT::Utils->runxcmd( 
		{ 
		command => ["rspconfig"],
		node => [$defnode],
		arg     => [ "gateway=$gateway" ] 
		}, 
		$request, 0,1);
	
	if ($::RUNCMD_RC != 0) {
		my %rsp;
		push@{ $rsp{data} }, "Could not change gateway $gateway on default FPC";
		xCAT::MsgUtils->message( "I", \%rsp, $callback );
		$error++;
	}
	

	# Set FPC Ip address
	my $ipout = xCAT::Utils->runxcmd( 
		{ 
		command => ["rspconfig"],
		node => [$defnode],
		arg     => [ "ip=$newfpcip" ] 
		}, 
		$request, 0,1);
	
	if ($::RUNCMD_RC != 0) {
		my %rsp;
		push@{ $rsp{data} }, "Could not change ip address $newfpcip on default FPC";
		xCAT::MsgUtils->message( "S", \%rsp, $callback );
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
	
	# Print a message that this MAC has been found
	my %rsp;
	push@{ $rsp{data} }, "Found FPC with default IP $fpcip and MAC $fpcmac";
	xCAT::MsgUtils->message( "I", \%rsp, $callback );
	
	# Usee find_mac to 1) look for which switch port contains this MAC address
	# and 2) look in the xcat DB to find the node associated with the switch port this MAC was found in
	my $macmap = xCAT::MacMap->new();
	my $node = '';
	$node = $macmap->find_mac($fpcmac,0);
	
	return ($node,$fpcmac);
}
1;
