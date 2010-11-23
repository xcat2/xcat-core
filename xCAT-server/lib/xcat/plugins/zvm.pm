# IBM(c) 2010 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1

	xCAT plugin to support z/VM (s390x)
	
=cut

#-------------------------------------------------------
package xCAT_plugin::zvm;
use xCAT::Client;
use xCAT::zvmUtils;
use xCAT::zvmCPUtils;
use xCAT::MsgUtils;
use Sys::Hostname;
use xCAT::Table;
use xCAT::Utils;
use Getopt::Long;
use strict;

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
		rpower   => 'nodehm:power,mgt',
		rinv     => 'nodehm:mgt',
		mkvm     => 'nodehm:mgt',
		rmvm     => 'nodehm:mgt',
		lsvm     => 'nodehm:mgt',
		chvm     => 'nodehm:mgt',
		rscan    => 'nodehm:mgt',
		nodeset  => 'noderes:netboot',
		getmacs  => 'nodehm:getmac,mgt',
		rnetboot => 'nodehm:mgt',

		# updatenode => 'nodehm:mgt',
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
	if ( $req->{_xcatpreprocessed}->[0] == 1 ) {
		return [$req];
	}
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

	# Directory where executables are on zHCP
	$::DIR = "/opt/zhcp/bin";

	# Process ID for xfork()
	my $pid;

	# Child process IDs
	my @children;

	#*** Power on or off a node ***
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

			# Handle 10 nodes at a time, else you will get errors
			if ( !( @children % 10 ) ) {

				# Wait for all processes to end
				foreach (@children) {
					waitpid( $_, 0 );
				}

				# Clear children
				@children = ();
			}
		}    # End of foreach
	}    # End of case

	#*** Hardware and software inventory ***
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

	#*** Create a virtual server ***
	elsif ( $command eq "mkvm" ) {

		# Determine if the argument is a node
		my $clone = 'FALSE';
		if ( $args->[0] ) {
			$clone = xCAT::zvmUtils->isZvmNode( $args->[0] );
		}

		#*** Clone virtual server ***
		if ( $clone eq 'TRUE' ) {
			cloneVM( $callback, \@nodes, $args );
		}

		#*** Create user entry ***
		# Create node based on directory entry
		# or create a NOLOG if no entry is provided
		else {
			foreach (@nodes) {
				$pid = xCAT::Utils->xfork();

				# Parent process
				if ($pid) {
					push( @children, $pid );
				}

				# Child process
				elsif ( $pid == 0 ) {

					makeVM( $callback, $_, $args );

					# Exit process
					exit(0);
				}    # End of elsif
				else {

					# Ran out of resources
					die "Error: Could not fork\n";
				}
			}    # End of foreach
		}    # End of else
	}    # End of case

	#*** Remove a virtual server ***
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

			# Handle 10 nodes at a time, else you will get errors
			if ( !( @children % 10 ) ) {

				# Wait for all processes to end
				foreach (@children) {
					waitpid( $_, 0 );
				}

				# Clear children
				@children = ();
			}
		}    # End of foreach
	}    # End of case

	#*** Print the user entry ***
	elsif ( $command eq "lsvm" ) {
		foreach (@nodes) {
			$pid = xCAT::Utils->xfork();

			# Parent process
			if ($pid) {
				push( @children, $pid );
			}

			# Child process
			elsif ( $pid == 0 ) {
				listVM( $callback, $_, $args );

				# Exit process
				exit(0);
			}
			else {

				# Ran out of resources
				die "Error: Could not fork\n";
			}

			# Handle 10 nodes at a time, else you will get errors
			if ( !( @children % 10 ) ) {

				# Wait for all processes to end
				foreach (@children) {
					waitpid( $_, 0 );
				}

				# Clear children
				@children = ();
			}
		}    # End of foreach
	}    # End of case

	#*** Change the user entry ***
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

			# Handle 10 nodes at a time, else you will get errors
			if ( !( @children % 10 ) ) {

				# Wait for all processes to end
				foreach (@children) {
					waitpid( $_, 0 );
				}

				# Clear children
				@children = ();
			}
		}    # End of foreach
	}    # End of case

	#*** Collect node information from zHCP ***
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

	#*** Set the boot state for a node ***
	elsif ( $command eq "nodeset" ) {
		foreach (@nodes) {

			# Only one file can be punched to reader at a time
			# Forking this process is not possible
			nodeSet( $callback, $_, $args );

		}    # End of foreach
	}    # End of case

	#*** Get the MAC address of a node ***
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

	#*** Boot from network ***
	elsif ( $command eq "rnetboot" ) {
		foreach (@nodes) {
			$pid = xCAT::Utils->xfork();

			# Parent process
			if ($pid) {
				push( @children, $pid );
			}

			# Child process
			elsif ( $pid == 0 ) {
				netBoot( $callback, $_, $args );

				# Exit process
				exit(0);
			}
			else {

				# Ran out of resources
				die "Error: Could not fork\n";
			}

			# Handle 10 nodes at a time, else you will get errors
			if ( !( @children % 10 ) ) {

				# Wait for all processes to end
				foreach (@children) {
					waitpid( $_, 0 );
				}

				# Clear children
				@children = ();
			}
		}    # End of foreach
	}    # End of case

	#*** Update the node (no longer supported) ***
	elsif ( $command eq "updatenode" ) {
		foreach (@nodes) {
			$pid = xCAT::Utils->xfork();

			# Parent process
			if ($pid) {
				push( @children, $pid );
			}

			# Child process
			elsif ( $pid == 0 ) {
				updateNode( $callback, $_, $args );

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

	Description	: Delete the user entry from user directory
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
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = $propVals->{'userid'};
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node ID" );
		return;
	}

	# Power off userID
	my $out = `ssh $hcp "$::DIR/stopvs $userId"`;
	xCAT::zvmUtils->printLn( $callback, "$node: $out" );

	# Delete user entry
	$out = `ssh $hcp "$::DIR/deletevs $userId"`;
	xCAT::zvmUtils->printLn( $callback, "$node: $out" );

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
 		* add3390 [disk pool] [device address] [cylinders] [mode]	[read password] [write password] [multi password]
		* add3390active [device address] [mode]
		* add9336 [disk pool] [virtual device] [block size] [mode] [blocks] [read password] [write password] [multi password]
		* addnic [address] [type] [device count]
		* addprocessor [address]
		* addvdisk [userID] [device address] [size]
		* connectnic2guestlan [address] [lan] [owner]
		* connectnic2vswitch [address] [vswitch]
		* copydisk [target address] [source node] [source address]
		* dedicatedevice [virtual device] [real device] [mode]
		* deleteipl
		* formatdisk [disk address] [multi password]
		* disconnectnic [address]
		* grantvswitch [VSwitch]
		* removedisk [virtual device]
		* removenic [address]
		* removeprocessor [address]
		* replacevs [user directory entry]
		* setipl [ipl target] [load parms] [parms]
		* setpassword [password]
	 	
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
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = $propVals->{'userid'};
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node ID" );
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
		$out = xCAT::zvmUtils->appendHostname( $node, $out );
	}

	# add3390active [device address] [mode]
	elsif ( $args->[0] eq "--add3390active" ) {
		my $addr = $args->[1];
		my $mode = $args->[2];

		$out = `ssh $hcp "$::DIR/add3390active $userId $addr $mode"`;
		$out = xCAT::zvmUtils->appendHostname( $node, $out );
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
		$out = xCAT::zvmUtils->appendHostname( $node, $out );
	}

	# addnic [address] [type] [device count]
	elsif ( $args->[0] eq "--addnic" ) {
		my $addr     = $args->[1];
		my $type     = $args->[2];
		my $devcount = $args->[3];

		$out = `ssh $hcp "$::DIR/addnic $userId $addr $type $devcount"`;
		$out = xCAT::zvmUtils->appendHostname( $node, $out );
	}

	# addprocessor [type] address]
	elsif ( $args->[0] eq "--addprocessor" ) {
		my $type = $args->[1];
		my $addr = $args->[2];

		$out = `ssh $hcp "$::DIR/addprocessor $userId $type $addr"`;
		$out = xCAT::zvmUtils->appendHostname( $node, $out );
	}

	# addprocessoractive [address] [type]
	elsif ( $args->[0] eq "--addprocessoractive" ) {
		my $addr = $args->[1];
		my $type = $args->[2];

		$out = xCAT::zvmCPUtils->defineCpu( $node, $addr, $type );
		$out = xCAT::zvmUtils->appendHostname( $node, $out );
	}

	# addvdisk [device address] [size]
	elsif ( $args->[0] eq "--addvdisk" ) {
		my $addr = $args->[1];
		my $size = $args->[2];

		$out = `ssh $hcp "$::DIR/addvdisk $userId $addr $size"`;
		$out = xCAT::zvmUtils->appendHostname( $node, $out );
	}

	# connectnic2guestlan [address] [lan] [owner]
	elsif ( $args->[0] eq "--connectnic2guestlan" ) {
		my $addr  = $args->[1];
		my $lan   = $args->[2];
		my $owner = $args->[3];

		$out = `ssh $hcp "$::DIR/connectnic2guestlan $userId $addr $lan $owner"`;
		$out = xCAT::zvmUtils->appendHostname( $node, $out );
	}

	# connectnic2vswitch [address] [vswitch]
	elsif ( $args->[0] eq "--connectnic2vswitch" ) {
		my $addr    = $args->[1];
		my $vswitch = $args->[2];

		# Connect to VSwitch
		$out = `ssh $hcp "$::DIR/connectnic2vswitch $userId $addr $vswitch"`;

		# Grant access to VSWITCH for Linux user
		$out .= "Granting access to VSWITCH for $userId\n  ";
		$out .= `ssh $hcp "vmcp set vswitch $vswitch grant $userId"`;
		$out = xCAT::zvmUtils->appendHostname( $node, $out );
	}

	# copydisk [target address] [source node] [source address]
	elsif ( $args->[0] eq "--copydisk" ) {
		my $tgtNode   = $node;
		my $tgtUserId = $userId;
		my $tgtAddr   = $args->[1];
		my $srcNode   = $args->[2];
		my $srcAddr   = $args->[3];

		# Get source userID
		@propNames = ( 'hcp', 'userid' );
		$propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $srcNode, @propNames );
		my $sourceId = $propVals->{'userid'};

		#*** Link and copy disk ***
		my $rc;
		my $try;
		my $srcDevNode;
		my $tgtDevNode;

		# Link source disk to HCP
		my $srcLinkAddr;
		$try = 10;
		while ( $try > 0 ) {

			# New disk address
			$srcLinkAddr = $srcAddr + 1000;

			# Check if new disk address is used (source)
			$rc = xCAT::zvmUtils->isAddressUsed( $hcp, $srcLinkAddr );

			# If disk address is used (source)
			while ( $rc == 0 ) {

				# Generate a new disk address
				# Sleep 5 seconds to let existing disk appear
				sleep(5);
				$srcLinkAddr = $srcLinkAddr + 1;
				$rc = xCAT::zvmUtils->isAddressUsed( $hcp, $srcLinkAddr );
			}

			# Link source disk
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: Linking source disk ($srcAddr) as ($srcLinkAddr)" );
			$out = `ssh -o ConnectTimeout=5 $hcp "vmcp link $sourceId $srcAddr $srcLinkAddr MR"`;

			# If link fails
			if ( $out =~ m/not linked/i ) {

				# Wait before trying again
				sleep(5);

				$try = $try - 1;
			}
			else {
				last;
			}
		}    # End of while ( $try > 0 )

		# Link target disk to HCP
		my $tgtLinkAddr;
		$try = 10;
		while ( $try > 0 ) {

			# New disk address
			$tgtLinkAddr = $tgtAddr + 2000;

			# Check if new disk address is used (target)
			$rc = xCAT::zvmUtils->isAddressUsed( $hcp, $tgtLinkAddr );

			# If disk address is used (target)
			while ( $rc == 0 ) {

				# Generate a new disk address
				# Sleep 5 seconds to let existing disk appear
				sleep(5);
				$tgtLinkAddr = $tgtLinkAddr + 1;
				$rc = xCAT::zvmUtils->isAddressUsed( $hcp, $tgtLinkAddr );
			}

			# Link target disk
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: Linking target disk ($tgtAddr) as ($tgtLinkAddr)" );
			$out = `ssh -o ConnectTimeout=5 $hcp "vmcp link $tgtUserId $tgtAddr $tgtLinkAddr MR"`;

			# If link fails
			if ( $out =~ m/not linked/i ) {

				# Wait before trying again
				sleep(5);

				$try = $try - 1;
			}
			else {
				last;
			}
		}    # End of while ( $try > 0 )

		# If target disk is not linked
		if ( $out =~ m/not linked/i ) {
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Failed to link target disk ($tgtAddr)" );
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: Failed" );

			# Exit
			return;
		}

		# If source disk is not linked
		if ( $out =~ m/not linked/i ) {
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Failed to link source disk ($srcAddr)" );
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: Failed" );

			# Exit
			return;
		}

		#*** Use flashcopy ***
		$out = `ssh $hcp "vmcp flashcopy"`;
		if ( $out =~ m/HCPNFC026E/i ) {

			# Flashcopy is supported
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: Copying source disk ($srcLinkAddr) to target disk ($tgtLinkAddr) using FLASHCOPY" );

			# Check for flashcopy lock
			my $wait = 0;
			while ( `ssh $hcp "ls /tmp/.flashcopy_lock"` && $wait < 90 ) {

				# Wait until the lock dissappears
				# 90 seconds wait limit
				sleep(2);
				$wait = $wait + 2;
			}

			# If flashcopy locks still exists
			if (`ssh $hcp "ls /tmp/.flashcopy_lock"`) {

				# Detatch disks from HCP
				$out = `ssh $hcp "vmcp det $tgtLinkAddr"`;
				$out = `ssh $hcp "vmcp det $srcLinkAddr"`;

				xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Flashcopy lock is enabled" );
				return;
			}
			else {

				# Enable lock
				$out = `ssh $hcp "touch /tmp/.flashcopy_lock"`;

				# Flashcopy source disk
				$out = xCAT::zvmCPUtils->flashCopy( $hcp, $srcLinkAddr, $tgtLinkAddr );
				$rc = xCAT::zvmUtils->checkOutput( $callback, $out );
				if ( $rc == -1 ) {
					xCAT::zvmUtils->printLn( $callback, "$tgtNode: $out" );

					# Detatch disks from HCP
					$out = `ssh $hcp "vmcp det $tgtAddr"`;
					$out = `ssh $hcp "vmcp det $srcLinkAddr"`;

					# Remove lock
					$out = `ssh $hcp "rm -f /tmp/.flashcopy_lock"`;
					return;
				}

				# Remove lock
				$out = `ssh $hcp "rm -f /tmp/.flashcopy_lock"`;
			}
		}
		else {

			# Flashcopy not supported

			#*** Use Linux dd to copy ***
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: FLASHCOPY not supported.  Using Linux DD" );

			# Enable disks
			$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", $tgtLinkAddr );
			$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", $srcLinkAddr );

			# Determine source device node
			$srcDevNode = xCAT::zvmUtils->getDeviceNode($hcp, $srcLinkAddr);

			# Determine target device node
			$tgtDevNode = xCAT::zvmUtils->getDeviceNode($hcp, $tgtLinkAddr);

			# Format target disk
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: Formating target disk ($tgtDevNode)" );
			$out = `ssh $hcp "dasdfmt -b 4096 -y -f /dev/$tgtDevNode"`;

			# Check for errors
			$rc = xCAT::zvmUtils->checkOutput( $callback, $out );
			if ( $rc == -1 ) {
				xCAT::zvmUtils->printLn( $callback, "$tgtNode: $out" );
				return;
			}

			# Sleep 2 seconds to let the system settle
			sleep(2);

			# Copy source disk to target disk (4096 block size)
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: Copying source disk ($srcDevNode) to target disk ($tgtDevNode)" );
			$out = `ssh $hcp "dd if=/dev/$srcDevNode of=/dev/$tgtDevNode bs=4096"`;

			# Disable disks
			$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-d", $tgtLinkAddr );
			$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-d", $srcLinkAddr );

			# Check for error
			$rc = xCAT::zvmUtils->checkOutput( $callback, $out );
			if ( $rc == -1 ) {
				xCAT::zvmUtils->printLn( $callback, "$tgtNode: $out" );

				# Detatch disks from HCP
				$out = `ssh $hcp "vmcp det $tgtLinkAddr"`;
				$out = `ssh $hcp "vmcp det $srcLinkAddr"`;

				return;
			}

			# Sleep 2 seconds to let the system settle
			sleep(2);
		}

		# Detatch disks from HCP
		xCAT::zvmUtils->printLn( $callback, "$tgtNode: Detatching target disk ($tgtLinkAddr)" );
		xCAT::zvmUtils->printLn( $callback, "$tgtNode: Detatching source disk ($srcLinkAddr)" );
		$out = `ssh $hcp "vmcp det $tgtLinkAddr"`;
		$out = `ssh $hcp "vmcp det $srcLinkAddr"`;

		$out = "$tgtNode: Done";
	}

	# dedicatedevice [virtual device] [real device] [mode]
	elsif ( $args->[0] eq "--dedicatedevice" ) {
		my $vaddr = $args->[1];
		my $raddr = $args->[2];
		my $mode  = $args->[3];

		$out = `ssh $hcp "$::DIR/dedicatedevice $userId $vaddr $raddr $mode"`;
		$out = xCAT::zvmUtils->appendHostname( $node, $out );
	}

	# deleteipl
	elsif ( $args->[0] eq "--deleteipl" ) {
		$out = `ssh $hcp "$::DIR/deleteipl $userId"`;
		$out = xCAT::zvmUtils->appendHostname( $node, $out );
	}

	# formatdisk [address] [multi password]
	elsif ( $args->[0] eq "--formatdisk" ) {
		my $tgtNode   = $node;
		my $tgtUserId = $userId;
		my $tgtAddr   = $args->[1];

		#*** Link and format disk ***
		my $rc;
		my $try;
		my $tgtDevNode;

		# Link target disk to HCP
		my $tgtLinkAddr;
		$try = 10;
		while ( $try > 0 ) {

			# New disk address
			$tgtLinkAddr = $tgtAddr + 1000;

			# Check if new disk address is used (target)
			$rc = xCAT::zvmUtils->isAddressUsed( $hcp, $tgtLinkAddr );

			# If disk address is used (target)
			while ( $rc == 0 ) {

				# Generate a new disk address
				# Sleep 5 seconds to let existing disk appear
				sleep(5);
				$tgtLinkAddr = $tgtLinkAddr + 1;
				$rc = xCAT::zvmUtils->isAddressUsed( $hcp, $tgtLinkAddr );
			}

			# Link target disk
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: Linking target disk ($tgtAddr) as ($tgtLinkAddr)" );
			$out = `ssh -o ConnectTimeout=5 $hcp "vmcp link $tgtUserId $tgtAddr $tgtLinkAddr MR"`;

			# If link fails
			if ( $out =~ m/not linked/i ) {

				# Wait before trying again
				sleep(5);

				$try = $try - 1;
			}
			else {
				last;
			}
		}    # End of while ( $try > 0 )

		# If target disk is not linked
		if ( $out =~ m/not linked/i ) {
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Failed to link target disk ($tgtAddr)" );
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: Failed" );

			# Exit
			return;
		}

		#*** Format disk ***
		my @words;
		if ( $rc == -1 ) {

			# Enable disk
			$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", $tgtLinkAddr );

			# Determine target device node
			$tgtDevNode = xCAT::zvmUtils->getDeviceNode($hcp, $tgtLinkAddr);

			# Format target disk
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: Formating target disk ($tgtDevNode)" );
			$out = `ssh $hcp "dasdfmt -b 4096 -y -f /dev/$tgtDevNode"`;

			# Check for errors
			$rc = xCAT::zvmUtils->checkOutput( $callback, $out );
			if ( $rc == -1 ) {
				xCAT::zvmUtils->printLn( $callback, "$tgtNode: $out" );
				return;
			}

			# Sleep 2 seconds to let the system settle
			sleep(2);
		}

		# Disable disk
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-d", $tgtLinkAddr );

		# Detatch disk from HCP
		xCAT::zvmUtils->printLn( $callback, "$tgtNode: Detatching target disk ($tgtLinkAddr)" );
		$out = `ssh $hcp "vmcp det $tgtLinkAddr"`;

		$out = "$tgtNode: Done";
	}

	# grantvswitch [VSwitch]
	elsif ( $args->[0] eq "--grantvswitch" ) {
		my $vsw = $args->[1];

		$out = xCAT::zvmCPUtils->grantVSwitch( $callback, $hcp, $userId, $vsw );
		$out = xCAT::zvmUtils->appendHostname( $node, $out );
	}

	# disconnectnic [address]
	elsif ( $args->[0] eq "--disconnectnic" ) {
		my $addr = $args->[1];

		$out = `ssh $hcp "$::DIR/disconnectnic $userId $addr"`;
		$out = xCAT::zvmUtils->appendHostname( $node, $out );
	}

	# removedisk [virtual device address]
	elsif ( $args->[0] eq "--removedisk" ) {
		my $addr = $args->[1];

		$out = `ssh $hcp "$::DIR/removemdisk $userId $addr"`;
		$out = xCAT::zvmUtils->appendHostname( $node, $out );
	}

	# removenic [address]
	elsif ( $args->[0] eq "--removenic" ) {
		my $addr = $args->[1];

		$out = `ssh $hcp "$::DIR/removenic $userId $addr"`;
		$out = xCAT::zvmUtils->appendHostname( $node, $out );
	}

	# removeprocessor [address]
	elsif ( $args->[0] eq "--removeprocessor" ) {
		my $addr = $args->[1];

		$out = `ssh $hcp "$::DIR/removeprocessor $userId $addr"`;
		$out = xCAT::zvmUtils->appendHostname( $node, $out );
	}

	# replacevs [file]
	elsif ( $args->[0] eq "--replacevs" ) {
		my $file = $args->[1];

		# Target system (HCP), e.g. root@gpok2.endicott.ibm.com
		my $target = "root@";
		$target .= $hcp;
		if ($file) {

			# SCP file over to HCP
			$out = `scp $file $target:$file`;

			# Replace user directory entry
			$out = `ssh $hcp "$::DIR/replacevs $userId $file"`;
			$out = xCAT::zvmUtils->appendHostname( $node, $out );
		}
		else {
			$out = "$node: (Error) No user entry file specified";
			xCAT::zvmUtils->printLn( $callback, "$out" );
			return;
		}
	}

	# resetsmapi
	elsif ( $args->[0] eq "--resetsmapi" ) {		
		# Force each worker machine off
		my @workers = ('VSMWORK1', 'VSMWORK2', 'VSMWORK3', 'VSMREQIN', 'VSMREQIU');
		foreach ( @workers ) {
			$out = `ssh $hcp "vmcp force $_ logoff immediate"`;
		}
				
		# Log on VSMWORK1
		$out = `ssh $hcp "vmcp xautolog VSMWORK1"`;
		
		$out = "$node: Resetting SMAPI... Done";
	}
	
	# setipl [ipl target] [load parms] [parms]
	elsif ( $args->[0] eq "--setipl" ) {
		my $trgt      = $args->[1];
		my $loadparms = $args->[2];
		my $parms     = $args->[3];

		$out = `ssh $hcp "$::DIR/setipl $userId $trgt $loadparms $parms"`;
		$out = xCAT::zvmUtils->appendHostname( $node, $out );
	}

	# setpassword [password]
	elsif ( $args->[0] eq "--setpassword" ) {
		my $pw = $args->[1];

		$out = `ssh $hcp "$::DIR/setpassword $userId $pw"`;
		$out = xCAT::zvmUtils->appendHostname( $node, $out );
	}

	# Otherwise, print out error
	else {
		$out = "$node: (Error) Option not supported";
	}

	xCAT::zvmUtils->printLn( $callback, "$out" );
	return;
}

#-------------------------------------------------------

=head3   powerVM

	Description	: Power on or off a given node
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
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = $propVals->{'userid'};
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node ID" );
		return;
	}

	# Output string
	my $out;

	# Power on virtual server
	if ( $args->[0] eq 'on' ) {
		$out = `ssh $hcp "$::DIR/startvs $userId"`;
		xCAT::zvmUtils->printLn( $callback, "$node: $out" );
	}

	# Power off virtual server
	elsif ( $args->[0] eq 'off' ) {
		$out = `ssh $hcp "$::DIR/stopvs $userId"`;
		xCAT::zvmUtils->printLn( $callback, "$node: $out" );
	}

	# Get the status (on|off)
	elsif ( $args->[0] eq 'stat' ) {
		$out = `ssh $hcp "vmcp q user $userId 2>/dev/null" | sed 's/HCPCQU045E.*/off/' | sed 's/$userId.*/on/'`;

		# Wait for output
		my $max = 0;
		while ( !$out && $max < 10 ) {
			$out = `ssh $hcp "vmcp q user $userId 2>/dev/null" | sed 's/HCPCQU045E.*/off/' | sed 's/$userId.*/on/'`;
			$max++;
		}

		xCAT::zvmUtils->printLn( $callback, "$node: $out" );
	}

	# Reset a virtual server
	elsif ( $args->[0] eq 'reset' ) {

		$out = `ssh $hcp "$::DIR/stopvs $userId"`;
		xCAT::zvmUtils->printLn( $callback, "$node: $out" );

		# Wait for output
		while ( `vmcp q user $userId 2>/dev/null | sed 's/HCPCQU045E.*/Done/'` != "Done" ) {

			# Do nothing
		}

		$out = `ssh $hcp "$::DIR/startvs $userId"`;
		xCAT::zvmUtils->printLn( $callback, "$node: $out" );
	}
	else {
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Option not supported" );
	}
	return;
}

#-------------------------------------------------------

=head3   scanVM

	Description	: Get node information from zHCP
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
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = $propVals->{'userid'};
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node ID" );
		return;
	}

	# Print output string
	# [Node name]:
	#	objtype=node
	#   id=[userID]
	#   arch=[Architecture]
	#   hcp=[HCP node name]
	#   groups=[Group]
	#   mgt=zvm
	#
	# gpok123:
	#	objtype=node
	#   id=LINUX123
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

	# Search for nodes managed by given HCP
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

		# Get operating system (not to be saved)
		$os = xCAT::zvmUtils->getOs($managedNode);

		# Get architecture
		$arch = xCAT::zvmCPUtils->getArch($managedNode);

		# Create output string
		$str .= "$managedNode:\n";
		$str .= "  objtype=node\n";
		$str .= "  userid=$id\n";
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

	Description	: Get hardware and software inventory of a given node
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
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = $propVals->{'userid'};
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node ID" );
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
		my $arch = xCAT::zvmUtils->getArch($node);

		# Get operating system
		my $os = xCAT::zvmUtils->getOs($node);

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
		my $arch = xCAT::zvmUtils->getArch($node);

		# Get operating system
		my $os = xCAT::zvmUtils->getOs($node);

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
		$str = "$node: (Error) Option not supported";
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

	Description	: Show the info for a given node
    Arguments	: 	Node
 					Option
 		
 	Options supported:
 		* getnetworknames
 		* getnetwork [networkname]
 		* diskpoolnames
 		* diskpool [pool name] [space (free or used)]
		
    Returns		: Nothing
    Example		: listVM($callback, $node);
    
=cut

#-------------------------------------------------------
sub listVM {

	# Get inputs
	my ( $callback, $node, $args ) = @_;

	# Set cache directory
	my $cache = '/var/opt/zhcp/.vmapi/.cache';

	# Get node properties from 'zvm' table
	my @propNames = ( 'hcp', 'userid' );
	my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

	# Get HCP
	my $hcp = $propVals->{'hcp'};
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = $propVals->{'userid'};
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node ID" );
		return;
	}

	my $out;

	# Get disk pool names
	if ( $args->[0] eq "--diskpoolnames" ) {
		my $file = "$cache/diskpoolnames";
		
		# If a cache for disk pool names exists
		if (`ssh $hcp "ls $file"`) {
			# Get current Epoch
			my $curTime = time();
			# Get time of last change as seconds since Epoch
			my $fileTime = xCAT::zvmUtils->trimStr(`ssh $hcp "stat -c %Z $file"`);
			
			# If the current time is greater than 5 minutes of the file timestamp
			my $interval = 300;		# 300 seconds = 5 minutes * 60 seconds/minute
			if ($curTime > $fileTime + $interval) {
				# Get disk pool names and save it in a file
				$out = `ssh $hcp "$::DIR/getdiskpoolnames $userId > $file"`;
			}
		} else {
			# Get disk pool names and save it in a file
			$out = `ssh $hcp "$::DIR/getdiskpoolnames $userId > $file"`;
		}
		
		# Print out the file contents
		$out = `ssh $hcp "cat $file"`;
	}

	# Get disk pool configuration
	elsif ( $args->[0] eq "--diskpool" ) {
		my $pool  = $args->[1];
		my $space = $args->[2];

		$out = `ssh $hcp "$::DIR/getdiskpool $userId $pool $space"`;
	}

	# Get network names
	elsif ( $args->[0] eq "--getnetworknames" ) {
		$out = xCAT::zvmCPUtils->getNetworkNames($hcp);
	}

	# Get network
	elsif ( $args->[0] eq "--getnetwork" ) {
		my $netName = $args->[1];

		$out = xCAT::zvmCPUtils->getNetwork( $hcp, $netName );
	}

	# Get user entry
	elsif ( !$args->[0] ) {
		$out = `ssh $hcp "$::DIR/getuserentry $userId"`;
	}

	else {
		$out = "$node: (Error) Option not supported";
	}

	# Append hostname (e.g. gpok3) in front
	$out = xCAT::zvmUtils->appendHostname( $node, $out );
	xCAT::zvmUtils->printLn( $callback, "$out" );

	return;
}

#-------------------------------------------------------

=head3   makeVM

	Description	: Create a virtual server 
				  	* A unique MAC address will be assigned
    Arguments	: 	Node
    				User entry text file (optional)
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
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = $propVals->{'userid'};
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node ID" );
		return;
	}

	# Get user entry file (if any)
	my $userEntry = $args->[0];

	# Create virtual server
	my $out;
	my $target = "root@" . $hcp;
	if ($userEntry) {

		# Get MAC address in 'mac' table
		my $macId;
		my $generateNew = 0;
		@propNames = ('mac');
		$propVals = xCAT::zvmUtils->getNodeProps( 'mac', $node, @propNames );
		if ( $propVals->{'mac'} ) {

			# Get MAC suffix (MACID)
			$macId = $propVals->{'mac'};
			$macId = xCAT::zvmUtils->replaceStr( $macId, ":", "" );
			$macId = substr( $macId, 6 );
		}
		else {

			# If no MACID is found, get one
			$macId = xCAT::zvmUtils->getMacID($hcp);
			if ( !$macId ) {
				xCAT::zvmUtils->printLn( $callback, "$node: (Error) Could not generate MACID" );
				return;
			}

			# Set flag to generate new MACID after virtual server is created
			$generateNew = 1;
		}

		# If the user entry contains a NICDEF statement
		$out = `cat $userEntry | egrep -i "NICDEF"`;
		my @lines;
		my @words;
		if ($out) {

			# Get the network used by the HCP
			$out   = `ssh $hcp "vmcp q v nic" | egrep -i "VSWITCH|LAN"`;
			@lines = split( '\n', $out );

			# There should only be one network
			my $line = xCAT::zvmUtils->trimStr( $lines[0] );
			@words = split( ' ', $line );
			my $netName = $words[4];

			# Find NICDEF statement
			my $oldNicDef = `cat $userEntry | egrep -i "NICDEF" | egrep -i "$netName"`;
			$oldNicDef = xCAT::zvmUtils->trimStr($oldNicDef);
			my $nicDef = xCAT::zvmUtils->replaceStr( $oldNicDef, $netName, "$netName MACID $macId" );

			# Append MACID at the end
			$out = `sed --in-place -e "s,$oldNicDef,$nicDef,g" $userEntry`;
		}

		# SCP file over to HCP
		$out = `scp $userEntry $target:$userEntry`;

		# Create virtual server
		$out = `ssh $hcp "$::DIR/createvs $userId $userEntry"`;
		xCAT::zvmUtils->printLn( $callback, "$node: $out" );

		# Check output
		my $rc = xCAT::zvmUtils->checkOutput( $callback, $out );
		if ( $rc == 0 ) {

			# Get VSwitch of HCP (if any)
			my @vswId = xCAT::zvmCPUtils->getVswitchId($hcp);

			# Grant access to VSwitch for Linux user
			# GuestLan do not need permissions
			foreach (@vswId) {
				xCAT::zvmUtils->printLn( $callback, "$node: Granting VSwitch ($_) access for $userId" );
				$out = xCAT::zvmCPUtils->grantVSwitch( $callback, $hcp, $userId, $_ );
				xCAT::zvmUtils->printLn( $callback, "$node: $out" );
			}

			# Get HCP MAC address
			# The HCP should only have (1) network and (1) MAC address
			xCAT::zvmCPUtils->loadVmcp($hcp);
			$out   = `ssh -o ConnectTimeout=5 $hcp "vmcp q v nic" | grep "MAC:"`;
			if ($out) {
				@lines = split( "\n", $out );
				@words = split( " ", $lines[0] );

				# Extract MAC prefix
				my $prefix = $words[1];
				$prefix = xCAT::zvmUtils->replaceStr( $prefix, "-", "" );
				$prefix = substr( $prefix, 0, 6 );

				# Generate MAC address
				my $mac = $prefix . $macId;

				# If length is less than 12, append a zero
				if ( length($mac) != 12 ) {
					$mac = "0" . $mac;
				}
	
				# Format MAC address
				$mac =
				    substr( $mac, 0, 2 ) . ":"
				  . substr( $mac, 2,  2 ) . ":"
				  . substr( $mac, 4,  2 ) . ":"
				  . substr( $mac, 6,  2 ) . ":"
				  . substr( $mac, 8,  2 ) . ":"
				  . substr( $mac, 10, 2 );
	
				# Save MAC address in 'mac' table
				xCAT::zvmUtils->setNodeProp( 'mac', $node, 'mac', $mac );
			} else {
				xCAT::zvmUtils->printLn( $callback, "$node: (Error) Could not find the MAC address of the zHCP" );
			}

			# Generate new MACID
			if ( $generateNew == 1 ) {
				$out = xCAT::zvmUtils->generateMacId($hcp);
			}

			# Remove user entry file (on HCP)
			$out = `ssh -o ConnectTimeout=5 $hcp "rm $userEntry"`;
		}
	}
	else {

		# Create NOLOG virtual server
		$out = `ssh $hcp "$::DIR/createvs $userId"`;
		xCAT::zvmUtils->printLn( $callback, "$node: $out" );
	}

	return;
}

#-------------------------------------------------------

=head3   cloneVM

	Description	: Clone a virtual server
    Arguments	: 	Node 
    				Disk pool
    				Disk password
    Returns		: Nothing
    Example		: cloneVM($callback, $targetNode, $args);
    
=cut

#-------------------------------------------------------
sub cloneVM {

	# Get inputs
	my ( $callback, $nodes, $args ) = @_;

	# Get nodes
	my @nodes = @$nodes;

	# Return code for each command
	my $rc;
	my $out;

	# Child process IDs
	my @children;

	# Process ID for xfork()
	my $pid;

	# Get source node
	my $sourceNode = $args->[0];
	my @propNames  = ( 'hcp', 'userid' );
	my $propVals   = xCAT::zvmUtils->getNodeProps( 'zvm', $sourceNode, @propNames );

	# Get HCP
	my $srcHcp = $propVals->{'hcp'};

	# Get node userID
	my $sourceId = $propVals->{'userid'};

	foreach (@nodes) {
		xCAT::zvmUtils->printLn( $callback, "$_: Cloning $sourceNode" );

		# Exit if missing source node
		if ( !$sourceNode ) {
			xCAT::zvmUtils->printLn( $callback, "$_: (Error) Missing source node" );
			return;
		}

		# Exit if missing source HCP
		if ( !$srcHcp ) {
			xCAT::zvmUtils->printLn( $callback, "$_: (Error) Missing source node HCP" );
			return;
		}

		# Exit if missing source user ID
		if ( !$sourceId ) {
			xCAT::zvmUtils->printLn( $callback, "$_: (Error) Missing source node ID" );
			return;
		}

		# Get target node
		@propNames = ( 'hcp', 'userid' );
		$propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $_, @propNames );

		# Get target HCP
		my $tgtHcp = $propVals->{'hcp'};

		# Get node userID
		my $tgtId = $propVals->{'userid'};

		# Exit if missing target HCP
		if ( !$tgtHcp ) {
			xCAT::zvmUtils->printLn( $callback, "$_: (Error) Missing target node HCP" );
			return;
		}

		# Exit if missing target user ID
		if ( !$tgtId ) {
			xCAT::zvmUtils->printLn( $callback, "$_: (Error) Missing target node ID" );
			return;
		}

		# Exit if source and target HCP are not equal
		if ( $srcHcp ne $tgtHcp ) {
			xCAT::zvmUtils->printLn( $callback, "$_: (Error) Source and target HCP are not equal" );
			return;
		}

		#*** Get MAC address ***
		my $targetMac;
		my $macId;
		my $generateNew = 0;    # Flag to generate new MACID
		@propNames = ('mac');
		$propVals = xCAT::zvmUtils->getNodeProps( 'mac', $_, @propNames );
		if ( !$propVals->{'mac'} ) {

			# If no MACID is found, get one
			$macId = xCAT::zvmUtils->getMacID($tgtHcp);
			if ( !$macId ) {
				xCAT::zvmUtils->printLn( $callback, "$_: (Error) Could not generate MACID" );
				return;
			}

			# Create MAC address (target)
			$targetMac = xCAT::zvmUtils->createMacAddr( $_, $macId );

			# Save MAC address in 'mac' table
			xCAT::zvmUtils->setNodeProp( 'mac', $_, 'mac', $targetMac );

			# Generate new MACID
			$out = xCAT::zvmUtils->generateMacId($tgtHcp);
		}
	}

	#*** Link source disks ***
	# Get MDisk statements of source node
	my @words;
	my $addr;
	my $type;
	my $srcMultiPw;
	my $linkAddr;

	# Load vmcp module
	xCAT::zvmCPUtils->loadVmcp($sourceNode);

	# Hash table of source disk addresses
	# $srcLinkAddr[$addr] = $linkAddr
	my %srcLinkAddr;
	my %srcDiskSize;

	# Hash table of source disk type
	# $srcLinkAddr[$addr] = $type
	my %srcDiskType;

	my @srcDisks = xCAT::zvmUtils->getMdisks( $callback, $sourceNode );
	foreach (@srcDisks) {

		# Get disk address
		@words      = split( ' ', $_ );
		$addr       = $words[1];
		$type       = $words[2];
		$srcMultiPw = $words[9];

		# Get disk type
		$srcDiskType{$addr} = $type;

		# Get disk size (cylinders or blocks)
		# ECKD or FBA disk
		if ( $type eq '3390' || $type eq '9336' ) {
			$out                = `ssh -o ConnectTimeout=5 $sourceNode "vmcp q v dasd" | grep "DASD $addr"`;
			@words              = split( ' ', $out );
			$srcDiskSize{$addr} = xCAT::zvmUtils->trimStr( $words[5] );
		}

		# If source disk is not linked
		my $try = 10;
		while ( $try > 0 ) {

			# New disk address
			$linkAddr = $addr + 1000;

			# Check if new disk address is used (source)
			$rc = xCAT::zvmUtils->isAddressUsed( $srcHcp, $linkAddr );

			# If disk address is used (source)
			while ( $rc == 0 ) {

				# Generate a new disk address
				# Sleep 5 seconds to let existing disk appear
				sleep(5);
				$linkAddr = $linkAddr + 1;
				$rc = xCAT::zvmUtils->isAddressUsed( $srcHcp, $linkAddr );
			}

			$srcLinkAddr{$addr} = $linkAddr;

			# Link source disk to HCP
			foreach (@nodes) {
				xCAT::zvmUtils->printLn( $callback, "$_: Linking source disk ($addr) as ($linkAddr)" );
			}
			$out = `ssh -o ConnectTimeout=5 $srcHcp "vmcp link $sourceId $addr $linkAddr RR $srcMultiPw"`;

			if ( $out =~ m/not linked/i ) {

				# Do nothing
			}
			else {
				last;
			}

			$try = $try - 1;

			# Wait before next try
			sleep(5);
		}    # End of while ( $try > 0 )

		# If source disk is not linked
		if ( $out =~ m/not linked/i ) {
			foreach (@nodes) {
				xCAT::zvmUtils->printLn( $callback, "$_: Failed" );
			}

			# Exit
			return;
		}

		# Enable source disk
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $srcHcp, "-e", $linkAddr );

	}    # End of foreach (@srcDisks)

	# Get the network name the HCP is on
	$out = `ssh $srcHcp "vmcp q v nic" | egrep -i "VSWITCH|LAN"`;
	my @lines = split( '\n', $out );
	my $line = xCAT::zvmUtils->trimStr( $lines[0] );
	@words = split( ' ', $line );
	my $hcpNetName = $words[4];

	# Get the NICDEF address of the network on the source node
	my @tmp;
	my $i;
	my $hcpNicAddr;

	# Find the NIC address
	xCAT::zvmCPUtils->loadVmcp($sourceNode);
	$out = `ssh $sourceNode "vmcp q v nic"`;
	@lines = split( '\n', $out );
	for ( $i = 0 ; $i < @lines ; $i++ ) {
		if ( $lines[$i] =~ m/$hcpNetName/i ) {
			$line       = xCAT::zvmUtils->trimStr( $lines[ $i - 1 ] );
			@words      = split( ' ', $line );
			@tmp        = split( /\./, $words[1] );
			$hcpNicAddr = $tmp[0];
			last;
		}
	}

	# Exit if network address is not found
	if ( $out && !$hcpNicAddr ) {
		foreach (@nodes) {
			xCAT::zvmUtils->printLn( $callback, "$_: (Error) Node is not on the same network ($hcpNetName) as the hardware control point" );
		}
		return;
	}

	# Get VSwitch of source node (if any)
	my @srcVswitch = xCAT::zvmCPUtils->getVswitchId($sourceNode);

	# Get device address that is the root partition (/)
	my $srcRootPartAddr = xCAT::zvmUtils->getRootDeviceAddr($sourceNode);

	# Get source node OS
	my $srcOs = xCAT::zvmUtils->getOs($sourceNode);

	# Get source MAC address in 'mac' table
	my $srcMac;
	@propNames = ('mac');
	$propVals = xCAT::zvmUtils->getNodeProps( 'mac', $sourceNode, @propNames );
	if ( $propVals->{'mac'} ) {

		# Get MAC address
		$srcMac = $propVals->{'mac'};
	}

	# Get network configuration file
	# Location of this file depends on the OS
	my $srcIfcfg = xCAT::zvmUtils->getIfcfgByNic( $sourceNode, "0.0." . $hcpNicAddr );

	# Get source hardware configuration (SUSE only)
	my $srcHwcfg = '';
	if ( $srcOs =~ m/SUSE/i ) {
		$srcHwcfg = xCAT::zvmUtils->getHwcfg($sourceNode);
	}

	# Get user entry of source node
	my $srcUserEntry = "/tmp/$sourceNode.txt";
	$out = `rm $srcUserEntry`;
	$out = xCAT::zvmUtils->getUserEntryWODisk( $callback, $sourceNode, $srcUserEntry );

	# Check if user entry is valid
	$out = `cat $srcUserEntry`;

	# If output contains USER LINUX123, then user entry is good
	if ( $out =~ m/USER $sourceId/i ) {

		# Turn off source node
		$out = `ssh $srcHcp "$::DIR/stopvs $sourceId"`;
		foreach (@nodes) {
			xCAT::zvmUtils->printLn( $callback, "$_: $out" );
		}

		#*** Clone source node ***
		# Remove flashcopy lock (if any)
		$out = `ssh $srcHcp "rm -f /tmp/.flashcopy_lock"`;
		foreach (@nodes) {
			$pid = xCAT::Utils->xfork();

			# Parent process
			if ($pid) {
				push( @children, $pid );
			}

			# Child process
			elsif ( $pid == 0 ) {

				clone(
					$callback, $_, $args, \@srcDisks, \%srcLinkAddr, \%srcDiskSize, \%srcDiskType, 
					$hcpNicAddr, $hcpNetName, \@srcVswitch, $srcOs, $srcMac, $srcRootPartAddr, $srcIfcfg, 
					$srcHwcfg
				);

				# Exit process
				exit(0);
			}

			# End of elsif
			else {

				# Ran out of resources
				die "Error: Could not fork\n";
			}

			# Clone 4 nodes at a time
			# If you handle more than this, some nodes will not be cloned
			# You will get errors because SMAPI cannot handle many nodes
			if ( !( @children % 4 ) ) {

				# Wait for all processes to end
				foreach (@children) {
					waitpid( $_, 0 );
				}

				# Clear children
				@children = ();
			}
		}    # End of foreach

		# Handle the remaining nodes
		# Wait for all processes to end
		foreach (@children) {
			waitpid( $_, 0 );
		}

		# Remove source user entry
		$out = `rm $srcUserEntry`;
	}    # End of if

	#*** Detatch source disks ***
	for $addr ( keys %srcLinkAddr ) {
		$linkAddr = $srcLinkAddr{$addr};

		# Disable and detatch source disk
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $srcHcp, "-d", $linkAddr );
		$out = `ssh -o ConnectTimeout=5 $srcHcp "vmcp det $linkAddr"`;

		foreach (@nodes) {
			xCAT::zvmUtils->printLn( $callback, "$_: Detatching source disk ($addr) at ($linkAddr)" );
		}
	}

	# Turn back on source node
	$out = `ssh $srcHcp "$::DIR/startvs $sourceId"`;
	foreach (@nodes) {
		xCAT::zvmUtils->printLn( $callback, "$_: $out" );
	}

	#*** Done ***
	foreach (@nodes) {
		xCAT::zvmUtils->printLn( $callback, "$_: Done" );
	}

	return;
}

#-------------------------------------------------------

=head3   clone

	Description	: Clone a virtual server
    Arguments	: 	Target node
    				Disk pool
    				Disk password (optional)
    				Source disks
    				Source disk link addresses
    				Source disk sizes
    				NIC address
    				Network name
    				VSwitch names (if any)
    				Operating system
    				MAC address
    				Root parition device address
    				Path to network configuration file
    				Path to hardware configuration file (SUSE only)
    Returns		: Nothing
    Example		: clone($callback, $_, $args, \@srcDisks, \%srcLinkAddr, \%srcDiskSize, 
    				$hcpNicAddr, $hcpNetName, \@srcVswitch, $srcOs, $srcMac, 
    				$srcRootPartAddr, $srcIfcfg, $srcHwcfg);
    
=cut

#-------------------------------------------------------
sub clone {

	# Get inputs
	my (
		$callback, $tgtNode, $args, $srcDisksRef, $srcLinkAddrRef, $srcDiskSizeRef, $srcDiskTypeRef, 
		$hcpNicAddr, $hcpNetName, $srcVswitchRef, $srcOs, $srcMac, $srcRootPartAddr, $srcIfcfg, $srcHwcfg
	  )
	  = @_;

	# Get source node properties from 'zvm' table
	my $sourceNode = $args->[0];
	my @propNames  = ( 'hcp', 'userid' );
	my $propVals   = xCAT::zvmUtils->getNodeProps( 'zvm', $sourceNode, @propNames );

	# Get HCP
	my $srcHcp = $propVals->{'hcp'};

	# Get node userID
	my $sourceId = $propVals->{'userid'};

	# Get source disks
	my @srcDisks    = @$srcDisksRef;
	my %srcLinkAddr = %$srcLinkAddrRef;
	my %srcDiskSize = %$srcDiskSizeRef;
	my %srcDiskType = %$srcDiskTypeRef;
	my @srcVswitch  = @$srcVswitchRef;

	# Return code for each command
	my $rc;

	# Get node properties from 'zvm' table
	@propNames = ( 'hcp', 'userid' );
	$propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $tgtNode, @propNames );

	# Get HCP
	my $hcp = $propVals->{'hcp'};
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Missing node HCP" );
		return;
	}

	# Get node userID
	my $tgtUserId = $propVals->{'userid'};
	if ( !$tgtUserId ) {
		xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Missing node ID" );
		return;
	}

	# Exit if source node HCP is not the same as target node HCP
	if ( !( $srcHcp eq $hcp ) ) {
		xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Source node HCP ($srcHcp) is not the same as target node HCP ($hcp)" );
		return;
	}

	# Get target IP from /etc/hosts
	my $targetIp = xCAT::zvmUtils->getIp($tgtNode);
	if ( !$targetIp ) {
		xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Missing IP for $tgtNode in /etc/hosts" );
		return;
	}

	my $out;
	my @lines;
	my @words;

	# Get disk pool and multi password
	my $i;
	my %inputs;
	foreach $i ( 1 .. 2 ) {
		if ( $args->[$i] ) {

			# Split parameters by '='
			@words = split( "=", $args->[$i] );

			# Create hash array
			$inputs{ $words[0] } = $words[1];
		}
	}

	# Get disk pool
	my $pool = $inputs{"pool"};
	if ( !$pool ) {
		xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Missing disk pool" );
		return;
	}

	# Get multi password
	# It is Ok not have a password
	my $tgtPw = $inputs{"pw"};

	# Set IP address
	my $sourceIp = xCAT::zvmUtils->getIp($sourceNode);

	# Save user directory entry as /tmp/hostname.txt, e.g. /tmp/gpok3.txt
	# The source user entry is retrieved in cloneVM()
	my $userEntry    = "/tmp/$tgtNode.txt";
	my $srcUserEntry = "/tmp/$sourceNode.txt";

	# Remove existing user entry if any
	$out = `rm $userEntry`;
	$out = `ssh -o ConnectTimeout=5 $hcp "rm $userEntry"`;

	# Copy user entry of source node
	$out = `cp $srcUserEntry $userEntry`;

	# Replace source userID with target userID
	$out = `sed --in-place -e "s,$sourceId,$tgtUserId,g" $userEntry`;

	# Get target MAC address in 'mac' table
	my $targetMac;
	my $macId;
	my $generateNew = 0;    # Flag to generate new MACID
	@propNames = ('mac');
	$propVals = xCAT::zvmUtils->getNodeProps( 'mac', $tgtNode, @propNames );
	if ($propVals) {

		# Get MACID
		$targetMac = $propVals->{'mac'};
		$macId     = $propVals->{'mac'};
		$macId     = xCAT::zvmUtils->replaceStr( $macId, ":", "" );
		$macId     = substr( $macId, 6 );
	}
	else {
		xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Missing target MAC address" );
		return;
	}

	# If the user entry contains a NICDEF statement
	$out = `cat $userEntry | egrep -i "NICDEF"`;
	if ($out) {

		# Get the network used by the HCP
		$out   = `ssh $hcp "vmcp q v nic" | egrep -i "VSWITCH|LAN"`;
		@lines = split( '\n', $out );

		# There should only be one network
		my $line = xCAT::zvmUtils->trimStr( $lines[0] );
		@words = split( ' ', $line );
		my $hcpNetName = $words[4];

		# If the user entry contains a MACID
		$out = `cat $userEntry | egrep -i "MACID"`;
		if ($out) {
			my $pos = rindex( $out, "MACID" );
			my $oldMacId = substr( $out, $pos + 6, 12 );
			$oldMacId = xCAT::zvmUtils->trimStr($oldMacId);

			# Replace old MACID
			$out = `sed --in-place -e "s,$oldMacId,$macId,g" $userEntry`;
		}
		else {

			# Find NICDEF statement
			my $oldNicDef = `cat $userEntry | egrep -i "NICDEF" | egrep -i "$hcpNetName"`;
			$oldNicDef = xCAT::zvmUtils->trimStr($oldNicDef);
			my $nicDef = xCAT::zvmUtils->replaceStr( $oldNicDef, $hcpNetName, "$hcpNetName MACID $macId" );

			# Append MACID at the end
			$out = `sed --in-place -e "s,$oldNicDef,$nicDef,g" $userEntry`;
		}
	}

	# SCP user entry file over to HCP
	xCAT::zvmUtils->sendFile( $hcp, $userEntry, $userEntry );

	#*** Create new virtual server ***
	my $try = 10;
	while ( $try > 0 ) {
		if ( $try > 9 ) {
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: Creating user directory entry" );
		}
		else {
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: Trying again ($try) to create user directory entry" );
		}
		$out = `ssh $hcp "$::DIR/createvs $tgtUserId $userEntry"`;

		# Check if user entry is created
		$out = `ssh $hcp "$::DIR/getuserentry $tgtUserId"`;
		$rc  = xCAT::zvmUtils->checkOutput( $callback, $out );

		if ( $rc == -1 ) {

			# Wait before trying again
			sleep(5);

			$try = $try - 1;
		}
		else {
			last;
		}
	}

	# Remove user entry
	$out = `rm $userEntry`;
	$out = `ssh -o ConnectTimeout=5 $hcp "rm $userEntry"`;

	# Exit on bad output
	if ( $rc == -1 ) {
		xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Could not create user entry" );
		return;
	}

	# Load VMCP module on HCP and source node
	xCAT::zvmCPUtils->loadVmcp($hcp);

	# Grant access to VSwitch for Linux user
	# GuestLan do not need permissions
	foreach (@srcVswitch) {
		xCAT::zvmUtils->printLn( $callback, "$tgtNode: Granting VSwitch ($_) access for $tgtUserId" );
		$out = xCAT::zvmCPUtils->grantVSwitch( $callback, $hcp, $tgtUserId, $_ );

		# Check for errors
		$rc = xCAT::zvmUtils->checkOutput( $callback, $out );
		if ( $rc == -1 ) {

			# Exit on bad output
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: $out" );
			return;
		}
	}    # End of foreach (@vswitchId)

	#*** Add MDisk to target user entry ***
	my $addr;
	my @tgtDisks;
	my $type;
	my $mode;
	my $cyl;
	my $srcMultiPw;
	foreach (@srcDisks) {

		# Get disk address
		@words = split( ' ', $_ );
		$addr = $words[1];
		push( @tgtDisks, $addr );
		$type       = $words[2];
		$mode       = $words[6];
		$srcMultiPw = $words[9];

		# Add ECKD disk
		if ( $type eq '3390' ) {

			# Get disk size (cylinders)
			$cyl = $srcDiskSize{$addr};

			$try = 10;
			while ( $try > 0 ) {

				# Add ECKD disk
				if ( $try > 9 ) {
					xCAT::zvmUtils->printLn( $callback, "$tgtNode: Adding minidisk ($addr)" );
				}
				else {
					xCAT::zvmUtils->printLn( $callback, "$tgtNode: Trying again ($try) to add minidisk ($addr)" );
				}
				$out = `ssh $hcp "$::DIR/add3390 $tgtUserId $pool $addr $cyl $mode $tgtPw $tgtPw $tgtPw"`;

				# Check output
				$rc = xCAT::zvmUtils->checkOutput( $callback, $out );
				if ( $rc == -1 ) {

					# Wait before trying again
					sleep(5);

					# One less try
					$try = $try - 1;
				}
				else {

					# If output is good, exit loop
					last;
				}
			}    # End of while ( $try > 0 )

			# Exit on bad output
			if ( $rc == -1 ) {
				xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Could not create user entry" );
				return;
			}
		}    # End of if ( $type eq '3390' )

		# Add FBA disk
		elsif ( $type eq '9336' ) {

			# Get disk size (blocks)
			my $blkSize = '512';
			my $blks    = $srcDiskSize{$addr};

			$try = 10;
			while ( $try > 0 ) {

				# Add FBA disk
				if ( $try > 9 ) {
					xCAT::zvmUtils->printLn( $callback, "$tgtNode: Adding minidisk ($addr)" );
				}
				else {
					xCAT::zvmUtils->printLn( $callback, "$tgtNode: Trying again ($try) to add minidisk ($addr)" );
				}
				$out = `ssh $hcp "$::DIR/add9336 $tgtUserId $pool $addr $blkSize $blks $mode $tgtPw $tgtPw $tgtPw"`;

				# Check output
				$rc = xCAT::zvmUtils->checkOutput( $callback, $out );
				if ( $rc == -1 ) {

					# Wait before trying again
					sleep(5);

					# One less try
					$try = $try - 1;
				}
				else {

					# If output is good, exit loop
					last;
				}
			}    # End of while ( $try > 0 )

			# Exit on bad output
			if ( $rc == -1 ) {
				xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Could not create user entry" );
				return;
			}
		}    # End of elsif ( $type eq '9336' )
	}

	# Check if the number of disks in target user entry
	# is equal to the number of disks added
	my @disks;
	$try = 10;
	while ( $try > 0 ) {

		# Get disks within user entry
		$out = `ssh $hcp "$::DIR/getuserentry $tgtUserId" | grep "MDISK"`;
		@disks = split( '\n', $out );
		xCAT::zvmUtils->printLn( $callback, "$tgtNode: Disks added (" . @tgtDisks . "). Disks in user entry (" . @disks . ")" );

		if ( @disks != @tgtDisks ) {
			$try = $try - 1;

			# Wait before trying again
			sleep(5);
		}
		else {
			last;
		}
	}

	# Exit if all disks are not present
	if ( @disks != @tgtDisks ) {
		xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Disks not present in user entry" );
		return;
	}

	#*** Link, format, and copy source disks ***
	my $srcAddr;
	my $tgtAddr;
	my $srcDevNode;
	my $tgtDevNode;
	my $tgtDiskType;
	foreach (@tgtDisks) {

		#*** Link target disk ***
		$try = 10;
		while ( $try > 0 ) {

			# New disk address
			$srcAddr = $srcLinkAddr{$_};
			$tgtAddr = $_ + 2000;

			# Check if new disk address is used (target)
			$rc = xCAT::zvmUtils->isAddressUsed( $hcp, $tgtAddr );

			# If disk address is used (target)
			while ( $rc == 0 ) {

				# Generate a new disk address
				# Sleep 5 seconds to let existing disk appear
				sleep(5);
				$tgtAddr = $tgtAddr + 1;
				$rc = xCAT::zvmUtils->isAddressUsed( $hcp, $tgtAddr );
			}

			# Link target disk
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: Linking target disk ($_) as ($tgtAddr)" );
			$out = `ssh -o ConnectTimeout=5 $hcp "vmcp link $tgtUserId $_ $tgtAddr MR $tgtPw"`;

			# If link fails
			if ( $out =~ m/not linked/i ) {

				# Wait before trying again
				sleep(5);

				$try = $try - 1;
			}
			else {
				last;
			}
		}    # End of while ( $try > 0 )

		# If target disk is not linked
		if ( $out =~ m/not linked/i ) {
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Failed to link target disk ($_)" );
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: Failed" );

			# Exit
			return;
		}
		
		# Get disk type (3390 or 9336)
		$tgtDiskType = $srcDiskType{$_};
		
		#*** Use flashcopy ***
		# Flashcopy only supports ECKD volumes
		$out = `ssh $hcp "vmcp flashcopy"`;
		if ( ($out =~ m/HCPNFC026E/i) && ($tgtDiskType eq '3390')) {

			# Flashcopy is supported
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: Copying source disk ($srcAddr) to target disk ($tgtAddr) using FLASHCOPY" );

			# Check for flashcopy lock
			my $wait = 0;
			while ( `ssh $hcp "ls /tmp/.flashcopy_lock"` && $wait < 90 ) {

				# Wait until the lock dissappears
				# 90 seconds wait limit
				sleep(2);
				$wait = $wait + 2;
			}

			# If flashcopy locks still exists
			if (`ssh $hcp "ls /tmp/.flashcopy_lock"`) {

				# Detatch disks from HCP
				$out = `ssh $hcp "vmcp det $tgtAddr"`;
				xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Flashcopy lock is enabled" );
				return;
			}
			else {

				# Enable lock
				$out = `ssh $hcp "touch /tmp/.flashcopy_lock"`;

				# Flashcopy source disk
				$out = xCAT::zvmCPUtils->flashCopy( $hcp, $srcAddr, $tgtAddr );
				$rc = xCAT::zvmUtils->checkOutput( $callback, $out );
				if ( $rc == -1 ) {
					xCAT::zvmUtils->printLn( $callback, "$tgtNode: $out" );

					# Detatch disks from HCP
					$out = `ssh $hcp "vmcp det $tgtAddr"`;

					# Remove lock
					$out = `ssh $hcp "rm -f /tmp/.flashcopy_lock"`;
					return;
				}

				# Wait a while for flashcopy to completely finish
				sleep(10);

				# Remove lock
				$out = `ssh $hcp "rm -f /tmp/.flashcopy_lock"`;
			}
		}
		else {

			# Flashcopy not supported

			#*** Use Linux dd to copy ***
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: FLASHCOPY not supported.  Using Linux DD" );

			# Enable target disk
			$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", $tgtAddr );

			# Determine source device node
			$srcDevNode = xCAT::zvmUtils->getDeviceNode($hcp, $srcAddr);

			# Determine target device node
			$tgtDevNode = xCAT::zvmUtils->getDeviceNode($hcp, $tgtAddr);

			# Format target disk
			# Only ECKD disks need to be formated
			if ($tgtDiskType eq '3390') {
				xCAT::zvmUtils->printLn( $callback, "$tgtNode: Formating target disk ($tgtAddr)" );
				$out = `ssh $hcp "dasdfmt -b 4096 -y -f /dev/$tgtDevNode"`;

				# Check for errors
				$rc = xCAT::zvmUtils->checkOutput( $callback, $out );
				if ( $rc == -1 ) {
					xCAT::zvmUtils->printLn( $callback, "$tgtNode: $out" );
					return;
				}
	
				# Sleep 2 seconds to let the system settle
				sleep(2);
			
				# Copy source disk to target disk
				xCAT::zvmUtils->printLn( $callback, "$tgtNode: Copying source disk ($srcAddr) to target disk ($tgtAddr)" );
				$out = `ssh $hcp "dd if=/dev/$srcDevNode of=/dev/$tgtDevNode bs=4096"`;
			} else {
				# Copy source disk to target disk
				# Block size = 512
				xCAT::zvmUtils->printLn( $callback, "$tgtNode: Copying source disk ($srcAddr) to target disk ($tgtAddr)" );
				$out = `ssh $hcp "dd if=/dev/$srcDevNode of=/dev/$tgtDevNode bs=512"`;
				
				# Force Linux to re-read partition table
				xCAT::zvmUtils->printLn( $callback, "$tgtNode: Forcing Linux to re-read partition table" );
				$out = 
`ssh $hcp "cat<<EOM | fdisk /dev/$tgtDevNode
p
w
EOM"`;
			}
						
			# Check for error
			$rc = xCAT::zvmUtils->checkOutput( $callback, $out );
			if ( $rc == -1 ) {
				xCAT::zvmUtils->printLn( $callback, "$tgtNode: $out" );
				return;
			}

			# Sleep 2 seconds to let the system settle
			sleep(2);
		}

		# Disable and enable target disk
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-d", $tgtAddr );
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", $tgtAddr );

		# Determine target device node (it might have changed)
		$tgtDevNode = xCAT::zvmUtils->getDeviceNode($hcp, $tgtAddr);

		# Get disk address that is the root partition (/)
		if ( $_ eq $srcRootPartAddr ) {

			# Mount target disk
			my $cloneMntPt = "/mnt/$tgtUserId";
			$tgtDevNode .= "1";

			xCAT::zvmUtils->printLn( $callback, "$tgtNode: Mounting /dev/$tgtDevNode to $cloneMntPt" );

			# Check the disk is mounted
			$try = 10;
			while ( !(`ssh $hcp "ls $cloneMntPt/etc/"`) && $try > 0 ) {
				$out = `ssh $hcp "mkdir -p $cloneMntPt"`;
				$out = `ssh $hcp "mount /dev/$tgtDevNode $cloneMntPt"`;

				# Wait before trying again
				sleep(10);
				$try = $try - 1;
			}

			# If the disk is not mounted
			if ( !(`ssh $hcp "ls $cloneMntPt/etc/"`) ) {
				xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Could not mount /dev/$tgtDevNode" );

				# Flush disk
				$out = `ssh $hcp "sync"`;

				# Unmount disk
				$out = `ssh $hcp "umount $cloneMntPt"`;

				# Remove mount point
				$out = `ssh $hcp "rm -rf $cloneMntPt"`;

				# Disable disks
				$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-d", $tgtAddr );

				# Detatch disks from HCP
				$out = `ssh $hcp "vmcp det $tgtAddr"`;

				return;
			}

			#*** Set network configuration ***
			# Set hostname
			xCAT::zvmUtils->printLn( $callback, "$tgtNode: Setting network configuration" );
			$out = `ssh $hcp sed --in-place -e "s/$sourceNode/$tgtNode/g" $cloneMntPt/etc/HOSTNAME`;

			# If Red Hat - Set hostname in /etc/sysconfig/network
			if ( $srcOs =~ m/Red Hat/i ) {
				$out = `ssh $hcp sed --in-place -e "s/$sourceNode/$tgtNode/g" $cloneMntPt/etc/sysconfig/network`;
			}

			# Get network configuration file
			# Location of this file depends on the OS
			my $ifcfgPath = $cloneMntPt;
			$ifcfgPath .= $srcIfcfg;
			$out = `ssh $hcp sed --in-place -e "s/$sourceNode/$tgtNode/g" \ -e "s/$sourceIp/$targetIp/g" $cloneMntPt/etc/hosts`;
			$out = `ssh $hcp sed --in-place -e "s/$sourceIp/$targetIp/g" \ -e "s/$sourceNode/$tgtNode/g" $ifcfgPath`;

			# Set MAC address
			my $networkFile = $tgtNode . "NetworkConfig";
			if ( $srcOs =~ m/Red Hat/i ) {

				# Red Hat only
				$out = `ssh $hcp "cat $ifcfgPath" | grep -v "MACADDR" > /tmp/$networkFile`;
				$out = `echo "MACADDR='$targetMac'" >> /tmp/$networkFile`;
			}
			else {

				# SUSE only
				$out = `ssh $hcp "cat $ifcfgPath" | grep -v "LLADDR" | grep -v "UNIQUE" > /tmp/$networkFile`;
				$out = `echo "LLADDR='$targetMac'" >> /tmp/$networkFile`;
				$out = `echo "UNIQUE=''" >> /tmp/$networkFile`;
			}
			xCAT::zvmUtils->sendFile( $hcp, "/tmp/$networkFile", $ifcfgPath );

			# Remove network file from /tmp
			$out = `rm /tmp/$networkFile`;

			# Set to hardware configuration (Only for layer 2)
			my $layer = xCAT::zvmCPUtils->getNetworkLayer( $hcp, $hcpNetName );
			if ( $layer == 2 ) {

				#*** Red Hat ***
				if ( $srcOs =~ m/Red Hat/i ) {
					my $srcMac;

					# Get source MAC address in 'mac' table
					@propNames = ('mac');
					$propVals = xCAT::zvmUtils->getNodeProps( 'mac', $sourceNode, @propNames );
					if ($propVals) {

						# Get MAC address
						$srcMac = $propVals->{'mac'};
					}
					else {
						xCAT::zvmUtils->printLn( $callback, "$tgtNode: (Error) Could not find MAC address of $sourceNode" );

						# Unmount disk
						$out = `ssh $hcp "umount $cloneMntPt"`;

						# Disable disks
						$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-d", $tgtAddr );

						# Detatch disks from HCP
						$out = `ssh $hcp "vmcp det $tgtAddr"`;

						return;
					}

					# Set MAC address
					$out = `ssh $hcp sed --in-place -e "s/$srcMac/$targetMac/g" $ifcfgPath`;
				}

				#*** SUSE ***
				else {

					# Get hardware configuration
					my $hwcfgPath = $cloneMntPt;

					# Set layer 2 support
					$hwcfgPath .= $srcHwcfg;
					my $hardwareFile = $tgtNode . "HardwareConfig";
					$out = `ssh $hcp "cat $hwcfgPath" | grep -v "QETH_LAYER2_SUPPORT" > /tmp/$hardwareFile`;
					$out = `echo "QETH_LAYER2_SUPPORT='1'" >> /tmp/$hardwareFile`;
					xCAT::zvmUtils->sendFile( $hcp, "/tmp/$hardwareFile", $hwcfgPath );

					# Remove hardware file from /tmp
					$out = `rm /tmp/$hardwareFile`;
				}
			}    # End of if ( $layer == 2 )

			# Remove old SSH keys
			$out = `ssh $hcp "rm -f $cloneMntPt/etc/ssh/ssh_host_*"`;

			# Flush disk
			$out = `ssh $hcp "sync"`;

			# Unmount disk
			$out = `ssh $hcp "umount $cloneMntPt"`;

			# Remove mount point
			$out = `ssh $hcp "rm -rf $cloneMntPt"`;
		}

		# Disable disks
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-d", $tgtAddr );

		# Detatch disks from HCP
		$out = `ssh $hcp "vmcp det $tgtAddr"`;

		sleep(5);
	}    # End of foreach (@tgtDisks)

	# Update DHCP
	$out = `makedhcp -a`;

	# Power on target virtual server
	xCAT::zvmUtils->printLn( $callback, "$tgtNode: Powering on" );
	$out = `ssh $hcp "$::DIR/startvs $tgtUserId"`;

	# Check for error
	$rc = xCAT::zvmUtils->checkOutput( $callback, $out );
	if ( $rc == -1 ) {
		xCAT::zvmUtils->printLn( $callback, "$tgtNode: $out" );
		return;
	}
}

#-------------------------------------------------------

=head3   nodeSet

	Description	: Set the boot state for a node 
					* Punch initrd, kernel, and parmfile to node reader
					* Layer 2 and 3 VSwitch/Lan supported
    Arguments	: Node
    Returns		: Nothing
    Example		: nodeSet($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub nodeSet {

	# Get inputs
	my ( $callback, $node, $args ) = @_;

	# Get node properties from 'zvm' table
	my @propNames = ( 'hcp', 'userid' );
	my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

	# Get HCP
	my $hcp = $propVals->{'hcp'};
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = $propVals->{'userid'};
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node ID" );
		return;
	}

	# Get install directory and domain from site table
	my $siteTab        = xCAT::Table->new('site');
	my $installDirHash = $siteTab->getAttribs( { key => "installdir" }, 'value' );
	my $installDir     = $installDirHash->{'value'};
	my $domainHash     = $siteTab->getAttribs( { key => "domain" }, 'value' );
	my $domain         = $domainHash->{'value'};
	my $masterHash     = $siteTab->getAttribs( { key => "master" }, 'value' );
	my $master         = $masterHash->{'value'};
	my $xcatdPortHash  = $siteTab->getAttribs( { key => "xcatdport" }, 'value' );
	my $xcatdPort      = $xcatdPortHash->{'value'};

	# Get node OS, arch, and profile from 'nodetype' table
	@propNames = ( 'os', 'arch', 'profile' );
	$propVals = xCAT::zvmUtils->getNodeProps( 'nodetype', $node, @propNames );

	my $os      = $propVals->{'os'};
	my $arch    = $propVals->{'arch'};
	my $profile = $propVals->{'profile'};

	# If no OS, arch, or profile is found
	if ( !$os || !$arch || !$profile ) {

		# Exit
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node OS, arch, and profile in nodetype table" );
		return;
	}

	# Get action
	my $action = $args->[0];
	my $out;
	if ( $action eq "install" ) {

		# Get node root password
		@propNames = ('password');
		$propVals = xCAT::zvmUtils->getTabPropsByKey( 'passwd', 'key', 'system', @propNames );
		my $passwd = $propVals->{'password'};
		if ( !$passwd ) {
			xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing root password for this node" );
			return;
		}

		# Get node OS base
		my @tmp;
		if ( $os =~ m/sp/i ) {
			@tmp = split( /sp/, $os );
		} else {
			@tmp = split( /\./, $os );
		}
		my $osBase = $tmp[0];

		# Get autoyast/kickstart template
		my $tmpl = "$profile.$osBase.$arch.tmpl";

		# Get host IP and hostname from /etc/hosts
		$out = `cat /etc/hosts | grep "$node "`;
		my @words    = split( ' ', $out );
		my $hostIP   = $words[0];
		my $hostname = $words[2];
		if ( !$hostIP || !$hostname ) {
			xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing IP for $node in /etc/hosts" );
			return;
		}

		# Get the network name the HCP is on
		$out = `ssh $hcp "vmcp q v nic" | egrep -i "VSWITCH|LAN"`;
		my @lines = split( '\n', $out );
		my $line = xCAT::zvmUtils->trimStr( $lines[0] );
		@words = split( ' ', $line );
		my $hcpNetName = $words[4];

		# Get NIC address from user entry
		my $userEntry = `ssh $hcp "$::DIR/getuserentry $userId"`;
		$out = `echo "$userEntry" | grep "NICDEF" | grep "$hcpNetName"`;
		if (!$out) {
			# Check for user profile
			my $profileName = `echo "$userEntry" | grep "INCLUDE"`;
			if ($profileName) {
				@words = split( ' ', xCAT::zvmUtils->trimStr($profileName) );
				
				# Get user profile
				my $userProfile = xCAT::zvmUtils->getUserProfile($hcp, $words[1]);
				# Get the NICDEF statement containing the HCP network
				$out = `echo "$userProfile" | grep "NICDEF" | grep "$hcpNetName"`;
			}
		}

		# If no NICDEF is found, exit
		if ( !$out ) {
			xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing NICDEF statement in user entry of node" );
			return;
		}

		# Grab first NICDEF address
		@lines = split( '\n', $out );
		@words = split( ' ',  $lines[0] );
		my $readChannel;
		my $writeChannel;
		my $dataChannel;

		# Convert subchannel to decimal
		my $channel = sprintf('%d', hex($words[1]));

		$readChannel = "0.0." . ( sprintf('%X', $channel + 0) );
		if ( length($readChannel) < 8 ) {

			# Prepend a zero
			$readChannel = "0.0.0" . ( sprintf('%X', $channel + 0) );
		}

		$writeChannel = "0.0." . ( sprintf('%X', $channel + 1) );
		if ( length($writeChannel) < 8 ) {

			# Prepend a zero
			$writeChannel = "0.0.0" . ( sprintf('%X', $channel + 1) );
		}

		$dataChannel = "0.0." . ( sprintf('%X', $channel + 2) );
		if ( length($dataChannel) < 8 ) {

			# Prepend a zero
			$dataChannel = "0.0.0" . ( sprintf('%X', $channel + 2) );
		}

		# Get network type (Layer 2 or 3)
		$out = `ssh $hcp "vmcp q lan $hcpNetName"`;
		if ( !$out ) {
			xCAT::zvmUtils->printLn( $callback, "$node: (Error) Could not determine network type (layer 2 or 3)" );
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

		# Get MAC address (Only for layer 2)
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
				xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing MAC address of node" );
				return;
			}
		}

		# Get first 3 octets of node IP (IPv4)
		@words = split( /\./, $hostIP );
		my $octets = "$words[0].$words[1].$words[2]";

		# Get networks in 'networks' table
		my $entries = xCAT::zvmUtils->getAllTabEntries('networks');

		# Go through each network
		my $network;
		foreach (@$entries) {

			# Get network
			$network = $_->{'net'};

			# If networks contains the first 3 octets of the node IP
			if ( $network =~ m/$octets/i ) {

				# Exit loop
				last;
			}
			else {
				$network = "";
			}
		}

		# If no network found
		if ( !$network ) {

			# Exit
			xCAT::zvmUtils->printLn( $callback, "$node: (Error) Node does not belong to any network in the networks table" );
			return;
		}

		@propNames = ( 'mask', 'gateway', 'tftpserver', 'nameservers' );
		$propVals = xCAT::zvmUtils->getTabPropsByKey( 'networks', 'net', $network, @propNames );
		my $mask       = $propVals->{'mask'};
		my $gateway    = $propVals->{'gateway'};
		my $ftp        = $propVals->{'tftpserver'};
		my $nameserver = $propVals->{'nameservers'};
		if ( !$network || !$mask || !$ftp || !$nameserver ) {

			# It is acceptable to not have a gateway
			xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing network information" );
			return;
		}

		# Get broadcast address of NIC
		my $ifcfg = xCAT::zvmUtils->getIfcfgByNic( $hcp, $readChannel );
		$out = `ssh $hcp "cat $ifcfg" | grep "BROADCAST"`;
		@words = split( '=', $out );
		my $broadcast = $words[1];
		$broadcast = xCAT::zvmUtils->trimStr($broadcast);
		$broadcast =~ s;"|';;g;

		# Load VMCP module on HCP
		xCAT::zvmCPUtils->loadVmcp($hcp);

		# Sample paramter file exists in installation CD (Use that as a guide)
		my $sampleParm;
		my $parmHeader;
		my $parms;
		my $parmFile;
		my $kernelFile;
		my $initFile;

		# If punch is successful - Look for this string
		my $searchStr = "created and transferred";

		# Default parameters - SUSE
		my $instNetDev   = "osa";     # Only OSA interface type is supported
		my $osaInterface = "qdio";    # OSA interface = qdio or lcs
		my $osaMedium    = "eth";     # OSA medium = eth (ethernet) or tr (token ring)

		# Default parameters - RHEL
		my $netType  = "qeth";
		my $portName = "FOOBAR";
		my $portNo   = "0";

		# Get postscript content
		my $postScript;
		if ( $os =~ m/sles10/i ) {
			$postScript = "/opt/xcat/share/xcat/install/scripts/post.sles10.s390x";
		} elsif ( $os =~ m/sles11/i ) {
			$postScript = "/opt/xcat/share/xcat/install/scripts/post.sles11.s390x";
		} elsif ( $os =~ m/rhel5/i ) {
			$postScript = "/opt/xcat/share/xcat/install/scripts/post.rhel5.s390x";
		} else {
			xCAT::zvmUtils->printLn( $callback, "$node: (Error) No postscript available for $os" );
			return;
		}

		# SUSE installation
		my $customTmpl;
		if ( $os =~ m/sles/i ) {

			# Create directory in FTP root (/install) to hold template
			$out = `mkdir -p $installDir/custom/install/sles`;

			# Copy autoyast template
			$customTmpl = "$installDir/custom/install/sles/" . $node . "." . $profile . ".tmpl";
			if ( -e "$installDir/custom/install/sles/$tmpl" ) {
				$out = `cp $installDir/custom/install/sles/$tmpl $customTmpl`;
			}
			else {
				xCAT::zvmUtils->printLn( $callback, "$node: (Error) An autoyast template does not exist for $os in $installDir/custom/install/sles/" );
				return;
			}

			# Copy postscript into template
			$out = `sed --in-place -e "/<scripts>/r $postScript" $customTmpl`;

			# Edit template
			my $device;
			my $chanIds = "$readChannel $writeChannel $dataChannel";

			# SLES 11
			if ( $os =~ m/sles11/i ) {
				$device = "eth0";
			}
			else {

				# SLES 10
				$device = "qeth-bus-ccw-$readChannel";
			}

			$out =
`sed --in-place -e "s,replace_host_address,$hostIP,g" \ -e "s,replace_long_name,$hostname,g" \ -e "s,replace_short_name,$node,g" \ -e "s,replace_domain,$domain,g" \ -e "s,replace_hostname,$node,g" \ -e "s,replace_nameserver,$nameserver,g" \ -e "s,replace_broadcast,$broadcast,g" \ -e "s,replace_device,$device,g" \ -e "s,replace_ipaddr,$hostIP,g" \ -e "s,replace_lladdr,$mac,g" \ -e "s,replace_netmask,$mask,g" \ -e "s,replace_network,$network,g" \ -e "s,replace_ccw_chan_ids,$chanIds,g" \ -e "s,replace_ccw_chan_mode,FOOBAR,g" \ -e "s,replace_gateway,$gateway,g" \ -e "s,replace_root_password,$passwd,g" \ -e "s,replace_nic_addr,$readChannel,g" \ -e "s,replace_master,$master,g" \ -e "s,replace_install_dir,$installDir,g" $customTmpl`;

			# Read sample parmfile in /install/sles10.2/s390x/1/boot/s390x/
			$sampleParm = "$installDir/$os/s390x/1/boot/s390x/parmfile";
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

			# Create parmfile -- Limited to 10 lines
			# End result should be:
			# 	ramdisk_size=65536 root=/dev/ram1 ro init=/linuxrc TERM=dumb
			# 	HostIP=10.0.0.5 Hostname=gpok5.endicott.ibm.com
			# 	Gateway=10.0.0.1 Netmask=255.255.255.0
			# 	Broadcast=10.0.0.0 Layer2=1 OSAHWaddr=02:00:01:FF:FF:FF
			# 	ReadChannel=0.0.0800  WriteChannel=0.0.0801  DataChannel=0.0.0802
			# 	Nameserver=9.0.2.11 Portname=OSAPORT Portno=0
			#	Install=ftp://10.0.0.1/sles10.2/s390x/1/
			#	UseVNC=1  VNCPassword=12345678
			#	InstNetDev=osa OsaInterface=qdio OsaMedium=eth Manual=0
			my $ay = "ftp://$ftp/custom/install/sles/" . $node . "." . $profile . ".tmpl";

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
			$parms = $parms . "Nameserver=$nameserver Portname=$portName Portno=0\n";
			$parms = $parms . "Install=ftp://$ftp/$os/s390x/1/\n";
			$parms = $parms . "UseVNC=1 VNCPassword=12345678\n";
			$parms = $parms . "InstNetDev=$instNetDev OsaInterface=$osaInterface OsaMedium=$osaMedium Manual=0\n";

			# Write to parmfile
			$parmFile = "/tmp/" . $node . "Parm";
			open( PARMFILE, ">$parmFile" );
			print PARMFILE "$parms";
			close(PARMFILE);

			# Send kernel, parmfile, and initrd to reader to HCP
			$kernelFile = "/tmp/" . $node . "Kernel";
			$initFile   = "/tmp/" . $node . "Initrd";
			$out        = `cp $installDir/$os/s390x/1/boot/s390x/vmrdr.ikr $kernelFile`;
			$out        = `cp $installDir/$os/s390x/1/boot/s390x/initrd $initFile`;
			xCAT::zvmUtils->sendFile( $hcp, $kernelFile, $kernelFile );
			xCAT::zvmUtils->sendFile( $hcp, $parmFile,   $parmFile );
			xCAT::zvmUtils->sendFile( $hcp, $initFile,   $initFile );

			# Set the virtual unit record devices online on HCP
			$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", "c" );
			$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", "d" );

			# Purge reader
			$out = xCAT::zvmCPUtils->purgeReader( $hcp, $userId );
			xCAT::zvmUtils->printLn( $callback, "$node: Purging reader... Done" );

			# Punch kernel to reader on HCP
			$out = xCAT::zvmCPUtils->punch2Reader( $hcp, $userId, $kernelFile, "sles.kernel", "" );
			xCAT::zvmUtils->printLn( $callback, "$node: Punching kernel to reader... $out" );
			if ( $out =~ m/Failed/i ) {
				return;
			}

			# Punch parm to reader on HCP
			$out = xCAT::zvmCPUtils->punch2Reader( $hcp, $userId, $parmFile, "sles.parm", "-t" );
			xCAT::zvmUtils->printLn( $callback, "$node: Punching parm to reader... $out" );
			if ( $out =~ m/Failed/i ) {
				return;
			}

			# Punch initrd to reader on HCP
			$out = xCAT::zvmCPUtils->punch2Reader( $hcp, $userId, $initFile, "sles.initrd", "" );
			xCAT::zvmUtils->printLn( $callback, "$node: Punching initrd to reader... $out" );
			if ( $out =~ m/Failed/i ) {
				return;
			}

			# Remove kernel, parmfile, and initrd from /tmp
			$out = `rm $parmFile $kernelFile $initFile`;
			$out = `ssh -o ConnectTimeout=5 $hcp "rm $parmFile $kernelFile $initFile"`;

			xCAT::zvmUtils->printLn( $callback, "$node: Kernel, parm, and initrd punched to reader.  Ready for boot." );
		}

		# RHEL installation
		elsif ( $os =~ m/rhel/i ) {

			# Create directory in FTP root (/install) to hold template
			$out = `mkdir -p $installDir/custom/install/rh`;

			# Copy kickstart template
			$customTmpl = "$installDir/custom/install/rh/" . $node . "." . $profile . ".tmpl";
			if ( -e "$installDir/custom/install/rh/$tmpl" ) {
				$out = `cp $installDir/custom/install/rh/$tmpl $customTmpl`;
			}
			else {
				xCAT::zvmUtils->printLn( $callback, "$node: (Error) An kickstart template does not exist for $os in $installDir/custom/install/rh/" );
				return;
			}

			# Copy postscript into template
			$out = `sed --in-place -e "/%post/r $postScript" $customTmpl`;

			# Edit template
			my $url = "ftp://$ftp/$os/s390x/";
			$out =
`sed --in-place -e "s,replace_url,$url,g" \ -e "s,replace_ip,$hostIP,g" \ -e "s,replace_netmask,$mask,g" \ -e "s,replace_gateway,$gateway,g" \ -e "s,replace_nameserver,$nameserver,g" \ -e "s,replace_hostname,$hostname,g" \ -e "s,replace_rootpw,$passwd,g" \ -e "s,replace_master,$master,g" \ -e "s,replace_install_dir,$installDir,g" $customTmpl`;

			# Read sample parmfile in /install/rhel5.3/s390x/images
			$sampleParm = "$installDir/$os/s390x/images/generic.prm";
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
				@words = split( ' ', $_ );

				# Do not put a comma at the end of the last disk address
				if ( $i == @mdisks ) {
					$dasd = $dasd . "0.0.$words[1]";
				}
				else {
					$dasd = $dasd . "0.0.$words[1],";
				}
			}

			# Create parmfile -- Limited to 80 characters/line, maximum of 11 lines
			# End result should be:
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
			#	vnc vncpassword=12345678
			my $ks = "ftp://$ftp/custom/install/rh/" . $node . "." . $profile . ".tmpl";

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

			$parms = $parms . "vnc vncpassword=12345678\n";

			# Write to parmfile
			$parmFile = "/tmp/" . $node . "Parm";
			open( PARMFILE, ">$parmFile" );
			print PARMFILE "$parms";
			close(PARMFILE);

			# Send kernel, parmfile, conf, and initrd to reader to HCP
			$kernelFile = "/tmp/" . $node . "Kernel";
			$initFile   = "/tmp/" . $node . "Initrd";

			$out = `cp $installDir/$os/s390x/images/kernel.img $kernelFile`;
			$out = `cp $installDir/$os/s390x/images/initrd.img $initFile`;
			xCAT::zvmUtils->sendFile( $hcp, $kernelFile, $kernelFile );
			xCAT::zvmUtils->sendFile( $hcp, $parmFile,   $parmFile );
			xCAT::zvmUtils->sendFile( $hcp, $initFile,   $initFile );

			# Set the virtual unit record devices online
			$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", "c" );
			$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", "d" );

			# Purge reader
			$out = xCAT::zvmCPUtils->purgeReader( $hcp, $userId );
			xCAT::zvmUtils->printLn( $callback, "$node: Purging reader... Done" );

			# Punch kernel to reader on HCP
			$out = xCAT::zvmCPUtils->punch2Reader( $hcp, $userId, $kernelFile, "rhel.kernel", "" );
			xCAT::zvmUtils->printLn( $callback, "$node: Punching kernel to reader... $out" );
			if ( $out =~ m/Failed/i ) {
				return;
			}

			# Punch parm to reader on HCP
			$out = xCAT::zvmCPUtils->punch2Reader( $hcp, $userId, $parmFile, "rhel.parm", "-t" );
			xCAT::zvmUtils->printLn( $callback, "$node: Punching parm to reader... $out" );
			if ( $out =~ m/Failed/i ) {
				return;
			}

			# Punch initrd to reader on HCP
			$out = xCAT::zvmCPUtils->punch2Reader( $hcp, $userId, $initFile, "rhel.initrd", "" );
			xCAT::zvmUtils->printLn( $callback, "$node: Punching initrd to reader... $out" );
			if ( $out =~ m/Failed/i ) {
				return;
			}

			# Remove kernel, parmfile, and initrd from /tmp
			$out = `rm $parmFile $kernelFile $initFile`;
			$out = `ssh -o ConnectTimeout=5 $hcp "rm $parmFile $kernelFile $initFile"`;

			xCAT::zvmUtils->printLn( $callback, "$node: Kernel, parm, and initrd punched to reader.  Ready for boot." );
		}
	}
	elsif ( $action eq "statelite" ) {

		# Get node group from 'nodelist' table
		@propNames = ('groups');
		$propVals = xCAT::zvmUtils->getTabPropsByKey( 'nodelist', 'node', $node, @propNames );
		my $group = $propVals->{'groups'};

		# Get node statemnt (statelite mount point) from 'statelite' table
		@propNames = ('statemnt');
		$propVals = xCAT::zvmUtils->getTabPropsByKey( 'statelite', 'node', $node, @propNames );
		my $stateMnt = $propVals->{'statemnt'};
		if ( !$stateMnt ) {
			$propVals = xCAT::zvmUtils->getTabPropsByKey( 'statelite', 'node', $group, @propNames );
			$stateMnt = $propVals->{'statemnt'};

			if ( !$stateMnt ) {
				xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node statemnt in statelite table" );
				return;
			}
		}

		# Netboot directory
		my $netbootDir = "$installDir/netboot/$os/$arch/$profile";
		my $kernelFile = "$netbootDir/kernel";
		my $parmFile   = "$netbootDir/parm-statelite";
		my $initFile   = "$netbootDir/initrd-statelite.gz";

		# If parmfile exists
		if ( -e $parmFile ) {

			# Do nothing
		}
		else {
			xCAT::zvmUtils->printLn( $callback, "$node: Creating parmfile" );

			my $sampleParm;
			my $parmHeader;
			my $parms;
			if ( $os =~ m/sles/i ) {

				if ( -e "$installDir/$os/s390x/1/boot/s390x/parmfile" ) {

					# Read sample parmfile in /install/sles11.1/s390x/1/boot/s390x/
					$sampleParm = "$installDir/$os/s390x/1/boot/s390x/parmfile";
				}
				else {
					xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing $installDir/$os/s390x/1/boot/s390x/parmfile" );
					return;
				}
			}
			elsif ( $os =~ m/rhel/i ) {

				if ( -e "$installDir/$os/s390x/images/generic.prm" ) {

					# Read sample parmfile in /install/rhel5.3/s390x/images
					$sampleParm = "$installDir/$os/s390x/images/generic.prm";
				}
				else {
					xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing $installDir/$os/s390x/images/generic.prm" );
					return;
				}
			}

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
			# End result should be:
			# 	ramdisk_size=65536 root=/dev/ram1 ro init=/linuxrc TERM=dumb
			# 	NFSROOT=10.1.100.1:/install/netboot/sles11.1.1/s390x/compute
			# 	STATEMNT=10.1.100.1:/lite/state XCAT=10.1.100.1:3001
			$parms = $parmHeader . "\n";
			$parms = $parms . "NFSROOT=$master:$netbootDir\n";
			$parms = $parms . "STATEMNT=$stateMnt XCAT=$master:$xcatdPort\n";

			# Write to parmfile
			open( PARMFILE, ">$parmFile" );
			print PARMFILE "$parms";
			close(PARMFILE);
		}

		# Temporary kernel, parmfile, and initrd
		my $tmpKernelFile = "/tmp/$os-kernel";
		my $tmpParmFile   = "/tmp/$os-parm-statelite";
		my $tmpInitFile   = "/tmp/$os-initrd-statelite.gz";

		if (`ssh -o ConnectTimeout=5 $hcp "ls /tmp" | grep "$os-kernel"`) {

			# Do nothing
		}
		else {

			# Send kernel to reader to HCP
			xCAT::zvmUtils->sendFile( $hcp, $kernelFile, $tmpKernelFile );
		}

		if (`ssh -o ConnectTimeout=5 $hcp "ls /tmp" | grep "$os-parm-statelite"`) {

			# Do nothing
		}
		else {

			# Send parmfile to reader to HCP
			xCAT::zvmUtils->sendFile( $hcp, $parmFile, $tmpParmFile );
		}

		if (`ssh -o ConnectTimeout=5 $hcp "ls /tmp" | grep "$os-initrd-statelite.gz"`) {

			# Do nothing
		}
		else {

			# Send initrd to reader to HCP
			xCAT::zvmUtils->sendFile( $hcp, $initFile, $tmpInitFile );
		}

		# Set the virtual unit record devices online
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", "c" );
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $hcp, "-e", "d" );

		# Purge reader
		$out = xCAT::zvmCPUtils->purgeReader( $hcp, $userId );
		xCAT::zvmUtils->printLn( $callback, "$node: Purging reader... Done" );

		# Kernel, parm, and initrd are in /install/netboot/<os>/<arch>/<profile>
		# Punch kernel to reader on HCP
		$out = xCAT::zvmCPUtils->punch2Reader( $hcp, $userId, $tmpKernelFile, "sles.kernel", "" );
		xCAT::zvmUtils->printLn( $callback, "$node: Punching kernel to reader... $out" );
		if ( $out =~ m/Failed/i ) {
			return;
		}

		# Punch parm to reader on HCP
		$out = xCAT::zvmCPUtils->punch2Reader( $hcp, $userId, $tmpParmFile, "sles.parm", "-t" );
		xCAT::zvmUtils->printLn( $callback, "$node: Punching parm to reader... $out" );
		if ( $out =~ m/Failed/i ) {
			return;
		}

		# Punch initrd to reader on HCP
		$out = xCAT::zvmCPUtils->punch2Reader( $hcp, $userId, $tmpInitFile, "sles.initrd", "" );
		xCAT::zvmUtils->printLn( $callback, "$node: Punching initrd to reader... $out" );
		if ( $out =~ m/Failed/i ) {
			return;
		}

		xCAT::zvmUtils->printLn( $callback, "$node: Kernel, parm, and initrd punched to reader.  Ready for boot." );
	}
	else {
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Option not supported" );
		return;
	}

	return;
}

#-------------------------------------------------------

=head3   getMacs

	Description	: Get the MAC address of a given node
					* Requires the node be online
					* Saves MAC address in 'mac' table
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
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = $propVals->{'userid'};
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node ID" );
		return;
	}

	# Get MAC address in 'mac' table
	@propNames = ('mac');
	$propVals = xCAT::zvmUtils->getNodeProps( 'mac', $node, @propNames );
	my $mac;
	if ( $propVals->{'mac'} ) {

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
	my @words;

	# Go through each line and extract VSwitch and Lan names
	# and create search string
	my $searchStr = "";
	my $i;
	for ( $i = 0 ; $i < @lines ; $i++ ) {

		# Extract VSwitch name
		if ( $lines[$i] =~ m/VSWITCH/i ) {
			@words = split( ' ', $lines[$i] );
			$searchStr = $searchStr . "$words[4]";
		}

		# Extract Lan name
		elsif ( $lines[$i] =~ m/LAN/i ) {
			@words = split( ' ', $lines[$i] );
			$searchStr = $searchStr . "$words[4]";
		}

		if ( $i != ( @lines - 1 ) ) {
			$searchStr = $searchStr . "|";
		}
	}

	# Get MAC address of node
	# This node should be on only 1 of the networks that the xCat MN is on
	$out = `ssh -o ConnectTimeout=5 $node "vmcp q v nic" | egrep -i "$searchStr"`;
	if ( !$out ) {
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Failed to find MAC address" );
		return;
	}

	@lines = split( '\n', $out );
	@words = split( ' ',  $lines[0] );
	$mac   = $words[1];

	# Replace - with :
	$mac = xCAT::zvmUtils->replaceStr( $mac, "-", ":" );
	xCAT::zvmUtils->printLn( $callback, "$node: $mac" );

	# Save MAC address and network interface into 'mac' table
	xCAT::zvmUtils->setNodeProp( 'mac', $node, 'mac', $mac );

	return;
}

#-------------------------------------------------------

=head3   netBoot

	Description	: Boot from network
    Arguments	: 	Node
    				Address to IPL from
    Returns		: Nothing
    Example		: netBoot($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub netBoot {

	# Get inputs
	my ( $callback, $node, $args ) = @_;

	# Get node properties from 'zvm' table
	my @propNames = ( 'hcp', 'userid' );
	my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

	# Get HCP
	my $hcp = $propVals->{'hcp'};
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = $propVals->{'userid'};
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node ID" );
		return;
	}

	# Get IPL
	my @ipl = split( '=', $args->[0] );
	if ( !( $ipl[0] eq "ipl" ) ) {
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing IPL" );
		return;
	}

	# Boot node
	my $out = `ssh $hcp "$::DIR/startvs $userId"`;
	my $rc = xCAT::zvmUtils->checkOutput( $callback, $out );
	if ( $rc == -1 ) {
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Boot failed" );
		return;
	}
	else {
		xCAT::zvmUtils->printLn( $callback, "$node: $out" );
	}

	# IPL when virtual server is online
	sleep(5);
	$out = xCAT::zvmCPUtils->sendCPCmd( $hcp, $userId, "IPL $ipl[1]" );
	xCAT::zvmUtils->printLn( $callback, "$node: Booting from $ipl[1]... Done" );

	return;
}

#-------------------------------------------------------

=head3   updateNode (No longer supported)

	Description	: Update node
    Arguments	: 	Node
    				Option
    				
    Options supported:
 		* release [updated version]
 		
    Returns		: Nothing
    Example		: updateNode($callback, $node, $args);
    
=cut

#-------------------------------------------------------
sub updateNode {

	# Get inputs
	my ( $callback, $node, $args ) = @_;

	# Get node properties from 'zvm' table
	my @propNames = ( 'hcp', 'userid' );
	my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

	# Get HCP
	my $hcp = $propVals->{'hcp'};
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = $propVals->{'userid'};
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing node ID" );
		return;
	}

	# Get install directory
	my $siteTab        = xCAT::Table->new('site');
	my $installDirHash = $siteTab->getAttribs( { key => "installdir" }, 'value' );
	my $installDir     = $installDirHash->{'value'};

	# Get host IP and hostname from /etc/hosts
	my $out      = `cat /etc/hosts | grep $node`;
	my @words    = split( ' ', $out );
	my $hostIP   = $words[0];
	my $hostname = $words[2];
	if ( !$hostIP || !$hostname ) {
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing IP for $node in /etc/hosts" );
		return;
	}

	# Get first 3 octets of node IP (IPv4)
	@words = split( /\./, $hostIP );
	my $octets = "$words[0].$words[1].$words[2]";

	# Get networks in 'networks' table
	my $entries = xCAT::zvmUtils->getAllTabEntries('networks');

	# Go through each network
	my $network;
	foreach (@$entries) {

		# Get network
		$network = $_->{'net'};

		# If networks contains the first 3 octets of the node IP
		if ( $network =~ m/$octets/i ) {

			# Exit loop
			last;
		}
		else {
			$network = "";
		}
	}

	# If no network found
	if ( !$network ) {

		# Exit
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Node does not belong to any networks in the networks table" );
		return;
	}

	# Get FTP server
	@propNames = ('tftpserver');
	$propVals = xCAT::zvmUtils->getTabPropsByKey( 'networks', 'net', $network, @propNames );
	my $ftp = $propVals->{'tftpserver'};
	if ( !$ftp ) {

		# It is acceptable to not have a gateway
		xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing FTP server" );
		return;
	}

	# Update node operating system
	if ( $args->[0] eq "--release" ) {
		my $version = $args->[1];

		if ( !$version ) {
			xCAT::zvmUtils->printLn( $callback, "$node: (Error) Missing operating system release" );
			return;
		}

		# Get node operating system
		my $os = xCAT::zvmUtils->getOs($node);

		# Check node OS is the same as the version OS given
		# You do not want to update a SLES with a RHEL
		if ( ( ( $os =~ m/SUSE/i ) && !( $version =~ m/sles/i ) ) || ( ( $os =~ m/Red Hat/i ) && !( $version =~ m/rhel/i ) ) ) {
			xCAT::zvmUtils->printLn( $callback, "$node: (Error) Node operating system is different from the operating system given to upgrade to" );
			return;
		}

		# Generate FTP path to operating system image
		my $path;
		if ( $version =~ m/sles/i ) {

			# The following only applies to SLES 10
			# SLES 11 requires zypper

			# SuSE Enterprise Linux path - ftp://10.0.0.1/sles10.3/s390x/1/
			$path = "ftp://$ftp/$version/s390x/1/";

			# Add installation source using rug
			$out = `ssh $node "rug sa -t zypp $path $version"`;
			xCAT::zvmUtils->printLn( $callback, "$node: $out" );

			# Subscribe to catalog
			$out = `ssh $node "rug sub $version"`;
			xCAT::zvmUtils->printLn( $callback, "$node: $out" );

			# Refresh services
			$out = `ssh $node "rug ref"`;
			xCAT::zvmUtils->printLn( $callback, "$node: $out" );

			# Update
			$out = `ssh $node "rug up -y"`;
			xCAT::zvmUtils->printLn( $callback, "$node: $out" );
		}
		else {

			# Red Hat Enterprise Linux path - ftp://10.0.0.1/rhel5.4/s390x/Server/
			$path = "ftp://$ftp/$version/s390x/Server/";

			# Check if file.repo already has this repository location
			$out = `ssh $node "cat /etc/yum.repos.d/file.repo"`;
			if ( $out =~ m/[$version]/i ) {

				# Send over release key
				my $key = "$installDir/$version/s390x/RPM-GPG-KEY-redhat-release";
				my $tmp = "/tmp/RPM-GPG-KEY-redhat-release";
				xCAT::zvmUtils->sendFile( $node, $key, $tmp );

				# Import key
				$out = `ssh $node "rpm --import /tmp/$key"`;

				# Upgrade
				$out = `ssh $node "yum upgrade -y"`;
				xCAT::zvmUtils->printLn( $callback, "$node: $out" );
			}
			else {

				# Create repository
				$out = `ssh $node "echo [$version] >> /etc/yum.repos.d/file.repo"`;
				$out = `ssh $node "echo baseurl=$path >> /etc/yum.repos.d/file.repo"`;
				$out = `ssh $node "echo enabled=1 >> /etc/yum.repos.d/file.repo"`;

				# Send over release key
				my $key = "$installDir/$version/s390x/RPM-GPG-KEY-redhat-release";
				my $tmp = "/tmp/RPM-GPG-KEY-redhat-release";
				xCAT::zvmUtils->sendFile( $node, $key, $tmp );

				# Import key
				$out = `ssh $node "rpm --import $tmp"`;

				# Upgrade
				$out = `ssh $node "yum upgrade -y"`;
				xCAT::zvmUtils->printLn( $callback, "$node: $out" );
			}
		}
	}

	# Otherwise, print out error
	else {
		$out = "$node: (Error) Option not supported";
	}

	xCAT::zvmUtils->printLn( $callback, "$out" );
	return;
}
