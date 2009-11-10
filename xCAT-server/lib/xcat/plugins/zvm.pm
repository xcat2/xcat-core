# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1

	xCAT plugin package to handle z/VM
	Supported command:
		zvm->zvm
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
use warnings;

# If this line is not included, you get:
# /opt/xcat/lib/perl/xCAT_plugin/zvm.pm did not return a true value
1;

#-------------------------------------------------------

=head3  handled_commands

	Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands {
	return {
		rpower  => 'nodehm:mgt',
		rinv    => 'nodehm:mgt',
		mkvm    => 'nodehm:mgt',
		rmvm    => 'nodehm:mgt',
		lsvm    => 'nodehm:mgt',
		chvm    => 'nodehm:mgt',
		rscan   => 'nodehm:mgt',
		nodeset => 'nodehm:mgt',
		getmacs => 'nodehm:mgt',
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

	# In order for any SSH command to be sent, you will need to run
	# xdsh [group | node] -K

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

	# Creates zVM virtual server
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

	# Removes zVM virtual server
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

	# Lists zVM user directory entry
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

	# Changes zVM user directory entry
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
			$pid = fork();

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
			$pid = fork();

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
    Arguments	: Node
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

	# Get device address of each MDISK
	my @disks = xCAT::zvmUtils->getMdisks( $callback, $node );
	my @parms;
	my $addr;
	foreach (@disks) {
		@parms = split( ' ', $_ );
		$addr  = $parms[1];

		# Remove MDISK
		# This cleans up the disks before it is put back in the pool
		$out = `ssh $hcp "$::DIR/removemdisk $userId $addr"`;
		xCAT::zvmUtils->printLn( $callback, "$out" );
	}

	# Sleep 5 seconds
	# To let the z/VM user directory settle
	sleep(5);

	# Delete user directory entry
	$out = `ssh $hcp "$::DIR/deletevs $userId"`;
	xCAT::zvmUtils->printLn( $callback, "$out" );

	# Check for errors
	my $rc = xCAT::zvmUtils->isOutputGood( $callback, $out );
	if ( $rc == -1 ) {
		return;
	}

	# Remove node from tables
	$out = `noderm $node`;

	return;
}

#-------------------------------------------------------

=head3   changeVM

 	Description	: Changes server configuration
 	Arguments	: 	Node
 					Option
 		
 	Options supported:
		add3390 [disk pool] [device address] [mode] [cylinders]
		add9336 [disk pool] [virtual device] [mode] [block size] [blocks]
	 	addnic [address] [type] [device count]
	 	addprocessor [address]
	 	addvdisk [userID] [device address] [size]
	 	connectnic2guestlan [address] [lan] [owner]
	 	connectnic2vswitch [address] [vswitch]
	 	dedicatedevice [virtual device] [real device] [mode]
	 	deleteipl 
	 	disconnectnic [address]
	 	removemdisk [virtual device]
	 	removenic [address]
	 	removeprocessor [address]
	 	replacevs [file]
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

		$out = `ssh $hcp "$::DIR/add3390 $userId $pool $addr $mode $cyl $readPw $writePw $multiPw"`;
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
		$out = `ssh $hcp "$::DIR/add9336 $userId $pool $addr $mode $blksize $blks $readPw $writePw $multiPw"`;
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

		# Check if there is an existing address (disk address)
		my $rc = xCAT::zvmUtils->isAddressUsed( $hcp, $addr );

		# If there is an existing address
		while ( $rc == 0 ) {

			# Generate a new address
			# Sleep 2 seconds to let existing disk appear
			sleep(2);
			$lnkAddr = $lnkAddr + 1;
			$rc = xCAT::zvmUtils->isAddressUsed( $hcp, $lnkAddr );
		}

		# Load VMCP module on HCP
		$out = xCAT::zvmCPUtils->loadVmcp($hcp);

		# Link target disk
		$out = `ssh -o ConnectTimeout=5 $hcp "vmcp link $userId $addr $lnkAddr MW $multiPw"`;

		# Check for errors
		$rc = xCAT::zvmUtils->isOutputGood( $callback, $out );
		if ( $rc == -1 ) {
			xCAT::zvmUtils->printLn( $callback, "Linking disk... Failed" );
			xCAT::zvmUtils->printLn( $callback, "$out" );
			return;
		}

		# Enable disk
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", $lnkAddr );

		# Determine device node
		$out = `ssh $hcp "cat /proc/dasd/devices" | grep ".$lnkAddr("`;
		my @parms   = split( ' ', $out );
		my $devNode = $parms[6];

		# Format target disk (only ECKD supported)
		$out = `ssh $hcp "dasdfmt -b 4096 -y -f /dev/$devNode"`;

		# Check for errors
		$rc = xCAT::zvmUtils->isOutputGood( $callback, $out );
		if ( $rc == -1 ) {
			xCAT::zvmUtils->printLn( $callback, "Formating disk... Failed" );
			xCAT::zvmUtils->printLn( $callback, "$out" );

			# Disable disk
			$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-d", $lnkAddr );

			# Detatch disk
			$out = `ssh -o ConnectTimeout=5 $hcp "vmcp det $lnkAddr"`;

			# Check for errors
			$rc = xCAT::zvmUtils->isOutputGood( $callback, $out );
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
		$rc = xCAT::zvmUtils->isOutputGood( $callback, $out );
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

	# replaceuserentry [file]
	elsif ( $args->[0] eq "--replaceuserentry" ) {
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
			$out = "Error: No directory entry file specified";
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

	Description	: Powers on/off a virtual server
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

	Description	: Collects node information from one or more hardware control points
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

	my $out;
	my $managedNode;
	my $id;
	my $os;
	my $arch;
	my $groups;

	# Search for nodes managed by specified HCP
	# Get 'node' and 'userid' properties
	my @results = $tab->getAllAttribsWhere( "hcp like '%" . $hcp . "%'", 'node', 'userid' );
	foreach (@results) {
		$managedNode = $_->{'node'};

		# Get groups
		@propNames = ('groups');
		$propVals  = xCAT::zvmUtils->getNodeProps( 'nodelist', $managedNode, @propNames );
		$groups    = $propVals->{'groups'};

		# Load VMCP module
		$out = xCAT::zvmCPUtils->loadVmcp($managedNode);

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
    Arguments	: Node and arguments (config|all)
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
	my $out = xCAT::zvmCPUtils->loadVmcp($node);

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

	Description	: Get user directory entry
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
    Arguments	: 	Node 
    				User entry as text file
    Returns		: Nothing
    Example		: makeVM($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub makeVM {

	# Before a virtual server can be created
	# You need to add the virtual server into the tables:
	# 	mkdef -t node -o gpok123 userid=linux123 hcp=gpok456.endicott.ibm.com mgt=zvm groups=all
	# 	This will add the node into the 'nodelist', 'nodehm', and 'zvm' tables

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

	# Get file (if any)
	my $file = $args->[0];
	my $out;

	# Target system (HCP) -- root@gpok123.endicott.ibm.com
	my $target = "root@";
	$target .= $hcp;
	if ($file) {

		# SCP file over to HCP
		$out = `scp $file $target:$file`;

		# Create virtual server
		$out = `ssh $hcp "$::DIR/createvs $userId $file"`;
		xCAT::zvmUtils->printLn( $callback, "$out" );
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
    Arguments	: Node and configuration
    Returns		: Nothing
    Example		: cloneVM($callback, $targetNode, $args);
    
=cut

#-------------------------------------------------------
sub cloneVM {

	# Before a virtual server can be created
	# You need to add the virtual server into the tables:
	# 	mkdef -t node -o gpok123 userid=LINUX123 ip=9.60.18.123 hcp=gpok456.endicott.ibm.com mgt=zvm groups=all
	# 	This will add the node into the 'nodelist', 'nodehm', 'zvm', and 'hosts' tables

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
	my @parms    = split( ' ', $out );
	my $targetIp = $parms[0];
	if ( !$targetIp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing IP for $targetNode in /etc/hosts" );
		return;
	}

	# Get other inputs (2 in total)
	# Disk pool and multi password
	my $i;
	my %inputs;
	foreach $i ( 1 .. 2 ) {
		if ( $args->[$i] ) {

			# Split parameters by '='
			@parms = split( "=", $args->[$i] );

			# Create hash array
			$inputs{ $parms[0] } = $parms[1];
		}
	}

	# Get disk pool
	my $pool = $inputs{"pool"};
	if ( !$pool ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing pool ID" );
		return;
	}

	# Get read, write, and multi password
	my $trgtPw = $inputs{"pw"};
	if ( !$trgtPw ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing read/write/multi password" );
		return;
	}

	# Get MDisk statements of source node
	my @srcDisks = xCAT::zvmUtils->getMdisks( $callback, $sourceNode );

	# Get directory entry of source node
	# Save user directory entry as /tmp/userEntry.txt
	my $dirFile = "/tmp/dirEntry.txt";
	$out = xCAT::zvmUtils->saveDirEntryNoDisk( $callback, $sourceNode, $dirFile );

	# SCP directory entry file over to HCP
	$out = xCAT::zvmUtils->sendFile( $hcp, $dirFile );

	# Create new virtual server
	xCAT::zvmUtils->printLn( $callback, "$targetNode: Creating user directory entry" );
	$out = `ssh $hcp "$::DIR/createvs $targetUserId $dirFile"`;

	# Check for errors
	$rc = xCAT::zvmUtils->isOutputGood( $callback, $out );
	if ( $rc == -1 ) {

		# Exit on bad output
		xCAT::zvmUtils->printLn( $callback, "$out" );
		return;
	}

	# Load VMCP module on HCP and source node
	$out = xCAT::zvmCPUtils->loadVmcp($hcp);
	$out = xCAT::zvmCPUtils->loadVmcp($sourceNode);

	# Get VSwitch of master node
	my @vswitchId = xCAT::zvmCPUtils->getVswitchId($sourceNode);

	# Grant access to VSwitch for Linux user
	# GuestLan do not need permissions
	xCAT::zvmUtils->printLn( $callback, "$targetNode: Granting VSwitch access" );
	foreach (@vswitchId) {
		$out = xCAT::zvmCPUtils->grantVSwitch( $callback, $hcp, $targetUserId, $_ );

		# Check for errors
		$rc = xCAT::zvmUtils->isOutputGood( $callback, $out );
		if ( $rc == -1 ) {

			# Exit on bad output
			xCAT::zvmUtils->printLn( $callback, "$out" );
			return;
		}
	}

	# Add MDisk to target user directory entry
	my @trgtDisks;
	my $addr;
	my $type;
	my $mode;
	my $cyl;
	my $srcMultiPw;
	foreach (@srcDisks) {

		# Get disk device address
		@parms = split( ' ', $_ );
		$addr = $parms[1];
		push( @trgtDisks, $addr );
		$type       = $parms[2];
		$mode       = $parms[6];
		$srcMultiPw = $parms[9];

		# Add ECKD disk
		if ( $type eq '3390' ) {

			# Get disk size (cylinders)
			$out   = `ssh -o ConnectTimeout=5 $sourceNode "vmcp q v dasd" | grep "DASD $addr"`;
			@parms = split( ' ', $out );
			$cyl   = xCAT::zvmUtils->trimStr( $parms[5] );

			# Add disk
			xCAT::zvmUtils->printLn( $callback, "$targetNode: Adding minidisk" );
			$out = `ssh $hcp "$::DIR/add3390 $targetUserId $pool $addr $mode $cyl $trgtPw $trgtPw $trgtPw"`;

			# Check for errors
			$rc = xCAT::zvmUtils->isOutputGood( $callback, $out );
			if ( $rc == -1 ) {
				xCAT::zvmUtils->printLn( $callback, "$out" );

				# Exit on bad output
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
		$srcAddr    = $_ + 1000;
		$targetAddr = $_ + 2000;

		# Check if there is an existing address (source address)
		$rc = xCAT::zvmUtils->isAddressUsed( $hcp, $srcAddr );

		# If there is an existing address (source address)
		while ( $rc == 0 ) {

			# Generate a new address
			# Sleep 2 seconds to let existing disk appear
			sleep(2);
			$srcAddr = $srcAddr + 1;
			$rc = xCAT::zvmUtils->isAddressUsed( $hcp, $srcAddr );
		}

		# Check if there is an existing address (target address)
		$rc = xCAT::zvmUtils->isAddressUsed( $hcp, $targetAddr );

		# If there is an existing address
		while ( $rc == 0 ) {

			# Generate a new address
			# Sleep 2 seconds to let existing disk appear
			sleep(2);
			$targetAddr = $targetAddr + 1;
			$rc = xCAT::zvmUtils->isAddressUsed( $hcp, $targetAddr );
		}

		# Link source disk to HCP
		$out = `ssh -o ConnectTimeout=5 $hcp "vmcp link $sourceId $_ $srcAddr MW $srcMultiPw"`;

		# Check for errors
		$rc = xCAT::zvmUtils->isOutputGood( $callback, $out );
		if ( $rc == -1 ) {
			xCAT::zvmUtils->printLn( $callback, "$out" );
			return;
		}

		# Link target disk to HCP
		$out = `ssh -o ConnectTimeout=5 $hcp "vmcp link $targetUserId $_ $targetAddr MW $trgtPw"`;

		# Check for errors
		$rc = xCAT::zvmUtils->isOutputGood( $callback, $out );
		if ( $rc == -1 ) {
			xCAT::zvmUtils->printLn( $callback, "$out" );
			return;
		}

		# Use FLASHCOPY
		xCAT::zvmUtils->printLn( $callback, "$targetNode: Copying source disk using FLASHCOPY" );
		$out = xCAT::zvmCPUtils->flashCopy( $hcp, $srcAddr, $targetAddr );

		# Check for errors
		$rc = xCAT::zvmUtils->isOutputGood( $callback, $out );
		if ( $rc == -1 ) {

			# FLASHCOPY is not supported
			xCAT::zvmUtils->printLn( $callback, "$targetNode: FLASHCOPY not supported.  Using Linux DD" );

			# Enable source disk
			$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", $srcAddr );

			# Enable target disk
			$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", $targetAddr );

			# Determine source device node
			$out           = `ssh $hcp "cat /proc/dasd/devices" | grep ".$srcAddr("`;
			@parms         = split( ' ', $out );
			$sourceDevNode = $parms[6];

			# Determine target device node
			$out           = `ssh $hcp "cat /proc/dasd/devices" | grep ".$targetAddr("`;
			@parms         = split( ' ', $out );
			$targetDevNode = $parms[6];

			# Format target disk
			xCAT::zvmUtils->printLn( $callback, "$targetNode: Formating disk" );
			$out = `ssh $hcp "dasdfmt -b 4096 -y -f /dev/$targetDevNode"`;

			# Check for errors
			$rc = xCAT::zvmUtils->isOutputGood( $callback, $out );
			if ( $rc == -1 ) {

				# Exit on bad output
				xCAT::zvmUtils->printLn( $callback, "$out" );
				return;
			}

			# Sleep 2 seconds to let the system settle
			sleep(2);

			# Copy source disk to target disk
			xCAT::zvmUtils->printLn( $callback, "$targetNode: Copying source disk" );
			$out = `ssh $hcp "dd if=/dev/$sourceDevNode of=/dev/$targetDevNode bs=4096"`;

			# Check for error
			$rc = xCAT::zvmUtils->isOutputGood( $callback, $out );
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
		@parms         = split( ' ', $out );
		$targetDevNode = $parms[6];

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
			$out = xCAT::zvmCPUtils->getOs($sourceNode);
			if ( $out =~ m/Red Hat/i ) {
				$out = `ssh $hcp sed --in-place -e "s/$sourceNode/$targetNode/g" $cloneMntPt/etc/sysconfig/network`;
			}

			# Set /etc/resolve.conf (If necessary)

			# Set IP address
			my $sourceIp = xCAT::zvmUtils->getIp($sourceNode);

			# Set MAC address for Layer 2 (If necessary)

			# Get network configuration file
			# Location of this file depends on the OS
			my $ifcfg     = xCAT::zvmUtils->getIfcfg($sourceNode);
			my $ifcfgPath = $cloneMntPt;
			$ifcfgPath .= $ifcfg;
			$out =
`ssh $hcp sed --in-place -e "s/$sourceNode/$targetNode/g" \ -e "s/$sourceIp/$targetIp/g" $cloneMntPt/etc/hosts`;
			$out = `ssh $hcp sed --in-place -e "s/$sourceIp/$targetIp/g" \ -e "s/$sourceNode/$targetNode/g" $ifcfgPath`;

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

	# Power on target virtual server
	xCAT::zvmUtils->printLn( $callback, "$targetNode: Powering on" );
	$out = `ssh $hcp "$::DIR/startvs $targetUserId"`;

	# Check for error
	$rc = xCAT::zvmUtils->isOutputGood( $callback, $out );
	if ( $rc == -1 ) {

		# Exit on bad output
		xCAT::zvmUtils->printLn( $callback, "$out" );
		return;
	}

	xCAT::zvmUtils->printLn( $callback, "$targetNode: Done" );

	return;
}

#-------------------------------------------------------

=head3   nodeSet

	Description	: Set the boot state for a noderange 
				(Perform installation of zLinux)
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

	# Get profile
	my $profile = $propVals->{'profile'};
	if ( !$distr ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing profile for this node" );
		return;
	}

	# Get network adapter
	@propNames = ( 'primarynic', 'tftpserver' );
	$propVals = xCAT::zvmUtils->getNodeProps( 'noderes', $node, @propNames );
	my $interface = $propVals->{'primarynic'};
	if ( !$interface ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing network adapter of this node" );
		return;
	}

	# Get host IP and hostname from /etc/hosts
	my $out      = `cat /etc/hosts | grep $node`;
	my @parms    = split( ' ', $out );
	my $hostIP   = $parms[0];
	my $hostname = $parms[1];
	if ( !$hostIP || !$hostname ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing IP for $node in /etc/hosts" );
		return;
	}

	# Get NIC address from user entry
	$out = `ssh $hcp "$::DIR/getuserentry $userId" | grep "NICDEF"`;
	my @lines = split( '\n', $out );
	if ( !$lines[0] ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing NICDEF statement in user entry of node" );
		return;
	}

	# Grab the first NICDEF address
	@parms = split( ' ', $lines[0] );
	my $readChannel  = "0.0.0" . ( $parms[1] + 0 );
	my $writeChannel = "0.0.0" . ( $parms[1] + 1 );
	my $dataChannel  = "0.0.0" . ( $parms[1] + 2 );

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
	@parms = split( '=', $out );
	my $broadcast = $parms[1];
	$broadcast = xCAT::zvmUtils->trimStr($broadcast);
	$broadcast = xCAT::zvmUtils->replaceStr( $broadcast, "'", "" );

	# Load VMCP module on HCP
	$out = xCAT::zvmCPUtils->loadVmcp($hcp);

	# Sample paramter file exists in installation CD
	# Use that as a guide
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
	my $layer    = "0";

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
`sed --in-place -e "s,replace_host_address,$hostIP,g" \ -e "s,replace_long_name,$hostname,g" \ -e "s,replace_short_name,$node,g" \ -e "s,replace_domain,$domain,g" \ -e "s,replace_hostname,$node,g" \ -e "s,replace_nameserver,$node,g" \ -e "s,replace_broadcast,$broadcast,g" \ -e "s,replace_device,$device,g" \ -e "s,replace_ipaddr,$hostIP,g" \ -e "s,replace_netmask,$mask,g" \ -e "s,replace_network,$network,g" \ -e "s,replace_ccw_chan_ids,$chanIds,g" \ -e "s,replace_ccw_chan_mode,FOOBAR,g" \ -e "s,replace_gateway,$gateway,g" \ -e "s,replace_root_password,rootpw,g" $template`;

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
		$parms = $parms . "Broadcast=$network Layer2=$layer\n";
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
		$out = xCAT::zvmUtils->sendFile( $hcp, "/tmp/kernel" );
		$out = xCAT::zvmUtils->sendFile( $hcp, "/tmp/parm" );
		$out = xCAT::zvmUtils->sendFile( $hcp, "/tmp/initrd" );

		# Set the virtual unit record devices online on HCP
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", "c" );
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", "d" );

		# Purge reader
		$out = xCAT::zvmCPUtils->purgeReader( $hcp, $userId );
		xCAT::zvmUtils->printLn( $callback, "$node: Purging reader... Done" );

		# Punch kernel to reader on HCP
		$out = xCAT::zvmCPUtils->punch2Reader( $hcp, $userId, "/tmp/kernel", "sles.kernel", "" );
		if ( !( $out =~ m/$searchStr/i ) ) {
			xCAT::zvmUtils->printLn( $callback, "$node: Punching kernel to reader... Failed" );
			return;
		}
		else {
			xCAT::zvmUtils->printLn( $callback, "$node: Punching kernel to reader... Done" );
		}

		# Punch parm to reader on HCP
		$out = xCAT::zvmCPUtils->punch2Reader( $hcp, $userId, "/tmp/parm", "sles.parm", "-t" );
		if ( !( $out =~ m/$searchStr/i ) ) {
			xCAT::zvmUtils->printLn( $callback, "$node: Punching parm to reader... Failed" );
			return;
		}
		else {
			xCAT::zvmUtils->printLn( $callback, "$node: Punching parm to reader... Done" );
		}

		# Punch initrd to reader on HCP
		$out = xCAT::zvmCPUtils->punch2Reader( $hcp, $userId, "/tmp/initrd", "sles.initrd", "" );
		if ( !( $out =~ m/$searchStr/i ) ) {
			xCAT::zvmUtils->printLn( $callback, "$node: Punching initrd to reader... Failed" );
			return;
		}
		else {
			xCAT::zvmUtils->printLn( $callback, "$node: Punching initrd to reader... Done" );
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
			$i     = $i + 1;
			@parms = split( ' ', $_ );

			# Do not put a comma at the end of the last disk address
			if ( $i == @mdisks ) {
				$dasd = $dasd . "0.0.$parms[1]";
			}
			else {
				$dasd = $dasd . "0.0.$parms[1],";
			}
		}

		# Create parmfile LINUX5 PARM-R53
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
		$parms = $parms . "PORTNAME=$portName PORTNO=$portNo LAYER2=$layer\n";
		$parms = $parms . "vnc vncpassword=123456\n";

		# Write to parmfile
		$parmFile = "/tmp/parm";
		open( PARMFILE, ">$parmFile" );
		print PARMFILE "$parms";
		close(PARMFILE);

		# Send kernel, parmfile, conf, and initrd to reader to HCP
		$out = `cp /install/$distr/s390x/images/kernel.img /tmp/kernel`;
		$out = `cp /install/$distr/s390x/images/initrd.img /tmp/initrd`;
		$out = xCAT::zvmUtils->sendFile( $hcp, "/tmp/kernel" );
		$out = xCAT::zvmUtils->sendFile( $hcp, "/tmp/parm" );
		$out = xCAT::zvmUtils->sendFile( $hcp, "/tmp/initrd" );

		# Set the virtual unit record devices online
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", "c" );
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", "d" );

		# Purge reader
		$out = xCAT::zvmCPUtils->purgeReader( $hcp, $userId );
		xCAT::zvmUtils->printLn( $callback, "$node: Purging reader... Done" );

		# Punch kernel to reader on HCP
		$out = xCAT::zvmCPUtils->punch2Reader( $hcp, $userId, "/tmp/kernel", "rhel.kernel", "" );
		if ( !( $out =~ m/$searchStr/i ) ) {
			xCAT::zvmUtils->printLn( $callback, "$node: Punching kernel to reader... Failed" );
			return;
		}
		else {
			xCAT::zvmUtils->printLn( $callback, "$node: Punching kernel to reader... Done" );
		}

		# Punch parm to reader on HCP
		$out = xCAT::zvmCPUtils->punch2Reader( $hcp, $userId, "/tmp/parm", "rhel.parm", "-t" );
		if ( !( $out =~ m/$searchStr/i ) ) {
			xCAT::zvmUtils->printLn( $callback, "$node: Punching parm to reader... Failed" );
			return;
		}
		else {
			xCAT::zvmUtils->printLn( $callback, "$node: Punching parm to reader... Done" );
		}

		# Punch initrd to reader on HCP
		$out = xCAT::zvmCPUtils->punch2Reader( $hcp, $userId, "/tmp/initrd", "rhel.initrd", "" );
		if ( !( $out =~ m/$searchStr/i ) ) {
			xCAT::zvmUtils->printLn( $callback, "$node: Punching initrd to reader... Failed" );
			return;
		}
		else {
			xCAT::zvmUtils->printLn( $callback, "$node: Punching initrd to reader... Done" );
		}
	}

	# Boot node
	$out = `ssh $hcp "$::DIR/startvs $userId"`;
	my $rc = xCAT::zvmUtils->isOutputGood( $callback, $out );
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

	Description	: Collects node MAC address
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

	# Get the last 3 letters of userID
	my $hexStr = xCAT::zvmUtils->ascii2hex("123");
	xCAT::zvmUtils->printLn( $callback, "Hex string -- $hexStr" );

	return;
}
