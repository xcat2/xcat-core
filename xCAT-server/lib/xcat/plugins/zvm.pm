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
use Switch;
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
	return { zvm => "zvm" };
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

	# Determine command sent
	switch ($command) {

		# Controls the power for a single or range of nodes
		case "rpower" {
			foreach (@nodes) {
				$pid = fork();

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
		case "rinv" {
			foreach (@nodes) {
				$pid = fork();

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
		case "mkvm" {
			foreach (@nodes) {

				$pid = fork();

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
		case "rmvm" {
			foreach (@nodes) {
				$pid = fork();

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
		case "lsvm" {
			foreach (@nodes) {
				$pid = fork();

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
		case "chvm" {
			foreach (@nodes) {
				$pid = fork();

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

		# Collects node information from one or more hardware control points.
		case "rscan" {
			foreach (@nodes) {
				$pid = fork();

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
	}    # End of switch

	# Wait for all processes to end
	foreach (@children) {
		waitpid( $_, 0 );
	}

	return;
}

#-------------------------------------------------------

=head3   removeVM

	Description	: Removes server
    Arguments	: Node
    Returns		: Nothing
    Example		: removeVM($node);
    
=cut

#-------------------------------------------------------
sub removeVM {

	# Get inputs
	my ( $callback, $node ) = @_;

	# Get HCP
	my $hcp = xCAT::zvmUtils->getTabProp( 'zvm', $node, 'hcp' );
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = xCAT::zvmUtils->getTabProp( 'zvm', $node, 'userid' );
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node ID" );
		return;
	}

	# Power off userID
	my $out = `ssh $hcp $::DIR/stopvs $userId`;
	xCAT::zvmUtils->printLn( $callback, "$out" );

	# Get device address for each MDISK
	my @mdisks = xCAT::zvmUtils->getMdisks( $callback, $node );
	my @parms;
	my $addr;
	foreach (@mdisks) {
		@parms = split( ' ', $_ );
		$addr  = $parms[1];

		# Remove MDISK
		# This cleans up the disks before it is put back in the pool
		$out = `ssh $hcp $::DIR/removemdisk $userId $addr`;
		xCAT::zvmUtils->printLn( $callback, "$out" );
	}

	# Sleep 5 seconds
	# To let the z/VM user directory settle
	sleep(5);

	# Delete user directory entry
	$out = `ssh $hcp $::DIR/deletevs $userId`;
	xCAT::zvmUtils->printLn( $callback, "$out" );

	# Remove node from 'zvm', 'nodelist', 'nodehm', and 'hosts' table
	xCAT::zvmUtils->delTabNode( 'zvm',      $node );
	xCAT::zvmUtils->delTabNode( 'nodelist', $node );
	xCAT::zvmUtils->delTabNode( 'nodetype', $node );
	xCAT::zvmUtils->delTabNode( 'nodehm',   $node );
	xCAT::zvmUtils->delTabNode( 'hosts',    $node );

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
 	Example		: changeVM($node, $args);
 		
=cut

#-------------------------------------------------------
sub changeVM {

	# Get inputs
	my ( $callback, $node, $args ) = @_;

	# Get HCP
	my $hcp = xCAT::zvmUtils->getTabProp( 'zvm', $node, 'hcp' );
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = xCAT::zvmUtils->getTabProp( 'zvm', $node, 'userid' );
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node ID" );
		return;
	}

	my $out;

	# add3390 [disk pool] [device address] [mode] [cylinders]
	if ( $args->[0] eq "--add3390" ) {
		my $pool    = $args->[1];
		my $addr    = $args->[2];
		my $mode    = $args->[3];
		my $cyl     = $args->[4];
		my $readPw  = $args->[5];
		my $writePw = $args->[6];
		my $multiPw = $args->[7];

		$out = `ssh $hcp $::DIR/add3390 $userId $pool $addr $mode $cyl $readPw $writePw $multiPw`;
	}

	# add9336 [disk pool] [virtual device address] [mode] [block size] [blocks]
	elsif ( $args->[0] eq "--add9336" ) {
		my $pool    = $args->[1];
		my $addr    = $args->[2];
		my $mode    = $args->[3];
		my $blksize = $args->[4];
		my $blks    = $args->[5];
		$out = `ssh $hcp $::DIR/add9336 $userId $pool $addr $mode $blksize $blks`;
	}

	# addnic [address] [type] [device count]
	elsif ( $args->[0] eq "--addnic" ) {
		my $addr     = $args->[1];
		my $type     = $args->[2];
		my $devcount = $args->[3];

		$out = `ssh $hcp $::DIR/addnic $userId $addr $type $devcount`;
	}

	# addprocessor [address]
	elsif ( $args->[0] eq "--addprocessor" ) {
		my $addr = $args->[1];

		$out = `ssh $hcp $::DIR/addprocessor $userId $addr`;
	}

	# addvdisk [device address] [size]
	elsif ( $args->[0] eq "--addvdisk" ) {
		my $addr = $args->[1];
		my $size = $args->[2];

		$out = `ssh $hcp $::DIR/addvdisk $userId $addr $size`;
	}

	# connectnic2guestlan [address] [lan] [owner]
	elsif ( $args->[0] eq "--connectnic2guestlan" ) {
		my $addr  = $args->[1];
		my $lan   = $args->[2];
		my $owner = $args->[3];

		$out = `ssh $hcp $::DIR/connectnic2guestlan $userId $addr $lan $owner`;
	}

	# connectnic2vswitch [address] [vswitch]
	elsif ( $args->[0] eq "--connectnic2vswitch" ) {
		my $addr    = $args->[1];
		my $vswitch = $args->[2];

		# Connect to VSwitch
		$out = `ssh $hcp $::DIR/connectnic2vswitch $userId $addr $vswitch`;

		# Grant access to VSWITCH for Linux user
		$out .= "Granting access to VSWITCH for $userId...\n  ";
		$out .= `ssh $hcp vmcp set vswitch $vswitch grant $userId`;
	}

	# dedicatedevice [virtual device] [real device] [mode]
	elsif ( $args->[0] eq "--dedicatedevice" ) {
		my $vaddr = $args->[1];
		my $raddr = $args->[2];
		my $mode  = $args->[3];

		$out = `ssh $hcp $::DIR/dedicatedevice $userId $vaddr $raddr $mode`;
	}

	# deleteipl
	elsif ( $args->[0] eq "--deleteipl" ) {
		$out = `ssh $hcp $::DIR/deleteipl $userId`;
	}

	# disconnectnic [address]
	elsif ( $args->[0] eq "--disconnectnic" ) {
		my $addr = $args->[1];
		$out = `ssh $hcp $::DIR/disconnectnic $userId $addr`;
	}

	# removemdisk [virtual device address]
	elsif ( $args->[0] eq "--removemdisk" ) {
		my $addr = $args->[1];
		$out = `ssh $hcp $::DIR/removemdisk $userId $addr`;
	}

	# removenic [address]
	elsif ( $args->[0] eq "--removenic" ) {
		my $addr = $args->[1];
		$out = `ssh $hcp $::DIR/removenic $userId $addr`;
	}

	# removeprocessor [address]
	elsif ( $args->[0] eq "--removeprocessor" ) {
		my $addr = $args->[1];
		$out = `ssh $hcp $::DIR/removeprocessor $userId $addr`;
	}

	# replacevs [file]
	elsif ( $args->[0] eq "--replacevs" ) {
		my $file = $args->[1];

		my $dest = "root@";
		$dest .= $hcp;
		if ($file) {

			# SCP file over to HCP
			$out = `scp $file $dest:$file`;

			# Replace user directory entry
			$out = `ssh $hcp $::DIR/replacevs $userId $file`;
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
		$out = `ssh $hcp $::DIR/setipl $userId $trgt $loadparms $parms`;
	}

	# setpassword [password]
	elsif ( $args->[0] eq "--setpassword" ) {
		my $pw = $args->[1];
		$out = `ssh $hcp $::DIR/setpassword $userId $pw`;
	}

	# Print out error
	else {
		$out = "Error: Option not supported";
	}

	xCAT::zvmUtils->printLn( $callback, "$out" );
	return;
}

#-------------------------------------------------------

=head3   powerVM

	Description	: Powers on/off a server
    Arguments	: 	Node 
    				Option [on|off|reset|stat]
    Returns		: Nothing
    Example		: powerVM($node, $args);
    
=cut

#-------------------------------------------------------
sub powerVM {

	# Get inputs
	my ( $callback, $node, $args ) = @_;

	# Get HCP
	my $hcp = xCAT::zvmUtils->getTabProp( 'zvm', $node, 'hcp' );
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = xCAT::zvmUtils->getTabProp( 'zvm', $node, 'userid' );
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node ID" );
		return;
	}

	my $out;
	if ( $args->[0] eq 'on' ) {
		$out = `ssh $hcp $::DIR/startvs $userId`;
		xCAT::zvmUtils->printLn( $callback, "$out" );
	}
	elsif ( $args->[0] eq 'off' ) {

		$out = `ssh $hcp $::DIR/stopvs $userId`;
		xCAT::zvmUtils->printLn( $callback, "$out" );
	}
	elsif ( $args->[0] eq 'stat' ) {

		# Output is different on SLES 11
		$out = `vmcp q user $userId 2>/dev/null | sed 's/HCPCQU045E.*/off/' | sed 's/$userId.*/on/'`;
		xCAT::zvmUtils->printLn( $callback, "$node: $out" );
	}
	elsif ( $args->[0] eq 'reset' ) {

		$out = `ssh $hcp $::DIR/stopvs $userId`;
		xCAT::zvmUtils->printLn( $callback, "$out" );

		# Wait for output
		while ( `vmcp q user $node 2>/dev/null | sed 's/HCPCQU045E.*/proceed/'` != "proceed" ) {
		}
		$out = `ssh $hcp $::DIR/startvs $userId`;
		xCAT::zvmUtils->printLn( $callback, "$out" );
	}
	else {
		xCAT::zvmUtils->printLn( $callback, "Error: Option not supported" );
	}
	return;
}

#-------------------------------------------------------

=head3   scanVM

	Description	: Collects node information from one or more hardware control points.
    Arguments	: zHCP node
    Returns		: Nothing
    Example		: scanVM($node);
    
=cut

#-------------------------------------------------------
sub scanVM {

	# Get inputs
	my ( $callback, $node ) = @_;

	# Get HCP DNS host name
	my $hcp = xCAT::zvmUtils->getTabProp( 'zvm', $node, 'hcp' );
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = xCAT::zvmUtils->getTabProp( 'zvm', $node, 'userid' );
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

	# Get 'node' and 'userid' properties
	my @results = $tab->getAllAttribsWhere( "hcp like '%" . $hcp . "%'", 'node', 'userid' );
	foreach (@results) {
		$managedNode = $_->{'node'};
		$id          = $_->{'userid'};
		$groups      = xCAT::zvmUtils->getTabProp( 'nodelist', $managedNode, 'groups' );

		# Get userID if one is not in the table
		if ( !$id ) {

			# Load VMCP module
			$out = xCAT::zvmCPUtils->loadVmcp($managedNode);

			# Get userID
			$id = xCAT::zvmCPUtils->getUserId($managedNode);
		}

		# Get operating system
		$os = xCAT::zvmCPUtils->getOs($managedNode);

		# Get architecture
		$arch = xCAT::zvmCPUtils->getArch($managedNode);

		# Create output string
		$str .= "$managedNode:\n";
		$str .= "  objtype=node\n";
		$str .= "  id=$id\n";
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

	Description	: Get server hardware and software inventory
    Arguments	: Node and arguments
    Returns		: Nothing
    Example		: inventoryVM($node, $args);
    
=cut

#-------------------------------------------------------
sub inventoryVM {

	# Get inputs
	my ( $callback, $node, $args ) = @_;

	# Output string
	my $str = "";

	# Get HCP
	my $hcp = xCAT::zvmUtils->getTabProp( 'zvm', $node, 'hcp' );

	# Get node userID
	my $userId = xCAT::zvmUtils->getTabProp( 'zvm', $node, 'userid' );
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node ID" );
		return;
	}

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
		$str = "Error: Invalid argument";
		xCAT::zvmUtils->printLn( $callback, "$str" );
		return;
	}

	# Append hostname in front
	$str = xCAT::zvmUtils->appendHostname( $node, $str );

	xCAT::zvmUtils->printLn( $callback, "$str" );
	return;
}

#-------------------------------------------------------

=head3   listVM

	Description	: Get user directory entry
    Arguments	: Node
    Returns		: Nothing
    Example		: listVM($node);
    
=cut

#-------------------------------------------------------
sub listVM {

	# Get inputs
	my ( $callback, $node ) = @_;

	# Get HCP
	my $hcp = xCAT::zvmUtils->getTabProp( 'zvm', $node, 'hcp' );
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node HCP" );
		return;
	}

	# Get node userID
	my $userId = xCAT::zvmUtils->getTabProp( 'zvm', $node, 'userid' );
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node ID" );
		return;
	}

	# Get virtual server directory entry
	my $out = `ssh $hcp $::DIR/getimagerecords $userId`;
	xCAT::zvmUtils->printLn( $callback, "$out" );

	return;
}

#-------------------------------------------------------

=head3   makeVM

	Description	: Create a server
    Arguments	: 	Node 
    				User directory entry as text file
    Returns		: Nothing
    Example		: makeVM($node, $args);
    
=cut

#-------------------------------------------------------
sub makeVM {

	# Before a virtual server can be created
	# You need to add the virtual server into the tables:
	# 	mkdef -t node -o gpok123 userid=linux123 hcp=gpok456.endicott.ibm.com mgt=zvm groups=all
	# 	This will add the node into the 'nodelist', 'nodehm', and 'zvm' tables

	# Get inputs
	my ( $callback, $node, $args ) = @_;

	# Get HCP
	# It was defined in mkdef command
	my $hcp = xCAT::zvmUtils->getTabProp( 'zvm', $node, 'hcp' );
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: No HCP defined for this node" );
		return;
	}

	# Get new node userID
	my $userId = xCAT::zvmUtils->getTabProp( 'zvm', $node, 'userid' );
	if ( !$userId ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node ID" );
		return;
	}

	# Get file (if any)
	my $file = $args->[0];
	my $out;

	# Create destination string, e.g.
	# root@gpok123.endicott.ibm.com
	my $dest = "root@";
	$dest .= $hcp;
	if ($file) {

		# SCP file over to HCP
		$out = `scp $file $dest:$file`;

		# Create virtual server
		$out = `ssh $hcp $::DIR/createvs $userId $file`;
		xCAT::zvmUtils->printLn( $callback, "$out" );
	}
	else {

		# Create NOLOG virtual server
		$out = `ssh $hcp $::DIR/createvs $userId`;
		xCAT::zvmUtils->printLn( $callback, "$out" );
	}

	return;

}

#-------------------------------------------------------

=head3   cloneVM

	Description	: Clone a server
    Arguments	: Node and configuration
    Returns		: Nothing
    Example		: cloneVM($node, $args);
    
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
	my $rtn;

	xCAT::zvmUtils->printLn( $callback, "$targetNode: Cloning" );

	# Get HCP
	my $hcp = xCAT::zvmUtils->getTabProp( 'zvm', $targetNode, 'hcp' );
	if ( !$hcp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: No HCP defined for this node" );
		return;
	}

	# Get target node userID
	my $targetUserId = xCAT::zvmUtils->getTabProp( 'zvm', $targetNode, 'userid' );
	if ( !$targetUserId ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing node ID" );
		return;
	}

	# Get source node
	my $sourceNode = $args->[0];
	if ( !$sourceNode ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing master node" );
		return;
	}

	# Get source node userID
	my $sourceId = xCAT::zvmUtils->getTabProp( 'zvm', $sourceNode, 'userid' );
	if ( !$sourceId ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing master node ID" );
		return;
	}

	# Get source node HCP
	my $sourceHcp = xCAT::zvmUtils->getTabProp( 'zvm', $sourceNode, 'hcp' );
	if ( !$sourceHcp ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing master node ID" );
		return;
	}

	# Exit if source node HCP is not the same as target node HCP
	elsif ( !( $sourceHcp eq $hcp ) ) {
		xCAT::zvmUtils->printLn( $callback,
			"Error: Source node HCP ($sourceHcp) is not the same as target node HCP ($hcp)" );
		return;
	}

	# Get other inputs (4 in total)
	# Disk pool, read, write, and multi passwords
	my $i;
	my @parms;
	my %inputs;
	foreach $i ( 1 .. 4 ) {
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
	my $readPw = $inputs{"readpw"};
	if ( !$readPw ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing read password" );
		return;
	}
	my $writePw = $inputs{"writepw"};
	if ( !$writePw ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing write password" );
		return;
	}
	my $multiPw = $inputs{"multipw"};
	if ( !$multiPw ) {
		xCAT::zvmUtils->printLn( $callback, "Error: Missing multi password" );
		return;
	}

	# Get MDisk statements of source node
	my @srcDisks = xCAT::zvmUtils->getMdisks( $callback, $sourceNode );

	# Get directory entry of source node
	# Save user directory entry as /tmp/dirEntry.txt
	my $dirFile = "/tmp/dirEntry.txt";
	my $out     = xCAT::zvmUtils->saveDirEntryNoDisk( $callback, $sourceNode, $dirFile );

	# SCP directory entry file over to HCP
	$out = xCAT::zvmUtils->sendFile( $hcp, $dirFile );

	# Create new virtual server
	xCAT::zvmUtils->printLn( $callback, "$targetNode: Creating user directory entry" );
	$out = `ssh $hcp $::DIR/createvs $targetUserId $dirFile`;

	# Check for errors
	$rtn = xCAT::zvmUtils->isOutputGood( $callback, $out );
	if ( $rtn == -1 ) {

		# Exit on bad output
		xCAT::zvmUtils->printLn( $callback, "$out" );
		return;
	}

	# Load VMCP module
	$out = xCAT::zvmCPUtils->loadVmcp($sourceNode);

	# Get VSwitch of master node
	my @vswitchId = xCAT::zvmCPUtils->getVswitchId($sourceNode);

	# Grant access to VSwitch for Linux user
	# GuestLan do not need permissions
	xCAT::zvmUtils->printLn( $callback, "$targetNode: Granting VSwitch access" );
	foreach (@vswitchId) {
		$out = xCAT::zvmUtils->grantVSwitch( $callback, $hcp, $targetUserId, $_ );

		# Check for errors
		$rtn = xCAT::zvmUtils->isOutputGood( $callback, $out );
		if ( $rtn == -1 ) {

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
	foreach (@srcDisks) {

		# Get disk device address
		@parms = split( ' ', $_ );
		$addr = $parms[1];
		push( @trgtDisks, $addr );
		$type = $parms[2];
		$mode = $parms[6];

		# Add ECKD disk
		if ( $type eq '3390' ) {

			# Get disk size (cylinders)
			$out   = `ssh -o ConnectTimeout=5 $sourceNode vmcp q v dasd | grep "DASD $addr"`;
			@parms = split( ' ', $out );
			$cyl   = xCAT::zvmUtils->trim( $parms[5] );

			# Add disk
			xCAT::zvmUtils->printLn( $callback, "$targetNode: Adding minidisk" );
			$out = `ssh $hcp $::DIR/add3390 $targetUserId $pool $addr $mode $cyl $readPw $writePw $multiPw`;

			# Check for errors
			$rtn = xCAT::zvmUtils->isOutputGood( $callback, $out );
			if ( $rtn == -1 ) {
				xCAT::zvmUtils->printLn( $callback, "$out" );

				# Exit on bad output
				return;
			}
		}

		# Add FBA disk
		elsif ( $type eq '9336' ) {

			# Get disk size (blocks)
		}

	}

	# Format and copy source disks
	my $targetAddr;
	my $targetDevNode;
	my $sourceDevNode;
	foreach (@trgtDisks) {
		$targetAddr = $_ + 1000;

		# Check if there is an existing address
		$out = xCAT::zvmUtils->isAddressUsed( $sourceNode, $targetAddr );

		# If there is an existing address
		while ( $out == 0 ) {

			# Generate a new address
			# Sleep 2 seconds to let existing disk appear
			sleep(2);
			$targetAddr = $targetAddr + 1;
			$out = xCAT::zvmUtils->isAddressUsed( $sourceNode, $targetAddr );
		}

		# Link target disk to source disk
		$out = `ssh $sourceNode vmcp link $targetUserId $_ $targetAddr MW $multiPw`;

		# Get for errors
		$rtn = xCAT::zvmUtils->isOutputGood( $callback, $out );
		if ( $rtn == -1 ) {
			xCAT::zvmUtils->printLn( $callback, "$out" );
			return;
		}

		# Enable target disk
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $sourceNode, "-e", $targetAddr );

		# Determine target device node
		$out           = `ssh $sourceNode cat /proc/dasd/devices | grep ".$targetAddr("`;
		@parms         = split( ' ', $out );
		$targetDevNode = $parms[6];

		# Determine source device node
		$out           = `ssh $sourceNode cat /proc/dasd/devices | grep "$_"`;
		@parms         = split( ' ', $out );
		$sourceDevNode = $parms[6];

		# Format disk
		xCAT::zvmUtils->printLn( $callback, "$targetNode: Formating disk" );
		$out = `ssh $sourceNode dasdfmt -b 4096 -y -f /dev/$targetDevNode`;

		# Check for errors
		$rtn = xCAT::zvmUtils->isOutputGood( $callback, $out );
		if ( $rtn == -1 ) {

			# Exit on bad output
			xCAT::zvmUtils->printLn( $callback, "$out" );
			return;
		}

		# Sleep 2 seconds to let the system settle
		sleep(2);

		# Copy source disk to target disk
		xCAT::zvmUtils->printLn( $callback, "$targetNode: Copying source disk" );
		$out = `ssh $sourceNode dd if=/dev/$sourceDevNode of=/dev/$targetDevNode bs=4096`;

		# Check for error
		$rtn = xCAT::zvmUtils->isOutputGood( $callback, $out );
		if ( $rtn == -1 ) {
			xCAT::zvmUtils->printLn( $callback, "$out" );
			return;
		}

		# Sleep 2 seconds to let the system settle
		sleep(2);

		# Disable and enable target disk
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $sourceNode, "-d", $targetAddr );
		$out = xCAT::zvmUtils->disableEnableDisk( $callback, $sourceNode, "-e", $targetAddr );

		# Determine target device node
		$out           = `ssh $sourceNode cat /proc/dasd/devices | grep ".$targetAddr("`;
		@parms         = split( ' ', $out );
		$targetDevNode = $parms[6];

		# Get source device node that is mounted on (/)
		my $sourceRootDevNode = xCAT::zvmUtils->getRootNode($sourceNode);
		if ( $sourceRootDevNode =~ m/$sourceDevNode/i ) {

			# Set network configuration
			xCAT::zvmUtils->printLn( $callback, "$targetNode: Setting network configuration" );

			# Mount target disk
			my $cloneMntPt = "/mnt/$targetUserId";
			$targetDevNode .= "1";

			# xCAT::zvmUtils->printLn( $callback, "Mounting $cloneMntPt..." );
			$out = `ssh $sourceNode mkdir $cloneMntPt`;
			$out = `ssh $sourceNode mount /dev/$targetDevNode $cloneMntPt`;

			# Set hostname
			$out = `ssh $sourceNode sed --in-place -e "s/$sourceNode/$targetNode/g" $cloneMntPt/etc/HOSTNAME`;
			$out = `ssh $sourceNode cat $cloneMntPt/etc/HOSTNAME`;

			# Set IP address
			my $sourceIp  = xCAT::zvmUtils->getIp($sourceNode);
			my $targetIp  = xCAT::zvmUtils->getTabProp( "hosts", $targetNode, "ip" );
			my $ifcfg     = xCAT::zvmUtils->getIfcfg($sourceNode);
			my $ifcfgPath = $cloneMntPt;
			$ifcfgPath .= $ifcfg;
			$out =
`ssh $sourceNode sed --in-place -e "s/$sourceNode/$targetNode/g" \ -e "s/$sourceIp/$targetIp/g" $cloneMntPt/etc/hosts`;
			$out =
`ssh $sourceNode sed --in-place -e "s/$sourceIp/$targetIp/g" \ -e "s/$sourceNode/$targetNode/g" $ifcfgPath`;

			# Flush disk
			$out = `ssh $sourceNode sync`;

			# Unmount disk
			$out = `ssh $sourceNode umount $cloneMntPt`;
		}

		# Detatch disk
		$out = `ssh $sourceNode vmcp det $targetAddr`;
	}

	# Power on target virtual server
	xCAT::zvmUtils->printLn( $callback, "$targetNode: Powering on" );
	$out = `ssh $hcp $::DIR/startvs $targetUserId`;

	# Check for error
	$rtn = xCAT::zvmUtils->isOutputGood( $callback, $out );
	if ( $rtn == -1 ) {

		# Exit on bad output
		xCAT::zvmUtils->printLn( $callback, "$out" );
		return;
	}

	xCAT::zvmUtils->printLn( $callback, "$targetNode: Done" );

	return;
}
