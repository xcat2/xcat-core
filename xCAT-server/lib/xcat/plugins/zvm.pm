# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1

	xCAT plugin to support z/VM
	
=cut

#-------------------------------------------------------
package xCAT_plugin::zvm;
use xCAT::zvmUtils;
use xCAT::zvmCPUtils;
use xCAT::MsgUtils;
use Sys::Hostname;
use xCAT::Table;
use xCAT::Utils;
use Getopt::Long;
use strict;

# use warnings;

# If the following line is not included, you get:
# /opt/xcat/lib/perl/xCAT_plugin/zvm.pm did not return a true value
1;

#-------------------------------------------------------

=head3  handled_commands

	Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands {
	return {
		rpower  => 'nodehm:power,mgt',
		rinv    => 'nodehm:mgt',
		mkvm    => 'nodehm:mgt',
		rmvm    => 'nodehm:mgt',
		lsvm    => 'nodehm:mgt',
		chvm    => 'nodehm:mgt',
		rscan   => 'nodehm:mgt',
		nodeset => 'noderes:netboot',
		getmacs => 'nodehm:getmac,mgt',
	};
}

#-------------------------------------------------------

=head3  preprocess_request

	Check and setup for hierarchy 

=cut

#-------------------------------------------------------
sub preprocess_request {
	my $req      = shift;
	my $callback = shift;

	# Hash array
	my %sn;

	# Scalar variable
	my $sn;

	# Array
	my @requests;

	# If already preprocessed, go straight to request
	if ( $req->{_xcatpreprocessed}->[0] == 1 ) { return [$req]; }
	my $nodes   = $req->{node};
	my $service = "xcat";

	# Find service nodes for requested nodes
	# Build an individual request for each service node
	if ($nodes) {
		$sn = xCAT::Utils->get_ServiceNode( $nodes, $service, "MN" );

		# Build each request for each service node
		foreach my $snkey ( keys %$sn ) {
			my $n = $sn->{$snkey};
			print "snkey=$snkey, nodes=@$n\n";
			my $reqcopy = {%$req};
			$reqcopy->{node}                   = $sn->{$snkey};
			$reqcopy->{'_xcatdest'}            = $snkey;
			$reqcopy->{_xcatpreprocessed}->[0] = 1;
			push @requests, $reqcopy;
		}

		return \@requests;
	}
	else {

		# Input error
		my %rsp;
		my $rsp;
		$rsp->{data}->[0] = "Input noderange missing. Useage: zvm <noderange> \n";
		xCAT::MsgUtils->message( "I", $rsp, $callback, 0 );
		return 1;
	}
}

#-------------------------------------------------------

=head3  process_request

	Process the command.  This is the main call.

=cut

#-------------------------------------------------------
sub process_request {
	my $request  = shift;
	my $callback = shift;
	my $nodes    = $request->{node};
	my $command  = $request->{command}->[0];
	my $args     = $request->{arg};
	my $envs     = $request->{env};
	my %rsp;
	my $rsp;
	my @nodes = @$nodes;
	my $host  = hostname();

	# Directory where executables are
	$::DIR = "/opt/zhcp/bin";

	# Process ID for fork()
	my $pid;

	# Child process IDs
	my @children;

	# Controls the power for a single or range of nodes
	if ( $command eq "rpower" ) {
		foreach (@nodes) {
			$pid = xCAT::Utils->xfork();

			# Parent process
			if ($pid) {
				push( @children, $pid );
			}

			# Child process
			elsif ( $pid == 0 ) {
				powerVM( $callback, $_, $args );

				# Exit process
				exit(0);
			}
			else {

				# Ran out of resources
				die "Error: Could not fork\n";
			}

		}    # End of foreach
	}    # End of case

	# Remote hardware inventory
	elsif ( $command eq "rinv" ) {
		foreach (@nodes) {
			$pid = xCAT::Utils->xfork();

			# Parent process
			if ($pid) {
				push( @children, $pid );
			}

			# Child process
			elsif ( $pid == 0 ) {
				inventoryVM( $callback, $_, $args );

				# Exit process
				exit(0);
			}
			else {

				# Ran out of resources
				die "Error: Could not fork\n";
			}

		}    # End of foreach
	}    # End of case

	# Creates virtual server
	elsif ( $command eq "mkvm" ) {
		foreach (@nodes) {

			$pid = xCAT::Utils->xfork();

			# Parent process
			if ($pid) {
				push( @children, $pid );
			}

			# Child process
			elsif ( $pid == 0 ) {

				# Determine if the argument is a node
				my $ans = 'FALSE';
				if ( $args->[0] ) {
					$ans = xCAT::zvmUtils->isZvmNode( $args->[0] );
				}

				# If it is a node -- then clone specified node
				if ( $ans eq 'TRUE' ) {
					cloneVM( $callback, $_, $args );
				}

				# If it is not a node -- then create node based on directory entry
				# Or create a NOLOG if no entry is provided
				else {
					makeVM( $callback, $_, $args );
				}

				# Exit process
				exit(0);
			}    # End of elsif
			else {

				# Ran out of resources
				die "Error: Could not fork\n";
			}

		}    # End of foreach
	}    # End of case

	# Removes virtual server
	elsif ( $command eq "rmvm" ) {
		foreach (@nodes) {
			$pid = xCAT::Utils->xfork();

			# Parent process
			if ($pid) {
				push( @children, $pid );
			}

			# Child process
			elsif ( $pid == 0 ) {
				removeVM( $callback, $_ );

				# Exit process
				exit(0);
			}
			else {

				# Ran out of resources
				die "Error: Could not fork\n";
			}

		}    # End of foreach
	}    # End of case

	# Lists user directory entry
	elsif ( $command eq "lsvm" ) {
		foreach (@nodes) {
			$pid = xCAT::Utils->xfork();

			# Parent process
			if ($pid) {
				push( @children, $pid );
			}

			# Child process
			elsif ( $pid == 0 ) {
				listVM( $callback, $_ );

				# Exit process
				exit(0);
			}
			else {

				# Ran out of resources
				die "Error: Could not fork\n";
			}

		}    # End of foreach
	}    # End of case

	# Changes user directory entry
	elsif ( $command eq "chvm" ) {
		foreach (@nodes) {
			$pid = xCAT::Utils->xfork();

			# Parent process
			if ($pid) {
				push( @children, $pid );
			}

			# Child process
			elsif ( $pid == 0 ) {
				changeVM( $callback, $_, $args );

				# Exit process
				exit(0);
			}
			else {

				# Ran out of resources
				die "Error: Could not fork\n";
			}

		}    # End of foreach
	}    # End of case

	# Collects node information from one or more hardware control points
	elsif ( $command eq "rscan" ) {
		foreach (@nodes) {
			$pid = xCAT::Utils->xfork();

			# Parent process
			if ($pid) {
				push( @children, $pid );
			}

			# Child process
			elsif ( $pid == 0 ) {
				scanVM( $callback, $_ );

				# Exit process
				exit(0);
			}
			else {

				# Ran out of resources
				die "Error: Could not fork\n";
			}

		}    # End of foreach
	}    # End of case

	# Set the boot state for a noderange
	elsif ( $command eq "nodeset" ) {
		foreach (@nodes) {
			$pid = xCAT::Utils->xfork();

			# Parent process
			if ($pid) {
				push( @children, $pid );
			}

			# Child process
			elsif ( $pid == 0 ) {
				nodeSet( $callback, $_, $args );

				# Exit process
				exit(0);
			}
			else {

				# Ran out of resources
				die "Error: Could not fork\n";
			}

		}    # End of foreach
	}    # End of case

	# Collects node MAC address
	elsif ( $command eq "getmacs" ) {
		foreach (@nodes) {
			$pid = xCAT::Utils->xfork();

			# Parent process
			if ($pid) {
				push( @children, $pid );
			}

			# Child process
			elsif ( $pid == 0 ) {
				getMacs( $callback, $_, $args );

				# Exit process
				exit(0);
			}
			else {

				# Ran out of resources
				die "Error: Could not fork\n";
			}

		}    # End of foreach
	}    # End of case

	# Wait for all processes to end
	foreach (@children) {
		waitpid( $_, 0 );
	}

	return;
}

#-------------------------------------------------------

=head3   removeVM

	Description	: Remove a virtual server 
					- This will delete the user entry from user directory
    Arguments	: Node to remove
    Returns		: Nothing
    Example		: removeVM($callback, $node);
    
=cut

#-------------------------------------------------------
sub removeVM {

	# Get inputs
	my ( $callback, $node ) = @_;

	# Get node properties from 'zvm' table
	my @propNames = ( 'hcp', 'userid' );
	my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

	# Get HCP
	my $hcp = $propVals->{'hcp'};
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = $propVals->{'userid'};
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node ID" );
		return;
	}

	# Power off userID
	my $out = `ssh $hcp "$::DIR/stopvs $userId"`;
	xCAT::zvmUtils->printLn( $callback, "$out" );

	# Get MDISK statements
	my @disks = xCAT::zvmUtils->getMdisks( $callback, $node );
	my @vars;
	my $addr;
	foreach (@disks) {

		# Get device address of each MDISK
		@vars = split( ' ', $_ );
		$addr = $vars[1];

		# Remove MDISK
		# This cleans up the disks before it is put back in the pool
		$out = `ssh $hcp "$::DIR/removemdisk $userId $addr"`;
		xCAT::zvmUtils->printLn( $callback, "$out" );
	}

	# Sleep 5 seconds
	# To let the z/VM user directory update
	sleep(5);

	# Delete user entry
	$out = `ssh $hcp "$::DIR/deletevs $userId"`;
	xCAT::zvmUtils->printLn( $callback, "$out" );

	# Check for errors
	my $rc = xCAT::zvmUtils->checkOutput( $callback, $out );
	if ( $rc == -1 ) {
		return;
	}

	# Remove node from 'zvm', 'nodelist', 'nodetype', 'noderes', and 'nodehm' tables
	# Save node entry in 'mac' table
	xCAT::zvmUtils->delTabEntry( 'zvm',      'node', $node );
	xCAT::zvmUtils->delTabEntry( 'nodelist', 'node', $node );
	xCAT::zvmUtils->delTabEntry( 'nodetype', 'node', $node );
	xCAT::zvmUtils->delTabEntry( 'noderes',  'node', $node );
	xCAT::zvmUtils->delTabEntry( 'nodehm',   'node', $node );

	return;
}

#-------------------------------------------------------

=head3   changeVM

 	Description	: Change a virtual server configuration
 	Arguments	: 	Node
 					Option
 		
 	Options supported:
 		add3390 [disk pool] [device address] [cylinders] [mode]	[read password] [write password] [multi password]
		add9336 [disk pool] [virtual device] [block size] [mode] [blocks] [read password] [write password] [multi password]
		addnic [address] [type] [device count]
		addprocessor [address]
		addvdisk [userID] [device address] [size]
		connectnic2guestlan [address] [lan] [owner]
		connectnic2vswitch [address] [vswitch]
		dedicatedevice [virtual device] [real device] [mode]
		deleteipl
		formatdisk [disk address] [multi password]
		disconnectnic [address]
		grantvswitch [VSwitch]
		removedisk [virtual device]
		removenic [address]
		removeprocessor [address]
		replacevs [user directory entry]
		setipl [ipl target] [load parms] [parms]
		setpassword [password]
	 	
	Returns		: Nothing
 	Example		: changeVM($callback, $node, $args);
 		
=cut

#-------------------------------------------------------
sub changeVM {

	# Get inputs
	my ( $callback, $node, $args ) = @_;

	# Get node properties from 'zvm' table
	my @propNames = ( 'hcp', 'userid' );
	my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

	# Get HCP
	my $hcp = $propVals->{'hcp'};
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = $propVals->{'userid'};
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node ID" );
		return;
	}

	# Output string
	my $out;

	# add3390 [disk pool] [device address] [cylinders] [mode] [read password] [write password] [multi password]
	if ( $args->[0] eq "--add3390" ) {
		my $pool    = $args->[1];
		my $addr    = $args->[2];
		my $cyl     = $args->[3];
		my $mode    = $args->[4];
		my $readPw  = $args->[5];
		my $writePw = $args->[6];
		my $multiPw = $args->[7];

		$out = `ssh $hcp "$::DIR/add3390 $userId $pool $addr $cyl $mode $readPw $writePw $multiPw"`;
	}

# add9336 [disk pool] [virtual device address] [block size] [blocks] [mode] [read password] [write password] [multi password]
	elsif ( $args->[0] eq "--add9336" ) {
		my $pool    = $args->[1];
		my $addr    = $args->[2];
		my $blksize = $args->[3];
		my $blks    = $args->[4];
		my $mode    = $args->[5];
		my $readPw  = $args->[6];
		my $writePw = $args->[7];
		my $multiPw = $args->[8];
		$out = `ssh $hcp "$::DIR/add9336 $userId $pool $addr $blksize $blks $mode $readPw $writePw $multiPw"`;
	}

	# addnic [address] [type] [device count]
	elsif ( $args->[0] eq "--addnic" ) {
		my $addr     = $args->[1];
		my $type     = $args->[2];
		my $devcount = $args->[3];

		$out = `ssh $hcp "$::DIR/addnic $userId $addr $type $devcount"`;
	}

	# addprocessor [address]
	elsif ( $args->[0] eq "--addprocessor" ) {
		my $addr = $args->[1];

		$out = `ssh "$hcp $::DIR/addprocessor $userId $addr"`;
	}

	# addvdisk [device address] [size]
	elsif ( $args->[0] eq "--addvdisk" ) {
		my $addr = $args->[1];
		my $size = $args->[2];

		$out = `ssh $hcp "$::DIR/addvdisk $userId $addr $size"`;
	}

	# connectnic2guestlan [address] [lan] [owner]
	elsif ( $args->[0] eq "--connectnic2guestlan" ) {
		my $addr  = $args->[1];
		my $lan   = $args->[2];
		my $owner = $args->[3];

		$out = `ssh $hcp "$::DIR/connectnic2guestlan $userId $addr $lan $owner"`;
	}

	# connectnic2vswitch [address] [vswitch]
	elsif ( $args->[0] eq "--connectnic2vswitch" ) {
		my $addr    = $args->[1];
		my $vswitch = $args->[2];

		# Connect to VSwitch
		$out = `ssh $hcp "$::DIR/connectnic2vswitch $userId $addr $vswitch"`;

		# Grant access to VSWITCH for Linux user
		$out .= "Granting access to VSWITCH for $userId...\n  ";
		$out .= `ssh $hcp "vmcp set vswitch $vswitch grant $userId"`;
	}

	# dedicatedevice [virtual device] [real device] [mode]
	elsif ( $args->[0] eq "--dedicatedevice" ) {
		my $vaddr = $args->[1];
		my $raddr = $args->[2];
		my $mode  = $args->[3];

		$out = `ssh $hcp "$::DIR/dedicatedevice $userId $vaddr $raddr $mode"`;
	}

	# deleteipl
	elsif ( $args->[0] eq "--deleteipl" ) {
		$out = `ssh $hcp "$::DIR/deleteipl $userId"`;
	}

	# formatdisk [address] [multi password]
	elsif ( $args->[0] eq "--formatdisk" ) {

		# Get disk address
		my $addr    = $args->[1];
		my $lnkAddr = $addr + 1000;
		my $multiPw = $args->[2];

		# Check if new disk address is used
		my $rc = xCAT::zvmUtils->isAddressUsed( $hcp, $addr );

		# If new disk address is used, generate new disk address
		while ( $rc == 0 ) {

			# Sleep 2 seconds to let existing disk appear
			sleep(2);
			$lnkAddr = $lnkAddr + 1;

			# Check again
			$rc = xCAT::zvmUtils->isAddressUsed( $hcp, $lnkAddr );
		}

		# Load VMCP module on HCP
		xCAT::zvmCPUtils->loadVmcp($hcp);

		# Link target disk
		$out = `ssh -o ConnectTimeout=5 $hcp "vmcp link $userId $addr $lnkAddr MW $multiPw"`;

		# Check for errors
		$rc = xCAT::zvmUtils->checkOutput( $callback, $out );
		if ( $rc == -1 ) {
			xCAT::zvmUtils->printLn( $callback, "Linking disk... Failed" );
			xCAT::zvmUtils->printLn( $callback, "$out" );
			return;
		}

		# Enable disk
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", $lnkAddr );

		# Determine device node
		$out = `ssh $hcp "cat /proc/dasd/devices" | grep ".$lnkAddr("`;
		my @vars    = split( ' ', $out );
		my $devNode = $vars[6];

		# Format target disk (only ECKD supported)
		$out = `ssh $hcp "dasdfmt -b 4096 -y -f /dev/$devNode"`;

		# Check for errors
		$rc = xCAT::zvmUtils->checkOutput( $callback, $out );
		if ( $rc == -1 ) {
			xCAT::zvmUtils->printLn( $callback, "Formating disk... Failed" );
			xCAT::zvmUtils->printLn( $callback, "$out" );

			# Disable disk
			$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-d", $lnkAddr );

			# Detatch disk
			$out = `ssh -o ConnectTimeout=5 $hcp "vmcp det $lnkAddr"`;

			# Check for errors
			$rc = xCAT::zvmUtils->checkOutput( $callback, $out );
			if ( $rc == -1 ) {
				xCAT::zvmUtils->printLn( $callback, "Detaching disk... Failed" );
				xCAT::zvmUtils->printLn( $callback, "$out" );
				return;
			}

			return;
		}
		else {
			xCAT::zvmUtils->printLn( $callback, "Formating disk... Done" );
		}

		# Disable disk
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-d", $lnkAddr );

		# Detatch disk
		$out = `ssh -o ConnectTimeout=5 $hcp "vmcp det $lnkAddr"`;

		# Check for errors
		$rc = xCAT::zvmUtils->checkOutput( $callback, $out );
		if ( $rc == -1 ) {
			xCAT::zvmUtils->printLn( $callback, "Detaching disk... Failed" );
			xCAT::zvmUtils->printLn( $callback, "$out" );
			return;
		}

		$out = "";
	}

	# grantvswitch [VSwitch]
	elsif ( $args->[0] eq "--grantvswitch" ) {
		my $vsw = $args->[1];
		$out = xCAT::zvmCPUtils->grantVSwitch( $callback, $hcp, $userId, $vsw );
	}

	# disconnectnic [address]
	elsif ( $args->[0] eq "--disconnectnic" ) {
		my $addr = $args->[1];
		$out = `ssh $hcp "$::DIR/disconnectnic $userId $addr"`;
	}

	# removedisk [virtual device address]
	elsif ( $args->[0] eq "--removedisk" ) {
		my $addr = $args->[1];
		$out = `ssh $hcp "$::DIR/removemdisk $userId $addr"`;
	}

	# removenic [address]
	elsif ( $args->[0] eq "--removenic" ) {
		my $addr = $args->[1];
		$out = `ssh $hcp "$::DIR/removenic $userId $addr"`;
	}

	# removeprocessor [address]
	elsif ( $args->[0] eq "--removeprocessor" ) {
		my $addr = $args->[1];
		$out = `ssh $hcp "$::DIR/removeprocessor $userId $addr"`;
	}

	# replacevs [file]
	elsif ( $args->[0] eq "--replacevs" ) {
		my $file = $args->[1];

		# Target system (HCP) -- root@gpok2.endicott.ibm.com
		my $target = "root@";
		$target .= $hcp;
		if ($file) {

			# SCP file over to HCP
			$out = `scp $file $target:$file`;

			# Replace user directory entry
			$out = `ssh $hcp "$::DIR/replacevs $userId $file"`;
		}
		else {
			$out = "Error: No user entry file specified";
			xCAT::zvmUtils->printLn( $callback, "$out" );
			return;
		}
	}

	# setipl [ipl target] [load parms] [parms]
	elsif ( $args->[0] eq "--setipl" ) {
		my $trgt      = $args->[1];
		my $loadparms = $args->[2];
		my $parms     = $args->[3];
		$out = `ssh $hcp "$::DIR/setipl $userId $trgt $loadparms $parms"`;
	}

	# setpassword [password]
	elsif ( $args->[0] eq "--setpassword" ) {
		my $pw = $args->[1];
		$out = `ssh $hcp "$::DIR/setpassword $userId $pw"`;
	}

	# Otherwise, print out error
	else {
		$out = "Error: Option not supported";
	}

	xCAT::zvmUtils->printLn( $callback, "$out" );
	return;
}

#-------------------------------------------------------

=head3   powerVM

	Description	: Power on/off a virtual server
    Arguments	: 	Node 
    				Option [on|off|reset|stat]
    Returns		: Nothing
    Example		: powerVM($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub powerVM {

	# Get inputs
	my ( $callback, $node, $args ) = @_;

	# Get node properties from 'zvm' table
	my @propNames = ( 'hcp', 'userid' );
	my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

	# Get HCP
	my $hcp = $propVals->{'hcp'};
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = $propVals->{'userid'};
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node ID" );
		return;
	}

	# Output string
	my $out;

	# Power on virtual server
	if ( $args->[0] eq 'on' ) {
		$out = `ssh $hcp "$::DIR/startvs $userId"`;
		xCAT::zvmUtils->printLn( $callback, "$out" );
	}

	# Power off virtual server
	elsif ( $args->[0] eq 'off' ) {
		$out = `ssh $hcp "$::DIR/stopvs $userId"`;
		xCAT::zvmUtils->printLn( $callback, "$out" );
	}

	# Get status (on|off)
	elsif ( $args->[0] eq 'stat' ) {

		# Output is different on SLES 11
		$out = `vmcp q user $userId 2>/dev/null | sed 's/HCPCQU045E.*/off/' | sed 's/$userId.*/on/'`;
		xCAT::zvmUtils->printLn( $callback, "$node: $out" );
	}

	# Reset virtual server
	elsif ( $args->[0] eq 'reset' ) {

		$out = `ssh $hcp "$::DIR/stopvs $userId"`;
		xCAT::zvmUtils->printLn( $callback, "$out" );

		# Wait for output
		while ( `vmcp q user $userId 2>/dev/null | sed 's/HCPCQU045E.*/Done/'` != "Done" ) {

			# Do nothing
		}

		$out = `ssh $hcp "$::DIR/startvs $userId"`;
		xCAT::zvmUtils->printLn( $callback, "$out" );
	}
	else {
		xCAT::zvmUtils->printLn( $callback, "Error: Option not supported" );
	}
	return;
}

#-------------------------------------------------------

=head3   scanVM

	Description	: Collects node information from HCP
    Arguments	: HCP node
    Returns		: Nothing
    Example		: scanVM($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub scanVM {

	# Get inputs
	my ( $callback, $node ) = @_;

	# Get node properties from 'zvm' table
	my @propNames = ( 'hcp', 'userid' );
	my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

	# Get HCP
	my $hcp = $propVals->{'hcp'};
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = $propVals->{'userid'};
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node ID" );
		return;
	}

	# Print output string
	# [Node name]:
	#	objtype=node
	#   id=[userID]
	#   os=[Operating system]
	#   arch=[Architecture]
	#   hcp=[HCP node name]
	#   groups=[Group]
	#   mgt=zvm
	#
	# gpok123:
	#	objtype=node
	#   id=LINUX123
	#   os=SUSE Linux Enterprise Server 10 (s390x)
	#   arch=s390x
	#   hcp=gpok456.endicott.ibm.com
	#   groups=all
	#   mgt=zvm

	# Output string
	my $str = "";

	# Get nodes managed by this HCP
	# Look in 'zvm' table
	my $tab = xCAT::Table->new( 'zvm', -create => 1, -autocommit => 0 );
	my @entries = $tab->getAllAttribsWhere( "hcp like '%" . $hcp . "%'", 'node', 'userid' );

	my $out;
	my $managedNode;
	my $id;
	my $os;
	my $arch;
	my $groups;

	# Search for nodes managed by specified HCP
	# Get 'node' and 'userid' properties
	foreach (@entries) {
		$managedNode = $_->{'node'};

		# Get groups
		@propNames = ('groups');
		$propVals  = xCAT::zvmUtils->getNodeProps( 'nodelist', $managedNode, @propNames );
		$groups    = $propVals->{'groups'};

		# Load VMCP module
		xCAT::zvmCPUtils->loadVmcp($managedNode);

		# Get userID
		$id = xCAT::zvmCPUtils->getUserId($managedNode);

		# Get operating system
		$os = xCAT::zvmCPUtils->getOs($managedNode);

		# Get architecture
		$arch = xCAT::zvmCPUtils->getArch($managedNode);

		# Create output string
		$str .= "$managedNode:\n";
		$str .= "  objtype=node\n";
		$str .= "  userid=$id\n";
		$str .= "  os=$os\n";
		$str .= "  arch=$arch\n";
		$str .= "  hcp=$hcp\n";
		$str .= "  groups=$groups\n";
		$str .= "  mgt=zvm\n\n";
	}

	xCAT::zvmUtils->printLn( $callback, "$str" );
	return;
}

#-------------------------------------------------------

=head3   inventoryVM

	Description	: Get virtual server hardware and software inventory
    Arguments	: 	Node 
    				Type of inventory (config|all)
    Returns		: Nothing
    Example		: inventoryVM($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub inventoryVM {

	# Get inputs
	my ( $callback, $node, $args ) = @_;

	# Get node properties from 'zvm' table
	my @propNames = ( 'hcp', 'userid' );
	my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

	# Get HCP
	my $hcp = $propVals->{'hcp'};
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = $propVals->{'userid'};
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node ID" );
		return;
	}

	# Output string
	my $str = "";

	# Load VMCP module
	xCAT::zvmCPUtils->loadVmcp($node);

	# Get configuration
	if ( $args->[0] eq 'config' ) {

		# Get z/VM host for specified node
		my $host = xCAT::zvmCPUtils->getHost($node);

		# Get architecture
		my $arch = xCAT::zvmCPUtils->getArch($node);

		# Get operating system
		my $os = xCAT::zvmCPUtils->getOs($node);

		# Get privileges
		my $priv = xCAT::zvmCPUtils->getPrivileges($node);

		# Get memory configuration
		my $memory = xCAT::zvmCPUtils->getMemory($node);

		# Get processors configuration
		my $proc = xCAT::zvmCPUtils->getCpu($node);

		$str .= "z/VM UserID: $userId\n";
		$str .= "z/VM Host: $host\n";
		$str .= "Operating System: $os\n";
		$str .= "Architecture:	$arch\n";
		$str .= "HCP: $hcp\n";
		$str .= "Privileges: \n$priv\n";
		$str .= "Total Memory:	$memory\n";
		$str .= "Processors: \n$proc\n";
	}
	elsif ( $args->[0] eq 'all' ) {

		# Get z/VM host for specified node
		my $host = xCAT::zvmCPUtils->getHost($node);

		# Get architecture
		my $arch = xCAT::zvmCPUtils->getArch($node);

		# Get operating system
		my $os = xCAT::zvmCPUtils->getOs($node);

		# Get privileges
		my $priv = xCAT::zvmCPUtils->getPrivileges($node);

		# Get memory configuration
		my $memory = xCAT::zvmCPUtils->getMemory($node);

		# Get processors configuration
		my $proc = xCAT::zvmCPUtils->getCpu($node);

		# Get disks configuration
		my $storage = xCAT::zvmCPUtils->getDisks($node);

		# Get NICs configuration
		my $nic = xCAT::zvmCPUtils->getNic($node);

		# Create output string
		$str .= "z/VM UserID: $userId\n";
		$str .= "z/VM Host: $host\n";
		$str .= "Operating System: $os\n";
		$str .= "Architecture:	$arch\n";
		$str .= "HCP: $hcp\n";
		$str .= "Privileges: \n$priv\n";
		$str .= "Total Memory:	$memory\n";
		$str .= "Processors: \n$proc\n";
		$str .= "Disks: \n$storage\n";
		$str .= "NICs:	\n$nic\n";
	}
	else {
		$str = "Error: Option not supported";
		xCAT::zvmUtils->printLn( $callback, "$str" );
		return;
	}

	# Append hostname (e.g. gpok3) in front
	$str = xCAT::zvmUtils->appendHostname( $node, $str );

	xCAT::zvmUtils->printLn( $callback, "$str" );
	return;
}

#-------------------------------------------------------

=head3   listVM

	Description	: Get user entry
    Arguments	: Node
    Returns		: Nothing
    Example		: listVM($callback, $node);
    
=cut

#-------------------------------------------------------
sub listVM {

	# Get inputs
	my ( $callback, $node ) = @_;

	# Get node properties from 'zvm' table
	my @propNames = ( 'hcp', 'userid' );
	my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

	# Get HCP
	my $hcp = $propVals->{'hcp'};
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = $propVals->{'userid'};
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node ID" );
		return;
	}

	# Get user entry
	my $out = `ssh $hcp "$::DIR/getuserentry $userId"`;
	xCAT::zvmUtils->printLn( $callback, "$out" );

	return;
}

#-------------------------------------------------------

=head3   makeVM

	Description	: Create a virtual server
					- This assigns a unique MAC address to the virtual server
    Arguments	: 	Node
    				User entry text file
    Returns		: Nothing
    Example		: makeVM($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub makeVM {

	# Get inputs
	my ( $callback, $node, $args ) = @_;

	# Get node properties from 'zvm' table
	my @propNames = ( 'hcp', 'userid' );
	my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

	# Get HCP
	my $hcp = $propVals->{'hcp'};
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = $propVals->{'userid'};
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node ID" );
		return;
	}

	# Get user entry file (if any)
	my $userEntry = $args->[0];

	my $out;
	my $nodeStr = "root@" . $hcp;
	if ($userEntry) {

		# Grab first NICDEF statement in user entry
		$out = `cat $userEntry | grep "NICDEF"`;
		my @lines = split( '\n', $out );
		my @vars  = split( ' ',  $lines[0] );

		# Get LAN name
		my $netName = $vars[6];

		# Get MAC address in 'mac' table
		my $macId;
		my $generateNew = 0;
		@propNames = ('mac');
		$propVals = xCAT::zvmUtils->getNodeProps( 'mac', $node, @propNames );
		if ($propVals) {

			# Get MAC suffix -- This is the MACID value
			$macId = $propVals->{'mac'};
			$macId = xCAT::zvmUtils->replaceStr( $macId, ":", "" );
			$macId = substr( $macId, 6 );
		}
		else {

			# If no MACID is found, get one
			$macId = xCAT::zvmUtils->getMacID($hcp);
			if ( !$macId ) {
				xCAT::zvmUtils->printLn( $callback, "Error: Could not generate MACID" );
				return;
			}

			# Set flag to generate new MACID after virtual server is created
			$generateNew = 1;
		}

		# Append MACID at the end of the NICDEF statement in user entry text file
		$out = `sed --in-place -e "s,$netName,$netName MACID $macId,g" $userEntry`;

		# SCP file over to HCP
		$out = `scp $userEntry $nodeStr:$userEntry`;

		# Create virtual server
		$out = `ssh $hcp "$::DIR/createvs $userId $userEntry"`;
		xCAT::zvmUtils->printLn( $callback, "$out" );

		# Check output
		my $rc = xCAT::zvmUtils->checkOutput( $callback, $out );
		if ( $rc == 0 ) {

			# Get HCP MAC address
			$out   = `ssh -o ConnectTimeout=5 $hcp "vmcp q nic" | grep $netName`;
			@lines = split( "\n", $out );
			@vars  = split( " ", $lines[0] );

			# Extract MAC prefix
			my $prefix = $vars[1];
			$prefix = xCAT::zvmUtils->replaceStr( $prefix, "-", "" );
			$prefix = substr( $prefix, 0, 6 );

			# Generate MAC address
			my $mac = $prefix . $macId;

			# If length is less than 12, append a zero
			if ( length($mac) != 12 ) {
				$mac = "0" . $mac;
			}

			$mac =
			    substr( $mac, 0, 2 ) . ":"
			  . substr( $mac, 2,  2 ) . ":"
			  . substr( $mac, 4,  2 ) . ":"
			  . substr( $mac, 6,  2 ) . ":"
			  . substr( $mac, 8,  2 ) . ":"
			  . substr( $mac, 10, 2 );

			# Save MAC address in 'mac' table
			xCAT::zvmUtils->setNodeProp( 'mac', $node, 'mac', $mac );

			# Generate new MACID
			if ( $generateNew == 1 ) {
				$mac = xCAT::zvmUtils->generateMacId($hcp);
			}
		}
	}
	else {

		# Create NOLOG virtual server
		$out = `ssh $hcp "$::DIR/createvs $userId"`;
		xCAT::zvmUtils->printLn( $callback, "$out" );
	}

	return;
}

#-------------------------------------------------------

=head3   cloneVM

	Description	: Clone a virtual server
    Arguments	: 	Node 
    				Disk pool
    				Multi password
    Returns		: Nothing
    Example		: cloneVM($callback, $targetNode, $args);
    
=cut

#-------------------------------------------------------
sub cloneVM {

	# Get inputs
	my ( $callback, $targetNode, $args ) = @_;

	# Return code for each command
	my $rc;

	xCAT::zvmUtils->printLn( $callback, "$targetNode: Cloning" );

	# Get node properties from 'zvm' table
	my @propNames = ( 'hcp', 'userid' );
	my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $targetNode, @propNames );

	# Get HCP
	my $hcp = $propVals->{'hcp'};
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node HCP" );
		return;
	}

	# Get node userID
	my $targetUserId = $propVals->{'userid'};
	if ( !$targetUserId ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node ID" );
		return;
	}

	# Get source node
	my $sourceNode = $args->[0];
	if ( !$sourceNode ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing source node" );
		return;
	}

	# Get source node properties from 'zvm' table
	@propNames = ( 'hcp', 'userid' );
	$propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $sourceNode, @propNames );

	# Get HCP
	my $sourceHcp = $propVals->{'hcp'};
	if ( !$sourceHcp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing source node HCP" );
		return;
	}

	# Get node userID
	my $sourceId = $propVals->{'userid'};
	if ( !$sourceId ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing source node ID" );
		return;
	}

	# Exit if source node HCP is not the same as target node HCP
	if ( !( $sourceHcp eq $hcp ) ) {
		xCAT::zvmUtils->printLn( $callback,
			"Error: Source node HCP ($sourceHcp) is not the same as target node HCP ($hcp)" );
		return;
	}

	# Get target IP from /etc/hosts
	my $out      = `cat /etc/hosts | grep $targetNode`;
	my @lines    = split( '\n', $out );
	my @vars     = split( ' ', $lines[0] );
	my $targetIp = $vars[0];
	if ( !$targetIp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing IP for $targetNode in /etc/hosts" );
		return;
	}

	# Get disk pool and multi password
	my $i;
	my %inputs;
	foreach $i ( 1 .. 2 ) {
		if ( $args->[$i] ) {

			# Split parameters by '='
			@vars = split( "=", $args->[$i] );

			# Create hash array
			$inputs{ $vars[0] } = $vars[1];
		}
	}

	# Get disk pool
	my $pool = $inputs{"pool"};
	if ( !$pool ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing pool ID" );
		return;
	}

	# Get multi password
	my $trgtPw = $inputs{"pw"};
	if ( !$trgtPw ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing read/write/multi password" );
		return;
	}

	# Get MDisk statements of source node
	my @srcDisks = xCAT::zvmUtils->getMdisks( $callback, $sourceNode );

	# Get user entry of source node
	# Save user directory entry as /tmp/node.txt
	my $userEntry = "/tmp/$targetNode.txt";
	$out = `rm $userEntry`;	# Remove existing user entry if any
	$out = xCAT::zvmUtils->getUserEntryWODisk( $callback, $sourceNode, $userEntry );

	# Replace source userID with target userID
	$out = `sed --in-place -e "s,$sourceId,$targetUserId,g" $userEntry`;

	# Get MAC address in 'mac' table
	my $targetMac;
	my $macId;
	my $generateNew = 0;    # Flag to generate new MACID
	@propNames = ('mac');
	$propVals = xCAT::zvmUtils->getNodeProps( 'mac', $targetNode, @propNames );
	if ($propVals) {

		# Get MACID
		$targetMac = $propVals->{'mac'};
		$macId     = $propVals->{'mac'};
		$macId     = xCAT::zvmUtils->replaceStr( $macId, ":", "" );
		$macId     = substr( $macId, 6 );
	}
	else {

		# If no MACID is found, get one
		$macId = xCAT::zvmUtils->getMacID($hcp);
		if ( !$macId ) {
			xCAT::zvmUtils->printLn( $callback, "Error: Could not generate MACID" );
			return;
		}

		# Create MAC address for target node
		$targetMac = xCAT::zvmUtils->createMacAddr( $targetNode, $macId );

		# Set flag to generate new MACID after virtual server is created
		$generateNew = 1;
	}

	# Open user entry and find MACID
	$out = `cat $userEntry | grep "NICDEF"`;
	@lines = split( '\n', $out );
	if ( @lines < 1 ) {
		xCAT::zvmUtils->printLn( $callback, "Error: No NICDEF statement found in user entry" );
		return;
	}

	my $foundMacId = 0;
	my $targetMacId;
	my $netName;

	# Go through each NICDEF line
	foreach (@lines) {

		# Go through every parameter
		@vars = split( ' ', $_ );

		# Get LAN name
		$netName = $vars[6];
		foreach (@vars) {

			# If MACID declaration found, get MACID value
			if ( $foundMacId == 1 ) {
				$targetMacId = $_;
				$foundMacId  = 0;
			}

			# Find MACID declaration
			if ( $_ =~ m/MACID/i ) {
				$foundMacId = 1;
			}
		}    # End of foreach (@vars)

		# If MACID is found, generate a new MACID
		if ($targetMacId) {

			$out = `sed --in-place -e "s,$targetMacId,$macId,g" $userEntry`;
			last;
		}    # End of if ($targetMacId)
	}    # End of foreach (@lines)

	# SCP directory entry file over to HCP
	xCAT::zvmUtils->sendFile( $hcp, $userEntry, $userEntry );

	# Create new virtual server
	my $try = 0;
	$rc = -1;
	xCAT::zvmUtils->printLn( $callback, "$targetNode: Creating user directory entry" );
	while ( ( $rc == -1 ) && ( $try < 5 ) ) {

		# Create new virtual server
		$out = `ssh $hcp "$::DIR/createvs $targetUserId $userEntry"`;
		$rc  = xCAT::zvmUtils->checkOutput( $callback, $out );

		# Exit loop on good return
		if ( $rc == 0 ) {
			last;
		}

		# Try again to create virtual server
		$try = $try + 1;
		sleep(4);
	}

	# Exit on bad output
	if ( $rc == -1 ) {
		xCAT::zvmUtils->printLn( $callback, "$out" );
		return;
	}

	# Save MAC address in 'mac' table
	xCAT::zvmUtils->setNodeProp( 'mac', $targetNode, 'mac', $targetMac );

	# Generate new MACID
	if ( $generateNew == 1 ) {
		$out = xCAT::zvmUtils->generateMacId($hcp);
	}

	# Load VMCP module on HCP and source node
	xCAT::zvmCPUtils->loadVmcp($hcp);
	xCAT::zvmCPUtils->loadVmcp($sourceNode);

	# Get VSwitch of master node
	my @vswitchId = xCAT::zvmCPUtils->getVswitchId($sourceNode);

	# Grant access to VSwitch for Linux user
	# GuestLan do not need permissions
	my $netType = xCAT::zvmCPUtils->getNetworkType( $hcp, $netName );
	if ( $netType eq "VSWITCH" ) {
		xCAT::zvmUtils->printLn( $callback, "$targetNode: Granting VSwitch access" );
		foreach (@vswitchId) {
			$out = xCAT::zvmCPUtils->grantVSwitch( $callback, $hcp, $targetUserId, $_ );

			# Check for errors
			$rc = xCAT::zvmUtils->checkOutput( $callback, $out );
			if ( $rc == -1 ) {

				# Exit on bad output
				xCAT::zvmUtils->printLn( $callback, "$out" );
				return;
			}
		}    # End of foreach (@vswitchId)
	}    # End of if ( $netType eq "VSWITCH" )

	# Add MDisk to target user directory entry
	my @trgtDisks;
	my $addr;
	my $type;
	my $mode;
	my $cyl;
	my $srcMultiPw;
	foreach (@srcDisks) {

		# Get disk address
		@vars = split( ' ', $_ );
		$addr = $vars[1];
		push( @trgtDisks, $addr );
		$type       = $vars[2];
		$mode       = $vars[6];
		$srcMultiPw = $vars[9];

		# Add ECKD disk
		if ( $type eq '3390' ) {

			# Get disk size (cylinders)
			$out  = `ssh -o ConnectTimeout=5 $sourceNode "vmcp q v dasd" | grep "DASD $addr"`;
			@vars = split( ' ', $out );
			$cyl  = xCAT::zvmUtils->trimStr( $vars[5] );

			xCAT::zvmUtils->printLn( $callback, "$targetNode: Adding minidisk" );
			$try = 0;
			$rc  = -1;
			while ( ( $rc == -1 ) && ( $try < 5 ) ) {

				# Add ECKD disk
				$out = `ssh $hcp "$::DIR/add3390 $targetUserId $pool $addr $cyl $mode $trgtPw $trgtPw $trgtPw"`;
				$rc  = xCAT::zvmUtils->checkOutput( $callback, $out );

				# Exit loop on good return
				if ( $rc == 0 ) {
					last;
				}

				# Try again to add ECKD disk
				$try = $try + 1;
				sleep(4);
			}

			# Exit on bad output
			if ( $rc == -1 ) {
				xCAT::zvmUtils->printLn( $callback, "$out" );
				return;
			}
		}

		# Add FBA disk
		elsif ( $type eq '9336' ) {

			# -- To be supported --
			# Get disk size (blocks)
			# Add disk
		}

	}

	# Link, format, and copy source disks
	my $srcAddr;
	my $targetAddr;
	my $sourceDevNode;
	my $targetDevNode;
	foreach (@trgtDisks) {

		# New disk address
		$srcAddr    = $_ + 1000;
		$targetAddr = $_ + 2000;

		# Check if new disk address is used (source)
		$rc = xCAT::zvmUtils->isAddressUsed( $hcp, $srcAddr );

		# If disk address is used, generate a new one (source)
		while ( $rc == 0 ) {

			# Generate a new disk address
			# Sleep 2 seconds to let existing disk appear
			sleep(2);
			$srcAddr = $srcAddr + 1;
			$rc = xCAT::zvmUtils->isAddressUsed( $hcp, $srcAddr );
		}

		# Check if new disk address is used (target)
		$rc = xCAT::zvmUtils->isAddressUsed( $hcp, $targetAddr );

		# If disk address is used, generate a new one (target)
		while ( $rc == 0 ) {

			# Generate a new disk address
			# Sleep 2 seconds to let existing disk appear
			sleep(2);
			$targetAddr = $targetAddr + 1;
			$rc = xCAT::zvmUtils->isAddressUsed( $hcp, $targetAddr );
		}

		# Link source disk to HCP
		$out = `ssh -o ConnectTimeout=5 $hcp "vmcp link $sourceId $_ $srcAddr MW $srcMultiPw"`;

		# Check for errors
		$rc = xCAT::zvmUtils->checkOutput( $callback, $out );
		if ( $rc == -1 ) {
			xCAT::zvmUtils->printLn( $callback, "$out" );
			return;
		}

		# Link target disk to HCP
		$out = `ssh -o ConnectTimeout=5 $hcp "vmcp link $targetUserId $_ $targetAddr MW $trgtPw"`;

		# Check for errors
		$rc = xCAT::zvmUtils->checkOutput( $callback, $out );
		if ( $rc == -1 ) {
			xCAT::zvmUtils->printLn( $callback, "$out" );
			return;
		}

		# Use FLASHCOPY
		xCAT::zvmUtils->printLn( $callback, "$targetNode: Copying source disk using FLASHCOPY" );
		$out = xCAT::zvmCPUtils->flashCopy( $hcp, $srcAddr, $targetAddr );

		# Check for errors
		$rc = xCAT::zvmUtils->checkOutput( $callback, $out );
		if ( $rc == -1 ) {

			# FLASHCOPY is not supported -- use Linux DD
			xCAT::zvmUtils->printLn( $callback, "$targetNode: FLASHCOPY not supported.  Using Linux DD" );

			# Enable source disk
			$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", $srcAddr );

			# Enable target disk
			$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", $targetAddr );

			# Determine source device node
			$out           = `ssh $hcp "cat /proc/dasd/devices" | grep ".$srcAddr("`;
			@vars          = split( ' ', $out );
			$sourceDevNode = $vars[6];

			# Determine target device node
			$out           = `ssh $hcp "cat /proc/dasd/devices" | grep ".$targetAddr("`;
			@vars          = split( ' ', $out );
			$targetDevNode = $vars[6];

			# Format target disk
			xCAT::zvmUtils->printLn( $callback, "$targetNode: Formating disk" );
			$out = `ssh $hcp "dasdfmt -b 4096 -y -f /dev/$targetDevNode"`;

			# Check for errors
			$rc = xCAT::zvmUtils->checkOutput( $callback, $out );
			if ( $rc == -1 ) {
				xCAT::zvmUtils->printLn( $callback, "$out" );
				return;
			}

			# Sleep 2 seconds to let the system settle
			sleep(2);

			# Copy source disk to target disk
			xCAT::zvmUtils->printLn( $callback, "$targetNode: Copying source disk" );
			$out = `ssh $hcp "dd if=/dev/$sourceDevNode of=/dev/$targetDevNode bs=4096"`;

			# Check for error
			$rc = xCAT::zvmUtils->checkOutput( $callback, $out );
			if ( $rc == -1 ) {
				xCAT::zvmUtils->printLn( $callback, "$out" );
				return;
			}

			# Sleep 2 seconds to let the system settle
			sleep(2);
		}

		# Disable and enable target disk
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-d", $targetAddr );
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", $targetAddr );

		# Determine target device node (it might have changed)
		$out           = `ssh $hcp "cat /proc/dasd/devices" | grep ".$targetAddr("`;
		@vars          = split( ' ', $out );
		$targetDevNode = $vars[6];

		# Get disk address that is the root partition
		my $rootPartitionAddr = xCAT::zvmUtils->getRootDiskAddr($sourceNode);
		if ( $_ eq $rootPartitionAddr ) {

			# Set network configuration
			xCAT::zvmUtils->printLn( $callback, "$targetNode: Setting network configuration" );

			# Mount target disk
			my $cloneMntPt = "/mnt/$targetUserId";
			$targetDevNode .= "1";
			$out = `ssh $hcp "mkdir $cloneMntPt"`;
			$out = `ssh $hcp "mount /dev/$targetDevNode $cloneMntPt"`;

			# Set hostname
			$out = `ssh $hcp sed --in-place -e "s/$sourceNode/$targetNode/g" $cloneMntPt/etc/HOSTNAME`;

			# If Red Hat -- Set hostname in /etc/sysconfig/network
			my $os = xCAT::zvmCPUtils->getOs($sourceNode);
			if ( $os =~ m/Red Hat/i ) {
				$out = `ssh $hcp sed --in-place -e "s/$sourceNode/$targetNode/g" $cloneMntPt/etc/sysconfig/network`;
			}

			# Set IP address
			my $sourceIp = xCAT::zvmUtils->getIp($sourceNode);

			# Get network configuration file
			# Location of this file depends on the OS
			my $ifcfg     = xCAT::zvmUtils->getIfcfg($sourceNode);
			my $ifcfgPath = $cloneMntPt;
			$ifcfgPath .= $ifcfg;
			$out =
`ssh $hcp sed --in-place -e "s/$sourceNode/$targetNode/g" \ -e "s/$sourceIp/$targetIp/g" $cloneMntPt/etc/hosts`;
			$out = `ssh $hcp sed --in-place -e "s/$sourceIp/$targetIp/g" \ -e "s/$sourceNode/$targetNode/g" $ifcfgPath`;

			# Set MAC address (If necessary)
			# Remove LLADDR and UNIQUE parameters and append with correct values
			$out = `ssh $hcp "cat $ifcfgPath" | grep -v "LLADDR" | grep -v "UNIQUE" > /tmp/network_config`;
			$out = `echo "LLADDR='$targetMac'" >> /tmp/network_config`;
			$out = `echo "UNIQUE=''" >> /tmp/network_config`;
			xCAT::zvmUtils->sendFile( $hcp, "/tmp/network_config", $ifcfgPath );

			# Set to hardware configuration -- Only for layer 2
			my $layer = xCAT::zvmCPUtils->getNetworkLayer($sourceNode);
			if ( $layer == 2 ) {
				if ( $os =~ m/Red Hat/i ) {
					my $srcMac;

					# Get source MAC address in 'mac' table
					@propNames = ('mac');
					$propVals = xCAT::zvmUtils->getNodeProps( 'mac', $sourceNode, @propNames );
					if ($propVals) {

						# Get MAC address
						$srcMac = $propVals->{'mac'};
					}
					else {
						xCAT::zvmUtils->printLn( $callback, "$targetNode: Could not find MAC address of $sourceNode" );

						# Unmount disk
						$out = `ssh $hcp "umount $cloneMntPt"`;

						# Disable disks
						$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-d", $srcAddr );
						$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-d", $targetAddr );

						# Detatch disks from HCP
						$out = `ssh $hcp "vmcp det $srcAddr"`;
						$out = `ssh $hcp "vmcp det $targetAddr"`;

						return;
					}

					# Set MAC address
					$out = `ssh $hcp sed --in-place -e "s/$srcMac/$targetMac/g" $ifcfgPath`;
				}
				else {

					# Get hardware configuration
					my $hwcfg     = xCAT::zvmUtils->getHwcfg($sourceNode);
					my $hwcfgPath = $cloneMntPt;

					# Set layer 2 support
					$hwcfgPath .= $hwcfg;
					$out = `ssh $hcp "cat $hwcfgPath" | grep -v "QETH_LAYER2_SUPPORT" > /tmp/hardware_config`;
					$out = `echo "QETH_LAYER2_SUPPORT='1'" >> /tmp/hardware_config`;
					xCAT::zvmUtils->sendFile( $hcp, "/tmp/hardware_config", $hwcfgPath );
				}
			}    # End of if ( $layer == 2 )

			# Flush disk
			$out = `ssh $hcp "sync"`;

			# Unmount disk
			$out = `ssh $hcp "umount $cloneMntPt"`;
		}

		# Disable disks
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-d", $srcAddr );
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-d", $targetAddr );

		# Detatch disks from HCP
		$out = `ssh $hcp "vmcp det $srcAddr"`;
		$out = `ssh $hcp "vmcp det $targetAddr"`;
	}

	# Add node to DHCP
	$out = `makedhcp -a`;

	# Power on target virtual server
	xCAT::zvmUtils->printLn( $callback, "$targetNode: Powering on" );
	$out = `ssh $hcp "$::DIR/startvs $targetUserId"`;

	# Check for error
	$rc = xCAT::zvmUtils->checkOutput( $callback, $out );
	if ( $rc == -1 ) {
		xCAT::zvmUtils->printLn( $callback, "$out" );
		return;
	}

	xCAT::zvmUtils->printLn( $callback, "$targetNode: Done" );
	return;
}

#-------------------------------------------------------

=head3   nodeSet

	Description	: Set the boot state for a noderange 
					- Installs zLinux
					- Layer 2 and 3 VSwitch/Lan supported 
					- Uses 1st NICDEF in the user entry
    Arguments	: Node
    Returns		: Nothing
    Example		: nodeSet($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub nodeSet {

	# Get inputs
	my ( $callback, $node, $args ) = @_;

	# Get action
	my $action = $args->[0];
	if ( !( $action eq "install" ) ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Option not supported" );
		return;
	}

	# Get node properties from 'zvm' table
	my @propNames = ( 'hcp', 'userid' );
	my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

	# Get HCP
	my $hcp = $propVals->{'hcp'};
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = $propVals->{'userid'};
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node ID" );
		return;
	}

	# Get Linux distribution
	@propNames = ( 'os', 'profile' );
	$propVals = xCAT::zvmUtils->getNodeProps( 'nodetype', $node, @propNames );
	my $distr = $propVals->{'os'};
	if ( !$distr ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing operating system to be deployed on this node" );
		return;
	}

	# Get autoyast/kickstart template
	my $profile = $propVals->{'profile'};
	if ( !$distr ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing profile for this node" );
		return;
	}

	# Get network interface
	@propNames = ( 'primarynic', 'tftpserver' );
	$propVals = xCAT::zvmUtils->getNodeProps( 'noderes', $node, @propNames );
	my $interface = $propVals->{'primarynic'};
	if ( !$interface ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing network adapter of this node" );
		return;
	}

	# Get host IP and hostname from /etc/hosts
	my $out      = `cat /etc/hosts | grep $node`;
	my @vars     = split( ' ', $out );
	my $hostIP   = $vars[0];
	my $hostname = $vars[1];
	if ( !$hostIP || !$hostname ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing IP for $node in /etc/hosts" );
		return;
	}

	# Get NIC address from user entry
	$out = `ssh $hcp "$::DIR/getuserentry $userId" | grep "NICDEF"`;
	if ( !$out ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing NICDEF statement in user entry of node" );
		return;
	}

	# Grab first NICDEF address
	my @lines = split( '\n', $out );
	@vars = split( ' ', $lines[0] );
	my $readChannel  = "0.0.0" . ( $vars[1] + 0 );
	my $writeChannel = "0.0.0" . ( $vars[1] + 1 );
	my $dataChannel  = "0.0.0" . ( $vars[1] + 2 );

	# Get network type (Layer 2 or 3)
	my $netName = $vars[6];
	$out = `ssh $hcp "vmcp q lan $netName"`;
	if ( !$out ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing NICDEF statement in user entry of node" );
		return;
	}

	# Go through each line
	my $layer = 3;    # Default to layer 3
	@lines = split( '\n', $out );
	foreach (@lines) {

		# If the line contains ETHERNET, then it is a layer 2 network
		if ( $_ =~ m/ETHERNET/i ) {
			$layer = 2;
		}
	}

	# Get MAC address -- Only for layer 2
	my $mac = "";
	my @propNames;
	my $propVals;
	if ( $layer == 2 ) {

		# Search 'mac' table for node
		@propNames = ('mac');
		$propVals  = xCAT::zvmUtils->getTabPropsByKey( 'mac', 'node', $node, @propNames );
		$mac       = $propVals->{'mac'};

		# If no MAC address is found, exit
		# MAC address should have been assigned to the node upon creation
		if ( !$mac ) {
			xCAT::zvmUtils->printLn( $callback, "Error: Missing MAC address of node" );
			return;
		}
	}

	# Get domain from site table
	my $siteTab    = xCAT::Table->new('site');
	my $domainHash = $siteTab->getAttribs( { key => "domain" }, 'value' );
	my $domain     = $domainHash->{'value'};

	# Get network properties for network adapter
	@propNames = ( 'net', 'mask', 'gateway', 'tftpserver', 'nameservers' );
	$propVals = xCAT::zvmUtils->getTabPropsByKey( 'networks', 'mgtifname', $interface, @propNames );
	my $network    = $propVals->{'net'};
	my $mask       = $propVals->{'mask'};
	my $gateway    = $propVals->{'gateway'};
	my $ftp        = $propVals->{'tftpserver'};
	my $nameserver = $propVals->{'nameservers'};
	if ( !$network || !$mask || !$ftp || !$nameserver ) {

		# It is acceptable to not have a gateway
		xCAT::zvmUtils->printLn( $callback, "Error: Missing network information for $interface" );
		return;
	}

	# Get broadcast address of NIC
	my $ifcfg = xCAT::zvmUtils->getIfcfgByNic( $hcp, $readChannel );
	$out = `cat $ifcfg | grep "BROADCAST"`;
	@vars = split( '=', $out );
	my $broadcast = $vars[1];
	$broadcast = xCAT::zvmUtils->trimStr($broadcast);
	$broadcast = xCAT::zvmUtils->replaceStr( $broadcast, "'", "" );

	# Load VMCP module on HCP
	xCAT::zvmCPUtils->loadVmcp($hcp);

	# Sample paramter file exists in installation CD -- Use that as a guide
	my $sampleParm;
	my $parmHeader;
	my $parms;
	my $parmFile;

	# If punch is successful -- Look for this string
	my $searchStr = "created and transferred";

	# Default parameters -- SLES
	my $instNetDev   = "osa";     # Only OSA interface type is supported
	my $osaInterface = "qdio";    # OSA interface = qdio or lcs
	my $osaMedium    = "eth";     # OSA medium = eth (ethernet) or tr (token ring)

	# Default parameters -- RHEL
	my $netType  = "qeth";
	my $portName = "FOOBAR";
	my $portNo   = "0";

	# SUSE installation
	my $template;
	if ( $distr =~ m/sles/i ) {

		# Create directory in FTP root (/install) to hold template
		$out = `mkdir -p /install/custom/install/sles`;

		# Copy autoyast template
		$template = "/install/custom/install/sles/$profile";
		$out      = `cp /opt/xcat/share/xcat/install/sles/$profile $template`;

		# Edit template
		my $device  = "qeth-bus-ccw-$readChannel";
		my $chanIds = "$readChannel $writeChannel $dataChannel";

		$out =
`sed --in-place -e "s,replace_host_address,$hostIP,g" \ -e "s,replace_long_name,$hostname,g" \ -e "s,replace_short_name,$node,g" \ -e "s,replace_domain,$domain,g" \ -e "s,replace_hostname,$node,g" \ -e "s,replace_nameserver,$nameserver,g" \ -e "s,replace_broadcast,$broadcast,g" \ -e "s,replace_device,$device,g" \ -e "s,replace_ipaddr,$hostIP,g" \ -e "s,replace_lladdr,$mac,g" \ -e "s,replace_netmask,$mask,g" \ -e "s,replace_network,$network,g" \ -e "s,replace_ccw_chan_ids,$chanIds,g" \ -e "s,replace_ccw_chan_mode,FOOBAR,g" \ -e "s,replace_gateway,$gateway,g" \ -e "s,replace_root_password,rootpw,g" $template`;

		# Read sample parmfile in /install/sles10.2/s390x/1/boot/s390x/
		$sampleParm = "/install/$distr/s390x/1/boot/s390x/parmfile";
		open( SAMPLEPARM, "<$sampleParm" );

		# Search parmfile for -- ramdisk_size=65536 root=/dev/ram1 ro init=/linuxrc TERM=dumb
		while (<SAMPLEPARM>) {

			# If the line contains 'ramdisk_size'
			if ( $_ =~ m/ramdisk_size/i ) {
				$parmHeader = xCAT::zvmUtils->trimStr($_);
			}
		}

		# Close sample parmfile
		close(SAMPLEPARM);

		# Create parmfile
		# Limited to 10 lines
		# End result should be --
		# 	ramdisk_size=65536 root=/dev/ram1 ro init=/linuxrc TERM=dumb
		# 	HostIP=10.0.0.5 Hostname=gpok5.endicott.ibm.com
		# 	Gateway=10.0.0.1 Netmask=255.255.255.0
		# 	Broadcast=10.0.0.0 Layer2=0
		# 	ReadChannel=0.0.0800  WriteChannel=0.0.0801  DataChannel=0.0.0802
		# 	Nameserver=9.0.2.11 Portname=OSAPORT
		#	Install=ftp://10.0.0.1/sles10.2/s390x/1/
		#	UseVNC=1  VNCPassword=123456
		#	InstNetDev=osa OsaInterface=qdio OsaMedium=eth Manual=0
		my $ay = "ftp://$ftp/custom/install/sles/$profile";

		$parms = $parmHeader . "\n";
		$parms = $parms . "AutoYaST=$ay\n";
		$parms = $parms . "HostIP=$hostIP Hostname=$hostname\n";
		$parms = $parms . "Gateway=$gateway Netmask=$mask\n";

		# Set layer in autoyast profile
		if ( $layer == 2 ) {
			$parms = $parms . "Broadcast=$network Layer2=1 OSAHWaddr=$mac\n";
		}
		else {
			$parms = $parms . "Broadcast=$network Layer2=0\n";
		}

		$parms = $parms . "ReadChannel=$readChannel WriteChannel=$writeChannel DataChannel=$dataChannel\n";
		$parms = $parms . "Nameserver=$nameserver Portname=$portName\n";
		$parms = $parms . "Install=ftp://$ftp/$distr/s390x/1/\n";
		$parms = $parms . "UseVNC=1 VNCPassword=123456\n";
		$parms = $parms . "InstNetDev=$instNetDev OsaInterface=$osaInterface OsaMedium=$osaMedium Manual=0\n";

		# Write to parmfile
		$parmFile = "/tmp/parm";
		open( PARMFILE, ">$parmFile" );
		print PARMFILE "$parms";
		close(PARMFILE);

		# Send kernel, parmfile, and initrd to reader to HCP
		$out = `cp /install/$distr/s390x/1/boot/s390x/vmrdr.ikr /tmp/kernel`;
		$out = `cp /install/$distr/s390x/1/boot/s390x/initrd /tmp/initrd`;
		xCAT::zvmUtils->sendFile( $hcp, "/tmp/kernel", "/tmp/kernel" );
		xCAT::zvmUtils->sendFile( $hcp, "/tmp/parm",   "/tmp/parm" );
		xCAT::zvmUtils->sendFile( $hcp, "/tmp/initrd", "/tmp/initrd" );

		# Set the virtual unit record devices online on HCP
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", "c" );
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", "d" );

		# Purge reader
		$out = xCAT::zvmCPUtils->purgeReader( $hcp, $userId );
		xCAT::zvmUtils->printLn( $callback, "$node: Purging reader... Done" );

		# Punch kernel to reader on HCP
		$out = xCAT::zvmCPUtils->punch2Reader( $hcp, $userId, "/tmp/kernel", "sles.kernel", "" );
		xCAT::zvmUtils->printLn( $callback, "$node: Punching kernel to reader... $out" );
		if ( $out =~ m/Failed/i ) {
			return;
		}

		# Punch parm to reader on HCP
		$out = xCAT::zvmCPUtils->punch2Reader( $hcp, $userId, "/tmp/parm", "sles.parm", "-t" );
		xCAT::zvmUtils->printLn( $callback, "$node: Punching parm to reader... $out" );
		if ( $out =~ m/Failed/i ) {
			return;
		}

		# Punch initrd to reader on HCP
		$out = xCAT::zvmCPUtils->punch2Reader( $hcp, $userId, "/tmp/initrd", "sles.initrd", "" );
		xCAT::zvmUtils->printLn( $callback, "$node: Punching initrd to reader... $out" );
		if ( $out =~ m/Failed/i ) {
			return;
		}
	}

	# RHEL installation
	elsif ( $distr =~ m/rhel/i ) {

		# Create directory in FTP root (/install) to hold template
		$out = `mkdir -p /install/custom/install/rh`;

		# Copy kickstart template
		$template = "/install/custom/install/rh/$profile";
		$out      = `cp /opt/xcat/share/xcat/install/rh/$profile $template`;

		# Edit template
		my $url = "ftp://$ftp/$distr/s390x/";
		$out =
`sed --in-place -e "s,replace_url,$url,g" \ -e "s,replace_ip,$hostIP,g" \ -e "s,replace_netmask,$mask,g" \ -e "s,replace_gateway,$gateway,g" \ -e "s,replace_nameserver,$nameserver,g" \ -e "s,replace_hostname,$hostname,g" \ -e "s,replace_rootpw,rootpw,g" $template`;

		# Read sample parmfile in /install/rhel5.3/s390x/images
		$sampleParm = "/install/$distr/s390x/images/generic.prm";
		open( SAMPLEPARM, "<$sampleParm" );

		# Search parmfile for -- root=/dev/ram0 ro ip=off ramdisk_size=40000
		while (<SAMPLEPARM>) {

			# If the line contains 'ramdisk_size'
			if ( $_ =~ m/ramdisk_size/i ) {
				$parmHeader = xCAT::zvmUtils->trimStr($_);
			}
		}

		# Close sample parmfile
		close(SAMPLEPARM);

		# Get mdisk address
		my @mdisks = xCAT::zvmUtils->getMdisks( $callback, $node );
		my $dasd   = "";
		my $i      = 0;
		foreach (@mdisks) {
			$i    = $i + 1;
			@vars = split( ' ', $_ );

			# Do not put a comma at the end of the last disk address
			if ( $i == @mdisks ) {
				$dasd = $dasd . "0.0.$vars[1]";
			}
			else {
				$dasd = $dasd . "0.0.$vars[1],";
			}
		}

		# Create parmfile
		# Limit to 80 characters/line -- maximum of 11 lines
		# End result should be --
		#	ramdisk_size=40000 root=/dev/ram0 ro ip=off
		# 	ks=ftp://10.0.0.1/rhel5.3/s390x/compute.rhel5.s390x.tmpl
		#	RUNKS=1 cmdline
		#	DASD=0.0.0100 HOSTNAME=gpok4.endicott.ibm.com
		#	NETTYPE=qeth IPADDR=10.0.0.4
		#	SUBCHANNELS=0.0.0800,0.0.0801,0.0.0800
		#	NETWORK=10.0.0.0 NETMASK=255.255.255.0
		#	SEARCHDNS=endicott.ibm.com BROADCAST=10.0.0.255
		#	GATEWAY=10.0.0.1 DNS=9.0.2.11 MTU=1500
		#	PORTNAME=UNASSIGNED PORTNO=0 LAYER2=0
		#	vnc vncpassword=123456
		my $ks = "ftp://$ftp/custom/install/rh/$profile";

		$parms = $parmHeader . "\n";
		$parms = $parms . "ks=$ks\n";
		$parms = $parms . "RUNKS=1 cmdline\n";
		$parms = $parms . "DASD=$dasd HOSTNAME=$hostname\n";
		$parms = $parms . "NETTYPE=$netType IPADDR=$hostIP\n";
		$parms = $parms . "SUBCHANNELS=$readChannel,$writeChannel,$dataChannel\n";
		$parms = $parms . "NETWORK=$network NETMASK=$mask\n";
		$parms = $parms . "SEARCHDNS=$domain BROADCAST=$broadcast\n";
		$parms = $parms . "GATEWAY=$gateway DNS=$nameserver MTU=1500\n";

		# Set layer in kickstart profile
		if ( $layer == 2 ) {
			$parms = $parms . "PORTNAME=$portName PORTNO=$portNo LAYER2=1 MACADDR=$mac\n";
		}
		else {
			$parms = $parms . "PORTNAME=$portName PORTNO=$portNo LAYER2=0\n";
		}

		$parms = $parms . "vnc vncpassword=123456\n";

		# Write to parmfile
		$parmFile = "/tmp/parm";
		open( PARMFILE, ">$parmFile" );
		print PARMFILE "$parms";
		close(PARMFILE);

		# Send kernel, parmfile, conf, and initrd to reader to HCP
		$out = `cp /install/$distr/s390x/images/kernel.img /tmp/kernel`;
		$out = `cp /install/$distr/s390x/images/initrd.img /tmp/initrd`;
		xCAT::zvmUtils->sendFile( $hcp, "/tmp/kernel", "/tmp/kernel" );
		xCAT::zvmUtils->sendFile( $hcp, "/tmp/parm",   "/tmp/parm" );
		xCAT::zvmUtils->sendFile( $hcp, "/tmp/initrd", "/tmp/initrd" );

		# Set the virtual unit record devices online
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", "c" );
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", "d" );

		# Purge reader
		$out = xCAT::zvmCPUtils->purgeReader( $hcp, $userId );
		xCAT::zvmUtils->printLn( $callback, "$node: Purging reader... Done" );

		# Punch kernel to reader on HCP
		$out = xCAT::zvmCPUtils->punch2Reader( $hcp, $userId, "/tmp/kernel", "rhel.kernel", "" );
		xCAT::zvmUtils->printLn( $callback, "$node: Punching kernel to reader... $out" );
		if ( $out =~ m/Failed/i ) {
			return;
		}

		# Punch parm to reader on HCP
		$out = xCAT::zvmCPUtils->punch2Reader( $hcp, $userId, "/tmp/parm", "rhel.parm", "-t" );
		xCAT::zvmUtils->printLn( $callback, "$node: Punching parm to reader... $out" );
		if ( $out =~ m/Failed/i ) {
			return;
		}

		# Punch initrd to reader on HCP
		$out = xCAT::zvmCPUtils->punch2Reader( $hcp, $userId, "/tmp/initrd", "rhel.initrd", "" );
		xCAT::zvmUtils->printLn( $callback, "$node: Punching initrd to reader... $out" );
		if ( $out =~ m/Failed/i ) {
			return;
		}
	}

	# Boot node
	$out = `ssh $hcp "$::DIR/startvs $userId"`;
	my $rc = xCAT::zvmUtils->checkOutput( $callback, $out );
	if ( $rc == -1 ) {
		xCAT::zvmUtils->printLn( $callback, "Installation failed" );
		return;
	}
	else {
		xCAT::zvmUtils->printLn( $callback, "$node: $out" );
	}

	# IPL 000C (reader) on node when virtual server is online
	sleep(5);
	$out = xCAT::zvmCPUtils->sendCPCmd( $hcp, $userId, "IPL 000C" );
	xCAT::zvmUtils->printLn( $callback,
"$node: Starting VNC server.  This may take a couple of minutes.\nYou may try and open a VNC client at any time."
	);

	return;
}

#-------------------------------------------------------

=head3   getMacs

	Description	: Collect node MAC address 
					- Requires the node be online
    Arguments	: Node
    Returns		: Nothing
    Example		: getMacs($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub getMacs {

	# Get inputs
	my ( $callback, $node, $args ) = @_;

	# Get node properties from 'zvm' table
	my @propNames = ( 'hcp', 'userid' );
	my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

	# Get HCP
	my $hcp = $propVals->{'hcp'};
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = $propVals->{'userid'};
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node ID" );
		return;
	}

	# Get MAC address in 'mac' table
	my @propNames = ('mac');
	my $propVals = xCAT::zvmUtils->getNodeProps( 'mac', $node, @propNames );
	my $mac;
	if ($propVals) {

		# Get MAC address
		$mac = $propVals->{'mac'};
		xCAT::zvmUtils->printLn( $callback, "$node: $mac" );
		return;
	}

	# If MAC address is not in the 'mac' table, get it using VMCP
	xCAT::zvmCPUtils->loadVmcp($node);

	# Get xCat MN Lan/VSwitch name
	my $out = `vmcp q v nic | egrep -i "VSWITCH|LAN"`;
	my @lines = split( '\n', $out );
	my @vars;

	# Go through each line and extract VSwitch and Lan names
	# and create search string
	my $searchStr = "";
	my $i;
	for ( $i = 0 ; $i < @lines ; $i++ ) {

		# Extract VSwitch name
		if ( $lines[$i] =~ m/VSWITCH/i ) {
			@vars = split( ' ', $lines[$i] );
			$searchStr = $searchStr . "$vars[4]";
		}

		# Extract Lan name
		elsif ( $lines[$i] =~ m/LAN/i ) {
			@vars = split( ' ', $lines[$i] );
			$searchStr = $searchStr . "$vars[4]";
		}

		if ( $i != ( @lines - 1 ) ) {
			$searchStr = $searchStr . "|";
		}
	}

	# Get MAC address of node
	# This node should be on only 1 of the networks that the xCat MN is on
	$out = `ssh -o ConnectTimeout=5 $node "vmcp q v nic" | egrep -i "$searchStr"`;
	if ( !$out ) {
		xCAT::zvmUtils->printLn( $callback, "$node: Failed to find MAC address" );
		return;
	}

	@lines = split( '\n', $out );
	@vars  = split( ' ',  $lines[0] );
	my $mac = $vars[1];

	# Replace - with :
	$mac = xCAT::zvmUtils->replaceStr( $mac, "-", ":" );
	xCAT::zvmUtils->printLn( $callback, "$node: $mac" );

	# Get network interface using MAC address
	$out = `ssh -o ConnectTimeout=5 $node "ifconfig" | grep "$mac"`;
	if ( !$out ) {
		xCAT::zvmUtils->printLn( $callback, "$node: Failed find network interface" );
		return;
	}

	@lines = split( '\n', $out );
	@vars  = split( ' ',  $lines[0] );
	my $interface = $vars[0];

	# Save MAC address and network interface into 'mac' table
	xCAT::zvmUtils->setNodeProp( 'mac', $node, 'mac',       $mac );
	xCAT::zvmUtils->setNodeProp( 'mac', $node, 'interface', $interface );

	return;
}
