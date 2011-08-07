# IBM(c) 2010 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1

	This is a utility plugin for z/VM.

=cut

#-------------------------------------------------------
package xCAT::zvmUtils;
use xCAT::MsgUtils;
use xCAT::Utils;
use xCAT::Table;
use strict;
use warnings;
1;

#-------------------------------------------------------

=head3   getNodeProps
	Description	: Get node properties
    Arguments	: 	Table name
    				Node
    				Properties
    Returns		: Node properties from given table
    Example		: my $propVals = xCAT::zvmUtils->getNodeProps($tabName, $node, $propNames);
    
=cut

#-------------------------------------------------------
sub getNodeProps {

	# Get inputs
	my ( $class, $tabName, $node, @propNames ) = @_;

	# Get table
	my $tab = xCAT::Table->new($tabName);

	# Get property values
	my $propVals = $tab->getNodeAttribs( $node, [@propNames] );

	return ($propVals);
}

#-------------------------------------------------------

=head3   getTabPropsByKey
	Description	: Get table entry properties by key
    Arguments	: 	Table
    				Key name
    				Key value
    				Requested properties
    Returns		: Table entry properties
    Example		: my $propVals = xCAT::zvmUtils->getTabPropsByKey($tabName, $key, $keyValue, @reqProps);
    
=cut

#-------------------------------------------------------
sub getTabPropsByKey {

	# Get inputs
	my ( $class, $tabName, $key, $keyVal, @propNames ) = @_;

	# Get table
	my $tab = xCAT::Table->new($tabName);
	my $propVals;

	# Get table attributes matching given key
	$propVals = $tab->getAttribs( { $key => $keyVal }, @propNames );
	return ($propVals);
}

#-------------------------------------------------------

=head3   getAllTabEntries
	Description	: Get all entries within given table
    Arguments	: Table name
    Returns		: All table entries
    Example		: my $entries = xCAT::zvmUtils->getAllTabEntries($tabName);
    
=cut

#-------------------------------------------------------
sub getAllTabEntries {

	# Get inputs
	my ( $class, $tabName ) = @_;

	# Get table
	my $tab = xCAT::Table->new($tabName);
	my $entries;

	# Get all entries within given table
	$entries = $tab->getAllEntries();
	return ($entries);
}

#-------------------------------------------------------

=head3   setNodeProp

	Description	: Set a node property in a given table
    Arguments	: 	Table name
    			 	Node
    				Property name
    				Property value
    Returns		: Nothing
    Example		: xCAT::zvmUtils->setNodeProp($tabName, $node, $propName, $propVal);
    
=cut

#-------------------------------------------------------
sub setNodeProp {

	# Get inputs
	my ( $class, $tabName, $node, $propName, $propVal ) = @_;

	# Get table
	my $tab = xCAT::Table->new( $tabName, -create => 1, -autocommit => 0 );

	# Set property
	$tab->setAttribs( { 'node' => $node }, { $propName => $propVal } );

	# Save table
	$tab->commit;

	return;
}

#-------------------------------------------------------

=head3   setNodeProps

	Description	: Set node properties in a given table
    Arguments	: 	Table name
    			 	Node
    				Reference to property name/value hash
    Returns		: Nothing
    Example		: xCAT::zvmUtils->setNodeProps($tabName, $node, \%propHash);
    
=cut

#-------------------------------------------------------
sub setNodeProps {

	# Get inputs
	my ( $class, $tabName, $node, $propHash ) = @_;

	# Get table
	my $tab = xCAT::Table->new( $tabName, -create => 1, -autocommit => 0 );

	# Set property
	$tab->setAttribs( { 'node' => $node }, $propHash );

	# Save table
	$tab->commit;

	return;
}

#-------------------------------------------------------

=head3   delTabEntry

	Description	: Delete a table entry
    Arguments	: 	Table
    				Key name
    				Key value 
    Returns		: Nothing
    Example		: xCAT::zvmUtils->delTabEntry($tabName, $keyName, $keyVal);
    
=cut

#-------------------------------------------------------
sub delTabEntry {

	# Get inputs
	my ( $class, $tabName, $keyName, $keyVal ) = @_;

	# Get table
	my $tab = xCAT::Table->new( $tabName, -create => 1, -autocommit => 0 );

	# Delete entry from table
	my %key = ( $keyName => $keyVal );
	$tab->delEntries( \%key );

	# Save table
	$tab->commit;

	return;
}

#-------------------------------------------------------

=head3   tabStr

	Description	: Tab a string (4 spaces)
    Arguments	: String
    Returns		: Tabbed string
    Example		: my $str = xCAT::zvmUtils->tabStr($str);
    
=cut

#-------------------------------------------------------
sub tabStr {

	# Get inputs
	my ( $class, $inStr ) = @_;
	my @lines = split( "\n", $inStr );

	# Tab output
	my $outStr;
	foreach (@lines) {
		$outStr .= "    $_\n";
	}

	return ($outStr);
}

#-------------------------------------------------------

=head3   trimStr

	Description	: Trim the whitespaces in a string
    Arguments	: String
    Returns		: Trimmed string
    Example		: my $str = xCAT::zvmUtils->trimStr($str);
    
=cut

#-------------------------------------------------------
sub trimStr {

	# Get string
	my ( $class, $str ) = @_;

	# Trim right
	$str =~ s/\s*$//;

	# Trim left
	$str =~ s/^\s*//;

	return ($str);
}

#-------------------------------------------------------

=head3   replaceStr

	Description	: Replace a given pattern in a string
    Arguments	: String
    Returns		: New string
    Example		: my $str = xCAT::zvmUtils->replaceStr($str, $pattern, $replacement);
    
=cut

#-------------------------------------------------------
sub replaceStr {

	# Get string
	my ( $class, $str, $pattern, $replacement ) = @_;

	# Replace string
	$str =~ s/$pattern/$replacement/g;

	return ($str);
}

#-------------------------------------------------------

=head3   printLn

	Description	: Print a string to stdout
    Arguments	: String
    Returns		: Nothing
    Example		: xCAT::zvmUtils->printLn($callback, $str);
    
=cut

#-------------------------------------------------------
sub printLn {

	# Get inputs
	my ( $class, $callback, $str ) = @_;

	# Print string
	my $rsp;
	$rsp->{data}->[0] = "$str";
	xCAT::MsgUtils->message( "I", $rsp, $callback );

	return;
}

#-------------------------------------------------------

=head3   isZvmNode

	Description	: Determines if a given node is in the 'zvm' table
    Arguments	: Node
    Returns		: 	TRUE	Node exists
    				FALSE	Node does not exists
    Example		: my $out = xCAT::zvmUtils->isZvmNode($node);
    
=cut

#-------------------------------------------------------
sub isZvmNode {

	# Get inputs
	my ( $class, $node ) = @_;

	# zVM guest ID
	my $id;

	# Look in 'zvm' table
	my $tab = xCAT::Table->new( 'zvm', -create => 1, -autocommit => 0 );

	my @results = $tab->getAllAttribsWhere( "node like '%" . $node . "%'", 'userid' );
	foreach (@results) {

		# Get userID
		$id = $_->{'userid'};

		# Return 'TRUE' if given node is in the table
		if ($id) {
			return ('TRUE');
		}
	}

	return ('FALSE');
}

#-------------------------------------------------------

=head3   getHwcfg

	Description	: 	Get the hardware configuration file path (SUSE only)
					e.g. /etc/sysconfig/hardwarehwcfg-qeth-bus-ccw-0.0.0600
    Arguments	: Node
    Returns		: Hardware configuration file path
    Example		: my $hwcfg = xCAT::zvmUtils->getHwcfg($node);
    
=cut

#-------------------------------------------------------
sub getHwcfg {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get OS
	my $os = xCAT::zvmUtils->getOs($node);

	# Get network configuration file path
	my $out;
	my @parms;

	# If it is SUSE - hwcfg-qeth file is in /etc/sysconfig/hardware
	if ( $os =~ m/SUSE/i ) {
		$out = `ssh -o ConnectTimeout=5 $node "ls /etc/sysconfig/hardware/hwcfg-qeth*"`;
		@parms = split( '\n', $out );
		return ( $parms[0] );
	}

	# If no file is found - Return nothing
	return;
}

#-------------------------------------------------------

=head3   getIp

	Description	: Get the IP address of a given node
    Arguments	: Node
    Returns		: IP address of given node
    Example		: my $ip = xCAT::zvmUtils->getIp($node);
    
=cut

#-------------------------------------------------------
sub getIp {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get IP address
	# You need the extra space in the pattern,
	# else it will confuse gpok2 with gpok21
	my $out   = `cat /etc/hosts | grep "$node "`;
	my @parms = split( ' ', $out );

	return $parms[0];
}

#-------------------------------------------------------

=head3   getIfcfg

	Description	: 	Get the network configuration file path of a given node
					* Red Hat -	/etc/sysconfig/network-scripts/ifcfg-eth
					* SUSE 	  -	/etc/sysconfig/network/ifcfg-qeth
    Arguments	: Node
    Returns		: Network configuration file path
    Example		: my $ifcfg = xCAT::zvmUtils->getIfcfg($node);
    
=cut

#-------------------------------------------------------
sub getIfcfg {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get OS
	my $os = xCAT::zvmUtils->getOs($node);

	# Get network configuration file path
	my $out;
	my @parms;

	# If it is Red Hat - ifcfg-qeth file is in /etc/sysconfig/network-scripts
	if ( $os =~ m/Red Hat/i ) {
		$out = `ssh -o ConnectTimeout=5 $node "ls /etc/sysconfig/network-scripts/ifcfg-eth*"`;
		@parms = split( '\n', $out );
		return ( $parms[0] );
	}

	# If it is SUSE - ifcfg-qeth file is in /etc/sysconfig/network
	elsif ( $os =~ m/SUSE/i ) {
		$out = `ssh -o ConnectTimeout=5 $node "ls /etc/sysconfig/network/ifcfg-qeth*"`;
		@parms = split( '\n', $out );
		return ( $parms[0] );
	}

	# If no file is found - Return nothing
	return;
}

#-------------------------------------------------------

=head3   getIfcfgByNic

	Description	: Get the network configuration file path of a given node
    Arguments	: 	Node
    				NIC address
    Returns		: Network configuration file path
    Example		: my $ifcfg = xCAT::zvmUtils->getIfcfgByNic($node, $nic);
    
=cut

#-------------------------------------------------------
sub getIfcfgByNic {

	# Get inputs
	my ( $class, $node, $nic ) = @_;

	# Get OS
	my $os = xCAT::zvmUtils->getOs($node);

	# Get network configuration file path
	my $out;
	my @parms;

	# If it is Red Hat - ifcfg-qeth file is in /etc/sysconfig/network-scripts
	if ( $os =~ m/Red Hat/i ) {
		$out   = `ssh -o ConnectTimeout=5 $node "ls /etc/sysconfig/network-scripts/ifcfg-eth*"`;
		@parms = split( '\n', $out );

		# Go through each line
		foreach (@parms) {

			# If the network file contains the NIC address
			$out = `ssh -o ConnectTimeout=5 $node "cat $_" | grep "$nic"`;
			if ($out) {

				# Return network file path
				return ($_);
			}
		}
	}

	# If it is SLES 10 - ifcfg-qeth file is in /etc/sysconfig/network
	elsif ( $os =~ m/SUSE Linux Enterprise Server 10/i ) {
		$out = `ssh -o ConnectTimeout=5 $node "ls /etc/sysconfig/network/ifcfg-qeth*" | grep "$nic"`;
		@parms = split( '\n', $out );
		return ( $parms[0] );
	}

	# If it is SLES 11 - ifcfg-qeth file is in /etc/sysconfig/network
	elsif ( $os =~ m/SUSE Linux Enterprise Server 11/i ) {

		# Get a list of ifcfg-eth files found
		$out = `ssh -o ConnectTimeout=5 $node "ls /etc/sysconfig/network/ifcfg-eth*"`;
		my @file = split( '\n', $out );

		# Go through each ifcfg-eth file
		foreach (@file) {

			# If the network file contains the NIC address
			$out = `ssh -o ConnectTimeout=5 $node "cat $_" | grep "$nic"`;
			if ($out) {

				# Return ifcfg-eth file path
				return ($_);
			}
		}
	}

	# If no file is found - Return nothing
	return;
}

#-------------------------------------------------------

=head3   sendFile

	Description	: SCP a file to a given node
    Arguments	: 	Node 
    				Source file 
    				Target file
    Returns		: Nothing
    Example		: xCAT::zvmUtils->sendFile($node, $srcFile, $trgtFile);
    
=cut

#-------------------------------------------------------
sub sendFile {

	# Get inputs
	my ( $class, $node, $srcFile, $trgtFile ) = @_;

	# Create destination string
	my $dest = "root@" . $node;

	# SCP directory entry file over to HCP
	my $out = `scp $srcFile $dest:$trgtFile`;

	return;
}

#-------------------------------------------------------

=head3   getRootDeviceAddr

	Description	: Get the root device address of a given node
    Arguments	: Node name
    Returns		: Root device address
    Example		: my $deviceAddr = xCAT::zvmUtils->getRootDeviceAddr($node);
    
=cut

#-------------------------------------------------------
sub getRootDeviceAddr {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get the root device node
	# LVM is not supported
	my $out = `ssh $node  "mount" | grep "/ type" | sed 's/1//'`;
	my @parms = split( " ", $out );
	@parms = split( "/", xCAT::zvmUtils->trimStr( $parms[0] ) );
	my $devNode = $parms[0];

	# Get disk address
	$out = `ssh $node "cat /proc/dasd/devices" | grep "$devNode" | sed 's/(ECKD)//' | sed 's/(FBA )//' | sed 's/0.0.//'`;
	@parms = split( " ", $out );
	return ( $parms[0] );
}

#-------------------------------------------------------

=head3   disableEnableDisk

	Description	: Disable/enable a disk for a given node
    Arguments	: 	Device address
    				Option (-d|-e)
    Returns		: Nothing
    Example		: my $out = xCAT::zvmUtils->disableEnableDisk($callback, $node, $option, $devAddr);
    
=cut

#-------------------------------------------------------
sub disableEnableDisk {

	# Get inputs
	my ( $class, $callback, $node, $option, $devAddr ) = @_;

	# Disable/enable disk
	my $out;
	if ( $option eq "-d" || $option eq "-e" ) {
		$out = `ssh $node "chccwdev $option $devAddr"`;
	}

	return ($out);
}

#-------------------------------------------------------

=head3   getMdisks

	Description	: Get the MDISK statements in the user entry of a given node
    Arguments	: Node
    Returns		: MDISK statements
    Example		: my @mdisks = xCAT::zvmUtils->getMdisks($callback, $node);
    
=cut

#-------------------------------------------------------
sub getMdisks {

	# Get inputs
	my ( $class, $callback, $node ) = @_;

	# Directory where executables are
	my $dir = '/opt/zhcp/bin';

	# Get HCP
	my @propNames = ( 'hcp', 'userid' );
	my $propVals = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );
	my $hcp      = $propVals->{'hcp'};

	# Get node userID
	my $userId = $propVals->{'userid'};

	my $out = `ssh $hcp "$dir/getuserentry $userId" | grep "MDISK"`;

	# Get MDISK statements
	my @lines = split( '\n', $out );
	my @disks;
	foreach (@lines) {
		$_ = xCAT::zvmUtils->trimStr($_);

		# Save MDISK statements
		push( @disks, $_ );
	}

	return (@disks);
}

#-------------------------------------------------------

=head3   getUserEntryWODisk

	Description	: 	Get the user entry of a given node without MDISK statments, 
					and save it to a file
    Arguments	: 	Node
    				File name to save user entry under
    Returns		: 	Nothing
    Example		: my $out = xCAT::zvmUtils->getUserEntryWODisk($callback, $node, $file);
    
=cut

#-------------------------------------------------------
sub getUserEntryWODisk {

	# Get inputs
	my ( $class, $callback, $node, $file ) = @_;

	# Directory where executables are
	my $dir = '/opt/zhcp/bin';

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

	my $out = `ssh $hcp "$dir/getuserentry $userId" | grep -v "MDISK"`;

	# Create a file to save output
	open( DIRENTRY, ">$file" );

	# Save output
	my @lines = split( '\n', $out );
	foreach (@lines) {

		# Trim line
		$_ = xCAT::zvmUtils->trimStr($_);

		# Write directory entry into file
		print DIRENTRY "$_\n";
	}
	close(DIRENTRY);

	return;
}

#-------------------------------------------------------

=head3   appendHostname

	Description	: 	Append a hostname in front of a given string
    Arguments	: 	Hostname
    				String
    Returns		: 	String appended with hostname
    Example		: my $str = xCAT::zvmUtils->appendHostname($hostname, $str);
    
=cut

#-------------------------------------------------------
sub appendHostname {
	my ( $class, $hostname, $str ) = @_;

	# Append hostname to every line
	my @outLn = split( "\n", $str );
	$str = "";
	foreach (@outLn) {
		$str .= "$hostname: " . $_ . "\n";
	}

	return $str;
}

#-------------------------------------------------------

=head3   checkOutput

	Description	: 	Check the return of given output
    Arguments	: 	Output string
    Returns		: 	 0	Good output
    				-1	Bad output
    Example		: my $rtn = xCAT::zvmUtils->checkOutput($callback, $out);
    
=cut

#-------------------------------------------------------
sub checkOutput {
	my ( $class, $callback, $out ) = @_;

	# Check output string
	my @outLn = split( "\n", $out );
	foreach (@outLn) {

		# If output contains 'Failed', return -1
		if ( $_ =~ m/Failed/i ) {
			return -1;
		}
	}

	return 0;
}

#-------------------------------------------------------

=head3   getDeviceNode

	Description	: 	Get the device node for a given address
    Arguments	: 	Node
    				Disk address
    Returns		: 	Device node
    Example		: my $devNode = xCAT::zvmUtils->getDeviceNode($node, $tgtAddr);
    
=cut

#-------------------------------------------------------
sub getDeviceNode {
	my ( $class, $node, $tgtAddr ) = @_;

	# Determine device node
	my $out = `ssh $node "cat /proc/dasd/devices" | grep ".$tgtAddr("`;
	my @words = split( ' ', $out );
	my $tgtDevNode;

	# /proc/dasd/devices look similar to this:
	# 0.0.0100(ECKD) at ( 94: 0) is dasda : active at blocksize: 4096, 1802880 blocks, 7042 MB
	# Look for the string 'is'
	my $i = 0;
	while ( $tgtDevNode ne 'is' ) {
		$tgtDevNode = $words[$i];
		$i++;
	}

	return $words[$i];
}

#-------------------------------------------------------

=head3   isAddressUsed

	Description	: 	Check if a given address is used
    Arguments	: 	Node
    				Disk address
    Returns		: 	 0	Address used
    				-1	Address not used
    Example		: my $ans = xCAT::zvmUtils->isAddressUsed($node, $address);
    
=cut

#-------------------------------------------------------
sub isAddressUsed {
	my ( $class, $node, $address ) = @_;

	# Search for disk address
	my $out = `ssh -o ConnectTimeout=5 $node "vmcp q v dasd" | grep "DASD $address"`;
	if ($out) {
		return 0;
	}

	return -1;
}

#-------------------------------------------------------

=head3   getMacID

	Description	: Get the MACID from /opt/zhcp/conf/next_macid on the HCP
    Arguments	: HCP node
    Returns		: MACID
    Example		: my $macId = xCAT::zvmUtils->getMacID($hcp);
    
=cut

#-------------------------------------------------------
sub getMacID {
	my ( $class, $hcp ) = @_;

	# Check /opt/zhcp/conf directory on HCP
	my $out = `ssh -o ConnectTimeout=5 $hcp "test -d /opt/zhcp/conf && echo 'Directory exists'"`;
	if ( $out =~ m/Directory exists/i ) {

		# Check next_macid file
		$out = `ssh -o ConnectTimeout=5 $hcp "test -e /opt/zhcp/conf/next_macid && echo 'File exists'"`;
		if ( $out =~ m/File exists/i ) {

			# Do nothing
		}
		else {

			# Create next_macid file
			$out = `ssh -o ConnectTimeout=5 $hcp "echo 'FFFFF0' > /opt/zhcp/conf/next_macid"`;
		}
	}
	else {

		# Create /opt/zhcp/conf directory
		# Create next_mac - Contains next MAC address to use
		$out = `ssh -o ConnectTimeout=5 $hcp "mkdir /opt/zhcp/conf"`;
		$out = `ssh -o ConnectTimeout=5 $hcp "echo 'FFFFF0' > /opt/zhcp/conf/next_macid"`;
	}

	# Read /opt/zhcp/conf/next_macid file
	$out = `ssh -o ConnectTimeout=5 $hcp "cat /opt/zhcp/conf/next_macid"`;
	my $macId = xCAT::zvmUtils->trimStr($out);

	return $macId;
}

#-------------------------------------------------------

=head3   generateMacId

	Description	: Generate a new MACID 
    Arguments	: HCP node
    Returns		: Nothing
    Example		: my $macId = xCAT::zvmUtils->generateMacId($hcp);
    
=cut

#-------------------------------------------------------
sub generateMacId {
	my ( $class, $hcp ) = @_;

	# Check /opt/zhcp/conf directory on HCP
	my $out = `ssh -o ConnectTimeout=5 $hcp "test -d /opt/zhcp/conf && echo 'Directory exists'"`;
	if ( $out =~ m/Directory exists/i ) {

		# Check next_macid file
		$out = `ssh -o ConnectTimeout=5 $hcp "test -e /opt/zhcp/conf/next_macid && echo 'File exists'"`;
		if ( $out =~ m/File exists/i ) {

			# Do nothing
		}
		else {

			# Create next_macid file
			$out = `ssh -o ConnectTimeout=5 $hcp "echo 'FFFFF0' > /opt/zhcp/conf/next_macid"`;
		}
	}
	else {

		# Create /opt/zhcp/conf directory
		# Create next_mac - Contains next MAC address to use
		$out = `ssh -o ConnectTimeout=5 $hcp "mkdir /opt/zhcp/conf"`;
		$out = `ssh -o ConnectTimeout=5 $hcp "echo 'FFFFF0' > /opt/zhcp/conf/next_macid"`;
	}

	# Read /opt/zhcp/conf/next_macid file
	$out = `ssh -o ConnectTimeout=5 $hcp "cat /opt/zhcp/conf/next_macid"`;
	my $macId = xCAT::zvmUtils->trimStr($out);
	my $int;

	if ($macId) {

		# Convert hexadecimal - decimal
		$int   = hex($macId);
		$macId = sprintf( "%d", $int );

		# Generate new MAC suffix
		$macId = $macId - 1;

		# Convert decimal - hexadecimal
		$macId = sprintf( "%X", $macId );

		# Save new MACID
		$out = `ssh -o ConnectTimeout=5 $hcp "echo $macId > /opt/zhcp/conf/next_macid"`;
	}

	return;
}

#-------------------------------------------------------

=head3   createMacAddr

	Description	: 	Create a MAC address using the HCP MAC prefix and a given MAC suffix
    Arguments	: 	Node
    				MAC suffix
    Returns		: 	MAC address
    Example		: my $mac = xCAT::zvmUtils->createMacAddr($node, $suffix);
    
=cut

#-------------------------------------------------------
sub createMacAddr {
	my ( $class, $node, $suffix ) = @_;

	# Get node properties from 'zvm' table
	my @propNames = ('hcp');
	my $propVals  = xCAT::zvmUtils->getNodeProps( 'zvm', $node, @propNames );

	# Get HCP
	my $hcp = $propVals->{'hcp'};
	if ( !$hcp ) {
		return -1;
	}

	# Get HCP MAC address
	# Get the first MAC address found
	my $out   = `ssh -o ConnectTimeout=5 $hcp "vmcp q v nic" | grep "MAC:"`;
	my @lines = split( "\n", $out );
	my @vars  = split( " ", $lines[0] );

	# Extract MAC prefix
	my $prefix = $vars[1];
	$prefix = xCAT::zvmUtils->replaceStr( $prefix, "-", "" );
	$prefix = substr( $prefix, 0, 6 );

	# Generate MAC address of source node
	my $mac = $prefix . $suffix;

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

	return $mac;
}

#-------------------------------------------------------

=head3   getOs

	Description	: Get the operating system of a given node
    Arguments	: Node
    Returns		: Operating system name
    Example		: my $osName = xCAT::zvmUtils->getOs($node);
    
=cut

#-------------------------------------------------------
sub getOs {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get operating system
	my $out = `ssh -o ConnectTimeout=10 $node "cat /etc/*release"`;
	my @results = split( '\n', $out );
	return ( xCAT::zvmUtils->trimStr( $results[0] ) );
}

#-------------------------------------------------------

=head3   getArch

	Description	: Get the architecture of a given node
    Arguments	: Node
    Returns		: Architecture of node
    Example		: my $arch = xCAT::zvmUtils->getArch($node);
    
=cut

#-------------------------------------------------------
sub getArch {

	# Get inputs
	my ( $class, $node ) = @_;

	# Get host using VMCP
	my $arch = `ssh $node "uname -p"`;

	return ( xCAT::zvmUtils->trimStr($arch) );
}

#-------------------------------------------------------

=head3   getUserProfile

	Description	: Get the user profile
    Arguments	: Profile name
    Returns		: User profile
    Example		: my $profile = xCAT::zvmUtils->getUserProfile($hcp, $name);
    
=cut

#-------------------------------------------------------
sub getUserProfile {

	# Get inputs
	my ( $class, $hcp, $profile ) = @_;

	# Set directory where executables are on zHCP
	my $hcpDir = "/opt/zhcp/bin";

	my $out;

	# Set directory for cache
	my $cache = '/var/opt/zhcp/cache';
	# If the cache directory does not exist
	if (!(`ssh $hcp "test -d $cache && echo Exists"`)) {
		# Create cache directory
		$out = `ssh $hcp "mkdir -p $cache"`;
	}

	# Set output file name
	my $file = "$cache/$profile.profile";

	# If a cache for the user profile exists
	if (`ssh $hcp "ls $file"`) {

		# Get current Epoch
		my $curTime = time();

		# Get time of last change as seconds since Epoch
		my $fileTime = xCAT::zvmUtils->trimStr(`ssh $hcp "stat -c %Z $file"`);

		# If the current time is greater than 5 minutes of the file timestamp
		my $interval = 300;    # 300 seconds = 5 minutes * 60 seconds/minute
		if ( $curTime > $fileTime + $interval ) {

			# Get user profiles and save it in a file
			$out = `ssh $hcp "$hcpDir/getuserprofile $profile > $file"`;
		}
	}
	else {

		# Get user profiles and save it in a file
		$out = `ssh $hcp "$hcpDir/getuserprofile $profile > $file"`;
	}

	# Return the file contents
	$out = `ssh $hcp "cat $file"`;
	return $out;
}

#-------------------------------------------------------

=head3   inArray

	Description	: Checks if a value exists in an array
    Arguments	: 	Value to search for
    				Array to search in
    Returns		: The searched expression
    Example		: my $rtn = xCAT::zvmUtils->inArray($needle, @haystack);
    
=cut

#-------------------------------------------------------
sub inArray {

	# Get inputs
	my ( $class, $needle, @haystack ) = @_;
	return grep{ $_ eq $needle } @haystack;
}

#-------------------------------------------------------

=head3   getOsVersion

	Description	: Get the operating system of a given node
    Arguments	: Node
    Returns		: Operating system name
    Example		: my $os = xCAT::zvmUtils->getOsVersion($node);
    
=cut

#-------------------------------------------------------
sub getOsVersion {
	
	# Get inputs
	my ( $class, $node ) = @_;

	my $os = '';
	my $version = '';

	# Get operating system
	my $release = `ssh -o ConnectTimeout=2 $node "cat /etc/*release"`;
	my @lines = split('\n', $release);
	if (grep(/SLES|Enterprise Server/, @lines)) {
		$os = 'sles';
		$version = $lines[0];
		$version =~ tr/\.//;
		$version =~ s/[^0-9]*([0-9]+).*/$1/;
		$os = $os . $version;
		
		# Append service level
		$version = `echo "$release" | grep "LEVEL"`;
		$version =~ tr/\.//;
		$version =~ s/[^0-9]*([0-9]+).*/$1/;
		$os = $os . 'sp' . $version;
	} elsif (grep(/Red Hat Enterprise Linux Server/, @lines)) {
		$os = 'rhel';
		$version = $lines[0];
		$version =~ tr/\.//;
		$version =~ s/([A-Za-z\s\(\)]+)//g;
		$os = $os . $version;
	}

	return xCAT::zvmUtils->trimStr($os);
}