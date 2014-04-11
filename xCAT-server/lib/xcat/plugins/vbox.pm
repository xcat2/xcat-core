# IBM(c) 2008 EPL license http://www.eclipse.org/legal/epl-v10.html
# Ver. 2.1 (4) - sf@mauricebrinkmann.de
# Ver. 3.0     - Herbert Mehlhose, IBM - add support of VirtualBox V4 				
#
#-------------------------------------------------------

=head1
  xCAT plugin package to handle VirtualBox machines

   Supported command:
		 rpower

=cut

#-------------------------------------------------------
package xCAT_plugin::vbox;
require Sys::Hostname;
require xCAT::Table;

require xCAT::Utils;
require xCAT::TableUtils;
require xCAT::ServiceNodeUtils;
require xCAT::MsgUtils;
use Getopt::Long;
1;

use strict;
use warnings;

#-------------------------------------------------------

=head3	handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
	return {rpower => 'nodehm:power,mgt'};
}

#-------------------------------------------------------

=head3	preprocess_request

  Check and setup for hierarchy 

=cut

#-------------------------------------------------------
sub preprocess_request
{
	my $req = shift;
	my $cb	= shift;
	if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }
	#exit if preprocessed
	my $nodes	 = $req->{node};
	my $service  = "xcat";

	# find service nodes for requested nodes
	# build an individual request for each service node
	my $sn = xCAT::ServiceNodeUtils->get_ServiceNode($nodes, $service, "MN");

	my @requests = ();
	
	# build each request for each service node
	foreach my $snkey (keys %$sn) {
	my $n=$sn->{$snkey};
	print "snkey=$snkey, nodes=@$n\n";
			my $reqcopy = {%$req};
			$reqcopy->{node} = $sn->{$snkey};
			$reqcopy->{'_xcatdest'} = $snkey;
			$reqcopy->{_xcatpreprocessed}->[0] = 1;
			push @requests, $reqcopy;

	}
	return \@requests;
}


#-------------------------------------------------------

=head3	process_request

  Process the command

=cut

#-------------------------------------------------------
sub process_request
{

	my $request  = shift;
	our $callback = shift;
	my $nodes	 = $request->{node};
	my $command  = $request->{command}->[0];
	my $args	 = $request->{arg};
	my $envs	 = $request->{env};
	our $rsp;
	my $node;

	my $soapsupport = eval { require SOAP::Lite; };
	unless ($soapsupport) { #Still no SOAP::Lite module
	  $callback->({error=>"SOAP::Lite perl module missing, unable to fulfill Virtual Box plugin requirements",errorcode=>[42]});
	  return [];
	}
require xCAT::vboxService;
   
	my @nodes=@$nodes;

	PROCESSNODES: foreach $node (@nodes) ######################################
	{
		# Load node information from xCAT tables
		my ($error, $url, $username, $password, $vmname, $vncport) = getInfo($node);
		next PROCESSNODES if ($error == 1);
		last PROCESSNODES if ($error == 2);
		
		# Create connection to VirtualBox web service
		my $api;  # we assume V4 as default API
		my $vbox = getWebService($url, $username, $password, $node);
		next PROCESSNODES if (!$vbox);
		
		# get version
		my $vboxvers = xCAT::vboxService->IVirtualBox_getVersion($url, $vbox);
		#$callback->({info=>"$node: Vbox version: '$vboxvers', requested vncport via xCAT 'vm' table: '$vncport'"});
		if ($vboxvers =~ "^3.0" and $vncport =~ ",")
		{
			addError("$node: VirtualBox version 3.0 does only support a single RDP port, please correct entry vncport='$vncport' in table 'vm' for this node.");
			next PROCESSNODES;
		}
		if($vboxvers =~ "^3.") {
			$api="3";    # There is no getAPIVersion in Version 3, set to 3
		} elsif($vboxvers =~ "^4.0") {
			$api="4_0";  # There is no getAPIVersion in Version 4.0 set to 4_0
		} else {		
			$api = xCAT::vboxService->IVirtualBox_getAPIVersion($url, $vbox);
		}	
		# Get the machine
		my $machine = getMachine($api, $url, $vbox, $vmname, $node);
		if ($machine) {
						
			# Command differentiation #------------------------------------
			
			if ($command eq "rpower" and @$args > 0) {
				powerCtrl($vboxvers, $api, $url, $vbox, $machine, $vmname, $node, $vncport, $args);
			}
			
			#else # unrecognized command
			#{
			#	 addError("$node: $command unsupported on vm");
			#}
			
			# End Command differentiation #--------------------------------

		} # /existing $machine reference
		
		xCAT::vboxService->IWebsessionManager_logoff($url, $vbox);
		
	} # /for each $node in @nodes
	continue
	{
		# print out status before waiting for others and others and ..
		printMessages();
		
		# yield???
	}
	
	# last chance to print remaining messages
	printMessages();
	
	return;
	
	
	sub addMessage ############################################################
	{
		push @{$rsp->{data}}, shift;
		
	} # /addMessage
	
	sub addError ##############################################################
	{
		push @{$rsp->{error}}, shift;
		
	} # /addError
	
	
	sub printMessages #########################################################
	{
		if (defined($rsp->{data}) or defined($rsp->{error})) {
			if (defined($rsp->{error}))	{
				push @{$rsp->{errorcode}}, 1;
				xCAT::MsgUtils->message("E", $rsp, $callback, 0);
			} else {
				xCAT::MsgUtils->message("I", $rsp, $callback, 0);
			}
		}
		
	} # /printMessages
	
	
	sub powerCtrl #############################################################
	{
		my ($vboxvers, $api, $url, $vbox, $machine, $vmname, $node, $vncport, $args) =
			(shift, shift, shift, shift, shift, shift, shift, shift, shift);
		
		# Get state of the machine first
		my $cmd = "IMachine_getState";
		if($api eq "3") {
			$cmd=$cmd . "_V3";
		}
		my $vmstate = xCAT::vboxService->$cmd($url, $machine);
		
		# Check if there is anything to do
		if (!$vmstate) {
			addError("$node: Can not determine vm's state!");
			return;
		} elsif ($vmstate =~ m/^PoweredOff|^Aborted|^Saved/) { 
			if ($args->[0] eq "off") {
				addMessage("$node: off");
				return;
			} elsif ($args->[0] =~ m/^reset|^boot/) {
				# if machine is off: turn on when reset was choosen
				$args->[0] = "on reset";
			} elsif ($args->[0] =~ m/^stat/) {
				# addMessage("$node: off ($vmstate)");
				addMessage("$node: off");
				return;
			}
		} else {
			if ($args->[0] eq "on") {
				addMessage("$node: on");
				return;
			} elsif ($args->[0] =~ m/^stat/) {
				# addMessage("$node: on ($vmstate)");
				addMessage("$node: on");
				return;
			}
		}
		
		# Determine machine's UUID - Should work since we got the state
		$cmd = "IMachine_getId";
		if($api eq "3") {$cmd=$cmd . "_V3";}
		my $uuid = xCAT::vboxService->$cmd($url, $machine);

		# Open Session
		my $session = getSession($api, $url, $vbox, $node, $vmname);
		if ($session) {
			# Decide what to do
			if ($args->[0] =~ m/^on/) {
				if($api eq "3")	{
					powerOn_V3($vboxvers, $url, $vbox, $machine, $session, $uuid, $node, $vncport, $args);
				} else {
					powerOn($url, $vbox, $machine, $session, $uuid, $node, $vncport, $args);
				}
			} else {
				if($api eq "3") {
					powerOff_V3($url, $vbox, $session, $machine, $uuid, $node, $args);
				} else {
					powerOff($url, $vbox, $session, $machine, $uuid, $node, $args);
				}
			}
			
			xCAT::vboxService->ISession_unlockMachine($url,$session);
		} # /existing $session
		
		return;
		
	
		sub powerOn #**********************************************************
		{
			my	($url, $vbox, $machine, $session, $uuid, $node, $vncport, $args) =
				(shift, shift, shift, shift, shift, shift, shift, shift);
				
			my $locktype="Write";
			xCAT::vboxService->IMachine_lockMachine($url,$machine,$session,$locktype);
					
			my $directmachine = xCAT::vboxService->ISession_getMachine($url, $session);
			if (!$directmachine) {
				addError("$node: Could not access mutable machine");
			} else {
				my $vrde = xCAT::vboxService->IMachine_getVRDEServer($url, $directmachine);

				# 'Oracle VM VirtualBox Extension Pack' needs to be installed on vbox server
				# to be able to use RDP
				my $extpack;
				my @VRDEextpack = xCAT::vboxService->IVRDEServer_getVRDEExtPack($url, $vrde);
				foreach(@VRDEextpack) {
					if($_ eq "Oracle VM VirtualBox Extension Pack") {
						$extpack=1;
					}
				}

				if($extpack) {
					my $hasVRDE = xCAT::vboxService->IVRDEServer_getEnabled($url, $vrde);

					my $prop="TCP/Ports";
					my $portno = xCAT::vboxService->IVRDEServer_getVRDEProperty($url, $vrde, $prop);

					if ($vncport) {	# vncport determines, if rdp will be enabled
						my $change;
						# If port is specified but different: Update machine settings
						if($hasVRDE eq "false") {
							$hasVRDE="true";
							xCAT::vboxService->IVRDEServer_setEnabled($url, $vrde, $hasVRDE);
							$change=1;
						}
						if($vncport ne $portno) {
							xCAT::vboxService->IVRDEServer_setVRDEProperty($url, $vrde, $prop, $vncport);
							$change=1;
						}
						if($change) {
							xCAT::vboxService->IMachine_saveSettings($url, $directmachine);
						}
					} elsif (!$vncport and $hasVRDE eq "true") {
						# If not specified: disable RDP for the guest
						$hasVRDE="false";
						xCAT::vboxService->IVRDEServer_setEnabled($url, $vrde, $hasVRDE);
						xCAT::vboxService->IMachine_saveSettings($url, $directmachine);
					}
					#xCAT::vboxService->IMachine_saveSettings($url, $directmachine);
					xCAT::vboxService->IManagedObjectRef_release($url, $directmachine);
				} else {
					if($vncport) {
						addMessage("Warning: for VirtualBox Version 4 and above, RDP needs the VRDE Extension Pack to be installed on the VirtualBox host system. Either install this package to use RDP with the guest machine or remove the 'vncport' from xCAT vm table for '$node' to avoid this warning message to appear. Starting without RDP for now.");
					}
				}
			}
			
			xCAT::vboxService->ISession_unlockMachine($url,$session);
			
			my $progress =	xCAT::vboxService->IMachine_launchVMProcess($url, $machine, $session, "headless", ""); #gui
							
			if (!$progress) {
				addError("$node: Can not open remote session");
			} else {  # existing $progress
				xCAT::vboxService->IProgress_waitForCompletion($url, $progress, -1);
			
				if (xCAT::vboxService->IProgress_getCompleted($url, $progress)) {
					addMessage("$node: $args->[0]");
				} else { # not successfully completed
					addError("$node: Power on failed");
				}
				
			} # /existing $progress
			
			return;
			
		} # /powerOn
		

		sub powerOn_V3 #**********************************************************
		{
			my ($vboxvers, $url, $vbox, $machine, $session, $uuid, $node, $vncport, $args) =
				(shift, shift, shift, shift, shift, shift, shift, shift, shift);

			xCAT::vboxService->IVirtualBox_openSession_V3($url, $vbox, $session, $uuid);

			my $directmachine = xCAT::vboxService->ISession_getMachine_V3($url, $session);
			my $hasVRDP;
			if (!$directmachine) {
				addError("$node: Could not access mutable machine");
			} else {
				my $vrdp = xCAT::vboxService->IMachine_getVRDPServer_V3($url, $directmachine);
				$hasVRDP = xCAT::vboxService->IVRDPServer_getEnabled_V3($url, $vrdp);
				my $portno;
				my $vncportmismatch;	# current rdp port differs from vm table vncport definition
				if($vboxvers =~ "^3.0") {	# returns single port as unsigned long
					$portno = xCAT::vboxService->IVRDPServer_getPort_V30($url, $vrdp);
					if ($vncport and ($vncport != $portno)) {
						$vncportmismatch=1;
					}
				} else {					# returns one or more ports as string
					$portno = xCAT::vboxService->IVRDPServer_getPorts_V3($url, $vrdp);
					if ($vncport and ($vncport ne $portno)) {
						$vncportmismatch=1;
					}
				}
				my $change;
				if($vncport and ($hasVRDP eq "false")) {
					$hasVRDP="true";
					xCAT::vboxService->IVRDPServer_setEnabled_V3($url, $vrdp, $hasVRDP);
					$change=1;
				}
				if ($vncportmismatch) {
					if($vboxvers =~ "^3.0")	{ # returns single port as unsigned long
						xCAT::vboxService->IVRDPServer_setPort_V30($url, $vrdp, $vncport);
					} else {
						xCAT::vboxService->IVRDPServer_setPorts_V3($url, $vrdp, $vncport);
					}
					$change=1;
				}
				if (!$vncport and $hasVRDP eq "true") {
					$hasVRDP="false";
					xCAT::vboxService->IVRDPServer_setEnabled_V3($url, $vrdp, $hasVRDP);
					$change=1;
				}
				if ($change) {
					xCAT::vboxService->IMachine_saveSettings_V3($url, $directmachine);
				}
				xCAT::vboxService->IManagedObjectRef_release_V3($url, $vrdp);
				xCAT::vboxService->IManagedObjectRef_release_V3($url, $directmachine);
			}

			xCAT::vboxService->ISession_close_V3($url, $session);
			my $v3session;
			if ($hasVRDP eq "true")	{
				$v3session="vrdp"; #vrdp
			} else {
				# found "headles" to be undocumented in SDK ref, but this allows to open a headless session w/o VRDP
				# and thus we can disable rdp without being forced to launch the gui. This allows to follow
				# the logic, that an empty vncport in the vm table will disable rdp, and having a value in
				# table vm will define the port and enable rdp.
				$v3session="headless"; # gui
			}
			#my $progress = xCAT::vboxService->IVirtualBox_openRemoteSession_V3($url, $vbox, $session, $uuid, "vrdp", "");
			my $progress = xCAT::vboxService->IVirtualBox_openRemoteSession_V3($url, $vbox, $session, $uuid, $v3session, "");

			if (!$progress)	{
				addError("$node: Can not open remote session");
			} else { # existing $progress
				xCAT::vboxService->IProgress_waitForCompletion_V3($url, $progress, -1);

				if (xCAT::vboxService->IProgress_getCompleted_V3($url, $progress)) {
					addMessage("$node: $args->[0]");
				} else { # not successfully completed
					addError("$node: Power on failed");
				}

			} # /existing $progress

			return;
		} # /powerOn_V3
		
		sub powerOff #*********************************************************
		{
			my ($url, $vbox, $session, $machine, $uuid, $node, $args) =
				(shift, shift, shift, shift, shift, shift, shift);
			
			# Lock session with machine
			my $vmsessionstate = xCAT::vboxService->IMachine_getSessionState($url, $machine);
			my $vmsessiontype =	xCAT::vboxService->IMachine_getSessionType($url, $machine);
						 
			if ($vmsessionstate eq "Locked") {
				my $locktype="Shared";
				xCAT::vboxService->IMachine_lockMachine($url,$machine,$session,$locktype);
			} elsif ($vmsessionstate eq "Unlocked")	{
				my $locktype="Write";
				xCAT::vboxService->IMachine_lockMachine($url,$machine,$session,$locktype);
			} else { # !$vmsessionstate
				addError("$node: No direct session to machine");
			}

			# just test: check sessiontype - it turns out, that this needs a lock from traces
			#my $teste = xCAT::vboxService->ISession_getType($url, $session);
			#addError("$node: sessiontype =$teste");
			
			# The session is now locked with the machine, now its direct session or console can be optained and manipulated
			# Now get the console for the mutable machine
			my $console = xCAT::vboxService->ISession_getConsole($url, $session);
			if (!$console) {
				addError("$node: No console for mutable machine");
			} else { # existing $console
				if ($args->[0] =~ m/^reset|^boot/) {
					xCAT::vboxService->IConsole_reset($url, $console);
					xCAT::vboxService->IManagedObjectRef_release($url, $console);
					addMessage("$node: on reset");
					#xCAT::vboxService->IManagedObjectRef_release($url, $console);
					return;
				} else {
					xCAT::vboxService->IConsole_powerButton($url, $console);
					unless (xCAT::vboxService->IConsole_getPowerButtonHandled($url, $console) eq "true") {
						# In case of no reaction: force to power down machine
						xCAT::vboxService->IConsole_powerDown($url, $console);
					} addMessage("$node: off");
				}
				
				xCAT::vboxService->IManagedObjectRef_release($url, $console);
				
			} # /existing $console
			
			return;
			
		} # /powerOff
		
		sub powerOff_V3 #*********************************************************
		{
			my ($url, $vbox, $session, $machine, $uuid, $node, $args) =
				(shift, shift, shift, shift, shift, shift, shift);

			# Lock session with machine
			my $vmsessionstate = xCAT::vboxService->IMachine_getSessionState_V3($url, $machine);

			if ($vmsessionstate eq "Open") {
				xCAT::vboxService->IVirtualBox_openExistingSession_V3($url, $vbox, $session, $uuid);
			} elsif ($vmsessionstate eq "Closed") {
				xCAT::vboxService->IVirtualBox_openSession_V3($url, $vbox, $session, $uuid);
			} else {
				addError("$node: No direct session to machine");
			}

			# Now get the console for the mutable machine
			my $console = xCAT::vboxService->ISession_getConsole_V3($url, $session);
			if (!$console) {
				addError("$node: No console for mutable machine");
			} else { # existing $console
				if ($args->[0] =~ m/^reset|^boot/) {
					xCAT::vboxService->IConsole_reset_V3($url, $console);
					xCAT::vboxService->IManagedObjectRef_release_V3($url, $console);
					addMessage("$node: on reset");
					#xCAT::vboxService->IManagedObjectRef_release_V3($url, $console);
					return;
				} else {
					xCAT::vboxService->IConsole_powerButton_V3($url, $console);
					unless (xCAT::vboxService->IConsole_getPowerButtonHandled_V3($url, $console) eq "true") {
						# In case of no reaction: force to power down machine
						xCAT::vboxService->IConsole_powerDown_V3($url, $console);
					} addMessage("$node: off");
				}

				xCAT::vboxService->IManagedObjectRef_release_V3($url, $console);

			} # /existing $console
			
			return;
		} # /powerOff_V3
		
	} # /powerCtrl
	
	
	sub getSession ############################################################
	{
		my $sess;
		my ($api, $url, $vbox, $node, $vmname) = (shift, shift, shift, shift, shift);
		
		my $cmd = "IWebsessionManager_getSessionObject";
		if($api eq "3") {$cmd=$cmd . "_V3";}

		eval {
		$sess = xCAT::vboxService->$cmd($url, $vbox);
		};
		
		return $sess if ($sess and not $@);
		
		addError("$node: No session for $vmname on web service @ $url.");
		return undef;
	} # /getSession
	
	
	sub getMachine ############################################################
	{
		my $machine;
		my ($api, $url, $vbox, $vmname, $node) = (shift, shift, shift, shift, shift);
		
		my $cmd = "IVirtualBox_findMachine";
		if($api eq "3") {$cmd=$cmd . "_V3";}

		eval {
		$machine = xCAT::vboxService->$cmd($url, $vbox, $vmname);
		};
		return $machine if ($machine and not $@);
		
		addError("$node: VM $vmname not known by the web service @ $url.");
		return undef;
	} # /getMachine
	
	
	sub getWebService #########################################################
	{
		my $ws;
		my ($url, $user, $passwd, $node) = (shift, shift, shift, shift);
		
		my $cmd = "IWebsessionManager_logon";
		eval {
		$ws = xCAT::vboxService->$cmd($url, $user, $passwd);
		};
		
		return $ws if ($ws and not $@);
		
		addError("$node: No connection to the web service @ $url.");
		return undef;
	} # /getWebService
	
	
	sub getInfo ###############################################################
	{
		my $node = shift;
		
		# Open tables first, return in case of a critical error = 2
		my $hostsTab = openTable('hosts');
		return (2, undef, undef, undef, undef)	 if (!$hostsTab);
		
		my $vmTab = openTable('vm');
		return (2, undef, undef, undef, undef)	 if (!$vmTab);
		
		my $websrvTab = openTable('websrv');
		return (2, undef, undef, undef, undef)	 if (!$websrvTab);
		
		# Load attributes, return in case of missing information error = 1
		my $values;
		
		my @attributes	= ('host','vncport','comments');
		$values = loadValues($vmTab, $node, \@attributes);
		return (1, undef, undef, undef, undef)	 if (!defined($values));
			
		my $hostname	= $values->{host};
		my $vncport		= $values->{vncport};
		my $comments	= $values->{comments};
		my $vmname		= undef;
		if ($comments	=~ m/vmname:(.+)!/) {
			$vmname		=  $1;
		} else {
			$vmname		=  $node;
		}
		
		@attributes  = ('port','username', 'password');
		$values = loadValues($websrvTab, $hostname, \@attributes);
		return (1, undef, undef, undef, undef)	 if (!defined($values));
			
		my $port	 = $values->{port};
		my $username = $values->{username};
		my $password = $values->{password};
		
		@attributes  = ('ip');
		$values = loadValues($hostsTab, $hostname, \@attributes);
		return (1, undef, undef, undef, undef)	 if (!defined($values));
			
		my $ipaddr	 = $values->{ip};
		my $url		 = "http://$ipaddr:$port/";
		
		return (0, $url, $username, $password, $vmname, $vncport);
		
		
		sub loadValues #*******************************************************
		{
			my ($table, $node, $attributes) = (shift, shift, shift);
			my ($values) = $table->getAttribs({'node'=>$node}, @$attributes);
			$table->close;
			
			addError("$node: Missing information: @$attributes")
				if (!defined($values));
				
			return $values;
			
		} # /loadValues
		
		
		sub openTable #********************************************************
		{
			my $tabname = shift;
			my $table = xCAT::Table->new($tabname);
			
			# try to create vbox tables if they don't exist yet
			if (!$table and $tabname =~ m/websrv/)
			{
				$table = xCAT::Table->new( $tabname, -create=>1, -autocommit=>1 );
				$table->close;
				addMessage("[xCAT] Info: The table $tabname has been created.");
				$table = xCAT::Table->new($tabname);
			}
			
			addError("[xCAT] Can not open table: $tabname. Command aborted.")
				if (!$table);
			
			return $table;
			
		} # /openTable
		
	} # /getInfo
}

# see Lite.pm for other serializer code, e.g. as_string
sub SOAP::Serializer::as_LockType
{
	my ($self, $value, $name, $type, $attr) = @_;
	die "String value expected instead of @{[ref $value]} reference\n"
		if ref $value;
	return [
		$name,
		{'xsi:type' => 'vbox:LockType', %$attr},
		SOAP::Utils::encode_data($value)
	];
}

1;
